#if os(macOS)
    import AppKit

    /// Shared Cmd+Shift+<key> "disabled feature" hotkey gating, used by the
    /// Scratchpad ("j") and TabSidebar ("b") controllers and the AppDelegate
    /// event monitor. When the feature is disabled these hotkeys overlap
    /// Ghostty/terminal bindings, so we consume-and-beep instead of falling
    /// through. The per-controller `isToggleHotkey` / `shouldConsume…` methods
    /// (which tests call) are thin wrappers over this.
    enum DisabledToggleHotkey {
        nonisolated static func isToggleHotkey(
            charactersIgnoringModifiers: String?,
            modifierFlags: NSEvent.ModifierFlags,
            key: String
        ) -> Bool {
            let normalizedModifiers = modifierFlags.intersection(
                .deviceIndependentFlagsMask)
            guard normalizedModifiers == [.command, .shift] else { return false }
            guard let pressed = charactersIgnoringModifiers?.lowercased() else {
                return false
            }
            return pressed == key
        }

        nonisolated static func shouldConsume(
            charactersIgnoringModifiers: String?,
            modifierFlags: NSEvent.ModifierFlags,
            key: String,
            featureEnabled: Bool
        ) -> Bool {
            guard !featureEnabled else { return false }
            return isToggleHotkey(
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                modifierFlags: modifierFlags,
                key: key
            )
        }
    }
#endif
