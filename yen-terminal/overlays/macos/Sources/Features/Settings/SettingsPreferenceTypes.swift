#if os(macOS)
import Foundation
import Cocoa
import SwiftUI
import UserNotifications
#if canImport(Translation)
import Translation
#endif

enum DictationTranslationPreferences {
    static let enabledPreferenceKey = "com.yenchat.yen.translateOnDictateEnabled"
    static let targetLanguagePreferenceKey = "com.yenchat.yen.dictationTranslateTargetLanguage"

    static var translateOnDictateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledPreferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledPreferenceKey) }
    }

    static var targetLanguageIdentifier: String {
        get {
            let raw = UserDefaults.standard.string(forKey: targetLanguagePreferenceKey)
            return normalizeLanguageIdentifier(raw)
        }
        set {
            UserDefaults.standard.set(
                normalizeLanguageIdentifier(newValue),
                forKey: targetLanguagePreferenceKey
            )
        }
    }

    static var preferredTargetLanguageIdentifier: String {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return normalizeLanguageIdentifier(preferred)
    }

    static func normalizeLanguageIdentifier(_ rawValue: String?) -> String {
        let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return fallbackLanguageIdentifier()
        }

        let minimal = Locale.Language(identifier: raw).minimalIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if minimal.isEmpty {
            return fallbackLanguageIdentifier()
        }
        return minimal
    }

    static func isSameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLeft = normalizeLanguageIdentifier(lhs)
        let normalizedRight = normalizeLanguageIdentifier(rhs)
        guard let left = languageIdentity(for: normalizedLeft),
              let right = languageIdentity(for: normalizedRight) else {
            return false
        }
        guard left.languageCode == right.languageCode else { return false }

        let leftScript = left.effectiveScript(
            maximalIdentifier: Locale.Language(identifier: normalizedLeft).maximalIdentifier
        )
        let rightScript = right.effectiveScript(
            maximalIdentifier: Locale.Language(identifier: normalizedRight).maximalIdentifier
        )
        if let leftScript, let rightScript, leftScript != rightScript {
            return false
        }
        return true
    }

    static func validatedTargetIdentifier(
        currentIdentifier: String,
        supportedIdentifiers: [String],
        preferredIdentifier: String
    ) -> String {
        let supported = supportedIdentifiers.compactMap(sanitizeSupportedIdentifier)
        guard !supported.isEmpty else {
            return normalizeLanguageIdentifier(currentIdentifier)
        }

        let normalizedSupported = supported.map(normalizeLanguageIdentifier)

        let normalizedCurrent = normalizeLanguageIdentifier(currentIdentifier)
        if let exactCurrentIndex = normalizedSupported.firstIndex(of: normalizedCurrent) {
            return supported[exactCurrentIndex]
        }

        if let languageMatchIndex = normalizedSupported.firstIndex(where: {
            isSameLanguage($0, normalizedCurrent)
        }) {
            return supported[languageMatchIndex]
        }

        let normalizedPreferred = normalizeLanguageIdentifier(preferredIdentifier)
        if let exactPreferredIndex = normalizedSupported.firstIndex(of: normalizedPreferred) {
            return supported[exactPreferredIndex]
        }

        if let languageMatchIndex = normalizedSupported.firstIndex(where: {
            isSameLanguage($0, normalizedPreferred)
        }) {
            return supported[languageMatchIndex]
        }

        return supported[0]
    }

    private static func sanitizeSupportedIdentifier(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "_", with: "-")
    }

    private struct LanguageIdentity {
        let languageCode: String
        let scriptCode: String?

        func effectiveScript(maximalIdentifier: String) -> String? {
            if let scriptCode {
                return scriptCode
            }
            let maximalComponents = Locale.Components(
                identifier: maximalIdentifier.replacingOccurrences(of: "-", with: "_")
            )
            return maximalComponents.languageComponents.script?.identifier.lowercased()
        }
    }

    private static func languageIdentity(for identifier: String) -> LanguageIdentity? {
        let components = Locale.Components(
            identifier: identifier.replacingOccurrences(of: "-", with: "_")
        )
        guard let languageCode = components.languageComponents.languageCode?.identifier.lowercased(),
              !languageCode.isEmpty else {
            return nil
        }
        let scriptCode = components.languageComponents.script?.identifier.lowercased()
        return LanguageIdentity(
            languageCode: languageCode,
            scriptCode: scriptCode
        )
    }

    private static func fallbackLanguageIdentifier() -> String {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let minimal = Locale.Language(identifier: preferred).minimalIdentifier
        if minimal.isEmpty {
            return "en"
        }
        return minimal
    }
}

enum WindowBorderPalette: String, CaseIterable {
    case sunrise
    case ember
    case aurora
    case ocean
    case graphite

    var displayName: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .ember: return "Ember"
        case .aurora: return "Aurora"
        case .ocean: return "Ocean"
        case .graphite: return "Graphite"
        }
    }

    var startHex: String {
        switch self {
        case .sunrise: return "#FF6A00"
        case .ember: return "#FF3B30"
        case .aurora: return "#22C55E"
        case .ocean: return "#0EA5E9"
        case .graphite: return "#6B7280"
        }
    }

    var endHex: String {
        switch self {
        case .sunrise: return "#FFD60A"
        case .ember: return "#FF9500"
        case .aurora: return "#06B6D4"
        case .ocean: return "#6366F1"
        case .graphite: return "#9CA3AF"
        }
    }

    // Convenience Color values for overlay usage. Prefer these instead of parsing hex at call sites.
    var startColor: Color { Color(hex: startHex) ?? .accentColor }
    var endColor: Color { Color(hex: endHex) ?? .accentColor }

    static var defaultFocused: WindowBorderPalette { .sunrise }
    static var defaultUnfocused: WindowBorderPalette { .graphite }

    static func normalized(rawValue: String, fallback: WindowBorderPalette) -> WindowBorderPalette {
        WindowBorderPalette(rawValue: rawValue) ?? fallback
    }
}

enum WindowBorderColorMode: String, CaseIterable {
    case manual
    case matchTheme = "match-theme"

    var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .matchTheme: return "Match Theme"
        }
    }

    static func normalized(rawValue: String, fallback: WindowBorderColorMode) -> WindowBorderColorMode {
        WindowBorderColorMode(rawValue: rawValue) ?? fallback
    }
}

enum WindowBorderScope: String, CaseIterable {
    case window
    case focusedSplit = "focused-split"

    var displayName: String {
        switch self {
        case .window: return "Window"
        case .focusedSplit: return "Focused Split"
        }
    }

    static func normalized(rawValue: String, fallback: WindowBorderScope) -> WindowBorderScope {
        WindowBorderScope(rawValue: rawValue) ?? fallback
    }
}

enum BackgroundImageScope: String, CaseIterable {
    case eachSplit = "each-split"
    case wholeWindow = "whole-window"

    var displayName: String {
        switch self {
        case .eachSplit: return "Each Split"
        case .wholeWindow: return "Whole Window"
        }
    }

    static func normalized(rawValue: String?, fallback: BackgroundImageScope) -> BackgroundImageScope {
        guard let rawValue else { return fallback }
        return BackgroundImageScope(rawValue: rawValue) ?? fallback
    }
}

enum BackgroundImageScopePreferences {
    static let preferenceKey = "com.yenchat.yen.backgroundImage.scope"
    static let defaultScope: BackgroundImageScope = .eachSplit

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            preferenceKey: defaultScope.rawValue,
        ])
    }

    static func scope(from defaults: UserDefaults = .standard) -> BackgroundImageScope {
        BackgroundImageScope.normalized(
            rawValue: defaults.string(forKey: preferenceKey),
            fallback: defaultScope
        )
    }
}

struct WindowBorderGradient: Equatable {
    let startColor: Color
    let endColor: Color

    static func == (lhs: WindowBorderGradient, rhs: WindowBorderGradient) -> Bool {
        componentsEqual(rgbaTuple(lhs.startColor), rgbaTuple(rhs.startColor))
            && componentsEqual(rgbaTuple(lhs.endColor), rgbaTuple(rhs.endColor))
    }

    private static func rgbaTuple(_ color: Color) -> (Int, Int, Int, Int)? {
        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
        return (
            Int(round(nsColor.redComponent * 255.0)),
            Int(round(nsColor.greenComponent * 255.0)),
            Int(round(nsColor.blueComponent * 255.0)),
            Int(round(nsColor.alphaComponent * 255.0))
        )
    }

    private static func componentsEqual(
        _ lhs: (Int, Int, Int, Int)?,
        _ rhs: (Int, Int, Int, Int)?
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return lhs.0 == rhs.0
                && lhs.1 == rhs.1
                && lhs.2 == rhs.2
                && lhs.3 == rhs.3
        case (.none, .none):
            return true
        default:
            return false
        }
    }
}

/// How fast the aura pulses.
enum WindowBorderAuraPulse: String, CaseIterable, Identifiable {
    case slow
    case medium
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .medium: return "Medium"
        case .fast: return "Fast"
        }
    }

    /// Seconds from the dim end of a pulse to the bright end.
    var halfPeriod: Double {
        switch self {
        case .slow: return 3.0
        case .medium: return 1.8
        case .fast: return 0.9
        }
    }

    static func normalized(rawValue: String, fallback: WindowBorderAuraPulse) -> WindowBorderAuraPulse {
        WindowBorderAuraPulse(rawValue: rawValue) ?? fallback
    }
}

/// How fast the spark travels around the outline.
enum WindowBorderSparkSpeed: String, CaseIterable, Identifiable {
    case superSlow
    case slow
    case medium
    case fast
    case superFast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .superSlow: return "Super Slow"
        case .slow: return "Slow"
        case .medium: return "Medium"
        case .fast: return "Fast"
        case .superFast: return "Super Fast"
        }
    }

    /// The spark's speed relative to Medium. Each step is about 1.6 times the
    /// one before it, so every step reads as a clear change.
    var multiplier: Double {
        switch self {
        case .superSlow: return 0.4
        case .slow: return 0.63
        case .medium: return 1
        case .fast: return 1.6
        case .superFast: return 2.5
        }
    }

    static func normalized(rawValue: String, fallback: WindowBorderSparkSpeed) -> WindowBorderSparkSpeed {
        WindowBorderSparkSpeed(rawValue: rawValue) ?? fallback
    }
}

/// The animated effects an outline can carry on top of its stroke.
struct WindowBorderEffects: Equatable {
    /// A light that travels around the outline.
    var sparkEnabled: Bool
    /// A glow in `auraColorHex` that pulses around the outline.
    var auraEnabled: Bool
    /// `#RRGGBB`, in sRGB.
    var auraColorHex: String
    var auraPulse: WindowBorderAuraPulse = .medium
    var sparkSpeed: WindowBorderSparkSpeed = .medium

    static let none = WindowBorderEffects(
        sparkEnabled: false,
        auraEnabled: false,
        auraColorHex: WindowBorderPreferences.defaultAuraColorHex
    )

    var auraColor: Color {
        Color(hex: auraColorHex) ?? .yenBrand
    }
}

struct WindowBorderPreferenceState: Equatable {
    var enabled: Bool
    var scope: WindowBorderScope
    var width: Double
    var radius: Double
    var colorMode: WindowBorderColorMode
    var focusedPalette: WindowBorderPalette
    var unfocusedPalette: WindowBorderPalette
    var effects: WindowBorderEffects = .none
}

enum WindowBorderPreferences {
    static let enabledPreferenceKey = "com.yenchat.yen.windowBorder.enabled"
    static let scopePreferenceKey = "com.yenchat.yen.windowBorder.scope"
    static let widthPreferenceKey = "com.yenchat.yen.windowBorder.width"
    static let radiusPreferenceKey = "com.yenchat.yen.windowBorder.radius"
    static let colorModePreferenceKey = "com.yenchat.yen.windowBorder.colorMode"
    static let focusedPalettePreferenceKey = "com.yenchat.yen.windowBorder.focusedPalette"
    static let unfocusedPalettePreferenceKey = "com.yenchat.yen.windowBorder.unfocusedPalette"
    static let sparkPreferenceKey = "com.yenchat.yen.windowBorder.spark"
    static let auraPreferenceKey = "com.yenchat.yen.windowBorder.aura"
    static let auraColorPreferenceKey = "com.yenchat.yen.windowBorder.auraColor"
    static let auraPulsePreferenceKey = "com.yenchat.yen.windowBorder.auraPulse"
    static let sparkSpeedPreferenceKey = "com.yenchat.yen.windowBorder.sparkSpeed"
    /// The brand orange, `Color.yenBrand`.
    static let defaultAuraColorHex = "#FF5100"
    static let widthRange: ClosedRange<Double> = 1.0...8.0
    static let radiusRange: ClosedRange<Double> = 1.0...24.0
    static let widthStep = 0.5
    static let radiusStep = 1.0

    static let defaultState = WindowBorderPreferenceState(
        enabled: false,
        scope: .window,
        width: 2.0,
        radius: 10.0,
        colorMode: .manual,
        focusedPalette: .defaultFocused,
        unfocusedPalette: .defaultUnfocused
    )

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledPreferenceKey: defaultState.enabled,
            scopePreferenceKey: defaultState.scope.rawValue,
            widthPreferenceKey: defaultState.width,
            radiusPreferenceKey: defaultState.radius,
            colorModePreferenceKey: defaultState.colorMode.rawValue,
            focusedPalettePreferenceKey: defaultState.focusedPalette.rawValue,
            unfocusedPalettePreferenceKey: defaultState.unfocusedPalette.rawValue,
            sparkPreferenceKey: defaultState.effects.sparkEnabled,
            auraPreferenceKey: defaultState.effects.auraEnabled,
            auraColorPreferenceKey: defaultState.effects.auraColorHex,
            auraPulsePreferenceKey: defaultState.effects.auraPulse.rawValue,
            sparkSpeedPreferenceKey: defaultState.effects.sparkSpeed.rawValue,
        ])
    }

    static func state(from defaults: UserDefaults = .standard) -> WindowBorderPreferenceState {
        let scopeRaw = defaults.string(forKey: scopePreferenceKey) ?? defaultState.scope.rawValue
        let colorModeRaw = defaults.string(forKey: colorModePreferenceKey) ?? defaultState.colorMode.rawValue
        let focusedRaw = defaults.string(forKey: focusedPalettePreferenceKey) ?? defaultState.focusedPalette.rawValue
        let unfocusedRaw = defaults.string(forKey: unfocusedPalettePreferenceKey) ?? defaultState.unfocusedPalette.rawValue
        return WindowBorderPreferenceState(
            enabled: defaults.bool(forKey: enabledPreferenceKey),
            scope: WindowBorderScope.normalized(rawValue: scopeRaw, fallback: defaultState.scope),
            width: normalizedWidth(defaults.double(forKey: widthPreferenceKey)),
            radius: normalizedRadius(defaults.double(forKey: radiusPreferenceKey)),
            colorMode: WindowBorderColorMode.normalized(rawValue: colorModeRaw, fallback: defaultState.colorMode),
            focusedPalette: WindowBorderPalette.normalized(rawValue: focusedRaw, fallback: defaultState.focusedPalette),
            unfocusedPalette: WindowBorderPalette.normalized(rawValue: unfocusedRaw, fallback: defaultState.unfocusedPalette),
            effects: WindowBorderEffects(
                sparkEnabled: defaults.bool(forKey: sparkPreferenceKey),
                auraEnabled: defaults.bool(forKey: auraPreferenceKey),
                auraColorHex: normalizedAuraColorHex(defaults.string(forKey: auraColorPreferenceKey) ?? ""),
                auraPulse: WindowBorderAuraPulse.normalized(
                    rawValue: defaults.string(forKey: auraPulsePreferenceKey) ?? "",
                    fallback: defaultState.effects.auraPulse
                ),
                sparkSpeed: WindowBorderSparkSpeed.normalized(
                    rawValue: defaults.string(forKey: sparkSpeedPreferenceKey) ?? "",
                    fallback: defaultState.effects.sparkSpeed
                )
            )
        )
    }

    /// `#RRGGBB` in capitals, or the default when the value is not a color.
    static func normalizedAuraColorHex(_ value: String) -> String {
        var digits = value.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return defaultAuraColorHex }
        return "#" + digits.uppercased()
    }

    /// The sRGB `#RRGGBB` value of a picked color; opacity is dropped.
    static func auraColorHex(from color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return defaultAuraColorHex }
        func channel(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X",
            channel(rgb.redComponent),
            channel(rgb.greenComponent),
            channel(rgb.blueComponent)
        )
    }

    static func clampedWidth(_ value: Double) -> Double {
        min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }

    static func clampedRadius(_ value: Double) -> Double {
        min(max(value, radiusRange.lowerBound), radiusRange.upperBound)
    }

    static func normalizedWidth(_ value: Double) -> Double {
        normalizedSteppedValue(
            value,
            range: widthRange,
            step: widthStep,
            fallback: defaultState.width
        )
    }

    static func normalizedRadius(_ value: Double) -> Double {
        normalizedSteppedValue(
            value,
            range: radiusRange,
            step: radiusStep,
            fallback: defaultState.radius
        )
    }

    static func normalizedState(_ state: WindowBorderPreferenceState) -> WindowBorderPreferenceState {
        WindowBorderPreferenceState(
            enabled: state.enabled,
            scope: state.scope,
            width: normalizedWidth(state.width),
            radius: normalizedRadius(state.radius),
            colorMode: state.colorMode,
            focusedPalette: state.focusedPalette,
            unfocusedPalette: state.unfocusedPalette,
            effects: WindowBorderEffects(
                sparkEnabled: state.effects.sparkEnabled,
                auraEnabled: state.effects.auraEnabled,
                auraColorHex: normalizedAuraColorHex(state.effects.auraColorHex),
                auraPulse: state.effects.auraPulse,
                sparkSpeed: state.effects.sparkSpeed
            )
        )
    }

    private static func normalizedSteppedValue(
        _ value: Double,
        range: ClosedRange<Double>,
        step: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let normalized = (clamped / step).rounded(.toNearestOrAwayFromZero) * step
        let scale = max(1, Int((1 / step).rounded()))
        return (normalized * Double(scale)).rounded() / Double(scale)
    }
}

struct WorkspacePreferenceState: Equatable {
    var tabSidebarEnabled: Bool
    var tabSidebarPresentationMode: TabSidebarPresentationMode
    var tabSidebarPersistentVisible: Bool
    var paneStyle: PaneStyle = .comfortable
    var splitPaneLabelsEnabled: Bool
    var splitPaneWorktreeNamingEnabled: Bool
    var browserTerminalLinkCaptureEnabled: Bool
    var browserSplitEnabled: Bool
    var scratchpadEnabled: Bool
    var backgroundImageScope: BackgroundImageScope
}

enum TabSidebarPreferences {
    static let enabledPreferenceKey = TabSidebarController.tabSidebarEnabledPreferenceKey
    static let presentationModePreferenceKey = TabSidebarController.presentationModePreferenceKey
    static let persistentVisiblePreferenceKey = TabSidebarController.persistentVisiblePreferenceKey

    static let defaultEnabled = true
    static let defaultPresentationMode = TabSidebarPresentationMode.transient
    static let defaultPersistentVisible = true

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledPreferenceKey: defaultEnabled,
            presentationModePreferenceKey: defaultPresentationMode.rawValue,
            persistentVisiblePreferenceKey: defaultPersistentVisible,
        ])
    }

    static func enabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledPreferenceKey) as? Bool ?? defaultEnabled
    }

    static func normalizedPresentationMode(rawValue: String?) -> TabSidebarPresentationMode? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return TabSidebarPresentationMode(rawValue: trimmed)
    }

    static func presentationMode(from defaults: UserDefaults = .standard) -> TabSidebarPresentationMode {
        normalizedPresentationMode(rawValue: defaults.string(forKey: presentationModePreferenceKey))
            ?? defaultPresentationMode
    }

    static func repairedPresentationMode(in defaults: UserDefaults = .standard) -> TabSidebarPresentationMode {
        let mode = presentationMode(from: defaults)
        defaults.set(mode.rawValue, forKey: presentationModePreferenceKey)
        return mode
    }

    static func persistentVisible(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: persistentVisiblePreferenceKey) as? Bool ?? defaultPersistentVisible
    }
}

enum PaneStyle: String {
    case comfortable
    case compact

    static let preferenceKey = "com.yenchat.yen.paneStyle"

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .comfortable
    }
}

enum SplitPaneLabelsPreferences {
    static let enabledPreferenceKey = "com.yenchat.yen.splitPaneLabelsEnabled"
    static let worktreeNamingEnabledPreferenceKey = "com.yenchat.yen.splitPaneLabelsWorktreeNamingEnabled"
    static let defaultEnabled = true
    static let defaultWorktreeNamingEnabled = false

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledPreferenceKey: defaultEnabled,
            worktreeNamingEnabledPreferenceKey: defaultWorktreeNamingEnabled,
        ])
    }

    static func enabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledPreferenceKey) as? Bool ?? defaultEnabled
    }

    static func worktreeNamingEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: worktreeNamingEnabledPreferenceKey) as? Bool
            ?? defaultWorktreeNamingEnabled
    }
}

enum NativeBrowserPreferences {
    static let terminalLinkCaptureEnabledPreferenceKey =
        "com.yenchat.yen.browser.terminalLinkCaptureEnabled"
    static let browserSplitEnabledPreferenceKey =
        "com.yenchat.yen.browser.splitEnabled"

    static let defaultTerminalLinkCaptureEnabled = false
    static let defaultBrowserSplitEnabled = false

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            terminalLinkCaptureEnabledPreferenceKey: defaultTerminalLinkCaptureEnabled,
            browserSplitEnabledPreferenceKey: defaultBrowserSplitEnabled,
        ])
    }

    static func terminalLinkCaptureEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: terminalLinkCaptureEnabledPreferenceKey) as? Bool
            ?? defaultTerminalLinkCaptureEnabled
    }

    static func terminalLinkCaptureEnabled() -> Bool {
        terminalLinkCaptureEnabled(from: .standard)
    }

    static func browserSplitEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: browserSplitEnabledPreferenceKey) as? Bool
            ?? defaultBrowserSplitEnabled
    }

    static func browserSplitEnabled() -> Bool {
        browserSplitEnabled(from: .standard)
    }
}

enum WindowBorderThemeContrast {
    static let minimumFocusedContrastRatio: Double = 1.8
    static let minimumUnfocusedContrastRatio: Double = 1.2
    static let minimumFocusedGradientDistance: Double = 0.14
    static let unfocusedStartOpacity: Double = 0.68
    static let unfocusedEndOpacity: Double = 0.5
}

struct DictationTranslationLanguageOption: Identifiable, Equatable {
    let identifier: String
    let displayName: String

    var id: String { identifier }
}

enum SettingsStatusSeverity: Equatable {
    case success
    case info
    case warning
    case error
}

@MainActor
final class SettingsRuntimeStatusStore: ObservableObject {
    @Published var accessibilityGranted: Bool = false
    @Published var microphoneGranted: Bool = false
    @Published var speechRecognitionGranted: Bool = false
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var dictationLocalServiceIssueDetail: String = ""
}

enum DictationTranslationLanguageCatalog {
    static func supportedLanguageOptions(
        sourceLocaleIdentifier: String = Locale.current.identifier
    ) async -> [DictationTranslationLanguageOption] {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let availability = LanguageAvailability()
            let supportedLanguages = await availability.supportedLanguages
            return await compatibleLanguageOptions(
                sourceLocaleIdentifier: sourceLocaleIdentifier,
                supportedLanguageIdentifiers: supportedLanguages.map(\.minimalIdentifier)
            ) { source, target in
                let status = await availability.status(from: source, to: target)
                switch status {
                case .installed:
                    return .installed
                case .supported:
                    return .supported
                case .unsupported:
                    return .unsupported
                @unknown default:
                    return .unsupported
                }
            }
        }
        #endif

        return []
    }

    static func compatibleLanguageOptions(
        sourceLocaleIdentifier: String,
        supportedLanguageIdentifiers: [String],
        availability: @escaping (Locale.Language, Locale.Language) async -> DictationTranslationAvailability
    ) async -> [DictationTranslationLanguageOption] {
        let normalizedSource = DictationTranslationPreferences.normalizeLanguageIdentifier(
            sourceLocaleIdentifier
        )
        let sourceLanguage = Locale.Language(identifier: normalizedSource)

        var uniqueByIdentifier: [String: DictationTranslationLanguageOption] = [:]
        for rawIdentifier in supportedLanguageIdentifiers {
            guard let identifier = normalizedSupportedIdentifier(rawIdentifier) else { continue }
            guard !DictationTranslationPreferences.isSameLanguage(identifier, normalizedSource) else {
                continue
            }

            let targetLanguage = Locale.Language(identifier: identifier)
            let status = await availability(sourceLanguage, targetLanguage)
            guard status != .unsupported else { continue }

            if uniqueByIdentifier[identifier] == nil {
                uniqueByIdentifier[identifier] = option(for: identifier)
            }
        }

        return uniqueByIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func option(for identifier: String) -> DictationTranslationLanguageOption {
        let normalized = DictationTranslationPreferences.normalizeLanguageIdentifier(identifier)
        let language = Locale.Language(identifier: normalized)
        let displayName =
            Locale.current.localizedString(forIdentifier: language.maximalIdentifier)
            ?? Locale.current.localizedString(forIdentifier: normalized)
            ?? normalized

        return DictationTranslationLanguageOption(
            identifier: normalized,
            displayName: displayName
        )
    }

    private static func normalizedSupportedIdentifier(_ rawIdentifier: String) -> String? {
        let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = Locale.Language(identifier: trimmed).minimalIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }
}

#endif
