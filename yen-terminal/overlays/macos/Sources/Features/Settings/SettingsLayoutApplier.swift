#if os(macOS)
import AppKit
import YENKit

@MainActor
final class SettingsLayoutApplier {
    typealias StatusHandler = @MainActor (String, SettingsStatusSeverity, TimeInterval, NSWindow?) -> Void
    typealias SurfaceFactory = @MainActor (yen_app_t, YEN.SurfaceConfiguration?) -> YEN.SurfaceView

    private static let destructiveLayoutConfirmationTimeout: Duration = .seconds(4)
    private let layoutConfirmationClock = ContinuousClock()
    private let statusHandler: StatusHandler
    private let makeSurface: SurfaceFactory
    private weak var lastFocusedTerminalController: BaseTerminalController?
    private var pendingLayoutConfirmation: PendingLayoutConfirmation?

    private struct PendingLayoutConfirmation {
        let controllerIdentifier: ObjectIdentifier
        let focusedSurfaceIdentifier: UUID
        let layout: LayoutTemplate
        let issuedAt: ContinuousClock.Instant
    }

    init(
        showStatus: @escaping StatusHandler,
        makeSurface: @escaping SurfaceFactory = { YEN.SurfaceView($0, baseConfig: $1) }
    ) {
        self.statusHandler = showStatus
        self.makeSurface = makeSurface
    }

    func recordFocusedTerminalController(_ controller: BaseTerminalController) {
        lastFocusedTerminalController = controller
    }

    private func showLayoutStatus(
        _ message: String,
        severity: SettingsStatusSeverity = .success,
        duration: TimeInterval = 2,
        targetWindow: NSWindow? = nil
    ) {
        statusHandler(message, severity, duration, targetWindow)
    }

    // MARK: - Layout Application

    /// Apply a split layout template to the focused terminal pane.
    /// Builds the target tree directly and swaps it in with a single replaceSurfaceTree call,
    /// giving atomic undo, one focus move, and no intermediate states.
    func apply(_ layout: LayoutTemplate, controller targetController: BaseTerminalController? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))

        // Find the active terminal controller
        guard let controller = targetController ?? preferredLayoutTargetController() else {
            YEN.logger.info("layout: no terminal window available")
            showLayoutStatus("Open a terminal window first", severity: .info, duration: 3)
            return
        }

        guard let focusedSurface = controller.focusedSurface else {
            YEN.logger.info("layout: no focused surface")
            showLayoutStatus("No focused terminal pane", severity: .info, duration: 3, targetWindow: controller.window)
            return
        }

        guard let currentRoot = controller.surfaceTree.root else {
            YEN.logger.info("layout: no tree root")
            showLayoutStatus("No terminal surface", severity: .info, duration: 3, targetWindow: controller.window)
            return
        }

        // Reject stale focus before confirmation or terminal allocation.
        let focusedLeaf = SplitTree<YEN.SurfaceView>.Node.leaf(view: focusedSurface)

        guard let path = currentRoot.path(to: focusedLeaf) else {
            clearPendingLayoutConfirmation(for: controller)
            YEN.logger.warning("layout: focused surface not found in split tree")
            showLayoutStatus("Layout failed", severity: .error, duration: 3, targetWindow: controller.window)
            return
        }

        // Single Pane: replace entire tree with just the focused surface
        if layout == .singlePane {
            guard controller.surfaceTree.isSplit else {
                clearPendingLayoutConfirmation(for: controller)
                showLayoutStatus("Already a single pane", severity: .info, duration: 2, targetWindow: controller.window)
                return
            }

            guard consumePendingSinglePaneConfirmation(for: controller, focusedSurface: focusedSurface) else {
                return
            }

            let newTree = SplitTree<YEN.SurfaceView>(view: focusedSurface)
            applyLayoutTree(
                newTree,
                layout: layout,
                controller: controller,
                focusedSurface: focusedSurface
            )

            YEN.logger.info("layout: applied \(layout.rawValue)")
            completeLayout(controller: controller)
            return
        }

        clearPendingLayoutConfirmation(for: controller)

        // Create new surface views for the layout
        guard let yenApp = controller.yen.app else {
            YEN.logger.warning("layout: yen.app is nil")
            showLayoutStatus("Layout failed", severity: .error, duration: 3, targetWindow: controller.window)
            return
        }

        let inheritedBaseConfig = inheritedSplitSurfaceConfiguration(for: focusedSurface)
        var newViews: [YEN.SurfaceView] = []
        for _ in 0..<layout.newSurfaceCount {
            newViews.append(makeSurface(yenApp, inheritedBaseConfig))
        }

        // Build the layout subtree
        guard let layoutRoot = layout.buildTree(focused: focusedSurface, newViews: newViews) else {
            YEN.logger.warning("layout: buildTree returned nil for \(layout.rawValue)")
            showLayoutStatus("Layout failed", severity: .error, duration: 3, targetWindow: controller.window)
            return
        }

        let newRoot: SplitTree<YEN.SurfaceView>.Node
        do {
            newRoot = try currentRoot.replacingNode(at: path, with: layoutRoot)
        } catch {
            YEN.logger.warning("layout: tree construction failed: \(error)")
            showLayoutStatus("Layout failed", severity: .error, duration: 3, targetWindow: controller.window)
            return
        }

        let newTree = SplitTree(
            root: newRoot,
            zoomed: remappedZoomNode(from: controller.surfaceTree, replacingRoot: currentRoot, with: newRoot)
        )
        applyLayoutTree(
            newTree,
            layout: layout,
            controller: controller,
            focusedSurface: focusedSurface
        )

        YEN.logger.info("layout: applied \(layout.rawValue)")
        completeLayout(controller: controller)
    }

    private func applyLayoutTree(
        _ newTree: SplitTree<YEN.SurfaceView>,
        layout: LayoutTemplate,
        controller: BaseTerminalController,
        focusedSurface: YEN.SurfaceView
    ) {
        controller.replaceSurfaceTree(
            newTree,
            moveFocusTo: focusedSurface,
            moveFocusFrom: focusedSurface,
            undoAction: "Apply \(layout.displayName)"
        )
    }

    /// Shared completion for all layout applications — shows status and brings terminal to front.
    private func completeLayout(controller: BaseTerminalController) {
        showLayoutStatus("Layout applied", duration: 2, targetWindow: controller.window)
        if let focusedSurface = controller.focusedSurface {
            controller.focusSurface(focusedSurface)
        } else {
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func preferredLayoutTargetController() -> BaseTerminalController? {
        if let keyController = NSApp.keyWindow?.windowController as? BaseTerminalController {
            return keyController
        }

        // When the Settings panel (or another utility window) holds key, neither
        // keyWindow nor mainWindow reliably resolves to the focused tab — with
        // tabbed windows mainWindow can point at the wrong tab. Prefer the
        // terminal controller that was focused most recently before key moved away.
        if let tracked = lastFocusedTerminalController, tracked.window?.isVisible == true {
            return tracked
        }

        if let mainController = NSApp.mainWindow?.windowController as? BaseTerminalController {
            return mainController
        }

        let terminalControllers = NSApp.windows.compactMap { $0.windowController as? BaseTerminalController }
        return terminalControllers.first(where: { $0.window?.isVisible == true }) ?? terminalControllers.last
    }

    private func clearPendingLayoutConfirmation(for controller: BaseTerminalController) {
        guard let pendingLayoutConfirmation else { return }
        guard pendingLayoutConfirmation.controllerIdentifier == ObjectIdentifier(controller) else { return }
        self.pendingLayoutConfirmation = nil
    }

    private func consumePendingSinglePaneConfirmation(
        for controller: BaseTerminalController,
        focusedSurface: YEN.SurfaceView
    ) -> Bool {
        let controllerIdentifier = ObjectIdentifier(controller)
        let now = layoutConfirmationClock.now

        if let pendingLayoutConfirmation,
           pendingLayoutConfirmation.controllerIdentifier == controllerIdentifier,
           pendingLayoutConfirmation.focusedSurfaceIdentifier == focusedSurface.id,
           pendingLayoutConfirmation.layout == .singlePane,
           now - pendingLayoutConfirmation.issuedAt <= Self.destructiveLayoutConfirmationTimeout {
            self.pendingLayoutConfirmation = nil
            return true
        }

        pendingLayoutConfirmation = PendingLayoutConfirmation(
            controllerIdentifier: controllerIdentifier,
            focusedSurfaceIdentifier: focusedSurface.id,
            layout: .singlePane,
            issuedAt: now
        )
        showLayoutStatus(
            "Press Single Pane again to close the other panes",
            severity: .warning,
            duration: 4,
            targetWindow: controller.window
        )
        return false
    }

    private func inheritedSplitSurfaceConfiguration(for focusedSurface: YEN.SurfaceView) -> YEN.SurfaceConfiguration? {
        guard let surface = focusedSurface.surface else { return nil }
        return YEN.SurfaceConfiguration(
            from: yen_surface_inherited_config(surface, YEN_SURFACE_CONTEXT_SPLIT)
        )
    }

    private func remappedZoomNode(
        from currentTree: SplitTree<YEN.SurfaceView>,
        replacingRoot oldRoot: SplitTree<YEN.SurfaceView>.Node,
        with newRoot: SplitTree<YEN.SurfaceView>.Node
    ) -> SplitTree<YEN.SurfaceView>.Node? {
        guard let zoomedNode = currentTree.zoomed,
              let zoomedPath = oldRoot.path(to: zoomedNode) else {
            return nil
        }
        return newRoot.node(at: zoomedPath)
    }
}
#endif
