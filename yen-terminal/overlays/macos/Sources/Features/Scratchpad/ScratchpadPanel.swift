#if os(macOS)
import Cocoa

final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        identifier = .init(rawValue: "com.yenchat.yen.scratchpad")
        setAccessibilitySubrole(.floatingWindow)
        title = "Scratchpad"
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .textBackgroundColor
        standardWindowButton(.zoomButton)?.isHidden = true
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
