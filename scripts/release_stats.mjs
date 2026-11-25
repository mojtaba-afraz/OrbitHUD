#!/usr/bin/env node
/**
 * OrbitHUD Release Download Analytics (Zero-Telemetry)
 *
 * Queries the GitHub Releases API to summarize installer downloads per version
 * and per operating system (macOS, Windows, Linux).
 *
 * Usage:
 *   node scripts/release_stats.mjs
 *   node scripts/release_stats.mjs --markdown
 *   node scripts/release_stats.mjs --json
 *   node scripts/release_stats.mjs --repo mojtaba-afraz/OrbitHUD
 */

import { fileURLToPath } from "node:url";
import path from "node:path";

export const DEFAULT_REPO = "mojtaba-afraz/OrbitHUD";

/**
 * Classifies a GitHub release asset filename into a platform bucket.
 * Metadata/checksum files are classified as "checksum" and excluded from installer totals.
 */
export function classifyAssetPlatform(assetName) {
  if (!assetName || typeof assetName !== "string") return "other";
  const lower = assetName.toLowerCase();

  if (
    lower.includes("sha256") ||
    lower.endsWith(".sig") ||
    lower.endsWith(".asc") ||
    lower.endsWith(".blockmap") ||
    lower.endsWith(".yml") ||
    lower.endsWith(".yaml")
  ) {
    return "checksum";
  }

  if (
    lower.endsWith(".dmg") ||
    lower.endsWith(".pkg") ||
    lower.includes("macos") ||
    lower.includes("darwin")
  ) {
    return "macos";
  }

  if (
    lower.endsWith(".exe") ||
    lower.endsWith(".msi") ||
    lower.includes("windows") ||
    lower.includes("win32") ||
    lower.includes("win64")
  ) {
    return "windows";
  }

  if (
    lower.endsWith(".appimage") ||
    lower.endsWith(".deb") ||
    lower.endsWith(".rpm") ||
    lower.endsWith(".snap") ||
    lower.includes("linux")
  ) {
    return "linux";
  }

  return "other";
}

/**
 * Aggregates GitHub Releases API payload into per-release and grand-total download stats.
 */
export function aggregateReleaseStats(releases, options = {}) {
  const includeDrafts = Boolean(options.includeDrafts);
  const totals = { macos: 0, windows: 0, linux: 0, other: 0, total: 0 };
  const releaseRows = [];

  for (const rel of releases || []) {
    if (!rel) continue;
    if (rel.draft && !includeDrafts) continue;

    const counts = { macos: 0, windows: 0, linux: 0, other: 0, total: 0 };
    const assets = [];

    for (const asset of rel.assets || []) {
      const name = String(asset.name || "");
      const downloads = Number(asset.download_count || 0);
      const platform = classifyAssetPlatform(name);

      if (platform === "checksum") continue;

      counts[platform] += downloads;
      counts.total += downloads;
      totals[platform] += downloads;
      totals.total += downloads;

      assets.push({ name, platform, downloads });
    }

    assets.sort((a, b) => b.downloads - a.downloads || a.name.localeCompare(b.name));

    releaseRows.push({
      tag: String(rel.tag_name || rel.name || "unknown"),
      name: String(rel.name || rel.tag_name || "unknown"),
      publishedAt: rel.published_at ? String(rel.published_at).slice(0, 10) : "—",
      prerelease: Boolean(rel.prerelease),
      draft: Boolean(rel.draft),
      counts,
      assets,
    });
  }

  return { totals, releases: releaseRows };
}

function pct(part, total) {
  if (!total || total <= 0) return "0%";
  return `${Math.round((part / total) * 100)}%`;
}

function platformLabel(platform) {
  switch (platform) {
    case "macos":
      return "macOS";
    case "windows":
      return "Windows";
    case "linux":
      return "Linux";
    default:
      return "Other";
  }
}

/**
 * Formats aggregated stats as GitHub-flavored Markdown (ideal for GitHub Actions Job Summaries).
 */
export function formatMarkdownReport(stats, repo = DEFAULT_REPO) {
  const { totals, releases } = stats;
  const lines = [];

  lines.push(`# OrbitHUD Release Download Analytics`);
  lines.push("");
  lines.push(`Repository: \`${repo}\` · Releases tracked: **${releases.length}** · Zero-telemetry (GitHub Releases API)`);
  lines.push("");
  lines.push(`## Overall Summary`);
  lines.push("");
  lines.push(`| Platform | Downloads | Share |`);
  lines.push(`| :--- | ---: | ---: |`);
  lines.push(`| 🍎 macOS | **${totals.macos.toLocaleString("en-US")}** | ${pct(totals.macos, totals.total)} |`);
  lines.push(`| 🪟 Windows | **${totals.windows.toLocaleString("en-US")}** | ${pct(totals.windows, totals.total)} |`);
  lines.push(`| 🐧 Linux | **${totals.linux.toLocaleString("en-US")}** | ${pct(totals.linux, totals.total)} |`);
  if (totals.other > 0) {
    lines.push(`| 📦 Other | **${totals.other.toLocaleString("en-US")}** | ${pct(totals.other, totals.total)} |`);
  }
  lines.push(`| **Total Installer Downloads** | **${totals.total.toLocaleString("en-US")}** | **100%** |`);
  lines.push("");

  lines.push(`## Downloads by Release Version`);
  lines.push("");
  lines.push(`| Version | Published | macOS | Windows | Linux | Total |`);
  lines.push(`| :--- | :--- | ---: | ---: | ---: | ---: |`);
  for (const r of releases) {
    lines.push(
      `| \`${r.tag}\` | ${r.publishedAt} | ${r.counts.macos.toLocaleString("en-US")} | ${r.counts.windows.toLocaleString("en-US")} | ${r.counts.linux.toLocaleString("en-US")} | **${r.counts.total.toLocaleString("en-US")}** |`
    );
  }

  const latest = releases[0];
  if (latest && latest.assets.length > 0) {
    lines.push("");
    lines.push(`## Latest Release Breakdown (\`${latest.tag}\`)`);
    lines.push("");
    lines.push(`| Asset | Platform | Downloads |`);
    lines.push(`| :--- | :--- | ---: |`);
    for (const a of latest.assets) {
      lines.push(`| \`${a.name}\` | ${platformLabel(a.platform)} | ${a.downloads.toLocaleString("en-US")} |`);
    }
  }

  lines.push("");
  return lines.join("\n");
}

/**
 * Formats aggregated stats as a clean aligned terminal table.
 */
export function formatTerminalReport(stats, repo = DEFAULT_REPO) {
  const { totals, releases } = stats;
  const lines = [];

  lines.push(`OrbitHUD Release Download Analytics (${repo})`);
  lines.push("=".repeat(68));
  lines.push(
    `Total: ${totals.total}  |  macOS: ${totals.macos} (${pct(totals.macos, totals.total)})  |  Windows: ${totals.windows} (${pct(totals.windows, totals.total)})  |  Linux: ${totals.linux} (${pct(totals.linux, totals.total)})`
  );
  lines.push("-".repeat(68));

  const header = [
    "Version".padEnd(12),
    "Date".padEnd(12),
    "macOS".padStart(8),
    "Windows".padStart(9),
    "Linux".padStart(8),
    "Total".padStart(9),
  ].join("  ");
  lines.push(header);
  lines.push("-".repeat(68));

  for (const r of releases) {
    lines.push(
      [
        r.tag.padEnd(12),
        r.publishedAt.padEnd(12),
        String(r.counts.macos).padStart(8),
        String(r.counts.windows).padStart(9),
        String(r.counts.linux).padStart(8),
        String(r.counts.total).padStart(9),
      ].join("  ")
    );
  }

  const latest = releases[0];
  if (latest && latest.assets.length > 0) {
    lines.push("");
    lines.push(`Latest Release Assets (${latest.tag}):`);
    for (const a of latest.assets) {
      lines.push(
        `  ${a.name.padEnd(36)} ${platformLabel(a.platform).padEnd(9)} ${String(a.downloads).padStart(6)}`
      );
    }
  }

  return lines.join("\n");
}

/**
 * Fetches all releases from GitHub REST API (handling pagination).
 */
export async function fetchAllReleases(repo = DEFAULT_REPO, token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN) {
  const all = [];
  let page = 1;

  while (true) {
    const url = `https://api.github.com/repos/${repo}/releases?per_page=100&page=${page}`;
    const headers = {
      Accept: "application/vnd.github+json",
      "User-Agent": "OrbitHUD-ReleaseStats",
    };
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }

    const res = await fetch(url, { headers });
    if (!res.ok) {
      throw new Error(`GitHub API error: HTTP ${res.status} ${res.statusText}`);
    }
    const batch = await res.json();
    if (!Array.isArray(batch) || batch.length === 0) break;
    all.push(...batch);
    if (batch.length < 100) break;
    page += 1;
  }

  return all;
}

async function main() {
  const args = process.argv.slice(2);
  let repo = DEFAULT_REPO;
  let format = "terminal";
  let includeDrafts = false;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--markdown" || arg === "--md") {
      format = "markdown";
    } else if (arg === "--json") {
      format = "json";
    } else if (arg === "--include-drafts") {
      includeDrafts = true;
    } else if (arg === "--repo" && args[i + 1]) {
      repo = args[++i];
    }
  }

  const releases = await fetchAllReleases(repo);
  const stats = aggregateReleaseStats(releases, { includeDrafts });

  if (format === "json") {
    console.log(JSON.stringify({ repo, generatedAt: new Date().toISOString(), ...stats }, null, 2));
  } else if (format === "markdown") {
    console.log(formatMarkdownReport(stats, repo));
  } else {
    console.log(formatTerminalReport(stats, repo));
  }
}

const isDirectRun =
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));

if (isDirectRun) {
  main().catch((err) => {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  });
}
