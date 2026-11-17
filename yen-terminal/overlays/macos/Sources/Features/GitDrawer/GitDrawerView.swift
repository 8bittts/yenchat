#if os(macOS)
import AppKit
import SwiftUI

enum GitDrawerHostingView {
    @MainActor
    static func make(
        state: GitDrawerPresentationState,
        isLoading: Bool,
        onRefresh: @escaping () -> Void,
        onSelectPath: @escaping (String) -> Void,
        onCopyPathValue: @escaping (String) -> Void,
        onCopyDiff: @escaping () -> Void,
        onOpenPathValue: @escaping (String) -> Void,
        onRevealPathValue: @escaping (String) -> Void,
        onOpenGitTUI: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) -> NSHostingView<GitDrawerView> {
        let view = GitDrawerView(
            state: state,
            isLoading: isLoading,
            onRefresh: onRefresh,
            onSelectPath: onSelectPath,
            onCopyPathValue: onCopyPathValue,
            onCopyDiff: onCopyDiff,
            onOpenPathValue: onOpenPathValue,
            onRevealPathValue: onRevealPathValue,
            onOpenGitTUI: onOpenGitTUI,
            onClose: onClose
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.setAccessibilityIdentifier("yen.gitDrawer")
        return hostingView
    }
}

struct GitDrawerView: View {
    let state: GitDrawerPresentationState
    let isLoading: Bool
    let onRefresh: () -> Void
    let onSelectPath: (String) -> Void
    let onCopyPathValue: (String) -> Void
    let onCopyDiff: () -> Void
    let onOpenPathValue: (String) -> Void
    let onRevealPathValue: (String) -> Void
    let onOpenGitTUI: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var filter: GitDrawerFilter = .all
    @State private var diffFocusProbe = GitDrawerDiffFocusProbe()
    @FocusState private var focusedRegion: GitDrawerFocusedRegion?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.45))
                .frame(height: 1)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveSelection(.previous)
            case .down:
                moveSelection(.next)
            default:
                break
            }
        }
        .accessibilityIdentifier("yen.gitDrawer")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            if state.emptyMessage == nil {
                GitDrawerFilterIconBar(selection: $filter)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(state.header.title)
                        .settingsScaledSystemFont(size: 13, weight: .semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Computing changes")
                    }
                }

                HStack(spacing: 8) {
                    Text(state.header.subtitle)
                        .settingsScaledSystemFont(size: 11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(state.header.summary)
                        .settingsScaledSystemFont(size: 11, weight: .medium, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                GitDrawerHeaderButton(
                    systemName: "arrow.clockwise",
                    helpText: "Refresh Git Drawer",
                    accessibilityLabel: "Refresh Git Drawer",
                    action: onRefresh
                )

                GitDrawerHeaderButton(
                    systemName: "terminal",
                    helpText: "Open Repo in Lazygit",
                    accessibilityLabel: "Open Repo in Lazygit",
                    isDisabled: state.repoRoot.isEmpty,
                    action: onOpenGitTUI
                )

                GitDrawerHeaderButton(
                    systemName: "xmark",
                    helpText: "Close Git Drawer",
                    accessibilityLabel: "Close Git Drawer",
                    action: onClose
                )
            }
            .frame(height: GitDrawerHeaderMetrics.buttonSize, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }

    private var content: some View {
        GeometryReader { geometry in
            let fileColumnWidth = GitDrawerLayout.fileColumnWidth(for: geometry.size.width)
            HStack(spacing: 0) {
                fileGroups
                    .frame(width: fileColumnWidth)
                    .background(Color(NSColor.windowBackgroundColor))
                Divider()
                diffPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fileGroups: some View {
        VStack(spacing: 0) {
            if state.emptyMessage == nil {
                keyboardShortcutButtons
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let emptyMessage = state.emptyMessage {
                        if let notice = state.notice {
                            GitDrawerNoticeView(notice: notice)
                        } else {
                            Text(emptyMessage)
                                .settingsScaledSystemFont(size: 12, weight: .medium)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        let groups = filter.showsChangeGroups ? GitDrawerFilter.filteredGroups(state.groups, by: filter) : []
                        let stashEntries = filter.showsStashes ? state.stashEntries : []
                        if groups.isEmpty, stashEntries.isEmpty {
                            Text(emptyStateMessage)
                                .settingsScaledSystemFont(size: 12, weight: .medium)
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // Header and rows are emitted as SIBLINGS of the LazyVStack,
                            // not wrapped per group. GitDrawerGroupView used to nest them
                            // in a VStack, which is eager — so every row in every group
                            // was constructed on each refresh (up to 500) and the
                            // LazyVStack above did nothing.
                            ForEach(groups, id: \.title) { group in
                                GitDrawerSectionHeader(title: group.title, count: group.count)

                                ForEach(group.rows) { row in
                                    GitDrawerRowView(
                                        row: row,
                                        isSelected: row.repoRelativePath == state.selectedPath,
                                        onSelectPath: { path in
                                            focusedRegion = .fileList
                                            onSelectPath(path)
                                        },
                                        onCopyPath: onCopyPathValue,
                                        onOpenPath: onOpenPathValue,
                                        onRevealPath: onRevealPathValue,
                                        differentiateWithoutColor: differentiateWithoutColor
                                    )
                                }
                            }
                            if !stashEntries.isEmpty {
                                GitDrawerStashEntriesView(
                                    entries: stashEntries,
                                    totalCount: state.stashTotalCount,
                                    isTruncated: state.isStashListTruncated,
                                    onCopyPath: onCopyPathValue,
                                    differentiateWithoutColor: differentiateWithoutColor
                                )
                            }
                        }
                    }
                }
            }
        }
        .clipped()
    }

    private var diffPane: some View {
        diffContent
            .background(Color(GitDrawerSemanticColors.diffBackgroundColor))
            .contextMenu {
                Button("Copy Diff", action: onCopyDiff)
                    .disabled(state.selectedDiffText.isEmpty)
            }
    }

    @ViewBuilder
    private var diffContent: some View {
        if state.selectedDiffText.isEmpty, state.selectedPath != nil {
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    Text("No textual changes to display for this file.")
                        .settingsScaledSystemFont(size: 12)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        .padding(.top, 8)
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .accessibilityLabel(state.diffAccessibilityLabel)
                }
            }
        } else {
            // Native NSTextView so the diff is genuinely selectable in the AppKit
            // responder chain and Copy on Select works via the text view's own
            // selection delegate. See GitDrawerDiffTextView.
            GitDrawerDiffTextView(
                diffText: state.selectedDiffText,
                accessibilityLabel: state.diffAccessibilityLabel,
                renderIdentity: "\(state.repoRoot)#\(state.selectedPath ?? "none")",
                focusProbe: diffFocusProbe
            )
        }
    }

    private var emptyStateMessage: String {
        filter == .stashes ? "No stash entries" : "No \(filter.emptyStateTitle) changes"
    }

    private var keyboardShortcutButtons: some View {
        Group {
            Button("Previous Git Change") {
                moveSelection(.previous)
            }
            .keyboardShortcut("k", modifiers: [])
            .accessibilityHidden(true)
            .hidden()

            Button("Next Git Change") {
                moveSelection(.next)
            }
            .keyboardShortcut("j", modifiers: [])
            .accessibilityHidden(true)
            .hidden()
        }
        .frame(width: 0, height: 0)
    }

    private func moveSelection(_ direction: GitDrawerNavigationDirection) {
        // Don't hijack j/k for file navigation while the diff text view is the
        // first responder (the user is reading/selecting the diff).
        guard !diffFocusProbe.isDiffFirstResponder else { return }
        guard focusedRegion == .fileList || focusedRegion == nil else { return }
        guard let destination = GitDrawerNavigationPolicy.destinationPath(
            currentPath: state.selectedPath,
            groups: state.groups,
            filter: filter,
            direction: direction
        ) else {
            return
        }
        focusedRegion = .fileList
        onSelectPath(destination)
    }
}

private enum GitDrawerFocusedRegion: Hashable {
    case fileList
}

private struct GitDrawerNoticeView: View {
    let notice: GitDrawerNotice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .settingsScaledSystemFont(size: 13, weight: .semibold)
                .foregroundStyle(Color(tintColor))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(notice.title)
                    .settingsScaledSystemFont(size: 12, weight: .semibold)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(notice.message)
                    .settingsScaledSystemFont(size: 12)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionText = notice.actionText {
                    Text(actionText)
                        .settingsScaledSystemFont(size: 11, weight: .medium)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch notice.severity {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var tintColor: NSColor {
        switch notice.severity {
        case .info:
            return .systemBlue
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    private var accessibilityLabel: String {
        [notice.title, notice.message, notice.actionText]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

private struct GitDrawerHeaderButton: View {
    let systemName: String
    let helpText: String
    let accessibilityLabel: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .settingsScaledSystemFont(size: GitDrawerHeaderMetrics.glyphSize, weight: .medium)
                .symbolRenderingMode(.hierarchical)
                .frame(
                    width: GitDrawerHeaderMetrics.buttonSize,
                    height: GitDrawerHeaderMetrics.buttonSize,
                    alignment: .center
                )
                .foregroundStyle(isDisabled ? Color(NSColor.disabledControlTextColor) : Color(NSColor.labelColor))
                .background(headerButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
                .offset(y: GitDrawerHeaderMetrics.controlVerticalOffset)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering in
            isHovering = hovering
            NSCursor.arrow.set()
        }
    }

    private var headerButtonBackground: Color {
        guard isHovering, !isDisabled else { return .clear }
        return Color(NSColor.separatorColor).opacity(0.22)
    }
}

private struct GitDrawerFilterIconBar: View {
    @Binding var selection: GitDrawerFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(GitDrawerFilter.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Image(systemName: option.headerIconSystemName)
                        .settingsScaledSystemFont(size: GitDrawerHeaderMetrics.glyphSize, weight: .medium)
                        .symbolRenderingMode(.hierarchical)
                        .frame(
                            width: GitDrawerHeaderMetrics.buttonSize,
                            height: GitDrawerHeaderMetrics.buttonSize,
                            alignment: .center
                        )
                        .foregroundStyle(selection == option ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                        .background(selection == option ? Color.accentColor.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(option.accessibilityLabel)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityValue(selection == option ? "Selected" : "Not selected")
                .onHover { _ in NSCursor.arrow.set() }
            }
        }
        .offset(y: GitDrawerHeaderMetrics.controlVerticalOffset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Git change filter")
    }
}

private enum GitDrawerHeaderMetrics {
    static let buttonSize: CGFloat = 26
    static let glyphSize: CGFloat = 14
    static let controlVerticalOffset: CGFloat = 2
}

private enum GitDrawerLayout {
    static func fileColumnWidth(for drawerWidth: CGFloat) -> CGFloat {
        if drawerWidth < 520 {
            return max(210, drawerWidth * 0.42)
        }
        if drawerWidth < 760 {
            return 260
        }
        return min(320, max(280, drawerWidth * 0.24))
    }
}

private struct GitDrawerRowView: View {
    let row: GitDrawerPresentationState.Row
    let isSelected: Bool
    let onSelectPath: (String) -> Void
    let onCopyPath: (String) -> Void
    let onOpenPath: (String) -> Void
    let onRevealPath: (String) -> Void
    let differentiateWithoutColor: Bool

    var body: some View {
        Button {
            onSelectPath(row.repoRelativePath)
        } label: {
            HStack(spacing: 8) {
                Text(row.stageGlyph)
                    .settingsScaledSystemFont(size: 11, weight: .bold, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .center)
                    .accessibilityHidden(true)

                Text(row.badge)
                    .settingsScaledSystemFont(size: 11, weight: .bold, design: .monospaced)
                    .foregroundStyle(differentiateWithoutColor ? Color(NSColor.labelColor) : badgeColor)
                    .frame(width: 24, alignment: .leading)
                    .accessibilityHidden(true)

                Text(row.path)
                    .settingsScaledSystemFont(size: 12, design: .monospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.path)

                Spacer(minLength: 8)

                Text(row.numstat)
                    .settingsScaledSystemFont(size: 11, weight: .medium, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .focusable()
        .contextMenu {
            if row.status != .deleted {
                Button("Open File") { onOpenPath(row.repoRelativePath) }
                Button("Reveal in Finder") { onRevealPath(row.repoRelativePath) }
            }
            Button("Copy Path") { onCopyPath(row.repoRelativePath) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var badgeColor: Color {
        Color(GitDrawerSemanticColors.badgeTextColor(
            for: row.badge,
            differentiateWithoutColor: differentiateWithoutColor
        ))
    }
}

private struct GitDrawerStashEntriesView: View {
    let entries: [GitDrawerPresentationState.StashEntry]
    let totalCount: Int
    let isTruncated: Bool
    let onCopyPath: (String) -> Void
    let differentiateWithoutColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GitDrawerSectionHeader(title: "Stash", count: max(totalCount, entries.count))

            if isTruncated {
                Text("Showing first \(entries.count) stashes")
                    .settingsScaledSystemFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .accessibilityLabel("Showing first \(entries.count) of \(totalCount) stashes")
            }

            ForEach(entries) { entry in
                GitDrawerStashEntryView(
                    entry: entry,
                    onCopyPath: onCopyPath,
                    differentiateWithoutColor: differentiateWithoutColor
                )
            }
        }
    }
}

private struct GitDrawerStashEntryView: View {
    let entry: GitDrawerPresentationState.StashEntry
    let onCopyPath: (String) -> Void
    let differentiateWithoutColor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(entry.ref)
                    .settingsScaledSystemFont(size: 11, weight: .semibold, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(entry.message)
                    .settingsScaledSystemFont(size: 12)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(entry.files.count)")
                    .settingsScaledSystemFont(size: 11, weight: .medium, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.accessibilityLabel)

            if entry.files.isEmpty {
                Text("No file list available")
                    .settingsScaledSystemFont(size: 11)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 2)
            } else {
                ForEach(entry.files) { file in
                    GitDrawerStashFileView(
                        file: file,
                        onCopyPath: onCopyPath,
                        differentiateWithoutColor: differentiateWithoutColor
                    )
                }
            }
        }
    }
}

private struct GitDrawerStashFileView: View {
    let file: GitDrawerPresentationState.StashFile
    let onCopyPath: (String) -> Void
    let differentiateWithoutColor: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(" ")
                .settingsScaledSystemFont(size: 11, weight: .bold, design: .monospaced)
                .frame(width: 12)
                .accessibilityHidden(true)

            Text(file.badge)
                .settingsScaledSystemFont(size: 11, weight: .bold, design: .monospaced)
                .foregroundStyle(differentiateWithoutColor ? Color(NSColor.labelColor) : badgeColor)
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)

            Text(file.path)
                .settingsScaledSystemFont(size: 12, design: .monospaced)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.path)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Path") { onCopyPath(file.repoRelativePath) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.accessibilityLabel)
    }

    private var badgeColor: Color {
        Color(GitDrawerSemanticColors.badgeTextColor(
            for: file.badge,
            differentiateWithoutColor: differentiateWithoutColor
        ))
    }
}

private struct GitDrawerSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .settingsScaledSystemFont(size: 11, weight: .semibold)
            Spacer()
            Text("\(count)")
                .settingsScaledSystemFont(size: 11, weight: .medium, design: .monospaced)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
#endif
