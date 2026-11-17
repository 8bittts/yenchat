#if os(macOS)
import AppKit

/// Dedicated host window for the YEN Settings panel.
///
/// The content fills the whole window, under a transparent titlebar: the live
/// terminal preview is the window, and the controls float above it.
///
/// `toolbar` is forced to `nil` so SwiftUI cannot attach a window toolbar. The
/// inspector's pane switcher is the navigation, and a toolbar would add a
/// second strip above the preview. One-shot removal in
/// `SettingsWindowFactory.applyChrome(_:)` is not enough: SwiftUI can re-apply
/// a toolbar after attachment and on a full layout pass.
final class SettingsWindow: NSWindow {
    override var toolbar: NSToolbar? {
        get { nil }
        set { super.toolbar = nil }
    }
}
#endif
