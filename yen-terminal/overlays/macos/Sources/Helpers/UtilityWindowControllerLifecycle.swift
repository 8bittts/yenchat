#if os(macOS)
import AppKit

@MainActor
extension NSWindowController {
    func yenReleaseOwnedUtilityWindow(from notification: Notification) {
        if let closingWindow = notification.object as? NSWindow {
            yenReleaseOwnedUtilityWindow(closingWindow)
        } else {
            yenReleaseOwnedUtilityWindow()
        }
    }

    func yenReleaseOwnedUtilityWindow(_ candidateWindow: NSWindow? = nil) {
        guard let ownedWindow = candidateWindow ?? window else {
            window = nil
            return
        }

        ownedWindow.delegate = nil
        ownedWindow.contentView = nil

        if candidateWindow == nil || window === ownedWindow {
            window = nil
        }
    }

    @discardableResult
    func yenDiscardReleasedUtilityWindowIfNeeded() -> Bool {
        guard let existingWindow = window, existingWindow.contentView == nil else {
            return false
        }

        existingWindow.orderOut(nil)
        yenReleaseOwnedUtilityWindow(existingWindow)
        return true
    }
}
#endif
