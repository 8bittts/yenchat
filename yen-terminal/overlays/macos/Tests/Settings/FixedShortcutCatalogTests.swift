import Foundation
import Testing
@testable import YEN

@MainActor
struct FixedShortcutCatalogTests {
    // Both overlays and the applied Ghostty tree have the same test depth.
    private static let repositoryRoot = ProcessInfo.processInfo.environment["YEN_NATIVE_TEST_SOURCE_ROOT"]
        .map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Settings
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent() // overlays or ghostty
        .deletingLastPathComponent() // yen-terminal
        .deletingLastPathComponent() // repository

    @Test func tabSidebarShortcutLabelsMatchMacTabBehavior() {
        #expect(TabSidebarController.shortcutLabel(for: 0, totalTabs: 1) == "1")
        #expect(TabSidebarController.shortcutLabel(for: 7, totalTabs: 12) == "8")
        #expect(TabSidebarController.shortcutLabel(for: 8, totalTabs: 9) == "9")
        #expect(TabSidebarController.shortcutLabel(for: 8, totalTabs: 12) == nil)
        #expect(TabSidebarController.shortcutLabel(for: 11, totalTabs: 12) == "9")
        #expect(TabSidebarController.shortcutLabel(for: 12, totalTabs: 12) == nil)
    }

    @Test func yenFixedShortcutsArePresentAndLocked() {
        let expected: [(String, KeyTrigger)] = [
            ("yen_show_settings", KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "comma")),
            ("yen_toggle_tab_sidebar", KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "b")),
            ("yen_toggle_scratchpad", KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j")),
            ("yen_open_file_browser", KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "o")),
            ("yen_take_screenshot", KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "s")),
            ("yen_dictation_push_to_talk", KeyTrigger(modifiers: KeyModifiers(option: true), key: "space")),
        ]

        for (action, trigger) in expected {
            let entry = KeybindRegistry.defaults.first { $0.action == action }
            #expect(entry != nil)
            #expect(entry?.defaultTrigger == trigger)
            #expect(entry?.isEditable == false)
            #expect(entry?.lockDescription?.isEmpty == false)
            #expect(entry?.isReservedFixed == true)
        }
    }

    @Test func layoutShortcutsRemainLockedAndVisible() {
        let layouts = KeybindRegistry.defaults.filter { $0.action.hasPrefix("layout:") }
        #expect(layouts.count == 10)
        #expect(layouts.allSatisfy { !$0.isEditable })
        #expect(layouts.allSatisfy { $0.lockDescription?.isEmpty == false })
        #expect(layouts.allSatisfy { $0.isReservedFixed })
        #expect(layouts.allSatisfy { $0.defaultTrigger.keyCode != nil })
    }

    @Test func layoutShortcutCatalogUsesSharedPhysicalDigitRowLookup() throws {
        for ordinal in 1...10 {
            let displayDigit = ordinal == 10 ? 0 : ordinal
            let entry = try #require(KeybindRegistry.defaults.first { $0.action == "layout:\(ordinal)" })
            #expect(entry.defaultTrigger.modifiers == KeyModifiers(cmd: true, option: true))
            #expect(entry.defaultTrigger.keyCode == PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: displayDigit))
        }
    }

    @Test(arguments: [
        (UInt16(18), "1"),
        (UInt16(19), "2"),
        (UInt16(20), "3"),
        (UInt16(21), "4"),
        (UInt16(23), "5"),
        (UInt16(22), "6"),
        (UInt16(26), "7"),
        (UInt16(28), "8"),
        (UInt16(25), "9"),
        (UInt16(29), "0"),
    ])
    func digitRowFallbackNamesComeFromSharedPhysicalMapping(_ keyCode: UInt16, _ expectedKey: String) {
        let descriptor = KeybindRegistry.keyDescriptor(
            forKeyCode: keyCode,
            translatedCharacters: nil,
            displayCharacters: nil
        )
        #expect(descriptor.key == expectedKey)
        #expect(PhysicalDigitRowKeyCodes.fallbackDigitName(forKeyCode: keyCode) == expectedKey)
    }

    @Test func reservedFixedShortcutsAreLockedAndRejectedByTheRecorder() {
        let reserved = [
            KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "comma"),
            KeyTrigger(modifiers: KeyModifiers(option: true), key: "space"),
            KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "b"),
            KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j"),
        ]
        for trigger in reserved {
            #expect(KeybindRegistry.reservedFixedTriggers.contains(trigger), "\(trigger.displayString)")
            #expect(KeybindRegistry.validationError(for: trigger) == .reservedFixedShortcut)
        }
        #expect(KeybindRegistry.reservedFixedShortcutValidationMessage.contains("Reserved by YEN"))
        #expect(KeybindRegistry.reservedFixedShortcutValidationMessage.contains("conflict checks"))

        #expect(
            KeybindRegistry.validationError(
                for: KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j")
            ) == .reservedFixedShortcut
        )
        #expect(
            KeybindRegistry.validationError(
                for: KeyTrigger(modifiers: KeyModifiers(shift: true), key: "j")
            ) == .missingRequiredModifier
        )
        #expect(
            KeybindRegistry.validationError(
                for: KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "y")
            ) == nil
        )
        #expect(
            KeybindRegistry.validationError(
                for: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, option: true),
                    key: "&",
                    keyCode: 18
                )
            ) == .reservedFixedShortcut
        )
    }

    @Test func screenFileShortcutsAvoidScratchpadCollision() {
        let scratchpadTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j")
        let collisions = KeybindRegistry.defaults.filter {
            $0.defaultTrigger == scratchpadTrigger && $0.action != "yen_toggle_scratchpad"
        }
        #expect(collisions.isEmpty)

        let expected: [(String, KeyTrigger)] = [
            (
                "write_screen_file:copy,plain",
                KeyTrigger(modifiers: KeyModifiers(cmd: true, ctrl: true, shift: true), key: "u")
            ),
            (
                "write_screen_file:paste,plain",
                KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "u")
            ),
            (
                "write_screen_file:open,plain",
                KeyTrigger(modifiers: KeyModifiers(cmd: true, option: true, shift: true), key: "u")
            ),
        ]

        for (action, trigger) in expected {
            let entry = KeybindRegistry.defaults.first { $0.action == action }
            #expect(entry != nil)
            #expect(entry?.defaultTrigger == trigger)
        }
    }

    @Test func fixedShortcutDocsStayAlignedWithShippedKeyboardCatalog() throws {
        let commandsDoc = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("_docs/12-commands.md"),
            encoding: .utf8
        )
        let qolDoc = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("_docs/13-desktop-features.md"),
            encoding: .utf8
        )

        for shortcut in [
            "Cmd + ,",
            "Option + Space",
            "Cmd + Shift + O",
            "Cmd + Shift + S",
            "Cmd + Shift + B",
            "Cmd + Shift + J",
            "Cmd + Option + 1-0",
        ] {
            #expect(commandsDoc.contains(shortcut))
            #expect(qolDoc.contains(shortcut))
        }
    }

    @Test func configZigSentinelsStayAlignedWithRegistryDefaults() throws {
        let configSource = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("yen-terminal/ghostty/src/config/Config.zig"),
            encoding: .utf8
        ).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let sharedCopyBindingSnippets = [
            "const mods: inputpkg.Mods = if (builtin.target.os.tag.isDarwin()) .{ .super = true } else .{ .ctrl = true, .shift = true };",
            ".{ .key = .{ .unicode = 'c' }, .mods = mods }, .{ .copy_to_clipboard = .mixed }",
        ].map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }

        let expectedSnippets = [
            ".{ .key = .{ .unicode = 'n' }, .mods = .{ .super = true } }, .{ .new_window = {} }",
            ".{ .key = .{ .unicode = 't' }, .mods = .{ .super = true } }, .{ .new_tab = {} }",
            ".{ .key = .{ .unicode = 'd' }, .mods = .{ .super = true } }, .{ .new_split = .right }",
            ".{ .key = .{ .physical = .arrow_left }, .mods = .{ .super = true, .alt = true } }, .{ .goto_split = .left }",
            ".{ .key = .{ .unicode = '=' }, .mods = inputpkg.ctrlOrSuper(.{}) }, .{ .increase_font_size = 1 }",
            ".{ .key = .{ .unicode = 'f' }, .mods = .{ .super = true } }, .start_search",
            ".{ .key = .{ .physical = .backquote }, .mods = .{ .ctrl = true } }, .{ .toggle_quick_terminal = {} }, .{ .global = true }",
        ].map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }

        for snippet in sharedCopyBindingSnippets {
            #expect(configSource.contains(snippet))
        }

        for snippet in expectedSnippets {
            #expect(configSource.contains(snippet))
        }
    }
}
