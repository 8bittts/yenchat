#if os(macOS)
import AppKit
import SwiftUI

/// Shared insets for the Web Preview chrome bars (split-pane header + inline
/// toolbar) so they don't drift as independent literals.
enum WebPreviewChromeMetrics {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
}

struct WebPreviewToolbar: View {
    @ObservedObject var model: WebPreviewModel

    var body: some View {
        VStack(spacing: 6) {
            WebPreviewNavigationControls(model: model)
            WebPreviewStatusLine(model: model)
        }
        .padding(.horizontal, WebPreviewChromeMetrics.horizontalPadding)
        .padding(.vertical, WebPreviewChromeMetrics.verticalPadding)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
final class WebPreviewWindowToolbar: NSToolbar, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("com.yenchat.yen.browser.toolbar")
    private static let controlsIdentifier = NSToolbarItem.Identifier("com.yenchat.yen.browser.controls")

    private let model: WebPreviewModel

    init(model: WebPreviewModel) {
        self.model = model
        super.init(identifier: Self.toolbarIdentifier)
        allowsUserCustomization = false
        autosavesConfiguration = false
        displayMode = .iconOnly
        sizeMode = .regular
        delegate = self
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.controlsIdentifier else {
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let hostingView = NSHostingView(rootView: WebPreviewWindowToolbarContent(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.widthAnchor.constraint(greaterThanOrEqualToConstant: 640),
            hostingView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        ])
        item.view = hostingView
        item.visibilityPriority = .user
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.controlsIdentifier, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.controlsIdentifier]
    }
}

private struct WebPreviewWindowToolbarContent: View {
    @ObservedObject var model: WebPreviewModel

    var body: some View {
        HStack(spacing: 8) {
            WebPreviewNavigationControls(
                model: model,
                addressMinWidth: 280,
                addressIdealWidth: 420
            )

            Divider()
                .frame(height: 18)

            WebPreviewStatusContent(model: model)
                .frame(minWidth: 80, idealWidth: 180, maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 32)
    }
}

private struct WebPreviewNavigationControls: View {
    @ObservedObject var model: WebPreviewModel
    @FocusState private var addressFieldFocused: Bool
    // Default floor so the split-pane inline toolbar keeps a readable address
    // field even at the pane's 320pt minimum; the standalone window overrides
    // this with a wider value.
    var addressMinWidth: CGFloat? = 120
    var addressIdealWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Back")
            .accessibilityLabel("Back")

            Button {
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Forward")
            .accessibilityLabel("Forward")

            Button {
                if model.isLoading {
                    model.stopLoading()
                } else {
                    model.reload()
                }
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(model.isLoading ? "Stop" : "Reload")
            .accessibilityLabel(model.isLoading ? "Stop" : "Reload")

            TextField("https://yen.chat/docs", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: addressMinWidth, idealWidth: addressIdealWidth)
                .focused($addressFieldFocused)
                .onChange(of: addressFieldFocused) { focused in
                    model.setAddressFieldEditing(focused)
                }
                .onSubmit {
                    model.submitAddress()
                    addressFieldFocused = false
                }
                .accessibilityLabel("Browser address")

            Button("Open") {
                model.submitAddress()
                addressFieldFocused = false
            }
            .help("Open address")

            Button {
                model.openCurrentURLExternally()
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .disabled(model.currentURL == nil)
            .help("Open in default browser")
            .accessibilityLabel("Open in default browser")
        }
        .onDisappear {
            model.setAddressFieldEditing(false)
        }
    }
}

private struct WebPreviewStatusLine: View {
    @ObservedObject var model: WebPreviewModel

    var body: some View {
        HStack(spacing: 8) {
            WebPreviewStatusContent(model: model)
            Spacer()
        }
        .frame(height: 18)
    }
}

private struct WebPreviewStatusContent: View {
    @ObservedObject var model: WebPreviewModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            }

            if model.statusIsError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(Color(NSColor.systemRed))
                    .accessibilityHidden(true)
            }
            Text(model.statusMessage ?? model.pageTitle)
                .font(.caption)
                .foregroundColor(
                    model.statusIsError
                        ? Color(NSColor.systemRed)
                        : (model.statusMessage == nil ? .secondary : .primary)
                )
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#endif
