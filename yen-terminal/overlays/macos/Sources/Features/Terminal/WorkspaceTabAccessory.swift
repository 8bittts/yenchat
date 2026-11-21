import AppKit

/// AppKit moves each window's accessory between tab buttons when a group changes.
/// Keep the icon host with its window and let the native button own all input.
final class WorkspaceTabAccessory: NSStackView {
    private var icons: PaneTabIconAccessory?
    private weak var tabWindow: NSWindow?
    private var leadingInset: NSLayoutConstraint?
    private let selection = WorkspaceTabHighlight()
    private weak var observedGroup: NSWindowTabGroup?
    private var selectionObservation: NSKeyValueObservation?

    func install(_ icons: PaneTabIconAccessory, for window: NSWindow) {
        selection.onWidthChange = { [weak icons] width in
            // At the native minimum tab width, give the title the icon's space.
            icons?.isHidden = width > 0 && width < 150
        }
        self.icons = icons
        tabWindow = window
        placeIcons()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        placeIcons()
    }

    override func layout() {
        super.layout()
        placeIcons()
    }

    private func placeIcons() {
        guard let icons else { return }
        let isTitlebar = tabWindow is TitlebarTabsTahoeTerminalWindow || tabWindow is TitlebarTabsVenturaTerminalWindow
        guard isTitlebar, let content = superview as? NSStackView,
              let title = content.views(in: .center).first as? NSStackView,
              title.identifier?.rawValue == "_titleContainerView" else {
            // Other AppKit layouts keep the pane icons in the standard accessory.
            if icons.superview !== self {
                selection.removeFromSuperview()
                selectionObservation = nil
                observedGroup = nil
                leadingInset?.isActive = false
                icons.isHidden = false
                icons.removeFromSuperview()
                insertArrangedSubview(icons, at: 0)
            }
            return
        }

        updateSelection(in: content)
        guard !title.views(in: .center).contains(icons) else { return }
        leadingInset?.isActive = false
        icons.removeFromSuperview()
        // Put the native close control beside the shortcut to free the leading margin.
        if let close = content.views(in: .leading).first(where: { $0.identifier?.rawValue == "_closeButton" }) {
            content.removeView(close)
            content.insertView(close, at: 0, in: .trailing)
        }
        title.insertView(icons, at: 0, in: .center)
        title.setCustomSpacing(8, after: icons)
        // Yield to truncation and native overflow in narrow windows.
        let inset = title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12)
        inset.priority = .defaultHigh
        inset.isActive = true
        leadingInset = inset
        updateTitleAppearance()
    }

    private func updateSelection(in content: NSStackView) {
        guard let tabWindow, let group = tabWindow.tabGroup, let parent = content.superview else { return }
        if selection.superview !== parent {
            selection.removeFromSuperview()
            selection.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(selection, positioned: .below, relativeTo: content)
            NSLayoutConstraint.activate([
                selection.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
                selection.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
                selection.topAnchor.constraint(equalTo: parent.topAnchor),
                selection.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            ])
        }
        if observedGroup !== group {
            observedGroup = group
            selectionObservation = group.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
                self?.updateTitleAppearance()
            }
        }
        updateTitleAppearance()
    }

    private func updateTitleAppearance() {
        guard let tabWindow else { return }
        let selected = tabWindow.tabGroup?.selectedWindow === tabWindow
        selection.isHidden = !selected
        guard let title = icons?.superview as? NSStackView, title !== self,
              let label = title.views(in: .center).first(where: { $0 is NSTextField }) as? NSTextField else { return }
        let font = (tabWindow as? TerminalWindow)?.titlebarFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        if label.font != font { label.font = font }
        let color = NSColor.labelColor
        if label.textColor != color { label.textColor = color }
    }
}

private final class WorkspaceTabHighlight: NSView {
    var onWidthChange: ((CGFloat) -> Void)?

    override func setFrameSize(_ size: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(size)
        if size.width != oldWidth { onWidthChange?(size.width) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.20).setFill()
        shape.fill()
    }
}
