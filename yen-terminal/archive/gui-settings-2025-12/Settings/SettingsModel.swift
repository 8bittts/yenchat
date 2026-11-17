import Foundation
import SwiftUI

/// Settings data model with @Published properties
/// Manages all YEN Terminal configuration settings
///
/// IMPORTANT: Default values here MUST match customizations/config.yen
/// This ensures consistency between fresh installs, Settings GUI, and Reset to Defaults.
class SettingsModel: ObservableObject {
    // MARK: - Appearance Settings
    // Values match config.yen: background=#282c34, foreground=#ffffff, opacity=0.9

    @Published var background: String = "#282c34"
    @Published var foreground: String = "#ffffff"
    @Published var backgroundOpacity: Double = 0.9
    @Published var backgroundBlur: Bool = false
    @Published var windowTheme: String = "auto"
    @Published var unfocusedSplitOpacity: Double = 0.7

    // MARK: - Font Settings

    @Published var fontFamily: String = ""
    @Published var fontSize: Int = 13
    @Published var fontFamilyBold: String = ""
    @Published var fontFamilyItalic: String = ""
    @Published var fontThicken: Bool = false
    @Published var fontSyntheticStyle: String = "bold-italic"

    // MARK: - Color Settings
    // Values match config.yen: cursor=#ff5100, selection-background=#ff5100

    @Published var cursorColor: String = "#ff5100"
    @Published var cursorOpacity: Double = 1.0
    @Published var cursorText: String = "#1a1a1a"
    @Published var cursorStyle: String = "block"
    @Published var selectionBackground: String = "#ff5100"
    @Published var selectionForeground: String = "#ffffff"

    // Standard 16-color palette (matches config.yen Gruvbox-inspired palette)
    @Published var palette: [String] = [
        "#1d2021", "#cc241d", "#98971a", "#ff5100",  // 0-3: black, red, green, yellow (brand orange)
        "#458588", "#b16286", "#689d6a", "#a89984",  // 4-7: blue, magenta, cyan, white
        "#7c6f64", "#fb4934", "#b8bb26", "#fabd2f",  // 8-11: bright variants
        "#83a598", "#d3869b", "#8ec07c", "#fbf1c7"   // 12-15: bright variants
    ]

    // Extended colors (orange spectrum for YEN brand)
    @Published var extendedPalette: [String] = [
        "#ff5100", "#ff6622", "#ff7733",
        "#ff8844", "#ff9955", "#ffaa66"
    ]

    // MARK: - Window Settings
    // Values match config.yen: padding-x=8, padding-y=8

    @Published var windowPaddingX: Int = 8
    @Published var windowPaddingY: Int = 8
    @Published var windowPaddingBalance: Bool = false
    @Published var windowWidth: Int = 80
    @Published var windowHeight: Int = 24
    @Published var windowDecoration: Bool = true

    // MARK: - Behavior Settings

    @Published var focusFollowsMouse: Bool = false
    @Published var copyOnSelect: Bool = false
    @Published var mouseHideWhileTyping: Bool = false
    @Published var bellFeatures: String = "system, audio, attention, title"
    
    // MARK: - Bell Features (computed properties for individual toggles)
    
    private var bellFeaturesArray: [String] {
        bellFeatures.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    var bellFeatureSystem: Bool {
        get {
            bellFeaturesArray.contains("system") && !bellFeaturesArray.contains("no-system")
        }
        set {
            updateBellFeature("system", enabled: newValue)
        }
    }
    
    var bellFeatureAudio: Bool {
        get {
            bellFeaturesArray.contains("audio") && !bellFeaturesArray.contains("no-audio")
        }
        set {
            updateBellFeature("audio", enabled: newValue)
        }
    }
    
    var bellFeatureAttention: Bool {
        get {
            bellFeaturesArray.contains("attention") && !bellFeaturesArray.contains("no-attention")
        }
        set {
            updateBellFeature("attention", enabled: newValue)
        }
    }
    
    var bellFeatureTitle: Bool {
        get {
            bellFeaturesArray.contains("title") && !bellFeaturesArray.contains("no-title")
        }
        set {
            updateBellFeature("title", enabled: newValue)
        }
    }
    
    var bellFeatureBorder: Bool {
        get {
            bellFeaturesArray.contains("border") && !bellFeaturesArray.contains("no-border")
        }
        set {
            updateBellFeature("border", enabled: newValue)
        }
    }
    
    private func updateBellFeature(_ feature: String, enabled: Bool) {
        var features = bellFeaturesArray.filter { $0 != feature && $0 != "no-\(feature)" }
        if enabled {
            features.append(feature)
        } else {
            features.append("no-\(feature)")
        }
        bellFeatures = features.joined(separator: ", ")
    }

    // MARK: - macOS Settings
    // NOTE: macos-icon is intentionally NOT included - YEN uses custom bundled icons
    // Setting macos-icon would override our YEN icon with YEN's built-in icons

    @Published var windowColorspace: String = "srgb"
    @Published var windowVSync: Bool = true
    @Published var windowSaveState: String = "default"
    @Published var quickTerminalPosition: String = "top"

    // MARK: - Config Path

    let configPath: String = "~/Library/Application Support/com.yenchat.yen/config.yen"

    private let configManager = ConfigManager.shared

    // MARK: - Load from Config

    func loadFromConfig() {
        let config = configManager.read()

        // Appearance
        background = config["background"] ?? background
        foreground = config["foreground"] ?? foreground
        if let opacity = config["background-opacity"], let value = Double(opacity) {
            backgroundOpacity = value
        }
        // background-blur can be: false, true, or a number (radius)
        // "0", "false", or missing = disabled; "true" or any positive number = enabled
        if let blurValue = config["background-blur"] {
            backgroundBlur = blurValue != "false" && blurValue != "0"
        } else {
            backgroundBlur = false
        }
        windowTheme = config["window-theme"] ?? windowTheme
        if let opacity = config["unfocused-split-opacity"], let value = Double(opacity) {
            unfocusedSplitOpacity = value
        }

        // Fonts
        // Handle empty strings: empty = system default (use default), missing = use default
        if let family = config["font-family"] {
            fontFamily = family  // Empty string is valid (system default)
        }
        if let size = config["font-size"], let value = Int(size) {
            fontSize = value
        }
        if let bold = config["font-family-bold"] {
            fontFamilyBold = bold  // Empty string is valid (same as primary)
        }
        if let italic = config["font-family-italic"] {
            fontFamilyItalic = italic  // Empty string is valid (same as primary)
        }
        fontThicken = config["font-thicken"] == "true"
        fontSyntheticStyle = config["font-synthetic-style"] ?? fontSyntheticStyle

        // Colors
        cursorColor = config["cursor-color"] ?? cursorColor
        if let opacity = config["cursor-opacity"], let value = Double(opacity) {
            cursorOpacity = value
        }
        cursorText = config["cursor-text"] ?? cursorText
        cursorStyle = config["cursor-style"] ?? cursorStyle
        selectionBackground = config["selection-background"] ?? selectionBackground
        selectionForeground = config["selection-foreground"] ?? selectionForeground

        // Palette
        for i in 0..<16 {
            if let color = config["palette-\(i)"] {
                palette[i] = color
            }
        }

        // Extended palette
        for i in 0..<6 {
            if let color = config["palette-\(i + 16)"] {
                extendedPalette[i] = color
            }
        }

        // Window
        if let padding = config["window-padding-x"], let value = Int(padding) {
            windowPaddingX = value
        }
        if let padding = config["window-padding-y"], let value = Int(padding) {
            windowPaddingY = value
        }
        windowPaddingBalance = config["window-padding-balance"] == "true"
        if let width = config["window-width"], let value = Int(width) {
            windowWidth = value
        }
        if let height = config["window-height"], let value = Int(height) {
            windowHeight = value
        }
        windowDecoration = config["window-decoration"] != "false"

        // Behavior
        focusFollowsMouse = config["focus-follows-mouse"] == "true"
        copyOnSelect = config["copy-on-select"] == "true"
        mouseHideWhileTyping = config["mouse-hide-while-typing"] == "true"
        bellFeatures = config["bell-features"] ?? bellFeatures

        // macOS (NOTE: macos-icon intentionally NOT loaded - YEN uses bundled icons)
        windowColorspace = config["window-colorspace"] ?? windowColorspace
        windowVSync = config["window-vsync"] != "false"
        windowSaveState = config["window-save-state"] ?? windowSaveState
        quickTerminalPosition = config["quick-terminal-position"] ?? quickTerminalPosition
    }

    // MARK: - Save to Config

    func saveToConfig() throws {
        var settings: [String: String] = [:]

        // Appearance
        settings["background"] = background
        settings["foreground"] = foreground
        // CRITICAL: Always write background-opacity to clear previous values when resetting to 1.0
        settings["background-opacity"] = String(format: "%.2f", backgroundOpacity)
        // CRITICAL: Always write background-blur to clear previous values when disabling
        if backgroundBlur {
            settings["background-blur"] = "20"
        } else {
            settings["background-blur"] = "false"  // Explicitly disable to clear previous value
        }
        settings["window-theme"] = windowTheme
        settings["unfocused-split-opacity"] = String(format: "%.2f", unfocusedSplitOpacity)

        // Fonts
        // CRITICAL: Write font settings even when empty to clear previous values
        // Empty values reset to system default per YEN config format (key = )
        settings["font-family"] = fontFamily  // Empty string clears to system default
        settings["font-size"] = String(fontSize)
        settings["font-family-bold"] = fontFamilyBold  // Empty string clears to same as primary
        settings["font-family-italic"] = fontFamilyItalic  // Empty string clears to same as primary
        // CRITICAL: Always write font-thicken to clear previous values when disabling
        settings["font-thicken"] = fontThicken ? "true" : "false"
        settings["font-synthetic-style"] = fontSyntheticStyle

        // Colors
        settings["cursor-color"] = cursorColor
        settings["cursor-opacity"] = String(format: "%.2f", cursorOpacity)
        settings["cursor-text"] = cursorText
        settings["cursor-style"] = cursorStyle
        settings["selection-background"] = selectionBackground
        settings["selection-foreground"] = selectionForeground

        // NOTE: Palette colors are not supported in YEN config files
        // They are defined in Config.zig defaults instead
        // Commenting out to avoid "unknown field" errors:
        // for (i, color) in palette.enumerated() {
        //     settings["palette-\(i)"] = color
        // }
        // for (i, color) in extendedPalette.enumerated() {
        //     settings["palette-\(i + 16)"] = color
        // }

        // Window
        settings["window-padding-x"] = String(windowPaddingX)
        settings["window-padding-y"] = String(windowPaddingY)
        // CRITICAL: Always write window-padding-balance to clear previous values
        settings["window-padding-balance"] = windowPaddingBalance ? "true" : "false"
        settings["window-width"] = String(windowWidth)
        settings["window-height"] = String(windowHeight)
        // CRITICAL: Always write window-decoration to clear previous values
        // Note: YEN uses "auto", "system", "none" but our UI uses bool (true = auto, false = none)
        // We map: true -> "auto", false -> "none"
        settings["window-decoration"] = windowDecoration ? "auto" : "none"

        // Behavior
        // CRITICAL: Always write boolean behavior settings to clear previous values
        settings["focus-follows-mouse"] = focusFollowsMouse ? "true" : "false"
        settings["copy-on-select"] = copyOnSelect ? "true" : "false"
        settings["mouse-hide-while-typing"] = mouseHideWhileTyping ? "true" : "false"
        settings["bell-features"] = bellFeatures

        // macOS (NOTE: macos-icon intentionally NOT saved - YEN uses bundled icons)
        settings["window-colorspace"] = windowColorspace
        // CRITICAL: Always write window-vsync to clear previous values
        settings["window-vsync"] = windowVSync ? "true" : "false"
        settings["window-save-state"] = windowSaveState
        settings["quick-terminal-position"] = quickTerminalPosition

        // CRITICAL: Config write failures must propagate to caller
        // This ensures Settings GUI can show error messages to user
        do {
            try configManager.write(settings)
        } catch {
            // Re-throw to allow caller to handle error
            throw error
        }
    }

    // MARK: - Reset to Defaults

    /// Reset all settings to YEN's bundled defaults.
    /// SINGLE SOURCE OF TRUTH: Reads from bundled config.yen, falling back to hardcoded
    /// values only if bundled config cannot be read.
    func resetToDefaults() {
        // Try to load defaults from bundled config.yen (single source of truth)
        if loadBundledConfigDefaults() {
            // Successfully loaded from bundled config
            try? saveToConfig()
            return
        }

        // Fallback: use hardcoded defaults matching bundled config.yen
        // These values MUST match customizations/config.yen exactly
        resetToHardcodedDefaults()
    }

    /// Load defaults from bundled config.yen (YEN.app/Contents/Resources/config.yen)
    /// Returns true if successfully loaded, false if bundled config not available
    private func loadBundledConfigDefaults() -> Bool {
        // Get bundled config path
        let bundledConfigURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("config.yen")

        guard let configText = try? String(contentsOf: bundledConfigURL, encoding: .utf8) else {
            return false
        }

        let config = ConfigManager.shared.parseConfig(configText)

        // Apply bundled config values (with fallbacks matching bundled config.yen)
        background = config["background"] ?? "#282c34"
        foreground = config["foreground"] ?? "#ffffff"
        if let opacity = config["background-opacity"], let value = Double(opacity) {
            backgroundOpacity = value
        } else {
            backgroundOpacity = 0.9
        }
        backgroundBlur = false
        windowTheme = config["window-theme"] ?? "auto"
        unfocusedSplitOpacity = 0.7

        fontFamily = config["font-family"] ?? ""
        if let size = config["font-size"], let value = Int(size) {
            fontSize = value
        } else {
            fontSize = 13
        }
        fontFamilyBold = config["font-family-bold"] ?? ""
        fontFamilyItalic = config["font-family-italic"] ?? ""
        fontThicken = config["font-thicken"] == "true"
        fontSyntheticStyle = config["font-synthetic-style"] ?? "bold-italic"

        cursorColor = config["cursor-color"] ?? "#ff5100"
        if let opacity = config["cursor-opacity"], let value = Double(opacity) {
            cursorOpacity = value
        } else {
            cursorOpacity = 1.0
        }
        cursorText = config["cursor-text"] ?? "#1a1a1a"
        cursorStyle = config["cursor-style"] ?? "block"
        selectionBackground = config["selection-background"] ?? "#ff5100"
        selectionForeground = config["selection-foreground"] ?? "#ffffff"

        if let padding = config["window-padding-x"], let value = Int(padding) {
            windowPaddingX = value
        } else {
            windowPaddingX = 8
        }
        if let padding = config["window-padding-y"], let value = Int(padding) {
            windowPaddingY = value
        } else {
            windowPaddingY = 8
        }
        windowPaddingBalance = config["window-padding-balance"] == "true"
        if let width = config["window-width"], let value = Int(width) {
            windowWidth = value
        } else {
            windowWidth = 80
        }
        if let height = config["window-height"], let value = Int(height) {
            windowHeight = value
        } else {
            windowHeight = 24
        }
        windowDecoration = config["window-decoration"] != "false"

        focusFollowsMouse = config["focus-follows-mouse"] == "true"
        copyOnSelect = config["copy-on-select"] == "true"
        mouseHideWhileTyping = config["mouse-hide-while-typing"] == "true"
        bellFeatures = config["bell-features"] ?? "system, audio, attention, title"

        windowColorspace = config["window-colorspace"] ?? "srgb"
        windowVSync = config["window-vsync"] != "false"
        windowSaveState = config["window-save-state"] ?? "default"
        quickTerminalPosition = config["quick-terminal-position"] ?? "top"

        return true
    }

    /// Fallback: Reset using hardcoded defaults that MUST match bundled config.yen
    /// This is only used if bundled config.yen cannot be read.
    private func resetToHardcodedDefaults() {
        // IMPORTANT: These values MUST match customizations/config.yen exactly!
        // If you change these, also update config.yen to keep them in sync.
        background = "#282c34"
        foreground = "#ffffff"
        backgroundOpacity = 0.9
        backgroundBlur = false
        windowTheme = "auto"
        unfocusedSplitOpacity = 0.7

        fontFamily = ""
        fontSize = 13
        fontFamilyBold = ""
        fontFamilyItalic = ""
        fontThicken = false
        fontSyntheticStyle = "bold-italic"

        cursorColor = "#ff5100"  // YEN brand orange
        cursorOpacity = 1.0
        cursorText = "#1a1a1a"
        cursorStyle = "block"
        selectionBackground = "#ff5100"  // YEN brand orange
        selectionForeground = "#ffffff"

        windowPaddingX = 8
        windowPaddingY = 8
        windowPaddingBalance = false
        windowWidth = 80
        windowHeight = 24
        windowDecoration = true

        focusFollowsMouse = false
        copyOnSelect = false
        mouseHideWhileTyping = false
        bellFeatures = "system, audio, attention, title"

        windowColorspace = "srgb"
        windowVSync = true
        windowSaveState = "default"
        quickTerminalPosition = "top"

        try? saveToConfig()
    }

    // MARK: - Export for Cloud Sync

    /// Convert current settings to dictionary for cloud sync
    /// Used by CloudSyncService to upload settings to YEN cloud
    func toDict() -> [String: String] {
        var dict: [String: String] = [:]

        // Appearance
        dict["background"] = background
        dict["foreground"] = foreground
        dict["background-opacity"] = String(format: "%.2f", backgroundOpacity)
        dict["background-blur"] = backgroundBlur ? "20" : "false"
        dict["window-theme"] = windowTheme
        dict["unfocused-split-opacity"] = String(format: "%.2f", unfocusedSplitOpacity)

        // Fonts
        dict["font-family"] = fontFamily
        dict["font-size"] = String(fontSize)
        dict["font-family-bold"] = fontFamilyBold
        dict["font-family-italic"] = fontFamilyItalic
        dict["font-thicken"] = fontThicken ? "true" : "false"
        dict["font-synthetic-style"] = fontSyntheticStyle

        // Colors
        dict["cursor-color"] = cursorColor
        dict["cursor-opacity"] = String(format: "%.2f", cursorOpacity)
        dict["cursor-text"] = cursorText
        dict["cursor-style"] = cursorStyle
        dict["selection-background"] = selectionBackground
        dict["selection-foreground"] = selectionForeground

        // Window
        dict["window-padding-x"] = String(windowPaddingX)
        dict["window-padding-y"] = String(windowPaddingY)
        dict["window-padding-balance"] = windowPaddingBalance ? "true" : "false"
        dict["window-width"] = String(windowWidth)
        dict["window-height"] = String(windowHeight)
        dict["window-decoration"] = windowDecoration ? "auto" : "none"

        // Behavior
        dict["focus-follows-mouse"] = focusFollowsMouse ? "true" : "false"
        dict["copy-on-select"] = copyOnSelect ? "true" : "false"
        dict["mouse-hide-while-typing"] = mouseHideWhileTyping ? "true" : "false"
        dict["bell-features"] = bellFeatures

        // macOS
        dict["window-colorspace"] = windowColorspace
        dict["window-vsync"] = windowVSync ? "true" : "false"
        dict["window-save-state"] = windowSaveState
        dict["quick-terminal-position"] = quickTerminalPosition

        return dict
    }
}
