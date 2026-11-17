import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsLoadConfigNotificationTests {
    @Test func loadConfigPublishesCoalescedSectionNotificationsInFirstMutationOrder() throws {
        try withIsolatedSettingsNotificationContext { controller, configURL in
            controller.applyConfigContentsForTesting(
                """
                font-size = 19
                notify-on-command-finish = always
                background-opacity = 0.35
                theme = Initial Theme
                """
            )
            try """
            font-size = 17
            notify-on-command-finish = unfocused
            background-opacity = 0.65
            theme = Config Theme
            """.write(to: configURL, atomically: true, encoding: .utf8)

            let recorder = SettingsNotificationRecorder(controller: controller)
            defer { recorder.stop() }

            controller.loadConfigForTesting()

            let keybindEntryCount = controller.keybindEntries.count
            let expectedEvents: [SettingsNotificationEvent] = [
                event(.general, fontSize: 17, notify: "unfocused", opacity: 0.65, theme: "Config Theme", keybinds: keybindEntryCount),
                event(.sounds, fontSize: 17, notify: "unfocused", opacity: 0.65, theme: "Config Theme", keybinds: keybindEntryCount),
                event(.terminalPresentation, fontSize: 17, notify: "unfocused", opacity: 0.65, theme: "Config Theme", keybinds: keybindEntryCount),
                event(.themes, fontSize: 17, notify: "unfocused", opacity: 0.65, theme: "Config Theme", keybinds: keybindEntryCount),
            ]
            #expect(recorder.events == expectedEvents)
        }
    }

    @Test func resetAllSettingsPublishesCoalescedSectionNotificationsInFirstMutationOrder() throws {
        try withIsolatedSettingsNotificationContext { controller, _ in
            controller.applyConfigContentsForTesting(
                """
                font-size = 19
                notify-on-command-finish = always
                background-opacity = 0.35
                theme = Initial Theme
                """
            )
            controller.keybindEntries = []
            let defaultsKeybindCount = KeybindRegistry.defaults.count

            let recorder = SettingsNotificationRecorder(controller: controller)
            defer { recorder.stop() }

            controller.resetAllSettingsToDefaultsForTesting()

            let expectedEvents: [SettingsNotificationEvent] = [
                event(.general, fontSize: 14, notify: "never", opacity: 1.0, theme: "", keybinds: defaultsKeybindCount),
                event(.sounds, fontSize: 14, notify: "never", opacity: 1.0, theme: "", keybinds: defaultsKeybindCount),
                event(.terminalPresentation, fontSize: 14, notify: "never", opacity: 1.0, theme: "", keybinds: defaultsKeybindCount),
                event(.themes, fontSize: 14, notify: "never", opacity: 1.0, theme: "", keybinds: defaultsKeybindCount),
                event(.keyboard, fontSize: 14, notify: "never", opacity: 1.0, theme: "", keybinds: defaultsKeybindCount),
            ]
            #expect(recorder.events == expectedEvents)
        }
    }

    private func withIsolatedSettingsNotificationContext(
        _ operation: (SettingsController, URL) throws -> Void
    ) throws {
        try TestExclusiveLock.withLock(named: "settings-load-config-notifications") {
            let controller = SettingsController.shared
            let baselineState = controller.captureSettingsStateForTesting()
            let originalSelectedSettingsTab = controller.selectedSettingsPane
            let originalBackgroundImagePath = controller.backgroundImagePath
            let originalKeybindEntries = controller.keybindEntries
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("yen-settings-notifications-\(UUID().uuidString)", isDirectory: true)
            let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try "font-size = 14\n".write(to: configURL, atomically: true, encoding: .utf8)

            SettingsController._testSetConfigPathOverride(configURL.path)
            controller.hide()
            drainMainRunLoop()
            controller._testResetWindowState()
            controller._testResetStatusState()
            controller.resetKeybindReloadStateForTesting()
            resetNonConfigNotificationInputs(controller)
            controller.applyConfigContentsForTesting("font-size = 14\n")

            defer {
                controller.hide()
                drainMainRunLoop()
                controller._testResetWindowState()
                controller._testResetStatusState()
                controller.resetKeybindReloadStateForTesting()
                // Restores into the temporary config, never the real one.
                controller.restoreSettingsStateForTesting(baselineState)
                controller.selectedSettingsPane = originalSelectedSettingsTab
                controller.backgroundImagePath = originalBackgroundImagePath
                controller.keybindEntries = originalKeybindEntries
                SettingsController._testSetConfigPathOverride(nil)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            try operation(controller, configURL)
        }
    }

    private func resetNonConfigNotificationInputs(_ controller: SettingsController) {
        controller.selectedSettingsPane = .general
        controller.keyboardRecordingActive = false
        controller.resetKeybindReloadStateForTesting()
        controller.tabSidebarEnabled = TabSidebarPreferences.defaultEnabled
        controller.tabSidebarPresentationMode = TabSidebarPreferences.defaultPresentationMode
        controller.splitPaneLabelsEnabled = SplitPaneLabelsPreferences.defaultEnabled
        controller.browserTerminalLinkCaptureEnabled = NativeBrowserPreferences.defaultTerminalLinkCaptureEnabled
        controller.browserSplitEnabled = NativeBrowserPreferences.defaultBrowserSplitEnabled
        controller.scratchpadEnabled = true
        controller.backgroundImageScope = BackgroundImageScopePreferences.defaultScope
        controller.windowBorderEnabled = false
        controller.windowBorderScope = .window
        controller.windowBorderWidth = 2.0
        controller.windowBorderRadius = 10.0
        controller.windowBorderColorMode = .manual
        controller.windowBorderFocusedPalette = .defaultFocused
        controller.windowBorderUnfocusedPalette = .defaultUnfocused
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    private func event(
        _ kind: SettingsNotificationKind,
        fontSize: Double,
        notify: String,
        opacity: Double,
        theme: String,
        keybinds: Int
    ) -> SettingsNotificationEvent {
        SettingsNotificationEvent(
            kind,
            snapshot: SettingsNotificationSnapshot(
                fontSize: fontSize,
                notifyOnCommandFinish: notify,
                backgroundOpacity: opacity,
                selectedTheme: theme,
                keybindEntryCount: keybinds
            )
        )
    }
}

private enum SettingsNotificationKind: String, Equatable, CustomStringConvertible {
    case terminalPresentation
    case splitPaneLabel
    case workspace
    case general
    case sounds
    case themes
    case keyboard

    var description: String { rawValue }
}

private struct SettingsNotificationSnapshot: Equatable, CustomStringConvertible {
    let fontSize: Double
    let notifyOnCommandFinish: String
    let backgroundOpacity: Double
    let selectedTheme: String
    let keybindEntryCount: Int

    @MainActor
    init(
        fontSize: Double,
        notifyOnCommandFinish: String,
        backgroundOpacity: Double,
        selectedTheme: String,
        keybindEntryCount: Int
    ) {
        self.fontSize = fontSize
        self.notifyOnCommandFinish = notifyOnCommandFinish
        self.backgroundOpacity = backgroundOpacity
        self.selectedTheme = selectedTheme
        self.keybindEntryCount = keybindEntryCount
    }

    @MainActor
    init(controller: SettingsController) {
        self.fontSize = controller.fontSize
        self.notifyOnCommandFinish = controller.notifyOnCommandFinish
        self.backgroundOpacity = controller.backgroundOpacity
        self.selectedTheme = controller.selectedTheme
        self.keybindEntryCount = controller.keybindEntries.count
    }

    var description: String {
        "fontSize=\(fontSize), notify=\(notifyOnCommandFinish), opacity=\(backgroundOpacity), theme=\(selectedTheme), keybinds=\(keybindEntryCount)"
    }
}

private struct SettingsNotificationEvent: Equatable, CustomStringConvertible {
    let kind: SettingsNotificationKind
    let snapshot: SettingsNotificationSnapshot

    init(_ kind: SettingsNotificationKind, snapshot: SettingsNotificationSnapshot) {
        self.kind = kind
        self.snapshot = snapshot
    }

    var description: String {
        "\(kind): \(snapshot)"
    }
}

@MainActor
private final class SettingsNotificationRecorder {
    private let controller: SettingsController
    private var observers: [NSObjectProtocol] = []
    private(set) var events: [SettingsNotificationEvent] = []

    init(controller: SettingsController) {
        self.controller = controller
        let notifications: [(Notification.Name, SettingsNotificationKind)] = [
            (.yenTerminalPresentationSettingsDidChange, .terminalPresentation),
            (.yenSplitPaneLabelSettingsDidChange, .splitPaneLabel),
            (.yenWorkspaceSettingsDidChange, .workspace),
            (.yenGeneralSettingsDidChange, .general),
            (.yenSoundsSettingsDidChange, .sounds),
            (.yenThemesSettingsDidChange, .themes),
            (.yenKeyboardSettingsDidChange, .keyboard),
        ]

        observers = notifications.map { name, kind in
            NotificationCenter.default.addObserver(
                forName: name,
                object: controller,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.events.append(
                        SettingsNotificationEvent(
                            kind,
                            snapshot: SettingsNotificationSnapshot(controller: self.controller)
                        )
                    )
                }
            }
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
