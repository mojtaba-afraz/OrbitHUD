import Foundation

public struct ParsedTranscriptStep: Equatable {
    public let createdAt: Date
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int

    public init(createdAt: Date, model: String, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int) {
        self.createdAt = createdAt
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

public final class TranscriptUsageAggregator {
    private struct CachedTranscriptFile {
        let modificationDate: Date
        let fileSize: UInt64
        let steps: [ParsedTranscriptStep]
    }

    private var fileCache: [String: CachedTranscriptFile] = [:]
    private let brainDirectoryURL: URL

    public init(brainDirectoryURL: URL? = nil) {
        if let brainDirectoryURL {
            self.brainDirectoryURL = brainDirectoryURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.brainDirectoryURL = home
                .appendingPathComponent(".gemini")
                .appendingPathComponent("antigravity")
                .appendingPathComponent("brain")
        }
    }

    /// Parses the content of a single `transcript.jsonl` file and extracts token steps.
    public static func parseTranscriptJSONL(_ content: String) -> [ParsedTranscriptStep] {
        var steps: [ParsedTranscriptStep] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        for line in content.split(whereSeparator: \.isNewline) {
            // Fast pre-check before JSON deserialization
            guard line.contains("\"input_tokens\"") || line.contains("\"output_tokens\"") else {
                continue
            }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let inputTokens = (obj["input_tokens"] as? Int) ?? 0
            let outputTokens = (obj["output_tokens"] as? Int) ?? 0
            let cacheReadTokens = (obj["cache_read_tokens"] as? Int) ?? 0
            guard inputTokens > 0 || outputTokens > 0 || cacheReadTokens > 0 else {
                continue
            }

            let rawModel = (obj["model"] as? String) ?? "unknown"
            var date = Date()
            if let createdStr = obj["created_at"] as? String {
                date = isoFormatter.date(from: createdStr)
                    ?? fallbackFormatter.date(from: createdStr)
                    ?? Date()
            }

            steps.append(
                ParsedTranscriptStep(
                    createdAt: date,
                    model: rawModel,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens
                )
            )
        }
        return steps
    }

    /// Aggregates parsed steps into today's summary, 7-day daily buckets, and per-model breakdown.
    public static func aggregate(
        steps: [ParsedTranscriptStep],
        scannedConversationsCount: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenUsageSummary {
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let todayKey = dayFormatter.string(from: referenceDate)
        let startOfToday = calendar.startOfDay(for: referenceDate)

        // Pre-populate last 7 days buckets
        var bucketsByKey: [String: DailyTokenBucket] = [:]
        var orderedKeys: [String] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            if let dayDate = calendar.date(byAdding: .day, value: -offset, to: startOfToday) {
                let key = dayFormatter.string(from: dayDate)
                orderedKeys.append(key)
                bucketsByKey[key] = DailyTokenBucket(id: key, date: dayDate)
            }
        }

        var todayInput = 0
        var todayOutput = 0
        var todayCache = 0
        var todaySteps = 0
        var sevenDayTotal = 0

        var modelsByKey: [String: ModelTokenBreakdown] = [:]
        var latestStep: ParsedTranscriptStep?

        for step in steps {
            if latestStep == nil || step.createdAt > latestStep!.createdAt {
                latestStep = step
            }

            let stepKey = dayFormatter.string(from: step.createdAt)
            if stepKey == todayKey {
                todayInput += step.inputTokens
                todayOutput += step.outputTokens
                todayCache += step.cacheReadTokens
                todaySteps += 1
            }

            if var bucket = bucketsByKey[stepKey] {
                bucket.inputTokens += step.inputTokens
                bucket.outputTokens += step.outputTokens
                bucket.cacheReadTokens += step.cacheReadTokens
                bucket.stepCount += 1
                bucketsByKey[stepKey] = bucket
                sevenDayTotal += (step.inputTokens + step.outputTokens + step.cacheReadTokens)

                let readableModel = TokenFormatter.humanReadableModelName(step.model)
                var modelEntry = modelsByKey[readableModel] ?? ModelTokenBreakdown(id: readableModel, modelName: readableModel)
                modelEntry.inputTokens += step.inputTokens
                modelEntry.outputTokens += step.outputTokens
                modelEntry.cacheReadTokens += step.cacheReadTokens
                modelEntry.stepCount += 1
                modelsByKey[readableModel] = modelEntry
            }
        }

        let dailyBuckets = orderedKeys.compactMap { bucketsByKey[$0] }
        let sortedModels = modelsByKey.values.sorted { $0.totalTokens > $1.totalTokens }
        let activeModel = latestStep.map { TokenFormatter.humanReadableModelName($0.model) }

        return TokenUsageSummary(
            todayInputTokens: todayInput,
            todayOutputTokens: todayOutput,
            todayCacheReadTokens: todayCache,
            todayStepCount: todaySteps,
            sevenDayTotalTokens: sevenDayTotal,
            activeModelName: activeModel,
            dailyBuckets: dailyBuckets,
            modelBreakdowns: sortedModels,
            scannedConversationsCount: scannedConversationsCount
        )
    }

    public func collectUsageSummary(referenceDate: Date = Date()) -> TokenUsageSummary {
        let fm = FileManager.default
        var transcriptFiles: [URL] = []

        if let convDirs = try? fm.contentsOfDirectory(
            at: brainDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in convDirs {
                let transcriptURL = dir
                    .appendingPathComponent(".system_generated")
                    .appendingPathComponent("logs")
                    .appendingPathComponent("transcript.jsonl")
                if fm.fileExists(atPath: transcriptURL.path) {
                    transcriptFiles.append(transcriptURL)
                }
            }
        }

        // Also check if current process has brain subdirectories accessible via known active env or fallback
        var allSteps: [ParsedTranscriptStep] = []
        for fileURL in transcriptFiles {
            let path = fileURL.path
            let attrs = try? fm.attributesOfItem(atPath: path)
            let modDate = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let fileSize = (attrs?[.size] as? UInt64) ?? 0

            if let cached = fileCache[path],
               cached.modificationDate == modDate,
               cached.fileSize == fileSize {
                allSteps.append(contentsOf: cached.steps)
                continue
            }

            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let parsed = Self.parseTranscriptJSONL(content)
                fileCache[path] = CachedTranscriptFile(
                    modificationDate: modDate,
                    fileSize: fileSize,
                    steps: parsed
                )
                allSteps.append(contentsOf: parsed)
            }
        }

        return Self.aggregate(
            steps: allSteps,
            scannedConversationsCount: transcriptFiles.count,
            referenceDate: referenceDate
        )
    }
}
