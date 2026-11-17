#if os(macOS)
import AppKit
import Combine
import SwiftUI

@MainActor
final class GitDrawerController {
    typealias FocusedDirectoryProvider = @MainActor () -> String?
    typealias Resolver = @Sendable (GitDrawerSnapshotRequest) async throws -> GitDrawerSnapshot

    private weak var container: TerminalViewContainer?
    private weak var terminalController: BaseTerminalController?
    private var directoryObservation: AnyCancellable?
    private let focusedDirectory: FocusedDirectoryProvider
    private let resolver: Resolver
    private let backgroundRefreshEligibility: (@MainActor () -> Bool)?
    private var hostingView: NSHostingView<GitDrawerView>?
    private var refreshTask: Task<Void, Never>?
    private var retargetObservers: [NSObjectProtocol] = []
    private var keyMonitor: Any?
    private var fallbackRefreshTimer: Timer?
    private var repositoryWatcher: GitDrawerRepositoryWatcher?
    private var watcherSetupTask: Task<Void, Never>?
    private var repositoryRefreshTask: Task<Void, Never>?
    private var watchedRepositoryRoot: String?
    private var repositoryChangePending = false
    private weak var previousFirstResponder: NSResponder?
    private weak var previousFirstResponderWindow: NSWindow?
    private var generation = 0
    private var currentTargetID: String?
    private var currentWorkingDirectory: String?
    private var selectedPath: String?
    private var listSnapshot: GitDrawerSnapshot?

    #if DEBUG
    private(set) var testingPresentationUpdateCount = 0
    private(set) var testingRefreshStartCount = 0
    func testingWaitForRefresh() async { await refreshTask?.value }
    func testingWaitForWatcher() async { await watcherSetupTask?.value }
    var testingHasRepositoryWatcher: Bool { repositoryWatcher != nil }
    var testingFallbackRefreshInterval: TimeInterval? { fallbackRefreshTimer?.timeInterval }
    #endif

    private(set) var isVisible = false
    private(set) var isLoading = false
    private(set) var presentationState: GitDrawerPresentationState?

    init(
        container: TerminalViewContainer,
        focusedDirectory: @escaping FocusedDirectoryProvider,
        terminalController: BaseTerminalController? = nil,
        backgroundRefreshEligibility: (@MainActor () -> Bool)? = nil,
        resolver: @escaping Resolver = { request in
            try await GitDrawerSnapshotResolver.resolve(request, runner: GitDrawerShellClient(disableOptionalLocks: true))
        }
    ) {
        self.container = container
        self.focusedDirectory = focusedDirectory
        self.terminalController = terminalController
        self.resolver = resolver
        self.backgroundRefreshEligibility = backgroundRefreshEligibility
    }

    deinit {
        refreshTask?.cancel()
        fallbackRefreshTimer?.invalidate()
        MainActor.assumeIsolated {
            removeRetargetObservers()
            stopRepositoryWatcher()
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard let container else { return }
        previousFirstResponderWindow = container.window
        previousFirstResponder = container.window?.firstResponder
        isVisible = true
        installKeyMonitor()
        installRetargetObservers()
        installDirectoryObservation()
        installFallbackRefreshTimer()
        attachDrawer(to: container)
        refresh()
    }

    func close() {
        isVisible = false
        directoryObservation = nil
        stopRepositoryWatcher()
        refreshTask?.cancel()
        refreshTask = nil
        fallbackRefreshTimer?.invalidate()
        fallbackRefreshTimer = nil
        removeRetargetObservers()
        isLoading = false
        currentTargetID = nil
        currentWorkingDirectory = nil
        selectedPath = nil
        presentationState = nil
        listSnapshot = nil
        hostingView = nil
        removeKeyMonitor()
        container?.setGitDrawerHostingView(
            nil,
            preferredHeight: 0,
            animationDuration: SlidingUtilityPanel.currentAnimationDuration()
        )
        restorePreviousFirstResponderIfPossible()
    }

    func shouldCloseForKeyDown(keyCode: UInt16, eventWindow: NSWindow?) -> Bool {
        Self.shouldCloseForKeyDown(
            keyCode: keyCode,
            eventWindow: eventWindow,
            containerWindow: container?.window
        )
    }

    static func shouldCloseForKeyDown(
        keyCode: UInt16,
        eventWindow: NSWindow?,
        containerWindow: NSWindow?
    ) -> Bool {
        keyCode == 0x35 && eventWindow === containerWindow
    }

    @discardableResult
    func refresh(
        selectedPath requestedPath: String? = nil,
        background: Bool = false,
        selectionOnly: Bool = false
    ) -> Bool {
        guard isVisible else { return false }
        guard let workingDirectory = focusedDirectory() else {
            showUnavailable(reason: .notGitWorktree)
            return false
        }
        #if DEBUG
        testingRefreshStartCount += 1
        #endif
        if !selectionOnly { repositoryChangePending = false }
        let effectiveSelectedPath = requestedPath ?? selectedPath
        refreshTask?.cancel()
        generation += 1
        let request = GitDrawerSnapshotRequest(
            workingDirectory: workingDirectory,
            targetID: workingDirectory,
            generation: generation,
            selectedPath: effectiveSelectedPath,
            listSnapshot: selectionOnly ? listSnapshot : nil
        )
        currentTargetID = request.targetID
        currentWorkingDirectory = workingDirectory
        selectedPath = effectiveSelectedPath
        let showLoading = !background || presentationState == nil
        if isLoading != showLoading || presentationState == nil {
            isLoading = showLoading
            updateHostingView()
        }
        refreshTask = Task { [weak self, resolver] in
            do {
                let snapshot = try await resolver(request)
                self?.apply(snapshot, for: request)
            } catch {
                self?.finishFailedRefresh(for: request, error: error)
            }
        }
        return true
    }

    @discardableResult
    func retargetIfNeeded() -> Bool {
        guard isVisible else { return false }
        let workingDirectory = focusedDirectory()
        guard workingDirectory != currentWorkingDirectory else { return false }
        stopRepositoryWatcher()
        installFallbackRefreshTimer()
        presentationState = nil
        listSnapshot = nil
        selectedPath = nil
        return refresh()
    }

    func select(path: String) {
        _ = refresh(selectedPath: path, selectionOnly: true)
    }

    func copySelectedPath(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let selectedPath, !selectedPath.isEmpty else { return false }
        return copy(path: selectedPath, to: pasteboard)
    }

    func copy(path: String, to pasteboard: NSPasteboard = .general) -> Bool {
        guard !path.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(path, forType: .string)
    }

    func copySelectedDiff(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let diff = presentationState?.selectedDiffText, !diff.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(diff, forType: .string)
    }

    func revealSelectedFile(workspace: NSWorkspace = .shared) -> Bool {
        reveal(path: selectedPath, workspace: workspace)
    }

    func reveal(path: String?, workspace: NSWorkspace = .shared) -> Bool {
        guard let fileURL = selectedFileURL(for: path) else { return false }
        workspace.activateFileViewerSelecting([fileURL])
        return true
    }

    func openSelectedFile(workspace: NSWorkspace = .shared) -> Bool {
        open(path: selectedPath, workspace: workspace)
    }

    func open(path: String?, workspace: NSWorkspace = .shared) -> Bool {
        guard let fileURL = selectedFileURL(for: path) else { return false }
        return workspace.open(fileURL)
    }

    func openGitTUI() -> Bool {
        guard let repoRoot = presentationState?.repoRoot, !repoRoot.isEmpty else { return false }
        return TerminalSurfaceCommandLauncher.launchGitTUI(in: container?.window)
    }

    private func attachDrawer(to _: TerminalViewContainer) {
        updateHostingView()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.shouldCloseForKeyDown(keyCode: event.keyCode, eventWindow: event.window) {
                self.close()
                return nil
            }
            return event
        }
    }

    private func installDirectoryObservation() {
        guard let terminalController else { return }
        directoryObservation = terminalController.$surfaceTree
            .map { tree -> AnyPublisher<Void, Never> in
                let changes = tree.flatMap { surface -> [AnyPublisher<Void, Never>] in
                    [
                        surface.$pwd.map { _ in () }.eraseToAnyPublisher(),
                        surface.agentWorkingDirectoryState.$report.map { _ in () }.eraseToAnyPublisher(),
                        surface.$focusInstant.map { _ in () }.eraseToAnyPublisher(),
                    ]
                }
                return Publishers.MergeMany(changes).prepend(()).eraseToAnyPublisher()
            }
            .switchToLatest()
            // Published emits before assignment. Read the effective directory on the next turn.
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.retargetIfNeeded() }
            }
    }

    private func installRetargetObservers() {
        guard retargetObservers.isEmpty else { return }
        let center = NotificationCenter.default
        retargetObservers.append(
            center.addObserver(
                forName: .yenTabSidebarStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in _ = self?.retargetIfNeeded() }
            }
        )
        retargetObservers.append(
            center.addObserver(
                forName: .yenTabSidebarGitContextDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in self?.handleGitContextDidChange(notification) }
            }
        )
        // Paired with `isEligibleForBackgroundRefresh`: the timer skips ticks while the
        // drawer is unobservable, so catch up the moment it becomes observable again.
        // Registered here, so they share the show/close lifetime of the other observers.
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ] {
            retargetObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refreshAfterBecomingObservable() }
                }
            )
        }
    }

    private func removeRetargetObservers() {
        let center = NotificationCenter.default
        for observer in retargetObservers {
            center.removeObserver(observer)
        }
        retargetObservers.removeAll()
    }

    private func handleGitContextDidChange(_ notification: Notification) {
        guard isVisible else { return }
        if let workingDirectory = notification.object as? String,
           !workingDirectory.isEmpty,
           workingDirectory != currentWorkingDirectory {
            return
        }
        if !retargetIfNeeded(), repositoryWatcher == nil {
            _ = refresh(selectedPath: selectedPath, background: true)
        }
    }

    private func restorePreviousFirstResponderIfPossible() {
        defer {
            previousFirstResponder = nil
            previousFirstResponderWindow = nil
        }
        guard let window = previousFirstResponderWindow,
              let responder = previousFirstResponder
        else { return }
        window.makeFirstResponder(responder)
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func updateHostingView() {
        #if DEBUG
        testingPresentationUpdateCount += 1
        #endif
        let state = presentationState ?? GitDrawerPresentationState(snapshot: loadingSnapshot)
        let view = GitDrawerView(
            state: state,
            isLoading: isLoading,
            onRefresh: { [weak self] in
                Task { @MainActor in self?.refreshSelectedPath() }
            },
            onSelectPath: { [weak self] path in
                Task { @MainActor in self?.select(path: path) }
            },
            onCopyPathValue: { [weak self] path in
                Task { @MainActor in _ = self?.copy(path: path) }
            },
            onCopyDiff: { [weak self] in
                Task { @MainActor in _ = self?.copySelectedDiff() }
            },
            onOpenPathValue: { [weak self] path in
                Task { @MainActor in _ = self?.open(path: path) }
            },
            onRevealPathValue: { [weak self] path in
                Task { @MainActor in _ = self?.reveal(path: path) }
            },
            onOpenGitTUI: { [weak self] in
                Task { @MainActor in _ = self?.openGitTUI() }
            },
            onClose: { [weak self] in
                Task { @MainActor in self?.close() }
            }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            let newHostingView = NSHostingView(rootView: view)
            newHostingView.setAccessibilityIdentifier("yen.gitDrawer")
            hostingView = newHostingView
        }
        if isVisible, let container, let hostingView {
            let preferredHeight = GitDrawerHeightPolicy.defaultHeight(for: max(container.bounds.height, 1))
            container.setGitDrawerHostingView(
                hostingView,
                preferredHeight: preferredHeight,
                animationDuration: SlidingUtilityPanel.currentAnimationDuration()
            )
        }
    }

    /// Defer filesystem and timer refreshes while the window is unobservable.
    private var isEligibleForBackgroundRefresh: Bool {
        if let backgroundRefreshEligibility { return backgroundRefreshEligibility() }
        guard let window = container?.window else { return false }
        guard !window.isMiniaturized else { return false }
        // VISIBILITY, not focus. An earlier `NSApp.isActive` guard froze the drawer for a
        // window sitting unoccluded beside an editor while another app was frontmost —
        // fully observable, and stale with nothing to indicate the pause. `occlusionState`
        // already captures "nobody can see it", including for a hidden app.
        // Both conditions required: an ordered-out window is ineligible, not exempt.
        guard window.isVisible, window.occlusionState.contains(.visible) else { return false }
        return true
    }

    private func installRepositoryWatcher(for root: String) {
        guard !root.isEmpty, watchedRepositoryRoot != root else { return }
        stopRepositoryWatcher()
        watchedRepositoryRoot = root
        installFallbackRefreshTimer()
        watcherSetupTask = Task { [weak self] in
            let paths = await Task.detached(priority: .utility) {
                GitDrawerRepositoryWatchPaths.resolve(repositoryRoot: root)
            }.value
            guard !Task.isCancelled, let self, self.isVisible, self.watchedRepositoryRoot == root else { return }
            self.watcherSetupTask = nil
            guard let paths else { self.watchedRepositoryRoot = nil; return }
            self.repositoryWatcher = GitDrawerRepositoryWatcher(paths: paths) { [weak self] in
                self?.repositoryDidChange()
            }
            self.installFallbackRefreshTimer()
            // Cover changes between the first snapshot and stream installation.
            if self.repositoryWatcher != nil {
                self.repositoryDidChange()
            } else {
                self.watchedRepositoryRoot = nil
            }
        }
    }

    private func stopRepositoryWatcher() {
        watcherSetupTask?.cancel()
        watcherSetupTask = nil
        repositoryRefreshTask?.cancel()
        repositoryRefreshTask = nil
        repositoryWatcher?.stop()
        repositoryWatcher = nil
        watchedRepositoryRoot = nil
        repositoryChangePending = false
    }

    private func repositoryDidChange() {
        guard isVisible else { return }
        repositoryChangePending = true
        scheduleRepositoryRefresh()
    }

    private func scheduleRepositoryRefresh() {
        repositoryRefreshTask?.cancel()
        repositoryRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, self.isVisible else { return }
            self.repositoryRefreshTask = nil
            guard self.repositoryChangePending, self.refreshTask == nil,
                  self.isEligibleForBackgroundRefresh else { return }
            _ = self.refresh(selectedPath: self.selectedPath, background: true)
        }
    }

    private func installFallbackRefreshTimer() {
        fallbackRefreshTimer?.invalidate()
        let interval: TimeInterval = repositoryWatcher == nil ? 15 : 60
        fallbackRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible, self.refreshTask == nil else { return }
                guard self.isEligibleForBackgroundRefresh else { return }
                _ = self.refresh(selectedPath: self.selectedPath, background: true)
            }
        }
        // Low-priority background refresh: let the system coalesce the fire for energy savings.
        fallbackRefreshTimer?.tolerance = interval / 5
    }

    /// Refresh once when the drawer becomes observable again, so suspending the ticks
    /// above cannot leave stale contents on screen.
    private func refreshAfterBecomingObservable() {
        guard isVisible, refreshTask == nil, isEligibleForBackgroundRefresh else { return }
        _ = refresh(selectedPath: selectedPath, background: true)
    }

    private func refreshSelectedPath() {
        _ = refresh(selectedPath: selectedPath)
    }

    nonisolated static func animationDuration(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> TimeInterval {
        SlidingUtilityPanel.animationDuration(reduceMotion: reduceMotion)
    }

    private func apply(_ snapshot: GitDrawerSnapshot, for request: GitDrawerSnapshotRequest) {
        guard isVisible,
              request.generation == generation,
              request.targetID == currentTargetID
        else { return }
        refreshTask = nil
        listSnapshot = snapshot
        present(GitDrawerPresentationState(snapshot: snapshot))
        installRepositoryWatcher(for: snapshot.repoRoot)
        if repositoryChangePending { scheduleRepositoryRefresh() }
    }

    private func present(_ next: GitDrawerPresentationState) {
        let needsUpdate = isLoading || presentationState != next
        isLoading = false
        presentationState = next
        if needsUpdate { updateHostingView() }
    }

    private func finishFailedRefresh(for request: GitDrawerSnapshotRequest, error: Error) {
        guard isVisible,
              request.generation == generation,
              request.targetID == currentTargetID
        else { return }
        refreshTask = nil
        listSnapshot = nil
        present(GitDrawerPresentationState(unavailable: Self.unavailableReason(for: error)))
        if repositoryChangePending { scheduleRepositoryRefresh() }
    }

    nonisolated static func unavailableReason(for error: Error) -> GitDrawerUnavailableReason {
        guard let shellError = error as? GitDrawerShellError else {
            return .unknown
        }
        switch shellError {
        case .missingGit:
            return .missingGit
        case .timedOut:
            return .timedOut
        case .bareRepository:
            return .bareRepository
        case .mutatingCommandRejected:
            return .mutationRejected
        case .commandFailed:
            return .commandFailed
        }
    }

    private func showUnavailable(reason: GitDrawerUnavailableReason) {
        stopRepositoryWatcher()
        installFallbackRefreshTimer()
        refreshTask?.cancel()
        refreshTask = nil
        generation += 1
        currentTargetID = nil
        currentWorkingDirectory = nil
        listSnapshot = nil
        isLoading = false
        presentationState = GitDrawerPresentationState(unavailable: reason)
        updateHostingView()
    }

    private var selectedFileURL: URL? {
        selectedFileURL(for: selectedPath)
    }

    private func selectedFileURL(for path: String?) -> URL? {
        guard let state = presentationState,
              let path,
              !path.isEmpty,
              !state.repoRoot.isEmpty,
              !state.groups.flatMap(\.rows).contains(where: { $0.repoRelativePath == path && $0.status == .deleted })
        else { return nil }
        let url = URL(fileURLWithPath: state.repoRoot).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private var loadingSnapshot: GitDrawerSnapshot {
        GitDrawerSnapshot(
            repoRoot: "",
            branch: "Git",
            upstream: nil,
            ahead: 0,
            behind: 0,
            staged: [],
            unstaged: [],
            untracked: [],
            conflicted: [],
            stashCount: 0,
            selectedFile: nil,
            selectedDiff: nil,
            isDiffTruncated: false,
            generation: generation
        )
    }
}
#endif
