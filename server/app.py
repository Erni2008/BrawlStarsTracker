from __future__ import annotations

import asyncio
import json
import subprocess
import sqlite3
import threading
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
DATA_DIR = APP_DIR / "data"
DB_PATH = DATA_DIR / "tracker.sqlite3"
API_BASE = "https://api.bsinfox.com"
DEFAULT_SYNC_INTERVAL_SECONDS = 10 * 60


class SetupRequest(BaseModel):
    player_tag: str = Field(..., min_length=2)
    sync_interval_minutes: int = Field(default=10, ge=2, le=120)


class SettingsUpdate(BaseModel):
    player_tag: str | None = None
    sync_interval_minutes: int | None = Field(default=None, ge=2, le=120)


@dataclass(frozen=True)
class TrackerConfig:
    player_tag: str
    sync_interval_seconds: int


app = FastAPI(title="Brawl Trophy Tracker", version="1.0.0")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

_sync_lock = threading.Lock()
_last_scheduler_error: str | None = None


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return now_utc().isoformat(timespec="seconds")


def normalize_tag(tag: str) -> str:
    clean = tag.strip().upper().replace("O", "0")
    if not clean.startswith("#"):
        clean = f"#{clean}"
    return clean


def encoded_tag_path(tag: str) -> str:
    return quote(normalize_tag(tag).lstrip("#"), safe="")


@contextmanager
def db() -> Any:
    DATA_DIR.mkdir(exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS player_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                captured_at TEXT NOT NULL,
                tag TEXT NOT NULL,
                name TEXT NOT NULL,
                trophies INTEGER NOT NULL,
                highest_trophies INTEGER NOT NULL DEFAULT 0,
                exp_level INTEGER NOT NULL DEFAULT 0,
                three_vs_three_victories INTEGER NOT NULL DEFAULT 0,
                solo_victories INTEGER NOT NULL DEFAULT 0,
                duo_victories INTEGER NOT NULL DEFAULT 0,
                raw_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS brawler_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                snapshot_id INTEGER NOT NULL REFERENCES player_snapshots(id) ON DELETE CASCADE,
                brawler_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                trophies INTEGER NOT NULL,
                highest_trophies INTEGER NOT NULL DEFAULT 0,
                power INTEGER NOT NULL DEFAULT 0,
                rank INTEGER NOT NULL DEFAULT 0,
                raw_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS battles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                battle_key TEXT NOT NULL UNIQUE,
                battle_time TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                mode TEXT NOT NULL DEFAULT '',
                map_name TEXT NOT NULL DEFAULT '',
                battle_type TEXT NOT NULL DEFAULT '',
                result TEXT NOT NULL DEFAULT '',
                rank INTEGER,
                duration INTEGER,
                trophy_change INTEGER NOT NULL DEFAULT 0,
                brawler_id INTEGER,
                brawler_name TEXT NOT NULL DEFAULT '',
                raw_json TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_snapshots_captured_at ON player_snapshots(captured_at);
            CREATE INDEX IF NOT EXISTS idx_battles_battle_time ON battles(battle_time);
            CREATE INDEX IF NOT EXISTS idx_battles_brawler_name ON battles(brawler_name);
            """
        )


def get_setting(conn: sqlite3.Connection, key: str, default: str = "") -> str:
    row = conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
    return str(row["value"]) if row else default


def set_setting(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute(
        "INSERT INTO settings(key, value) VALUES(?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, value),
    )


def get_config() -> TrackerConfig | None:
    with db() as conn:
        player_tag = get_setting(conn, "player_tag")
        interval_raw = get_setting(conn, "sync_interval_seconds", str(DEFAULT_SYNC_INTERVAL_SECONDS))
    if not player_tag:
        return None
    return TrackerConfig(
        player_tag=normalize_tag(player_tag),
        sync_interval_seconds=max(120, int(interval_raw or DEFAULT_SYNC_INTERVAL_SECONDS)),
    )


def public_settings() -> dict[str, Any]:
    config = get_config()
    if not config:
        return {
            "configured": False,
            "playerTag": "",
            "syncIntervalMinutes": DEFAULT_SYNC_INTERVAL_SECONDS // 60,
            "lastSchedulerError": _last_scheduler_error,
        }
    return {
        "configured": True,
        "playerTag": config.player_tag,
        "syncIntervalMinutes": config.sync_interval_seconds // 60,
        "lastSchedulerError": _last_scheduler_error,
    }


class BrawlApiError(RuntimeError):
    pass


def request_bsinfo(path: str) -> dict[str, Any]:
    url = f"{API_BASE}{path}"
    request = Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "BrawlTrophyTracker/1.0",
        },
    )
    try:
        with urlopen(request, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise BrawlApiError(f"Brawl API error {exc.code}: {detail}") from exc
    except URLError as exc:
        if "CERTIFICATE_VERIFY_FAILED" in str(exc.reason):
            return request_bsinfo_with_curl(url)
        raise BrawlApiError(f"Network error: {exc.reason}") from exc


def request_bsinfo_with_curl(url: str) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            ["curl", "-L", "-sS", "--max-time", "20", "-H", "Accept: application/json", url],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or str(exc)
        raise BrawlApiError(f"BSInfo curl fallback failed: {detail}") from exc
    except json.JSONDecodeError as exc:
        raise BrawlApiError("BSInfo returned a non-JSON response.") from exc


def unwrap_player_response(response: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    player = response.get("data") if isinstance(response.get("data"), dict) else response
    tag = normalize_tag(str(response.get("tag") or player.get("tag") or ""))
    return tag, player


def sync_once() -> dict[str, Any]:
    config = get_config()
    if not config:
        raise BrawlApiError("Tracker is not configured yet.")

    if not _sync_lock.acquire(blocking=False):
        return {"status": "already_running"}

    try:
        fetched_at = iso_now()
        response = request_bsinfo(f"/players/{encoded_tag_path(config.player_tag)}")
        response_tag, player = unwrap_player_response(response)

        with db() as conn:
            cursor = conn.execute(
                """
                INSERT INTO player_snapshots (
                    captured_at, tag, name, trophies, highest_trophies, exp_level,
                    three_vs_three_victories, solo_victories, duo_victories, raw_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    fetched_at,
                    response_tag or config.player_tag,
                    player.get("name", "Unknown"),
                    int(player.get("trophies", 0)),
                    int(player.get("highestTrophies", 0)),
                    int(player.get("expLevel", 0)),
                    int(player.get("3vs3Victories", 0)),
                    int(player.get("soloVictories", 0)),
                    int(player.get("duoVictories", 0)),
                    json.dumps(player, ensure_ascii=False),
                ),
            )
            snapshot_id = cursor.lastrowid
            for brawler in player.get("brawlers", []) or []:
                conn.execute(
                    """
                    INSERT INTO brawler_snapshots (
                        snapshot_id, brawler_id, name, trophies, highest_trophies,
                        power, rank, raw_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        snapshot_id,
                        int(brawler.get("id", 0)),
                        brawler.get("name", ""),
                        int(brawler.get("trophies", 0)),
                        int(brawler.get("highestTrophies", 0)),
                        int(brawler.get("power", 0)),
                        int(brawler.get("rank", 0)),
                        json.dumps(brawler, ensure_ascii=False),
                    ),
                )

            set_setting(conn, "last_sync_at", fetched_at)

        return {
            "status": "ok",
            "capturedAt": fetched_at,
            "playerName": player.get("name", "Unknown"),
            "trophies": int(player.get("trophies", 0)),
            "brawlerCount": len(player.get("brawlers", []) or []),
        }
    finally:
        _sync_lock.release()


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {key: row[key] for key in row.keys()}


def profile_summary(snapshot: sqlite3.Row | None) -> dict[str, Any] | None:
    if not snapshot:
        return None
    raw = json.loads(snapshot["raw_json"])
    return {
        "ranked": raw.get("ranked"),
        "rankedPoints": raw.get("rankedPoints"),
        "highestWinStreak": raw.get("highestWinStreak"),
        "playedHours": raw.get("playedHours"),
        "masteryPoints": raw.get("masteryPoints"),
        "totalPrestigeLevel": raw.get("totalPrestigeLevel"),
        "clubName": (raw.get("club") or {}).get("name"),
    }


def brawler_deltas(
    conn: sqlite3.Connection,
    current_snapshot_id: int | None,
    baseline_snapshot_id: int | None,
    limit: int = 30,
) -> list[dict[str, Any]]:
    if not current_snapshot_id or not baseline_snapshot_id or current_snapshot_id == baseline_snapshot_id:
        return []
    rows = conn.execute(
        """
        SELECT
            current.name AS name,
            current.trophies AS current_trophies,
            previous.trophies AS previous_trophies,
            current.power AS power,
            current.rank AS rank,
            current.highest_trophies AS highest_trophies,
            current.trophies - previous.trophies AS trophy_change
        FROM brawler_snapshots current
        JOIN brawler_snapshots previous ON previous.brawler_id = current.brawler_id
        WHERE current.snapshot_id = ? AND previous.snapshot_id = ?
          AND current.trophies != previous.trophies
        ORDER BY ABS(current.trophies - previous.trophies) DESC, current.name ASC
        LIMIT ?
        """,
        (current_snapshot_id, baseline_snapshot_id, limit),
    ).fetchall()
    return [row_to_dict(row) for row in rows]


def date_bounds(date_value: str | None) -> tuple[str, str]:
    if date_value:
        day = datetime.strptime(date_value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    else:
        day = now_utc().replace(hour=0, minute=0, second=0, microsecond=0)
    start = day.isoformat(timespec="seconds")
    end = (day + timedelta(days=1)).isoformat(timespec="seconds")
    return start, end


def build_stats(date_value: str | None = None) -> dict[str, Any]:
    start, end = date_bounds(date_value)
    with db() as conn:
        first_snapshot = conn.execute(
            "SELECT * FROM player_snapshots WHERE captured_at >= ? AND captured_at < ? ORDER BY captured_at ASC LIMIT 1",
            (start, end),
        ).fetchone()
        last_snapshot = conn.execute(
            "SELECT * FROM player_snapshots ORDER BY captured_at DESC LIMIT 1"
        ).fetchone()
        latest_today = conn.execute(
            "SELECT * FROM player_snapshots WHERE captured_at >= ? AND captured_at < ? ORDER BY captured_at DESC LIMIT 1",
            (start, end),
        ).fetchone()
        previous_snapshot = conn.execute(
            "SELECT * FROM player_snapshots WHERE captured_at < ? ORDER BY captured_at DESC LIMIT 1",
            (start,),
        ).fetchone()
        history = conn.execute(
            """
            SELECT substr(captured_at, 1, 10) AS day,
                   MIN(trophies) AS min_trophies,
                   MAX(trophies) AS max_trophies,
                   (SELECT trophies FROM player_snapshots ps2
                    WHERE substr(ps2.captured_at, 1, 10) = substr(ps.captured_at, 1, 10)
                    ORDER BY captured_at ASC LIMIT 1) AS first_trophies,
                   (SELECT trophies FROM player_snapshots ps3
                    WHERE substr(ps3.captured_at, 1, 10) = substr(ps.captured_at, 1, 10)
                    ORDER BY captured_at DESC LIMIT 1) AS last_trophies
            FROM player_snapshots ps
            GROUP BY day
            ORDER BY day DESC
            LIMIT 14
            """
        ).fetchall()
        previous_latest_snapshot = conn.execute(
            """
            SELECT * FROM player_snapshots
            WHERE id != COALESCE((SELECT id FROM player_snapshots ORDER BY captured_at DESC LIMIT 1), -1)
            ORDER BY captured_at DESC
            LIMIT 1
            """
        ).fetchone()
        last_sync_at = get_setting(conn, "last_sync_at")

    baseline = first_snapshot or previous_snapshot
    current = latest_today or last_snapshot
    snapshot_delta = None
    if baseline and current:
        snapshot_delta = int(current["trophies"]) - int(baseline["trophies"])

    with db() as conn:
        today_brawler_deltas = brawler_deltas(
            conn,
            int(current["id"]) if current else None,
            int(baseline["id"]) if baseline else None,
            limit=20,
        )
        recent_brawler_deltas = brawler_deltas(
            conn,
            int(last_snapshot["id"]) if last_snapshot else None,
            int(previous_latest_snapshot["id"]) if previous_latest_snapshot else None,
            limit=40,
        )

    return {
        "range": {"start": start, "end": end},
        "lastSyncAt": last_sync_at,
        "latest": row_to_dict(last_snapshot) if last_snapshot else None,
        "profile": profile_summary(last_snapshot),
        "today": {
            "snapshotDelta": snapshot_delta,
            "changedBrawlers": len(today_brawler_deltas),
            "positiveBrawlers": sum(1 for item in today_brawler_deltas if int(item["trophy_change"]) > 0),
            "negativeBrawlers": sum(1 for item in today_brawler_deltas if int(item["trophy_change"]) < 0),
        },
        "byBrawler": today_brawler_deltas,
        "recentBrawlerChanges": recent_brawler_deltas,
        "history": [row_to_dict(row) for row in reversed(history)],
        "settings": public_settings(),
    }


async def scheduler() -> None:
    global _last_scheduler_error
    while True:
        config = get_config()
        interval = config.sync_interval_seconds if config else DEFAULT_SYNC_INTERVAL_SECONDS
        if config:
            try:
                await asyncio.to_thread(sync_once)
                _last_scheduler_error = None
            except Exception as exc:  # noqa: BLE001 - shown in local dashboard
                _last_scheduler_error = str(exc)
        await asyncio.sleep(interval)


@app.on_event("startup")
async def startup() -> None:
    init_db()
    asyncio.create_task(scheduler())


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/settings")
async def settings() -> dict[str, Any]:
    return public_settings()


@app.post("/api/setup")
async def setup(payload: SetupRequest) -> dict[str, Any]:
    with db() as conn:
        set_setting(conn, "player_tag", normalize_tag(payload.player_tag))
        set_setting(conn, "sync_interval_seconds", str(payload.sync_interval_minutes * 60))
    return public_settings()


@app.patch("/api/settings")
async def update_settings(payload: SettingsUpdate) -> dict[str, Any]:
    with db() as conn:
        if payload.player_tag is not None:
            set_setting(conn, "player_tag", normalize_tag(payload.player_tag))
        if payload.sync_interval_minutes is not None:
            set_setting(conn, "sync_interval_seconds", str(payload.sync_interval_minutes * 60))
    return public_settings()


@app.post("/api/sync")
async def sync() -> dict[str, Any]:
    try:
        return await asyncio.to_thread(sync_once)
    except BrawlApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/api/stats")
async def stats(date: str | None = None) -> dict[str, Any]:
    return build_stats(date)


@app.get("/api/battles")
async def battles(limit: int = 50) -> dict[str, Any]:
    return {"items": [], "message": "Battle log is not available in tokenless BSInfo mode."}


@app.get("/api/brawlers")
async def brawlers() -> dict[str, Any]:
    with db() as conn:
        latest = conn.execute(
            "SELECT id FROM player_snapshots ORDER BY captured_at DESC LIMIT 1"
        ).fetchone()
        if not latest:
            return {"items": []}
        rows = conn.execute(
            """
            SELECT name, trophies, highest_trophies, power, rank
            FROM brawler_snapshots
            WHERE snapshot_id = ?
            ORDER BY trophies DESC, name ASC
            """,
            (latest["id"],),
        ).fetchall()
    return {"items": [row_to_dict(row) for row in rows]}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host="127.0.0.1", port=8765, reload=True)
