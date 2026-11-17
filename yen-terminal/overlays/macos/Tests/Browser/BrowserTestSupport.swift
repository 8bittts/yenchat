#if os(macOS)
import AppKit
import Foundation
import Testing
import WebKit
@testable import YEN

// Shared fixtures for the browser test suites. These live here rather than in
// WebPreviewCommandTests because the window/split-dependent cases were split out
// into BrowserSplitWindowTests, and both suites need the same teardown.
//
// [CRITICAL] Every test-created NSWindow must set `isReleasedWhenClosed = false`.
// NSWindow defaults it to TRUE for programmatically-created windows, so `close()`
// releases the window while ARC still holds the Swift reference — an over-release
// that does not surface as an assertion failure or a crash report. It takes down
// the entire XCTest host: the runner reports "exited with code 1 before finishing
// running tests" and EVERY remaining test in the bundle is marked failed, which
// reads like a broken suite rather than one bad teardown. That is what made the
// browser suites fail the pre-build component gate.

final class FocusableTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
func resetBrowserSurfaces() {
    WebPreviewCommandReceiver.shared._testSetKeyWindowProvider(nil)
    let browserWindow = WebPreviewController.shared.window
    WebPreviewController.shared._testResetState()
    BrowserSplitController.shared.close()
    closeBrowserTestWindow(browserWindow)
}

@MainActor
func installBrowserTestWindow(url: URL) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: true
    )
    window.isReleasedWhenClosed = false
    WebPreviewController.shared._testInstallWindow(window, url: url)
    return window
}

@MainActor
func makeRegisteredTerminalWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: true
    )
    window.isReleasedWhenClosed = false
    BrowserSplitController.shared.registerTerminalWindow(window)
    return window
}

@MainActor
func closeBrowserTestWindow(_ window: NSWindow?) {
    guard let window else { return }
    window.makeFirstResponder(nil)
    window.orderOut(nil)
    window.delegate = nil
    window.contentView = nil
    window.close()
}

func reloadPayload(target: BrowserSurfaceTarget = .automatic) -> WebPreviewCommandPayload {
    WebPreviewCommandPayload(
        action: .reload,
        urlString: nil,
        presentation: .window,
        responsePath: nil,
        targetExecutablePath: nil,
        target: target
    )
}
#endif
