import Foundation
import SwiftUI

@MainActor
final class KeyboardSettingsStore: SettingsSnapshotStore<KeyboardSettingsStore.Snapshot> {
    struct Snapshot: Equatable {
        struct TriggerIdentity: Equatable {
            let modifiers: KeyModifiers
            let key: String
            let keyCode: UInt16?
            let displayKey: String?

            init(_ trigger: KeyTrigger) {
                modifiers = trigger.modifiers
                key = trigger.key
                keyCode = trigger.keyCode
                displayKey = trigger.displayKey
            }
        }

        struct ConflictIdentity: Equatable {
            enum SourceIdentity: Equatable {
                case macOS(name: String)
                case app(bundleId: String, name: String, hasIcon: Bool)
            }

            let source: SourceIdentity
            let description: String

            init(_ conflict: KeybindConflict) {
                switch conflict.source {
                case .macOS(let name):
                    source = .macOS(name: name)
                case .app(let bundleId, let name, let icon):
                    source = .app(bundleId: bundleId, name: name, hasIcon: icon != nil)
                }
                description = conflict.description
            }
        }

        struct EntryIdentity: Equatable {
            let stableId: String
            let action: String
            let displayName: String
            let category: KeybindCategory
            let defaultTrigger: TriggerIdentity
            let currentTrigger: TriggerIdentity
            let isUserOverride: Bool
            let isEditable: Bool
            let lockDescription: String?
            let isReservedFixed: Bool
            let conflicts: [ConflictIdentity]

            init(_ entry: KeybindEntry) {
                stableId = entry.stableId
                action = entry.action
                displayName = entry.displayName
                category = entry.category
                defaultTrigger = TriggerIdentity(entry.defaultTrigger)
                currentTrigger = TriggerIdentity(entry.currentTrigger)
                isUserOverride = entry.isUserOverride
                isEditable = entry.isEditable
                lockDescription = entry.lockDescription
                isReservedFixed = entry.isReservedFixed
                conflicts = entry.conflicts.map(ConflictIdentity.init)
            }
        }

        let keybindEntries: [KeybindEntry]
        let entryIdentities: [EntryIdentity]
        let keybindReloadPending: Bool
        let keyboardRecordingActive: Bool

        @MainActor
        static func capture(from controller: SettingsController) -> Snapshot {
            let keybindEntries = controller.keybindEntries
            return Snapshot(
                keybindEntries: keybindEntries,
                entryIdentities: keybindEntries.map(EntryIdentity.init),
                keybindReloadPending: controller.keybindReloadPendingForUI,
                keyboardRecordingActive: controller.keyboardRecordingActive
            )
        }

        /// Identity-only equality: the raw `keybindEntries` (carrying `NSImage`
        /// conflict icons, not `Equatable`) is deliberately excluded — change
        /// detection runs off `entryIdentities` + the scalar fields, matching the
        /// former hand-written `snapshotMatches`.
        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.entryIdentities == rhs.entryIdentities
                && lhs.keybindReloadPending == rhs.keybindReloadPending
                && lhs.keyboardRecordingActive == rhs.keyboardRecordingActive
        }
    }

    private let controller: SettingsController

    init(controller: SettingsController) {
        self.controller = controller
        super.init(
            notification: .yenKeyboardSettingsDidChange,
            object: controller,
            capture: { Snapshot.capture(from: controller) }
        )
    }

    func setKeyboardRecordingActive(_ value: Bool) {
        controller.keyboardRecordingActive = value
    }
}
