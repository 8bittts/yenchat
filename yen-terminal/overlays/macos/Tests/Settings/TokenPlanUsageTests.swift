import Foundation
import Testing
@testable import YEN

struct TokenPlanUsageTests {
    @Test func sharedPlanReadingsRequireAnOptInAndAnUnexpiredPool() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let directory = home.appendingPathComponent("Library/Application Support/JPtheCat")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = #"{"fetchedAt":1799999900,"meters":[{"key":"all_models","usedPercent":0,"resetsAt":1800000100},{"key":"grok_bot_weekly","usedPercent":85,"resetsAt":1799999999}]}"#
        try Data(cache.utf8).write(to: directory.appendingPathComponent("grok-plan-usage.json"))
        #expect(TokenLocalPlans.sharedCursorPools(home: home, now: now).isEmpty)
        try Data().write(to: directory.appendingPathComponent("cursor-plan-usage.enabled"))
        let meters = TokenLocalPlans.sharedCursorPools(home: home, now: now)
        #expect(meters.map(\.label) == ["Cursor all models"])
        #expect(meters.map(\.percent) == [0])
    }

    @Test func connectionKeepsThreeIndependentPools() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let client = TokenPlanClient { request in
            #expect(request.url?.host == "api2.cursor.sh")
            #expect(request.httpMethod == "POST")
            #expect(request.httpBody == Data("{}".utf8))
            let path = try #require(request.url?.lastPathComponent)
            let expectedHeader = path == "exchange_user_api_key" ? "Bearer fixture-key" : "Bearer fixture-session"
            #expect(request.value(forHTTPHeaderField: "Authorization") == expectedHeader)
            let body: String
            switch path {
            case "exchange_user_api_key": body = #"{"accessToken":"fixture-session"}"#
            case "GetCurrentPeriodUsage":
                body = #"{"billingCycleEnd":"1900000000000","planUsage":{"autoPercentUsed":0,"apiPercentUsed":42}}"#
            case "GetSandUsageStatus":
                body = #"{"hasNonZeroIncludedLimit":true,"usagePercent":81,"nextResetTimestampUtc":"2030-03-17T00:00:00Z"}"#
            default: throw URLError(.unsupportedURL)
            }
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(body.utf8), response)
        }
        let pools = try await client.read(key: "fixture-key")
        #expect(!pools.partial)
        #expect(pools.meters.map(\.label) == ["Cursor models", "Cursor other models", "Grok Bot weekly"])
        #expect(pools.meters.map(\.percent) == [0, 42, 81])
        #expect(pools.meters.allSatisfy { $0.isCurrent(at: now) })
        #expect(pools.meters.allSatisfy { !$0.isCurrent(at: Date(timeIntervalSince1970: 2_000_000_000)) })
    }

    @Test func independentWeeklyResponseSurvivesMonthlyOutage() async throws {
        let client = TokenPlanClient { request in
            let exchange = request.url?.lastPathComponent == "exchange_user_api_key"
            let monthly = request.url?.lastPathComponent == "GetCurrentPeriodUsage"
            let body = exchange ? #"{"accessToken":"fixture"}"# : #"{"hasNonZeroIncludedLimit":true,"usagePercent":0}"#
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: monthly ? 503 : 200, httpVersion: nil, headerFields: nil))
            return (Data(body.utf8), response)
        }
        let pools = try await client.read(key: "fixture-key")
        #expect(pools.partial)
        #expect(pools.meters.map(\.label) == ["Grok Bot weekly"])
        #expect(pools.meters.map(\.percent) == [0])
    }

    @Test func accountQuotaIgnoresAddOnAndRollingZero() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func limit(_ id: String, _ offset: Double) -> TokenRecord.Object {
            ["limit_id": id, "secondary": ["window_minutes": 10080, "used_percent": 0, "resets_at": now.timeIntervalSince1970 + offset]]
        }
        #expect(TokenPlanReading.codex(limit("addon", 600), at: now) == nil)
        let first = try #require(TokenPlanReading.codex(limit("codex", 600), at: now))
        let next = now.addingTimeInterval(10)
        #expect(try #require(TokenPlanReading.codex(limit("codex", 610), at: next)).isRollingPlaceholder(after: first))
        #expect(try !#require(TokenPlanReading.codex(limit("codex", 600), at: next)).isRollingPlaceholder(after: first))
    }

    @Test func barTonesStayVisibleOnLightAndDarkPanels() {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        // The panel draws on the window background: white in light themes, near black in dark ones.
        for (dark, background) in [(false, [1.0, 1.0, 1.0]), (true, [0.157, 0.157, 0.157])] {
            for tone in TokenBarTone.neutrals(dark: dark) {
                let pair = [luminance(tone), luminance(background)].sorted()
                #expect((pair[1] + 0.05) / (pair[0] + 0.05) >= 3, "tone \(tone) on a \(dark ? "dark" : "light") panel")
            }
        }
    }
}
