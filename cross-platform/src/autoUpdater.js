"use strict";

const https = require("node:https");
const http = require("node:http");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawn } = require("node:child_process");

const REPO_OWNER = "mojtaba-afraz";
const REPO_NAME = "OrbitHUD";
const LATEST_RELEASE_API = `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`;

/**
 * Parses a semver tag like "v1.0.4" or "1.2.3" into [major, minor, patch].
 */
function parseSemver(versionStr) {
  if (!versionStr || typeof versionStr !== "string") return [0, 0, 0];
  const cleaned = versionStr.trim().replace(/^v/i, "").split("-")[0];
  const parts = cleaned.split(".").map((n) => parseInt(n, 10) || 0);
  return [parts[0] || 0, parts[1] || 0, parts[2] || 0];
}

/**
 * Returns > 0 if `a > b`, < 0 if `a < b`, 0 if equal.
 */
function compareSemver(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

/**
 * Picks the best matching release asset for the current OS & packaging mode.
 */
function selectAssetForPlatform(
  assets,
  platform = process.platform,
  env = process.env
) {
  if (!Array.isArray(assets) || assets.length === 0) return null;

  const findByPattern = (regex) =>
    assets.find(
      (a) =>
        a &&
        typeof a.name === "string" &&
        typeof a.browser_download_url === "string" &&
        regex.test(a.name)
    ) || null;

  if (platform === "win32") {
    const isPortable = Boolean(env && env.PORTABLE_EXECUTABLE_FILE);
    if (isPortable) {
      return (
        findByPattern(/portable.*\.exe$/i) ||
        findByPattern(/setup.*\.exe$/i) ||
        findByPattern(/\.exe$/i)
      );
    }
    return (
      findByPattern(/setup.*\.exe$/i) ||
      findByPattern(/windows.*\.exe$/i) ||
      findByPattern(/\.exe$/i)
    );
  }

  if (platform === "linux") {
    const isAppImage = Boolean(env && env.APPIMAGE);
    if (isAppImage) {
      return findByPattern(/\.AppImage$/i) || findByPattern(/\.deb$/i);
    }
    return findByPattern(/\.AppImage$/i) || findByPattern(/\.deb$/i);
  }

  if (platform === "darwin") {
    return findByPattern(/\.zip$/i) || findByPattern(/\.dmg$/i);
  }

  return null;
}

/**
 * Finds the SHA256SUMS.txt asset in a GitHub release's assets array.
 */
function selectChecksumAsset(assets) {
  if (!Array.isArray(assets) || assets.length === 0) return null;
  return (
    assets.find(
      (a) =>
        a &&
        typeof a.name === "string" &&
        typeof a.browser_download_url === "string" &&
        /^SHA256SUMS(\.txt)?$/i.test(a.name.trim())
    ) || null
  );
}

/**
 * Performs an HTTPS GET returning UTF-8 text (follows redirects).
 */
function fetchText(url, maxRedirects = 4) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https:") ? https : http;
    const req = client.get(
      url,
      {
        headers: {
          "User-Agent": "OrbitHUD-AutoUpdater",
          Accept: "text/plain, application/octet-stream, */*",
        },
        timeout: 10000,
      },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          maxRedirects > 0
        ) {
          res.resume();
          resolve(fetchText(res.headers.location, maxRedirects - 1));
          return;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          reject(new Error(`Checksum fetch failed with HTTP ${res.statusCode}`));
          return;
        }
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => resolve(body));
      }
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("Checksum request timed out"));
    });
  });
}

/**
 * Parses standard `sha256sum` text (e.g. `<hex>  <filename>` or `<hex> *<filename>`)
 * into a map `{ [basename]: lowercaseHex }`.
 */
function parseSha256Sums(text) {
  const sums = {};
  if (!text || typeof text !== "string") return sums;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = line.match(/^([0-9a-fA-F]{64})\s+\*?(.+)$/);
    if (!match) continue;
    const hash = match[1].toLowerCase();
    const rawName = match[2].trim().replace(/^\.\//, "");
    const baseName = path.posix.basename(rawName.replace(/\\/g, "/"));
    if (baseName) {
      sums[baseName] = hash;
    }
  }
  return sums;
}

/**
 * Computes the lowercase hex SHA256 digest of a file on disk.
 */
function computeFileSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256");
    const stream = fs.createReadStream(filePath);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex").toLowerCase()));
    stream.on("error", reject);
  });
}

/**
 * Verifies a downloaded file against an expected 64-char hex SHA256 digest.
 * Deletes the file and throws on mismatch or invalid expected hash.
 */
async function verifyFileSha256(filePath, expectedHash) {
  const cleanup = () => {
    try {
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    } catch {
      // ignore cleanup errors
    }
  };

  if (typeof expectedHash !== "string" || !/^[0-9a-fA-F]{64}$/.test(expectedHash.trim())) {
    cleanup();
    throw new Error("Invalid expected SHA256 checksum format");
  }

  const normalizedExpected = expectedHash.trim().toLowerCase();
  const actual = await computeFileSha256(filePath);
  const expectedBuf = Buffer.from(normalizedExpected, "hex");
  const actualBuf = Buffer.from(actual, "hex");

  if (
    expectedBuf.length !== actualBuf.length ||
    !crypto.timingSafeEqual(expectedBuf, actualBuf)
  ) {
    cleanup();
    throw new Error(
      `SHA256 checksum mismatch (expected ${normalizedExpected.slice(0, 12)}..., got ${actual.slice(0, 12)}...)`
    );
  }

  return { verified: true, sha256: actual };
}

/**
 * Performs an HTTPS GET returning parsed JSON (follows redirects).
 */
function fetchJson(url, maxRedirects = 4) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https:") ? https : http;
    const req = client.get(
      url,
      {
        headers: {
          "User-Agent": "OrbitHUD-AutoUpdater",
          Accept: "application/vnd.github+json",
        },
        timeout: 10000,
      },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          maxRedirects > 0
        ) {
          res.resume();
          resolve(fetchJson(res.headers.location, maxRedirects - 1));
          return;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          reject(new Error(`GitHub API HTTP ${res.statusCode}`));
          return;
        }
        let body = "";
        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          body += chunk;
        });
        res.on("end", () => {
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            reject(err);
          }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("Request timed out"));
    });
  });
}

/**
 * Checks GitHub Releases for a version newer than `currentVersion`.
 * Returns `{ available, currentVersion, latestVersion, releaseUrl, notes, asset }` or null on error.
 */
async function checkForUpdate(
  currentVersion,
  platform = process.platform,
  env = process.env
) {
  const release = await fetchJson(LATEST_RELEASE_API);
  const latestVersion = String(release.tag_name || "").replace(/^v/i, "");
  const isNewer = compareSemver(latestVersion, currentVersion) > 0;
  const asset = selectAssetForPlatform(release.assets || [], platform, env);
  const checksumAsset = selectChecksumAsset(release.assets || []);

  return {
    available: Boolean(isNewer && asset),
    currentVersion,
    latestVersion,
    releaseUrl:
      release.html_url ||
      `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest`,
    notes: release.body || "",
    asset: asset
      ? {
          name: asset.name,
          url: asset.browser_download_url,
          size: asset.size || 0,
        }
      : null,
    checksumAsset: checksumAsset
      ? {
          name: checksumAsset.name,
          url: checksumAsset.browser_download_url,
        }
      : null,
  };
}

/**
 * Downloads a release asset URL to `destPath`, following GitHub redirects and reporting progress (0..100).
 */
function downloadFileWithProgress(url, destPath, onProgress, maxRedirects = 6) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https:") ? https : http;
    const req = client.get(
      url,
      {
        headers: {
          "User-Agent": "OrbitHUD-AutoUpdater",
          Accept: "application/octet-stream",
        },
        timeout: 30000,
      },
      (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          maxRedirects > 0
        ) {
          res.resume();
          resolve(
            downloadFileWithProgress(
              res.headers.location,
              destPath,
              onProgress,
              maxRedirects - 1
            )
          );
          return;
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          res.resume();
          reject(new Error(`Download failed with HTTP ${res.statusCode}`));
          return;
        }

        const totalBytes = parseInt(res.headers["content-length"] || "0", 10);
        let receivedBytes = 0;
        let lastReported = -1;

        fs.mkdirSync(path.dirname(destPath), { recursive: true });
        const fileStream = fs.createWriteStream(destPath);

        res.on("data", (chunk) => {
          receivedBytes += chunk.length;
          if (totalBytes > 0 && typeof onProgress === "function") {
            const pct = Math.min(
              100,
              Math.round((receivedBytes / totalBytes) * 100)
            );
            if (pct !== lastReported) {
              lastReported = pct;
              onProgress(pct);
            }
          }
        });

        res.pipe(fileStream);

        fileStream.on("finish", () => {
          fileStream.close(() => {
            if (typeof onProgress === "function") onProgress(100);
            resolve(destPath);
          });
        });

        fileStream.on("error", (err) => {
          try {
            fs.unlinkSync(destPath);
          } catch {
            // ignore
          }
          reject(err);
        });
      }
    );

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy(new Error("Download timed out"));
    });
  });
}

/**
 * Installs the downloaded update automatically and relaunches OrbitHUD.
 * Returns `{ relaunching: true }` when the caller should call `app.quit()`.
 */
function installDownloadedUpdate(downloadedPath, platform = process.platform, env = process.env) {
  if (platform === "win32") {
    const portableTarget = env && env.PORTABLE_EXECUTABLE_FILE;
    if (portableTarget) {
      // Portable .exe: wait for current process to exit, swap binary, and relaunch
      const batPath = path.join(os.tmpdir(), `orbithud-update-${Date.now()}.bat`);
      const batContent = [
        "@echo off",
        "timeout /t 2 /nobreak > nul",
        `copy /Y "${downloadedPath}" "${portableTarget}" > nul`,
        `start "" "${portableTarget}"`,
        `del "${downloadedPath}" > nul 2>&1`,
        'del "%~f0" > nul 2>&1',
      ].join("\r\n");
      fs.writeFileSync(batPath, batContent, "utf8");
      const child = spawn("cmd.exe", ["/c", batPath], {
        detached: true,
        stdio: "ignore",
        windowsHide: true,
      });
      child.unref();
      return { relaunching: true };
    }

    // NSIS Setup .exe: run silently (/S); NSIS oneClick + runAfterFinish relaunches OrbitHUD automatically
    const child = spawn(downloadedPath, ["/S"], {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    });
    child.unref();
    return { relaunching: true };
  }

  if (platform === "linux") {
    const appImageTarget = env && env.APPIMAGE;
    if (appImageTarget && downloadedPath.endsWith(".AppImage")) {
      fs.chmodSync(downloadedPath, 0o755);
      const shPath = path.join(os.tmpdir(), `orbithud-update-${Date.now()}.sh`);
      const shContent = [
        "#!/bin/sh",
        "sleep 2",
        `mv -f "${downloadedPath}" "${appImageTarget}"`,
        `chmod +x "${appImageTarget}"`,
        `"${appImageTarget}" >/dev/null 2>&1 &`,
        `rm -f "${shPath}"`,
      ].join("\n");
      fs.writeFileSync(shPath, shContent, { mode: 0o755 });
      const child = spawn("/bin/sh", [shPath], {
        detached: true,
        stdio: "ignore",
      });
      child.unref();
      return { relaunching: true };
    }
    return { relaunching: false, openPath: downloadedPath };
  }

  if (platform === "darwin" && downloadedPath.endsWith(".zip")) {
    const shPath = path.join(os.tmpdir(), `orbithud-update-${Date.now()}.sh`);
    const extractDir = path.join(os.tmpdir(), `orbithud-extract-${Date.now()}`);
    const shContent = [
      "#!/bin/sh",
      "sleep 2",
      `mkdir -p "${extractDir}"`,
      `ditto -xk "${downloadedPath}" "${extractDir}"`,
      `if [ -d "${extractDir}/OrbitHUD.app" ]; then`,
      `  rm -rf "/Applications/OrbitHUD.app"`,
      `  mv "${extractDir}/OrbitHUD.app" "/Applications/OrbitHUD.app"`,
      `  open "/Applications/OrbitHUD.app"`,
      "fi",
      `rm -rf "${extractDir}" "${downloadedPath}" "${shPath}"`,
    ].join("\n");
    fs.writeFileSync(shPath, shContent, { mode: 0o755 });
    const child = spawn("/bin/sh", [shPath], {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
    return { relaunching: true };
  }

  return { relaunching: false, openPath: downloadedPath };
}

module.exports = {
  parseSemver,
  compareSemver,
  selectAssetForPlatform,
  selectChecksumAsset,
  fetchText,
  parseSha256Sums,
  computeFileSha256,
  verifyFileSha256,
  checkForUpdate,
  downloadFileWithProgress,
  installDownloadedUpdate,
};
