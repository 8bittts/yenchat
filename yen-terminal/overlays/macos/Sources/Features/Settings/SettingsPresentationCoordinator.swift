#if os(macOS)
import AppKit

@MainActor
enum SettingsPresentationRefreshReason: Equatable {
    case initialPresentation
    case reopenHiddenWindow
    case retargetVisibleWindow
    case refocusVisibleWindow

    var requiresFullRefresh: Bool {
        switch self {
        case .initialPresentation, .reopenHiddenWindow:
            return true
        case .retargetVisibleWindow, .refocusVisibleWindow:
            return false
        }
    }
}

@MainActor
final class SettingsPresentationCoordinator {
    private var pendingRefreshGeneration: UInt64?
    private var refreshTaskGeneration: UInt64 = 0

#if DEBUG
    private(set) var scheduledRefreshCount = 0
#endif

    func presentationReason(
        createdWindow: Bool,
        windowWasVisible: Bool,
        requestedPane: SettingsPane?
    ) -> SettingsPresentationRefreshReason {
        if createdWindow {
            return .initialPresentation
        }
        if windowWasVisible {
            return requestedPane == nil ? .refocusVisibleWindow : .retargetVisibleWindow
        }
        return .reopenHiddenWindow
    }

    func scheduleRefreshIfNeeded(
        for reason: SettingsPresentationRefreshReason,
        isWindowVisible: @escaping @MainActor () -> Bool,
        refresh: @escaping @MainActor () -> Void
    ) {
        guard reason.requiresFullRefresh else { return }

#if DEBUG
        scheduledRefreshCount += 1
#endif
        cancelRefresh()
        refreshTaskGeneration &+= 1
        let generation = refreshTaskGeneration
        pendingRefreshGeneration = generation
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.pendingRefreshGeneration == generation else { return }
                defer {
                    if self.pendingRefreshGeneration == generation {
                        self.pendingRefreshGeneration = nil
                    }
                }

                guard isWindowVisible() else { return }
                refresh()
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    func cancelRefresh() {
        pendingRefreshGeneration = nil
    }

    var hasRefreshTask: Bool {
        pendingRefreshGeneration != nil
    }

#if DEBUG
    func _testResetMetrics() {
        scheduledRefreshCount = 0
    }
#endif
}
#endif
