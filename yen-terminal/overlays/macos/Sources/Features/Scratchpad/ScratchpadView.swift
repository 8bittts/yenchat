#if os(macOS)
import AppKit
import SwiftUI

/// Editor for the floating scratchpad.
struct ScratchpadView: View {
    @ObservedObject var controller: ScratchpadController

    var body: some View {
        ScratchpadTextEditor(text: $controller.text) { controller.registerTextView($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ScratchpadTextEditor: NSViewRepresentable {
    private static let horizontalInset = YENDesignTokens.contentInset
    private static let verticalInset = YENDesignTokens.contentInset

    @Binding var text: String
    let onReady: (NSTextView) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ScratchpadEditorTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.setAccessibilityLabel("Scratchpad notes")
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: Self.horizontalInset, height: Self.verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        let end = textView.string.utf16.count
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))

        onReady(textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text != textView.string {
                text = textView.string
            }
        }

        // Copy on Select: copy the live selection straight from the text view's
        // own selection delegate. This is immune to whether the selection's
        // terminating mouse-up ever reaches an NSEvent monitor. An empty
        // selection (a plain click or caret move) never writes the clipboard.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated {
                _ = CopyOnSelectClipboard.copyIfEnabled(
                    textView,
                    enabled: SettingsController.shared.copyOnSelect
                )
            }
        }
    }
}

private final class ScratchpadEditorTextView: NSTextView {
    override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool {
        false
    }

    override func paste(_ sender: Any?) {
        if pasteClipboardText() { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if pasteClipboardText() { return }
        super.pasteAsPlainText(sender)
    }

    private func pasteClipboardText() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        insertText(text, replacementRange: selectedRange())
        return true
    }
}
#endif
