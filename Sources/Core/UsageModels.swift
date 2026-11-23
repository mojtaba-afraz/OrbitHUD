import Foundation

public enum WidgetDisplayMode: String, CaseIterable, Codable, Identifiable {
    case floatingHUD = "floating"
    case desktopPinned = "desktop"
    case both = "both"
    case menuBarOnly = "menubar"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .floatingHUD: return "Floating Widget"
        case .desktopPinned: return "Desktop Widget"
        case .both: return "Desktop + Floating"
        case .menuBarOnly: return "Menu Bar Only"
        }
    }

    public var iconName: String {
        switch self {
        case .floatingHUD: return "pip.swap"
        case .desktopPinned: return "macwindow.on.rectangle"
        case .both: return "square.on.square"
        case .menuBarOnly: return "menubar.rectangle"
        }
    }
}

public struct QuotaRingItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let remainingFraction: Double
    public let category: String

    public init(id: String, title: String, subtitle: String, remainingFraction: Double, category: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.remainingFraction = min(max(remainingFraction, 0.0), 1.0)
        self.category = category
    }

    public var remainingPercentage: Int {
        Int((remainingFraction * 100.0).rounded())
    }
}

public struct QuotaBucket: Identifiable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let window: String
    public let remainingFraction: Double
    public let resetTime: Date?

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        window: String,
        remainingFraction: Double,
        resetTime: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.window = window
        self.remainingFraction = min(max(remainingFraction, 0.0), 1.0)
        self.resetTime = resetTime
    }

    public var remainingPercentage: Int {
        Int((remainingFraction * 100.0).rounded())
    }

    public var windowLabel: String {
        switch window.lowercased() {
        case "weekly":
            return "Weekly limit"
        case "5h", "5hr", "five_hour":
            return "5h limit"
        case "daily":
            return "Daily limit"
        default:
            return window.isEmpty ? displayName : "\(window) limit"
        }
    }

    /// Formats reset time identically to the Antigravity Usage popup: e.g. "6d 1h", "3h 10m", "6d 22h".
    public func formattedResetDuration(relativeTo now: Date = Date()) -> String? {
        guard let resetTime else { return nil }
        let totalSeconds = Int(resetTime.timeIntervalSince(now))
        guard totalSeconds > 0 else { return "soon" }

        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(max(minutes, 1))m"
        }
    }

    public func formattedResetLine(relativeTo now: Date = Date()) -> String? {
        guard remainingPercentage < 100, let duration = formattedResetDuration(relativeTo: now) else {
            return nil
        }
        return "Resets in \(duration)"
    }

    public func formattedInlineSubtitle(relativeTo now: Date = Date()) -> String {
        if remainingPercentage < 100, let duration = formattedResetDuration(relativeTo: now) {
            return "\(windowLabel), resets in \(duration)"
        }
        return windowLabel
    }
}

public struct QuotaGroup: Identifiable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let buckets: [QuotaBucket]

    public init(id: String, displayName: String, description: String? = nil, buckets: [QuotaBucket]) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.buckets = buckets
    }
}

public struct ModelQuotaInfo: Identifiable, Codable, Equatable {
    public let id: String
    public let label: String
    public let remainingFraction: Double
    public let resetTime: Date?
    public let isActive: Bool

    public init(id: String, label: String, remainingFraction: Double, resetTime: Date?, isActive: Bool = false) {
        self.id = id
        self.label = label
        self.remainingFraction = min(max(remainingFraction, 0.0), 1.0)
        self.resetTime = resetTime
        self.isActive = isActive
    }

    public var remainingPercentage: Int {
        Int((remainingFraction * 100.0).rounded())
    }
}

public struct DailyTokenBucket: Identifiable, Codable, Equatable {
    public let id: String
    public let date: Date
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var stepCount: Int

    public init(id: String, date: Date, inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, stepCount: Int = 0) {
        self.id = id
        self.date = date
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.stepCount = stepCount
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens
    }
}

public struct ModelTokenBreakdown: Identifiable, Codable, Equatable {
    public let id: String
    public var modelName: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var stepCount: Int

    public init(id: String, modelName: String, inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, stepCount: Int = 0) {
        self.id = id
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.stepCount = stepCount
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens
    }
}

public struct TokenUsageSummary: Codable, Equatable {
    public var todayInputTokens: Int
    public var todayOutputTokens: Int
    public var todayCacheReadTokens: Int
    public var todayStepCount: Int
    public var sevenDayTotalTokens: Int
    public var activeModelName: String?
    public var dailyBuckets: [DailyTokenBucket]
    public var modelBreakdowns: [ModelTokenBreakdown]
    public var scannedConversationsCount: Int

    public init(
        todayInputTokens: Int = 0,
        todayOutputTokens: Int = 0,
        todayCacheReadTokens: Int = 0,
        todayStepCount: Int = 0,
        sevenDayTotalTokens: Int = 0,
        activeModelName: String? = nil,
        dailyBuckets: [DailyTokenBucket] = [],
        modelBreakdowns: [ModelTokenBreakdown] = [],
        scannedConversationsCount: Int = 0
    ) {
        self.todayInputTokens = todayInputTokens
        self.todayOutputTokens = todayOutputTokens
        self.todayCacheReadTokens = todayCacheReadTokens
        self.todayStepCount = todayStepCount
        self.sevenDayTotalTokens = sevenDayTotalTokens
        self.activeModelName = activeModelName
        self.dailyBuckets = dailyBuckets
        self.modelBreakdowns = modelBreakdowns
        self.scannedConversationsCount = scannedConversationsCount
    }

    public var todayTotalTokens: Int {
        todayInputTokens + todayOutputTokens + todayCacheReadTokens
    }
}

public struct AntigravityUsageSnapshot: Codable, Equatable {
    public var timestamp: Date
    public var isLanguageServerConnected: Bool
    public var quotaGroups: [QuotaGroup]
    public var modelQuotas: [ModelQuotaInfo]
    public var tokenUsage: TokenUsageSummary
    public var statusMessage: String

    public init(
        timestamp: Date = Date(),
        isLanguageServerConnected: Bool = false,
        quotaGroups: [QuotaGroup] = [],
        modelQuotas: [ModelQuotaInfo] = [],
        tokenUsage: TokenUsageSummary = TokenUsageSummary(),
        statusMessage: String = "Ready"
    ) {
        self.timestamp = timestamp
        self.isLanguageServerConnected = isLanguageServerConnected
        self.quotaGroups = quotaGroups
        self.modelQuotas = modelQuotas
        self.tokenUsage = tokenUsage
        self.statusMessage = statusMessage
    }

    /// Returns the live primary quota percentage (Gemini 5h limit, matching the main ring on the widget).
    public var primaryQuotaPercentage: Int? {
        if let geminiGroup = quotaGroups.first(where: {
            let l = $0.displayName.lowercased()
            return l.contains("gemini") && !l.contains("argon")
        }) ?? quotaGroups.first {
            if let fiveH = geminiGroup.buckets.first(where: { $0.window.lowercased() == "5h" }) {
                return fiveH.remainingPercentage
            }
            if let minBucket = geminiGroup.buckets.min(by: { $0.remainingFraction < $1.remainingFraction }) {
                return minBucket.remainingPercentage
            }
        }
        return modelQuotas.first?.remainingPercentage
    }

    /// Maps the raw quota groups into clean ring items (including both 5h and Weekly for Gemini and Claude/GPT).
    public func iosRingItems(relativeTo now: Date = Date()) -> [QuotaRingItem] {
        var items: [QuotaRingItem] = []

        for group in quotaGroups {
            let lowerName = group.displayName.lowercased()

            if lowerName.contains("gemini models") || (lowerName.contains("gemini") && !lowerName.contains("argon")) {
                let sortedBuckets = group.buckets.sorted { a, _ in a.window.lowercased() == "5h" }
                for bucket in sortedBuckets {
                    let is5h = bucket.window.lowercased() == "5h"
                    let title = is5h ? "Gemini 5h" : "Gemini Wk"
                    let sub: String
                    if bucket.remainingPercentage < 100, let dur = bucket.formattedResetDuration(relativeTo: now) {
                        sub = "↻ \(dur)"
                    } else {
                        sub = is5h ? "5h limit" : "Weekly"
                    }
                    items.append(
                        QuotaRingItem(
                            id: bucket.id,
                            title: title,
                            subtitle: sub,
                            remainingFraction: bucket.remainingFraction,
                            category: "gemini"
                        )
                    )
                }
            } else if lowerName.contains("argon") {
                if let bucket = group.buckets.first {
                    let sub: String
                    if bucket.remainingPercentage < 100, let dur = bucket.formattedResetDuration(relativeTo: now) {
                        sub = "↻ \(dur)"
                    } else {
                        sub = "Weekly"
                    }
                    items.append(
                        QuotaRingItem(
                            id: bucket.id,
                            title: "Argon 4",
                            subtitle: sub,
                            remainingFraction: bucket.remainingFraction,
                            category: "argon"
                        )
                    )
                }
            } else if lowerName.contains("claude") || lowerName.contains("gpt") {
                let sortedBuckets = group.buckets.sorted { a, _ in a.window.lowercased() == "5h" }
                for bucket in sortedBuckets {
                    let is5h = bucket.window.lowercased() == "5h"
                    let title = is5h ? "Claude 5h" : "Claude Wk"
                    let sub: String
                    if bucket.remainingPercentage < 100, let dur = bucket.formattedResetDuration(relativeTo: now) {
                        sub = "↻ \(dur)"
                    } else {
                        sub = "Full"
                    }
                    items.append(
                        QuotaRingItem(
                            id: bucket.id,
                            title: title,
                            subtitle: sub,
                            remainingFraction: bucket.remainingFraction,
                            category: "claude"
                        )
                    )
                }
            } else {
                for bucket in group.buckets {
                    let sub = bucket.formattedResetDuration(relativeTo: now).map { "↻ \($0)" } ?? bucket.windowLabel
                    items.append(
                        QuotaRingItem(
                            id: bucket.id,
                            title: group.displayName,
                            subtitle: sub,
                            remainingFraction: bucket.remainingFraction,
                            category: "other"
                        )
                    )
                }
            }
        }

        return items
    }
}

public enum TokenFormatter {
    public static func format(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000_000.0)
        } else {
            return "\(count)"
        }
    }

    public static func humanReadableModelName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("argon") {
            return "Gemini 4 Argon"
        } else if lower.contains("gemini-2.5-pro") || lower.contains("gemini-pro") {
            return "Gemini Pro"
        } else if lower.contains("flash-lite") {
            return "Gemini Flash Lite"
        } else if lower.contains("flash") {
            return "Gemini Flash"
        } else if lower.contains("claude") && lower.contains("sonnet") {
            return "Claude Sonnet"
        } else if lower.contains("claude") && lower.contains("opus") {
            return "Claude Opus"
        }
        return raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
