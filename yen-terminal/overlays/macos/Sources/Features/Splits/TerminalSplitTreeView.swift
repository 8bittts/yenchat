// YEN Overlay: replaces upstream macos/Sources/Features/Splits/TerminalSplitTreeView.swift
//
import AppKit
import SwiftUI

/// A single operation within the split tree.
///
/// Rather than binding the split tree (which is immutable), any mutable operations are
/// exposed via this enum to the embedder to handle.
enum TerminalSplitOperation {
    case resize(Resize)
    case drop(Drop)

    struct Resize {
        let node: SplitTree<YEN.SurfaceView>.Node
        let ratio: Double
    }

    struct Drop {
        /// The surface being dragged.
        let payload: YEN.SurfaceView

        /// The surface it was dragged onto
        let destination: YEN.SurfaceView

        /// The zone it was dropped to determine how to split the destination.
        let zone: TerminalSplitDropZone
    }
}

enum SplitPaneLabelForegroundRole {
    case light
    case dark
}

enum SplitPaneLabelRules {
    static let minimumWidth: CGFloat = 140
    static let minimumHeight: CGFloat = 80

    static func isVisible(
        enabled: Bool,
        isSplit: Bool,
        availableSize: CGSize
    ) -> Bool {
        guard enabled, isSplit else { return false }
        guard availableSize.width >= minimumWidth, availableSize.height >= minimumHeight else { return false }
        return true
    }

    /// A hand-typed label always wins; `worktreeLabel` is the "Name Panes After Worktree"
    /// value and is nil when that setting is off or the pane is not inside a repository.
    static func displayTitle(
        explicitLabel: String?,
        worktreeLabel: String? = nil,
        surfaceTitle: String,
        workingDirectory: String?
    ) -> String {
        let trimmedExplicitLabel = explicitLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedExplicitLabel.isEmpty {
            return trimmedExplicitLabel
        }

        let trimmedWorktreeLabel = worktreeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedWorktreeLabel.isEmpty {
            return trimmedWorktreeLabel
        }

        let trimmedTitle = surfaceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, trimmedTitle != "YEN" {
            return trimmedTitle
        }

        let trimmedWorkingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedWorkingDirectory.isEmpty {
            let leaf = URL(fileURLWithPath: trimmedWorkingDirectory).lastPathComponent
            if !leaf.isEmpty {
                return leaf
            }

            let abbreviated = NSString(string: trimmedWorkingDirectory).abbreviatingWithTildeInPath
            if !abbreviated.isEmpty {
                return abbreviated
            }
        }

        return "Terminal"
    }

    static func foregroundRole(backgroundColor: NSColor) -> SplitPaneLabelForegroundRole {
        backgroundColor.isLightColor ? .dark : .light
    }

    static func textColor(backgroundColor: NSColor) -> NSColor {
        switch foregroundRole(backgroundColor: backgroundColor) {
        case .light:
            return .white.withAlphaComponent(0.96)
        case .dark:
            return .black.withAlphaComponent(0.82)
        }
    }

    static func headerBackgroundColor(backgroundColor: NSColor) -> NSColor {
        if backgroundColor.isLightColor {
            let shaded = backgroundColor.blended(withFraction: 0.18, of: .black)
                ?? backgroundColor.shadow(withLevel: 0.18)
                ?? backgroundColor
            return shaded.withAlphaComponent(0.92)
        }

        let lifted = backgroundColor.blended(withFraction: 0.16, of: .white)
            ?? backgroundColor.highlight(withLevel: 0.16)
            ?? backgroundColor
        return lifted.withAlphaComponent(0.94)
    }

    static func borderColor(backgroundColor: NSColor) -> NSColor {
        switch foregroundRole(backgroundColor: backgroundColor) {
        case .light:
            return .white.withAlphaComponent(0.16)
        case .dark:
            return .black.withAlphaComponent(0.12)
        }
    }
}

enum SplitFocusClickHitTesting {
    static func surfaceOwnsWindowClick(surfaceView: NSView, eventLocationInWindow: NSPoint) -> Bool {
        guard let contentView = surfaceView.window?.contentView else { return false }
        let locationInContentView = contentView.convert(eventLocationInWindow, from: nil)
        return surfaceOwnsContentViewHit(
            surfaceView: surfaceView,
            contentView: contentView,
            locationInContentView: locationInContentView
        )
    }

    static func surfaceOwnsContentViewHit(
        surfaceView: NSView,
        contentView: NSView,
        locationInContentView: NSPoint
    ) -> Bool {
        guard let hitView = contentView.hitTest(locationInContentView) else { return false }
        return hitView === surfaceView || hitView.isDescendant(of: surfaceView)
    }
}

struct TerminalSplitTreeView: View {
    let tree: SplitTree<YEN.SurfaceView>
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            TerminalSplitSubtreeView(
                node: node,
                // A zoomed node becomes the rendered root, so its leaf should not
                // be treated as a split pane for label visibility.
                isRoot: true,
                action: action)
            // This is necessary because we can't rely on SwiftUI's implicit
            // structural identity to detect changes to this view. Due to
            // the tree structure of splits it could result in bad behaviors.
            // See: https://github.com/yen-org/yen/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct TerminalSplitSubtreeView: View {
    @EnvironmentObject var yen: YEN.App

    let node: SplitTree<YEN.SurfaceView>.Node
    var isRoot: Bool = false
    let action: (TerminalSplitOperation) -> Void

    var body: some View {
        switch node {
        case .leaf(let leafView):
            TerminalSplitLeaf(surfaceView: leafView, isSplit: !isRoot, action: action)

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    action(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: yen.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    TerminalSplitSubtreeView(node: split.left, action: action)
                },
                right: {
                    TerminalSplitSubtreeView(node: split.right, action: action)
                },
                onEqualize: {
                    guard let surface = node.leftmostLeaf().surface else { return }
                    yen.splitEqualize(surface: surface)
                }
            )
        }
    }
}

private struct TerminalSplitLeaf: View {
    @ObservedObject var surfaceView: YEN.SurfaceView
    let isSplit: Bool
    let action: (TerminalSplitOperation) -> Void

    @ObservedObject private var splitPaneLabelSettings = SplitPaneLabelSettings.shared
    @State private var dropState: DropState = .idle
    @State private var isSelfDragging: Bool = false
    @EnvironmentObject private var yen: YEN.App

    var body: some View {
        GeometryReader { geometry in
            let showSplitLabel = SplitPaneLabelRules.isVisible(
                enabled: splitPaneLabelSettings.isEnabled,
                isSplit: isSplit,
                availableSize: geometry.size
            )

            VStack(spacing: 0) {
                if showSplitLabel {
                    SplitPaneLabelView(surfaceView: surfaceView, dragEnabled: yen.config.dragHandle != .never)
                }
                YEN.InspectableSurface(surfaceView: surfaceView, isSplit: isSplit)
                    .environment(\.paneHeaderVisible, showSplitLabel)
            }
            .background {
                // If we're dragging ourself, we hide the entire drop zone. This makes
                // it so that a released drop animates back to its source properly
                // so it is a proper invalid drop zone.
                if !isSelfDragging {
                    Color.clear
                        .onDrop(of: [.yenSurfaceId], delegate: SplitDropDelegate(
                            dropState: $dropState,
                            viewSize: geometry.size,
                            destinationSurface: surfaceView,
                            action: action
                        ))
                }
            }
            .overlay {
                if !isSelfDragging, case .dropping(let zone) = dropState {
                    zone.overlay(in: geometry)
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(YEN.DraggingSurfaceKey.self) { value in
                isSelfDragging = value == surfaceView.id
                if isSelfDragging {
                    dropState = .idle
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal pane")
        }
    }

    private enum DropState: Equatable {
        case idle
        case dropping(TerminalSplitDropZone)
    }

    private struct SplitDropDelegate: DropDelegate {
        @Binding var dropState: DropState
        let viewSize: CGSize
        let destinationSurface: YEN.SurfaceView
        let action: (TerminalSplitOperation) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.yenSurfaceId])
        }

        func dropEntered(info: DropInfo) {
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            // For some reason dropUpdated is sent after performDrop is called
            // and we don't want to reset our drop zone to show it so we have
            // to guard on the state here.
            guard case .dropping = dropState else { return DropProposal(operation: .forbidden) }
            dropState = .dropping(.calculate(at: info.location, in: viewSize))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            dropState = .idle
        }

        func performDrop(info: DropInfo) -> Bool {
            let zone = TerminalSplitDropZone.calculate(at: info.location, in: viewSize)
            dropState = .idle

            // Load the dropped surface asynchronously using Transferable
            let providers = info.itemProviders(for: [.yenSurfaceId])
            guard let provider = providers.first else { return false }

            // Capture action before the async closure
            _ = provider.loadTransferable(type: YEN.SurfaceView.self) { [weak destinationSurface] result in
                switch result {
                case .success(let sourceSurface):
                    DispatchQueue.main.async {
                        // Don't allow dropping on self
                        guard let destinationSurface else { return }
                        guard sourceSurface !== destinationSurface else { return }
                        action(.drop(.init(payload: sourceSurface, destination: destinationSurface, zone: zone)))
                    }

                case .failure:
                    break
                }
            }

            return true
        }
    }
}

private struct SplitPaneLabelView: View {
    @ObservedObject var surfaceView: YEN.SurfaceView
    @ObservedObject private var labelState: SplitPaneLabelState
    /// Observed only to redraw when an agent reports or drops a directory; the value is read
    /// through `surfaceView.effectiveWorkingDirectory`, which also checks the report is still live.
    @ObservedObject private var agentWorkingDirectory: AgentWorkingDirectoryState
    @ObservedObject private var splitPaneLabelSettings = SplitPaneLabelSettings.shared
    @ObservedObject private var worktreeLabels = SplitPaneWorktreeLabelStore.shared
    let dragEnabled: Bool
    @State private var isDragging = false
    @State private var isHovering = false

    init(surfaceView: YEN.SurfaceView, dragEnabled: Bool) {
        self.surfaceView = surfaceView
        self.dragEnabled = dragEnabled
        _labelState = ObservedObject(wrappedValue: surfaceView.splitPaneLabelState)
        _agentWorkingDirectory = ObservedObject(wrappedValue: surfaceView.agentWorkingDirectoryState)
    }

    private var baseBackgroundColor: NSColor {
        let color = surfaceView.backgroundColor ?? surfaceView.derivedConfig.backgroundColor
        return NSColor(color)
    }

    private func displayTitle(for activity: PaneActivity) -> String {
        SplitPaneLabelRules.displayTitle(
            explicitLabel: labelState.label,
            worktreeLabel: worktreeLabel,
            surfaceTitle: activity.agentName ?? surfaceView.title,
            workingDirectory: surfaceView.effectiveWorkingDirectory
        )
    }

    private var worktreeLabel: String? {
        guard let directory = worktreeWatchDirectory else { return nil }
        return worktreeLabels.label(forWorkingDirectory: directory)
    }

    /// The directory this header keeps polled, or nil when worktree naming is off. An agent's
    /// reported worktree wins over the shell's `pwd` while that agent runs.
    private var worktreeWatchDirectory: String? {
        guard splitPaneLabelSettings.isWorktreeNamingEnabled else { return nil }
        return surfaceView.effectiveWorkingDirectory
    }

    var body: some View {
        PaneActivityReader(surface: surfaceView) { activity in
            let directory = surfaceView.effectiveWorkingDirectory.map { NSString(string: $0).abbreviatingWithTildeInPath }
            let title = displayTitle(for: activity)
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    PaneActivityIcon(activity: activity)
                    Text(title)
                        .settingsScaledSystemFont(size: 11, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    if let directory, directory != title {
                        Text(directory)
                            .settingsScaledSystemFont(size: 11)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .opacity(0.68)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    if dragEnabled {
                        YEN.SurfaceDragSource(surfaceView: surfaceView, isDragging: $isDragging, isHovering: $isHovering)
                    } else {
                        Color.clear.contentShape(Rectangle()).onTapGesture { focusSurface() }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Focus pane: \(title)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { focusSurface() }
                .help(dragEnabled ? "Click to focus. Drag to move this pane." : "Click to focus this pane.")

                Button(action: renameSurface) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 0.85 : 0.55)
                .help("Rename split label")
                .accessibilityLabel("Rename split label: \(title)")
            }
            .frame(height: 26)
            .foregroundStyle(Color(nsColor: SplitPaneLabelRules.textColor(backgroundColor: baseBackgroundColor)))
            .background(Color(nsColor: SplitPaneLabelRules.headerBackgroundColor(backgroundColor: baseBackgroundColor)))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(nsColor: SplitPaneLabelRules.borderColor(backgroundColor: baseBackgroundColor)))
                    .frame(height: 1).allowsHitTesting(false)
            }
        }
        .task(id: worktreeWatchDirectory) { [worktreeWatchDirectory] in
            await worktreeLabels.watch(workingDirectory: worktreeWatchDirectory)
        }
    }

    private func focusSurface() {
        if let window = surfaceView.window {
            window.makeFirstResponder(surfaceView)
        } else {
            YEN.moveFocus(to: surfaceView)
        }
    }

    private func renameSurface() {
        focusSurface()
        surfaceView.promptSplitPaneLabel()
    }
}

private struct PaneHeaderVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var paneHeaderVisible: Bool {
        get { self[PaneHeaderVisibleKey.self] }
        set { self[PaneHeaderVisibleKey.self] = newValue }
    }
}

enum TerminalSplitDropZone: String, Equatable {
    case top
    case bottom
    case left
    case right

    /// Determines which drop zone the cursor is in based on proximity to edges.
    ///
    /// Divides the view into four triangular regions by drawing diagonals from
    /// corner to corner. The drop zone is determined by which edge the cursor
    /// is closest to, creating natural triangular hit regions for each side.
    static func calculate(at point: CGPoint, in size: CGSize) -> TerminalSplitDropZone {
        let relX = point.x / size.width
        let relY = point.y / size.height

        let distToLeft = relX
        let distToRight = 1 - relX
        let distToTop = relY
        let distToBottom = 1 - relY

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        if minDist == distToLeft { return .left }
        if minDist == distToRight { return .right }
        if minDist == distToTop { return .top }
        return .bottom
    }

    @ViewBuilder
    func overlay(in geometry: GeometryProxy) -> some View {
        let overlayColor = Color.accentColor.opacity(0.3)

        switch self {
        case .top:
            VStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
                Spacer()
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(height: geometry.size.height / 2)
            }
        case .left:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
                Spacer()
            }
        case .right:
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(overlayColor)
                    .frame(width: geometry.size.width / 2)
            }
        }
    }
}
