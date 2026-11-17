import AppKit
import SwiftUI
import Testing
@testable import YEN

struct GitDrawerPresentationTests {
    @Test func diffTextColorReturnsCachedInstancePerRole() {
        // The five diff role colors are built once and shared; diffTextColor(for:)
        // is called per diff line on every re-render, so it must return the cached
        // instance (identity) instead of allocating fresh NSColors each call.
        for role in [GitDrawerDiffLineRole.metadata, .hunk, .addition, .deletion, .truncation] {
            #expect(
                GitDrawerSemanticColors.diffTextColor(for: role)
                    === GitDrawerSemanticColors.diffTextColor(for: role)
            )
        }
    }

    @Test func populatedSnapshotBuildsDenseHeaderAndGroupedRows() {
        let state = GitDrawerPresentationState(snapshot: populatedSnapshot)

        #expect(state.header.title == "repo // feature/git-drawer")
        #expect(state.header.subtitle == "origin/feature/git-drawer")
        #expect(state.header.summary == "6 files  +20  -4  ↑3  ↓2  stash 2")
        #expect(state.groups.map(\.title) == ["Staged", "Unstaged", "Untracked", "Conflicted"])
        #expect(state.groups.map(\.count) == [3, 1, 1, 1])
        #expect(state.groups.flatMap(\.rows).map(\.badge) == ["M", "A", "R", "M", "??", "U"])
        #expect(state.groups.flatMap(\.rows).map(\.stageGlyph) == ["S", "S", "S", "W", "?", "!"])
        #expect(state.groups[0].rows[2].path == "old-name.swift -> new-name.swift")
        #expect(state.groups[0].rows[2].numstat == "+4 -2")
        #expect(state.selectedDiffText == "@@ -1 +1 @@\n-old\n+new")
        #expect(state.diffAccessibilityLabel == "Unified diff for staged.swift")
    }

    @Test func cleanRepoKeepsHeaderButNoChangeGroups() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: "origin/main",
                ahead: 0,
                behind: 1,
                staged: [],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: 1
            )
        )

        #expect(state.header.title == "repo // main")
        #expect(state.header.subtitle == "origin/main")
        #expect(state.header.summary == "working tree clean  ↓1")
        #expect(state.groups.isEmpty)
        #expect(state.emptyMessage == "Working tree clean")
        #expect(state.selectedDiffText == "")
    }

    @Test func stashEntriesAreVisibleWithoutMarkingCleanRepoEmpty() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: "origin/main",
                ahead: 0,
                behind: 0,
                staged: [],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 1,
                stashEntries: [
                    GitDrawerStashEntry(
                        ref: "stash@{0}",
                        message: "WIP on main: abc1234 docs",
                        files: [
                            GitDrawerStashFile(path: "README.md", oldPath: nil, status: .modified),
                            GitDrawerStashFile(path: "docs/git.md", oldPath: nil, status: .added),
                        ]
                    ),
                ],
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: 1
            )
        )

        #expect(state.groups.isEmpty)
        #expect(state.stashEntries.map(\.ref) == ["stash@{0}"])
        #expect(state.stashEntries.first?.files.map(\.path) == ["README.md", "docs/git.md"])
        #expect(state.emptyMessage == nil)
        #expect(state.header.summary == "working tree clean  stash 1")
    }

    @Test func truncatedStashListKeepsTotalCountSeparateFromLoadedEntries() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 22,
                stashEntries: [
                    GitDrawerStashEntry(
                        ref: "stash@{0}",
                        message: "WIP",
                        files: [GitDrawerStashFile(path: "README.md", oldPath: nil, status: .modified)]
                    ),
                ],
                isStashListTruncated: true,
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: 1
            )
        )

        #expect(state.stashTotalCount == 22)
        #expect(state.stashEntries.count == 1)
        #expect(state.isStashListTruncated)
        #expect(state.header.summary == "working tree clean  stash 22")
    }

    @Test func fileListTruncationIsVisibleInHeaderSummary() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [
                    GitDrawerFileChange(
                        path: "staged.swift",
                        oldPath: nil,
                        status: .modified,
                        stage: .staged,
                        additions: 1,
                        deletions: 0
                    ),
                ],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                isFileListTruncated: true,
                generation: 1
            )
        )

        #expect(state.header.summary == "1 file  +1  -0  file list truncated")
    }

    @Test func rowAccessibilityHumanizesStatusAndNumstat() {
        let state = GitDrawerPresentationState(snapshot: populatedSnapshot)
        let renamed = state.groups[0].rows[2]

        #expect(renamed.accessibilityLabel == "Renamed, staged, old-name.swift to new-name.swift, plus 4 minus 2")
    }

    @Test func rowPresentationShowsBinaryPlaceholder() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [],
                unstaged: [
                    GitDrawerFileChange(
                        path: "image.png",
                        oldPath: nil,
                        status: .modified,
                        stage: .unstaged,
                        additions: nil,
                        deletions: nil,
                        statPlaceholder: "binary"
                    ),
                ],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: "image.png",
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: 1
            )
        )
        let row = state.groups[0].rows[0]

        #expect(row.numstat == "binary")
        #expect(row.accessibilityLabel == "Modified, unstaged, image.png, binary")
    }

    @Test func rowAccessibilityHumanizesTypeChangedStatus() {
        let row = GitDrawerPresentationState.Row(
            change: GitDrawerFileChange(
                path: "bin/tool",
                oldPath: nil,
                status: .typeChanged,
                stage: .unstaged,
                additions: 0,
                deletions: 0
            )
        )

        #expect(row.badge == "T")
        #expect(row.accessibilityLabel == "Type changed, unstaged, bin/tool, plus 0 minus 0")
    }

    @Test func rowPresentationKeepsBidiPathSeparateFromBadgeAndCounts() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "feature/rtl-\u{202E}txt",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [
                    GitDrawerFileChange(
                        path: "Sources/\u{202E}eman.swift",
                        oldPath: nil,
                        status: .modified,
                        stage: .staged,
                        additions: 12,
                        deletions: 3
                    ),
                ],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: 1
            )
        )
        let row = state.groups[0].rows[0]

        #expect(row.badge == "M")
        #expect(row.stageGlyph == "S")
        #expect(row.path == "Sources/\u{202E}eman.swift")
        #expect(row.numstat == "+12 -3")
        #expect(row.accessibilityLabel == "Modified, staged, Sources/\u{202E}eman.swift, plus 12 minus 3")
    }

    @Test func filtersReturnExpectedChangeGroups() {
        let groups = GitDrawerPresentationState(snapshot: populatedSnapshot).groups

        #expect(GitDrawerFilter.filteredGroups(groups, by: .all).map(\.title) == [
            "Staged",
            "Unstaged",
            "Untracked",
            "Conflicted",
        ])
        #expect(GitDrawerFilter.filteredGroups(groups, by: .staged).map(\.title) == ["Staged"])
        #expect(GitDrawerFilter.filteredGroups(groups, by: .unstaged).map(\.title) == ["Unstaged"])
        #expect(GitDrawerFilter.filteredGroups(groups, by: .untracked).map(\.title) == ["Untracked"])
        #expect(GitDrawerFilter.filteredGroups(groups, by: .conflicted).map(\.title) == ["Conflicted"])
        #expect(GitDrawerFilter.filteredGroups(groups, by: .stashes).isEmpty)
    }

    @Test func navigationPolicyMovesThroughFilteredRowsAndClampsAtEdges() {
        let groups = GitDrawerPresentationState(snapshot: populatedSnapshot).groups

        #expect(GitDrawerNavigationPolicy.destinationPath(
            currentPath: nil,
            groups: groups,
            direction: .next
        ) == "staged.swift")
        #expect(GitDrawerNavigationPolicy.destinationPath(
            currentPath: nil,
            groups: groups,
            direction: .previous
        ) == "conflicted.swift")
        #expect(GitDrawerNavigationPolicy.destinationPath(
            currentPath: "staged.swift",
            groups: groups,
            direction: .previous
        ) == "staged.swift")
        #expect(GitDrawerNavigationPolicy.destinationPath(
            currentPath: "conflicted.swift",
            groups: groups,
            direction: .next
        ) == "conflicted.swift")
        #expect(GitDrawerNavigationPolicy.destinationPath(
            currentPath: "staged.swift",
            groups: groups,
            filter: .unstaged,
            direction: .next
        ) == "unstaged.swift")
    }

    @Test func semanticColorsMeetContrastFloorInLightAndDarkAppearances() {
        let badges = ["M", "A", "D", "R", "C", "??", "U"]
        let diffRoles: [GitDrawerDiffLineRole] = [.metadata, .hunk, .addition, .deletion, .truncation, .context]
        let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

        for appearance in appearances {
            let windowBackground = resolvedColor(.windowBackgroundColor, appearance: appearance)
            let diffBackground = resolvedColor(GitDrawerSemanticColors.diffBackgroundColor, appearance: appearance)
            let diffText = resolvedColor(GitDrawerSemanticColors.diffTextColor, appearance: appearance)

            #expect(
                WindowBorderGradientResolver.contrastRatioForTesting(of: diffText, against: diffBackground) >= wcagNormalTextContrastFloor,
                "Git drawer diff text contrast failed in \(appearance.rawValue)"
            )

            for role in diffRoles {
                let diffRoleText = resolvedColor(GitDrawerSemanticColors.diffTextColor(for: role), appearance: appearance)
                #expect(
                    WindowBorderGradientResolver.contrastRatioForTesting(of: diffRoleText, against: diffBackground) >= wcagNormalTextContrastFloor,
                    "Git drawer diff \(role) contrast failed in \(appearance.rawValue)"
                )
            }

            for badge in badges {
                let badgeText = resolvedColor(
                    GitDrawerSemanticColors.badgeTextColor(for: badge),
                    appearance: appearance
                )
                #expect(
                    WindowBorderGradientResolver.contrastRatioForTesting(of: badgeText, against: windowBackground) >= wcagNormalTextContrastFloor,
                    "Git drawer badge \(badge) contrast failed in \(appearance.rawValue)"
                )
            }
        }
    }

    @Test func diffLineClassifierRecognizesUnifiedDiffRoles() {
        let lines = [
            "diff --git a/Sources/App.swift b/Sources/App.swift",
            "index 1111111..2222222 100644",
            "--- a/Sources/App.swift",
            "+++ b/Sources/App.swift",
            "@@ -1,2 +1,2 @@",
            "-old",
            "+new",
            " unchanged",
            "\\ No newline at end of file",
            "[diff truncated]",
            "new file mode 100644",
            "deleted file mode 100644",
            "old mode 100755",
            "new mode 100644",
            "similarity index 91%",
            "dissimilarity index 12%",
            "rename from old.swift",
            "rename to new.swift",
            "copy from source.swift",
            "copy to duplicate.swift",
            "Binary files a/image.png and b/image.png differ",
            "GIT binary patch",
            "literal 12",
            "delta 8",
            "+++literal",
            "---literal",
        ]

        #expect(lines.map(GitDrawerDiffLineClassifier.role(for:)) == [
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .hunk,
            .deletion,
            .addition,
            .context,
            .metadata,
            .truncation,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .addition,
            .deletion,
        ])
    }

    @Test func streamedDiffClassificationDistinguishesHeadersFromPrefixedSource() {
        let lines = [
            "diff --git a/list.md b/list.md",
            "--- a/list.md",
            "+++ b/list.md",
            "@@ -1 +1 @@",
            "--- deleted source beginning with two dashes",
            "+++ added source beginning with two pluses",
        ]
        var classifier = SelectableDiffTextLineClassifier()

        #expect(lines.map { classifier.role(for: $0, renderingMode: .unifiedDiff) } == [
            .metadata,
            .metadata,
            .metadata,
            .hunk,
            .deletion,
            .addition,
        ])
    }

    @Test func plainTextModeNeverTreatsSourcePrefixesAsDiffSyntax() {
        let lines = [
            "- Markdown list item",
            "+ literal source line",
            "@@ decorator",
            "diff --git prose",
        ]
        var classifier = SelectableDiffTextLineClassifier()

        #expect(lines.map { classifier.role(for: $0, renderingMode: .plain) } == [
            .context,
            .context,
            .context,
            .context,
        ])
    }

    @Test @MainActor func replacingSelectableDiffContentResetsSelectionAndBothScrollAxes() throws {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let textView = try #require(scrollView.documentView as? NSTextView)
        textView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 2_000)
        textView.string = String(repeating: "long diff line\n", count: 200)
        textView.setSelectedRange(NSRange(location: 5, length: 8))
        scrollView.contentView.scroll(to: NSPoint(x: 40, y: 800))

        #expect(scrollView.contentView.bounds.origin != .zero)
        GitDrawerDiffTextView.resetSelectionAndViewport(in: textView)

        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(scrollView.contentView.bounds.origin == .zero)
    }

    @Test func identicalTextAndLabelsStillRenderForANewTargetIdentity() {
        let commonArguments = (
            diff: "same source text",
            label: "Ours • HEAD",
            mode: SelectableDiffTextRenderingMode.plain
        )

        #expect(
            GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-1#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 12
            )
        )
        #expect(
            !GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-2#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 12
            )
        )
        #expect(
            GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-2#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 15
            )
        )
    }

    @Test func drawerHeightPolicyClampsRestoredHeightToWindowBounds() {
        #expect(GitDrawerHeightPolicy.defaultHeight(for: 1_000) == 380)
        #expect(GitDrawerHeightPolicy.clampedHeight(900, windowHeight: 1_000) == 700)
        #expect(GitDrawerHeightPolicy.clampedHeight(80, windowHeight: 1_000) == 220)
        #expect(GitDrawerHeightPolicy.clampedHeight(420, windowHeight: 1_000) == 420)
        #expect(GitDrawerHeightPolicy.clampedHeight(900, windowHeight: 1_000) == Double(YENGeometryClamp.clampedLength(
            900,
            minimum: 220,
            maximum: 700
        )))
    }

    @Test func untrackedFilterUsesCompactDisplayTitle() {
        #expect(GitDrawerFilter.untracked.rawValue == "Untracked")
        #expect(GitDrawerFilter.untracked.displayTitle == "New")
        #expect(GitDrawerFilter.untracked.emptyStateTitle == "untracked")
    }

    @Test func filtersExposeCompactHeaderIconMetadata() {
        #expect(GitDrawerFilter.allCases.map(\.headerIconSystemName) == [
            "square.grid.2x2",
            "checkmark.circle",
            "pencil",
            "plus",
            "exclamationmark.triangle",
            "archivebox",
        ])
        #expect(GitDrawerFilter.allCases.map(\.accessibilityLabel) == [
            "All changes",
            "Staged changes",
            "Unstaged changes",
            "New changes",
            "Conflicted changes",
            "Stashes",
        ])
    }

    @MainActor
    @Test func drawerViewCanBeHostedWithPopulatedState() {
        let host = GitDrawerHostingView.make(
            state: GitDrawerPresentationState(snapshot: populatedSnapshot),
            isLoading: false,
            onRefresh: {},
            onSelectPath: { _ in },
            onCopyPathValue: { _ in },
            onCopyDiff: {},
            onOpenPathValue: { _ in },
            onRevealPathValue: { _ in },
            onOpenGitTUI: {},
            onClose: {}
        )

        #expect(host.accessibilityIdentifier() == "yen.gitDrawer")
    }

    @Test func truncatedDiffGetsExplicitTextLabel() {
        let state = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "main",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: "large.swift",
                selectedDiff: "@@\n+partial",
                isDiffTruncated: true,
                generation: 1
            )
        )

        #expect(state.isDiffTruncated)
        #expect(state.selectedDiffText == "@@\n+partial\n\n[diff truncated]")
        #expect(state.diffAccessibilityLabel == "Unified diff for large.swift")
    }

    @Test func unavailableStateDoesNotLookLikeCleanRepo() {
        let state = GitDrawerPresentationState(unavailable: .notGitWorktree)

        #expect(state.header.title == "No Git repository")
        #expect(state.header.summary == "not a git worktree")
        #expect(state.groups.isEmpty)
        #expect(state.emptyMessage == "The focused split is not inside a Git working tree.")
        #expect(state.notice?.title == "No Git repository here")
        #expect(state.notice?.actionText?.contains("git init") == true)
        #expect(state.selectedDiffText == "")
        #expect(state.diffAccessibilityLabel == "Unified diff")
    }

    @Test func unsupportedAndEdgeStatesUseHonestCopy() {
        let cases: [(GitDrawerUnavailableReason, String, String)] = [
            (.notGitWorktree, "No Git repository here", "git init"),
            (.bareRepository, "Bare repositories are not supported", "working tree checkout"),
            (.missingGit, "Git is not available", "/usr/bin/git"),
            (.timedOut, "Git is taking too long", "Refresh again"),
            (.commandFailed, "Unable to read this worktree", "permissions"),
            (.mutationRejected, "Read-only drawer blocked a mutating command", "intentional write"),
            (.unknown, "Unable to open Git drawer", "split directory"),
        ]

        for (reason, title, actionFragment) in cases {
            let state = GitDrawerPresentationState(unavailable: reason)

            #expect(state.header.title == "No Git repository")
            #expect(state.header.summary == "not a git worktree")
            #expect(state.groups.isEmpty)
            #expect(state.notice?.title == title)
            #expect(state.notice?.actionText?.contains(actionFragment) == true)
        }

        let specialState = GitDrawerPresentationState(
            snapshot: GitDrawerSnapshot(
                repoRoot: "/repo",
                branch: "feature/git-drawer",
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [
                    GitDrawerFileChange(
                        path: "vendor/toolkit",
                        oldPath: nil,
                        status: .modified,
                        stage: .staged,
                        additions: nil,
                        deletions: nil,
                        statPlaceholder: "submodule"
                    ),
                ],
                unstaged: [
                    GitDrawerFileChange(
                        path: "image.png",
                        oldPath: nil,
                        status: .modified,
                        stage: .unstaged,
                        additions: nil,
                        deletions: nil,
                        statPlaceholder: "binary"
                    ),
                ],
                untracked: [],
                conflicted: [
                    GitDrawerFileChange(
                        path: "conflicted.swift",
                        oldPath: nil,
                        status: .conflicted,
                        stage: .conflicted,
                        additions: nil,
                        deletions: nil
                    ),
                ],
                stashCount: 0,
                selectedFile: "large.swift",
                selectedDiff: "@@\n+partial",
                isDiffTruncated: true,
                generation: 1
            )
        )

        #expect(specialState.groups.map(\.title) == ["Staged", "Unstaged", "Conflicted"])
        #expect(specialState.groups[0].rows[0].numstat == "submodule")
        #expect(specialState.groups[1].rows[0].numstat == "binary")
        #expect(specialState.groups[2].rows[0].badge == "U")
        #expect(specialState.groups[2].rows[0].stageGlyph == "!")
        #expect(specialState.groups[2].rows[0].accessibilityLabel == "Conflicted, conflicted, conflicted.swift")
        #expect(specialState.selectedDiffText == "@@\n+partial\n\n[diff truncated]")
    }
}

private let populatedSnapshot = GitDrawerSnapshot(
    repoRoot: "/repo",
    branch: "feature/git-drawer",
    upstream: "origin/feature/git-drawer",
    ahead: 3,
    behind: 2,
    staged: [
        GitDrawerFileChange(path: "staged.swift", oldPath: nil, status: .modified, stage: .staged, additions: 2, deletions: 0),
        GitDrawerFileChange(path: "added.swift", oldPath: nil, status: .added, stage: .staged, additions: 9, deletions: 1),
        GitDrawerFileChange(path: "new-name.swift", oldPath: "old-name.swift", status: .renamed, stage: .staged, additions: 4, deletions: 2),
    ],
    unstaged: [
        GitDrawerFileChange(path: "unstaged.swift", oldPath: nil, status: .modified, stage: .unstaged, additions: 5, deletions: 1),
    ],
    untracked: [
        GitDrawerFileChange(path: "new-file.swift", oldPath: nil, status: .untracked, stage: .untracked, additions: nil, deletions: nil),
    ],
    conflicted: [
        GitDrawerFileChange(path: "conflicted.swift", oldPath: nil, status: .conflicted, stage: .conflicted, additions: nil, deletions: nil),
    ],
    stashCount: 2,
    selectedFile: "staged.swift",
    selectedDiff: "@@ -1 +1 @@\n-old\n+new",
    isDiffTruncated: false,
    generation: 1
)

private let wcagNormalTextContrastFloor = 4.5

private func resolvedColor(_ color: NSColor, appearance: NSAppearance.Name) -> NSColor {
    var resolved = color
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.deviceRGB) ?? color
    }
    return resolved
}
