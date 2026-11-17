import AppKit
import Testing
@testable import YEN

@MainActor
struct CopyOnSelectClipboardTests {
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("yen.copy-on-select.\(UUID().uuidString)"))
    }

    @Test func copySelectedPlainTextWritesOnlySelectedString() {
        let pasteboard = scratchPasteboard()
        let didCopy = CopyOnSelectClipboard.copySelectedPlainText(
            string: "alpha beta gamma",
            selection: NSRange(location: 6, length: 4),
            to: pasteboard
        )

        #expect(didCopy)
        #expect(pasteboard.string(forType: .string) == "beta")
    }

    @Test func copySelectedPlainTextRejectsOutOfRangeSelection() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("unchanged", forType: .string)

        let didCopy = CopyOnSelectClipboard.copySelectedPlainText(
            string: "alpha",
            selection: NSRange(location: 20, length: 4),
            to: pasteboard
        )

        #expect(!didCopy)
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }

    @Test func copySelectedPlainTextRejectsEmptySelection() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("unchanged", forType: .string)

        let didCopy = CopyOnSelectClipboard.copySelectedPlainText(
            string: "alpha",
            selection: NSRange(location: 0, length: 0),
            to: pasteboard
        )

        #expect(!didCopy)
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }

    // Drives a real NSTextView selection through the public copy hook — the path
    // the live surfaces use — rather than only the pure range helper.
    @Test func copyIfEnabledCopiesRealTextViewSelection() {
        let pasteboard = scratchPasteboard()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 6, length: 5))

        let didCopy = CopyOnSelectClipboard.copyIfEnabled(textView, enabled: true, to: pasteboard)

        #expect(didCopy)
        #expect(pasteboard.string(forType: .string) == "world")
    }

    @Test func copyIfEnabledRespectsDisabledFlag() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("unchanged", forType: .string)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        let didCopy = CopyOnSelectClipboard.copyIfEnabled(textView, enabled: false, to: pasteboard)

        #expect(!didCopy)
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }

    @Test func copyIfEnabledSkipsEmptyTextViewSelection() {
        let pasteboard = scratchPasteboard()
        pasteboard.setString("unchanged", forType: .string)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textView.string = "hello world"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        let didCopy = CopyOnSelectClipboard.copyIfEnabled(textView, enabled: true, to: pasteboard)

        #expect(!didCopy)
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }
}
