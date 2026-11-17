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
    #if DEBUG
    var testingMetadataScanCount: Int { observationSession.testingMetadataScanCount }
    #endif

    func attach(to window: NSWindow?) {
        hostWindow = window
        observationSession.attach(to: window)
        refreshTabs()
        restartRefreshTimerIfNeeded()
    }

    func setVisible(_ visible: Bool) {
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
            stopRefreshTimer()
            observationSession.detach()
        }
    }
}

#endif
