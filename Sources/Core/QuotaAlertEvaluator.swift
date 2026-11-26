import Foundation

public struct QuotaAlertConfig: Equatable, Codable, Sendable {
    public static let thresholdPresets: [Int] = [20, 15, 10, 5]

    public var enabled: Bool
    public var lowThresholdPercent: Int
    public var notifyOnReset: Bool

    public init(
        enabled: Bool = false,
        lowThresholdPercent: Int = 20,
        notifyOnReset: Bool = true
    ) {
        self.enabled = enabled
        self.lowThresholdPercent = min(max(lowThresholdPercent, 1), 99)
        self.notifyOnReset = notifyOnReset
    }
}

public enum QuotaAlertKind: String, Equatable, Codable, Sendable {
    case lowQuota
    case quotaReset
}

public struct QuotaAlertEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: QuotaAlertKind
    public let groupId: String
    public let bucketId: String
    public let title: String
    public let body: String

    public init(
        id: String,
        kind: QuotaAlertKind,
        groupId: String,
        bucketId: String,
        title: String,
        body: String
    ) {
        self.id = id
        self.kind = kind
        self.groupId = groupId
        self.bucketId = bucketId
        self.title = title
        self.body = body
    }
}

/// Pure, deterministic quota alert evaluator with baseline seeding and per-reset-cycle deduplication.
public final class QuotaAlertEvaluator {
    private struct BucketTrackState {
        var lastPercentage: Int
        var lastResetTime: Date?
        var hasAlertedLowInCycle: Bool
        var wasLowOrExhausted: Bool
    }

    private var states: [String: BucketTrackState] = [:]

    public init() {}

    public func reset() {
        states.removeAll()
    }

    /// Evaluates the current visible/enabled quota groups and returns any alerts that should fire.
    public func evaluate(
        groups: [QuotaGroup],
        config: QuotaAlertConfig,
        now: Date = Date()
    ) -> [QuotaAlertEvent] {
        var events: [QuotaAlertEvent] = []
        let threshold = min(max(config.lowThresholdPercent, 1), 99)

        for group in groups {
            for bucket in group.buckets {
                let key = "\(group.id)::\(bucket.id)"
                let pct = bucket.remainingPercentage

                guard var prev = states[key] else {
                    // Seed baseline on first observation without firing a launch alert.
                    // Record wasLowOrExhausted so a subsequent reset to 100% still notifies.
                    states[key] = BucketTrackState(
                        lastPercentage: pct,
                        lastResetTime: bucket.resetTime,
                        hasAlertedLowInCycle: pct <= threshold,
                        wasLowOrExhausted: pct <= threshold
                    )
                    continue
                }

                // Detect a new reset cycle if resetTime shifted forward by more than 10 minutes
                let cycleAdvanced: Bool = {
                    guard let oldReset = prev.lastResetTime, let newReset = bucket.resetTime else {
                        return false
                    }
                    return newReset.timeIntervalSince(oldReset) > 600
                }()

                if cycleAdvanced {
                    prev.hasAlertedLowInCycle = false
                }

                // 1. Check Reset-to-100% notification
                if pct >= 100 {
                    if config.enabled && config.notifyOnReset && prev.wasLowOrExhausted && prev.lastPercentage < 100 {
                        events.append(
                            QuotaAlertEvent(
                                id: "reset::\(key)::\(Int(now.timeIntervalSince1970))",
                                kind: .quotaReset,
                                groupId: group.id,
                                bucketId: bucket.id,
                                title: "Quota Reset: \(group.displayName)",
                                body: "\(bucket.windowLabel) is back to 100% remaining."
                            )
                        )
                    }
                    prev.hasAlertedLowInCycle = false
                    prev.wasLowOrExhausted = false
                } else if pct <= threshold {
                    // 2. Check Low-Quota notification (deduplicated per cycle)
                    let crossedDown = prev.lastPercentage > threshold || cycleAdvanced
                    if config.enabled && !prev.hasAlertedLowInCycle && crossedDown {
                        let resetSuffix: String = {
                            if let dur = bucket.formattedResetDuration(relativeTo: now) {
                                return " · Resets in \(dur)"
                            }
                            return ""
                        }()
                        events.append(
                            QuotaAlertEvent(
                                id: "low::\(key)::\(Int(now.timeIntervalSince1970))",
                                kind: .lowQuota,
                                groupId: group.id,
                                bucketId: bucket.id,
                                title: "Low Quota: \(group.displayName)",
                                body: "\(bucket.windowLabel) is at \(pct)% remaining\(resetSuffix)"
                            )
                        )
                        prev.hasAlertedLowInCycle = true
                    }
                    prev.wasLowOrExhausted = true
                }

                prev.lastPercentage = pct
                if let newReset = bucket.resetTime {
                    prev.lastResetTime = newReset
                }
                states[key] = prev
            }
        }

        return events
    }
}
