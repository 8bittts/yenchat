import Foundation
import Testing
@testable import YEN

@MainActor
struct SystemSettingsOpenerTests {
    @Test func keyboardShortcutsDestinationPrefersShortcutsPaneBeforeFallback() {
        #expect(SystemSettingsOpener.keyboardShortcutsCandidates == [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ])
    }

    @Test func keyboardDictationDestinationPrefersDictationPaneBeforeFallback() {
        #expect(SystemSettingsOpener.keyboardDictationCandidates == [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard?Dictation",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ])
    }

    @Test func accessibilityDisplayDestinationPrefersDisplayPaneBeforeFallback() {
        #expect(SystemSettingsOpener.accessibilityDisplayCandidates == [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display",
            "x-apple.systempreferences:com.apple.Accessibility?Display",
            "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ])
    }

}
