"use strict";

const modeBtn = document.getElementById("mode-btn");
const modeBtnText = document.getElementById("mode-btn-text");
const modeBadge = document.getElementById("mode-badge");
const layoutBtn = document.getElementById("layout-btn");
const refreshBtn = document.getElementById("refresh-btn");
const menuBtn = document.getElementById("menu-btn");
const quitBtn = document.getElementById("quit-btn");
const updateBanner = document.getElementById("update-banner");
const bentoContainer = document.getElementById("bento-container");
const widgetCard = document.getElementById("widget-card");
let latestUpdateState = null;

function semanticColor(fraction) {
  if (fraction <= 0.15) return "#FF5252";
  if (fraction <= 0.4) return "#FAB838";
  return "#3DDB94";
}

function renderCircularGauge(fraction, size = 46, strokeWidth = 4.5, showText = true) {
  const clamped = Math.min(Math.max(fraction, 0.02), 1.0);
  const pct = Math.round(fraction * 100);
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference * (1 - clamped);
  const color = semanticColor(fraction);

  return `
    <div class="gauge-wrap" style="width:${size}px;height:${size}px">
      <svg class="gauge-svg" viewBox="0 0 ${size} ${size}">
        <circle
          cx="${size / 2}"
          cy="${size / 2}"
          r="${radius}"
          fill="none"
          stroke="rgba(255,255,255,0.12)"
          stroke-width="${strokeWidth}"
        />
        <circle
          cx="${size / 2}"
          cy="${size / 2}"
          r="${radius}"
          fill="none"
          stroke="${color}"
          stroke-width="${strokeWidth}"
          stroke-linecap="round"
          stroke-dasharray="${circumference.toFixed(2)}"
          stroke-dashoffset="${offset.toFixed(2)}"
        />
      </svg>
      ${showText ? `<div class="gauge-pct">${pct}<small>%</small></div>` : ""}
    </div>
  `;
}

function renderDualWindowBentoCard(group) {
  if (!group || !group.buckets || group.buckets.length === 0) return "";
  const fiveH = group.buckets.find((b) => b.window === "5h") || group.buckets[0];
  const weekly = group.buckets.find((b) => b.window === "weekly");
  const fiveHColor = semanticColor(fiveH.remainingFraction);

  return `
    <div class="bento-card bento-hero">
      ${renderCircularGauge(fiveH.remainingFraction, 46, 4.5, true)}
      <div class="hero-details">
        <div class="hero-top-row">
          <span class="hero-title">${group.displayName}</span>
          <span class="hero-meta" style="color:${fiveHColor};font-weight:600">${
            fiveH.remainingPercentage < 100
              ? `5h: ${fiveH.remainingPercentage}% · ${fiveH.resetDuration || "soon"}`
              : "5h: 100% left"
          }</span>
        </div>
        ${
          weekly
            ? `
          <div>
            <div class="weekly-row">
              <span class="weekly-label">Weekly limit</span>
              <span class="weekly-val">${
                weekly.remainingPercentage < 100
                  ? `${weekly.remainingPercentage}% left · ${weekly.resetDuration || ""}`
                  : "100% left"
              }</span>
            </div>
            <div class="glass-bar-track">
              <div class="glass-bar-fill" style="width:${Math.max(
                weekly.remainingPercentage,
                4
              )}%;background:${semanticColor(weekly.remainingFraction)}"></div>
            </div>
          </div>
        `
            : ""
        }
      </div>
    </div>
  `;
}

function renderSingleWindowBentoCard(group) {
  if (!group || !group.buckets || group.buckets.length === 0) return "";
  const b = group.buckets[0];
  const color = semanticColor(b.remainingFraction);
  const sub =
    b.remainingPercentage < 100 && b.resetDuration
      ? `Weekly limit · Resets in ${b.resetDuration}`
      : "Weekly limit · Full";

  return `
    <div class="bento-card bento-hero">
      ${renderCircularGauge(b.remainingFraction, 42, 4.2, true)}
      <div class="hero-details">
        <div class="hero-top-row">
          <span class="hero-title">${group.displayName}</span>
          <span class="tile-pct" style="color:${color}">${b.remainingPercentage}% left</span>
        </div>
        <div class="glass-bar-track">
          <div class="glass-bar-fill" style="width:${Math.max(
            b.remainingPercentage,
            4
          )}%;background:${color}"></div>
        </div>
        <div class="tile-sub" style="margin-top:2px">${sub}</div>
      </div>
    </div>
  `;
}

function renderUpdateBanner(update) {
  if (!updateBanner) return;
  if (
    !update ||
    update.dismissed ||
    (update.status !== "available" &&
      update.status !== "downloading" &&
      update.status !== "installing" &&
      update.status !== "error")
  ) {
    updateBanner.classList.add("hidden");
    updateBanner.innerHTML = "";
    return;
  }

  updateBanner.classList.remove("hidden");

  if (update.status === "available") {
    updateBanner.innerHTML = `
      <div class="update-info">
        <span class="update-text">Update v${update.latestVersion} available</span>
      </div>
      <div class="update-actions">
        <button id="banner-update-btn" class="update-action-btn">Update</button>
        <button id="banner-dismiss-btn" class="update-dismiss-btn" title="Dismiss">✕</button>
      </div>
    `;
    const btn = document.getElementById("banner-update-btn");
    if (btn) {
      btn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.startUpdate();
      });
    }
    const dismissBtn = document.getElementById("banner-dismiss-btn");
    if (dismissBtn) {
      dismissBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.dismissUpdate();
      });
    }
  } else if (update.status === "downloading") {
    const pct = Math.min(Math.max(update.progress || 0, 0), 100);
    updateBanner.innerHTML = `
      <div class="update-info">
        <span class="update-text">Downloading v${update.latestVersion || ""}... ${pct}%</span>
        <div class="update-progress-track">
          <div class="update-progress-fill" style="width:${pct}%"></div>
        </div>
      </div>
    `;
  } else if (update.status === "installing") {
    updateBanner.innerHTML = `
      <div class="update-info">
        <span class="update-text">Installing update & restarting...</span>
        <div class="update-progress-track">
          <div class="update-progress-fill" style="width:100%"></div>
        </div>
      </div>
    `;
  } else if (update.status === "error") {
    updateBanner.innerHTML = `
      <div class="update-info">
        <span class="update-text">Update error — try again</span>
      </div>
      <div class="update-actions">
        <button id="banner-retry-btn" class="update-action-btn">Retry</button>
        <button id="banner-dismiss-btn" class="update-dismiss-btn" title="Dismiss">✕</button>
      </div>
    `;
    const retryBtn = document.getElementById("banner-retry-btn");
    if (retryBtn) {
      retryBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.checkUpdate();
      });
    }
    const dismissBtn = document.getElementById("banner-dismiss-btn");
    if (dismissBtn) {
      dismissBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.dismissUpdate();
      });
    }
  }
}

function renderWidget(quotaData, isCompact) {
  widgetCard.classList.toggle("compact-mode", Boolean(isCompact));

  const groups = quotaData?.groups || [];
  const ringItems = quotaData?.ringItems || [];

  if (groups.length === 0) {
    if (isCompact) {
      bentoContainer.innerHTML = `
        <div class="pill-row" style="justify-content:space-between;padding:4px 6px">
          <span style="font-size:11px;color:rgba(255,255,255,0.65)">Waiting for Antigravity...</span>
          <div style="display:flex;gap:4px">
            <button id="expand-pill-btn" class="glass-icon-btn" title="Expand Bento View">⤢</button>
            <button id="pill-menu-btn" class="glass-icon-btn" title="Settings & Controls">⚙</button>
          </div>
        </div>
      `;
      const expandBtn = document.getElementById("expand-pill-btn");
      if (expandBtn) {
        expandBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          window.antigravityWidget.toggleCompact();
        });
      }
      const pillMenuBtn = document.getElementById("pill-menu-btn");
      if (pillMenuBtn) {
        pillMenuBtn.addEventListener("click", (e) => {
          e.stopPropagation();
          window.antigravityWidget.showMenu();
        });
      }
      return;
    }
    bentoContainer.innerHTML = `
      <div class="bento-card empty-card">
        <span>Waiting for Antigravity live quota...</span>
      </div>
    `;
    return;
  }

  if (isCompact) {
    bentoContainer.innerHTML = `
      <div class="pill-row">
        ${ringItems
          .slice(0, 5)
          .map((item) => {
            const shortName =
              item.title === "Gemini 5h"
                ? "Gem 5h"
                : item.title === "Gemini Wk"
                ? "Gem Wk"
                : item.title === "Claude 5h"
                ? "Cld 5h"
                : item.title === "Claude Wk"
                ? "Cld Wk"
                : item.title === "Argon 4"
                ? "Argon"
                : item.title;
            return `
              <div class="pill-item">
                ${renderCircularGauge(item.remainingFraction, 24, 2.8, false)}
                <div>
                  <div class="pill-pct">${item.remainingPercentage}%</div>
                  <div class="pill-name">${shortName}</div>
                </div>
              </div>
            `;
          })
          .join("")}
        ${
          latestUpdateState &&
          latestUpdateState.status === "available" &&
          !latestUpdateState.dismissed
            ? `<button id="pill-update-btn" class="glass-icon-btn update-pill-btn" title="Install Update v${latestUpdateState.latestVersion}">↑</button>`
            : ""
        }
        <button id="expand-pill-btn" class="glass-icon-btn" title="Expand Bento View">⤢</button>
        <button id="pill-menu-btn" class="glass-icon-btn" title="Settings & Controls">⚙</button>
      </div>
    `;
    const pillUpdateBtn = document.getElementById("pill-update-btn");
    if (pillUpdateBtn) {
      pillUpdateBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.startUpdate();
      });
    }
    const expandBtn = document.getElementById("expand-pill-btn");
    if (expandBtn) {
      expandBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.toggleCompact();
      });
    }
    const pillMenuBtn = document.getElementById("pill-menu-btn");
    if (pillMenuBtn) {
      pillMenuBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        window.antigravityWidget.showMenu();
      });
    }
    return;
  }

  const geminiGroup =
    groups.find(
      (g) =>
        g.displayName.toLowerCase().includes("gemini") &&
        !g.displayName.toLowerCase().includes("argon")
    ) || groups[0];
  const claudeGroup = groups.find(
    (g) =>
      g.displayName.toLowerCase().includes("claude") ||
      g.displayName.toLowerCase().includes("gpt")
  );
  const argonGroup = groups.find((g) =>
    g.displayName.toLowerCase().includes("argon")
  );

  bentoContainer.innerHTML = `
    ${renderDualWindowBentoCard(geminiGroup)}
    ${renderDualWindowBentoCard(claudeGroup)}
    ${renderSingleWindowBentoCard(argonGroup)}
  `;
}

window.antigravityWidget.onStateUpdate((state) => {
  const isFloating = state.mode === "floating";
  modeBadge.textContent = isFloating ? "Float" : "Desktop";
  modeBtnText.textContent = isFloating ? "Pin Desktop" : "Float Top";
  widgetCard.classList.toggle("locked", Boolean(state.locked));
  latestUpdateState = state.update || null;
  renderUpdateBanner(latestUpdateState);
  renderWidget(state.quotaData, state.compact);
});

modeBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  window.antigravityWidget.toggleMode();
});

layoutBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  window.antigravityWidget.toggleCompact();
});

refreshBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  window.antigravityWidget.refresh();
});

if (menuBtn) {
  menuBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    window.antigravityWidget.showMenu();
  });
}

if (quitBtn) {
  quitBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    window.antigravityWidget.quit();
  });
}

// Right-click anywhere on the widget opens the full OrbitHUD control menu (Windows / Linux / macOS)
window.addEventListener("contextmenu", (e) => {
  e.preventDefault();
  window.antigravityWidget.showMenu();
});
