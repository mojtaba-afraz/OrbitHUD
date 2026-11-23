"use strict";

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");
const https = require("node:https");
const { execFileSync } = require("node:child_process");

const PORT_PATTERNS = [
  /ANTIGRAVITY_LS_ADDRESS=(?:https?:\/\/)?(?:localhost|127\.0\.0\.1):(\d+)/gi,
  /--hub-port=(\d+)/gi,
  /--hub-port\s+(\d+)/gi,
  /--https_server_port=(\d+)/gi,
  /--https_server_port\s+(\d+)/gi,
];

const TOKEN_PATTERNS = [
  /ANTIGRAVITY_SERVER_CSRF_TOKEN=([A-Za-z0-9_-]+)/gi,
  /ANTIGRAVITY_CSRF_TOKEN=([A-Za-z0-9_-]+)/gi,
  /--csrf_token=([A-Za-z0-9_-]+)/gi,
  /--csrf_token\s+([A-Za-z0-9_-]+)/gi,
];

function getCacheFilePath() {
  const dir = path.join(os.homedir(), ".gemini", "antigravity-usage-widget");
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  return path.join(dir, "ls_connection.json");
}

function saveCachedConnection(conn) {
  try {
    fs.writeFileSync(getCacheFilePath(), JSON.stringify(conn, null, 2), "utf8");
  } catch {
    // ignore
  }
}

function loadCachedConnection() {
  try {
    const raw = fs.readFileSync(getCacheFilePath(), "utf8");
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed.port === "number" && typeof parsed.csrfToken === "string") {
      return parsed;
    }
  } catch {
    // ignore
  }
  return null;
}

/**
 * Extracts all `{ port, csrfToken }` combinations from process command line / environment strings.
 * Works across macOS (`ps auxeww`), Linux (`/proc/<pid>/cmdline` + `/proc/<pid>/environ`), and Windows.
 */
function parseConnectionsFromText(text) {
  if (!text || typeof text !== "string") {
    return [];
  }

  const allPorts = [];
  const allTokens = [];
  const paired = [];
  const seenKey = new Set();

  const addPair = (port, csrfToken) => {
    const key = `${port}:${csrfToken}`;
    if (!seenKey.has(key)) {
      seenKey.add(key);
      paired.push({ port, csrfToken });
    }
  };

  for (const line of text.split(/\r?\n/)) {
    if (
      !line.includes("ANTIGRAVITY") &&
      !line.includes("agy") &&
      !line.includes("language_server") &&
      !line.includes("csrf_token") &&
      !line.includes("hub-port")
    ) {
      continue;
    }

    const linePorts = [];
    const lineTokens = [];

    for (const regex of PORT_PATTERNS) {
      regex.lastIndex = 0;
      let m;
      while ((m = regex.exec(line)) !== null) {
        const p = parseInt(m[1], 10);
        if (p > 1024) {
          if (!linePorts.includes(p)) linePorts.push(p);
          if (!allPorts.includes(p)) allPorts.push(p);
        }
      }
    }

    for (const regex of TOKEN_PATTERNS) {
      regex.lastIndex = 0;
      let m;
      while ((m = regex.exec(line)) !== null) {
        const tok = m[1];
        if (tok && tok !== "REDACTED") {
          if (!lineTokens.includes(tok)) lineTokens.push(tok);
          if (!allTokens.includes(tok)) allTokens.push(tok);
        }
      }
    }

    for (const p of linePorts) {
      for (const t of lineTokens) {
        addPair(p, t);
      }
    }
  }

  for (const p of allPorts) {
    for (const t of allTokens) {
      addPair(p, t);
    }
  }

  return paired;
}

/**
 * Linux discovery: reads `/proc/<pid>/cmdline` and `/proc/<pid>/environ` directly for zero-overhead discovery,
 * with fallback to `ps auxeww`.
 */
function discoverOnLinux() {
  const lines = [];
  try {
    const entries = fs.readdirSync("/proc");
    for (const entry of entries) {
      if (!/^\d+$/.test(entry)) continue;
      try {
        const cmdline = fs
          .readFileSync(`/proc/${entry}/cmdline`, "utf8")
          .replace(/\0/g, " ");
        if (
          !cmdline.includes("agy") &&
          !cmdline.includes("language_server") &&
          !cmdline.includes("antigravity")
        ) {
          continue;
        }
        let environ = "";
        try {
          environ = fs
            .readFileSync(`/proc/${entry}/environ`, "utf8")
            .replace(/\0/g, " ");
        } catch {
          // ignore permission errors on other users' processes
        }
        lines.push(`${cmdline} ${environ}`);
      } catch {
        // process exited or inaccessible
      }
    }
  } catch {
    // /proc not mounted
  }

  try {
    const psOut = execFileSync("/bin/ps", ["auxeww"], {
      encoding: "utf8",
      timeout: 3000,
      maxBuffer: 16 * 1024 * 1024,
    });
    lines.push(psOut);
  } catch {
    // ignore
  }

  return parseConnectionsFromText(lines.join("\n"));
}

/**
 * macOS discovery: runs `/bin/ps auxeww` and `/bin/ps efww`.
 */
function discoverOnMacOS() {
  const chunks = [];
  for (const args of [["auxeww"], ["efww"]]) {
    try {
      const out = execFileSync("/bin/ps", args, {
        encoding: "utf8",
        timeout: 3000,
        maxBuffer: 16 * 1024 * 1024,
      });
      chunks.push(out);
    } catch {
      // ignore
    }
  }
  return parseConnectionsFromText(chunks.join("\n"));
}

/**
 * Windows discovery: queries Win32_Process via PowerShell for `agy.exe` / `language_server.exe` command lines
 * and environment blocks.
 */
function discoverOnWindows() {
  const chunks = [];
  try {
    const psScript = [
      "Get-CimInstance Win32_Process |",
      "Where-Object { $_.Name -match 'agy|language_server|antigravity|node|electron' } |",
      "ForEach-Object { $_.CommandLine }",
    ].join(" ");
    const out = execFileSync(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", psScript],
      {
        encoding: "utf8",
        timeout: 4000,
        maxBuffer: 16 * 1024 * 1024,
        windowsHide: true,
      }
    );
    chunks.push(out);
  } catch {
    // ignore
  }
  return parseConnectionsFromText(chunks.join("\n"));
}

function discoverConnections(platform = process.platform) {
  const candidates = [];
  const seen = new Set();
  const pushUnique = (conn) => {
    if (!conn || !conn.port || !conn.csrfToken) return;
    const key = `${conn.port}:${conn.csrfToken}`;
    if (!seen.has(key)) {
      seen.add(key);
      candidates.push(conn);
    }
  };

  // 1. Check current environment variables
  const addr = process.env.ANTIGRAVITY_LS_ADDRESS;
  const token =
    process.env.ANTIGRAVITY_CSRF_TOKEN || process.env.ANTIGRAVITY_SERVER_CSRF_TOKEN;
  if (addr && token) {
    const portMatch = /:(\d+)$/.exec(addr.trim());
    if (portMatch) {
      pushUnique({ port: parseInt(portMatch[1], 10), csrfToken: token.trim() });
    }
  }

  // 2. Check cached connection on disk
  const cached = loadCachedConnection();
  if (cached) {
    pushUnique(cached);
  }

  // 3. OS-specific live process discovery
  let osConns = [];
  if (platform === "linux") {
    osConns = discoverOnLinux();
  } else if (platform === "win32") {
    osConns = discoverOnWindows();
  } else {
    osConns = discoverOnMacOS();
  }

  for (const c of osConns) {
    pushUnique(c);
  }

  return candidates;
}

/**
 * Formats reset duration identically to Antigravity: "6d 1h", "3h 10m", "6d 22h".
 */
function formatResetDuration(resetTimeISO, nowMs = Date.now()) {
  if (!resetTimeISO) return null;
  const resetMs = Date.parse(resetTimeISO);
  if (Number.isNaN(resetMs)) return null;
  const totalSeconds = Math.floor((resetMs - nowMs) / 1000);
  if (totalSeconds <= 0) return "soon";

  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);

  if (days > 0) {
    return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
  }
  if (hours > 0) {
    return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  }
  return `${Math.max(minutes, 1)}m`;
}

/**
 * Parses the JSON response from `/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`
 * and maps it to both full `groups` and the 4 iOS Battery-Widget style `ringItems`.
 */
function parseQuotaSummaryResponse(rawJson, nowMs = Date.now()) {
  const root = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson;
  if (!root || typeof root !== "object") return null;

  const responseObj = root.response || root;
  const rawGroups = Array.isArray(responseObj.groups) ? responseObj.groups : [];
  if (rawGroups.length === 0) return null;

  const groups = [];
  for (let i = 0; i < rawGroups.length; i++) {
    const g = rawGroups[i];
    const displayName = g.displayName || g.display_name || `Group ${i + 1}`;
    const rawBuckets = Array.isArray(g.buckets) ? g.buckets : [];
    const buckets = [];

    for (let j = 0; j < rawBuckets.length; j++) {
      const b = rawBuckets[j];
      const id = b.bucketId || b.bucket_id || `${displayName}-${j}`;
      const window = (b.window || "").toLowerCase();
      let remainingFraction = 1.0;
      if (typeof b.remainingFraction === "number") {
        remainingFraction = b.remainingFraction;
      } else if (typeof b.remaining_fraction === "number") {
        remainingFraction = b.remaining_fraction;
      } else if (b.disabled === true) {
        remainingFraction = 0.0;
      }
      remainingFraction = Math.min(Math.max(remainingFraction, 0.0), 1.0);
      const remainingPercentage = Math.round(remainingFraction * 100);
      const resetTime = b.resetTime || b.reset_time || null;
      const resetDuration = formatResetDuration(resetTime, nowMs);

      buckets.push({
        id,
        displayName: b.displayName || b.display_name || id,
        window,
        remainingFraction,
        remainingPercentage,
        resetTime,
        resetDuration,
      });
    }

    if (buckets.length > 0) {
      groups.push({
        id: displayName,
        displayName,
        description: g.description || null,
        buckets,
      });
    }
  }

  if (groups.length === 0) return null;

  // Map to 4 clean iOS Battery-Widget rings: Gemini 5h, Gemini Wk, Claude, Argon 4
  const ringItems = [];
  for (const group of groups) {
    const lower = group.displayName.toLowerCase();
    if (lower.includes("gemini models") || (lower.includes("gemini") && !lower.includes("argon"))) {
      const sorted = [...group.buckets].sort((a, b) => (a.window === "5h" ? -1 : b.window === "5h" ? 1 : 0));
      for (const bucket of sorted) {
        const is5h = bucket.window === "5h";
        const title = is5h ? "Gemini 5h" : "Gemini Wk";
        const subtitle =
          bucket.remainingPercentage < 100 && bucket.resetDuration
            ? `↻ ${bucket.resetDuration}`
            : is5h
            ? "5h limit"
            : "Weekly";
        ringItems.push({
          id: bucket.id,
          title,
          subtitle,
          remainingFraction: bucket.remainingFraction,
          remainingPercentage: bucket.remainingPercentage,
          category: "gemini",
        });
      }
    } else if (lower.includes("argon")) {
      const bucket = group.buckets[0];
      const subtitle =
        bucket.remainingPercentage < 100 && bucket.resetDuration
          ? `↻ ${bucket.resetDuration}`
          : "Weekly";
      ringItems.push({
        id: bucket.id,
        title: "Argon 4",
        subtitle,
        remainingFraction: bucket.remainingFraction,
        remainingPercentage: bucket.remainingPercentage,
        category: "argon",
      });
    } else if (lower.includes("claude") || lower.includes("gpt")) {
      const sorted = [...group.buckets].sort((a, b) => (a.window === "5h" ? -1 : b.window === "5h" ? 1 : 0));
      for (const bucket of sorted) {
        const is5h = bucket.window === "5h";
        const title = is5h ? "Claude 5h" : "Claude Wk";
        const subtitle =
          bucket.remainingPercentage < 100 && bucket.resetDuration
            ? `↻ ${bucket.resetDuration}`
            : "Full";
        ringItems.push({
          id: bucket.id,
          title,
          subtitle,
          remainingFraction: bucket.remainingFraction,
          remainingPercentage: bucket.remainingPercentage,
          category: "claude",
        });
      }
    } else {
      for (const bucket of group.buckets) {
        ringItems.push({
          id: bucket.id,
          title: group.displayName,
          subtitle: bucket.resetDuration ? `↻ ${bucket.resetDuration}` : bucket.window,
          remainingFraction: bucket.remainingFraction,
          remainingPercentage: bucket.remainingPercentage,
          category: "other",
        });
      }
    }
  }

  return {
    timestamp: new Date(nowMs).toISOString(),
    groups,
    ringItems,
  };
}

function requestQuotaSummary(scheme, port, csrfToken) {
  return new Promise((resolve) => {
    const client = scheme === "https" ? https : http;
    const req = client.request(
      {
        protocol: `${scheme}:`,
        hostname: "127.0.0.1",
        port,
        path: "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-codeium-csrf-token": csrfToken,
        },
        rejectUnauthorized: false,
        timeout: 2500,
      },
      (res) => {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          resolve(null);
          return;
        }
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => {
          try {
            resolve(parseQuotaSummaryResponse(body));
          } catch {
            resolve(null);
          }
        });
      }
    );

    req.on("error", () => resolve(null));
    req.on("timeout", () => {
      req.destroy();
      resolve(null);
    });
    req.write("{}");
    req.end();
  });
}

async function fetchLiveQuotaSummary() {
  const candidates = discoverConnections();
  for (const candidate of candidates) {
    for (const scheme of ["http", "https"]) {
      const result = await requestQuotaSummary(scheme, candidate.port, candidate.csrfToken);
      if (result) {
        saveCachedConnection(candidate);
        return result;
      }
    }
  }
  return null;
}

module.exports = {
  parseConnectionsFromText,
  formatResetDuration,
  parseQuotaSummaryResponse,
  discoverConnections,
  fetchLiveQuotaSummary,
};
