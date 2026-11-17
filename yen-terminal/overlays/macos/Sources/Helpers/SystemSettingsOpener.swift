#if os(macOS)
import Cocoa

/// Shared helper for opening macOS System Settings panes.
/// Tries each URL candidate in order — stops on the first that succeeds.
/// macOS versions use different URL schemes for the same pane, so callers
/// supply an ordered list of candidates (newest scheme first).
enum SystemSettingsOpener {
    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    static let keyboardShortcutsCandidates = [
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        "x-apple.systempreferences:com.apple.preference.keyboard"
    ]
    static let keyboardDictationCandidates = [
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation",
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        "x-apple.systempreferences:com.apple.preference.keyboard?Dictation",
        "x-apple.systempreferences:com.apple.preference.keyboard"
    ]
    static let accessibilityDisplayCandidates = [
        "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display",
        "x-apple.systempreferences:com.apple.Accessibility?Display",
        "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display",
        "x-apple.systempreferences:com.apple.preference.universalaccess"
    ]

    @MainActor
    static func openKeyboardShortcutsSettings() {
        open(candidates: keyboardShortcutsCandidates)
    }

    @MainActor
    static func openKeyboardDictationSettings() {
        open(candidates: keyboardDictationCandidates)
    }

    @MainActor
    static func openAccessibilityDisplaySettings() {
        open(candidates: accessibilityDisplayCandidates)
    }

    @MainActor
    static func open(candidates: [String]) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                activateSystemSettingsIfRunning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    activateSystemSettingsIfRunning()
                }
                return
            }
        }
        print("SystemSettingsOpener: all candidates failed to open — \(candidates)")
    }

    private static func activateSystemSettingsIfRunning() {
        if let settingsApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: settingsBundleIdentifier
        ).first {
            settingsApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}
#endif // os(macOS)
