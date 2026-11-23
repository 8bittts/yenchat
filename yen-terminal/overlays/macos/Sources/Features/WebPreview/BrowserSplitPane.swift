#if os(macOS)
import AppKit
import SwiftUI

struct BrowserSplitPane: View {
    @ObservedObject var model: WebPreviewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrowserSplitHeader(onClose: onClose)
            Divider()

            WebPreviewView(
                model: model,
                minimumSize: CGSize(width: 320, height: 240),
                onWebViewReady: { webView in
                    MainActor.assumeIsolated {
                        BrowserSplitController.shared.setWebView(webView)
                    }
                },
                onWebViewDismantled: { webView in
                    MainActor.assumeIsolated {
                        BrowserSplitController.shared.clearWebView(webView)
                    }
                }
            )
        }
        .frame(minWidth: 320, idealWidth: 520, maxWidth: 900)
    }
}

private struct BrowserSplitHeader: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Browser")
                .font(YENTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close browser split")
            .accessibilityLabel("Close browser split")
        }
        .padding(.horizontal, WebPreviewChromeMetrics.horizontalPadding)
        .padding(.vertical, WebPreviewChromeMetrics.verticalPadding)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
