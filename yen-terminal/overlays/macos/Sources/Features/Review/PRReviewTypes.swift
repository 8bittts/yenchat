#if os(macOS)
import AppKit
import Foundation
import SwiftUI

struct PullRequestReviewSummary: Equatable, Sendable {
    let number: Int
    let title: String
    let url: String
    let author: String
    let baseRefName: String
    let headRefName: String
    let headRefOID: String
    let changedFiles: Int
    let additions: Int
    let deletions: Int
}

struct PullRequestReviewFile: Identifiable, Equatable, Hashable, Sendable {
    let path: String
    let diff: String
    let hunks: [PullRequestReviewDiffHunk]

    var id: String { path }

    init(
        path: String,
        diff: String,
        hunks: [PullRequestReviewDiffHunk] = []
    ) {
        self.path = path
        self.diff = diff
        self.hunks = hunks
    }
}

struct PullRequestReviewDiffHunk: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let index: Int
    let header: String
    let location: IDESemanticLocation
    let commentLine: Int
    let commentSide: PullRequestReviewCommentSide
    let diff: String

    init(
        id: String,
        index: Int,
        header: String,
        location: IDESemanticLocation,
        commentLine: Int? = nil,
        commentSide: PullRequestReviewCommentSide = .right,
        diff: String
    ) {
        self.id = id
        self.index = index
        self.header = header
        self.location = location
        self.commentLine = commentLine ?? location.line ?? 1
        self.commentSide = commentSide
        self.diff = diff
    }
}

struct PullRequestReviewSnapshot: Equatable, Sendable {
    let repoRoot: String
    let summary: PullRequestReviewSummary
    let files: [PullRequestReviewFile]
}

enum PullRequestReviewCommentSide: String, CaseIterable, Identifiable, Sendable {
    case left = "LEFT"
    case right = "RIGHT"

    var id: String { rawValue }
}

enum PullRequestReviewDecisionMode: String, CaseIterable, Identifiable, Sendable {
    case approve = "approve"
    case requestChanges = "request-changes"
    case comment = "comment"

    var id: String { rawValue }

    var heading: String {
        switch self {
        case .approve:
            return "Approve"
        case .requestChanges:
            return "Request Changes"
        case .comment:
            return "Comment"
        }
    }

    var submissionTitle: String {
        switch self {
        case .approve:
            return "Submit Approval"
        case .requestChanges:
            return "Request Changes"
        case .comment:
            return "Post Comment"
        }
    }
}

struct PullRequestReviewVerifySecurityStep: Equatable, Sendable {
    let id: String
    let result: String
    let exitCode: Int
    let summary: String
}

struct PullRequestReviewVerifyStatusSnapshot: Equatable, Sendable {
    let latestStatus: String
    let lastRunAt: String
    let summaryReportPath: String?
    let detailsReportPath: String?
    let semanticReportPath: String?
    let readinessStatus: String
    let readinessReason: String
    let mergeReady: Bool
    let securityStatus: String
    let securityReason: String
    let securityStepCount: Int
    let securityWarningSteps: Int
    let securityFailingSteps: Int
    let securitySteps: [PullRequestReviewVerifySecurityStep]
}

struct PullRequestReviewEvidenceContext: Equatable, Sendable {
    let ideStateDirectory: String
    let latestVerifySummaryPath: String?
    let latestVerifySummaryContents: String?
    let latestVerifySemanticPath: String?
    let latestVerifySemanticContents: String?
    let latestVerifyStatus: PullRequestReviewVerifyStatusSnapshot?
    let recentTimelineEvents: [String]

    init(
        ideStateDirectory: String,
        latestVerifySummaryPath: String?,
        latestVerifySummaryContents: String?,
        latestVerifySemanticPath: String?,
        latestVerifySemanticContents: String?,
        latestVerifyStatus: PullRequestReviewVerifyStatusSnapshot? = nil,
        recentTimelineEvents: [String]
    ) {
        self.ideStateDirectory = ideStateDirectory
        self.latestVerifySummaryPath = latestVerifySummaryPath
        self.latestVerifySummaryContents = latestVerifySummaryContents
        self.latestVerifySemanticPath = latestVerifySemanticPath
        self.latestVerifySemanticContents = latestVerifySemanticContents
        self.latestVerifyStatus = latestVerifyStatus
        self.recentTimelineEvents = recentTimelineEvents
    }

    static let empty = PullRequestReviewEvidenceContext(
        ideStateDirectory: PullRequestReviewLocalEvidenceContextLoader.defaultIDEStateDirectory,
        latestVerifySummaryPath: nil,
        latestVerifySummaryContents: nil,
        latestVerifySemanticPath: nil,
        latestVerifySemanticContents: nil,
        latestVerifyStatus: nil,
        recentTimelineEvents: []
    )
}

struct PullRequestReviewEvidenceDraft: Identifiable, Equatable, Sendable {
    let suggestedFileName: String
    let preview: String
    let latestVerifySummaryPath: String?
    let latestVerifySemanticPath: String?

    var id: String { "evidence" }
}

struct PullRequestReviewInlineCommentDraft: Identifiable, Equatable, Sendable {
    let id: String
    let location: IDESemanticLocation
    let side: PullRequestReviewCommentSide
    let body: String
    let suggestedFileName: String
    let preview: String

    init(
        id: String,
        path: String,
        line: Int,
        side: PullRequestReviewCommentSide,
        body: String,
        suggestedFileName: String,
        preview: String
    ) {
        self.init(
            id: id,
            location: IDESemanticLocation(
                path: path,
                relativePath: path,
                line: line,
                column: 1
            ),
            side: side,
            body: body,
            suggestedFileName: suggestedFileName,
            preview: preview
        )
    }

    init(
        id: String,
        location: IDESemanticLocation,
        side: PullRequestReviewCommentSide,
        body: String,
        suggestedFileName: String,
        preview: String
    ) {
        self.id = id
        self.location = location
        self.side = side
        self.body = body
        self.suggestedFileName = suggestedFileName
        self.preview = preview
    }

    var path: String {
        location.relativePath ?? location.displayPath
    }

    var line: Int {
        location.line ?? 1
    }
}

struct PullRequestReviewDecisionDraft: Equatable, Sendable {
    let suggestedFileName: String
    let preview: String
}

enum PullRequestReviewStagedDraft: Identifiable, Equatable, Sendable {
    case evidence(PullRequestReviewEvidenceDraft)
    case inline(PullRequestReviewInlineCommentDraft)

    var id: String {
        switch self {
        case .evidence:
            return "evidence"
        case .inline(let draft):
            return draft.id
        }
    }

    var title: String {
        switch self {
        case .evidence:
            return "Evidence Bundle"
        case .inline(let draft):
            return "\(draft.location.target) \(draft.side.rawValue)"
        }
    }

    var subtitle: String {
        switch self {
        case .evidence(let draft):
            if let verifyPath = draft.latestVerifySummaryPath {
                return "Preview mirrors \(verifyPath)"
            }
            return "Local-only staged markdown preview"
        case .inline(let draft):
            return draft.suggestedFileName
        }
    }

    var suggestedFileName: String {
        switch self {
        case .evidence(let draft):
            return draft.suggestedFileName
        case .inline(let draft):
            return draft.suggestedFileName
        }
    }

    var preview: String {
        switch self {
        case .evidence(let draft):
            return draft.preview
        case .inline(let draft):
            return draft.preview
        }
    }
}

enum PullRequestReviewCommandError: LocalizedError {
    case noWorkingDirectory
    case notInGitRepository
    case toolUnavailable(String)
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noWorkingDirectory:
            return "No working directory is available for the active terminal."
        case .notInGitRepository:
            return "This terminal is not inside a git repository with GitHub PR context."
        case .toolUnavailable(let tool):
            return "\(tool) is required to load desktop PR review."
        case .commandFailed(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}

enum PullRequestReviewSubmissionKind: Equatable, Sendable {
    case inlineComments
    case evidenceComment
    case decision(PullRequestReviewDecisionMode)
}

struct PullRequestReviewSubmissionRequest: Sendable {
    let kind: PullRequestReviewSubmissionKind
    let snapshot: PullRequestReviewSnapshot
    let selectedFilePath: String?
    let selectedFocusLocation: IDESemanticLocation?
    let evidenceContext: PullRequestReviewEvidenceContext
    let stagedInlineDrafts: [PullRequestReviewInlineCommentDraft]
    let stagedEvidenceDraft: PullRequestReviewEvidenceDraft?
    let reviewNote: String
}

struct PullRequestReviewSubmissionResult: Sendable {
    let kind: PullRequestReviewSubmissionKind
    let postedInlineDraftIDs: [String]
    let didPostEvidenceComment: Bool
    let didConsumeStagedEvidenceDraft: Bool
    let evidenceFilePath: String?
    let decisionFilePath: String?

    var hasProgress: Bool {
        !postedInlineDraftIDs.isEmpty || didPostEvidenceComment || didConsumeStagedEvidenceDraft || decisionFilePath != nil
    }
}

struct PullRequestReviewSubmissionError: LocalizedError {
    let message: String
    let partialResult: PullRequestReviewSubmissionResult?

    var errorDescription: String? { message }
}

struct PullRequestReviewSubmissionConfirmation: Identifiable, Equatable, Sendable {
    let kind: PullRequestReviewSubmissionKind
    let title: String
    let message: String
    let confirmLabel: String

    var id: String {
        switch kind {
        case .inlineComments:
            return "inline-comments"
        case .evidenceComment:
            return "evidence-comment"
        case .decision(let mode):
            return "decision-\(mode.rawValue)"
        }
    }
}

protocol PullRequestReviewRunning: Sendable {
    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String?
    func loadPullRequest(requestedPR: String?, repoRoot: String) async throws -> PullRequestReviewSnapshot
    func loadEvidenceContext(repoRoot: String) async -> PullRequestReviewEvidenceContext
    func submit(request: PullRequestReviewSubmissionRequest) async throws -> PullRequestReviewSubmissionResult
}

struct PullRequestReviewDiffBlock: Equatable, Sendable {
    let keys: [String]
    let diff: String
}

struct PullRequestReviewDiffIndex: Equatable, Sendable {
    let blocks: [PullRequestReviewDiffBlock]
    let paths: [String]
    private let blocksByPath: [String: PullRequestReviewDiffBlock]

    init(blocks: [PullRequestReviewDiffBlock]) {
        self.blocks = blocks

        var orderedPaths: [String] = []
        var seenPrimaryPaths: Set<String> = []
        var indexedBlocks: [String: PullRequestReviewDiffBlock] = [:]

        for block in blocks {
            if let primaryPath = block.keys.first,
               !seenPrimaryPaths.contains(primaryPath) {
                orderedPaths.append(primaryPath)
                seenPrimaryPaths.insert(primaryPath)
            }

            for key in block.keys where indexedBlocks[key] == nil {
                indexedBlocks[key] = block
            }
        }

        self.paths = orderedPaths
        self.blocksByPath = indexedBlocks
    }

    func focusedDiff(for path: String) -> String? {
        blocksByPath[path]?.diff
    }
}

#endif
