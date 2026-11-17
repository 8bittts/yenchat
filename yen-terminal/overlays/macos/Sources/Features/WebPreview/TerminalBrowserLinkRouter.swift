#if os(macOS)
import AppKit
import Foundation

enum TerminalBrowserLinkRouter {
    static func open(
        _ url: URL,
        presentation: WebPreviewPresentation = .automatic,
        targetWindow: NSWindow? = nil
    ) -> Bool {
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            openOnMain(url, presentation: presentation, targetWindow: targetWindow ?? NSApp.keyWindow)
        }
    }

    @MainActor
    private static func openOnMain(
        _ url: URL,
        presentation: WebPreviewPresentation,
        targetWindow: NSWindow?
    ) -> Bool {
        guard let routedURL = captureURL(
            url,
            linkCaptureEnabled: NativeBrowserPreferences.terminalLinkCaptureEnabled()
        ) else {
            return false
        }

        let result = BrowserCommandService.shared.openTrustedURL(
            routedURL,
            presentation: presentation,
            sourceWindow: targetWindow,
            splitFallback: .window
        )
        return result.accepted
    }

    nonisolated static func captureURL(
        _ url: URL,
        linkCaptureEnabled: Bool
    ) -> URL? {
        guard linkCaptureEnabled else { return nil }
        switch WebPreviewURLPolicy.decision(for: url.absoluteString) {
        case .load(let trustedURL):
            return trustedURL
        case .openExternally, .block:
            return nil
        }
    }

}
#endif
