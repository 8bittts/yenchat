#if os(macOS)
import Foundation
import SwiftUI

struct ThemeInfo: Identifiable, Hashable, @unchecked Sendable {
    private struct CachedPreviewColors {
        let modificationDate: Date?
        let fileSize: UInt64?
        let backgroundColor: Color
        let foregroundColor: Color
        let cursorColor: Color
    }

    private static let previewCacheLock = NSLock()
    private static var previewCache: [String: CachedPreviewColors] = [:]
#if DEBUG
    private static var previewParseCount = 0
    private static var previewParseCounts: [String: Int] = [:]
#endif

    let id = UUID()
    let name: String
    let path: String
    let bundled: Bool
    let tags: Set<String>
    /// The value written to the `theme` config key.
    ///
    /// The engine resolves a named theme by exact file name, so a user theme
    /// saved as `Name.yen` resolves only as `Name.yen`. `name` drops that
    /// suffix for display and must not be written to config.
    let configReference: String

    // Parsed colors for preview
    let backgroundColor: Color
    let foregroundColor: Color
    let cursorColor: Color

    init(
        name: String,
        path: String,
        bundled: Bool,
        tags: Set<String> = [],
        configReference: String? = nil
    ) {
        self.name = name
        self.path = path
        self.bundled = bundled
        self.tags = tags
        self.configReference = configReference ?? name

        let cachedPreviewColors = Self.cachedPreviewColors(for: path)
        self.backgroundColor = cachedPreviewColors.backgroundColor
        self.foregroundColor = cachedPreviewColors.foregroundColor
        self.cursorColor = cachedPreviewColors.cursorColor
    }

    var displayName: String {
        name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    // Hashable conformance (exclude colors, just use name)
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: ThemeInfo, rhs: ThemeInfo) -> Bool {
        lhs.name == rhs.name
    }

    private static func cachedPreviewColors(for path: String) -> CachedPreviewColors {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let modificationDate = attributes[.modificationDate] as? Date
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value

        previewCacheLock.lock()
        if let cached = previewCache[path],
           cached.modificationDate == modificationDate,
           cached.fileSize == fileSize {
            previewCacheLock.unlock()
            return cached
        }
        previewCacheLock.unlock()

        let parsed = parsePreviewColors(
            at: path,
            modificationDate: modificationDate,
            fileSize: fileSize
        )

        previewCacheLock.lock()
        previewCache[path] = parsed
#if DEBUG
        previewParseCount += 1
        previewParseCounts[path, default: 0] += 1
#endif
        previewCacheLock.unlock()
        return parsed
    }

    private static func parsePreviewColors(
        at path: String,
        modificationDate: Date?,
        fileSize: UInt64?
    ) -> CachedPreviewColors {
        var backgroundColor = Color(red: 0.15, green: 0.17, blue: 0.21)
        var foregroundColor = Color.white
        var cursorColor = Color.yenBrand

        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)

                switch key {
                case "background":
                    if let color = Color(hex: value) { backgroundColor = color }
                case "foreground":
                    if let color = Color(hex: value) { foregroundColor = color }
                case "cursor-color":
                    if let color = Color(hex: value) { cursorColor = color }
                default:
                    break
                }
            }
        }

        return CachedPreviewColors(
            modificationDate: modificationDate,
            fileSize: fileSize,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cursorColor: cursorColor
        )
    }

#if DEBUG
    static func _testResetPreviewCache() {
        previewCacheLock.lock()
        previewCache.removeAll()
        previewParseCount = 0
        previewParseCounts.removeAll()
        previewCacheLock.unlock()
    }

    static var _testPreviewCacheEntryCount: Int {
        previewCacheLock.lock()
        let count = previewCache.count
        previewCacheLock.unlock()
        return count
    }

    static func _testPreviewParseCount(for path: String) -> Int {
        previewCacheLock.lock()
        let count = previewParseCounts[path, default: 0]
        previewCacheLock.unlock()
        return count
    }

    static func _testPreviewCacheContains(path: String) -> Bool {
        previewCacheLock.lock()
        let containsPath = previewCache[path] != nil
        previewCacheLock.unlock()
        return containsPath
    }

    static var _testPreviewParseCount: Int {
        previewCacheLock.lock()
        let count = previewParseCount
        previewCacheLock.unlock()
        return count
    }
#endif
}
#endif
