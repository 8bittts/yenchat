import Foundation

/// Canonical local paths, preserving each caller's input policy.
enum LocalPathResolver {
    static func canonicalPath(
        _ rawPath: String?,
        trimWhitespace: Bool = false,
        requireAbsolute: Bool = false
    ) -> String? {
        guard let rawPath else { return nil }
        let path = trimWhitespace ? rawPath.trimmingCharacters(in: .whitespacesAndNewlines) : rawPath
        guard !path.isEmpty else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        guard !requireAbsolute || expanded.hasPrefix("/") else { return nil }
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
