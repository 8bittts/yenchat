#if os(macOS)
import Cocoa

extension ScratchpadController {
    /// Rests the panel flush inside the terminal window's right edge. The panel frame
    /// never animates; the reveal slides its content from behind that edge.
    func positionPanel(_ panel: NSWindow, relativeTo terminalWindow: NSWindow) {
        EdgeRevealPanelGeometry.place(
            panel,
            edge: .trailing,
            in: terminalWindow,
            width: Self.panelWidth
        )
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

    /// Shared reveal core for the focus/reveal flows: re-anchor, position on-screen, and
    /// fade-in/order-front when the panel isn't already visible. Callers keep
    /// installEscapeMonitor()/focusTextEditor() at the call site to preserve per-flow order
    /// (windowWillClose intentionally skips installEscapeMonitor()).
    func revealPanel(_ panel: NSPanel, anchoredTo window: NSWindow) {
        anchorWindow = window
        positionPanel(panel, relativeTo: window)
        if !panel.isVisible {
            revealView?.showAtRest()
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
            animateOut()
        }
    }

    @objc func windowDidMiniaturize(_ notification: Notification) {
        guard visible else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow else { return }
        animateOut()
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
        animateOut(restoringFocus: false)
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        // The only place a blocking write is correct: the process is exiting, so an
        // async write would race the teardown.
        flushPendingSave(blocking: true)
    }
}

#endif
