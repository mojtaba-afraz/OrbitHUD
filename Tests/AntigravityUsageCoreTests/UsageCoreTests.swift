import XCTest
#if canImport(AntigravityUsageCore)
@testable import AntigravityUsageCore
#endif

final class UsageCoreTests: XCTestCase {
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
}
