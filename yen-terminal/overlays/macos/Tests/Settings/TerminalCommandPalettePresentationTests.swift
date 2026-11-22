import Foundation
import SwiftUI
import Testing
@testable import YEN

struct TerminalCommandPalettePresentationTests {
    @Test func emptyQueryKeepsLauncherActions() {
        let actions = [
            action(id: "settings:open", title: "Settings", description: "Open Settings", leadingIcon: "gearshape"),
            action(id: "workspace:toggle-tab-sidebar", title: "Toggle Tab Sidebar", description: "Show or hide the vertical tab sidebar", leadingIcon: "sidebar.left"),
        ]

        let state = TerminalCommandPaletteView.presentationStateForTesting(
            query: "   ",
            isSearching: false,
            paletteActions: actions,
            searchResults: [
                TerminalCommandPaletteSearchResult(
                    source: .file,
                    score: 180,
                    targetKey: "verify-guide.md",
                    previewKey: "verify-guide.md",
                    title: "verify-guide.md",
                    subtitle: nil,
                    execution: .openLocation(
                        TerminalCommandPaletteLocation(
                            path: "/tmp/verify-guide.md",
                            line: nil,
                            column: nil,
                            severity: nil,
                            code: nil,
                            diagnosticSource: nil
                        )
                    )
                ),
            ]
        )

        #expect(state.displayedOptions.map(\.id) == actions.map(\.id))
        #expect(state.displayedOptions.map(\.badge) == [nil, nil])
        #expect(state.emptyStateText == "No matches")
    }

    @Test func mixedResultsMapToSourceBadgesAndDescriptions() {
        let actions: [TerminalCommandPaletteView.PaletteActionDescriptor] = [
            action(id: "settings:open", title: "Settings", description: "Open Settings", leadingIcon: "gearshape"),
        ]
        let results: [TerminalCommandPaletteSearchResult] = [
            TerminalCommandPaletteSearchResult(
                source: .action,
                score: 310,
                targetKey: "Settings",
                previewKey: "Open Settings",
                title: "Settings",
                subtitle: "Open Settings",
                execution: .action(id: "settings:open")
            ),
            TerminalCommandPaletteSearchResult(
                source: .symbol,
                score: 260,
                targetKey: "src/review.ts:12:7",
                previewKey: "class • src/review.ts:12:7",
                title: "ReviewWorkspace [class]",
                subtitle: "class • src/review.ts:12:7",
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: "/tmp/review.ts",
                        line: 12,
                        column: 7,
                        severity: nil,
                        code: nil,
                        diagnosticSource: nil
                    )
                )
            ),
            TerminalCommandPaletteSearchResult(
                source: .file,
                score: 250,
                targetKey: "verify-guide.md",
                previewKey: "verify-guide.md",
                title: "verify-guide.md",
                subtitle: nil,
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: "/tmp/verify-guide.md",
                        line: nil,
                        column: nil,
                        severity: nil,
                        code: nil,
                        diagnosticSource: nil
                    )
                )
            ),
            TerminalCommandPaletteSearchResult(
                source: .content,
                score: 240,
                targetKey: "src/notes.txt:2:1",
                previewKey: "verify keyword here",
                title: "src/notes.txt:2:1",
                subtitle: "verify keyword here",
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: "/tmp/notes.txt",
                        line: 2,
                        column: 1,
                        severity: nil,
                        code: nil,
                        diagnosticSource: nil
                    )
                )
            ),
            TerminalCommandPaletteSearchResult(
                source: .diagnostic,
                score: 235,
                targetKey: "src/notes.txt:2:3",
                previewKey: "error: verify diagnostic",
                title: "src/notes.txt:2:3",
                subtitle: "error: verify diagnostic",
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: "/tmp/notes.txt",
                        line: 2,
                        column: 3,
                        severity: "error",
                        code: "VERIFY100",
                        diagnosticSource: "fake-lsp"
                    )
                )
            ),
            TerminalCommandPaletteSearchResult(
                source: .history,
                score: 230,
                targetKey: "2026-03-07T12:00:00Z",
                previewKey: "yen ide verify --quick (cwd=.)",
                title: "yen ide verify --quick",
                subtitle: "cwd=.",
                execution: .insertHistoryCommand(command: "yen ide verify --quick")
            ),
        ]

        let state = TerminalCommandPaletteView.presentationStateForTesting(
            query: "verify",
            isSearching: false,
            paletteActions: actions,
            searchResults: results
        )

        let badges = state.displayedOptions.map(\.badge)
        let icons = state.displayedOptions.map(\.leadingIcon)

        #expect(badges == ["action", "symbol", "file", "content", "diagnostic", "history"])
        #expect(icons == ["gearshape", "curlybraces", "doc.text", "text.magnifyingglass", "exclamationmark.bubble", "clock.arrow.circlepath"])
        #expect(state.displayedOptions[1].description == "Open matching symbol definition in the editor")
        #expect(state.displayedOptions[2].description == "Open file in the default editor")
        #expect(state.displayedOptions[3].description == "Open matching file location in the editor")
        #expect(state.displayedOptions[4].description == "Open matching diagnostic location in the editor")
        #expect(state.displayedOptions[5].description == "Insert command at the active terminal prompt")
    }

    @Test func lineAwareEditorLaunchPlanCoversRecognizedEditors() {
        let codePlan = TerminalCommandPaletteView.lineAwareEditorLaunchPlan(
            applicationName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            path: "/tmp/notes.txt",
            line: 14,
            column: 7
        )
        #expect(codePlan == TerminalCommandPaletteView.EditorLaunchPlan())

        let codiumPlan = TerminalCommandPaletteView.lineAwareEditorLaunchPlan(
            applicationName: "VSCodium",
            bundleIdentifier: "com.vscodium",
            path: "/tmp/notes.txt",
            line: 14,
            column: 7
        )
        #expect(codiumPlan == TerminalCommandPaletteView.EditorLaunchPlan())

        let xcodePlan = TerminalCommandPaletteView.lineAwareEditorLaunchPlan(
            applicationName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            path: "/tmp/notes.txt",
            line: 14,
            column: 7
        )
        #expect(xcodePlan == TerminalCommandPaletteView.EditorLaunchPlan())

        let zedPlan = TerminalCommandPaletteView.lineAwareEditorLaunchPlan(
            applicationName: "Zed",
            bundleIdentifier: "dev.zed.Zed",
            path: "/tmp/notes.txt",
            line: 14,
            column: 7
        )
        #expect(zedPlan == TerminalCommandPaletteView.EditorLaunchPlan())

        let fallbackPlan = TerminalCommandPaletteView.lineAwareEditorLaunchPlan(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            path: "/tmp/notes.txt",
            line: 14,
            column: 7
        )
        #expect(fallbackPlan == nil)
    }

    @Test func searchingQueryUsesSearchingEmptyStateCopy() {
        let state = TerminalCommandPaletteView.presentationStateForTesting(
            query: "verify",
            isSearching: true,
            paletteActions: [],
            searchResults: []
        )

        #expect(state.displayedOptions.isEmpty)
        #expect(state.emptyStateText == "Searching...")
    }

    @Test func hiddenPaletteSkipsCatalogConstructionUntilPresented() {
        var buildCount = 0

        let hiddenCatalog = TerminalCommandPaletteView.visibleActionCatalog(isPresented: false) {
            buildCount += 1
            return [action(id: "settings:open", title: "Settings", description: "Open Settings", leadingIcon: "gearshape")]
        }

        #expect(hiddenCatalog == nil)
        #expect(buildCount == 0)

        let visibleCatalog = TerminalCommandPaletteView.visibleActionCatalog(isPresented: true) {
            buildCount += 1
            return [action(id: "settings:open", title: "Settings", description: "Open Settings", leadingIcon: "gearshape")]
        }

        #expect(visibleCatalog?.map(\.id) == ["settings:open"])
        #expect(buildCount == 1)
    }

    @Test func actionCatalogInvalidationKeyTracksExplicitInputsOnly() {
        let firstSurface = NSObject()
        let secondSurface = NSObject()
        let base = actionCatalogInvalidationKey(
            jumpTargets: [
                jumpTargetKey(for: firstSurface),
            ]
        )

        #expect(
            base == actionCatalogInvalidationKey(
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                isPresented: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                workingDirectory: "/repo/other",
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                isRepositoryWorkspace: true,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                jumpTargets: [
                    jumpTargetKey(for: secondSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                jumpTargets: [
                    jumpTargetKey(for: firstSurface, title: "Deploy", subtitle: "~/deploy", tabColor: .green),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                updateAction: TerminalCommandPaletteView.ActionCatalogUpdateKey(
                    title: "Update YEN and Restart",
                    description: "Download and install the latest version",
                    iconName: "shippingbox.fill",
                    badge: "2.0",
                    isCancellable: true
                ),
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                tabSidebarEnabled: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                splitPaneLabelsEnabled: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                hasActiveTerminalController: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                hasMultiplePanes: true,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                scratchpadEnabled: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderEnabled: false,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderScope: .focusedSplit,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderColorMode: .matchTheme,
                windowBorderResolvedThemeName: "Solarized",
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderFocusedPalette: .ocean,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderUnfocusedPalette: .sunrise,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                windowBorderMatchThemeUsesManualFallback: true,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                reduceMotion: true,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                differentiateWithoutColor: true,
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
        #expect(
            base != actionCatalogInvalidationKey(
                customCommands: [
                    TerminalCommandPaletteView.ActionCatalogCustomCommandKey(
                        index: 0,
                        action: "new_window",
                        title: "New Window",
                        description: "Open a new terminal window",
                        symbols: ["⌘", "N"]
                    ),
                ],
                jumpTargets: [
                    jumpTargetKey(for: firstSurface),
                ]
            )
        )
    }

    @Test func ideQuickActionBlueprintsStayRegisteredWithExpectedCommands() {
        let blueprints = TerminalCommandPaletteView.ideQuickActionBlueprints

        #expect(blueprints.count == 21)
        #expect(blueprints.map(\.id) == [
            "ide:doctor",
            "ide:merge-readiness",
            "ide:agents-timeline",
            "ide:agents-export",
            "ide:benchmark-status",
            "ide:benchmark-run",
            "ide:format-status",
            "ide:lint-status",
            "ide:fix-status",
            "ide:debug-status",
            "ide:debug-tui",
            "ide:lsp-status",
            "ide:lsp-diagnostics",
            "ide:lsp-install-status",
            "ide:share-status",
            "ide:share-host-read-only",
            "ide:share-revoke",
            "ide:devcontainer-status",
            "ide:vscode-inventory",
            "ide:vscode-import-dry-run",
            "ide:ast-status",
        ])
        #expect(blueprints.map(\.title) == [
            "IDE: Workspace Doctor",
            "IDE: Merge Readiness",
            "IDE: Agents Timeline",
            "IDE: Agents Export",
            "IDE: Benchmark Status",
            "IDE: Run Benchmarks",
            "IDE: Format Status",
            "IDE: Lint Status",
            "IDE: Fix Status",
            "IDE: Debug Status",
            "IDE: Debug TUI",
            "IDE: LSP Status",
            "IDE: LSP Diagnostics",
            "IDE: LSP Install Matrix",
            "IDE: Share Status",
            "IDE: Share Host (Read-Only)",
            "IDE: Share Revoke",
            "IDE: Devcontainer Status",
            "IDE: VS Code Inventory",
            "IDE: VS Code Import (Dry Run)",
            "IDE: AST Status",
        ])
        #expect(blueprints.map(\.command) == [
            "yen ide doctor",
            "yen ide merge-readiness",
            "yen agents timeline",
            "yen agents export",
            "yen ide benchmark status",
            "yen ide benchmark run",
            "yen ide format status",
            "yen ide lint status",
            "yen ide fix status",
            "yen ide debug status",
            "yen ide debug tui",
            "yen ide lsp status",
            "yen ide lsp diagnostics",
            "yen ide lsp install status --all",
            "yen ide share status",
            "yen ide share host --read-only",
            "yen ide share revoke",
            "yen ide devcontainer status",
            "yen ide vscode inventory",
            "yen ide vscode import --dry-run",
            "yen ide ast status",
        ])
    }

    @Test func terminalCommandInputStepsPreserveIdeFlagsAndDigits() {
        for blueprint in TerminalCommandPaletteView.ideQuickActionBlueprints {
            let rendered = TerminalCommandPaletteView
                .terminalCommandInputSteps(for: blueprint.command)
                .map(\.text)
                .joined()
            #expect(rendered == blueprint.command)
        }

        let flaggy = TerminalCommandPaletteView
            .terminalCommandInputSteps(for: "yen ide vscode import --dry-run")
            .map(\.text)
            .joined()
        #expect(flaggy.contains("--dry-run"))

        let matrix = TerminalCommandPaletteView
            .terminalCommandInputSteps(for: "yen ide lsp install status --all")
            .map(\.text)
            .joined()
        #expect(matrix.contains("--all"))

        let readOnly = TerminalCommandPaletteView
            .terminalCommandInputSteps(for: "yen ide share host --read-only")
            .map(\.text)
            .joined()
        #expect(readOnly.contains("--read-only"))
    }

    @Test func dismissalOnlyRestoresFocusForKeyTerminalWindow() {
        #expect(
            TerminalCommandPaletteView.shouldRestoreSurfaceFocusOnDismiss(
                suppressSurfaceRefocusOnDismiss: false,
                surfaceWindowIsKey: true
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldRestoreSurfaceFocusOnDismiss(
                suppressSurfaceRefocusOnDismiss: false,
                surfaceWindowIsKey: false
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldRestoreSurfaceFocusOnDismiss(
                suppressSurfaceRefocusOnDismiss: true,
                surfaceWindowIsKey: true
            )
        )
    }

    @Test func repositoryWorkspaceActionsRequireWorkflowTrustForRepoBackedPaths() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-repo-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let nonRepo = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-nonrepo-\(UUID().uuidString)", isDirectory: true)
        let trustFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-trusted-workflow-\(UUID().uuidString)", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: nonRepo)
            try? FileManager.default.removeItem(at: trustFile)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        try root.path.write(to: trustFile, atomically: true, encoding: .utf8)

        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nested.path,
                workflowTrustFilePath: trustFile.path
            )
        )
        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nonRepo.path,
                workflowTrustFilePath: trustFile.path
            ) == false
        )
        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nil,
                workflowTrustFilePath: trustFile.path
            ) == false
        )
    }

    @Test func repositoryWorkspaceTrustParsingHandlesWhitespaceVariance() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-trust-whitespace-")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let trustFile = root.appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "\r\n  \(root.path)  \r\n\r\n".write(to: trustFile, atomically: true, encoding: .utf8)

        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nested.path,
                workflowTrustFilePath: trustFile.path
            )
        )
        #expect(
            TerminalCommandPaletteView.repositoryWorkspaceTrustContext(
                for: nested.path,
                workflowTrustFilePath: trustFile.path
            ) == TerminalCommandPaletteView.RepositoryWorkspaceTrustContext(
                workingDirectory: nested.path,
                repositoryRoot: root.path
            )
        )
    }

    @Test func repositoryWorkspaceActionsStayHiddenForUntrustedRepos() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-untrusted-repo-")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let trustFile = root.appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "".write(to: trustFile, atomically: true, encoding: .utf8)

        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nested.path,
                workflowTrustFilePath: trustFile.path
            ) == false
        )
        #expect(
            TerminalCommandPaletteView.repositoryWorkspaceTrustContext(
                for: nested.path,
                workflowTrustFilePath: trustFile.path
            ) == nil
        )
    }

    @Test func repositoryWorkspaceActionsHandleSymlinkedWorktreePaths() throws {
        let workspaceRoot = try makeTemporaryDirectory(prefix: "yen-palette-worktree-")
        let nested = workspaceRoot.appendingPathComponent("src/deep", isDirectory: true)
        let symlinkRoot = try makeTemporaryDirectory(prefix: "yen-palette-worktree-link-")
        let symlink = symlinkRoot.appendingPathComponent("alias", isDirectory: true)
        let symlinkedNested = symlink.appendingPathComponent("src/deep", isDirectory: true)
        let trustFile = try makeTemporaryDirectory(prefix: "yen-palette-worktree-trust-")
            .appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: workspaceRoot)
            try? FileManager.default.removeItem(at: symlinkRoot)
            try? FileManager.default.removeItem(at: trustFile.deletingLastPathComponent())
        }

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "gitdir: /tmp/fake-worktree".write(
            to: workspaceRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: workspaceRoot)
        try workspaceRoot.path.write(to: trustFile, atomically: true, encoding: .utf8)

        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: symlinkedNested.path,
                workflowTrustFilePath: trustFile.path
            )
        )
        #expect(
            TerminalCommandPaletteView.normalizedWorkingDirectory(symlinkedNested.path)
                == nested.resolvingSymlinksInPath().path
        )
        #expect(
            TerminalCommandPaletteView.repositoryWorkspaceTrustContext(
                for: symlinkedNested.path,
                workflowTrustFilePath: trustFile.path
            )
                == TerminalCommandPaletteView.RepositoryWorkspaceTrustContext(
                    workingDirectory: nested.resolvingSymlinksInPath().path,
                    repositoryRoot: workspaceRoot.resolvingSymlinksInPath().path
                )
        )
    }

    @Test func repositoryWorkflowTrustFilePathHonorsStateDirOverride() {
        let path = TerminalCommandPaletteView.repositoryWorkflowTrustFilePath(
            environment: ["YEN_IDE_STATE_DIR": "/tmp/custom-ide-state"],
            homeDirectoryPath: "/Users/tester"
        )

        #expect(path == "/tmp/custom-ide-state/trusted-workflow-projects")
    }

    @Test func repositoryWorkspaceActionBlueprintsAdvertiseTheirActualRenderingModes() {
        let blueprints = TerminalCommandPaletteView.repositoryWorkspaceActionBlueprints

        #expect(blueprints.map(\.id) == [
            "review:pull-request",
            "review:merge-conflicts",
        ])
        #expect(blueprints.map(\.title) == [
            "Review Pull Request",
            "Resolve Merge Conflicts",
        ])
        #expect(blueprints.allSatisfy { $0.searchTags.contains("hunk") })
        guard blueprints.count == 2 else { return }
        #expect(blueprints[0].description.contains("raw selectable previews"))
        #expect(blueprints[0].searchTags.contains("unified"))
        #expect(blueprints[1].description.contains("colored patch previews"))
        #expect(blueprints[1].searchTags.contains("patch"))
    }

    @Test func repositoryWorkspaceActionsRecheckTrustAndWorkingDirectoryAtExecutionTime() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-action-recheck-repo-")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let nonRepo = try makeTemporaryDirectory(prefix: "yen-palette-action-recheck-nonrepo-")
        let trustFile = root.appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: nonRepo)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        try "\(root.path)\n".write(to: trustFile, atomically: true, encoding: .utf8)

        var currentWorkingDirectory: String? = nested.path
        var reviewLaunches: [String] = []
        var mergeLaunches: [String] = []
        let actions = TerminalCommandPaletteView.repositoryWorkspaceActionDescriptorsForTesting(
            workingDirectory: { currentWorkingDirectory },
            workflowTrustFilePath: trustFile.path,
            pullRequestReviewLauncher: { reviewLaunches.append($0) },
            mergeConflictLauncher: { mergeLaunches.append($0) }
        )
        let reviewAction = try #require(actions.first { $0.id == "review:pull-request" })
        let mergeAction = try #require(actions.first { $0.id == "review:merge-conflicts" })

        reviewAction.execute()
        mergeAction.execute()
        #expect(reviewLaunches == [nested.path])
        #expect(mergeLaunches == [nested.path])

        reviewLaunches.removeAll()
        mergeLaunches.removeAll()
        try "".write(to: trustFile, atomically: true, encoding: .utf8)

        reviewAction.execute()
        mergeAction.execute()
        #expect(reviewLaunches.isEmpty)
        #expect(mergeLaunches.isEmpty)

        try "\(root.path)\n".write(to: trustFile, atomically: true, encoding: .utf8)
        currentWorkingDirectory = nonRepo.path

        reviewAction.execute()
        mergeAction.execute()
        #expect(reviewLaunches.isEmpty)
        #expect(mergeLaunches.isEmpty)
    }

    @Test func browserActionDescriptorRegistersManualPreview() {
        var didLaunch = false
        let descriptor = TerminalCommandPaletteView.browserActionDescriptorForTesting {
            didLaunch = true
        }

        #expect(descriptor.id == "browser:open")
        #expect(descriptor.title == "Browser")
        #expect(descriptor.subtitle == "Native web preview window")
        #expect(descriptor.description == "Open a native WebKit window for docs, HTTPS URLs, and localhost dev servers")
        #expect(descriptor.leadingIcon == "globe")
        #expect(descriptor.searchTags.contains("browser"))
        #expect(descriptor.searchTags.contains("native web"))
        #expect(descriptor.searchTags.contains("web preview"))
        #expect(descriptor.searchTags.contains("docs"))
        #expect(descriptor.searchTags.contains("localhost"))
        #expect(descriptor.searchTags.contains("loopback"))
        #expect(descriptor.searchTags.contains("dev server"))

        descriptor.execute()
        #expect(didLaunch)
    }

    @Test func browserSplitActionDescriptorRegistersManualSplitPreview() {
        var didLaunch = false
        let descriptor = TerminalCommandPaletteView.browserSplitActionDescriptorForTesting {
            didLaunch = true
        }

        #expect(descriptor.id == "browser:open-split")
        #expect(descriptor.title == "Browser Split")
        #expect(descriptor.subtitle == "Native web preview beside this terminal")
        #expect(
            descriptor.description == "Open the native browser split for docs, HTTPS URLs, and localhost dev servers"
        )
        #expect(descriptor.leadingIcon == "rectangle.split.2x1")
        #expect(descriptor.searchTags.contains("browser"))
        #expect(descriptor.searchTags.contains("browser split"))
        #expect(descriptor.searchTags.contains("web preview"))
        #expect(descriptor.searchTags.contains("split"))
        #expect(descriptor.searchTags.contains("terminal browser"))
        #expect(descriptor.searchTags.contains("localhost"))
        #expect(descriptor.searchTags.contains("dev server"))

        descriptor.execute()
        #expect(didLaunch)
    }

    @Test func browserActionSearchRanksNativePreviewBeforeFileBrowser() {
        let actions = [
            action(
                id: "terminal:file-browser",
                title: "File Browser",
                description: "Launch file browser in the active terminal",
                leadingIcon: "folder",
                searchTags: ["files", "browser", "project", "workspace"]
            ),
            TerminalCommandPaletteView.browserActionDescriptorForTesting(),
        ]
        let searchResults = TerminalCommandPaletteSearchEngine.immediateResults(
            query: "browser",
            context: .empty,
            actions: actions.map(\.searchDescriptor)
        )

        let state = TerminalCommandPaletteView.presentationStateForTesting(
            query: "browser",
            isSearching: false,
            paletteActions: actions,
            searchResults: searchResults
        )

        if case .action(let id)? = searchResults.first?.execution {
            #expect(id == "browser:open")
        } else {
            Issue.record("Expected Browser action to be the first search result")
        }
        #expect(state.displayedOptions.first?.id == "search:action:browser:open")
        #expect(state.displayedOptions.first?.title == "Browser")
    }

    @Test func browserActionsSearchByNativeWebAndTerminalSplitPhrases() {
        let actions = [
            TerminalCommandPaletteView.browserActionDescriptorForTesting(),
            TerminalCommandPaletteView.browserSplitActionDescriptorForTesting(),
        ]

        let nativeWebResults = TerminalCommandPaletteSearchEngine.immediateResults(
            query: "web preview",
            context: .empty,
            actions: actions.map(\.searchDescriptor)
        )
        if case .action(let id)? = nativeWebResults.first?.execution {
            #expect(id == "browser:open")
        } else {
            Issue.record("Expected Browser action for web preview query")
        }

        let terminalBrowserResults = TerminalCommandPaletteSearchEngine.immediateResults(
            query: "terminal browser",
            context: .empty,
            actions: actions.map(\.searchDescriptor)
        )
        if case .action(let id)? = terminalBrowserResults.first?.execution {
            #expect(id == "browser:open-split")
        } else {
            Issue.record("Expected Browser Split action for terminal browser query")
        }
    }

    @MainActor
    @Test func repositoryWorkspaceModelFailsClosedAcrossAsyncPathTransitions() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-repo-model-")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let nonRepo = try makeTemporaryDirectory(prefix: "yen-palette-nonrepo-model-")
        let deleted = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-deleted-\(UUID().uuidString)", isDirectory: true)
        let trustFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-trusted-workflow-model-\(UUID().uuidString)", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: nonRepo)
            try? FileManager.default.removeItem(at: deleted)
            try? FileManager.default.removeItem(at: trustFile)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deleted, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: deleted)
        try root.path.write(to: trustFile, atomically: true, encoding: .utf8)

        let model = TerminalCommandPaletteRepositoryWorkspaceModel(
            workflowTrustFilePathResolver: { trustFile.path }
        )

        model.refresh(workingDirectory: nested.path)
        model.refresh(workingDirectory: nonRepo.path)
        #expect(model.isRepositoryWorkspace == false)

        try await Task.sleep(nanoseconds: 250_000_000)
        #expect(model.isRepositoryWorkspace == false)

        model.refresh(workingDirectory: nested.path)
        await waitUntil(description: "repo eligibility") {
            model.isRepositoryWorkspace
        }
        #expect(model.isRepositoryWorkspace)

        model.refresh(workingDirectory: deleted.path)
        #expect(model.isRepositoryWorkspace == false)

        model.refresh(workingDirectory: nil)
        #expect(model.isRepositoryWorkspace == false)
    }

    private func action(
        id: String,
        title: String,
        description: String,
        leadingIcon: String,
        searchTags: [String] = []
    ) -> TerminalCommandPaletteView.PaletteActionDescriptor {
        TerminalCommandPaletteView.PaletteActionDescriptor(
            id: id,
            title: title,
            subtitle: nil,
            description: description,
            symbols: nil,
            leadingIcon: leadingIcon,
            leadingColor: nil,
            badge: nil,
            emphasis: false,
            sortKey: nil,
            searchTags: searchTags
        ) {}
    }

    private func actionCatalogInvalidationKey(
        isPresented: Bool = true,
        workingDirectory: String? = "/repo",
        isRepositoryWorkspace: Bool = false,
        updateAction: TerminalCommandPaletteView.ActionCatalogUpdateKey? = nil,
        tabSidebarEnabled: Bool = true,
        splitPaneLabelsEnabled: Bool = true,
        hasActiveTerminalController: Bool = true,
        hasMultiplePanes: Bool = false,
        scratchpadEnabled: Bool = true,
        windowBorderEnabled: Bool = true,
        windowBorderScope: WindowBorderScope = .window,
        windowBorderColorMode: WindowBorderColorMode = .manual,
        windowBorderFocusedPalette: WindowBorderPalette = .aurora,
        windowBorderUnfocusedPalette: WindowBorderPalette = .graphite,
        windowBorderMatchThemeUsesManualFallback: Bool = false,
        windowBorderResolvedThemeName: String? = "Nebula",
        reduceMotion: Bool = false,
        differentiateWithoutColor: Bool = false,
        customCommands: [TerminalCommandPaletteView.ActionCatalogCustomCommandKey] = [],
        jumpTargets: [TerminalCommandPaletteView.ActionCatalogJumpTargetKey] = []
    ) -> TerminalCommandPaletteView.ActionCatalogInvalidationKey {
        TerminalCommandPaletteView.actionCatalogInvalidationKeyForTesting(
            isPresented: isPresented,
            workingDirectory: workingDirectory,
            isRepositoryWorkspace: isRepositoryWorkspace,
            jumpTargets: jumpTargets,
            updateAction: updateAction,
            tabSidebarEnabled: tabSidebarEnabled,
            splitPaneLabelsEnabled: splitPaneLabelsEnabled,
            hasActiveTerminalController: hasActiveTerminalController,
            hasMultiplePanes: hasMultiplePanes,
            scratchpadEnabled: scratchpadEnabled,
            windowBorderEnabled: windowBorderEnabled,
            windowBorderScope: windowBorderScope,
            windowBorderColorMode: windowBorderColorMode,
            windowBorderFocusedPalette: windowBorderFocusedPalette,
            windowBorderUnfocusedPalette: windowBorderUnfocusedPalette,
            windowBorderMatchThemeUsesManualFallback: windowBorderMatchThemeUsesManualFallback,
            windowBorderResolvedThemeName: windowBorderResolvedThemeName,
            reduceMotion: reduceMotion,
            differentiateWithoutColor: differentiateWithoutColor,
            customCommands: customCommands
        )
    }

    private func jumpTargetKey(
        for surface: NSObject,
        title: String = "Build",
        subtitle: String? = "~/repo",
        tabColor: TerminalTabColor = .blue
    ) -> TerminalCommandPaletteView.ActionCatalogJumpTargetKey {
        TerminalCommandPaletteView.ActionCatalogJumpTargetKey(
            objectID: ObjectIdentifier(surface),
            title: title,
            subtitle: subtitle,
            tabColor: tabColor
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1.0,
        description: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await advanceMainQueueTurn()
        }

        Issue.record("Timed out waiting for \(description)")
    }

    private func advanceMainQueueTurn() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
        await Task.yield()
    }
}
