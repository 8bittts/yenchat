#if os(macOS)
import AppKit
import SwiftUI
import WebKit

struct WebPreviewRepresentable: NSViewRepresentable {
    @ObservedObject var model: WebPreviewModel
    let onWebViewReady: ((WKWebView) -> Void)?
    let onWebViewDismantled: ((WKWebView) -> Void)?

    init(
        model: WebPreviewModel,
        onWebViewReady: ((WKWebView) -> Void)? = nil,
        onWebViewDismantled: ((WKWebView) -> Void)? = nil
    ) {
        self.model = model
        self.onWebViewReady = onWebViewReady
        self.onWebViewDismantled = onWebViewDismantled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            model: model,
            onWebViewDismantled: onWebViewDismantled
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.attach(webView)
        onWebViewReady?(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(model.pendingRequest, to: webView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle(nsView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebPreviewModel
        let onWebViewDismantled: ((WKWebView) -> Void)?
        private weak var webView: WKWebView?
        private var webViewIdentifier: ObjectIdentifier?
        private var lifecycleGeneration = UUID()
        private var handledRequestID: UUID?

        init(
            model: WebPreviewModel,
            onWebViewDismantled: ((WKWebView) -> Void)?
        ) {
            self.model = model
            self.onWebViewDismantled = onWebViewDismantled
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            webViewIdentifier = ObjectIdentifier(webView)
            lifecycleGeneration = UUID()
            handledRequestID = nil
        }

        func dismantle(_ webView: WKWebView) {
            let wasCurrent = isCurrent(webView)
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil

            if wasCurrent {
                self.webView = nil
                webViewIdentifier = nil
                lifecycleGeneration = UUID()
            }
            onWebViewDismantled?(webView)
        }

        func apply(_ request: WebPreviewRequest?, to webView: WKWebView) {
            guard isCurrent(webView), let request, request.id != handledRequestID else { return }
            handledRequestID = request.id

            switch request.action {
            case .load(let url):
                webView.load(URLRequest(url: url))
            case .back:
                if webView.canGoBack {
                    webView.goBack()
                }
            case .forward:
                if webView.canGoForward {
                    webView.goForward()
                }
            case .reload:
                webView.reload()
            case .stop:
                webView.stopLoading()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard isCurrent(webView) else {
                decisionHandler(.cancel)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let frame: WebPreviewNavigationFrame = (navigationAction.targetFrame?.isMainFrame ?? true)
                ? .mainFrame
                : .subframe

            switch WebPreviewNavigationPolicy.decision(for: url.absoluteString, frame: frame) {
            case .allow:
                decisionHandler(.allow)
            case .openExternally(let externalURL):
                updateModel(for: webView) { model in
                    model.openExternally(externalURL)
                }
                decisionHandler(.cancel)
            case .block(let message):
                updateModel(for: webView) { model in
                    model.markBlockedNavigation(message)
                }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            updateModel(with: snapshot(for: webView), for: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateModel(with: snapshot(for: webView), for: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateModel(with: snapshot(for: webView), for: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            markFailure(error, webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            markFailure(error, webView: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let snapshot = snapshot(for: webView)
            updateModel(for: webView) { model in
                model.markContentProcessTerminated(snapshot: snapshot)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard isCurrent(webView),
                  navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url
            else {
                return nil
            }

            switch WebPreviewURLPolicy.decision(for: url.absoluteString) {
            case .load:
                webView.load(URLRequest(url: url))
            case .openExternally(let externalURL):
                updateModel(for: webView) { model in
                    model.openExternally(externalURL)
                }
            case .block(let message):
                updateModel(for: webView) { model in
                    model.markBlockedNavigation(message)
                }
            }
            return nil
        }

        private func markFailure(_ error: Error, webView: WKWebView) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                updateModel(with: snapshot(for: webView), for: webView)
                return
            }

            let snapshot = snapshot(for: webView)
            updateModel(for: webView) { model in
                model.markNavigationFailed(error.localizedDescription, snapshot: snapshot)
            }
        }

        private func updateModel(with snapshot: WebPreviewNavigationSnapshot, for webView: WKWebView) {
            updateModel(for: webView) { model in
                model.updateNavigationState(snapshot)
            }
        }

        private func updateModel(
            for webView: WKWebView,
            _ update: @escaping @MainActor (WebPreviewModel) -> Void
        ) {
            guard isCurrent(webView) else { return }
            let webViewIdentifier = ObjectIdentifier(webView)
            let generation = lifecycleGeneration
            Task { @MainActor [weak self, model] in
                guard self?.isCurrent(webViewIdentifier: webViewIdentifier, generation: generation) == true else {
                    return
                }
                update(model)
            }
        }

        private func isCurrent(_ webView: WKWebView) -> Bool {
            // `webView` is only ever passed a live WKWebView, and `webView`/`webViewIdentifier`
            // are set in lockstep, so the identity check already implies matching identifiers.
            self.webView === webView
        }

        private func isCurrent(webViewIdentifier: ObjectIdentifier, generation: UUID) -> Bool {
            self.webViewIdentifier == webViewIdentifier && lifecycleGeneration == generation && webView != nil
        }

        private func snapshot(for webView: WKWebView) -> WebPreviewNavigationSnapshot {
            WebPreviewNavigationSnapshot(
                url: webView.url,
                title: webView.title,
                isLoading: webView.isLoading,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
        }
    }
}

#if DEBUG
extension WebPreviewRepresentable.Coordinator {
    func _testApplySnapshot(_ snapshot: WebPreviewNavigationSnapshot, from webView: WKWebView) {
        updateModel(with: snapshot, for: webView)
    }

    func _testMarkContentProcessTerminated(from webView: WKWebView) {
        webViewWebContentProcessDidTerminate(webView)
    }

    func _testIsCurrent(_ webView: WKWebView) -> Bool {
        isCurrent(webView)
    }

    func _testHasHandledRequest(_ request: WebPreviewRequest) -> Bool {
        handledRequestID == request.id
    }
}
#endif
#endif
