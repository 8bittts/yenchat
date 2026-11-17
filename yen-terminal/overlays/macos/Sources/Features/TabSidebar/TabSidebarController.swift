#if os(macOS)
import Cocoa
import Combine
import SwiftUI

/// Manages the vertical tab sidebar panel.
/// Singleton. Reads tab state from NSWindowTabGroup, dispatches existing terminal APIs,
/// and coordinates transient floating vs persistent docked presentation.
@MainActor
final class TabSidebarController: TabSidebarDataSource, NSMenuItemValidation {
    static let shared = TabSidebarController()
    nonisolated static let metadataFallbackRefreshInterval: TimeInterval = 2
    nonisolated static let metadataFallbackRefreshTolerance: TimeInterval = 0.4
    nonisolated static let panelWidth: CGFloat = 300
    nonisolated static let defaultTransientAnimationDuration = SlidingUtilityPanel.defaultAnimationDuration
    nonisolated static let tabSidebarEnabledPreferenceKey = "com.yenchat.yen.tabSidebarEnabled"
    nonisolated static let presentationModePreferenceKey = "com.yenchat.yen.tabSidebarPresentationMode"
    nonisolated static let persistentVisiblePreferenceKey = "com.yenchat.yen.tabSidebarPersistentVisible"
    private lazy var observationSession = TabSidebarObservationSession { [weak self] in
        self?.refreshTabs(rescan: false)
    }
    private static let metadataCache = TabSidebarMetadataCache()

    private struct MetadataCacheKey: Equatable {
        let focusedSurfaceID: UUID?
        let rawWorkingDirectory: String?
    }

    private struct MetadataValue {
        let trustedWorkingDirectory: String?
        let cwdSummary: String?
    }

    @MainActor
    private final class TabSidebarMetadataCache {
        private final class Entry {
            weak var window: NSWindow?
            let key: MetadataCacheKey
            let value: MetadataValue
            let expiresAt: Date

            init(window: NSWindow, key: MetadataCacheKey, value: MetadataValue, referenceDate: Date) {
                self.window = window
                self.key = key
                self.value = value
                expiresAt = referenceDate.addingTimeInterval(TabSidebarGitContextCache.refreshInterval)
            }
        }

        private var entries: [ObjectIdentifier: Entry] = [:]
#if DEBUG
        private(set) var buildCount = 0
#endif

        func value(
            for window: NSWindow,
            key: MetadataCacheKey,
            referenceDate: Date,
            build: () -> MetadataValue
        ) -> MetadataValue {
            let id = ObjectIdentifier(window)
            if let entry = entries[id] {
                if entry.window === window, entry.key == key, referenceDate < entry.expiresAt {
                    return entry.value
                }
                entries.removeValue(forKey: id)
            }

#if DEBUG
            buildCount += 1
#endif
            entries = entries.filter { $0.value.window != nil }
            let value = build()
            entries[id] = Entry(window: window, key: key, value: value, referenceDate: referenceDate)
            return value
        }

        func invalidate(window: NSWindow) {
            entries.removeValue(forKey: ObjectIdentifier(window))
        }

        func invalidate(surfaceID: UUID) {
            entries = entries.filter { entry in
                entry.value.window != nil && entry.value.key.focusedSurfaceID != surfaceID
            }
        }

        func invalidate(workingDirectory: String) {
            entries = entries.filter { entry in
                entry.value.window != nil && entry.value.value.trustedWorkingDirectory != workingDirectory
            }
        }

        func invalidateAll() {
            entries.removeAll()
        }

#if DEBUG
        func resetForTesting() {
            entries.removeAll()
            buildCount = 0
        }
#endif
    }

    /// Mirrors macOS tab shortcuts: Cmd+1...Cmd+8 jump to numbered tabs,
    /// Cmd+9 jumps to the last tab.
    nonisolated static func shortcutLabel(for index: Int, totalTabs: Int) -> String? {
        guard index >= 0, index < totalTabs else { return nil }
        if index < 8 { return "\(index + 1)" }
        if totalTabs >= 9 && index == totalTabs - 1 { return "9" }
        return nil
    }

    nonisolated static var tabSidebarEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: tabSidebarEnabledPreferenceKey) == nil {
            return true
        }
        return defaults.bool(forKey: tabSidebarEnabledPreferenceKey)
    }

    nonisolated static var presentationMode: TabSidebarPresentationMode {
        let defaults = UserDefaults.standard
        guard let rawValue = defaults.string(forKey: presentationModePreferenceKey),
              let mode = TabSidebarPresentationMode(rawValue: rawValue) else {
            return .transient
        }
        return mode
    }

    nonisolated static var persistentVisible: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: persistentVisiblePreferenceKey) == nil {
            return true
        }
        return defaults.bool(forKey: persistentVisiblePreferenceKey)
    }

    nonisolated static func canShowDockedSidebar(
        windowControllerIsTerminal: Bool,
        isFullscreen: Bool,
        isMiniaturized: Bool
    ) -> Bool {
        windowControllerIsTerminal && !isFullscreen && !isMiniaturized
    }

    static func shouldShowDockedSidebar(in window: NSWindow?) -> Bool {
        guard tabSidebarEnabled else { return false }
        guard presentationMode == .persistent else { return false }
        guard persistentVisible else { return false }
        guard let window else { return false }
        return canShowDockedSidebar(
            windowControllerIsTerminal: window.windowController is TerminalController,
            isFullscreen: window.yenIsEffectivelyFullscreen,
            isMiniaturized: window.isMiniaturized
        )
    }

    private(set) var visible: Bool = false
    private var panel: TabSidebarPanel?
    private weak var anchorWindow: NSWindow?
    private var hasSetup = false
    private var refreshTimer: Timer?
    private var escapeMonitor: Any?

    nonisolated static func transientAnimationDuration(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> TimeInterval {
        SlidingUtilityPanel.animationDuration(reduceMotion: reduceMotion)
    }

    private override init() {
        super.init()
        visible = Self.tabSidebarEnabled && Self.presentationMode == .persistent ? Self.persistentVisible : false
    }

    // MARK: - Setup

    func setup() {
        guard !hasSetup else { return }
        hasSetup = true
        TabSidebarBuildStatusStore.shared.setup()
        UserDefaults.standard.register(defaults: [
            Self.tabSidebarEnabledPreferenceKey: true,
            Self.presentationModePreferenceKey: TabSidebarPresentationMode.transient.rawValue,
            Self.persistentVisiblePreferenceKey: true,
        ])

        if let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu {
            viewMenu.addItem(NSMenuItem.separator())
            let item = NSMenuItem(
                title: "Toggle Tab Sidebar",
                action: #selector(toggleAction(_:)),
                keyEquivalent: "b"
            )
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.setImageIfDesired(systemSymbolName: "sidebar.left")
            viewMenu.addItem(item)
        }

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeFrame(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidMiniaturize(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowFullscreenStateDidChange(_:)),
            name: .yenNativeFullscreenTransitionDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    // MARK: - Preferences

    func setPresentationMode(_ mode: TabSidebarPresentationMode) {
        let previousMode = Self.presentationMode
        guard previousMode != mode else { return }

        // Dismiss any live floating panel before we flip the persisted mode.
        // Otherwise the transition can strand the transient panel above the app
        // while the docked sidebar mounts.
        if previousMode == .transient || visible || panel?.isVisible == true {
            dismissTransientPanelImmediately(postStateChange: false)
        }

        UserDefaults.standard.set(mode.rawValue, forKey: Self.presentationModePreferenceKey)

        if mode == .persistent {
            setPersistentVisiblePreference(true)
        } else {
            visible = false
            updateTabsIfNeeded([])
            postStateDidChange()
        }
    }

    func setPersistentVisiblePreference(_ isVisible: Bool) {
        let effectiveVisible = Self.tabSidebarEnabled && Self.presentationMode == .persistent && isVisible
        guard Self.persistentVisible != isVisible || visible != effectiveVisible else { return }

        UserDefaults.standard.set(isVisible, forKey: Self.persistentVisiblePreferenceKey)
        guard Self.presentationMode == .persistent else {
            postStateDidChange()
            return
        }
        visible = effectiveVisible
        if !isVisible {
            updateTabsIfNeeded([])
        }
        postStateDidChange()
    }

    func applyWorkspacePreferenceStateTransition(
        from previousState: WorkspacePreferenceState,
        to state: WorkspacePreferenceState,
        preserveTransientVisibility: Bool = false
    ) {
        let previousVisible = visible
        let hadTransientPanel =
            panel?.isVisible == true ||
            anchorWindow != nil ||
            (previousState.tabSidebarPresentationMode == .transient && visible)
        let logicalStateChanged =
            previousState.tabSidebarEnabled != state.tabSidebarEnabled ||
            previousState.tabSidebarPresentationMode != state.tabSidebarPresentationMode ||
            previousState.tabSidebarPersistentVisible != state.tabSidebarPersistentVisible

        if state.tabSidebarPresentationMode == .persistent {
            if hadTransientPanel {
                dismissTransientPanelImmediately(postStateChange: false)
            }

            let effectiveVisible = state.tabSidebarEnabled && state.tabSidebarPersistentVisible
            visible = effectiveVisible
            if !effectiveVisible {
                updateTabsIfNeeded([])
            }

            if logicalStateChanged || previousVisible != visible || hadTransientPanel {
                postStateDidChange()
            }
            return
        }

        let shouldHideVisibleSidebar =
            !state.tabSidebarEnabled ||
            !preserveTransientVisibility ||
            previousState.tabSidebarPresentationMode == .persistent

        if shouldHideVisibleSidebar {
            if hadTransientPanel {
                dismissTransientPanelImmediately(postStateChange: false)
            } else if visible {
                visible = false
                updateTabsIfNeeded([])
            }
        }

        if logicalStateChanged || previousVisible != visible || (shouldHideVisibleSidebar && hadTransientPanel) {
            postStateDidChange()
        }
    }

    private func postStateDidChange() {
        objectWillChange.send()
        NotificationCenter.default.post(name: .yenTabSidebarStateDidChange, object: nil)
    }

    // MARK: - Toggle

    @objc func toggleAction(_ sender: Any?) {
        toggle()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleAction(_:)) else { return true }
        return Self.tabSidebarEnabled
    }

    nonisolated static func shouldConsumeDisabledToggleHotkey(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        tabSidebarEnabled: Bool
    ) -> Bool {
        DisabledToggleHotkey.shouldConsume(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags,
            key: "b",
            featureEnabled: tabSidebarEnabled
        )
    }

    nonisolated static func isToggleHotkey(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        DisabledToggleHotkey.isToggleHotkey(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags,
            key: "b"
        )
    }

    func toggle() {
        guard Self.tabSidebarEnabled else {
            NSSound.beep()
            DisabledFeatureToast.post(featureName: "Tab Sidebar")
            return
        }

        switch Self.presentationMode {
        case .transient:
            if visible {
                animateOut()
            } else {
                animateIn()
            }

        case .persistent:
            setPersistentVisiblePreference(!visible)
        }
    }

    // MARK: - Floating Panel Animation

    private func animateIn() {
        guard Self.presentationMode == .transient else { return }
        guard !visible else { return }
        guard let terminalWindow = activeTerminalWindow() else { return }

        anchorWindow = terminalWindow
        visible = true
        refreshTabs(for: terminalWindow)
        startRefreshTimer()
        observationSession.attach(to: terminalWindow)
        installEscapeMonitor()
        postStateDidChange()

        let panel = ensurePanel()
        // Quick Terminal's sequence: rest frame, content parked behind the window's
        // left edge at alpha 0, then slide in.
        positionPanel(panel, relativeTo: terminalWindow)
        revealView?.park()
        panel.orderFront(nil)
        revealView?.slide(.entering, duration: SlidingUtilityPanel.currentAnimationDuration())
    }

    private func animateOut() {
        guard visible else { return }
        guard Self.presentationMode == .transient else { return }
        guard let panel = panel, panel.isVisible else {
            dismissTransientPanelImmediately()
            return
        }
        let terminalWindow = transientPanelWindow()
        visible = false
        anchorWindow = nil
        teardownObservation()
        postStateDidChange()

        guard terminalWindow != nil, let reveal = revealView else {
            panel.orderOut(nil)
            return
        }

        // Match Quick Terminal: slide back behind the edge, then orderOut synchronously
        // in the exit completion (no Task hop).
        reveal.slide(
            .exiting,
            duration: SlidingUtilityPanel.currentAnimationDuration(),
            completion: { [weak self] in
                guard let self else { return }
                guard self.visible == false else { return }
                self.panel?.orderOut(nil)
            }
        )
    }

    private func dismissTransientPanelImmediately(postStateChange: Bool = true) {
        guard visible || panel?.isVisible == true else { return }

        visible = false
        anchorWindow = nil
        teardownObservation()
        panel?.orderOut(nil)

        if postStateChange {
            postStateDidChange()
        }
    }

    // MARK: - Panel Management

    private var revealView: EdgeRevealView? { panel?.contentView as? EdgeRevealView }

    private func ensurePanel() -> TabSidebarPanel {
        if let existing = panel { return existing }
        let panel = TabSidebarPanel()
        applyPanelAppearance(to: panel)
        let reveal = EdgeRevealView(edge: .leading)
        reveal.embed(
            TabSidebarHostingViewFactory.make(model: self, style: .floating),
            extent: Self.panelWidth
        )
        panel.contentView = reveal
        self.panel = panel
        return panel
    }

    private func applyPanelAppearance(to panel: TabSidebarPanel) {
        panel.appearance = nil
    }

    /// Rests the panel flush inside the terminal window's left edge. The panel frame
    /// never animates; the reveal slides its content from behind that edge.
    private func positionPanel(_ panel: NSWindow, relativeTo terminalWindow: NSWindow) {
        EdgeRevealPanelGeometry.place(
            panel,
            edge: .leading,
            in: terminalWindow,
            width: Self.panelWidth
        )
    }

    // MARK: - Tab State

    override func newTab() {
        guard let controller = transientPanelWindow()?.windowController as? TerminalController else { return }
        controller.newTab(nil)
    }

    private func refreshTabs(rescan: Bool = true) {
        refreshTabs(for: transientPanelWindow(), rescan: rescan)
    }

    private func refreshTabs(for terminalWindow: NSWindow?, rescan: Bool = true) {
        guard let terminalWindow else {
            observationSession.detach()
            updateTabsIfNeeded([])
            return
        }
        if rescan { observationSession.rescanObservedWindows() }
        updateTabsIfNeeded(Self.items(for: terminalWindow))
    }

    static func items(
        for terminalWindow: NSWindow,
        referenceDate: Date = Date(),
        gitContextCache: TabSidebarGitContextCache? = nil,
        buildStatusStore: TabSidebarBuildStatusStore? = nil
    ) -> [TabSidebarItem] {
        // The shared instances are main-actor state; a default argument is
        // evaluated outside the actor, so they resolve here instead.
        let gitContextCache = gitContextCache ?? .shared
        let buildStatusStore = buildStatusStore ?? .shared
        let windows = terminalWindow.tabbedWindows ?? [terminalWindow]
        let selectedWindow = terminalWindow.tabGroup?.selectedWindow ?? terminalWindow

        return windows.enumerated().map { index, window in
            let isSelected = window == selectedWindow
            let metadata = cachedMetadata(for: window, referenceDate: referenceDate)
            let controller = window.windowController as? BaseTerminalController
            let gitSnapshot = gitContextCache.snapshot(forTrustedDirectory: metadata.trustedWorkingDirectory)
            let signal = statusSignal(for: controller?.focusedSurface, controller: controller, buildStatusStore: buildStatusStore)
            let terminalWindow = window as? TerminalWindow

            return TabSidebarItem(
                id: ObjectIdentifier(window),
                window: window,
                title: window.title.isEmpty ? "Untitled Tab" : window.title,
                shortcut: shortcutLabel(for: index, totalTabs: windows.count),
                color: terminalWindow?.tabColor ?? .none,
                isSelected: isSelected,
                cwdSummary: metadata.cwdSummary,
                gitSummary: gitSnapshot?.summary,
                statusSummary: signal?.summary,
                statusTone: signal?.tone ?? (isSelected ? .neutral : .idle)
            )
        }
    }

    /// Observer scans and row rendering share the same bounded path cache.
    static func cachedWorkingDirectory(for window: NSWindow) -> String? {
        cachedMetadata(for: window, referenceDate: Date()).trustedWorkingDirectory
    }

    private static func cachedMetadata(for window: NSWindow, referenceDate: Date) -> MetadataValue {
        let surface = (window.windowController as? BaseTerminalController)?.focusedSurface
        let key = MetadataCacheKey(focusedSurfaceID: surface?.id,
            rawWorkingDirectory: surface?.effectiveWorkingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines))
        return metadataCache.value(for: window, key: key, referenceDate: referenceDate) {
            let path = trustedWorkingDirectory(for: surface)
            return MetadataValue(trustedWorkingDirectory: path, cwdSummary: displayPathSummary(for: path))
        }
    }

    static func invalidateMetadataCache(for window: NSWindow) {
        metadataCache.invalidate(window: window)
    }

    static func invalidateMetadataCache(forSurfaceID surfaceID: UUID) {
        metadataCache.invalidate(surfaceID: surfaceID)
    }

    static func invalidateAllMetadataCache() {
        metadataCache.invalidateAll()
    }

    static func invalidateMetadataCache(notificationName: Notification.Name, object: Any?) {
        switch notificationName {
        case .yenTabSidebarGitContextDidChange:
            guard let workingDirectory = object as? String else {
                metadataCache.invalidateAll()
                return
            }
            metadataCache.invalidate(workingDirectory: workingDirectory)
        case .yenTabSidebarBuildStatusDidChange:
            guard let surfaceID = object as? UUID else {
                metadataCache.invalidateAll()
                return
            }
            metadataCache.invalidate(surfaceID: surfaceID)
        case .yenBellDidRing:
            guard let surface = object as? YEN.SurfaceView else {
                metadataCache.invalidateAll()
                return
            }
            metadataCache.invalidate(surfaceID: surface.id)
        case YEN.Notification.yenFocusSplit,
             YEN.Notification.yenNewSplit,
             YEN.Notification.yenCloseSurface,
             YEN.Notification.didEqualizeSplits,
             YEN.Notification.yenPresentTerminal:
            metadataCache.invalidateAll()
        default:
            return
        }
    }

    /// The sidebar and git drawer describe an agent's reported worktree while it runs, then the
    /// shell's `pwd` again; see `AgentWorkingDirectory.swift`.
    static func trustedWorkingDirectory(for surface: YEN.SurfaceView?) -> String? {
        trustedWorkingDirectory(from: surface?.effectiveWorkingDirectory)
    }

    static func trustedWorkingDirectory(from rawPath: String?) -> String? {
        LocalPathResolver.canonicalPath(rawPath, trimWhitespace: true, requireAbsolute: true)
    }

    private static func displayPathSummary(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return NSString(string: path).abbreviatingWithTildeInPath
    }

    private static func terminalStatusSignal(for surface: YEN.SurfaceView?) -> TabSidebarStatusSignal? {
        guard let report = surface?.progressReport else { return nil }
        switch report.state {
        case .error:
            return TabSidebarStatusSignal(summary: "Task error", tone: .error)
        case .pause:
            return TabSidebarStatusSignal(summary: "Task paused", tone: .warning)
        case .indeterminate:
            return TabSidebarStatusSignal(summary: "Task running", tone: .running)
        case .set:
            if let progress = report.progress {
                return TabSidebarStatusSignal(summary: "Task \(progress)%", tone: .running)
            }
            return TabSidebarStatusSignal(summary: "Task running", tone: .running)
        case .remove:
            return nil
        }
    }

    private static func statusSignal(
        for surface: YEN.SurfaceView?,
        controller: BaseTerminalController?,
        buildStatusStore: TabSidebarBuildStatusStore? = nil
    ) -> TabSidebarStatusSignal? {
        let buildStatusStore = buildStatusStore ?? .shared
        if let terminalStatusSignal = terminalStatusSignal(for: surface) {
            return terminalStatusSignal
        }

        if let buildStatusSignal = buildStatusStore.signal(for: surface?.id) {
            return buildStatusSignal
        }

        if controller?.bell == true {
            return TabSidebarStatusSignal(summary: "Attention", tone: .warning)
        }

        return nil
    }

    // MARK: - Helpers

    private func activeTerminalWindow(excluding excludedWindow: NSWindow? = nil) -> NSWindow? {
        let candidates: [NSWindow?] = [
            NSApp.keyWindow,
            NSApp.mainWindow,
            TerminalController.preferredParent?.window,
        ]
            + NSApp.orderedWindows
            + NSApp.windows
        return TerminalAuxiliaryAnchorPolicy.firstEligible(in: candidates.compactMap {
            activeTerminalWindowCandidate(for: $0, excluding: excludedWindow)
        })
    }

    private func activeTerminalWindowCandidate(
        for window: NSWindow?,
        excluding excludedWindow: NSWindow?
    ) -> TerminalAuxiliaryAnchorPolicy.Candidate<NSWindow>? {
        guard let window, window !== excludedWindow else { return nil }
        return TerminalAuxiliaryAnchorPolicy.Candidate(
            identity: ObjectIdentifier(window),
            window: window,
            isEligible: TerminalAuxiliaryAnchorPolicy.canAnchor(
                windowControllerIsTerminal: window.windowController is TerminalController,
                isQuickTerminal: window is QuickTerminalWindow,
                isFullscreen: window.yenIsEffectivelyFullscreen,
                isMiniaturized: window.isMiniaturized,
                isVisible: window.isVisible
            )
        )
    }

    private func transientPanelWindow() -> NSWindow? {
        if Self.presentationMode == .transient, let anchorWindow {
            return anchorWindow
        }
        return activeTerminalWindow()
    }

    private func handoffTransientPanel(from closingWindow: NSWindow, to replacementWindow: NSWindow?) {
        tabs.removeAll { $0.window === closingWindow }

        guard let replacementWindow else {
            dismissTransientPanelImmediately()
            return
        }

        anchorWindow = replacementWindow
        observationSession.attach(to: replacementWindow)
        refreshTabs(for: replacementWindow)

        if let panel {
            applyPanelAppearance(to: panel)
            positionPanel(panel, relativeTo: replacementWindow)
            if !panel.isVisible {
                revealView?.showAtRest()
                panel.orderFront(nil)
            }
        }

        startRefreshTimer()
        installEscapeMonitor()
    }

    // MARK: - Notifications

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible else { return }
        guard let panel else { return }
        guard let window = notification.object as? NSWindow else { return }

        guard window.windowController is TerminalController else {
            panel.orderOut(nil)
            teardownObservation()
            return
        }

        reattachPanel(to: window)
    }

    @objc private func windowDidChangeFrame(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible, let panel else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow || window.isKeyWindow else { return }
        if window.isKeyWindow {
            anchorWindow = window
        }
        positionPanel(panel, relativeTo: window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        handoffTransientPanel(from: window, to: activeTerminalWindow(excluding: window))
    }

    @objc private func windowDidMiniaturize(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible, let panel else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow else { return }
        panel.orderOut(nil)
        teardownObservation()
    }

    @objc private func windowFullscreenStateDidChange(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible, let panel else { return }
        guard let window = notification.object as? NSWindow,
              window.windowController is TerminalController else { return }
        guard window === anchorWindow || window.isKeyWindow else { return }

        if window.yenIsEffectivelyFullscreen {
            panel.orderOut(nil)
            teardownObservation()
            return
        }

        reattachPanel(to: window)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        guard Self.presentationMode == .transient else { return }
        guard visible else { return }
        teardownObservation()
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.metadataFallbackRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTabs()
            }
        }
        refreshTimer?.tolerance = Self.metadataFallbackRefreshTolerance
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Escape Monitor

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard Self.presentationMode == .transient else { return event }
            guard self.visible, let panel = self.panel, panel.isVisible else { return event }
            if event.keyCode == 0x35 {
                guard Self.shouldDismissTransientPanelForEscape(
                    panelFirstResponder: panel.firstResponder,
                    activeTerminalFirstResponder: self.transientPanelWindow()?.firstResponder
                ) else {
                    return event
                }
                self.animateOut()
                return nil
            }
            return event
        }
    }

    nonisolated static func shouldDismissTransientPanelForEscape(
        panelFirstResponder: NSResponder?,
        activeTerminalFirstResponder: NSResponder?
    ) -> Bool {
        !hasActiveFieldEditor(firstResponder: panelFirstResponder) &&
        !hasActiveFieldEditor(firstResponder: activeTerminalFirstResponder)
    }

    private nonisolated static func hasActiveFieldEditor(firstResponder: NSResponder?) -> Bool {
        guard let textView = firstResponder as? NSTextView else { return false }
        return MainActor.assumeIsolated {
            textView.isFieldEditor
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Observation Teardown / Reattach

    /// Strict-order observation teardown shared by every transient hide and dismiss path.
    /// Order is load-bearing: stop timer, detach session, invalidate metadata cache, clear tabs, drop monitor.
    /// Callers own their own visible/anchorWindow reset and per-site panel ops (orderOut).
    private func teardownObservation() {
        stopRefreshTimer()
        observationSession.detach()
        Self.invalidateAllMetadataCache()
        updateTabsIfNeeded([])
        removeEscapeMonitor()
    }

    /// Reattaches the live panel to `window` and resumes observation. Callers own
    /// any preceding guard/prefix (e.g. the fullscreen early-return).
    private func reattachPanel(to window: NSWindow) {
        guard let panel else { return }
        anchorWindow = window
        applyPanelAppearance(to: panel)
        observationSession.attach(to: window)
        refreshTabs(for: window)
        positionPanel(panel, relativeTo: window)

        if !panel.isVisible {
            revealView?.showAtRest()
            panel.orderFront(nil)
        }

        startRefreshTimer()
        installEscapeMonitor()
    }
}

#if DEBUG
extension TabSidebarController {
    nonisolated static var testingTrackedOnlyStatusArguments: [String] {
        TabSidebarGitStatusSemantics.trackedOnlyStatusArguments
    }

    static var testingMetadataCacheBuildCount: Int {
        metadataCache.buildCount
    }

    static func testingResetMetadataCache() {
        metadataCache.resetForTesting()
    }

    static func testingInvalidateMetadataCache(for window: NSWindow) {
        invalidateMetadataCache(for: window)
    }

    static func testingInvalidateMetadataCache(notificationName: Notification.Name, object: Any?) {
        invalidateMetadataCache(notificationName: notificationName, object: object)
    }

    func testingConfigureFloatingPanel(_ panel: TabSidebarPanel?, visible: Bool) {
        self.panel = panel
        self.visible = visible
    }

    func testingHandleWindowDidBecomeKey(_ window: NSWindow) {
        windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    }

    func testingHandleClosingWindow(_ closingWindow: NSWindow, replacementWindow: NSWindow?) {
        handoffTransientPanel(from: closingWindow, to: replacementWindow)
    }

    func testingHandleWindowDidMiniaturize(_ window: NSWindow) {
        windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
    }

    func testingHandleNativeFullscreenStateChange(_ window: NSWindow) {
        windowFullscreenStateDidChange(
            Notification(name: .yenNativeFullscreenTransitionDidChange, object: window)
        )
    }

    func testingReloadVisibleStateFromPreferences() {
        visible = Self.tabSidebarEnabled && Self.presentationMode == .persistent ? Self.persistentVisible : false
        if !visible {
            tabs = []
        }
    }

    func testingResetState() {
        dismissTransientPanelImmediately(postStateChange: false)
        panel = nil
        anchorWindow = nil
        visible = false
        tabs = []
    }
}
#endif

extension Notification.Name {
    static let yenTabSidebarGitContextDidChange = Notification.Name("com.yenchat.yen.tabSidebarGitContextDidChange")
    static let yenTabSidebarBuildStatusDidChange = Notification.Name("com.yenchat.yen.tabSidebarBuildStatusDidChange")
    static let yenTabSidebarStateDidChange = Notification.Name("com.yenchat.yen.tabSidebarStateDidChange")
}
#endif
