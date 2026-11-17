#if os(macOS)
import Foundation

struct GitDrawerSnapshot: Equatable, Sendable {
    let repoRoot: String
    let workingDirectory: String
    let branch: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: [GitDrawerFileChange]
    let unstaged: [GitDrawerFileChange]
    let untracked: [GitDrawerFileChange]
    let conflicted: [GitDrawerFileChange]
    let stashCount: Int
    let stashEntries: [GitDrawerStashEntry]
    let isStashListTruncated: Bool
    let selectedFile: String?
    let selectedDiff: String?
    let isDiffTruncated: Bool
    let isFileListTruncated: Bool
    let generation: Int
    let hasCommits: Bool

    init(
        repoRoot: String,
        workingDirectory: String? = nil,
        branch: String,
        upstream: String?,
        ahead: Int,
        behind: Int,
        staged: [GitDrawerFileChange],
        unstaged: [GitDrawerFileChange],
        untracked: [GitDrawerFileChange],
        conflicted: [GitDrawerFileChange],
        stashCount: Int,
        stashEntries: [GitDrawerStashEntry] = [],
        isStashListTruncated: Bool = false,
        selectedFile: String?,
        selectedDiff: String?,
        isDiffTruncated: Bool,
        isFileListTruncated: Bool = false,
        generation: Int,
        hasCommits: Bool = true
    ) {
        self.repoRoot = repoRoot
        self.workingDirectory = workingDirectory ?? repoRoot
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
        self.stashCount = stashCount
        self.stashEntries = stashEntries
        self.isStashListTruncated = isStashListTruncated
        self.selectedFile = selectedFile
        self.selectedDiff = selectedDiff
        self.isDiffTruncated = isDiffTruncated
        self.isFileListTruncated = isFileListTruncated
        self.generation = generation
        self.hasCommits = hasCommits
    }

    var totalChangedFileCount: Int {
        Set((staged + unstaged + untracked + conflicted).map(\.path)).count
    }

    var totalAdditions: Int {
        (staged + unstaged).compactMap(\.additions).reduce(0, +)
    }

    var totalDeletions: Int {
        (staged + unstaged).compactMap(\.deletions).reduce(0, +)
    }

    var isClean: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && conflicted.isEmpty
    }
}

struct GitDrawerStashEntry: Equatable, Sendable, Identifiable {
    let id: String
    let ref: String
    let message: String
    let files: [GitDrawerStashFile]

    init(ref: String, message: String, files: [GitDrawerStashFile]) {
        self.id = ref
        self.ref = ref
        self.message = message
        self.files = files
    }
}

struct GitDrawerStashFile: Equatable, Sendable, Identifiable {
    let id: String
    let path: String
    let oldPath: String?
    let status: GitDrawerFileStatus

    init(path: String, oldPath: String?, status: GitDrawerFileStatus) {
        self.id = "\(status.rawValue)-\(oldPath ?? "")-\(path)"
        self.path = path
        self.oldPath = oldPath
        self.status = status
    }

    var displayPath: String {
        if let oldPath, oldPath != path {
            return "\(oldPath) -> \(path)"
        }
        return path
    }
}

struct GitDrawerFileChange: Equatable, Sendable {
    let path: String
    let oldPath: String?
    let status: GitDrawerFileStatus
    let stage: GitDrawerChangeStage
    let additions: Int?
    let deletions: Int?
    let statPlaceholder: String?

    init(
        path: String,
        oldPath: String?,
        status: GitDrawerFileStatus,
        stage: GitDrawerChangeStage,
        additions: Int?,
        deletions: Int?,
        statPlaceholder: String? = nil
    ) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.stage = stage
        self.additions = additions
        self.deletions = deletions
        self.statPlaceholder = statPlaceholder
    }

    var displayPath: String {
        if let oldPath, oldPath != path {
            return "\(oldPath) -> \(path)"
        }
        return path
    }
}

enum GitDrawerFileStatus: String, Equatable, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case typeChanged = "T"
    case conflicted = "U"
    case untracked = "??"
}

enum GitDrawerChangeStage: Equatable, Sendable {
    case staged
    case unstaged
    case untracked
    case conflicted
}

enum GitDrawerSnapshotParser {
    static let defaultFileLimit = 500
    static let defaultStashEntryLimit = 20

    static func snapshot(
        repoRoot: String,
        branch: String,
        upstream: String?,
        aheadBehindOutput: String,
        statusPorcelainZ: String,
        parsedStatusEntries: [GitStatusPorcelainV2.Entry]? = nil,
        unstagedNameStatusZ: String,
        stagedNameStatusZ: String,
        unstagedNumstatZ: String,
        stagedNumstatZ: String,
        stashListOutput: String,
        stashFileOutputsByRef: [String: String] = [:],
        stashEntryLimit: Int = defaultStashEntryLimit,
        fileLimit: Int = defaultFileLimit
    ) -> GitDrawerSnapshot {
        let counts = parseAheadBehind(aheadBehindOutput)
        let entries = parsedStatusEntries ?? GitStatusPorcelainV2.parseEntries(statusPorcelainZ) ?? []
        let statusEntries = entries.map {
            GitDrawerStatusEntry(path: $0.path, oldPath: $0.oldPath, status: statusFromPorcelain($0.code))
        }
        let unstagedStats = parseNumstat(unstagedNumstatZ)
        let stagedStats = parseNumstat(stagedNumstatZ)
        let submodulePaths = Set(entries
            .filter(\.isSubmodule).map(\.path))

        let parsedStaged = parseNameStatus(
            stagedNameStatusZ,
            stage: .staged,
            stats: stagedStats,
            submodulePaths: submodulePaths
        ).filter { $0.status != .conflicted }
        let parsedUnstaged = parseNameStatus(
            unstagedNameStatusZ,
            stage: .unstaged,
            stats: unstagedStats,
            submodulePaths: submodulePaths
        ).filter { $0.status != .conflicted }
        let parsedUntracked = statusEntries
            .filter { $0.status == .untracked }
            .map { entry in
                GitDrawerFileChange(
                    path: entry.path,
                    oldPath: entry.oldPath,
                    status: .untracked,
                    stage: .untracked,
                    additions: nil,
                    deletions: nil,
                    statPlaceholder: nil
                )
            }
        let parsedConflicted = statusEntries
            .filter { $0.status == .conflicted }
            .map { entry in
                let stats = unstagedStats[entry.path] ?? stagedStats[entry.path]
                let isSubmodule = submodulePaths.contains(entry.path)
                return GitDrawerFileChange(
                    path: entry.path,
                    oldPath: entry.oldPath,
                    status: .conflicted,
                    stage: .conflicted,
                    additions: isSubmodule ? nil : stats?.additions,
                    deletions: isSubmodule ? nil : stats?.deletions,
                    statPlaceholder: isSubmodule ? "submodule" : stats?.placeholder
                )
            }
        let capped = cappedGroups(
            staged: parsedStaged,
            unstaged: parsedUnstaged,
            untracked: parsedUntracked,
            conflicted: parsedConflicted,
            fileLimit: fileLimit
        )
        let parsedStashes = parseStashEntries(
            stashListOutput,
            fileOutputsByRef: stashFileOutputsByRef,
            entryLimit: stashEntryLimit
        )

        return GitDrawerSnapshot(
            repoRoot: repoRoot,
            workingDirectory: repoRoot,
            branch: branch,
            upstream: upstream,
            ahead: counts.ahead,
            behind: counts.behind,
            staged: capped.staged,
            unstaged: capped.unstaged,
            untracked: capped.untracked,
            conflicted: capped.conflicted,
            stashCount: stashCount(stashListOutput),
            stashEntries: parsedStashes.entries,
            isStashListTruncated: parsedStashes.isTruncated,
            selectedFile: nil,
            selectedDiff: nil,
            isDiffTruncated: false,
            isFileListTruncated: capped.isTruncated,
            generation: 0
        )
    }

    static func parseAheadBehind(_ output: String) -> (behind: Int, ahead: Int) {
        let counts = output
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard counts.count == 2 else {
            return (0, 0)
        }
        return (counts[0], counts[1])
    }

    static func testingStatusEntries(
        _ output: String
    ) -> [(path: String, oldPath: String?, status: GitDrawerFileStatus)] {
        parseStatusPorcelain(output).map { ($0.path, $0.oldPath, $0.status) }
    }

    static func testingStashEntries(
        stashListOutput: String,
        stashFileOutputsByRef: [String: String],
        entryLimit: Int = defaultStashEntryLimit
    ) -> [GitDrawerStashEntry] {
        parseStashEntries(
            stashListOutput,
            fileOutputsByRef: stashFileOutputsByRef,
            entryLimit: entryLimit
        ).entries
    }

    static func stashRefs(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let separator = trimmed.firstIndex(of: ":")
                else { return nil }
                return String(trimmed[..<separator])
            }
    }

    private static func parseNameStatus(
        _ output: String,
        stage: GitDrawerChangeStage,
        stats: [String: GitDrawerNumstat],
        submodulePaths: Set<String>
    ) -> [GitDrawerFileChange] {
        let tokens = nulTokens(output)
        var rows: [GitDrawerFileChange] = []
        var index = 0

        while index < tokens.count {
            let rawStatus = tokens[index]
            index += 1
            guard !rawStatus.isEmpty, index < tokens.count else { break }

            let status = statusFromNameStatus(rawStatus)
            let pathCount = status == .renamed || status == .copied ? 2 : 1
            guard index + pathCount - 1 < tokens.count else { break }

            let oldPath: String?
            let path: String
            if pathCount == 2 {
                oldPath = tokens[index]
                path = tokens[index + 1]
                index += 2
            } else {
                oldPath = nil
                path = tokens[index]
                index += 1
            }

            let numstat = stats[path] ?? oldPath.flatMap { stats[$0] }
            let isSubmodule = submodulePaths.contains(path) || oldPath.map(submodulePaths.contains) == true
            rows.append(
                GitDrawerFileChange(
                    path: path,
                    oldPath: oldPath,
                    status: status,
                    stage: stage,
                    additions: isSubmodule ? nil : numstat?.additions,
                    deletions: isSubmodule ? nil : numstat?.deletions,
                    statPlaceholder: isSubmodule ? "submodule" : numstat?.placeholder
                )
            )
        }

        return rows
    }

    private static func parseNumstat(_ output: String) -> [String: GitDrawerNumstat] {
        var stats: [String: GitDrawerNumstat] = [:]
        let tokens = nulTokens(output)
        var index = 0

        while index < tokens.count {
            // `git diff --numstat -z` emits "<add>\t<del>\t<path>" for ordinary entries, but a
            // rename/copy splits the paths into separate NUL fields: "<add>\t<del>\t" then <from>
            // then <to> as the next two NUL tokens. maxSplits keeps any tab inside a path intact.
            let fields = tokens[index]
                .split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                .map(String.init)
            index += 1
            guard fields.count >= 3 else { continue }

            let additions: Int?
            let deletions: Int?
            let placeholder: String?
            if fields[0] == "-" || fields[1] == "-" {
                additions = nil
                deletions = nil
                placeholder = "binary"
            } else if let parsedAdditions = Int(fields[0]), let parsedDeletions = Int(fields[1]) {
                additions = parsedAdditions
                deletions = parsedDeletions
                placeholder = nil
            } else {
                continue
            }

            let path: String
            if fields[2].isEmpty {
                // Rename/copy: the next two NUL tokens are <from> and <to>; key under <to>.
                guard index + 1 < tokens.count else { break }
                path = tokens[index + 1]
                index += 2
            } else {
                path = fields[2]
            }

            stats[path] = GitDrawerNumstat(
                additions: additions,
                deletions: deletions,
                placeholder: placeholder
            )
        }

        return stats
    }

    private static func parseStatusPorcelain(_ output: String) -> [GitDrawerStatusEntry] {
        (GitStatusPorcelainV2.parseEntries(output) ?? []).map {
            GitDrawerStatusEntry(path: $0.path, oldPath: $0.oldPath, status: statusFromPorcelain($0.code))
        }
    }

    private static func statusFromNameStatus(_ rawStatus: String) -> GitDrawerFileStatus {
        if rawStatus.hasPrefix("R") {
            return .renamed
        }
        if rawStatus.hasPrefix("C") {
            return .copied
        }
        if rawStatus.hasPrefix("A") {
            return .added
        }
        if rawStatus.hasPrefix("D") {
            return .deleted
        }
        if rawStatus.hasPrefix("T") {
            return .typeChanged
        }
        if rawStatus.hasPrefix("U") {
            return .conflicted
        }
        return .modified
    }

    private static func statusFromPorcelain(_ statusCode: String) -> GitDrawerFileStatus {
        if statusCode == "??" {
            return .untracked
        }
        if statusCode.contains("U") || statusCode == "AA" || statusCode == "DD" {
            return .conflicted
        }
        if statusCode.hasPrefix("R") || statusCode.hasSuffix("R") {
            return .renamed
        }
        if statusCode.hasPrefix("C") || statusCode.hasSuffix("C") {
            return .copied
        }
        if statusCode.hasPrefix("A") || statusCode.hasSuffix("A") {
            return .added
        }
        if statusCode.hasPrefix("D") || statusCode.hasSuffix("D") {
            return .deleted
        }
        if statusCode.hasPrefix("T") || statusCode.hasSuffix("T") {
            return .typeChanged
        }
        return .modified
    }

    private static func stashCount(_ output: String) -> Int {
        output
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private static func parseStashEntries(
        _ stashListOutput: String,
        fileOutputsByRef: [String: String],
        entryLimit: Int
    ) -> (entries: [GitDrawerStashEntry], isTruncated: Bool) {
        let safeLimit = max(0, entryLimit)
        let lines = stashListOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let entries = lines
            .prefix(safeLimit)
            .compactMap { line -> GitDrawerStashEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let separator = trimmed.firstIndex(of: ":")
                else { return nil }

                let ref = String(trimmed[..<separator])
                let messageStart = trimmed.index(after: separator)
                let message = trimmed[messageStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                return GitDrawerStashEntry(
                    ref: ref,
                    message: message,
                    files: parseStashFiles(fileOutputsByRef[ref] ?? "")
                )
            }
        return (entries, lines.count > safeLimit)
    }

    private static func parseStashFiles(_ output: String) -> [GitDrawerStashFile] {
        let tokens = nulTokens(output)
        var rows: [GitDrawerStashFile] = []
        var index = 0

        while index < tokens.count {
            let rawStatus = tokens[index]
            index += 1
            guard !rawStatus.isEmpty, index < tokens.count else { break }

            let status = statusFromNameStatus(rawStatus)
            let pathCount = status == .renamed || status == .copied ? 2 : 1
            guard index + pathCount - 1 < tokens.count else { break }

            let oldPath: String?
            let path: String
            if pathCount == 2 {
                oldPath = tokens[index]
                path = tokens[index + 1]
                index += 2
            } else {
                oldPath = nil
                path = tokens[index]
                index += 1
            }

            rows.append(GitDrawerStashFile(path: path, oldPath: oldPath, status: status))
        }

        return rows
    }

    private static func cappedGroups(
        staged: [GitDrawerFileChange],
        unstaged: [GitDrawerFileChange],
        untracked: [GitDrawerFileChange],
        conflicted: [GitDrawerFileChange],
        fileLimit: Int
    ) -> (
        staged: [GitDrawerFileChange],
        unstaged: [GitDrawerFileChange],
        untracked: [GitDrawerFileChange],
        conflicted: [GitDrawerFileChange],
        isTruncated: Bool
    ) {
        let safeLimit = max(0, fileLimit)
        var remaining = safeLimit
        var truncated = false

        func take(_ changes: [GitDrawerFileChange]) -> [GitDrawerFileChange] {
            guard remaining > 0 else {
                truncated = truncated || !changes.isEmpty
                return []
            }
            if changes.count <= remaining {
                remaining -= changes.count
                return changes
            }
            truncated = true
            let prefix = Array(changes.prefix(remaining))
            remaining = 0
            return prefix
        }

        let cappedConflicted = take(conflicted)
        let cappedStaged = take(staged)
        let cappedUnstaged = take(unstaged)
        let cappedUntracked = take(untracked)

        return (cappedStaged, cappedUnstaged, cappedUntracked, cappedConflicted, truncated)
    }

    private static func nulTokens(_ output: String) -> [String] {
        output
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

private struct GitDrawerNumstat: Equatable {
    let additions: Int?
    let deletions: Int?
    let placeholder: String?
}

private struct GitDrawerStatusEntry: Equatable {
    let path: String
    let oldPath: String?
    let status: GitDrawerFileStatus
}
#endif
