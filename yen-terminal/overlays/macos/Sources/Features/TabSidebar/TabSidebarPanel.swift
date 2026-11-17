#if os(macOS)
import Cocoa

/// Panel for the transient vertical tab sidebar. It rests flush inside the terminal
/// window's left edge and never moves; its `EdgeRevealView` content slides out from
/// behind that edge. canBecomeKey = false keeps the terminal window focused.
class TabSidebarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: TabSidebarController.panelWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.identifier = .init(rawValue: "com.yenchat.yen.tabSidebar")
        self.setAccessibilitySubrole(.floatingWindow)
        // Disable AppKit's default window show/hide so only SlidingUtilityPanel owns motion.
        self.animationBehavior = .none
        self.isOpaque = false
        self.backgroundColor = .clear
        // The content slides inside a fixed frame; a window shadow is computed once and
        // would outline the full panel before the content arrives.
        self.hasShadow = false
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = true
        self.collectionBehavior = [.fullScreenAuxiliary]
    }

    required init?(coder: NSCoder) {
        fatalError("TabSidebarPanel does not support nib/storyboard instantiation")
    }
}
#endif
