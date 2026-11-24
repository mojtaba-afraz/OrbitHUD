"use strict";

const { fetchLiveQuotaSummary } = require("../quotaFetcher");
const { makeProviderResult } = require("./types");

async function fetchAntigravityProvider(options = {}) {
  const forceRefresh = options.forceRefresh !== false;
  const live = await fetchLiveQuotaSummary(forceRefresh);
  if (!live || !Array.isArray(live.groups) || live.groups.length === 0) {
    return makeProviderResult("antigravity", {
      status: "disconnected",
      message: "Waiting for Antigravity live quota...",
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
