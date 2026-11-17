#if os(macOS)
import AppKit

/// Builds and chrome-configures the Settings host window, extracted from
/// `SettingsController.createWindow`. Owns only construction: geometry, title,
/// minimum size, initial frame placement, and the full-size-content chrome. The
/// controller still owns delegate wiring (`window.delegate = self`) and the
/// `window` reference itself, because `windowWillClose` cleanup lives there.
///
/// The `SettingsWindow` subclass separately enforces the no-toolbar invariant
/// on every write; `applyChrome` performs the initial one-shot setup.
@MainActor
enum SettingsWindowFactory {
    // First-launch content size. Width tracks the SwiftUI-declared ideal so the
    // window doesn't open narrower than its own "ideal" layout width.
    static let defaultContentSize = NSSize(width: SettingsSpacing.panelIdealWidth, height: 690)
    static let minimumContentHeight: CGFloat = 620
    static let defaultTitle = "YEN Settings"

    /// The HIG asks a settings window to show the visible pane in its title.
    static func title(for pane: SettingsPane) -> String {
        pane.rawValue
    }

    /// Dim the zoom button. AppKit can re-enable it when the window changes key
    /// state, so the controller calls this again from its delegate callbacks.
    static func dimZoomButton(_ window: NSWindow) {
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    /// Construct a fully chrome-configured Settings window hosting `contentView`.
    /// Restores `lastFrame` when provided, otherwise centers the window.
    static func makeWindow(contentView: NSView, lastFrame: NSRect?) -> SettingsWindow {
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            // No `.miniaturizable`: the HIG dims a settings window's minimize and zoom
            // buttons. The window stays resizable so the preview can grow.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = defaultTitle
        window.minSize = NSSize(
            width: SettingsSpacing.panelMinWidth,
            height: minimumContentHeight
        )
        window.contentView = contentView
        if let lastFrame {
            window.setFrame(lastFrame, display: false)
        } else {
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.toolbar = nil
        applyChrome(window)
        return window
    }

    /// Apply the Studio chrome: the content fills the window under a
    /// transparent titlebar, and the window itself is clear so the preview's
    /// opacity shows what is behind it.
    ///
    /// The title is hidden but still set to the pane name, which is what
    /// Mission Control, the Window menu and VoiceOver read.
    static func applyChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        dimZoomButton(window)
    }

    /// Break the window's retain graph so the SwiftUI `NSHostingView` tree and
    /// its reachable scroll/detail state can deallocate: drop the delegate (so a
    /// closing window stops calling back into `SettingsController`) and the
    /// content view. Idempotent — clearing an already-nil content view is a no-op.
    static func releaseWindowGraph(_ window: NSWindow) {
        window.delegate = nil
        window.contentView = nil
    }
}
#endif
