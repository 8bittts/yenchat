import Foundation
import Testing
@testable import YEN

@Suite(.serialized)
struct ThemePreviewCacheTests {
    @Test func previewCacheOnlyStoresOneEntryForRepeatedLoadsOfSamePath() throws {
        try withCleanPreviewCache {
            let path = try makeTempThemeFile(contents: """
            background = #111111
            foreground = #EEEEEE
            cursor-color = #FF5100
            """)
            defer { try? FileManager.default.removeItem(atPath: path) }

            for _ in 0..<5 {
                _ = ThemeInfo(name: "unit-repeat", path: path, bundled: false)
            }

            #expect(ThemeInfo._testPreviewCacheContains(path: path))
            #expect(ThemeInfo._testPreviewParseCount(for: path) == 1)
        }
    }

    @Test func previewCacheReparsesModifiedFileWithoutGrowingCardinality() throws {
        try withCleanPreviewCache {
            let path = try makeTempThemeFile(contents: """
            background = #101820
            foreground = #F8F9FA
            cursor-color = #FFB703
            """)
            defer { try? FileManager.default.removeItem(atPath: path) }

            _ = ThemeInfo(name: "unit-modified", path: path, bundled: false)
            #expect(ThemeInfo._testPreviewCacheContains(path: path))
            #expect(ThemeInfo._testPreviewParseCount(for: path) == 1)

            try rewriteThemeFile(
                at: path,
                contents: """
                background = #0B132B
                foreground = #F4F4F9
                cursor-color = #6FFFE9
                """,
                modificationDate: Date(timeIntervalSinceNow: 5)
            )

            _ = ThemeInfo(name: "unit-modified", path: path, bundled: false)

            #expect(ThemeInfo._testPreviewCacheContains(path: path))
            #expect(ThemeInfo._testPreviewParseCount(for: path) == 2)
        }
    }

    @Test func previewCacheGrowthTracksUniqueThemePathsOnly() throws {
        try withCleanPreviewCache {
            let paths = try [
                """
                background = #1B1B1E
                foreground = #FBFFFE
                cursor-color = #F65A83
                """,
                """
                background = #102542
                foreground = #F7FFF7
                cursor-color = #7CC6FE
                """,
                """
                background = #201A23
                foreground = #F4EDEA
                cursor-color = #FF6A3D
                """
            ].map(makeTempThemeFile(contents:))

            defer {
                for path in paths {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            for _ in 0..<4 {
                for (index, path) in paths.enumerated() {
                    _ = ThemeInfo(name: "unit-\(index)", path: path, bundled: false)
                }
            }

            for path in paths {
                #expect(ThemeInfo._testPreviewCacheContains(path: path))
                #expect(ThemeInfo._testPreviewParseCount(for: path) == 1)
            }
        }
    }

    private func withCleanPreviewCache(_ operation: () throws -> Void) rethrows {
        ThemeInfo._testResetPreviewCache()
        defer { ThemeInfo._testResetPreviewCache() }
        try operation()
    }

    private func makeTempThemeFile(contents: String) throws -> String {
        let path = "\(NSTemporaryDirectory())/theme-preview-cache-\(UUID().uuidString).yentheme"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func rewriteThemeFile(
        at path: String,
        contents: String,
        modificationDate: Date
    ) throws {
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: path)
    }
}
