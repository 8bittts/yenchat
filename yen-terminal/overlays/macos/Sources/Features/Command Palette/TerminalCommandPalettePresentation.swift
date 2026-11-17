// YEN Overlay: command palette search-result presentation mapping.

import AppKit
import SwiftUI
import YENKit

extension TerminalCommandPaletteView {
    static func presentationStateForTesting(
        query: String,
        isSearching: Bool,
        paletteActions: [PaletteActionDescriptor],
        searchResults: [TerminalCommandPaletteSearchResult]
    ) -> PalettePresentationState {
        presentationState(
            query: query,
            isSearching: isSearching,
            paletteActions: paletteActions,
            searchResults: searchResults,
            openLocation: { _ in },
            insertHistoryCommand: { _ in }
        )
    }

    static func actionCatalogInvalidationKeyForTesting(
        isPresented: Bool,
        workingDirectory: String?,
        isRepositoryWorkspace: Bool,
        jumpTargets: [ActionCatalogJumpTargetKey],
        updateAction: ActionCatalogUpdateKey?,
        tabSidebarEnabled: Bool,
        splitPaneLabelsEnabled: Bool,
        hasActiveTerminalController: Bool,
        hasMultiplePanes: Bool,
        scratchpadEnabled: Bool,
        windowBorderEnabled: Bool,
        windowBorderColorMode: WindowBorderColorMode,
        windowBorderFocusedPalette: WindowBorderPalette,
        windowBorderUnfocusedPalette: WindowBorderPalette,
        windowBorderMatchThemeUsesManualFallback: Bool,
        windowBorderResolvedThemeName: String?,
        reduceMotion: Bool,
        differentiateWithoutColor: Bool,
        customCommands: [ActionCatalogCustomCommandKey]
    ) -> ActionCatalogInvalidationKey {
        actionCatalogInvalidationKey(
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

    static func windowBorderActionSnapshotsForTesting(
        borderEnabled: Bool,
        colorMode: WindowBorderColorMode,
        focusedPalette: WindowBorderPalette,
        unfocusedPalette: WindowBorderPalette,
        matchThemeUsesManualFallback: Bool,
        resolvedThemeName: String?,
        reduceMotion: Bool,
        differentiateWithoutColor: Bool
    ) -> [WindowBorderActionSnapshot] {
        buildWindowBorderActionSnapshots(
            borderEnabled: borderEnabled,
            colorMode: colorMode,
            focusedPalette: focusedPalette,
            unfocusedPalette: unfocusedPalette,
            matchThemeUsesManualFallback: matchThemeUsesManualFallback,
            resolvedThemeName: resolvedThemeName,
            reduceMotion: reduceMotion,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    static func actionCatalogInvalidationKey(
        isPresented: Bool,
        workingDirectory: String?,
        isRepositoryWorkspace: Bool,
        jumpTargets: [ActionCatalogJumpTargetKey],
        updateAction: ActionCatalogUpdateKey?,
        tabSidebarEnabled: Bool,
        splitPaneLabelsEnabled: Bool,
        hasActiveTerminalController: Bool,
        hasMultiplePanes: Bool,
        scratchpadEnabled: Bool,
        windowBorderEnabled: Bool,
        windowBorderColorMode: WindowBorderColorMode,
        windowBorderFocusedPalette: WindowBorderPalette,
        windowBorderUnfocusedPalette: WindowBorderPalette,
        windowBorderMatchThemeUsesManualFallback: Bool,
        windowBorderResolvedThemeName: String?,
        reduceMotion: Bool,
        differentiateWithoutColor: Bool,
        customCommands: [ActionCatalogCustomCommandKey]
    ) -> ActionCatalogInvalidationKey {
        ActionCatalogInvalidationKey(
            isPresented: isPresented,
            workingDirectory: workingDirectory,
            isRepositoryWorkspace: isRepositoryWorkspace,
            jumpTargets: jumpTargets,
            availability: ActionCatalogAvailabilityKey(
                updateAction: updateAction,
                tabSidebarEnabled: tabSidebarEnabled,
                splitPaneLabelsEnabled: splitPaneLabelsEnabled,
                hasActiveTerminalController: hasActiveTerminalController,
                hasMultiplePanes: hasMultiplePanes,
                scratchpadEnabled: scratchpadEnabled,
                windowBorder: ActionCatalogWindowBorderKey(
                    enabled: windowBorderEnabled,
                    colorMode: windowBorderColorMode,
                    focusedPalette: windowBorderFocusedPalette,
                    unfocusedPalette: windowBorderUnfocusedPalette,
                    matchThemeUsesManualFallback: windowBorderMatchThemeUsesManualFallback,
                    resolvedThemeName: windowBorderResolvedThemeName,
                    reduceMotion: reduceMotion,
                    differentiateWithoutColor: differentiateWithoutColor
                ),
                customCommands: customCommands
            )
        )
    }

    static func updateActionInvalidationKey(
        from updateViewModel: UpdateViewModel?
    ) -> ActionCatalogUpdateKey? {
        guard let updateViewModel else { return nil }

        let isInstallable = updateViewModel.state.isInstallable
        let isCancellable = updateViewModel.state.isCancellable
        guard isInstallable || isCancellable else { return nil }

        let title: String?
        if !isInstallable {
            title = nil
        } else if case .updateAvailable = updateViewModel.state {
            title = "Update YEN and Restart"
        } else {
            title = updateViewModel.text
        }

        return ActionCatalogUpdateKey(
            title: title,
            description: isInstallable ? updateViewModel.description : nil,
            iconName: isInstallable ? updateViewModel.iconName : nil,
            badge: isInstallable ? updateViewModel.badge : nil,
            isCancellable: isCancellable
        )
    }

    static func customCommandInvalidationKeys(
        entries: [YEN.Command],
        keyboardShortcutSymbols: (String) -> [String]?
    ) -> [ActionCatalogCustomCommandKey] {
        entries
            .filter(\.isSupported)
            .enumerated()
            .map { index, entry in
                ActionCatalogCustomCommandKey(
                    index: index,
                    action: entry.action,
                    title: entry.title,
                    description: entry.description,
                    symbols: keyboardShortcutSymbols(entry.action)
                )
            }
    }

    static func presentationState(
        query: String,
        isSearching: Bool,
        paletteActions: [PaletteActionDescriptor],
        searchResults: [TerminalCommandPaletteSearchResult],
        openLocation: @escaping (TerminalCommandPaletteLocation) -> Void,
        insertHistoryCommand: @escaping (String) -> Void
    ) -> PalettePresentationState {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionLookup = Dictionary(uniqueKeysWithValues: paletteActions.map { ($0.id, $0) })
        let displayedOptions = displayedOptions(
            trimmedQuery: trimmedQuery,
            paletteActions: paletteActions,
            actionLookup: actionLookup,
            searchResults: searchResults,
            openLocation: openLocation,
            insertHistoryCommand: insertHistoryCommand
        )
        let emptyStateText = trimmedQuery.isEmpty
            ? "No matches"
            : (isSearching ? "Searching..." : "No matches")
        return PalettePresentationState(
            displayedOptions: displayedOptions,
            emptyStateText: emptyStateText
        )
    }

    private static func displayedOptions(
        trimmedQuery: String,
        paletteActions: [PaletteActionDescriptor],
        actionLookup: [String: PaletteActionDescriptor],
        searchResults: [TerminalCommandPaletteSearchResult],
        openLocation: @escaping (TerminalCommandPaletteLocation) -> Void,
        insertHistoryCommand: @escaping (String) -> Void
    ) -> [CommandOption] {
        if trimmedQuery.isEmpty {
            return paletteActions.map(\.commandOption)
        }

        return searchResults.compactMap { result in
            commandOption(
                for: result,
                actionLookup: actionLookup,
                openLocation: openLocation,
                insertHistoryCommand: insertHistoryCommand
            )
        }
    }

    private static func commandOption(
        for result: TerminalCommandPaletteSearchResult,
        actionLookup: [String: PaletteActionDescriptor],
        openLocation: @escaping (TerminalCommandPaletteLocation) -> Void,
        insertHistoryCommand: @escaping (String) -> Void
    ) -> CommandOption? {
        switch result.execution {
        case .action(let id):
            guard let action = actionLookup[id] else { return nil }
            return CommandOption(
                id: "search:action:\(id)",
                title: result.title,
                subtitle: result.subtitle,
                description: action.description,
                symbols: action.symbols,
                leadingIcon: action.leadingIcon ?? sourceIcon(for: result.source),
                leadingColor: action.leadingColor,
                badge: result.source.rawValue,
                emphasis: action.emphasis,
                action: action.execute
            )
        case .openLocation(let location):
            let description: String
            switch result.source {
            case .symbol:
                description = "Open matching symbol definition in the editor"
            case .diagnostic:
                description = "Open matching diagnostic location in the editor"
            default:
                description = location.line == nil
                    ? "Open file in the default editor"
                    : "Open matching file location in the editor"
            }
            return CommandOption(
                id: "search:\(result.source.rawValue):\(result.targetKey)",
                title: result.title,
                subtitle: result.subtitle,
                description: description,
                leadingIcon: sourceIcon(for: result.source),
                badge: result.source.rawValue
            ) {
                openLocation(location)
            }
        case .insertHistoryCommand(let command):
            return CommandOption(
                id: "search:history:\(result.targetKey)",
                title: result.title,
                subtitle: result.subtitle,
                description: "Insert command at the active terminal prompt",
                leadingIcon: sourceIcon(for: result.source),
                badge: result.source.rawValue
            ) {
                insertHistoryCommand(command)
            }
        }
    }

    static func lineAwareEditorLaunchPlan(
        applicationName: String,
        bundleIdentifier: String?,
        path: String,
        line: Int,
        column: Int?
    ) -> EditorLaunchPlan? {
        IDEEditorNavigator.lineAwareEditorLaunchPlan(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            path: path,
            line: line,
            column: column
        )
    }

    private static func sourceIcon(for source: TerminalCommandPaletteResultSource) -> String {
        switch source {
        case .action:
            return "command"
        case .symbol:
            return "curlybraces"
        case .file:
            return "doc.text"
        case .content:
            return "text.magnifyingglass"
        case .diagnostic:
            return "exclamationmark.bubble"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

}
