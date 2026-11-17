#if os(macOS)
import Foundation

enum ScratchpadStorageError: Error {
    case invalidUTF8
}

struct ScratchpadStorage: Sendable {
    static let directoryName = "com.yenchat.yen"
    static let fileName = "scratchpad.txt"
    static let starterText = """
This is my YENpad. There are many like it, but this one is mine.

- CTRL + C to copy
- CTRL + V to paste
- Highlight text to auto-copy (when enabled in Settings)
- GLHF!
"""

    let fileURL: URL

    static func defaultStorage() -> ScratchpadStorage {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
        return ScratchpadStorage(fileURL: directoryURL.appendingPathComponent(fileName, isDirectory: false))
    }

    func load() throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Self.starterText }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ScratchpadStorageError.invalidUTF8
        }
        return text
    }

    func save(_ text: String) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        try Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}
#endif
