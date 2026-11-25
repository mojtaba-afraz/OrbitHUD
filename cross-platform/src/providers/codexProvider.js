"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const https = require("node:https");
const crypto = require("node:crypto");
const { formatResetDuration, formatWindowLabel } = require("../quotaFetcher");
const { utilizationToRemaining, makeProviderResult } = require("./types");

function parseCodexCredentialsJson(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const parsed = JSON.parse(raw.trim());
    const tokens = parsed?.tokens || parsed;
    const accessToken =
      tokens?.access_token ||
      tokens?.accessToken ||
      parsed?.OPENAI_ACCESS_TOKEN ||
      null;
    if (typeof accessToken !== "string" || !accessToken.trim()) return null;
    const accountId =
      tokens?.account_id || tokens?.accountId || parsed?.account_id || null;
    return {
      accessToken: accessToken.trim(),
      accountId: typeof accountId === "string" ? accountId.trim() : null,
    };
  } catch {
    return null;
  }
}

function discoverCodexCredentials(homeDir = os.homedir()) {
  const codexHome = process.env.CODEX_HOME || path.join(homeDir, ".codex");
  const candidates = [path.join(codexHome, "auth.json")];
  if (process.env.USERPROFILE && process.env.USERPROFILE !== homeDir) {
    candidates.push(path.join(process.env.USERPROFILE, ".codex", "auth.json"));
  }

  for (const filePath of candidates) {
    try {
      if (!fs.existsSync(filePath)) continue;
      const raw = fs.readFileSync(filePath, "utf8");
      const parsed = parseCodexCredentialsJson(raw);
      if (parsed) return parsed;
    } catch {
      // ignore
    }
  }
  return null;
}

function resolveCodexResetIso(win, nowMs) {
  if (!win || typeof win !== "object") return null;
  if (typeof win.reset_at === "number" && Number.isFinite(win.reset_at)) {
    const ms = win.reset_at > 1e12 ? win.reset_at : win.reset_at * 1000;
    return new Date(ms).toISOString();
  }
  if (typeof win.reset_at === "string" && win.reset_at.trim()) {
    return win.reset_at.trim();
  }
  if (typeof win.reset_after_seconds === "number" && Number.isFinite(win.reset_after_seconds)) {
    return new Date(nowMs + win.reset_after_seconds * 1000).toISOString();
  }
  return null;
}

function inferWindowName(win, fallback) {
  const sec = win?.limit_window_seconds || win?.window_seconds;
  if (typeof sec === "number") {
    if (sec <= 21_600) return "5h";
    if (sec <= 90_000) return "daily";
    return "weekly";
  }
  return fallback;
}

function buildCodexBucket(id, fallbackWindow, win, nowMs) {
  if (!win || typeof win !== "object") return null;
  const used =
    typeof win.used_percent === "number"
      ? win.used_percent
      : typeof win.usedPercent === "number"
      ? win.usedPercent
      : typeof win.utilization === "number"
      ? win.utilization
      : null;
  if (used === null || !Number.isFinite(used)) return null;

  const windowName = inferWindowName(win, fallbackWindow);
  const remainingFraction = utilizationToRemaining(used);
  const remainingPercentage = Math.round(remainingFraction * 100);
  const resetTime = resolveCodexResetIso(win, nowMs);
  const resetDuration = formatResetDuration(resetTime, nowMs);

  return {
    id,
    displayName: formatWindowLabel(windowName),
    window: windowName,
    windowLabel: formatWindowLabel(windowName),
    remainingFraction,
    remainingPercentage,
    resetTime,
    resetDuration,
  };
}

function parseCodexUsageResponse(rawJson, nowMs = Date.now()) {
  const data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson;
  if (!data || typeof data !== "object") return null;

  const rateLimit = data.rate_limit || data.rateLimit || data;
  const primaryWin = rateLimit.primary_window || rateLimit.primaryWindow || null;
  const secondaryWin = rateLimit.secondary_window || rateLimit.secondaryWindow || null;

  const buckets = [];
  const primary = buildCodexBucket("codex-5h", "5h", primaryWin, nowMs);
  const secondary = buildCodexBucket("codex-weekly", "weekly", secondaryWin, nowMs);
  if (primary) buckets.push(primary);
  if (secondary) buckets.push(secondary);

  if (buckets.length === 0) return null;

  const groupId = "codex::primary";
  const planSuffix =
    typeof data.plan_type === "string" && data.plan_type.trim()
      ? ` (${data.plan_type.trim()})`
      : "";

  const groups = [
    {
      id: groupId,
      providerId: "codex",
      displayName: `Codex CLI${planSuffix}`,
      description: "OpenAI Codex CLI usage",
      buckets,
    },
  ];

  const ringItems = buckets.map((bucket) => {
    const is5h = bucket.window === "5h";
    return {
      id: bucket.id,
      groupId,
      providerId: "codex",
      title: is5h ? "CDX 5h" : "CDX Wk",
      subtitle:
        bucket.remainingPercentage < 100 && bucket.resetDuration
          ? `↻ ${bucket.resetDuration}`
          : is5h
          ? "5h limit"
          : "Weekly",
      remainingFraction: bucket.remainingFraction,
      remainingPercentage: bucket.remainingPercentage,
      category: "codex",
    };
  });

  return { groups, ringItems };
}

function requestCodexUsage(accessToken, accountId) {
  return new Promise((resolve) => {
    const headers = {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
      "User-Agent": "codex-cli/1.0",
    };
    if (accountId) {
      headers["ChatGPT-Account-Id"] = accountId;
    }

    const req = https.request(
      {
        protocol: "https:",
        hostname: "chatgpt.com",
        path: "/backend-api/wham/usage",
        method: "GET",
        headers,
        timeout: 6000,
      },
      (res) => {
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => {
          resolve({
            statusCode: res.statusCode || 0,
            headers: res.headers || {},
            body,
          });
        });
      }
    );

    req.on("error", () => resolve({ statusCode: 0, headers: {}, body: "" }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ statusCode: 0, headers: {}, body: "" });
    });
    req.end();
  });
}

async function fetchCodexProvider() {
  const creds = discoverCodexCredentials();
  if (!creds) {
    return makeProviderResult("codex", {
      status: "auth_required",
      message: 'Not signed in — run "codex login"',
    });
  }

  const res = await requestCodexUsage(creds.accessToken, creds.accountId);
  if (res.statusCode === 401 || res.statusCode === 403) {
    return makeProviderResult("codex", {
      status: "auth_required",
      message: 'Session expired — run "codex login"',
      retryAfterMs: 120_000,
    });
  }

  if (res.statusCode === 429) {
    const retrySec = parseInt(res.headers["retry-after"] || "300", 10);
    return makeProviderResult("codex", {
      status: "rate_limited",
      message: "Rate limited — backing off automatically",
      retryAfterMs: Number.isFinite(retrySec) ? Math.max(retrySec * 1000, 180_000) : 300_000,
    });
  }

  if (res.statusCode < 200 || res.statusCode >= 300) {
    return makeProviderResult("codex", {
      status: "disconnected",
      message: "Codex usage endpoint unreachable",
    });
  }

  try {
    const parsed = parseCodexUsageResponse(res.body);
    if (!parsed) {
      return makeProviderResult("codex", {
        status: "disconnected",
        message: "No active Codex quota windows",
      });
    }
    return makeProviderResult("codex", {
      status: "connected",
      groups: parsed.groups,
      ringItems: parsed.ringItems,
    });
  } catch {
    return makeProviderResult("codex", {
      status: "disconnected",
      message: "Failed to parse Codex quota response",
    });
  }
}

function getCodexCredentialFingerprint(homeDir = os.homedir()) {
  const creds = discoverCodexCredentials(homeDir);
  if (!creds?.accessToken) return null;
  return crypto
    .createHash("sha256")
    .update(`codex:${creds.accountId || ""}:${creds.accessToken}`)
    .digest("hex")
    .slice(0, 24);
}

module.exports = {
  parseCodexCredentialsJson,
  discoverCodexCredentials,
  getCodexCredentialFingerprint,
  parseCodexUsageResponse,
  fetchCodexProvider,
};
