#if os(macOS)
import Foundation

/// Pure, `@MainActor`-free model of the managed portion of a `config.yen`
/// document: the ordered managed key/value pairs plus the two governing
/// key-sets and the config-line parser. Extracted from `SettingsController` so
/// the merge algorithm is directly unit-testable without the singleton or disk.
struct ManagedConfigDocument: Equatable {
    struct Entry: Equatable {
        let key: String
        let value: String
    }

    /// Managed key/value pairs in write order.
    let settings: [Entry]
    /// Whether a theme is currently selected (governs theme-color stripping).
    let hasSelectedTheme: Bool
    /// Whether a background image is set (governs background-image-key stripping).
    let hasBackgroundImage: Bool

    /// Keys that themes control — strip these when a theme is selected
    /// so the theme's colors actually take effect.
    static let themeColorKeys: Set<String> = [
        "background", "foreground",
        "cursor-color", "cursor-text",
        "selection-background", "selection-foreground",
        "search-background", "search-foreground",
        "search-selected-background", "search-selected-foreground",
        "bold-color",
        "palette",
    ]
    static let backgroundImageManagedKeys: Set<String> = [
        "background-image",
        "background-image-fit",
        "background-image-opacity",
        "background-image-position",
        "background-image-repeat",
    ]

    /// Config keys that legitimately appear MORE THAN ONCE and accumulate.
    ///
    /// [KNOWN GAP] `palette` is in this set AND in `themeColorKeys`. When a theme IS
    /// selected, the theme-color strip below removes every `palette` line before the
    /// repeatable rule is ever consulted, so the protection here does NOT apply to a
    /// theme user. That strip is deliberate — it is how a theme's palette takes effect —
    /// so closing the gap means deciding whether an explicit `palette` line should
    /// override a selected theme. That is a product call, not a cleanup; do not change
    /// it silently. Not scheduled while YEN is in maintenance mode.
    ///
    /// [CRITICAL] The merge below de-duplicates by key. Any repeatable key missing
    /// from this set has every occurrence after the first silently DELETED from the
    /// user's `config.yen` the next time Settings writes anything — a hand-authored
    /// 16-line `palette` block or several `config-file` includes destroyed by an
    /// unrelated slider drag. Only `keybind` used to be listed here.
    ///
    /// Derived from the upstream config schema: every field whose type is one of the
    /// `Repeatable*` families, plus `palette` and `keybind`, which accumulate through
    /// their own types. `tests/45-overlay-patching.test.ts` re-derives this set from
    /// the vendored `Config.zig` and fails when upstream adds a repeatable key we do
    /// not list, so this cannot rot silently across a vendor bump.
    static let repeatableKeys: Set<String> = [
        // These three accumulate through their own types, not a `Repeatable*` family:
        // `Keybinds`, `Palette`, `KeyRemapSet`. Config.zig documents key-remap as
        // "This configuration can be repeated to specify multiple remaps."
        "keybind",
        "palette",
        "key-remap",
        "config-file",
        "font-family",
        "font-family-bold",
        "font-family-italic",
        "font-family-bold-italic",
        "font-feature",
        "font-variation",
        "font-variation-bold",
        "font-variation-italic",
        "font-variation-bold-italic",
        "font-codepoint-map",
        "clipboard-codepoint-map",
        "env",
        "input",
        "link",
        "command-palette-entry",
        "custom-shader",
        "gtk-custom-css",
    ]

    static func activeConfigLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        return trimmed
    }

    static func entry(from line: String) -> Entry? {
        guard let trimmed = activeConfigLine(line) else { return nil }
        let parts = trimmed.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return Entry(
            key: String(parts[0].trimmingCharacters(in: .whitespaces)),
            value: String(parts[1].trimmingCharacters(in: .whitespaces))
        )
    }

    static func key(from line: String) -> String? {
        guard let trimmed = activeConfigLine(line),
              let keyPart = trimmed.split(separator: "=", maxSplits: 1).first else {
            return nil
        }
        return String(keyPart.trimmingCharacters(in: .whitespaces))
    }

    /// Merge the managed settings into existing config lines, preserving comments
    /// and unknown keys. Exact transcription of the former
    /// `SettingsController.mergeSettings`: `existingKeys` is recomputed here from
    /// the same lines, identical to what every former caller precomputed.
    func merged(intoExistingLines existingLines: [String]) -> [String] {
        var existingKeys: Set<String> = []
        for line in existingLines {
            guard let key = Self.key(from: line) else { continue }
            existingKeys.insert(key)
        }

        var newLines: [String] = []
        var writtenKeys: Set<String> = []

        for line in existingLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                newLines.append(line)
                continue
            }

            guard let key = Self.key(from: line) else {
                newLines.append(line)
                continue
            }

            // Repeatable keys accumulate — every occurrence must survive. Dropping the
            // tail here deletes user data on an unrelated Settings write.
            if writtenKeys.contains(key) && !Self.repeatableKeys.contains(key) { continue }
            if key == "theme" && !hasSelectedTheme { continue }
            if key == "tab-sidebar-enabled" { continue }
            // Legacy key from removed dedicated split-opacity settings UI.
            if key == "unfocused-split-opacity" { continue }
            if Self.backgroundImageManagedKeys.contains(key) && !hasBackgroundImage { continue }
            if hasSelectedTheme && Self.themeColorKeys.contains(key) { continue }

            // A managed value replaces only the FIRST occurrence of a repeatable key;
            // later occurrences pass through untouched. Rewriting all of them would
            // collapse a user's `font-family` fallback chain into N copies of the
            // picker's primary family.
            let alreadyReplaced = writtenKeys.contains(key)
            if !alreadyReplaced, let setting = settings.first(where: { $0.key == key }) {
                newLines.append("\(setting.key) = \(setting.value)")
            } else {
                newLines.append(line)
            }
            writtenKeys.insert(key)
        }

        for setting in settings {
            if !existingKeys.contains(setting.key) {
                newLines.append("\(setting.key) = \(setting.value)")
            }
        }

        return newLines
    }
}
#endif
