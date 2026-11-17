#if os(macOS)
import AppKit
import Foundation

struct GitDrawerPresentationState: Equatable, Sendable {
    let header: Header
    let groups: [Group]
    let stashTotalCount: Int
    let stashEntries: [StashEntry]
    let isStashListTruncated: Bool
    let emptyMessage: String?
    let notice: GitDrawerNotice?
    let selectedDiffText: String
    let diffAccessibilityLabel: String
    let isDiffTruncated: Bool
    let repoRoot: String
    let selectedPath: String?
    let canOpenSelectedPath: Bool

    init(snapshot: GitDrawerSnapshot) {
        header = Header(snapshot: snapshot)
        repoRoot = snapshot.repoRoot
        selectedPath = snapshot.selectedFile
        groups = [
            Group(title: "Staged", changes: snapshot.staged),
            Group(title: "Unstaged", changes: snapshot.unstaged),
            Group(title: "Untracked", changes: snapshot.untracked),
            Group(title: "Conflicted", changes: snapshot.conflicted),
        ].filter { !$0.rows.isEmpty }
        stashTotalCount = snapshot.stashCount
        stashEntries = snapshot.stashEntries.map(StashEntry.init(entry:))
        isStashListTruncated = snapshot.isStashListTruncated
        emptyMessage = snapshot.isClean && stashEntries.isEmpty ? "Working tree clean" : nil
        notice = nil
        isDiffTruncated = snapshot.isDiffTruncated
        if snapshot.isDiffTruncated, let diff = snapshot.selectedDiff, !diff.isEmpty {
            selectedDiffText = diff + "\n\n[diff truncated]"
        } else {
            selectedDiffText = snapshot.selectedDiff ?? ""
        }
        if let selectedFile = snapshot.selectedFile, !selectedFile.isEmpty {
            diffAccessibilityLabel = "Unified diff for \(selectedFile)"
        } else {
            diffAccessibilityLabel = "Unified diff"
        }
        canOpenSelectedPath = Self.canOpenSelectedPath(snapshot)
    }

    init(unavailableMessage: String) {
        self.init(unavailableMessage: unavailableMessage, notice: .plain(message: unavailableMessage))
    }

    init(unavailable: GitDrawerUnavailableReason) {
        let notice = GitDrawerFailureNoticeCatalog.notice(for: unavailable)
        self.init(unavailableMessage: notice.message, notice: notice)
    }

    private init(unavailableMessage: String, notice: GitDrawerNotice?) {
        header = Header(
            title: "No Git repository",
            subtitle: "Focused split",
            summary: "not a git worktree"
        )
        groups = []
        stashTotalCount = 0
        stashEntries = []
        isStashListTruncated = false
        emptyMessage = unavailableMessage
        self.notice = notice
        selectedDiffText = ""
        diffAccessibilityLabel = "Unified diff"
        isDiffTruncated = false
        repoRoot = ""
        selectedPath = nil
        canOpenSelectedPath = false
    }

    struct Header: Equatable, Sendable {
        let title: String
        let subtitle: String
        let summary: String

        init(title: String, subtitle: String, summary: String) {
            self.title = title
            self.subtitle = subtitle
            self.summary = summary
        }

        init(snapshot: GitDrawerSnapshot) {
            title = Self.displayTitle(
                contextName: Self.pathDisplayName(
                    snapshot.workingDirectory,
                    fallback: snapshot.repoRoot
                ),
                branch: snapshot.branch
            )
            subtitle = snapshot.upstream ?? "No upstream"

            var parts: [String]
            if snapshot.isClean {
                parts = ["working tree clean"]
            } else {
                parts = [
                    "\(snapshot.totalChangedFileCount) \(snapshot.totalChangedFileCount == 1 ? "file" : "files")",
                    "+\(snapshot.totalAdditions)",
                    "-\(snapshot.totalDeletions)",
                ]
            }
            if snapshot.ahead > 0 {
                parts.append("↑\(snapshot.ahead)")
            }
            if snapshot.behind > 0 {
                parts.append("↓\(snapshot.behind)")
            }
            if snapshot.stashCount > 0 {
                parts.append("stash \(snapshot.stashCount)")
            }
            if snapshot.isFileListTruncated {
                parts.append("file list truncated")
            }
            summary = parts.joined(separator: "  ")
        }

        private static func displayTitle(contextName: String, branch: String) -> String {
            if contextName.isEmpty {
                return branch
            }
            if branch.isEmpty {
                return contextName
            }
            return "\(contextName) // \(branch)"
        }

        private static func pathDisplayName(_ path: String, fallback: String) -> String {
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate: String
            if trimmedPath.isEmpty {
                candidate = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                candidate = trimmedPath
            }
            guard !candidate.isEmpty else { return "" }

            let name = URL(fileURLWithPath: candidate).lastPathComponent
            return name.isEmpty ? candidate : name
        }
    }

    struct Group: Equatable, Sendable {
        let title: String
        let rows: [Row]

        var count: Int {
            rows.count
        }

        init(title: String, changes: [GitDrawerFileChange]) {
            self.title = title
            rows = changes.map(Row.init(change:))
        }
    }

    struct Row: Equatable, Sendable, Identifiable {
        let id: String
        let repoRelativePath: String
        let status: GitDrawerFileStatus
        let badge: String
        let stageGlyph: String
        let path: String
        let numstat: String
        let accessibilityLabel: String

        init(change: GitDrawerFileChange) {
            id = "\(change.stage)-\(change.path)-\(change.oldPath ?? "")"
            repoRelativePath = change.path
            status = change.status
            badge = change.status.rawValue
            stageGlyph = Self.stageGlyph(change.stage)
            path = change.displayPath
            numstat = Self.numstat(
                additions: change.additions,
                deletions: change.deletions,
                placeholder: change.statPlaceholder
            )
            accessibilityLabel = Self.accessibilityLabel(for: change)
        }

        private static func numstat(additions: Int?, deletions: Int?, placeholder: String?) -> String {
            if let placeholder {
                return placeholder
            }
            guard let additions, let deletions else { return "—" }
            return "+\(additions) -\(deletions)"
        }

        private static func stageGlyph(_ stage: GitDrawerChangeStage) -> String {
            switch stage {
            case .staged:
                return "S"
            case .unstaged:
                return "W"
            case .untracked:
                return "?"
            case .conflicted:
                return "!"
            }
        }

        private static func accessibilityLabel(for change: GitDrawerFileChange) -> String {
            var parts = [
                statusLabel(change.status),
                stageLabel(change.stage),
                pathLabel(change),
            ]
            if let additions = change.additions, let deletions = change.deletions {
                parts.append("plus \(additions) minus \(deletions)")
            } else if let statPlaceholder = change.statPlaceholder {
                parts.append(statPlaceholder)
            }
            return parts.joined(separator: ", ")
        }

        private static func statusLabel(_ status: GitDrawerFileStatus) -> String {
            switch status {
            case .modified:
                return "Modified"
            case .added:
                return "Added"
            case .deleted:
                return "Deleted"
            case .renamed:
                return "Renamed"
            case .copied:
                return "Copied"
            case .typeChanged:
                return "Type changed"
            case .conflicted:
                return "Conflicted"
            case .untracked:
                return "Untracked"
            }
        }

        private static func stageLabel(_ stage: GitDrawerChangeStage) -> String {
            switch stage {
            case .staged:
                return "staged"
            case .unstaged:
                return "unstaged"
            case .untracked:
                return "untracked"
            case .conflicted:
                return "conflicted"
            }
        }

        private static func pathLabel(_ change: GitDrawerFileChange) -> String {
            if let oldPath = change.oldPath, oldPath != change.path {
                return "\(oldPath) to \(change.path)"
            }
            return change.path
        }
    }

    struct StashEntry: Equatable, Sendable, Identifiable {
        let id: String
        let ref: String
        let message: String
        let files: [StashFile]
        let accessibilityLabel: String

        init(entry: GitDrawerStashEntry) {
            id = entry.id
            ref = entry.ref
            message = entry.message
            files = entry.files.map(StashFile.init(file:))
            accessibilityLabel = "\(entry.ref), \(entry.message), \(entry.files.count) \(entry.files.count == 1 ? "file" : "files")"
        }
    }

    struct StashFile: Equatable, Sendable, Identifiable {
        let id: String
        let repoRelativePath: String
        let badge: String
        let path: String
        let accessibilityLabel: String

        init(file: GitDrawerStashFile) {
            id = file.id
            repoRelativePath = file.path
            badge = file.status.rawValue
            path = file.displayPath
            accessibilityLabel = "\(Self.statusLabel(file.status)), stash file, \(path)"
        }

        private static func statusLabel(_ status: GitDrawerFileStatus) -> String {
            switch status {
            case .modified:
                return "Modified"
            case .added:
                return "Added"
            case .deleted:
                return "Deleted"
            case .renamed:
                return "Renamed"
            case .copied:
                return "Copied"
            case .typeChanged:
                return "Type changed"
            case .conflicted:
                return "Conflicted"
            case .untracked:
                return "Untracked"
            }
        }
    }

    private static func canOpenSelectedPath(_ snapshot: GitDrawerSnapshot) -> Bool {
        guard let selectedFile = snapshot.selectedFile, !selectedFile.isEmpty else { return false }
        return !(snapshot.staged + snapshot.unstaged + snapshot.conflicted)
            .contains { $0.path == selectedFile && $0.status == .deleted }
    }
}

enum GitDrawerNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

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

enum GitDrawerNavigationPolicy {
    static func orderedPaths(
        in groups: [GitDrawerPresentationState.Group],
        filter: GitDrawerFilter = .all
    ) -> [String] {
        GitDrawerFilter.filteredGroups(groups, by: filter)
            .flatMap(\.rows)
            .map(\.repoRelativePath)
    }

    static func destinationPath(
        currentPath: String?,
        groups: [GitDrawerPresentationState.Group],
        filter: GitDrawerFilter = .all,
        direction: GitDrawerNavigationDirection
    ) -> String? {
        let paths = orderedPaths(in: groups, filter: filter)
        guard !paths.isEmpty else { return nil }
        guard let currentPath,
              let currentIndex = paths.firstIndex(of: currentPath)
        else {
            return direction == .previous ? paths.last : paths.first
        }

        switch direction {
        case .previous:
            return paths[max(paths.startIndex, currentIndex - 1)]
        case .next:
            return paths[min(paths.index(before: paths.endIndex), currentIndex + 1)]
        }
    }
}

enum GitDrawerFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all = "All"
    case staged = "Staged"
    case unstaged = "Unstaged"
    case untracked = "Untracked"
    case conflicted = "Conflicts"
    case stashes = "Stash"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .untracked:
            return "New"
        default:
            return rawValue
        }
    }

    var headerIconSystemName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .staged:
            return "checkmark.circle"
        case .unstaged:
            return "pencil"
        case .untracked:
            return "plus"
        case .conflicted:
            return "exclamationmark.triangle"
        case .stashes:
            return "archivebox"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .untracked:
            return "New changes"
        case .conflicted:
            return "Conflicted changes"
        case .stashes:
            return "Stashes"
        default:
            return "\(rawValue) changes"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .stashes:
            return "stash"
        default:
            return rawValue.lowercased()
        }
    }

    var showsChangeGroups: Bool {
        self != .stashes
    }

    var showsStashes: Bool {
        self == .all || self == .stashes
    }

    func includes(groupTitle: String) -> Bool {
        switch self {
        case .all:
            return true
        case .staged:
            return groupTitle == "Staged"
        case .unstaged:
            return groupTitle == "Unstaged"
        case .untracked:
            return groupTitle == "Untracked"
        case .conflicted:
            return groupTitle == "Conflicted"
        case .stashes:
            return false
        }
    }

    static func filteredGroups(
        _ groups: [GitDrawerPresentationState.Group],
        by filter: GitDrawerFilter
    ) -> [GitDrawerPresentationState.Group] {
        groups.filter { filter.includes(groupTitle: $0.title) }
    }
}

enum GitDrawerUnavailableReason: Equatable, Sendable {
    case notGitWorktree
    case bareRepository
    case missingGit
    case timedOut
    case commandFailed
    case mutationRejected
    case unknown
}

enum GitDrawerNoticeSeverity: Equatable, Sendable {
    case info
    case warning
    case error
}

struct GitDrawerNotice: Equatable, Sendable {
    let severity: GitDrawerNoticeSeverity
    let title: String
    let message: String
    let actionText: String?

    static func plain(message: String) -> GitDrawerNotice {
        GitDrawerNotice(
            severity: .info,
            title: "Git drawer unavailable",
            message: message,
            actionText: nil
        )
    }
}

enum GitDrawerFailureNoticeCatalog {
    static func notice(for reason: GitDrawerUnavailableReason) -> GitDrawerNotice {
        switch reason {
        case .notGitWorktree:
            return GitDrawerNotice(
                severity: .info,
                title: "No Git repository here",
                message: "The focused split is not inside a Git working tree.",
                actionText: "Open a split inside a Git checkout, or run `git init` in this directory."
            )
        case .bareRepository:
            return GitDrawerNotice(
                severity: .warning,
                title: "Bare repositories are not supported",
                message: "The Git drawer needs a working tree so it can list files and render diffs.",
                actionText: "Open a working tree checkout for this repository before using the drawer."
            )
        case .missingGit:
            return GitDrawerNotice(
                severity: .error,
                title: "Git is not available",
                message: "YEN could not find an executable Git binary at `/usr/bin/git`.",
                actionText: "Install Git or restore `/usr/bin/git`, then refresh the drawer."
            )
        case .timedOut:
            return GitDrawerNotice(
                severity: .warning,
                title: "Git is taking too long",
                message: "The read-only Git command timed out before YEN could build the drawer.",
                actionText: "Refresh again, or open the repo in bundled lazygit to inspect the slow operation."
            )
        case .commandFailed:
            return GitDrawerNotice(
                severity: .error,
                title: "Unable to read this worktree",
                message: "YEN could not collect status or diff data for the focused repository.",
                actionText: "Check repository permissions, hooks, and Git config, then refresh."
            )
        case .mutationRejected:
            return GitDrawerNotice(
                severity: .warning,
                title: "Read-only drawer blocked a mutating command",
                message: "The Git drawer only runs inspection commands and refuses writes.",
                actionText: "Use bundled lazygit or the terminal for intentional write actions."
            )
        case .unknown:
            return GitDrawerNotice(
                severity: .error,
                title: "Unable to open Git drawer",
                message: "YEN could not build the Git view for the focused split.",
                actionText: "Refresh after checking the split directory and repository state."
            )
        }
    }
}

enum GitDrawerHeightPolicy {
    static let minimumHeight: Double = 220
    static let preferredWindowRatio: Double = 0.38
    static let maximumWindowRatio: Double = 0.70

    static func defaultHeight(for windowHeight: Double) -> Double {
        clampedHeight(windowHeight * preferredWindowRatio, windowHeight: windowHeight)
    }

    static func clampedHeight(_ proposedHeight: Double, windowHeight: Double) -> Double {
        let maxHeight = max(minimumHeight, windowHeight * maximumWindowRatio)
        return Double(YENGeometryClamp.clampedLength(
            CGFloat(proposedHeight),
            minimum: CGFloat(minimumHeight),
            maximum: CGFloat(maxHeight)
        ))
    }
}
#endif
