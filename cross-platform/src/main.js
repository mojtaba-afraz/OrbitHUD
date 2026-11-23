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
  compact: false, // false = 1x4 Wide (356x156), true = 2x2 Square (210x225)
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

function createWidgetWindow() {
  const { width, height } = getTargetDimensions();
  const primaryDisplay = screen.getPrimaryDisplay();
  const workArea = primaryDisplay.workArea;

  const defaultX = workArea.x + workArea.width - width - 28;
  const defaultY = workArea.y + 40;

  widgetWindow = new BrowserWindow({
    width,
    height,
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
  const [curW, curH] = widgetWindow.getSize();
  if (curW !== width || curH !== height) {
    const [curX, curY] = widgetWindow.getPosition();
    const newX = curX + (curW - width);
    widgetWindow.setBounds({ x: newX, y: curY, width, height }, true);
  }

  widgetWindow.setOpacity(state.opacity);
  widgetWindow.setMovable(!state.locked);
  widgetWindow.setSkipTaskbar(true);

  if (state.mode === "floating") {
    // Always-on-top Floating HUD across Windows, Linux, and macOS
    widgetWindow.setAlwaysOnTop(true, "floating");
    widgetWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  } else {
    // Desktop Pinned Widget mode (sits on desktop behind normal windows)
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

function createTrayIcon() {
  // Official OrbitHUD SVG logo (dual orbital rings + center sparkle core)
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="64 64 384 384" width="16" height="16">
    <circle cx="256" cy="256" r="144" fill="none" stroke="#3DDB94" stroke-width="36" stroke-linecap="round" stroke-dasharray="700 905" transform="rotate(-90 256 256)" />
    <circle cx="256" cy="256" r="96" fill="none" stroke="#38BDF8" stroke-width="28" stroke-linecap="round" stroke-dasharray="420 603" transform="rotate(-45 256 256)" />
    <path d="M256 190 C262 232, 280 250, 322 256 C280 262, 262 280, 256 322 C250 280, 232 262, 190 256 C232 250, 250 232, 256 190 Z" fill="#FFFFFF" />
  </svg>`;
  const img = nativeImage.createFromDataURL(
    `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`
  );
  tray = new Tray(img);
  tray.setToolTip("OrbitHUD — Antigravity Usage Widget");
  updateTrayMenu();
}

function updateTrayMenu() {
  if (!tray) return;
  const items = state.lastQuotaData?.ringItems || [];
  const summaryLines =
    items.length > 0
      ? items.map((it) => ({
          label: `${it.title}: ${it.remainingPercentage}% (${it.subtitle})`,
          enabled: false,
        }))
      : [{ label: "Syncing with Antigravity...", enabled: false }];

  const menu = Menu.buildFromTemplate([
    { label: "Antigravity Usage Widget", enabled: false },
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
      label: "Square 2×2 iOS Layout",
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
      label: "Refresh Now",
      click: () => refreshQuota(),
    },
    { type: "separator" },
    {
      label: "Quit",
      click: () => app.quit(),
    },
  ]);

  tray.setContextMenu(menu);
}

// IPC handlers for renderer controls & cross-platform smooth dragging
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

ipcMain.on("widget:move-by", (_event, { dx, dy }) => {
  if (!widgetWindow || widgetWindow.isDestroyed() || state.locked) return;
  const [x, y] = widgetWindow.getPosition();
  widgetWindow.setPosition(Math.round(x + dx), Math.round(y + dy));
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
