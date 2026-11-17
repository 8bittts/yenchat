#if os(macOS)
import AppKit
import Foundation
import Testing
import WebKit
@testable import YEN

/// Browser split cases that drive real `NSWindow` lifecycle.
///
/// Carved out of `WebPreviewCommandTests` so the window/split-dependent cases sit
/// together: they all register a terminal window, take `BrowserSplitController`
/// through `show()` -> `activateSplit()`, and close the window as teardown.
///
/// They are run by BOTH the pre-build component gate and the browser smoke lane
/// (`scripts/native/01-macos-smoke.sh --browser`). The separation is organizational,
/// not a coverage reduction — every case here previously took down the whole XCTest
/// host, and the cause was a missing `isReleasedWhenClosed = false` on the test
/// windows (see BrowserTestSupport), not anything about the split behavior itself.
@MainActor
@Suite(.serialized)
struct BrowserSplitWindowTests {
    @Test func commandServiceSplitOpenUsesInjectedKeyWindowProviderWhenNoSourceWindow() {
        resetBrowserSurfaces()
        defer {
            BrowserCommandService.shared._testSetKeyWindowProvider(nil)
            resetBrowserSurfaces()
        }

        let terminalWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        terminalWindow.isReleasedWhenClosed = false
        BrowserSplitController.shared.registerTerminalWindow(terminalWindow)
        BrowserCommandService.shared._testSetKeyWindowProvider { terminalWindow }

        // No sourceWindow: the split path must resolve the window via keyWindowProvider(),
        // not ambient NSApp.keyWindow (nil headless), so this opens in the injected window.
        let result = BrowserCommandService.shared.openTrustedURL(
            WebPreviewDefaults.docsURL,
            presentation: .split,
            sourceWindow: nil,
            splitFallback: .failClosed
        )

        #expect(result.accepted)
        #expect(BrowserSplitController.shared.isVisible(in: terminalWindow))

        BrowserSplitController.shared.unregisterTerminalWindow(terminalWindow)
        terminalWindow.close()
    }

    @Test func browserSplitControllerRequiresRegisteredTerminalWindow() {
        let controller = BrowserSplitController.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            controller.unregisterTerminalWindow(window)
            closeBrowserTestWindow(window)
        }

        #expect(!controller.show(url: WebPreviewDefaults.docsURL, in: window))
        #expect(!controller.visibleInAnyWindow)

        controller.registerTerminalWindow(window)
        #expect(controller.show(url: WebPreviewDefaults.docsURL, in: window))
        #expect(controller.isVisible(in: window))

        controller.close()
        #expect(!controller.visibleInAnyWindow)
    }

    @Test func browserSplitControllerClosesWhenTargetWindowCloses() {
        let controller = BrowserSplitController.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            controller.close()
            controller.unregisterTerminalWindow(window)
            closeBrowserTestWindow(window)
        }

        controller.registerTerminalWindow(window)
        #expect(controller.show(url: WebPreviewDefaults.docsURL, in: window))
        #expect(controller.visibleInAnyWindow)

        closeBrowserTestWindow(window)

        #expect(!controller.visibleInAnyWindow)
        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .split))
        #expect(!result.accepted)
        #expect(result.message == "No browser split is open for reload.")
    }

    @Test func browserSplitCloseShortcutRequiresFocusedWebViewDescendant() {
        let controller = BrowserSplitController.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let unrelatedFocusView = FocusableTestView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let webFocusView = FocusableTestView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        webView.addSubview(webFocusView)

        defer {
            WebPreviewCommandReceiver.shared._testSetKeyWindowProvider(nil)
            controller.close()
            controller.unregisterTerminalWindow(window)
            closeBrowserTestWindow(window)
        }

        controller.registerTerminalWindow(window)
        #expect(controller.show(url: WebPreviewDefaults.docsURL, in: window))
        controller.setWebView(webView)

        window.contentView = unrelatedFocusView
        window.makeFirstResponder(unrelatedFocusView)
        #expect(!controller.closeIfWebViewFocused(keyWindow: window))
        #expect(controller.visibleInAnyWindow)

        window.contentView = webView
        window.makeFirstResponder(webFocusView)
        WebPreviewCommandReceiver.shared._testSetKeyWindowProvider { window }
        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .focused))

        #expect(result.accepted)
        #expect(result.message == "Browser reload command sent.")
        #expect(controller.model.pendingRequest?.action == .reload)
        #expect(controller.closeIfWebViewFocused(keyWindow: window))
        #expect(!controller.visibleInAnyWindow)
    }

    @Test func browserSurfaceClosePathsClearAddressEditingState() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: WebPreviewDefaults.docsURL)
        WebPreviewController.shared.model.setAddressFieldEditing(true)
        WebPreviewController.shared._testResetState()
        #expect(WebPreviewController.shared.model.isAddressFieldEditing == false)

        let splitWindow = makeRegisteredTerminalWindow()
        defer { closeBrowserTestWindow(splitWindow) }
        #expect(BrowserSplitController.shared.show(url: WebPreviewDefaults.docsURL, in: splitWindow))
        BrowserSplitController.shared.model.setAddressFieldEditing(true)
        BrowserSplitController.shared.close()
        #expect(BrowserSplitController.shared.model.isAddressFieldEditing == false)
    }








}
#endif
