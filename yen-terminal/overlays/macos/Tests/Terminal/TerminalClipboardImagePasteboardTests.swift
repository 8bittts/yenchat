import AppKit
import Testing
@testable import YEN

struct TerminalClipboardImagePasteboardTests {
    @Test func rawClipboardPngMaterializesAsTemporaryImagePath() throws {
        let pasteboard = NSPasteboard(name: .init("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let rootURL = try NSPasteboard.opinionatedClipboardImageDirectoryURL()

        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(pngData, forType: .png)

        #expect(pasteboard.hasOpinionatedStringContents())

        let imagePath = try #require(pasteboard.getOpinionatedStringContents())
        #expect(imagePath.contains("com.yenchat.yen.clipboard-image-"))
        #expect(imagePath.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: imagePath))
        #expect(URL(fileURLWithPath: imagePath).deletingLastPathComponent() == rootURL)
        let attributes = try #require(
            try? FileManager.default.attributesOfItem(atPath: imagePath)
        )
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue == 0o600)
        let rootAttributes = try #require(
            try? FileManager.default.attributesOfItem(atPath: rootURL.path)
        )
        let rootPermissions = try #require(rootAttributes[.posixPermissions] as? NSNumber)
        #expect(rootPermissions.intValue == 0o700)

        try? FileManager.default.removeItem(atPath: imagePath)
    }

    @Test func opinionatedPasteboardContentsStillPreferExistingStrings() throws {
        let pasteboard = NSPasteboard(name: .init("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("hello world", forType: .string)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()
        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(pngData, forType: .png)

        #expect(pasteboard.hasOpinionatedStringContents())
        #expect(pasteboard.getOpinionatedStringContents() == "hello world")
    }

    @Test func staleOpinionatedClipboardImagesArePrunedWhenMaterializingNewPath() throws {
        let fileManager = FileManager.default
        let rootURL = try NSPasteboard.opinionatedClipboardImageDirectoryURL()
        let staleURL = rootURL.appendingPathComponent("com.yenchat.yen.clipboard-image-stale.png")
        try Data("x".utf8).write(to: staleURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staleURL.path)
        let staleDate = Date(timeIntervalSinceNow: -(60 * 60 * 25))
        try fileManager.setAttributes(
            [.modificationDate: staleDate, .creationDate: staleDate],
            ofItemAtPath: staleURL.path
        )

        let pasteboard = NSPasteboard(name: .init("test-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let image = NSImage(size: NSSize(width: 6, height: 6))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 6, height: 6)).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(pngData, forType: .png)

        let imagePath = try #require(pasteboard.getOpinionatedStringContents())
        #expect(FileManager.default.fileExists(atPath: imagePath))
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))

        try? fileManager.removeItem(atPath: imagePath)
    }

    @Test func missingFileURLPayloadFallsBackToFreshImagePath() throws {
        let pasteboard = NSPasteboard(name: .init("test-\(UUID().uuidString)"))
        pasteboard.clearContents()

        let missingPath = URL(
            fileURLWithPath: "/tmp/com.yenchat.yen.clipboard-images-missing-\(UUID().uuidString).png"
        )
        let item = NSPasteboardItem()
        item.setPropertyList(missingPath.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([item])

        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(pngData, forType: .png)

        let contents = try #require(pasteboard.getOpinionatedStringContents())
        #expect(!contents.contains("missing-"))
        #expect(contents.contains("com.yenchat.yen.clipboard-image-"))
        #expect(FileManager.default.fileExists(atPath: contents))

        try? FileManager.default.removeItem(atPath: contents)
    }
}
