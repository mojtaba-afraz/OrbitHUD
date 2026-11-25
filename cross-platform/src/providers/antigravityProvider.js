"use strict";

const { fetchLiveQuotaStatus } = require("../quotaFetcher");
const { makeProviderResult } = require("./types");

async function fetchAntigravityProvider(options = {}) {
  const forceRefresh = options.forceRefresh !== false;
  const live = await fetchLiveQuotaStatus(forceRefresh);

  if (live?.status === "auth_required") {
    return makeProviderResult("antigravity", {
      status: "auth_required",
      message: live.message || "Not signed in to Antigravity",
    });
  }

  if (!live || live.status !== "connected" || !Array.isArray(live.groups) || live.groups.length === 0) {
    return makeProviderResult("antigravity", {
      status: "disconnected",
      message: live?.message || "Waiting for Antigravity live quota...",
    });
  }

  const groups = live.groups.map((g) => ({
    ...g,
    providerId: "antigravity",
  }));

  const ringItems = (live.ringItems || []).map((it) => ({
    ...it,
    providerId: "antigravity",
  }));

  return makeProviderResult("antigravity", {
    status: "connected",
    groups,
    ringItems,
  });
}

module.exports = {
  fetchAntigravityProvider,
};
