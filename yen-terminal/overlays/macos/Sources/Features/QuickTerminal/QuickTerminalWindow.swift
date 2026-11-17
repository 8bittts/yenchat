import Cocoa

class QuickTerminalWindow: NSPanel {
    static let terminalFacingCornerRadius: CGFloat = YENDesignTokens.terminalFacingCornerRadius

    // Both of these must be true for windows without decorations to be able to
    // still become key/main and receive events.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func awakeFromNib() {
        super.awakeFromNib()

        // The quick terminal window isn't intended to be interacted with via
        // the window manager, so make it difficult to discover there.
        isExcludedFromWindowsMenu = true
        collectionBehavior.insert(.transient)

        identifier = .init(rawValue: "com.yenchat.yen.quickTerminal")
        setAccessibilitySubrole(.floatingWindow)
        animationBehavior = .none
        styleMask.remove(.titled)
        styleMask.insert(.nonactivatingPanel)
    }

    /// Applies only the terminal-facing mask after the native controller has
    /// established its frame. Positioning and animation remain vendor-native.
    func applyTerminalFacingCorners(for position: QuickTerminalPosition) {
        guard let contentView else { return }
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        let maskedCorners: CACornerMask
        switch position {
        case .top:
            maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .bottom:
            maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .left:
            maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .right:
            maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case .center:
            maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner,
            ]
        }

        layer.cornerRadius = Self.terminalFacingCornerRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = maskedCorners
        layer.masksToBounds = true
    }

    /// This is set to the frame prior to setting `contentView`. This is purely a hack to workaround
    /// bugs in older macOS versions (Ventura): https://github.com/yen-org/yen/pull/8026
    var initialFrame: NSRect?

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // If we find we have cached the "initial" frame, use that instead
        // the propagated one through the framework.
        super.setFrame(initialFrame ?? frameRect, display: flag)
    }
}
