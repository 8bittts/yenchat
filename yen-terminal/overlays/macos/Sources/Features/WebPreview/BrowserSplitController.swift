#if os(macOS)
import AppKit
import SwiftUI
import WebKit

@MainActor
final class BrowserSplitController: ObservableObject {
    static let shared = BrowserSplitController()

    let model = WebPreviewModel()

    @Published private(set) var isVisible = false
    @Published private(set) var targetWindowNumber: Int?
    @Published private(set) var targetWindowDiagnosticIdentifier: String?

    private var terminalWindows: [ObjectIdentifier: RegisteredTerminalWindow] = [:]
    private var windowCloseObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var targetWindowIdentifier: ObjectIdentifier?
    private weak var targetWindow: NSWindow?
    private weak var webView: WKWebView?
    #if DEBUG
    private var debugRetainedSplitWindow: NSWindow?
    #endif

    var visibleInAnyWindow: Bool {
        liveTargetWindow() != nil
    }

    private init() {}

    func registerTerminalWindow(_ window: NSWindow?) {
        guard let window else { return }
        pruneDeadWindows()

        let identifier = ObjectIdentifier(window)
        terminalWindows[identifier] = RegisteredTerminalWindow(window: window)
        if windowCloseObservers[identifier] == nil {
            windowCloseObservers[identifier] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: nil
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    self?.unregisterTerminalWindow(window)
                }
            }
        }
    }

    func unregisterTerminalWindow(_ window: NSWindow?) {
        guard let window else { return }
        let identifier = ObjectIdentifier(window)
        terminalWindows.removeValue(forKey: identifier)
        removeCloseObserver(for: identifier)
        if targetWindow === window {
            close()
        }
    }

    @discardableResult
    func show(url: URL? = nil, in window: NSWindow?) -> Bool {
        pruneDeadWindows()
        guard let window, isRegisteredTerminalWindow(window) else {
            return false
        }
        guard !(window is NSPanel), !(window is QuickTerminalWindow) else {
            return false
        }

        activateSplit(url: url, in: window, bringForward: true)
        return true
    }

    func close() {
        model.stopLoading()
        model.setAddressFieldEditing(false)
        isVisible = false
        targetWindowNumber = nil
        targetWindowDiagnosticIdentifier = nil
        targetWindowIdentifier = nil
        targetWindow = nil
        webView = nil
        #if DEBUG
        debugRetainedSplitWindow = nil
        #endif
    }

    func isVisible(in window: NSWindow?) -> Bool {
        guard let window, let liveTarget = liveTargetWindow() else { return false }
        return liveTarget === window
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    func clearWebView(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        self.webView = nil
    }

    func isWebViewFocused(keyWindow: NSWindow?) -> Bool {
        guard isVisible(in: keyWindow),
              let focusedView = keyWindow?.firstResponder as? NSView,
              let webView,
              focusedView.isDescendant(of: webView) || focusedView === webView
        else {
            return false
        }

        return true
    }

    @discardableResult
    func closeIfWebViewFocused(keyWindow: NSWindow?) -> Bool {
        guard isWebViewFocused(keyWindow: keyWindow) else { return false }
        close()
        return true
    }

    private func isRegisteredTerminalWindow(_ window: NSWindow) -> Bool {
        let identifier = ObjectIdentifier(window)
        guard let registered = terminalWindows[identifier], registered.window === window else {
            terminalWindows.removeValue(forKey: identifier)
            removeCloseObserver(for: identifier)
            return false
        }
        return true
    }

    private func activateSplit(url: URL?, in window: NSWindow, bringForward: Bool) {
        let identifier = ObjectIdentifier(window)
        targetWindow = window
        targetWindowIdentifier = identifier
        targetWindowNumber = window.windowNumber
        targetWindowDiagnosticIdentifier = Self.diagnosticIdentifier(for: window)
        model.prepareForPresentation(url: url, forceLoadCurrent: true)
        isVisible = true
        if bringForward {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func liveTargetWindow() -> NSWindow? {
        // No prune here: this runs on every surface-state query (per focusedSurfaceFrameTick).
        // Dead/closed windows are already removed by the willCloseNotification observer
        // (-> unregisterTerminalWindow) and the isRegisteredTerminalWindow self-prune, and the
        // guard below independently rejects a deallocated/unregistered target. register()/show()
        // still prune. A non-target weak-nil entry left between queries is harmless (no retain).
        guard isVisible,
              let targetWindowIdentifier,
              let targetWindow,
              terminalWindows[targetWindowIdentifier]?.window === targetWindow
        else {
            if isVisible {
                close()
            }
            return nil
        }
        return targetWindow
    }

    private func pruneDeadWindows() {
        let deadIdentifiers = terminalWindows.compactMap { identifier, registered in
            registered.window == nil ? identifier : nil
        }
        for identifier in deadIdentifiers {
            terminalWindows.removeValue(forKey: identifier)
            removeCloseObserver(for: identifier)
        }
    }

    private func removeCloseObserver(for identifier: ObjectIdentifier) {
        guard let observer = windowCloseObservers.removeValue(forKey: identifier) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    private static func diagnosticIdentifier(for window: NSWindow) -> String {
        "windowNumber=\(window.windowNumber) identity=\(ObjectIdentifier(window))"
    }
}

private final class RegisteredTerminalWindow {
    weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
    }
}

#if DEBUG
extension BrowserSplitController {
    @discardableResult
    func _testInstallVisibleSplitForCommandRouting(url: URL? = nil, in window: NSWindow? = nil) -> NSWindow {
        let splitWindow: NSWindow
        if let window {
            splitWindow = window
        } else {
            splitWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            debugRetainedSplitWindow = splitWindow
        }
        registerTerminalWindow(splitWindow)
        activateSplit(url: url, in: splitWindow, bringForward: false)
        return splitWindow
    }

    func _testIsTrackingWebView(_ webView: WKWebView) -> Bool {
        self.webView === webView
    }
}
#endif

#endif
