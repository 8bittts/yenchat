#if os(macOS)
import AppKit
import Testing
import WebKit
@testable import YEN

@MainActor
struct WebPreviewRepresentableTests {
    @Test func coordinatorDropsQueuedUpdatesAfterDismantle() async {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let coordinator = WebPreviewRepresentable.Coordinator(
            model: model,
            onWebViewDismantled: nil
        )
        let webView = makeTestWebView()
        coordinator.attach(webView)

        coordinator._testApplySnapshot(
            WebPreviewNavigationSnapshot(
                url: URL(string: "https://yen.chat/stale")!,
                title: "Stale",
                isLoading: true,
                canGoBack: true,
                canGoForward: true
            ),
            from: webView
        )
        coordinator.dismantle(webView)
        await drainQueuedModelUpdates()

        #expect(!coordinator._testIsCurrent(webView))
        #expect(model.currentURL == WebPreviewDefaults.docsURL)
        #expect(model.pageTitle != "Stale")
        #expect(model.isLoading == false)
        #expect(model.canGoBack == false)
        #expect(model.canGoForward == false)
    }

    @Test func coordinatorIgnoresStaleWebViewAfterReplacement() async {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let coordinator = WebPreviewRepresentable.Coordinator(
            model: model,
            onWebViewDismantled: nil
        )
        let oldWebView = makeTestWebView()
        let replacementWebView = makeTestWebView()
        coordinator.attach(oldWebView)
        coordinator.attach(replacementWebView)

        coordinator._testApplySnapshot(
            WebPreviewNavigationSnapshot(
                url: URL(string: "https://yen.chat/old")!,
                title: "Old",
                isLoading: true,
                canGoBack: true,
                canGoForward: false
            ),
            from: oldWebView
        )
        await drainQueuedModelUpdates()

        #expect(model.currentURL == WebPreviewDefaults.docsURL)
        #expect(model.pageTitle != "Old")

        coordinator._testApplySnapshot(
            WebPreviewNavigationSnapshot(
                url: URL(string: "https://yen.chat/replacement")!,
                title: "Replacement",
                isLoading: false,
                canGoBack: false,
                canGoForward: true
            ),
            from: replacementWebView
        )
        await drainQueuedModelUpdates()

        #expect(model.currentURL == URL(string: "https://yen.chat/replacement")!)
        #expect(model.pageTitle == "Replacement")
        #expect(model.canGoForward == true)
    }

    @Test func coordinatorDropsContentProcessTerminationAfterDismantle() async {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let coordinator = WebPreviewRepresentable.Coordinator(
            model: model,
            onWebViewDismantled: nil
        )
        let webView = makeTestWebView()
        coordinator.attach(webView)

        coordinator._testMarkContentProcessTerminated(from: webView)
        coordinator.dismantle(webView)
        await drainQueuedModelUpdates()

        #expect(model.statusMessage == nil)
        #expect(model.isLoading == false)
    }

    @Test func coordinatorTearsDownStaleReplacedWebViewDelegates() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let coordinator = WebPreviewRepresentable.Coordinator(
            model: model,
            onWebViewDismantled: nil
        )
        let oldWebView = makeTestWebView()
        let replacementWebView = makeTestWebView()
        coordinator.attach(oldWebView)
        oldWebView.navigationDelegate = coordinator
        oldWebView.uiDelegate = coordinator

        coordinator.attach(replacementWebView)
        coordinator.dismantle(oldWebView)

        #expect(oldWebView.navigationDelegate == nil)
        #expect(oldWebView.uiDelegate == nil)
        #expect(coordinator._testIsCurrent(replacementWebView))
    }

    @Test func coordinatorReplaysCurrentRequestAfterWebViewReplacement() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let coordinator = WebPreviewRepresentable.Coordinator(
            model: model,
            onWebViewDismantled: nil
        )
        let request = model.pendingRequest
        let oldWebView = makeTestWebView()
        let replacementWebView = makeTestWebView()

        coordinator.attach(oldWebView)
        coordinator.apply(request, to: oldWebView)
        #expect(request.map { coordinator._testHasHandledRequest($0) } == true)

        coordinator.attach(replacementWebView)
        #expect(request.map { coordinator._testHasHandledRequest($0) } == false)

        coordinator.apply(request, to: replacementWebView)
        #expect(request.map { coordinator._testHasHandledRequest($0) } == true)
    }

    @Test func splitFocusReferenceClearsOnlyMatchingDismantledWebView() {
        let controller = BrowserSplitController.shared
        let activeWebView = makeTestWebView()
        let staleWebView = makeTestWebView()
        defer { controller.close() }

        controller.setWebView(activeWebView)
        controller.clearWebView(staleWebView)
        #expect(controller._testIsTrackingWebView(activeWebView))

        controller.clearWebView(activeWebView)
        #expect(!controller._testIsTrackingWebView(activeWebView))
    }
}

@MainActor
private func makeTestWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    return WKWebView(frame: .zero, configuration: configuration)
}

@MainActor
private func drainQueuedModelUpdates() async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: 20_000_000)
    await Task.yield()
}
#endif
