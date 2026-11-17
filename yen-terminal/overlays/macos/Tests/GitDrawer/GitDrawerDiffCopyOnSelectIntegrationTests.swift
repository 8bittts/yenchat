#if os(macOS)
import AppKit
import Testing
@testable import YEN

/// Exercises the PRODUCTION copy-on-select path end to end: a real `NSTextView`
/// wired to the real `GitDrawerDiffTextView.Coordinator` delegate, with a
/// selection change driving `textViewDidChangeSelection` ->
/// `CopyOnSelectClipboard` -> the system pasteboard. The pure-helper unit tests
/// bypass this wiring; this is the integration the runtime depends on.
/// (The Scratchpad coordinator is private but runs the byte-identical delegate
/// body, so this covers the shared mechanism for both surfaces.)
@MainActor
struct GitDrawerDiffCopyOnSelectIntegrationTests {
    private func makeHostedTextView(_ string: String) -> (NSWindow, NSTextView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: window.contentLayoutRect)
        textView.string = string
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        return (window, textView)
    }

    @Test func selectionChangeViaDelegateCopiesToClipboard() {
        let prior = SettingsController.shared.copyOnSelect
        SettingsController.shared.copyOnSelect = true
        defer { SettingsController.shared.copyOnSelect = prior }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("sentinel-before", forType: .string)

        let (window, textView) = makeHostedTextView("@@ -1 +1 @@\n-old line\n+new line")
        let coordinator = GitDrawerDiffTextView.Coordinator()
        textView.delegate = coordinator

        // What a finished drag-select produces: NSTextView settles the selection,
        // which fires textViewDidChangeSelection on the delegate.
        let range = (textView.string as NSString).range(of: "old line")
        textView.setSelectedRange(range)

        #expect(pasteboard.string(forType: .string) == "old line")
        window.orderOut(nil)
    }

    @Test func emptySelectionViaDelegateDoesNotClobberClipboard() {
        let prior = SettingsController.shared.copyOnSelect
        SettingsController.shared.copyOnSelect = true
        defer { SettingsController.shared.copyOnSelect = prior }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("keep-me", forType: .string)

        let (window, textView) = makeHostedTextView("hello world")
        let coordinator = GitDrawerDiffTextView.Coordinator()
        textView.delegate = coordinator

        // A plain click collapses to a caret (empty selection) -> must not write.
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        #expect(pasteboard.string(forType: .string) == "keep-me")
        window.orderOut(nil)
    }
}
#endif
