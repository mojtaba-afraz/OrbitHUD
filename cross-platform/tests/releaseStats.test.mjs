import assert from "node:assert/strict";
import {
  classifyAssetPlatform,
  aggregateReleaseStats,
  formatMarkdownReport,
  formatTerminalReport,
} from "../../scripts/release_stats.mjs";

console.log("Running Release Download Analytics tests...");

// 1. Asset platform classification
assert.equal(classifyAssetPlatform("OrbitHUD-macOS.dmg"), "macos");
assert.equal(classifyAssetPlatform("OrbitHUD-macOS.zip"), "macos");
assert.equal(classifyAssetPlatform("OrbitHUD-Windows-Setup.exe"), "windows");
assert.equal(classifyAssetPlatform("OrbitHUD-Windows-Portable.exe"), "windows");
assert.equal(classifyAssetPlatform("OrbitHUD-Linux-x86_64.AppImage"), "linux");
assert.equal(classifyAssetPlatform("OrbitHUD-Linux-amd64.deb"), "linux");
assert.equal(classifyAssetPlatform("SHA256SUMS.txt"), "checksum");
assert.equal(classifyAssetPlatform("latest.yml"), "checksum");
assert.equal(classifyAssetPlatform("notes.txt"), "other");
console.log("  ✓ Asset platform classification passed");

// 2. Aggregation across multiple releases (excluding drafts & checksum files)
const mockReleases = [
  {
    tag_name: "v1.2.2",
    published_at: "2026-11-25T10:00:00Z",
    draft: false,
    prerelease: false,
    assets: [
      { name: "OrbitHUD-macOS.dmg", download_count: 42 },
      { name: "OrbitHUD-macOS.zip", download_count: 8 },
      { name: "OrbitHUD-Windows-Setup.exe", download_count: 35 },
      { name: "OrbitHUD-Windows-Portable.exe", download_count: 5 },
      { name: "OrbitHUD-Linux-x86_64.AppImage", download_count: 7 },
      { name: "OrbitHUD-Linux-amd64.deb", download_count: 3 },
      { name: "SHA256SUMS.txt", download_count: 99 },
    ],
  },
  {
    tag_name: "v1.2.0",
    published_at: "2026-11-20T08:30:00Z",
    draft: false,
    prerelease: false,
    assets: [
      { name: "OrbitHUD-macOS.dmg", download_count: 10 },
      { name: "OrbitHUD-Windows-Setup.exe", download_count: 20 },
    ],
  },
  {
    tag_name: "v1.3.0-draft",
    published_at: null,
    draft: true,
    prerelease: false,
    assets: [{ name: "OrbitHUD-macOS.dmg", download_count: 999 }],
  },
];

const stats = aggregateReleaseStats(mockReleases);
assert.equal(stats.releases.length, 2);
assert.deepEqual(stats.totals, {
  macos: 60,
  windows: 60,
  linux: 10,
  other: 0,
  total: 130,
});
assert.equal(stats.releases[0].tag, "v1.2.2");
assert.equal(stats.releases[0].publishedAt, "2026-11-25");
assert.equal(stats.releases[0].counts.total, 100);
assert.equal(stats.releases[0].assets.length, 6); // SHA256SUMS.txt excluded
console.log("  ✓ Multi-release download aggregation passed");

// 3. Markdown & Terminal formatting
const md = formatMarkdownReport(stats, "mojtaba-afraz/OrbitHUD");
assert.ok(md.includes("| `v1.2.2` | 2026-11-25 | 50 | 40 | 10 | **100** |"));
assert.ok(md.includes("Latest Release Breakdown (`v1.2.2`)"));
assert.ok(md.includes("Total Installer Downloads"));

const term = formatTerminalReport(stats, "mojtaba-afraz/OrbitHUD");
assert.ok(term.includes("Total: 130"));
assert.ok(term.includes("v1.2.2"));
assert.ok(term.includes("OrbitHUD-macOS.dmg"));
console.log("  ✓ Markdown and terminal report formatters passed");

console.log("✅ All release download analytics tests passed!");
