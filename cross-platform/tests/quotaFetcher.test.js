"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  parseDiscoveryJsonObject,
  parseConnectionsFromText,
  formatResetDuration,
  parseQuotaSummaryResponse,
  classifyQuotaHttpResponse,
} = require("../src/quotaFetcher");
const {
  compareSemver,
  selectAssetForPlatform,
  selectChecksumAsset,
  parseSha256Sums,
  computeFileSha256,
  verifyFileSha256,
  buildWindowsPortableUpdateScript,
  buildWindowsNsisUpdateScript,
  buildLinuxAppImageUpdateScript,
  buildMacZipUpdateScript,
} = require("../src/autoUpdater");
const {
  isRectVisibleOnDisplays,
  resolveWindowPosition,
} = require("../src/windowBounds");
const {
  parseClaudeCredentialsJson,
  parseClaudeUsageResponse,
} = require("../src/providers/claudeCodeProvider");
const {
  parseCodexCredentialsJson,
  parseCodexUsageResponse,
} = require("../src/providers/codexProvider");
const { ProviderManager, mergeProviderResults } = require("../src/providers/providerManager");

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

// 5. Test Multi-Provider adapters (Claude Code & OpenAI Codex CLI) + ProviderManager merging
const claudeCreds = parseClaudeCredentialsJson(
  JSON.stringify({
    claudeAiOauth: {
      accessToken: "sk-ant-oat01-test-token",
      expiresAt: 1799999999000,
    },
  })
);
assert.equal(claudeCreds.accessToken, "sk-ant-oat01-test-token");

const claudeUsage = parseClaudeUsageResponse(
  {
    five_hour: { utilization: 33.0, resets_at: "2026-11-23T14:00:00Z" },
    seven_day: { utilization: 13.0, resets_at: "2026-11-29T11:00:00Z" },
    seven_day_sonnet: { utilization: 5.0, resets_at: "2026-11-29T11:00:00Z" },
    seven_day_opus: null,
  },
  refNowMs
);
assert.ok(claudeUsage);
assert.equal(claudeUsage.groups.length, 2);
assert.equal(claudeUsage.groups[0].id, "claude-code::primary");
assert.equal(claudeUsage.groups[0].providerId, "claude-code");
assert.equal(claudeUsage.groups[0].buckets[0].remainingPercentage, 67);
assert.equal(claudeUsage.groups[0].buckets[1].remainingPercentage, 87);
assert.equal(claudeUsage.ringItems[0].title, "CC 5h");
assert.equal(claudeUsage.ringItems[1].title, "CC Wk");

const codexCreds = parseCodexCredentialsJson(
  JSON.stringify({
    tokens: { access_token: "codex-access-xyz", account_id: "acct_123" },
  })
);
assert.equal(codexCreds.accessToken, "codex-access-xyz");
assert.equal(codexCreds.accountId, "acct_123");

const codexUsage = parseCodexUsageResponse(
  {
    plan_type: "Plus",
    rate_limit: {
      primary_window: {
        used_percent: 25,
        limit_window_seconds: 18000,
        reset_after_seconds: 7200,
      },
      secondary_window: {
        used_percent: 40,
        limit_window_seconds: 604800,
        reset_after_seconds: 259200,
      },
    },
  },
  refNowMs
);
assert.ok(codexUsage);
assert.equal(codexUsage.groups.length, 1);
assert.equal(codexUsage.groups[0].id, "codex::primary");
assert.equal(codexUsage.groups[0].displayName, "Codex CLI (Plus)");
assert.equal(codexUsage.groups[0].buckets[0].remainingPercentage, 75);
assert.equal(codexUsage.groups[0].buckets[1].remainingPercentage, 60);
assert.equal(codexUsage.ringItems[0].title, "CDX 5h");
assert.equal(codexUsage.ringItems[1].title, "CDX Wk");

// Regression: 1% used (e.g. weekly after a 5h usage reset) must be 99% remaining, never 0%
const codexPostReset = parseCodexUsageResponse(
  {
    plan_type: "Plus",
    rate_limit: {
      primary_window: {
        used_percent: 0,
        limit_window_seconds: 18000,
        reset_after_seconds: 18000,
      },
      secondary_window: {
        used_percent: 1,
        limit_window_seconds: 604800,
        reset_after_seconds: 604800,
      },
    },
  },
  refNowMs
);
assert.ok(codexPostReset);
assert.equal(codexPostReset.groups[0].buckets[0].remainingPercentage, 100);
assert.equal(codexPostReset.groups[0].buckets[1].remainingPercentage, 99);

const claudeOnePercent = parseClaudeUsageResponse(
  {
    five_hour: { utilization: 0.0, resets_at: "2026-11-23T14:00:00Z" },
    seven_day: { utilization: 1.0, resets_at: "2026-11-29T11:00:00Z" },
  },
  refNowMs
);
assert.ok(claudeOnePercent);
assert.equal(claudeOnePercent.groups[0].buckets[0].remainingPercentage, 100);
assert.equal(claudeOnePercent.groups[0].buckets[1].remainingPercentage, 99);

const mergedMulti = mergeProviderResults(
  {
    antigravity: {
      status: "connected",
      groups: parsed.groups.map((g) => ({ ...g, providerId: "antigravity" })),
      ringItems: parsed.ringItems.map((it) => ({ ...it, providerId: "antigravity" })),
    },
    "claude-code": {
      status: "connected",
      groups: claudeUsage.groups,
      ringItems: claudeUsage.ringItems,
    },
    codex: {
      status: "connected",
      groups: codexUsage.groups,
      ringItems: codexUsage.ringItems,
    },
  },
  ["antigravity", "claude-code", "codex"],
  refNowMs
);
assert.equal(mergedMulti.groups.length, 6);
assert.equal(mergedMulti.providerStatuses.antigravity.status, "connected");
assert.equal(mergedMulti.providerStatuses["claude-code"].shortName, "CC");
assert.equal(mergedMulti.providerStatuses.codex.shortName, "CDX");
console.log("  ✓ Multi-Provider adapters (Claude Code, Codex CLI) & ProviderManager passed");

// 6. Test Antigravity auth_required vs connected classification
assert.equal(classifyQuotaHttpResponse(401, "{}").status, "auth_required");
assert.equal(classifyQuotaHttpResponse(403, "{}").status, "auth_required");
assert.equal(classifyQuotaHttpResponse(200, '{"response":{"groups":[]}}').status, "auth_required");
assert.equal(
  classifyQuotaHttpResponse(200, '{"code":"UNAUTHENTICATED","message":"not signed in"}').status,
  "auth_required"
);
assert.equal(classifyQuotaHttpResponse(500, '{"error":"boom"}'), null);
assert.equal(
  classifyQuotaHttpResponse(200, JSON.stringify(sampleQuotaResponse)).status,
  "connected"
);
console.log("  ✓ Antigravity auth_required vs connected classification passed");

// 7. Test ProviderManager immediate cache invalidation on logout & account switch
(async () => {
  let currentFp = "acct-A-fp";
  let fetchCount = 0;

  const pm = new ProviderManager(
    {
      codex: async () => {
        fetchCount += 1;
        if (!currentFp) {
          return {
            providerId: "codex",
            status: "auth_required",
            message: 'Not signed in — run "codex login"',
            groups: [],
            ringItems: [],
          };
        }
        return {
          providerId: "codex",
          status: "connected",
          groups: [{ id: `codex::${currentFp}`, providerId: "codex", displayName: currentFp, buckets: [] }],
          ringItems: [],
        };
      },
    },
    {
      codex: () => currentFp,
    }
  );

  // Initial fetch for Account A
  const res1 = await pm.refresh(["codex"]);
  assert.equal(fetchCount, 1);
  assert.equal(res1.groups[0].id, "codex::acct-A-fp");

  // Cached hit while still on Account A
  const res2 = await pm.refresh(["codex"]);
  assert.equal(fetchCount, 1);
  assert.equal(res2.groups[0].id, "codex::acct-A-fp");

  // Logout (fingerprint becomes null) -> must immediately bypass 90s cache & clear groups
  currentFp = null;
  const res3 = await pm.refresh(["codex"]);
  assert.equal(fetchCount, 2);
  assert.equal(res3.groups.length, 0);
  assert.equal(res3.providerStatuses.codex.status, "auth_required");

  // Login to Account B -> must immediately bypass backoff & load Account B
  currentFp = "acct-B-fp";
  const res4 = await pm.refresh(["codex"]);
  assert.equal(fetchCount, 3);
  assert.equal(res4.groups[0].id, "codex::acct-B-fp");
  assert.equal(res4.providerStatuses.codex.status, "connected");

  console.log("  ✓ ProviderManager instant logout & account-switch cache invalidation passed");

  // 8. Test Multi-Monitor window bounds validation & off-screen recovery
  const primaryDisplay = { workArea: { x: 0, y: 0, width: 1920, height: 1040 } };
  const secondaryDisplay = { workArea: { x: 1920, y: 0, width: 2560, height: 1400 } };

  // Valid position on secondary display when both displays are attached
  const validSecondary = resolveWindowPosition({
    savedX: 2100,
    savedY: 120,
    width: 380,
    height: 200,
    displays: [primaryDisplay, secondaryDisplay],
    primaryDisplay,
  });
  assert.deepEqual(validSecondary, { x: 2100, y: 120, wasReset: false });

  // Disconnected secondary display -> savedX=2100 is now off-screen, must reset to primary
  const recoveredOffscreen = resolveWindowPosition({
    savedX: 2100,
    savedY: 120,
    width: 380,
    height: 200,
    displays: [primaryDisplay],
    primaryDisplay,
  });
  assert.equal(recoveredOffscreen.wasReset, true);
  assert.equal(recoveredOffscreen.x, 1920 - 380 - 28);
  assert.equal(recoveredOffscreen.y, 40);

  // Barely touching corner (only 10px visible) -> treated as off-screen and recovered
  assert.equal(
    isRectVisibleOnDisplays({ x: 1910, y: 100, width: 380, height: 200 }, [primaryDisplay]),
    false
  );

  // Invalid / null saved coordinates -> falls back to primary
  const nullSaved = resolveWindowPosition({
    savedX: null,
    savedY: NaN,
    width: 380,
    height: 200,
    displays: [primaryDisplay],
    primaryDisplay,
  });
  assert.equal(nullSaved.wasReset, true);
  console.log("  ✓ Multi-Monitor window bounds validation & off-screen recovery passed");

  // 9. Test Auto-Updater SHA256SUMS.txt parsing & file verification
  const checksumAsset = selectChecksumAsset([
    ...sampleAssets,
    { name: "SHA256SUMS.txt", browser_download_url: "https://example.com/SHA256SUMS.txt" },
  ]);
  assert.equal(checksumAsset.name, "SHA256SUMS.txt");

  const fakeHashA = "A".repeat(64);
  const fakeHashB = "b".repeat(64);
  const parsedSums = parseSha256Sums(
    [
      "# generated by sha256sum",
      `${fakeHashA}  OrbitHUD-Windows-Setup.exe`,
      `${fakeHashB} *./OrbitHUD-Linux-x86_64.AppImage`,
      "malformed line",
    ].join("\n")
  );
  assert.equal(parsedSums["OrbitHUD-Windows-Setup.exe"], fakeHashA.toLowerCase());
  assert.equal(parsedSums["OrbitHUD-Linux-x86_64.AppImage"], fakeHashB);

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "orbithud-sha-test-"));
  const goodFile = path.join(tmpDir, "update.bin");
  const payload = Buffer.from("orbithud-release-binary-payload-v1.2.1");
  fs.writeFileSync(goodFile, payload);
  const expectedSha = crypto.createHash("sha256").update(payload).digest("hex");

  assert.equal(await computeFileSha256(goodFile), expectedSha);
  const verified = await verifyFileSha256(goodFile, expectedSha.toUpperCase());
  assert.equal(verified.verified, true);
  assert.equal(fs.existsSync(goodFile), true);

  // Mismatched hash must throw and delete the tampered/corrupted file
  const badFile = path.join(tmpDir, "tampered.bin");
  fs.writeFileSync(badFile, "corrupted-bytes");
  await assert.rejects(
    () => verifyFileSha256(badFile, "0".repeat(64)),
    /SHA256 checksum mismatch/i
  );
  assert.equal(fs.existsSync(badFile), false);
  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log("  ✓ Auto-Updater SHA256 checksum parsing & verification passed");

  // 10. Test Auto-Updater relaunch scripts (Windows NSIS, Windows Portable, Linux AppImage, macOS Zip)
  const winNsisScript = buildWindowsNsisUpdateScript({
    downloadedPath: "C:\\Temp\\OrbitHUD-Windows-Setup.exe",
    execPath: "C:\\Users\\Dev\\AppData\\Local\\Programs\\OrbitHUD\\OrbitHUD.exe",
    pid: 12345,
  });
  assert.ok(!winNsisScript.includes("timeout /t"), "Windows NSIS script must not use timeout /t");
  assert.ok(winNsisScript.includes('tasklist /FI "PID eq 12345"'));
  assert.ok(winNsisScript.includes('start /wait "" "C:\\Temp\\OrbitHUD-Windows-Setup.exe" /S'));
  assert.ok(
    winNsisScript.includes('start "" "C:\\Users\\Dev\\AppData\\Local\\Programs\\OrbitHUD\\OrbitHUD.exe"')
  );

  const winPortableScript = buildWindowsPortableUpdateScript({
    downloadedPath: "C:\\Temp\\OrbitHUD-Windows-Portable.exe",
    portableTarget: "D:\\Tools\\OrbitHUD.exe",
    pid: 54321,
  });
  assert.ok(!winPortableScript.includes("timeout /t"), "Windows Portable script must not use timeout /t");
  assert.ok(winPortableScript.includes('tasklist /FI "PID eq 54321"'));
  assert.ok(winPortableScript.includes('copy /Y "C:\\Temp\\OrbitHUD-Windows-Portable.exe" "D:\\Tools\\OrbitHUD.exe"'));
  assert.ok(winPortableScript.includes('start "" "D:\\Tools\\OrbitHUD.exe"'));

  const linuxScript = buildLinuxAppImageUpdateScript({
    downloadedPath: "/tmp/OrbitHUD-Linux-x86_64.AppImage",
    appImageTarget: "/home/dev/Apps/OrbitHUD.AppImage",
    pid: 9876,
    shPath: "/tmp/update.sh",
  });
  assert.ok(linuxScript.includes("while kill -0 9876 2>/dev/null"));
  assert.ok(linuxScript.includes('nohup "/home/dev/Apps/OrbitHUD.AppImage" >/dev/null 2>&1 </dev/null &'));

  const macScript = buildMacZipUpdateScript({
    downloadedPath: "/tmp/OrbitHUD-macOS.zip",
    extractDir: "/tmp/extract",
    pid: 4321,
    shPath: "/tmp/update-mac.sh",
  });
  assert.ok(macScript.includes("while kill -0 4321 2>/dev/null"));
  assert.ok(macScript.includes('open -n "/Applications/OrbitHUD.app"'));
  console.log("  ✓ Auto-Updater relaunch scripts (Windows NSIS/Portable, Linux, macOS) passed");

  console.log("✅ All cross-platform tests passed!");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
