#if os(macOS)
import AppKit
import Foundation
import SwiftUI

struct PullRequestReviewShellClient: PullRequestReviewRunning {
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
                failureSummary: "Unable to resolve the repository root for desktop PR review."
            )
        } catch PullRequestReviewCommandError.commandFailed {
            return nil
        }

        let repoRoot = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return repoRoot.isEmpty ? nil : repoRoot
    }

    func loadPullRequest(requestedPR: String?, repoRoot: String) async throws -> PullRequestReviewSnapshot {
        let requestedTokens = prReferenceTokens(for: requestedPR)

        let metadataOutput = try await runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh", "pr", "view"] + requestedTokens + [
                "--json",
                "number,title,url,headRefName,baseRefName,headRefOid,author,changedFiles,additions,deletions",
            ],
            currentDirectory: repoRoot,
            toolName: "GitHub CLI (gh)",
            failureSummary: "Unable to load pull request metadata."
        )

        let diffOutput = try await runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh", "pr", "diff"] + requestedTokens,
            currentDirectory: repoRoot,
            toolName: "GitHub CLI (gh)",
            failureSummary: "Unable to load the focused diff for this pull request."
        )

        let response = try decodeMetadata(from: metadataOutput.stdout)
        let diffIndex = PullRequestReviewDiffParser.index(diffOutput.stdout)
        let filePaths = diffIndex.paths

        let files = filePaths.map { path in
            let focusedDiff = PullRequestReviewDiffParser.focusedDiff(for: path, from: diffIndex)
                ?? "No focused diff block found for \(path)."
            return PullRequestReviewFile(
                path: path,
                diff: focusedDiff,
                hunks: PullRequestReviewDiffParser.hunks(
                    for: path,
                    repoRoot: repoRoot,
                    from: diffIndex
                )
            )
        }

        return PullRequestReviewSnapshot(
            repoRoot: repoRoot,
            summary: PullRequestReviewSummary(
                number: response.number,
                title: response.title,
                url: response.url,
                author: response.author.login,
                baseRefName: response.baseRefName,
                headRefName: response.headRefName,
                headRefOID: response.headRefOid,
                changedFiles: response.changedFiles,
                additions: response.additions,
                deletions: response.deletions
            ),
            files: files
        )
    }

    func loadEvidenceContext(repoRoot: String) async -> PullRequestReviewEvidenceContext {
        await Task.detached(priority: .utility) {
            PullRequestReviewLocalEvidenceContextLoader.load(repoRoot: repoRoot)
        }.value
    }

    func submit(request: PullRequestReviewSubmissionRequest) async throws -> PullRequestReviewSubmissionResult {
        let ideStateDirectory = request.evidenceContext.ideStateDirectory
        var result = PullRequestReviewSubmissionResult(
            kind: request.kind,
            postedInlineDraftIDs: [],
            didPostEvidenceComment: false,
            didConsumeStagedEvidenceDraft: false,
            evidenceFilePath: nil,
            decisionFilePath: nil
        )

        do {
            try PullRequestReviewAuditWriter.ensureStateDirectories(ideStateDirectory: ideStateDirectory)

            switch request.kind {
            case .inlineComments:
                try await submitInlineDrafts(request: request, result: &result)
            case .evidenceComment:
                try await submitEvidenceDraft(request: request, result: &result)
            case .decision(let mode):
                try await submitReviewDecision(request: request, mode: mode, result: &result)
            }

            return result
        } catch let error as PullRequestReviewSubmissionError {
            throw error
        } catch let error as PullRequestReviewCommandError {
            throw PullRequestReviewSubmissionError(
                message: error.errorDescription ?? error.localizedDescription,
                partialResult: result.hasProgress ? result : nil
            )
        } catch {
            throw PullRequestReviewSubmissionError(
                message: error.localizedDescription,
                partialResult: result.hasProgress ? result : nil
            )
        }
    }

    private func submitInlineDrafts(
        request: PullRequestReviewSubmissionRequest,
        result: inout PullRequestReviewSubmissionResult
    ) async throws {
        let ideStateDirectory = request.evidenceContext.ideStateDirectory
        try await postInlineComments(
            request.stagedInlineDrafts,
            summary: request.snapshot.summary,
            repoRoot: request.snapshot.repoRoot,
            ideStateDirectory: ideStateDirectory,
            result: &result
        )
        try PullRequestReviewAuditWriter.appendTimeline(
            event: "pr-review",
            projectRoot: request.snapshot.repoRoot,
            status: "pr=\(request.snapshot.summary.number)",
            detail: "file=\(timelineSelectionDetail(for: request));evidence=0;post=1",
            ideStateDirectory: ideStateDirectory
        )
    }

    private func submitEvidenceDraft(
        request: PullRequestReviewSubmissionRequest,
        result: inout PullRequestReviewSubmissionResult
    ) async throws {
        let ideStateDirectory = request.evidenceContext.ideStateDirectory
        guard let stagedEvidenceDraft = request.stagedEvidenceDraft else {
            throw PullRequestReviewSubmissionError(
                message: "Stage an evidence bundle before posting it.",
                partialResult: result.hasProgress ? result : nil
            )
        }

        let evidencePath = PullRequestReviewAuditPaths.evidenceFilePath(
            ideStateDirectory: ideStateDirectory,
            suggestedFileName: stagedEvidenceDraft.suggestedFileName
        )
        try PullRequestReviewAuditWriter.write(text: stagedEvidenceDraft.preview, to: evidencePath)
        result = PullRequestReviewSubmissionResult(
            kind: request.kind,
            postedInlineDraftIDs: [],
            didPostEvidenceComment: false,
            didConsumeStagedEvidenceDraft: false,
            evidenceFilePath: evidencePath,
            decisionFilePath: nil
        )

        try await postPullRequestComment(
            prNumber: request.snapshot.summary.number,
            repoRoot: request.snapshot.repoRoot,
            bodyFilePath: evidencePath,
            failureSummary: "Unable to post the staged evidence comment."
        )
        result = PullRequestReviewSubmissionResult(
            kind: request.kind,
            postedInlineDraftIDs: [],
            didPostEvidenceComment: true,
            didConsumeStagedEvidenceDraft: true,
            evidenceFilePath: evidencePath,
            decisionFilePath: nil
        )

        try PullRequestReviewAuditWriter.appendTimeline(
            event: "pr-evidence",
            projectRoot: request.snapshot.repoRoot,
            status: "pr=\(request.snapshot.summary.number)",
            detail: "file=\(timelineSelectionDetail(for: request));path=\(evidencePath)",
            ideStateDirectory: ideStateDirectory
        )
        try PullRequestReviewAuditWriter.appendTimeline(
            event: "pr-review",
            projectRoot: request.snapshot.repoRoot,
            status: "pr=\(request.snapshot.summary.number)",
            detail: "file=\(timelineSelectionDetail(for: request));evidence=1;post=1",
            ideStateDirectory: ideStateDirectory
        )
    }

    private func submitReviewDecision(
        request: PullRequestReviewSubmissionRequest,
        mode: PullRequestReviewDecisionMode,
        result: inout PullRequestReviewSubmissionResult
    ) async throws {
        let ideStateDirectory = request.evidenceContext.ideStateDirectory
        try await postInlineComments(
            request.stagedInlineDrafts,
            summary: request.snapshot.summary,
            repoRoot: request.snapshot.repoRoot,
            ideStateDirectory: ideStateDirectory,
            result: &result
        )

        var evidencePath: String?
        if let stagedEvidenceDraft = request.stagedEvidenceDraft {
            let path = PullRequestReviewAuditPaths.evidenceFilePath(
                ideStateDirectory: ideStateDirectory,
                suggestedFileName: stagedEvidenceDraft.suggestedFileName
            )
            try PullRequestReviewAuditWriter.write(text: stagedEvidenceDraft.preview, to: path)
            evidencePath = path
            try PullRequestReviewAuditWriter.appendTimeline(
                event: "pr-evidence",
                projectRoot: request.snapshot.repoRoot,
                status: "pr=\(request.snapshot.summary.number)",
                detail: "file=\(timelineSelectionDetail(for: request));path=\(path)",
                ideStateDirectory: ideStateDirectory
            )
        }

        let decisionDraft = PullRequestReviewDraftFormatter.decisionDraft(
            mode: mode,
            summary: request.snapshot.summary,
            repoRoot: request.snapshot.repoRoot,
            selectedFocusLocation: request.selectedFocusLocation,
            evidenceFilePath: evidencePath,
            reviewNote: request.reviewNote
        )
        let decisionPath = PullRequestReviewAuditPaths.evidenceFilePath(
            ideStateDirectory: ideStateDirectory,
            suggestedFileName: decisionDraft.suggestedFileName
        )
        try PullRequestReviewAuditWriter.write(text: decisionDraft.preview, to: decisionPath)
        try await submitDecision(
            mode: mode,
            prNumber: request.snapshot.summary.number,
            repoRoot: request.snapshot.repoRoot,
            bodyFilePath: decisionPath
        )

        result = PullRequestReviewSubmissionResult(
            kind: request.kind,
            postedInlineDraftIDs: result.postedInlineDraftIDs,
            didPostEvidenceComment: false,
            didConsumeStagedEvidenceDraft: evidencePath != nil,
            evidenceFilePath: evidencePath,
            decisionFilePath: decisionPath
        )

        try PullRequestReviewAuditWriter.appendTimeline(
            event: "pr-decision",
            projectRoot: request.snapshot.repoRoot,
            status: "pr=\(request.snapshot.summary.number);mode=\(mode.rawValue)",
            detail: "file=\(timelineSelectionDetail(for: request));post=1",
            ideStateDirectory: ideStateDirectory
        )
        try PullRequestReviewAuditWriter.appendTimeline(
            event: "pr-review",
            projectRoot: request.snapshot.repoRoot,
            status: "pr=\(request.snapshot.summary.number)",
            detail: "file=\(timelineSelectionDetail(for: request));evidence=\(evidencePath == nil ? 0 : 1);post=1",
            ideStateDirectory: ideStateDirectory
        )
    }

    private func prReferenceTokens(for requestedPR: String?) -> [String] {
        let trimmed = requestedPR?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private func decodeMetadata(from rawJSON: String) throws -> PullRequestMetadataResponse {
        let data = Data(rawJSON.utf8)
        do {
            return try JSONDecoder().decode(PullRequestMetadataResponse.self, from: data)
        } catch {
            throw PullRequestReviewCommandError.invalidResponse(
                "GitHub CLI returned unexpected pull request metadata."
            )
        }
    }

    private func postInlineComments(
        _ drafts: [PullRequestReviewInlineCommentDraft],
        summary: PullRequestReviewSummary,
        repoRoot: String,
        ideStateDirectory: String,
        result: inout PullRequestReviewSubmissionResult
    ) async throws {
        guard !drafts.isEmpty else { return }

        guard let repoSlug = repoSlug(from: summary.url) else {
            throw PullRequestReviewSubmissionError(
                message: "Unable to resolve the GitHub repository slug for inline comment posting.",
                partialResult: result.hasProgress ? result : nil
            )
        }

        for draft in drafts {
            let inlineFilePath = PullRequestReviewAuditPaths.evidenceFilePath(
                ideStateDirectory: ideStateDirectory,
                suggestedFileName: draft.suggestedFileName
            )
            try PullRequestReviewAuditWriter.write(text: draft.preview, to: inlineFilePath)

            try await postInlineComment(
                repoSlug: repoSlug,
                summary: summary,
                repoRoot: repoRoot,
                draft: draft
            )

            result = PullRequestReviewSubmissionResult(
                kind: result.kind,
                postedInlineDraftIDs: result.postedInlineDraftIDs + [draft.id],
                didPostEvidenceComment: result.didPostEvidenceComment,
                didConsumeStagedEvidenceDraft: result.didConsumeStagedEvidenceDraft,
                evidenceFilePath: result.evidenceFilePath,
                decisionFilePath: result.decisionFilePath
            )

            try PullRequestReviewAuditWriter.appendTimeline(
                event: "pr-inline-comment",
                projectRoot: repoRoot,
                status: "pr=\(summary.number);posted=yes",
                detail: "path=\(draft.path);line=\(draft.line);location=\(draft.location.target);side=\(draft.side.rawValue)",
                ideStateDirectory: ideStateDirectory
            )
        }
    }

    private func timelineSelectionDetail(for request: PullRequestReviewSubmissionRequest) -> String {
        request.selectedFocusLocation?.target ?? request.selectedFilePath ?? ""
    }

    private func postInlineComment(
        repoSlug: String,
        summary: PullRequestReviewSummary,
        repoRoot: String,
        draft: PullRequestReviewInlineCommentDraft
    ) async throws {
        _ = try await runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: Self.inlineCommentArguments(
                repoSlug: repoSlug,
                summary: summary,
                draft: draft
            ),
            currentDirectory: repoRoot,
            toolName: "GitHub CLI (gh)",
            failureSummary: "Unable to post inline comment for \(draft.path):\(draft.line)."
        )
    }

    static func inlineCommentArguments(
        repoSlug: String,
        summary: PullRequestReviewSummary,
        draft: PullRequestReviewInlineCommentDraft
    ) -> [String] {
        [
            "gh",
            "api",
            "repos/\(repoSlug)/pulls/\(summary.number)/comments",
            "-f",
            "body=\(draft.body)",
            "-f",
            "commit_id=\(summary.headRefOID)",
            "-f",
            "path=\(draft.path)",
            "-F",
            "line=\(draft.line)",
            "-f",
            "side=\(draft.side.rawValue)",
        ]
    }

    private func postPullRequestComment(
        prNumber: Int,
        repoRoot: String,
        bodyFilePath: String,
        failureSummary: String
    ) async throws {
        _ = try await runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh", "pr", "comment", "\(prNumber)", "--body-file", bodyFilePath],
            currentDirectory: repoRoot,
            toolName: "GitHub CLI (gh)",
            failureSummary: failureSummary
        )
    }

    private func submitDecision(
        mode: PullRequestReviewDecisionMode,
        prNumber: Int,
        repoRoot: String,
        bodyFilePath: String
    ) async throws {
        switch mode {
        case .approve:
            _ = try await runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["gh", "pr", "review", "\(prNumber)", "--approve", "--body-file", bodyFilePath],
                currentDirectory: repoRoot,
                toolName: "GitHub CLI (gh)",
                failureSummary: "Unable to submit the approval review."
            )
        case .requestChanges:
            _ = try await runCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["gh", "pr", "review", "\(prNumber)", "--request-changes", "--body-file", bodyFilePath],
                currentDirectory: repoRoot,
                toolName: "GitHub CLI (gh)",
                failureSummary: "Unable to submit the request-changes review."
            )
        case .comment:
            try await postPullRequestComment(
                prNumber: prNumber,
                repoRoot: repoRoot,
                bodyFilePath: bodyFilePath,
                failureSummary: "Unable to post the review summary comment."
            )
        }
    }

    private func repoSlug(from pullRequestURL: String) -> String? {
        guard let url = URL(string: pullRequestURL) else { return nil }
        let components = url.path.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return nil }
        return "\(components[0])/\(components[1])"
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectory: String,
        toolName: String,
        failureSummary: String
    ) async throws -> ReviewCommandOutput {
        let output = try await IDEBlockingProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectory: currentDirectory,
            toolUnavailable: PullRequestReviewCommandError.toolUnavailable(toolName),
            commandFailed: { detail in
                let message = detail.isEmpty ? failureSummary : "\(failureSummary)\n\(detail)"
                return PullRequestReviewCommandError.commandFailed(message)
            }
        )
        return ReviewCommandOutput(stdout: output.stdout)
    }
}

private struct PullRequestMetadataResponse: Decodable {
    struct Author: Decodable {
        let login: String
    }

    let number: Int
    let title: String
    let url: String
    let headRefName: String
    let baseRefName: String
    let headRefOid: String
    let author: Author
    let changedFiles: Int
    let additions: Int
    let deletions: Int
}

#endif
