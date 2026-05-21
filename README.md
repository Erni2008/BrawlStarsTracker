# Brawl Stars Tracker

Unofficial Brawl Stars tracker for personal profile stats, trophy progress,
brawler details, maps, and account switching.

## PWA

The repository root contains the web/PWA version:

- `index.html`
- `app.js`
- `styles.css`
- `manifest.webmanifest`
- `sw.js`

## Native iPhone App

The SwiftUI iOS project is in:

```text
BrawlTrophyTrackerIOS/BrawlTrophyTrackerIOS.xcodeproj
```

Open that project in Xcode and run the `BrawlTrophyTrackerIOS` target on an
iPhone simulator or physical iPhone.

## Notes

The app uses public/tokenless Brawl Stars data sources where available. Battle
logs and map data depend on unofficial sources, so availability can change.

## Local Python Dashboard

The original local FastAPI dashboard is included in:

```text
server/
```

Run it with:

```bash
cd server
python3 -m uvicorn app:app --reload --host 127.0.0.1 --port 8765
```

It stores local snapshots in `server/data/tracker.sqlite3`; that database is
created at runtime and is intentionally not committed.
