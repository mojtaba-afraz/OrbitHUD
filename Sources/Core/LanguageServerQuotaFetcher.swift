import Foundation

public struct LanguageServerConnection: Codable, Equatable, Hashable {
    public let port: Int
    public let csrfToken: String

    public init(port: Int, csrfToken: String) {
        self.port = port
        self.csrfToken = csrfToken
    }
}

public final class LanguageServerQuotaFetcher: NSObject, URLSessionDelegate {
    private lazy var localSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 4.0
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == "127.0.0.1" || challenge.protectionSpace.host == "localhost",
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    public static var cachedConnectionURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("AntigravityUsageWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ls_connection.json")
    }

    public static func saveCachedConnection(_ conn: LanguageServerConnection) {
        if let data = try? JSONEncoder().encode(conn) {
            try? data.write(to: cachedConnectionURL, options: .atomic)
        }
    }

    public static func loadCachedConnection() -> LanguageServerConnection? {
        guard let data = try? Data(contentsOf: cachedConnectionURL) else { return nil }
        return try? JSONDecoder().decode(LanguageServerConnection.self, from: data)
    }

    /// Parses output of `ps auxeww` (which includes CLI flags and environment variables for user processes)
    /// to extract active Antigravity language server / hub `(port, csrfToken)` pairs.
    public static func parseConnectionsFromPsOutput(_ psOutput: String) -> [LanguageServerConnection] {
        var ports: [Int] = []
        var tokens: [String] = []
        var paired: [LanguageServerConnection] = []

        let portPatterns = [
            #"ANTIGRAVITY_LS_ADDRESS=(?:https?://)?(?:localhost|127\.0\.0\.1):(\d+)"#,
            #"--hub-port=(\d+)"#,
            #"--hub-port\s+(\d+)"#,
            #"--https_server_port=(\d+)"#,
            #"--https_server_port\s+(\d+)"#
        ]
        let tokenPatterns = [
            #"ANTIGRAVITY_SERVER_CSRF_TOKEN=([A-Za-z0-9_\-]+)"#,
            #"ANTIGRAVITY_CSRF_TOKEN=([A-Za-z0-9_\-]+)"#,
            #"--csrf_token=([A-Za-z0-9_\-]+)"#,
            #"--csrf_token\s+([A-Za-z0-9_\-]+)"#
        ]

        let compiledPortRegexes = portPatterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let compiledTokenRegexes = tokenPatterns.compactMap { try? NSRegularExpression(pattern: $0) }

        for line in psOutput.components(separatedBy: .newlines) {
            guard line.contains("ANTIGRAVITY") || line.contains("agy") || line.contains("language_server") || line.contains("csrf_token") || line.contains("hub-port") else {
                continue
            }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            var linePorts: [Int] = []
            var lineTokens: [String] = []

            for regex in compiledPortRegexes {
                for match in regex.matches(in: line, range: nsRange) {
                    if match.numberOfRanges > 1,
                       let r = Range(match.range(at: 1), in: line),
                       let port = Int(line[r]), port > 1024 {
                        if !linePorts.contains(port) { linePorts.append(port) }
                        if !ports.contains(port) { ports.append(port) }
                    }
                }
            }

            for regex in compiledTokenRegexes {
                for match in regex.matches(in: line, range: nsRange) {
                    if match.numberOfRanges > 1,
                       let r = Range(match.range(at: 1), in: line) {
                        let tok = String(line[r])
                        if !tok.isEmpty && tok != "REDACTED" {
                            if !lineTokens.contains(tok) { lineTokens.append(tok) }
                            if !tokens.contains(tok) { tokens.append(tok) }
                        }
                    }
                }
            }

            for p in linePorts {
                for t in lineTokens {
                    let conn = LanguageServerConnection(port: p, csrfToken: t)
                    if !paired.contains(conn) {
                        paired.append(conn)
                    }
                }
            }
        }

        // Also combine any discovered ports and tokens across parent/child lines
        for p in ports {
            for t in tokens {
                let conn = LanguageServerConnection(port: p, csrfToken: t)
                if !paired.contains(conn) {
                    paired.append(conn)
                }
            }
        }

        return paired
    }

    /// Parses the JSON response from `/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`.
    public static func parseRetrieveUserQuotaSummaryJSON(_ data: Data) -> [QuotaGroup]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let responseObj = (root["response"] as? [String: Any]) ?? root
        guard let rawGroups = responseObj["groups"] as? [[String: Any]], !rawGroups.isEmpty else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackIsoFormatter = ISO8601DateFormatter()

        var parsedGroups: [QuotaGroup] = []

        for (gIdx, rawGroup) in rawGroups.enumerated() {
            let groupName = (rawGroup["displayName"] as? String)
                ?? (rawGroup["display_name"] as? String)
                ?? "Group \(gIdx + 1)"
            let groupDesc = (rawGroup["description"] as? String)
            let rawBuckets = (rawGroup["buckets"] as? [[String: Any]]) ?? []

            var parsedBuckets: [QuotaBucket] = []
            for (bIdx, rawBucket) in rawBuckets.enumerated() {
                let bucketId = (rawBucket["bucketId"] as? String)
                    ?? (rawBucket["bucket_id"] as? String)
                    ?? "\(groupName)-\(bIdx)"
                let bucketName = (rawBucket["displayName"] as? String)
                    ?? (rawBucket["display_name"] as? String)
                    ?? bucketId
                let bucketDesc = rawBucket["description"] as? String
                let window = (rawBucket["window"] as? String) ?? ""

                let remaining: Double
                if let rem = rawBucket["remainingFraction"] as? Double {
                    remaining = rem
                } else if let remNum = rawBucket["remainingFraction"] as? NSNumber {
                    remaining = remNum.doubleValue
                } else if let rem = rawBucket["remaining_fraction"] as? Double {
                    remaining = rem
                } else if let remNum = rawBucket["remaining_fraction"] as? NSNumber {
                    remaining = remNum.doubleValue
                } else {
                    let isDisabled = (rawBucket["disabled"] as? Bool) ?? false
                    remaining = isDisabled ? 0.0 : 1.0
                }

                var resetDate: Date?
                if let resetStr = (rawBucket["resetTime"] as? String) ?? (rawBucket["reset_time"] as? String) {
                    resetDate = isoFormatter.date(from: resetStr) ?? fallbackIsoFormatter.date(from: resetStr)
                }

                parsedBuckets.append(
                    QuotaBucket(
                        id: bucketId,
                        displayName: bucketName,
                        description: bucketDesc,
                        window: window,
                        remainingFraction: remaining,
                        resetTime: resetDate
                    )
                )
            }

            if !parsedBuckets.isEmpty {
                parsedGroups.append(
                    QuotaGroup(
                        id: groupName,
                        displayName: groupName,
                        description: groupDesc,
                        buckets: parsedBuckets
                    )
                )
            }
        }

        return parsedGroups.isEmpty ? nil : parsedGroups
    }

    public func fetchLiveQuotaGroups() async -> [QuotaGroup]? {
        var candidates: [LanguageServerConnection] = []

        // 1. Check current environment variables if launched from Antigravity
        let env = ProcessInfo.processInfo.environment
        if let addr = env["ANTIGRAVITY_LS_ADDRESS"],
           let portStr = addr.split(separator: ":").last,
           let port = Int(portStr),
           let token = env["ANTIGRAVITY_CSRF_TOKEN"] ?? env["ANTIGRAVITY_SERVER_CSRF_TOKEN"] {
            candidates.append(LanguageServerConnection(port: port, csrfToken: token))
        }

        // 2. Check Antigravity daemon discovery files (~/.gemini/antigravity/daemon/*.json)
        for daemonConn in Self.discoverConnectionsFromDaemonFiles() {
            if !candidates.contains(daemonConn) {
                candidates.append(daemonConn)
            }
        }

        // 3. Check cached connection from disk
        if let cached = Self.loadCachedConnection(), !candidates.contains(cached) {
            candidates.append(cached)
        }

        // 4. Discover from `ps auxeww`
        for discovered in discoverConnectionsFromPs() {
            if !candidates.contains(discovered) {
                candidates.append(discovered)
            }
        }

        for candidate in candidates {
            for scheme in ["http", "https"] {
                if let groups = await queryQuotaSummary(scheme: scheme, connection: candidate) {
                    Self.saveCachedConnection(candidate)
                    return groups
                }
            }
        }

        return nil
    }

    public static func discoverConnectionsFromDaemonFiles() -> [LanguageServerConnection] {
        var results: [LanguageServerConnection] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [
            home.appendingPathComponent(".gemini/antigravity/daemon"),
            home.appendingPathComponent(".gemini/antigravity-ide/daemon"),
            home.appendingPathComponent(".gemini/antigravity-cli/daemon")
        ]
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                continue
            }
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = (obj["csrfToken"] as? String) ?? (obj["csrf_token"] as? String),
                      !token.isEmpty, token != "REDACTED" else {
                    continue
                }
                for key in ["httpsPort", "httpPort", "port", "hubPort", "lspPort"] {
                    if let port = obj[key] as? Int, port > 1024 {
                        let conn = LanguageServerConnection(port: port, csrfToken: token)
                        if !results.contains(conn) {
                            results.append(conn)
                        }
                    }
                }
            }
        }
        return results
    }

    private func discoverConnectionsFromPs() -> [LanguageServerConnection] {
        var all: [LanguageServerConnection] = []
        for args in [["auxeww"], ["efww"]] {
            if let out = Self.runCommand("/bin/ps", arguments: args) {
                for conn in Self.parseConnectionsFromPsOutput(out) {
                    if !all.contains(conn) {
                        all.append(conn)
                    }
                }
            }
        }
        return all
    }

    private func queryQuotaSummary(scheme: String, connection: LanguageServerConnection, forceRefresh: Bool = true) async -> [QuotaGroup]? {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(connection.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(connection.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data((forceRefresh ? "{\"forceRefresh\":true}" : "{}").utf8)

        do {
            let (data, response) = try await localSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                if forceRefresh {
                    return await queryQuotaSummary(scheme: scheme, connection: connection, forceRefresh: false)
                }
                return nil
            }
            return Self.parseRetrieveUserQuotaSummaryJSON(data)
        } catch {
            return nil
        }
    }

    private static func runCommand(_ launchPath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
