#if os(macOS)
import XCTest

final class OverlayTokenLintTests: XCTestCase {
    /// Files where hex string literals are intentional *data*, not hardcoded UI
    /// colors. Gradient presets store their seed colors as hex strings that are
    /// parsed once via `Color(hex:)`; the brand color file documents its
    /// canonical hex in a doc comment. These are allowed; everything else must
    /// route through design tokens.
    private static let allowedHexDataFiles: Set<String> = [
        "Features/Settings/SettingsPreferenceTypes.swift",
        "Helpers/YENBrandColor.swift",
    ]

    /// Resolve the overlay `Sources` directory relative to THIS test file rather
    /// than the process CWD. The Tests and Sources folders are siblings both in
    /// the overlay source tree (`overlays/macos/{Tests,Sources}`) and in the
    /// applied build tree (`ghostty/macos/{Tests,Sources}`), so deriving the
    /// path from `#filePath` makes the scan run under xcodebuild — where CWD is
    /// the DerivedData sandbox, not the repo root — instead of silently skipping.
    private func overlaySourcesURL(file: StaticString = #filePath) -> URL {
        if let root = ProcessInfo.processInfo.environment["YEN_NATIVE_TEST_SOURCE_ROOT"] {
            return URL(fileURLWithPath: root).appendingPathComponent("yen-terminal/ghostty/macos/Sources", isDirectory: true)
        }
        return URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // .../Tests/OverlayTokenLintTests.swift -> .../Tests
            .deletingLastPathComponent() // .../Tests -> .../macos
            .appendingPathComponent("Sources", isDirectory: true)
    }

    /// Fails if a 6-digit hex color literal (e.g. #FFAA00) is hardcoded in
    /// overlay Sources outside the allowlisted data files, and never inside a
    /// comment. New hardcoded colors must use a color token instead of raw hex.
    func test_no_hardcoded_hex_colors_in_overlays() throws {
        let fileManager = FileManager.default
        let sourcesURL = overlaySourcesURL()
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourcesURL.path, isDirectory: &isDir), isDir.boolValue else {
            XCTFail("Overlay Sources not present at: \(sourcesURL.path)")
            return
        }

        let pattern = "#[0-9A-Fa-f]{6}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            XCTFail("Failed to compile hex-color regex")
            return
        }

        var offenders: [String] = []
        let basePath = sourcesURL.path
        let enumerator = try XCTUnwrap(fileManager.enumerator(atPath: basePath))
        var scanned = 0
        while let casePath = enumerator.nextObject() as? String {
            // Only scan Swift source files.
            guard casePath.hasSuffix(".swift") else { continue }
            if Self.allowedHexDataFiles.contains(casePath) { continue }
            let full = basePath + "/" + casePath
            let contents = try String(contentsOfFile: full, encoding: .utf8)
            scanned += 1

            for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(rawLine)
                // Skip comment lines — documenting a hex value is not a hardcoded color.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    offenders.append("\(casePath):\(index + 1)")
                }
            }
        }

        XCTAssertGreaterThan(scanned, 0, "No overlay Swift sources were scanned")
        if !offenders.isEmpty {
            let list = offenders.joined(separator: "\n")
            XCTFail("Found hard-coded hex color literals in overlay source files:\n\(list)")
        }
    }
}
#endif // os(macOS)
