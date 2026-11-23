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
  /--http_server_port=(\d+)/gi,
  /--http_server_port\s+(\d+)/gi,
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
 * Extracts candidate ports from a daemon discovery JSON object (`hub_<port>.json` or `ls_<id>.json`).
 */
function extractPortsFromDiscoveryObject(obj, filename = "") {
  if (!obj || typeof obj !== "object") return [];
  const candidatePorts = [];
  for (const key of ["httpsPort", "httpPort", "port", "hubPort", "lspPort", "https_port", "http_port"]) {
    const val = obj[key];
    if (typeof val === "number" && val > 1024 && !candidatePorts.includes(val)) {
      candidatePorts.push(val);
    } else if (typeof val === "string" && /^\d+$/.test(val)) {
      const p = parseInt(val, 10);
      if (p > 1024 && !candidatePorts.includes(p)) candidatePorts.push(p);
    }
  }

  const nameMatch = /hub_(\d+)\.json$/i.exec(filename);
  if (nameMatch) {
    const p = parseInt(nameMatch[1], 10);
    if (p > 1024 && !candidatePorts.includes(p)) {
      candidatePorts.push(p);
    }
  }
  return candidatePorts;
}

/**
 * Parses a single Antigravity daemon discovery JSON file (`hub_<port>.json` or `ls_<id>.json`).
 */
function parseDiscoveryJsonObject(obj, filename = "") {
  if (!obj || typeof obj !== "object") return [];

  const csrfToken =
    obj.csrfToken ||
    obj.csrf_token ||
    obj.token ||
    obj.extensionServerCsrfToken ||
    "";
  if (
    typeof csrfToken !== "string" ||
    !csrfToken.trim() ||
    csrfToken.trim() === "REDACTED"
  ) {
    return [];
  }

  const candidatePorts = extractPortsFromDiscoveryObject(obj, filename);
  return candidatePorts.map((port) => ({
    port,
    csrfToken: csrfToken.trim(),
  }));
}

function getCandidateDaemonDirs(homeDir = os.homedir()) {
  const dirs = new Set([
    path.join(homeDir, ".gemini", "antigravity", "daemon"),
    path.join(homeDir, ".gemini", "antigravity-ide", "daemon"),
    path.join(homeDir, ".gemini", "antigravity-cli", "daemon"),
    path.join(homeDir, ".gemini", "antigravity-dev", "daemon"),
    path.join(homeDir, ".codeium", "antigravity", "daemon"),
  ]);

  const roots = [homeDir];
  if (process.env.USERPROFILE && process.env.USERPROFILE !== homeDir) {
    roots.push(process.env.USERPROFILE);
  }
  for (const root of roots) {
    const geminiRoot = path.join(root, ".gemini");
    try {
      for (const sub of fs.readdirSync(geminiRoot)) {
        dirs.add(path.join(geminiRoot, sub, "daemon"));
      }
    } catch {
      // ignore
    }
  }

  if (process.env.APPDATA) {
    dirs.add(path.join(process.env.APPDATA, "Antigravity", "daemon"));
    dirs.add(path.join(process.env.APPDATA, "Antigravity IDE", "daemon"));
    dirs.add(path.join(process.env.APPDATA, ".gemini", "antigravity", "daemon"));
  }
  if (process.env.LOCALAPPDATA) {
    dirs.add(path.join(process.env.LOCALAPPDATA, "Antigravity", "daemon"));
    dirs.add(path.join(process.env.LOCALAPPDATA, "Antigravity IDE", "daemon"));
  }

  return Array.from(dirs);
}

/**
 * Cross-platform discovery from Antigravity's official daemon discovery directory:
 * `~/.gemini/antigravity/daemon/hub_*.json` & `ls_*.json` (works on Windows, Linux, and macOS).
 */
function discoverFromDaemonFiles(homeDir = os.homedir()) {
  const results = [];
  const candidateDirs = getCandidateDaemonDirs(homeDir);

  for (const dir of candidateDirs) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir);
    } catch {
      continue;
    }

    // Sort newest first by mtime so most recently started hub/ls is tried first
    const jsonFiles = entries
      .filter((f) => f.endsWith(".json"))
      .map((f) => {
        const fullPath = path.join(dir, f);
        let mtimeMs = 0;
        try {
          mtimeMs = fs.statSync(fullPath).mtimeMs;
        } catch {
          // ignore
        }
        return { name: f, fullPath, mtimeMs };
      })
      .sort((a, b) => b.mtimeMs - a.mtimeMs);

    for (const file of jsonFiles) {
      try {
        const raw = fs.readFileSync(file.fullPath, "utf8");
        const parsed = JSON.parse(raw);
        for (const conn of parseDiscoveryJsonObject(parsed, file.name)) {
          results.push(conn);
        }
      } catch {
        // ignore malformed file
      }
    }
  }

  return results;
}

/**
 * Collects all ports mentioned in `daemon/*.json` even when `csrfToken` is redacted,
 * so they can be paired with CSRF tokens discovered from OS process environments.
 */
function discoverPortsFromDaemonFiles(homeDir = os.homedir()) {
  const ports = [];
  for (const dir of getCandidateDaemonDirs(homeDir)) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const f of entries) {
      if (!f.endsWith(".json")) continue;
      try {
        const raw = fs.readFileSync(path.join(dir, f), "utf8");
        const parsed = JSON.parse(raw);
        for (const p of extractPortsFromDiscoveryObject(parsed, f)) {
          if (!ports.includes(p)) ports.push(p);
        }
      } catch {
        // ignore
      }
    }
  }
  return ports;
}

/**
 * Extracts all `{ port, csrfToken }` combinations from process command line / environment strings.
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
          // ignore
        }
        lines.push(`${cmdline} ${environ}`);
      } catch {
        // ignore
      }
    }
  } catch {
    // ignore
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

function discoverOnWindows() {
  const chunks = [];

  // Include any ports from daemon/*.json in case csrfToken was redacted on disk
  for (const p of discoverPortsFromDaemonFiles()) {
    chunks.push(`agy --https_server_port=${p}`);
  }

  try {
    const psScript = `
$ErrorActionPreference = 'SilentlyContinue'
$pebCode = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class AgyPebReader {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_BASIC_INFORMATION {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2_0;
        public IntPtr Reserved2_1;
        public IntPtr UniqueProcessId;
        public IntPtr Reserved3;
    }
    [DllImport("kernel32.dll")]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")]
    public static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PROCESS_BASIC_INFORMATION pbi, int len, out int retLen);
    [DllImport("kernel32.dll")]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out int read);

    public static string GetEnv(int pid) {
        if (IntPtr.Size != 8) return "";
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) return "";
        try {
            PROCESS_BASIC_INFORMATION pbi = new PROCESS_BASIC_INFORMATION();
            int retLen;
            if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out retLen) != 0 || pbi.PebBaseAddress == IntPtr.Zero) return "";
            byte[] ptrBuf = new byte[8];
            int read;
            if (!ReadProcessMemory(h, IntPtr.Add(pbi.PebBaseAddress, 0x20), ptrBuf, 8, out read) || read != 8) return "";
            long procParams = BitConverter.ToInt64(ptrBuf, 0);
            if (procParams == 0) return "";
            if (!ReadProcessMemory(h, new IntPtr(procParams + 0x80), ptrBuf, 8, out read) || read != 8) return "";
            long envPtr = BitConverter.ToInt64(ptrBuf, 0);
            if (envPtr == 0) return "";
            int envSize = 65536;
            if (ReadProcessMemory(h, new IntPtr(procParams + 0x3F0), ptrBuf, 8, out read) && read == 8) {
                long sz = BitConverter.ToInt64(ptrBuf, 0);
                if (sz > 0 && sz < 524288) envSize = (int)sz;
            }
            byte[] envBuf = new byte[envSize];
            if (!ReadProcessMemory(h, new IntPtr(envPtr), envBuf, envSize, out read) || read <= 0) return "";
            return Encoding.Unicode.GetString(envBuf, 0, read).Replace('\\0', ' ');
        } catch {
            return "";
        } finally {
            CloseHandle(h);
        }
    }
}
"@
try { Add-Type -TypeDefinition $pebCode -ErrorAction SilentlyContinue } catch {}

$procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'agy|language_server|antigravity' }
foreach ($p in $procs) {
    $cmd = $p.CommandLine
    $portArgs = ""
    if ($p.Name -match 'agy|language_server') {
        $conns = Get-NetTCPConnection -State Listen -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            if ($c.LocalPort -gt 1024) {
                $portArgs += " --https_server_port=" + $c.LocalPort
            }
        }
    }
    $envStr = ""
    try { $envStr = [AgyPebReader]::GetEnv([int]$p.ProcessId) } catch {}
    Write-Output ("agy " + $cmd + " " + $portArgs + " " + $envStr)
}
`.trim();
    const out = execFileSync(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", psScript],
      {
        encoding: "utf8",
        timeout: 8000,
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

function discoverFastConnections() {
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

  // 2. Check Antigravity's official daemon discovery files (`~/.gemini/antigravity/daemon/hub_*.json` & `ls_*.json`)
  for (const daemonConn of discoverFromDaemonFiles()) {
    pushUnique(daemonConn);
  }

  // 3. Check cached connection on disk
  const cached = loadCachedConnection();
  if (cached) {
    pushUnique(cached);
  }

  return candidates;
}

function discoverConnections(platform = process.platform) {
  const candidates = discoverFastConnections();
  const seen = new Set(candidates.map((c) => `${c.port}:${c.csrfToken}`));
  const pushUnique = (conn) => {
    if (!conn || !conn.port || !conn.csrfToken) return;
    const key = `${conn.port}:${conn.csrfToken}`;
    if (!seen.has(key)) {
      seen.add(key);
      candidates.push(conn);
    }
  };

  // 4. OS-specific live process discovery fallback
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
  const tried = new Set();

  // 1. Try fast candidates first (env, daemon/*.json, cached connection) without spawning ps/powershell
  for (const candidate of discoverFastConnections()) {
    const key = `${candidate.port}:${candidate.csrfToken}`;
    tried.add(key);
    for (const scheme of ["https", "http"]) {
      const result = await requestQuotaSummary(scheme, candidate.port, candidate.csrfToken);
      if (result) {
        saveCachedConnection(candidate);
        return result;
      }
    }
  }

  // 2. Fallback to full OS process & PEB environment discovery
  for (const candidate of discoverConnections()) {
    const key = `${candidate.port}:${candidate.csrfToken}`;
    if (tried.has(key)) continue;
    tried.add(key);
    for (const scheme of ["https", "http"]) {
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
  parseDiscoveryJsonObject,
  discoverFromDaemonFiles,
  parseConnectionsFromText,
  formatResetDuration,
  parseQuotaSummaryResponse,
  discoverConnections,
  fetchLiveQuotaSummary,
};
