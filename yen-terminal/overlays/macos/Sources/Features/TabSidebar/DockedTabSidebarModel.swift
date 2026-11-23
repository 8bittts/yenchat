#if os(macOS)
import Cocoa
import Combine
import SwiftUI

@MainActor
final class DockedTabSidebarModel: TabSidebarDataSource {
    private weak var hostWindow: NSWindow?
    private lazy var observationSession = TabSidebarObservationSession { [weak self] in
        self?.refreshTabs(rescan: false)
    }
    private var refreshTimer: Timer?
    private var railVisible = true
    private var occlusionObserver: NSObjectProtocol?
    #if DEBUG
    var testingMetadataScanCount: Int { observationSession.testingMetadataScanCount }
    #endif

    func attach(to window: NSWindow?) {
        hostWindow = window
        observeOcclusion(of: window)
        syncHostsShowing()
        observationSession.attach(to: window)
        refreshTabs()
        restartRefreshTimerIfNeeded()
    }

    func setVisible(_ visible: Bool) {
        railVisible = visible
        syncHostsShowing()
        if visible {
            observationSession.attach(to: hostWindow)
            restartRefreshTimerIfNeeded()
            refreshTabs()
        } else {
            stopRefreshTimer()
            observationSession.detach()
            updateTabsIfNeeded([])
        }
    }

    override var commandTargetWindow: NSWindow? { hostWindow }

    /// A rail shows its Hosts section only while its window is on screen: a
    /// background tab, a minimized window or one on another Space is not.
    nonisolated static func railShowsHosts(railVisible: Bool, hasWindow: Bool, windowOnScreen: Bool) -> Bool {
        railVisible && hasWindow && windowOnScreen
    }

    private func syncHostsShowing() {
        hostsSection.setShowing(Self.railShowsHosts(
            railVisible: railVisible,
            hasWindow: hostWindow != nil,
            windowOnScreen: hostWindow?.occlusionState.contains(.visible) == true
        ))
    }

    private func observeOcclusion(of window: NSWindow?) {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncHostsShowing() }
        }
    }

    override func newTab() {
        guard let controller = hostWindow?.windowController as? TerminalController else { return }
        controller.newTab(nil)
    }

    private func refreshTabs(rescan: Bool = true) {
        guard let hostWindow else {
            observationSession.detach()
            updateTabsIfNeeded([])
            return
        }
        if rescan { observationSession.rescanObservedWindows() }
        updateTabsIfNeeded(TabSidebarController.items(for: hostWindow))
    }

    private func restartRefreshTimerIfNeeded() {
        stopRefreshTimer()
        guard hostWindow != nil else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TabSidebarController.metadataFallbackRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTabs()
            }
        }
        refreshTimer?.tolerance = TabSidebarController.metadataFallbackRefreshTolerance
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        MainActor.assumeIsolated {
            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
            hostsSection.setShowing(false)
            stopRefreshTimer()
            observationSession.detach()
        }
    }
}

#endif
