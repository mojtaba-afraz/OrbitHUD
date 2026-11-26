import XCTest
#if canImport(AntigravityUsageCore)
@testable import AntigravityUsageCore
#endif

final class UsageCoreTests: XCTestCase {
    // MARK: - LanguageServerQuotaFetcher

    func testParseRetrieveUserQuotaSummaryJSON() {
        let jsonString = """
        {"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":0.7424301,"resetTime":"2026-11-29T12:45:02Z"},{"bucketId":"gemini-5h","displayName":"Five Hour Limit Remaining","window":"5h","remainingFraction":0.44642693,"resetTime":"2026-11-23T14:10:34Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":1,"resetTime":"2026-11-30T10:59:39Z"},{"bucketId":"3p-5h","displayName":"Five Hour Limit Remaining","window":"5h","remainingFraction":1,"resetTime":"2026-11-23T15:59:39Z"}]},{"displayName":"Gemini 4 Argon","buckets":[{"bucketId":"gemini-argon-wtu-weekly","displayName":"Gemini 4 Argon Weekly Limit","window":"weekly","remainingFraction":0.9263821,"resetTime":"2026-11-30T09:58:45Z"}]}]}}
        """
        let data = jsonString.data(using: .utf8)!
        let groups = LanguageServerQuotaFetcher.parseRetrieveUserQuotaSummaryJSON(data)
        XCTAssertNotNil(groups)
        XCTAssertEqual(groups?.count, 3)
        XCTAssertEqual(groups?[0].displayName, "Gemini Models")
        XCTAssertEqual(groups?[0].buckets[0].remainingPercentage, 74)
        XCTAssertEqual(groups?[0].buckets[1].remainingPercentage, 45)
        XCTAssertEqual(groups?[1].displayName, "Claude and GPT models")
        XCTAssertEqual(groups?[1].buckets[0].remainingPercentage, 100)
        XCTAssertEqual(groups?[2].displayName, "Gemini 4 Argon")
        XCTAssertEqual(groups?[2].buckets[0].remainingPercentage, 93)
    }

    func testClassifyQuotaResponseAuthRequired() {
        let emptyGroups = Data(#"{"response":{"groups":[]}}"#.utf8)
        XCTAssertEqual(
            LanguageServerQuotaFetcher.classifyQuotaResponse(statusCode: 200, data: emptyGroups),
            .authRequired(message: "Not signed in to Antigravity")
        )

        let unauthBody = Data(#"{"code":"UNAUTHENTICATED","message":"User is not signed in"}"#.utf8)
        XCTAssertEqual(
            LanguageServerQuotaFetcher.classifyQuotaResponse(statusCode: 200, data: unauthBody),
            .authRequired(message: "Not signed in to Antigravity")
        )

        let http401 = Data("{}".utf8)
        XCTAssertEqual(
            LanguageServerQuotaFetcher.classifyQuotaResponse(statusCode: 401, data: http401),
            .authRequired(message: "Not signed in to Antigravity")
        )

        let serverErr = Data(#"{"error":"internal"}"#.utf8)
        XCTAssertNil(
            LanguageServerQuotaFetcher.classifyQuotaResponse(statusCode: 500, data: serverErr)
        )
    }

    // MARK: - TokenFormatter

    func testTokenFormatterFormat() {
        XCTAssertEqual(TokenFormatter.format(0), "0")
        XCTAssertEqual(TokenFormatter.format(42), "42")
        XCTAssertEqual(TokenFormatter.format(999), "999")
        XCTAssertEqual(TokenFormatter.format(1_000), "1.0K")
        XCTAssertEqual(TokenFormatter.format(1_500), "1.5K")
        XCTAssertEqual(TokenFormatter.format(50_000), "50.0K")
        XCTAssertEqual(TokenFormatter.format(125_400), "125.4K")
        XCTAssertEqual(TokenFormatter.format(999_949), "999.9K")
        XCTAssertEqual(TokenFormatter.format(1_000_000), "1.0M")
        XCTAssertEqual(TokenFormatter.format(2_500_000), "2.5M")
    }

    func testTokenFormatterHumanReadableModelName() {
        XCTAssertEqual(TokenFormatter.humanReadableModelName("gemini-4-argon"), "Gemini 4 Argon")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("gemini-2.5-pro"), "Gemini Pro")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("gemini-2.5-flash-lite"), "Gemini Flash Lite")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("gemini-2.5-flash"), "Gemini Flash")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("claude-3-7-sonnet"), "Claude Sonnet")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("claude-4-opus"), "Claude Opus")
        XCTAssertEqual(TokenFormatter.humanReadableModelName("custom_model-v1"), "Custom Model V1")
    }

    // MARK: - ClaudeCodeQuotaFetcher

    func testClaudeCodeParseAccessTokenVariants() {
        let nestedOauth = #"{"claudeAiOauth":{"accessToken":"  sk-ant-oat01-abc  "}}"#
        XCTAssertEqual(ClaudeCodeQuotaFetcher.parseAccessToken(from: nestedOauth), "sk-ant-oat01-abc")

        let genericOauth = #"{"oauth":{"access_token":"sk-ant-oat01-xyz"}}"#
        XCTAssertEqual(ClaudeCodeQuotaFetcher.parseAccessToken(from: genericOauth), "sk-ant-oat01-xyz")

        let topLevel = #"{"accessToken":"sk-ant-top-123"}"#
        XCTAssertEqual(ClaudeCodeQuotaFetcher.parseAccessToken(from: topLevel), "sk-ant-top-123")

        XCTAssertNil(ClaudeCodeQuotaFetcher.parseAccessToken(from: #"{"claudeAiOauth":{"accessToken":"   "}}"#))
        XCTAssertNil(ClaudeCodeQuotaFetcher.parseAccessToken(from: "not-json"))
    }

    func testClaudeCodeParseUsageJSON() {
        let jsonString = """
        {
          "five_hour": { "utilization": 33.0, "resets_at": "2026-11-23T14:00:00.500Z" },
          "seven_day": { "utilization": 1.0, "resets_at": "2026-11-29T11:00:00Z" },
          "seven_day_sonnet": { "utilization": 10.0, "resetsAt": "2026-11-29T11:00:00Z" },
          "seven_day_opus": { "utilization": 50.0, "resets_at": "2026-11-29T11:00:00Z" }
        }
        """
        let groups = ClaudeCodeQuotaFetcher.parseUsageJSON(Data(jsonString.utf8))
        XCTAssertNotNil(groups)
        XCTAssertEqual(groups?.count, 3)

        let primary = groups?[0]
        XCTAssertEqual(primary?.id, "claude-code::primary")
        XCTAssertEqual(primary?.providerId, "claude-code")
        XCTAssertEqual(primary?.buckets.count, 2)
        XCTAssertEqual(primary?.buckets[0].window, "5h")
        XCTAssertEqual(primary?.buckets[0].remainingPercentage, 67)
        XCTAssertNotNil(primary?.buckets[0].resetTime)
        XCTAssertEqual(primary?.buckets[1].window, "weekly")
        XCTAssertEqual(primary?.buckets[1].remainingPercentage, 99)
        XCTAssertNotNil(primary?.buckets[1].resetTime)

        XCTAssertEqual(groups?[1].id, "claude-code::sonnet")
        XCTAssertEqual(groups?[1].buckets[0].remainingPercentage, 90)
        XCTAssertEqual(groups?[2].id, "claude-code::opus")
        XCTAssertEqual(groups?[2].buckets[0].remainingPercentage, 50)

        XCTAssertNil(ClaudeCodeQuotaFetcher.parseUsageJSON(Data("{}".utf8)))
        XCTAssertNil(ClaudeCodeQuotaFetcher.parseUsageJSON(Data("invalid".utf8)))
    }

    // MARK: - CodexQuotaFetcher

    func testCodexParseCredentialsVariants() {
        let nested = #"{"tokens":{"access_token":"codex-tok-1","account_id":"acct_123"}}"#
        let parsed1 = CodexQuotaFetcher.parseCredentials(from: nested)
        XCTAssertEqual(parsed1?.accessToken, "codex-tok-1")
        XCTAssertEqual(parsed1?.accountId, "acct_123")

        let camel = #"{"tokens":{"accessToken":"codex-tok-2","accountId":"acct_456"}}"#
        let parsed2 = CodexQuotaFetcher.parseCredentials(from: camel)
        XCTAssertEqual(parsed2?.accessToken, "codex-tok-2")
        XCTAssertEqual(parsed2?.accountId, "acct_456")

        let envStyle = #"{"OPENAI_ACCESS_TOKEN":"  codex-tok-3  "}"#
        let parsed3 = CodexQuotaFetcher.parseCredentials(from: envStyle)
        XCTAssertEqual(parsed3?.accessToken, "codex-tok-3")
        XCTAssertNil(parsed3?.accountId)

        XCTAssertNil(CodexQuotaFetcher.parseCredentials(from: #"{"tokens":{"access_token":""}}"#))
        XCTAssertNil(CodexQuotaFetcher.parseCredentials(from: "bad-json"))
    }

    func testCodexParseUsageJSON() {
        let refNow = Date(timeIntervalSince1970: 1_760_000_000)
        let jsonString = """
        {
          "plan_type": "Plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 25.0,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 7200
            },
            "secondary_window": {
              "used_percent": 40.0,
              "limit_window_seconds": 604800,
              "reset_at": 1760604800000
            }
          }
        }
        """
        let groups = CodexQuotaFetcher.parseUsageJSON(Data(jsonString.utf8), now: refNow)
        XCTAssertNotNil(groups)
        XCTAssertEqual(groups?.count, 1)
        XCTAssertEqual(groups?[0].id, "codex::primary")
        XCTAssertEqual(groups?[0].providerId, "codex")
        XCTAssertEqual(groups?[0].displayName, "Codex CLI (Plus)")
        XCTAssertEqual(groups?[0].buckets.count, 2)

        XCTAssertEqual(groups?[0].buckets[0].window, "5h")
        XCTAssertEqual(groups?[0].buckets[0].remainingPercentage, 75)
        XCTAssertEqual(groups?[0].buckets[0].resetTime?.timeIntervalSince1970 ?? 0, 1_760_007_200, accuracy: 0.5)

        XCTAssertEqual(groups?[0].buckets[1].window, "weekly")
        XCTAssertEqual(groups?[0].buckets[1].remainingPercentage, 60)
        XCTAssertEqual(groups?[0].buckets[1].resetTime?.timeIntervalSince1970 ?? 0, 1_760_604_800, accuracy: 0.5)

        // Post-reset regression: 5h reset to 0% used (100% left), weekly at 1% used (must be 99% left, not 0%)
        let postResetJson = """
        {
          "plan_type": "Plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 0,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 1,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 604800
            }
          }
        }
        """
        let postResetGroups = CodexQuotaFetcher.parseUsageJSON(Data(postResetJson.utf8), now: refNow)
        XCTAssertEqual(postResetGroups?[0].buckets[0].remainingPercentage, 100)
        XCTAssertEqual(postResetGroups?[0].buckets[1].remainingPercentage, 99)

        // Daily window & missing plan_type
        let dailyJson = """
        {
          "rateLimit": {
            "primaryWindow": {
              "usedPercent": 20,
              "window_seconds": 86400,
              "reset_at": 1760086400
            }
          }
        }
        """
        let dailyGroups = CodexQuotaFetcher.parseUsageJSON(Data(dailyJson.utf8), now: refNow)
        XCTAssertEqual(dailyGroups?[0].displayName, "Codex CLI")
        XCTAssertEqual(dailyGroups?[0].buckets[0].window, "daily")
        XCTAssertEqual(dailyGroups?[0].buckets[0].remainingPercentage, 80)

        XCTAssertNil(CodexQuotaFetcher.parseUsageJSON(Data("{}".utf8), now: refNow))
        XCTAssertNil(CodexQuotaFetcher.parseUsageJSON(Data("not-json".utf8), now: refNow))
    }

    // MARK: - TranscriptUsageAggregator

    func testParseTranscriptJSONL() {
        let jsonl = """
        {"type":"USER_INPUT","content":"hello"}
        {"created_at":"2026-11-23T10:15:30.250Z","model":"gemini-2.5-pro","input_tokens":1200,"output_tokens":300,"cache_read_tokens":500}
        {"created_at":"2026-11-23T11:00:00Z","input_tokens":0,"output_tokens":0,"cache_read_tokens":0}
        not valid json with "input_tokens"
        {"created_at":"2026-11-23T12:00:00Z","output_tokens":450}
        """

        let steps = TranscriptUsageAggregator.parseTranscriptJSONL(jsonl)
        XCTAssertEqual(steps.count, 2)

        XCTAssertEqual(steps[0].model, "gemini-2.5-pro")
        XCTAssertEqual(steps[0].inputTokens, 1200)
        XCTAssertEqual(steps[0].outputTokens, 300)
        XCTAssertEqual(steps[0].cacheReadTokens, 500)

        XCTAssertEqual(steps[1].model, "unknown")
        XCTAssertEqual(steps[1].inputTokens, 0)
        XCTAssertEqual(steps[1].outputTokens, 450)
        XCTAssertEqual(steps[1].cacheReadTokens, 0)
    }

    func testAggregateTranscriptSteps() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let iso = ISO8601DateFormatter()
        let refDate = iso.date(from: "2026-11-23T15:00:00Z")!
        let todayEarly = iso.date(from: "2026-11-23T09:00:00Z")!
        let todayLate = iso.date(from: "2026-11-23T14:30:00Z")!
        let threeDaysAgo = iso.date(from: "2026-11-20T12:00:00Z")!
        let tenDaysAgo = iso.date(from: "2026-11-13T12:00:00Z")!

        let steps: [ParsedTranscriptStep] = [
            ParsedTranscriptStep(createdAt: todayEarly, model: "gemini-2.5-pro", inputTokens: 1000, outputTokens: 200, cacheReadTokens: 300),
            ParsedTranscriptStep(createdAt: todayLate, model: "claude-3-7-sonnet", inputTokens: 4000, outputTokens: 500, cacheReadTokens: 500),
            ParsedTranscriptStep(createdAt: threeDaysAgo, model: "gemini-2.5-pro", inputTokens: 2000, outputTokens: 1000, cacheReadTokens: 0),
            ParsedTranscriptStep(createdAt: tenDaysAgo, model: "gemini-2.5-flash", inputTokens: 99_999, outputTokens: 0, cacheReadTokens: 0),
        ]

        let summary = TranscriptUsageAggregator.aggregate(
            steps: steps,
            scannedConversationsCount: 2,
            referenceDate: refDate,
            calendar: utcCalendar
        )

        XCTAssertEqual(summary.scannedConversationsCount, 2)
        XCTAssertEqual(summary.todayInputTokens, 5000)
        XCTAssertEqual(summary.todayOutputTokens, 700)
        XCTAssertEqual(summary.todayCacheReadTokens, 800)
        XCTAssertEqual(summary.todayTotalTokens, 6500)
        XCTAssertEqual(summary.todayStepCount, 2)
        // 7-day total excludes tenDaysAgo: 1500 + 5000 + 3000 = 9500
        XCTAssertEqual(summary.sevenDayTotalTokens, 9500)
        XCTAssertEqual(summary.dailyBuckets.count, 7)
        XCTAssertEqual(summary.dailyBuckets.last?.id, "2026-11-23")
        XCTAssertEqual(summary.dailyBuckets.last?.totalTokens, 6500)
        // Latest step is todayLate (claude-3-7-sonnet -> Claude Sonnet)
        XCTAssertEqual(summary.activeModelName, "Claude Sonnet")
        // Sorted descending by totalTokens: Claude Sonnet (5000) > Gemini Pro (4500)
        XCTAssertEqual(summary.modelBreakdowns.count, 2)
        XCTAssertEqual(summary.modelBreakdowns[0].modelName, "Claude Sonnet")
        XCTAssertEqual(summary.modelBreakdowns[0].totalTokens, 5000)
        XCTAssertEqual(summary.modelBreakdowns[1].modelName, "Gemini Pro")
        XCTAssertEqual(summary.modelBreakdowns[1].totalTokens, 4500)
    }

    func testCollectUsageSummaryFromTempBrainDirectory() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("orbithud-transcript-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempRoot) }

        let logsDir = tempRoot
            .appendingPathComponent("conv-1")
            .appendingPathComponent(".system_generated")
            .appendingPathComponent("logs")
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        let refDate = iso.date(from: "2026-11-23T12:00:00Z")!
        let transcriptURL = logsDir.appendingPathComponent("transcript.jsonl")
        let content = """
        {"created_at":"2026-11-23T10:00:00Z","model":"gemini-4-argon","input_tokens":20000,"output_tokens":5000,"cache_read_tokens":25000}
        """
        try content.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let aggregator = TranscriptUsageAggregator(brainDirectoryURL: tempRoot)
        let first = aggregator.collectUsageSummary(referenceDate: refDate)
        XCTAssertEqual(first.scannedConversationsCount, 1)
        XCTAssertEqual(first.todayTotalTokens, 50_000)
        XCTAssertEqual(TokenFormatter.format(first.todayTotalTokens), "50.0K")
        XCTAssertEqual(first.activeModelName, "Gemini 4 Argon")

        // Second call hits fileCache and returns identical summary
        let second = aggregator.collectUsageSummary(referenceDate: refDate)
        XCTAssertEqual(second, first)
    }

    // MARK: - AutoUpdater

    func testAutoUpdaterSemverComparison() {
        XCTAssertEqual(AutoUpdater.parseSemver("v1.2.5").0, 1)
        XCTAssertEqual(AutoUpdater.parseSemver("v1.2.5").1, 2)
        XCTAssertEqual(AutoUpdater.parseSemver("v1.2.5").2, 5)
        XCTAssertEqual(AutoUpdater.parseSemver("1.3.0-beta.1").1, 3)

        XCTAssertGreaterThan(AutoUpdater.compareSemver("v1.2.6", "1.2.5"), 0)
        XCTAssertGreaterThan(AutoUpdater.compareSemver("1.10.0", "1.2.9"), 0)
        XCTAssertGreaterThan(AutoUpdater.compareSemver("2.0.0", "1.9.9"), 0)
        XCTAssertEqual(AutoUpdater.compareSemver("v1.2.5", "1.2.5"), 0)
        XCTAssertLessThan(AutoUpdater.compareSemver("1.2.4", "1.2.5"), 0)
    }

    func testAutoUpdaterAssetAndChecksumSelection() {
        let dmg = UpdateAssetInfo(name: "OrbitHUD-macOS.dmg", downloadURL: URL(string: "https://example.com/a.dmg")!)
        let zip = UpdateAssetInfo(name: "OrbitHUD-macOS.zip", downloadURL: URL(string: "https://example.com/a.zip")!)
        let exe = UpdateAssetInfo(name: "OrbitHUD-Windows-Setup.exe", downloadURL: URL(string: "https://example.com/a.exe")!)
        let sums = UpdateAssetInfo(name: "SHA256SUMS.txt", downloadURL: URL(string: "https://example.com/SHA256SUMS.txt")!)

        XCTAssertEqual(AutoUpdater.selectMacOSAsset(from: [dmg, exe, zip, sums]), zip)
        XCTAssertEqual(AutoUpdater.selectChecksumAsset(from: [dmg, exe, zip, sums]), sums)
        XCTAssertNil(AutoUpdater.selectMacOSAsset(from: [dmg, exe, sums]))
        XCTAssertNil(AutoUpdater.selectChecksumAsset(from: [dmg, exe, zip]))
    }

    func testAutoUpdaterParseSha256Sums() {
        let validA = String(repeating: "a", count: 64)
        let validB = String(repeating: "B", count: 64)
        let text = """
        # Release checksums
        \(validA)  OrbitHUD-macOS.zip
        \(validB) *./dist/OrbitHUD-Windows-Setup.exe
        not-a-hash  ignored.bin
        """
        let parsed = AutoUpdater.parseSha256Sums(text)
        XCTAssertEqual(parsed["OrbitHUD-macOS.zip"], validA)
        XCTAssertEqual(parsed["OrbitHUD-Windows-Setup.exe"], validB.lowercased())
        XCTAssertNil(parsed["ignored.bin"])
    }

    func testAutoUpdaterVerifyFileSha256() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("orbithud-sha-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Known SHA256 of "hello orbit"
        let payload = Data("hello orbit".utf8)
        let validFile = tempDir.appendingPathComponent("valid.zip")
        try payload.write(to: validFile)
        let expected = try AutoUpdater.computeFileSha256(at: validFile)
        XCTAssertEqual(expected.count, 64)

        // Matching hash succeeds and keeps file
        let verified = try AutoUpdater.verifyFileSha256(at: validFile, expectedHash: expected.uppercased())
        XCTAssertEqual(verified, expected)
        XCTAssertTrue(fm.fileExists(atPath: validFile.path))

        // Mismatched hash throws and deletes file
        let badFile = tempDir.appendingPathComponent("tampered.zip")
        try payload.write(to: badFile)
        let wrongHash = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try AutoUpdater.verifyFileSha256(at: badFile, expectedHash: wrongHash)) { err in
            if case AutoUpdaterError.checksumMismatch = err {
                // expected
            } else {
                XCTFail("Expected checksumMismatch, got \(err)")
            }
        }
        XCTAssertFalse(fm.fileExists(atPath: badFile.path))

        // Invalid hash format throws and deletes file
        let invalidFmtFile = tempDir.appendingPathComponent("invalidfmt.zip")
        try payload.write(to: invalidFmtFile)
        XCTAssertThrowsError(try AutoUpdater.verifyFileSha256(at: invalidFmtFile, expectedHash: "xyz")) { err in
            XCTAssertEqual(err as? AutoUpdaterError, .invalidChecksumFormat)
        }
        XCTAssertFalse(fm.fileExists(atPath: invalidFmtFile.path))
    }

    func testAutoUpdaterBuildMacOSInstallScript() {
        let script = AutoUpdater.buildMacOSInstallScript(
            downloadedZipPath: "/tmp/my dir/Orbit's.zip",
            extractDir: "/tmp/extract 1",
            targetAppPath: "/Applications/OrbitHUD.app",
            pid: 4242,
            scriptPath: "/tmp/update.sh"
        )
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(script.contains("while kill -0 4242"))
        XCTAssertTrue(script.contains("ditto -xk '/tmp/my dir/Orbit'\\''s.zip' '/tmp/extract 1'"))
        XCTAssertTrue(script.contains("mv '/Applications/OrbitHUD.app' '/Applications/OrbitHUD.app.backup'"))
        XCTAssertTrue(script.contains("open -n '/Applications/OrbitHUD.app'"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
    }

    func testAutoUpdaterResolveTargetAppBundlePath() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("orbithud-bundle-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let writableApp = tempDir.appendingPathComponent("OrbitHUD.app")
        XCTAssertEqual(AutoUpdater.resolveTargetAppBundlePath(bundleURL: writableApp), writableApp.path)

        let dmgApp = URL(fileURLWithPath: "/Volumes/OrbitHUD/OrbitHUD.app")
        XCTAssertEqual(AutoUpdater.resolveTargetAppBundlePath(bundleURL: dmgApp), "/Applications/OrbitHUD.app")

        let nonApp = tempDir.appendingPathComponent("AntigravityUsageWidget")
        XCTAssertEqual(AutoUpdater.resolveTargetAppBundlePath(bundleURL: nonApp), "/Applications/OrbitHUD.app")
    }

    // MARK: - QuotaAlertEvaluator

    func testQuotaAlertLowCrossingDeduplicationAndReset() {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-11-26T12:00:00Z")!
        let reset1 = iso.date(from: "2026-11-26T15:00:00Z")!
        let reset2 = iso.date(from: "2026-11-26T20:00:00Z")!

        func makeGroups(pct: Double, reset: Date) -> [QuotaGroup] {
            [
                QuotaGroup(
                    id: "antigravity::gemini",
                    providerId: "antigravity",
                    displayName: "Gemini Models",
                    buckets: [
                        QuotaBucket(
                            id: "gemini-5h",
                            displayName: "Five Hour Limit",
                            window: "5h",
                            remainingFraction: pct / 100.0,
                            resetTime: reset
                        )
                    ]
                )
            ]
        }

        let evaluator = QuotaAlertEvaluator()
        let config = QuotaAlertConfig(enabled: true, lowThresholdPercent: 20, notifyOnReset: true)

        // Seed at 50% -> no alert
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 50, reset: reset1), config: config, now: now).isEmpty)

        // Cross below 20% -> fires once
        let low1 = evaluator.evaluate(groups: makeGroups(pct: 18, reset: reset1), config: config, now: now)
        XCTAssertEqual(low1.count, 1)
        XCTAssertEqual(low1[0].kind, .lowQuota)
        XCTAssertTrue(low1[0].title.contains("Gemini Models"))
        XCTAssertTrue(low1[0].body.contains("18% remaining"))

        // Further drops in same cycle -> suppressed
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 12, reset: reset1), config: config, now: now).isEmpty)
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 0, reset: reset1), config: config, now: now).isEmpty)

        // Reset to 100% -> fires quotaReset once
        let resetEvents = evaluator.evaluate(groups: makeGroups(pct: 100, reset: reset2), config: config, now: now)
        XCTAssertEqual(resetEvents.count, 1)
        XCTAssertEqual(resetEvents[0].kind, .quotaReset)

        // Staying at 100% -> no duplicate
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 100, reset: reset2), config: config, now: now).isEmpty)

        // Dropping below threshold in new cycle -> fires lowQuota again
        let low2 = evaluator.evaluate(groups: makeGroups(pct: 15, reset: reset2), config: config, now: now)
        XCTAssertEqual(low2.count, 1)
        XCTAssertEqual(low2[0].kind, .lowQuota)
    }

    func testQuotaAlertSeedWhileLowAndOptInFlags() {
        func makeGroups(pct: Double) -> [QuotaGroup] {
            [
                QuotaGroup(
                    id: "claude-code::primary",
                    providerId: "claude-code",
                    displayName: "Claude Code",
                    buckets: [
                        QuotaBucket(id: "5h", displayName: "5h", window: "5h", remainingFraction: pct / 100.0)
                    ]
                )
            ]
        }

        // Seed while already low (8%) -> no launch spam, but reset to 100% notifies
        let evaluator = QuotaAlertEvaluator()
        let enabledCfg = QuotaAlertConfig(enabled: true, lowThresholdPercent: 20, notifyOnReset: true)
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 8), config: enabledCfg).isEmpty)
        let resetEv = evaluator.evaluate(groups: makeGroups(pct: 100), config: enabledCfg)
        XCTAssertEqual(resetEv.count, 1)
        XCTAssertEqual(resetEv[0].kind, .quotaReset)

        // Disabled alerts produce zero events
        let disabledCfg = QuotaAlertConfig(enabled: false, lowThresholdPercent: 20, notifyOnReset: true)
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 10), config: disabledCfg).isEmpty)
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 100), config: disabledCfg).isEmpty)

        // notifyOnReset = false suppresses reset alert while keeping low alert
        let noResetCfg = QuotaAlertConfig(enabled: true, lowThresholdPercent: 20, notifyOnReset: false)
        XCTAssertEqual(evaluator.evaluate(groups: makeGroups(pct: 10), config: noResetCfg).count, 1)
        XCTAssertTrue(evaluator.evaluate(groups: makeGroups(pct: 100), config: noResetCfg).isEmpty)
    }
}
