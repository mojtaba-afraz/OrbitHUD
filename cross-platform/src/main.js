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
const { fetchLiveQuotaSummary } = require("./quotaFetcher");
const {
  checkForUpdate,
  downloadFileWithProgress,
  installDownloadedUpdate,
} = require("./autoUpdater");

let widgetWindow = null;
let tray = null;
let refreshTimer = null;
let updateCheckTimer = null;

let updateState = {
  status: "idle", // "idle" | "checking" | "available" | "downloading" | "installing" | "error"
  latestVersion: null,
  progress: 0,
  error: null,
  dismissed: false,
  asset: null,
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
    return merged;
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function getVisibleGroups() {
  const groups = state.lastQuotaData?.groups || [];
  const hidden = new Set(state.hiddenGroupIds || []);
  return groups.filter((g) => !hidden.has(g.id));
}

function getVisibleRingItems() {
  const items = state.lastQuotaData?.ringItems || [];
  const hidden = new Set(state.hiddenGroupIds || []);
  return items.filter((it) => !it.groupId || !hidden.has(it.groupId));
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

  if (allGroups.length === 0 || visibleGroups.length === 0) {
    return 108 + bannerExtra;
  }

  // Outer card padding (28) + header (22) + gap (10)
  let h = 60 + bannerExtra;
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

function createWidgetWindow() {
  const { width, height } = getTargetDimensions();
  const primaryDisplay = screen.getPrimaryDisplay();
  const workArea = primaryDisplay.workArea;

  const defaultX = workArea.x + workArea.width - width - 28;
  const defaultY = workArea.y + 40;

  widgetWindow = new BrowserWindow({
    width,
    height,
    minWidth: width,
    maxWidth: width,
    minHeight: height,
    maxHeight: height,
    useContentSize: true,
    x: typeof state.x === "number" ? state.x : defaultX,
    y: typeof state.y === "number" ? state.y : defaultY,
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

    updateState.status = "installing";
    updateState.progress = 100;
    sendStateToRenderer();
    updateTrayMenu();

    const result = installDownloadedUpdate(destPath);
    if (result && result.relaunching) {
      setTimeout(() => app.quit(), 400);
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

async function refreshQuota() {
  const prevCount = state.lastQuotaData?.groups?.length || 0;
  const live = await fetchLiveQuotaSummary();
  if (live) {
    state.lastQuotaData = live;
    if ((live.groups?.length || 0) !== prevCount) {
      measuredBentoHeight = null;
      applyWindowMode();
    }
    saveState();
  }
  sendStateToRenderer();
  updateTrayMenu();
}

function buildControlMenuTemplate() {
  const allGroups = state.lastQuotaData?.groups || [];
  const hiddenSet = new Set(state.hiddenGroupIds || []);
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
                : "Waiting for Antigravity live quota...",
            enabled: false,
          },
        ];

  const visibleModelsSubmenu =
    allGroups.length > 0
      ? [
          ...allGroups.map((g) => ({
            label: g.displayName,
            type: "checkbox",
            checked: !hiddenSet.has(g.id),
            click: () => toggleGroupVisibility(g.id),
          })),
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
    { label: "OrbitHUD — Antigravity Usage", enabled: false },
    { type: "separator" },
    ...summaryLines,
    { type: "separator" },
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
      click: () => refreshQuota(),
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
    tray.setToolTip("OrbitHUD — Antigravity Usage Widget");
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

ipcMain.handle("widget:refresh", async () => {
  await refreshQuota();
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
  refreshTimer = setInterval(refreshQuota, 20000);
  setTimeout(() => runUpdateCheck(false), 5000);
  updateCheckTimer = setInterval(
    () => runUpdateCheck(false),
    4 * 60 * 60 * 1000
  );
});

app.on("window-all-closed", (e) => {
  e.preventDefault();
});
