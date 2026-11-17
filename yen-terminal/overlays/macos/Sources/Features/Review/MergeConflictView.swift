#if os(macOS)
import AppKit
import SwiftUI

struct MergeConflictResolutionView: View {
    @ObservedObject var model: MergeConflictResolutionModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert(
            "Write and Stage Resolved File?",
            isPresented: resolutionConfirmationIsPresented,
            presenting: model.pendingResolutionConfirmation
        ) { _ in
            Button("Write and Stage") {
                model.confirmPendingResolution()
            }
            Button("Cancel", role: .cancel) {
                model.dismissPendingResolutionConfirmation()
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var resolutionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { model.pendingResolutionConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissPendingResolutionConfirmation()
                }
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Merge Conflicts")
                        .settingsScaledSystemFont(size: 20, weight: .semibold)
                    Text(
                        model.repositorySummary
                            ?? model.workingDirectorySummary
                            ?? "Open this workspace from a repo-backed terminal tab."
                    )
                    .settingsScaledSystemFont(size: 12)
                    .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button(model.isLoading ? "Loading..." : "Reload") {
                    model.requestLoad()
                }
                .disabled(model.isLoading || model.isApplying)
            }

            if let snapshot = model.snapshot, !snapshot.files.isEmpty {
                HStack(alignment: .center, spacing: 14) {
                    Text("\(snapshot.files.count) conflicted file\(snapshot.files.count == 1 ? "" : "s")")
                        .settingsScaledSystemFont(size: 12, weight: .medium)
                    Text("\(model.totalUnresolvedHunks) unresolved hunk\(model.totalUnresolvedHunks == 1 ? "" : "s")")
                        .settingsScaledSystemFont(size: 12)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Load the active repository to inspect text conflict markers and resolve them with explicit ours / theirs / both actions.")
                    .settingsScaledSystemFont(size: 12)
                    .foregroundColor(.secondary)
            }

            if let errorMessage = model.errorMessage {
                ReviewChrome.statusBanner(message: errorMessage, isError: true)
            } else if let statusMessage = model.statusMessage {
                ReviewChrome.statusBanner(message: statusMessage, isError: false)
            } else if model.snapshot == nil {
                ReviewChrome.statusBanner(
                    message: "This workspace uses the active terminal repo context and lists files that still have unresolved merge markers.",
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
                Text("Loading conflicted files...")
                    .settingsScaledSystemFont(size: 13)
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else if let snapshot = model.snapshot, !snapshot.files.isEmpty {
            HSplitView {
                fileList(snapshot: snapshot)
                    .frame(minWidth: ReviewChrome.fileListMinWidth, idealWidth: ReviewChrome.fileListIdealWidth)

                hunkDetail
                    .frame(minWidth: ReviewChrome.detailMinWidth, idealWidth: ReviewChrome.detailIdealWidth)

                resultSidebar
                    .frame(minWidth: ReviewChrome.sidebarMinWidth, idealWidth: ReviewChrome.sidebarIdealWidth)
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "arrow.triangle.merge")
                    .settingsScaledSystemFont(size: 28, weight: .medium)
                    .foregroundColor(.secondary)
                Text("No Merge Conflicts Loaded")
                    .settingsScaledSystemFont(size: 16, weight: .semibold)
                Text("Reload after `git merge` or `git rebase` to inspect unresolved text conflicts for the active repository.")
                    .settingsScaledSystemFont(size: 12)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private func fileList(snapshot: MergeConflictSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Files")
                        .settingsScaledSystemFont(size: 13, weight: .semibold)
                    Text("\(snapshot.files.count) conflicted")
                        .settingsScaledSystemFont(size: 11)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button("Previous") {
                    model.selectPreviousFile()
                }
                .disabled(!model.canNavigateFiles || model.isApplying)

                Button("Next") {
                    model.selectNextFile()
                }
                .disabled(!model.canNavigateFiles || model.isApplying)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List(snapshot.files, selection: $model.selectedFilePath) { file in
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.path)
                        .settingsScaledSystemFont(size: 12.5, weight: .medium)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if let unsupportedReason = file.unsupportedReason {
                        Text("Unsupported marker layout")
                            .settingsScaledSystemFont(size: 11)
                            .foregroundColor(.orange)
                            .help(unsupportedReason)
                    } else {
                        let unresolved = model.unresolvedHunkCount(for: file)
                        Text("\(unresolved) unresolved hunk\(unresolved == 1 ? "" : "s")")
                            .settingsScaledSystemFont(size: 11)
                            .foregroundColor(unresolved == 0 ? .secondary : .orange)
                    }
                }
                .padding(.vertical, 3)
                .tag(Optional(file.path))
            }
            .listStyle(.sidebar)
        }
    }

    private var hunkDetail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedFile?.path ?? "Conflict Hunk")
                        .settingsScaledSystemFont(size: 13, weight: .semibold)
                        .lineLimit(2)
                    if let location = model.selectedEditorLocation {
                        Text(location.target)
                            .settingsScaledSystemFont(size: 11)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Text(model.selectedFileStatusSummary)
                        .settingsScaledSystemFont(size: 11)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button("Previous Hunk") {
                    model.selectPreviousHunk()
                }
                .disabled(!model.canNavigateHunks || model.isApplying)

                Button("Next Hunk") {
                    model.selectNextHunk()
                }
                .disabled(!model.canNavigateHunks || model.isApplying)

                Button("Open in Editor") {
                    Task { await model.openSelectedLocationInEditor() }
                }
                .disabled(model.selectedEditorLocation == nil || model.isApplying)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            hunkDetailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor).opacity(0.4))
        }
    }

    @ViewBuilder
    private var hunkDetailContent: some View {
        if let file = model.selectedFile {
            if let unsupportedReason = file.unsupportedReason {
                VStack(alignment: .leading, spacing: 12) {
                    ReviewChrome.statusBanner(message: unsupportedReason, isError: true)
                    Text("This workspace currently handles marker-based text conflicts. Resolve this file with your external merge tool, then reload.")
                        .settingsScaledSystemFont(size: 12)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else if let selectedHunk = model.selectedHunk {
                VStack(alignment: .leading, spacing: 12) {
                    hunkPicker(file: file)
                    resolutionButtons(hunk: selectedHunk)

                    // Each AppKit text surface owns its own scroll context. The
                    // split view keeps every side reachable without wrapping the
                    // self-scrolling NSTextViews in another vertical ScrollView.
                    VSplitView {
                        previewBlock(
                            title: "Ours • \(selectedHunk.oursHeader)",
                            lines: selectedHunk.oursLines,
                            renderIdentity: previewIdentity(pane: "ours"),
                            renderingMode: .plain
                        )
                        .frame(minHeight: 90)

                        if let baseLines = selectedHunk.baseLines {
                            previewBlock(
                                title: "Base • \(selectedHunk.baseHeader ?? "base")",
                                lines: baseLines,
                                renderIdentity: previewIdentity(pane: "base"),
                                renderingMode: .plain
                            )
                            .frame(minHeight: 80)
                        }

                        previewBlock(
                            title: "Theirs • \(selectedHunk.theirsHeader)",
                            lines: selectedHunk.theirsLines,
                            renderIdentity: previewIdentity(pane: "theirs"),
                            renderingMode: .plain
                        )
                        .frame(minHeight: 90)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
            } else {
                emptyHunkState
            }
        } else {
            emptyHunkState
        }
    }

    private func hunkPicker(file: MergeConflictFileSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hunks")
                .settingsScaledSystemFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(file.hunks) { hunk in
                        let choice = model.resolutionChoice(for: hunk)
                        Button {
                            model.selectHunk(id: hunk.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hunk \(hunk.index)")
                                    .settingsScaledSystemFont(size: 11.5, weight: .semibold)
                                Text(choice?.rawValue.uppercased() ?? "UNRESOLVED")
                                    .settingsScaledSystemFont(size: 10)
                                    .foregroundColor(choice == nil ? .orange : .secondary)
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

    private func resolutionButtons(hunk: MergeConflictHunk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolve hunk \(hunk.index) at line \(hunk.startLine)")
                .settingsScaledSystemFont(size: 12.5, weight: .semibold)

            HStack(spacing: 8) {
                ForEach(MergeConflictResolutionChoice.allCases) { choice in
                    Button(choice.title) {
                        model.chooseResolution(choice)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.resolutionChoice(for: hunk) == choice ? .accentColor : Color(NSColor.controlBackgroundColor))
                    .accessibilityValue(model.resolutionChoice(for: hunk) == choice ? "Selected" : "Not selected")
                    .disabled(model.isApplying)
                }
            }
        }
    }

    private var resultSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Result")
                        .settingsScaledSystemFont(size: 13, weight: .semibold)
                    Text("\(model.totalUnresolvedHunks) unresolved")
                        .settingsScaledSystemFont(size: 11)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button(model.isApplying ? "Applying..." : "Mark Resolved") {
                    model.markSelectedFileResolved()
                }
                .disabled(!model.canMarkSelectedFileResolved || model.pendingResolutionConfirmation != nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ReviewChrome.statusBanner(
                    message: "Each hunk choice updates local IDE timeline audit state. Mark Resolved now asks for confirmation, revalidates the on-disk conflict markers, writes the merged file, and stages it with git.",
                    isError: false
                )

                VSplitView {
                    previewBlock(
                        title: "\(model.selectedHunkLocation?.target ?? model.selectedFile?.path ?? "Selected Hunk") • \(model.selectedHunkDiffPreviewLabel)",
                        lines: model.selectedHunkDiffPreview.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                        renderIdentity: previewIdentity(pane: "resolution-patch"),
                        renderingMode: selectedHunkPreviewRenderingMode
                    )
                    .frame(minHeight: 120)

                    previewBlock(
                        title: model.selectedFile?.path ?? "Resolved Preview",
                        lines: model.selectedFileResolvedPreview.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                        renderIdentity: previewIdentity(pane: "resolved-file"),
                        renderingMode: .plain
                    )
                    .frame(minHeight: 200)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var selectedHunkPreviewRenderingMode: SelectableDiffTextRenderingMode {
        if model.selectedHunkDiffPreviewSource == .plain,
           model.selectedHunkDiffPreview.hasPrefix("diff --git ") {
            return .unifiedDiff
        }
        return .plain
    }

    private var emptyHunkState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 40)
            Text("No conflict hunk selected.")
                .settingsScaledSystemFont(size: 14, weight: .medium)
            Text("Select a conflicted file from the sidebar to inspect its hunks.")
                .settingsScaledSystemFont(size: 12)
                .foregroundColor(.secondary)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func previewBlock(
        title: String,
        lines: [String],
        renderIdentity: String,
        renderingMode: SelectableDiffTextRenderingMode
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .settingsScaledSystemFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)

            // Shared selectable, copy-on-select surface. Conflict file content
            // uses explicit plain mode so legitimate source lines beginning with
            // +, -, or @@ are never misclassified as unified-diff syntax.
            SelectableDiffTextView(
                diffText: lines.joined(separator: "\n"),
                accessibilityLabel: title,
                renderIdentity: renderIdentity,
                renderingMode: renderingMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func previewIdentity(pane: String) -> String {
        let repository = model.snapshot?.repoRoot ?? "unloaded"
        let file = model.selectedFile?.path ?? "none"
        let hunk = model.selectedHunk?.id ?? "none"
        return "\(repository)#\(file)#\(hunk)#\(pane)"
    }

}
#endif
