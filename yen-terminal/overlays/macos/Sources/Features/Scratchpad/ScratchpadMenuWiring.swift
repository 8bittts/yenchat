#if os(macOS)
import Cocoa

extension ScratchpadController {
    func installScratchpadMenuItem() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }

        viewMenu.addItem(NSMenuItem.separator())
        let item = NSMenuItem(
            title: "Toggle Scratchpad",
            action: #selector(toggleAction(_:)),
            keyEquivalent: "j"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        item.setImageIfDesired(systemSymbolName: "square.and.pencil")
        viewMenu.addItem(item)
    }

    @objc func toggleAction(_ sender: Any?) {
        toggle()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(toggleAction(_:)) else { return true }
        return Self.scratchpadEnabled
    }

    nonisolated static func shouldConsumeDisabledToggleHotkey(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        scratchpadEnabled: Bool
    ) -> Bool {
        DisabledToggleHotkey.shouldConsume(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags,
            key: "j",
            featureEnabled: scratchpadEnabled
        )
    }

    nonisolated static func isToggleHotkey(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        DisabledToggleHotkey.isToggleHotkey(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags,
            key: "j"
        )
    }
}
#endif
