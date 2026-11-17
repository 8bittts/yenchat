import AppKit
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct BackgroundImageStoreTests {
    @Test func importCopiesImageIntoManagedDirectoryWithOwnerOnlyPermissions() throws {
        let fileManager = FileManager.default
        let tempRoot = makeTemporaryRoot()
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let appSupportRoot = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let source = tempRoot.appendingPathComponent("background-source.png", isDirectory: false)
        try writeTestImage(to: source)

        let imported = try TerminalBackgroundImageStore.importImage(
            from: source,
            fileManager: fileManager,
            appSupportRootOverride: appSupportRoot
        )

        #expect(
            TerminalBackgroundImageStore.isManagedBackgroundImagePath(
                imported.path,
                fileManager: fileManager,
                appSupportRootOverride: appSupportRoot
            )
        )
        #expect(fileManager.fileExists(atPath: imported.path))

        let attrs = try fileManager.attributesOfItem(atPath: imported.path)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
    }

    @Test func importRejectsSymlinkSources() throws {
        let fileManager = FileManager.default
        let tempRoot = makeTemporaryRoot()
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let appSupportRoot = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let source = tempRoot.appendingPathComponent("background-source.png", isDirectory: false)
        try writeTestImage(to: source)

        let symlink = tempRoot.appendingPathComponent("background-link.png", isDirectory: false)
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: source)

        do {
            _ = try TerminalBackgroundImageStore.importImage(
                from: symlink,
                fileManager: fileManager,
                appSupportRootOverride: appSupportRoot
            )
            #expect(Bool(false))
        } catch BackgroundImageImportError.symlinkNotAllowed {
            // Expected.
        } catch {
            #expect(Bool(false))
        }
    }

    @Test func importRejectsUnsupportedButDecodableImageFormats() throws {
        let fileManager = FileManager.default
        let tempRoot = makeTemporaryRoot()
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let appSupportRoot = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let source = tempRoot.appendingPathComponent("background-source.tiff", isDirectory: false)
        try writeTestImage(to: source, format: .tiff)

        do {
            _ = try TerminalBackgroundImageStore.importImage(
                from: source,
                fileManager: fileManager,
                appSupportRootOverride: appSupportRoot
            )
            #expect(Bool(false))
        } catch BackgroundImageImportError.unsupportedFileType {
            // Expected.
        } catch {
            #expect(Bool(false))
        }
    }

    @Test func cleanupRetainsExplicitManagedImageAndLeavesOtherFilesAlone() throws {
        let fileManager = FileManager.default
        let tempRoot = makeTemporaryRoot()
        defer { try? fileManager.removeItem(at: tempRoot) }

        let appSupportRoot = tempRoot.appendingPathComponent("app-support", isDirectory: true)
        let backgroundsDirectory = TerminalBackgroundImageStore.backgroundsDirectoryURL(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRoot
        )
        try fileManager.createDirectory(
            at: backgroundsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let retained = backgroundsDirectory.appendingPathComponent(
            "terminal-background-retained.png",
            isDirectory: false
        )
        let removed = backgroundsDirectory.appendingPathComponent(
            "terminal-background-removed.png",
            isDirectory: false
        )
        let unrelated = backgroundsDirectory.appendingPathComponent("notes.txt", isDirectory: false)
        try Data("keep".utf8).write(to: retained)
        try Data("remove".utf8).write(to: removed)
        try Data("other".utf8).write(to: unrelated)

        try TerminalBackgroundImageStore.cleanupManagedImages(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRoot,
            retaining: [retained.path]
        )

        #expect(fileManager.fileExists(atPath: retained.path))
        #expect(!fileManager.fileExists(atPath: removed.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    private func makeTemporaryRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-background-test-\(UUID().uuidString)", isDirectory: true)
    }

    private func writeTestImage(to url: URL, format: NSBitmapImageRep.FileType = .png) throws {
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: format, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try imageData.write(to: url, options: .atomic)
    }
}
