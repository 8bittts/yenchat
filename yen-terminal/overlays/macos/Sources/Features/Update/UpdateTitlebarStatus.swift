import AppKit
import Combine
import SwiftUI

/// Shows the update status at the start of the titlebar, beside the window
/// buttons, in the same row as the workspace tabs.
///
/// It is not a toolbar item: once the tab bar sits in the toolbar, NSToolbar
/// has no room left and moves every item into its overflow menu. Like the tab
/// bar, the status is placed straight into the toolbar's view, and the tabs
/// start after it. The in-window overlay stays hidden while it can show
/// (`isShown(in:)`).
@MainActor
final class UpdateTitlebarStatus {
    private weak var window: TitlebarTabsTahoeTerminalWindow?
    private let host: NSView
    private var hostConstraints: [NSLayoutConstraint] = []
    private var stateObservation: AnyCancellable?

    /// Space between the zoom button and the status, matching the gap
    /// between the window buttons.
    private static let buttonGap: CGFloat = 12

    /// Returns nil for any window without titlebar tabs, which keeps the
    /// in-window overlay.
    init?(window: NSWindow?, model: UpdateViewModel?) {
        guard let model, let window = window as? TitlebarTabsTahoeTerminalWindow else { return nil }
        self.window = window
        host = NonDraggableHostingView(rootView: UpdateTab(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = model.state.isHidden
        stateObservation = model.$state.sink { [weak self] state in
            self?.host.isHidden = state.isHidden
            self?.attach()
        }
    }

    /// Places the status in the window's current toolbar view. AppKit moves
    /// the titlebar into another window in full screen and back, so the
    /// container calls this again after each layout; it does nothing when the
    /// status is already in place.
    func attach() {
        guard let window else { return }
        let toolbarView = window.titlebarView?.firstDescendant(withClassName: "NSToolbarView")
        if host.superview !== toolbarView {
            NSLayoutConstraint.deactivate(hostConstraints)
            hostConstraints = []
            host.removeFromSuperview()
            if let toolbarView {
                toolbarView.addSubview(host)
                hostConstraints = [
                    host.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: leadingInset(in: toolbarView)),
                    host.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
                ]
                NSLayoutConstraint.activate(hostConstraints)
            }
        } else if let toolbarView, let leading = hostConstraints.first {
            let inset = leadingInset(in: toolbarView)
            if leading.constant != inset { leading.constant = inset }
        }
        window.workspaceTabs.place(after: host.superview == nil || host.isHidden ? nil : host, as: .update)
    }

    func detach() {
        window?.workspaceTabs.place(after: nil, as: .update)
        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints = []
        host.removeFromSuperview()
    }

    private func leadingInset(in toolbarView: NSView) -> CGFloat {
        guard let zoom = window?.standardWindowButton(.zoomButton), !zoom.isHidden,
              let superview = zoom.superview else { return Self.buttonGap }
        return superview.convert(zoom.frame, to: toolbarView).maxX + Self.buttonGap
    }

    /// True when the update shows in the window's titlebar. Native full screen
    /// hides the titlebar until the pointer reaches the top edge, so the
    /// in-window overlay takes over there, as it does upstream.
    static func isShown(in window: NSWindow?) -> Bool {
        guard let window = window as? TitlebarTabsTahoeTerminalWindow,
              window.toolbar?.isVisible == true else { return false }
        if let controller = window.windowController as? BaseTerminalController,
           let fullscreenStyle = controller.fullscreenStyle {
            return !fullscreenStyle.isFullscreen
        }
        return !window.styleMask.contains(.fullScreen)
    }
}

/// The update status drawn like a native tab: a glass capsule with the state
/// icon, then the status in the tab title font. Clicking it opens the update
/// actions. The titlebar and the in-window overlay share it.
struct UpdateTab: View {

    @ObservedObject var model: UpdateViewModel

    @State private var showPopover = false
    @State private var resetTask: Task<Void, Never>?

    /// The tab title font, so the status reads at the same size as the tabs.
    static let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    var body: some View {
        if !model.state.isHidden {
            button
                .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                    UpdatePopoverView(model: model)
                }
                .onChange(of: model.state) { newState in
                    resetTask?.cancel()
                    guard case .notFound(let notFound) = newState else {
                        resetTask = nil
                        return
                    }
                    resetTask = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled, case .notFound = model.state else { return }
                        model.state = .idle
                        notFound.acknowledgement()
                    }
                }
        }
    }

    private var button: some View {
        Button(action: activate) {
            HStack(spacing: 6) {
                UpdateBadge(model: model)
                    .foregroundStyle(model.iconColor)
                    .frame(width: 14, height: 14)
                Text(model.text)
                    .font(Font(Self.titleFont))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Self.textWidth(for: model), alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: WorkspaceTabStrip.trackHeight)
            .glassEffect(.regular, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(model.text)
        .accessibilityLabel(model.text)
    }

    private func activate() {
        if case .notFound(let notFound) = model.state {
            model.state = .idle
            notFound.acknowledgement()
        } else {
            showPopover.toggle()
        }
    }

    /// A fixed width for the longest text of the current state, so progress
    /// updates do not resize the item.
    static func textWidth(for model: UpdateViewModel) -> CGFloat {
        let size = (model.maxWidthText as NSString).size(withAttributes: [.font: titleFont])
        return ceil(size.width)
    }
}
