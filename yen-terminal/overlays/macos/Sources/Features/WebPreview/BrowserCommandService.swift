#if os(macOS)
import AppKit
import Foundation

@MainActor
final class BrowserCommandService {
    enum SplitFallback {
        case failClosed
        case window
    }

    static let shared = BrowserCommandService()

    private var keyWindowProvider: () -> NSWindow? = { NSApp.keyWindow }

    private init() {}

    @discardableResult
    func perform(
        action: WebPreviewCommandAction,
        urlString: String?,
        presentation: WebPreviewPresentation,
        target: BrowserSurfaceTarget,
        sourceWindow: NSWindow? = nil,
        splitFallback: SplitFallback = .failClosed,
        acknowledgedExecutablePath: String? = nil
    ) -> WebPreviewCommandResult {
        switch action {
        case .open:
            return open(
                urlString: urlString,
                presentation: presentation,
                sourceWindow: sourceWindow,
                splitFallback: splitFallback
            )
        case .back:
            return withExistingModel(actionName: "back", target: target) { model in
                guard model.canGoBack else {
                    return WebPreviewCommandResult(accepted: false, message: "Browser cannot go back.")
                }
                model.goBack()
                return WebPreviewCommandResult(accepted: true, message: "Browser back command sent.")
            }
        case .forward:
            return withExistingModel(actionName: "forward", target: target) { model in
                guard model.canGoForward else {
                    return WebPreviewCommandResult(accepted: false, message: "Browser cannot go forward.")
                }
                model.goForward()
                return WebPreviewCommandResult(accepted: true, message: "Browser forward command sent.")
            }
        case .reload:
            return withExistingModel(actionName: "reload", target: target) { model in
                model.reload()
                return WebPreviewCommandResult(accepted: true, message: "Browser reload command sent.")
            }
        case .close:
            switch resolveExistingSurface(actionName: "close", target: target) {
            case .surface(let surface):
                surface.close()
                return WebPreviewCommandResult(accepted: true, message: "Browser \(surface.name) closed.")
            case .missing(let message):
                return WebPreviewCommandResult(accepted: false, message: message)
            }
        case .status:
            return status(target: target, acknowledgedExecutablePath: acknowledgedExecutablePath)
        }
    }

    @discardableResult
    func openDefault(
        presentation: WebPreviewPresentation,
        sourceWindow: NSWindow? = nil,
        splitFallback: SplitFallback = .failClosed
    ) -> WebPreviewCommandResult {
        openTrustedURL(
            nil,
            presentation: presentation,
            sourceWindow: sourceWindow,
            splitFallback: splitFallback
        )
    }

    @discardableResult
    func openTrustedURL(
        _ url: URL?,
        presentation: WebPreviewPresentation,
        sourceWindow: NSWindow? = nil,
        splitFallback: SplitFallback = .failClosed
    ) -> WebPreviewCommandResult {
        switch resolvedPresentation(presentation) {
        case .split:
            let splitWindow = sourceWindow ?? keyWindowProvider() ?? NSApp.mainWindow
            if BrowserSplitController.shared.show(url: url, in: splitWindow) {
                return WebPreviewCommandResult(accepted: true, message: "Browser split opened.")
            }
            switch splitFallback {
            case .failClosed:
                return WebPreviewCommandResult(
                    accepted: false,
                    message: "No active terminal window is available for browser split."
                )
            case .window:
                WebPreviewController.shared.show(url: url)
                return WebPreviewCommandResult(accepted: true, message: "Browser window opened.")
            }
        case .window, .automatic:
            WebPreviewController.shared.show(url: url)
            return WebPreviewCommandResult(accepted: true, message: "Browser window opened.")
        }
    }

    private func open(
        urlString: String?,
        presentation: WebPreviewPresentation,
        sourceWindow: NSWindow?,
        splitFallback: SplitFallback
    ) -> WebPreviewCommandResult {
        let decision: WebPreviewURLDecision
        if let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            decision = WebPreviewURLPolicy.decision(for: urlString)
        } else {
            decision = .load(WebPreviewDefaults.docsURL)
        }

        switch decision {
        case .load(let url):
            return openTrustedURL(
                url,
                presentation: presentation,
                sourceWindow: sourceWindow,
                splitFallback: splitFallback
            )
        case .openExternally(let url):
            let opened = WebPreviewController.shared.model.openExternally(url)
            return WebPreviewCommandResult(
                accepted: opened,
                message: opened ? "Opening in the default app." : "Could not open in the default app."
            )
        case .block(let message):
            return WebPreviewCommandResult(accepted: false, message: message)
        }
    }

    private func resolvedPresentation(_ presentation: WebPreviewPresentation) -> WebPreviewPresentation {
        switch presentation {
        case .automatic:
            return NativeBrowserPreferences.browserSplitEnabled() ? .split : .window
        case .window, .split:
            return presentation
        }
    }

    private func withExistingModel(
        actionName: String,
        target: BrowserSurfaceTarget,
        _ body: (WebPreviewModel) -> WebPreviewCommandResult
    ) -> WebPreviewCommandResult {
        switch resolveExistingSurface(actionName: actionName, target: target) {
        case .surface(let surface):
            return body(surface.model)
        case .missing(let message):
            return WebPreviewCommandResult(accepted: false, message: message)
        }
    }

    private enum SurfaceResolution {
        case surface(BrowserCommandSurface)
        case missing(String)
    }

    private func resolveExistingSurface(
        actionName: String,
        target: BrowserSurfaceTarget
    ) -> SurfaceResolution {
        switch target {
        case .automatic:
            if BrowserSplitController.shared.visibleInAnyWindow {
                return .surface(.split)
            }
            if WebPreviewController.shared.hasWindow {
                return .surface(.window)
            }
            return .missing("No browser surface is open for \(actionName).")
        case .window:
            guard WebPreviewController.shared.hasWindow else {
                return .missing("No browser window is open for \(actionName).")
            }
            return .surface(.window)
        case .split:
            guard BrowserSplitController.shared.visibleInAnyWindow else {
                return .missing("No browser split is open for \(actionName).")
            }
            return .surface(.split)
        case .focused:
            let keyWindow = keyWindowProvider()
            if WebPreviewController.shared.isFocused(keyWindow: keyWindow) {
                return .surface(.window)
            }
            if BrowserSplitController.shared.isWebViewFocused(keyWindow: keyWindow) {
                return .surface(.split)
            }
            return .missing("No focused browser surface is open for \(actionName).")
        }
    }

    private func status(
        target: BrowserSurfaceTarget,
        acknowledgedExecutablePath: String?
    ) -> WebPreviewCommandResult {
        let windowStatus = WebPreviewController.shared.hasWindow ? "window=open" : "window=closed"
        let splitStatus = BrowserSplitController.shared.visibleInAnyWindow ? "split=open" : "split=closed"
        let message: String
        switch target {
        case .automatic:
            message = "\(windowStatus) \(splitStatus)"
        case .window:
            message = windowStatus
        case .split:
            message = splitStatus
        case .focused:
            message = "focused=\(focusedSurfaceName()) \(windowStatus) \(splitStatus)"
        }
        return WebPreviewCommandResult(
            accepted: true,
            message: message,
            acknowledgedExecutablePath: acknowledgedExecutablePath
        )
    }

    private func focusedSurfaceName() -> String {
        switch resolveExistingSurface(actionName: "status", target: .focused) {
        case .surface(let surface):
            return surface.name
        case .missing:
            return "none"
        }
    }
}

@MainActor
private extension BrowserCommandSurface {
    var name: String {
        switch self {
        case .window: return "window"
        case .split: return "split"
        }
    }

    var model: WebPreviewModel {
        switch self {
        case .window: return WebPreviewController.shared.model
        case .split: return BrowserSplitController.shared.model
        }
    }

    func close() {
        switch self {
        case .window: WebPreviewController.shared.hide()
        case .split: BrowserSplitController.shared.close()
        }
    }
}

#if DEBUG
extension BrowserCommandService {
    func _testSetKeyWindowProvider(_ provider: (() -> NSWindow?)?) {
        keyWindowProvider = provider ?? { NSApp.keyWindow }
    }
}
#endif
#endif
