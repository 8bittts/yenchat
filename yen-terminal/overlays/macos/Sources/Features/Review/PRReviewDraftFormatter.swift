#if os(macOS)
import AppKit
import Foundation
import SwiftUI

struct PullRequestReviewInlineDraftInput: Equatable, Sendable {
    let path: String
    let line: Int
    let side: PullRequestReviewCommentSide
    let body: String
}

enum PullRequestReviewDraftFormatter {
    private static func verifyStatusSectionLines(
        snapshot: PullRequestReviewVerifyStatusSnapshot
    ) -> [String] {
        var lines: [String] = [
            "## Latest Verify Readiness + Security Snapshot",
            "",
            "- Latest status: \(snapshot.latestStatus)",
            "- Readiness: \(snapshot.readinessStatus)",
            "- Merge ready: \(snapshot.mergeReady ? "yes" : "no")",
            "- Readiness note: \(snapshot.readinessReason)",
            "- Security: \(snapshot.securityStatus)",
            "- Security note: \(snapshot.securityReason)",
            "- Security counts: \(snapshot.securityStepCount) total / \(snapshot.securityWarningSteps) warning / \(snapshot.securityFailingSteps) blocking",
            "- Last verify run: \(snapshot.lastRunAt.isEmpty ? "never" : snapshot.lastRunAt)",
            "- Summary report: \(snapshot.summaryReportPath ?? "missing")",
            "- Details report: \(snapshot.detailsReportPath ?? "missing")",
            "- Semantic report: \(snapshot.semanticReportPath ?? "missing")",
        ]

        if snapshot.securitySteps.isEmpty {
            lines.append("- Security step: none recorded")
        } else {
            for step in snapshot.securitySteps.prefix(12) {
                var line = "- Security step: \(step.id) | result=\(step.result) | exit=\(step.exitCode)"
                if !step.summary.isEmpty {
                    line += " | \(step.summary)"
                }
                lines.append(line)
            }
        }

        return lines
    }

    static func evidenceDraft(
        snapshot: PullRequestReviewSnapshot,
        context: PullRequestReviewEvidenceContext,
        selectedFocusLocation: IDESemanticLocation?,
        now: Date = Date()
    ) -> PullRequestReviewEvidenceDraft {
        var lines: [String] = [
            "# YEN IDE PR Review Evidence",
            "",
            "- Generated: \(ReviewWorkspaceTimestamps.isoNow(date: now))",
            "- Project root: \(snapshot.repoRoot)",
            "- PR: #\(snapshot.summary.number)",
            "- Title: \(snapshot.summary.title)",
            "- URL: \(snapshot.summary.url)",
            "- Author: \(snapshot.summary.author)",
            "- Base -> Head: \(snapshot.summary.baseRefName) -> \(snapshot.summary.headRefName)",
            "- Diff stats: \(snapshot.summary.additions) additions, \(snapshot.summary.deletions) deletions, \(snapshot.summary.changedFiles) files",
        ]

        if let selectedFocusLocation {
            lines.append("- Focus file: \(selectedFocusLocation.displayPath)")
            lines.append("- Focus target: \(selectedFocusLocation.target)")
        }

        lines.append("")
        lines.append("## Changed Files")
        lines.append("")
        if snapshot.files.isEmpty {
            lines.append("- No changed files reported.")
        } else {
            for file in snapshot.files.prefix(120) {
                lines.append("- \(file.path)")
            }
        }
        lines.append("")

        if let latestVerifyStatus = context.latestVerifyStatus {
            lines.append(contentsOf: verifyStatusSectionLines(snapshot: latestVerifyStatus))
            lines.append("")
        }

        if let latestVerifySummaryPath = context.latestVerifySummaryPath, !latestVerifySummaryPath.isEmpty {
            lines.append("## Latest Verify Summary Path")
            lines.append("")
            lines.append("- \(latestVerifySummaryPath)")
            lines.append("")

            if let latestVerifySummaryContents = context.latestVerifySummaryContents,
               !latestVerifySummaryContents.isEmpty {
                lines.append("## Latest Verify Summary (TSV)")
                lines.append("")
                lines.append("```tsv")
                lines.append(latestVerifySummaryContents)
                lines.append("```")
                lines.append("")
            }
        }

        if let latestVerifySemanticPath = context.latestVerifySemanticPath, !latestVerifySemanticPath.isEmpty {
            lines.append("## Latest Verify Semantic Report Path")
            lines.append("")
            lines.append("- \(latestVerifySemanticPath)")
            lines.append("")

            if let latestVerifySemanticContents = context.latestVerifySemanticContents,
               !latestVerifySemanticContents.isEmpty {
                lines.append("## Latest Verify Semantic Targets (TSV)")
                lines.append("")
                lines.append("```tsv")
                lines.append(latestVerifySemanticContents)
                lines.append("```")
                lines.append("")
            }
        }

        if !context.recentTimelineEvents.isEmpty {
            lines.append("## Recent IDE Timeline Events")
            lines.append("")
            lines.append("```text")
            lines.append(context.recentTimelineEvents.joined(separator: "\n"))
            lines.append("```")
            lines.append("")
        }

        return PullRequestReviewEvidenceDraft(
            suggestedFileName: "pr-\(snapshot.summary.number)-\(ReviewWorkspaceTimestamps.compactTimestamp(date: now)).md",
            preview: lines.joined(separator: "\n"),
            latestVerifySummaryPath: context.latestVerifySummaryPath,
            latestVerifySemanticPath: context.latestVerifySemanticPath
        )
    }

    static func inlineDraft(
        summary: PullRequestReviewSummary,
        input: PullRequestReviewInlineDraftInput,
        now: Date = Date()
    ) -> PullRequestReviewInlineCommentDraft {
        let suggestedFileName = "pr-\(summary.number)-inline-\(ReviewWorkspaceTimestamps.compactTimestamp(date: now)).md"
        let location = IDESemanticLocation(
            path: input.path,
            relativePath: input.path,
            line: input.line,
            column: 1
        )
        let preview = [
            "Inline review comment for PR #\(summary.number)",
            "",
            "- File: \(input.path)",
            "- Line: \(input.line)",
            "- Location: \(location.target)",
            "- Side: \(input.side.rawValue)",
            "- URL: \(summary.url)",
            "",
            input.body,
        ].joined(separator: "\n")

        return PullRequestReviewInlineCommentDraft(
            id: UUID().uuidString,
            location: location,
            side: input.side,
            body: input.body,
            suggestedFileName: suggestedFileName,
            preview: preview
        )
    }

    static func decisionDraft(
        mode: PullRequestReviewDecisionMode,
        summary: PullRequestReviewSummary,
        repoRoot: String,
        selectedFocusLocation: IDESemanticLocation?,
        evidenceFilePath: String?,
        reviewNote: String,
        now: Date = Date()
    ) -> PullRequestReviewDecisionDraft {
        var lines: [String] = [
            "[\(mode.heading)] PR #\(summary.number): \(summary.title)",
            "",
        ]

        if let selectedFocusLocation {
            lines.append("- Focus file: \(selectedFocusLocation.displayPath)")
            lines.append("- Focus target: \(selectedFocusLocation.target)")
        }
        if let evidenceFilePath, !evidenceFilePath.isEmpty {
            lines.append("- Evidence bundle: \(evidenceFilePath)")
        }
        lines.append("- Project root: \(repoRoot)")
        lines.append("- Generated: \(ReviewWorkspaceTimestamps.isoNow(date: now))")
        lines.append("")

        let trimmedReviewNote = reviewNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReviewNote.isEmpty {
            lines.append(trimmedReviewNote)
            lines.append("")
        }

        switch mode {
        case .approve:
            lines.append("Verification and targeted review checks look good from this terminal-native review pass.")
        case .requestChanges:
            lines.append("Please address the highlighted issues before merge. See focus file and evidence for context.")
        case .comment:
            lines.append("Review context attached for visibility. Leaving this as a comment-only pass.")
        }

        lines.append("")
        lines.append("PR: \(summary.url)")

        return PullRequestReviewDecisionDraft(
            suggestedFileName: "pr-\(summary.number)-decision-\(mode.rawValue)-\(ReviewWorkspaceTimestamps.compactTimestamp(date: now)).md",
            preview: lines.joined(separator: "\n")
        )
    }
}

#endif
