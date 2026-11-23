import AppKit
import AVFoundation
import Foundation
import Testing
@testable import YEN

struct TokenLimitAlertsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meter(_ label: String, _ percent: Double, resetIn hours: Double = 24) -> TokenPlanMeter {
        TokenPlanMeter(label, percent: NSNumber(value: percent), reset: now.addingTimeInterval(hours * 3600))!
    }

    @Test func eachThresholdAlertsOncePerWindow() {
        var fired = Set<String>()
        #expect(TokenLimitAlerts.due(plans: [.claude: [meter("Weekly", 79)]], fired: &fired, now: now).isEmpty)
        let warning = TokenLimitAlerts.due(plans: [.claude: [meter("Weekly", 81)]], fired: &fired, now: now)
        #expect(warning.map(\.threshold) == [80])
        #expect(TokenLimitAlerts.due(plans: [.claude: [meter("Weekly", 85)]], fired: &fired, now: now).isEmpty)
        let critical = TokenLimitAlerts.due(plans: [.claude: [meter("Weekly", 96)]], fired: &fired, now: now)
        #expect(critical.map(\.threshold) == [95])
        #expect(TokenLimitAlerts.due(plans: [.claude: [meter("Weekly", 99)]], fired: &fired, now: now).isEmpty)
    }

    @Test func aReadingPastBothThresholdsRaisesOnlyTheCriticalAlert() {
        var fired = Set<String>()
        let alerts = TokenLimitAlerts.due(plans: [.codex: [meter("5-hour", 97, resetIn: 2)]], fired: &fired, now: now)
        #expect(alerts.map(\.threshold) == [95])
        #expect(fired.count == 2)
    }

    @Test func theNextWindowAlertsAgainAndFinishedWindowsAreForgotten() {
        var fired = Set<String>()
        _ = TokenLimitAlerts.due(plans: [.claude: [meter("5-hour", 90, resetIn: 1)]], fired: &fired, now: now)
        let later = now.addingTimeInterval(2 * 3600)
        let next = TokenPlanMeter("5-hour", percent: NSNumber(value: 82), reset: later.addingTimeInterval(3600))!
        let alerts = TokenLimitAlerts.due(plans: [.claude: [next]], fired: &fired, now: later)
        #expect(alerts.map(\.threshold) == [80])
        #expect(fired.count == 1)
    }

    @Test func expiredAndSeparatePoolsAreIndependent() {
        var fired = Set<String>()
        let expired = TokenPlanMeter("Weekly", percent: NSNumber(value: 99), reset: now.addingTimeInterval(-60))!
        let alerts = TokenLimitAlerts.due(plans: [.claude: [expired, meter("Fable weekly", 88)], .grok: [meter("Grok weekly", 91)]],
                                          fired: &fired, now: now)
        #expect(alerts.map(\.pool) == ["Claude Code Fable weekly", "Grok weekly"])
    }

    @Test func copyNamesThePoolPercentAndReset() {
        let warning = TokenLimitAlerts.Alert(tool: .claude, meter: meter("Weekly", 82.4, resetIn: 2), threshold: 80)
        #expect(warning.title == "Claude Code weekly limit at 82%")
        #expect(warning.body(now: now).hasPrefix("Resets "))
        let full = TokenLimitAlerts.Alert(tool: .codex, meter: meter("5-hour", 100, resetIn: 2), threshold: 95)
        #expect(full.body(now: now).hasPrefix("Limit reached. Resets "))
        let critical = TokenLimitAlerts.Alert(tool: .codex, meter: meter("5-hour", 96, resetIn: 2), threshold: 95)
        #expect(critical.body(now: now).hasPrefix("Almost out. Resets "))
    }

    @Test func savedStateKeepsARelaunchQuietAndTheSwitchSilencesAlerts() throws {
        let suite = "yen-limit-alerts-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let plans: [TokenTool: [TokenPlanMeter]] = [.claude: [meter("Weekly", 84)]]
        #expect(TokenLimitAlerts.evaluate(plans: plans, now: now, defaults: defaults).count == 1)
        #expect(TokenLimitAlerts.evaluate(plans: plans, now: now, defaults: defaults).isEmpty)
        TokenLimitAlerts.reset(defaults: defaults)
        defaults.set(false, forKey: TokenLimitAlerts.enabledKey)
        #expect(TokenLimitAlerts.evaluate(plans: plans, now: now, defaults: defaults).isEmpty)
    }
}

@MainActor
@Suite(.serialized)
struct JPTheCatSoundTests {
    @Test func usageLimitsStreamStartsWithJPTheCatAndOthersStartSilent() {
        let defaults = UserDefaults.standard
        let manager = NotificationSoundManager.shared
        let saved = NotificationService.configurableCases.map { defaults.object(forKey: $0.defaultsKey) }
        defer {
            for (service, value) in zip(NotificationService.configurableCases, saved) {
                defaults.set(value, forKey: service.defaultsKey)
            }
        }
        for service in NotificationService.configurableCases { defaults.removeObject(forKey: service.defaultsKey) }
        #expect(NotificationService.configurableCases.contains(.usage))
        #expect(manager.soundName(for: .usage) == NotificationSoundManager.jpTheCatSelectionID)
        #expect(manager.soundName(for: .general) == NotificationSoundManager.silentSelectionID)
        #expect(SettingsNotificationsPane.serviceTitle(.usage) == "Usage Limits")
    }

    @Test func jpTheCatIsAStableSelectionForEveryStream() {
        let defaults = UserDefaults.standard
        let manager = NotificationSoundManager.shared
        let saved = defaults.object(forKey: NotificationService.general.defaultsKey)
        defer { defaults.set(saved, forKey: NotificationService.general.defaultsKey) }
        manager.setSoundName(NotificationSoundManager.jpTheCatSelectionID, for: .general)
        #expect(manager.soundName(for: .general) == NotificationSoundManager.jpTheCatSelectionID)
        #expect(manager.displayName(for: NotificationSoundManager.jpTheCatSelectionID) == "JP the Cat")
        #expect(NotificationSoundManager.isValidStoredSelectionID(NotificationSoundManager.jpTheCatSelectionID))
        // Only the sounds YEN ships resolve; any other yen: id is silence.
        manager.setSoundName("yen:not-a-sound", for: .general)
        #expect(manager.soundName(for: .general) == NotificationSoundManager.silentSelectionID)
    }

    @Test func theAppCarriesThePlayableSound() throws {
        let asset = try #require(NSDataAsset(name: NotificationSoundManager.jpTheCatAssetName))
        let player = try AVAudioPlayer(data: asset.data)
        #expect(player.duration > 1)
    }
}
