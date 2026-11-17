import AppKit
import Testing
@testable import YEN

struct NSPasteboardTypeExtensionTests {
    @Test func textPlainMimeType() {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "text/plain")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .string)
    }

    @Test func textHtmlMimeType() {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "text/html")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .html)
    }

    @Test func imagePngMimeType() {
        let pasteboardType = NSPasteboard.PasteboardType(mimeType: "image/png")
        #expect(pasteboardType != nil)
        #expect(pasteboardType == .png)
    }
}
