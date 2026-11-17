import AppKit

enum NativeFullscreenTransitionCoordinator {
    static func logToggleRequest(mode: FullscreenMode, window: NSWindow) {
        YEN.logger.debug(
            "fullscreen: toggle request mode=\(mode.rawValue) phase=\(window.yenNativeFullscreenTransitionPhase.rawValue) settled=\(window.styleMask.contains(.fullScreen))"
        )
    }

    static func shouldIgnoreToggleRequest(mode: FullscreenMode, window: NSWindow) -> Bool {
        guard window.yenIsNativeFullscreenTransitioning else { return false }

        YEN.logger.debug(
            "fullscreen: ignoring toggle request mode=\(mode.rawValue) phase=\(window.yenNativeFullscreenTransitionPhase.rawValue)"
        )
        return true
    }

    static func setPhase(
        _ phase: NativeFullscreenTransitionPhase,
        boundary: String,
        window: NSWindow
    ) {
        if window.yenNativeFullscreenTransitionPhase != phase {
            window.yenNativeFullscreenTransitionPhase = phase
        }
        YEN.logger.debug(
            "fullscreen: boundary=\(boundary) phase=\(phase.rawValue) settled=\(window.styleMask.contains(.fullScreen))"
        )
    }
}

extension BaseTerminalController {
    func logFullscreenToggleRequest(mode: FullscreenMode, window: NSWindow) {
        NativeFullscreenTransitionCoordinator.logToggleRequest(mode: mode, window: window)
    }

    func shouldIgnoreFullscreenToggleRequest(mode: FullscreenMode, window: NSWindow) -> Bool {
        NativeFullscreenTransitionCoordinator.shouldIgnoreToggleRequest(mode: mode, window: window)
    }

    private func setNativeFullscreenTransitionPhase(
        _ phase: NativeFullscreenTransitionPhase,
        boundary: String,
        window: NSWindow
    ) {
        NativeFullscreenTransitionCoordinator.setPhase(phase, boundary: boundary, window: window)
    }

    private func syncNativeFullscreenTitlebarSeparator(window: NSWindow) {
        window.titlebarSeparatorStyle = window.yenIsEffectivelyFullscreen ? .none : .automatic
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        window.titlebarSeparatorStyle = .none
        setNativeFullscreenTransitionPhase(.entering, boundary: "windowWillEnterFullScreen", window: window)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        setNativeFullscreenTransitionPhase(.none, boundary: "windowDidEnterFullScreen", window: window)
        syncNativeFullscreenTitlebarSeparator(window: window)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        window.titlebarSeparatorStyle = .automatic
        setNativeFullscreenTransitionPhase(.exiting, boundary: "windowWillExitFullScreen", window: window)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        setNativeFullscreenTransitionPhase(.none, boundary: "windowDidExitFullScreen", window: window)
        syncNativeFullscreenTitlebarSeparator(window: window)
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard window === self.window else { return }
        setNativeFullscreenTransitionPhase(.none, boundary: "windowDidFailToEnterFullScreen", window: window)
        syncNativeFullscreenTitlebarSeparator(window: window)
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        guard window === self.window else { return }
        setNativeFullscreenTransitionPhase(.none, boundary: "windowDidFailToExitFullScreen", window: window)
        syncNativeFullscreenTitlebarSeparator(window: window)
    }
}
