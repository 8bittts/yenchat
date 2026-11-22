#if os(macOS)
import AppKit
import Foundation

enum WebPreviewDefaults {
    static let docsURL = URL(string: "https://yen.chat/#guide")!
}

struct WebPreviewRequest: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case load(URL)
        case back
        case forward
        case reload
        case stop
    }

    let id = UUID()
    let action: Action
}

struct WebPreviewNavigationSnapshot: Sendable {
    let url: URL?
    let title: String?
    let isLoading: Bool
    let canGoBack: Bool
    let canGoForward: Bool
}

@MainActor
final class WebPreviewModel: ObservableObject {
    typealias ExternalURLOpener = (URL) -> Bool

    @Published var addressText: String
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle: String = "YEN Browser"
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var statusMessage: String?
    /// True when statusMessage describes an error/failure (navigation failed,
    /// blocked, or content-process terminated) so the status line can render it
    /// distinctly from benign informational messages.
    @Published private(set) var statusIsError = false
    @Published private(set) var pendingRequest: WebPreviewRequest?
    private(set) var isAddressFieldEditing = false

    private let externalURLOpener: ExternalURLOpener

    init(
        initialURL: URL = WebPreviewDefaults.docsURL,
        externalURLOpener: @escaping ExternalURLOpener = { NSWorkspace.shared.open($0) }
    ) {
        self.externalURLOpener = externalURLOpener
        self.addressText = initialURL.absoluteString
        self.currentURL = initialURL
        self.pendingRequest = WebPreviewRequest(action: .load(initialURL))
    }

    func prepareForPresentation(url: URL?, forceLoadCurrent: Bool = false) {
        if let url {
            handle(WebPreviewURLPolicy.decision(for: url.absoluteString))
        } else if forceLoadCurrent || currentURL == nil {
            let url = currentURL ?? WebPreviewDefaults.docsURL
            handle(WebPreviewURLPolicy.decision(for: url.absoluteString))
        }
    }

    func submitAddress() {
        setAddressFieldEditing(false)
        handle(WebPreviewURLPolicy.decision(for: addressText))
    }

    func openCurrentURLExternally() {
        guard let currentURL else { return }
        openExternally(currentURL)
    }

    @discardableResult
    func openExternally(_ url: URL) -> Bool {
        let opened = externalURLOpener(url)
        isLoading = false
        statusMessage = opened ? "Opening in the default app." : "Could not open in the default app."
        statusIsError = !opened
        return opened
    }

    func goBack() {
        guard canGoBack else { return }
        statusMessage = nil
        statusIsError = false
        pendingRequest = WebPreviewRequest(action: .back)
    }

    func goForward() {
        guard canGoForward else { return }
        statusMessage = nil
        statusIsError = false
        pendingRequest = WebPreviewRequest(action: .forward)
    }

    func reload() {
        statusMessage = nil
        statusIsError = false
        pendingRequest = WebPreviewRequest(action: .reload)
    }

    func stopLoading() {
        isLoading = false
        pendingRequest = WebPreviewRequest(action: .stop)
    }

    func setAddressFieldEditing(_ isEditing: Bool) {
        isAddressFieldEditing = isEditing
    }

    func updateNavigationState(_ snapshot: WebPreviewNavigationSnapshot) {
        if let url = snapshot.url {
            currentURL = url
            if !isAddressFieldEditing {
                addressText = url.absoluteString
            }
        }
        if let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            pageTitle = title
        } else if let url = snapshot.url ?? currentURL {
            pageTitle = title(for: url)
        }
        isLoading = snapshot.isLoading
        canGoBack = snapshot.canGoBack
        canGoForward = snapshot.canGoForward
    }

    func markNavigationFailed(_ message: String, snapshot: WebPreviewNavigationSnapshot) {
        updateNavigationState(snapshot)
        statusMessage = message
        statusIsError = true
        isLoading = false
    }

    func markBlockedNavigation(_ message: String) {
        statusMessage = message
        statusIsError = true
        isLoading = false
    }

    func markContentProcessTerminated(snapshot: WebPreviewNavigationSnapshot) {
        updateNavigationState(snapshot)
        statusMessage = "Web content stopped. Reload to try again."
        statusIsError = true
        isLoading = false
    }

    private func title(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return "YEN Browser"
    }

    private func handle(_ decision: WebPreviewURLDecision) {
        switch decision {
        case .load(let url):
            loadTrusted(url)
        case .openExternally(let url):
            openExternally(url)
        case .block(let message):
            markBlockedNavigation(message)
        }
    }

    private func loadTrusted(_ url: URL) {
        setAddressFieldEditing(false)
        addressText = url.absoluteString
        currentURL = url
        pageTitle = title(for: url)
        statusMessage = nil
        statusIsError = false
        pendingRequest = WebPreviewRequest(action: .load(url))
    }
}
#endif
