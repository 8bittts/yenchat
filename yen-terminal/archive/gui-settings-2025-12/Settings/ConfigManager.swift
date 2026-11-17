import Foundation

/// Manages reading and writing YEN Terminal configuration files
class ConfigManager {
    static let shared = ConfigManager()

    private let configURL: URL
    private let bundledConfigURL: URL

    init() {
        // YEN config path: ~/Library/Application Support/com.yenchat.yen/config.yen
        // This matches Yen's preferred config file name
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        configURL = appSupport
            .appendingPathComponent("com.yenchat.yen")
            .appendingPathComponent("config.yen")

        // Bundled config path: YEN.app/Contents/Resources/config.yen
        // Used as fallback for welcome banner command and defaults
        bundledConfigURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("config.yen")
    }

    // MARK: - First Launch Config Initialization

    /// Ensures YEN's branded config exists on first launch.
    /// MUST be called BEFORE YEN.App() is initialized to prevent the terminal from
    /// creating a generic template config that lacks YEN branding.
    ///
    /// This method:
    /// 1. Checks if user config exists at ~/Library/Application Support/com.yenchat.yen/config.yen
    /// 2. If not (or if empty/corrupted), copies bundled config.yen (with YEN branding and colors)
    /// 3. Creates the config directory if needed
    ///
    /// Without this, fresh installs show default styling instead of YEN branding.
    static func ensureFirstLaunchConfig() {
        let manager = shared
        let fileManager = FileManager.default

        // Check if user config exists and is valid (not empty)
        if fileManager.fileExists(atPath: manager.configURL.path) {
            // Verify file is not empty (empty files can cause OutOfMemory errors)
            if let attributes = try? fileManager.attributesOfItem(atPath: manager.configURL.path),
               let fileSize = attributes[.size] as? Int64,
               fileSize > 0 {
                return // User config exists and is valid, nothing to do
            }
            // File exists but is empty/corrupted - remove it so we can restore from bundled config
            try? fileManager.removeItem(at: manager.configURL)
        }

        // Check if bundled config exists
        guard fileManager.fileExists(atPath: manager.bundledConfigURL.path) else {
            print("WARNING: Bundled config.yen not found at \(manager.bundledConfigURL.path)")
            return
        }

        // Create config directory if needed
        let configDir = manager.configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            print("ERROR: Failed to create config directory: \(error.localizedDescription)")
            return
        }

        // Copy bundled config to user config location
        do {
            try fileManager.copyItem(at: manager.bundledConfigURL, to: manager.configURL)
            print("INFO: Copied bundled YEN config to \(manager.configURL.path)")
        } catch {
            print("ERROR: Failed to copy bundled config: \(error.localizedDescription)")
        }
    }

    // MARK: - Read Config

    /// Read config file and return key-value dictionary
    func read() -> [String: String] {
        guard let data = try? String(contentsOf: configURL, encoding: .utf8) else {
            return [:]
        }
        return parseConfig(data)
    }

    // MARK: - Write Config

    /// Write settings dictionary to config file
    /// YEN Customization: Settings GUI manages ONLY appearance/behavior settings
    /// The `command` key (if any) is managed by the build system and should NEVER
    /// be touched by Settings GUI. This ensures clear separation between:
    /// - Style settings (managed by Settings GUI)
    /// - Terminal startup behavior (managed by build system via config.yen)
    /// - Throws: File system errors if config file cannot be written
    ///
    /// Note: As of CLI refactoring, YEN uses a clean terminal (no command key).
    /// Users access YEN features via the standalone `yen` CLI tool.
    func write(_ settings: [String: String]) throws {
        // YEN Customization: Always preserve the command key from bundled config
        // Settings GUI NEVER modifies terminal startup behavior
        // Priority: 1) Bundled config command (authoritative source)
        var finalSettings = settings

        // Preserve any command from bundled config (currently empty for clean terminal)
        if let bundledConfig = try? String(contentsOf: bundledConfigURL, encoding: .utf8) {
            let bundledParsed = parseConfig(bundledConfig)
            if let bundledCommand = bundledParsed["command"], !bundledCommand.isEmpty {
                finalSettings["command"] = bundledCommand
            }
        }

        // Ensure config directory exists before writing
        let configDir = configURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: configDir.path) {
            do {
                try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
            } catch {
                print("ERROR: Failed to create config directory: \(error.localizedDescription)")
                throw error
            }
        }

        let configText = formatConfig(finalSettings)
        do {
            try configText.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            // CRITICAL: Config write failures must not be silent
            // Log error for debugging but don't crash Settings GUI
            print("ERROR: Failed to write config file: \(error.localizedDescription)")
            print("Config path: \(configURL.path)")
            // Re-throw to ensure caller knows write failed
            throw error
        }
    }

    // MARK: - Parse Config

    /// Parse config file text into key-value dictionary
    /// Format: key = value (one per line, # for comments)
    public func parseConfig(_ text: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Split on "=" and trim whitespace
            let parts = trimmed.components(separatedBy: "=")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            guard parts.count >= 2 else { continue }

            let key = parts[0]
            let value = parts[1...].joined(separator: "=") // Handle values with "=" in them

            result[key] = value
        }

        return result
    }

    // MARK: - Format Config

    /// Format settings dictionary into config file text
    private func formatConfig(_ settings: [String: String]) -> String {
        var lines: [String] = []

        // Header
        lines.append("# YEN Terminal - Configuration")
        lines.append("#")
        lines.append("# This configuration was generated by YEN Settings")
        lines.append("# Last updated: \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append("#")
        lines.append("# For complete configuration documentation, visit:")
        lines.append("# https://yen.chat/docs/configuration")
        lines.append("#")
        lines.append("# YEN can reload config with: Command + Shift + Comma")
        lines.append("#")
        lines.append("")

        // YEN Customization: Add welcome banner command at the top if present
        // This is a post-vendor modification to ensure YEN branding is visible
        if let command = settings["command"], !command.isEmpty {
            lines.append("# " + String(repeating: "=", count: 44))
            lines.append("# WELCOME BANNER")
            lines.append("# " + String(repeating: "=", count: 44))
            lines.append("# Shows ASCII art, version, tagline, and greeting on every terminal load")
            lines.append("command = \(command)")
            lines.append("")
        }

        // Group settings by category
        let categories: [(String, [String])] = [
            ("APPEARANCE", [
                "background", "foreground", "background-opacity", "background-blur",
                "window-theme", "unfocused-split-opacity"
            ]),
            ("TYPOGRAPHY", [
                "font-family", "font-size", "font-family-bold", "font-family-italic",
                "font-thicken", "font-synthetic-style"
            ]),
            ("CURSOR & SELECTION", [
                "cursor-color", "cursor-opacity", "cursor-text", "cursor-style",
                "selection-background", "selection-foreground"
            ]),
            ("COLOR PALETTE",
                (0..<16).map { "palette-\($0)" } +
                (16..<22).map { "palette-\($0)" }
            ),
            ("WINDOW", [
                "window-width", "window-height", "window-padding-x", "window-padding-y",
                "window-padding-balance", "window-decoration"
            ]),
            ("BEHAVIOR", [
                "focus-follows-mouse", "copy-on-select", "mouse-hide-while-typing",
                "bell-features"
            ]),
            ("MACOS", [
                // NOTE: macos-icon intentionally excluded - YEN uses custom bundled icons
                "window-colorspace", "window-vsync", "window-save-state",
                "quick-terminal-position"
            ])
        ]

        for (category, keys) in categories {
            var categoryHasSettings = false

            // Check if this category has any settings
            for key in keys {
                if settings[key] != nil {
                    categoryHasSettings = true
                    break
                }
            }

            guard categoryHasSettings else { continue }

            // Add category header
            lines.append("# " + String(repeating: "=", count: 44))
            lines.append("# \(category)")
            lines.append("# " + String(repeating: "=", count: 44))
            lines.append("")

            // Add settings for this category
            for key in keys {
                if let value = settings[key] {
                    // Special handling for palette to add comments
                    if key.hasPrefix("palette-") {
                        if let index = Int(key.replacingOccurrences(of: "palette-", with: "")) {
                            let comment = paletteComment(for: index)
                            if !comment.isEmpty {
                                lines.append("")
                                lines.append("# \(comment)")
                            }
                        }
                    }
                    // Write empty values as "key = " to reset to default (per YEN config format)
                    if value.isEmpty {
                        lines.append("\(key) =")
                    } else {
                        lines.append("\(key) = \(value)")
                    }
                }
            }
            lines.append("")
        }

        // Footer
        lines.append("# " + String(repeating: "=", count: 44))
        lines.append("# CUSTOMIZATION")
        lines.append("# " + String(repeating: "=", count: 44))
        lines.append("")
        lines.append("# Visit https://yen.chat/docs/configuration for more options")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Palette Comments

    /// Get descriptive comment for palette index
    private func paletteComment(for index: Int) -> String {
        switch index {
        case 0: return "Black"
        case 1: return "Red"
        case 2: return "Green"
        case 3: return "Yellow"
        case 4: return "Blue"
        case 5: return "Magenta"
        case 6: return "Cyan"
        case 7: return "White"
        case 8: return "Bright Black"
        case 9: return "Bright Red"
        case 10: return "Bright Green"
        case 11: return "Bright Yellow"
        case 12: return "Bright Blue"
        case 13: return "Bright Magenta"
        case 14: return "Bright Cyan"
        case 15: return "Bright White"
        case 16: return "Orange spectrum - YEN brand color (#ff5100)"
        default: return ""
        }
    }
}
