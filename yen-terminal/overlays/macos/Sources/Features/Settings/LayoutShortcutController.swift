#if os(macOS)
import Cocoa

/// Registers Cmd+Option+1-0 keyboard shortcuts for split layout presets.
/// Mirrors the TabSidebarController setup pattern — singleton, programmatic NSMenuItem, explicit target.
@MainActor
final class LayoutShortcutController: NSObject, NSMenuItemValidation {
    static let shared = LayoutShortcutController()
    private var hasSetup = false
    private var localKeyMonitor: Any?

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private override init() { super.init() }

    func setup() {
        guard !hasSetup else { return }

        // Insert layout items in File menu after the last split item (Split Up)
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }

        // Find insertion point: after the last "Split" item
        let splitUpIndex = fileMenu.items.lastIndex { $0.title.hasPrefix("Split") }
        let insertIndex = (splitUpIndex ?? fileMenu.items.count - 1) + 1

        fileMenu.insertItem(NSMenuItem.separator(), at: insertIndex)

        for (offset, layout) in LayoutTemplate.allCases.enumerated() {
            let item = NSMenuItem(
                title: layout.displayName,
                action: #selector(applyLayoutAction(_:)),
                keyEquivalent: "\((offset + 1) % 10)"
            )
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = offset
            item.target = self
            // Same glyph the command palette shows for this layout, so the two
            // surfaces cannot drift apart.
            item.setImageIfDesired(systemSymbolName: layout.commandPaletteIconName)
            fileMenu.insertItem(item, at: insertIndex + 1 + offset)
        }

        installLocalKeyMonitor()
        hasSetup = true
    }

    @objc private func applyLayoutAction(_ sender: NSMenuItem) {
        let allCases = LayoutTemplate.allCases
        guard sender.tag >= 0, sender.tag < allCases.count else { return }
        guard let controller = activeTerminalControllerForMenuAction() else { return }
        let layout = allCases[allCases.index(allCases.startIndex, offsetBy: sender.tag)]
        SettingsController.shared.applyLayout(layout, controller: controller)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(applyLayoutAction(_:)) else { return true }
        return canApplyLayoutAction
    }

    /// Test hook for verifying physical key code mapping.
    static func layoutIndex(forKeyCode keyCode: UInt16) -> Int? {
        PhysicalDigitRowKeyCodes.layoutIndex(forKeyCode: keyCode)
    }

    private var canApplyLayoutAction: Bool {
        guard let controller = activeTerminalControllerForMenuAction() else { return false }
        guard controller.focusedSurface != nil else { return false }
        guard controller.surfaceTree.root != nil else { return false }
        guard controller.yen.app != nil else { return false }
        return true
    }

    private var canApplyLayoutHotkey: Bool {
        let keyController = NSApp.keyWindow?.windowController as? BaseTerminalController
        let mainController = NSApp.mainWindow?.windowController as? BaseTerminalController
        guard let controller = Self.activeTerminalControllerForLayoutActions(
            keyController: keyController,
            mainController: mainController
        ) else { return false }
        guard controller.focusedSurface != nil else { return false }
        guard controller.surfaceTree.root != nil else { return false }
        guard controller.yen.app != nil else { return false }

        guard Self.shouldRouteShortcutToTerminal(
            hasKeyWindow: NSApp.keyWindow != nil,
            keyWindowIsTerminal: keyController != nil,
            mainWindowIsTerminal: mainController != nil,
            hasModalWindow: NSApp.modalWindow != nil,
            keyWindowHasAttachedSheet: NSApp.keyWindow?.attachedSheet != nil,
            mainWindowHasAttachedSheet: NSApp.mainWindow?.attachedSheet != nil,
            keyWindowOwnsFocusedTerminalResponder: Self.windowOwnsFocusedTerminalResponder(
                window: NSApp.keyWindow,
                controller: keyController
            )
        ) else {
            return false
        }

        return true
    }

    func activeTerminalControllerForMenuAction() -> BaseTerminalController? {
        let keyController = NSApp.keyWindow?.windowController as? BaseTerminalController
        let mainController = NSApp.mainWindow?.windowController as? BaseTerminalController
        guard Self.shouldRouteLayoutActionToTerminal(
            hasKeyWindow: NSApp.keyWindow != nil,
            keyWindowIsTerminal: keyController != nil,
            mainWindowIsTerminal: mainController != nil,
            hasModalWindow: NSApp.modalWindow != nil,
            keyWindowHasAttachedSheet: NSApp.keyWindow?.attachedSheet != nil,
            mainWindowHasAttachedSheet: NSApp.mainWindow?.attachedSheet != nil
        ) else {
            return nil
        }

        return Self.activeTerminalControllerForLayoutActions(
            keyController: keyController,
            mainController: mainController
        )
    }

    static func activeTerminalControllerForLayoutActions(
        keyController: BaseTerminalController?,
        mainController: BaseTerminalController?
    ) -> BaseTerminalController? {
        keyController ?? mainController
    }

    /// Pure routing rule for tests: utility key windows and modal UI must block
    /// layout actions from retargeting a background terminal.
    static func shouldRouteLayoutActionToTerminal(
        hasKeyWindow: Bool,
        keyWindowIsTerminal: Bool,
        mainWindowIsTerminal: Bool,
        hasModalWindow: Bool,
        keyWindowHasAttachedSheet: Bool,
        mainWindowHasAttachedSheet: Bool
    ) -> Bool {
        guard !hasModalWindow else { return false }
        if hasKeyWindow {
            guard keyWindowIsTerminal else { return false }
            return !keyWindowHasAttachedSheet
        }
        guard mainWindowIsTerminal else { return false }
        return !mainWindowHasAttachedSheet
    }

    /// Pure routing rule for tests: utility key windows, modal UI, and non-terminal
    /// first responders must block hotkey routing into the terminal.
    static func shouldRouteShortcutToTerminal(
        hasKeyWindow: Bool,
        keyWindowIsTerminal: Bool,
        mainWindowIsTerminal: Bool,
        hasModalWindow: Bool,
        keyWindowHasAttachedSheet: Bool,
        mainWindowHasAttachedSheet: Bool,
        keyWindowOwnsFocusedTerminalResponder: Bool
    ) -> Bool {
        guard shouldRouteLayoutActionToTerminal(
            hasKeyWindow: hasKeyWindow,
            keyWindowIsTerminal: keyWindowIsTerminal,
            mainWindowIsTerminal: mainWindowIsTerminal,
            hasModalWindow: hasModalWindow,
            keyWindowHasAttachedSheet: keyWindowHasAttachedSheet,
            mainWindowHasAttachedSheet: mainWindowHasAttachedSheet
        ) else {
            return false
        }
        return !hasKeyWindow || keyWindowOwnsFocusedTerminalResponder
    }

    private static func windowOwnsFocusedTerminalResponder(
        window: NSWindow?,
        controller: BaseTerminalController?
    ) -> Bool {
        guard let window, let focusedSurface = controller?.focusedSurface else { return false }
        return window.firstResponder === focusedSurface
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags == [.command, .option] else { return event }

        guard let index = Self.layoutIndex(forKeyCode: event.keyCode),
              index < LayoutTemplate.allCases.count else {
            return event
        }

        // Prevent accidental repeat-application when the key is held.
        guard !event.isARepeat else { return nil }

        // Don't consume layout shortcuts when Settings panel is focused
        if SettingsController.shared.window?.isKeyWindow == true { return event }

        // Mirror menu validation: if layout shortcuts are currently unavailable,
        // don't consume the event.
        guard canApplyLayoutHotkey else { return event }

        guard let controller = Self.activeTerminalControllerForLayoutActions(
            keyController: NSApp.keyWindow?.windowController as? BaseTerminalController,
            mainController: NSApp.mainWindow?.windowController as? BaseTerminalController
        ) else {
            return event
        }

        let layout = LayoutTemplate.allCases[LayoutTemplate.allCases.index(LayoutTemplate.allCases.startIndex, offsetBy: index)]
        SettingsController.shared.applyLayout(layout, controller: controller)
        return nil
    }
}
#endif
