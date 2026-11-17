import Foundation

extension TerminalController {
    func handleToggleFullscreenNotification(_ notification: Notification) {
        guard let target = notification.object as? YEN.SurfaceView else { return }
        guard target == focusedSurface else { return }

        guard let any = notification.userInfo?[YEN.Notification.FullscreenModeKey],
              let mode = any as? FullscreenMode else {
            YEN.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }

        toggleFullscreen(mode: mode)
    }
}
