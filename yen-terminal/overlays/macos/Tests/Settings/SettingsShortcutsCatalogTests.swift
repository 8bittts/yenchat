import Foundation
import Testing
@testable import YEN

@MainActor
struct SettingsShortcutsCatalogTests {
    private func entry(
        _ action: String,
        _ name: String,
        _ category: KeybindCategory,
        _ modifiers: KeyModifiers,
        _ key: String,
        editable: Bool = true
    ) -> KeybindEntry {
        KeybindEntry(
            action: action,
            displayName: name,
            category: category,
            trigger: KeyTrigger(modifiers: modifiers, key: key),
            isEditable: editable,
            lockDescription: editable ? nil : "Locked"
        )
    }

    @Test func everyEngineCategoryMapsToOneOfTheFiveGroups() {
        #expect(SettingsShortcutGroup.allCases.map(\.rawValue) == ["Terminal", "Windows", "Tabs", "Splits", "YEN"])
        let expected: [KeybindCategory: SettingsShortcutGroup] = [
            .terminal: .terminal,
            .navigation: .terminal,
            .font: .terminal,
            .search: .terminal,
            .window: .windows,
            .tabs: .tabs,
            .splits: .splits,
            .custom: .yen,
        ]
        #expect(expected.count == KeybindCategory.allCases.count)
        for category in KeybindCategory.allCases {
            #expect(SettingsShortcutGroup(category: category) == expected[category])
        }
    }

    @Test func catalogPlacesEveryDefaultShortcutInExactlyOneGroup() {
        let catalog = SettingsShortcutsCatalog.build(from: KeybindRegistry.defaults)
        let grouped = SettingsShortcutGroup.allCases.flatMap { catalog.entriesByGroup[$0] ?? [] }

        #expect(!KeybindRegistry.defaults.isEmpty)
        #expect(grouped.count == KeybindRegistry.defaults.count)
        #expect(Set(grouped.map(\.stableId)) == Set(KeybindRegistry.defaults.map(\.stableId)))
        for group in SettingsShortcutGroup.allCases {
            #expect(!(catalog.entriesByGroup[group] ?? []).isEmpty)
        }
    }

    @Test func catalogKeepsRegistryOrderInsideAGroup() {
        let copy = entry("copy_to_clipboard", "Copy", .terminal, KeyModifiers(cmd: true), "c")
        let zoom = entry("increase_font_size:1", "Increase Font Size", .font, KeyModifiers(cmd: true), "equal")
        let find = entry("start_search", "Find", .search, KeyModifiers(cmd: true), "f")
        let tab = entry("new_tab", "New Tab", .tabs, KeyModifiers(cmd: true), "t")

        let catalog = SettingsShortcutsCatalog.build(from: [copy, tab, zoom, find])

        #expect(catalog.entriesByGroup[.terminal]?.map(\.stableId) == [copy.stableId, zoom.stableId, find.stableId])
        #expect(catalog.entriesByGroup[.tabs]?.map(\.stableId) == [tab.stableId])
        #expect(catalog.entriesByGroup[.splits] == nil)
    }

    @Test func catalogCountsConflictsLockedRowsAndDuplicates() {
        var first = entry("split:left", "Split Left", .splits, KeyModifiers(cmd: true), "d")
        first.conflicts = [
            KeybindConflict(source: .macOS(name: "Mission Control"), description: "Conflict"),
        ]
        let second = entry("split:right", "Split Right", .splits, KeyModifiers(cmd: true), "d")
        let locked = entry(
            "yen_dictation_push_to_talk", "Dictation Push-to-Talk", .custom,
            KeyModifiers(option: true), "space", editable: false
        )
        let plain = entry("new_window", "New Window", .window, KeyModifiers(cmd: true), "n")

        let catalog = SettingsShortcutsCatalog.build(from: [first, second, locked, plain])

        #expect(catalog.conflictCount == 1)
        #expect(catalog.lockedCount == 1)
        #expect(catalog.duplicateStableIDs == [first.stableId, second.stableId])
        #expect(catalog.attentionSummary == "1 shortcut conflicts with macOS or another app. 2 shortcuts share keys.")
    }

    @Test func catalogFindsADuplicateByKeyCodeWhenTheKeyTextDiffers() {
        var first = entry("action:one", "One", .terminal, KeyModifiers(cmd: true), "y")
        first.currentTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "y", keyCode: 16)
        var second = entry("action:two", "Two", .terminal, KeyModifiers(cmd: true), "z")
        second.currentTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "z", keyCode: 16)

        let catalog = SettingsShortcutsCatalog.build(from: [first, second])

        #expect(catalog.duplicateStableIDs == [first.stableId, second.stableId])
    }

    @Test func cleanCatalogHasNothingToReport() {
        let catalog = SettingsShortcutsCatalog.build(from: [
            entry("new_window", "New Window", .window, KeyModifiers(cmd: true), "n"),
            entry("new_tab", "New Tab", .tabs, KeyModifiers(cmd: true), "t"),
        ])

        #expect(catalog.attentionSummary == nil)
        #expect(catalog.duplicateStableIDs.isEmpty)
        #expect(SettingsShortcutsCatalog.empty.entries.isEmpty)
        #expect(SettingsShortcutsCatalog.empty.attentionSummary == nil)
    }

    @Test func shortcutGlyphsFollowTheMenuModifierOrder() {
        func glyph(_ modifiers: KeyModifiers, _ key: String) -> String {
            KeyTrigger(modifiers: modifiers, key: key).glyphString
        }

        #expect(glyph(KeyModifiers(cmd: true), "d") == "⌘D")
        #expect(glyph(KeyModifiers(cmd: true, shift: true), "j") == "⇧⌘J")
        #expect(glyph(KeyModifiers(cmd: true, ctrl: true, option: true, shift: true), "k") == "⌃⌥⇧⌘K")
        #expect(glyph(KeyModifiers(option: true), "space") == "⌥Space")
        #expect(glyph(KeyModifiers(cmd: true), "enter") == "⌘↩")
        #expect(glyph(KeyModifiers(cmd: true), "left") == "⌘←")
        #expect(glyph(KeyModifiers(cmd: true, shift: true), "left_bracket") == "⇧⌘[")
        #expect(glyph(KeyModifiers(ctrl: true), "backquote") == "⌃`")
        #expect(glyph(KeyModifiers(cmd: true), "comma") == "⌘,")
    }

    @Test func shortcutGlyphPrefersTheLayoutAwareKeyLabel() {
        let trigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "y", keyCode: 16, displayKey: "Z")
        #expect(trigger.glyphString == "⌘Z")
        // The spoken form is unchanged.
        #expect(trigger.displayString == "Cmd + Z")
    }
}
