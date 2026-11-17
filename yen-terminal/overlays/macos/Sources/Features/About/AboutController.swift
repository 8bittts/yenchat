#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class AboutController: NSWindowController, NSWindowDelegate {
    static let shared = AboutController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        ensureWindowAvailable()
        NSApp.unhide(nil)
        NSApp.yenActivateCompat()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        yenReleaseOwnedUtilityWindow(from: notification)
    }

    private func ensureWindowAvailable() {
        yenDiscardReleasedUtilityWindowIfNeeded()
        if window == nil {
            createWindow()
        }
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 172),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false

        self.window = window
    }

    @IBAction func close(_ sender: Any?) {
        window?.performClose(sender)
    }

    @IBAction func closeWindow(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc func cancel(_ sender: Any?) {
        close(sender)
    }
}

#if DEBUG
extension AboutController {
    var _testHasWindow: Bool {
        window != nil
    }

    @discardableResult
    func _testEnsureWindow() -> NSWindow? {
        ensureWindowAvailable()
        return window
    }

    func _testResetState() {
        window?.orderOut(nil)
        yenReleaseOwnedUtilityWindow()
    }
}
#endif
#endif
