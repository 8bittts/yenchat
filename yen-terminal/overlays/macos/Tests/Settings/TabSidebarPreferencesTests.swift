import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct TabSidebarPreferencesTests {
    @Test func tabSidebarPreferencesRegisterDefaultsAndRepairInvalidStoredMode() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard

            TabSidebarPreferences.registerDefaults(in: defaults)

            #expect(TabSidebarPreferences.enabled(from: defaults) == TabSidebarPreferences.defaultEnabled)
            #expect(
                TabSidebarPreferences.presentationMode(from: defaults)
                    == TabSidebarPreferences.defaultPresentationMode
            )
            #expect(
                TabSidebarPreferences.persistentVisible(from: defaults)
                    == TabSidebarPreferences.defaultPersistentVisible
            )
            #expect(
                SplitPaneLabelsPreferences.enabled(from: defaults)
                    == SplitPaneLabelsPreferences.defaultEnabled
            )
            #expect(
                NativeBrowserPreferences.terminalLinkCaptureEnabled(from: defaults)
                    == NativeBrowserPreferences.defaultTerminalLinkCaptureEnabled
            )
            #expect(
                NativeBrowserPreferences.browserSplitEnabled(from: defaults)
                    == NativeBrowserPreferences.defaultBrowserSplitEnabled
            )

            defaults.set("sideways", forKey: TabSidebarPreferences.presentationModePreferenceKey)

            let repaired = TabSidebarPreferences.repairedPresentationMode(in: defaults)

            #expect(repaired == .transient)
            #expect(
                defaults.string(forKey: TabSidebarPreferences.presentationModePreferenceKey)
                    == TabSidebarPresentationMode.transient.rawValue
            )
        }
    }

    @Test func loadWorkspacePreferencesHydratesControllerFromDefaults() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: TabSidebarPreferences.enabledPreferenceKey)
            defaults.set(
                TabSidebarPresentationMode.persistent.rawValue,
                forKey: TabSidebarPreferences.presentationModePreferenceKey
            )
            defaults.set(false, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
            defaults.set(true, forKey: SplitPaneLabelsPreferences.enabledPreferenceKey)
            defaults.set(true, forKey: NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey)
            defaults.set(true, forKey: NativeBrowserPreferences.browserSplitEnabledPreferenceKey)
            defaults.set(false, forKey: ScratchpadController.scratchpadEnabledPreferenceKey)

            let controller = SettingsController.shared
            controller.loadWorkspacePreferences()

            #expect(!controller.tabSidebarEnabled)
            #expect(controller.tabSidebarPresentationMode == .persistent)
            #expect(!TabSidebarController.persistentVisible)
            #expect(controller.splitPaneLabelsEnabled)
            #expect(controller.browserTerminalLinkCaptureEnabled)
            #expect(controller.browserSplitEnabled)
            #expect(!controller.scratchpadEnabled)
        }
    }

    @Test func loadWorkspacePreferencesCoalescesHiddenPersistentSidebarTransition() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared

            controller.tabSidebarPresentationMode = .transient
            defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
            defaults.set(
                TabSidebarPresentationMode.persistent.rawValue,
                forKey: TabSidebarPreferences.presentationModePreferenceKey
            )
            defaults.set(false, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)

            let notificationCount = countSidebarStateChanges {
                controller.loadWorkspacePreferences()
            }

            #expect(notificationCount == 1)
            #expect(controller.tabSidebarPresentationMode == .persistent)
            #expect(!TabSidebarController.shared.visible)
            #expect(!TabSidebarController.persistentVisible)
        }
    }

    @Test func transientWorkspacePreferenceLoadDoesNotForceSidebarVisible() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            defaults.set(
                TabSidebarPresentationMode.transient.rawValue,
                forKey: TabSidebarPreferences.presentationModePreferenceKey
            )
            defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)

            let controller = SettingsController.shared
            controller.loadWorkspacePreferences()

            #expect(controller.tabSidebarPresentationMode == .transient)
            #expect(TabSidebarController.persistentVisible)
            #expect(!TabSidebarController.shared.visible)
        }
    }

    @Test func persistentSidebarColdStartVisibilityTracksStoredPreference() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
            defaults.set(
                TabSidebarPresentationMode.persistent.rawValue,
                forKey: TabSidebarPreferences.presentationModePreferenceKey
            )

            let sidebarController = TabSidebarController.shared

            defaults.set(false, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
            sidebarController.testingReloadVisibleStateFromPreferences()
            #expect(!sidebarController.visible)

            defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
            sidebarController.testingReloadVisibleStateFromPreferences()
            #expect(sidebarController.visible)
        }
    }

    @Test func disabledPersistentSidebarColdStartStaysLogicallyHidden() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: TabSidebarPreferences.enabledPreferenceKey)
            defaults.set(
                TabSidebarPresentationMode.persistent.rawValue,
                forKey: TabSidebarPreferences.presentationModePreferenceKey
            )
            defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)

            let sidebarController = TabSidebarController.shared
            sidebarController.testingReloadVisibleStateFromPreferences()
            #expect(!sidebarController.visible)
            #expect(TabSidebarController.persistentVisible)

            let controller = SettingsController.shared
            controller.loadWorkspacePreferences()

            #expect(!controller.tabSidebarEnabled)
            #expect(controller.tabSidebarPresentationMode == .persistent)
            #expect(!sidebarController.visible)
            #expect(TabSidebarController.persistentVisible)
        }
    }

    @Test func workspaceControllerWritesPresentationModePreferenceOnChange() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared

            controller.loadWorkspacePreferences()
            controller.tabSidebarPresentationMode = .persistent
            #expect(
                defaults.string(forKey: TabSidebarPreferences.presentationModePreferenceKey)
                    == TabSidebarPresentationMode.persistent.rawValue
            )

            controller.tabSidebarPresentationMode = .transient
            #expect(
                defaults.string(forKey: TabSidebarPreferences.presentationModePreferenceKey)
                    == TabSidebarPresentationMode.transient.rawValue
            )
        }
    }

    @Test func disablingSidebarPreservesPinnedVisibilityForReenable() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared
            let sidebarController = TabSidebarController.shared

            controller.tabSidebarEnabled = true
            controller.tabSidebarPresentationMode = .persistent
            sidebarController.setPersistentVisiblePreference(true)

            controller.tabSidebarEnabled = false
            #expect(!sidebarController.visible)
            #expect(
                defaults.object(forKey: TabSidebarPreferences.persistentVisiblePreferenceKey) as? Bool
                    == true
            )

            controller.tabSidebarEnabled = true
            #expect(sidebarController.visible)
            #expect(
                defaults.object(forKey: TabSidebarPreferences.persistentVisiblePreferenceKey) as? Bool
                    == true
            )
        }
    }

    @Test func workspaceControllerWritesSplitLabelPreferenceOnChange() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared

            controller.loadWorkspacePreferences()
            controller.splitPaneLabelsEnabled = true
            #expect(defaults.object(forKey: SplitPaneLabelsPreferences.enabledPreferenceKey) as? Bool == true)

            controller.splitPaneLabelsEnabled = false
            #expect(defaults.object(forKey: SplitPaneLabelsPreferences.enabledPreferenceKey) as? Bool == false)
        }
    }

    @Test func restoredWorkspacePreferencesCoalesceHiddenPersistentSidebarTransition() {
        withIsolatedWorkspacePreferences {
            let controller = SettingsController.shared
            let defaults = UserDefaults.standard

            controller.restoreWorkspacePreferenceState(
                WorkspacePreferenceState(
                    tabSidebarEnabled: true,
                    tabSidebarPresentationMode: .transient,
                    tabSidebarPersistentVisible: true,
                    splitPaneLabelsEnabled: false,
                    splitPaneWorktreeNamingEnabled: false,
                    browserTerminalLinkCaptureEnabled: false,
                    browserSplitEnabled: false,
                    scratchpadEnabled: true,
                    backgroundImageScope: .eachSplit
                )
            )

            // A reset or a rollback applies a whole workspace state at once.
            let notificationCount = countSidebarStateChanges {
                controller.restoreWorkspacePreferenceState(
                    WorkspacePreferenceState(
                        tabSidebarEnabled: true,
                        tabSidebarPresentationMode: .persistent,
                        tabSidebarPersistentVisible: false,
                        splitPaneLabelsEnabled: true,
                        splitPaneWorktreeNamingEnabled: true,
                        browserTerminalLinkCaptureEnabled: true,
                        browserSplitEnabled: true,
                        scratchpadEnabled: false,
                        backgroundImageScope: .eachSplit
                    )
                )
            }

            #expect(notificationCount == 1)
            #expect(
                controller.captureWorkspacePreferenceState() == WorkspacePreferenceState(
                    tabSidebarEnabled: true,
                    tabSidebarPresentationMode: .persistent,
                    tabSidebarPersistentVisible: false,
                    splitPaneLabelsEnabled: true,
                    splitPaneWorktreeNamingEnabled: true,
                    browserTerminalLinkCaptureEnabled: true,
                    browserSplitEnabled: true,
                    scratchpadEnabled: false,
                    backgroundImageScope: .eachSplit
                )
            )
            #expect(
                defaults.string(forKey: TabSidebarPreferences.presentationModePreferenceKey)
                    == TabSidebarPresentationMode.persistent.rawValue
            )
            #expect(
                defaults.object(forKey: TabSidebarPreferences.persistentVisiblePreferenceKey) as? Bool
                    == false
            )
        }
    }

    @Test func workspacePreferenceStateRestoreReinstatesPersistentMode() {
        withIsolatedWorkspacePreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared

            controller.tabSidebarEnabled = false
            controller.tabSidebarPresentationMode = .persistent
            TabSidebarController.shared.setPersistentVisiblePreference(false)
            controller.splitPaneLabelsEnabled = true
            controller.browserTerminalLinkCaptureEnabled = true
            controller.browserSplitEnabled = true
            controller.scratchpadEnabled = false
            let snapshot = controller.captureWorkspacePreferenceState()

            controller.tabSidebarEnabled = true
            controller.tabSidebarPresentationMode = .transient
            TabSidebarController.shared.setPersistentVisiblePreference(true)
            controller.splitPaneLabelsEnabled = false
            controller.browserTerminalLinkCaptureEnabled = false
            controller.browserSplitEnabled = false
            controller.scratchpadEnabled = true

            let notificationCount = countSidebarStateChanges {
                controller.restoreWorkspacePreferenceState(snapshot)
            }

            #expect(notificationCount == 1)
            #expect(controller.captureWorkspacePreferenceState() == snapshot)
            #expect(defaults.object(forKey: TabSidebarPreferences.enabledPreferenceKey) as? Bool == false)
            #expect(
                defaults.string(forKey: TabSidebarPreferences.presentationModePreferenceKey)
                    == TabSidebarPresentationMode.persistent.rawValue
            )
            #expect(
                defaults.object(forKey: TabSidebarPreferences.persistentVisiblePreferenceKey) as? Bool
                    == false
            )
            #expect(
                defaults.object(forKey: SplitPaneLabelsPreferences.enabledPreferenceKey) as? Bool
                    == true
            )
            #expect(
                defaults.object(forKey: NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey) as? Bool
                    == true
            )
            #expect(
                defaults.object(forKey: NativeBrowserPreferences.browserSplitEnabledPreferenceKey) as? Bool
                    == true
            )
            #expect(
                defaults.object(forKey: ScratchpadController.scratchpadEnabledPreferenceKey) as? Bool
                    == false
            )
        }
    }

    private func countSidebarStateChanges(_ operation: () throws -> Void) rethrows -> Int {
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .yenTabSidebarStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try operation()
        return count
    }

    private func withIsolatedWorkspacePreferences(
        _ operation: () throws -> Void
    ) rethrows {
        try TestExclusiveLock.withLock(named: "workspace-preferences") {
            let defaults = UserDefaults.standard
            let keys = [
                TabSidebarPreferences.enabledPreferenceKey,
                TabSidebarPreferences.presentationModePreferenceKey,
                TabSidebarPreferences.persistentVisiblePreferenceKey,
                SplitPaneLabelsPreferences.enabledPreferenceKey,
                NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey,
                NativeBrowserPreferences.browserSplitEnabledPreferenceKey,
                ScratchpadController.scratchpadEnabledPreferenceKey,
            ]
            let controller = SettingsController.shared
            let sidebarController = TabSidebarController.shared
            let originalState = controller.captureWorkspacePreferenceState()

            var originalValues: [String: Any] = [:]
            for key in keys {
                if let value = defaults.object(forKey: key) {
                    originalValues[key] = value
                }
                defaults.removeObject(forKey: key)
            }

            sidebarController.testingResetState()
            sidebarController.testingReloadVisibleStateFromPreferences()

            defer {
                for key in keys {
                    defaults.removeObject(forKey: key)
                    if let original = originalValues[key] {
                        defaults.set(original, forKey: key)
                    }
                }

                controller.restoreWorkspacePreferenceState(originalState)
                sidebarController.testingResetState()
                sidebarController.testingReloadVisibleStateFromPreferences()
            }

            try operation()
        }
    }
}
