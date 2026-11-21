import Foundation

@MainActor
final class WorkspaceSettingsStore: SettingsSnapshotStore<WorkspaceSettingsStore.Snapshot> {
    struct Snapshot: Equatable {
        let tabSidebarEnabled: Bool
        let tabSidebarPresentationMode: TabSidebarPresentationMode
        let paneStyle: PaneStyle
        let splitPaneLabelsEnabled: Bool
        let splitPaneWorktreeNamingEnabled: Bool
        let browserTerminalLinkCaptureEnabled: Bool
        let browserSplitEnabled: Bool
        let scratchpadEnabled: Bool

        @MainActor
        static func capture(from controller: SettingsController) -> Snapshot {
            Snapshot(
                tabSidebarEnabled: controller.tabSidebarEnabled,
                tabSidebarPresentationMode: controller.tabSidebarPresentationMode,
                paneStyle: controller.paneStyle,
                splitPaneLabelsEnabled: controller.splitPaneLabelsEnabled,
                splitPaneWorktreeNamingEnabled: controller.splitPaneWorktreeNamingEnabled,
                browserTerminalLinkCaptureEnabled: controller.browserTerminalLinkCaptureEnabled,
                browserSplitEnabled: controller.browserSplitEnabled,
                scratchpadEnabled: controller.scratchpadEnabled
            )
        }
    }

    private let controller: SettingsController

    init(controller: SettingsController) {
        self.controller = controller
        super.init(
            notification: .yenWorkspaceSettingsDidChange,
            object: controller,
            capture: { Snapshot.capture(from: controller) }
        )
    }

    func setTabSidebarEnabled(_ value: Bool) {
        controller.tabSidebarEnabled = value
    }

    func setTabSidebarPresentationMode(_ value: TabSidebarPresentationMode) {
        controller.tabSidebarPresentationMode = value
    }

    func setPaneStyle(_ style: PaneStyle) {
        controller.paneStyle = style
    }

    func setSplitPaneLabelsEnabled(_ value: Bool) {
        controller.splitPaneLabelsEnabled = value
    }

    func setSplitPaneWorktreeNamingEnabled(_ value: Bool) {
        controller.splitPaneWorktreeNamingEnabled = value
    }

    func setBrowserTerminalLinkCaptureEnabled(_ value: Bool) {
        controller.browserTerminalLinkCaptureEnabled = value
    }

    func setBrowserSplitEnabled(_ value: Bool) {
        controller.browserSplitEnabled = value
    }

    func setScratchpadEnabled(_ value: Bool) {
        controller.scratchpadEnabled = value
    }

}
