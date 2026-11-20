import Combine
import SwiftUI

/// The engine's resolved terminal background, republished for chrome that sits
/// beside the terminal, such as the Tab Sidebar rail.
///
/// Chrome must read this value and never re-derive it from the theme catalog.
/// The engine loads the theme and then replays every loaded config file over
/// it, and it accepts references the catalog cannot match by name: an absolute
/// path, a `light:,dark:` pair, or no theme at all. Only the finalized config
/// holds the color the terminal draws.
@MainActor
final class TerminalChromeAppearance: ObservableObject {
    static let shared = TerminalChromeAppearance(config: AppDelegate.shared?.yen.config)

    @Published private(set) var backgroundColor: Color

    private var cancellables: Set<AnyCancellable> = []

    init(config: YEN.Config?, notificationCenter: NotificationCenter = .default) {
        self.backgroundColor = Self.resolvedBackgroundColor(for: config)

        notificationCenter.publisher(for: .yenConfigDidChange)
            .sink { [weak self] notification in
                // A surface-level change carries that surface as its object. Chrome
                // follows the app-level config, which is posted with a nil object.
                guard notification.object == nil,
                      let config = notification.userInfo?[
                          Notification.Name.YENConfigChangeKey
                      ] as? YEN.Config else { return }
                self?.apply(config)
            }
            .store(in: &cancellables)
    }

    private func apply(_ config: YEN.Config) {
        let updatedColor = Self.resolvedBackgroundColor(for: config)
        guard updatedColor != backgroundColor else { return }
        backgroundColor = updatedColor
    }

    private static func resolvedBackgroundColor(for config: YEN.Config?) -> Color {
        config?.backgroundColor ?? Color(NSColor.windowBackgroundColor)
    }
}

/// AppKit owns the tab buttons, overflow menu and drag behavior. Give their host
/// a preferred width, while its required trailing edge keeps narrow windows usable.
@MainActor
final class WorkspaceTabStrip {
    private weak var host: NSView?
    private weak var group: NSWindowTabGroup?
    private var preferredWidth: NSLayoutConstraint?
    private var observation: NSKeyValueObservation?
    private weak var controls: NSView?
    private var controlsGap: NSLayoutConstraint?

    static func start(_ view: NSView, at anchor: NSLayoutXAxisAnchor, inset: CGFloat = 0) -> NSLayoutConstraint {
        let start = view.leftAnchor.constraint(equalTo: anchor, constant: inset)
        start.priority = .defaultHigh
        return start
    }

    func place(after controls: NSView?) {
        if self.controls === controls, controlsGap?.isActive == true { return }
        controlsGap?.isActive = false
        controlsGap = nil
        self.controls = controls
        guard let host, let controls, host.ancestorShared(with: controls) != nil else { return }
        let gap = host.leadingAnchor.constraint(greaterThanOrEqualTo: controls.trailingAnchor, constant: 6)
        gap.isActive = true
        controlsGap = gap
    }

    func fit(_ view: NSView, to group: NSWindowTabGroup?) {
        if host === view, self.group === group, preferredWidth?.isActive == true { return }
        observation = nil
        preferredWidth?.isActive = false
        controlsGap?.isActive = false
        host = view
        place(after: controls)
        self.group = group
        let width = view.widthAnchor.constraint(equalToConstant: Self.width(for: group))
        // Let the window shrink below the preferred strip width when AppKit
        // measures its minimum size. The native tab bar handles overflow.
        width.priority = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.fittingSizeCompression.rawValue - 1)
        width.isActive = true
        preferredWidth = width
        observation = group?.observe(\.windows, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.preferredWidth?.constant = Self.width(for: self.group)
            }
        }
    }

    private static func width(for group: NSWindowTabGroup?) -> CGFloat {
        // Leave room for AppKit's new-tab control after the last tab.
        CGFloat(max(1, group?.windows.count ?? 1)) * 188 + 36
    }
}


/// Native leading accessory keeps both actions available when macOS hides
/// the traffic lights. AppKit positions it beside the system controls on reveal.
@MainActor
final class FullscreenWorkspaceControls: NSTitlebarAccessoryViewController {
    weak var terminalWindow: NSWindow?
    private var tabStrip: WorkspaceTabStrip? {
        if let window = terminalWindow as? TitlebarTabsTahoeTerminalWindow { return window.workspaceTabs }
        return (terminalWindow as? TitlebarTabsVenturaTerminalWindow)?.workspaceTabs
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tabStrip?.place(after: view)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        tabStrip?.place(after: nil)
    }

    override func loadView() {
        let sidebar = button("sidebar.left", "Toggle Tab Sidebar", #selector(toggleSidebar))
        let exit = button("arrow.down.right.and.arrow.up.left", "Exit Full Screen", #selector(leaveFullscreen))
        let buttons = NSStackView(views: [sidebar, exit])
        buttons.orientation = .horizontal
        buttons.spacing = 2
        buttons.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        buttons.frame.size = NSSize(width: 62, height: 28)
        view = buttons
        layoutAttribute = .left
    }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: icon, target: self, action: action)
        button.isBordered = false
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    @objc private func toggleSidebar() {
        TabSidebarController.shared.toggle(in: terminalWindow)
    }

    @objc private func leaveFullscreen() {
        terminalWindow?.toggleFullScreen(nil)
    }
}
