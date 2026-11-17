#if os(macOS)
import AppKit
import SwiftUI
import WebKit

struct WebPreviewView: View {
    @ObservedObject var model: WebPreviewModel
    let minimumSize: CGSize
    let showsInlineToolbar: Bool
    let onWebViewReady: ((WKWebView) -> Void)?
    let onWebViewDismantled: ((WKWebView) -> Void)?

    init(
        model: WebPreviewModel,
        minimumSize: CGSize = CGSize(width: 840, height: 560),
        showsInlineToolbar: Bool = true,
        onWebViewReady: ((WKWebView) -> Void)? = nil,
        onWebViewDismantled: ((WKWebView) -> Void)? = nil
    ) {
        self.model = model
        self.minimumSize = minimumSize
        self.showsInlineToolbar = showsInlineToolbar
        self.onWebViewReady = onWebViewReady
        self.onWebViewDismantled = onWebViewDismantled
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsInlineToolbar {
                WebPreviewToolbar(model: model)
                Divider()
            }

            WebPreviewRepresentable(
                model: model,
                onWebViewReady: onWebViewReady,
                onWebViewDismantled: onWebViewDismantled
            )
        }
        .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
    }
}
#endif
