import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct ConflictShortcutCacheTests {
    @Test func currentInstallStateConflictCacheIsReusedUntilExplicitInvalidation() {
        let controller = SettingsController.shared
        reset(controller)
        defer {
            ConflictDetector._testSetInstalledKnownAppBundleIDs(nil)
            reset(controller)
        }

        let installedBundleIDs: Set<String> = ["dev.yen.installed"]
        ConflictDetector._testSetInstalledKnownAppBundleIDs(installedBundleIDs)

        controller.keybindEntries = KeybindRegistry.defaults
        controller._testSetConflictShortcutCache(
            ConflictDetector.CachedShortcuts(
                systemShortcuts: [],
                appShortcuts: [],
                installedKnownAppBundleIDs: installedBundleIDs
            )
        )

        ConflictDetector._testResetMetrics()
        _ = controller._testLoadCurrentConflictShortcutCache()
        _ = controller._testLoadCurrentConflictShortcutCache()

        #expect(ConflictDetector._testScanShortcutInvocationCount == 0)
    }

    @Test func installedAppStateChangeInvalidatesConflictCacheOnNextAccess() {
        let controller = SettingsController.shared
        reset(controller)
        defer {
            ConflictDetector._testSetInstalledKnownAppBundleIDs(nil)
            reset(controller)
        }

        ConflictDetector._testSetInstalledKnownAppBundleIDs(["dev.yen.before"])
        controller._testSetConflictShortcutCache(
            ConflictDetector.CachedShortcuts(
                systemShortcuts: [],
                appShortcuts: [],
                installedKnownAppBundleIDs: ["dev.yen.before"]
            )
        )

        ConflictDetector._testResetMetrics()
        _ = controller._testLoadCurrentConflictShortcutCache()
        #expect(ConflictDetector._testScanShortcutInvocationCount == 0)

        ConflictDetector._testSetInstalledKnownAppBundleIDs(["dev.yen.after"])
        _ = controller._testLoadCurrentConflictShortcutCache()

        #expect(ConflictDetector._testScanShortcutInvocationCount == 1)
    }

    @Test func invalidatedConflictCacheRefreshesOnNextAccess() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller._testSetConflictShortcutCache(
            ConflictDetector.CachedShortcuts(
                systemShortcuts: [],
                appShortcuts: [],
                installedKnownAppBundleIDs: []
            )
        )
        controller._testInvalidateConflictShortcutCache()

        ConflictDetector._testResetMetrics()
        _ = controller._testLoadCurrentConflictShortcutCache()

        #expect(ConflictDetector._testScanShortcutInvocationCount == 1)
    }

    @Test func singleTriggerConflictLookupUsesModifierBucketsAndKeepsPhysicalKeyMatching() {
        let commandModifiers = KeyModifiers(cmd: true)
        let controlModifiers = KeyModifiers(ctrl: true)
        let target = KeyTrigger(modifiers: commandModifiers, key: "a", keyCode: 0)
        let cache = ConflictDetector.CachedShortcuts(
            systemShortcuts: [
                ConflictDetector.SystemShortcut(
                    name: "Command Same Physical",
                    trigger: KeyTrigger(modifiers: commandModifiers, key: "q", keyCode: 0)
                ),
                ConflictDetector.SystemShortcut(
                    name: "Command Other Physical",
                    trigger: KeyTrigger(modifiers: commandModifiers, key: "b", keyCode: 11)
                ),
                ConflictDetector.SystemShortcut(
                    name: "Control Same Physical",
                    trigger: KeyTrigger(modifiers: controlModifiers, key: "a", keyCode: 0)
                ),
            ],
            appShortcuts: [
                ConflictDetector.AppShortcut(
                    bundleId: "dev.yen.match",
                    appName: "Match App",
                    actionName: "Match Action",
                    trigger: KeyTrigger(modifiers: commandModifiers, key: "a"),
                    icon: nil
                ),
                ConflictDetector.AppShortcut(
                    bundleId: "dev.yen.control",
                    appName: "Control App",
                    actionName: "Control Action",
                    trigger: KeyTrigger(modifiers: controlModifiers, key: "a"),
                    icon: nil
                ),
            ],
            installedKnownAppBundleIDs: ["dev.yen.match", "dev.yen.control"]
        )

        let conflicts = ConflictDetector.conflicts(for: target, using: cache)

        #expect(cache._testSystemShortcutBucketCount(for: commandModifiers) == 2)
        #expect(cache._testSystemShortcutBucketCount(for: controlModifiers) == 1)
        #expect(cache._testAppShortcutBucketCount(for: commandModifiers) == 1)
        #expect(cache._testAppShortcutBucketCount(for: controlModifiers) == 1)
        #expect(conflicts.map(\.description) == [
            "macOS: Command Same Physical uses Cmd + Q",
            "Match App: Match Action uses Cmd + A",
        ])
    }

    @Test func updatingOneKeybindReappliesConflictsOnlyForChangedEntry() throws {
        let controller = SettingsController.shared
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "".write(to: configURL, atomically: true, encoding: .utf8)
        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            ConflictDetector._testSetInstalledKnownAppBundleIDs(nil)
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        let replacementTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true, option: true), key: "c")
        ConflictDetector._testSetInstalledKnownAppBundleIDs(["dev.yen.clipboard"])
        controller.keybindEntries = KeybindRegistry.defaults
        controller._testSetConflictShortcutCache(
            ConflictDetector.CachedShortcuts(
                systemShortcuts: [],
                appShortcuts: [
                    ConflictDetector.AppShortcut(
                        bundleId: "dev.yen.clipboard",
                        appName: "Clipboard App",
                        actionName: "Clipboard History",
                        trigger: replacementTrigger,
                        icon: nil
                    ),
                ],
                installedKnownAppBundleIDs: ["dev.yen.clipboard"]
            )
        )

        guard let editableEntry = controller.keybindEntries.first(where: {
            $0.action == "paste_from_clipboard" && $0.isEditable
        }) else {
            Issue.record("Missing editable paste_from_clipboard keybind entry")
            return
        }

        ConflictDetector._testResetMetrics()
        #expect(
            controller.updateKeybind(stableId: editableEntry.stableId, trigger: replacementTrigger)
                == .recorded
        )

        let updatedEntry = controller.keybindEntries.first(where: { $0.stableId == editableEntry.stableId })
        #expect(ConflictDetector._testConflictEntryApplicationCount == 1)
        #expect(updatedEntry?.conflicts.map(\.description) == [
            "Clipboard App: Clipboard History uses Cmd + Option + C",
        ])
    }

    @Test func resettingOneKeybindReappliesConflictsOnlyForChangedEntry() throws {
        let controller = SettingsController.shared
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "".write(to: configURL, atomically: true, encoding: .utf8)
        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            ConflictDetector._testSetInstalledKnownAppBundleIDs(nil)
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        let overrideTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true, option: true), key: "c")
        ConflictDetector._testSetInstalledKnownAppBundleIDs(["dev.yen.paste"])
        controller.keybindEntries = KeybindRegistry.defaults

        guard let editableIndex = controller.keybindEntries.firstIndex(where: {
            $0.action == "paste_from_clipboard" && $0.isEditable
        }) else {
            Issue.record("Missing editable paste_from_clipboard keybind entry")
            return
        }

        let editableEntry = controller.keybindEntries[editableIndex]
        controller.keybindEntries[editableIndex].currentTrigger = overrideTrigger
        controller.keybindEntries[editableIndex].isUserOverride = true
        controller._testSetConflictShortcutCache(
            ConflictDetector.CachedShortcuts(
                systemShortcuts: [],
                appShortcuts: [
                    ConflictDetector.AppShortcut(
                        bundleId: "dev.yen.paste",
                        appName: "Paste App",
                        actionName: "Paste",
                        trigger: editableEntry.defaultTrigger,
                        icon: nil
                    ),
                ],
                installedKnownAppBundleIDs: ["dev.yen.paste"]
            )
        )

        ConflictDetector._testResetMetrics()
        controller.resetKeybind(stableId: editableEntry.stableId)

        let resetEntry = controller.keybindEntries.first(where: { $0.stableId == editableEntry.stableId })
        #expect(ConflictDetector._testConflictEntryApplicationCount == 1)
        #expect(resetEntry?.currentTrigger == editableEntry.defaultTrigger)
        #expect(resetEntry?.isUserOverride == false)
        #expect(resetEntry?.conflicts.map(\.description) == [
            "Paste App: Paste uses Cmd + V",
        ])
    }

    private func reset(_ controller: SettingsController) {
        controller.hide()
        controller.resetKeybindReloadStateForTesting()
        controller._testInvalidateConflictShortcutCache()
    }
}
