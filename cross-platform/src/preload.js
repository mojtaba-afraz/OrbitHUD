"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("antigravityWidget", {
  onStateUpdate: (callback) => {
    ipcRenderer.on("widget:state", (_event, data) => callback(data));
  },
  toggleMode: () => ipcRenderer.invoke("widget:toggle-mode"),
  toggleCompact: () => ipcRenderer.invoke("widget:toggle-compact"),
  toggleGroupVisibility: (groupId) =>
    ipcRenderer.invoke("widget:toggle-group-visibility", groupId),
  showAllGroups: () => ipcRenderer.invoke("widget:show-all-groups"),
  syncHeight: (cardHeight) => ipcRenderer.send("widget:sync-height", cardHeight),
  refresh: () => ipcRenderer.invoke("widget:refresh"),
  showMenu: () => ipcRenderer.send("widget:show-menu"),
  quit: () => ipcRenderer.send("widget:quit"),
  checkUpdate: () => ipcRenderer.invoke("widget:check-update"),
  startUpdate: () => ipcRenderer.send("widget:start-update"),
  dismissUpdate: () => ipcRenderer.send("widget:dismiss-update"),
});
