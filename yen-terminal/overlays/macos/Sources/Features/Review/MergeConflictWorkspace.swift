#if os(macOS)
import AppKit
import Darwin
import Foundation

enum MergeConflictResolutionChoice: String, CaseIterable, Identifiable, Sendable {
    case ours = "ours"
    case theirs = "theirs"
    case both = "both"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ours:
            return "Accept Ours"
        case .theirs:
            return "Accept Theirs"
        case .both:
            return "Accept Both"
        }
    }
}

struct MergeConflictHunk: Identifiable, Equatable, Sendable {
    let id: String
    let index: Int
    let startLine: Int
    let oursHeader: String
    let baseHeader: String?
    let theirsHeader: String
    let oursLines: [String]
    let baseLines: [String]?
    let theirsLines: [String]
    let markerLines: [String]
}

enum MergeConflictFileSection: Equatable, Sendable {
    case plain([String])
    case conflict(MergeConflictHunk)

    var conflict: MergeConflictHunk? {
        if case .conflict(let hunk) = self {
            return hunk
        }
        return nil
    }
}

struct MergeConflictFileSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let sections: [MergeConflictFileSection]
    let unsupportedReason: String?

    init(
        path: String,
        id: String? = nil,
        sections: [MergeConflictFileSection],
        unsupportedReason: String?
    ) {
        self.id = id ?? path
        self.path = path
        self.sections = sections
        self.unsupportedReason = unsupportedReason
    }

    var hunks: [MergeConflictHunk] {
        sections.compactMap(\.conflict)
    }
}

struct MergeConflictSnapshot: Equatable, Sendable {
    let repoRoot: String
    let files: [MergeConflictFileSnapshot]
}

struct MergeConflictChoiceRequest: Sendable {
    let repoRoot: String
    let path: String
    let hunkIndex: Int
    let line: Int?
    let choice: MergeConflictResolutionChoice
    let unresolvedHunks: Int
}

struct MergeConflictResolveRequest: Sendable {
    let repoRoot: String
    let path: String
    let expectedSourceContent: String
    let resolvedContent: String
    let remainingFiles: Int
}

struct MergeConflictResolutionConfirmation: Identifiable, Equatable, Sendable {
    let path: String
    let repoRoot: String
    let unresolvedHunks: Int

    var id: String { path }

    var message: String {
        let hunkLabel = unresolvedHunks == 1 ? "hunk" : "hunks"
        return "This writes the resolved file to disk, stages it with git, and revalidates the on-disk conflict markers before applying. \(unresolvedHunks) \(hunkLabel) currently have explicit choices for \(path)."
    }
}

enum MergeConflictCommandError: LocalizedError {
    case noWorkingDirectory
    case notInGitRepository
    case commandFailed(String)
    case toolUnavailable(String)
    case invalidTextFile(String)
    case conflictedFileChangedOnDisk(String)

    var errorDescription: String? {
        switch self {
        case .noWorkingDirectory:
            return "No working directory is available for the active terminal."
        case .notInGitRepository:
            return "This terminal is not inside a git repository."
        case .commandFailed(let message):
            return message
        case .toolUnavailable(let tool):
            return "\(tool) is required to load merge conflicts."
        case .invalidTextFile(let path):
            return "Unable to decode conflicted file as text: \(path)"
        case .conflictedFileChangedOnDisk(let path):
            return "The conflicted file changed on disk before resolve: \(path). Reload the merge-conflict workspace and confirm again."
        }
    }
}

protocol MergeConflictRunning: Sendable {
    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String?
    func loadSnapshot(repoRoot: String) async throws -> MergeConflictSnapshot
    func recordChoice(request: MergeConflictChoiceRequest) throws
    func markResolved(request: MergeConflictResolveRequest) async throws -> MergeConflictSnapshot
}

enum MergeConflictParser {
    static func normalizedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func parse(path: String, content: String) -> MergeConflictFileSnapshot? {
        let normalized = normalizedText(content)
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var sections: [MergeConflictFileSection] = []
        var currentPlainLines: [String] = []
        var index = 0
        var lineNumber = 1
        var hunkCount = 0

        func flushPlainLines() {
            guard !currentPlainLines.isEmpty else { return }
            sections.append(.plain(currentPlainLines))
            currentPlainLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("<<<<<<< ") else {
                currentPlainLines.append(line)
                index += 1
                lineNumber += 1
                continue
            }

            flushPlainLines()

            let startLine = lineNumber
            let oursHeader = String(line.dropFirst("<<<<<<< ".count))
            var markerLines: [String] = [line]
            index += 1
            lineNumber += 1

            var oursLines: [String] = []
            while index < lines.count,
                  !lines[index].hasPrefix("||||||| "),
                  lines[index] != "=======" {
                oursLines.append(lines[index])
                markerLines.append(lines[index])
                index += 1
                lineNumber += 1
            }

            var baseHeader: String?
            var baseLines: [String]?
            if index < lines.count, lines[index].hasPrefix("||||||| ") {
                let baseMarker = lines[index]
                baseHeader = String(baseMarker.dropFirst("||||||| ".count))
                markerLines.append(baseMarker)
                index += 1
                lineNumber += 1

                var collectedBaseLines: [String] = []
                while index < lines.count, lines[index] != "=======" {
                    collectedBaseLines.append(lines[index])
                    markerLines.append(lines[index])
                    index += 1
                    lineNumber += 1
                }
                baseLines = collectedBaseLines
            }

            guard index < lines.count, lines[index] == "=======" else {
                return nil
            }
            markerLines.append(lines[index])
            index += 1
            lineNumber += 1

            var theirsLines: [String] = []
            while index < lines.count, !lines[index].hasPrefix(">>>>>>> ") {
                theirsLines.append(lines[index])
                markerLines.append(lines[index])
                index += 1
                lineNumber += 1
            }

            guard index < lines.count, lines[index].hasPrefix(">>>>>>> ") else {
                return nil
            }
            let theirsHeader = String(lines[index].dropFirst(">>>>>>> ".count))
            markerLines.append(lines[index])
            index += 1
            lineNumber += 1

            hunkCount += 1
            sections.append(
                .conflict(
                    MergeConflictHunk(
                        id: "\(path)#\(hunkCount)",
                        index: hunkCount,
                        startLine: startLine,
                        oursHeader: oursHeader,
                        baseHeader: baseHeader,
                        theirsHeader: theirsHeader,
                        oursLines: oursLines,
                        baseLines: baseLines,
                        theirsLines: theirsLines,
                        markerLines: markerLines
                    )
                )
            )
        }

        flushPlainLines()
        guard sections.contains(where: { $0.conflict != nil }) else { return nil }
        return MergeConflictFileSnapshot(path: path, sections: sections, unsupportedReason: nil)
    }

    static func originalContent(for file: MergeConflictFileSnapshot) -> String {
        var lines: [String] = []
        for section in file.sections {
            switch section {
            case .plain(let plainLines):
                lines.append(contentsOf: plainLines)
            case .conflict(let hunk):
                lines.append(contentsOf: hunk.markerLines)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func resolvedContent(
        for file: MergeConflictFileSnapshot,
        choices: [String: MergeConflictResolutionChoice]
    ) -> String {
        let lines = file.sections.flatMap { section -> [String] in
            switch section {
            case .plain(let plainLines):
                return plainLines
            case .conflict(let hunk):
                guard let choice = choices[hunk.id] else {
                    return hunk.markerLines
                }
                switch choice {
                case .ours:
                    return hunk.oursLines
                case .theirs:
                    return hunk.theirsLines
                case .both:
                    return hunk.oursLines + hunk.theirsLines
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

private enum MergeConflictAudit {
    static var ideStateDirectory: String {
        ReviewIDEStateDirectory.defaultPath
    }

    static func appendTimeline(
        event: String,
        projectRoot: String,
        status: String,
        detail: String,
        now: Date = Date()
    ) throws {
        try ReviewTimelineWriter.append(
            event: event,
            projectRoot: projectRoot,
            status: status,
            detail: detail,
            ideStateDirectory: ideStateDirectory,
            now: now
        )
    }
}

struct MergeConflictShellClient: MergeConflictRunning {
    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String? {
        guard let workingDirectory = ReviewWorkingDirectory.normalized(for: workingDirectory) else {
            return nil
        }

        let output: ReviewCommandOutput
        do {
            output = try await runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", workingDirectory, "rev-parse", "--show-toplevel"],
                currentDirectory: workingDirectory,
                toolName: "git",
                failureSummary: "Unable to resolve the repository root for merge conflict resolution."
            )
        } catch MergeConflictCommandError.commandFailed {
            return nil
        }

        let repoRoot = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return repoRoot.isEmpty ? nil : repoRoot
    }

    func loadSnapshot(repoRoot: String) async throws -> MergeConflictSnapshot {
        let output = try await runRawCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            // core.quotePath=false + -z emit raw NUL-delimited paths, so non-ASCII
            // (accented/CJK/emoji) and special-char conflicted filenames survive
            // instead of arriving C-quoted and failing the on-disk existence check.
            arguments: ["-C", repoRoot, "-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=U", "-z"],
            currentDirectory: repoRoot,
            toolName: "git",
            failureSummary: "Unable to load conflicted files."
        )

        let files = Self.conflictedPathEntries(from: output.stdoutBytes).map { entry in
            guard let path = entry.path else {
                return MergeConflictFileSnapshot(
                    path: entry.displayPath,
                    id: entry.id,
                    sections: [],
                    unsupportedReason: "Git reports this conflicted filename using bytes that are not valid UTF-8, so YEN cannot address it safely. Resolve it outside the merge-conflict workspace."
                )
            }

            let absolutePath = URL(fileURLWithPath: repoRoot)
                .appendingPathComponent(path)
                .path

            guard FileManager.default.fileExists(atPath: absolutePath) else {
                return MergeConflictFileSnapshot(
                    path: path,
                    sections: [],
                    unsupportedReason: "This conflicted path is not present on disk. Resolve it outside the merge-conflict workspace."
                )
            }

            let contents: String
            do {
                contents = try readTextFile(at: absolutePath)
            } catch {
                return MergeConflictFileSnapshot(
                    path: path,
                    sections: [],
                    unsupportedReason: "Unable to read this conflicted file as supported text. Resolve it outside the merge-conflict workspace."
                )
            }
            if let parsed = MergeConflictParser.parse(path: path, content: contents) {
                return parsed
            }

            return MergeConflictFileSnapshot(
                path: path,
                sections: [],
                unsupportedReason: "Git reports this file as conflicted, but no text conflict markers were found. Binary, rename, and non-marker conflicts still need an external resolver."
            )
        }

        return MergeConflictSnapshot(repoRoot: repoRoot, files: files)
    }

    private struct ConflictedPathEntry {
        let id: String
        let path: String?
        let displayPath: String
    }

    private static func conflictedPathEntries(from data: Data) -> [ConflictedPathEntry] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { rawPath in
            let bytes = Data(rawPath)
            if let path = String(data: bytes, encoding: .utf8) {
                return ConflictedPathEntry(id: path, path: path, displayPath: path)
            }

            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            return ConflictedPathEntry(
                id: "raw-git-path:\(bytes.base64EncodedString())",
                path: nil,
                displayPath: "Non-UTF-8 path [\(hex)]"
            )
        }
    }

    func recordChoice(request: MergeConflictChoiceRequest) throws {
        let location = request.line.map { "\(request.path):\($0):1" } ?? request.path
        try MergeConflictAudit.appendTimeline(
            event: "merge-conflict",
            projectRoot: request.repoRoot,
            status: "choice",
            detail: "path=\(request.path);location=\(location);hunk=\(request.hunkIndex);choice=\(request.choice.rawValue);remaining=\(request.unresolvedHunks)"
        )
    }

    func markResolved(request: MergeConflictResolveRequest) async throws -> MergeConflictSnapshot {
        let filePath = URL(fileURLWithPath: request.repoRoot)
            .appendingPathComponent(request.path)
            .path

        let currentSourceContents: String
        do {
            currentSourceContents = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            throw MergeConflictCommandError.invalidTextFile(request.path)
        }

        guard MergeConflictParser.normalizedText(currentSourceContents) == MergeConflictParser.normalizedText(request.expectedSourceContent) else {
            throw MergeConflictCommandError.conflictedFileChangedOnDisk(request.path)
        }

        let parentDirectory = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(
            atPath: parentDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try request.resolvedContent.write(
            to: URL(fileURLWithPath: filePath),
            atomically: true,
            encoding: .utf8
        )

        _ = try await runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", request.repoRoot, "add", "--", request.path],
            currentDirectory: request.repoRoot,
            toolName: "git",
            failureSummary: "Unable to stage the resolved conflict file."
        )

        try MergeConflictAudit.appendTimeline(
            event: "merge-conflict",
            projectRoot: request.repoRoot,
            status: "resolved",
            detail: "path=\(request.path);remaining-files=\(request.remainingFiles)"
        )

        return try await loadSnapshot(repoRoot: request.repoRoot)
    }

    private func readTextFile(at path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        if let value = String(data: data, encoding: .utf8) {
            return value
        }
        throw MergeConflictCommandError.invalidTextFile(path)
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectory: String,
        toolName: String,
        failureSummary: String
    ) async throws -> ReviewCommandOutput {
        let output = try await runRawCommand(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectory: currentDirectory,
            toolName: toolName,
            failureSummary: failureSummary
        )
        return ReviewCommandOutput(stdout: output.stdout)
    }

    private func runRawCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectory: String,
        toolName: String,
        failureSummary: String
    ) async throws -> IDEBlockingProcessOutput {
        try await IDEBlockingProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectory: currentDirectory,
            toolUnavailable: MergeConflictCommandError.toolUnavailable(toolName),
            commandFailed: { detail in
                let message = detail.isEmpty ? failureSummary : "\(failureSummary)\n\(detail)"
                return MergeConflictCommandError.commandFailed(message)
            }
        )
    }
}

private actor MergeConflictChoiceAuditQueue {
    private var tail: Task<String?, Never>?

    func enqueue(
        request: MergeConflictChoiceRequest,
        runner: any MergeConflictRunning
    ) async -> String? {
        let predecessor = tail
        let task = Task.detached(priority: .utility) { () -> String? in
            _ = await predecessor?.value
            do {
                try runner.recordChoice(request: request)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        tail = task
        return await task.value
    }
}

@MainActor
final class MergeConflictResolutionModel: ObservableObject {
    @Published private(set) var workingDirectorySummary: String?
    @Published private(set) var repositorySummary: String?
    @Published private(set) var snapshot: MergeConflictSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedHunkDiffPreview: String = "Select a conflicted hunk to preview its patch."
    @Published private(set) var selectedHunkDiffPreviewSource: IDEDiffPreviewSource = .plain
    @Published var pendingResolutionConfirmation: MergeConflictResolutionConfirmation?
    @Published var selectedFilePath: String? {
        didSet {
            pendingResolutionConfirmation = nil
            syncSelectedHunk(previousSelection: oldValue)
        }
    }
    @Published var selectedHunkID: String? {
        didSet {
            syncSelectedHunkPreview()
        }
    }

    private let runner: any MergeConflictRunning
    private let renderDiffPreview: @Sendable (String) async -> IDEDiffRenderedPreview
    private let openInEditor: @MainActor (IDESemanticLocation) async -> String?
    private let choiceAuditQueue = MergeConflictChoiceAuditQueue()
    private var workingDirectory: String?
    private var loadTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var loadTaskGeneration = 0
    private var applyTaskGeneration = 0
    private var previewTaskGeneration = 0
    private var choiceAuditGeneration = 0
    private var editorOpenGeneration = 0
    private var choicesByHunkID: [String: MergeConflictResolutionChoice] = [:]
    private var renderedPreviewCache: [String: IDEDiffRenderedPreview] = [:]
    private var renderedPreviewCacheOrder: [String] = []
    private static let renderedPreviewCacheLimit = 64

    init(
        runner: any MergeConflictRunning = MergeConflictShellClient(),
        openInEditor: @escaping @MainActor (IDESemanticLocation) async -> String? = { await IDEEditorNavigator.open($0) },
        renderDiffPreview: @escaping @Sendable (String) async -> IDEDiffRenderedPreview = {
            await IDEDiffPreviewRenderer.renderAsync(diff: $0)
        }
    ) {
        self.runner = runner
        self.openInEditor = openInEditor
        self.renderDiffPreview = renderDiffPreview
    }

    deinit {
        loadTask?.cancel()
        applyTask?.cancel()
        previewTask?.cancel()
    }

    var selectedFile: MergeConflictFileSnapshot? {
        guard let selectedFilePath else { return nil }
        return snapshot?.files.first(where: { $0.path == selectedFilePath })
    }

    var selectedHunk: MergeConflictHunk? {
        guard let selectedHunkID else { return nil }
        return selectedFile?.hunks.first(where: { $0.id == selectedHunkID })
    }

    var selectedFileLocation: IDESemanticLocation? {
        guard let snapshot, let selectedFilePath else { return nil }
        return IDESemanticLocation.repositoryLocation(
            repoRoot: snapshot.repoRoot,
            relativePath: selectedFilePath
        )
    }

    var selectedHunkLocation: IDESemanticLocation? {
        guard let snapshot, let selectedFile, let selectedHunk else { return nil }
        return IDESemanticLocation.repositoryLocation(
            repoRoot: snapshot.repoRoot,
            relativePath: selectedFile.path,
            line: selectedHunk.startLine,
            column: 1
        )
    }

    var selectedEditorLocation: IDESemanticLocation? {
        selectedHunkLocation ?? selectedFileLocation
    }

    var canNavigateFiles: Bool {
        guard let snapshot else { return false }
        return snapshot.files.count > 1
    }

    var canNavigateHunks: Bool {
        (selectedFile?.hunks.count ?? 0) > 1
    }

    var totalUnresolvedHunks: Int {
        snapshot?.files.reduce(0) { total, file in
            total + unresolvedHunkCount(for: file)
        } ?? 0
    }

    var selectedFileResolvedPreview: String {
        guard let selectedFile else {
            return "Load a conflicted repository to preview the resolved output."
        }
        if let unsupportedReason = selectedFile.unsupportedReason {
            return unsupportedReason
        }
        return MergeConflictParser.resolvedContent(for: selectedFile, choices: choicesByHunkID)
    }

    var selectedHunkDiffPreviewLabel: String {
        selectedHunkDiffPreviewSource.label
    }

    var selectedFileStatusSummary: String {
        guard let selectedFile else {
            return "No conflicted file selected."
        }
        if let unsupportedReason = selectedFile.unsupportedReason {
            return unsupportedReason
        }
        let unresolved = unresolvedHunkCount(for: selectedFile)
        return unresolved == 0
            ? "All hunks have a resolution choice. Mark the file resolved to write it and stage it."
            : "\(unresolved) unresolved hunk\(unresolved == 1 ? "" : "s") remain in this file."
    }

    var canMarkSelectedFileResolved: Bool {
        guard let selectedFile else { return false }
        guard selectedFile.unsupportedReason == nil else { return false }
        return !isApplying && !selectedFile.hunks.isEmpty && unresolvedHunkCount(for: selectedFile) == 0
    }

    func prepareForPresentation(workingDirectory: String?) {
        let normalized = Self.normalizedWorkingDirectory(workingDirectory)
        if normalized != self.workingDirectory {
            cancelLoading()
            cancelApplying()
            previewTask?.cancel()
            previewTask = nil
            previewTaskGeneration += 1
            snapshot = nil
            selectedFilePath = nil
            selectedHunkID = nil
            choicesByHunkID = [:]
            renderedPreviewCache = [:]
            renderedPreviewCacheOrder = []
            selectedHunkDiffPreview = "Select a conflicted hunk to preview its patch."
            selectedHunkDiffPreviewSource = .plain
            statusMessage = nil
            errorMessage = nil
            pendingResolutionConfirmation = nil
            repositorySummary = nil
            choiceAuditGeneration += 1
        }

        self.workingDirectory = normalized
        workingDirectorySummary = normalized.map(\.abbreviatedPath)
    }

    /// Drop every retained conflict payload so the process-lifetime singleton
    /// controller does not keep a repo's full conflict snapshot plus up to 64
    /// rendered previews resident after the workspace window closes.
    func releaseHeldState() {
        cancelLoading()
        cancelApplying()
        previewTask?.cancel()
        previewTask = nil
        previewTaskGeneration += 1
        snapshot = nil
        selectedFilePath = nil
        selectedHunkID = nil
        choicesByHunkID = [:]
        renderedPreviewCache = [:]
        renderedPreviewCacheOrder = []
        selectedHunkDiffPreview = "Select a conflicted hunk to preview its patch."
        selectedHunkDiffPreviewSource = .plain
        statusMessage = nil
        errorMessage = nil
        pendingResolutionConfirmation = nil
        repositorySummary = nil
        workingDirectorySummary = nil
        workingDirectory = nil
        choiceAuditGeneration += 1
    }

    func requestLoad() {
        cancelLoading()
        isLoading = true
        errorMessage = nil

        let workingDirectory = self.workingDirectory
        let runner = self.runner
        loadTaskGeneration += 1
        let taskGeneration = loadTaskGeneration

        loadTask = Task { [weak self] in
            do {
                guard let repoRoot = try await runner.resolveRepositoryRoot(for: workingDirectory) else {
                    throw MergeConflictCommandError.notInGitRepository
                }
                let snapshot = try await runner.loadSnapshot(repoRoot: repoRoot)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, self.loadTaskGeneration == taskGeneration else { return }
                    self.applyLoadedSnapshot(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.loadTaskGeneration == taskGeneration else { return }
                    self.applyLoadError(error)
                }
            }
        }
    }

    func cancelLoading() {
        loadTaskGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func cancelApplying() {
        applyTaskGeneration += 1
        applyTask?.cancel()
        applyTask = nil
        isApplying = false
    }

    func selectPreviousFile() {
        selectedFilePath = Self.adjacentSelection(
            from: snapshot?.files.map(\.path) ?? [],
            current: selectedFilePath,
            direction: -1
        )
    }

    func selectNextFile() {
        selectedFilePath = Self.adjacentSelection(
            from: snapshot?.files.map(\.path) ?? [],
            current: selectedFilePath,
            direction: 1
        )
    }

    func selectHunk(id: String) {
        selectedHunkID = id
    }

    func selectPreviousHunk() {
        selectedHunkID = Self.adjacentSelection(
            from: selectedFile?.hunks.map(\.id) ?? [],
            current: selectedHunkID,
            direction: -1
        )
    }

    func selectNextHunk() {
        selectedHunkID = Self.adjacentSelection(
            from: selectedFile?.hunks.map(\.id) ?? [],
            current: selectedHunkID,
            direction: 1
        )
    }

    func resolutionChoice(for hunk: MergeConflictHunk) -> MergeConflictResolutionChoice? {
        choicesByHunkID[hunk.id]
    }

    func chooseResolution(_ choice: MergeConflictResolutionChoice) {
        guard let snapshot, let selectedFile, let selectedHunk else {
            statusMessage = "Select a conflicted hunk before choosing a resolution."
            return
        }
        guard selectedFile.unsupportedReason == nil else {
            statusMessage = "This conflicted file is not marker-based text. Resolve it outside the merge-conflict workspace."
            return
        }

        choicesByHunkID[selectedHunk.id] = choice
        syncSelectedHunkPreview()
        pendingResolutionConfirmation = nil
        let remaining = unresolvedHunkCount(for: selectedFile)
        let selectedTarget = selectedHunkLocation?.target ?? selectedFile.path
        statusMessage = "Selected \(choice.rawValue) for \(selectedTarget) hunk \(selectedHunk.index). \(remaining) unresolved hunk\(remaining == 1 ? "" : "s") remain."
        errorMessage = nil

        let auditGeneration = choiceAuditGeneration
        let choiceAuditQueue = self.choiceAuditQueue
        let runner = self.runner
        let request = MergeConflictChoiceRequest(
            repoRoot: snapshot.repoRoot,
            path: selectedFile.path,
            hunkIndex: selectedHunk.index,
            line: selectedHunk.startLine,
            choice: choice,
            unresolvedHunks: remaining
        )
        Task { [weak self, choiceAuditQueue, runner, request, auditGeneration] in
            guard let failure = await choiceAuditQueue.enqueue(request: request, runner: runner) else {
                return
            }
            await MainActor.run {
                guard let self, self.choiceAuditGeneration == auditGeneration else { return }
                self.errorMessage = failure
            }
        }
    }

    func openSelectedLocationInEditor() async {
        guard let location = selectedEditorLocation else {
            statusMessage = "Select a conflicted file or hunk before opening it in the editor."
            return
        }
        editorOpenGeneration += 1
        let generation = editorOpenGeneration
        let priorMessage = statusMessage
        let failure = await openInEditor(location)
        guard editorOpenGeneration == generation,
              selectedEditorLocation?.target == location.target,
              statusMessage == priorMessage else { return }
        statusMessage = failure
    }

    func markSelectedFileResolved() {
        guard let confirmation = resolutionConfirmation() else { return }
        pendingResolutionConfirmation = confirmation
        errorMessage = nil
        statusMessage = "Confirm resolve to write \(confirmation.path) and stage it with git."
    }

    func dismissPendingResolutionConfirmation() {
        pendingResolutionConfirmation = nil
    }

    func confirmPendingResolution() {
        guard let confirmation = pendingResolutionConfirmation else { return }
        pendingResolutionConfirmation = nil
        applySelectedFileResolution(expectedPath: confirmation.path, repoRoot: confirmation.repoRoot)
    }

    private func resolutionConfirmation() -> MergeConflictResolutionConfirmation? {
        guard let snapshot, let selectedFile else {
            statusMessage = "Select a conflicted file before marking it resolved."
            return nil
        }
        guard selectedFile.unsupportedReason == nil else {
            statusMessage = "This conflicted file is not marker-based text. Resolve it outside the merge-conflict workspace."
            return nil
        }
        guard unresolvedHunkCount(for: selectedFile) == 0 else {
            statusMessage = "Resolve every hunk in this file before marking it resolved."
            return nil
        }

        return MergeConflictResolutionConfirmation(
            path: selectedFile.path,
            repoRoot: snapshot.repoRoot,
            unresolvedHunks: selectedFile.hunks.count
        )
    }

    private func applySelectedFileResolution(expectedPath: String, repoRoot: String) {
        guard let snapshot, let selectedFile else {
            statusMessage = "Select a conflicted file before marking it resolved."
            return
        }
        guard selectedFile.path == expectedPath, snapshot.repoRoot == repoRoot else {
            statusMessage = "The selected file changed before confirm. Review the current file and confirm again."
            return
        }

        cancelApplying()
        isApplying = true
        errorMessage = nil
        statusMessage = nil
        let runner = self.runner
        let request = MergeConflictResolveRequest(
            repoRoot: snapshot.repoRoot,
            path: selectedFile.path,
            expectedSourceContent: MergeConflictParser.originalContent(for: selectedFile),
            resolvedContent: MergeConflictParser.resolvedContent(for: selectedFile, choices: choicesByHunkID),
            remainingFiles: max(snapshot.files.count - 1, 0)
        )
        applyTaskGeneration += 1
        let taskGeneration = applyTaskGeneration

        applyTask = Task { [weak self] in
            do {
                let updatedSnapshot = try await runner.markResolved(request: request)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, self.applyTaskGeneration == taskGeneration else { return }
                    self.applyResolvedSnapshot(updatedSnapshot, path: request.path)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.applyTaskGeneration == taskGeneration else { return }
                    self.isApplying = false
                    self.applyTask = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func unresolvedHunkCount(for file: MergeConflictFileSnapshot) -> Int {
        file.hunks.reduce(0) { count, hunk in
            count + (choicesByHunkID[hunk.id] == nil ? 1 : 0)
        }
    }

    static func adjacentSelection(from ids: [String], current: String?, direction: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return ids.first
        }

        let nextIndex = min(max(index + direction, 0), ids.count - 1)
        return ids[nextIndex]
    }

    private static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        return NSString(string: workingDirectory).expandingTildeInPath
    }

    private func applyLoadedSnapshot(_ snapshot: MergeConflictSnapshot) {
        let existingChoices = choicesByHunkID
        let validHunkIDs = Set(snapshot.files.flatMap { $0.hunks.map(\.id) })
        choicesByHunkID = existingChoices.filter { validHunkIDs.contains($0.key) }
        pendingResolutionConfirmation = nil

        self.snapshot = snapshot
        repositorySummary = snapshot.repoRoot.abbreviatedPath
        isLoading = false
        loadTask = nil

        let existingSelection = selectedFilePath
        selectedFilePath = if let existingSelection,
                             snapshot.files.contains(where: { $0.path == existingSelection }) {
            existingSelection
        } else {
            snapshot.files.first?.path
        }
        syncSelectedHunk(previousSelection: existingSelection)
        syncSelectedHunkPreview()

        if snapshot.files.isEmpty {
            statusMessage = "No unresolved conflicted files were found in this repository."
        } else {
            statusMessage = "Loaded \(snapshot.files.count) conflicted file\(snapshot.files.count == 1 ? "" : "s")."
        }
        errorMessage = nil
    }

    private func applyResolvedSnapshot(_ snapshot: MergeConflictSnapshot, path: String) {
        isApplying = false
        applyTask = nil
        pendingResolutionConfirmation = nil

        let oldHunkIDs = Set(self.snapshot?.files.first(where: { $0.path == path })?.hunks.map(\.id) ?? [])
        for hunkID in oldHunkIDs {
            choicesByHunkID.removeValue(forKey: hunkID)
        }

        applyLoadedSnapshot(snapshot)
        statusMessage = "Marked \(path) resolved and staged it with git."
    }

    private func applyLoadError(_ error: Error) {
        isLoading = false
        loadTask = nil
        if let reviewError = error as? MergeConflictCommandError {
            errorMessage = reviewError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func syncSelectedHunk(previousSelection: String?) {
        guard let file = selectedFile else {
            selectedHunkID = nil
            return
        }

        if let current = selectedHunkID,
           file.hunks.contains(where: { $0.id == current }) {
            return
        }

        if let firstUnresolved = file.hunks.first(where: { choicesByHunkID[$0.id] == nil }) {
            selectedHunkID = firstUnresolved.id
            return
        }

        selectedHunkID = file.hunks.first?.id
    }

    private func syncSelectedHunkPreview() {
        // Invalidate any in-flight render so a stale delta result can't clobber a
        // newer selection (or a placeholder set by the guards below).
        previewTaskGeneration += 1
        previewTask?.cancel()
        previewTask = nil

        guard let selectedFile, let selectedHunk else {
            selectedHunkDiffPreview = "Select a conflicted hunk to preview its patch."
            selectedHunkDiffPreviewSource = .plain
            return
        }

        guard let choice = choicesByHunkID[selectedHunk.id] else {
            selectedHunkDiffPreview = "Choose ours, theirs, or both to preview the patch for \(selectedHunkLocation?.target ?? selectedFile.path)."
            selectedHunkDiffPreviewSource = .plain
            return
        }

        let resolvedLines: [String]
        switch choice {
        case .ours:
            resolvedLines = selectedHunk.oursLines
        case .theirs:
            resolvedLines = selectedHunk.theirsLines
        case .both:
            resolvedLines = selectedHunk.oursLines + selectedHunk.theirsLines
        }

        let syntheticDiff = IDEDiffPreviewBuilder.syntheticUnifiedDiff(
            path: selectedFile.path,
            startLine: selectedHunk.startLine,
            oldLines: selectedHunk.markerLines,
            newLines: resolvedLines
        )

        // `delta` output is deterministic per diff, so a re-visited hunk/choice
        // renders synchronously from the cache with no subprocess.
        if let cached = renderedPreviewCache[syntheticDiff] {
            selectedHunkDiffPreview = cached.text
            selectedHunkDiffPreviewSource = cached.source
            return
        }

        // Show the raw patch instantly, then upgrade to the delta-rendered preview
        // once the off-main render completes. The subprocess now runs off the main
        // actor (IDEBlockingProcessRunner), so selecting a hunk never blocks the UI.
        selectedHunkDiffPreview = syntheticDiff
        selectedHunkDiffPreviewSource = .plain

        let taskGeneration = previewTaskGeneration
        let render = renderDiffPreview
        previewTask = Task { [weak self] in
            let rendered = await render(syntheticDiff)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.previewTaskGeneration == taskGeneration else { return }
                self.insertRenderedPreview(rendered, for: syntheticDiff)
                self.selectedHunkDiffPreview = rendered.text
                self.selectedHunkDiffPreviewSource = rendered.source
                self.previewTask = nil
            }
        }
    }

    /// Memoizes a rendered hunk preview by its exact diff string so navigating back
    /// to an already-rendered hunk/choice reuses the result instead of re-spawning
    /// `delta`. Bounded to avoid unbounded growth across a long session.
    private func insertRenderedPreview(_ rendered: IDEDiffRenderedPreview, for syntheticDiff: String) {
        guard renderedPreviewCache[syntheticDiff] == nil else { return }
        renderedPreviewCache[syntheticDiff] = rendered
        renderedPreviewCacheOrder.append(syntheticDiff)
        if renderedPreviewCacheOrder.count > Self.renderedPreviewCacheLimit {
            let evicted = renderedPreviewCacheOrder.removeFirst()
            renderedPreviewCache.removeValue(forKey: evicted)
        }
    }
}
#endif
