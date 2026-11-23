#if os(macOS)
import Cocoa
import Combine
import SwiftUI

@MainActor
final class TabSidebarObservationSession {
    private weak var terminalWindow: NSWindow?
    private let onChange: @MainActor () -> Void
    private var notificationObservers: [NSObjectProtocol] = []
    private var titleObservations: [NSKeyValueObservation] = []
    private var cancellables: Set<AnyCancellable> = []
    private let metadataChanges = PassthroughSubject<Void, Never>()
    private var metadataRefresh: AnyCancellable?
    private var rebuildPending = false
    #if DEBUG
    private(set) var testingMetadataScanCount = 0
    #endif
    private var orderedWindowIDs: [ObjectIdentifier] = []
    private var observedWorkingDirectories: Set<String> = []
    private var observedSurfaceIDs: Set<UUID> = []

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        installMetadataRefresh()

        let center = NotificationCenter.default
        let notifications: [Notification.Name] = [
            .yenTabSidebarGitContextDidChange,
            .yenTabSidebarBuildStatusDidChange,
            .yenTokenProjectUsageDidChange,
            .yenBellDidRing,
            YEN.Notification.yenFocusSplit,
            YEN.Notification.yenNewSplit,
            YEN.Notification.yenCloseSurface,
            YEN.Notification.didEqualizeSplits,
            YEN.Notification.yenPresentTerminal,
        ]

        for name in notifications {
            notificationObservers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard self.shouldHandle(notificationName: name, object: notification.object) else { return }
                        TabSidebarController.invalidateMetadataCache(
                            notificationName: name,
                            object: notification.object
                        )
                        self.queueMetadataRefresh(force: Self.requiresObserverRebuild(for: name))
                    }
                }
            )
        }
    }

    nonisolated static func requiresObserverRebuild(for notificationName: Notification.Name) -> Bool {
        switch notificationName {
        case YEN.Notification.yenNewSplit,
             YEN.Notification.yenCloseSurface,
             YEN.Notification.didEqualizeSplits:
            return true
        default:
            return false
        }
    }

    deinit {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
    }

    func attach(to window: NSWindow?) {
        guard terminalWindow !== window else {
            return
        }

        installMetadataRefresh()
        terminalWindow = window
        orderedWindowIDs = []
        refreshObservedState(force: true, notifyChange: true)
    }

    func rescanObservedWindows() {
        refreshObservedState(force: false, notifyChange: false)
    }

    func detach() {
        metadataRefresh = nil
        rebuildPending = false
        terminalWindow = nil
        orderedWindowIDs = []
        observedWorkingDirectories.removeAll()
        observedSurfaceIDs.removeAll()
        titleObservations.removeAll()
        cancellables.removeAll()
    }

    private func refreshObservedState(force: Bool, notifyChange: Bool) {
        guard let terminalWindow else {
            detach()
            return
        }

        let windows = terminalWindow.tabbedWindows ?? [terminalWindow]
        let currentIDs = windows.map { ObjectIdentifier($0) }
        if force || currentIDs != orderedWindowIDs {
            orderedWindowIDs = currentIDs
            rebuildObservers(for: windows)
        } else {
            updateObservedMetadata(for: windows)
        }

        if notifyChange {
            onChange()
        }
    }

    private func rebuildObservers(for windows: [NSWindow]) {
        titleObservations.removeAll()
        cancellables.removeAll()
        updateObservedMetadata(for: windows)

        for window in windows {
            titleObservations.append(
                window.observe(\.title, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        self?.queueMetadataRefresh()
                    }
                }
            )

            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            controller.$surfaceTree
                // Published replay fires immediately on subscription; ignore that initial value
                // or observer installation will schedule an unbounded rebuild loop.
                .dropFirst()
                // `controller` is captured weakly: capturing it strongly here closes a retain
                // cycle (controller -> window -> contentView -> DockedTabSidebarModel ->
                // observationSession -> cancellables -> this closure -> controller) that leaks
                // the whole window graph on close in docked/pinned mode.
                .sink { [weak self, weak controller] _ in
                    Task { @MainActor [weak self, weak controller] in
                        if let window = controller?.window {
                            TabSidebarController.invalidateMetadataCache(for: window)
                        }
                        self?.queueMetadataRefresh(force: true)
                    }
                }
                .store(in: &cancellables)

            let changes = metadataChanges
            controller.$bell
                .dropFirst()
                .sink { [weak changes] _ in changes?.send(()) }
                .store(in: &cancellables)

            for surface in controller.surfaceTree {
                observe(surface: surface)
            }
        }
    }

    private func installMetadataRefresh() {
        guard metadataRefresh == nil else { return }
        metadataRefresh = metadataChanges
            .debounce(for: .zero, scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let force = self.rebuildPending
                    self.rebuildPending = false
                    self.refreshObservedState(force: force, notifyChange: true)
                }
            }
    }

    private func queueMetadataRefresh(force: Bool = false) {
        rebuildPending = rebuildPending || force
        metadataChanges.send(())
    }

    private func observe(surface: YEN.SurfaceView) {
        // Ignore every publisher's initial replay before merging, and never retain
        // the surface in its own subscription. The session coalesces all surfaces.
        let publishers: [AnyPublisher<Void, Never>] = [
            surface.$focusInstant.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            surface.$pwd.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            surface.agentWorkingDirectoryState.$report.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            surface.$progressReport.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            surface.$bell.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        let changes = metadataChanges
        Publishers.MergeMany(publishers)
            .sink { [weak changes] in changes?.send(()) }
            .store(in: &cancellables)
    }

    private func updateObservedMetadata(for windows: [NSWindow]) {
        #if DEBUG
        testingMetadataScanCount += 1
        #endif
        observedWorkingDirectories = Set(
            windows.compactMap { window in
                TabSidebarController.cachedWorkingDirectory(for: window)
            }
        )
        observedSurfaceIDs = Set(
            windows.compactMap { window in
                (window.windowController as? BaseTerminalController)?.focusedSurface?.id
            }
        )
    }

    private func shouldHandle(notificationName: Notification.Name, object: Any?) -> Bool {
        guard terminalWindow != nil else { return false }

        switch notificationName {
        case .yenTabSidebarGitContextDidChange:
            guard let workingDirectory = object as? String else { return true }
            return observedWorkingDirectories.contains(workingDirectory)
        case .yenTabSidebarBuildStatusDidChange:
            guard let surfaceID = object as? UUID else { return true }
            return observedSurfaceIDs.contains(surfaceID)
        default:
            return true
        }
    }
}

#if DEBUG
extension TabSidebarObservationSession {
    func testingShouldHandle(notificationName: Notification.Name, object: Any?) -> Bool {
        shouldHandle(notificationName: notificationName, object: object)
    }
}

#endif
#endif
