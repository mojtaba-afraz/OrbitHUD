import Foundation
import CryptoKit

// MARK: - Models

public struct UpdateAssetInfo: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let size: Int64

    public init(name: String, downloadURL: URL, size: Int64 = 0) {
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
    }
}

public struct UpdateReleaseInfo: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String
    public let releaseURL: URL
    public let notes: String
    public let asset: UpdateAssetInfo
    public let checksumAsset: UpdateAssetInfo?

    public init(
        currentVersion: String,
        latestVersion: String,
        releaseURL: URL,
        notes: String,
        asset: UpdateAssetInfo,
        checksumAsset: UpdateAssetInfo?
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.notes = notes
        self.asset = asset
        self.checksumAsset = checksumAsset
    }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(version: String)
    case available(UpdateReleaseInfo)
    case downloading(version: String, progress: Int)
    case verifying(version: String)
    case installing(version: String)
    case error(message: String, releaseURL: URL?)

    public var isBannerRelevant: Bool {
        switch self {
        case .available, .downloading, .verifying, .installing, .error:
            return true
        case .idle, .checking, .upToDate:
            return false
        }
    }
}

public enum AutoUpdaterError: LocalizedError, Equatable {
    case invalidResponse(Int)
    case invalidReleasePayload
    case missingChecksumAsset
    case missingChecksumEntry(String)
    case invalidChecksumFormat
    case checksumMismatch(expectedPrefix: String, actualPrefix: String)
    case downloadFailed(String)
    case installLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code):
            return "GitHub API returned HTTP \(code)"
        case .invalidReleasePayload:
            return "Unable to parse release information"
        case .missingChecksumAsset:
            return "Release is missing SHA256SUMS.txt"
        case .missingChecksumEntry(let name):
            return "No SHA256 checksum found for \(name)"
        case .invalidChecksumFormat:
            return "Invalid SHA256 checksum format"
        case .checksumMismatch(let expectedPrefix, let actualPrefix):
            return "SHA256 mismatch (expected \(expectedPrefix)..., got \(actualPrefix)...)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .installLaunchFailed(let reason):
            return "Failed to launch updater: \(reason)"
        }
    }
}

// MARK: - AutoUpdater Engine

public enum AutoUpdater {
    public static let repoOwner = "mojtaba-afraz"
    public static let repoName = "OrbitHUD"
    public static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    public static let fallbackReleasePageURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!
    public static let userAgent = "OrbitHUD-AutoUpdater"

    // MARK: Semver

    /// Parses a semver string like "v1.2.5" or "1.3.0-beta.1" into (major, minor, patch).
    public static func parseSemver(_ version: String) -> (Int, Int, Int) {
        var cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        if let dashIndex = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[..<dashIndex])
        }
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }
        let parts = cleaned.split(separator: ".").map { Int($0) ?? 0 }
        let major = parts.count > 0 ? parts[0] : 0
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0
        return (major, minor, patch)
    }

    /// Returns > 0 if `lhs > rhs`, < 0 if `lhs < rhs`, or 0 if equal.
    public static func compareSemver(_ lhs: String, _ rhs: String) -> Int {
        let a = parseSemver(lhs)
        let b = parseSemver(rhs)
        if a.0 != b.0 { return a.0 - b.0 }
        if a.1 != b.1 { return a.1 - b.1 }
        if a.2 != b.2 { return a.2 - b.2 }
        return 0
    }

    // MARK: Asset Selection

    /// Picks the macOS `.zip` asset (preferring `OrbitHUD-macOS.zip`).
    public static func selectMacOSAsset(from assets: [UpdateAssetInfo]) -> UpdateAssetInfo? {
        if let exact = assets.first(where: { $0.name.caseInsensitiveCompare("OrbitHUD-macOS.zip") == .orderedSame }) {
            return exact
        }
        if let macZip = assets.first(where: {
            let lower = $0.name.lowercased()
            return lower.contains("macos") && lower.hasSuffix(".zip")
        }) {
            return macZip
        }
        return assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
    }

    /// Finds the `SHA256SUMS.txt` (or `SHA256SUMS`) asset in a release.
    public static func selectChecksumAsset(from assets: [UpdateAssetInfo]) -> UpdateAssetInfo? {
        assets.first { asset in
            let trimmed = asset.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "sha256sums.txt" || trimmed == "sha256sums"
        }
    }

    // MARK: SHA256 Parsing & Verification

    /// Parses standard `sha256sum` output (`<64-hex>  <filename>` or `<64-hex> *<filename>`)
    /// into a dictionary mapping file basenames to lowercase 64-char hex digests.
    public static func parseSha256Sums(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Split on first whitespace run
            guard let firstSpace = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                continue
            }
            let hashPart = String(line[..<firstSpace])
            guard isValidSha256Hex(hashPart) else { continue }

            var namePart = String(line[firstSpace...]).trimmingCharacters(in: .whitespaces)
            if namePart.hasPrefix("*") {
                namePart.removeFirst()
            }
            if namePart.hasPrefix("./") {
                namePart.removeFirst(2)
            }
            let normalizedPath = namePart.replacingOccurrences(of: "\\", with: "/")
            let baseName = (normalizedPath as NSString).lastPathComponent
            if !baseName.isEmpty {
                result[baseName] = hashPart.lowercased()
            }
        }
        return result
    }

    public static func isValidSha256Hex(_ hex: String) -> Bool {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else { return false }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || // 0-9
            (scalar.value >= 65 && scalar.value <= 70) || // A-F
            (scalar.value >= 97 && scalar.value <= 102)   // a-f
        }
    }

    /// Computes lowercase hex SHA256 digest of a file on disk using streaming reads.
    public static func computeFileSha256(at fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 65_536) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies a downloaded file against an expected 64-char hex SHA256 digest.
    /// Deletes the file immediately on mismatch or invalid hash format.
    @discardableResult
    public static func verifyFileSha256(at fileURL: URL, expectedHash: String) throws -> String {
        let cleanup = {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let normalizedExpected = expectedHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let expectedBytes = hexToBytes(normalizedExpected), expectedBytes.count == 32 else {
            cleanup()
            throw AutoUpdaterError.invalidChecksumFormat
        }

        let actualHex: String
        do {
            actualHex = try computeFileSha256(at: fileURL)
        } catch {
            cleanup()
            throw error
        }

        guard let actualBytes = hexToBytes(actualHex), actualBytes.count == 32 else {
            cleanup()
            throw AutoUpdaterError.invalidChecksumFormat
        }

        var diff: UInt8 = 0
        for (a, b) in zip(expectedBytes, actualBytes) {
            diff |= (a ^ b)
        }

        if diff != 0 {
            cleanup()
            throw AutoUpdaterError.checksumMismatch(
                expectedPrefix: String(normalizedExpected.prefix(12)),
                actualPrefix: String(actualHex.prefix(12))
            )
        }

        return actualHex
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count == 64 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = hex.startIndex
        for _ in 0..<32 {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    // MARK: Networking

    private struct GitHubReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int64?
        }

        let tag_name: String
        let html_url: String?
        let body: String?
        let assets: [Asset]?
    }

    /// Checks GitHub Releases for a newer version than `currentVersion`.
    /// Returns `UpdateReleaseInfo` if a newer version with a macOS `.zip` asset is available, or `nil` if up to date.
    public static func checkForUpdate(
        currentVersion: String,
        apiURL: URL = latestReleaseAPIURL,
        session: URLSession = .shared
    ) async throws -> UpdateReleaseInfo? {
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AutoUpdaterError.invalidReleasePayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw AutoUpdaterError.invalidResponse(http.statusCode)
        }

        let payload: GitHubReleasePayload
        do {
            payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw AutoUpdaterError.invalidReleasePayload
        }

        let latestVersion = payload.tag_name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)

        guard compareSemver(latestVersion, currentVersion) > 0 else {
            return nil
        }

        let mappedAssets: [UpdateAssetInfo] = (payload.assets ?? []).compactMap { raw in
            guard let url = URL(string: raw.browser_download_url) else { return nil }
            return UpdateAssetInfo(name: raw.name, downloadURL: url, size: raw.size ?? 0)
        }

        guard let macAsset = selectMacOSAsset(from: mappedAssets) else {
            return nil
        }

        let checksumAsset = selectChecksumAsset(from: mappedAssets)
        let releaseURL = payload.html_url.flatMap(URL.init(string:)) ?? fallbackReleasePageURL

        return UpdateReleaseInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: releaseURL,
            notes: payload.body ?? "",
            asset: macAsset,
            checksumAsset: checksumAsset
        )
    }

    /// Fetches UTF-8 text from a URL (used for `SHA256SUMS.txt`).
    public static func fetchText(from url: URL, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/octet-stream, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AutoUpdaterError.invalidReleasePayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw AutoUpdaterError.invalidResponse(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AutoUpdaterError.invalidReleasePayload
        }
        return text
    }

    /// Downloads a release asset to `destinationURL`, reporting throttled progress (0...100).
    public static func downloadAsset(
        from url: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destinationURL)

        let delegate = AssetDownloadDelegate(destinationURL: destinationURL, onProgress: onProgress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        return try await withCheckedThrowingContinuation { continuation in
            delegate.setContinuation(continuation, session: session)
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    // MARK: App Replacement & Detached Relaunch

    /// Resolves the `.app` bundle path to replace. Uses the currently running `.app` bundle if
    /// writable (e.g. `/Applications/OrbitHUD.app` or `~/Applications/OrbitHUD.app`), otherwise
    /// falls back to `/Applications/OrbitHUD.app`.
    public static func resolveTargetAppBundlePath(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        let path = bundleURL.path
        if bundleURL.pathExtension.lowercased() == "app",
           !path.hasPrefix("/Volumes/"),
           fileManager.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) {
            return path
        }
        return "/Applications/OrbitHUD.app"
    }

    /// Escapes a string for safe inclusion as a POSIX single-quoted shell argument.
    public static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Builds a detached POSIX `/bin/sh` script that waits for `pid` to exit, extracts the verified
    /// `.zip` via `ditto`, swaps `OrbitHUD.app` with rollback protection, strips quarantine xattrs,
    /// relaunches OrbitHUD, and removes temporary files.
    public static func buildMacOSInstallScript(
        downloadedZipPath: String,
        extractDir: String,
        targetAppPath: String,
        pid: Int32,
        scriptPath: String
    ) -> String {
        let qZip = shellSingleQuote(downloadedZipPath)
        let qExtract = shellSingleQuote(extractDir)
        let qTarget = shellSingleQuote(targetAppPath)
        let qBackup = shellSingleQuote(targetAppPath + ".backup")
        let qScript = shellSingleQuote(scriptPath)

        var lines: [String] = ["#!/bin/sh"]
        if pid > 0 {
            lines.append("WAIT_COUNT=0")
            lines.append("while kill -0 \(pid) 2>/dev/null && [ \"$WAIT_COUNT\" -lt 15 ]; do")
            lines.append("  sleep 1")
            lines.append("  WAIT_COUNT=$((WAIT_COUNT + 1))")
            lines.append("done")
        } else {
            lines.append("sleep 2")
        }

        lines.append(contentsOf: [
            "mkdir -p \(qExtract)",
            "if ditto -xk \(qZip) \(qExtract); then",
            "  NEW_APP=\(qExtract)'/OrbitHUD.app'",
            "  if [ -d \"$NEW_APP\" ]; then",
            "    xattr -dr com.apple.quarantine \"$NEW_APP\" 2>/dev/null || true",
            "    rm -rf \(qBackup)",
            "    if [ -d \(qTarget) ]; then",
            "      mv \(qTarget) \(qBackup)",
            "    fi",
            "    if mv \"$NEW_APP\" \(qTarget); then",
            "      rm -rf \(qBackup)",
            "      open -n \(qTarget)",
            "    elif [ -d \(qBackup) ]; then",
            "      mv \(qBackup) \(qTarget)",
            "    fi",
            "  fi",
            "fi",
            "rm -rf \(qExtract) \(qZip) \(qScript)"
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    /// Writes the detached macOS swap script to `/tmp` and launches it so the app can exit cleanly.
    public static func launchDetachedMacOSInstaller(
        downloadedZipURL: URL,
        targetAppPath: String = resolveTargetAppBundlePath(),
        pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let token = UUID().uuidString.prefix(8)
        let tempDir = FileManager.default.temporaryDirectory
        let extractDir = tempDir.appendingPathComponent("orbithud-extract-\(token)").path
        let scriptURL = tempDir.appendingPathComponent("orbithud-update-\(token).sh")

        let script = buildMacOSInstallScript(
            downloadedZipPath: downloadedZipURL.path,
            extractDir: extractDir,
            targetAppPath: targetAppPath,
            pid: pid,
            scriptPath: scriptURL.path
        )

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            throw AutoUpdaterError.installLaunchFailed(error.localizedDescription)
        }
    }
}

// MARK: - Download Progress Delegate

private final class AssetDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let onProgress: @Sendable (Int) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var lastReportedPercent: Int = -1
    private var finished = false

    init(destinationURL: URL, onProgress: @escaping @Sendable (Int) -> Void) {
        self.destinationURL = destinationURL
        self.onProgress = onProgress
    }

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>, session: URLSession) {
        lock.lock()
        self.continuation = continuation
        self.session = session
        lock.unlock()
    }

    private func complete(with result: Result<URL, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let cont = continuation
        let sess = session
        continuation = nil
        session = nil
        lock.unlock()

        sess?.finishTasksAndInvalidate()
        switch result {
        case .success(let url):
            onProgress(100)
            cont?.resume(returning: url)
        case .failure(let error):
            cont?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = min(100, max(0, Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100.0).rounded())))
        lock.lock()
        let shouldReport = pct != lastReportedPercent
        if shouldReport {
            lastReportedPercent = pct
        }
        lock.unlock()
        if shouldReport {
            onProgress(pct)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            complete(with: .failure(AutoUpdaterError.downloadFailed("HTTP \(http.statusCode)")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            complete(with: .success(destinationURL))
        } catch {
            complete(with: .failure(AutoUpdaterError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(with: .failure(AutoUpdaterError.downloadFailed(error.localizedDescription)))
        }
    }
}
