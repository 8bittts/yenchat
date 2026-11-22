import AppKit
import Combine

/// AppKit moves each window's accessory between tab buttons when a group changes.
/// The title leads the tab and the split count trails it. Holding Command swaps
/// the count for the native tab shortcut. The native button owns all input.
final class WorkspaceTabAccessory: NSStackView {
    private var splitCount: PaneTabIconAccessory?
    private weak var tabWindow: NSWindow?
    private weak var alignedTitle: NSStackView?
    private var leadingInset: NSLayoutConstraint?
    private let selection = WorkspaceTabHighlight()
    private weak var observedGroup: NSWindowTabGroup?
    private var selectionObservation: NSKeyValueObservation?
    private var revealObservation: AnyCancellable?
    private var isNarrow = false
    private var isRevealed = false

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

    private func updateTrailingContent() {
        if let shortcutLabel, shortcutLabel.isHidden == isRevealed { shortcutLabel.isHidden = !isRevealed }
        let hidesCount = isRevealed || isNarrow
        if let splitCount, splitCount.isHidden != hidesCount { splitCount.isHidden = hidesCount }
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
            return
        }

        updateSelection(in: content)
        guard alignedTitle !== title || leadingInset?.isActive != true else { return }
        leadingInset?.isActive = false
        // Put the native close control beside the trailing content to free the leading margin.
        if let close = content.views(in: .leading).first(where: { $0.identifier?.rawValue == "_closeButton" }) {
            content.removeView(close)
            content.insertView(close, at: 0, in: .trailing)
        }
        // Lead with the title. Yield to truncation and native overflow in narrow windows.
        let inset = title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12)
        inset.priority = .defaultHigh
        inset.isActive = true
        leadingInset = inset
        alignedTitle = title
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
        guard let label = alignedTitle?.views(in: .center).first(where: { $0 is NSTextField }) as? NSTextField else { return }
        let font = (tabWindow as? TerminalWindow)?.titlebarFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        if label.font != font { label.font = font }
        // The selected pill is muted, so the title weight of the focus comes from its text.
        let color: NSColor = selected ? .labelColor : .secondaryLabelColor
        if label.textColor != color { label.textColor = color }
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
