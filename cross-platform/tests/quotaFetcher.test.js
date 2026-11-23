"use strict";

const assert = require("node:assert/strict");
const {
  parseConnectionsFromText,
  formatResetDuration,
  parseQuotaSummaryResponse,
} = require("../src/quotaFetcher");

console.log("Running Cross-Platform Antigravity Usage Widget tests...");

// 1. Test Windows, Linux, and macOS process discovery patterns
const sampleProcessDump = [
  // Windows agy.exe process line
  `"C:\\Users\\dev\\.gemini\\bin\\agy.exe" --hub --hub-port=58100 --app_data_dir=antigravity --csrf_token=win-token-123`,
  // Linux /proc/<pid>/cmdline + environ line
  `/home/dev/.gemini/bin/agy --hub --hub-port=56726 --app_data_dir=antigravity ANTIGRAVITY_SERVER_CSRF_TOKEN=linux-token-456`,
  // macOS language_server line
  `/Applications/Antigravity.app/Contents/Resources/bin/language_server --https_server_port 59200 ANTIGRAVITY_CSRF_TOKEN=mac-token-789`,
].join("\n");

const connections = parseConnectionsFromText(sampleProcessDump);
assert.equal(connections.length >= 3, true);
assert.deepEqual(connections[0], { port: 58100, csrfToken: "win-token-123" });
assert.deepEqual(connections[1], { port: 56726, csrfToken: "linux-token-456" });
assert.deepEqual(connections[2], { port: 59200, csrfToken: "mac-token-789" });
console.log("  ✓ Windows, Linux, and macOS process & CSRF token discovery passed");

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

console.log("  ✓ RetrieveUserQuotaSummary parser & iOS ring items mapping passed");
console.log("✅ All cross-platform tests passed!");
