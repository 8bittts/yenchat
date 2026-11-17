#if os(macOS)
import AppKit
import Testing
@testable import YEN

/// Verifies the j/k navigation gate: the probe reports first-responder state of
/// the diff text view so `moveSelection` can skip file navigation while the diff
/// is focused, and re-enable it once focus moves away (no stuck-suppressed state).
@MainActor
struct GitDrawerDiffFocusProbeTests {
    @Test func reportsWhetherDiffTextViewHoldsFirstResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let diffTextView = NSTextView(frame: window.contentLayoutRect)
        diffTextView.isEditable = false
        diffTextView.isSelectable = true
        let otherResponder = NSTextView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(diffTextView)
        window.contentView?.addSubview(otherResponder)

        let probe = GitDrawerDiffFocusProbe()
        #expect(!probe.isDiffFirstResponder) // no text view referenced yet

        probe.textView = diffTextView
        #expect(!probe.isDiffFirstResponder) // referenced but not first responder

        #expect(window.makeFirstResponder(diffTextView))
        #expect(probe.isDiffFirstResponder) // diff focused -> j/k suppressed

        #expect(window.makeFirstResponder(otherResponder))
        #expect(!probe.isDiffFirstResponder) // focus moved away -> j/k allowed again
    }
}
#endif
