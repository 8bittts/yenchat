#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class WebPreviewController: NSWindowController, NSWindowDelegate {
    static let shared = WebPreviewController()
    private static let frameAutosaveName: NSWindow.FrameAutosaveName = "com.yenchat.yen.browser.window"

    let model: WebPreviewModel

    var hasWindow: Bool {
        window != nil
    }

    private init() {
        self.model = WebPreviewModel()
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(url: URL? = nil) {
        let createdWindow = ensureWindowAvailable()
        model.prepareForPresentation(url: url, forceLoadCurrent: createdWindow)
        NSApp.unhide(nil)
        NSApp.yenActivateCompat()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.close()
    }

    @IBAction func close(_ sender: Any?) {
        window?.close()
    }

    @IBAction func closeWindow(_ sender: Any?) {
        window?.close()
    }

    func isFocused(keyWindow: NSWindow?) -> Bool {
        guard let browserWindow = window else { return false }
        return keyWindow === browserWindow
    }

    @discardableResult
    func closeIfFocused(keyWindow: NSWindow?, sender: Any?) -> Bool {
        guard isFocused(keyWindow: keyWindow), let browserWindow = window else { return false }
        browserWindow.close()
        return true
    }

    nonisolated static func isStandardCloseShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiers = modifierFlags.intersection([.shift, .control, .option, .command])
        return charactersIgnoringModifiers?.lowercased() == "w" && modifiers == .command
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow {
            closingWindow.saveFrame(usingName: Self.frameAutosaveName)
        }
        model.stopLoading()
        model.setAddressFieldEditing(false)
        releaseBrowserWindow(from: notification)
    }

    @discardableResult
    private func ensureWindowAvailable() -> Bool {
        if let existingWindow = window, existingWindow.contentView == nil {
            existingWindow.orderOut(nil)
            existingWindow.setFrameAutosaveName("")
            existingWindow.toolbar = nil
            existingWindow.delegate = nil
            window = nil
        }
        if window == nil {
            createWindow()
            return true
        }
        return false
    }

    private func createWindow() {
        let hostingView = NSHostingView(rootView: WebPreviewView(model: model, showsInlineToolbar: false))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YEN Browser"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 840, height: 560)
        restoreSavedFrameOrCenter(window)
        window.toolbar = WebPreviewWindowToolbar(model: model)
        window.toolbarStyle = .automatic

        self.window = window
    }

    private func restoreSavedFrameOrCenter(_ window: NSWindow) {
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    private func releaseBrowserWindow(from notification: Notification? = nil) {
        if let releasedWindow = notification?.object as? NSWindow {
            releasedWindow.setFrameAutosaveName("")
            releasedWindow.toolbar = nil
            releasedWindow.delegate = nil
            releasedWindow.contentView = nil
            if let currentWindow = window, currentWindow === releasedWindow {
                window = nil
            }
        } else {
            window?.setFrameAutosaveName("")
            window?.toolbar = nil
            window?.delegate = nil
            window?.contentView = nil
            window = nil
        }
    }
}

#if DEBUG
extension WebPreviewController {
    static var _testFrameAutosaveName: NSWindow.FrameAutosaveName {
        frameAutosaveName
    }

    var _testHasWindow: Bool {
        window != nil
    }

    @discardableResult
    func _testEnsureWindow() -> NSWindow? {
        ensureWindowAvailable()
        return window
    }

    func _testResetState() {
        model.stopLoading()
        model.setAddressFieldEditing(false)
        releaseBrowserWindow()
    }

    func _testInstallWindow(_ testWindow: NSWindow, url: URL) {
        _testResetState()
        self.window = testWindow
        model.prepareForPresentation(url: url, forceLoadCurrent: true)
    }

    @discardableResult
    func _testCloseIfFocused(keyWindow: NSWindow?) -> Bool {
        closeIfFocused(keyWindow: keyWindow, sender: nil)
    }
}
#endif
#endif
