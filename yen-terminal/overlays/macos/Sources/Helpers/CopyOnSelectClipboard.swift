#if os(macOS)
import AppKit

/// Shared "Copy on Select" clipboard helper for native `NSTextView` surfaces
/// (Git drawer, PR Review, Merge Conflict, and the Scratchpad editor).
///
/// Copy-on-select is driven from the text view's own selection delegate
/// (`NSTextViewDelegate.textViewDidChangeSelection`) rather than a global
/// `NSEvent` mouse monitor. A monitor is the wrong mechanism here: a SwiftUI
/// `Text(.textSelection(.enabled))` never vends an `NSTextView` first responder
/// to probe, and an `NSTextView`'s own selection tracking can hide the
/// selection-terminating mouse-up from a local monitor. Hooking the selection
/// change directly is immune to both and fires whenever the selection settles.
enum CopyOnSelectClipboard {
    /// Writes the current non-empty selection of `textView` to `pasteboard`
    /// when `enabled`. Returns `true` when text was copied.
    ///
    /// Callers pass `enabled` (typically `SettingsController.shared.copyOnSelect`).
    @discardableResult
    @MainActor
    static func copyIfEnabled(
        _ textView: NSTextView,
        enabled: Bool,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard enabled else { return false }
        return copySelectedPlainText(from: textView, to: pasteboard)
    }

    /// Writes the substring of `string` covered by `selection` to `pasteboard`.
    /// Returns `false` for a not-found, out-of-range, or empty selection
    /// (so a plain click that collapses the selection never clobbers the clipboard).
    @discardableResult
    nonisolated static func copySelectedPlainText(
        string: String,
        selection: NSRange,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard selection.location != NSNotFound,
              selection.length > 0,
              let range = Range(selection, in: string)
        else {
            return false
        }

        let selectedText = String(string[range])
        guard !selectedText.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(selectedText, forType: .string)
    }

    @discardableResult
    @MainActor
    static func copySelectedPlainText(
        from textView: NSTextView,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        copySelectedPlainText(
            string: textView.string,
            selection: textView.selectedRange(),
            to: pasteboard
        )
    }
}
#endif
