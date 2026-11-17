import AppKit
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsShellControlsTests {
    @Test func resetAllSettingsRestoresEveryGroupOfSettings() throws {
        try withIsolatedShellControlsContext { controller, _ in
            controller.selectedTheme = "Retro Theme"
            controller.backgroundOpacity = 0.45
            controller.windowBorderEnabled = true
            controller.windowBorderScope = .focusedSplit
            controller.windowBorderWidth = 6.5
            controller.windowBorderRadius = 18.0
            controller.windowBorderColorMode = .matchTheme
            controller.windowBorderFocusedPalette = .aurora
            controller.windowBorderUnfocusedPalette = .graphite
            controller.dictationLiveTranscriptPreviewEnabled = true
            controller.soundWhenFocused = false
            controller.bannerWhenFocused = true
            controller.keyboardRecordingActive = true
            controller.keybindEntries = []

            controller.resetAllSettingsToDefaultsForTesting()

            #expect(controller.selectedTheme.isEmpty)
            #expect(controller.backgroundOpacity == 1.0)
            #expect(!controller.windowBorderEnabled)
            #expect(controller.windowBorderScope == .window)
            #expect(controller.windowBorderWidth == 2.0)
            #expect(controller.windowBorderRadius == 10.0)
            #expect(controller.windowBorderColorMode == .manual)
            #expect(controller.windowBorderFocusedPalette == .defaultFocused)
            #expect(controller.windowBorderUnfocusedPalette == .defaultUnfocused)
            #expect(!controller.dictationLiveTranscriptPreviewEnabled)
            #expect(!DictationPreviewPreferences.liveTranscriptEnabled)
            #expect(controller.soundWhenFocused)
            #expect(!controller.bannerWhenFocused)
            #expect(NotificationSoundManager.shared.soundWhenFocused)
            #expect(!NotificationSoundManager.shared.bannerWhenFocused)
            #expect(!controller.keyboardRecordingActive)
            #expect(controller.keybindEntries.count == KeybindRegistry.defaults.count)
        }
    }

    @Test func restoreDefaultShortcutsRestoresShortcutsAndLeavesOtherSettingsAlone() throws {
        try withIsolatedShellControlsContext { controller, configURL in
            controller.loadKeybinds()
            let editable = try #require(controller.keybindEntries.first(where: { $0.isEditable }))
            let recorded = KeyTrigger(modifiers: KeyModifiers(cmd: true, ctrl: true, option: true), key: "u")
            #expect(controller.updateKeybind(stableId: editable.stableId, trigger: recorded) == .recorded)
            #expect(controller.keybindEntries.contains(where: { $0.isUserOverride }))

            controller.backgroundOpacity = 0.45
            controller.windowBorderEnabled = true
            controller.keyboardRecordingActive = true

            controller.restoreDefaultShortcutsForTesting()

            #expect(!controller.keyboardRecordingActive)
            #expect(controller.keybindEntries.count == KeybindRegistry.defaults.count)
            #expect(!controller.keybindEntries.contains(where: { $0.isUserOverride }))
            let restored = try #require(controller.keybindEntries.first(where: { $0.stableId == editable.stableId }))
            #expect(restored.currentTrigger == editable.defaultTrigger)
            // Only shortcuts are restored.
            #expect(controller.backgroundOpacity == 0.45)
            #expect(controller.windowBorderEnabled)

            let writtenConfig = try String(contentsOf: configURL, encoding: .utf8)
            #expect(!writtenConfig.contains(recorded.configString))
            #expect(writtenConfig.contains("background-opacity = 0.45"))
        }
    }

    @Test func liveTranscriptPreviewPersistsAndResets() throws {
        try withIsolatedShellControlsContext { controller, _ in
            controller.dictationLiveTranscriptPreviewEnabled = true

            #expect(controller.dictationLiveTranscriptPreviewEnabled)
            #expect(DictationPreviewPreferences.liveTranscriptEnabled)

            controller.resetAllSettingsToDefaultsForTesting()

            #expect(!controller.dictationLiveTranscriptPreviewEnabled)
            #expect(!DictationPreviewPreferences.liveTranscriptEnabled)
        }
    }

    @Test func focusBehaviorPersistsAndResets() throws {
        try withIsolatedShellControlsContext { controller, _ in
            controller.soundWhenFocused = false
            controller.bannerWhenFocused = true

            #expect(!NotificationSoundManager.shared.soundWhenFocused)
            #expect(NotificationSoundManager.shared.bannerWhenFocused)

            controller.resetAllSettingsToDefaultsForTesting()

            #expect(controller.soundWhenFocused)
            #expect(!controller.bannerWhenFocused)
            #expect(NotificationSoundManager.shared.soundWhenFocused)
            #expect(!NotificationSoundManager.shared.bannerWhenFocused)
        }
    }

    @Test func translateOnDictateSelectionTracksAvailableTargetsAndResets() throws {
        try withIsolatedShellControlsContext { controller, _ in
            controller.availableDictationTargetLanguages = [
                DictationTranslationLanguageCatalog.option(for: "es"),
                DictationTranslationLanguageCatalog.option(for: "fr")
            ]
            controller.translateOnDictateEnabled = true
            controller.dictationTranslateTargetLanguageIdentifier = "fr"

            #expect(controller.translateOnDictateEnabled)
            #expect(DictationTranslationPreferences.translateOnDictateEnabled)
            #expect(controller.dictationTranslateTargetLanguageIdentifier == "fr")
            #expect(DictationTranslationPreferences.targetLanguageIdentifier == "fr")

            controller.availableDictationTargetLanguages = [
                DictationTranslationLanguageCatalog.option(for: "es")
            ]
            #expect(controller.dictationTranslateTargetLanguageIdentifier == "es")
            #expect(DictationTranslationPreferences.targetLanguageIdentifier == "es")

            controller.availableDictationTargetLanguages = []
            #expect(!controller.translateOnDictateEnabled)
            #expect(!DictationTranslationPreferences.translateOnDictateEnabled)

            controller.availableDictationTargetLanguages = [
                DictationTranslationLanguageCatalog.option(for: "es"),
                DictationTranslationLanguageCatalog.option(for: "fr")
            ]
            controller.translateOnDictateEnabled = true
            #expect(controller.translateOnDictateEnabled)

            controller.resetAllSettingsToDefaultsForTesting()

            #expect(!controller.translateOnDictateEnabled)
            #expect(!DictationTranslationPreferences.translateOnDictateEnabled)
            #expect(
                controller.dictationTranslateTargetLanguageIdentifier
                    == SettingsController.normalizeDictationTranslationIdentifier(
                        DictationTranslationPreferences.preferredTargetLanguageIdentifier
                    )
            )
        }
    }

    @Test func capturedSettingsStateRestoresWhatAResetChanged() throws {
        try withIsolatedShellControlsContext { controller, configURL in
            try "font-size = 17\nbackground-opacity = 0.6\n".write(to: configURL, atomically: true, encoding: .utf8)
            controller.loadConfigForTesting()
            controller.windowBorderEnabled = true
            controller.soundWhenFocused = false
            controller.dictationLiveTranscriptPreviewEnabled = true
            let captured = controller.captureSettingsStateForTesting()

            controller.resetAllSettingsToDefaultsForTesting()
            #expect(controller.fontSize == 14)
            #expect(!controller.windowBorderEnabled)

            controller.restoreSettingsStateForTesting(captured)

            #expect(controller.fontSize == 17)
            #expect(controller.backgroundOpacity == 0.6)
            #expect(controller.windowBorderEnabled)
            #expect(!controller.soundWhenFocused)
            #expect(controller.dictationLiveTranscriptPreviewEnabled)
        }
    }

    private func withIsolatedShellControlsContext(
        _ operation: (SettingsController, URL) throws -> Void
    ) throws {
        try TestExclusiveLock.withLock(named: "settings-shell-controls") {
            let controller = SettingsController.shared
            let baselineState = controller.captureSettingsStateForTesting()
            let originalBackgroundImagePath = controller.backgroundImagePath
            let originalSelectedSettingsTab = controller.selectedSettingsPane
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("yen-settings-shell-\(UUID().uuidString)", isDirectory: true)
            let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try "font-size = 14\n".write(to: configURL, atomically: true, encoding: .utf8)

            SettingsController._testSetConfigPathOverride(configURL.path)
            controller.hide()
            drainMainRunLoop()
            controller._testResetWindowState()
            controller.resetKeybindReloadStateForTesting()
            controller._testResetStatusState()
            controller.applyConfigContentsForTesting("font-size = 14\n")

            defer {
                controller.hide()
                drainMainRunLoop()
                controller._testResetWindowState()
                controller.resetKeybindReloadStateForTesting()
                // Restores into the temporary config, never the real one.
                controller.restoreSettingsStateForTesting(baselineState)
                controller.backgroundImagePath = originalBackgroundImagePath
                controller.selectedSettingsPane = originalSelectedSettingsTab
                controller._testResetStatusState()
                SettingsController._testSetConfigPathOverride(nil)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            try operation(controller, configURL)
        }
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}
