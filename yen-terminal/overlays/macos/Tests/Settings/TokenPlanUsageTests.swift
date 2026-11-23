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

    @MainActor @Test func menuBarMarkFollowsTheTokenCount() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = TokenUsageMenu(index: TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache")))
        defer { menu.stop() }
        #expect(menu.statusButton?.imagePosition == .imageTrailing)
        // The space separates the count from the mark that follows it, never the
        // count from the menu bar item before it.
        let title = try #require(menu.statusButton?.title)
        #expect(title.first?.isWhitespace == false, "Title \"\(title)\" starts with a space")
        #expect(title.hasSuffix(" ") && !title.hasSuffix("  "), "Title \"\(title)\" needs one space before the mark")
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

    @Test func rotatingMenuBarShowsTheTotalAndEachCurrentLimitInTurn() throws {
        let now = Date()
        let later = now.addingTimeInterval(3600)
        func meter(_ label: String, _ percent: Double, _ reset: Date = later) throws -> TokenPlanMeter {
            try #require(TokenPlanMeter(label, percent: percent as NSNumber, reset: reset))
        }
        let counts: TokenUsageIndex.Counts = [.claude: 514_000_000, .codex: 0, .grok: 0, .openCode: 0]
        let plans: [TokenTool: [TokenPlanMeter]] = [
            .claude: [try meter("Weekly", 64), try meter("Opus weekly", 40), try meter("5-hour", 9, now.addingTimeInterval(-1))],
            .codex: [try meter("5-hour", 12), try meter("Weekly", 97)],
            .grok: [try meter("Grok weekly", 1)]
        ]
        let total = 514_000_000.formatted(.number.notation(.compactName))
        func pct(_ value: Double) -> String { (value / 100).formatted(.percent.precision(.fractionLength(0))) }
        // A weekly pool carries no label; the expired Claude 5-hour window is skipped.
        let expected = ["Claude " + pct(64), "Claude Opus " + pct(40), "Codex 5h " + pct(12), "Codex " + pct(97), "Grok " + pct(1)]
        for step in 0..<(expected.count + 1) {
            let caption = TokenMenuDisplay.rotating.caption(counts: counts, plans: plans, step: step, now: now)
            #expect(caption == total + " · " + expected[step % expected.count])
        }
        // With no current reading the rotating view still shows the total.
        #expect(TokenMenuDisplay.rotating.caption(counts: counts, plans: [:], step: 3, now: now) == total)
        #expect(TokenMenuDisplay.mark.caption(counts: counts, plans: plans, step: 0, now: now).isEmpty)
    }

    @Test func savedDisplayChoicesSurviveTheRename() {
        #expect(TokenMenuDisplay(stored: "Plan limits") == .rotating)
        #expect(TokenMenuDisplay(stored: "Top provider") == .provider)
        #expect(TokenMenuDisplay(stored: nil) == .total)
        #expect(TokenMenuDisplay(stored: "unknown") == .total)
    }

    @MainActor @Test func rightClickMenuOffersRefreshUpdatesAndQuit() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let menu = TokenUsageMenu(index: TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache")))
        defer { menu.stop() }
        let items = menu.contextMenu().items.filter { !$0.isSeparatorItem }
        #expect(items.map(\.title).dropFirst() == ["Refresh", "Check for Updates…", "Quit YEN"])
        #expect(items.first?.title.hasPrefix("YEN") == true && items.first?.isEnabled == false)
        #expect(items[1].target === menu && items[1].keyEquivalent == "r")
        // No target: the responder chain carries it to the app delegate's Sparkle check.
        #expect(items[2].action == NSSelectorFromString("checkForUpdates:") && items[2].target == nil)
        #expect(items[3].action == #selector(NSApplication.terminate(_:)) && items[3].keyEquivalent == "q")
        #expect(menu.statusButton.map { NSEvent.EventTypeMask(rawValue: UInt64($0.sendAction(on: []))).contains(.rightMouseUp) } == true)
    }
}
