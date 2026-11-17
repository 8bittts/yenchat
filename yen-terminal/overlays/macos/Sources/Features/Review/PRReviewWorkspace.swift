#if os(macOS)
import AppKit
import Foundation
import SwiftUI

@MainActor
final class PullRequestReviewModel: ObservableObject {
    @Published var prReference: String = ""
    @Published private(set) var workingDirectorySummary: String?
    @Published private(set) var repositorySummary: String?
    @Published private(set) var snapshot: PullRequestReviewSnapshot?
    @Published private(set) var evidenceContext: PullRequestReviewEvidenceContext = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var focusedDiff: String = ""
    @Published private(set) var stagingMessage: String?
    @Published private(set) var submissionErrorMessage: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var stagedDrafts: [PullRequestReviewStagedDraft] = []
    @Published var selectedDecisionMode: PullRequestReviewDecisionMode = .comment
    @Published var reviewNote: String = ""
    @Published var pendingSubmissionConfirmation: PullRequestReviewSubmissionConfirmation?
    @Published var inlineDraftPath: String = ""
    @Published var inlineDraftLine: String = ""
    @Published var inlineDraftSide: PullRequestReviewCommentSide = .right
    @Published var inlineDraftBody: String = ""
    @Published var selectedHunkID: String? {
        didSet {
            cachedCurrentEvidenceDraft = nil
            syncFocusedDiff()
        }
    }
    @Published var selectedFilePath: String? {
        didSet {
            cachedCurrentEvidenceDraft = nil
            syncFocusedDiff()
            syncSelectedHunk(previousSelection: oldValue)
            syncInlineDraftPath(previousSelection: oldValue)
        }
    }

    /// Drop the heavy DERIVED payload when the window closes, but keep the user's
    /// unsubmitted work.
    ///
    /// This is a process-lifetime singleton, and `gh pr diff` output is uncapped on the
    /// load side — the only `prefix(...)` limits in this file are render/report-side.
    /// A large PR's full file list plus every diff string therefore stayed resident for
    /// the rest of the session.
    ///
    /// Deliberately NOT a blanket reset like `MergeConflictResolutionModel`: its
    /// `choicesByHunkID` is cheap to re-pick, whereas `stagedDrafts`, `reviewNote`,
    /// `selectedDecisionMode` and the `inlineDraft*` fields can hold a half-written
    /// multi-comment review. Those survive so a reopen restores the session.
    func releaseHeldState() {
        cancelLoading()
        cancelSubmission()
        // `applyLoadedSnapshot` decides "same PR?" by comparing against the CURRENT
        // snapshot, so nilling it below would make every reopen look like a different PR
        // and wipe exactly the staged drafts this method exists to preserve. Remember the
        // identity first and let the reload fall back to it.
        heldSnapshotIdentity = snapshotIdentity(for: snapshot)
        snapshot = nil
        focusedDiff = ""
        evidenceContext = .empty
        cachedCurrentEvidenceDraft = nil
        repositorySummary = nil
        workingDirectorySummary = nil
        loadErrorMessage = nil
        stagingMessage = nil
    }

    private let runner: any PullRequestReviewRunning
    private let openInEditor: @MainActor (IDESemanticLocation) async -> String?
    private var workingDirectory: String?
    private var loadTask: Task<Void, Never>?
    private var submissionTask: Task<Void, Never>?
    private var loadTaskGeneration = 0
    private var submissionTaskGeneration = 0
    private var editorOpenGeneration = 0
    private var cachedCurrentEvidenceDraft: PullRequestReviewEvidenceDraft?
    /// Identity of the snapshot dropped by `releaseHeldState()`, so the next load can
    /// tell "reopened the same PR" from "switched PR" without holding the snapshot.
    private var heldSnapshotIdentity: String?

    init(
        runner: any PullRequestReviewRunning = PullRequestReviewShellClient(),
        openInEditor: @escaping @MainActor (IDESemanticLocation) async -> String? = { await IDEEditorNavigator.open($0) }
    ) {
        self.runner = runner
        self.openInEditor = openInEditor
    }

    deinit {
        let pendingLoadTask = loadTask
        let pendingSubmissionTask = submissionTask
        pendingLoadTask?.cancel()
        pendingSubmissionTask?.cancel()
    }

    var selectedFile: PullRequestReviewFile? {
        guard let selectedFilePath else { return nil }
        return snapshot?.files.first(where: { $0.path == selectedFilePath })
    }

    var selectedHunk: PullRequestReviewDiffHunk? {
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

    var selectedReviewLocation: IDESemanticLocation? {
        selectedHunk?.location ?? selectedFileLocation
    }

    var currentInlineDraftLocation: IDESemanticLocation? {
        guard let snapshot else { return nil }
        let path = inlineDraftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              snapshot.files.contains(where: { $0.path == path }),
              let line = Int(inlineDraftLine.trimmingCharacters(in: .whitespacesAndNewlines)),
              line > 0 else {
            return nil
        }
        return IDESemanticLocation.repositoryLocation(
            repoRoot: snapshot.repoRoot,
            relativePath: path,
            line: line,
            column: 1
        )
    }

    var canNavigateFiles: Bool {
        snapshot?.files.isEmpty == false
    }

    var canNavigateHunks: Bool {
        (selectedFile?.hunks.count ?? 0) > 1
    }

    var canStageInlineDraft: Bool {
        snapshot != nil && currentInlineDraftInput != nil
    }

    var stagedInlineDrafts: [PullRequestReviewInlineCommentDraft] {
        stagedDrafts.compactMap { stagedDraft in
            if case .inline(let draft) = stagedDraft {
                return draft
            }
            return nil
        }
    }

    var stagedEvidenceDraft: PullRequestReviewEvidenceDraft? {
        stagedDrafts.first {
            if case .evidence = $0 {
                return true
            }
            return false
        }.flatMap { stagedDraft in
            if case .evidence(let draft) = stagedDraft {
                return draft
            }
            return nil
        }
    }

    var currentEvidenceDraft: PullRequestReviewEvidenceDraft? {
        if let cachedCurrentEvidenceDraft {
            return cachedCurrentEvidenceDraft
        }
        guard let snapshot else { return nil }
        let draft = PullRequestReviewDraftFormatter.evidenceDraft(
            snapshot: snapshot,
            context: evidenceContext,
            selectedFocusLocation: selectedReviewLocation
        )
        cachedCurrentEvidenceDraft = draft
        return draft
    }

    var hasStagedEvidenceDraft: Bool {
        stagedDrafts.contains {
            if case .evidence = $0 {
                return true
            }
            return false
        }
    }

    var inlineDraftPreview: String {
        guard let snapshot else {
            return "Load a pull request to preview local comment drafts."
        }
        guard let input = currentInlineDraftInput else {
            return "Set file, line, side, and comment body to preview the same inline draft shape used by yen ide pr-review."
        }
        return PullRequestReviewDraftFormatter.inlineDraft(
            summary: snapshot.summary,
            input: input
        ).preview
    }

    var auditDirectorySummary: String {
        PullRequestReviewAuditPaths.evidenceDirectory(ideStateDirectory: evidenceContext.ideStateDirectory)
            .abbreviatedPath
    }

    var currentDecisionDraft: PullRequestReviewDecisionDraft? {
        guard let snapshot else { return nil }
        let evidenceFilePath = stagedEvidenceDraft.map { draft in
            PullRequestReviewAuditPaths.evidenceFilePath(
                ideStateDirectory: evidenceContext.ideStateDirectory,
                suggestedFileName: draft.suggestedFileName
            )
        }
        return PullRequestReviewDraftFormatter.decisionDraft(
            mode: selectedDecisionMode,
            summary: snapshot.summary,
            repoRoot: snapshot.repoRoot,
            selectedFocusLocation: selectedReviewLocation,
            evidenceFilePath: evidenceFilePath,
            reviewNote: reviewNote
        )
    }

    func prepareForPresentation(workingDirectory: String?) {
        let normalized = Self.normalizedWorkingDirectory(workingDirectory)
        if normalized != self.workingDirectory {
            cancelLoading()
            cancelSubmission()
            prReference = ""
            snapshot = nil
            evidenceContext = .empty
            cachedCurrentEvidenceDraft = nil
            selectedFilePath = nil
            selectedHunkID = nil
            focusedDiff = ""
            loadErrorMessage = nil
            repositorySummary = nil
            resetDraftState(defaultPath: nil)
        }

        self.workingDirectory = normalized
        workingDirectorySummary = normalized.map(\.abbreviatedPath)
    }

    func requestLoad() {
        cancelLoading()
        isLoading = true
        loadErrorMessage = nil
        submissionErrorMessage = nil

        let requestedPR = Self.normalizedPRReference(prReference)
        let workingDirectory = self.workingDirectory
        let runner = self.runner
        loadTaskGeneration += 1
        let taskGeneration = loadTaskGeneration

        loadTask = Task { [weak self] in
            do {
                guard let repoRoot = try await runner.resolveRepositoryRoot(for: workingDirectory) else {
                    throw PullRequestReviewCommandError.notInGitRepository
                }

                async let snapshot = runner.loadPullRequest(
                    requestedPR: requestedPR,
                    repoRoot: repoRoot
                )
                async let evidenceContext = runner.loadEvidenceContext(repoRoot: repoRoot)

                let loadedSnapshot = try await snapshot
                let loadedEvidenceContext = await evidenceContext
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self, self.loadTaskGeneration == taskGeneration else { return }
                    self.applyLoadedSnapshot(loadedSnapshot, evidenceContext: loadedEvidenceContext)
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

    func cancelSubmission() {
        submissionTaskGeneration += 1
        submissionTask?.cancel()
        submissionTask = nil
        isSubmitting = false
        pendingSubmissionConfirmation = nil
    }

    func requestSubmission(_ kind: PullRequestReviewSubmissionKind) {
        submissionErrorMessage = nil
        guard let confirmation = submissionConfirmation(for: kind) else { return }
        pendingSubmissionConfirmation = confirmation
    }

    func dismissSubmissionConfirmation() {
        pendingSubmissionConfirmation = nil
    }

    func confirmSubmission(_ kind: PullRequestReviewSubmissionKind) {
        pendingSubmissionConfirmation = nil
        submit(kind)
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

    func selectHunk(id: String) {
        selectedHunkID = id
    }

    func useSelectedTargetForInlineDraft() {
        inlineDraftPath = selectedReviewLocation?.displayPath ?? selectedFilePath ?? ""
        inlineDraftSide = selectedHunk?.commentSide ?? .right
        if let selectedHunk {
            inlineDraftLine = "\(selectedHunk.commentLine)"
        } else if let line = selectedReviewLocation?.line {
            inlineDraftLine = "\(line)"
        } else {
            inlineDraftLine = ""
        }
    }

    func openSelectedReviewLocationInEditor() async {
        guard let location = selectedReviewLocation else {
            stagingMessage = "Select a file or hunk before opening it in the editor."
            return
        }
        editorOpenGeneration += 1
        let generation = editorOpenGeneration
        let priorMessage = stagingMessage
        let failure = await openInEditor(location)
        guard editorOpenGeneration == generation,
              selectedReviewLocation?.target == location.target,
              stagingMessage == priorMessage else { return }
        stagingMessage = failure
    }

    func openCurrentInlineDraftLocationInEditor() async {
        guard let location = currentInlineDraftLocation else {
            stagingMessage = "Provide a valid file and line before opening the inline target."
            return
        }
        editorOpenGeneration += 1
        let generation = editorOpenGeneration
        let priorMessage = stagingMessage
        let failure = await openInEditor(location)
        guard editorOpenGeneration == generation,
              currentInlineDraftLocation?.target == location.target,
              stagingMessage == priorMessage else { return }
        stagingMessage = failure
    }

    func stageCurrentInlineDraft() {
        submissionErrorMessage = nil
        guard let snapshot, let input = currentInlineDraftInput else {
            stagingMessage = "Load a pull request and complete the inline draft fields before staging."
            return
        }

        let draft = PullRequestReviewDraftFormatter.inlineDraft(
            summary: snapshot.summary,
            input: input
        )
        stagedDrafts.insert(.inline(draft), at: 0)
        inlineDraftLine = ""
        inlineDraftBody = ""
        inlineDraftPath = selectedFilePath ?? input.path
        inlineDraftSide = .right
        stagingMessage = "Staged inline comment locally. Use an explicit post action to submit it."
    }

    func stageEvidenceDraft() {
        submissionErrorMessage = nil
        guard let draft = currentEvidenceDraft else {
            stagingMessage = "Load a pull request before staging evidence."
            return
        }

        if let existingIndex = stagedDrafts.firstIndex(where: {
            if case .evidence = $0 {
                return true
            }
            return false
        }) {
            stagedDrafts[existingIndex] = .evidence(draft)
        } else {
            stagedDrafts.insert(.evidence(draft), at: 0)
        }
        stagingMessage = "Staged local evidence bundle preview. Use an explicit post action to publish it."
    }

    func removeStagedDraft(id: String) {
        submissionErrorMessage = nil
        stagedDrafts.removeAll { $0.id == id }
        if stagedDrafts.isEmpty {
            stagingMessage = "Cleared all local review drafts."
        } else {
            stagingMessage = "Removed staged draft from the local review queue."
        }
    }

    func clearStagedDrafts() {
        submissionErrorMessage = nil
        stagedDrafts = []
        inlineDraftPath = selectedFilePath ?? snapshot?.files.first?.path ?? ""
        inlineDraftLine = ""
        inlineDraftSide = .right
        inlineDraftBody = ""
        stagingMessage = "Cleared all local review drafts."
    }

    func submit(_ kind: PullRequestReviewSubmissionKind) {
        guard let request = submissionRequest(for: kind) else { return }

        cancelSubmission()
        isSubmitting = true
        submissionErrorMessage = nil
        loadErrorMessage = nil
        let runner = self.runner
        submissionTaskGeneration += 1
        let taskGeneration = submissionTaskGeneration

        submissionTask = Task { [weak self] in
            do {
                let result = try await runner.submit(request: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.submissionTaskGeneration == taskGeneration else { return }
                    self.applySubmissionResult(result)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.submissionTaskGeneration == taskGeneration else { return }
                    self.applySubmissionError(error, requestedKind: kind)
                }
            }
        }
    }

    static func adjacentSelection(from paths: [String], current: String?, direction: Int) -> String? {
        guard !paths.isEmpty else { return nil }
        guard let current,
              let index = paths.firstIndex(of: current) else {
            return paths.first
        }

        let nextIndex = min(max(index + direction, 0), paths.count - 1)
        return paths[nextIndex]
    }

    private static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        return NSString(string: workingDirectory).expandingTildeInPath
    }

    private static func normalizedPRReference(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentInlineDraftInput: PullRequestReviewInlineDraftInput? {
        let path = inlineDraftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = inlineDraftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              let snapshot,
              snapshot.files.contains(where: { $0.path == path }),
              let line = Int(inlineDraftLine.trimmingCharacters(in: .whitespacesAndNewlines)),
              line > 0,
              !body.isEmpty else {
            return nil
        }

        return PullRequestReviewInlineDraftInput(
            path: path,
            line: line,
            side: inlineDraftSide,
            body: body
        )
    }

    private func applyLoadedSnapshot(
        _ snapshot: PullRequestReviewSnapshot,
        evidenceContext: PullRequestReviewEvidenceContext
    ) {
        // Falls back to `heldSnapshotIdentity` so a window close (which releases the
        // snapshot) followed by a reopen on the same PR is NOT treated as a PR switch.
        let previousIdentity = snapshotIdentity(for: self.snapshot) ?? heldSnapshotIdentity
        let newIdentity = snapshotIdentity(for: snapshot)
        let shouldResetDraftState = previousIdentity != newIdentity
        heldSnapshotIdentity = nil

        self.snapshot = snapshot
        self.evidenceContext = evidenceContext
        cachedCurrentEvidenceDraft = nil
        repositorySummary = snapshot.repoRoot.abbreviatedPath
        isLoading = false
        loadTask = nil
        loadErrorMessage = nil

        let existingSelection = selectedFilePath
        selectedFilePath = if let existingSelection,
                             snapshot.files.contains(where: { $0.path == existingSelection }) {
            existingSelection
        } else {
            snapshot.files.first?.path
        }
        syncSelectedHunk(previousSelection: nil)
        syncFocusedDiff()

        if shouldResetDraftState {
            resetDraftState(defaultPath: selectedFilePath ?? snapshot.files.first?.path)
        } else {
            stagedDrafts.removeAll { stagedDraft in
                switch stagedDraft {
                case .evidence:
                    return false
                case .inline(let draft):
                    return !snapshot.files.contains(where: { $0.path == draft.path })
                }
            }
            refreshStagedEvidenceDraft()
            if inlineDraftPath.isEmpty ||
                (!snapshot.files.contains(where: { $0.path == inlineDraftPath }) && !hasInlineDraftComposerContent) {
                inlineDraftPath = selectedFilePath ?? snapshot.files.first?.path ?? ""
            }
        }
    }

    private func applyLoadError(_ error: Error) {
        isLoading = false
        loadTask = nil
        if let reviewError = error as? PullRequestReviewCommandError {
            loadErrorMessage = reviewError.errorDescription
        } else {
            loadErrorMessage = error.localizedDescription
        }
        syncFocusedDiff()
    }

    private func applySubmissionResult(_ result: PullRequestReviewSubmissionResult) {
        isSubmitting = false
        submissionTask = nil
        submissionErrorMessage = nil

        if !result.postedInlineDraftIDs.isEmpty {
            stagedDrafts.removeAll { result.postedInlineDraftIDs.contains($0.id) }
        }
        if result.didConsumeStagedEvidenceDraft {
            stagedDrafts.removeAll {
                if case .evidence = $0 {
                    return true
                }
                return false
            }
        }

        if case .decision = result.kind {
            reviewNote = ""
        }

        stagingMessage = submissionSuccessMessage(for: result)
    }

    private func applySubmissionError(_ error: Error, requestedKind: PullRequestReviewSubmissionKind) {
        isSubmitting = false
        submissionTask = nil

        if let submissionError = error as? PullRequestReviewSubmissionError,
           let partialResult = submissionError.partialResult {
            applyPartialSubmissionResult(partialResult)
            submissionErrorMessage = submissionError.message
            stagingMessage = partialSuccessMessage(for: partialResult, requestedKind: requestedKind)
            return
        }

        if let reviewError = error as? PullRequestReviewSubmissionError {
            submissionErrorMessage = reviewError.errorDescription
        } else if let commandError = error as? PullRequestReviewCommandError {
            submissionErrorMessage = commandError.errorDescription
        } else {
            submissionErrorMessage = error.localizedDescription
        }
    }

    private func syncFocusedDiff() {
        focusedDiff = selectedHunk?.diff ?? selectedFile?.diff ?? ""
    }

    private func syncSelectedHunk(previousSelection: String?) {
        guard let file = selectedFile else {
            selectedHunkID = nil
            return
        }

        if previousSelection == selectedFilePath,
           let currentSelection = selectedHunkID,
           file.hunks.contains(where: { $0.id == currentSelection }) {
            return
        }

        selectedHunkID = file.hunks.first?.id
    }

    private func syncInlineDraftPath(previousSelection: String?) {
        let currentSelection = selectedFilePath ?? ""
        if inlineDraftPath.isEmpty {
            inlineDraftPath = currentSelection
            return
        }

        if inlineDraftPath == previousSelection && !hasInlineDraftComposerContent {
            inlineDraftPath = currentSelection
        }
    }

    private func resetDraftState(defaultPath: String?) {
        stagedDrafts = []
        stagingMessage = nil
        submissionErrorMessage = nil
        reviewNote = ""
        selectedDecisionMode = .comment
        pendingSubmissionConfirmation = nil
        inlineDraftPath = defaultPath ?? ""
        inlineDraftLine = ""
        inlineDraftSide = .right
        inlineDraftBody = ""
    }

    private func refreshStagedEvidenceDraft() {
        guard let currentEvidenceDraft,
              let existingIndex = stagedDrafts.firstIndex(where: {
                  if case .evidence = $0 {
                      return true
                  }
                  return false
              }) else {
            return
        }

        stagedDrafts[existingIndex] = .evidence(currentEvidenceDraft)
    }

    private func snapshotIdentity(for snapshot: PullRequestReviewSnapshot?) -> String? {
        guard let snapshot else { return nil }
        return "\(snapshot.repoRoot)#\(snapshot.summary.number)"
    }

    private var hasInlineDraftComposerContent: Bool {
        !inlineDraftLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !inlineDraftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submissionConfirmation(for kind: PullRequestReviewSubmissionKind) -> PullRequestReviewSubmissionConfirmation? {
        guard let snapshot else {
            stagingMessage = "Load a pull request before posting review actions."
            return nil
        }
        guard !isSubmitting else {
            stagingMessage = "A review action is already in progress."
            return nil
        }

        switch kind {
        case .inlineComments:
            guard !stagedInlineDrafts.isEmpty else {
                stagingMessage = "Stage at least one inline comment before posting it."
                return nil
            }
            let count = stagedInlineDrafts.count
            return PullRequestReviewSubmissionConfirmation(
                kind: kind,
                title: "Post \(count) Inline Comment\(count == 1 ? "" : "s")?",
                message: "This writes audit files under \(auditDirectorySummary) and posts the staged inline comment previews to PR #\(snapshot.summary.number).",
                confirmLabel: "Post Comments"
            )

        case .evidenceComment:
            guard stagedEvidenceDraft != nil else {
                stagingMessage = "Stage the evidence bundle before posting it."
                return nil
            }
            return PullRequestReviewSubmissionConfirmation(
                kind: kind,
                title: "Post Evidence Comment?",
                message: "This writes the staged evidence bundle under \(auditDirectorySummary) and posts it as a PR comment on #\(snapshot.summary.number).",
                confirmLabel: "Post Evidence"
            )

        case .decision(let mode):
            let inlineCount = stagedInlineDrafts.count
            let evidenceClause = stagedEvidenceDraft == nil ? "No staged evidence bundle will be attached." : "The staged evidence bundle will be written under \(auditDirectorySummary) and referenced in the submitted review."
            let inlineClause = inlineCount == 0 ? "No staged inline comments are queued." : "This also posts \(inlineCount) staged inline comment\(inlineCount == 1 ? "" : "s") first."
            return PullRequestReviewSubmissionConfirmation(
                kind: kind,
                title: "\(mode.submissionTitle)?",
                message: "\(inlineClause) \(evidenceClause)",
                confirmLabel: mode.submissionTitle
            )
        }
    }

    private func submissionRequest(for kind: PullRequestReviewSubmissionKind) -> PullRequestReviewSubmissionRequest? {
        guard let snapshot else {
            stagingMessage = "Load a pull request before posting review actions."
            return nil
        }

        switch kind {
        case .inlineComments:
            guard !stagedInlineDrafts.isEmpty else {
                stagingMessage = "Stage at least one inline comment before posting it."
                return nil
            }
        case .evidenceComment:
            guard stagedEvidenceDraft != nil else {
                stagingMessage = "Stage the evidence bundle before posting it."
                return nil
            }
        case .decision:
            break
        }

        return PullRequestReviewSubmissionRequest(
            kind: kind,
            snapshot: snapshot,
            selectedFilePath: selectedFilePath,
            selectedFocusLocation: selectedReviewLocation,
            evidenceContext: evidenceContext,
            stagedInlineDrafts: stagedInlineDrafts,
            stagedEvidenceDraft: stagedEvidenceDraft,
            reviewNote: reviewNote
        )
    }

    private func applyPartialSubmissionResult(_ result: PullRequestReviewSubmissionResult) {
        if !result.postedInlineDraftIDs.isEmpty {
            stagedDrafts.removeAll { result.postedInlineDraftIDs.contains($0.id) }
        }
        if result.didPostEvidenceComment {
            stagedDrafts.removeAll {
                if case .evidence = $0 {
                    return true
                }
                return false
            }
        }
    }

    private func submissionSuccessMessage(for result: PullRequestReviewSubmissionResult) -> String {
        guard let snapshot else {
            return "Posted review action."
        }

        switch result.kind {
        case .inlineComments:
            let count = result.postedInlineDraftIDs.count
            return "Posted \(count) inline comment\(count == 1 ? "" : "s") to PR #\(snapshot.summary.number)."
        case .evidenceComment:
            return "Posted the staged evidence comment to PR #\(snapshot.summary.number)."
        case .decision(let mode):
            let inlinePrefix: String
            if result.postedInlineDraftIDs.isEmpty {
                inlinePrefix = ""
            } else {
                inlinePrefix = " after posting \(result.postedInlineDraftIDs.count) inline comment\(result.postedInlineDraftIDs.count == 1 ? "" : "s")"
            }
            return "Submitted \(mode.rawValue) review for PR #\(snapshot.summary.number)\(inlinePrefix)."
        }
    }

    private func partialSuccessMessage(
        for result: PullRequestReviewSubmissionResult,
        requestedKind: PullRequestReviewSubmissionKind
    ) -> String {
        switch requestedKind {
        case .inlineComments, .decision:
            guard !result.postedInlineDraftIDs.isEmpty else {
                return "Review action failed before any staged drafts were posted."
            }
            return "Some review actions completed before the submission failed. Posted \(result.postedInlineDraftIDs.count) inline comment\(result.postedInlineDraftIDs.count == 1 ? "" : "s"); remaining drafts stayed local."
        case .evidenceComment:
            return "The evidence bundle audit file was written, but the PR comment did not complete."
        }
    }
}


#endif
