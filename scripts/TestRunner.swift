import Foundation

@main
struct TestRunner {
    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", line: Int = #line) {
        if a != b {
            fputs("❌ Assertion failed at line \(line): \(a) != \(b). \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        print("Running AntigravityUsageCore unit tests...")

        // 1. Test RetrieveUserQuotaSummary JSON parsing and exact UI strings
        let jsonString = """
        {"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":0.7424301,"resetTime":"2026-11-29T12:45:02Z"},{"bucketId":"gemini-5h","displayName":"Five Hour Limit Remaining","window":"5h","remainingFraction":0.44642693,"resetTime":"2026-11-23T14:10:34Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","window":"weekly","remainingFraction":1,"resetTime":"2026-11-30T10:59:39Z"},{"bucketId":"3p-5h","displayName":"Five Hour Limit Remaining","window":"5h","remainingFraction":1,"resetTime":"2026-11-23T15:59:39Z"}]},{"displayName":"Gemini 4 Argon","buckets":[{"bucketId":"gemini-argon-wtu-weekly","displayName":"Gemini 4 Argon Weekly Limit","window":"weekly","remainingFraction":0.9263821,"resetTime":"2026-11-30T09:58:45Z"}]}]}}
        """
        let data = jsonString.data(using: .utf8)!
        guard let groups = LanguageServerQuotaFetcher.parseRetrieveUserQuotaSummaryJSON(data) else {
            fputs("❌ Failed to parse RetrieveUserQuotaSummary JSON\n", stderr)
            exit(1)
        }
        assertEqual(groups.count, 3)
        assertEqual(groups[0].displayName, "Gemini Models")
        assertEqual(groups[0].buckets[0].windowLabel, "Weekly limit")
        assertEqual(groups[0].buckets[0].remainingPercentage, 74)
        assertEqual(groups[0].buckets[1].windowLabel, "5h limit")
        assertEqual(groups[0].buckets[1].remainingPercentage, 45)

        let iso = ISO8601DateFormatter()
        let refNow = iso.date(from: "2026-11-23T11:00:00Z")!
        assertEqual(groups[0].buckets[0].formattedResetLine(relativeTo: refNow), "Resets in 6d 1h")
        assertEqual(groups[0].buckets[1].formattedResetLine(relativeTo: refNow), "Resets in 3h 10m")

        assertEqual(groups[1].displayName, "Claude and GPT models")
        assertEqual(groups[1].buckets[0].remainingPercentage, 100)
        assertEqual(groups[1].buckets[0].formattedResetLine(relativeTo: refNow), nil)

        assertEqual(groups[2].displayName, "Gemini 4 Argon")
        assertEqual(groups[2].buckets[0].remainingPercentage, 93)
        assertEqual(groups[2].buckets[0].formattedInlineSubtitle(relativeTo: refNow), "Weekly limit, resets in 6d 22h")

        let snapshot = AntigravityUsageSnapshot(timestamp: refNow, isLanguageServerConnected: true, quotaGroups: groups)
        assertEqual(snapshot.primaryQuotaPercentage, 45)
        let ringItems = snapshot.iosRingItems(relativeTo: refNow)
        assertEqual(ringItems.count, 5)
        assertEqual(ringItems[0].title, "Gemini 5h")
        assertEqual(ringItems[0].remainingPercentage, 45)
        assertEqual(ringItems[0].subtitle, "↻ 3h 10m")
        assertEqual(ringItems[1].title, "Gemini Wk")
        assertEqual(ringItems[1].remainingPercentage, 74)
        assertEqual(ringItems[1].subtitle, "↻ 6d 1h")
        assertEqual(ringItems[2].title, "Claude 5h")
        assertEqual(ringItems[2].remainingPercentage, 100)
        assertEqual(ringItems[2].subtitle, "Full")
        assertEqual(ringItems[3].title, "Claude Wk")
        assertEqual(ringItems[3].remainingPercentage, 100)
        assertEqual(ringItems[3].subtitle, "Full")
        assertEqual(ringItems[4].title, "Argon 4")
        assertEqual(ringItems[4].remainingPercentage, 93)
        assertEqual(ringItems[4].subtitle, "↻ 6d 22h")
        print("  ✓ RetrieveUserQuotaSummary parser, iOS ring items & reset timer tests passed")

        // 2. Test ps auxeww connection discovery
        let psSample = """
        mojtaba_afraz 41822 0.4 1.2 /Users/mojtaba_afraz/.gemini/bin/agy --hub --hub-port=56726 --app_data_dir=antigravity ANTIGRAVITY_SERVER_CSRF_TOKEN=657de39e-210c-422a-92ea-b2edec0681f1
        """
        let conns = LanguageServerQuotaFetcher.parseConnectionsFromPsOutput(psSample)
        assertEqual(conns, [LanguageServerConnection(port: 56726, csrfToken: "657de39e-210c-422a-92ea-b2edec0681f1")])
        print("  ✓ Process & CSRF token discovery tests passed")

        print("✅ All unit tests passed!")
    }
}
