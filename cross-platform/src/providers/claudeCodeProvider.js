"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const https = require("node:https");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { formatResetDuration, formatWindowLabel } = require("../quotaFetcher");
const { utilizationToRemaining, makeProviderResult } = require("./types");

function parseClaudeCredentialsJson(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const parsed = JSON.parse(raw.trim());
    const oauth = parsed?.claudeAiOauth || parsed?.oauth || parsed;
    const accessToken =
      oauth?.accessToken || oauth?.access_token || parsed?.accessToken || null;
    if (typeof accessToken !== "string" || !accessToken.trim()) return null;
    const expiresAt = typeof oauth?.expiresAt === "number" ? oauth.expiresAt : null;
    return {
      accessToken: accessToken.trim(),
      expiresAt,
    };
  } catch {
    return null;
  }
}

function discoverClaudeCredentials(platform = process.platform, homeDir = os.homedir()) {
  if (platform === "darwin") {
    try {
      const secret = execFileSync(
        "/usr/bin/security",
        ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
        {
          encoding: "utf8",
          timeout: 3000,
          stdio: ["ignore", "pipe", "ignore"],
        }
      );
      const parsed = parseClaudeCredentialsJson(secret);
      if (parsed) return parsed;
    } catch {
      // Fallback to file
    }
  }

  const candidateFiles = [
    path.join(homeDir, ".claude", ".credentials.json"),
    path.join(homeDir, ".claude", "credentials.json"),
  ];
  if (process.env.USERPROFILE && process.env.USERPROFILE !== homeDir) {
    candidateFiles.push(path.join(process.env.USERPROFILE, ".claude", ".credentials.json"));
  }

  for (const filePath of candidateFiles) {
    try {
      if (!fs.existsSync(filePath)) continue;
      const raw = fs.readFileSync(filePath, "utf8");
      const parsed = parseClaudeCredentialsJson(raw);
      if (parsed) return parsed;
    } catch {
      // ignore
    }
  }

  return null;
}

function buildBucket(id, window, entry, nowMs) {
  if (!entry || typeof entry !== "object") return null;
  if (typeof entry.utilization !== "number" || !Number.isFinite(entry.utilization)) {
    return null;
  }
  const remainingFraction = utilizationToRemaining(entry.utilization);
  const remainingPercentage = Math.round(remainingFraction * 100);
  const resetTime = entry.resets_at || entry.resetsAt || null;
  const resetDuration = formatResetDuration(resetTime, nowMs);

  return {
    id,
    displayName: formatWindowLabel(window),
    window,
    windowLabel: formatWindowLabel(window),
    remainingFraction,
    remainingPercentage,
    resetTime,
    resetDuration,
  };
}

function parseClaudeUsageResponse(rawJson, nowMs = Date.now()) {
  const data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson;
  if (!data || typeof data !== "object") return null;

  const groups = [];
  const ringItems = [];

  const primaryBuckets = [];
  const fiveH = buildBucket("claude-code-5h", "5h", data.five_hour, nowMs);
  const weekly = buildBucket("claude-code-weekly", "weekly", data.seven_day, nowMs);
  if (fiveH) primaryBuckets.push(fiveH);
  if (weekly) primaryBuckets.push(weekly);

  if (primaryBuckets.length > 0) {
    const groupId = "claude-code::primary";
    groups.push({
      id: groupId,
      providerId: "claude-code",
      displayName: "Claude Code",
      description: "Anthropic Claude Code subscription usage",
      buckets: primaryBuckets,
    });

    for (const bucket of primaryBuckets) {
      const is5h = bucket.window === "5h";
      ringItems.push({
        id: bucket.id,
        groupId,
        providerId: "claude-code",
        title: is5h ? "CC 5h" : "CC Wk",
        subtitle:
          bucket.remainingPercentage < 100 && bucket.resetDuration
            ? `↻ ${bucket.resetDuration}`
            : is5h
            ? "5h limit"
            : "Weekly",
        remainingFraction: bucket.remainingFraction,
        remainingPercentage: bucket.remainingPercentage,
        category: "claude-code",
      });
    }
  }

  const sonnet = buildBucket("claude-code-sonnet-wk", "weekly", data.seven_day_sonnet, nowMs);
  if (sonnet) {
    const groupId = "claude-code::sonnet";
    groups.push({
      id: groupId,
      providerId: "claude-code",
      displayName: "Claude Sonnet",
      description: "Weekly Sonnet pool",
      buckets: [sonnet],
    });
    ringItems.push({
      id: sonnet.id,
      groupId,
      providerId: "claude-code",
      title: "CC Sonnet",
      subtitle:
        sonnet.remainingPercentage < 100 && sonnet.resetDuration
          ? `↻ ${sonnet.resetDuration}`
          : "Weekly",
      remainingFraction: sonnet.remainingFraction,
      remainingPercentage: sonnet.remainingPercentage,
      category: "claude-code",
    });
  }

  const opus = buildBucket("claude-code-opus-wk", "weekly", data.seven_day_opus, nowMs);
  if (opus) {
    const groupId = "claude-code::opus";
    groups.push({
      id: groupId,
      providerId: "claude-code",
      displayName: "Claude Opus",
      description: "Weekly Opus pool",
      buckets: [opus],
    });
    ringItems.push({
      id: opus.id,
      groupId,
      providerId: "claude-code",
      title: "CC Opus",
      subtitle:
        opus.remainingPercentage < 100 && opus.resetDuration
          ? `↻ ${opus.resetDuration}`
          : "Weekly",
      remainingFraction: opus.remainingFraction,
      remainingPercentage: opus.remainingPercentage,
      category: "claude-code",
    });
  }

  if (groups.length === 0) return null;
  return { groups, ringItems };
}

function requestClaudeUsage(accessToken) {
  return new Promise((resolve) => {
    const req = https.request(
      {
        protocol: "https:",
        hostname: "api.anthropic.com",
        path: "/api/oauth/usage",
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "anthropic-beta": "oauth-2025-04-20",
          "User-Agent": "claude-code/2.0.0",
          Accept: "application/json",
          "Content-Type": "application/json",
        },
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

async function fetchClaudeCodeProvider() {
  const creds = discoverClaudeCredentials();
  if (!creds) {
    return makeProviderResult("claude-code", {
      status: "auth_required",
      message: 'Not signed in — run "claude /login"',
    });
  }

  const res = await requestClaudeUsage(creds.accessToken);
  if (res.statusCode === 401 || res.statusCode === 403) {
    return makeProviderResult("claude-code", {
      status: "auth_required",
      message: 'Session expired — run "claude /login"',
      retryAfterMs: 120_000,
    });
  }

  if (res.statusCode === 429) {
    const retrySec = parseInt(res.headers["retry-after"] || "300", 10);
    return makeProviderResult("claude-code", {
      status: "rate_limited",
      message: "Rate limited — backing off automatically",
      retryAfterMs: Number.isFinite(retrySec) ? Math.max(retrySec * 1000, 180_000) : 300_000,
    });
  }

  if (res.statusCode < 200 || res.statusCode >= 300) {
    return makeProviderResult("claude-code", {
      status: "disconnected",
      message: "Claude Code usage endpoint unreachable",
    });
  }

  try {
    const parsed = parseClaudeUsageResponse(res.body);
    if (!parsed) {
      return makeProviderResult("claude-code", {
        status: "disconnected",
        message: "No active Claude Code quota windows",
      });
    }
    return makeProviderResult("claude-code", {
      status: "connected",
      groups: parsed.groups,
      ringItems: parsed.ringItems,
    });
  } catch {
    return makeProviderResult("claude-code", {
      status: "disconnected",
      message: "Failed to parse Claude Code quota response",
    });
  }
}

function getClaudeCredentialFingerprint(platform = process.platform, homeDir = os.homedir()) {
  const creds = discoverClaudeCredentials(platform, homeDir);
  if (!creds?.accessToken) return null;
  return crypto
    .createHash("sha256")
    .update(`claude:${creds.accessToken}`)
    .digest("hex")
    .slice(0, 24);
}

module.exports = {
  parseClaudeCredentialsJson,
  discoverClaudeCredentials,
  getClaudeCredentialFingerprint,
  parseClaudeUsageResponse,
  fetchClaudeCodeProvider,
};
