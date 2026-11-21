#if os(macOS)
import Cocoa

extension ScratchpadController {
    static func panelFrame(in bounds: CGRect, preferred: CGSize?, center: CGPoint) -> CGRect {
        let margin = min(YENDesignTokens.contentInset, min(bounds.width, bounds.height) / 8)
        let area = bounds.insetBy(dx: margin, dy: margin)
        let width = min(area.width, max(240, preferred?.width ?? min(720, area.width * 0.6)))
        let height = min(area.height, max(160, preferred?.height ?? min(520, area.height * 0.6)))
        let x = min(area.maxX - width, max(area.minX, bounds.minX + bounds.width * center.x - width / 2))
        let y = min(area.maxY - height, max(area.minY, bounds.minY + bounds.height * center.y - height / 2))
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    private func availableFrame(in window: NSWindow) -> CGRect {
        let layout = window.convertToScreen(window.contentLayoutRect)
        guard let screen = window.screen else { return layout }
        let visible = layout.intersection(screen.visibleFrame)
        return visible.isEmpty ? screen.visibleFrame : visible
    }

    func positionPanel(_ panel: NSWindow, relativeTo window: NSWindow) {
        let bounds = availableFrame(in: window)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let frame = Self.panelFrame(in: bounds, preferred: preferredPanelSize, center: relativeCenter)
        placingPanel = true
        defer { placingPanel = false }
        panel.minSize = NSSize(width: min(240, frame.width), height: min(160, frame.height))
        panel.setFrame(frame, display: true)
    }

    func windowDidMove(_ notification: Notification) {
        guard !placingPanel, visible, let panel, notification.object as? NSWindow === panel,
              let anchorWindow else { return }
        let bounds = availableFrame(in: anchorWindow)
        guard bounds.width > 0, bounds.height > 0 else { return }
        relativeCenter = CGPoint(x: (panel.frame.midX - bounds.minX) / bounds.width,
                                 y: (panel.frame.midY - bounds.minY) / bounds.height)
    }

    func activeTerminalWindow(excluding: NSWindow? = nil) -> NSWindow? {
        let candidates: [NSWindow?] = [
            NSApp.keyWindow,
            NSApp.mainWindow,
            TerminalController.preferredParent?.window,
        ]
            + NSApp.orderedWindows
            + NSApp.windows
        return TerminalAuxiliaryAnchorPolicy.firstEligible(in: candidates.compactMap {
            activeTerminalWindowCandidate(for: $0, excluding: excluding)
        })
    }

    private func activeTerminalWindowCandidate(
        for window: NSWindow?,
        excluding excludedWindow: NSWindow?
    ) -> TerminalAuxiliaryAnchorPolicy.Candidate<NSWindow>? {
        guard let window, window !== excludedWindow else { return nil }
        return TerminalAuxiliaryAnchorPolicy.Candidate(
            identity: ObjectIdentifier(window),
            window: window,
            isEligible: TerminalAuxiliaryAnchorPolicy.canAnchor(
                windowControllerIsTerminal: window.windowController is TerminalController,
                isQuickTerminal: window is QuickTerminalWindow,
                isFullscreen: window.yenIsEffectivelyFullscreen,
                isMiniaturized: window.isMiniaturized,
                isVisible: window.isVisible
            )
        )
    }

    func revealPanel(_ panel: NSPanel, anchoredTo window: NSWindow) {
        if anchorWindow !== window { relativeCenter = CGPoint(x: 0.5, y: 0.5) }
        anchorWindow = window
        positionPanel(panel, relativeTo: window)
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func registerScratchpadObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidMiniaturize(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowFullscreenStateDidChange(_:)),
            name: .yenNativeFullscreenTransitionDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard visible else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController,
              let panel else { return }

        revealPanel(panel, anchoredTo: window)
        installEscapeMonitor()
        focusTextEditor()
    }

    @objc func windowDidChangeFrame(_ notification: Notification) {
        guard visible, let panel else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow || window.isKeyWindow else { return }
        if window.isKeyWindow {
            anchorWindow = window
        }
        positionPanel(panel, relativeTo: window)
    }

    @objc func windowWillClose(_ notification: Notification) {
        guard visible else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow else { return }

        if let nextWindow = activeTerminalWindow(excluding: window), let panel {
            revealPanel(panel, anchoredTo: nextWindow)
            focusTextEditor()
        } else {
            dismiss()
        }
    }

    @objc func windowDidMiniaturize(_ notification: Notification) {
        guard visible else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow else { return }
        dismiss()
    }

    @objc func windowFullscreenStateDidChange(_ notification: Notification) {
        guard visible, let panel else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow || window.isKeyWindow else { return }

        if window.yenIsEffectivelyFullscreen {
            panel.orderOut(nil)
            removeEscapeMonitor()
            return
        }

        revealPanel(panel, anchoredTo: window)
        installEscapeMonitor()
        focusTextEditor()
    }

    @objc func applicationDidResignActive(_ notification: Notification) {
        guard visible else { return }
        dismiss(restoringFocus: false)
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        // The only place a blocking write is correct: the process is exiting, so an
        // async write would race the teardown.
        flushPendingSave(blocking: true)
    }
}

#endif
