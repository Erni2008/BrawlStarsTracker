const BSINFO_BASE = "https://api.bsinfox.com";
const BRAWLAPI_EVENTS = "https://api.brawlapi.com/v1/events";
const STORAGE_KEY = "brawl_tracker_pwa_state_v1";

const i18n = {
  ru: {
    eyebrow: "Brawl Stars companion",
    appTitle: "Трекер кубков",
    appSubtitle: "Без токена: снимки профиля, бравлеры, карты и дневная динамика прямо на iPhone.",
    install: "Установить",
    playerTag: "Player tag",
    syncInterval: "Интервал, мин",
    syncNow: "Обновить",
    statusReady: "Введи тег и сделай первый снимок.",
    tabDashboard: "Главная",
    tabBrawlers: "Бравлеры",
    tabMaps: "Карты",
    tabHistory: "История",
    today: "Сегодня",
    todayHint: "по снимкам профиля",
    currentTrophies: "Кубки",
    wins: "Победы",
    losses: "Поражения",
    lossesHint: "оценка по минусу кубков",
    quickCoach: "Быстрый коуч",
    quickCoachHint: "Что стоит сделать дальше по последним данным.",
    recentChanges: "Последние изменения",
    recentChangesHint: "Сравнение двух последних снимков.",
    brawlersTitle: "Бравлеры",
    brawlersHint: "Кубки, сила, ранг и прогресс каждого персонажа.",
    sortTrophies: "Кубки",
    sortPower: "Сила",
    sortRank: "Ранг",
    sortName: "Имя",
    currentMaps: "Сейчас в игре",
    currentMapsHint: "Активные карты и режимы из BrawlAPI.",
    upcomingMaps: "Следующие карты",
    upcomingMapsHint: "Отдельный список будущей ротации.",
    historyTitle: "История кубков",
    historyHint: "Каждый столбец показывает дельту за день.",
    snapshotsTitle: "Снимки",
    snapshotsHint: "Данные хранятся локально в браузере.",
    clear: "Очистить",
    noSnapshots: "Пока нет снимков. Нажми «Обновить».",
    noChanges: "Изменения появятся после второго снимка.",
    noMaps: "Карты пока не загрузились.",
    syncing: "Запрашиваю публичный профиль...",
    synced: "Снимок сохранен.",
    syncError: "Не удалось обновить данные",
    mapsError: "Карты временно недоступны",
    installHint: "На iPhone: Safari -> Поделиться -> На экран «Домой».",
    brawlerGoal: "Цель бравлеров",
    pushGoal: "Ближайшая цель",
    goodDay: "Хороший день",
    recovery: "Восстановление",
    stable: "Стабильно",
    trophies: "кубков",
    power: "сила",
    rank: "ранг",
    best: "пик",
    openMap: "Открыть карту",
    now: "сейчас",
    soon: "скоро",
    total: "всего",
    profile: "Профиль",
    clearConfirm: "Очистить локальную историю снимков?"
  },
  en: {
    eyebrow: "Brawl Stars companion",
    appTitle: "Trophy tracker",
    appSubtitle: "Tokenless profile snapshots, brawlers, maps, and daily progress on iPhone.",
    install: "Install",
    playerTag: "Player tag",
    syncInterval: "Interval, min",
    syncNow: "Sync",
    statusReady: "Enter a tag and take the first snapshot.",
    tabDashboard: "Home",
    tabBrawlers: "Brawlers",
    tabMaps: "Maps",
    tabHistory: "History",
    today: "Today",
    todayHint: "from profile snapshots",
    currentTrophies: "Trophies",
    wins: "Wins",
    losses: "Losses",
    lossesHint: "estimated from trophy drops",
    quickCoach: "Quick coach",
    quickCoachHint: "What to do next based on recent data.",
    recentChanges: "Recent changes",
    recentChangesHint: "Comparison of the two latest snapshots.",
    brawlersTitle: "Brawlers",
    brawlersHint: "Trophies, power, rank, and progress for each character.",
    sortTrophies: "Trophies",
    sortPower: "Power",
    sortRank: "Rank",
    sortName: "Name",
    currentMaps: "Live maps",
    currentMapsHint: "Active maps and modes from BrawlAPI.",
    upcomingMaps: "Upcoming maps",
    upcomingMapsHint: "Future rotation separated from live maps.",
    historyTitle: "Trophy history",
    historyHint: "Each bar shows the daily delta.",
    snapshotsTitle: "Snapshots",
    snapshotsHint: "Data is stored locally in this browser.",
    clear: "Clear",
    noSnapshots: "No snapshots yet. Tap Sync.",
    noChanges: "Changes appear after the second snapshot.",
    noMaps: "Maps have not loaded yet.",
    syncing: "Fetching public profile...",
    synced: "Snapshot saved.",
    syncError: "Could not sync data",
    mapsError: "Maps are temporarily unavailable",
    installHint: "On iPhone: Safari -> Share -> Add to Home Screen.",
    brawlerGoal: "Brawler goal",
    pushGoal: "Closest goal",
    goodDay: "Good day",
    recovery: "Recovery",
    stable: "Stable",
    trophies: "trophies",
    power: "power",
    rank: "rank",
    best: "best",
    openMap: "Open map",
    now: "now",
    soon: "soon",
    total: "total",
    profile: "Profile",
    clearConfirm: "Clear local snapshot history?"
  }
};

const modeTranslations = {
  "gem grab": ["Захват кристаллов", "Gem Grab"],
  showdown: ["Столкновение", "Showdown"],
  "solo showdown": ["Одиночное столкновение", "Solo Showdown"],
  "duo showdown": ["Парное столкновение", "Duo Showdown"],
  brawlball: ["Броулбол", "Brawl Ball"],
  "brawl ball": ["Броулбол", "Brawl Ball"],
  heist: ["Ограбление", "Heist"],
  bounty: ["Награда за поимку", "Bounty"],
  knockout: ["Нокаут", "Knockout"],
  hotzone: ["Горячая зона", "Hot Zone"],
  "hot zone": ["Горячая зона", "Hot Zone"],
  wipeout: ["Зачистка", "Wipeout"],
  basketbrawl: ["Баскетбой", "Basket Brawl"],
  duels: ["Дуэли", "Duels"]
};

const els = {
  setupForm: document.querySelector("#setupForm"),
  playerTagInput: document.querySelector("#playerTagInput"),
  intervalInput: document.querySelector("#intervalInput"),
  syncButton: document.querySelector("#syncButton"),
  languageButton: document.querySelector("#languageButton"),
  installButton: document.querySelector("#installButton"),
  statusDot: document.querySelector("#statusDot"),
  statusText: document.querySelector("#statusText"),
  tabs: document.querySelectorAll(".tab"),
  panels: document.querySelectorAll(".tab-panel"),
  todayDelta: document.querySelector("#todayDelta"),
  currentTrophies: document.querySelector("#currentTrophies"),
  playerName: document.querySelector("#playerName"),
  winsTotal: document.querySelector("#winsTotal"),
  winsSplit: document.querySelector("#winsSplit"),
  lossEstimate: document.querySelector("#lossEstimate"),
  lastSync: document.querySelector("#lastSync"),
  coachList: document.querySelector("#coachList"),
  recentChanges: document.querySelector("#recentChanges"),
  brawlerSort: document.querySelector("#brawlerSort"),
  brawlerList: document.querySelector("#brawlerList"),
  currentMaps: document.querySelector("#currentMaps"),
  upcomingMaps: document.querySelector("#upcomingMaps"),
  historyChart: document.querySelector("#historyChart"),
  snapshotList: document.querySelector("#snapshotList"),
  clearButton: document.querySelector("#clearButton"),
  mapDialog: document.querySelector("#mapDialog"),
  closeMapDialog: document.querySelector("#closeMapDialog"),
  mapPreview: document.querySelector("#mapPreview"),
  mapDialogTitle: document.querySelector("#mapDialogTitle"),
  mapDialogMode: document.querySelector("#mapDialogMode")
};

let deferredInstallPrompt = null;
let state = loadState();

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    return {
      language: saved.language || "ru",
      playerTag: saved.playerTag || "",
      syncIntervalMinutes: saved.syncIntervalMinutes || 10,
      snapshots: Array.isArray(saved.snapshots) ? saved.snapshots : [],
      maps: saved.maps || { current: [], upcoming: [], fetchedAt: null }
    };
  } catch {
    return { language: "ru", playerTag: "", syncIntervalMinutes: 10, snapshots: [], maps: { current: [], upcoming: [], fetchedAt: null } };
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function t(key) {
  return i18n[state.language][key] || i18n.ru[key] || key;
}

function localizeMode(mode) {
  const pair = modeTranslations[String(mode || "").toLowerCase()];
  if (!pair) return mode || "-";
  return state.language === "ru" ? pair[0] : pair[1];
}

function normalizeTag(tag) {
  const clean = String(tag || "").trim().toUpperCase().replaceAll("O", "0");
  return clean.startsWith("#") ? clean : `#${clean}`;
}

function encodeTag(tag) {
  return encodeURIComponent(normalizeTag(tag).replace("#", ""));
}

function setStatus(kind, text) {
  els.statusDot.className = `status-dot ${kind || ""}`;
  els.statusText.textContent = text;
}

function formatNumber(value) {
  return Number(value || 0).toLocaleString(state.language === "ru" ? "ru-RU" : "en-US");
}

function formatDelta(value) {
  const number = Number(value || 0);
  return number > 0 ? `+${number}` : `${number}`;
}

function deltaClass(value) {
  const number = Number(value || 0);
  if (number > 0) return "positive";
  if (number < 0) return "negative";
  return "neutral";
}

function snapshotDate(snapshot) {
  return new Date(snapshot.capturedAt);
}

function dayKey(date) {
  return date.toISOString().slice(0, 10);
}

function sameLocalDay(a, b = new Date()) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function latestSnapshot() {
  return state.snapshots.at(-1) || null;
}

function previousSnapshot() {
  return state.snapshots.at(-2) || null;
}

function todayBaseline() {
  const todaySnapshots = state.snapshots.filter((snapshot) => sameLocalDay(snapshotDate(snapshot)));
  return todaySnapshots[0] || state.snapshots.findLast((snapshot) => !sameLocalDay(snapshotDate(snapshot))) || state.snapshots[0] || null;
}

function computeBrawlerChanges(current, baseline) {
  if (!current || !baseline) return [];
  const previousById = new Map((baseline.brawlers || []).map((item) => [item.id || item.name, item]));
  return (current.brawlers || [])
    .map((item) => {
      const old = previousById.get(item.id || item.name);
      if (!old) return null;
      const delta = Number(item.trophies || 0) - Number(old.trophies || 0);
      if (!delta) return null;
      return { ...item, previousTrophies: old.trophies || 0, delta };
    })
    .filter(Boolean)
    .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
}

function estimateLosses(changes) {
  const visibleLostTrophies = changes.filter((item) => item.delta < 0).reduce((sum, item) => sum + Math.abs(item.delta), 0);
  return {
    count: Math.max(0, Math.round(visibleLostTrophies / 8)),
    visibleLostTrophies
  };
}

function translate() {
  document.documentElement.lang = state.language;
  document.querySelectorAll("[data-i18n]").forEach((node) => {
    node.textContent = t(node.dataset.i18n);
  });
  els.languageButton.textContent = state.language === "ru" ? "EN" : "RU";
}

function render() {
  translate();
  els.playerTagInput.value = state.playerTag;
  els.intervalInput.value = state.syncIntervalMinutes;

  const latest = latestSnapshot();
  const baseline = todayBaseline();
  const recentBaseline = previousSnapshot();
  const todayDelta = latest && baseline ? Number(latest.trophies || 0) - Number(baseline.trophies || 0) : 0;
  const recentChanges = computeBrawlerChanges(latest, recentBaseline);
  const todayChanges = computeBrawlerChanges(latest, baseline);
  const losses = estimateLosses(recentChanges);

  els.todayDelta.textContent = formatDelta(todayDelta);
  els.todayDelta.className = deltaClass(todayDelta);
  els.currentTrophies.textContent = latest ? formatNumber(latest.trophies) : "-";
  els.playerName.textContent = latest ? `${latest.name} · ${latest.tag}` : t("noSnapshots");

  const wins = latest ? Number(latest.threeVsThreeVictories || 0) + Number(latest.soloVictories || 0) + Number(latest.duoVictories || 0) : 0;
  els.winsTotal.textContent = formatNumber(wins);
  els.winsSplit.textContent = latest ? `3v3 ${formatNumber(latest.threeVsThreeVictories)} · solo ${formatNumber(latest.soloVictories)} · duo ${formatNumber(latest.duoVictories)}` : "3v3 0 · solo 0 · duo 0";
  els.lossEstimate.textContent = `~${losses.count}`;
  els.lastSync.textContent = latest ? new Date(latest.capturedAt).toLocaleString(state.language === "ru" ? "ru-RU" : "en-US", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "-";

  renderCoach(latest, todayDelta, todayChanges, losses);
  renderChanges(recentChanges);
  renderBrawlers(latest);
  renderMaps();
  renderHistory();
  renderSnapshots();
}

function renderCoach(latest, todayDelta, changes, losses) {
  const rows = [];
  if (!latest) {
    rows.push([t("profile"), t("installHint"), "sparkles"]);
  } else if (todayDelta > 0) {
    rows.push([t("goodDay"), `${formatDelta(todayDelta)} ${t("trophies")} ${t("today").toLowerCase()}.`, "chart-line"]);
  } else if (todayDelta < 0) {
    rows.push([t("recovery"), `${Math.abs(todayDelta)} ${t("trophies")} ${state.language === "ru" ? "нужно вернуть до нуля дня." : "to recover today's balance."}`, "rotate-ccw"]);
  } else {
    rows.push([t("stable"), state.language === "ru" ? "Сделай еще один снимок после пуша." : "Take another snapshot after a push session.", "gauge"]);
  }

  const target = (latest?.brawlers || []).slice().sort((a, b) => (b.trophies || 0) - (a.trophies || 0)).find((brawler) => (brawler.trophies || 0) % 50 >= 35);
  if (target) {
    const nextGoal = Math.ceil((target.trophies + 1) / 50) * 50;
    rows.push([t("pushGoal"), `${target.name}: ${target.trophies} -> ${nextGoal}`, "target"]);
  }

  if (changes.length) {
    const best = changes[0];
    rows.push([t("brawlerGoal"), `${best.name}: ${formatDelta(best.delta)} ${t("trophies")}`, "zap"]);
  }

  if (losses.visibleLostTrophies > 0) {
    rows.push([t("losses"), `${state.language === "ru" ? "Потеряно видно" : "Visible lost"}: ${losses.visibleLostTrophies} ${t("trophies")}.`, "shield-alert"]);
  }

  els.coachList.innerHTML = rows.map(([title, detail]) => `
    <div class="coach-card">
      <strong>${title}</strong>
      <span>${detail}</span>
    </div>
  `).join("");
}

function renderChanges(changes) {
  if (!changes.length) {
    els.recentChanges.innerHTML = `<div class="empty">${t("noChanges")}</div>`;
    return;
  }
  els.recentChanges.innerHTML = changes.slice(0, 8).map((item) => `
    <div class="row">
      <div>
        <strong>${item.name}</strong>
        <span>${item.previousTrophies} -> ${item.trophies} · ${t("power")} ${item.power || "-"}</span>
      </div>
      <b class="${deltaClass(item.delta)}">${formatDelta(item.delta)}</b>
    </div>
  `).join("");
}

function renderBrawlers(latest) {
  if (!latest?.brawlers?.length) {
    els.brawlerList.innerHTML = `<div class="empty">${t("noSnapshots")}</div>`;
    return;
  }
  const sortKey = els.brawlerSort.value;
  const items = latest.brawlers.slice().sort((a, b) => {
    if (sortKey === "name") return String(a.name).localeCompare(String(b.name));
    return Number(b[sortKey] || 0) - Number(a[sortKey] || 0);
  });
  const maxTrophies = Math.max(1, ...items.map((item) => Number(item.trophies || 0)));
  els.brawlerList.innerHTML = items.map((item) => {
    const progress = Math.max(4, Math.round((Number(item.trophies || 0) / maxTrophies) * 100));
    const image = item.id ? `https://cdn.brawlify.com/brawlers/borderless/${item.id}.png` : "";
    return `
      <article class="brawler-card">
        <div class="brawler-avatar">${image ? `<img src="${image}" alt="${item.name}" loading="lazy">` : `<span>${String(item.name || "?").slice(0, 1)}</span>`}</div>
        <div class="brawler-body">
          <div class="brawler-title">
            <strong>${item.name}</strong>
            <b>${formatNumber(item.trophies)}</b>
          </div>
          <div class="chip-row">
            <span>${t("power")} ${item.power || "-"}</span>
            <span>${t("rank")} ${item.rank || "-"}</span>
            <span>${t("best")} ${formatNumber(item.highestTrophies || 0)}</span>
            <span>SP ${item.starPowers || 0}</span>
            <span>G ${item.gadgets || 0}</span>
            <span>Gear ${item.gears || 0}</span>
            <span>H ${item.hyperCharges || 0}</span>
          </div>
          <div class="progress"><i style="width:${progress}%"></i></div>
        </div>
      </article>
    `;
  }).join("");
}

function renderMaps() {
  renderMapList(els.currentMaps, state.maps.current, "now");
  renderMapList(els.upcomingMaps, state.maps.upcoming, "soon");
}

function renderMapList(container, maps, kind) {
  if (!maps.length) {
    container.innerHTML = `<div class="empty">${t("noMaps")}</div>`;
    return;
  }
  container.innerHTML = maps.slice(0, kind === "now" ? 12 : 18).map((event, index) => {
    const map = event.map || {};
    const image = map.imageUrl || map.imageUrl2 || (map.id ? `https://cdn.brawlify.com/maps/regular/${map.id}.png` : "");
    const mode = map.gameMode?.name || event.mode?.name || event.mode || "";
    return `
      <button class="map-card" type="button" data-map-kind="${kind}" data-map-index="${index}">
        ${image ? `<img src="${image}" alt="${map.name || "Map"}" loading="lazy">` : ""}
        <span>${localizeMode(mode)}</span>
        <strong>${map.name || "-"}</strong>
        <small>${t(kind)}</small>
      </button>
    `;
  }).join("");
}

function renderHistory() {
  const byDay = new Map();
  state.snapshots.forEach((snapshot) => {
    const key = dayKey(snapshotDate(snapshot));
    if (!byDay.has(key)) byDay.set(key, []);
    byDay.get(key).push(snapshot);
  });
  const rows = Array.from(byDay.entries()).slice(-14).map(([day, snapshots]) => ({
    day,
    delta: Number(snapshots.at(-1)?.trophies || 0) - Number(snapshots[0]?.trophies || 0)
  }));
  if (!rows.length) {
    els.historyChart.innerHTML = `<div class="empty">${t("noSnapshots")}</div>`;
    return;
  }
  const maxAbs = Math.max(1, ...rows.map((row) => Math.abs(row.delta)));
  els.historyChart.innerHTML = rows.map((row) => {
    const height = Math.max(8, Math.round(Math.abs(row.delta) / maxAbs * 150));
    const label = row.day.slice(5).replace("-", ".");
    return `
      <div class="bar-wrap">
        <div class="bar ${row.delta < 0 ? "negative-bar" : ""}" style="height:${height}px"></div>
        <span>${label}</span>
        <b class="${deltaClass(row.delta)}">${formatDelta(row.delta)}</b>
      </div>
    `;
  }).join("");
}

function renderSnapshots() {
  if (!state.snapshots.length) {
    els.snapshotList.innerHTML = `<div class="empty">${t("noSnapshots")}</div>`;
    return;
  }
  els.snapshotList.innerHTML = state.snapshots.slice(-12).reverse().map((snapshot) => `
    <div class="row">
      <div>
        <strong>${snapshot.name}</strong>
        <span>${new Date(snapshot.capturedAt).toLocaleString(state.language === "ru" ? "ru-RU" : "en-US")}</span>
      </div>
      <b>${formatNumber(snapshot.trophies)}</b>
    </div>
  `).join("");
}

async function fetchProfile(tag) {
  const response = await fetch(`${BSINFO_BASE}/players/${encodeTag(tag)}`, {
    headers: { Accept: "application/json" }
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.detail || payload.message || `${t("syncError")}: ${response.status}`);
  }
  const player = payload.data && typeof payload.data === "object" ? payload.data : payload;
  return {
    capturedAt: new Date().toISOString(),
    tag: normalizeTag(player.tag || tag),
    name: player.name || "Unknown",
    trophies: Number(player.trophies || 0),
    highestTrophies: Number(player.highestTrophies || 0),
    expLevel: Number(player.expLevel || 0),
    threeVsThreeVictories: Number(player["3vs3Victories"] || 0),
    soloVictories: Number(player.soloVictories || 0),
    duoVictories: Number(player.duoVictories || 0),
    ranked: player.ranked,
    rankedPoints: player.rankedPoints,
    highestWinStreak: player.highestWinStreak,
    brawlers: (player.brawlers || []).map((brawler) => ({
      id: brawler.id,
      name: brawler.name || "Brawler",
      trophies: Number(brawler.trophies || 0),
      highestTrophies: Number(brawler.highestTrophies || 0),
      power: Number(brawler.power || 0),
      rank: Number(brawler.rank || 0),
      starPowers: (brawler.starPowers || []).length,
      gadgets: (brawler.gadgets || []).length,
      gears: (brawler.gears || []).length,
      hyperCharges: (brawler.hyperCharges || []).length,
      buffies: brawler.buffies || null
    }))
  };
}

async function syncNow() {
  const tag = normalizeTag(els.playerTagInput.value || state.playerTag);
  if (tag.length < 3) {
    setStatus("bad", t("statusReady"));
    return;
  }
  state.playerTag = tag;
  state.syncIntervalMinutes = Number(els.intervalInput.value || 10);
  saveState();

  els.syncButton.disabled = true;
  setStatus("", t("syncing"));
  try {
    const profile = await fetchProfile(tag);
    state.snapshots.push(profile);
    state.snapshots = state.snapshots.slice(-240);
    saveState();
    setStatus("good", `${t("synced")} ${profile.name}: ${formatNumber(profile.trophies)} ${t("trophies")}.`);
    render();
  } catch (error) {
    setStatus("bad", `${t("syncError")}: ${error.message}`);
  } finally {
    els.syncButton.disabled = false;
  }
}

async function loadMaps() {
  try {
    const response = await fetch(BRAWLAPI_EVENTS);
    const payload = await response.json();
    const current = (Array.isArray(payload) ? payload : payload.active || payload.events || []).map((event) => event.event || event);
    const upcoming = (payload.upcoming || []).map((event) => event.event || event);
    state.maps = {
      current,
      upcoming,
      fetchedAt: new Date().toISOString()
    };
    saveState();
    renderMaps();
  } catch {
    setStatus("bad", t("mapsError"));
  }
}

function openMap(kind, index) {
  const item = state.maps[kind === "now" ? "current" : "upcoming"][Number(index)];
  if (!item) return;
  const map = item.map || {};
  const image = map.imageUrl || map.imageUrl2 || (map.id ? `https://cdn.brawlify.com/maps/regular/${map.id}.png` : "");
  const mode = map.gameMode?.name || item.mode?.name || item.mode || "";
  els.mapPreview.src = image;
  els.mapPreview.alt = map.name || "Map";
  els.mapDialogTitle.textContent = map.name || "-";
  els.mapDialogMode.textContent = localizeMode(mode);
  els.mapDialog.showModal();
}

function bindEvents() {
  els.setupForm.addEventListener("submit", (event) => {
    event.preventDefault();
    syncNow();
  });

  els.languageButton.addEventListener("click", () => {
    state.language = state.language === "ru" ? "en" : "ru";
    saveState();
    render();
  });

  els.tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      els.tabs.forEach((item) => item.classList.toggle("active", item === tab));
      els.panels.forEach((panel) => panel.classList.toggle("active", panel.id === `${tab.dataset.tab}Tab`));
    });
  });

  els.brawlerSort.addEventListener("change", render);
  els.clearButton.addEventListener("click", () => {
    if (!confirm(t("clearConfirm"))) return;
    state.snapshots = [];
    saveState();
    render();
  });

  document.addEventListener("click", (event) => {
    const card = event.target.closest(".map-card");
    if (card) openMap(card.dataset.mapKind, card.dataset.mapIndex);
  });

  els.closeMapDialog.addEventListener("click", () => els.mapDialog.close());

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredInstallPrompt = event;
    els.installButton.classList.remove("hidden");
  });

  els.installButton.addEventListener("click", async () => {
    if (!deferredInstallPrompt) {
      setStatus("", t("installHint"));
      return;
    }
    deferredInstallPrompt.prompt();
    await deferredInstallPrompt.userChoice;
    deferredInstallPrompt = null;
    els.installButton.classList.add("hidden");
  });
}

function scheduleAutoSync() {
  window.setInterval(() => {
    if (!state.playerTag) return;
    syncNow();
  }, Math.max(2, Number(state.syncIntervalMinutes || 10)) * 60_000);
}

async function boot() {
  bindEvents();
  render();
  await loadMaps();
  scheduleAutoSync();
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

boot();
