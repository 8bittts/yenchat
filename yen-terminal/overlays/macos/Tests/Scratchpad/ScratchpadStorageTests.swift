import Foundation
import Testing
@testable import YEN

struct ScratchpadStorageTests {
    @Test func starterTextMatchesScratchpadCopy() {
        let expected = """
This is my YENpad. There are many like it, but this one is mine.

- CTRL + C to copy
- CTRL + V to paste
- Highlight text to auto-copy (when enabled in Settings)
- GLHF!
"""

        #expect(ScratchpadStorage.starterText == expected)
    }

    @Test func loadMissingFileReturnsStarterText() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("scratchpad.txt", isDirectory: false)
        let storage = ScratchpadStorage(fileURL: url)

        #expect(try storage.load() == ScratchpadStorage.starterText)
    }

    @Test func loadExistingEmptyFileReturnsEmptyString() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        let storage = ScratchpadStorage(fileURL: url)

        try storage.save("")

        #expect(try storage.load() == "")
    }

    @Test func saveAndLoadRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        let storage = ScratchpadStorage(fileURL: url)
        let expected = "first line\nsecond line"

        try storage.save(expected)

        #expect(try storage.load() == expected)
    }

    @Test func saveOverwritesExistingContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        let storage = ScratchpadStorage(fileURL: url)

        try storage.save("old")
        try storage.save("new")

        #expect(try storage.load() == "new")
    }

    @Test func loadUnreadableExistingFileThrowsInsteadOfReturningStarterText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        try Data([0xFF, 0xFE]).write(to: url)

        let storage = ScratchpadStorage(fileURL: url)
        #expect(throws: ScratchpadStorageError.self) {
            try storage.load()
        }
    }
}
