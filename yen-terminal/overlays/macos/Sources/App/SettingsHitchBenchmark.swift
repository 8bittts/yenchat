import AppKit
import OSLog

@MainActor
enum SettingsHitchBenchmark {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yenchat.yen",
        category: "SettingsHitchBenchmark"
    )

    private static let scenarioEnvironmentKey = "YEN_SETTINGS_HITCH_SCENARIO"
    private static let pauseMillisecondsEnvironmentKey = "YEN_SETTINGS_HITCH_PAUSE_MS"
    private static let startFileEnvironmentKey = "YEN_SETTINGS_HITCH_START_FILE"

    private enum Scenario: String {
        case firstOpen = "first-open"
        case reopen
        case rapidTabs = "rapid-tabs"
        case soundsRefresh = "sounds-refresh"
    }

    static func maybeStart() {
        let environment = ProcessInfo.processInfo.environment
        guard let rawScenario = environment[scenarioEnvironmentKey],
              let scenario = Scenario(rawValue: rawScenario.lowercased()) else { return }

        let pauseMilliseconds = max(Int(environment[pauseMillisecondsEnvironmentKey] ?? "") ?? 120, 20)

        Task { @MainActor in
            await pause(milliseconds: 250)
            await waitForStartFileIfNeeded(environment: environment)
            await run(scenario: scenario, pauseMilliseconds: pauseMilliseconds)
        }
    }

    private static func run(scenario: Scenario, pauseMilliseconds: Int) async {
        let settings = SettingsController.shared

        logger.info("settings-hitch-benchmark starting scenario=\(scenario.rawValue, privacy: .public)")

        switch scenario {
        case .firstOpen:
            settings.show(pane: .appearance)
            await pause(milliseconds: pauseMilliseconds * 6)

        case .reopen:
            settings.show(pane: .appearance)
            await pause(milliseconds: pauseMilliseconds * 2)
            settings.hide()
            await pause(milliseconds: pauseMilliseconds * 2)
            settings.show(pane: .appearance)
            await pause(milliseconds: pauseMilliseconds * 4)

        case .rapidTabs:
            settings.show(pane: .appearance)
            await pause(milliseconds: pauseMilliseconds * 2)
            let panes = SettingsPane.allCases
            for _ in 0..<4 {
                for pane in panes {
                    settings.selectedSettingsPane = pane
                    await pause(milliseconds: pauseMilliseconds)
                }
            }

        case .soundsRefresh:
            settings.show(pane: .notifications)
            await pause(milliseconds: pauseMilliseconds * 2)
            settings.refreshNotificationAuthorizationStatus()
            settings.refreshDictationLocalSpeechServiceStatus()
            await pause(milliseconds: pauseMilliseconds * 2)
            settings.selectedSettingsPane = .dictation
            await pause(milliseconds: pauseMilliseconds * 2)
        }

        logger.info("settings-hitch-benchmark completed scenario=\(scenario.rawValue, privacy: .public)")
        NSApp.terminate(nil)
    }

    private static func pause(milliseconds: Int) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private static func waitForStartFileIfNeeded(environment: [String: String]) async {
        guard let path = environment[startFileEnvironmentKey], !path.isEmpty else { return }

        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: path), Date() < deadline {
            await pause(milliseconds: 50)
        }
    }

}
