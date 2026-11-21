import Combine
import Foundation
import Testing
@testable import YEN

@Suite(.serialized)
@MainActor
struct WorkspaceSettingsStoreTests {
    @Test func suppressesPublishWhenWorkspaceNotificationLeavesSnapshotEqual() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let store = WorkspaceSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenWorkspaceSettingsDidChange, object: controller)
        drainMainRunLoop()

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func ignoresIrrelevantSettingsChanges() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let store = WorkspaceSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.selectedSettingsPane = .shortcuts
        drainMainRunLoop()

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func republishesWhenWorkspaceSettingsChange() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.tabSidebarEnabled = true
        let store = WorkspaceSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.tabSidebarEnabled = false
        drainMainRunLoop()

        #expect(store.snapshot.tabSidebarEnabled != baseline.tabSidebarEnabled)
        #expect(emissionCount == 1)
    }

    @Test func refreshesAcrossWorkspacePreferenceLoads() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let store = WorkspaceSettingsStore(controller: controller)
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: TabSidebarPreferences.enabledPreferenceKey)
        defaults.set(
            TabSidebarPresentationMode.persistent.rawValue,
            forKey: TabSidebarPreferences.presentationModePreferenceKey
        )
        defaults.set(PaneStyle.compact.rawValue, forKey: PaneStyle.preferenceKey)
        defaults.set(true, forKey: SplitPaneLabelsPreferences.enabledPreferenceKey)
        defaults.set(true, forKey: SplitPaneLabelsPreferences.worktreeNamingEnabledPreferenceKey)
        defaults.set(true, forKey: NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey)
        defaults.set(true, forKey: NativeBrowserPreferences.browserSplitEnabledPreferenceKey)
        defaults.set(false, forKey: ScratchpadController.scratchpadEnabledPreferenceKey)

        controller.loadWorkspacePreferences()
        drainMainRunLoop()

        #expect(store.snapshot == .init(
            tabSidebarEnabled: false,
            tabSidebarPresentationMode: .persistent,
            paneStyle: .compact,
            splitPaneLabelsEnabled: true,
            splitPaneWorktreeNamingEnabled: true,
            browserTerminalLinkCaptureEnabled: true,
            browserSplitEnabled: true,
            scratchpadEnabled: false
        ))
        #expect(emissionCount > 0)
    }

    @Test func setterMutatesControllerAndRepublishesSnapshot() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.tabSidebarEnabled = true
        let store = WorkspaceSettingsStore(controller: controller)
        #expect(store.snapshot.tabSidebarEnabled)

        store.setTabSidebarEnabled(false)
        drainMainRunLoop()

        #expect(controller.tabSidebarEnabled == false)
        #expect(store.snapshot.tabSidebarEnabled == false)

        controller.splitPaneLabelsEnabled = false
        let presentation = SplitPaneLabelSettings(settingsController: controller)
        store.setPaneStyle(.compact)
        drainMainRunLoop()

        #expect(store.snapshot.paneStyle == .compact)
        #expect(presentation.paneStyle == .compact)
        #expect(PaneStyle.stored() == .compact)
        #expect(!presentation.isEnabled)

        store.setSplitPaneWorktreeNamingEnabled(true)
        drainMainRunLoop()

        #expect(controller.splitPaneWorktreeNamingEnabled)
        #expect(store.snapshot.splitPaneWorktreeNamingEnabled)
    }

    private func reset(_ controller: SettingsController) {
        SettingsController._testSetWindowCloseMemoryModeOverride(nil)
        controller.hide()
        drainMainRunLoop()
        controller._testResetWindowState()
        controller.selectedSettingsPane = .general
        controller.resetKeybindReloadStateForTesting()
        controller.paneStyle = .comfortable
        controller.tabSidebarEnabled = TabSidebarPreferences.defaultEnabled
        controller.tabSidebarPresentationMode = TabSidebarPreferences.defaultPresentationMode
        controller.splitPaneLabelsEnabled = SplitPaneLabelsPreferences.defaultEnabled
        controller.splitPaneWorktreeNamingEnabled = SplitPaneLabelsPreferences.defaultWorktreeNamingEnabled
        controller.browserTerminalLinkCaptureEnabled = NativeBrowserPreferences.defaultTerminalLinkCaptureEnabled
        controller.browserSplitEnabled = NativeBrowserPreferences.defaultBrowserSplitEnabled
        controller.scratchpadEnabled = true
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}
