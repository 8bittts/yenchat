#if os(macOS)
import AppKit
import SwiftUI

struct PullRequestReviewView: View {
    @ObservedObject var model: PullRequestReviewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert(
            model.pendingSubmissionConfirmation?.title ?? "",
            isPresented: submissionConfirmationIsPresented,
            presenting: model.pendingSubmissionConfirmation
        ) { confirmation in
            Button(confirmation.confirmLabel, role: .destructive) {
                model.confirmSubmission(confirmation.kind)
            }
            Button("Cancel", role: .cancel) {
                model.dismissSubmissionConfirmation()
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var submissionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingSubmissionConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissSubmissionConfirmation()
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PR Review")
                        .font(YENTypography.title.weight(.semibold))
                    Text(
                        model.repositorySummary
                            ?? model.workingDirectorySummary
                            ?? "Open this workspace from a repo-backed terminal tab."
                    )
                    .font(YENTypography.callout)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    TextField(
                        "PR number or URL (empty = current branch)",
                        text: $model.prReference
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 280, idealWidth: 340)

                    Button(model.isLoading ? "Loading..." : "Load") {
                        model.requestLoad()
                    }
                    .disabled(model.isLoading || model.isSubmitting)
                }
            }

            if let snapshot = model.snapshot {
                reviewSummary(snapshot.summary)
            } else {
                Text(
                    "This desktop review workspace loads pull request metadata, changed files, and focused diffs from the active repo, then posts only through explicit confirmed review actions."
                )
                .font(YENTypography.callout)
                .foregroundColor(.secondary)
            }

            if let loadErrorMessage = model.loadErrorMessage {
                ReviewChrome.statusBanner(message: loadErrorMessage, isError: true)
            } else if model.snapshot == nil {
                ReviewChrome.statusBanner(
                    message: "Leave the field empty to load the pull request for the current branch, or enter a PR number / URL explicitly.",
                    isError: false
                )
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.snapshot == nil {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                Text("Loading pull request review context...")
                    .font(YENTypography.body)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else if let snapshot = model.snapshot {
            HSplitView {
                fileList(snapshot: snapshot)
                    .frame(minWidth: ReviewChrome.fileListMinWidth, idealWidth: ReviewChrome.fileListIdealWidth)

                diffDetail(snapshot: snapshot)
                    .frame(minWidth: ReviewChrome.detailMinWidth, idealWidth: ReviewChrome.detailIdealWidth)

                stagingSidebar(snapshot: snapshot)
                    .frame(minWidth: ReviewChrome.sidebarMinWidth, idealWidth: ReviewChrome.sidebarIdealWidth)
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(YENTypography.largeTitle.weight(.medium))
                    .foregroundColor(.secondary)
                Text("No Pull Request Loaded")
                    .font(YENTypography.sectionTitle.weight(.semibold))
                Text("Use the active terminal repo context and load the current branch PR or an explicit PR number.")
                    .font(YENTypography.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private func fileList(snapshot: PullRequestReviewSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Files")
                        .font(YENTypography.body.weight(.semibold))
                    Text("\(snapshot.files.count) changed")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List(snapshot.files, selection: $model.selectedFilePath) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .font(YENTypography.body.weight(.medium))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(file.hunks.isEmpty ? "Focused diff" : "\(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s")")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 3)
                .tag(Optional(file.path))
            }
            .listStyle(.sidebar)
        }
    }

    private func diffDetail(snapshot: PullRequestReviewSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedReviewLocation?.target ?? model.selectedFile?.path ?? "Focused Diff")
                        .font(YENTypography.body.weight(.semibold))
                        .lineLimit(2)
                    Text("Raw Diff")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                    if let selectedHunk = model.selectedHunk {
                        Text(selectedHunk.header)
                            .font(YENTypography.secondary)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Drafts stay local until you explicitly post comments, evidence, or a review decision.")
                            .font(YENTypography.secondary)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button("Previous") {
                    model.selectPreviousFile()
                }
                .disabled(!model.canNavigateFiles)

                Button("Next") {
                    model.selectNextFile()
                }
                .disabled(!model.canNavigateFiles)

                Button("Previous Hunk") {
                    model.selectPreviousHunk()
                }
                .disabled(!model.canNavigateHunks)

                Button("Next Hunk") {
                    model.selectNextHunk()
                }
                .disabled(!model.canNavigateHunks)

                Button("Open in Editor") {
                    Task { await model.openSelectedReviewLocationInEditor() }
                }
                .disabled(model.selectedReviewLocation == nil || model.isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if model.focusedDiff.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 40)
                    Text("No focused diff available.")
                        .font(YENTypography.body.weight(.medium))
                    Text("Select a file from the sidebar to inspect its patch or focused hunk preview.")
                        .font(YENTypography.callout)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let file = model.selectedFile, !file.hunks.isEmpty {
                        hunkPicker(file: file)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)
                    }

                    // Shared colored, selectable, copy-on-select diff surface —
                    // the same NSTextView the Git drawer uses. It self-scrolls,
                    // so it must NOT be nested inside a SwiftUI ScrollView.
                    SelectableDiffTextView(
                        diffText: model.focusedDiff,
                        accessibilityLabel: diffAccessibilityLabel,
                        renderIdentity: diffRenderIdentity
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.4))
            }
        }
    }

    private var diffAccessibilityLabel: String {
        if let target = model.selectedReviewLocation?.target {
            return "Focused diff for \(target)"
        }
        if let path = model.selectedFile?.path {
            return "Focused diff for \(path)"
        }
        return "Focused diff"
    }

    private var diffRenderIdentity: String {
        let repository = model.repositorySummary ?? "unloaded"
        let review = model.snapshot.map { "\($0.summary.number)#\($0.summary.headRefOID)" } ?? "unloaded"
        let target = model.selectedHunk?.id ?? model.selectedFile?.path ?? "none"
        return "\(repository)#\(review)#\(target)"
    }

    private func hunkPicker(file: PullRequestReviewFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hunks")
                .font(YENTypography.secondary.weight(.medium))
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(file.hunks) { hunk in
                        Button {
                            model.selectHunk(id: hunk.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hunk \(hunk.index)")
                                    .font(YENTypography.secondary.weight(.semibold))
                                Text(hunk.location.target)
                                    .font(YENTypography.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(hunk.id == model.selectedHunkID ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(hunk.id == model.selectedHunkID ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }

    private func stagingSidebar(snapshot: PullRequestReviewSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review Actions")
                        .font(YENTypography.body.weight(.semibold))
                    Text("\(model.stagedDrafts.count) staged")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button("Clear All") {
                    model.clearStagedDrafts()
                }
                .disabled(model.stagedDrafts.isEmpty || model.isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReviewChrome.statusBanner(
                        message: "Staged drafts stay local until you explicitly confirm a post action. Published comments and decisions reuse the same gh-backed file formats and audit trail as `yen ide pr-review`.",
                        isError: false
                    )

                    if let submissionErrorMessage = model.submissionErrorMessage {
                        ReviewChrome.statusBanner(message: submissionErrorMessage, isError: true)
                    }

                    if let stagingMessage = model.stagingMessage {
                        ReviewChrome.statusBanner(message: stagingMessage, isError: false)
                    }

                    inlineDraftComposer(snapshot: snapshot)
                    evidenceDraftComposer
                    decisionComposer(snapshot: snapshot)
                    stagedDraftsSection
                }
                .padding(16)
            }
        }
    }

    private func inlineDraftComposer(snapshot: PullRequestReviewSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Uses the same file + line + side contract as `yen ide pr-review --inline`.")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("File path", text: $model.inlineDraftPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Use Selected Target") {
                        model.useSelectedTargetForInlineDraft()
                    }
                    .disabled(model.selectedFile == nil || model.isSubmitting)

                    Button("Open Target") {
                        Task { await model.openCurrentInlineDraftLocationInEditor() }
                    }
                    .disabled(model.currentInlineDraftLocation == nil || model.isSubmitting)
                }

                HStack(spacing: 8) {
                    TextField("Line", text: $model.inlineDraftLine)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)

                    Picker("Side", selection: $model.inlineDraftSide) {
                        ForEach(PullRequestReviewCommentSide.allCases) { side in
                            Text(side.rawValue).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let location = model.currentInlineDraftLocation {
                    Text("Target: \(location.target)")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                TextEditor(text: $model.inlineDraftBody)
                    .font(YENTypography.body)
                    .accessibilityLabel("Inline comment body")
                    .frame(minHeight: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                previewBlock(
                    title: "Inline Preview",
                    content: model.inlineDraftPreview,
                    minHeight: 120
                )

                HStack {
                    Spacer(minLength: 0)

                    Button("Stage Comment") {
                        model.stageCurrentInlineDraft()
                    }
                    .disabled(!model.canStageInlineDraft || model.isSubmitting)
                }
            }
        } label: {
            Text("Inline Comment Draft")
                .font(YENTypography.body.weight(.semibold))
        }
    }

    private var evidenceDraftComposer: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview the same markdown evidence bundle shape the CLI writes under the IDE evidence directory.")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)

                if let latestVerifySummaryPath = model.currentEvidenceDraft?.latestVerifySummaryPath {
                    Text("Latest verify summary: \(latestVerifySummaryPath)")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No recent verify summary found in the local IDE state; the preview will still include PR metadata and changed files.")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                }

                if let latestVerifySemanticPath = model.currentEvidenceDraft?.latestVerifySemanticPath {
                    Text("Latest verify semantic report: \(latestVerifySemanticPath)")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                previewBlock(
                    title: "Evidence Preview",
                    content: model.currentEvidenceDraft?.preview
                        ?? "Load a pull request to preview the evidence bundle.",
                    minHeight: 150
                )

                HStack {
                    Button(model.isSubmitting ? "Posting..." : "Post Evidence Comment") {
                        model.requestSubmission(.evidenceComment)
                    }
                    .disabled(model.stagedEvidenceDraft == nil || model.isSubmitting)

                    Spacer(minLength: 0)

                    Button(model.hasStagedEvidenceDraft ? "Restage Evidence" : "Stage Evidence") {
                        model.stageEvidenceDraft()
                    }
                    .disabled(model.currentEvidenceDraft == nil || model.isSubmitting)
                }
            }
        } label: {
            Text("Evidence Bundle")
                .font(YENTypography.body.weight(.semibold))
        }
    }

    private func decisionComposer(snapshot: PullRequestReviewSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compose the review summary body used for comment, approve, or request-changes actions. Staged inline comments are posted first, and staged evidence is referenced from the submitted review when present.")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)

                Text("Audit files write to \(model.auditDirectorySummary)")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                Picker("Decision", selection: $model.selectedDecisionMode) {
                    ForEach(PullRequestReviewDecisionMode.allCases) { mode in
                        Text(mode.heading).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextEditor(text: $model.reviewNote)
                    .font(YENTypography.body)
                    .accessibilityLabel("Review summary note")
                    .frame(minHeight: 84)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                previewBlock(
                    title: "\(model.selectedDecisionMode.heading) Preview",
                    content: model.currentDecisionDraft?.preview
                        ?? "Load a pull request to preview the review summary body.",
                    minHeight: 140
                )

                HStack {
                    Button(model.isSubmitting ? "Posting..." : "Post Inline Comments") {
                        model.requestSubmission(.inlineComments)
                    }
                    .disabled(model.stagedInlineDrafts.isEmpty || model.isSubmitting)

                    Spacer(minLength: 0)

                    Button(model.isSubmitting ? "Posting..." : model.selectedDecisionMode.submissionTitle) {
                        model.requestSubmission(.decision(model.selectedDecisionMode))
                    }
                    .disabled(model.snapshot == nil || model.isSubmitting)
                }

                Text("PR #\(snapshot.summary.number) reuses the same decision-template shape as `yen ide pr-review --decision`, including focus-file and evidence references when staged.")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)
            }
        } label: {
            Text("Review Summary")
                .font(YENTypography.body.weight(.semibold))
        }
    }

    private var stagedDraftsSection: some View {
        GroupBox {
            if model.stagedDrafts.isEmpty {
                Text("No local drafts staged yet.")
                    .font(YENTypography.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.stagedDrafts) { draft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(draft.title)
                                        .font(YENTypography.body.weight(.semibold))
                                    Text(draft.subtitle)
                                        .font(YENTypography.secondary)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer(minLength: 0)

                                Button("Remove") {
                                    model.removeStagedDraft(id: draft.id)
                                }
                                .disabled(model.isSubmitting)
                            }

                            previewBlock(
                                title: draft.suggestedFileName,
                                content: draft.preview,
                                minHeight: 110
                            )
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        } label: {
            Text("Staged Queue")
                .font(YENTypography.body.weight(.semibold))
        }
    }

    private func previewBlock(title: String, content: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(YENTypography.secondary.weight(.medium))
                .foregroundColor(.secondary)

            // Pin readable text to the top-leading corner even when it is
            // shorter than the fixed-height box (Scrollable Text Surface
            // Alignment; see _docs/01-architecture.md). A bare maxWidth lets the
            // scroll view vertically center short content.
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    Text(content)
                        .font(YENTypography.secondary.monospaced())
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                        .padding(10)
                }
            }
            .frame(minHeight: minHeight, maxHeight: minHeight)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func reviewSummary(_ summary: PullRequestReviewSummary) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(summary.number) \(summary.title)")
                    .font(YENTypography.body.weight(.semibold))
                    .lineLimit(2)
                Text("@\(summary.author)  •  \(summary.baseRefName) → \(summary.headRefName)")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Text("+\(summary.additions) / -\(summary.deletions) / \(summary.changedFiles) files")
                .font(YENTypography.secondary.weight(.medium))
                .foregroundColor(.secondary)

            if let url = URL(string: summary.url) {
                Link(destination: url) {
                    Text("Open on GitHub")
                        .font(YENTypography.secondary.weight(.semibold))
                }
            }
        }
    }

}
#endif
