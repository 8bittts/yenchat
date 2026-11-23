import AppKit
import Foundation
import Testing
@testable import YEN

struct TokenPlanUsageTests {
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

    @Test func grokBillingReadingSkipsANewerLineWithoutAPercentage() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let log = home.appendingPathComponent(".grok/logs/unified.jsonl")
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(86400).ISO8601Format()
        func line(_ age: TimeInterval, _ percent: String) -> String {
            """
            {"ts":"\(now.addingTimeInterval(-age).ISO8601Format())","msg":"billing: fetched credits config","ctx":{"config":{\(percent)"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"\(end)"}}}}
            """
        }
        // Grok omits the percentage on some fetches; the last line that carries one is still current.
        try Data((line(60, #""creditUsagePercent":14,"#) + "\n" + line(30, "") + "\n").utf8).write(to: log)
        let meters = TokenLocalPlans.grok(home: home, now: now)
        #expect(meters.map(\.label) == ["Grok weekly"])
        #expect(meters.map(\.percent) == [14])
    }

    @Test func planPercentagesClampToTheBarRange() {
        // A pool past its included limit still shows a full bar.
        #expect(TokenPlanMeter("Weekly", percent: 104.2, reset: nil)?.percent == 100)
        #expect(TokenPlanMeter("Weekly", percent: -1, reset: nil)?.percent == 0)
        #expect(TokenPlanMeter("Weekly", percent: true, reset: nil) == nil)
        #expect(TokenPlanMeter("Weekly", percent: "40", reset: nil) == nil)
        #expect(TokenPlanMeter("Weekly", percent: Double.nan, reset: nil) == nil)
    }

    @Test func barTonesStayVisibleOnLightAndDarkPanels() {
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        // The panel draws on the window background: white in light themes, near black in dark ones.
        for (dark, background) in [(false, [1.0, 1.0, 1.0]), (true, [0.157, 0.157, 0.157])] {
            func contrast(_ tone: [Double]) -> Double {
                let pair = [luminance(tone), luminance(background)].sorted()
                return (pair[1] + 0.05) / (pair[0] + 0.05)
            }
            for tone in TokenBarTone.neutrals(dark: dark) {
                #expect(contrast(tone) >= 3, "tone \(tone) on a \(dark ? "dark" : "light") panel")
            }
            // A hovered label is small text, so it needs the body-text ratio.
            #expect(contrast(TokenBarTone.link(dark: dark)) >= 4.5, "link tone on a \(dark ? "dark" : "light") panel")
        }
    }

    @MainActor @Test func repeatedTogglesReleaseTheMenuAndItsWork() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let file = TokenTool.claude.root(home: home).appendingPathComponent("project/session.jsonl")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
            {"type":"assistant","timestamp":"\(Date().ISO8601Format())","requestId":"r","message":{"id":"m","model":"claude-sonnet","usage":{"input_tokens":4,"output_tokens":1}}}

            """.utf8).write(to: file)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))

        // Each round is one switch on and off. Some rounds stop the menu while its first read runs.
        for round in 0..<12 {
            weak var released: TokenUsageMenu?
            do {
                let menu = TokenUsageMenu(index: index)
                released = menu
                if round.isMultiple(of: 2) { try await Task.sleep(for: .milliseconds(60)) }
                menu.stop()
            }
            // The read and the watcher hold the menu weakly, so nothing keeps it after the switch goes off.
            for _ in 0..<150 where released != nil { try await Task.sleep(for: .milliseconds(20)) }
            #expect(released == nil, "round \(round)")
        }
        // The cache is still usable after the cancelled reads.
        #expect(try index.read(tools: [.claude])[.claude] == 5)
    }

    @MainActor @Test func menuBarMarkFollowsTheTokenCount() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = TokenUsageMenu(index: TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache")))
        defer { menu.stop() }
        #expect(menu.statusButton?.imagePosition == .imageTrailing)
    }

    @MainActor @Test func resetForgetsTheDisplayChoices() throws {
        let suite = "token-display-reset-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = [TokenMenuDisplay.key, TokenMenuDisplay.columnsKey]
        for key in keys { defaults.set(true, forKey: key) }
        defaults.set(true, forKey: DesktopExtras.usageKey)
        TokenMenuDisplay.reset(defaults: defaults)
        #expect(keys.allSatisfy { defaults.object(forKey: $0) == nil })
        // The switch itself belongs to the Settings reset, not to the display reset.
        #expect(defaults.bool(forKey: DesktopExtras.usageKey))
    }
}
