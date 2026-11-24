"use strict";

const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  ipcMain,
  screen,
  nativeImage,
} = require("electron");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");
const { fetchLiveQuotaSummary } = require("./quotaFetcher");

let widgetWindow = null;
let tray = null;
let refreshTimer = null;

const STATE_PATH = path.join(
  os.homedir(),
  ".gemini",
  "antigravity-usage-widget",
  "widget_state.json"
);

const DEFAULT_STATE = {
  mode: "floating", // "floating" | "desktop"
  compact: false, // false = Bento Glass (356x280), true = Compact Pill (356x68)
  locked: false,
  opacity: 0.96,
  x: null,
  y: null,
  lastQuotaData: null,
};

let state = loadState();

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_PATH, "utf8");
    return { ...DEFAULT_STATE, ...JSON.parse(raw) };
  } catch {
    return { ...DEFAULT_STATE };
  }
}

function saveState() {
  try {
    fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
    fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2), "utf8");
  } catch {
    // ignore
  }
}

function getTargetDimensions() {
  return state.compact
    ? { width: 356, height: 68 }
    : { width: 356, height: 280 };
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
    hasShadow: true,
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
    quotaData: state.lastQuotaData,
  });
}

async function refreshQuota() {
  const live = await fetchLiveQuotaSummary();
  if (live) {
    state.lastQuotaData = live;
    saveState();
  }
  sendStateToRenderer();
  updateTrayMenu();
}

function buildControlMenuTemplate() {
  const items = state.lastQuotaData?.ringItems || [];
  const summaryLines =
    items.length > 0
      ? items.map((it) => ({
          label: `${it.title}: ${it.remainingPercentage}% (${it.subtitle})`,
          enabled: false,
        }))
      : [{ label: "Waiting for Antigravity live quota...", enabled: false }];

  return [
    { label: "OrbitHUD — Antigravity Usage", enabled: false },
    { type: "separator" },
    ...summaryLines,
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
  saveState();
  applyWindowMode();
  sendStateToRenderer();
  return state;
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

app.whenReady().then(() => {
  if (process.platform === "darwin" && app.dock) {
    app.dock.hide();
  }
  createTrayIcon();
  createWidgetWindow();
  refreshTimer = setInterval(refreshQuota, 30000);
});

app.on("window-all-closed", (e) => {
  e.preventDefault();
});
