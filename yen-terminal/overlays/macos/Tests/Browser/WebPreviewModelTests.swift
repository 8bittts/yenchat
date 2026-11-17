#if os(macOS)
import Foundation
import Testing
@testable import YEN

@MainActor
struct WebPreviewModelTests {
    @Test func focusingExistingBrowserDoesNotReloadCurrentPage() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let initialRequest = model.pendingRequest

        model.prepareForPresentation(url: nil)

        #expect(model.pendingRequest == initialRequest)
    }

    @Test func reopeningBrowserIssuesFreshLoadForCurrentPage() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let initialRequest = model.pendingRequest

        model.prepareForPresentation(url: nil, forceLoadCurrent: true)

        #expect(model.pendingRequest != initialRequest)
        #expect(model.currentURL == WebPreviewDefaults.docsURL)
    }

    @Test func presentationURLUsesPolicyBeforeLoading() {
        let currentURL = URL(string: "https://yen.chat/docs")!
        let model = WebPreviewModel(initialURL: currentURL)
        let initialRequest = model.pendingRequest
        model.updateNavigationState(WebPreviewNavigationSnapshot(
            url: currentURL,
            title: "YEN Docs",
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        ))

        model.prepareForPresentation(url: URL(string: "file:///Users/dev/secrets.txt")!)

        #expect(model.currentURL == currentURL)
        #expect(model.pendingRequest == initialRequest)
        #expect(model.isLoading == false)
        #expect(model.statusMessage == "File URLs are not opened silently.")
    }

    @Test func presentationExternalURLUsesInjectedHandoff() {
        var openedURLs: [URL] = []
        let model = WebPreviewModel(externalURLOpener: { url in
            openedURLs.append(url)
            return true
        })

        model.prepareForPresentation(url: URL(string: "mailto:hello@yen.chat")!)

        #expect(openedURLs == [URL(string: "mailto:hello@yen.chat")!])
        #expect(model.statusMessage == "Opening in the default app.")
    }

    @Test func blockedAddressSubmissionClearsLoadingState() {
        let currentURL = URL(string: "https://yen.chat/docs")!
        let model = WebPreviewModel(initialURL: currentURL)
        model.updateNavigationState(WebPreviewNavigationSnapshot(
            url: currentURL,
            title: "YEN Docs",
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        ))
        model.addressText = "http://example.com"

        model.submitAddress()

        #expect(model.currentURL == currentURL)
        #expect(model.isLoading == false)
        #expect(model.statusMessage == "Only HTTPS or localhost HTTP URLs can open in YEN.")
    }

    @Test func trustedAddressSubmissionNormalizesLoopbackAndIssuesLoadRequest() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        let initialRequest = model.pendingRequest
        model.addressText = "localhost:5173"

        model.submitAddress()

        #expect(model.currentURL == URL(string: "http://localhost:5173")!)
        #expect(model.addressText == "http://localhost:5173")
        #expect(model.pageTitle == "localhost")
        #expect(model.pendingRequest != initialRequest)
        #expect(model.pendingRequest?.action == .load(URL(string: "http://localhost:5173")!))
    }

    @Test func loadingToolbarActionsStopThenReloadWithoutChangingAddress() {
        let currentURL = URL(string: "https://yen.chat/docs")!
        let model = WebPreviewModel(initialURL: currentURL)
        model.updateNavigationState(WebPreviewNavigationSnapshot(
            url: currentURL,
            title: "YEN Docs",
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        ))

        model.stopLoading()
        #expect(model.isLoading == false)
        #expect(model.pendingRequest?.action == .stop)
        #expect(model.addressText == currentURL.absoluteString)

        model.reload()
        #expect(model.pendingRequest?.action == .reload)
        #expect(model.addressText == currentURL.absoluteString)
    }

    @Test func navigationSnapshotDoesNotOverwriteAddressWhileEditing() {
        let originalURL = URL(string: "https://yen.chat/docs")!
        let navigatedURL = URL(string: "https://yen.chat/blog")!
        let model = WebPreviewModel(initialURL: originalURL)

        model.addressText = "localhost:5173/draft"
        model.setAddressFieldEditing(true)
        model.updateNavigationState(WebPreviewNavigationSnapshot(
            url: navigatedURL,
            title: "YEN Blog",
            isLoading: true,
            canGoBack: true,
            canGoForward: false
        ))

        #expect(model.currentURL == navigatedURL)
        #expect(model.addressText == "localhost:5173/draft")
        #expect(model.pageTitle == "YEN Blog")
        #expect(model.isLoading == true)
        #expect(model.canGoBack == true)
        #expect(model.canGoForward == false)

        model.setAddressFieldEditing(false)
        model.updateNavigationState(WebPreviewNavigationSnapshot(
            url: navigatedURL,
            title: "YEN Blog",
            isLoading: false,
            canGoBack: true,
            canGoForward: false
        ))

        #expect(model.addressText == navigatedURL.absoluteString)
        #expect(model.isLoading == false)
    }

    @Test func addressSubmissionClearsEditingStateBeforeNormalizingAddress() {
        let model = WebPreviewModel(initialURL: WebPreviewDefaults.docsURL)
        model.addressText = "localhost:5173"
        model.setAddressFieldEditing(true)

        model.submitAddress()

        #expect(model.isAddressFieldEditing == false)
        #expect(model.addressText == "http://localhost:5173")
        #expect(model.currentURL == URL(string: "http://localhost:5173")!)
    }

    @Test func externalHandoffReportsSuccessAndFailure() {
        var openedURLs: [URL] = []
        let successModel = WebPreviewModel(externalURLOpener: { url in
            openedURLs.append(url)
            return true
        })
        successModel.addressText = "mailto:hello@yen.chat"
        successModel.submitAddress()

        #expect(openedURLs == [URL(string: "mailto:hello@yen.chat")!])
        #expect(successModel.statusMessage == "Opening in the default app.")

        let failureModel = WebPreviewModel(externalURLOpener: { _ in false })
        let opened = failureModel.openExternally(URL(string: "mailto:hello@yen.chat")!)

        #expect(!opened)
        #expect(failureModel.statusMessage == "Could not open in the default app.")
        #expect(failureModel.isLoading == false)
    }

    @Test func defaultBrowserHandoffUsesCurrentURL() {
        let currentURL = URL(string: "https://yen.chat/docs")!
        var openedURLs: [URL] = []
        let model = WebPreviewModel(initialURL: currentURL, externalURLOpener: { url in
            openedURLs.append(url)
            return true
        })

        model.openCurrentURLExternally()

        #expect(openedURLs == [currentURL])
        #expect(model.statusMessage == "Opening in the default app.")
    }

    @Test func utilityAndSplitModelsKeepIndependentNavigationState() {
        let utilityModel = WebPreviewModel(initialURL: URL(string: "https://yen.chat/window")!)
        let splitModel = WebPreviewModel(initialURL: URL(string: "https://yen.chat/split")!)
        let splitInitialRequest = splitModel.pendingRequest

        utilityModel.updateNavigationState(WebPreviewNavigationSnapshot(
            url: URL(string: "https://yen.chat/window/page")!,
            title: "Window Page",
            isLoading: false,
            canGoBack: true,
            canGoForward: false
        ))
        splitModel.updateNavigationState(WebPreviewNavigationSnapshot(
            url: URL(string: "https://yen.chat/split/page")!,
            title: "Split Page",
            isLoading: false,
            canGoBack: false,
            canGoForward: true
        ))

        utilityModel.goBack()

        #expect(utilityModel.pendingRequest?.action == .back)
        #expect(splitModel.pendingRequest == splitInitialRequest)
        #expect(splitModel.currentURL == URL(string: "https://yen.chat/split/page")!)
        #expect(splitModel.pageTitle == "Split Page")

        splitModel.reload()
        #expect(splitModel.pendingRequest?.action == .reload)
        #expect(utilityModel.currentURL == URL(string: "https://yen.chat/window/page")!)
        #expect(utilityModel.pageTitle == "Window Page")
    }

    @Test func contentProcessTerminationStopsLoadingAndShowsReloadStatus() {
        let currentURL = URL(string: "https://yen.chat/docs")!
        let model = WebPreviewModel(initialURL: currentURL)
        let snapshot = WebPreviewNavigationSnapshot(
            url: currentURL,
            title: "YEN Docs",
            isLoading: true,
            canGoBack: true,
            canGoForward: false
        )

        model.markContentProcessTerminated(snapshot: snapshot)

        #expect(model.currentURL == currentURL)
        #expect(model.pageTitle == "YEN Docs")
        #expect(model.canGoBack == true)
        #expect(model.canGoForward == false)
        #expect(model.isLoading == false)
        #expect(model.statusMessage == "Web content stopped. Reload to try again.")
    }
}
#endif
