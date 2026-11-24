"use strict";

const assert = require("node:assert/strict");
const {
  parseDiscoveryJsonObject,
  parseConnectionsFromText,
  formatResetDuration,
  parseQuotaSummaryResponse,
} = require("../src/quotaFetcher");
const {
  compareSemver,
  selectAssetForPlatform,
} = require("../src/autoUpdater");

console.log("Running Cross-Platform Antigravity Usage Widget tests...");

// 1. Test Antigravity daemon discovery files (`hub_56726.json` & `ls_*.json`)
const hubDiscovery = parseDiscoveryJsonObject(
  {
    pid: 14820,
    httpsPort: 56726,
    httpPort: 56727,
    lspPort: 56728,
    lsVersion: "1.5.2",
    csrfToken: "daemon-hub-token-abc",
  },
  "hub_56726.json"
);
assert.equal(hubDiscovery.length, 3);
assert.deepEqual(hubDiscovery[0], { port: 56726, csrfToken: "daemon-hub-token-abc" });
assert.deepEqual(hubDiscovery[1], { port: 56727, csrfToken: "daemon-hub-token-abc" });

// Redacted token in discovery JSON should return empty array
const redactedDiscovery = parseDiscoveryJsonObject(
  {
    pid: 14820,
    httpsPort: 56726,
    csrfToken: "REDACTED",
  },
  "ls_test.json"
);
assert.equal(redactedDiscovery.length, 0);
console.log("  ✓ Antigravity daemon JSON discovery (hub_*.json / ls_*.json) passed");

// 2. Test Windows (including --random_port + PEB env + NetTCPConnection), Linux, and macOS process discovery
const sampleProcessDump = [
  // Windows agy.exe / language_server.exe with --random_port, NetTCPConnection port, and PEB environment token
  `agy "C:\\Program Files\\Antigravity\\resources\\bin\\language_server_windows_x64.exe" --enable_lsp --random_port --https_server_port=61420 ANTIGRAVITY_SERVER_CSRF_TOKEN=win-peb-token-999`,
  // Windows agy.exe hub process line
  `"C:\\Users\\dev\\.gemini\\bin\\agy.exe" --hub --hub-port=58100 --app_data_dir=antigravity --csrf_token=win-token-123`,
  // Linux /proc/<pid>/cmdline + environ line
  `/home/dev/.gemini/bin/agy --hub --hub-port=56726 --app_data_dir=antigravity ANTIGRAVITY_SERVER_CSRF_TOKEN=linux-token-456`,
  // macOS language_server line
  `/Applications/Antigravity.app/Contents/Resources/bin/language_server --https_server_port 59200 ANTIGRAVITY_CSRF_TOKEN=mac-token-789`,
].join("\n");

const connections = parseConnectionsFromText(sampleProcessDump);
assert.equal(connections.length >= 4, true);
assert.deepEqual(connections[0], { port: 61420, csrfToken: "win-peb-token-999" });
assert.deepEqual(connections[1], { port: 58100, csrfToken: "win-token-123" });
assert.deepEqual(connections[2], { port: 56726, csrfToken: "linux-token-456" });
assert.deepEqual(connections[3], { port: 59200, csrfToken: "mac-token-789" });
console.log("  ✓ Windows (PEB + NetTCPConnection + CLI), Linux, and macOS process discovery passed");

// 2. Test RetrieveUserQuotaSummary parsing & iOS ring items mapping
const sampleQuotaResponse = {
  response: {
    groups: [
      {
        displayName: "Gemini Models",
        buckets: [
          {
            bucketId: "gemini-weekly",
            displayName: "Weekly Limit Remaining",
            window: "weekly",
            remainingFraction: 0.7424301,
            resetTime: "2026-11-29T12:45:02Z",
          },
          {
            bucketId: "gemini-5h",
            displayName: "Five Hour Limit Remaining",
            window: "5h",
            remainingFraction: 0.44642693,
            resetTime: "2026-11-23T14:10:34Z",
          },
        ],
      },
      {
        displayName: "Claude and GPT models",
        buckets: [
          {
            bucketId: "3p-weekly",
            displayName: "Weekly Limit Remaining",
            window: "weekly",
            remainingFraction: 1,
            resetTime: "2026-11-30T10:59:39Z",
          },
          {
            bucketId: "3p-5h",
            displayName: "Five Hour Limit Remaining",
            window: "5h",
            remainingFraction: 1,
            resetTime: "2026-11-23T15:59:39Z",
          },
        ],
      },
      {
        displayName: "Gemini 4 Argon",
        buckets: [
          {
            bucketId: "gemini-argon-wtu-weekly",
            displayName: "Gemini 4 Argon Weekly Limit",
            window: "weekly",
            remainingFraction: 0.9263821,
            resetTime: "2026-11-30T09:58:45Z",
          },
        ],
      },
    ],
  },
};

const refNowMs = Date.parse("2026-11-23T11:00:00Z");
const parsed = parseQuotaSummaryResponse(sampleQuotaResponse, refNowMs);
assert.ok(parsed);
assert.equal(parsed.ringItems.length, 5);

assert.equal(parsed.ringItems[0].title, "Gemini 5h");
assert.equal(parsed.ringItems[0].remainingPercentage, 45);
assert.equal(parsed.ringItems[0].subtitle, "↻ 3h 10m");

assert.equal(parsed.ringItems[1].title, "Gemini Wk");
assert.equal(parsed.ringItems[1].remainingPercentage, 74);
assert.equal(parsed.ringItems[1].subtitle, "↻ 6d 1h");

assert.equal(parsed.ringItems[2].title, "Claude 5h");
assert.equal(parsed.ringItems[2].remainingPercentage, 100);
assert.equal(parsed.ringItems[2].subtitle, "Full");

assert.equal(parsed.ringItems[3].title, "Claude Wk");
assert.equal(parsed.ringItems[3].remainingPercentage, 100);
assert.equal(parsed.ringItems[3].subtitle, "Full");

assert.equal(parsed.ringItems[4].title, "Argon 4");
assert.equal(parsed.ringItems[4].remainingPercentage, 93);
assert.equal(parsed.ringItems[4].subtitle, "↻ 6d 22h");
assert.equal(parsed.ringItems[0].groupId, "Gemini Models");
assert.equal(parsed.ringItems[2].groupId, "Claude and GPT models");
assert.equal(parsed.ringItems[4].groupId, "Gemini 4 Argon");
assert.equal(parsed.groups[0].buckets[0].windowLabel, "Weekly limit");
assert.equal(parsed.groups[0].buckets[1].windowLabel, "5h limit");

// 3. Test dynamic / future unknown model groups (resilience against Google model changes)
const futureQuotaResponse = {
  response: {
    groups: [
      {
        displayName: "Future Ultra Model",
        buckets: [
          {
            bucketId: "ultra-weekly",
            displayName: "Weekly Limit",
            window: "weekly",
            remainingFraction: 0.8,
            resetTime: "2026-11-29T12:00:00Z",
          },
          {
            bucketId: "ultra-5h",
            displayName: "5h Limit",
            window: "5h",
            remainingFraction: 0.6,
            resetTime: "2026-11-23T14:00:00Z",
          },
        ],
      },
      {
        displayName: "Daily Experimental Pool",
        buckets: [
          {
            bucketId: "exp-daily",
            displayName: "Daily Limit",
            window: "daily",
            remainingFraction: 0.5,
            resetTime: "2026-11-24T11:00:00Z",
          },
        ],
      },
    ],
  },
};
const parsedFuture = parseQuotaSummaryResponse(futureQuotaResponse, refNowMs);
assert.ok(parsedFuture);
assert.equal(parsedFuture.groups.length, 2);
assert.equal(parsedFuture.ringItems.length, 3);
assert.equal(parsedFuture.ringItems[0].title, "Future Ultra Model 5h");
assert.equal(parsedFuture.ringItems[0].groupId, "Future Ultra Model");
assert.equal(parsedFuture.ringItems[1].title, "Future Ultra Model Wk");
assert.equal(parsedFuture.ringItems[2].title, "Daily Experimental Pool");
assert.equal(parsedFuture.groups[1].buckets[0].windowLabel, "Daily limit");

console.log("  ✓ RetrieveUserQuotaSummary parser & dynamic group/ring mapping passed");

// 4. Test Auto-Updater semver comparison & asset selection
assert.equal(compareSemver("v1.0.4", "1.0.3") > 0, true);
assert.equal(compareSemver("1.1.0", "1.0.9") > 0, true);
assert.equal(compareSemver("v1.0.4", "1.0.4"), 0);
assert.equal(compareSemver("1.0.2", "1.0.4") < 0, true);

const sampleAssets = [
  { name: "OrbitHUD-macOS.zip", browser_download_url: "https://example.com/mac.zip" },
  { name: "OrbitHUD-Windows-Setup.exe", browser_download_url: "https://example.com/setup.exe" },
  { name: "OrbitHUD-Windows-Portable.exe", browser_download_url: "https://example.com/portable.exe" },
  { name: "OrbitHUD-Linux-x86_64.AppImage", browser_download_url: "https://example.com/linux.AppImage" },
];
assert.equal(selectAssetForPlatform(sampleAssets, "win32", {}).name, "OrbitHUD-Windows-Setup.exe");
assert.equal(
  selectAssetForPlatform(sampleAssets, "win32", { PORTABLE_EXECUTABLE_FILE: "C:\\OrbitHUD.exe" }).name,
  "OrbitHUD-Windows-Portable.exe"
);
assert.equal(selectAssetForPlatform(sampleAssets, "linux", { APPIMAGE: "/opt/OrbitHUD.AppImage" }).name, "OrbitHUD-Linux-x86_64.AppImage");
assert.equal(selectAssetForPlatform(sampleAssets, "darwin", {}).name, "OrbitHUD-macOS.zip");
console.log("  ✓ Auto-Updater semver & platform asset selection passed");

console.log("✅ All cross-platform tests passed!");
