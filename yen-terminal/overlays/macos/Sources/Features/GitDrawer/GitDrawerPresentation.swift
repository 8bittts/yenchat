#if os(macOS)
import AppKit

enum GitDrawerSemanticColors {
    static func badgeTextColor(for badge: String, differentiateWithoutColor: Bool = false) -> NSColor {
        .labelColor
    }

    static var diffTextColor: NSColor {
        diffTextColor(for: .context)
    }

    // Shared dynamic role colors, built once. diffTextColor(for:) is called per diff
    // line (diffs up to 256 KB) on every re-render, so returning cached instances
    // avoids reallocating three NSColors per line for the five fixed roles.
    private static let metadataDiffColor = adaptiveColor(light: rgb(0.36, 0.35, 0.40), dark: rgb(0.65, 0.68, 0.78))
    private static let hunkDiffColor = adaptiveColor(light: rgb(0.03, 0.34, 0.64), dark: rgb(0.38, 0.68, 0.93))
    private static let additionDiffColor = adaptiveColor(light: rgb(0.04, 0.37, 0.18), dark: rgb(0.60, 0.76, 0.47))
    private static let deletionDiffColor = adaptiveColor(light: rgb(0.63, 0.10, 0.15), dark: rgb(0.88, 0.42, 0.46))
    private static let truncationDiffColor = adaptiveColor(light: rgb(0.48, 0.28, 0.00), dark: rgb(0.90, 0.75, 0.42))

    static func diffTextColor(for role: GitDrawerDiffLineRole) -> NSColor {
        switch role {
        case .metadata:
            return metadataDiffColor
        case .hunk:
            return hunkDiffColor
        case .addition:
            return additionDiffColor
        case .deletion:
            return deletionDiffColor
        case .truncation:
            return truncationDiffColor
        case .context:
            return .labelColor
        }
    }

    static var diffBackgroundColor: NSColor {
        .textBackgroundColor
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

enum GitDrawerDiffLineRole: Equatable, Sendable {
    case metadata
    case hunk
    case addition
    case deletion
    case truncation
    case context
}

enum GitDrawerDiffLineClassifier {
    /// Stateful unified-diff classification. Header markers such as `+++ b/file`
    /// and `--- a/file` are metadata before a hunk, but the same prefixes inside
    /// a hunk can be real added/deleted source (for example an added `++ item`).
    struct Stream: Sendable {
        private var isInsideHunk = false

        mutating func role(for line: String) -> GitDrawerDiffLineRole {
            if line.hasPrefix("diff --git") {
                isInsideHunk = false
                return .metadata
            }
            if line.hasPrefix("@@") {
                isInsideHunk = true
                return .hunk
            }
            if isInsideHunk {
                if line.hasPrefix("+") {
                    return .addition
                }
                if line.hasPrefix("-") {
                    return .deletion
                }
                if line.hasPrefix("\\ No newline") {
                    return .metadata
                }
                return .context
            }
            return GitDrawerDiffLineClassifier.role(for: line)
        }
    }

    static func role(for line: String) -> GitDrawerDiffLineRole {
        if line == "[diff truncated]" {
            return .truncation
        }
        if line.hasPrefix("@@") {
            return .hunk
        }
        if line.hasPrefix("+"), !line.hasPrefix("+++ ") {
            return .addition
        }
        if line.hasPrefix("-"), !line.hasPrefix("--- ") {
            return .deletion
        }
        if line.hasPrefix("diff --git")
            || line.hasPrefix("index ")
            || line.hasPrefix("new file mode ")
            || line.hasPrefix("deleted file mode ")
            || line.hasPrefix("old mode ")
            || line.hasPrefix("new mode ")
            || line.hasPrefix("similarity index ")
            || line.hasPrefix("dissimilarity index ")
            || line.hasPrefix("rename from ")
            || line.hasPrefix("rename to ")
            || line.hasPrefix("copy from ")
            || line.hasPrefix("copy to ")
            || line.hasPrefix("Binary files ")
            || line == "GIT binary patch"
            || line.hasPrefix("literal ")
            || line.hasPrefix("delta ")
            || line.hasPrefix("--- ")
            || line.hasPrefix("+++ ")
            || line.hasPrefix("\\ No newline") {
            return .metadata
        }
        return .context
    }
}

#endif
