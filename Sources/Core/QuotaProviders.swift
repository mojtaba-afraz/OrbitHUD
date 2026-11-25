import Foundation
import Security
import CryptoKit

private func sha256Fingerprint(_ raw: String) -> String {
    let digest = SHA256.hash(data: Data(raw.utf8))
    return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
}

public enum QuotaProviderID: String, CaseIterable, Codable, Identifiable, Hashable {
    case antigravity = "antigravity"
    case claudeCode = "claude-code"
    case codex = "codex"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .antigravity: return "Antigravity"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex CLI"
        }
    }

    public var shortTabName: String {
        switch self {
        case .antigravity: return "Antigravity"
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        }
    }

    public var shortBadge: String {
        switch self {
        case .antigravity: return "AGY"
        case .claudeCode: return "CC"
        case .codex: return "CDX"
        }
    }

    public var defaultPollInterval: TimeInterval {
        switch self {
        case .antigravity: return 20
        case .claudeCode, .codex: return 90
        }
    }
}

public enum ProviderConnectionState: String, Codable, Equatable {
    case connected
    case authRequired
    case rateLimited
    case disconnected
}

public struct ProviderStatusInfo: Codable, Equatable {
    public let providerId: QuotaProviderID
    public let state: ProviderConnectionState
    public let message: String?

    public init(providerId: QuotaProviderID, state: ProviderConnectionState, message: String? = nil) {
        self.providerId = providerId
        self.state = state
        self.message = message
    }
}

public struct ExternalProviderFetchResult {
    public let groups: [QuotaGroup]
    public let status: ProviderStatusInfo
    public let retryAfterSeconds: TimeInterval

    public init(groups: [QuotaGroup], status: ProviderStatusInfo, retryAfterSeconds: TimeInterval = 0) {
        self.groups = groups
        self.status = status
        self.retryAfterSeconds = retryAfterSeconds
    }
}

// MARK: - Claude Code Quota Fetcher

public final class ClaudeCodeQuotaFetcher {
    public init() {}

    public func fetchLiveQuota() async -> ExternalProviderFetchResult {
        guard let token = discoverAccessToken() else {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(
                    providerId: .claudeCode,
                    state: .authRequired,
                    message: "Not signed in — run \"claude /login\""
                )
            )
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(providerId: .claudeCode, state: .disconnected, message: "Invalid endpoint")
            )
        }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(providerId: .claudeCode, state: .disconnected, message: "No HTTP response")
                )
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .claudeCode,
                        state: .authRequired,
                        message: "Session expired — run \"claude /login\""
                    ),
                    retryAfterSeconds: 120
                )
            }
            if http.statusCode == 429 {
                let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "300") ?? 300
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .claudeCode,
                        state: .rateLimited,
                        message: "Rate limited — backing off automatically"
                    ),
                    retryAfterSeconds: max(retry, 180)
                )
            }
            guard (200..<300).contains(http.statusCode),
                  let groups = Self.parseUsageJSON(data) else {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .claudeCode,
                        state: .disconnected,
                        message: "Claude Code usage unavailable"
                    )
                )
            }
            return ExternalProviderFetchResult(
                groups: groups,
                status: ProviderStatusInfo(providerId: .claudeCode, state: .connected)
            )
        } catch {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(
                    providerId: .claudeCode,
                    state: .disconnected,
                    message: "Claude Code endpoint unreachable"
                )
            )
        }
    }

    public func credentialFingerprint() -> String? {
        guard let token = discoverAccessToken() else { return nil }
        return sha256Fingerprint("claude:\(token)")
    }

    public func discoverAccessToken() -> String? {
        if let keychainRaw = readKeychainPassword(service: "Claude Code-credentials"),
           let token = Self.parseAccessToken(from: keychainRaw) {
            return token
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            home.appendingPathComponent(".claude/.credentials.json"),
            home.appendingPathComponent(".claude/credentials.json")
        ]
        for path in paths {
            if let raw = try? String(contentsOf: path, encoding: .utf8),
               let token = Self.parseAccessToken(from: raw) {
                return token
            }
        }
        return nil
    }

    private func readKeychainPassword(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func parseAccessToken(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any])
            ?? (json["oauth"] as? [String: Any])
            ?? json
        let token = (oauth["accessToken"] as? String)
            ?? (oauth["access_token"] as? String)
            ?? (json["accessToken"] as? String)
        guard let cleaned = token?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }

    public static func parseUsageJSON(_ data: Data) -> [QuotaGroup]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func makeBucket(id: String, window: String, dict: [String: Any]?) -> QuotaBucket? {
            guard let dict, let util = dict["utilization"] as? Double else { return nil }
            let used = util > 1.0 ? util / 100.0 : util
            let remaining = min(max(1.0 - used, 0.0), 1.0)
            let resetISO = (dict["resets_at"] as? String) ?? (dict["resetsAt"] as? String)
            let resetDate = resetISO.flatMap(parseISODate)
            return QuotaBucket(
                id: id,
                displayName: window == "5h" ? "5h limit" : "Weekly limit",
                window: window,
                remainingFraction: remaining,
                resetTime: resetDate
            )
        }

        var groups: [QuotaGroup] = []
        var primaryBuckets: [QuotaBucket] = []
        if let b5 = makeBucket(id: "claude-code-5h", window: "5h", dict: json["five_hour"] as? [String: Any]) {
            primaryBuckets.append(b5)
        }
        if let b7 = makeBucket(id: "claude-code-weekly", window: "weekly", dict: json["seven_day"] as? [String: Any]) {
            primaryBuckets.append(b7)
        }
        if !primaryBuckets.isEmpty {
            groups.append(
                QuotaGroup(
                    id: "claude-code::primary",
                    providerId: QuotaProviderID.claudeCode.rawValue,
                    displayName: "Claude Code",
                    buckets: primaryBuckets
                )
            )
        }

        if let sonnet = makeBucket(id: "claude-code-sonnet-wk", window: "weekly", dict: json["seven_day_sonnet"] as? [String: Any]) {
            groups.append(
                QuotaGroup(
                    id: "claude-code::sonnet",
                    providerId: QuotaProviderID.claudeCode.rawValue,
                    displayName: "Claude Sonnet",
                    buckets: [sonnet]
                )
            )
        }

        if let opus = makeBucket(id: "claude-code-opus-wk", window: "weekly", dict: json["seven_day_opus"] as? [String: Any]) {
            groups.append(
                QuotaGroup(
                    id: "claude-code::opus",
                    providerId: QuotaProviderID.claudeCode.rawValue,
                    displayName: "Claude Opus",
                    buckets: [opus]
                )
            )
        }

        return groups.isEmpty ? nil : groups
    }

    private static func parseISODate(_ iso: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: iso) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }
}

// MARK: - OpenAI Codex CLI Quota Fetcher

public final class CodexQuotaFetcher {
    public init() {}

    public func fetchLiveQuota() async -> ExternalProviderFetchResult {
        guard let creds = discoverCredentials() else {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(
                    providerId: .codex,
                    state: .authRequired,
                    message: "Not signed in — run \"codex login\""
                )
            )
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(providerId: .codex, state: .disconnected, message: "Invalid endpoint")
            )
        }

        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli/1.0", forHTTPHeaderField: "User-Agent")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(providerId: .codex, state: .disconnected, message: "No HTTP response")
                )
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .codex,
                        state: .authRequired,
                        message: "Session expired — run \"codex login\""
                    ),
                    retryAfterSeconds: 120
                )
            }
            if http.statusCode == 429 {
                let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "300") ?? 300
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .codex,
                        state: .rateLimited,
                        message: "Rate limited — backing off automatically"
                    ),
                    retryAfterSeconds: max(retry, 180)
                )
            }
            guard (200..<300).contains(http.statusCode),
                  let groups = Self.parseUsageJSON(data) else {
                return ExternalProviderFetchResult(
                    groups: [],
                    status: ProviderStatusInfo(
                        providerId: .codex,
                        state: .disconnected,
                        message: "Codex usage unavailable"
                    )
                )
            }
            return ExternalProviderFetchResult(
                groups: groups,
                status: ProviderStatusInfo(providerId: .codex, state: .connected)
            )
        } catch {
            return ExternalProviderFetchResult(
                groups: [],
                status: ProviderStatusInfo(
                    providerId: .codex,
                    state: .disconnected,
                    message: "Codex endpoint unreachable"
                )
            )
        }
    }

    public func credentialFingerprint() -> String? {
        guard let creds = discoverCredentials() else { return nil }
        return sha256Fingerprint("codex:\(creds.accountId ?? ""):\(creds.accessToken)")
    }

    public func discoverCredentials() -> (accessToken: String, accountId: String?)? {
        let codexHome: URL
        if let envHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !envHome.isEmpty {
            codexHome = URL(fileURLWithPath: envHome)
        } else {
            codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        }
        let authURL = codexHome.appendingPathComponent("auth.json")
        guard let raw = try? String(contentsOf: authURL, encoding: .utf8) else {
            return nil
        }
        return Self.parseCredentials(from: raw)
    }

    public static func parseCredentials(from raw: String) -> (accessToken: String, accountId: String?)? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tokens = (json["tokens"] as? [String: Any]) ?? json
        let token = (tokens["access_token"] as? String)
            ?? (tokens["accessToken"] as? String)
            ?? (json["OPENAI_ACCESS_TOKEN"] as? String)
        guard let cleaned = token?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        let accountId = (tokens["account_id"] as? String)
            ?? (tokens["accountId"] as? String)
            ?? (json["account_id"] as? String)
        return (cleaned, accountId)
    }

    public static func parseUsageJSON(_ data: Data, now: Date = Date()) -> [QuotaGroup]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rateLimit = (json["rate_limit"] as? [String: Any])
            ?? (json["rateLimit"] as? [String: Any])
            ?? json

        func makeBucket(id: String, fallbackWindow: String, dict: [String: Any]?) -> QuotaBucket? {
            guard let dict else { return nil }
            let used: Double? = (dict["used_percent"] as? Double)
                ?? (dict["usedPercent"] as? Double)
                ?? (dict["utilization"] as? Double)
            guard let usedVal = used else { return nil }

            let winSeconds = (dict["limit_window_seconds"] as? Double) ?? (dict["window_seconds"] as? Double)
            let window: String
            if let sec = winSeconds {
                if sec <= 21_600 { window = "5h" }
                else if sec <= 90_000 { window = "daily" }
                else { window = "weekly" }
            } else {
                window = fallbackWindow
            }

            let usedFrac = usedVal > 1.0 ? usedVal / 100.0 : usedVal
            let remaining = min(max(1.0 - usedFrac, 0.0), 1.0)

            var resetDate: Date? = nil
            if let resetEpoch = dict["reset_at"] as? Double {
                let seconds = resetEpoch > 1e12 ? resetEpoch / 1000.0 : resetEpoch
                resetDate = Date(timeIntervalSince1970: seconds)
            } else if let resetAfter = dict["reset_after_seconds"] as? Double {
                resetDate = now.addingTimeInterval(resetAfter)
            }

            return QuotaBucket(
                id: id,
                displayName: window == "5h" ? "5h limit" : "Weekly limit",
                window: window,
                remainingFraction: remaining,
                resetTime: resetDate
            )
        }

        var buckets: [QuotaBucket] = []
        if let p = makeBucket(
            id: "codex-5h",
            fallbackWindow: "5h",
            dict: (rateLimit["primary_window"] as? [String: Any]) ?? (rateLimit["primaryWindow"] as? [String: Any])
        ) {
            buckets.append(p)
        }
        if let s = makeBucket(
            id: "codex-weekly",
            fallbackWindow: "weekly",
            dict: (rateLimit["secondary_window"] as? [String: Any]) ?? (rateLimit["secondaryWindow"] as? [String: Any])
        ) {
            buckets.append(s)
        }

        guard !buckets.isEmpty else { return nil }
        let planType = (json["plan_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (planType != nil && !(planType!.isEmpty)) ? "Codex CLI (\(planType!))" : "Codex CLI"

        return [
            QuotaGroup(
                id: "codex::primary",
                providerId: QuotaProviderID.codex.rawValue,
                displayName: title,
                buckets: buckets
            )
        ]
    }
}
