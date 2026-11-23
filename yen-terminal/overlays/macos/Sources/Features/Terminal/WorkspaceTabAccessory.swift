import AppKit
import Combine

/// AppKit moves each window's accessory between tab buttons when a group changes.
/// The title leads the tab, then the pane count, then the close button, which takes
/// no room until the pointer is over the tab. The first and last mark sit the same
/// `edgeInset` from the pill's ends. Holding Command swaps the count for the native
/// tab shortcut. The native button owns all input.
final class WorkspaceTabAccessory: NSStackView {
    /// The system title face. AppKit's tab bar draws 11 pt regular unless the tab
    /// carries an attributed title.
    static let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    /// The inset of the title and of the last trailing mark from the pill's ends.
    static let edgeInset: CGFloat = 12
    /// The trailing inset while the close button shows. Its glyph sits about 4 pt
    /// inside the 16 pt button, so this puts the glyph's ink as far from the pill's
    /// edge as the title's and the count's ink, measured on a running tab.
    static let closeTrailingInset: CGFloat = 9

    private var splitCount: PaneTabIconAccessory?
    private weak var tabWindow: NSWindow?
    private weak var alignedTitle: NSStackView?
    private weak var alignedContent: NSStackView?
    private weak var closeButton: NSView?
    private var leadingInset: NSLayoutConstraint?
    private let selection = WorkspaceTabHighlight()
    private weak var observedGroup: NSWindowTabGroup?
    private var selectionObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var revealObservation: AnyCancellable?
    private var hoverArea: NSTrackingArea?
    private var isNarrow = false
    private var isRevealed = false
    private(set) var isHovered = false

    /// The engine's key-equivalent label, the only text field in this stack.
    private var shortcutLabel: NSTextField? {
        arrangedSubviews.lazy.compactMap { $0 as? NSTextField }.first
    }

    func install(_ splitCount: PaneTabIconAccessory, for window: NSWindow) {
        selection.onWidthChange = { [weak self] width in
            // At the native minimum tab width, give the title the count's space.
            self?.isNarrow = width > 0 && width < 150
            self?.updateTrailingContent()
        }
        self.splitCount = splitCount
        tabWindow = window
        // The engine resets the tab's attributed title whenever the title changes.
        titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateTitleAppearance() }
        }
        if splitCount.superview !== self {
            splitCount.removeFromSuperview()
            let index = shortcutLabel.flatMap { arrangedSubviews.firstIndex(of: $0) } ?? arrangedSubviews.count
            insertArrangedSubview(splitCount, at: index)
        }
        revealObservation = TabShortcutReveal.shared.$isRevealed
            .removeDuplicates()
            // `@Published` emits before it stores, so use the emitted value.
            .sink { [weak self] revealed in
                self?.isRevealed = revealed
                self?.updateTrailingContent()
            }
        alignTitle()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        alignTitle()
    }

    override func layout() {
        super.layout()
        alignTitle()
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }

    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// Shows the close button while the pointer is over the tab. AppKit fades it in
    /// on its own; detaching it the rest of the time lets the count take its place.
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateTrailingContent()
    }

    func updateTrailingContent() {
        if let shortcutLabel, shortcutLabel.isHidden == isRevealed { shortcutLabel.isHidden = !isRevealed }
        // A narrow tab gives the count's room to its title.
        let hidesCount = isRevealed || isNarrow || splitCount?.showsCount != true
        if let splitCount, splitCount.isHidden != hidesCount { splitCount.isHidden = hidesCount }
        guard let content = alignedContent else { return }
        let showsClose = isHovered
        // AppKit's tab stack keeps a hidden view's slot, so detach the button instead.
        if let closeButton {
            let priority: NSStackView.VisibilityPriority = showsClose ? .mustHold : .notVisible
            if content.visibilityPriority(for: closeButton) != priority {
                content.setVisibilityPriority(priority, for: closeButton)
            }
        }
        let trailing = showsClose ? Self.closeTrailingInset : Self.edgeInset
        if content.edgeInsets.right != trailing { content.edgeInsets.right = trailing }
    }

    private func alignTitle() {
        updateTrailingContent()
        let isTitlebar = tabWindow is TitlebarTabsTahoeTerminalWindow || tabWindow is TitlebarTabsVenturaTerminalWindow
        guard isTitlebar, let content = superview as? NSStackView,
              let title = content.views(in: .center).first as? NSStackView,
              title.identifier?.rawValue == "_titleContainerView" else {
            // Other AppKit layouts keep their native title placement.
            selection.removeFromSuperview()
            selectionObservation = nil
            observedGroup = nil
            leadingInset?.isActive = false
            alignedTitle = nil
            releaseContent()
            return
        }

        updateSelection(in: content)
        guard alignedTitle !== title || alignedContent !== content || leadingInset?.isActive != true else { return }
        leadingInset?.isActive = false
        releaseContent()
        // Put the native close control after the trailing content to free the leading margin.
        if let close = content.views.first(where: { $0.identifier?.rawValue == "_closeButton" }) {
            if content.views(in: .trailing).last !== close {
                content.removeView(close)
                content.addView(close, in: .trailing)
            }
            closeButton = close
        }
        // Lead with the title. Yield to truncation and native overflow in narrow windows.
        let inset = title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.edgeInset)
        inset.priority = .defaultHigh
        inset.isActive = true
        leadingInset = inset
        alignedTitle = title
        alignedContent = content
        trackHover(in: content)
        updateTrailingContent()
        updateTitleAppearance()
    }

    private func trackHover(in content: NSView) {
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        )
        content.addTrackingArea(area)
        hoverArea = area
        // A tab created under the pointer gets no entered event.
        if let window = content.window {
            isHovered = content.bounds.contains(content.convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }
    }

    /// Returns the tab button this accessory left to AppKit's own layout.
    private func releaseContent() {
        if let hoverArea { alignedContent?.removeTrackingArea(hoverArea) }
        hoverArea = nil
        isHovered = false
        if let closeButton, let alignedContent, alignedContent.views.contains(closeButton) {
            alignedContent.setVisibilityPriority(.mustHold, for: closeButton)
        }
        closeButton = nil
        alignedContent = nil
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
        guard let tabWindow, alignedTitle != nil else { return }
        let selected = tabWindow.tabGroup?.selectedWindow === tabWindow
        selection.isHidden = !selected
        let title = Self.attributedTitle(tabWindow.title, font: (tabWindow as? TerminalWindow)?.titlebarFont)
        if tabWindow.tab.attributedTitle != title { tabWindow.tab.attributedTitle = title }
        // The selected pill is muted, so the focus comes from the title's color.
        // AppKit replaces a color in the attributed title, so set it on the label.
        guard let label = alignedTitle?.views.first(where: { $0 is NSTextField }) as? NSTextField else { return }
        let color: NSColor = selected ? .labelColor : .secondaryLabelColor
        if label.textColor != color { label.textColor = color }
    }

    static func attributedTitle(_ title: String, font: NSFont?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: title, attributes: [.font: font ?? titleFont, .paragraphStyle: paragraph])
    }
}

/// Command alone reveals every tab's shortcut; any other modifier or leaving the
/// app hides them again, so a missed key-up cannot leave them on screen.
@MainActor
final class TabShortcutReveal: ObservableObject {
    static let shared = TabShortcutReveal()

    @Published private(set) var isRevealed = false

    private var monitor: Any?
    private var resignObservation: AnyCancellable?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { TabShortcutReveal.shared.update(event.modifierFlags) }
            return event
        }
        resignObservation = NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { _ in MainActor.assumeIsolated { TabShortcutReveal.shared.update([]) } }
    }

    func update(_ flags: NSEvent.ModifierFlags) {
        let revealed = flags.intersection([.command, .shift, .option, .control, .function]) == .command
        if isRevealed != revealed { isRevealed = revealed }
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
        // A low-contrast tint of the theme's own label color over the themed titlebar,
        // with a hairline edge so the pill reads in light and dark themes alike.
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.labelColor.withAlphaComponent(0.09).setFill()
        shape.fill()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }
}
