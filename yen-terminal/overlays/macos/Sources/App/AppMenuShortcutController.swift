import AppKit
import YENKit

/// `@MainActor` because upstream Ghostty 9886f481 made `Config.keyboardShortcut(for:)`
/// main-actor-isolated: physical menu shortcuts are now translated through the live
/// keyboard layout, which is main-thread state. This controller mutates `NSMenuItem`
/// anyway, so main-actor isolation is where it already belonged.
@MainActor
final class AppMenuShortcutController {
    struct MenuItems {
        let checkForUpdates: NSMenuItem?
        let openConfig: NSMenuItem?
        let reloadConfig: NSMenuItem?
        let quit: NSMenuItem?
        let newWindow: NSMenuItem?
        let newTab: NSMenuItem?
        let close: NSMenuItem?
        let closeTab: NSMenuItem?
        let closeWindow: NSMenuItem?
        let closeAllWindows: NSMenuItem?
        let splitRight: NSMenuItem?
        let splitLeft: NSMenuItem?
        let splitDown: NSMenuItem?
        let splitUp: NSMenuItem?
        let undo: NSMenuItem?
        let redo: NSMenuItem?
        let copy: NSMenuItem?
        let paste: NSMenuItem?
        let pasteSelection: NSMenuItem?
        let selectAll: NSMenuItem?
        let find: NSMenuItem?
        let selectionForFind: NSMenuItem?
        let scrollToSelection: NSMenuItem?
        let findNext: NSMenuItem?
        let findPrevious: NSMenuItem?
        let zoomSplit: NSMenuItem?
        let previousSplit: NSMenuItem?
        let nextSplit: NSMenuItem?
        let selectSplitAbove: NSMenuItem?
        let selectSplitBelow: NSMenuItem?
        let selectSplitLeft: NSMenuItem?
        let selectSplitRight: NSMenuItem?
        let moveSplitDividerUp: NSMenuItem?
        let moveSplitDividerDown: NSMenuItem?
        let moveSplitDividerLeft: NSMenuItem?
        let moveSplitDividerRight: NSMenuItem?
        let equalizeSplits: NSMenuItem?
        let returnToDefaultSize: NSMenuItem?
        let increaseFontSize: NSMenuItem?
        let decreaseFontSize: NSMenuItem?
        let resetFontSize: NSMenuItem?
        let changeTitle: NSMenuItem?
        let changeTabTitle: NSMenuItem?
        let gitDrawer: NSMenuItem?
        let quickTerminal: NSMenuItem?
        let toggleVisibility: NSMenuItem?
        let floatOnTop: NSMenuItem?
        let terminalInspector: NSMenuItem?
        let commandPalette: NSMenuItem?
        let secureInput: NSMenuItem?
        let settings: NSMenuItem?
    }

    private var menuItemsByShortcut: [MenuShortcutKey: Weak<NSMenuItem>] = [:]

    func sync(config: YEN.Config, menuItems: MenuItems) {
        menuItemsByShortcut.removeAll(keepingCapacity: true)

        syncMenuShortcut(config, action: "check_for_updates", menuItem: menuItems.checkForUpdates)
        syncMenuShortcut(config, action: "open_config", menuItem: menuItems.openConfig)
        syncMenuShortcut(config, action: "reload_config", menuItem: menuItems.reloadConfig)
        syncMenuShortcut(config, action: "quit", menuItem: menuItems.quit)

        syncMenuShortcut(config, action: "new_window", menuItem: menuItems.newWindow)
        syncMenuShortcut(config, action: "new_tab", menuItem: menuItems.newTab)
        syncMenuShortcut(config, action: "close_surface", menuItem: menuItems.close)
        syncMenuShortcut(config, action: "close_tab", menuItem: menuItems.closeTab)
        syncMenuShortcut(config, action: "close_window", menuItem: menuItems.closeWindow)
        syncMenuShortcut(config, action: "close_all_windows", menuItem: menuItems.closeAllWindows)
        syncMenuShortcut(config, action: "new_split:right", menuItem: menuItems.splitRight)
        syncMenuShortcut(config, action: "new_split:left", menuItem: menuItems.splitLeft)
        syncMenuShortcut(config, action: "new_split:down", menuItem: menuItems.splitDown)
        syncMenuShortcut(config, action: "new_split:up", menuItem: menuItems.splitUp)

        syncMenuShortcut(config, action: "undo", menuItem: menuItems.undo)
        syncMenuShortcut(config, action: "redo", menuItem: menuItems.redo)
        syncMenuShortcut(config, action: "copy_to_clipboard", menuItem: menuItems.copy)
        syncMenuShortcut(config, action: "paste_from_clipboard", menuItem: menuItems.paste)
        syncMenuShortcut(config, action: "paste_from_selection", menuItem: menuItems.pasteSelection)
        syncMenuShortcut(config, action: "select_all", menuItem: menuItems.selectAll)
        syncMenuShortcut(config, action: "start_search", menuItem: menuItems.find)
        syncMenuShortcut(config, action: "search_selection", menuItem: menuItems.selectionForFind)
        syncMenuShortcut(config, action: "scroll_to_selection", menuItem: menuItems.scrollToSelection)
        syncMenuShortcut(config, action: "navigate_search:next", menuItem: menuItems.findNext)
        syncMenuShortcut(config, action: "navigate_search:previous", menuItem: menuItems.findPrevious)

        syncMenuShortcut(config, action: "toggle_split_zoom", menuItem: menuItems.zoomSplit)
        syncMenuShortcut(config, action: "goto_split:previous", menuItem: menuItems.previousSplit)
        syncMenuShortcut(config, action: "goto_split:next", menuItem: menuItems.nextSplit)
        syncMenuShortcut(config, action: "goto_split:up", menuItem: menuItems.selectSplitAbove)
        syncMenuShortcut(config, action: "goto_split:down", menuItem: menuItems.selectSplitBelow)
        syncMenuShortcut(config, action: "goto_split:left", menuItem: menuItems.selectSplitLeft)
        syncMenuShortcut(config, action: "goto_split:right", menuItem: menuItems.selectSplitRight)
        syncMenuShortcut(config, action: "resize_split:up,10", menuItem: menuItems.moveSplitDividerUp)
        syncMenuShortcut(config, action: "resize_split:down,10", menuItem: menuItems.moveSplitDividerDown)
        syncMenuShortcut(config, action: "resize_split:right,10", menuItem: menuItems.moveSplitDividerRight)
        syncMenuShortcut(config, action: "resize_split:left,10", menuItem: menuItems.moveSplitDividerLeft)
        syncMenuShortcut(config, action: "equalize_splits", menuItem: menuItems.equalizeSplits)
        syncMenuShortcut(config, action: "reset_window_size", menuItem: menuItems.returnToDefaultSize)

        syncMenuShortcut(config, action: "increase_font_size:1", menuItem: menuItems.increaseFontSize)
        syncMenuShortcut(config, action: "decrease_font_size:1", menuItem: menuItems.decreaseFontSize)
        syncMenuShortcut(config, action: "reset_font_size", menuItem: menuItems.resetFontSize)
        syncMenuShortcut(config, action: "prompt_surface_title", menuItem: menuItems.changeTitle)
        syncMenuShortcut(config, action: "prompt_tab_title", menuItem: menuItems.changeTabTitle)
        syncFixedRegistryShortcut(action: "yen_toggle_git_drawer", menuItem: menuItems.gitDrawer)
        syncMenuShortcut(config, action: "toggle_quick_terminal", menuItem: menuItems.quickTerminal)
        syncMenuShortcut(config, action: "toggle_visibility", menuItem: menuItems.toggleVisibility)
        syncMenuShortcut(config, action: "toggle_window_float_on_top", menuItem: menuItems.floatOnTop)
        syncMenuShortcut(config, action: "inspector:toggle", menuItem: menuItems.terminalInspector)
        syncMenuShortcut(config, action: "toggle_command_palette", menuItem: menuItems.commandPalette)

        syncMenuShortcut(config, action: "toggle_secure_input", menuItem: menuItems.secureInput)

        indexReservedSettingsShortcut(menuItems.settings)
        clearConflictingBuiltInShortcuts(in: NSApp.mainMenu)
    }

    func matchedYENMenuItem(for event: NSEvent) -> NSMenuItem? {
        guard let key = MenuShortcutKey(event: event) else {
            return nil
        }

        guard let weakItem = menuItemsByShortcut[key] else {
            return nil
        }

        guard let item = weakItem.value else {
            menuItemsByShortcut.removeValue(forKey: key)
            return nil
        }

        guard let parentMenu = item.menu else {
            return nil
        }

        parentMenu.update()
        guard item.isEnabled else {
            return nil
        }

        guard parentMenu.index(of: item) >= 0 else {
            return nil
        }

        return item
    }

    /// `nonisolated` because this is a pure predicate over its arguments. It touches
    /// no main-actor state, so it should not inherit the type's isolation and force
    /// every caller — including the test suites — onto the main actor.
    nonisolated static func isReservedSettingsShortcut(
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        keyEquivalent.lowercased() == "," &&
            modifiers.intersection([.shift, .control, .option, .command]) == [.command]
    }

    private func syncMenuShortcut(_ config: YEN.Config, action: String, menuItem: NSMenuItem?) {
        guard let menu = menuItem else { return }

        guard let shortcut = config.keyboardShortcut(for: action) else {
            menu.keyEquivalent = ""
            menu.keyEquivalentModifierMask = []
            return
        }

        let keyEquivalent = shortcut.key.character.description
        let modifierMask = NSEvent.ModifierFlags(swiftUIFlags: shortcut.modifiers)
        guard !Self.isReservedSettingsShortcut(
            keyEquivalent: keyEquivalent,
            modifiers: modifierMask
        ) else {
            menu.keyEquivalent = ""
            menu.keyEquivalentModifierMask = []
            return
        }

        menu.keyEquivalent = keyEquivalent
        menu.keyEquivalentModifierMask = modifierMask
        index(menu, keyEquivalent: keyEquivalent, modifiers: modifierMask)
    }

    private func syncFixedRegistryShortcut(action: String, menuItem: NSMenuItem?) {
        guard let menu = menuItem else { return }
        guard let entry = KeybindRegistry.defaults.first(where: { $0.action == action }) else {
            menu.keyEquivalent = ""
            menu.keyEquivalentModifierMask = []
            return
        }

        let shortcut = entry.defaultTrigger
        let keyEquivalent = Self.keyEquivalent(for: shortcut.key)
        let modifierMask = NSEvent.ModifierFlags(keyModifiers: shortcut.modifiers)
        menu.keyEquivalent = keyEquivalent
        menu.keyEquivalentModifierMask = modifierMask
        index(menu, keyEquivalent: keyEquivalent, modifiers: modifierMask)
    }

    private func indexReservedSettingsShortcut(_ menu: NSMenuItem?) {
        guard let menu else { return }
        index(menu, keyEquivalent: menu.keyEquivalent, modifiers: menu.keyEquivalentModifierMask)
    }

    private func index(_ menu: NSMenuItem, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        guard let key = MenuShortcutKey(
            keyEquivalent: keyEquivalent,
            modifiers: modifiers
        ) else {
            return
        }

        menuItemsByShortcut[key] = .init(menu)

        // A shifted top-row symbol like "+" is produced with Shift on US/ANSI
        // layouts but is a dedicated key on others (e.g. German). The engine records
        // such bindings without Shift (see increase_font_size in Config.zig), so the
        // incoming event for "Cmd +" carries Shift while the indexed key does not.
        // Index the Shift-toggled variant too so both Cmd+= and Cmd+Shift+= resolve
        // to the same menu item.
        if MenuShortcutKey.isShiftOptionalSymbol(key.keyEquivalent),
           let altKey = MenuShortcutKey(
               keyEquivalent: key.keyEquivalent,
               modifiers: key.modifierFlags.symmetricDifference(.shift)
           ),
           menuItemsByShortcut[altKey] == nil {
            menuItemsByShortcut[altKey] = .init(menu)
        }
    }

    private func clearConflictingBuiltInShortcuts(in menu: NSMenu?) {
        guard let menu else { return }

        for item in menu.items {
            clearShortcutIfConflicting(item)
            clearConflictingBuiltInShortcuts(in: item.submenu)
        }
    }

    private func clearShortcutIfConflicting(_ item: NSMenuItem) {
        guard let key = MenuShortcutKey(item) else { return }
        guard let ownedItem = menuItemsByShortcut[key]?.value else { return }
        guard ownedItem !== item else { return }

        item.keyEquivalent = ""
        item.keyEquivalentModifierMask = []
    }
}

private extension NSEvent.ModifierFlags {
    init(keyModifiers: KeyModifiers) {
        self = []
        if keyModifiers.cmd { insert(.command) }
        if keyModifiers.ctrl { insert(.control) }
        if keyModifiers.option { insert(.option) }
        if keyModifiers.shift { insert(.shift) }
    }
}

private extension AppMenuShortcutController {
    static func keyEquivalent(for key: String) -> String {
        switch key.lowercased() {
        case "backquote": return "`"
        case "comma": return ","
        case "minus": return "-"
        case "equal": return "="
        default: return key.lowercased()
        }
    }
}

extension AppMenuShortcutController {
    struct MenuShortcutKey: Hashable {
        private static let shortcutModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

        /// Symbols that are produced with Shift on US/ANSI keyboards but may be a
        /// dedicated (Shift-free) key on other layouts. For these the Shift modifier
        /// is ambiguous, so a binding to one of them should match the keypress with or
        /// without Shift. These have no upper/lower case distinction, so the existing
        /// uppercase-letter Shift handling does not cover them.
        private static let shiftOptionalSymbols: Set<String> = [
            "+", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
            "_", "{", "}", "|", ":", "\"", "<", ">", "?", "~"
        ]

        static func isShiftOptionalSymbol(_ keyEquivalent: String) -> Bool {
            shiftOptionalSymbols.contains(keyEquivalent)
        }

        let keyEquivalent: String
        let modifiersRawValue: UInt

        var modifierFlags: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifiersRawValue)
        }

        init?(keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
            let normalized = keyEquivalent.lowercased()
            guard !normalized.isEmpty else { return nil }
            var mods = modifiers.intersection(Self.shortcutModifiers)
            if
                keyEquivalent.lowercased() != keyEquivalent.uppercased(),
                normalized.uppercased() == keyEquivalent {
                mods.insert(.shift)
            }

            self.keyEquivalent = normalized
            self.modifiersRawValue = mods.rawValue
        }

        init?(event: NSEvent) {
            guard let keyEquivalent = event.charactersIgnoringModifiers else { return nil }
            self.init(keyEquivalent: keyEquivalent, modifiers: event.modifierFlags)
        }

        init?(_ menuItem: NSMenuItem) {
            self.init(
                keyEquivalent: menuItem.keyEquivalent,
                modifiers: menuItem.keyEquivalentModifierMask
            )
        }
    }
}
