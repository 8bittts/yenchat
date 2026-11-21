#if os(macOS)
import Cocoa
import Carbon

// MARK: - Data Models

enum KeybindCategory: String, CaseIterable {
    case terminal = "Terminal"
    case window = "Window"
    case tabs = "Tabs"
    case splits = "Splits"
    case navigation = "Navigation"
    case font = "Font"
    case search = "Search"
    case custom = "Custom"

}

enum KeybindValidationError: Equatable {
    case missingRequiredModifier
    case reservedFixedShortcut
}

struct KeyModifiers: Hashable {
    var cmd: Bool = false
    var ctrl: Bool = false
    var option: Bool = false
    var shift: Bool = false

    /// Display string: "Cmd + Shift + ..."
    var displayString: String {
        var parts: [String] = []
        if cmd { parts.append("Cmd") }
        if ctrl { parts.append("Ctrl") }
        if option { parts.append("Option") }
        if shift { parts.append("Shift") }
        return parts.joined(separator: " + ")
    }

    /// Terminal engine config format: "super+shift+..."
    var configString: String {
        var parts: [String] = []
        if ctrl { parts.append("ctrl") }
        if option { parts.append("alt") }
        if shift { parts.append("shift") }
        if cmd { parts.append("super") }
        return parts.joined(separator: "+")
    }

    /// Whether at least one modifier (Cmd, Ctrl, or Option) is present.
    var hasRequiredModifier: Bool {
        cmd || ctrl || option
    }

    /// Build from NSEvent modifier flags.
    init(flags: NSEvent.ModifierFlags) {
        let clean = flags.intersection(.deviceIndependentFlagsMask)
        cmd = clean.contains(.command)
        ctrl = clean.contains(.control)
        option = clean.contains(.option)
        shift = clean.contains(.shift)
    }

    init(cmd: Bool = false, ctrl: Bool = false, option: Bool = false, shift: Bool = false) {
        self.cmd = cmd
        self.ctrl = ctrl
        self.option = option
        self.shift = shift
    }

    /// Build from the modifier field of an `AppleSymbolicHotKeys` entry.
    ///
    /// [CRITICAL] Those values are COCOA `NSEvent.ModifierFlags` (1<<17 .. 1<<20), not
    /// Carbon masks. The two share no bits, so decoding these with Carbon values silently
    /// resolves every system hotkey to "no modifiers" and no conflict can ever be reported.
    init(symbolicHotkeyFlags: Int) {
        self.init(flags: NSEvent.ModifierFlags(rawValue: UInt(bitPattern: symbolicHotkeyFlags)))
    }
}

struct KeyTrigger: Equatable, Hashable {
    var modifiers: KeyModifiers
    var key: String          // "d", "enter", "backquote", "left", etc.
    var keyCode: UInt16?     // Physical keycode for system shortcut comparison
    var displayKey: String?  // Layout-aware UI label when available

    // Equality ignores keyCode — two triggers with the same modifiers + key are the same
    // shortcut regardless of physical key code (defaults have nil, recorded shortcuts have a value).
    static func == (lhs: KeyTrigger, rhs: KeyTrigger) -> Bool {
        lhs.modifiers == rhs.modifiers && lhs.key.lowercased() == rhs.key.lowercased()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers)
        hasher.combine(key.lowercased())
    }

    private var normalizedKey: String {
        key.lowercased()
    }

    init(
        modifiers: KeyModifiers,
        key: String,
        keyCode: UInt16? = nil,
        displayKey: String? = nil
    ) {
        self.modifiers = modifiers
        self.key = key
        self.keyCode = keyCode
        self.displayKey = displayKey
    }

    func conflicts(with other: KeyTrigger) -> Bool {
        guard modifiers == other.modifiers else { return false }
        if normalizedKey == other.normalizedKey {
            return true
        }
        if let keyCode, let otherKeyCode = other.keyCode {
            return keyCode == otherKeyCode
        }
        return false
    }

    /// Full display string: "Cmd + D"
    var displayString: String {
        let modStr = modifiers.displayString
        let keyStr = displayKey ?? Self.displayLabel(forKey: key)
        if modStr.isEmpty { return keyStr }
        return "\(modStr) + \(keyStr)"
    }

    /// Terminal engine config format: "super+d"
    var configString: String {
        let modStr = modifiers.configString
        if modStr.isEmpty { return key }
        return "\(modStr)+\(key)"
    }

    /// The shortcut as macOS menus draw it: "⇧⌘D".
    ///
    /// Modifiers follow the menu order Control, Option, Shift, Command.
    /// `displayString` stays the spoken and logged form.
    var glyphString: String {
        var glyphs = ""
        if modifiers.ctrl { glyphs += "⌃" }
        if modifiers.option { glyphs += "⌥" }
        if modifiers.shift { glyphs += "⇧" }
        if modifiers.cmd { glyphs += "⌘" }
        return glyphs + (displayKey ?? Self.glyphLabel(forKey: key))
    }

    /// The key cap glyph for a named key, or its display label.
    fileprivate static func glyphLabel(forKey key: String) -> String {
        switch key.lowercased() {
        case "enter", "return": return "↩"
        case "escape", "esc": return "⎋"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "tab": return "⇥"
        case "backspace", "delete": return "⌫"
        case "home": return "↖"
        case "end": return "↘"
        case "page_up": return "⇞"
        case "page_down": return "⇟"
        default: return displayLabel(forKey: key)
        }
    }

    /// Human-readable key name for special keys.
    fileprivate static func displayLabel(forKey key: String) -> String {
        if key.count == 1 {
            return key.uppercased()
        }

        switch key.lowercased() {
        case "enter", "return": return "Return"
        case "escape", "esc": return "Esc"
        case "backquote": return "`"
        case "apostrophe", "quote": return "'"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "left": return "<-"
        case "right": return "->"
        case "up": return "Up"
        case "down": return "Down"
        case "space": return "Space"
        case "tab": return "Tab"
        case "backspace", "delete": return "Delete"
        case "home": return "Home"
        case "end": return "End"
        case "page_up": return "Page Up"
        case "page_down": return "Page Down"
        case "equal": return "="
        case "minus": return "-"
        case "plus": return "+"
        case "zero": return "0"
        case "left_bracket": return "["
        case "right_bracket": return "]"
        default: return key
        }
    }
}

struct KeybindEntry: Identifiable {
    let id = UUID()
    let action: String           // "new_split:right"
    let displayName: String      // "Split Right"
    let category: KeybindCategory
    let defaultTrigger: KeyTrigger
    var currentTrigger: KeyTrigger
    var isUserOverride: Bool
    var isEditable: Bool         // false for layout shortcuts and duplicate-action entries
    var lockDescription: String? // shown when isEditable is false
    var isReservedFixed: Bool    // true for app-owned shortcuts that the recorder must not assign
    /// Whether this action's config line carries the `global:` prefix — the flag that
    /// makes the hotkey fire while YEN is NOT frontmost. Remapping used to write a bare
    /// trigger, so `yen_app_has_global_keybinds` went false, the global event tap was
    /// never installed, and Quick Terminal silently became app-local only.
    var isGlobal: Bool
    var conflicts: [KeybindConflict]

    /// Stable identifier for matching across app restarts (action + default trigger).
    /// Unlike `id` (UUID, regenerated each load), this is deterministic.
    var stableId: String {
        "\(defaultTrigger.configString)=\(action)"
    }

    init(
        action: String,
        displayName: String,
        category: KeybindCategory,
        trigger: KeyTrigger,
        isEditable: Bool = true,
        lockDescription: String? = nil,
        isReservedFixed: Bool = false,
        isGlobal: Bool = false
    ) {
        self.action = action
        self.displayName = displayName
        self.category = category
        self.defaultTrigger = trigger
        self.currentTrigger = trigger
        self.isUserOverride = false
        self.isEditable = isEditable
        self.lockDescription = lockDescription
        self.isReservedFixed = isReservedFixed
        self.isGlobal = isGlobal
        self.conflicts = []
    }
}

struct KeybindConflict: Identifiable {
    let id = UUID()
    let source: ConflictSource
    let description: String
}

enum ConflictSource {
    case macOS(name: String)
    case app(bundleId: String, name: String, icon: NSImage?)
}

// MARK: - Static Keybind Catalog

/// Static catalog of YEN macOS default keybinds.
/// Built from Config.zig macOS defaults (lines 6532-6818) + YEN injections.
/// Maintained manually — check after vendor updates.
@MainActor
enum KeybindRegistry {
    struct KeyDescriptor {
        let key: String
        let displayKey: String?
    }


    /// All default keybinds for macOS, organized by category.
    static let defaults: [KeybindEntry] = buildDefaults()

    /// Fixed shortcuts that are reserved by YEN and should not be assignable via the recorder.
    static let reservedFixedTriggers: Set<KeyTrigger> = Set(defaults.compactMap {
        isReservedFixedEntry($0) ? $0.defaultTrigger : nil
    })

    static let reservedFixedShortcutValidationMessage =
        "Reserved by YEN; kept for conflict checks."

    static let missingRequiredModifierValidationMessage =
        "Add Cmd, Ctrl, or Option."

    static func validationError(for trigger: KeyTrigger) -> KeybindValidationError? {
        guard trigger.modifiers.hasRequiredModifier else {
            return .missingRequiredModifier
        }
        if reservedFixedTriggers.contains(where: { $0.conflicts(with: trigger) }) {
            return .reservedFixedShortcut
        }
        return nil
    }

    private static func buildDefaults() -> [KeybindEntry] {
        var entries: [KeybindEntry] = []
        let fixedShortcutLock = "Fixed YEN shortcut (not configurable)."
        let multiBindingLock = "Multiple default shortcuts; not editable."

        // -- Terminal --
        entries.append(keybind("copy_to_clipboard", "Copy", .terminal, cmd: true, key: "c"))
        entries.append(keybind("paste_from_clipboard", "Paste", .terminal, cmd: true, key: "v"))
        entries.append(keybind("paste_from_selection", "Paste Selection", .terminal, cmd: true, shift: true, key: "v"))
        entries.append(keybind("select_all", "Select All", .terminal, cmd: true, key: "a"))
        entries.append(keybind("clear_screen", "Clear Screen", .terminal, cmd: true, key: "k"))
        entries.append(keybind(
            "write_screen_file:copy,plain", "Copy Screen File Path", .terminal,
            cmd: true, ctrl: true, shift: true, key: "u"
        ))
        entries.append(keybind(
            "write_screen_file:paste,plain", "Paste Screen File Path", .terminal,
            cmd: true, shift: true, key: "u"
        ))
        entries.append(keybind(
            "write_screen_file:open,plain", "Open Screen File", .terminal,
            cmd: true, option: true, shift: true, key: "u"
        ))
        entries.append(keybind(
            "text:\\x0d", "Insert Newline (Shift + Return)", .terminal,
            shift: true, key: "enter",
            editable: false,
            lockDescription: "Shift-only; not editable."
        ))
        entries.append(keybind("quit", "Quit", .terminal, cmd: true, key: "q"))
        entries.append(keybind("undo", "Undo", .terminal, cmd: true, key: "z"))
        entries.append(keybind("redo", "Redo", .terminal, cmd: true, shift: true, key: "z"))
        entries.append(keybind("undo", "Reopen Closed Tab", .terminal, cmd: true, shift: true, key: "t"))

        // -- Window --
        entries.append(keybind("new_window", "New Window", .window, cmd: true, key: "n"))
        entries.append(keybind("close_surface", "Close Pane", .window, cmd: true, key: "w"))
        entries.append(keybind("close_tab", "Close Tab", .window, cmd: true, option: true, key: "w"))
        entries.append(keybind("close_window", "Close Window", .window, cmd: true, shift: true, key: "w"))
        entries.append(keybind("close_all_windows", "Close All Windows", .window, cmd: true, option: true, shift: true, key: "w"))
        entries.append(keybind("toggle_fullscreen", "Toggle Fullscreen", .window, cmd: true, key: "enter"))
        entries.append(keybind("toggle_fullscreen", "Toggle Fullscreen (Alt)", .window, cmd: true, ctrl: true, key: "f"))
        entries.append(keybind("toggle_split_zoom", "Toggle Split Zoom", .window, cmd: true, shift: true, key: "enter"))
        entries.append(keybind("toggle_command_palette", "Command Palette", .window, cmd: true, shift: true, key: "p"))
        entries.append(keybind("inspector:toggle", "Toggle Inspector", .window, cmd: true, option: true, key: "i"))

        // -- Tabs --
        entries.append(keybind("new_tab", "New Tab", .tabs, cmd: true, key: "t"))
        entries.append(keybind("previous_tab", "Previous Tab", .tabs, cmd: true, shift: true, key: "left_bracket"))
        entries.append(keybind("next_tab", "Next Tab", .tabs, cmd: true, shift: true, key: "right_bracket"))
        entries.append(keybind("goto_tab:1", "Tab 1", .tabs, cmd: true, key: "1"))
        entries.append(keybind("goto_tab:2", "Tab 2", .tabs, cmd: true, key: "2"))
        entries.append(keybind("goto_tab:3", "Tab 3", .tabs, cmd: true, key: "3"))
        entries.append(keybind("goto_tab:4", "Tab 4", .tabs, cmd: true, key: "4"))
        entries.append(keybind("goto_tab:5", "Tab 5", .tabs, cmd: true, key: "5"))
        entries.append(keybind("goto_tab:6", "Tab 6", .tabs, cmd: true, key: "6"))
        entries.append(keybind("goto_tab:7", "Tab 7", .tabs, cmd: true, key: "7"))
        entries.append(keybind("goto_tab:8", "Tab 8", .tabs, cmd: true, key: "8"))
        entries.append(keybind("last_tab", "Last Tab", .tabs, cmd: true, key: "9"))

        // -- Splits --
        entries.append(keybind("new_split:right", "Split Right", .splits, cmd: true, key: "d"))
        entries.append(keybind("new_split:down", "Split Down", .splits, cmd: true, shift: true, key: "d"))
        entries.append(keybind("goto_split:previous", "Previous Split", .splits, cmd: true, key: "left_bracket"))
        entries.append(keybind("goto_split:next", "Next Split", .splits, cmd: true, key: "right_bracket"))
        entries.append(keybind("goto_split:up", "Split Up", .splits, cmd: true, option: true, key: "up"))
        entries.append(keybind("goto_split:down", "Split Down (Navigate)", .splits, cmd: true, option: true, key: "down"))
        entries.append(keybind("goto_split:left", "Split Left", .splits, cmd: true, option: true, key: "left"))
        entries.append(keybind("goto_split:right", "Split Right (Navigate)", .splits, cmd: true, option: true, key: "right"))
        entries.append(keybind("resize_split:up,10", "Resize Split Up", .splits, cmd: true, ctrl: true, key: "up"))
        entries.append(keybind("resize_split:down,10", "Resize Split Down", .splits, cmd: true, ctrl: true, key: "down"))
        entries.append(keybind("resize_split:left,10", "Resize Split Left", .splits, cmd: true, ctrl: true, key: "left"))
        entries.append(keybind("resize_split:right,10", "Resize Split Right", .splits, cmd: true, ctrl: true, key: "right"))
        entries.append(keybind("equalize_splits", "Equalize Splits", .splits, cmd: true, ctrl: true, key: "equal"))

        // -- Navigation --
        entries.append(keybind("scroll_to_top", "Scroll to Top", .navigation, cmd: true, key: "home"))
        entries.append(keybind("scroll_to_bottom", "Scroll to Bottom", .navigation, cmd: true, key: "end"))
        entries.append(keybind("scroll_page_up", "Page Up", .navigation, cmd: true, key: "page_up"))
        entries.append(keybind("scroll_page_down", "Page Down", .navigation, cmd: true, key: "page_down"))
        entries.append(keybind("scroll_to_selection", "Scroll to Selection", .navigation, cmd: true, key: "j"))
        entries.append(keybind("jump_to_prompt:-1", "Previous Prompt", .navigation, cmd: true, shift: true, key: "up"))
        entries.append(keybind("jump_to_prompt:1", "Next Prompt", .navigation, cmd: true, shift: true, key: "down"))
        entries.append(keybind("jump_to_prompt_alt:-1", "Previous Prompt (Cmd + Up)", .navigation, cmd: true, key: "up", editable: false))
        entries.append(keybind("jump_to_prompt_alt:1", "Next Prompt (Cmd + Down)", .navigation, cmd: true, key: "down", editable: false))
        entries.append(keybind("text:\\x05", "Move to End of Line", .navigation, cmd: true, key: "right"))
        entries.append(keybind("text:\\x01", "Move to Start of Line", .navigation, cmd: true, key: "left"))
        entries.append(keybind("text:\\x15", "Delete to Start of Line", .navigation, cmd: true, key: "backspace"))
        entries.append(keybind("esc:b", "Move Backward Word", .navigation, option: true, key: "left"))
        entries.append(keybind("esc:f", "Move Forward Word", .navigation, option: true, key: "right"))

        // -- Font --
        entries.append(keybind("increase_font_size:1", "Increase Font Size", .font, cmd: true, key: "equal"))
        entries.append(keybind("decrease_font_size:1", "Decrease Font Size", .font, cmd: true, key: "minus"))
        entries.append(keybind("reset_font_size", "Reset Font Size", .font, cmd: true, key: "0"))

        // -- Search --
        entries.append(keybind("start_search", "Find", .search, cmd: true, key: "f"))
        entries.append(keybind("search_selection", "Find Selection", .search, cmd: true, key: "e"))
        entries.append(keybind("end_search", "Close Find Bar", .search, cmd: true, shift: true, key: "f"))
        entries.append(keybind("navigate_search:next", "Find Next", .search, cmd: true, key: "g"))
        entries.append(keybind("navigate_search:previous", "Find Previous", .search, cmd: true, shift: true, key: "k"))

        // -- Custom (YEN-specific) --
        entries.append(keybind("toggle_quick_terminal", "Quick Terminal", .custom, ctrl: true, key: "backquote", isGlobal: true))
        entries.append(keybind(
            "yen_show_settings", "Settings", .custom,
            cmd: true, key: "comma",
            editable: false,
            lockDescription: fixedShortcutLock,
            isReservedFixed: true
        ))
        entries.append(keybind(
            "yen_toggle_tab_sidebar", "Toggle Tab Sidebar", .custom,
            cmd: true, shift: true, key: "b",
            editable: false,
            lockDescription: fixedShortcutLock,
            isReservedFixed: true
        ))
        entries.append(keybind(
            "yen_toggle_scratchpad", "Toggle Scratchpad", .custom,
            cmd: true, shift: true, key: "j",
            editable: false,
            lockDescription: fixedShortcutLock,
            isReservedFixed: true
        ))
        entries.append(keybind(
            "yen_open_file_browser", "Open File Browser", .custom,
            cmd: true, shift: true, key: "o",
            editable: false,
            lockDescription: fixedShortcutLock,
            isReservedFixed: true
        ))
        entries.append(keybind(
            "yen_take_screenshot", "Screenshot", .custom,
            cmd: true, shift: true, key: "s",
            editable: false,
            lockDescription: fixedShortcutLock,
            isReservedFixed: true
        ))
        entries.append(keybind(
            "yen_dictation_push_to_talk", "Dictation Push-to-Talk", .custom,
            option: true, key: "space",
            editable: false,
            lockDescription: "Fixed global shortcut.",
            isReservedFixed: true
        ))
        // Layout shortcuts are handled by LayoutShortcutController (Cmd+Option+1-0),
        // not config.yen keybinds. Listed here for visibility / conflict detection only.
        for i in 1...10 {
            let displayIndex = i == 10 ? 0 : i
            let template = i <= LayoutTemplate.allCases.count
                ? LayoutTemplate.allCases[i - 1]
                : nil
            let name = template?.displayName ?? "Layout \(i)"
            entries.append(keybind(
                "layout:\(i)", name, .custom,
                trigger: layoutShortcutTrigger(forDisplayIndex: displayIndex),
                editable: false,
                lockDescription: "Handled by layout shortcuts (Cmd + Option + 1-0).",
                isReservedFixed: true
            ))
        }

        // Mark entries with duplicate action names as non-editable.
        // Config format "trigger=action" can't distinguish which entry an override
        // belongs to when multiple entries share the same action string.
        var actionCounts: [String: Int] = [:]
        for entry in entries { actionCounts[entry.action, default: 0] += 1 }
        let duplicateActions = Set(actionCounts.filter { $0.value > 1 }.keys)
        for i in entries.indices where duplicateActions.contains(entries[i].action) {
            entries[i].isEditable = false
            if entries[i].lockDescription == nil {
                entries[i].lockDescription = multiBindingLock
            }
        }

        return entries
    }

    /// Convenience to build a KeybindEntry with named modifier flags.
    private static func keybind(
        _ action: String, _ name: String, _ category: KeybindCategory,
        cmd: Bool = false, ctrl: Bool = false, option: Bool = false, shift: Bool = false,
        key: String, editable: Bool = true, lockDescription: String? = nil, isReservedFixed: Bool = false,
        isGlobal: Bool = false
    ) -> KeybindEntry {
        keybind(
            action,
            name,
            category,
            trigger: KeyTrigger(
                modifiers: KeyModifiers(cmd: cmd, ctrl: ctrl, option: option, shift: shift),
                key: key
            ),
            editable: editable,
            lockDescription: lockDescription,
            isReservedFixed: isReservedFixed,
            isGlobal: isGlobal
        )
    }

    private static func keybind(
        _ action: String,
        _ name: String,
        _ category: KeybindCategory,
        trigger: KeyTrigger,
        editable: Bool = true,
        lockDescription: String? = nil,
        isReservedFixed: Bool = false,
        isGlobal: Bool = false
    ) -> KeybindEntry {
        KeybindEntry(
            action: action,
            displayName: name,
            category: category,
            trigger: trigger,
            isEditable: editable,
            lockDescription: lockDescription,
            isReservedFixed: isReservedFixed,
            isGlobal: isGlobal
        )
    }

    private static func layoutShortcutTrigger(forDisplayIndex displayIndex: Int) -> KeyTrigger {
        let fallbackKey = "\(displayIndex)"
        guard let keyCode = PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: displayIndex) else {
            return KeyTrigger(
                modifiers: KeyModifiers(cmd: true, option: true),
                key: fallbackKey
            )
        }

        let layoutCharacters = currentKeyboardLayoutCharacters(forKeyCode: keyCode)
        let normalizedKey = layoutCharacters.flatMap(canonicalKey(fromLayoutAwareSource:)) ?? fallbackKey
        let displayKey = displayLabel(fromLayoutAwareSource: layoutCharacters)
        let resolvedDisplayKey =
            displayKey == KeyTrigger.displayLabel(forKey: normalizedKey) ? nil : displayKey

        return KeyTrigger(
            modifiers: KeyModifiers(cmd: true, option: true),
            key: normalizedKey,
            keyCode: keyCode,
            displayKey: resolvedDisplayKey
        )
    }

    // MARK: - Config Parsing

    /// Parse a keybind config value into action + trigger.
    /// Format: "super+d=new_split:right" or "ctrl+backquote=toggle_quick_terminal"
    static func parseConfigLine(_ value: String) -> (trigger: KeyTrigger, action: String)? {
        guard let separatorIndex = value.lastIndex(of: "=") else { return nil }

        let triggerStr = String(value[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let action = String(value[value.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !triggerStr.isEmpty else { return nil }
        guard !action.isEmpty else { return nil }

        if let trigger = parseTrigger(triggerStr) {
            return (trigger, action)
        }

        // `super+=action` uses the separator character as the literal `=` key.
        guard triggerStr.hasSuffix("+"), let trigger = parseTrigger(triggerStr + "=") else { return nil }
        return (trigger, action)
    }

    /// Split an optional leading `global:` off a trigger string.
    ///
    /// Deliberately NOT folded into `parseTrigger`: the merge filter treats "parses"
    /// as "Settings owns this line and will re-emit it", and a non-overridden
    /// `global:` line must keep flowing through the preserve path instead.
    static func splitGlobalPrefix(_ triggerString: String) -> (isGlobal: Bool, remainder: String) {
        let trimmed = triggerString.trimmingCharacters(in: .whitespaces)
        let prefix = "global:"
        guard trimmed.lowercased().hasPrefix(prefix) else { return (false, trimmed) }
        return (true, String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
    }

    /// Like `parseConfigLine`, but also accepts a `global:`-prefixed trigger and
    /// reports the prefix. Used by the READ path so a remapped global binding is
    /// recognised as a user override on the next launch.
    static func parseConfigLineAllowingGlobal(
        _ value: String
    ) -> (trigger: KeyTrigger, action: String, isGlobal: Bool)? {
        if let direct = parseConfigLine(value) {
            return (direct.trigger, direct.action, false)
        }
        guard let separatorIndex = value.lastIndex(of: "=") else { return nil }
        let triggerStr = String(value[..<separatorIndex])
        let action = String(value[value.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespaces)
        guard !action.isEmpty else { return nil }
        let split = splitGlobalPrefix(triggerStr)
        guard split.isGlobal, let trigger = parseTrigger(split.remainder) else { return nil }
        return (trigger, action, true)
    }

    /// Parse a trigger string like "super+shift+d" into a KeyTrigger.
    static func parseTrigger(_ str: String) -> KeyTrigger? {
        let normalizedInput = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedInput.isEmpty else { return nil }
        // Restrict parser to simple "modifier+key" triggers managed by Settings.
        // Advanced syntax (global:, table/, sequences) must be preserved as-is.
        if normalizedInput.contains(":") || normalizedInput.contains(">") {
            return nil
        }

        var mods = KeyModifiers()
        let modifierSection: String
        let rawKeyToken: String

        if normalizedInput == "+" {
            modifierSection = ""
            rawKeyToken = "+"
        } else if normalizedInput.hasSuffix("++") {
            modifierSection = String(normalizedInput.dropLast(2))
            rawKeyToken = "+"
        } else if let separatorIndex = normalizedInput.lastIndex(of: "+") {
            modifierSection = String(normalizedInput[..<separatorIndex])
            rawKeyToken = String(normalizedInput[normalizedInput.index(after: separatorIndex)...])
            guard !rawKeyToken.isEmpty else { return nil }
        } else {
            modifierSection = ""
            rawKeyToken = normalizedInput
        }

        let modifierTokens: [String]
        if modifierSection.isEmpty {
            modifierTokens = []
        } else {
            let rawModifierTokens = modifierSection.split(separator: "+", omittingEmptySubsequences: false)
            let trimmedModifierTokens = rawModifierTokens.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard trimmedModifierTokens.allSatisfy({ !$0.isEmpty }) else { return nil }
            modifierTokens = trimmedModifierTokens
        }

        for token in modifierTokens {
            switch token {
            case "super", "cmd", "command":
                guard !mods.cmd else { return nil }
                mods.cmd = true
            case "ctrl", "control":
                guard !mods.ctrl else { return nil }
                mods.ctrl = true
            case "alt", "opt", "option":
                guard !mods.option else { return nil }
                mods.option = true
            case "shift":
                guard !mods.shift else { return nil }
                mods.shift = true
            default:
                return nil
            }
        }

        guard let k = normalizedTriggerKey(rawKeyToken) else { return nil }
        return KeyTrigger(modifiers: mods, key: k)
    }

    /// Normalize simple trigger keys into canonical key names.
    static func normalizedTriggerKey(_ token: String) -> String? {
        switch token {
        case "+": return "plus"
        case "←": return "left"
        case "→": return "right"
        case "↑": return "up"
        case "↓": return "down"
        case ",": return "comma"
        case ".": return "period"
        case "/": return "slash"
        case "\\": return "backslash"
        case ";": return "semicolon"
        case "'": return "apostrophe"
        case "`": return "backquote"
        case "[": return "left_bracket"
        case "]": return "right_bracket"
        case "=": return "equal"
        case "-": return "minus"
        case "return": return "enter"
        case "esc": return "escape"
        case "pgup": return "page_up"
        case "pgdn": return "page_down"
        case "del": return "delete"
        case "bksp": return "backspace"
        case " ": return "space"
        case "spacebar": return "space"
        case "quote": return "apostrophe"
        case "plus": return "plus"
        case "minus": return "minus"
        case "equal", "equals": return "equal"
        default:
            if let scalar = singleDisplayScalar(from: token) {
                return String(scalar).lowercased()
            }
            guard token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
                return nil
            }
            return token
        }
    }

    // MARK: - Shared Keycode Mapping

    /// Resolve a canonical key token plus an optional layout-aware display label.
    static func keyDescriptor(forKeyCode keyCode: UInt16, event: NSEvent? = nil) -> KeyDescriptor {
        let translatedCharacters = event?.characters(byApplyingModifiers: []) ?? event?.charactersIgnoringModifiers
        let displayCharacters = event?.charactersIgnoringModifiers ?? event?.characters
        return keyDescriptor(
            forKeyCode: keyCode,
            translatedCharacters: translatedCharacters,
            displayCharacters: displayCharacters
        )
    }

    /// Resolve a system-hotkey key token plus display label using current-layout translation
    /// for matching and the plist character code for user-facing display when available.
    static func keyDescriptor(forSystemHotkeyKeyCode keyCode: UInt16, characterCode: Int?) -> KeyDescriptor {
        keyDescriptor(
            forKeyCode: keyCode,
            translatedCharacters: currentKeyboardLayoutCharacters(forKeyCode: keyCode),
            displayCharacters: displayCharacters(forSymbolicHotkeyCharacterCode: characterCode)
        )
    }

    static func keyDescriptor(
        forKeyCode keyCode: UInt16,
        translatedCharacters: String?,
        displayCharacters: String?
    ) -> KeyDescriptor {
        if let translatedKey = canonicalKey(fromLayoutAwareSource: translatedCharacters) {
            let displayKey = displayLabel(fromLayoutAwareSource: displayCharacters ?? translatedCharacters)
            return KeyDescriptor(
                key: translatedKey,
                displayKey: displayKey == KeyTrigger.displayLabel(forKey: translatedKey) ? nil : displayKey
            )
        }

        if let displayDerivedKey = canonicalKey(fromLayoutAwareSource: displayCharacters) {
            let displayKey = displayLabel(fromLayoutAwareSource: displayCharacters)
            return KeyDescriptor(
                key: displayDerivedKey,
                displayKey: displayKey == KeyTrigger.displayLabel(forKey: displayDerivedKey) ? nil : displayKey
            )
        }

        let fallbackKey = fallbackKeyName(forKeyCode: keyCode) ?? "unknown_\(keyCode)"
        let displayKey = displayLabel(fromLayoutAwareSource: displayCharacters)
        return KeyDescriptor(
            key: fallbackKey,
            displayKey: displayKey == KeyTrigger.displayLabel(forKey: fallbackKey) ? nil : displayKey
        )
    }

    private static func fallbackKeyName(forKeyCode keyCode: UInt16) -> String? {
        if let digitKey = PhysicalDigitRowKeyCodes.fallbackDigitName(forKeyCode: keyCode) {
            return digitKey
        }

        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 24: return "equal"
        case 27: return "minus"
        case 30: return "right_bracket"
        case 31: return "o"
        case 32: return "u"
        case 33: return "left_bracket"
        case 34: return "i"
        case 35: return "p"
        case 36: return "enter"
        case 37: return "l"
        case 38: return "j"
        case 39: return "apostrophe"
        case 40: return "k"
        case 41: return "semicolon"
        case 42: return "backslash"
        case 43: return "comma"
        case 44: return "slash"
        case 45: return "n"
        case 46: return "m"
        case 47: return "period"
        case 48: return "tab"
        case 49: return "space"
        case 50: return "backquote"
        case 51: return "backspace"
        case 53: return "escape"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 99: return "f3"
        case 100: return "f8"
        case 101: return "f9"
        case 103: return "f11"
        case 105: return "f13"
        case 107: return "f14"
        case 109: return "f10"
        case 111: return "f12"
        case 113: return "f15"
        case 115: return "home"
        case 116: return "page_up"
        case 117: return "delete"
        case 118: return "f4"
        case 119: return "end"
        case 120: return "f2"
        case 121: return "page_down"
        case 122: return "f1"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default: return nil
        }
    }

    private static func canonicalKey(fromLayoutAwareSource source: String?) -> String? {
        if source == "+" {
            return "plus"
        }
        guard let scalar = singleDisplayScalar(from: source) else { return nil }
        return normalizedTriggerKey(String(scalar))
    }

    private static func displayLabel(fromLayoutAwareSource source: String?) -> String? {
        if source == "+" {
            return "+"
        }
        guard let scalar = singleDisplayScalar(from: source) else { return nil }
        guard let canonical = normalizedTriggerKey(String(scalar)) else { return nil }
        return KeyTrigger.displayLabel(forKey: canonical)
    }

    private static func singleDisplayScalar(from source: String?) -> UnicodeScalar? {
        guard let source, !source.isEmpty else { return nil }
        let scalars = Array(source.unicodeScalars)
        guard scalars.count == 1 else { return nil }

        let scalar = scalars[0]
        if scalar.value == 0x2B {
            return nil
        }
        if scalar.properties.isWhitespace && scalar.value != 0x20 {
            return nil
        }
        if scalar.properties.generalCategory == .control ||
            scalar.properties.generalCategory == .privateUse {
            return nil
        }

        return scalar
    }

    private static func displayCharacters(forSymbolicHotkeyCharacterCode characterCode: Int?) -> String? {
        guard let characterCode,
              characterCode > 0,
              characterCode != 0xFFFF,
              let scalar = UnicodeScalar(characterCode) else {
            return nil
        }
        return String(scalar)
    }

    private static func currentKeyboardLayoutCharacters(forKeyCode keyCode: UInt16) -> String? {
        guard let layoutData = currentUnicodeKeyboardLayoutData(),
              let rawLayout = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(rawLayout))
        var deadKeyState: UInt32 = 0
        var translatedLength: Int = 0
        var translatedCharacters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            translatedCharacters.count,
            &translatedLength,
            &translatedCharacters
        )

        guard status == noErr, translatedLength > 0 else { return nil }
        return String(
            utf16CodeUnits: translatedCharacters,
            count: Int(translatedLength)
        )
    }

    private static func currentUnicodeKeyboardLayoutData() -> CFData? {
        let inputSources: [TISInputSource?] = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        ]

        for source in inputSources.compactMap({ $0 }) {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                continue
            }
            let data = unsafeBitCast(raw, to: CFData.self)
            if CFDataGetLength(data) > 0 {
                return data
            }
        }

        return nil
    }

    private static func isReservedFixedEntry(_ entry: KeybindEntry) -> Bool {
        entry.isReservedFixed
    }
}

#endif // os(macOS)
