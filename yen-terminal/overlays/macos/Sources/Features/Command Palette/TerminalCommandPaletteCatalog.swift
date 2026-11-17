// YEN Overlay: command palette action catalog construction.

import AppKit
import SwiftUI
import YENKit

extension TerminalCommandPaletteView {
    /// All commands available in the command palette.
    /// Includes update actions, YEN feature actions, surface jump actions,
    /// and user-configured command-palette entries.
    var actionCatalog: [PaletteActionDescriptor] {
        var actions: [PaletteActionDescriptor] = []
        actions.append(contentsOf: updateActionDescriptors)

        // Decorate-sort-undecorate. The comparator used to rebuild the tab-substituted
        // title for BOTH sides of every comparison, and this whole catalog is rebuilt on
        // each body pass — `query`, `isSearching` and `results` are three separate
        // @Published properties on the same observed model, so one keystroke triggers
        // several passes. Computing the key once per descriptor leaves only the
        // locale-aware compare, and ordering is unchanged.
        let unsorted = yenActionDescriptors + jumpActionDescriptors + terminalActionDescriptors
        let byID = Dictionary(uniqueKeysWithValues: unsorted.map { ($0.id, $0) })
        // Same comparator as sortedTerminalPaletteOptions (upstream 5c952ac/#13872).
        actions.append(contentsOf: sortedTerminalPaletteOptions(unsorted.map(\.commandOption)).compactMap { byID[$0.id] })
        return actions
    }

    /// Built-in YEN feature actions that should be discoverable from Cmd + Shift + P.
    private var yenActionDescriptors: [PaletteActionDescriptor] {
        var actions: [PaletteActionDescriptor] = [
            actionDescriptor(
                id: "settings:open",
                title: "Settings",
                description: "Open Settings",
                symbols: ["⌘", ","],
                leadingIcon: "gearshape",
                searchTags: ["settings", "preferences", "config"]
            ) {
                SettingsController.shared.show()
            },
        ]

        actions.append(contentsOf: Self.settingsDeepLinkDefinitions.map { deepLink in
            actionDescriptor(
                id: deepLink.id,
                title: deepLink.title,
                description: deepLink.description,
                leadingIcon: deepLink.leadingIcon,
                searchTags: ["settings"] + deepLink.title.lowercased().split(separator: " ").map(String.init)
            ) {
                Self.openSettingsDeepLink(deepLink)
            }
        })

        actions.append(contentsOf: [
            actionDescriptor(
                id: "terminal:file-browser",
                title: "File Browser",
                description: "Launch file browser in the active terminal",
                symbols: ["⌘", "⇧", "O"],
                leadingIcon: "folder",
                searchTags: ["files", "browser", "project", "workspace"]
            ) {
                launchFileBrowser()
            },
            Self.gitDrawerActionDescriptor {
                AppDelegate.shared?.toggleGitDrawer(NSApp as Any)
            },
            Self.browserActionDescriptor {
                BrowserCommandService.shared.openDefault(presentation: .window)
            },
            Self.browserSplitActionDescriptor {
                BrowserCommandService.shared.openDefault(
                    presentation: .split,
                    sourceWindow: surfaceView.window
                )
            },
            actionDescriptor(
                id: "terminal:screenshot",
                title: "Take Screenshot",
                description: "Capture the active terminal window and copy to clipboard",
                symbols: ["⌘", "⇧", "S"],
                leadingIcon: "camera",
                searchTags: ["screenshot", "capture", "image", "clipboard"]
            ) {
                AppDelegate.shared?.takeScreenshot(nil)
            },
            actionDescriptor(
                id: "terminal:rename-terminal-title",
                title: "Rename Terminal Title",
                description: "Change the active terminal title override",
                leadingIcon: "character.cursor.ibeam",
                searchTags: ["terminal", "title", "rename", "name"]
            ) {
                presentTerminalTitleRenamePrompt()
            },
        ])

        if Self.shouldShowTabSidebarCommand(tabSidebarEnabled: settingsController.tabSidebarEnabled) {
            actions.append(
                actionDescriptor(
                    id: "workspace:toggle-tab-sidebar",
                    title: "Toggle Tab Sidebar",
                    description: "Show or hide the vertical tab sidebar",
                    symbols: ["⌘", "⇧", "B"],
                    leadingIcon: "sidebar.left",
                    searchTags: ["tabs", "sidebar", "workspace", "rail"]
                ) {
                    TabSidebarController.shared.toggle()
                }
            )
        }

        if activeTerminalController != nil {
            actions.append(
                actionDescriptor(
                    id: "terminal:rename-tab-title",
                    title: "Rename Tab Title",
                    description: "Change the selected tab title override",
                    leadingIcon: "uiwindow.split.2x1",
                    searchTags: ["tab", "title", "rename", "window title", "name"]
                ) {
                    presentTabTitleRenamePrompt()
                }
            )
        }

        if Self.shouldShowSplitLabelCommand(
            splitPaneLabelsEnabled: settingsController.splitPaneLabelsEnabled,
            hasMultiplePanes: activeTerminalController?.surfaceTree.isSplit ?? false
        ) {
            actions.append(
                actionDescriptor(
                    id: "workspace:rename-split-label",
                    title: "Rename Split Label",
                    description: "Change the bottom label for the focused split pane",
                    leadingIcon: "pencil.line",
                    searchTags: ["split", "pane", "label", "rename", "title"]
                ) {
                    presentSplitLabelRenamePrompt()
                }
            )
        }

        if repositoryWorkspaceModel.isRepositoryWorkspace {
            actions.append(contentsOf: Self.repositoryWorkspaceActionDescriptorsForTesting(
                workingDirectory: { surfaceView.pwd },
                pullRequestReviewLauncher: {
                    PullRequestReviewController.shared.show(workingDirectory: $0)
                },
                mergeConflictLauncher: {
                    MergeConflictResolutionController.shared.show(workingDirectory: $0)
                }
            ))
        }

        if Self.shouldShowScratchpadCommand(scratchpadEnabled: settingsController.scratchpadEnabled) {
            actions.append(
                actionDescriptor(
                    id: "workspace:toggle-scratchpad",
                    title: "Toggle Scratchpad",
                    description: "Show or hide the right-side scratchpad panel",
                    symbols: ["⌘", "⇧", "J"],
                    leadingIcon: "square.and.pencil",
                    searchTags: ["scratchpad", "notes", "panel", "workspace"]
                ) {
                    ScratchpadController.shared.toggle()
                }
            )
        }

        actions.append(contentsOf: ideActionDescriptors)

        actions.append(
            contentsOf: Self.shellCommandBlueprints.map { blueprint in
                actionDescriptor(
                    id: blueprint.id,
                    title: blueprint.title,
                    description: blueprint.description,
                    leadingIcon: blueprint.leadingIcon,
                    searchTags: blueprint.searchTags
                ) {
                    sendTerminalCommand(blueprint.command)
                }
            }
        )

        actions.append(contentsOf: windowBorderActionDescriptors)
        actions.append(contentsOf: layoutActionDescriptors)
        return actions
    }

    /// Commands for installing or canceling available updates.
    private var updateActionDescriptors: [PaletteActionDescriptor] {
        guard let updateViewModel else { return [] }

        var descriptors: [PaletteActionDescriptor] = []

        if updateViewModel.state.isInstallable {
            let title: String
            if case .updateAvailable = updateViewModel.state {
                title = "Update YEN and Restart"
            } else {
                title = updateViewModel.text
            }

            descriptors.append(
                actionDescriptor(
                    id: "update:install",
                    title: title,
                    description: updateViewModel.description,
                    leadingIcon: updateViewModel.iconName ?? "shippingbox.fill",
                    badge: updateViewModel.badge,
                    emphasis: true,
                    searchTags: ["update", "install", "restart", "version"]
                ) {
                    updateViewModel.state.confirm()
                }
            )
        }

        // Only offer the cancel command when the state actually has something
        // to cancel (upstream ccb08f35).
        if updateViewModel.state.isCancellable {
            descriptors.append(
                actionDescriptor(
                    id: "update:cancel",
                    title: "Cancel or Skip Update",
                    description: "Dismiss the current update process",
                    searchTags: ["update", "cancel", "skip"]
                ) {
                    updateViewModel.state.cancel()
                }
            )
        }

        return descriptors
    }

    /// Custom commands from the command-palette-entry configuration.
    private var terminalActionDescriptors: [PaletteActionDescriptor] {
        customCommandInvalidationKeys
            .map { entry in
                let searchTags = actionTokenTags(entry.action)
                return actionDescriptor(
                    id: "custom:\(entry.index):\(entry.action)",
                    title: entry.title,
                    description: entry.description,
                    symbols: entry.symbols,
                    searchTags: searchTags
                ) {
                    onAction(entry.action)
                }
            }
    }

    private var ideActionDescriptors: [PaletteActionDescriptor] {
        var actions = Self.ideQuickActionBlueprints.map { blueprint in
            actionDescriptor(
                id: blueprint.id,
                title: blueprint.title,
                description: blueprint.description,
                leadingIcon: blueprint.leadingIcon,
                searchTags: blueprint.searchTags
            ) {
                sendTerminalCommand(blueprint.command)
            }
        }
        actions.append(
            actionDescriptor(
                id: "ide:open-location",
                title: "IDE: Open Editor Target",
                description: "Insert yen ide open at the active terminal prompt",
                leadingIcon: "arrow.up.forward.app",
                searchTags: ["ide", "open", "editor", "goto", "location", "handoff"]
            ) {
                insertHistoryCommand("yen ide open ")
            }
        )
        actions.append(
            actionDescriptor(
                id: "ide:debug-start",
                title: "IDE: Start Debug Session",
                description: "Insert yen ide debug start at the active terminal prompt",
                leadingIcon: "play.circle",
                searchTags: ["ide", "debug", "debugger", "launch", "breakpoint", "target"]
            ) {
                insertHistoryCommand("yen ide debug start ")
            }
        )
        return actions
    }

    /// Commands for jumping to other terminal surfaces.
    private var jumpActionDescriptors: [PaletteActionDescriptor] {
        jumpTargetsModel.snapshots.map { snapshot in
            let displayColor = snapshot.tabColor != .none ? snapshot.tabColor : nil

            return actionDescriptor(
                id: "jump:\(snapshot.objectID)",
                title: "Focus: \(snapshot.title)",
                subtitle: snapshot.subtitle,
                leadingIcon: "rectangle.on.rectangle",
                leadingColor: displayColor?.displayColor.map { Color($0) },
                sortKey: snapshot.objectID,
                searchTags: ["focus", "terminal", "tab", "window"]
            ) {
                NotificationCenter.default.post(
                    name: YEN.Notification.yenPresentTerminal,
                    object: snapshot.surface
                )
            }
        }
    }

    /// Layout presets dispatched through the same SettingsController path as Cmd + Option + 1-0.
    private var layoutActionDescriptors: [PaletteActionDescriptor] {
        LayoutTemplate.allCases.enumerated().map { index, layout in
            actionDescriptor(
                id: "layout:\(index)",
                title: "Layout: \(layout.displayName)",
                description: "Apply the \(layout.displayName) split layout",
                symbols: ["⌘", "⌥", layoutShortcutSymbol(for: index)],
                leadingIcon: layout.commandPaletteIconName,
                // Layout titles are unique (`Layout: <displayName>`), so the
                // ObjectIdentifier tie-break is unused. The old AnySortKey(index)
                // cannot be expressed after upstream 5c952ac/#13872.
                sortKey: nil,
                searchTags: ["layout", "split", "workspace"] + layout.displayName.lowercased().split(separator: " ").map(String.init)
            ) {
                SettingsController.shared.applyLayout(layout)
            }
        }
    }

    private var windowBorderActionDescriptors: [PaletteActionDescriptor] {
        Self.buildWindowBorderActionSnapshots(
            borderEnabled: settingsController.windowBorderEnabled,
            colorMode: settingsController.windowBorderColorMode,
            focusedPalette: settingsController.windowBorderFocusedPalette,
            unfocusedPalette: settingsController.windowBorderUnfocusedPalette,
            matchThemeUsesManualFallback: settingsController.windowBorderMatchThemeUsesManualFallback,
            resolvedThemeName: settingsController.windowBorderResolvedThemeName,
            reduceMotion: reduceMotion,
            differentiateWithoutColor: differentiateWithoutColor
        ).map { snapshot in
            actionDescriptor(
                id: snapshot.id,
                title: snapshot.title,
                description: snapshot.description,
                leadingIcon: snapshot.leadingIcon,
                searchTags: snapshot.searchTags
            ) {
                performWindowBorderAction(snapshot.id)
            }
        }
    }

    private func actionDescriptor(
        id: String,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        symbols: [String]? = nil,
        leadingIcon: String? = nil,
        leadingColor: Color? = nil,
        badge: String? = nil,
        emphasis: Bool = false,
        sortKey: ObjectIdentifier? = nil,
        searchTags: [String] = [],
        execute: @escaping () -> Void
    ) -> PaletteActionDescriptor {
        PaletteActionDescriptor(
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
            searchTags: searchTags,
            execute: execute
        )
    }

    static func repositoryWorkspaceActionDescriptors(
        workingDirectory: @escaping () -> String?,
        trustContextResolver: @escaping (String?) -> RepositoryWorkspaceTrustContext?,
        pullRequestReviewLauncher: @escaping (String) -> Void,
        mergeConflictLauncher: @escaping (String) -> Void
    ) -> [PaletteActionDescriptor] {
        repositoryWorkspaceActionBlueprints.map { blueprint in
            PaletteActionDescriptor(
                id: blueprint.id,
                title: blueprint.title,
                subtitle: nil,
                description: blueprint.description,
                symbols: nil,
                leadingIcon: blueprint.leadingIcon,
                leadingColor: nil,
                badge: nil,
                emphasis: false,
                sortKey: nil,
                searchTags: blueprint.searchTags
            ) {
                guard let trustedRepositoryContext = trustContextResolver(workingDirectory()) else {
                    return
                }
                switch blueprint.id {
                case "review:pull-request":
                    pullRequestReviewLauncher(trustedRepositoryContext.workingDirectory)
                case "review:merge-conflicts":
                    mergeConflictLauncher(trustedRepositoryContext.workingDirectory)
                default:
                    break
                }
            }
        }
    }

    private func actionTokenTags(_ action: String) -> [String] {
        action
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func layoutShortcutSymbol(for index: Int) -> String {
        index == 9 ? "0" : String(index + 1)
    }

    static func buildWindowBorderActionSnapshots(
        borderEnabled: Bool,
        colorMode: WindowBorderColorMode,
        focusedPalette: WindowBorderPalette,
        unfocusedPalette: WindowBorderPalette,
        matchThemeUsesManualFallback: Bool,
        resolvedThemeName: String?,
        reduceMotion: Bool,
        differentiateWithoutColor: Bool
    ) -> [WindowBorderActionSnapshot] {
        [
            .init(
                id: "window-border:toggle",
                title: "Window Border: Toggle",
                description: borderEnabled
                    ? "Disable the chromatic border around terminal windows"
                    : "Enable the chromatic border around terminal windows",
                leadingIcon: borderEnabled ? "rectangle.slash" : "rectangle",
                searchTags: ["window", "border", "chrome"]
            ),
            .init(
                id: "window-border:match-theme",
                title: "Window Border: Toggle Match Theme",
                description: windowBorderMatchThemeDescription(
                    colorMode: colorMode,
                    matchThemeUsesManualFallback: matchThemeUsesManualFallback,
                    resolvedThemeName: resolvedThemeName
                ),
                leadingIcon: colorMode == .matchTheme ? "paintbrush.pointed" : "swatchpalette",
                searchTags: ["window", "border", "theme", "colors", "manual", "match theme"]
            ),
            .init(
                id: "window-border:cycle-focused",
                title: "Window Border: Cycle Focused Palette",
                description: colorMode == .matchTheme
                    ? "Unavailable in Match Theme mode"
                    : "Focused palette: \(focusedPalette.displayName)",
                leadingIcon: "circle.lefthalf.filled",
                searchTags: ["window", "border", "focused", "palette", "colors"] + windowBorderPaletteSearchTags(focusedPalette)
            ),
            .init(
                id: "window-border:cycle-unfocused",
                title: "Window Border: Cycle Unfocused Palette",
                description: colorMode == .matchTheme
                    ? "Unavailable in Match Theme mode"
                    : "Unfocused palette: \(unfocusedPalette.displayName)",
                leadingIcon: "circle.dashed.inset.filled",
                searchTags: ["window", "border", "unfocused", "palette", "colors"] + windowBorderPaletteSearchTags(unfocusedPalette)
            ),
            .init(
                id: "window-border:reduce-motion",
                title: "Window Border: Open Reduce Motion Settings",
                description: reduceMotion
                    ? "Reduce Motion is currently enabled in macOS."
                    : "Open macOS Accessibility > Display to control Reduce Motion behavior.",
                leadingIcon: "accessibility",
                searchTags: ["window", "border", "reduce motion", "accessibility"]
            ),
            .init(
                id: "window-border:differentiate-without-color",
                title: "Window Border: Open Differentiate Without Color Settings",
                description: differentiateWithoutColor
                    ? "Differentiate Without Color is enabled, so unfocused borders currently use dashed outlines."
                    : "Open macOS Accessibility > Display to control dashed unfocused border outlines.",
                leadingIcon: "circle.dashed",
                searchTags: ["window", "border", "differentiate without color", "accessibility"]
            ),
        ]
    }

    private func performWindowBorderAction(_ actionID: String) {
        switch actionID {
        case "window-border:toggle":
            settingsController.toggleWindowBorderEnabled()
        case "window-border:match-theme":
            settingsController.windowBorderColorMode = settingsController.windowBorderColorMode == .matchTheme
                ? .manual
                : .matchTheme
        case "window-border:cycle-focused":
            settingsController.cycleWindowBorderFocusedPalette()
        case "window-border:cycle-unfocused":
            settingsController.cycleWindowBorderUnfocusedPalette()
        case "window-border:reduce-motion":
            settingsController.openReduceMotionSettings()
        case "window-border:differentiate-without-color":
            settingsController.openDifferentiateWithoutColorSettings()
        default:
            break
        }
    }

    private static func windowBorderMatchThemeDescription(
        colorMode: WindowBorderColorMode,
        matchThemeUsesManualFallback: Bool,
        resolvedThemeName: String?
    ) -> String {
        if colorMode == .matchTheme {
            if matchThemeUsesManualFallback {
                return "Match Theme is on, but the theme is unresolved; currently using manual fallback colors"
            }
            if let themeName = resolvedThemeName {
                return "Using active theme (\(themeName)); switch to manual focused/unfocused palettes"
            }
            return "Use manual focused/unfocused palettes"
        }
        return "Derive border colors from the active terminal theme"
    }

    private static func windowBorderPaletteSearchTags(_ palette: WindowBorderPalette) -> [String] {
        let displayName = palette.displayName.lowercased()
        let collapsed = displayName.replacingOccurrences(of: " ", with: "")
        return collapsed == displayName ? [displayName] : [displayName, collapsed]
    }

}
