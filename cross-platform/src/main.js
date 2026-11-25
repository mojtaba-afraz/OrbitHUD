"use strict";

const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  screen,
  nativeImage,
  shell,
} = require("electron");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");
const { ProviderManager } = require("./providers/providerManager");
const { PROVIDER_META, PROVIDER_ORDER } = require("./providers/types");
const { getCandidateDaemonDirs } = require("./quotaFetcher");
const {
  checkForUpdate,
  downloadFileWithProgress,
  installDownloadedUpdate,
  fetchText,
  parseSha256Sums,
  verifyFileSha256,
} = require("./autoUpdater");
const { resolveWindowPosition } = require("./windowBounds");

const providerManager = new ProviderManager();

let widgetWindow = null;
let tray = null;
let refreshTimer = null;
let activeRefreshIntervalMs = 0;
let updateCheckTimer = null;
let isRefreshingQuota = false;
let pendingQuotaRefresh = false;
let pendingQuotaForce = false;
let consecutiveAgyDisconnects = 0;
const fsWatchers = [];
let watcherDebounceTimer = null;

let updateState = {
  status: "idle", // "idle" | "checking" | "available" | "downloading" | "installing" | "error"
  latestVersion: null,
  progress: 0,
  error: null,
  dismissed: false,
  asset: null,
  checksumAsset: null,
  releaseUrl: null,
};

const STATE_PATH = path.join(
  os.homedir(),
  ".gemini",
  "antigravity-usage-widget",
  "widget_state.json"
);

const DEFAULT_STATE = {
  mode: "floating", // "floating" | "desktop"
  compact: false, // false = Bento Glass (dynamic height), true = Compact Pill (height 52)
  locked: false,
  opacity: 0.96,
  x: null,
  y: null,
  enabledProviders: ["antigravity"],
  activeProviderFilter: "all",
  hiddenGroupIds: [],
  lastQuotaData: null,
};

let state = loadState();
let measuredBentoHeight = null;

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_PATH, "utf8");
    const parsed = JSON.parse(raw);
    const merged = { ...DEFAULT_STATE, ...parsed };
    merged.hiddenGroupIds = Array.isArray(merged.hiddenGroupIds)
      ? merged.hiddenGroupIds.filter((id) => typeof id === "string")
      : [];
    merged.enabledProviders = Array.isArray(merged.enabledProviders)
      ? PROVIDER_ORDER.filter((id) => merged.enabledProviders.includes(id))
      : ["antigravity"];
    if (merged.enabledProviders.length === 0) {
      merged.enabledProviders = ["antigravity"];
    }
    if (
      merged.activeProviderFilter !== "all" &&
      !merged.enabledProviders.includes(merged.activeProviderFilter)
    ) {
      merged.activeProviderFilter = "all";
    }
    return merged;
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function getVisibleGroups() {
  const groups = state.lastQuotaData?.groups || [];
  const hidden = new Set(state.hiddenGroupIds || []);
  const filter = state.activeProviderFilter || "all";
  return groups.filter((g) => {
    if (hidden.has(g.id)) return false;
    const pid = g.providerId || "antigravity";
    if (!state.enabledProviders.includes(pid)) return false;
    if (filter !== "all" && pid !== filter) return false;
    return true;
  });
}

function getVisibleRingItems() {
  const items = state.lastQuotaData?.ringItems || [];
  const hidden = new Set(state.hiddenGroupIds || []);
  const filter = state.activeProviderFilter || "all";
  return items.filter((it) => {
    if (it.groupId && hidden.has(it.groupId)) return false;
    const pid = it.providerId || "antigravity";
    if (!state.enabledProviders.includes(pid)) return false;
    if (filter !== "all" && pid !== filter) return false;
    return true;
  });
}

function toggleProvider(providerId) {
  if (!PROVIDER_ORDER.includes(providerId)) return;
  const set = new Set(state.enabledProviders || ["antigravity"]);
  if (set.has(providerId)) {
    if (set.size <= 1) return; // Always keep at least one provider enabled
    set.delete(providerId);
  } else {
    set.add(providerId);
  }
  state.enabledProviders = PROVIDER_ORDER.filter((id) => set.has(id));
  if (
    state.activeProviderFilter !== "all" &&
    !state.enabledProviders.includes(state.activeProviderFilter)
  ) {
    state.activeProviderFilter = "all";
  }
  measuredBentoHeight = null;
  saveState();
  applyWindowMode();
  sendStateToRenderer();
  refreshQuota(true);
}

function setProviderFilter(filterId) {
  if (filterId !== "all" && !state.enabledProviders.includes(filterId)) {
    return;
  }
  state.activeProviderFilter = filterId;
  measuredBentoHeight = null;
  saveState();
  applyWindowMode();
  sendStateToRenderer();
}

function toggleGroupVisibility(groupId) {
  if (!groupId || typeof groupId !== "string") return;
  const set = new Set(state.hiddenGroupIds || []);
  if (set.has(groupId)) {
    set.delete(groupId);
  } else {
    set.add(groupId);
  }
  state.hiddenGroupIds = Array.from(set);
  measuredBentoHeight = null;
  saveState();
  applyWindowMode();
  sendStateToRenderer();
}

function showAllGroups() {
  state.hiddenGroupIds = [];
  measuredBentoHeight = null;
  saveState();
  applyWindowMode();
  sendStateToRenderer();
}

function saveState() {
  try {
    fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
    fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2), "utf8");
  } catch {
    // ignore
  }
}

function hasVisibleUpdateBanner() {
  if (updateState.dismissed) return false;
  return (
    updateState.status === "available" ||
    updateState.status === "downloading" ||
    updateState.status === "installing" ||
    updateState.status === "error"
  );
}

// 12px transparent halo around the rounded card so CSS drop-shadow never clips at window edges
const WINDOW_SHADOW_PAD = 12;

function computeEstimatedBentoHeight() {
  const allGroups = state.lastQuotaData?.groups || [];
  const visibleGroups = getVisibleGroups();
  const bannerExtra = hasVisibleUpdateBanner() ? 42 : 0;
  const tabsExtra = (state.enabledProviders || []).length > 1 ? 30 : 0;

  if (allGroups.length === 0 || visibleGroups.length === 0) {
    return 108 + bannerExtra + tabsExtra;
  }

  // Outer card padding (28) + header (22) + gap (10)
  let h = 60 + bannerExtra + tabsExtra;
  visibleGroups.forEach((group, idx) => {
    const isDual = Array.isArray(group.buckets) && group.buckets.length >= 2;
    h += isDual ? 80 : 72;
    if (idx > 0) h += 10;
  });
  return Math.min(Math.max(h, 108), 640);
}

function getTargetDimensions() {
  if (state.compact) {
    const visibleCount = getVisibleRingItems().length;
    let cardWidth = 368;
    if (visibleCount === 0) {
      cardWidth = 276;
    } else if (visibleCount <= 2) {
      cardWidth = 256;
    } else if (visibleCount === 3) {
      cardWidth = 316;
    } else if (visibleCount <= 5) {
      cardWidth = 368;
    } else {
      cardWidth = 428;
    }
    return {
      width: cardWidth + WINDOW_SHADOW_PAD * 2,
      height: 52 + WINDOW_SHADOW_PAD * 2,
    };
  }
  const cardHeight =
    typeof measuredBentoHeight === "number"
      ? measuredBentoHeight
      : computeEstimatedBentoHeight();
  return {
    width: 356 + WINDOW_SHADOW_PAD * 2,
    height: cardHeight + WINDOW_SHADOW_PAD * 2,
  };
}

function getAppIconImage() {
  const candidates = [
    path.join(__dirname, "..", "assets", "tray-icon.png"),
    path.join(__dirname, "..", "assets", "icon.png"),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      const img = nativeImage.createFromPath(p);
      if (!img.isEmpty()) {
        return img;
      }
    }
  }
  return nativeImage.createEmpty();
}

function getLinuxAutostartPath() {
  const configHome =
    process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  return path.join(configHome, "autostart", "orbithud.desktop");
}

function getLaunchAtLogin() {
  try {
    if (process.platform === "linux") {
      return fs.existsSync(getLinuxAutostartPath());
    }
    return Boolean(app.getLoginItemSettings().openAtLogin);
  } catch {
    return false;
  }
}

function setLaunchAtLogin(enabled) {
  const target = Boolean(enabled);
  try {
    if (process.platform === "linux") {
      const desktopFile = getLinuxAutostartPath();
      if (target) {
        const execTarget = process.env.APPIMAGE || process.execPath;
        const desktopEntry = [
          "[Desktop Entry]",
          "Type=Application",
          "Name=OrbitHUD",
          "Comment=Zero-Gravity AI Usage & Quota HUD",
          `Exec="${execTarget}"`,
          "Terminal=false",
          "X-GNOME-Autostart-enabled=true",
          "",
        ].join("\n");
        fs.mkdirSync(path.dirname(desktopFile), { recursive: true });
        fs.writeFileSync(desktopFile, desktopEntry, "utf8");
      } else if (fs.existsSync(desktopFile)) {
        fs.unlinkSync(desktopFile);
      }
    } else {
      app.setLoginItemSettings({ openAtLogin: target });
    }
  } catch {
    // ignore OS-level permission failures and re-sync menu state below
  }
  updateTrayMenu();
}

function ensureWidgetOnScreen() {
  if (!widgetWindow || widgetWindow.isDestroyed()) return;
  const [curX, curY] = widgetWindow.getPosition();
  const [curW, curH] = widgetWindow.getSize();
  const resolved = resolveWindowPosition({
    savedX: curX,
    savedY: curY,
    width: curW,
    height: curH,
    displays: screen.getAllDisplays(),
    primaryDisplay: screen.getPrimaryDisplay(),
  });
  if (resolved.wasReset) {
    widgetWindow.setPosition(resolved.x, resolved.y, false);
    state.x = resolved.x;
    state.y = resolved.y;
    saveState();
  }
}

function createWidgetWindow() {
  const { width, height } = getTargetDimensions();
  const resolvedPos = resolveWindowPosition({
    savedX: typeof state.x === "number" ? state.x : null,
    savedY: typeof state.y === "number" ? state.y : null,
    width,
    height,
    displays: screen.getAllDisplays(),
    primaryDisplay: screen.getPrimaryDisplay(),
  });

  if (resolvedPos.wasReset && (state.x !== null || state.y !== null)) {
    state.x = resolvedPos.x;
    state.y = resolvedPos.y;
    saveState();
  }

  widgetWindow = new BrowserWindow({
    width,
    height,
    minWidth: width,
    maxWidth: width,
    minHeight: height,
    maxHeight: height,
    useContentSize: true,
    x: resolvedPos.x,
    y: resolvedPos.y,
    frame: false,
    transparent: true,
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    hasShadow: false,
    icon: getAppIconImage(),
    backgroundColor: "#00000000",
    ...(process.platform === "darwin"
      ? { vibrancy: "hud", visualEffectState: "active" }
      : {}),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  if (process.platform === "win32") {
    // Suppress Windows native titlebar context menu on -webkit-app-region: drag areas
    // and open OrbitHUD's control menu instead.
    const WM_INITMENU = 0x0116;
    widgetWindow.hookWindowMessage(WM_INITMENU, () => {
      if (!widgetWindow || widgetWindow.isDestroyed()) return;
      widgetWindow.setEnabled(false);
      widgetWindow.setEnabled(true);
      const menu = Menu.buildFromTemplate(buildControlMenuTemplate());
      menu.popup({ window: widgetWindow });
    });
  }

  widgetWindow.loadFile(path.join(__dirname, "index.html"));

  widgetWindow.on("moved", () => {
    if (!widgetWindow) return;
    const [x, y] = widgetWindow.getPosition();
    state.x = x;
    state.y = y;
    saveState();
  });

  widgetWindow.webContents.on("did-finish-load", () => {
    applyWindowMode();
    sendStateToRenderer();
    refreshQuota();
  });
}

function applyWindowMode() {
  if (!widgetWindow || widgetWindow.isDestroyed()) return;

  const { width, height } = getTargetDimensions();
  const [curW, curH] = widgetWindow.getContentSize();
  if (curW !== width || curH !== height) {
    widgetWindow.setResizable(true);
    widgetWindow.setMinimumSize(width, height);
    widgetWindow.setMaximumSize(width, height);
    widgetWindow.setContentSize(width, height, false);
    widgetWindow.setResizable(false);
  }

  widgetWindow.setOpacity(state.opacity);
  widgetWindow.setMovable(!state.locked);
  widgetWindow.setSkipTaskbar(true);

  if (state.mode === "floating") {
    widgetWindow.setAlwaysOnTop(true, "floating");
    widgetWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  } else {
    if (process.platform === "darwin") {
      widgetWindow.setAlwaysOnTop(false, "normal", -1);
    } else {
      widgetWindow.setAlwaysOnTop(false);
      widgetWindow.blur();
    }
    widgetWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: false });
  }

  updateTrayMenu();
}

function sendStateToRenderer() {
  if (!widgetWindow || widgetWindow.isDestroyed()) return;
  widgetWindow.webContents.send("widget:state", {
    mode: state.mode,
    compact: state.compact,
    locked: state.locked,
    opacity: state.opacity,
    enabledProviders: state.enabledProviders,
    activeProviderFilter: state.activeProviderFilter,
    providerMeta: PROVIDER_META,
    hiddenGroupIds: state.hiddenGroupIds,
    quotaData: state.lastQuotaData,
    appVersion: app.getVersion(),
    update: {
      status: updateState.status,
      latestVersion: updateState.latestVersion,
      progress: updateState.progress,
      error: updateState.error,
      dismissed: updateState.dismissed,
    },
  });
}

async function runUpdateCheck(manual = false) {
  if (
    updateState.status === "downloading" ||
    updateState.status === "installing"
  ) {
    return updateState;
  }
  if (manual) {
    updateState.status = "checking";
    updateState.error = null;
    sendStateToRenderer();
    updateTrayMenu();
  }
  try {
    const info = await checkForUpdate(app.getVersion());
    if (info && info.available) {
      updateState = {
        status: "available",
        latestVersion: info.latestVersion,
        progress: 0,
        error: null,
        dismissed: false,
        asset: info.asset,
        checksumAsset: info.checksumAsset || null,
        releaseUrl: info.releaseUrl,
      };
    } else {
      updateState.status = "idle";
      updateState.error = null;
    }
  } catch (err) {
    if (manual) {
      updateState.status = "error";
      updateState.error = err?.message || "Update check failed";
      updateState.dismissed = false;
    }
  }
  applyWindowMode();
  sendStateToRenderer();
  updateTrayMenu();
  return updateState;
}

async function startAutoUpdateDownload() {
  if (
    !updateState.asset ||
    !updateState.asset.url ||
    updateState.status === "downloading" ||
    updateState.status === "installing"
  ) {
    return;
  }

  updateState.status = "downloading";
  updateState.progress = 0;
  updateState.error = null;
  updateState.dismissed = false;
  applyWindowMode();
  sendStateToRenderer();
  updateTrayMenu();

  try {
    const destDir = path.join(os.tmpdir(), "orbithud-updates");
    const destPath = path.join(destDir, updateState.asset.name);
    await downloadFileWithProgress(updateState.asset.url, destPath, (pct) => {
      updateState.progress = pct;
      sendStateToRenderer();
    });

    // Fail-closed SHA256 verification against SHA256SUMS.txt before executing installer
    if (!updateState.checksumAsset || !updateState.checksumAsset.url) {
      try {
        if (fs.existsSync(destPath)) fs.unlinkSync(destPath);
      } catch {
        // ignore cleanup errors
      }
      throw new Error("Update aborted: SHA256SUMS.txt missing from release");
    }

    const checksumText = await fetchText(updateState.checksumAsset.url);
    const sums = parseSha256Sums(checksumText);
    const expectedHash = sums[updateState.asset.name];
    if (!expectedHash) {
      try {
        if (fs.existsSync(destPath)) fs.unlinkSync(destPath);
      } catch {
        // ignore cleanup errors
      }
      throw new Error(
        `Update aborted: no SHA256 checksum found for ${updateState.asset.name}`
      );
    }

    await verifyFileSha256(destPath, expectedHash);

    updateState.status = "installing";
    updateState.progress = 100;
    sendStateToRenderer();
    updateTrayMenu();

    const result = installDownloadedUpdate(destPath, process.platform, process.env, {
      execPath: process.execPath,
      pid: process.pid,
    });
    if (result && result.relaunching) {
      setTimeout(() => app.quit(), 250);
    } else if (result && result.openPath) {
      await shell.openPath(result.openPath);
    } else if (updateState.releaseUrl) {
      await shell.openExternal(updateState.releaseUrl);
    }
  } catch (err) {
    updateState.status = "error";
    updateState.error = err?.message || "Download failed";
    sendStateToRenderer();
    updateTrayMenu();
  }
}

function scheduleRefreshTimer(intervalMs) {
  const clamped = Math.max(intervalMs, 2000);
  if (refreshTimer && activeRefreshIntervalMs === clamped) {
    return;
  }
  if (refreshTimer) {
    clearInterval(refreshTimer);
  }
  activeRefreshIntervalMs = clamped;
  refreshTimer = setInterval(() => {
    refreshQuota(false);
  }, clamped);
}

function updateAdaptivePolling(providerStatuses) {
  const statuses = providerStatuses || {};
  const needsFastRecovery = (state.enabledProviders || ["antigravity"]).some((pid) => {
    const st = statuses[pid]?.status;
    return st === "auth_required" || st === "disconnected";
  });
  scheduleRefreshTimer(needsFastRecovery ? 3000 : 20000);
}

function setupAuthAndDaemonWatchers() {
  for (const w of fsWatchers) {
    try {
      w.close();
    } catch {
      // ignore
    }
  }
  fsWatchers.length = 0;

  const home = os.homedir();
  const watchDirs = new Set([
    ...getCandidateDaemonDirs(home),
    path.join(home, ".claude"),
    process.env.CODEX_HOME || path.join(home, ".codex"),
  ]);

  const triggerDebouncedRefresh = () => {
    if (watcherDebounceTimer) {
      clearTimeout(watcherDebounceTimer);
    }
    watcherDebounceTimer = setTimeout(() => {
      watcherDebounceTimer = null;
      refreshQuota(true);
    }, 300);
  };

  for (const dir of watchDirs) {
    try {
      if (!fs.existsSync(dir)) continue;
      const watcher = fs.watch(dir, { persistent: false }, () => {
        triggerDebouncedRefresh();
      });
      watcher.on("error", () => {});
      fsWatchers.push(watcher);
    } catch {
      // ignore unwatched dirs
    }
  }
}

async function refreshQuota(force = false) {
  if (isRefreshingQuota) {
    pendingQuotaRefresh = true;
    pendingQuotaForce = pendingQuotaForce || Boolean(force);
    return;
  }
  isRefreshingQuota = true;

  try {
    let nextForce = Boolean(force);
    do {
      pendingQuotaRefresh = false;
      pendingQuotaForce = false;

      const prevCount = state.lastQuotaData?.groups?.length || 0;
      const prevStatusKey = JSON.stringify(state.lastQuotaData?.providerStatuses || {});
      const merged = await providerManager.refresh(state.enabledProviders, { force: nextForce });
      if (merged) {
        const agyStatus = merged.providerStatuses?.antigravity?.status;
        if (state.enabledProviders.includes("antigravity")) {
          if (agyStatus === "connected") {
            consecutiveAgyDisconnects = 0;
          } else if (agyStatus === "auth_required") {
            // Immediately clear previous account's Antigravity groups on logout
            consecutiveAgyDisconnects = 0;
          } else if (agyStatus === "disconnected") {
            consecutiveAgyDisconnects += 1;
            // Preserve last known Antigravity groups only for 1 transient cycle (brief IDE restart)
            if (
              consecutiveAgyDisconnects <= 1 &&
              !merged.groups.some((g) => (g.providerId || "antigravity") === "antigravity") &&
              state.lastQuotaData?.groups?.some((g) => (g.providerId || "antigravity") === "antigravity")
            ) {
              const prevAgyGroups = state.lastQuotaData.groups.filter(
                (g) => (g.providerId || "antigravity") === "antigravity"
              );
              const prevAgyRings = (state.lastQuotaData.ringItems || []).filter(
                (it) => (it.providerId || "antigravity") === "antigravity"
              );
              merged.groups = [...prevAgyGroups, ...merged.groups];
              merged.ringItems = [...prevAgyRings, ...merged.ringItems];
            }
          }
        }

        state.lastQuotaData = merged;
        const newStatusKey = JSON.stringify(merged.providerStatuses || {});
        if ((merged.groups?.length || 0) !== prevCount || newStatusKey !== prevStatusKey) {
          measuredBentoHeight = null;
          applyWindowMode();
        }
        saveState();
        updateAdaptivePolling(merged.providerStatuses);
      }
      sendStateToRenderer();
      updateTrayMenu();

      nextForce = pendingQuotaForce;
    } while (pendingQuotaRefresh);
  } finally {
    isRefreshingQuota = false;
  }
}

function buildControlMenuTemplate() {
  const allGroups = state.lastQuotaData?.groups || [];
  const hiddenSet = new Set(state.hiddenGroupIds || []);
  const enabledSet = new Set(state.enabledProviders || ["antigravity"]);
  const items = getVisibleRingItems();
  const summaryLines =
    items.length > 0
      ? items.map((it) => ({
          label: `${it.title}: ${it.remainingPercentage}% (${it.subtitle})`,
          enabled: false,
        }))
      : [
          {
            label:
              allGroups.length > 0
                ? "All models hidden (enable in Visible Models)"
                : "Waiting for live quota...",
            enabled: false,
          },
        ];

  const providersSubmenu = PROVIDER_ORDER.map((id) => {
    const meta = PROVIDER_META[id];
    const isEnabled = enabledSet.has(id);
    const statusObj = state.lastQuotaData?.providerStatuses?.[id];
    const statusTag =
      isEnabled && statusObj?.status === "auth_required"
        ? " (Login needed)"
        : isEnabled && statusObj?.status === "rate_limited"
        ? " (Rate limited)"
        : "";
    return {
      label: `${meta.name}${statusTag}`,
      type: "checkbox",
      checked: isEnabled,
      enabled: !(isEnabled && enabledSet.size <= 1),
      click: () => toggleProvider(id),
    };
  });

  const multiProvider = enabledSet.size > 1;
  const visibleModelsSubmenu =
    allGroups.length > 0
      ? [
          ...allGroups.map((g) => {
            const pid = g.providerId || "antigravity";
            const prefix = multiProvider ? `[${PROVIDER_META[pid]?.shortName || pid}] ` : "";
            return {
              label: `${prefix}${g.displayName}`,
              type: "checkbox",
              checked: !hiddenSet.has(g.id),
              click: () => toggleGroupVisibility(g.id),
            };
          }),
          ...(hiddenSet.size > 0
            ? [
                { type: "separator" },
                {
                  label: "Show All Models",
                  click: () => showAllGroups(),
                },
              ]
            : []),
        ]
      : [{ label: "No models detected yet", enabled: false }];

  return [
    { label: "OrbitHUD — AI Usage HUD", enabled: false },
    { type: "separator" },
    ...summaryLines,
    { type: "separator" },
    {
      label: "Providers",
      submenu: providersSubmenu,
    },
    {
      label: "Visible Models",
      submenu: visibleModelsSubmenu,
    },
    { type: "separator" },
    {
      label: "Floating Mode (Always on Top)",
      type: "radio",
      checked: state.mode === "floating",
      click: () => {
        state.mode = "floating";
        saveState();
        applyWindowMode();
        sendStateToRenderer();
      },
    },
    {
      label: "Desktop Widget Mode (Pinned to Wallpaper)",
      type: "radio",
      checked: state.mode === "desktop",
      click: () => {
        state.mode = "desktop";
        saveState();
        applyWindowMode();
        sendStateToRenderer();
      },
    },
    { type: "separator" },
    {
      label: "Compact Coding Pill Layout",
      type: "checkbox",
      checked: state.compact,
      click: () => {
        state.compact = !state.compact;
        measuredBentoHeight = null;
        saveState();
        applyWindowMode();
        sendStateToRenderer();
      },
    },
    {
      label: "Lock Widget Position",
      type: "checkbox",
      checked: state.locked,
      click: () => {
        state.locked = !state.locked;
        saveState();
        applyWindowMode();
        sendStateToRenderer();
      },
    },
    {
      label: "Launch at Login",
      type: "checkbox",
      checked: getLaunchAtLogin(),
      click: () => {
        setLaunchAtLogin(!getLaunchAtLogin());
      },
    },
    {
      label: "Window Opacity",
      submenu: [1.0, 0.95, 0.85, 0.75, 0.65].map((op) => ({
        label: `${Math.round(op * 100)}%`,
        type: "radio",
        checked: Math.abs(state.opacity - op) < 0.03,
        click: () => {
          state.opacity = op;
          saveState();
          applyWindowMode();
          sendStateToRenderer();
        },
      })),
    },
    {
      label: "Refresh Usage Now",
      click: () => refreshQuota(true),
    },
    ...(updateState.status === "available"
      ? [
          {
            label: `Install Update (v${updateState.latestVersion})`,
            click: () => startAutoUpdateDownload(),
          },
        ]
      : [
          {
            label:
              updateState.status === "downloading"
                ? `Downloading Update (${updateState.progress}%)...`
                : updateState.status === "checking"
                ? "Checking for Updates..."
                : `Check for Updates (v${app.getVersion()})`,
            enabled:
              updateState.status !== "downloading" &&
              updateState.status !== "installing",
            click: () => runUpdateCheck(true),
          },
        ]),
    { type: "separator" },
    {
      label: "Quit OrbitHUD",
      click: () => app.quit(),
    },
  ];
}

function createTrayIcon() {
  try {
    const img = getAppIconImage();
    if (img.isEmpty()) return;
    tray = new Tray(img.resize({ width: 16, height: 16 }));
    tray.setToolTip("OrbitHUD — AI Usage & Quota HUD");
    tray.on("click", () => {
      if (widgetWindow && !widgetWindow.isDestroyed()) {
        widgetWindow.show();
        widgetWindow.focus();
      }
    });
    updateTrayMenu();
  } catch {
    // ignore tray failure on headless environments
  }
}

function updateTrayMenu() {
  if (!tray) return;
  const menu = Menu.buildFromTemplate(buildControlMenuTemplate());
  tray.setContextMenu(menu);
}

// IPC handlers for renderer controls, context menu, and Quit
ipcMain.handle("widget:toggle-mode", () => {
  state.mode = state.mode === "floating" ? "desktop" : "floating";
  saveState();
  applyWindowMode();
  sendStateToRenderer();
  return state;
});

ipcMain.handle("widget:toggle-compact", () => {
  state.compact = !state.compact;
  measuredBentoHeight = null;
  saveState();
  applyWindowMode();
  sendStateToRenderer();
  return state;
});

ipcMain.handle("widget:toggle-group-visibility", (_event, groupId) => {
  toggleGroupVisibility(groupId);
  return state;
});

ipcMain.handle("widget:show-all-groups", () => {
  showAllGroups();
  return state;
});

ipcMain.on("widget:sync-height", (_event, cardHeight) => {
  if (state.compact) return;
  if (typeof cardHeight !== "number" || !Number.isFinite(cardHeight)) return;
  const clamped = Math.min(Math.max(Math.ceil(cardHeight), 84), 680);
  if (measuredBentoHeight === null || Math.abs(measuredBentoHeight - clamped) > 2) {
    measuredBentoHeight = clamped;
    applyWindowMode();
  }
});

ipcMain.handle("widget:toggle-provider", (_event, providerId) => {
  toggleProvider(providerId);
  return state;
});

ipcMain.handle("widget:set-provider-filter", (_event, filterId) => {
  setProviderFilter(filterId);
  return state;
});

ipcMain.handle("widget:refresh", async () => {
  await refreshQuota(true);
  return state;
});

ipcMain.on("widget:show-menu", () => {
  if (!widgetWindow || widgetWindow.isDestroyed()) return;
  const menu = Menu.buildFromTemplate(buildControlMenuTemplate());
  menu.popup({ window: widgetWindow });
});

ipcMain.on("widget:quit", () => {
  app.quit();
});

ipcMain.handle("widget:check-update", async () => {
  return runUpdateCheck(true);
});

ipcMain.on("widget:start-update", () => {
  startAutoUpdateDownload();
});

ipcMain.on("widget:dismiss-update", () => {
  updateState.dismissed = true;
  measuredBentoHeight = null;
  applyWindowMode();
  sendStateToRenderer();
});

app.whenReady().then(() => {
  if (process.platform === "darwin" && app.dock) {
    app.dock.hide();
  }
  createTrayIcon();
  createWidgetWindow();
  screen.on("display-removed", ensureWidgetOnScreen);
  screen.on("display-metrics-changed", ensureWidgetOnScreen);
  setupAuthAndDaemonWatchers();
  scheduleRefreshTimer(20000);
  setTimeout(() => runUpdateCheck(false), 5000);
  updateCheckTimer = setInterval(
    () => runUpdateCheck(false),
    4 * 60 * 60 * 1000
  );
});

app.on("window-all-closed", (e) => {
  e.preventDefault();
});
