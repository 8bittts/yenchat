import AppKit
import Testing
@testable import YEN

@MainActor
struct AppMenuShortcutControllerTests {
    @Test func syncClearsBuiltInShortcutWhenYENActionClaimsSameKey() throws {
        let originalMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = originalMainMenu }

        let appMenu = NSMenu(title: "YEN")
        let hideItem = NSMenuItem(title: "Hide YEN", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = .command
        appMenu.addItem(hideItem)

        let appMenuRootItem = NSMenuItem(title: "YEN", action: nil, keyEquivalent: "")
        appMenuRootItem.submenu = appMenu
        let mainMenu = NSMenu(title: "Main")
        mainMenu.addItem(appMenuRootItem)
        NSApp.mainMenu = mainMenu

        let selectSplitLeft = NSMenuItem(title: "Select Split Left", action: nil, keyEquivalent: "")
        let config = try TemporaryConfig("keybind=super+h=goto_split:left")
        let controller = AppMenuShortcutController()

        controller.sync(
            config: config,
            menuItems: .testItems(selectSplitLeft: selectSplitLeft)
        )

        #expect(hideItem.keyEquivalent.isEmpty)
        #expect(hideItem.keyEquivalentModifierMask.isEmpty)
        #expect(selectSplitLeft.keyEquivalent == "h")
        #expect(selectSplitLeft.keyEquivalentModifierMask == .command)
    }

    @Test func shortcutKeyNormalizationMatchesLegacyUppercaseShiftBehavior() {
        typealias Key = AppMenuShortcutController.MenuShortcutKey

        let fromUpper = Key(keyEquivalent: "C", modifiers: .command)
        let fromLowerWithShift = Key(keyEquivalent: "c", modifiers: [.command, .shift])

        #expect(fromUpper == fromLowerWithShift)
        #expect(fromUpper?.keyEquivalent == "c")
        #expect(fromUpper?.modifierFlags == [.command, .shift])
    }

    /// Regression: "Cmd +" (Cmd+Shift+= on US layouts) must trigger Increase Font Size.
    /// The engine records the binding as "+" with Super only (no Shift), but typing "+"
    /// requires Shift, so the live keypress event carries Shift. The matcher must resolve
    /// the same menu item with or without Shift for these shifted top-row symbols.
    @Test func shiftOptionalSymbolMatchesWithAndWithoutShift() {
        typealias Key = AppMenuShortcutController.MenuShortcutKey

        #expect(Key.isShiftOptionalSymbol("+"))
        #expect(!Key.isShiftOptionalSymbol("="))
        #expect(!Key.isShiftOptionalSymbol("-"))

        // "+" with Super-only and "+" with Super+Shift are distinct keys (so both must
        // be indexed); decrease/reset keys ("-", "0") are not Shift-ambiguous.
        let plusNoShift = Key(keyEquivalent: "+", modifiers: .command)
        let plusWithShift = Key(keyEquivalent: "+", modifiers: [.command, .shift])
        #expect(plusNoShift != plusWithShift)
    }

    @Test func increaseFontSyncIndexesBothShiftVariants() throws {
        let increaseFont = NSMenuItem(title: "Increase Font Size", action: #selector(NSResponder.keyDown(with:)), keyEquivalent: "")
        // matchedYENMenuItem requires the item to live in an enabled parent menu.
        let viewMenu = NSMenu(title: "View")
        viewMenu.autoenablesItems = false
        increaseFont.isEnabled = true
        viewMenu.addItem(increaseFont)

        let config = try TemporaryConfig("keybind=super+plus=increase_font_size:1")
        let controller = AppMenuShortcutController()

        controller.sync(
            config: config,
            menuItems: .testItems(increaseFontSize: increaseFont)
        )

        // Both "Cmd +" (engine binding, no Shift) and the real US keypress (with Shift)
        // resolve to the same menu item.
        let withoutShift = makeKeyEvent(charactersIgnoringModifiers: "+", flags: [.command])
        let withShift = makeKeyEvent(charactersIgnoringModifiers: "+", flags: [.command, .shift])
        #expect(controller.matchedYENMenuItem(for: withoutShift) === increaseFont)
        #expect(controller.matchedYENMenuItem(for: withShift) === increaseFont)
    }

    @Test func findPreviousUsesCmdShiftKToKeepCmdShiftGAvailable() throws {
        let findPrevious = NSMenuItem(title: "Find Previous", action: #selector(NSResponder.keyDown(with:)), keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.autoenablesItems = false
        findPrevious.isEnabled = true
        editMenu.addItem(findPrevious)

        let config = try TemporaryConfig("keybind=super+shift+k=navigate_search:previous")
        let controller = AppMenuShortcutController()

        controller.sync(
            config: config,
            menuItems: .testItems(findPrevious: findPrevious)
        )

        #expect(findPrevious.keyEquivalent == "k")
        #expect(findPrevious.keyEquivalentModifierMask == [.command, .shift])
        #expect(controller.matchedYENMenuItem(for: makeKeyEvent(charactersIgnoringModifiers: "k", flags: [.command, .shift])) === findPrevious)
        #expect(controller.matchedYENMenuItem(for: makeKeyEvent(charactersIgnoringModifiers: "g", flags: [.command, .shift])) == nil)
    }

    private func makeKeyEvent(
        charactersIgnoringModifiers: String,
        flags: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: 24
        )!
    }
}

private extension AppMenuShortcutController.MenuItems {
    static func testItems(
        selectSplitLeft: NSMenuItem? = nil,
        increaseFontSize: NSMenuItem? = nil,
        findPrevious: NSMenuItem? = nil,
        settings: NSMenuItem? = nil
    ) -> Self {
        Self(
            checkForUpdates: nil,
            openConfig: nil,
            reloadConfig: nil,
            quit: nil,
            newWindow: nil,
            newTab: nil,
            close: nil,
            closeTab: nil,
            closeWindow: nil,
            closeAllWindows: nil,
            splitRight: nil,
            splitLeft: nil,
            splitDown: nil,
            splitUp: nil,
            undo: nil,
            redo: nil,
            copy: nil,
            paste: nil,
            pasteSelection: nil,
            selectAll: nil,
            find: nil,
            selectionForFind: nil,
            scrollToSelection: nil,
            findNext: nil,
            findPrevious: findPrevious,
            zoomSplit: nil,
            previousSplit: nil,
            nextSplit: nil,
            selectSplitAbove: nil,
            selectSplitBelow: nil,
            selectSplitLeft: selectSplitLeft,
            selectSplitRight: nil,
            moveSplitDividerUp: nil,
            moveSplitDividerDown: nil,
            moveSplitDividerLeft: nil,
            moveSplitDividerRight: nil,
            equalizeSplits: nil,
            returnToDefaultSize: nil,
            increaseFontSize: increaseFontSize,
            decreaseFontSize: nil,
            resetFontSize: nil,
            changeTitle: nil,
            changeTabTitle: nil,
            quickTerminal: nil,
            toggleVisibility: nil,
            floatOnTop: nil,
            terminalInspector: nil,
            commandPalette: nil,
            secureInput: nil,
            settings: settings
        )
    }
}
