#if os(macOS)
    import AppKit

    /// Centralizes the "this feature is off" toast shown when a user tries to
    /// invoke a disabled feature's toggle (⇧⌘B Tab Sidebar, ⇧⌘J Scratchpad —
    /// via the hotkey consume path in `AppDelegate` or the Command Palette entry
    /// that reaches each controller's `toggle()` guard). Keeping the copy and the
    /// notification in one place stops the three swallow sites from drifting.
    ///
    /// `TerminalView` renders the toast via `.onReceive(.yenHotkeyDisabledToast)`
    /// filtered to the focused window, so the post carries only the message and a
    /// window number (never the window itself — no retention).
    ///
    /// Left nonisolated (not `@MainActor`) so the `AppDelegate` event-monitor
    /// consume path — a synchronous nonisolated context, always delivered on the
    /// main thread — can call it, matching the original inline `NSApp` access.
    enum DisabledFeatureToast {
        static func post(featureName: String) {
            NotificationCenter.default.post(
                name: .yenHotkeyDisabledToast,
                object: nil,
                userInfo: [
                    Notification.Name.yenHotkeyDisabledMessageKey:
                        "\(featureName) is off — enable it in Settings › Workspace",
                    Notification.Name.yenHotkeyDisabledWindowNumberKey:
                        NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber ?? 0,
                ]
            )
        }
    }
#endif
