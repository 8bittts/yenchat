// YEN Overlay: replaces upstream macos/Sources/Features/Command Palette/TerminalCommandPalette.swift
//
// Divergence from upstream:
//   - descriptor-backed action catalog so empty-query command launching and non-empty
//     mixed search results share one action source of truth
//   - overlay-owned palette search integration using the shipped CLI search contract
//     (files/symbols/content/history/actions, source labels, deterministic ordering)
//   - search execution targets stay value-oriented; row actions resolve through the
//     current palette session instead of retaining terminal objects in search state
//   - clipboard-backed history insertion for terminal-safe prompt recall
//
// Upstream sections preserved conceptually: update actions, terminal actions, jump actions,
// layout options, window-border actions, and ResponderChainInjector remain palette semantics.
// Merge strategy on a vendor bump: diff upstream TerminalCommandPalette.swift and merge generic
// command additions while keeping search orchestration in overlay-owned code.

import AppKit
import SwiftUI
import YENKit

/// Shared title/sort-key order for terminal palette rows.
/// Upstream 5c952ac/#13872 extracted this so CommandPaletteTests can exercise
/// equal-title ObjectIdentifier tie-breaks. YEN's catalog is descriptor-backed
/// and does not call this on the render path, but the TEST target does — keep
/// it verbatim even though it is dead code for the app.
func sortedTerminalPaletteOptions(_ options: [CommandOption]) -> [CommandOption] {
    options.sorted { lhs, rhs in
        let lhsTitle = lhs.title.replacingOccurrences(of: ":", with: "\t")
        let rhsTitle = rhs.title.replacingOccurrences(of: ":", with: "\t")
        let comparison = lhsTitle.localizedCaseInsensitiveCompare(rhsTitle)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        if let lhsKey = lhs.sortKey, let rhsKey = rhs.sortKey {
            return lhsKey < rhsKey
        }
        return false
    }
}

struct TerminalCommandPaletteView: View {
    /// The surface that this command palette represents.
    let surfaceView: YEN.SurfaceView

    /// Set this to true to show the view, this will be set to false if any actions
    /// result in the view disappearing.
    @Binding var isPresented: Bool

    /// The configuration so we can lookup keyboard shortcuts.
    @ObservedObject var yenConfig: YEN.Config

    /// Shared settings controller for app-level actions surfaced in the palette.
    @ObservedObject var settingsController: SettingsController

    /// The update view model for showing update commands.
    var updateViewModel: UpdateViewModel?

    /// The callback when an action is submitted.
    var onAction: ((String) -> Void)
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @StateObject private var searchModel: TerminalCommandPaletteSearchModel
    @StateObject var repositoryWorkspaceModel: TerminalCommandPaletteRepositoryWorkspaceModel
    @StateObject var jumpTargetsModel: TerminalCommandPaletteJumpTargetsModel
    /// Hosts discovery runs only while a palette is visible (RemoteHostsStore).
    @ObservedObject var hostsStore: RemoteHostsStore
    @State private var suppressSurfaceRefocusOnDismiss = false
    @State private var dismissalHandled = false

    init(
        surfaceView: YEN.SurfaceView,
        isPresented: Binding<Bool>,
        yenConfig: YEN.Config,
        settingsController: SettingsController,
        updateViewModel: UpdateViewModel?,
        hostsStore: RemoteHostsStore? = nil,
        onAction: @escaping ((String) -> Void)
    ) {
        self.surfaceView = surfaceView
        _isPresented = isPresented
        self.yenConfig = yenConfig
        self.settingsController = settingsController
        self.updateViewModel = updateViewModel
        self.onAction = onAction
        self.hostsStore = hostsStore ?? .shared
        _searchModel = StateObject(wrappedValue: TerminalCommandPaletteSearchModel())
        _repositoryWorkspaceModel = StateObject(
            wrappedValue: TerminalCommandPaletteRepositoryWorkspaceModel()
        )
        _jumpTargetsModel = StateObject(
            wrappedValue: TerminalCommandPaletteJumpTargetsModel()
        )
    }

    var body: some View {
        ZStack {
            if let paletteActions = Self.visibleActionCatalog(
                isPresented: isPresented,
                build: { actionCatalog }
            ) {
                let actionCatalogInvalidationKey = actionCatalogInvalidationKey
                let presentationState = Self.presentationState(
                    query: searchModel.query,
                    isSearching: searchModel.isSearching,
                    paletteActions: paletteActions,
                    searchResults: searchModel.results,
                    openLocation: openSearchResultLocation,
                    insertHistoryCommand: insertHistoryCommand
                )

                GeometryReader { geometry in
                    VStack {
                        Spacer().frame(height: geometry.size.height * 0.05)

                        ResponderChainInjector(responder: surfaceView)
                            .frame(width: 0, height: 0)

                        CommandPaletteView(
                            isPresented: $isPresented,
                            backgroundColor: yenConfig.backgroundColor,
                            options: paletteActions.map(\.commandOption),
                            externalQuery: $searchModel.query,
                            displayedOptions: presentationState.displayedOptions,
                            emptyStateText: presentationState.emptyStateText,
                            onQueryChange: { searchModel.queryDidChange(to: $0) },
                            onWillSelectOption: { prepareForOptionSelection(id: $0.id) },
                            onDismiss: { handleDismissal() }
                        )
                        .zIndex(1)

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
                .onAppear {
                    dismissalHandled = false
                    jumpTargetsModel.start()
                    hostsStore.surfaceDidAppear(surfaceView)
                    refreshRepositoryWorkspaceActions()
                    syncSearchCatalog(with: paletteActions)
                }
                .onDisappear {
                    jumpTargetsModel.stop()
                    hostsStore.surfaceDidDisappear(surfaceView)
                }
                .onChange(of: surfaceView.pwd) { _ in
                    refreshRepositoryWorkspaceActions()
                }
                .onChange(of: actionCatalogInvalidationKey) { _ in
                    // Rebuild from the models: this single-parameter closure
                    // carries the previous body's `paletteActions`, which left
                    // search one update behind (Hosts rows arrive after open).
                    syncSearchCatalog(with: actionCatalog)
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            if !newValue {
                handleDismissal()
            } else {
                dismissalHandled = false
            }
        }
    }

    private func handleDismissal() {
        guard !dismissalHandled else { return }
        dismissalHandled = true
        jumpTargetsModel.stop()
        hostsStore.surfaceDidDisappear(surfaceView)
        repositoryWorkspaceModel.reset()
        searchModel.resetSession()
        let shouldRestoreSurfaceFocus = Self.shouldRestoreSurfaceFocusOnDismiss(
            suppressSurfaceRefocusOnDismiss: suppressSurfaceRefocusOnDismiss,
            surfaceWindowIsKey: surfaceView.window?.isKeyWindow == true
        )
        suppressSurfaceRefocusOnDismiss = false

        if shouldRestoreSurfaceFocus {
            // Let SwiftUI tear down the field editor before restoring the terminal.
            // An immediate responder change can be overwritten by the disappearing
            // TextField, leaving the window itself as first responder.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = surfaceView.window, window.isKeyWindow else { return }
                window.makeFirstResponder(surfaceView)
            }
        }
    }

    private func refreshRepositoryWorkspaceActions() {
        guard isPresented else {
            repositoryWorkspaceModel.reset()
            return
        }

        repositoryWorkspaceModel.refresh(workingDirectory: surfaceView.pwd)
    }

    private func syncSearchCatalog(with actions: [PaletteActionDescriptor]) {
        searchModel.refreshContext(
            projectDirectory: surfaceView.pwd,
            actions: actions.map(\.searchDescriptor)
        )
    }

    private func prepareForOptionSelection(id: String) {
        suppressSurfaceRefocusOnDismiss = Self.shouldSuppressSurfaceRefocusOnDismiss(for: id)
    }

    func presentSplitLabelRenamePrompt() {
        restoreSurfaceFocusThen {
            surfaceView.promptSplitPaneLabel()
        }
    }

    func presentTerminalTitleRenamePrompt() {
        restoreSurfaceFocusThen {
            surfaceView.promptTitle()
        }
    }

    func presentTabTitleRenamePrompt() {
        guard let activeTerminalController else { return }
        restoreSurfaceFocusThen {
            activeTerminalController.promptTabTitle()
        }
    }

    /// Re-focuses the terminal surface, then runs `prompt` on the main queue. Shared by the
    /// split-label / title / tab-title rename prompts; the per-prompt trailing call stays at the site.
    private func restoreSurfaceFocusThen(_ prompt: @escaping @MainActor () -> Void) {
        suppressSurfaceRefocusOnDismiss = true
        DispatchQueue.main.async {
            if let window = surfaceView.window {
                window.makeFirstResponder(surfaceView)
            } else {
                YEN.moveFocus(to: surfaceView)
            }
            prompt()
        }
    }

    var activeTerminalController: BaseTerminalController? {
        // Resolve through split-tree ownership, not the view's `window`: while
        // AppKit attaches or moves a native tab, a surface's window is briefly
        // nil or still points at its previous one, which would drop the palette's
        // controller and invalidate its action catalog mid-move.
        BaseTerminalController.controller(owning: surfaceView)
    }

    private var actionCatalogInvalidationKey: ActionCatalogInvalidationKey {
        let activeTerminalController = activeTerminalController
        return Self.actionCatalogInvalidationKey(
            isPresented: isPresented,
            workingDirectory: surfaceView.pwd,
            isRepositoryWorkspace: repositoryWorkspaceModel.isRepositoryWorkspace,
            jumpTargets: jumpTargetsModel.snapshots.map(ActionCatalogJumpTargetKey.init(snapshot:)),
            updateAction: Self.updateActionInvalidationKey(from: updateViewModel),
            tabSidebarEnabled: settingsController.tabSidebarEnabled,
            splitPaneLabelsEnabled: settingsController.splitPaneLabelsEnabled,
            hasActiveTerminalController: activeTerminalController != nil,
            hasMultiplePanes: activeTerminalController?.surfaceTree.isSplit ?? false,
            scratchpadEnabled: settingsController.scratchpadEnabled,
            windowBorderEnabled: settingsController.windowBorderEnabled,
            windowBorderScope: settingsController.windowBorderScope,
            windowBorderColorMode: settingsController.windowBorderColorMode,
            windowBorderFocusedPalette: settingsController.windowBorderFocusedPalette,
            windowBorderUnfocusedPalette: settingsController.windowBorderUnfocusedPalette,
            windowBorderMatchThemeUsesManualFallback: settingsController.windowBorderMatchThemeUsesManualFallback,
            windowBorderResolvedThemeName: settingsController.windowBorderResolvedThemeName,
            reduceMotion: reduceMotion,
            differentiateWithoutColor: differentiateWithoutColor,
            customCommands: customCommandInvalidationKeys,
            hosts: hostsEntries
        )
    }

    /// The Hosts rows for the current store state. A session already shown by
    /// a pane here reads "Open in YEN" and focuses that pane.
    var hostsEntries: [RemoteHostsPaletteEntry] {
        let open = jumpTargetsModel.snapshots.compactMap { $0.surface.remotePaneIdentity }
        return RemoteHostsPaletteRows.entries(
            snapshot: hostsStore.snapshot,
            isOpenHere: { identity in open.contains { $0.isSameSession(as: identity) } }
        )
    }

    var customCommandInvalidationKeys: [ActionCatalogCustomCommandKey] {
        guard let appDelegate = AppDelegate.shared else { return [] }
        return Self.customCommandInvalidationKeys(
            entries: appDelegate.yen.config.commandPaletteEntries,
            keyboardShortcutSymbols: {
                appDelegate.yen.config.keyboardShortcut(for: $0)?.keyList
            }
        )
    }


}

extension LayoutTemplate {
    var commandPaletteIconName: String {
        switch self {
        case .singlePane: return "rectangle"
        case .threeColumns: return "rectangle.split.3x1"
        case .rightStack: return "rectangle.split.2x1"
        case .bottomStack: return "rectangle.split.1x2"
        case .quad: return "square.grid.2x2"
        case .eastward13: return "rectangle.split.2x1"
        case .eastward21: return "rectangle.split.2x1"
        case .eastward23: return "rectangle.split.3x1"
        case .centerStage: return "rectangle.split.3x1"
        case .threeColumnBottom: return "rectangle.split.3x1"
        }
    }
}

/// This is done to ensure that the given view is in the responder chain.
fileprivate struct ResponderChainInjector: NSViewRepresentable {
    let responder: NSResponder

    func makeNSView(context: Context) -> NSView {
        let dummy = NSView()
        DispatchQueue.main.async {
            dummy.nextResponder = responder
        }
        return dummy
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
