import SwiftUI

/// A toast notification that briefly shows when configuration is reloaded.
///
/// Callers set `trigger` to a new UUID on each reload event. The toast
/// shows itself and auto-dismisses after 2 seconds. Because UUID is always
/// unique, `onChange` fires reliably even during rapid-fire reloads or
/// mid-fade-out — solving the stuck-toast bug where `onAppear` wouldn't
/// re-fire when the view was being removed by animation.
struct ConfigReloadToast: View {
    /// Set to a new `UUID()` each time the toast should appear.
    @Binding var trigger: UUID?
    var body: some View {
        MessageToast(
            trigger: $trigger,
            message: "Configuration reloaded",
            iconName: "checkmark.circle.fill",
            tintColor: Color(NSColor.systemGreen)
        )
    }
}

#Preview {
    ConfigReloadToast(trigger: .constant(UUID()))
        .frame(width: 400, height: 300)
        .background(Color.gray.opacity(0.3))
}
