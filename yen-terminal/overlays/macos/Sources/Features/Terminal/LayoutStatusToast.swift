import SwiftUI
import AppKit

/// A toast for layout-preset feedback (`applyLayout`) when the Settings window is
/// closed and its footer — the only place these messages used to appear — is not
/// on screen.
///
/// Deliberately NOT `HotkeyDisabledToast`: that view hardcodes an "Open Settings"
/// action, an info tint, and the disabled-feature accessibility hint. Reusing it
/// gave "Layout applied" a bogus button, made an error indistinguishable from a
/// success, and — because `MessageToast` keeps an actionable toast on screen much
/// longer — left a 2-second status sitting there.
struct LayoutStatusToast: View {
    /// Set to a new `UUID()` each time the toast should appear.
    @Binding var trigger: UUID?
    @Binding var message: String
    /// Mirrors `SettingsStatusSeverity`, carried through the notification so the
    /// terminal toast reads the same as the Settings footer would have.
    @Binding var severity: LayoutStatusSeverity

    var body: some View {
        MessageToast(
            trigger: $trigger,
            message: message,
            iconName: severity.iconName,
            tintColor: severity.tintColor
            // No action deliberately: layout status is informational, and an actionable
            // toast stays on screen far longer than these 2-4 second messages want.
            // `MessageToast`'s action parameters already default to nil.
        )
    }
}

/// Severity for a layout status toast. Mirrors the `SettingsStatusSeverity` cases
/// that `applyLayout` actually emits, kept separate so the terminal surface does
/// not need to import the Settings status type.
enum LayoutStatusSeverity: String {
    case success
    case info
    case warning
    case error

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .success: return Color(NSColor.systemGreen)
        case .info: return .secondary
        case .warning: return Color(NSColor.systemOrange)
        case .error: return Color(NSColor.systemRed)
        }
    }
}

#Preview {
    LayoutStatusToast(
        trigger: .constant(UUID()),
        message: .constant("Press Single Pane again to close the other panes"),
        severity: .constant(.warning)
    )
        .frame(width: 400, height: 300)
        .background(Color.gray.opacity(0.3))
}
