#if os(macOS)
import Cocoa

/// Panel for the right-side scratchpad. It rests flush inside the terminal window's
/// right edge and never moves; its `EdgeRevealView` content slides out from behind
/// that edge. canBecomeKey/canBecomeMain are true so text input works without extra
/// focus hacks.
final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ScratchpadController.panelWidth, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        identifier = .init(rawValue: "com.yenchat.yen.scratchpad")
        setAccessibilitySubrole(.floatingWindow)
        // Disable AppKit's default window show/hide so only SlidingUtilityPanel owns motion.
        animationBehavior = .none
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // The content slides inside a fixed frame; a window shadow is computed once and
        // would outline the full panel before the content arrives. The terminal window
        // supplies the depth, as it does for the Git drawer.
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = false
        hidesOnDeactivate = true
        collectionBehavior = [.fullScreenAuxiliary]
    }

    required init?(coder: NSCoder) {
        fatalError("ScratchpadPanel does not support nib/storyboard instantiation")
    }
}
#endif
