"use strict";

const { PROVIDER_META, PROVIDER_ORDER } = require("./types");
const { fetchAntigravityProvider } = require("./antigravityProvider");
const {
  fetchClaudeCodeProvider,
  getClaudeCredentialFingerprint,
} = require("./claudeCodeProvider");
const {
  fetchCodexProvider,
  getCodexCredentialFingerprint,
} = require("./codexProvider");

const FETCHERS = {
  antigravity: fetchAntigravityProvider,
  "claude-code": fetchClaudeCodeProvider,
  codex: fetchCodexProvider,
};

const FINGERPRINT_GETTERS = {
  "claude-code": getClaudeCredentialFingerprint,
  codex: getCodexCredentialFingerprint,
};

function mergeProviderResults(resultsById, enabledProviders, nowMs = Date.now()) {
  const orderedIds = PROVIDER_ORDER.filter((id) => enabledProviders.includes(id));
  const groups = [];
  const ringItems = [];
  const providerStatuses = {};

  for (const id of orderedIds) {
    const res = resultsById[id];
    if (!res) continue;
    providerStatuses[id] = {
      id,
      name: PROVIDER_META[id]?.name || id,
      shortName: PROVIDER_META[id]?.shortName || id,
      accentColor: PROVIDER_META[id]?.accentColor || "#3DDB94",
      status: res.status,
      message: res.message || null,
    };
    for (const g of res.groups || []) {
      groups.push(g);
    }
    for (const it of res.ringItems || []) {
      ringItems.push(it);
    }
  }

  return {
    timestamp: new Date(nowMs).toISOString(),
    groups,
    ringItems,
    providerStatuses,
  };
}

class ProviderManager {
  constructor(customFetchers = null, customFingerprintGetters = null) {
    this.fetchers = customFetchers || FETCHERS;
    this.fingerprintGetters = customFingerprintGetters || FINGERPRINT_GETTERS;
    this.cache = new Map(); // providerId -> { result, nextAllowedAt, credentialFingerprint }
  }

  async refresh(enabledProviders = ["antigravity"], options = {}) {
    const force = Boolean(options.force);
    const now = Date.now();
    const activeIds = PROVIDER_ORDER.filter((id) => enabledProviders.includes(id));

    await Promise.all(
      activeIds.map(async (id) => {
        const fetcher = this.fetchers[id];
        if (!fetcher) return;

        const cached = this.cache.get(id);
        const pollMs = PROVIDER_META[id]?.defaultPollMs || 60_000;
        const isLocal = Boolean(PROVIDER_META[id]?.isLocal);
        const fpGetter = this.fingerprintGetters[id];
        const currentFingerprint = typeof fpGetter === "function" ? fpGetter() : undefined;
        const credentialsChanged =
          Boolean(cached) &&
          currentFingerprint !== undefined &&
          cached.credentialFingerprint !== currentFingerprint;

        const recoveringLocal =
          isLocal &&
          cached &&
          (cached.result?.status === "auth_required" || cached.result?.status === "disconnected");

        if (!force && !credentialsChanged && !recoveringLocal && cached && now < cached.nextAllowedAt) {
          return;
        }

        const result = await fetcher({ forceRefresh: force || credentialsChanged || isLocal });
        const backoffMs =
          result.retryAfterMs && result.retryAfterMs > 0
            ? result.retryAfterMs
            : isLocal && (result.status === "auth_required" || result.status === "disconnected")
            ? 0
            : pollMs;

        // Preserve last known groups only if an external provider is temporarily rate-limited for the same account
        const mergedResult =
          result.status === "rate_limited" &&
          !credentialsChanged &&
          cached?.result?.groups?.length > 0
            ? {
                ...cached.result,
                status: "rate_limited",
                message: result.message,
                retryAfterMs: result.retryAfterMs,
              }
            : result;

        this.cache.set(id, {
          result: mergedResult,
          nextAllowedAt: Date.now() + backoffMs,
          credentialFingerprint: currentFingerprint,
        });
      })
    );

    const resultsById = {};
    for (const id of activeIds) {
      const entry = this.cache.get(id);
      if (entry?.result) {
        resultsById[id] = entry.result;
      }
    }

    return mergeProviderResults(resultsById, activeIds, Date.now());
  }
}

module.exports = {
  ProviderManager,
  mergeProviderResults,
};
