import SwiftUI
import AppKit

/// A toast shown when a disabled feature's toggle hotkey (⇧⌘B Tab Sidebar,
/// ⇧⌘J Scratchpad) is pressed and swallowed. Without it the only feedback is
/// `NSSound.beep()`, which is opaque — and, under the "flash the screen when an
/// alert sound occurs" accessibility setting, renders as a silent whole-app
/// flash indistinguishable from a malfunction.
///
/// Wraps the shared `MessageToast` presenter with the disabled-feature copy and
/// Workspace deep link. Callers set `trigger` to a new UUID to show it.
struct HotkeyDisabledToast: View {
    /// Set to a new `UUID()` each time the toast should appear.
    @Binding var trigger: UUID?
    @Binding var message: String
    var body: some View {
        MessageToast(
            trigger: $trigger,
            message: message,
            iconName: "info.circle.fill",
            tintColor: .secondary,
            actionTitle: "Open Settings",
            actionAccessibilityHint: "Opens the General pane in YEN Settings",
            action: { SettingsController.shared.show(pane: .general) }
        )
    }
}

#Preview {
    HotkeyDisabledToast(
        trigger: .constant(UUID()),
        message: .constant("Tab Sidebar is off — enable it in Settings › Workspace")
    )
        .frame(width: 400, height: 300)
        .background(Color.gray.opacity(0.3))
}
