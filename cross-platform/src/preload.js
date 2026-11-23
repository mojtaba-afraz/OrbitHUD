"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("antigravityWidget", {
  onStateUpdate: (callback) => {
    ipcRenderer.on("widget:state", (_event, data) => callback(data));
  },
  toggleMode: () => ipcRenderer.invoke("widget:toggle-mode"),
  toggleCompact: () => ipcRenderer.invoke("widget:toggle-compact"),
  refresh: () => ipcRenderer.invoke("widget:refresh"),
  showMenu: () => ipcRenderer.send("widget:show-menu"),
  quit: () => ipcRenderer.send("widget:quit"),
  moveBy: (dx, dy) => ipcRenderer.send("widget:move-by", { dx, dy }),
});
