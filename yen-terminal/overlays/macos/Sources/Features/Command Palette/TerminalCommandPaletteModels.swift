// YEN Overlay: command palette observable models split from TerminalCommandPalette.swift.

import AppKit
import Combine
import SwiftUI
import YENKit

@MainActor
final class TerminalCommandPaletteRepositoryWorkspaceModel: ObservableObject {
    @Published private(set) var isRepositoryWorkspace = false

    private let workflowTrustFilePathResolver: () -> String
    private var currentWorkingDirectory: String?
    private var eligibilityTask: Task<Void, Never>?

    init(
        workflowTrustFilePathResolver: @escaping () -> String = {
            TerminalCommandPaletteView.repositoryWorkflowTrustFilePath()
        }
    ) {
        self.workflowTrustFilePathResolver = workflowTrustFilePathResolver
    }

    func refresh(workingDirectory: String?) {
        let normalizedWorkingDirectory = TerminalCommandPaletteView.normalizedWorkingDirectory(workingDirectory)
        let workflowTrustFilePath = workflowTrustFilePathResolver()
        currentWorkingDirectory = normalizedWorkingDirectory
        eligibilityTask?.cancel()
        eligibilityTask = nil
        isRepositoryWorkspace = false

        guard let normalizedWorkingDirectory else {
            return
        }

        eligibilityTask = Task { [weak self] in
            let isRepositoryWorkspace = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask(priority: .utility) {
                    TerminalCommandPaletteView.repositoryWorkspaceEligibility(
                        for: normalizedWorkingDirectory,
                        workflowTrustFilePath: workflowTrustFilePath
                    )
                }
                return await group.next() ?? false
            }

            guard !Task.isCancelled, let self else { return }
            guard self.currentWorkingDirectory == normalizedWorkingDirectory else { return }
            self.isRepositoryWorkspace = isRepositoryWorkspace
        }
    }

    func reset() {
        currentWorkingDirectory = nil
        eligibilityTask?.cancel()
        eligibilityTask = nil
        isRepositoryWorkspace = false
    }

    deinit {
        eligibilityTask?.cancel()
    }
}

struct TerminalCommandPaletteJumpTargetSnapshot: Equatable {
    let objectID: ObjectIdentifier
    let surface: YEN.SurfaceView
    let title: String
    let subtitle: String?
    let tabColor: TerminalTabColor

    static func == (lhs: TerminalCommandPaletteJumpTargetSnapshot, rhs: TerminalCommandPaletteJumpTargetSnapshot) -> Bool {
        lhs.objectID == rhs.objectID &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.tabColor == rhs.tabColor
    }
}

@MainActor
final class TerminalCommandPaletteJumpTargetsModel: ObservableObject {
    typealias ObserverRegistrar = (_ name: Notification.Name, _ handler: @escaping () -> Void) -> NSObjectProtocol
    typealias ObserverRemover = (_ observer: NSObjectProtocol) -> Void
    /// The action crosses into a `Task`, so it must be `@Sendable`.
    typealias RefreshScheduler = (_ action: @escaping @MainActor @Sendable () -> Void) -> Void

    @Published private(set) var snapshots: [TerminalCommandPaletteJumpTargetSnapshot] = []

    private let loadSnapshots: @MainActor () -> [TerminalCommandPaletteJumpTargetSnapshot]
    private let registerObserver: ObserverRegistrar
    private let removeObserver: ObserverRemover
    private let scheduleRefresh: RefreshScheduler
    private let refreshInterval: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var isActive = false
    private var generation = 0
    private let refreshRequests = PassthroughSubject<Void, Never>()
    private var refreshSubscription: AnyCancellable?
    private var surfaceSubscriptions: Set<AnyCancellable> = []
    private var titleObservations: [NSKeyValueObservation] = []
    private var observedSurfaceIDs: [ObjectIdentifier] = []
    private var observedWindowIDs: Set<ObjectIdentifier> = []

    init(
        loadSnapshots: @escaping @MainActor () -> [TerminalCommandPaletteJumpTargetSnapshot] = {
            TerminalCommandPaletteView.loadJumpTargetSnapshots()
        },
        notificationCenter: NotificationCenter = .default,
        registerObserver: ObserverRegistrar? = nil,
        removeObserver: ObserverRemover? = nil,
        scheduleRefresh: RefreshScheduler? = nil,
        refreshInterval: TimeInterval? = 5
    ) {
        self.loadSnapshots = loadSnapshots
        if let registerObserver {
            self.registerObserver = registerObserver
        } else {
            self.registerObserver = { name, handler in
                notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { _ in
                    handler()
                }
            }
        }
        if let removeObserver {
            self.removeObserver = removeObserver
        } else {
            self.removeObserver = { observer in
                notificationCenter.removeObserver(observer)
            }
        }
        if let scheduleRefresh {
            self.scheduleRefresh = scheduleRefresh
        } else {
            self.scheduleRefresh = { action in
                Task { @MainActor in
                    action()
                }
            }
        }
        self.refreshInterval = refreshInterval
    }

    func start() {
        guard !isActive else { return }

        isActive = true
        generation += 1
        refreshSubscription = refreshRequests.debounce(for: .zero, scheduler: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        refresh()
        installObservers()
        restartRefreshTimerIfNeeded()
    }

    func stop() {
        isActive = false
        generation += 1
        refreshSubscription = nil
        surfaceSubscriptions.removeAll()
        titleObservations.removeAll()
        observedSurfaceIDs = []
        observedWindowIDs = []
        for observer in observers {
            removeObserver(observer)
        }
        observers.removeAll(keepingCapacity: false)
        refreshTimer?.invalidate()
        refreshTimer = nil
        snapshots = []
    }

    func refresh() {
        guard isActive else { return }
        let updatedSnapshots = loadSnapshots()
        observeMetadata(in: updatedSnapshots)
        guard updatedSnapshots != snapshots else { return }
        snapshots = updatedSnapshots
    }

    deinit {
        refreshTimer?.invalidate()
        for observer in observers {
            removeObserver(observer)
        }
    }

    private func installObservers() {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            .yenTabSidebarStateDidChange,
            YEN.Notification.yenPresentTerminal,
            YEN.Notification.yenFocusSplit,
            YEN.Notification.yenNewSplit,
            YEN.Notification.yenCloseSurface,
            YEN.Notification.didEqualizeSplits,
        ]

        let generation = self.generation
        observers = names.map { name in
            registerObserver(name) { [weak self] in
                self?.scheduleRefresh { [weak self] in
                    self?.requestRefresh(generation: generation)
                }
            }
        }
    }

    private func requestRefresh(generation: Int) {
        guard isActive, self.generation == generation else { return }
        refreshRequests.send(())
    }

    private func observeMetadata(in snapshots: [TerminalCommandPaletteJumpTargetSnapshot]) {
        let surfaceIDs = snapshots.map(\.objectID)
        let windows = Dictionary(snapshots.compactMap { snapshot -> (ObjectIdentifier, NSWindow)? in
            guard let window = snapshot.surface.window else { return nil }
            return (ObjectIdentifier(window), window)
        }, uniquingKeysWith: { first, _ in first })
        let windowIDs = Set(windows.keys)
        guard surfaceIDs != observedSurfaceIDs || windowIDs != observedWindowIDs else { return }
        observedSurfaceIDs = surfaceIDs
        observedWindowIDs = windowIDs
        surfaceSubscriptions.removeAll()
        titleObservations.removeAll()
        let requests = refreshRequests
        for snapshot in snapshots {
            Publishers.Merge(snapshot.surface.$title.dropFirst().map { _ in () },
                snapshot.surface.$pwd.dropFirst().map { _ in () })
                .sink { [weak requests] in requests?.send(()) }
                .store(in: &surfaceSubscriptions)
        }
        let generation = self.generation
        for window in windows.values {
            titleObservations.append(window.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.requestRefresh(generation: generation) }
            })
        }
    }

    private func restartRefreshTimerIfNeeded() {
        refreshTimer?.invalidate()
        guard let refreshInterval else { return }
        let generation = self.generation
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestRefresh(generation: generation)
            }
        }
        refreshTimer?.tolerance = min(1, refreshInterval * 0.2)
    }
}


