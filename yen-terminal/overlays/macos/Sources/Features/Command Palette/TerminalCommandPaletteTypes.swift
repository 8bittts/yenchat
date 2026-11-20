// YEN Overlay: command palette descriptor and invalidation-key types.

import AppKit
import SwiftUI
import YENKit

extension TerminalCommandPaletteView {
    struct RepositoryWorkspaceTrustContext: Equatable {
        let workingDirectory: String
        let repositoryRoot: String
    }

    struct SettingsDeepLinkDefinition: Equatable {
        let id: String
        let title: String
        let description: String
        let leadingIcon: String
        let pane: SettingsPane
    }

    struct WindowBorderActionSnapshot: Equatable {
        let id: String
        let title: String
        let description: String
        let leadingIcon: String
        let searchTags: [String]
    }

    struct ActionCatalogJumpTargetKey: Equatable {
        let objectID: ObjectIdentifier
        let title: String
        let subtitle: String?
        let tabColor: TerminalTabColor

        init(
            objectID: ObjectIdentifier,
            title: String,
            subtitle: String?,
            tabColor: TerminalTabColor
        ) {
            self.objectID = objectID
            self.title = title
            self.subtitle = subtitle
            self.tabColor = tabColor
        }

        init(snapshot: TerminalCommandPaletteJumpTargetSnapshot) {
            self.init(
                objectID: snapshot.objectID,
                title: snapshot.title,
                subtitle: snapshot.subtitle,
                tabColor: snapshot.tabColor
            )
        }
    }

    struct ActionCatalogUpdateKey: Equatable {
        /// Nil when the state is not installable — the catalog then only offers
        /// the cancel command (upstream ccb08f35).
        let title: String?
        let description: String?
        let iconName: String?
        let badge: String?
        let isCancellable: Bool
    }

    struct ActionCatalogCustomCommandKey: Equatable {
        let index: Int
        let action: String
        let title: String
        let description: String
        let symbols: [String]?
    }

    struct ActionCatalogWindowBorderKey: Equatable {
        let enabled: Bool
        let scope: WindowBorderScope
        let colorMode: WindowBorderColorMode
        let focusedPalette: WindowBorderPalette
        let unfocusedPalette: WindowBorderPalette
        let matchThemeUsesManualFallback: Bool
        let resolvedThemeName: String?
        let reduceMotion: Bool
        let differentiateWithoutColor: Bool
    }

    struct ActionCatalogAvailabilityKey: Equatable {
        let updateAction: ActionCatalogUpdateKey?
        let tabSidebarEnabled: Bool
        let splitPaneLabelsEnabled: Bool
        let hasActiveTerminalController: Bool
        let hasMultiplePanes: Bool
        let scratchpadEnabled: Bool
        let windowBorder: ActionCatalogWindowBorderKey
        let customCommands: [ActionCatalogCustomCommandKey]
    }

    struct ActionCatalogInvalidationKey: Equatable {
        let isPresented: Bool
        let workingDirectory: String?
        let isRepositoryWorkspace: Bool
        let jumpTargets: [ActionCatalogJumpTargetKey]
        let availability: ActionCatalogAvailabilityKey
    }

    struct PaletteActionDescriptor {
        let id: String
        let title: String
        let subtitle: String?
        let description: String?
        let symbols: [String]?
        let leadingIcon: String?
        let leadingColor: Color?
        let badge: String?
        let emphasis: Bool
        let sortKey: ObjectIdentifier?
        let searchTags: [String]
        let execute: () -> Void

        var searchDescriptor: TerminalCommandPaletteActionSearchDescriptor {
            TerminalCommandPaletteActionSearchDescriptor(
                id: id,
                title: title,
                subtitle: subtitle,
                description: description,
                searchTags: searchTags
            )
        }

        var commandOption: CommandOption {
            CommandOption(
                id: id,
                title: title,
                subtitle: subtitle,
                description: description,
                symbols: symbols,
                leadingIcon: leadingIcon,
                leadingColor: leadingColor,
                badge: badge,
                emphasis: emphasis,
                sortKey: sortKey,
                action: execute
            )
        }
    }

    struct PalettePresentationState {
        let displayedOptions: [CommandOption]
        let emptyStateText: String
    }

    struct TerminalCommandBlueprint: Equatable {
        let id: String
        let title: String
        let description: String
        let leadingIcon: String
        let searchTags: [String]
        let command: String
    }

    struct RepositoryWorkspaceActionBlueprint: Equatable {
        let id: String
        let title: String
        let description: String
        let leadingIcon: String
        let searchTags: [String]
    }

    typealias EditorLaunchPlan = IDEEditorLaunchPlan

    struct TerminalCommandInputStep: Equatable {
        let key: YEN.Input.Key
        let text: String
    }

    static let settingsDeepLinkDefinitions: [SettingsDeepLinkDefinition] = [
        .init(
            id: "settings:appearance",
            title: "Settings: Appearance",
            description: "Open Settings on the Appearance pane, with themes, text and the window",
            leadingIcon: SettingsPane.appearance.symbolName,
            pane: .appearance
        ),
        .init(
            id: "settings:general",
            title: "Settings: General",
            description: "Open Settings on the General pane, with the workspace and links",
            leadingIcon: SettingsPane.general.symbolName,
            pane: .general
        ),
        .init(
            id: "settings:general:pane-labels",
            title: "Settings: Pane Labels",
            description: "Open General settings for pane labels",
            leadingIcon: "tag",
            pane: .general
        ),
        .init(
            id: "settings:notifications",
            title: "Settings: Notifications",
            description: "Open Settings on the Notifications pane",
            leadingIcon: SettingsPane.notifications.symbolName,
            pane: .notifications
        ),
        .init(
            id: "settings:dictation",
            title: "Settings: Dictation",
            description: "Open Settings on the Dictation pane",
            leadingIcon: SettingsPane.dictation.symbolName,
            pane: .dictation
        ),
        .init(
            id: "settings:shortcuts",
            title: "Settings: Shortcuts",
            description: "Open Settings on the Shortcuts pane",
            leadingIcon: SettingsPane.shortcuts.symbolName,
            pane: .shortcuts
        ),
    ]

    static func openSettingsDeepLink(_ deepLink: SettingsDeepLinkDefinition) {
        SettingsController.shared.show(pane: deepLink.pane)
    }

    static func jumpDisplayTitle(terminalTitle: String, titleOverride: String?) -> String {
        if let titleOverride, !titleOverride.isEmpty {
            return titleOverride
        }
        if !terminalTitle.isEmpty {
            return terminalTitle
        }
        return "Untitled"
    }

    static func shouldShowScratchpadCommand(scratchpadEnabled: Bool) -> Bool {
        scratchpadEnabled
    }

    static func shouldShowTabSidebarCommand(tabSidebarEnabled: Bool) -> Bool {
        tabSidebarEnabled
    }

    static func shouldShowSplitLabelCommand(
        splitPaneLabelsEnabled: Bool,
        hasMultiplePanes: Bool
    ) -> Bool {
        splitPaneLabelsEnabled && hasMultiplePanes
    }

    static func browserActionDescriptorForTesting(
        launcher: @escaping () -> Void = {}
    ) -> PaletteActionDescriptor {
        browserActionDescriptor(launcher: launcher)
    }

    static func browserSplitActionDescriptorForTesting(
        launcher: @escaping () -> Void = {}
    ) -> PaletteActionDescriptor {
        browserSplitActionDescriptor(launcher: launcher)
    }

    static func gitDrawerActionDescriptorForTesting(
        launcher: @escaping () -> Void = {}
    ) -> PaletteActionDescriptor {
        gitDrawerActionDescriptor(launcher: launcher)
    }

    static func shouldSuppressSurfaceRefocusOnDismiss(for optionID: String) -> Bool {
        let actionID = canonicalActionID(for: optionID)
        switch actionID {
        case "workspace:rename-split-label", "workspace:toggle-scratchpad":
            return true
        default:
            return false
        }
    }

    static func visibleActionCatalog(
        isPresented: Bool,
        build: () -> [PaletteActionDescriptor]
    ) -> [PaletteActionDescriptor]? {
        guard isPresented else { return nil }
        return build()
    }

    static func shouldRestoreSurfaceFocusOnDismiss(
        suppressSurfaceRefocusOnDismiss: Bool,
        surfaceWindowIsKey: Bool
    ) -> Bool {
        !suppressSurfaceRefocusOnDismiss && surfaceWindowIsKey
    }

    static func shouldShowRepositoryWorkspaceActions(
        workingDirectory: String?,
        workflowTrustFilePath: String? = nil
    ) -> Bool {
        repositoryWorkspaceTrustContext(
            for: workingDirectory,
            workflowTrustFilePath: workflowTrustFilePath
        ) != nil
    }

    nonisolated static func repositoryWorkflowTrustFilePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> String {
        let baseDirectory: String
        if let configuredStateDirectory = environment["YEN_IDE_STATE_DIR"],
           !configuredStateDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseDirectory = NSString(string: configuredStateDirectory).expandingTildeInPath
        } else {
            baseDirectory = URL(fileURLWithPath: homeDirectoryPath)
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("yen", isDirectory: true)
                .appendingPathComponent("ide", isDirectory: true)
                .path
        }
        return URL(fileURLWithPath: baseDirectory)
            .standardizedFileURL
            .appendingPathComponent("trusted-workflow-projects", isDirectory: false)
            .path
    }

    static func browserActionDescriptor(
        launcher: @escaping () -> Void
    ) -> PaletteActionDescriptor {
        PaletteActionDescriptor(
            id: "browser:open",
            title: "Browser",
            subtitle: "Native web preview window",
            description: "Open a native WebKit window for docs, HTTPS URLs, and localhost dev servers",
            symbols: nil,
            leadingIcon: "globe",
            leadingColor: nil,
            badge: nil,
            emphasis: false,
            sortKey: nil,
            searchTags: [
                "browser",
                "native browser",
                "native web",
                "web",
                "web preview",
                "webkit",
                "preview",
                "docs",
                "url",
                "site",
                "localhost",
                "loopback",
                "dev server",
            ],
            execute: launcher
        )
    }

    static func gitDrawerActionDescriptor(
        launcher: @escaping () -> Void
    ) -> PaletteActionDescriptor {
        PaletteActionDescriptor(
            id: "terminal:git-drawer",
            title: "Git Drawer",
            subtitle: nil,
            description: "Toggle the read-only local Git drawer",
            symbols: ["⌘", "⇧", "G"],
            leadingIcon: "point.3.connected.trianglepath.dotted",
            leadingColor: nil,
            badge: nil,
            emphasis: false,
            sortKey: nil,
            searchTags: [
                "git",
                "drawer",
                "diff",
                "changes",
                "status",
                "local changes",
                "source control",
            ],
            execute: launcher
        )
    }

    static func browserSplitActionDescriptor(
        launcher: @escaping () -> Void
    ) -> PaletteActionDescriptor {
        PaletteActionDescriptor(
            id: "browser:open-split",
            title: "Browser Split",
            subtitle: "Native web preview beside this terminal",
            description: "Open the native browser split for docs, HTTPS URLs, and localhost dev servers",
            symbols: nil,
            leadingIcon: "rectangle.split.2x1",
            leadingColor: nil,
            badge: nil,
            emphasis: false,
            sortKey: nil,
            searchTags: [
                "browser",
                "browser split",
                "native browser",
                "native web",
                "web",
                "web preview",
                "webkit",
                "preview",
                "docs",
                "url",
                "site",
                "localhost",
                "loopback",
                "dev server",
                "split",
                "terminal browser",
                "terminal split",
                "side by side",
                "pane",
            ],
            execute: launcher
        )
    }

    /// Static shell-command palette entries, mirroring the IDE quick-action
    /// table below so both map to descriptors identically (was 3 inline closures).
    static let shellCommandBlueprints: [TerminalCommandBlueprint] = [
        TerminalCommandBlueprint(
            id: "terminal:btop",
            title: "btop",
            description: "Open system monitor",
            leadingIcon: "chart.bar.xaxis",
            searchTags: ["btop", "monitor", "system", "performance"],
            command: "btop"
        ),
        TerminalCommandBlueprint(
            id: "terminal:fastfetch",
            title: "fastfetch",
            description: "Show system information summary",
            leadingIcon: "desktopcomputer",
            searchTags: ["fastfetch", "system", "info", "summary"],
            command: "fastfetch"
        ),
        TerminalCommandBlueprint(
            id: "terminal:sessions",
            title: "Persistent Sessions",
            description: "List sessions that keep running when YEN quits",
            leadingIcon: "rectangle.stack",
            searchTags: ["sessions", "persistent", "detached", "attach", "background", "zmx"],
            command: "yen sessions"
        ),
    ]

    static let ideQuickActionBlueprints: [TerminalCommandBlueprint] = [
        TerminalCommandBlueprint(
            id: "ide:doctor",
            title: "IDE: Workspace Doctor",
            description: "Run yen ide doctor in the active terminal",
            leadingIcon: "stethoscope",
            searchTags: ["ide", "doctor", "health", "toolchain", "workspace", "verify"],
            command: "yen ide doctor"
        ),
        TerminalCommandBlueprint(
            id: "ide:merge-readiness",
            title: "IDE: Merge Readiness",
            description: "Run yen ide merge-readiness in the active terminal",
            leadingIcon: "checklist.checked",
            searchTags: ["ide", "merge", "readiness", "review", "verify", "gate", "pr"],
            command: "yen ide merge-readiness"
        ),
        TerminalCommandBlueprint(
            id: "ide:agents-timeline",
            title: "IDE: Agents Timeline",
            description: "Run yen agents timeline in the active terminal",
            leadingIcon: "person.2.badge.gearshape",
            searchTags: ["agents", "timeline", "session", "claude", "codex", "workspace", "evidence"],
            command: "yen agents timeline"
        ),
        TerminalCommandBlueprint(
            id: "ide:agents-export",
            title: "IDE: Agents Export",
            description: "Run yen agents export in the active terminal",
            leadingIcon: "square.and.arrow.up.on.square",
            searchTags: ["agents", "export", "evidence", "bundle", "markdown", "json", "workspace"],
            command: "yen agents export"
        ),
        TerminalCommandBlueprint(
            id: "ide:benchmark-status",
            title: "IDE: Benchmark Status",
            description: "Run yen ide benchmark status in the active terminal",
            leadingIcon: "speedometer",
            searchTags: ["ide", "benchmark", "performance", "reliability", "status", "slo"],
            command: "yen ide benchmark status"
        ),
        TerminalCommandBlueprint(
            id: "ide:benchmark-run",
            title: "IDE: Run Benchmarks",
            description: "Run yen ide benchmark run in the active terminal",
            leadingIcon: "gauge.with.dots.needle.33percent",
            searchTags: ["ide", "benchmark", "performance", "reliability", "run", "latency"],
            command: "yen ide benchmark run"
        ),
        TerminalCommandBlueprint(
            id: "ide:format-status",
            title: "IDE: Format Status",
            description: "Run yen ide format status in the active terminal",
            leadingIcon: "paintbrush",
            searchTags: ["ide", "format", "formatter", "quality", "status", "workflow"],
            command: "yen ide format status"
        ),
        TerminalCommandBlueprint(
            id: "ide:lint-status",
            title: "IDE: Lint Status",
            description: "Run yen ide lint status in the active terminal",
            leadingIcon: "checklist.unchecked",
            searchTags: ["ide", "lint", "quality", "status", "warnings", "workflow"],
            command: "yen ide lint status"
        ),
        TerminalCommandBlueprint(
            id: "ide:fix-status",
            title: "IDE: Fix Status",
            description: "Run yen ide fix status in the active terminal",
            leadingIcon: "wrench.and.screwdriver",
            searchTags: ["ide", "fix", "quality", "status", "formatter", "workflow"],
            command: "yen ide fix status"
        ),
        TerminalCommandBlueprint(
            id: "ide:debug-status",
            title: "IDE: Debug Status",
            description: "Run yen ide debug status in the active terminal",
            leadingIcon: "ladybug",
            searchTags: ["ide", "debug", "debugger", "breakpoint", "status", "trust"],
            command: "yen ide debug status"
        ),
        TerminalCommandBlueprint(
            id: "ide:debug-tui",
            title: "IDE: Debug TUI",
            description: "Run yen ide debug tui in the active terminal",
            leadingIcon: "terminal",
            searchTags: ["ide", "debug", "debugger", "tui", "dashboard", "transcript", "watches"],
            command: "yen ide debug tui"
        ),
        TerminalCommandBlueprint(
            id: "ide:lsp-status",
            title: "IDE: LSP Status",
            description: "Run yen ide lsp status in the active terminal",
            leadingIcon: "chevron.left.forwardslash.chevron.right",
            searchTags: ["ide", "lsp", "status", "language server", "diagnostics"],
            command: "yen ide lsp status"
        ),
        TerminalCommandBlueprint(
            id: "ide:lsp-diagnostics",
            title: "IDE: LSP Diagnostics",
            description: "Run yen ide lsp diagnostics in the active terminal",
            leadingIcon: "exclamationmark.bubble",
            searchTags: ["ide", "lsp", "diagnostics", "errors", "warnings"],
            command: "yen ide lsp diagnostics"
        ),
        TerminalCommandBlueprint(
            id: "ide:lsp-install-status",
            title: "IDE: LSP Install Matrix",
            description: "Run yen ide lsp install status --all in the active terminal",
            leadingIcon: "square.and.arrow.down",
            searchTags: ["ide", "lsp", "install", "language server", "matrix"],
            command: "yen ide lsp install status --all"
        ),
        TerminalCommandBlueprint(
            id: "ide:share-status",
            title: "IDE: Share Status",
            description: "Run yen ide share status in the active terminal",
            leadingIcon: "rectangle.connected.to.line.below",
            searchTags: ["ide", "share", "status", "collaboration", "upterm", "tmate"],
            command: "yen ide share status"
        ),
        TerminalCommandBlueprint(
            id: "ide:share-host-read-only",
            title: "IDE: Share Host (Read-Only)",
            description: "Run yen ide share host --read-only in the active terminal",
            leadingIcon: "lock.shield",
            searchTags: ["ide", "share", "host", "read only", "pairing", "collaboration"],
            command: "yen ide share host --read-only"
        ),
        TerminalCommandBlueprint(
            id: "ide:share-revoke",
            title: "IDE: Share Revoke",
            description: "Run yen ide share revoke in the active terminal",
            leadingIcon: "xmark.shield",
            searchTags: ["ide", "share", "revoke", "stop", "collaboration", "safety"],
            command: "yen ide share revoke"
        ),
        TerminalCommandBlueprint(
            id: "ide:devcontainer-status",
            title: "IDE: Devcontainer Status",
            description: "Run yen ide devcontainer status in the active terminal",
            leadingIcon: "shippingbox",
            searchTags: ["ide", "devcontainer", "container", "workspace", "status"],
            command: "yen ide devcontainer status"
        ),
        TerminalCommandBlueprint(
            id: "ide:vscode-inventory",
            title: "IDE: VS Code Inventory",
            description: "Run yen ide vscode inventory in the active terminal",
            leadingIcon: "square.stack.3d.up",
            searchTags: ["ide", "vscode", "inventory", "migration", "workspace"],
            command: "yen ide vscode inventory"
        ),
        TerminalCommandBlueprint(
            id: "ide:vscode-import-dry-run",
            title: "IDE: VS Code Import (Dry Run)",
            description: "Run yen ide vscode import --dry-run in the active terminal",
            leadingIcon: "arrow.triangle.branch",
            searchTags: ["ide", "vscode", "import", "migration", "dry run"],
            command: "yen ide vscode import --dry-run"
        ),
        TerminalCommandBlueprint(
            id: "ide:ast-status",
            title: "IDE: AST Status",
            description: "Run yen ide ast status in the active terminal",
            leadingIcon: "point.topleft.down.curvedto.point.bottomright.up",
            searchTags: ["ide", "ast", "syntax", "status", "fallback"],
            command: "yen ide ast status"
        ),
    ]

    static let repositoryWorkspaceActionBlueprints: [RepositoryWorkspaceActionBlueprint] = [
        RepositoryWorkspaceActionBlueprint(
            id: "review:pull-request",
            title: "Review Pull Request",
            description: "Open the desktop PR review workspace with semantic hunk jumps and raw selectable previews",
            leadingIcon: "doc.text.magnifyingglass",
            searchTags: ["pr", "pull request", "review", "github", "diff", "hunk", "raw", "unified", "selectable", "preview"]
        ),
        RepositoryWorkspaceActionBlueprint(
            id: "review:merge-conflicts",
            title: "Resolve Merge Conflicts",
            description: "Open the desktop merge-conflict workspace with semantic hunk jumps and delta-backed previews",
            leadingIcon: "arrow.triangle.merge",
            searchTags: ["merge", "conflict", "rebase", "resolve", "git", "hunk", "delta", "preview"]
        ),
    ]

    static func repositoryWorkspaceActionDescriptorsForTesting(
        workingDirectory: @escaping () -> String?,
        workflowTrustFilePath: String? = nil,
        pullRequestReviewLauncher: @escaping (String) -> Void,
        mergeConflictLauncher: @escaping (String) -> Void
    ) -> [PaletteActionDescriptor] {
        repositoryWorkspaceActionDescriptors(
            workingDirectory: workingDirectory,
            trustContextResolver: { workingDirectory in
                repositoryWorkspaceTrustContext(
                    for: workingDirectory,
                    workflowTrustFilePath: workflowTrustFilePath
                )
            },
            pullRequestReviewLauncher: pullRequestReviewLauncher,
            mergeConflictLauncher: mergeConflictLauncher
        )
    }

    static func terminalCommandInputSteps(for command: String) -> [TerminalCommandInputStep] {
        TerminalSurfaceCommandLauncher.commandInputSteps(for: command).map {
            TerminalCommandInputStep(key: $0.key, text: $0.text)
        }
    }

}
