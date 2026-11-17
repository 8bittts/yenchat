import Combine
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct KeyboardSettingsStoreTests {
    @Test func storeDoesNotPublishForEqualSnapshotNotification() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries
        let originalKeyboardRecordingActive = controller.keyboardRecordingActive
        defer {
            controller.keybindEntries = originalKeybindEntries
            controller.keyboardRecordingActive = originalKeyboardRecordingActive
            reset(controller)
        }

        reset(controller)
        controller.keybindEntries = KeybindRegistry.defaults
        controller.keyboardRecordingActive = false

        let store = KeyboardSettingsStore(controller: controller)
        let baselineEntryIdentities = store.snapshot.entryIdentities
        let baselineReloadPending = store.snapshot.keybindReloadPending
        let baselineRecordingActive = store.snapshot.keyboardRecordingActive
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenKeyboardSettingsDidChange, object: controller)

        #expect(store.snapshot.entryIdentities == baselineEntryIdentities)
        #expect(store.snapshot.keybindReloadPending == baselineReloadPending)
        #expect(store.snapshot.keyboardRecordingActive == baselineRecordingActive)
        #expect(emissionCount == 0)
    }

    @Test func storeClearsPendingReloadOnSameValueRecorderAssignment() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries
        defer {
            controller.keybindEntries = originalKeybindEntries
            reset(controller)
        }

        reset(controller)
        controller.show(pane: .shortcuts)
        waitForSettingsBootstrapToFinish(controller)
        controller.resetKeybindReloadStateForTesting()
        controller.selectedSettingsPane = .general
        controller.keybindEntries = KeybindRegistry.defaults

        let store = KeyboardSettingsStore(controller: controller)
        #expect(!store.snapshot.keybindReloadPending)
        #expect(!store.snapshot.keyboardRecordingActive)

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(store.snapshot.keybindReloadPending)

        controller.selectedSettingsPane = .shortcuts
        controller.keyboardRecordingActive = false

        #expect(!store.snapshot.keybindReloadPending)
        #expect(!store.snapshot.keyboardRecordingActive)
    }

    @Test func storeRefreshesWhenConflictMetadataChangesForSameEntry() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries

        defer {
            controller.keybindEntries = originalKeybindEntries
            reset(controller)
        }

        reset(controller)

        var initialEntry = KeybindEntry(
            action: "split:left",
            displayName: "Split Left",
            category: .splits,
            trigger: KeyTrigger(
                modifiers: KeyModifiers(cmd: true),
                key: "d",
                keyCode: 2,
                displayKey: "D"
            )
        )
        initialEntry.conflicts = [
            KeybindConflict(
                source: .macOS(name: "Mission Control"),
                description: "Original conflict"
            )
        ]

        controller.keybindEntries = [initialEntry]
        let store = KeyboardSettingsStore(controller: controller)

        var refreshedEntry = initialEntry
        refreshedEntry.currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true),
            key: "d",
            keyCode: 14,
            displayKey: "D"
        )
        refreshedEntry.conflicts = [
            KeybindConflict(
                source: .app(bundleId: "com.apple.Terminal", name: "Terminal", icon: nil),
                description: "Terminal conflict"
            )
        ]

        controller.keybindEntries = [refreshedEntry]

        #expect(store.snapshot.keybindEntries.count == 1)
        #expect(store.snapshot.keybindEntries[0].currentTrigger.keyCode == 14)
        #expect(store.snapshot.keybindEntries[0].conflicts.count == 1)
        #expect(store.snapshot.keybindEntries[0].conflicts[0].description == "Terminal conflict")
    }

    @Test func storeRefreshesWhenReservedFixedIdentityChangesForSameEntry() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries

        defer {
            controller.keybindEntries = originalKeybindEntries
            reset(controller)
        }

        reset(controller)

        var initialEntry = KeybindEntry(
            action: "yen_toggle_scratchpad",
            displayName: "Toggle Scratchpad",
            category: .custom,
            trigger: KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j"),
            isEditable: false,
            lockDescription: "Reserved shortcut."
        )

        controller.keybindEntries = [initialEntry]
        let store = KeyboardSettingsStore(controller: controller)
        #expect(store.snapshot.entryIdentities[0].isReservedFixed == false)

        initialEntry.isReservedFixed = true
        controller.keybindEntries = [initialEntry]

        #expect(store.snapshot.entryIdentities[0].isReservedFixed == true)
        #expect(store.snapshot.keybindEntries[0].isReservedFixed == true)
    }

    // The Shortcuts pane once rebuilt its rows from the snapshot a view closure
    // captured, so the list stayed one update behind. These tests drive the same
    // store-following path the pane uses.

    @Test func catalogRowsFollowEntriesLoadedAfterThePaneWasBuilt() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries
        defer {
            controller.keybindEntries = originalKeybindEntries
            reset(controller)
        }

        reset(controller)
        controller.keybindEntries = []
        let probe = SettingsShortcutsPane._TestCatalogProbe(controller: controller)
        #expect(probe.stableIDs.isEmpty)

        controller.keybindEntries = KeybindRegistry.defaults

        #expect(probe.stableIDs.count == KeybindRegistry.defaults.count)
        #expect(!probe.stableIDs.isEmpty)
    }

    @Test func catalogRowsShowRecordedAndResetShortcutsAtOnceAndWarnOnDuplicates() throws {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-keyboard-derived-rows-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "".write(to: configURL, atomically: true, encoding: .utf8)
        SettingsController._testSetConfigPathOverride(configURL.path)
        defer {
            controller.keybindEntries = originalKeybindEntries
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        reset(controller)
        controller.keybindEntries = KeybindRegistry.defaults
        let editable = controller.keybindEntries.filter { $0.isEditable }
        let copy = try #require(editable.first { $0.action == "copy_to_clipboard" })
        let paste = try #require(editable.first { $0.action == "paste_from_clipboard" })
        let probe = SettingsShortcutsPane._TestCatalogProbe(controller: controller)
        #expect(probe.currentTriggerDisplay(stableId: copy.stableId) == copy.defaultTrigger.displayString)

        let result = controller.updateKeybind(stableId: copy.stableId, trigger: paste.currentTrigger)

        #expect(result == .recorded)
        #expect(probe.currentTriggerDisplay(stableId: copy.stableId) == paste.currentTrigger.displayString)
        #expect(probe.duplicateStableIDs.contains(copy.stableId))
        #expect(probe.duplicateStableIDs.contains(paste.stableId))
        #expect(
            controller.statusMessage
                == "\(paste.currentTrigger.displayString) is also assigned to \(paste.displayName)."
        )
        #expect(controller.statusSeverity == .warning)

        controller.resetKeybind(stableId: copy.stableId)

        #expect(probe.currentTriggerDisplay(stableId: copy.stableId) == copy.defaultTrigger.displayString)
        #expect(!probe.duplicateStableIDs.contains(copy.stableId))
    }

    @Test func storeTracksEntriesAddedAfterInitialization() {
        let controller = SettingsController.shared
        let originalKeybindEntries = controller.keybindEntries
        defer {
            controller.keybindEntries = originalKeybindEntries
            reset(controller)
        }

        reset(controller)
        let first = KeybindEntry(
            action: "split:left",
            displayName: "Split Left",
            category: .splits,
            trigger: KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "d")
        )
        let second = KeybindEntry(
            action: "toggle_command_palette",
            displayName: "Command Palette",
            category: .window,
            trigger: KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "p")
        )

        controller.keybindEntries = [first]
        let store = KeyboardSettingsStore(controller: controller)
        #expect(store.snapshot.keybindEntries.map(\.stableId) == [first.stableId])

        controller.keybindEntries = [first, second]

        #expect(store.snapshot.keybindEntries.map(\.stableId) == [first.stableId, second.stableId])
    }

    @Test func recorderAccessibilityLabelsNameTheShortcut() {
        #expect(
            KeyRecorderButton.accessibilityLabel("Record shortcut", actionName: "Copy")
                == "Record shortcut for Copy"
        )
        #expect(KeyRecorderButton.accessibilityLabel("Record shortcut", actionName: "") == "Record shortcut")
    }

    private func reset(_ controller: SettingsController) {
        SettingsController._testSetWindowCloseMemoryModeOverride(nil)
        controller.hide()
        drainMainRunLoop()
        controller._testResetWindowState()
        controller.selectedSettingsPane = .general
        controller.keyboardRecordingActive = false
        controller.resetKeybindReloadStateForTesting()
    }

    private func waitForSettingsBootstrapToFinish(
        _ controller: SettingsController,
        timeout: TimeInterval = 0.3
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while controller._testHasShowRefreshTask, Date() < deadline {
            drainMainRunLoop()
        }
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}
