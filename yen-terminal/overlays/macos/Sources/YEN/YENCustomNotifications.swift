import Foundation

// YEN-specific notification extensions not present in upstream.
// These are used by our overlay features (config reload toast, screenshot toast).

enum YENDistributedNotificationIdentifier {
    static let build = "com.yenchat.yen.buildNotification"
    static let webCommand = "com.yenchat.yen.webCommand"
    static let agentWorkingDirectory = "com.yenchat.yen.agentWorkingDirectory"
}

extension Notification.Name {
    /// Shared distributed-notification name for build notifications from hooks.
    static let yenBuildNotification = Notification.Name(YENDistributedNotificationIdentifier.build)

    /// Shared distributed-notification name for `yen web` browser commands.
    static let yenWebCommand = Notification.Name(YENDistributedNotificationIdentifier.webCommand)

    /// Shared distributed-notification name for `yen pane cwd` agent working-directory reports.
    static let yenAgentWorkingDirectory = Notification.Name(YENDistributedNotificationIdentifier.agentWorkingDirectory)

    /// Configuration was reloaded (via signal, menu action, or Settings panel). Shows toast notification.
    static let yenConfigDidReload = Notification.Name("com.yenchat.yen.configDidReload")

    /// Theme-tab state changed inside SettingsController.
    static let yenThemesSettingsDidChange = Notification.Name("com.yenchat.yen.themesSettingsDidChange")

    /// Keyboard-tab state changed inside SettingsController.
    static let yenKeyboardSettingsDidChange = Notification.Name("com.yenchat.yen.keyboardSettingsDidChange")

    /// Sounds-tab state changed inside SettingsController.
    static let yenSoundsSettingsDidChange = Notification.Name("com.yenchat.yen.soundsSettingsDidChange")

    /// General-tab state changed inside SettingsController.
    static let yenGeneralSettingsDidChange = Notification.Name("com.yenchat.yen.generalSettingsDidChange")

    /// Workspace-tab state changed inside SettingsController.
    static let yenWorkspaceSettingsDidChange = Notification.Name("com.yenchat.yen.workspaceSettingsDidChange")

    /// Screenshot status changed. Shows toast notification with best-available outcome detail.
    static let yenScreenshotCopied = Notification.Name("com.yenchat.yen.screenshotCopied")

    /// `String`: toast copy describing screenshot outcome.
    static let yenScreenshotToastMessageKey = "YENScreenshotToastMessage"

    /// `String`: typed screenshot outcome (`savedAndCopied`, `saved`, `copiedOnly`, `failure`).
    static let yenScreenshotOutcomeKey = "YENScreenshotOutcome"

    /// `Bool`: true when the screenshot file write succeeded.
    static let yenScreenshotSavedKey = "YENScreenshotSaved"

    /// `Bool`: true when PNG data was copied to clipboard.
    static let yenScreenshotClipboardCopiedKey = "YENScreenshotClipboardCopied"

    /// `String`: best-effort saved filename (basename only).
    static let yenScreenshotFilenameKey = "YENScreenshotFilename"

    /// `Int`: target window number for the screenshot toast presentation.
    static let yenScreenshotWindowNumberKey = "YENScreenshotWindowNumber"

    /// A disabled-feature toggle hotkey (⇧⌘B / ⇧⌘J) was pressed and swallowed
    /// because the feature is off. Shows a toast explaining why nothing happened.
    static let yenHotkeyDisabledToast = Notification.Name("com.yenchat.yen.hotkeyDisabledToast")

    /// `String`: toast copy naming the disabled feature and how to enable it.
    static let yenHotkeyDisabledMessageKey = "YENHotkeyDisabledMessage"

    /// `Int`: target window number for the disabled-hotkey toast presentation.
    static let yenHotkeyDisabledWindowNumberKey = "YENHotkeyDisabledWindowNumber"

    /// A layout preset was applied, rejected, or needs confirmation while the Settings
    /// window is CLOSED. Every `applyLayout` status used to render only in the Settings
    /// footer, so applying a layout from the File menu, a hotkey, or the command palette
    /// produced no feedback at all — on success or on any failure path.
    static let yenLayoutStatusToast = Notification.Name("com.yenchat.yen.layoutStatusToast")

    /// `String`: toast copy for the layout status.
    static let yenLayoutStatusMessageKey = "YENLayoutStatusMessage"

    /// `Int`: target window number for the layout status toast presentation.
    static let yenLayoutStatusWindowNumberKey = "YENLayoutStatusWindowNumber"

    /// `String`: `LayoutStatusSeverity` raw value, so the toast reads the same as the
    /// Settings footer would have (an error must not look like a success).
    static let yenLayoutStatusSeverityKey = "YENLayoutStatusSeverity"
}
