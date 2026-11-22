#if os(macOS)
import Foundation

/// Builds the unified diff the merge-conflict workspace shows for one hunk
/// choice. The view colors it natively, so no external renderer runs.
enum IDEDiffPreviewBuilder {
    static func syntheticUnifiedDiff(
        path: String,
        startLine: Int,
        oldLines: [String],
        newLines: [String]
    ) -> String {
        var lines = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -\(rangeText(start: startLine, count: oldLines.count)) +\(rangeText(start: startLine, count: newLines.count)) @@",
        ]
        lines.append(contentsOf: oldLines.map { "-\($0)" })
        lines.append(contentsOf: newLines.map { "+\($0)" })
        return lines.joined(separator: "\n")
    }

    private static func rangeText(start: Int, count: Int) -> String {
        let normalizedStart = max(1, start)
        return count == 1 ? "\(normalizedStart)" : "\(normalizedStart),\(count)"
    }
}
#endif
