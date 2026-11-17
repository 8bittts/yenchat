#if os(macOS)
import AppKit
import Foundation
import Testing
import WebKit
@testable import YEN

@MainActor
@Suite(.serialized)
struct WebPreviewCommandTests {
    @Test func commandPayloadParsesActionURLPresentationAndResponsePath() {
        let payload = WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "2",
            "action": "open",
            "url": "https://yen.chat/docs",
            "presentation": "split",
            "response_path": "/private/tmp/yen-web-command.test",
            "target_executable_path": "/tmp/YEN.app/Contents/MacOS/yen",
            "target": "focused",
        ])

        #expect(payload?.action == .open)
        #expect(payload?.urlString == "https://yen.chat/docs")
        #expect(payload?.presentation == .split)
        #expect(payload?.responsePath == "/private/tmp/yen-web-command.test")
        #expect(payload?.targetExecutablePath == "/tmp/YEN.app/Contents/MacOS/yen")
        #expect(payload?.target == .focused)
    }

    @Test func commandPayloadKeepsSchemaOneCompatibleForNormalCLICommands() {
        let payload = WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "1",
            "action": "status",
            "presentation": "window",
            "response_path": "/tmp/yen-web-command.test",
        ])

        #expect(payload?.action == .status)
        #expect(payload?.targetExecutablePath == nil)
        #expect(payload?.target == .automatic)
    }

    @Test func commandPayloadRejectsUnknownActions() {
        #expect(WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "1",
            "action": "scan-terminal-output",
        ]) == nil)
    }

    @Test func commandPayloadRejectsUnsupportedSchemaAndPresentation() {
        #expect(WebPreviewCommandPayload.from(userInfo: [
            "action": "open",
            "presentation": "window",
        ]) == nil)
        #expect(WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "2",
            "action": "open",
            "presentation": "window",
        ]) == nil)
        #expect(WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "1",
            "action": "open",
            "presentation": "sidebar",
        ]) == nil)
        #expect(WebPreviewCommandPayload.from(userInfo: [
            "schema_version": "1",
            "action": "reload",
            "target": "sidebar",
        ]) == nil)
    }

    @Test func commandReceiverBlocksUnsafeOpenWithoutCreatingWindow() {
        let controller = WebPreviewController.shared
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
        }

        let result = WebPreviewCommandReceiver.shared.perform(
            WebPreviewCommandPayload(
                action: .open,
                urlString: "file:///etc/passwd",
                presentation: .window,
                responsePath: nil,
                targetExecutablePath: nil
            )
        )

        #expect(!result.accepted)
        #expect(result.message == "File URLs are not opened silently.")
        #expect(!controller._testHasWindow)
    }

    @Test func commandServiceDefaultOpenFocusesExistingWindowWithoutReloading() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let currentURL = URL(string: "https://yen.chat/current")!
        _ = installBrowserTestWindow(url: currentURL)
        let request = WebPreviewController.shared.model.pendingRequest

        let result = BrowserCommandService.shared.openDefault(presentation: .window)

        #expect(result.accepted)
        #expect(result.message == "Browser window opened.")
        #expect(WebPreviewController.shared.model.currentURL == currentURL)
        #expect(WebPreviewController.shared.model.pendingRequest == request)
    }

    @Test func commandServiceExplicitSplitOpenFailsClosedWithoutTerminalWindow() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let result = BrowserCommandService.shared.openTrustedURL(
            WebPreviewDefaults.docsURL,
            presentation: .split,
            sourceWindow: nil,
            splitFallback: .failClosed
        )

        #expect(!result.accepted)
        #expect(result.message == "No active terminal window is available for browser split.")
        #expect(!WebPreviewController.shared._testHasWindow)
        #expect(!BrowserSplitController.shared.visibleInAnyWindow)
    }

    @Test func commandServiceTerminalLinkSplitFallbackOpensWindowWhenNoTerminalTargetExists() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let trustedURL = URL(string: "https://yen.chat/docs")!
        let result = BrowserCommandService.shared.openTrustedURL(
            trustedURL,
            presentation: .split,
            sourceWindow: nil,
            splitFallback: .window
        )

        #expect(result.accepted)
        #expect(result.message == "Browser window opened.")
        #expect(WebPreviewController.shared._testHasWindow)
        #expect(WebPreviewController.shared.model.currentURL == trustedURL)
        #expect(!BrowserSplitController.shared.visibleInAnyWindow)
    }

    @Test func commandReceiverKeepsStatefulCommandsClosedWhenNoBrowserExists() {
        WebPreviewController.shared._testResetState()
        BrowserSplitController.shared.close()

        let result = WebPreviewCommandReceiver.shared.perform(
            WebPreviewCommandPayload(
                action: .reload,
                urlString: nil,
                presentation: .window,
                responsePath: nil,
                targetExecutablePath: nil
            )
        )

        #expect(!result.accepted)
        #expect(result.message == "No browser surface is open for reload.")
    }

    @Test func commandReceiverTargetsAutomaticSplitBeforeWindow() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        let windowRequest = WebPreviewController.shared.model.pendingRequest
        BrowserSplitController.shared._testInstallVisibleSplitForCommandRouting(
            url: URL(string: "https://yen.chat/split")!
        )
        let splitRequest = BrowserSplitController.shared.model.pendingRequest

        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload())

        #expect(result.accepted)
        #expect(result.message == "Browser reload command sent.")
        #expect(BrowserSplitController.shared.model.pendingRequest?.action == .reload)
        #expect(BrowserSplitController.shared.model.pendingRequest != splitRequest)
        #expect(WebPreviewController.shared.model.pendingRequest == windowRequest)
    }

    @Test func commandReceiverTargetsExplicitWindowWhenSplitExists() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        BrowserSplitController.shared._testInstallVisibleSplitForCommandRouting(
            url: URL(string: "https://yen.chat/split")!
        )
        let splitRequest = BrowserSplitController.shared.model.pendingRequest

        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .window))

        #expect(result.accepted)
        #expect(result.message == "Browser reload command sent.")
        #expect(WebPreviewController.shared.model.pendingRequest?.action == .reload)
        #expect(BrowserSplitController.shared.model.pendingRequest == splitRequest)
    }

    @Test func commandReceiverRejectsMissingExplicitSplitWithoutMutatingWindow() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        let windowRequest = WebPreviewController.shared.model.pendingRequest

        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .split))

        #expect(!result.accepted)
        #expect(result.message == "No browser split is open for reload.")
        #expect(WebPreviewController.shared.model.pendingRequest == windowRequest)
    }

    @Test func commandReceiverTargetsFocusedWindow() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let browserWindow = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        WebPreviewCommandReceiver.shared._testSetKeyWindowProvider { browserWindow }
        #expect(WebPreviewController.shared.isFocused(keyWindow: browserWindow))

        let result = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .focused))

        #expect(result.accepted)
        #expect(result.message == "Browser reload command sent.")
        #expect(WebPreviewController.shared.model.pendingRequest?.action == .reload)
    }

    @Test func commandReceiverReportsTargetedStatus() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        BrowserSplitController.shared._testInstallVisibleSplitForCommandRouting(
            url: URL(string: "https://yen.chat/split")!
        )

        #expect(WebPreviewCommandReceiver.shared.perform(statusPayload()).message == "window=open split=open")
        #expect(WebPreviewCommandReceiver.shared.perform(statusPayload(target: .window)).message == "window=open")
        #expect(WebPreviewCommandReceiver.shared.perform(statusPayload(target: .split)).message == "split=open")

        let targetedStatus = WebPreviewCommandReceiver.shared.perform(
            statusPayload(targetExecutablePath: Bundle.main.executableURL?.path ?? "/tmp/YEN.app/Contents/MacOS/yen")
        )
        #expect(targetedStatus.message == "window=open split=open")
        #expect(targetedStatus.acknowledgedExecutablePath == Bundle.main.executableURL?.path)
    }

    @Test func focusedStatusAndCloseUseTheSameWindowTarget() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let window = installBrowserTestWindow(url: URL(string: "https://yen.chat/window")!)
        window.delegate = WebPreviewController.shared
        BrowserSplitController.shared._testInstallVisibleSplitForCommandRouting(url: WebPreviewDefaults.docsURL)
        WebPreviewCommandReceiver.shared._testSetKeyWindowProvider { window }
        #expect(WebPreviewCommandReceiver.shared.perform(statusPayload(target: .focused)).message == "focused=window window=open split=open")

        let result = BrowserCommandService.shared.perform(
            action: .close, urlString: nil, presentation: .automatic, target: .focused
        )
        #expect(result.accepted)
        #expect(result.message == "Browser window closed.")
        #expect(!WebPreviewController.shared.hasWindow)
        #expect(BrowserSplitController.shared.visibleInAnyWindow)
    }

    @Test func automaticClosePrefersSplitThenWindowAndFailsWhenEmpty() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        let window = installBrowserTestWindow(url: WebPreviewDefaults.docsURL)
        window.delegate = WebPreviewController.shared
        BrowserSplitController.shared._testInstallVisibleSplitForCommandRouting(url: WebPreviewDefaults.docsURL)
        let split = BrowserCommandService.shared.perform(
            action: .close, urlString: nil, presentation: .automatic, target: .automatic
        )
        #expect(split.message == "Browser split closed.")
        #expect(split.accepted)
        #expect(WebPreviewController.shared.hasWindow)
        #expect(!BrowserSplitController.shared.visibleInAnyWindow)

        let windowResult = BrowserCommandService.shared.perform(
            action: .close, urlString: nil, presentation: .automatic, target: .automatic
        )
        #expect(windowResult.message == "Browser window closed.")
        #expect(windowResult.accepted)
        let missing = BrowserCommandService.shared.perform(
            action: .close, urlString: nil, presentation: .automatic, target: .automatic
        )
        #expect(!missing.accepted)
        #expect(missing.message == "No browser surface is open for close.")
    }

    @Test func missingFocusStatusAndCloseLeaveExistingSurfacesOpen() {
        resetBrowserSurfaces()
        defer { resetBrowserSurfaces() }

        _ = installBrowserTestWindow(url: WebPreviewDefaults.docsURL)
        WebPreviewCommandReceiver.shared._testSetKeyWindowProvider { nil }
        #expect(WebPreviewCommandReceiver.shared.perform(statusPayload(target: .focused)).message == "focused=none window=open split=closed")
        let result = BrowserCommandService.shared.perform(
            action: .close, urlString: nil, presentation: .automatic, target: .focused
        )
        #expect(!result.accepted)
        #expect(result.message == "No focused browser surface is open for close.")
        #expect(WebPreviewController.shared.hasWindow)
    }

    @Test func responsePathsAreRestrictedToBrowserCommandTemporaryFiles() {
        #expect(WebPreviewCommandReceiver.isAllowedResponsePath("/tmp/yen-web-command.abc123"))
        #expect(WebPreviewCommandReceiver.isAllowedResponsePath("/private/tmp/yen-web-command.abc123"))
        #expect(!WebPreviewCommandReceiver.isAllowedResponsePath("/private/tmp/not-yen-web-command.abc123"))
        #expect(!WebPreviewCommandReceiver.isAllowedResponsePath("/tmp/not-yen-web-command.abc123"))
        #expect(!WebPreviewCommandReceiver.isAllowedResponsePath("/private/tmp/yen-web-command.abc123/response.json"))
        #expect(!WebPreviewCommandReceiver.isAllowedResponsePath("/private/tmp/yen-web-command.abc123/../not-yen-web-command"))
        #expect(!WebPreviewCommandReceiver.isAllowedResponsePath("/Users/dev/.ssh/config"))
    }

    @Test func targetExecutablePathPreventsCrossAppBrowserCommandResponses() {
        #expect(WebPreviewCommandReceiver.targetExecutablePathMatches(nil, executablePath: "/Applications/YEN.app/Contents/MacOS/yen"))
        #expect(WebPreviewCommandReceiver.targetExecutablePathMatches("   ", executablePath: "/Applications/YEN.app/Contents/MacOS/yen"))
        #expect(WebPreviewCommandReceiver.targetExecutablePathMatches(
            "/Users/dev/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen",
            executablePath: "/Users/dev/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen"
        ))
        #expect(!WebPreviewCommandReceiver.targetExecutablePathMatches(
            "/Users/dev/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen",
            executablePath: "/Applications/YEN.app/Contents/MacOS/yen"
        ))
        #expect(!WebPreviewCommandReceiver.targetExecutablePathMatches(
            "/Users/dev/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen",
            executablePath: nil
        ))
    }

    @Test func terminalLinkRouterOnlyCapturesTrustedLinksWhenEnabled() {
        #expect(
            TerminalBrowserLinkRouter.captureURL(
                URL(string: "https://yen.chat/docs")!,
                linkCaptureEnabled: true
            ) == URL(string: "https://yen.chat/docs")!
        )
        #expect(
            TerminalBrowserLinkRouter.captureURL(
                URL(string: "http://localhost:3000")!,
                linkCaptureEnabled: true
            ) == URL(string: "http://localhost:3000")!
        )
        #expect(
            TerminalBrowserLinkRouter.captureURL(
                URL(string: "https://yen.chat/docs")!,
                linkCaptureEnabled: false
            ) == nil
        )
        #expect(
            TerminalBrowserLinkRouter.captureURL(
                URL(string: "http://example.com")!,
                linkCaptureEnabled: true
            ) == nil
        )
        #expect(
            TerminalBrowserLinkRouter.captureURL(
                URL(string: "mailto:hello@yen.chat")!,
                linkCaptureEnabled: true
            ) == nil
        )
    }

    @Test func browserSplitControllerUsesWeakTargetWindowIdentity() {
        let controller = BrowserSplitController.shared
        let targetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        targetWindow.isReleasedWhenClosed = false
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        otherWindow.isReleasedWhenClosed = false
        defer {
            // Close semantics are covered separately; these identity-only windows stay unclosed to keep the AppKit test host stable.
            controller.close()
            controller.unregisterTerminalWindow(targetWindow)
            controller.unregisterTerminalWindow(otherWindow)
        }

        controller._testInstallVisibleSplitForCommandRouting(url: WebPreviewDefaults.docsURL, in: targetWindow)
        controller.registerTerminalWindow(otherWindow)
        #expect(controller.isVisible(in: targetWindow))
        #expect(!controller.isVisible(in: otherWindow))
        #expect(controller.targetWindowDiagnosticIdentifier?.contains("identity=ObjectIdentifier") == true)

        controller.unregisterTerminalWindow(otherWindow)
        #expect(controller.visibleInAnyWindow)
        #expect(controller.isVisible(in: targetWindow))

        controller.unregisterTerminalWindow(targetWindow)

        #expect(!controller.visibleInAnyWindow)
        let reloadResult = WebPreviewCommandReceiver.shared.perform(reloadPayload(target: .split))
        #expect(!reloadResult.accepted)
        #expect(reloadResult.message == "No browser split is open for reload.")
    }

    @Test func browserSplitControllerRejectsRegisteredPanels() {
        let controller = BrowserSplitController.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer {
            controller.unregisterTerminalWindow(panel)
            closeBrowserTestWindow(panel)
        }

        controller.registerTerminalWindow(panel)
        #expect(!controller.show(url: WebPreviewDefaults.docsURL, in: panel))
        #expect(!controller.visibleInAnyWindow)
    }

}

private func statusPayload(
    target: BrowserSurfaceTarget = .automatic,
    targetExecutablePath: String? = nil
) -> WebPreviewCommandPayload {
    WebPreviewCommandPayload(
        action: .status,
        urlString: nil,
        presentation: .window,
        responsePath: nil,
        targetExecutablePath: targetExecutablePath,
        target: target
    )
}
#endif
