#if os(macOS)
import SwiftUI
import Combine

// MARK: - Groups

/// The five shortcut groups the pane shows. Each engine category maps to one.
enum SettingsShortcutGroup: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case windows = "Windows"
    case tabs = "Tabs"
    case splits = "Splits"
    case yen = "YEN"

    var id: String { rawValue }

    init(category: KeybindCategory) {
        switch category {
        case .terminal, .navigation, .font, .search: self = .terminal
        case .window: self = .windows
        case .tabs: self = .tabs
        case .splits: self = .splits
        case .custom: self = .yen
        }
    }
}

// MARK: - Catalog

/// The shortcut list as the pane draws it: rows per group, plus the rows that
/// share a trigger with another row.
struct SettingsShortcutsCatalog {
    private struct TriggerTextIdentity: Hashable {
        let modifiers: KeyModifiers
        let key: String
    }

    private struct TriggerKeyCodeIdentity: Hashable {
        let modifiers: KeyModifiers
        let keyCode: UInt16
    }

    let entries: [KeybindEntry]
    let entriesByGroup: [SettingsShortcutGroup: [KeybindEntry]]
    let duplicateStableIDs: Set<String>
    let conflictCount: Int
    let lockedCount: Int

    static let empty = SettingsShortcutsCatalog.build(from: [])

    static func build(from entries: [KeybindEntry]) -> SettingsShortcutsCatalog {
        var entriesByGroup: [SettingsShortcutGroup: [KeybindEntry]] = [:]
        var conflictCount = 0
        var lockedCount = 0
        var entriesByTriggerText: [TriggerTextIdentity: [String]] = [:]
        var entriesByTriggerKeyCode: [TriggerKeyCodeIdentity: [String]] = [:]

        for entry in entries {
            entriesByGroup[SettingsShortcutGroup(category: entry.category), default: []].append(entry)
            if !entry.conflicts.isEmpty { conflictCount += 1 }
            if !entry.isEditable { lockedCount += 1 }

            let trigger = entry.currentTrigger
            let textIdentity = TriggerTextIdentity(modifiers: trigger.modifiers, key: trigger.key.lowercased())
            entriesByTriggerText[textIdentity, default: []].append(entry.stableId)
            if let keyCode = trigger.keyCode {
                let keyCodeIdentity = TriggerKeyCodeIdentity(modifiers: trigger.modifiers, keyCode: keyCode)
                entriesByTriggerKeyCode[keyCodeIdentity, default: []].append(entry.stableId)
            }
        }

        var duplicateStableIDs: Set<String> = []
        for stableIDs in entriesByTriggerText.values where stableIDs.count > 1 {
            duplicateStableIDs.formUnion(stableIDs)
        }
        for stableIDs in entriesByTriggerKeyCode.values where stableIDs.count > 1 {
            duplicateStableIDs.formUnion(stableIDs)
        }

        return SettingsShortcutsCatalog(
            entries: entries,
            entriesByGroup: entriesByGroup,
            duplicateStableIDs: duplicateStableIDs,
            conflictCount: conflictCount,
            lockedCount: lockedCount
        )
    }

    /// One line that counts conflicts and duplicates, or nil when there are none.
    var attentionSummary: String? {
        var parts: [String] = []
        if conflictCount > 0 {
            parts.append("\(conflictCount) \(conflictCount == 1 ? "shortcut conflicts" : "shortcuts conflict") with macOS or another app")
        }
        if !duplicateStableIDs.isEmpty {
            parts.append("\(duplicateStableIDs.count) shortcuts share keys")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
    }
}

/// Follows `KeyboardSettingsStore` through its publisher and never through a
/// view closure.
///
/// A single-parameter `onChange` closure captures values from BEFORE the
/// change, so a catalog rebuilt there stayed one update behind: empty on the
/// first visit, and unchanged after a record or a reset.
@MainActor
final class SettingsShortcutsCatalogModel: ObservableObject {
    @Published private(set) var catalog: SettingsShortcutsCatalog
    private var entryIdentities: [KeyboardSettingsStore.Snapshot.EntryIdentity]
    private var storeSubscription: AnyCancellable?

    init(entries: [KeybindEntry]) {
        catalog = SettingsShortcutsCatalog.build(from: entries)
        entryIdentities = entries.map(KeyboardSettingsStore.Snapshot.EntryIdentity.init)
    }

    /// Idempotent. Applies the store's current snapshot at once, so entries
    /// that loaded between `init` and the first appearance are not missed.
    func follow(_ store: KeyboardSettingsStore) {
        guard storeSubscription == nil else { return }
        apply(store.snapshot)
        storeSubscription = store.$snapshot.sink { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: KeyboardSettingsStore.Snapshot) {
        guard snapshot.entryIdentities != entryIdentities else { return }
        entryIdentities = snapshot.entryIdentities
        catalog = SettingsShortcutsCatalog.build(from: snapshot.keybindEntries)
    }
}

// MARK: - Pane

/// The Shortcuts pane: a group switcher and the shortcuts in that group.
/// Click a shortcut to record a new one.
struct SettingsShortcutsPane: View {
    private let controller: SettingsController
    @StateObject private var store: KeyboardSettingsStore
    @StateObject private var model: SettingsShortcutsCatalogModel
    @State private var group: SettingsShortcutGroup = .terminal
    @State private var recordingStableId: String?

    static let footer =
        "Click a shortcut, then press the new keys. A shortcut needs ⌘, ⌃, or ⌥. Locked shortcuts belong to YEN."

    init(controller: SettingsController) {
        self.controller = controller
        _store = StateObject(wrappedValue: KeyboardSettingsStore(controller: controller))
        _model = StateObject(wrappedValue: SettingsShortcutsCatalogModel(entries: controller.keybindEntries))
    }

#if DEBUG
    /// Drives the same store-following path the pane uses, so a test can change
    /// the controller and read the rows the pane would draw.
    @MainActor
    final class _TestCatalogProbe {
        private let store: KeyboardSettingsStore
        private let model: SettingsShortcutsCatalogModel

        init(controller: SettingsController) {
            store = KeyboardSettingsStore(controller: controller)
            model = SettingsShortcutsCatalogModel(entries: controller.keybindEntries)
            model.follow(store)
        }

        var stableIDs: [String] { model.catalog.entries.map(\.stableId) }

        func currentTriggerDisplay(stableId: String) -> String? {
            model.catalog.entries.first(where: { $0.stableId == stableId })?.currentTrigger.displayString
        }

        var duplicateStableIDs: Set<String> { model.catalog.duplicateStableIDs }
    }
#endif

    private func stopRecording() {
        recordingStableId = nil
        store.setKeyboardRecordingActive(false)
    }

    var body: some View {
        let catalog = model.catalog
        let rows = catalog.entriesByGroup[group] ?? []

        VStack(spacing: 0) {
            SettingsSegmentedControl(
                accessibilityLabel: "Shortcut Group",
                segments: SettingsShortcutGroup.allCases.map { SettingsSegment(value: $0, title: $0.rawValue) },
                selection: $group
            )
            .padding(.horizontal, SettingsSpacing.contentInset)
            .padding(.top, SettingsSpacing.headerBottom)

            SettingsStudioForm {
                if store.snapshot.keybindReloadPending {
                    Section {
                        LabeledContent {
                            Button(
                                store.snapshot.keyboardRecordingActive ? "Stop and Refresh" : "Refresh",
                                action: stopRecording
                            )
                        } label: {
                            SettingsStudioLabel(
                                title: "Shortcuts Changed",
                                hint: "The config file changed. Refresh to show its shortcuts."
                            )
                        }
                    }
                }

                if let summary = catalog.attentionSummary {
                    Section {
                        Label {
                            Text(summary)
                                .font(SettingsTypography.note)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(NSColor.systemOrange))
                        }
                    }
                }

                Section {
                    if rows.isEmpty {
                        Text(catalog.entries.isEmpty ? "Loading shortcuts…" : "No shortcuts in this group.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows, id: \.stableId) { entry in
                            SettingsShortcutRow(
                                entry: entry,
                                controller: controller,
                                isDuplicate: catalog.duplicateStableIDs.contains(entry.stableId),
                                recordingStableId: $recordingStableId
                            )
                        }
                    }
                } footer: {
                    Text(Self.footer)
                }

                Section {
                    LabeledContent("Restore Default Shortcuts") {
                        Button("Restore…") {
                            stopRecording()
                            controller.confirmRestoreDefaultShortcuts()
                        }
                    }
                }
            }
        }
        .onAppear {
            model.follow(store)
            store.setKeyboardRecordingActive(recordingStableId != nil)
        }
        .onChange(of: recordingStableId) { newValue in
            store.setKeyboardRecordingActive(newValue != nil)
        }
        .onChange(of: group) { _ in
            // A recorder in a group that is no longer on screen must not keep
            // capturing keys.
            recordingStableId = nil
        }
        .onDisappear {
            let stoppedByPaneSwitch = recordingStableId != nil && controller.selectedSettingsPane != .shortcuts
            stopRecording()
            if stoppedByPaneSwitch {
                controller.showKeyboardRecorderStoppedForPaneSwitchStatus()
            }
        }
    }
}

// MARK: - Row

private struct SettingsShortcutRow: View {
    let entry: KeybindEntry
    let controller: SettingsController
    let isDuplicate: Bool
    @Binding var recordingStableId: String?

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recordingStableId == entry.stableId },
            set: { newValue in
                if newValue {
                    recordingStableId = entry.stableId
                } else if recordingStableId == entry.stableId {
                    recordingStableId = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.hintSpacing) {
            HStack(spacing: SettingsSpacing.controlSpacing) {
                Text(entry.displayName)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: SettingsSpacing.controlSpacing)

                if entry.isEditable {
                    if entry.isUserOverride {
                        Button {
                            controller.resetKeybind(stableId: entry.stableId)
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Restore \(entry.defaultTrigger.glyphString)")
                        .accessibilityLabel(
                            "Restore \(entry.displayName) to \(entry.defaultTrigger.displayString)"
                        )
                    }
                    KeyRecorderButton(
                        isRecording: isRecording,
                        actionName: entry.displayName,
                        shortcutTitle: entry.currentTrigger.glyphString,
                        onRecord: { trigger in
                            controller.updateKeybind(stableId: entry.stableId, trigger: trigger)
                        },
                        onReject: { rejection in
                            controller.showKeyboardRecorderRejectedStatus(rejection)
                        }
                    )
                } else {
                    // Same button metrics as an editable shortcut, disabled.
                    Image(systemName: "lock.fill")
                        .font(SettingsTypography.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Button(entry.currentTrigger.glyphString) {}
                        .controlSize(.small)
                        .disabled(true)
                        .help(entry.lockDescription ?? "Locked")
                        .accessibilityLabel("\(entry.displayName), locked")
                        .accessibilityValue(entry.currentTrigger.displayString)
                }
            }

            if isDuplicate {
                SettingsShortcutNote(text: "Another shortcut uses these keys.")
            }

            ForEach(entry.conflicts) { conflict in
                HStack(alignment: .firstTextBaseline, spacing: SettingsSpacing.iconTextSpacing) {
                    SettingsShortcutNote(text: conflict.description)
                    if case .macOS = conflict.source {
                        Button("Open Keyboard Settings…") {
                            SystemSettingsOpener.openKeyboardShortcutsSettings()
                        }
                        .buttonStyle(.link)
                        .font(SettingsTypography.caption)
                    }
                }
            }
        }
    }
}

/// A caution under a shortcut row. The symbol carries the color; the text
/// stays a label color so it reads in both appearances.
private struct SettingsShortcutNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsSpacing.iconTextSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(NSColor.systemOrange))
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(SettingsTypography.caption)
        .accessibilityElement(children: .combine)
    }
}

#endif // os(macOS)
