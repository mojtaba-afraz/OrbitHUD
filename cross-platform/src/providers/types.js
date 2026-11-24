"use strict";

const PROVIDER_META = {
  antigravity: {
    id: "antigravity",
    name: "Antigravity",
    shortName: "AGY",
    accentColor: "#3DDB94",
    defaultPollMs: 20_000,
    isLocal: true,
  },
  "claude-code": {
    id: "claude-code",
    name: "Claude Code",
    shortName: "CC",
    accentColor: "#E8926B",
    defaultPollMs: 90_000,
    isLocal: false,
  },
  codex: {
    id: "codex",
    name: "Codex CLI",
    shortName: "CDX",
    accentColor: "#38BDF8",
    defaultPollMs: 90_000,
    isLocal: false,
  },
};

const PROVIDER_ORDER = ["antigravity", "claude-code", "codex"];

function clampFraction(val) {
  if (typeof val !== "number" || !Number.isFinite(val)) return 1.0;
  return Math.min(Math.max(val, 0.0), 1.0);
}

function utilizationToRemaining(utilization) {
  if (typeof utilization !== "number" || !Number.isFinite(utilization)) return 1.0;
  // Handle both 0..100 (standard API) and 0..1 fractional inputs safely
  const usedFraction = utilization > 1.0 ? utilization / 100.0 : utilization;
  return clampFraction(1.0 - usedFraction);
}

function makeProviderResult(providerId, partial = {}) {
  return {
    providerId,
    status: partial.status || "disconnected", // "connected" | "auth_required" | "rate_limited" | "disconnected"
    message: partial.message || null,
    groups: Array.isArray(partial.groups) ? partial.groups : [],
    ringItems: Array.isArray(partial.ringItems) ? partial.ringItems : [],
    retryAfterMs: typeof partial.retryAfterMs === "number" ? partial.retryAfterMs : 0,
    fetchedAt: partial.fetchedAt || Date.now(),
  };
}

module.exports = {
  PROVIDER_META,
  PROVIDER_ORDER,
  clampFraction,
  utilizationToRemaining,
  makeProviderResult,
};
