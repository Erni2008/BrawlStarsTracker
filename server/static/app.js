const els = {
  setupPanel: document.querySelector("#setupPanel"),
  setupForm: document.querySelector("#setupForm"),
  playerTagInput: document.querySelector("#playerTagInput"),
  intervalInput: document.querySelector("#intervalInput"),
  syncButton: document.querySelector("#syncButton"),
  dateInput: document.querySelector("#dateInput"),
  statusDot: document.querySelector("#statusDot"),
  statusText: document.querySelector("#statusText"),
  snapshotDelta: document.querySelector("#snapshotDelta"),
  battleDelta: document.querySelector("#battleDelta"),
  currentTrophies: document.querySelector("#currentTrophies"),
  playerName: document.querySelector("#playerName"),
  battleCount: document.querySelector("#battleCount"),
  battleSplit: document.querySelector("#battleSplit"),
  historyChart: document.querySelector("#historyChart"),
  brawlerStats: document.querySelector("#brawlerStats"),
  modeStats: document.querySelector("#modeStats"),
  brawlerTable: document.querySelector("#brawlerTable"),
  battleList: document.querySelector("#battleList"),
  battleUpdated: document.querySelector("#battleUpdated"),
};

const today = new Date();
els.dateInput.value = today.toISOString().slice(0, 10);

function formatDelta(value) {
  const number = Number(value || 0);
  if (number > 0) return `+${number}`;
  return String(number);
}

function deltaClass(value) {
  const number = Number(value || 0);
  if (number > 0) return "positive";
  if (number < 0) return "negative";
  return "neutral";
}

function formatDateTime(value) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.detail || "Ошибка запроса");
  }
  return data;
}

function setStatus(kind, text) {
  els.statusDot.className = `dot ${kind || ""}`;
  els.statusText.textContent = text;
}

function renderSetup(settings) {
  els.setupPanel.classList.toggle("hidden", settings.configured);
  els.playerTagInput.value = settings.playerTag || els.playerTagInput.value;
  els.intervalInput.value = settings.syncIntervalMinutes || 10;
}

function renderMetric(element, value) {
  element.textContent = formatDelta(value);
  element.className = deltaClass(value);
}

function renderHistory(items) {
  els.historyChart.innerHTML = "";
  if (!items.length) {
    els.historyChart.innerHTML = `<div class="empty">Нет истории</div>`;
    return;
  }
  const deltas = items.map((item) => Number(item.last_trophies || 0) - Number(item.first_trophies || 0));
  const maxAbs = Math.max(1, ...deltas.map((value) => Math.abs(value)));
  items.forEach((item, index) => {
    const delta = deltas[index];
    const height = Math.max(6, Math.round((Math.abs(delta) / maxAbs) * 185));
    const day = item.day.slice(5).replace("-", ".");
    const node = document.createElement("div");
    node.className = "bar-wrap";
    node.title = `${item.day}: ${formatDelta(delta)} кубков`;
    node.innerHTML = `
      <div class="bar ${delta < 0 ? "negative-bar" : ""}" style="height:${height}px"></div>
      <div class="bar-label">${day}<br>${formatDelta(delta)}</div>
    `;
    els.historyChart.appendChild(node);
  });
}

function renderRows(container, rows, nameKey = "name") {
  container.innerHTML = "";
  if (!rows.length) {
    container.innerHTML = `<div class="row"><span>Пока нет данных</span><b class="delta">0</b></div>`;
    return;
  }
  rows.forEach((row) => {
    const node = document.createElement("div");
    node.className = "row";
    node.innerHTML = `
      <div>
        <strong>${row[nameKey] || "unknown"}</strong><br>
        <span>${row.previous_trophies ?? "-"} → ${row.current_trophies ?? "-"}</span>
      </div>
      <b class="delta ${deltaClass(row.trophy_change)}">${formatDelta(row.trophy_change)}</b>
    `;
    container.appendChild(node);
  });
}

function renderBrawlerTable(items) {
  els.brawlerTable.innerHTML = "";
  if (!items.length) {
    els.brawlerTable.innerHTML = `<div class="row"><span>Сделай первый sync</span></div>`;
    return;
  }
  items.slice(0, 30).forEach((item) => {
    const node = document.createElement("div");
    node.className = "row";
    node.innerHTML = `
      <div>
        <strong>${item.name}</strong><br>
        <span>Сила ${item.power || "-"} · ранг ${item.rank || "-"}</span>
      </div>
      <b class="delta neutral">${item.trophies}</b>
    `;
    els.brawlerTable.appendChild(node);
  });
}

function renderProfile(profile, latest) {
  els.modeStats.innerHTML = "";
  if (!profile || !latest) {
    els.modeStats.innerHTML = `<div class="row"><span>Сделай первый sync</span></div>`;
    return;
  }
  const rows = [
    ["3v3 победы", latest.three_vs_three_victories],
    ["Solo победы", latest.solo_victories],
    ["Duo победы", latest.duo_victories],
    ["Ranked", profile.rankedPoints ? `${profile.rankedPoints} points` : profile.ranked || "-"],
    ["Лучший win streak", profile.highestWinStreak || "-"],
    ["Часов в игре", profile.playedHours ?? "-"],
    ["Клуб", profile.clubName || "-"],
  ];
  rows.forEach(([label, value]) => {
    const node = document.createElement("div");
    node.className = "row";
    node.innerHTML = `<strong>${label}</strong><span>${value}</span>`;
    els.modeStats.appendChild(node);
  });
}

function renderChanges(items) {
  els.battleList.innerHTML = "";
  if (!items.length) {
    els.battleList.innerHTML = `<div class="battle-item"><span>Изменения появятся после второго снимка профиля</span></div>`;
    return;
  }
  items.forEach((item) => {
    const node = document.createElement("div");
    node.className = "battle-item";
    node.innerHTML = `
      <div class="battle-meta">
        <strong>${item.name || "Brawler"}</strong>
        <span>${item.previous_trophies} → ${item.current_trophies} · сила ${item.power || "-"}</span>
      </div>
      <b class="delta ${deltaClass(item.trophy_change)}">${formatDelta(item.trophy_change)}</b>
    `;
    els.battleList.appendChild(node);
  });
}

async function refresh() {
  try {
    const stats = await api(`/api/stats?date=${els.dateInput.value}`);
    renderSetup(stats.settings);
    renderMetric(els.snapshotDelta, stats.today.snapshotDelta);
    els.battleDelta.textContent = stats.today.changedBrawlers || 0;
    els.battleDelta.className = "neutral";
    els.currentTrophies.textContent = stats.latest ? stats.latest.trophies.toLocaleString("ru-RU") : "-";
    els.playerName.textContent = stats.latest ? `${stats.latest.name} · ${stats.latest.tag}` : "Нет снимков профиля";
    els.battleCount.textContent = formatDelta((stats.today.positiveBrawlers || 0) - (stats.today.negativeBrawlers || 0));
    els.battleCount.className = deltaClass((stats.today.positiveBrawlers || 0) - (stats.today.negativeBrawlers || 0));
    els.battleSplit.textContent = `${stats.today.positiveBrawlers || 0} выросло / ${stats.today.negativeBrawlers || 0} упало`;
    renderHistory(stats.history || []);
    renderRows(els.brawlerStats, stats.byBrawler || [], "name");
    renderProfile(stats.profile, stats.latest);
    els.battleUpdated.textContent = stats.lastSyncAt ? `sync ${formatDateTime(stats.lastSyncAt)}` : "sync ещё не был";

    const brawlers = await api("/api/brawlers");
    renderBrawlerTable(brawlers.items || []);
    renderChanges(stats.recentBrawlerChanges || []);

    if (!stats.settings.configured) {
      setStatus("bad", "Введи player tag, чтобы начать трекинг без токена");
    } else if (stats.settings.lastSchedulerError) {
      setStatus("bad", stats.settings.lastSchedulerError);
    } else {
      setStatus("good", "Трекер готов. Фоновая синхронизация включена.");
    }
  } catch (error) {
    setStatus("bad", error.message);
  }
}

els.setupForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setStatus("", "Сохраняю настройки...");
  try {
    await api("/api/setup", {
      method: "POST",
      body: JSON.stringify({
        player_tag: els.playerTagInput.value,
        sync_interval_minutes: Number(els.intervalInput.value || 10),
      }),
    });
    await refresh();
  } catch (error) {
    setStatus("bad", error.message);
  }
});

els.syncButton.addEventListener("click", async () => {
  els.syncButton.disabled = true;
  setStatus("", "Запрашиваю BSInfo API...");
  try {
    const result = await api("/api/sync", { method: "POST" });
    setStatus("good", `Готово: ${result.trophies} кубков, бравлеров: ${result.brawlerCount}`);
    await refresh();
  } catch (error) {
    setStatus("bad", error.message);
  } finally {
    els.syncButton.disabled = false;
  }
});

els.dateInput.addEventListener("change", refresh);
refresh();
setInterval(refresh, 60_000);
