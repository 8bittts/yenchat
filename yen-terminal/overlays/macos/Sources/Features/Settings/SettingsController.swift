#if os(macOS)
import Foundation
import Cocoa
import SwiftUI
import CoreText
import ServiceManagement
import UniformTypeIdentifiers
import UserNotifications
import YENKit
#if canImport(Translation)
import Translation
#endif

/// Native settings panel controller for YEN Terminal.
/// Replaces the Go TUI with a SwiftUI panel triggered by Cmd+,.
@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate, ObservableObject, PermissionRefreshing {
    static let shared = SettingsController()
    private static var cachedMonospaceFonts: [String]?
    nonisolated private static let commonTerminalFonts = [
        "JetBrains Mono",
        "SF Mono",
        "Menlo",
        "Monaco",
        "Courier New",
        "Fira Code",
        "Source Code Pro",
        "Cascadia Code",
        "IBM Plex Mono",
        "Hack",
        "Inconsolata"
    ]
    private static let defaultFontFamily = "JetBrains Mono"
    private static let defaultFontSize = 14.0
    private static let defaultCursorStyle = "block"
    private static let defaultCursorBlink = true
    private static let defaultCopyOnSelect = true
    private static let defaultScrollbarVisibility = "system"
    private static let defaultNotifyOnCommandFinish = "never"
    private static let defaultNotifyOnCommandFinishActionBell = true
    private static let defaultNotifyOnCommandFinishActionNotify = false
    private static let defaultNotifyOnCommandFinishAfterSeconds = 5
    private static let defaultWindowPaddingX = 2
    private static let defaultWindowPaddingY = 2
    private static let defaultShellIntegrationFeatures = "no-cursor"
    private static let defaultBackgroundOpacity = 1.0
    private static let minBackgroundOpacity = 0.1
    private static let maxBackgroundOpacity = 1.0
    private static let themeReloadMinimumIntervalSeconds: CFAbsoluteTime = 12.0
    nonisolated(unsafe) private static var testConfigPathOverride: String?
    nonisolated private static let wholeWindowBackgroundRuntimeConfigFilename =
        ".yen-whole-window-background-runtime.yen"
    nonisolated private static func defaultConfigPath() -> String {
        if let override = testConfigPathOverride {
            return override
        }
        return resolveConfigPath(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    // `YEN_CONFIG_PATH` is the file the terminal itself loads (AppDelegate hands it
    // to `YEN.App`), so the Settings panel must read and write that same file.
    // The xcodebuild test plan sets it to a /tmp path; without this the test host
    // persisted its in-memory defaults into the operator's real config.yen on
    // every release build.
    nonisolated static func resolveConfigPath(
        environment: [String: String],
        homeDirectory: String
    ) -> String {
        if let envPath = environment["YEN_CONFIG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !envPath.isEmpty
        {
            return envPath
        }
        return "\(homeDirectory)/Library/Application Support/com.yenchat.yen/config.yen"
    }
    nonisolated private static func wholeWindowBackgroundRuntimeConfigPath(
        for configPath: String
    ) -> String {
        let configDirectory = (configPath as NSString).deletingLastPathComponent
        return (configDirectory as NSString).appendingPathComponent(
            wholeWindowBackgroundRuntimeConfigFilename
        )
    }
    nonisolated private static func removeWholeWindowBackgroundRuntimeConfigIfPresent(
        at path: String
    ) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
    private static func activeConfigLine(_ line: String) -> String? {
        ManagedConfigDocument.activeConfigLine(line)
    }

    private static func configEntry(from line: String) -> ManagedConfigDocument.Entry? {
        ManagedConfigDocument.entry(from: line)
    }

    private static func configKey(from line: String) -> String? {
        ManagedConfigDocument.key(from: line)
    }
    private let dictationTranslationAssetPreparer = DictationTranslationAssetPreparer()
    private lazy var layoutApplier = SettingsLayoutApplier(showStatus: { [weak self] message, severity, duration, window in
        self?.showLayoutStatus(message, severity: severity, duration: duration, targetWindow: window)
    })
    private let presentationCoordinator = SettingsPresentationCoordinator()
    let runtimeStatus = SettingsRuntimeStatusStore()

    private enum SettingsNotificationTopic: Hashable {
        case terminalPresentation
        case splitPaneLabel
        case workspace
        case themes
        case general
        case keyboard
        case sounds

        func post(from controller: SettingsController) {
            switch self {
            case .terminalPresentation:
                NotificationCenter.default.post(
                    name: .yenTerminalPresentationSettingsDidChange,
                    object: controller
                )
            case .splitPaneLabel:
                NotificationCenter.default.post(
                    name: .yenSplitPaneLabelSettingsDidChange,
                    object: controller
                )
            case .workspace:
                NotificationCenter.default.post(
                    name: .yenWorkspaceSettingsDidChange,
                    object: controller
                )
            case .themes:
                NotificationCenter.default.post(name: .yenThemesSettingsDidChange, object: controller)
            case .general:
                NotificationCenter.default.post(name: .yenGeneralSettingsDidChange, object: controller)
            case .keyboard:
                NotificationCenter.default.post(name: .yenKeyboardSettingsDidChange, object: controller)
            case .sounds:
                NotificationCenter.default.post(name: .yenSoundsSettingsDidChange, object: controller)
            }
        }
    }

    private var settingsNotificationCoalescingDepth = 0
    private var pendingSettingsNotificationTopics: [SettingsNotificationTopic] = []
    private var pendingSettingsNotificationTopicSet: Set<SettingsNotificationTopic> = []

    // MARK: - Property Canonicalization

    /// Re-normalizes a `@Published` setting in place from its own `didSet`. Returns `true` when
    /// the value was off-canonical and has been rewritten — the caller must then `return` so the
    /// re-entrant `didSet` (fired by the keyPath write below) runs the sync/notify tail exactly
    /// once after the value reaches a fixed point. This preserves the hand-written
    /// `let n = normalize(x); if n != x { x = n; return }` shape (same stored-property write,
    /// same re-entry, same equality gate). `normalize` must converge; some path cleanup inputs
    /// intentionally require more than one pass.
    @discardableResult
    private func canonicalizeIfNeeded<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<SettingsController, T>,
        normalize: (T) -> T
    ) -> Bool {
        let current = self[keyPath: keyPath]
        let normalized = normalize(current)
        guard normalized != current else { return false }
        self[keyPath: keyPath] = normalized
        return true
    }

    // MARK: - Published Properties (for SwiftUI binding)

    @Published var fontFamily: String = SettingsController.defaultFontFamily {
        didSet {
            guard fontFamily != oldValue else { return }
            refreshAvailableFontsForCurrentSelectionIfNeeded()
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: fontFamily)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var fontSize: Double = SettingsController.defaultFontSize {
        didSet {
            if canonicalizeIfNeeded(\.fontSize, normalize: Self.normalizedFontSize) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: fontSize)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var cursorStyle: String = SettingsController.defaultCursorStyle {
        didSet {
            if canonicalizeIfNeeded(\.cursorStyle, normalize: Self.normalizedCursorStyle) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: cursorStyle)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var cursorBlink: Bool = SettingsController.defaultCursorBlink {
        didSet {
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: cursorBlink)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var copyOnSelect: Bool = SettingsController.defaultCopyOnSelect {
        didSet {
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: copyOnSelect)
            notifyGeneralSettingsObservers()
        }
    }
    /// Persistent sessions are an app preference, not a config key; new panes
    /// read it when they are created (PersistentSessions.prepare).
    var persistentSessionsEnabled: Bool {
        get { PersistentSessions.isEnabled }
        set {
            UserDefaults.standard.set(newValue, forKey: PersistentSessions.enabledDefaultsKey)
            objectWillChange.send()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var scrollbarVisibility: String = SettingsController.defaultScrollbarVisibility {
        didSet {
            if canonicalizeIfNeeded(\.scrollbarVisibility, normalize: Self.normalizedScrollbarVisibility) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: scrollbarVisibility)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var notifyOnCommandFinish: String = SettingsController.defaultNotifyOnCommandFinish {
        didSet {
            if canonicalizeIfNeeded(\.notifyOnCommandFinish, normalize: Self.normalizedNotifyOnCommandFinish) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: notifyOnCommandFinish)
            notifySoundsSettingsObservers()
        }
    }
    @Published var notifyOnCommandFinishActionBell: Bool = SettingsController.defaultNotifyOnCommandFinishActionBell {
        didSet {
            scheduleRealTimeConfigSyncIfNeeded(
                oldValue: oldValue,
                newValue: notifyOnCommandFinishActionBell
            )
            notifySoundsSettingsObservers()
        }
    }
    @Published var notifyOnCommandFinishActionNotify: Bool = SettingsController.defaultNotifyOnCommandFinishActionNotify {
        didSet {
            scheduleRealTimeConfigSyncIfNeeded(
                oldValue: oldValue,
                newValue: notifyOnCommandFinishActionNotify
            )
            notifySoundsSettingsObservers()
        }
    }
    @Published var notifyOnCommandFinishAfterSeconds: Int = SettingsController.defaultNotifyOnCommandFinishAfterSeconds {
        didSet {
            if canonicalizeIfNeeded(
                \.notifyOnCommandFinishAfterSeconds,
                normalize: Self.clampedNotifyOnCommandFinishAfterSeconds
            ) { return }
            if !preserveNotifyOnCommandFinishAfterConfigValue {
                notifyOnCommandFinishAfterConfigValue = Self.notifyOnCommandFinishAfterValue(
                    notifyOnCommandFinishAfterSeconds
                )
            }
            scheduleRealTimeConfigSyncIfNeeded(
                oldValue: oldValue,
                newValue: notifyOnCommandFinishAfterSeconds
            )
            notifySoundsSettingsObservers()
        }
    }
    // Preserve imported Ghostty duration syntax until the user rewrites it
    // through the whole-second Settings control.
    private var notifyOnCommandFinishAfterConfigValue =
        "\(SettingsController.defaultNotifyOnCommandFinishAfterSeconds)s"
    private var preserveNotifyOnCommandFinishAfterConfigValue = false
    @Published var backgroundOpacity: Double = SettingsController.defaultBackgroundOpacity {
        didSet {
            if canonicalizeIfNeeded(\.backgroundOpacity, normalize: Self.normalizedBackgroundOpacity) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: backgroundOpacity)
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var backgroundImagePath: String = "" {
        didSet {
            if canonicalizeIfNeeded(\.backgroundImagePath, normalize: TerminalBackgroundImageStore.normalizedConfigPath) { return }
            refreshBackgroundImagePresentationState()
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: backgroundImagePath)
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    // Reads the PERSISTED value, not the hardcoded default. `didSet` does not fire for
    // an initial value, so nothing is re-persisted here. Matches the sibling workspace
    // prefs (`TabSidebarPreferences.enabled()` and friends), which all hydrate at
    // declaration.
    @Published var backgroundImageScope: BackgroundImageScope = BackgroundImageScopePreferences.scope() {
        didSet {
            if canonicalizeIfNeeded(\.backgroundImageScope, normalize: {
                BackgroundImageScope.normalized(
                    rawValue: $0.rawValue,
                    fallback: BackgroundImageScopePreferences.defaultScope
                )
            }) { return }
            guard backgroundImageScope != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    backgroundImageScope.rawValue,
                    forKey: BackgroundImageScopePreferences.preferenceKey
                )
                scheduleRealTimeConfigSyncIfNeeded(
                    oldValue: oldValue.rawValue,
                    newValue: backgroundImageScope.rawValue
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published private(set) var backgroundImagePreview: NSImage?
    @Published private(set) var backgroundImageIssueDescription: String = ""
    @Published private(set) var backgroundImagePreviewVersion: Int = 0
    @Published var selectedTheme: String = "" {
        didSet {
            guard selectedTheme != oldValue else { return }
            refreshResolvedActiveThemeInfo()
            notifyThemesSettingsObservers()
        }
    }
    @Published var availableThemes: [ThemeInfo] = [] {
        didSet {
            notifyTerminalPresentationObservers()
            notifyThemesSettingsObservers()
        }
    }
    @Published private(set) var isThemeCatalogLoading = false {
        didSet {
            guard isThemeCatalogLoading != oldValue else { return }
            notifyThemesSettingsObservers()
        }
    }
    @Published var windowPaddingX: Int = SettingsController.defaultWindowPaddingX {
        didSet {
            if canonicalizeIfNeeded(\.windowPaddingX, normalize: Self.clampedWindowPadding) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: windowPaddingX)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowPaddingY: Int = SettingsController.defaultWindowPaddingY {
        didSet {
            if canonicalizeIfNeeded(\.windowPaddingY, normalize: Self.clampedWindowPadding) { return }
            scheduleRealTimeConfigSyncIfNeeded(oldValue: oldValue, newValue: windowPaddingY)
            notifyGeneralSettingsObservers()
        }
    }
    @Published var availableFonts: [String] = [] {
        didSet { notifyGeneralSettingsObservers() }
    }
    var hasBackgroundImage: Bool {
        !backgroundImagePath.isEmpty
    }
    var backgroundImageDisplayTitle: String {
        guard hasBackgroundImage else { return "None" }
        if TerminalBackgroundImageStore.isManagedBackgroundImagePath(backgroundImagePath) {
            return "Imported image"
        }
        let displayName = TerminalBackgroundImageStore.displayName(for: backgroundImagePath)
        return displayName.isEmpty ? "Custom Background Image" : displayName
    }
    var wholeWindowBackgroundImageEnabled: Bool {
        backgroundImageScope == .wholeWindow && hasBackgroundImage
    }
    @Published var selectedSettingsPane: SettingsPane = .appearance {
        didSet {
            window?.title = SettingsWindowFactory.title(for: selectedSettingsPane)
            handleSelectedSettingsPaneChange(from: oldValue, to: selectedSettingsPane)
            if consumePendingKeybindReloadIfReady(isSettingsVisible: window?.isVisible == true) {
                scheduleKeybindReload()
            }
        }
    }
    @Published var windowBorderEnabled: Bool = WindowBorderPreferences.defaultState.enabled {
        didSet {
            guard windowBorderEnabled != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderEnabled,
                    forKey: WindowBorderPreferences.enabledPreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderScope: WindowBorderScope = WindowBorderPreferences.defaultState.scope {
        didSet {
            guard windowBorderScope != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderScope.rawValue,
                    forKey: WindowBorderPreferences.scopePreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderWidth: Double = WindowBorderPreferences.defaultState.width {
        didSet {
            if canonicalizeIfNeeded(\.windowBorderWidth, normalize: WindowBorderPreferences.normalizedWidth) { return }
            guard windowBorderWidth != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderWidth,
                    forKey: WindowBorderPreferences.widthPreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderRadius: Double = WindowBorderPreferences.defaultState.radius {
        didSet {
            if canonicalizeIfNeeded(\.windowBorderRadius, normalize: WindowBorderPreferences.normalizedRadius) { return }
            guard windowBorderRadius != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderRadius,
                    forKey: WindowBorderPreferences.radiusPreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderColorMode: WindowBorderColorMode = WindowBorderPreferences.defaultState.colorMode {
        didSet {
            guard windowBorderColorMode != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderColorMode.rawValue,
                    forKey: WindowBorderPreferences.colorModePreferenceKey
                )
            }
            if windowBorderColorMode == .matchTheme {
                refreshResolvedActiveThemeInfo()
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderFocusedPalette: WindowBorderPalette = WindowBorderPreferences.defaultState.focusedPalette {
        didSet {
            guard windowBorderFocusedPalette != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderFocusedPalette.rawValue,
                    forKey: WindowBorderPreferences.focusedPalettePreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    @Published var windowBorderUnfocusedPalette: WindowBorderPalette = WindowBorderPreferences.defaultState.unfocusedPalette {
        didSet {
            guard windowBorderUnfocusedPalette != oldValue else { return }
            if !suppressWindowBorderPersistence {
                UserDefaults.standard.set(
                    windowBorderUnfocusedPalette.rawValue,
                    forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey
                )
            }
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }
    var windowBorderFocusedGradient: WindowBorderGradient {
        windowBorderGradient(isFocused: true)
    }

    var windowBorderUnfocusedGradient: WindowBorderGradient {
        windowBorderGradient(isFocused: false)
    }

    var windowBorderResolvedThemeName: String? {
        activeThemeInfo?.displayName
    }

    var windowBorderMatchThemeUsesManualFallback: Bool {
        windowBorderColorMode == .matchTheme && activeThemeInfo == nil
    }

    var windowBorderMatchThemeStatusMessage: String {
        if let theme = activeThemeInfo {
            return "Following theme \(theme.displayName)."
        }
        let requestedTheme = Self.normalizedThemeName(selectedTheme)
        guard !requestedTheme.isEmpty else {
            return "No active theme; using Manual palettes."
        }
        return "Theme \"\(requestedTheme)\" unavailable; using Manual palettes."
    }

    /// Whether the tab sidebar can be toggled (Cmd + Shift + B).
    /// Stored in UserDefaults to avoid unknown-key diagnostics from config.yen.
    @Published var tabSidebarEnabled: Bool = TabSidebarPreferences.enabled() {
        didSet {
            guard tabSidebarEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                let previousState = WorkspacePreferenceState(
                    tabSidebarEnabled: oldValue,
                    tabSidebarPresentationMode: tabSidebarPresentationMode,
                    tabSidebarPersistentVisible: TabSidebarController.persistentVisible,
                    paneStyle: paneStyle,
                    splitPaneLabelsEnabled: splitPaneLabelsEnabled,
                    splitPaneWorktreeNamingEnabled: splitPaneWorktreeNamingEnabled,
                    browserTerminalLinkCaptureEnabled: browserTerminalLinkCaptureEnabled,
                    browserSplitEnabled: browserSplitEnabled,
                    scratchpadEnabled: scratchpadEnabled,
                    backgroundImageScope: backgroundImageScope
                )
                UserDefaults.standard.set(
                    tabSidebarEnabled,
                    forKey: TabSidebarPreferences.enabledPreferenceKey
                )
                TabSidebarController.shared.applyWorkspacePreferenceStateTransition(
                    from: previousState,
                    to: captureWorkspacePreferenceState()
                )
            }
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether the tab sidebar is transient or persistently docked in terminal windows.
    /// Stored in UserDefaults to avoid unknown-key diagnostics from config.yen.
    @Published var tabSidebarPresentationMode: TabSidebarPresentationMode = TabSidebarPreferences.presentationMode() {
        didSet {
            guard tabSidebarPresentationMode != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                TabSidebarController.shared.setPresentationMode(tabSidebarPresentationMode)
            }
            notifyWorkspaceSettingsObservers()
        }
    }

    @Published var paneStyle: PaneStyle = .stored() {
        didSet {
            guard paneStyle != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(paneStyle.rawValue, forKey: PaneStyle.preferenceKey)
            }
            notifySplitPaneLabelObservers()
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether split panes show a header with an optional custom title.
    /// Stored in UserDefaults to avoid unknown-key diagnostics from config.yen.
    @Published var splitPaneLabelsEnabled: Bool = SplitPaneLabelsPreferences.enabled() {
        didSet {
            guard splitPaneLabelsEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    splitPaneLabelsEnabled,
                    forKey: SplitPaneLabelsPreferences.enabledPreferenceKey
                )
            }
            notifySplitPaneLabelObservers()
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether a split pane with no hand-typed label names itself after the git worktree its
    /// working directory sits in. Only takes effect while `splitPaneLabelsEnabled` is on.
    /// Stored in UserDefaults to avoid unknown-key diagnostics from config.yen.
    @Published var splitPaneWorktreeNamingEnabled: Bool = SplitPaneLabelsPreferences.worktreeNamingEnabled() {
        didSet {
            guard splitPaneWorktreeNamingEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    splitPaneWorktreeNamingEnabled,
                    forKey: SplitPaneLabelsPreferences.worktreeNamingEnabledPreferenceKey
                )
            }
            notifySplitPaneLabelObservers()
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether explicit terminal URL activations open in the native browser.
    /// Stored in UserDefaults and defaults off so existing link behavior is preserved.
    @Published var browserTerminalLinkCaptureEnabled: Bool = NativeBrowserPreferences.terminalLinkCaptureEnabled() {
        didSet {
            guard browserTerminalLinkCaptureEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    browserTerminalLinkCaptureEnabled,
                    forKey: NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey
                )
            }
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether browser launches that use automatic targeting prefer a terminal split.
    /// Stored in UserDefaults and defaults off so the utility browser window remains the default.
    @Published var browserSplitEnabled: Bool = NativeBrowserPreferences.browserSplitEnabled() {
        didSet {
            guard browserSplitEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    browserSplitEnabled,
                    forKey: NativeBrowserPreferences.browserSplitEnabledPreferenceKey
                )
            }
            notifyWorkspaceSettingsObservers()
        }
    }

    /// Whether the scratchpad can be toggled (Cmd + Shift + J).
    /// Stored in UserDefaults to avoid unknown-key diagnostics from config.yen.
    @Published var scratchpadEnabled: Bool = ScratchpadController.scratchpadEnabled {
        didSet {
            guard scratchpadEnabled != oldValue else { return }
            if !suppressWorkspacePreferencePersistence {
                UserDefaults.standard.set(
                    scratchpadEnabled,
                    forKey: ScratchpadController.scratchpadEnabledPreferenceKey
                )
                if !scratchpadEnabled && ScratchpadController.shared.visible {
                    ScratchpadController.shared.toggle()
                }
            }
            notifyWorkspaceSettingsObservers()
        }
    }

    // MARK: - Notification Sounds (stored in UserDefaults, not config.yen)

    @Published private var notificationServiceSettings = NotificationServiceSettings.captureAll()

    @Published var soundWhenFocused: Bool = NotificationSoundManager.shared.soundWhenFocused {
        didSet {
            soundStore.syncSoundFocusBehaviorPreference(
                soundWhenFocused,
                oldValue: oldValue,
                keyPath: \.soundWhenFocused
            )
            notifySoundsSettingsObservers()
        }
    }

    @Published var bannerWhenFocused: Bool = NotificationSoundManager.shared.bannerWhenFocused {
        didSet {
            soundStore.syncSoundFocusBehaviorPreference(
                bannerWhenFocused,
                oldValue: oldValue,
                keyPath: \.bannerWhenFocused
            )
            notifySoundsSettingsObservers()
        }
    }

    @Published var availableSystemSounds: [NotificationSoundOption] = [] {
        didSet { notifySoundsSettingsObservers() }
    }

    /// Mirrors service edits and focus-toggle changes into `NotificationSoundManager`.
    /// Lazy so it captures `self` only after initialization.
    private lazy var soundStore = NotificationSoundStore(controller: self)

    /// Raw shell-integration-features value from config. We preserve user tokens
    /// (sudo, ssh-env, etc.) and ensure `no-cursor` is always present on save.
    private var shellIntegrationFeatures: String = SettingsController.defaultShellIntegrationFeatures

    private var themeCatalogSnapshot: ThemeCatalogSnapshot = .empty

    private func windowBorderGradient(isFocused: Bool) -> WindowBorderGradient {
        WindowBorderGradientResolver.gradient(
            isFocused: isFocused,
            colorMode: windowBorderColorMode,
            activeThemeInfo: activeThemeInfo,
            focusedPalette: windowBorderFocusedPalette,
            unfocusedPalette: windowBorderUnfocusedPalette
        )
    }

    private var activeThemeInfo: ThemeInfo? {
        let effectiveThemeName = selectedTheme
        let selectedThemeKey = Self.normalizedThemeLookupKey(effectiveThemeName)
        guard !selectedThemeKey.isEmpty else { return nil }
        if let catalogTheme = availableThemes.first(where: {
            Self.normalizedThemeLookupKey($0.name) == selectedThemeKey
        }) {
            return catalogTheme
        }
        guard let resolvedActiveThemeInfo else { return nil }
        return Self.normalizedThemeLookupKey(resolvedActiveThemeInfo.name) == selectedThemeKey
            ? resolvedActiveThemeInfo
            : nil
    }

    // Permissions
    var accessibilityGranted: Bool {
        get { runtimeStatus.accessibilityGranted }
        set {
            guard runtimeStatus.accessibilityGranted != newValue else { return }
            runtimeStatus.accessibilityGranted = newValue
            notifySoundsSettingsObservers()
        }
    }

    var microphoneGranted: Bool {
        get { runtimeStatus.microphoneGranted }
        set {
            guard runtimeStatus.microphoneGranted != newValue else { return }
            runtimeStatus.microphoneGranted = newValue
            notifySoundsSettingsObservers()
        }
    }

    var speechRecognitionGranted: Bool {
        get { runtimeStatus.speechRecognitionGranted }
        set {
            guard runtimeStatus.speechRecognitionGranted != newValue else { return }
            runtimeStatus.speechRecognitionGranted = newValue
            notifySoundsSettingsObservers()
        }
    }

    var notificationAuthorizationStatus: UNAuthorizationStatus {
        get { runtimeStatus.notificationAuthorizationStatus }
        set {
            guard runtimeStatus.notificationAuthorizationStatus != newValue else { return }
            runtimeStatus.notificationAuthorizationStatus = newValue
            notifySoundsSettingsObservers()
        }
    }

    var dictationLocalServiceIssueDetail: String {
        get { runtimeStatus.dictationLocalServiceIssueDetail }
        set {
            guard runtimeStatus.dictationLocalServiceIssueDetail != newValue else { return }
            runtimeStatus.dictationLocalServiceIssueDetail = newValue
            notifySoundsSettingsObservers()
        }
    }
    @Published var dictationLiveTranscriptPreviewEnabled: Bool = DictationPreviewPreferences.liveTranscriptEnabled {
        didSet {
            DictationPreviewPreferences.liveTranscriptEnabled = dictationLiveTranscriptPreviewEnabled
            notifySoundsSettingsObservers()
        }
    }

    /// Selected microphone, as a picker identifier. Empty string means System Default.
    /// Writes straight through to `DictationAudioDeviceStore`, so the binder picks it
    /// up on the next session; a change never disturbs a session already running.
    @Published var dictationSelectedInputDeviceIdentifier: String =
        DictationInputDeviceOptionsBuilder.selectedIdentifier(for: DictationAudioDeviceStore.selectedUID())
    {
        didSet {
            guard oldValue != dictationSelectedInputDeviceIdentifier else { return }
            DictationAudioDeviceStore.setSelectedUID(dictationSelectedInputDeviceIdentifier)
            refreshDictationInputDeviceOptions()
            notifySoundsSettingsObservers()
        }
    }

    /// Populated eagerly rather than left empty until the picker appears.
    ///
    /// It used to start `[]` and fill only from the row's own `.onAppear`, which
    /// made the row's content depend on the row having already been laid out. Build
    /// the list up front so the picker always has rows to draw on its first render.
    @Published private(set) var dictationInputDeviceOptions: [DictationInputDeviceOption] =
        SettingsController.makeDictationInputDeviceOptions()

    /// Reads the HAL and builds the picker rows. Static so it can seed the stored
    /// property above before `self` exists.
    static func makeDictationInputDeviceOptions() -> [DictationInputDeviceOption] {
        let devices = (try? DictationAudioDeviceResolver.inputDevices()) ?? []
        let defaultName = (try? DictationAudioDeviceResolver.defaultInputDeviceID())
            .flatMap { id in devices.first(where: { $0.objectID == id })?.name }
        return DictationInputDeviceOptionsBuilder.makeOptions(
            devices: devices,
            selectedUID: DictationAudioDeviceStore.selectedUID(),
            defaultDeviceName: defaultName
        )
    }

    /// Why the last dictation session did not use the selected microphone, if it
    /// did not. Phase 2 records this on the recognizer; showing it is the only
    /// thing that makes a fallback visible to the user rather than silent.
    @Published private(set) var dictationInputDeviceFallbackReason: String?

    /// Watches for hot-plug and default-device changes while Settings is open.
    /// Held here so it is torn down with the controller; the monitor unregisters
    /// its HAL listeners on deinit.
    private var dictationAudioDeviceMonitor: DictationAudioDeviceMonitor?

    func startDictationInputDeviceMonitoring() {
        refreshDictationInputDeviceOptions()
        guard dictationAudioDeviceMonitor == nil else { return }
        let monitor = DictationAudioDeviceMonitor { [weak self] _ in
            self?.refreshDictationInputDeviceOptions()
        }
        monitor.start()
        dictationAudioDeviceMonitor = monitor
    }

    func stopDictationInputDeviceMonitoring() {
        dictationAudioDeviceMonitor?.stop()
        dictationAudioDeviceMonitor = nil
    }

    /// Re-read the HAL and rebuild the picker rows. Called on Settings open and from
    /// the device monitor, so hot-plug shows up without a relaunch.
    func refreshDictationInputDeviceOptions() {
        let reason = DictationController.shared.lastInputDeviceFallbackReason
        if reason != dictationInputDeviceFallbackReason {
            dictationInputDeviceFallbackReason = reason
        }

        let options = Self.makeDictationInputDeviceOptions()
        guard options != dictationInputDeviceOptions else { return }
        dictationInputDeviceOptions = options
        notifySoundsSettingsObservers()
    }
    @Published var translateOnDictateEnabled: Bool = DictationTranslationPreferences.translateOnDictateEnabled {
        didSet {
            if !dictationTranslationSupportedOnThisMac && translateOnDictateEnabled {
                translateOnDictateEnabled = false
                return
            }
            DictationTranslationPreferences.translateOnDictateEnabled = translateOnDictateEnabled
            if translateOnDictateEnabled {
                scheduleDictationTranslationAssetPreparationIfNeeded()
            } else {
                cancelDictationTranslationAssetPreparation()
            }
            notifySoundsSettingsObservers()
        }
    }
    @Published var dictationTranslateTargetLanguageIdentifier: String = DictationTranslationPreferences.targetLanguageIdentifier {
        didSet {
            if canonicalizeIfNeeded(
                \.dictationTranslateTargetLanguageIdentifier,
                normalize: Self.normalizeDictationTranslationIdentifier
            ) { return }
            DictationTranslationPreferences.targetLanguageIdentifier = dictationTranslateTargetLanguageIdentifier
            scheduleDictationTranslationAssetPreparationIfNeeded()
            notifySoundsSettingsObservers()
        }
    }
    @Published private(set) var dictationTranslationPreparationRequest: DictationTranslationPreparationRequest? {
        didSet {
            notifySoundsSettingsObservers()
        }
    }
    @Published var availableDictationTargetLanguages: [DictationTranslationLanguageOption] = [
        DictationTranslationLanguageCatalog.option(
            for: DictationTranslationPreferences.targetLanguageIdentifier
        )
    ] {
        didSet {
            handleAvailableDictationTargetLanguagesChange()
            notifySoundsSettingsObservers()
        }
    }

    // Keyboard shortcuts
    @Published var keybindEntries: [KeybindEntry] = [] {
        didSet {
            notifyKeyboardSettingsObservers()
        }
    }
    /// True while the inline key recorder is capturing a shortcut.
    @Published var keyboardRecordingActive: Bool = false {
        didSet {
            if consumePendingKeybindReloadIfReady(isSettingsVisible: window?.isVisible == true) {
                scheduleKeybindReload()
            }
            notifyKeyboardSettingsObservers()
        }
    }

    // Status
    @Published var statusMessage: String = ""
    @Published var statusSeverity: SettingsStatusSeverity = .success
    private var statusClearWorkItem: DispatchWorkItem?
    private var statusClearGeneration: UInt64 = 0
    private var statusClearActiveGeneration: UInt64?

    /// Launch at Login — reads/writes SMAppService directly (not config.yen).
    /// Getter duplicated in DictationController.backgroundModeActive for AppDelegate use.
    var launchAtLoginNeedsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    var dictationLocalSpeechServiceReady: Bool {
        dictationLocalServiceIssueDetail.isEmpty
    }

    static func localSpeechStatusDetail(
        for issue: DictationController.LocalServiceIssue?
    ) -> String {
        guard let issue else { return "" }
        return DictationController.localServiceRecoveryBody(for: issue)
    }

    var notificationAuthorizationAllowsDelivery: Bool {
        NotificationAuthorizationStatusPolicy.allowsDelivery(notificationAuthorizationStatus)
    }

    var notificationAuthorizationStatusLabel: String {
        NotificationAuthorizationStatusPolicy.statusLabel(for: notificationAuthorizationStatus)
    }

    var notificationAuthorizationActionTitle: String {
        NotificationAuthorizationStatusPolicy.actionTitle(for: notificationAuthorizationStatus)
    }

    var notificationAuthorizationActionHint: String {
        NotificationAuthorizationStatusPolicy.actionHint(for: notificationAuthorizationStatus)
    }

    var notificationAuthorizationDetailLine: String {
        NotificationAuthorizationStatusPolicy.detailLine(for: notificationAuthorizationStatus)
    }

    var launchAtLogin: Bool {
        get {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                return true
            case .notRegistered, .notFound:
                return false
            @unknown default:
                return false
            }
        }
        set {
            defer {
                objectWillChange.send()
                notifyGeneralSettingsObservers()
                DictationController.shared.updateIdlePresence()
            }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                YEN.logger.error("SettingsController: Launch at login failed: \(error)")
                showStatus("Launch at Login failed: \(error.localizedDescription)", severity: .error, duration: 4)
                return
            }

            if newValue && launchAtLoginNeedsApproval {
                showStatus("Approve Launch at Login in System Settings", severity: .warning, duration: 4)
            } else if !newValue && launchAtLogin {
                showStatus("Launch at Login still active in System Settings", severity: .warning, duration: 4)
            }
        }
    }

    var dictationTranslationSupportedOnThisMac: Bool {
        DictationTranslationRuntime.supportsInstalledTranslationSession()
    }

    private func enforceDictationTranslationAvailability() {
        guard !dictationTranslationSupportedOnThisMac else { return }
        if translateOnDictateEnabled {
            translateOnDictateEnabled = false
        } else {
            DictationTranslationPreferences.translateOnDictateEnabled = false
        }
    }

    /// Owns the window-session permission-polling timer. See
    /// `SettingsPermissionPollingController`.
    private let permissionPolling = SettingsPermissionPollingController()
    // Deferred window-session reload tasks. Each owns its own generation-guarded
    // single-slot task lifecycle (cancel/yield/re-check). See `GenerationalMainActorTask`.
    private let deferredThemeLoadTask = GenerationalMainActorTask()
    private let deferredFontLoadTask = GenerationalMainActorTask()
    private let deferredKeybindReloadTask = GenerationalMainActorTask()
    private var themeCatalogLoadTask: Task<Void, Never>?
    private var themeCatalogLoadTaskGeneration: UInt64 = 0
    private var dictationTranslationPreparationTaskGeneration: UInt64 = 0
    private var hasLoadedNotificationSoundStateForVisibleSession = false
    private var lastSettingsWindowFrame: NSRect?
    private var lastThemeCatalogReloadAt: CFAbsoluteTime = 0
    private var resolvedActiveThemeInfo: ThemeInfo?
    private var suppressWorkspacePreferencePersistence = false

    /// Owns the theme live-preview lifecycle (debounce, snapshot/revert,
    /// auto-commit). See `ThemePreviewCoordinator`.
    private lazy var themePreview = ThemePreviewCoordinator(host: self)

    /// Theme name loaded from disk when settings opened — baseline for revert.
    private var originalThemeName: String = ""

    /// Debounce work item for sound previews so popover teardown can't stack plays.
    /// Owns the debounced notification-sound live preview. See
    /// `NotificationSoundPreviewCoordinator`.
    private let soundPreview = NotificationSoundPreviewCoordinator()
    /// Debounce work item for real-time config sync from General/Keyboard controls.
    private var realTimeConfigSyncWork: DispatchWorkItem?
    /// Suppresses auto-sync while controller is hydrating state from disk.
    private var suppressRealTimeConfigSync = false
    /// True only while `init()` hydrates config-backed state. Gates Settings-only derived
    /// state (currently the background-image preview decode) off the launch path.
    private var isHydratingConfigAtLaunch = false
    /// Suppresses UserDefaults writes while hydrating border settings.
    private var suppressWindowBorderPersistence = false
    /// Skips controller-side reload handling for config notifications emitted by Settings itself.
    private var pendingSelfInitiatedConfigReloadNotifications = 0
    /// Tracks deferred keybind refresh requests received during config reload notifications.
    private var keybindReloadPending = false
    private var configReloadObserver: NSObjectProtocol?
    /// Observes key-window changes so layout actions target the terminal that was
    /// focused before the Settings panel stole key, not an arbitrary tab.
    private var keyWindowObserver: NSObjectProtocol?
    /// Re-reads system-owned state when YEN becomes active again, so a Login Items
    /// approval made in System Settings shows without another edit in the panel.
    private var appActivationObserver: NSObjectProtocol?
    /// Test hook used by unit tests to simulate external theme reloads without touching disk.
    var testThemeNameOnConfigReload: (() -> String?)?
    /// Single in-flight refresh task for translation language options.
    private var dictationLanguageRefreshTask: Task<Void, Never>?
    /// Single in-flight asset preparation task for the selected translation pair.
    private var dictationTranslationPreparationTask: Task<Void, Never>?
#if DEBUG
    enum TestWindowCloseMemoryMode {
        case releaseWindowGraph
        case retainWindowGraph
    }

    private var testThemeCatalogPathsOverride: ThemeCatalogPaths?
    private static var testWindowCloseMemoryModeOverride: TestWindowCloseMemoryMode?
#endif

    /// Canonical home is `ManagedConfigDocument`; aliased here so the many
    /// `Self.themeColorKeys` / `backgroundImageManagedKeys` refs keep compiling.
    private static let themeColorKeys = ManagedConfigDocument.themeColorKeys
    private static let backgroundImageManagedKeys = ManagedConfigDocument.backgroundImageManagedKeys

    static func normalizeDictationTranslationIdentifier(_ identifier: String) -> String {
        DictationTranslationPreferences.normalizeLanguageIdentifier(identifier)
    }

    static func validatedDictationTargetIdentifier(
        currentIdentifier: String,
        supportedIdentifiers: [String],
        preferredIdentifier: String
    ) -> String {
        DictationTranslationPreferences.validatedTargetIdentifier(
            currentIdentifier: currentIdentifier,
            supportedIdentifiers: supportedIdentifiers,
            preferredIdentifier: preferredIdentifier
        )
    }

    // MARK: - Private Properties

    private var configPath: String {
        Self.defaultConfigPath()
    }

    private var themeCatalogPaths: ThemeCatalogPaths {
#if DEBUG
        if let testThemeCatalogPathsOverride {
            return testThemeCatalogPathsOverride
        }
#endif
        let resourcePath = Bundle.main.resourcePath ?? ""
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ThemeCatalogPaths(
            userThemesDirectory: "\(home)/.config/yen/themes",
            themesDirectory: "\(resourcePath)/yen/themes",
            bundledThemeManifestPath: "\(resourcePath)/yen/theme-curated-manifest.txt",
            bundledThemeTagsPath: "\(resourcePath)/yen/theme-curated-tags.txt"
        )
    }

    // MARK: - Initialization

    private init() {
        super.init(window: nil)
        TabSidebarPreferences.registerDefaults()
        SplitPaneLabelsPreferences.registerDefaults()
        NativeBrowserPreferences.registerDefaults()
        WindowBorderPreferences.registerDefaults()
        BackgroundImageScopePreferences.registerDefaults()
        removeWholeWindowBackgroundRuntimeConfigIfPresent()
        loadWindowBorderPreferences()
        refreshThemeContextFromDisk()
        // Hydrate the config-backed state too. Without this, values like
        // `copyOnSelect` and `backgroundImagePath` kept their hardcoded in-memory
        // defaults until the Settings window was opened for the first time — so
        // `copy-on-select = false` was ignored by the Scratchpad and the Git-drawer
        // diff, and a saved "Whole Window" background scope rendered per-split.
        //
        // `suppressRealTimeConfigSync` is required, not cosmetic: with `window == nil`,
        // `scheduleRealTimeConfigSync()` takes the not-visible branch and calls
        // `persistConfig` SYNCHRONOUSLY, so every key differing from its in-memory
        // default would trigger a full parse-merge-write of config.yen on the main
        // thread during launch. This runs AFTER `refreshThemeContextFromDisk()` so
        // `selectedTheme`'s didSet resolves against an already-built catalog.
        suppressRealTimeConfigSync = true
        isHydratingConfigAtLaunch = true
        loadConfig()
        isHydratingConfigAtLaunch = false
        suppressRealTimeConfigSync = false
        configReloadObserver = NotificationCenter.default.addObserver(
            forName: .yenConfigDidReload,
            object: nil,
            queue: .main
        ) { _ in
            // WindowBorderPreferencesTests depends on config reload settling synchronously.
            MainActor.assumeIsolated { [weak self] in
                self?.handleConfigReloadNotification()
            }
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated { [weak self] in
                self?.recordKeyTerminalController(from: notification)
            }
        }
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshSystemOwnedStateAfterActivation()
            }
        }
        enforceDictationTranslationAvailability()
    }

    /// `SMAppService` status has no change notification. The General snapshot
    /// captures it, so posting the General notification re-reads it; the store
    /// republishes only when the status actually changed.
    private func refreshSystemOwnedStateAfterActivation() {
        guard window?.isVisible == true, selectedSettingsPane == .general else { return }
        notifyGeneralSettingsObservers()
    }

    /// Opens System Settings at Login Items, where a pending approval is granted.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Records the terminal controller behind a newly key window so it can be
    /// preferred as the layout target. Ignores the Settings panel itself and any
    /// non-terminal utility window so the last real terminal focus is preserved.
    private func recordKeyTerminalController(from notification: Notification) {
        guard let keyWindow = notification.object as? NSWindow else { return }
        guard keyWindow !== window else { return }
        guard let controller = keyWindow.windowController as? BaseTerminalController else { return }
        layoutApplier.recordFocusedTerminalController(controller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let configReloadObserver {
            NotificationCenter.default.removeObserver(configReloadObserver)
        }
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
        Self.removeWholeWindowBackgroundRuntimeConfigIfPresent(
            at: Self.wholeWindowBackgroundRuntimeConfigPath(for: Self.defaultConfigPath())
        )
        let presentationCoordinator = presentationCoordinator
        // GenerationalMainActorTask.cancel() is @MainActor-isolated; hop through a
        // MainActor Task (the helpers are reference types, so capturing them keeps
        // them alive past self's teardown). Raw Task.cancel() below is nonisolated.
        let deferredThemeLoadTask = deferredThemeLoadTask
        let deferredFontLoadTask = deferredFontLoadTask
        let deferredKeybindReloadTask = deferredKeybindReloadTask
        Task { @MainActor in
            presentationCoordinator.cancelRefresh()
            deferredThemeLoadTask.cancel()
            deferredFontLoadTask.cancel()
            deferredKeybindReloadTask.cancel()
        }
        themeCatalogLoadTask?.cancel()
        dictationLanguageRefreshTask?.cancel()
        dictationTranslationPreparationTask?.cancel()
        dictationTranslationPreparationTask = nil
    }

    // MARK: - Window Management

    func show() {
        show(pane: nil)
    }

    func toggleVisibility() {
        if window?.isVisible == true {
            hide()
            return
        }
        show()
    }

    @MainActor
    func showNotificationSettings() {
        show(pane: .notifications)
    }

    func show(pane: SettingsPane?) {
        enforceDictationTranslationAvailability()
        let windowWasVisible = window?.isVisible == true
        if let pane {
            selectedSettingsPane = pane
        }
        let createdWindow = ensurePresentationWindow()

        prepareForPresentation()

        window?.makeKeyAndOrderFront(nil)
        restoreStoredWindowFrameIfNeeded(afterCreatingWindow: createdWindow)
        NSApp.yenActivateCompat()

        let reason = presentationCoordinator.presentationReason(
            createdWindow: createdWindow,
            windowWasVisible: windowWasVisible,
            requestedPane: pane
        )
        presentationCoordinator.scheduleRefreshIfNeeded(
            for: reason,
            isWindowVisible: { [weak self] in
                self?.window?.isVisible == true
            },
            refresh: { [weak self] in
                self?.performVisibleSessionRefresh()
            }
        )
    }

    func hide() {
        window?.close()
    }

    private func ensurePresentationWindow() -> Bool {
        guard let existingWindow = window else {
            createWindow()
            return true
        }

        guard existingWindow.contentView != nil else {
            lastSettingsWindowFrame = existingWindow.frame
            existingWindow.orderOut(nil)
            SettingsWindowFactory.releaseWindowGraph(existingWindow)
            window = nil
            createWindow()
            return true
        }

        return false
    }

    private func restoreStoredWindowFrameIfNeeded(afterCreatingWindow createdWindow: Bool) {
        guard createdWindow,
              let lastSettingsWindowFrame,
              let window else { return }
        // NavigationSplitView-backed settings content can momentarily refit the
        // recreated window to its intrinsic height during attachment. Reapply
        // the stored frame after the window is ordered front so reopen cycles
        // preserve the user's last size.
        window.setFrame(lastSettingsWindowFrame, display: false)
    }

    /// Panes that show system permission state, which has no change notification.
    private static let permissionPollingPanes: Set<SettingsPane> = [.notifications, .dictation]

    private func startPermissionPolling() {
        guard Self.permissionPollingPanes.contains(selectedSettingsPane), window?.isVisible == true else {
            stopPermissionPolling()
            return
        }
        permissionPolling.start { [weak self] in
            self?.refreshPermissions()
            self?.refreshNotificationAuthorizationStatus()
            self?.refreshDictationLocalSpeechServiceStatus()
        }
    }

    private func stopPermissionPolling() {
        permissionPolling.stop()
    }

    private func handleSelectedSettingsPaneChange(from oldPane: SettingsPane, to newPane: SettingsPane) {
        guard oldPane != newPane else { return }
        guard window?.isVisible == true else {
            stopPermissionPolling()
            return
        }

        switch newPane {
        case .appearance:
            refreshThemeDependentPresentationState()
            scheduleFontCatalogLoadIfNeeded()
        case .general:
            // Launch at Login reads `SMAppService`, which posts no change.
            notifyGeneralSettingsObservers()
        case .notifications, .dictation:
            ensureNotificationSoundStateLoadedForVisibleSession()
            refreshVisibleSoundsState()
        case .shortcuts:
            // Belt-and-suspenders alongside `selectedSettingsPane`'s `didSet`, which already
            // consumes a pending reload on pane change: force a load here too if the entry
            // list is still empty (e.g. first-ever open landed on Shortcuts with no prior
            // pending flag set), so the pane never renders a silently empty shortcut list.
            if keybindEntries.isEmpty || consumePendingKeybindReloadIfReady(isSettingsVisible: true) {
                scheduleKeybindReload()
            }
        }

        updatePermissionPollingForCurrentPane()
    }

    private func updatePermissionPollingForCurrentPane() {
        if Self.permissionPollingPanes.contains(selectedSettingsPane) {
            startPermissionPolling()
        } else {
            stopPermissionPolling()
        }
    }

    private func prepareForPresentation() {
        // If Settings is already open, flush pending debounced edits first so
        // deep links/re-open calls don't discard the user's latest changes.
        commitPendingThemeSelectionIfNeeded()
        flushPendingRealTimeConfigSyncIfNeeded()

        // Revert any in-flight preview before reloading.
        themePreview.cancelPendingPreview()
        realTimeConfigSyncWork?.cancel()
        realTimeConfigSyncWork = nil
        revertThemePreview()
    }

    private func performVisibleSessionRefresh() {
        suppressRealTimeConfigSync = true
        defer { suppressRealTimeConfigSync = false }

        hasLoadedNotificationSoundStateForVisibleSession = false
        loadConfig()
        loadWorkspacePreferences()
        loadWindowBorderPreferences()
        refreshThemeDependentPresentationState()

        if selectedSettingsPane == .appearance || availableFonts.isEmpty {
            scheduleFontCatalogLoadIfNeeded()
        }

        if Self.permissionPollingPanes.contains(selectedSettingsPane) {
            ensureNotificationSoundStateLoadedForVisibleSession()
        }

        cachedConflictShortcuts = nil
        setKeybindReloadPending(true)
        keyboardRecordingActive = false
        if consumePendingKeybindReloadIfReady(isSettingsVisible: true) {
            scheduleKeybindReload()
        }

        // Capture baseline theme for preview revert.
        originalThemeName = selectedTheme

        if Self.permissionPollingPanes.contains(selectedSettingsPane) {
            refreshVisibleSoundsState()
        }
        updatePermissionPollingForCurrentPane()
    }

    /// The live preview shows the theme in every pane, so the catalog and the
    /// resolved theme stay current whichever pane is selected.
    private func refreshThemeDependentPresentationState() {
        scheduleThemeReloadIfNeeded()
        refreshResolvedActiveThemeInfo()
    }

    private func refreshVisibleSoundsState() {
        refreshPermissions()
        refreshNotificationAuthorizationStatus()
        refreshDictationLocalSpeechServiceStatus()
        refreshDictationTranslationLanguageOptions()
    }

    private func ensureNotificationSoundStateLoadedForVisibleSession() {
        guard window?.isVisible == true else { return }
        guard !hasLoadedNotificationSoundStateForVisibleSession else { return }
        loadNotificationSoundState()
        hasLoadedNotificationSoundStateForVisibleSession = true
    }

    private func scheduleThemeReload() {
        deferredThemeLoadTask.run(
            shouldProceed: { [weak self] in self?.window?.isVisible == true }
        ) { [weak self] _ in
            self?.loadThemesAsync()
        }
    }

    private func scheduleThemeReloadIfNeeded(force: Bool = false) {
        if force || availableThemes.isEmpty {
            scheduleThemeReload()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if (now - lastThemeCatalogReloadAt) >= Self.themeReloadMinimumIntervalSeconds {
            scheduleThemeReload()
        }
    }

    private func scheduleFontCatalogLoadIfNeeded() {
        deferredFontLoadTask.cancel()
        if let cached = Self.cachedMonospaceFonts {
            availableFonts = Self.fontCatalogIncludingCurrentFont(
                cached,
                currentFontFamily: fontFamily
            )
            return
        }
        deferredFontLoadTask.run(
            shouldProceed: { [weak self] in self?.window?.isVisible == true }
        ) { [weak self] isStillCurrent in
            guard let self else { return }
            let currentFontFamily = self.fontFamily
            let fontSnapshotTask = Task.detached(priority: .utility) {
                Self.buildMonospaceFontCatalog()
            }
            let fonts = await withTaskCancellationHandler(operation: {
                await fontSnapshotTask.value
            }, onCancel: {
                fontSnapshotTask.cancel()
            })

            guard isStillCurrent() else { return }

            Self.cachedMonospaceFonts = fonts
            self.availableFonts = Self.fontCatalogIncludingCurrentFont(
                fonts,
                currentFontFamily: currentFontFamily
            )
        }
    }

    private func scheduleKeybindReload() {
        deferredKeybindReloadTask.run(
            shouldProceed: { [weak self] in self?.window?.isVisible == true }
        ) { [weak self] _ in
            self?.loadKeybinds()
        }
    }

    private func createWindow() {
        let contentView = SettingsPanel(controller: self)
        let hostingView = NSHostingView(rootView: contentView)
        let window = SettingsWindowFactory.makeWindow(
            contentView: hostingView,
            lastFrame: lastSettingsWindowFrame
        )
        // Manual delegate — NSHostingView does not forward NSWindowDelegate to SwiftUI,
        // so we set self as delegate to handle windowWillClose (cleanup, preview revert).
        window.delegate = self
        window.title = SettingsWindowFactory.title(for: selectedSettingsPane)
        self.window = window
    }

    private static func shouldReleaseWindowGraphOnClose() -> Bool {
#if DEBUG
        switch testWindowCloseMemoryModeOverride {
        case .retainWindowGraph:
            return false
        case .releaseWindowGraph, .none:
            return true
        }
#else
        return true
#endif
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        SettingsWindowFactory.dimZoomButton(window)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        let closingWindow = notification.object as? NSWindow ?? window
        stopPermissionPolling()
        presentationCoordinator.cancelRefresh()
        deferredThemeLoadTask.cancel()
        themeCatalogLoadTask?.cancel()
        themeCatalogLoadTask = nil
        deferredFontLoadTask.cancel()
        deferredKeybindReloadTask.cancel()
        dictationLanguageRefreshTask?.cancel()
        dictationLanguageRefreshTask = nil
        cancelDictationTranslationAssetPreparation()
        // Reset the status BEFORE the close-time flushes below. Those flushes can produce
        // a genuine "Apply failed: ..." that the user must still see on the next open;
        // clearing afterwards would erase the very failure this close just discovered.
        // Clearing here still kills a stale toast frozen by the cancelled timer.
        statusClearActiveGeneration = nil
        statusMessage = ""
        statusSeverity = .success
        commitPendingThemeSelectionIfNeeded()
        flushPendingRealTimeConfigSyncIfNeeded()
        revertThemePreview()
        hasLoadedNotificationSoundStateForVisibleSession = false
        setKeybindReloadPending(false)
        keyboardRecordingActive = false
        cachedConflictShortcuts = nil
        soundPreview.cancelAndStop()
        // The work item scheduled by `showStatus` is the ONLY production clearer of
        // `statusMessage`, so cancelling it without clearing the message froze the footer
        // badge into the next open. The reset itself happens ABOVE, before the close-time
        // flushes, so a failure those flushes report is preserved.
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        guard let closingWindow else { return }
        lastSettingsWindowFrame = closingWindow.frame
        guard Self.shouldReleaseWindowGraphOnClose() else { return }
        SettingsWindowFactory.releaseWindowGraph(closingWindow)
        if let currentWindow = window, currentWindow === closingWindow {
            window = nil
        }
    }

    @objc func cancel(_ sender: Any?) {
        hide()
    }

    func refreshDictationLocalSpeechServiceStatus() {
        let issueDetail = Self.localSpeechStatusDetail(
            for: DictationController.shared.currentLocalServiceIssue
        )
        if dictationLocalServiceIssueDetail != issueDetail {
            dictationLocalServiceIssueDetail = issueDetail
        }
    }

    func refreshNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let authorizationStatus = settings.authorizationStatus
                if self.notificationAuthorizationStatus != authorizationStatus {
                    self.notificationAuthorizationStatus = authorizationStatus
                }
            }
        }
    }

    func handleNotificationAuthorizationAction() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let authorizationStatus = settings.authorizationStatus
                if self.notificationAuthorizationStatus != authorizationStatus {
                    self.notificationAuthorizationStatus = authorizationStatus
                }

                switch authorizationStatus {
                case .notDetermined:
                    AppDelegate.requestNotificationAuthorizationIfNeeded()
                    self.showStatus("Requesting notification permission", severity: .info, duration: 3)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.refreshNotificationAuthorizationStatus()
                    }
                case .authorized, .provisional, .ephemeral, .denied:
                    AppDelegate.openNotificationSystemSettings()
                    self.showStatus("Opening Notification settings", severity: .info, duration: 3)
                @unknown default:
                    AppDelegate.openNotificationSystemSettings()
                    self.showStatus("Opening Notification settings", severity: .info, duration: 3)
                }
            }
        }
    }

    func validateDictationTranslationSelectionInBackground() {
        refreshDictationTranslationLanguageOptions()
    }

    private func refreshDictationTranslationLanguageOptions() {
        dictationLanguageRefreshTask?.cancel()
        dictationLanguageRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }

            let options = await DictationTranslationLanguageCatalog.supportedLanguageOptions(
                sourceLocaleIdentifier: self.currentDictationTranslationSourceLocaleIdentifier()
            )
            guard !Task.isCancelled else { return }
            if options.isEmpty {
                self.availableDictationTargetLanguages = []
                return
            }

            self.availableDictationTargetLanguages = options
        }
    }

    private func handleAvailableDictationTargetLanguagesChange() {
        if availableDictationTargetLanguages.isEmpty {
            if translateOnDictateEnabled {
                translateOnDictateEnabled = false
            } else {
                DictationTranslationPreferences.translateOnDictateEnabled = false
            }
            return
        }

        let validated = Self.validatedDictationTargetIdentifier(
            currentIdentifier: dictationTranslateTargetLanguageIdentifier,
            supportedIdentifiers: availableDictationTargetLanguages.map(\.identifier),
            preferredIdentifier: DictationTranslationPreferences.preferredTargetLanguageIdentifier
        )
        if validated != dictationTranslateTargetLanguageIdentifier {
            dictationTranslateTargetLanguageIdentifier = validated
        }
        scheduleDictationTranslationAssetPreparationIfNeeded()
    }

    private func cancelDictationTranslationAssetPreparation() {
        dictationTranslationPreparationTask?.cancel()
        dictationTranslationPreparationTask = nil
        dictationTranslationPreparationRequest = nil
        dictationTranslationPreparationTaskGeneration &+= 1
    }

    private func scheduleDictationTranslationAssetPreparationIfNeeded() {
        cancelDictationTranslationAssetPreparation()
        guard dictationTranslationSupportedOnThisMac else { return }
        guard translateOnDictateEnabled else { return }
        guard window?.isVisible == true else { return }
        guard !availableDictationTargetLanguages.isEmpty else { return }

        let sourceLocaleIdentifier = currentDictationTranslationSourceLocaleIdentifier()
        let targetLanguageIdentifier = dictationTranslateTargetLanguageIdentifier
        let generation = dictationTranslationPreparationTaskGeneration
        dictationTranslationPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.dictationTranslationPreparationTaskGeneration == generation {
                    self.dictationTranslationPreparationTask = nil
                }
            }
            guard !Task.isCancelled,
                  self.dictationTranslationPreparationTaskGeneration == generation else { return }

            let plan = await self.dictationTranslationAssetPreparer.preparationPlan(
                sourceLocaleIdentifier: sourceLocaleIdentifier,
                targetLanguageIdentifier: targetLanguageIdentifier,
                isAppActive: { NSApp.isActive }
            )
            guard !Task.isCancelled,
                  self.dictationTranslationPreparationTaskGeneration == generation else { return }

            switch plan {
            case .terminal(let outcome):
                self.dictationTranslationPreparationRequest = nil
                self.handleDictationTranslationPreparationOutcome(
                    outcome,
                    sourceLocaleIdentifier: sourceLocaleIdentifier,
                    targetLanguageIdentifier: targetLanguageIdentifier
                )
            case .request(let request):
                self.dictationTranslationPreparationRequest = request
            }
        }
    }

    private func currentDictationTranslationSourceLocaleIdentifier() -> String {
        DictationController.shared.currentTranslationSourceLocaleIdentifier()
    }

    private func handleDictationTranslationPreparationOutcome(
        _ outcome: DictationTranslationAssetPreparationOutcome,
        sourceLocaleIdentifier: String,
        targetLanguageIdentifier: String
    ) {
        let source = Self.normalizeDictationTranslationIdentifier(sourceLocaleIdentifier)
        let target = Self.normalizeDictationTranslationIdentifier(targetLanguageIdentifier)
        YEN.logger.info(
            "SettingsController: dictation_translation_preparation outcome=\(String(describing: outcome)) source=\(source) target=\(target)"
        )

        switch outcome {
        case .prepared:
            let targetLabel = DictationTranslationLanguageCatalog.option(for: target).displayName
            showStatus("Translation ready: \(targetLabel)", severity: .success, duration: 3)
        case .failed:
            showStatus(
                "Translation download failed; keeping original transcript.",
                severity: .warning,
                duration: 4
            )
        case .unsupportedPair:
            showStatus(
                "Unsupported language pair for this locale.",
                severity: .warning,
                duration: 4
            )
        case .sameLanguage:
            showStatus(
                "Target matches source; translation off.",
                severity: .info,
                duration: 3
            )
        case .unsupportedOS, .alreadyInstalled, .inactiveApp:
            break
        }
    }

#if canImport(Translation)
    @available(macOS 26.0, *)
    func prepareDictationTranslationAssets(
        with session: TranslationSession,
        requestID: UUID
    ) async {
        guard let request = dictationTranslationPreparationRequest,
              request.id == requestID else { return }

        do {
            try await withTaskCancellationHandler(operation: {
                try await session.prepareTranslation()
            }, onCancel: {
                session.cancel()
            })
            guard let currentRequest = dictationTranslationPreparationRequest,
                  currentRequest.id == requestID else { return }
            dictationTranslationPreparationRequest = nil
            handleDictationTranslationPreparationOutcome(
                .prepared,
                sourceLocaleIdentifier: currentRequest.sourceLocaleIdentifier,
                targetLanguageIdentifier: currentRequest.targetLanguageIdentifier
            )
        } catch {
            if error is CancellationError {
                return
            }
            guard let currentRequest = dictationTranslationPreparationRequest,
                  currentRequest.id == requestID else { return }
            dictationTranslationPreparationRequest = nil
            handleDictationTranslationPreparationOutcome(
                .failed,
                sourceLocaleIdentifier: currentRequest.sourceLocaleIdentifier,
                targetLanguageIdentifier: currentRequest.targetLanguageIdentifier
            )
        }
    }
#endif

    // MARK: - Config Management

    /// Says what Reset All touches. It also deletes the stored background
    /// image, which the alert names when there is one.
    static func resetAllAlertMessage(hasBackgroundImage: Bool) -> String {
        var message = "This restores every setting and shortcut to its default."
        if hasBackgroundImage {
            message += " It also removes the stored background image."
        }
        return message + " You cannot undo this."
    }

    func confirmResetAllSettings() {
        presentSettingsConfirmationAlert(
            title: "Reset All Settings?",
            message: Self.resetAllAlertMessage(hasBackgroundImage: hasBackgroundImage),
            confirmButtonTitle: "Reset All"
        ) { [weak self] in
            self?.resetAllSettingsToDefaults()
        }
    }

    func confirmEndAllPersistentSessions(count: Int, onEnded: @escaping () -> Void) {
        presentSettingsConfirmationAlert(
            title: count == 1 ? "End 1 Session?" : "End All \(count) Sessions?",
            message: "Every pane's shell and the programs running in it stop, including panes open now. You cannot undo this.",
            confirmButtonTitle: "End Sessions"
        ) {
            PersistentSessions.endAllSessions()
            onEnded()
        }
    }

    func confirmRestoreDefaultShortcuts() {
        presentSettingsConfirmationAlert(
            title: "Restore Default Shortcuts?",
            message: "This restores every shortcut to its default. You cannot undo this.",
            confirmButtonTitle: "Restore"
        ) { [weak self] in
            self?.restoreDefaultShortcuts()
        }
    }

    private func presentSettingsConfirmationAlert(
        title: String,
        message: String = "",
        confirmButtonTitle: String,
        onConfirm: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        if !message.isEmpty {
            alert.informativeText = message
        }
        alert.alertStyle = .warning
        let confirmButton = alert.addButton(withTitle: confirmButtonTitle)
        confirmButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        if let window {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                onConfirm()
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
    }


    /// Show a layout status where the user can actually see it.
    ///
    /// `showStatus` only renders in the Settings footer. Layouts are applied from the
    /// File menu, a hotkey, and the command palette, so with Settings closed every
    /// message — "Layout applied", "Already a single pane", "Open a terminal window
    /// first", "No focused terminal pane", "Layout failed", and the destructive
    /// single-pane confirmation — was invisible. Mirror it onto the terminal toast
    /// stack when the Settings window is not on screen.
    func showLayoutStatus(
        _ message: String,
        severity: SettingsStatusSeverity = .success,
        duration: TimeInterval = 2,
        targetWindow: NSWindow? = nil
    ) {
        showStatus(message, severity: severity, duration: duration)
        guard window?.isVisible != true else { return }
        // Prefer the window `applyLayout` already resolved. `NSApp.keyWindow` is nil in
        // the branch the layout routing explicitly supports — no key window, main window
        // is a terminal — and returning there dropped the toast in exactly the case this
        // exists for.
        guard let windowNumber = (targetWindow ?? NSApp.keyWindow ?? NSApp.mainWindow)?.windowNumber else { return }
        NotificationCenter.default.post(
            name: .yenLayoutStatusToast,
            object: nil,
            userInfo: [
                Notification.Name.yenLayoutStatusMessageKey: message,
                Notification.Name.yenLayoutStatusWindowNumberKey: windowNumber,
                Notification.Name.yenLayoutStatusSeverityKey: Self.layoutStatusSeverityRawValue(for: severity),
            ]
        )
    }

    private static func layoutStatusSeverityRawValue(for severity: SettingsStatusSeverity) -> String {
        switch severity {
        case .success: return "success"
        case .info: return "info"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    /// The theme a reset selects: the default theme when this build ships it,
    /// otherwise none. Removing the `theme` key instead would leave the terminal
    /// on the engine's built-in colors with no tile selected.
    private var defaultThemeSelection: String {
        SettingsThemeCatalog.resolveThemeInfo(
            named: ThemeConfigRepair.defaultThemeName,
            in: currentThemeCatalogSnapshot()
        )?.configReference ?? ""
    }

    private func restoreDefaultShortcuts() {
        withCoalescedSettingsNotifications {
            restoreDefaultShortcutsTransaction()
        }
    }

    private func restoreDefaultShortcutsTransaction() {
        performManagedConfigResetTransaction(successMessage: "Default shortcuts restored") {
            keyboardRecordingActive = false
            setKeybindReloadPending(false)
            var defaults = KeybindRegistry.defaults
            let cache = refreshConflictShortcutCache()
            ConflictDetector.applyConflicts(to: &defaults, using: cache)
            keybindEntries = defaults
        }
    }

    private func resetAllSettingsToDefaults() {
        withCoalescedSettingsNotifications {
            performConfigurationResetTransaction(
                successMessage: "All settings reset to defaults",
                postSuccess: { try? TerminalBackgroundImageStore.cleanupManagedImages() }
            ) {
                suppressRealTimeConfigSync = true
                resetTypographyConfigDefaults()
                resetCommandFinishConfigDefaults()
                resetBackgroundConfigDefaults()
                backgroundImageScope = BackgroundImageScopePreferences.defaultScope
                resetPaddingConfigDefaults()
                shellIntegrationFeatures = Self.defaultShellIntegrationFeatures
                selectedTheme = defaultThemeSelection
                keyboardRecordingActive = false
                setKeybindReloadPending(false)
                var defaults = KeybindRegistry.defaults
                let cache = refreshConflictShortcutCache()
                ConflictDetector.applyConflicts(to: &defaults, using: cache)
                keybindEntries = defaults
                suppressRealTimeConfigSync = false

                applyWindowBorderDefaults()
                applyWorkspacePreferenceState(Self.defaultWorkspacePreferenceState, persist: true)
                dictationLiveTranscriptPreviewEnabled = false
                translateOnDictateEnabled = false
                dictationTranslateTargetLanguageIdentifier = Self.normalizeDictationTranslationIdentifier(
                    DictationTranslationPreferences.preferredTargetLanguageIdentifier
                )
                resetNotificationPreferencesToDefaults()
                loadNotificationSoundState()
            }
        }
    }

    private func performManagedConfigResetTransaction(
        successMessage: String,
        postSuccess: (() -> Void)? = nil,
        mutation: () -> Void
    ) {
        performConfigurationResetTransaction(successMessage: successMessage, postSuccess: postSuccess) {
            suppressRealTimeConfigSync = true
            mutation()
            suppressRealTimeConfigSync = false
        }
    }

    private func performConfigurationResetTransaction(
        successMessage: String,
        postSuccess: (() -> Void)? = nil,
        mutation: () -> Void
    ) {
        guard SettingsConfigurationReset.reset(
            captureRollback: captureConfigurationRollbackState,
            mutate: mutation,
            persist: {
                persistConfig(
                    postReloadNotification: true,
                    successMessage: successMessage,
                    failurePrefix: "Reset failed"
                )
            },
            restore: restoreConfigurationRollbackState
        ) else {
            showStatus("Reset failed: restored previous settings.", severity: .error, duration: 4)
            return
        }
        postSuccess?()
    }

    private func applyWindowBorderDefaults() {
        storeWindowBorderState(WindowBorderPreferences.defaultState)
        loadWindowBorderPreferences()
    }

    private func resetNotificationPreferencesToDefaults() {
        SettingsConfigurationReset.resetNotificationPreferencesToDefaults()
    }

    private var rollbackDictationState: SettingsConfigurationRollbackState.DictationState {
        .init(
            liveTranscriptPreviewEnabled: dictationLiveTranscriptPreviewEnabled,
            translateOnDictateEnabled: translateOnDictateEnabled,
            targetLanguageIdentifier: dictationTranslateTargetLanguageIdentifier
        )
    }

    private func captureConfigurationRollbackState() -> SettingsConfigurationRollbackState {
        SettingsConfigurationReset.captureRollbackState(
            configPath: configPath,
            workspace: captureWorkspacePreferenceState(),
            dictation: rollbackDictationState
        )
    }

    private func restoreConfigurationRollbackState(_ rollback: SettingsConfigurationRollbackState) {
        SettingsConfigurationReset.restoreRollbackState(
            rollback,
            configPath: configPath,
            writeConfigFile: { try writeConfigFile($0) },
            restoreWorkspacePreferenceState: restoreWorkspacePreferenceState,
            restoreDictation: { dictation in
                dictationLiveTranscriptPreviewEnabled = dictation.liveTranscriptPreviewEnabled
                translateOnDictateEnabled = dictation.translateOnDictateEnabled
                dictationTranslateTargetLanguageIdentifier = dictation.targetLanguageIdentifier
            }
        )
        suppressRealTimeConfigSync = true
        reloadSettingsAfterRollback()
        suppressRealTimeConfigSync = false
        reloadTerminalConfigSilently()
    }

    private func reloadSettingsAfterRollback() {
        loadConfig()
        loadThemes()
        loadWindowBorderPreferences()
        loadNotificationSoundState()
        loadKeybinds()
        setKeybindReloadPending(false)
        keyboardRecordingActive = false
    }

    private func storeWindowBorderState(_ state: WindowBorderPreferenceState) {
        SettingsConfigurationReset.storeWindowBorderState(state)
    }

    /// A managed key whose hand-written value Settings normalized on load.
    private struct LoadedRawManagedValue {
        /// The value exactly as written in `config.yen`.
        let raw: String
        /// The value Settings would write for it after normalization.
        let managed: String
    }

    /// Keys whose file value is kept verbatim while the panel has not changed them.
    ///
    /// Every write emits the whole managed list, so an unrelated edit used to
    /// rewrite each of these with its normalized form: `font-size = 13.5` became
    /// `14`, `window-padding-x = 2,4` became `2`, `cursor-style = block_hollow`
    /// became `block`. Only keys that `applyConfigContents` parses from the file
    /// belong here; `window-save-state` is a forced constant and
    /// `notify-on-command-finish-after` keeps its raw syntax through its own path.
    static let rawPreservableConfigKeys: Set<String> = [
        "font-size",
        "cursor-style",
        "cursor-style-blink",
        "copy-on-select",
        "scrollbar",
        "notify-on-command-finish",
        "notify-on-command-finish-action",
        "background-opacity",
        "window-padding-x",
        "window-padding-y",
    ]

    private var loadedRawManagedValues: [String: LoadedRawManagedValue] = [:]

    private func discardLoadedRawManagedValues(for keys: [String]) {
        guard !loadedRawManagedValues.isEmpty else { return }
        for key in keys {
            loadedRawManagedValues.removeValue(forKey: key)
        }
    }

    /// Record the file values that differ from what Settings would write for them.
    /// A key that appears more than once is skipped: the reader takes the last
    /// occurrence and the merge keeps the first, so no single line is "the" value.
    private func recordLoadedRawManagedValues(from contents: String) {
        var rawValues: [String: [String]] = [:]
        for line in contents.components(separatedBy: .newlines) {
            guard let entry = Self.configEntry(from: line),
                  Self.rawPreservableConfigKeys.contains(entry.key) else { continue }
            rawValues[entry.key, default: []].append(entry.value)
        }

        var recorded: [String: LoadedRawManagedValue] = [:]
        for (key, managed) in buildSettingsList() {
            guard let values = rawValues[key], values.count == 1, values[0] != managed else { continue }
            recorded[key] = LoadedRawManagedValue(raw: values[0], managed: managed)
        }
        loadedRawManagedValues = recorded
    }

    /// Swap a managed value back to the file's own spelling when the panel has
    /// not changed that setting since it was loaded and the line is still there.
    private func settingsListPreservingLoadedRawValues(
        _ settings: [(String, String)],
        existingLines: [String]
    ) -> [(String, String)] {
        guard !loadedRawManagedValues.isEmpty else { return settings }

        var existingValues: [String: [String]] = [:]
        for line in existingLines {
            guard let entry = Self.configEntry(from: line),
                  loadedRawManagedValues[entry.key] != nil else { continue }
            existingValues[entry.key, default: []].append(entry.value)
        }

        return settings.map { key, value in
            guard let loaded = loadedRawManagedValues[key],
                  loaded.managed == value,
                  existingValues[key] == [loaded.raw] else {
                return (key, value)
            }
            return (key, loaded.raw)
        }
    }

    func loadConfig() {
        withCoalescedSettingsNotifications {
            resetManagedConfigState()

            guard FileManager.default.fileExists(atPath: configPath) else {
                // Use defaults if no config exists
                return
            }

            guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
                return
            }

            applyConfigContents(contents, resetManagedState: false)
            recordLoadedRawManagedValues(from: contents)
        }
    }

    private func applyConfigContents(_ contents: String, resetManagedState: Bool = true) {
        if resetManagedState {
            resetManagedConfigState()
        }

        var sawFontFamily = false

        for line in contents.components(separatedBy: .newlines) {
            guard let entry = Self.configEntry(from: line) else { continue }

            switch entry.key {
            case "font-family":
                // FIRST occurrence wins, matching the writer. `font-family` is repeatable
                // (a fallback chain) and `ManagedConfigDocument.merged` replaces only the
                // FIRST occurrence with the managed value. A last-wins reader would load
                // the final fallback — typically a symbol or emoji font — and the next
                // Settings write would then stamp that over the user's primary family.
                if !sawFontFamily {
                    fontFamily = entry.value
                    sawFontFamily = true
                }
            case "font-size":
                fontSize = Double(entry.value) ?? 14
            case "cursor-style":
                cursorStyle = Self.normalizedCursorStyle(entry.value)
            case "cursor-style-blink":
                cursorBlink = Self.parsedBoolean(entry.value) ?? Self.defaultCursorBlink
            case "copy-on-select":
                copyOnSelect = Self.parsedCopyOnSelect(entry.value) ?? false
            case "scrollbar":
                scrollbarVisibility = Self.normalizedScrollbarVisibility(entry.value)
            case "notify-on-command-finish":
                notifyOnCommandFinish = Self.normalizedNotifyOnCommandFinish(entry.value)
            case "notify-on-command-finish-action":
                let parsed = Self.parsedNotifyOnCommandFinishAction(entry.value)
                notifyOnCommandFinishActionBell = parsed?.bell ?? Self.defaultNotifyOnCommandFinishActionBell
                notifyOnCommandFinishActionNotify = parsed?.notify ?? Self.defaultNotifyOnCommandFinishActionNotify
            case "notify-on-command-finish-after":
                if let parsed = Self.parsedNotifyOnCommandFinishAfter(entry.value) {
                    applyNotifyOnCommandFinishAfter(
                        configValue: parsed.configValue,
                        displaySeconds: parsed.displaySeconds
                    )
                } else {
                    resetNotifyOnCommandFinishAfterToDefault()
                }
            case "background-opacity":
                if let parsed = Double(entry.value), parsed.isFinite {
                    backgroundOpacity = parsed
                } else {
                    backgroundOpacity = Self.defaultBackgroundOpacity
                }
            case "background-image":
                backgroundImagePath = TerminalBackgroundImageStore.normalizedConfigPath(entry.value)
            case "window-padding-x":
                windowPaddingX = Int(entry.value) ?? Self.defaultWindowPaddingX
            case "window-padding-y":
                windowPaddingY = Int(entry.value) ?? Self.defaultWindowPaddingY
            case "shell-integration-features":
                shellIntegrationFeatures = entry.value
            case "theme":
                selectedTheme = Self.normalizedThemeName(entry.value)
            default:
                break
            }
        }

        clampManagedConfigValues()
    }

    private func resetTypographyConfigDefaults() {
        discardLoadedRawManagedValues(
            for: ["font-size", "cursor-style", "cursor-style-blink", "copy-on-select", "scrollbar"]
        )
        fontFamily = Self.defaultFontFamily
        fontSize = Self.defaultFontSize
        cursorStyle = Self.defaultCursorStyle
        cursorBlink = Self.defaultCursorBlink
        copyOnSelect = Self.defaultCopyOnSelect
        scrollbarVisibility = Self.defaultScrollbarVisibility
    }

    private func resetCommandFinishConfigDefaults() {
        discardLoadedRawManagedValues(
            for: ["notify-on-command-finish", "notify-on-command-finish-action"]
        )
        notifyOnCommandFinish = Self.defaultNotifyOnCommandFinish
        notifyOnCommandFinishActionBell = Self.defaultNotifyOnCommandFinishActionBell
        notifyOnCommandFinishActionNotify = Self.defaultNotifyOnCommandFinishActionNotify
        resetNotifyOnCommandFinishAfterToDefault()
    }

    private func resetBackgroundConfigDefaults() {
        discardLoadedRawManagedValues(for: ["background-opacity"])
        backgroundOpacity = Self.defaultBackgroundOpacity
        backgroundImagePath = ""
    }

    private func resetPaddingConfigDefaults() {
        discardLoadedRawManagedValues(for: ["window-padding-x", "window-padding-y"])
        windowPaddingX = Self.defaultWindowPaddingX
        windowPaddingY = Self.defaultWindowPaddingY
    }

    private func resetManagedConfigState() {
        resetTypographyConfigDefaults()
        resetCommandFinishConfigDefaults()
        resetBackgroundConfigDefaults()
        resetPaddingConfigDefaults()
        shellIntegrationFeatures = Self.defaultShellIntegrationFeatures
        selectedTheme = ""
    }

    private func clampManagedConfigValues() {
        let normalizedFontSize = Self.normalizedFontSize(fontSize)
        if normalizedFontSize != fontSize {
            fontSize = normalizedFontSize
        }

        let clampedNotifyDelay = Self.clampedNotifyOnCommandFinishAfterSeconds(
            notifyOnCommandFinishAfterSeconds
        )
        if clampedNotifyDelay != notifyOnCommandFinishAfterSeconds {
            notifyOnCommandFinishAfterSeconds = clampedNotifyDelay
        }

        let normalizedBackgroundOpacity = Self.normalizedBackgroundOpacity(backgroundOpacity)
        if normalizedBackgroundOpacity != backgroundOpacity {
            backgroundOpacity = normalizedBackgroundOpacity
        }

        let clampedWindowPaddingX = Self.clampedWindowPadding(windowPaddingX)
        if clampedWindowPaddingX != windowPaddingX {
            windowPaddingX = clampedWindowPaddingX
        }

        let clampedWindowPaddingY = Self.clampedWindowPadding(windowPaddingY)
        if clampedWindowPaddingY != windowPaddingY {
            windowPaddingY = clampedWindowPaddingY
        }
    }

    private nonisolated static func clampedWindowPadding(_ value: Int) -> Int {
        min(max(value, 0), 50)
    }

    private static func clampedBackgroundOpacity(_ backgroundOpacity: Double) -> Double {
        guard backgroundOpacity.isFinite else { return defaultBackgroundOpacity }
        return min(max(backgroundOpacity, minBackgroundOpacity), maxBackgroundOpacity)
    }

    private static func normalizedBackgroundOpacity(_ backgroundOpacity: Double) -> Double {
        let clamped = clampedBackgroundOpacity(backgroundOpacity)
        return (clamped * 20).rounded(.toNearestOrAwayFromZero) / 20
    }

    private func refreshBackgroundImagePresentationState() {
        backgroundImagePreviewVersion &+= 1
        let normalizedPath = TerminalBackgroundImageStore.normalizedConfigPath(backgroundImagePath)
        guard !normalizedPath.isEmpty else {
            backgroundImagePreview = nil
            backgroundImageIssueDescription = ""
            return
        }

        guard FileManager.default.fileExists(atPath: normalizedPath) else {
            backgroundImagePreview = nil
            backgroundImageIssueDescription = "File missing. Replace or remove it."
            return
        }

        // Skip the DECODE during launch-time hydration ONLY. It reads and decodes the
        // image at full resolution and keeps the NSImage resident, so running it from
        // `init()` put that cost on the launch path — and held the image for the whole
        // session — for a user who never opens Settings. Scoped to the init window rather
        // than a persistent "has presented" flag so every other path, including tests,
        // behaves exactly as before; `performVisibleSessionRefresh` builds it on present.
        guard !isHydratingConfigAtLaunch else {
            backgroundImagePreview = nil
            backgroundImageIssueDescription = ""
            return
        }

        guard let preview = TerminalBackgroundImageStore.previewImage(for: normalizedPath) else {
            backgroundImagePreview = nil
            backgroundImageIssueDescription = "Can't decode image. Replace or remove it."
            return
        }

        backgroundImagePreview = preview
        backgroundImageIssueDescription =
            TerminalBackgroundImageStore.isSupportedRenderableImage(at: normalizedPath)
                ? ""
                : "Unsupported format; use PNG or JPEG."
    }

    private nonisolated static func normalizedScrollbarVisibility(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "never":
            return "never"
        default:
            return "system"
        }
    }

    private nonisolated static func parsedNotifyOnCommandFinish(_ rawValue: String) -> String? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "never":
            return "never"
        case "unfocused":
            return "unfocused"
        case "always":
            return "always"
        default:
            return nil
        }
    }

    private nonisolated static func normalizedCursorStyle(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bar":
            return "bar"
        case "underline":
            return "underline"
        default:
            return "block"
        }
    }

    private nonisolated static func normalizedNotifyOnCommandFinish(_ rawValue: String) -> String {
        parsedNotifyOnCommandFinish(rawValue) ?? "never"
    }

    private nonisolated static func notifyOnCommandFinishActionValue(
        bell: Bool,
        notify: Bool
    ) -> String {
        [
            bell ? "bell" : "no-bell",
            notify ? "notify" : "no-notify",
        ].joined(separator: ",")
    }

    private nonisolated static func parsedNotifyOnCommandFinishAction(
        _ rawValue: String
    ) -> (bell: Bool, notify: Bool)? {
        let tokens = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        var bell = true
        var notify = false

        for token in tokens {
            switch token {
            case "bell":
                bell = true
            case "no-bell":
                bell = false
            case "notify":
                notify = true
            case "no-notify":
                notify = false
            default:
                return nil
            }
        }

        return (bell: bell, notify: notify)
    }

    private nonisolated static func parsedBoolean(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private nonisolated static func parsedCopyOnSelect(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "clipboard", "both":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private nonisolated static func clampedNotifyOnCommandFinishAfterSeconds(_ value: Int) -> Int {
        min(max(value, 0), 999_999)
    }

    private nonisolated static func notifyOnCommandFinishAfterValue(_ seconds: Int) -> String {
        "\(clampedNotifyOnCommandFinishAfterSeconds(seconds))s"
    }

    private func applyNotifyOnCommandFinishAfter(
        configValue: String,
        displaySeconds: Int
    ) {
        preserveNotifyOnCommandFinishAfterConfigValue = true
        notifyOnCommandFinishAfterConfigValue = configValue
        notifyOnCommandFinishAfterSeconds = displaySeconds
        preserveNotifyOnCommandFinishAfterConfigValue = false
    }

    private func resetNotifyOnCommandFinishAfterToDefault() {
        applyNotifyOnCommandFinishAfter(
            configValue: Self.notifyOnCommandFinishAfterValue(
                Self.defaultNotifyOnCommandFinishAfterSeconds
            ),
            displaySeconds: Self.defaultNotifyOnCommandFinishAfterSeconds
        )
    }

    private nonisolated static func parsedNotifyOnCommandFinishAfter(
        _ rawValue: String
    ) -> (configValue: String, displaySeconds: Int)? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "0" {
            return (configValue: "0", displaySeconds: 0)
        }

        let units: [(String, Double)] = [
            ("ms", 0.001),
            ("us", 0.000_001),
            ("µs", 0.000_001),
            ("ns", 0.000_000_001),
            ("y", 31_536_000),
            ("w", 604_800),
            ("d", 86_400),
            ("h", 3_600),
            ("m", 60),
            ("s", 1),
        ]

        var index = trimmed.startIndex
        var totalSeconds = 0.0
        var matched = false
        var normalizedParts: [String] = []

        func skipWhitespace() {
            while index < trimmed.endIndex, trimmed[index].isWhitespace {
                index = trimmed.index(after: index)
            }
        }

        while index < trimmed.endIndex {
            skipWhitespace()
            guard index < trimmed.endIndex else { break }

            let digitsStart = index
            while index < trimmed.endIndex, trimmed[index].isNumber {
                index = trimmed.index(after: index)
            }

            guard digitsStart != index,
                  let amount = Double(trimmed[digitsStart..<index]) else {
                return nil
            }
            let amountToken = String(trimmed[digitsStart..<index])

            skipWhitespace()
            guard index < trimmed.endIndex else { return nil }

            guard let (unit, multiplier) = units.first(where: {
                trimmed[index...].hasPrefix($0.0)
            }) else {
                return nil
            }

            index = trimmed.index(index, offsetBy: unit.count)
            totalSeconds += amount * multiplier
            matched = true
            normalizedParts.append("\(amountToken)\(unit)")
        }

        guard matched, totalSeconds.isFinite, totalSeconds >= 0 else {
            return nil
        }

        return (
            configValue: normalizedParts.joined(),
            displaySeconds: clampedNotifyOnCommandFinishAfterSeconds(
                Int(totalSeconds.rounded(.up))
            )
        )
    }

    private func handleConfigReloadNotification() {
        if pendingSelfInitiatedConfigReloadNotifications > 0 {
            pendingSelfInitiatedConfigReloadNotifications -= 1
            return
        }

        handleExternalConfigReload()
        if consumeConfigReloadForKeybinds(isSettingsVisible: window?.isVisible == true) {
            scheduleKeybindReload()
        }
    }

    private func handleExternalConfigReload() {
        guard window?.isVisible == true else {
            refreshThemeContextFromDisk(
                reloadThemeCatalog: windowBorderColorMode == .matchTheme
                    && testThemeNameOnConfigReload == nil
            )
            return
        }

        suppressRealTimeConfigSync = true
        defer { suppressRealTimeConfigSync = false }
        loadConfig()
        // Re-read the active theme from disk even when the Settings window is
        // open so config reload notifications keep Match Theme state in sync.
        refreshSelectedThemeFromConfig()

        // The live preview shows the theme in every pane, so the resolved theme
        // and the catalog both follow an external edit.
        refreshResolvedActiveThemeInfo(forceRefreshSnapshot: testThemeNameOnConfigReload == nil)
        if testThemeNameOnConfigReload == nil {
            scheduleThemeReloadIfNeeded(force: true)
        }

        if !themePreview.isPreviewActive {
            originalThemeName = selectedTheme
        }
    }

    private func refreshThemeContextFromDisk(reloadThemeCatalog: Bool = true) {
        if let testThemeNameOnConfigReload {
            selectedTheme = testThemeNameOnConfigReload() ?? ""
            return
        }

        if reloadThemeCatalog {
            loadThemes()
        }
        refreshSelectedThemeFromConfig()
    }

    private func refreshSelectedThemeFromConfig() {
        if let testThemeNameOnConfigReload {
            selectedTheme = testThemeNameOnConfigReload() ?? ""
            return
        }
        guard FileManager.default.fileExists(atPath: configPath) else {
            selectedTheme = ""
            return
        }
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            selectedTheme = ""
            return
        }
        selectedTheme = Self.extractThemeName(from: contents)
    }

    static func extractThemeName(from contents: String) -> String {
        for line in contents.components(separatedBy: .newlines) {
            guard let entry = Self.configEntry(from: line),
                  entry.key.lowercased() == "theme" else {
                continue
            }
            return normalizedThemeName(entry.value)
        }

        return ""
    }

    nonisolated static func themeSelectionMatches(
        selectedTheme: String,
        catalogThemeName: String
    ) -> Bool {
        let selectedKey = normalizedThemeLookupKey(selectedTheme)
        let catalogKey = normalizedThemeLookupKey(catalogThemeName)
        guard !selectedKey.isEmpty, !catalogKey.isEmpty else { return false }
        return selectedKey == catalogKey
    }

    private nonisolated static func normalizedThemeName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private nonisolated static func normalizedThemeLookupKey(_ rawValue: String) -> String {
        let normalizedName = normalizedThemeName(rawValue)
        guard !normalizedName.isEmpty else { return "" }

        var baseName = normalizedName
        let lowercasedName = normalizedName.lowercased()
        if lowercasedName.hasSuffix(".yentheme") {
            baseName = String(normalizedName.dropLast(9))
        } else if lowercasedName.hasSuffix(".yen") {
            baseName = String(normalizedName.dropLast(4))
        }

        let folded = baseName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded
            .lowercased()
            .replacingOccurrences(of: "[\\s\\-_]+", with: "", options: .regularExpression)
    }

    func loadWorkspacePreferences() {
        applyWorkspacePreferenceState(
            workspacePreferenceState(from: .standard),
            persist: false,
            preserveTransientSidebar: true
        )
    }

    func captureWorkspacePreferenceState() -> WorkspacePreferenceState {
        WorkspacePreferenceState(
            tabSidebarEnabled: tabSidebarEnabled,
            tabSidebarPresentationMode: tabSidebarPresentationMode,
            tabSidebarPersistentVisible: TabSidebarController.persistentVisible,
            paneStyle: paneStyle,
            splitPaneLabelsEnabled: splitPaneLabelsEnabled,
            splitPaneWorktreeNamingEnabled: splitPaneWorktreeNamingEnabled,
            browserTerminalLinkCaptureEnabled: browserTerminalLinkCaptureEnabled,
            browserSplitEnabled: browserSplitEnabled,
            scratchpadEnabled: scratchpadEnabled,
            backgroundImageScope: backgroundImageScope
        )
    }

    func restoreWorkspacePreferenceState(_ state: WorkspacePreferenceState) {
        applyWorkspacePreferenceState(state, persist: true)
    }

    private static let defaultWorkspacePreferenceState = WorkspacePreferenceState(
        tabSidebarEnabled: TabSidebarPreferences.defaultEnabled,
        tabSidebarPresentationMode: TabSidebarPreferences.defaultPresentationMode,
        tabSidebarPersistentVisible: TabSidebarPreferences.defaultPersistentVisible,
        splitPaneLabelsEnabled: SplitPaneLabelsPreferences.defaultEnabled,
        splitPaneWorktreeNamingEnabled: SplitPaneLabelsPreferences.defaultWorktreeNamingEnabled,
        browserTerminalLinkCaptureEnabled: NativeBrowserPreferences.defaultTerminalLinkCaptureEnabled,
        browserSplitEnabled: NativeBrowserPreferences.defaultBrowserSplitEnabled,
        scratchpadEnabled: true,
        backgroundImageScope: BackgroundImageScopePreferences.defaultScope
    )

    private func workspacePreferenceState(from defaults: UserDefaults) -> WorkspacePreferenceState {
        WorkspacePreferenceState(
            tabSidebarEnabled: TabSidebarPreferences.enabled(from: defaults),
            tabSidebarPresentationMode: TabSidebarPreferences.repairedPresentationMode(in: defaults),
            tabSidebarPersistentVisible: TabSidebarPreferences.persistentVisible(from: defaults),
            paneStyle: PaneStyle.stored(in: defaults),
            splitPaneLabelsEnabled: SplitPaneLabelsPreferences.enabled(from: defaults),
            splitPaneWorktreeNamingEnabled:
                SplitPaneLabelsPreferences.worktreeNamingEnabled(from: defaults),
            browserTerminalLinkCaptureEnabled: NativeBrowserPreferences.terminalLinkCaptureEnabled(from: defaults),
            browserSplitEnabled: NativeBrowserPreferences.browserSplitEnabled(from: defaults),
            scratchpadEnabled:
                defaults.object(forKey: ScratchpadController.scratchpadEnabledPreferenceKey) as? Bool ?? true,
            backgroundImageScope: BackgroundImageScopePreferences.scope(from: defaults)
        )
    }

    private func storeWorkspacePreferenceState(_ state: WorkspacePreferenceState) {
        let defaults = UserDefaults.standard
        defaults.set(state.paneStyle.rawValue, forKey: PaneStyle.preferenceKey)
        defaults.set(state.tabSidebarEnabled, forKey: TabSidebarPreferences.enabledPreferenceKey)
        defaults.set(
            state.tabSidebarPresentationMode.rawValue,
            forKey: TabSidebarPreferences.presentationModePreferenceKey
        )
        defaults.set(
            state.tabSidebarPersistentVisible,
            forKey: TabSidebarPreferences.persistentVisiblePreferenceKey
        )
        defaults.set(
            state.splitPaneLabelsEnabled,
            forKey: SplitPaneLabelsPreferences.enabledPreferenceKey
        )
        defaults.set(
            state.splitPaneWorktreeNamingEnabled,
            forKey: SplitPaneLabelsPreferences.worktreeNamingEnabledPreferenceKey
        )
        defaults.set(
            state.browserTerminalLinkCaptureEnabled,
            forKey: NativeBrowserPreferences.terminalLinkCaptureEnabledPreferenceKey
        )
        defaults.set(
            state.browserSplitEnabled,
            forKey: NativeBrowserPreferences.browserSplitEnabledPreferenceKey
        )
        defaults.set(state.scratchpadEnabled, forKey: ScratchpadController.scratchpadEnabledPreferenceKey)
        defaults.set(state.backgroundImageScope.rawValue, forKey: BackgroundImageScopePreferences.preferenceKey)
    }

    private func applyWorkspacePreferenceState(
        _ state: WorkspacePreferenceState,
        persist: Bool,
        preserveTransientSidebar: Bool = false
    ) {
        let previousState = captureWorkspacePreferenceState()
        if persist {
            storeWorkspacePreferenceState(state)
        }

        let previousSuppression = suppressWorkspacePreferencePersistence
        suppressWorkspacePreferencePersistence = true
        tabSidebarEnabled = state.tabSidebarEnabled
        tabSidebarPresentationMode = state.tabSidebarPresentationMode
        paneStyle = state.paneStyle
        splitPaneLabelsEnabled = state.splitPaneLabelsEnabled
        splitPaneWorktreeNamingEnabled = state.splitPaneWorktreeNamingEnabled
        browserTerminalLinkCaptureEnabled = state.browserTerminalLinkCaptureEnabled
        browserSplitEnabled = state.browserSplitEnabled
        scratchpadEnabled = state.scratchpadEnabled
        backgroundImageScope = state.backgroundImageScope
        suppressWorkspacePreferencePersistence = previousSuppression

        TabSidebarController.shared.applyWorkspacePreferenceStateTransition(
            from: previousState,
            to: state,
            preserveTransientVisibility: preserveTransientSidebar
        )
        if !state.scratchpadEnabled && ScratchpadController.shared.visible {
            ScratchpadController.shared.toggle()
        }
    }

    func loadWindowBorderPreferences() {
        let state = WindowBorderPreferences.state()
        suppressWindowBorderPersistence = true
        defer { suppressWindowBorderPersistence = false }

        windowBorderEnabled = state.enabled
        windowBorderScope = state.scope
        windowBorderWidth = state.width
        windowBorderRadius = state.radius
        windowBorderColorMode = state.colorMode
        windowBorderFocusedPalette = state.focusedPalette
        windowBorderUnfocusedPalette = state.unfocusedPalette
        if state.colorMode == .matchTheme {
            refreshResolvedActiveThemeInfo()
        }
    }

    func toggleWindowBorderEnabled() {
        windowBorderEnabled.toggle()
    }

    func toggleWindowBorderScope() {
        windowBorderScope = windowBorderScope == .window ? .focusedSplit : .window
    }

    @discardableResult
    func cycleWindowBorderFocusedPalette() -> Bool {
        guard windowBorderColorMode == .manual else { return false }
        windowBorderFocusedPalette = nextWindowBorderPalette(after: windowBorderFocusedPalette)
        return true
    }

    @discardableResult
    func cycleWindowBorderUnfocusedPalette() -> Bool {
        guard windowBorderColorMode == .manual else { return false }
        windowBorderUnfocusedPalette = nextWindowBorderPalette(after: windowBorderUnfocusedPalette)
        return true
    }

    @MainActor
    func openReduceMotionSettings() {
        SystemSettingsOpener.openAccessibilityDisplaySettings()
    }

    @MainActor
    func openDifferentiateWithoutColorSettings() {
        SystemSettingsOpener.openAccessibilityDisplaySettings()
    }

    private func nextWindowBorderPalette(after palette: WindowBorderPalette) -> WindowBorderPalette {
        let palettes = WindowBorderPalette.allCases
        guard !palettes.isEmpty, let currentIndex = palettes.firstIndex(of: palette) else {
            return palette
        }
        let nextIndex = (currentIndex + 1) % palettes.count
        return palettes[nextIndex]
    }

    private func refreshAvailableFontsForCurrentSelectionIfNeeded() {
        guard !availableFonts.isEmpty || Self.cachedMonospaceFonts != nil else { return }
        loadAvailableFonts()
    }

    private func loadAvailableFonts() {
        if let cached = Self.cachedMonospaceFonts {
            availableFonts = Self.fontCatalogIncludingCurrentFont(
                cached,
                currentFontFamily: fontFamily
            )
        } else {
            let fonts = Self.buildMonospaceFontCatalog()
            Self.cachedMonospaceFonts = fonts
            availableFonts = Self.fontCatalogIncludingCurrentFont(
                fonts,
                currentFontFamily: fontFamily
            )
        }
    }

    // MARK: - Config Helpers

    private func scheduleRealTimeConfigSyncIfNeeded<T: Equatable>(oldValue: T, newValue: T) {
        guard oldValue != newValue else { return }
        scheduleRealTimeConfigSync()
    }

    private func scheduleRealTimeConfigSync() {
        guard !suppressRealTimeConfigSync else { return }
        guard window?.isVisible == true else {
            realTimeConfigSyncWork?.cancel()
            realTimeConfigSyncWork = nil
            _ = persistConfig(
                postReloadNotification: false,
                successMessage: nil,
                failurePrefix: "Apply failed"
            )
            return
        }

        realTimeConfigSyncWork?.cancel()
        var work: DispatchWorkItem?
        work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer {
                if let work, self.realTimeConfigSyncWork === work {
                    self.realTimeConfigSyncWork = nil
                }
            }
            _ = self.persistConfig(postReloadNotification: false, successMessage: nil, failurePrefix: "Apply failed")
        }
        realTimeConfigSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work!)
    }

    private func flushPendingRealTimeConfigSyncIfNeeded() {
        guard realTimeConfigSyncWork != nil else { return }
        realTimeConfigSyncWork?.cancel()
        realTimeConfigSyncWork = nil
        _ = persistConfig(postReloadNotification: false, successMessage: nil, failurePrefix: "Apply failed")
    }

    /// Flush BOTH debounced writers before the process exits.
    ///
    /// The theme selection has its own 150 ms debounce, separate from the real-time
    /// config sync. Flushing only the latter lost a theme click made within that
    /// window when no other config edit was pending — the tile showed as selected and
    /// the choice was gone on relaunch. Order matches `windowWillClose`: theme first,
    /// so `persistConfig`'s `buildSettingsList()` sees the committed selection.
    func flushPendingRealTimeConfigSyncForApplicationTermination() {
        commitPendingThemeSelectionIfNeeded()
        flushPendingRealTimeConfigSyncIfNeeded()
    }

    @discardableResult
    private func persistConfig(
        postReloadNotification: Bool,
        successMessage: String?,
        failurePrefix: String
    ) -> Bool {
        // Restore original config before reading so color keys stripped
        // during preview are not permanently lost.
        themePreview.cancelAndRestore()

        let contents = currentManagedConfigContents()

        do {
            try writeConfigFile(contents)
        } catch {
            showStatus("\(failurePrefix): \(error.localizedDescription)", severity: .error, duration: 4)
            return false
        }

        if postReloadNotification {
            reloadTerminalConfig()
        } else {
            reloadTerminalConfigSilently()
        }
        if let successMessage {
            showStatus(successMessage)
        }
        return true
    }

    /// The config file contents Settings would write now: the managed keys and
    /// the shortcut overrides merged into the lines already on disk. A value
    /// Settings normalized on load stays as the user wrote it until the panel
    /// changes it.
    private func currentManagedConfigContents() -> String {
        let existingLines = readExistingConfigLines()
        let managedLines = managedConfigDocument(preservingLoadedRawValuesIn: existingLines)
            .merged(intoExistingLines: existingLines)
        return KeybindConfigMerger.mergingKeybindOverrides(into: managedLines, entries: keybindEntries)
            .joined(separator: "\n")
    }

    private func surfaceBackgroundRuntimeConfigContents(
        useWholeWindowOverride: Bool
    ) -> String {
        let contents = currentManagedConfigContents()
        guard useWholeWindowOverride else { return contents }
        return Self.configByApplyingKeyOverrides(
            [
                // Make surfaces transparent so the SwiftUI WholeWindowBackgroundView
                // behind them is visible. That view provides the background color
                // tint at the user's configured opacity.
                ("background-opacity", "0.0"),
                ("background-image-opacity", "0.0"),
            ],
            to: contents
        )
    }

    func wholeWindowBackgroundRuntimeConfigContents() -> String {
        surfaceBackgroundRuntimeConfigContents(useWholeWindowOverride: true)
    }

    func currentManagedSurfaceConfigContents() -> String {
        surfaceBackgroundRuntimeConfigContents(useWholeWindowOverride: false)
    }

    @discardableResult
    func writeSurfaceBackgroundRuntimeConfig(useWholeWindowOverride: Bool) throws -> String {
        let path = wholeWindowBackgroundRuntimeConfigPath
        try writeConfigFile(
            surfaceBackgroundRuntimeConfigContents(useWholeWindowOverride: useWholeWindowOverride),
            to: path
        )
        return path
    }

    @discardableResult
    func writeWholeWindowBackgroundRuntimeConfig() throws -> String {
        try writeSurfaceBackgroundRuntimeConfig(useWholeWindowOverride: true)
    }

    @discardableResult
    func writeCurrentManagedSurfaceConfig() throws -> String {
        try writeSurfaceBackgroundRuntimeConfig(useWholeWindowOverride: false)
    }

    var wholeWindowBackgroundRuntimeConfigPath: String {
        Self.wholeWindowBackgroundRuntimeConfigPath(for: configPath)
    }

    func removeWholeWindowBackgroundRuntimeConfigIfPresent() {
        Self.removeWholeWindowBackgroundRuntimeConfigIfPresent(
            at: wholeWindowBackgroundRuntimeConfigPath
        )
    }

    private func readExistingConfigLines() -> [String] {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return []
        }
        return contents.components(separatedBy: .newlines)
    }

    /// Build the list of managed settings key-value pairs from current state.
    private func buildSettingsList() -> [(String, String)] {
        let normalizedBackgroundOpacity = Self.normalizedBackgroundOpacity(backgroundOpacity)
        var settings: [(String, String)] = [
            ("font-family", fontFamily),
            ("font-size", String(Int(Self.normalizedFontSize(fontSize)))),
            ("cursor-style", cursorStyle),
            ("cursor-style-blink", cursorBlink ? "true" : "false"),
            ("copy-on-select", copyOnSelect ? "both" : "false"),
            ("scrollbar", Self.normalizedScrollbarVisibility(scrollbarVisibility)),
            ("notify-on-command-finish", Self.normalizedNotifyOnCommandFinish(notifyOnCommandFinish)),
            (
                "notify-on-command-finish-action",
                Self.notifyOnCommandFinishActionValue(
                    bell: notifyOnCommandFinishActionBell,
                    notify: notifyOnCommandFinishActionNotify
                )
            ),
            (
                "notify-on-command-finish-after",
                notifyOnCommandFinishAfterConfigValue
            ),
            ("shell-integration-features", shellIntegrationFeaturesWithNoCursor()),
            ("background-opacity", String(format: "%.2f", normalizedBackgroundOpacity)),
            ("window-padding-x", String(windowPaddingX)),
            ("window-padding-y", String(windowPaddingY)),
            ("window-save-state", "always"),
        ]
        if !backgroundImagePath.isEmpty {
            settings.append(
                ("background-image", TerminalBackgroundImageStore.quotedConfigPath(backgroundImagePath))
            )
            settings.append(("background-image-fit", "cover"))
            settings.append(("background-image-opacity", "1.0"))
            settings.append(("background-image-repeat", "false"))
        }
        if !selectedTheme.isEmpty {
            settings.append(("theme", selectedTheme))
        }
        return settings
    }

    /// Snapshot the managed config as a pure `ManagedConfigDocument` value. The
    /// merge algorithm itself lives on that value type (directly unit-testable).
    private func managedConfigDocument(
        preservingLoadedRawValuesIn existingLines: [String]? = nil
    ) -> ManagedConfigDocument {
        var settings = buildSettingsList()
        if let existingLines {
            settings = settingsListPreservingLoadedRawValues(settings, existingLines: existingLines)
        }
        return ManagedConfigDocument(
            settings: settings.map { ManagedConfigDocument.Entry(key: $0.0, value: $0.1) },
            hasSelectedTheme: !selectedTheme.isEmpty,
            hasBackgroundImage: !backgroundImagePath.isEmpty
        )
    }

    private static func extractKeyValues(for keys: Set<String>, from contents: String) -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        var values: [String: String] = [:]

        for line in contents.components(separatedBy: .newlines) {
            guard let entry = Self.configEntry(from: line),
                  keys.contains(entry.key),
                  values[entry.key] == nil else {
                continue
            }
            values[entry.key] = entry.value
        }

        return values
    }

    /// Merge-safe rollback of preview-modified keys. Returns nil when rollback should
    /// remove the config file entirely (baseline was missing and no keys remain).
    static func configByRollingBackThemePreview(
        currentContents: String,
        baselineContents: String?,
        baselineWasMissing: Bool,
        previewThemeName: String
    ) -> String? {
        let rollbackKeys = themeColorKeys.union(["theme"])
        let baselineValues = extractKeyValues(for: rollbackKeys, from: baselineContents ?? "")
        let currentValues = extractKeyValues(for: rollbackKeys, from: currentContents)

        var overrides: [(String, String?)] = []
        let previewThemeStillActive = currentValues["theme"] == previewThemeName
        if previewThemeStillActive {
            overrides.append(("theme", baselineValues["theme"]))
            for key in themeColorKeys.sorted() where currentValues[key] == nil {
                overrides.append((key, baselineValues[key]))
            }
        }

        guard !overrides.isEmpty else {
            return currentContents
        }

        var merged = configByApplyingKeyOverrides(overrides, to: currentContents)

        // `configByApplyingKeyOverrides` writes ONE line per key, and the baseline
        // extraction above keeps only the first occurrence — so a hand-authored 16-line
        // `palette` block came back as a single line and fifteen were lost on revert.
        // `palette` is the only repeatable key in `themeColorKeys`, but this is written
        // against the shared set so a future addition is covered automatically.
        if previewThemeStillActive {
            let repeatableRollbackKeys = rollbackKeys
                .intersection(ManagedConfigDocument.repeatableKeys)
                .sorted()
            var restoredTail: [String] = []
            for key in repeatableRollbackKeys where currentValues[key] == nil {
                let baselineOccurrences = extractAllKeyValues(for: key, from: baselineContents ?? "")
                // The first occurrence is already restored by the override above.
                for value in baselineOccurrences.dropFirst() {
                    restoredTail.append("\(key) = \(value)")
                }
            }
            if !restoredTail.isEmpty {
                merged += (merged.hasSuffix("\n") ? "" : "\n") + restoredTail.joined(separator: "\n")
            }
        }

        if baselineWasMissing
            && merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }

        return merged
    }

    /// Every occurrence of `key` in `contents`, in file order.
    ///
    /// `extractKeyValues` keeps only the FIRST occurrence, which silently truncates a
    /// repeatable key. Used by theme-preview rollback to put a multi-line `palette` block
    /// back intact.
    private static func extractAllKeyValues(for key: String, from contents: String) -> [String] {
        contents
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard let entry = Self.configEntry(from: line), entry.key == key else { return nil }
                return entry.value
            }
    }

    /// Apply theme selection to raw config text:
    /// - replace/add `theme = ...`
    /// - remove explicit color keys so theme colors take effect
    static func configByApplyingTheme(_ themeName: String, to contents: String) -> String {
        if contents.isEmpty {
            return "theme = \(themeName)"
        }

        var newLines: [String] = []
        var wroteTheme = false

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                newLines.append(line)
                continue
            }

            guard let key = Self.configKey(from: line) else {
                newLines.append(line)
                continue
            }

            if key == "theme" {
                if !wroteTheme {
                    newLines.append("theme = \(themeName)")
                    wroteTheme = true
                }
                continue
            }

            if Self.themeColorKeys.contains(key) {
                continue
            }

            newLines.append(line)
        }

        if !wroteTheme {
            newLines.append("theme = \(themeName)")
        }

        return newLines.joined(separator: "\n")
    }

    /// Apply/remove specific key overrides while preserving comments and unknown keys.
    /// If a value is nil, that key is removed from the resulting config.
    static func configByApplyingKeyOverrides(_ overrides: [(String, String?)], to contents: String) -> String {
        if contents.isEmpty {
            return overrides.compactMap { key, value in
                guard let value else { return nil }
                return "\(key) = \(value)"
            }.joined(separator: "\n")
        }

        let overrideMap = Dictionary(overrides.map { ($0.0, $0.1) }, uniquingKeysWith: { _, last in last })
        var newLines: [String] = []
        var writtenKeys: Set<String> = []

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                newLines.append(line)
                continue
            }

            guard let key = Self.configKey(from: line) else {
                newLines.append(line)
                continue
            }
            guard let overrideValue = overrideMap[key] else {
                newLines.append(line)
                continue
            }

            if writtenKeys.contains(key) {
                continue
            }

            writtenKeys.insert(key)
            if let overrideValue {
                newLines.append("\(key) = \(overrideValue)")
            }
            // nil override removes existing line
        }

        for (key, value) in overrides where !writtenKeys.contains(key) {
            guard let value else { continue }
            newLines.append("\(key) = \(value)")
        }

        return newLines.joined(separator: "\n")
    }

    /// Write content to config.yen with secure permissions (0600).
    private func writeConfigFile(_ content: String, to path: String? = nil) throws {
        let targetPath = path ?? configPath
        let configDir = (targetPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try content.write(toFile: targetPath, atomically: true, encoding: .utf8)
        // Restrict config to owner-only read/write
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: targetPath
        )
    }

    /// Show a temporary status message that auto-clears after the given duration.
    private func showStatus(
        _ message: String,
        severity: SettingsStatusSeverity = .success,
        duration: TimeInterval = 2
    ) {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        statusClearActiveGeneration = nil
        statusMessage = message
        statusSeverity = severity
        announceStatus(message, severity: severity)
        // An error stays until it is dismissed or replaced. A failure that vanished
        // after four seconds was easy to miss, and impossible to read at a slow pace.
        guard severity != .error else { return }
        statusClearGeneration &+= 1
        let generation = statusClearGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.statusMessage == message, self.statusSeverity == severity {
                self.statusMessage = ""
            }
            if self.statusClearActiveGeneration == generation {
                self.statusClearActiveGeneration = nil
            }
            self.statusClearWorkItem = nil
        }
        statusClearWorkItem = work
        statusClearActiveGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Clears the status notice. The inspector shows a dismiss button for errors.
    func dismissStatus() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        statusClearActiveGeneration = nil
        statusMessage = ""
    }

    /// The status notice is visual only, so VoiceOver gets the same text as an
    /// announcement. Without it a failed save or a rejected shortcut was silent.
    private func announceStatus(_ message: String, severity: SettingsStatusSeverity) {
        guard !message.isEmpty else { return }
#if DEBUG
        testStatusAnnouncementHandler?(message)
#endif
        guard let window, window.isVisible else { return }
        let priority: NSAccessibilityPriorityLevel =
            (severity == .error || severity == .warning) ? .high : .medium
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }

    // MARK: - Test Hooks

#if DEBUG
    /// Receives every footer status that would be announced to VoiceOver.
    var testStatusAnnouncementHandler: ((String) -> Void)?

    /// Test hook for status notice behavior.
    func _testShowStatus(
        _ message: String,
        severity: SettingsStatusSeverity = .success,
        duration: TimeInterval
    ) {
        showStatus(message, severity: severity, duration: duration)
    }

    /// Test hook to reset footer status state and cancel auto-clear.
    func _testResetStatusState() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        statusClearActiveGeneration = nil
        presentationCoordinator.cancelRefresh()
        deferredThemeLoadTask.cancel()
        deferredFontLoadTask.cancel()
        deferredKeybindReloadTask.cancel()
        permissionPolling.stop()
        statusMessage = ""
        statusSeverity = .success
    }

    /// Test hook for checking whether showStatus replaced the clear timer.
    var _testStatusClearWorkItemIdentifier: UInt64? {
        statusClearActiveGeneration
    }

    var _testPermissionPollingActive: Bool {
        permissionPolling.isActive
    }

    var _testHasWindow: Bool {
        window != nil
    }

    var _testSettingsPaneScrollView: NSScrollView? {
        settingsPaneScrollViewForTesting()
    }

    var _testStoredWindowFrame: NSRect? {
        lastSettingsWindowFrame
    }

    var _testHasShowRefreshTask: Bool {
        presentationCoordinator.hasRefreshTask
    }

    var _testShowRefreshScheduleCount: Int {
        presentationCoordinator.scheduledRefreshCount
    }

    var _testHasDeferredThemeLoadTask: Bool {
        deferredThemeLoadTask.isScheduled
    }

    var _testHasThemeCatalogLoadTask: Bool {
        themeCatalogLoadTask != nil
    }

    var _testHasDeferredFontLoadTask: Bool {
        deferredFontLoadTask.isScheduled
    }

    var _testHasDeferredKeybindReloadTask: Bool {
        deferredKeybindReloadTask.isScheduled
    }

    var _testHasPendingRealTimeConfigSync: Bool {
        realTimeConfigSyncWork != nil
    }

    var _testHasPendingThemeSelectionCommit: Bool {
        themePreview.hasPendingCommit
    }

    var _testHasPendingNotificationPreview: Bool {
        soundPreview.hasPendingPreview
    }

    var _testResolvedActiveThemePath: String? {
        activeThemeInfo?.path
    }

    func _testSetThemeCatalogPaths(
        userThemesDirectory: String,
        themesDirectory: String,
        bundledThemeManifestPath: String = "",
        bundledThemeTagsPath: String = ""
    ) {
        testThemeCatalogPathsOverride = ThemeCatalogPaths(
            userThemesDirectory: userThemesDirectory,
            themesDirectory: themesDirectory,
            bundledThemeManifestPath: bundledThemeManifestPath,
            bundledThemeTagsPath: bundledThemeTagsPath
        )
        themeCatalogSnapshot = .empty
        resolvedActiveThemeInfo = nil
        availableThemes = []
    }

    func _testClearThemeCatalogPaths() {
        testThemeCatalogPathsOverride = nil
        themeCatalogSnapshot = .empty
        resolvedActiveThemeInfo = nil
        availableThemes = []
        lastThemeCatalogReloadAt = 0
    }

    static func _testSetCachedMonospaceFonts(_ fonts: [String]?) {
        cachedMonospaceFonts = fonts
    }

    func commitPendingThemeSelectionForTesting() {
        commitPendingThemeSelectionIfNeeded()
    }
#endif

    func loadThemes() {
        themeCatalogLoadTask?.cancel()
        themeCatalogLoadTask = nil
        themeCatalogLoadTaskGeneration &+= 1
        isThemeCatalogLoading = false
        let paths = themeCatalogPaths
        let directoryState = SettingsThemeCatalog.directoryState(
            userThemesDirectory: paths.userThemesDirectory,
            themesDirectory: paths.themesDirectory
        )
        applyThemeCatalogSnapshot(
            SettingsThemeCatalog.buildSnapshot(
                userThemesDirectory: paths.userThemesDirectory,
                themesDirectory: paths.themesDirectory,
                bundledThemeManifestPath: paths.bundledThemeManifestPath,
                bundledThemeTagsPath: paths.bundledThemeTagsPath,
                directoryState: directoryState
            )
        )
    }

    func loadThemesAsync() {
        themeCatalogLoadTask?.cancel()
        themeCatalogLoadTaskGeneration &+= 1
        let generation = themeCatalogLoadTaskGeneration
        let paths = themeCatalogPaths
        let directoryState = SettingsThemeCatalog.directoryState(
            userThemesDirectory: paths.userThemesDirectory,
            themesDirectory: paths.themesDirectory
        )

        isThemeCatalogLoading = true
        themeCatalogLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.themeCatalogLoadTaskGeneration == generation {
                    self.themeCatalogLoadTask = nil
                    self.isThemeCatalogLoading = false
                }
            }

            let snapshotTask = Task.detached(priority: .userInitiated) {
                SettingsThemeCatalog.buildSnapshot(
                    userThemesDirectory: paths.userThemesDirectory,
                    themesDirectory: paths.themesDirectory,
                    bundledThemeManifestPath: paths.bundledThemeManifestPath,
                    bundledThemeTagsPath: paths.bundledThemeTagsPath,
                    directoryState: directoryState
                )
            }
            let snapshot = await withTaskCancellationHandler(operation: {
                await snapshotTask.value
            }, onCancel: {
                snapshotTask.cancel()
            })

            guard !Task.isCancelled,
                  self.themeCatalogLoadTaskGeneration == generation else { return }
            self.applyThemeCatalogSnapshot(snapshot)
        }
    }

    private func applyThemeCatalogSnapshot(
        _ snapshot: ThemeCatalogSnapshot,
        markReloadAt: Bool = true
    ) {
        let previousResolvedThemeInfo = resolvedActiveThemeInfo
        themeCatalogSnapshot = snapshot
        resolvedActiveThemeInfo = SettingsThemeCatalog.resolveThemeInfo(named: selectedTheme, in: snapshot)
        availableThemes = snapshot.visibleThemes
        if resolvedActiveThemeInfo != previousResolvedThemeInfo {
            notifyGeneralSettingsObservers()
        }
        if markReloadAt {
            lastThemeCatalogReloadAt = CFAbsoluteTimeGetCurrent()
        }
    }

    private func currentThemeCatalogSnapshot(forceRefresh: Bool = false) -> ThemeCatalogSnapshot {
        let paths = themeCatalogPaths
        let directoryState = SettingsThemeCatalog.directoryState(
            userThemesDirectory: paths.userThemesDirectory,
            themesDirectory: paths.themesDirectory
        )
        if !forceRefresh,
           SettingsThemeCatalog.isSnapshot(
            themeCatalogSnapshot,
            validFor: directoryState
           ) {
            return themeCatalogSnapshot
        }

        let snapshot = SettingsThemeCatalog.buildSnapshot(
            userThemesDirectory: paths.userThemesDirectory,
            themesDirectory: paths.themesDirectory,
            bundledThemeManifestPath: paths.bundledThemeManifestPath,
            bundledThemeTagsPath: paths.bundledThemeTagsPath,
            directoryState: directoryState
        )
        applyThemeCatalogSnapshot(snapshot, markReloadAt: false)
        return snapshot
    }

    private nonisolated static func buildMonospaceFontCatalog() -> [String] {
        guard let familyNames = CTFontManagerCopyAvailableFontFamilyNames() as? [String] else {
            return []
        }

        let availableFamilies = Set(familyNames)
        var fonts: Set<String> = []

        for family in availableFamilies {
            if Task.isCancelled { break }

            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontFamilyNameAttribute: family
            ] as CFDictionary)
            guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil) as? [CTFontDescriptor] else {
                continue
            }

            for match in matches {
                if Task.isCancelled { break }
                guard let traits = CTFontDescriptorCopyAttribute(match, kCTFontTraitsAttribute) as? [CFString: Any],
                      let symbolicTraitsValue = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value else {
                    continue
                }
                let symbolicTraits = CTFontSymbolicTraits(rawValue: symbolicTraitsValue)
                if symbolicTraits.contains(.traitMonoSpace) {
                    fonts.insert(family)
                    break
                }
            }
        }

        for font in Self.commonTerminalFonts where availableFamilies.contains(font) {
            fonts.insert(font)
        }

        return fonts.sorted()
    }

    private nonisolated static func normalizedFontSize(_ value: Double) -> Double {
        min(max(value.rounded(.toNearestOrAwayFromZero), 8), 32)
    }

    private nonisolated static func fontCatalogIncludingCurrentFont(
        _ fonts: [String],
        currentFontFamily: String
    ) -> [String] {
        guard !currentFontFamily.isEmpty else { return fonts }
        if fonts.contains(currentFontFamily) {
            return fonts
        }
        return [currentFontFamily] + fonts
    }

    private func withCoalescedSettingsNotifications(_ operation: () -> Void) {
        settingsNotificationCoalescingDepth += 1
        defer {
            settingsNotificationCoalescingDepth -= 1
            if settingsNotificationCoalescingDepth == 0 {
                flushCoalescedSettingsNotifications()
            }
        }
        operation()
    }

    private func enqueueOrPostSettingsNotification(_ topic: SettingsNotificationTopic) {
        guard settingsNotificationCoalescingDepth > 0 else {
            topic.post(from: self)
            return
        }

        if pendingSettingsNotificationTopicSet.insert(topic).inserted {
            pendingSettingsNotificationTopics.append(topic)
        }
    }

    private func flushCoalescedSettingsNotifications() {
        let topics = pendingSettingsNotificationTopics
        pendingSettingsNotificationTopics.removeAll(keepingCapacity: true)
        pendingSettingsNotificationTopicSet.removeAll(keepingCapacity: true)

        for topic in topics {
            topic.post(from: self)
        }
    }

    private func notifyTerminalPresentationObservers() {
        enqueueOrPostSettingsNotification(.terminalPresentation)
    }

    private func notifySplitPaneLabelObservers() {
        enqueueOrPostSettingsNotification(.splitPaneLabel)
    }

    private func notifyWorkspaceSettingsObservers() {
        enqueueOrPostSettingsNotification(.workspace)
    }

    private func refreshResolvedActiveThemeInfo(forceRefreshSnapshot: Bool = false) {
        let previousResolvedThemeInfo = resolvedActiveThemeInfo
        let selectedThemeName = Self.normalizedThemeName(selectedTheme)
        guard !selectedThemeName.isEmpty else {
            resolvedActiveThemeInfo = nil
            if forceRefreshSnapshot || previousResolvedThemeInfo != nil {
                notifyTerminalPresentationObservers()
            }
            return
        }

        let snapshot = currentThemeCatalogSnapshot(forceRefresh: forceRefreshSnapshot)
        resolvedActiveThemeInfo = SettingsThemeCatalog.resolveThemeInfo(
            named: selectedThemeName,
            in: snapshot
        )
        if forceRefreshSnapshot || resolvedActiveThemeInfo != previousResolvedThemeInfo {
            notifyTerminalPresentationObservers()
            notifyGeneralSettingsObservers()
        }
    }

    private func notifyThemesSettingsObservers() {
        enqueueOrPostSettingsNotification(.themes)
    }

    private func notifyGeneralSettingsObservers() {
        enqueueOrPostSettingsNotification(.general)
    }

    private func notifyKeyboardSettingsObservers() {
        enqueueOrPostSettingsNotification(.keyboard)
    }

    func notifySoundsSettingsObservers() {
        enqueueOrPostSettingsNotification(.sounds)
    }

    private func setKeybindReloadPending(_ isPending: Bool) {
        guard keybindReloadPending != isPending else { return }
        keybindReloadPending = isPending
        notifyKeyboardSettingsObservers()
    }


    func applyTheme(_ theme: ThemeInfo) {
        themePreview.applyTheme(theme)
    }

    // MARK: - Theme Preview

    struct ThemePreviewConfigSnapshot: Equatable {
        let contents: String
        let wasMissing: Bool
    }

    enum ThemePreviewConfigReadError: Error, Equatable, LocalizedError {
        case unreadableExistingConfig(String)

        var errorDescription: String? {
            switch self {
            case .unreadableExistingConfig(let reason):
                return "Could not read config.yen: \(reason)"
            }
        }
    }

    static func themePreviewConfigSnapshot(
        fileExists: () -> Bool,
        readContents: () throws -> String
    ) throws -> ThemePreviewConfigSnapshot {
        do {
            return ThemePreviewConfigSnapshot(contents: try readContents(), wasMissing: false)
        } catch {
            guard fileExists() else {
                return ThemePreviewConfigSnapshot(contents: "", wasMissing: true)
            }
            throw ThemePreviewConfigReadError.unreadableExistingConfig(error.localizedDescription)
        }
    }

    /// Flush a debounced-but-unwritten theme selection (deep-link reopen,
    /// window close). Delegates to `ThemePreviewCoordinator`.
    private func commitPendingThemeSelectionIfNeeded() {
        themePreview.commitPendingIfNeeded()
    }

    /// Revert config.yen to its pre-preview state and reload. Delegates to
    /// `ThemePreviewCoordinator`.
    private func revertThemePreview() {
        themePreview.revert()
    }

    /// Reload terminal config without posting the `.yenConfigDidReload` notification,
    /// suppressing the "Configuration reloaded" toast during preview.
    private func reloadTerminalConfigSilently() {
        guard let appDelegate = AppDelegate.shared else { return }
        appDelegate.yen.reloadConfig()
    }

    /// Preserve user's shell-integration-features while ensuring `no-cursor` is present.
    /// Prevents shell integration from overriding cursor-style set in Settings.
    private func shellIntegrationFeaturesWithNoCursor() -> String {
        var tokens = shellIntegrationFeatures
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "cursor" }  // Remove explicit "cursor" (conflicts with no-cursor)

        if !tokens.contains("no-cursor") {
            tokens.append("no-cursor")
        }

        return tokens.joined(separator: ",")
    }

    private func reloadTerminalConfig() {
        guard let appDelegate = AppDelegate.shared else { return }
        pendingSelfInitiatedConfigReloadNotifications += 1
        appDelegate.yen.reloadConfig()
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
    }

    // MARK: - Background Image

    func importBackgroundImage() {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose Background Image"
        panel.allowedContentTypes = TerminalBackgroundImageStore.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Ensure iCloud files are downloaded before the panel returns the URL.
        // Default is true on macOS 10.10+, but explicit for clarity.
        panel.canDownloadUbiquitousContents = true

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let sourceURL = panel.url, let self else { return }
            _ = self.importBackgroundImage(from: sourceURL)
        }
    }

    func removeBackgroundImage() {
        _ = removeBackgroundImage(fileManager: .default, appSupportRootOverride: nil)
    }

    @discardableResult
    private func importBackgroundImage(
        from sourceURL: URL,
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil
    ) -> Bool {
        let previousPath = backgroundImagePath

        do {
            let importedURL = try TerminalBackgroundImageStore.importImage(
                from: sourceURL,
                fileManager: fileManager,
                appSupportRootOverride: appSupportRootOverride
            )
            setBackgroundImagePathWithoutRealTimeSync(importedURL.path)

            guard persistConfig(
                postReloadNotification: true,
                successMessage: "Imported background image",
                failurePrefix: "Import failed"
            ) else {
                setBackgroundImagePathWithoutRealTimeSync(previousPath)
                cleanupManagedBackgroundImages(
                    fileManager: fileManager,
                    appSupportRootOverride: appSupportRootOverride,
                    retaining: retainedBackgroundImagePaths(previousPath)
                )
                return false
            }

            cleanupManagedBackgroundImages(
                fileManager: fileManager,
                appSupportRootOverride: appSupportRootOverride,
                retaining: retainedBackgroundImagePaths(backgroundImagePath)
            )
            return true
        } catch {
            showStatus("Import failed: \(error.localizedDescription)", severity: .error, duration: 4)
            return false
        }
    }

    @discardableResult
    private func removeBackgroundImage(
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil
    ) -> Bool {
        guard hasBackgroundImage else { return false }

        let previousPath = backgroundImagePath
        setBackgroundImagePathWithoutRealTimeSync("")

        guard persistConfig(
            postReloadNotification: true,
            successMessage: "Removed background image",
            failurePrefix: "Remove failed"
        ) else {
            setBackgroundImagePathWithoutRealTimeSync(previousPath)
            return false
        }

        cleanupManagedBackgroundImages(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride
        )
        return true
    }

    private func setBackgroundImagePathWithoutRealTimeSync(_ path: String) {
        let previousSuppressRealTimeConfigSync = suppressRealTimeConfigSync
        suppressRealTimeConfigSync = true
        backgroundImagePath = path
        suppressRealTimeConfigSync = previousSuppressRealTimeConfigSync
    }

    private func cleanupManagedBackgroundImages(
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil,
        retaining retainedPaths: Set<String> = []
    ) {
        try? TerminalBackgroundImageStore.cleanupManagedImages(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride,
            retaining: retainedPaths
        )
    }

    private func retainedBackgroundImagePaths(_ path: String) -> Set<String> {
        let normalizedPath = TerminalBackgroundImageStore.normalizedConfigPath(path)
        guard !normalizedPath.isEmpty else { return [] }
        return [normalizedPath]
    }

    // MARK: - Notification Sounds

    private func loadNotificationSoundState() {
        let manager = NotificationSoundManager.shared
        soundStore.suppressSoundManagerSync = true
        defer { soundStore.suppressSoundManagerSync = false }
        availableSystemSounds = manager.systemSounds

        // The manager normalizes retired IDs before the UI observes them.
        notificationServiceSettings = NotificationServiceSettings.captureAll()

        // Load focus behavior toggles
        soundWhenFocused = manager.soundWhenFocused
        bannerWhenFocused = manager.bannerWhenFocused
        hasLoadedNotificationSoundStateForVisibleSession = window?.isVisible == true
        notifySoundsSettingsObservers()
    }

    private func notificationSettings(for service: NotificationService) -> NotificationServiceSettings {
        notificationServiceSettings[service] ?? NotificationServiceSettings.capture(for: service)
    }

    func notificationSoundSelection(for service: NotificationService) -> String {
        notificationSettings(for: service).selectionID
    }

    func setNotificationSoundSelection(_ selection: String, for service: NotificationService) {
        var settings = notificationSettings(for: service)
        let oldValue = settings.selectionID
        settings.selectionID = selection
        notificationServiceSettings[service] = settings
        soundStore.syncSoundNamePreference(selection, oldValue: oldValue, for: service)
    }

    func notificationSoundDeliveryMode(for service: NotificationService) -> NotificationDeliveryMode {
        notificationSettings(for: service).deliveryMode
    }

    func setNotificationSoundDeliveryMode(
        _ deliveryMode: NotificationDeliveryMode,
        for service: NotificationService
    ) {
        var settings = notificationSettings(for: service)
        let oldValue = settings.deliveryMode
        settings.deliveryMode = deliveryMode
        notificationServiceSettings[service] = settings
        soundStore.syncSoundDeliveryModePreference(deliveryMode, oldValue: oldValue, for: service)
    }

    func notificationSoundVolume(for service: NotificationService) -> Double {
        notificationSettings(for: service).volume
    }

    func setNotificationSoundVolume(_ volume: Double, for service: NotificationService) {
        var settings = notificationSettings(for: service)
        let oldValue = settings.volume
        settings.volume = volume
        notificationServiceSettings[service] = settings
        soundStore.syncSoundVolumePreference(volume, oldValue: oldValue, for: service)
    }

    func previewSound(_ name: String, volume: Double) {
        soundPreview.preview(name, volume: volume)
    }

    func displaySoundSelection(_ selectionID: String) -> String {
        NotificationSoundManager.shared.displayName(for: selectionID)
    }

    // MARK: - Keybind Management

    /// Cached conflict detection results for keybind conflict checks.
    /// Reused within the active Settings session and invalidated on close/install-state change.
    private var cachedConflictShortcuts: ConflictDetector.CachedShortcuts?

    var keybindReloadPendingForUI: Bool {
        keybindReloadPending
    }

#if DEBUG
    var pendingKeybindReloadForTesting: Bool {
        keybindReloadPending
    }

    func applyConfigContentsForTesting(_ contents: String) {
        realTimeConfigSyncWork?.cancel()
        realTimeConfigSyncWork = nil
        let previousSuppressRealTimeConfigSync = suppressRealTimeConfigSync
        suppressRealTimeConfigSync = true
        defer { suppressRealTimeConfigSync = previousSuppressRealTimeConfigSync }
        applyConfigContents(contents)
    }

    func loadConfigForTesting() {
        realTimeConfigSyncWork?.cancel()
        realTimeConfigSyncWork = nil
        let previousSuppressRealTimeConfigSync = suppressRealTimeConfigSync
        suppressRealTimeConfigSync = true
        defer { suppressRealTimeConfigSync = previousSuppressRealTimeConfigSync }
        loadConfig()
    }

    func managedSettingsListForTesting() -> [(String, String)] {
        buildSettingsList()
    }

    func wholeWindowBackgroundRuntimeConfigContentsForTesting() -> String {
        wholeWindowBackgroundRuntimeConfigContents()
    }

    func currentManagedSurfaceConfigContentsForTesting() -> String {
        currentManagedSurfaceConfigContents()
    }

    @discardableResult
    func _testImportBackgroundImage(
        from sourceURL: URL,
        appSupportRootOverride: URL? = nil
    ) -> Bool {
        importBackgroundImage(from: sourceURL, appSupportRootOverride: appSupportRootOverride)
    }

    @discardableResult
    func _testRemoveBackgroundImage(appSupportRootOverride: URL? = nil) -> Bool {
        removeBackgroundImage(appSupportRootOverride: appSupportRootOverride)
    }

    func restoreDefaultShortcutsForTesting() {
        restoreDefaultShortcuts()
    }

    /// Captures everything a reset can change, so a test can put it back.
    func captureSettingsStateForTesting() -> SettingsConfigurationRollbackState {
        captureConfigurationRollbackState()
    }

    func restoreSettingsStateForTesting(_ state: SettingsConfigurationRollbackState) {
        restoreConfigurationRollbackState(state)
    }

    func resetAllSettingsToDefaultsForTesting() {
        resetAllSettingsToDefaults()
    }

    static func configEntryForTesting(_ line: String) -> (key: String, value: String)? {
        guard let entry = Self.configEntry(from: line) else { return nil }
        return (key: entry.key, value: entry.value)
    }

    static func configKeyForTesting(_ line: String) -> String? {
        Self.configKey(from: line)
    }

    func refreshResolvedActiveThemeInfoForTesting() {
        refreshResolvedActiveThemeInfo()
    }

    func mergedManagedConfigForTesting(existingContents: String) -> String {
        let existingLines = existingContents.components(separatedBy: .newlines)
        return managedConfigDocument().merged(intoExistingLines: existingLines)
            .joined(separator: "\n")
    }

    func resetKeybindReloadStateForTesting() {
        setKeybindReloadPending(false)
        keyboardRecordingActive = false
        cachedConflictShortcuts = nil
        deferredKeybindReloadTask.cancel()
    }

    func _testResetWindowState() {
        presentationCoordinator.cancelRefresh()
#if DEBUG
        presentationCoordinator._testResetMetrics()
#endif
        if let window {
            SettingsWindowFactory.releaseWindowGraph(window)
        }
        self.window = nil
        lastSettingsWindowFrame = nil
    }

    func _testSetConflictShortcutCache(_ cache: ConflictDetector.CachedShortcuts?) {
        cachedConflictShortcuts = cache
    }

    func _testInvalidateConflictShortcutCache() {
        cachedConflictShortcuts = nil
    }

    @discardableResult
    func _testLoadCurrentConflictShortcutCache() -> ConflictDetector.CachedShortcuts {
        currentConflictShortcutCache()
    }
#endif

    private func settingsPaneScrollViewForTesting() -> NSScrollView? {
        window?.contentView?.layoutSubtreeIfNeeded()
        guard let rootView = window?.contentView else { return nil }
        let scrollViews = Self.descendantScrollViews(in: rootView)
        return scrollViews.max { lhs, rhs in
            lhs.frame.width < rhs.frame.width
        }
    }

    private static func descendantScrollViews(in rootView: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []

        func walk(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                found.append(scrollView)
            }
            for subview in view.subviews {
                walk(subview)
            }
        }

        walk(rootView)
        return found
    }

#if DEBUG
    static func _testSetWindowCloseMemoryModeOverride(_ mode: TestWindowCloseMemoryMode?) {
        testWindowCloseMemoryModeOverride = mode
    }

    static func _testSetConfigPathOverride(_ path: String?) {
        testConfigPathOverride = path
    }
#endif

    private func refreshConflictShortcutCache() -> ConflictDetector.CachedShortcuts {
        let scanned = ConflictDetector.scanShortcuts()
        cachedConflictShortcuts = scanned
        return scanned
    }

    private func currentConflictShortcutCache() -> ConflictDetector.CachedShortcuts {
        if let cached = cachedConflictShortcuts {
            guard ConflictDetector.cacheMatchesCurrentInstallState(cached) else {
                return refreshConflictShortcutCache()
            }
            return cached
        }

        return refreshConflictShortcutCache()
    }

    func showKeyboardRecorderRejectedStatus(_ rejection: KeyRecorderRejection) {
        showStatus(rejection.visibleMessage, severity: .warning, duration: 3)
    }

    func showKeyboardRecorderStoppedForPaneSwitchStatus() {
        showStatus("Shortcut recording stopped.", severity: .info, duration: 3)
    }

    /// Decide whether a config reload should refresh keybind entries immediately or be deferred.
    /// Returns true when the caller should invoke `loadKeybinds()` now.
    @discardableResult
    func consumeConfigReloadForKeybinds(isSettingsVisible: Bool) -> Bool {
        guard isSettingsVisible else { return false }
        if selectedSettingsPane == .shortcuts && !keyboardRecordingActive {
            setKeybindReloadPending(false)
            return true
        }
        let wasPending = keybindReloadPending
        setKeybindReloadPending(true)
        if selectedSettingsPane == .shortcuts && keyboardRecordingActive && !wasPending {
            showStatus(
                "Config changed; list refreshes after recording.",
                severity: .info,
                duration: 3
            )
        }
        return false
    }

    /// Consume a deferred keybind reload when the Shortcuts pane is visible and recorder is idle.
    /// Returns true when the caller should invoke `loadKeybinds()` now.
    @discardableResult
    func consumePendingKeybindReloadIfReady(isSettingsVisible: Bool) -> Bool {
        guard keybindReloadPending else { return false }
        guard isSettingsVisible, selectedSettingsPane == .shortcuts, !keyboardRecordingActive else {
            return false
        }
        setKeybindReloadPending(false)
        return true
    }

    /// Load keybind entries from static catalog, applying any user overrides from config.yen.
    func loadKeybinds() {
        setKeybindReloadPending(false)
        var entries = KeybindRegistry.defaults

        // Parse user overrides from config.yen
        let contents = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""

        // Collect all keybind = ... lines
        var userOverrides: [(trigger: KeyTrigger, action: String, isGlobal: Bool)] = []
        for line in contents.components(separatedBy: .newlines) {
            guard let entry = Self.configEntry(from: line), entry.key == "keybind" else { continue }
            // Accept the `global:` prefix here. `parseConfigLine` stays strict so the
            // MERGE still treats an unparsed global line as "preserve verbatim"; without
            // this the read path never saw a remapped global binding and the shortcut list
            // showed the default as current while config bound something else.
            if let parsed = KeybindRegistry.parseConfigLineAllowingGlobal(entry.value) {
                userOverrides.append((trigger: parsed.trigger, action: parsed.action, isGlobal: parsed.isGlobal))
            }
        }

        // Apply overrides: for duplicate actions, prefer matching by action + default trigger.
        // This ensures "keybind = super+shift+y=undo" maps to the right "undo" entry.
        for override in userOverrides {
            let candidates = entries.indices.filter { entries[$0].action == override.action && entries[$0].isEditable }

            // Prefer the entry whose default trigger matches the override trigger
            // `isGlobal` is OR-ed in, never cleared: upstream documents `global:` as valid
            // on any binding, so a hand-written global bind for a Settings-managed action
            // must keep its prefix when Settings next rewrites the file. Without this, an
            // unrelated slider drag silently demoted it to app-local.
            if let exactIndex = candidates.first(where: { entries[$0].defaultTrigger == override.trigger }) {
                entries[exactIndex].currentTrigger = override.trigger
                entries[exactIndex].isUserOverride = false  // trigger == default
                entries[exactIndex].isGlobal = entries[exactIndex].isGlobal || override.isGlobal
            } else if let firstIndex = candidates.first {
                entries[firstIndex].currentTrigger = override.trigger
                entries[firstIndex].isUserOverride = (override.trigger != entries[firstIndex].defaultTrigger)
                entries[firstIndex].isGlobal = entries[firstIndex].isGlobal || override.isGlobal
            }
            // If no editable candidate, the line is preserved in config but not applied to any entry
        }

        YEN.logger.info("SettingsController: loaded \(userOverrides.count) keybind override(s) from config.yen")

        // Detect conflicts with system and app shortcuts
        let cache = currentConflictShortcutCache()
        ConflictDetector.applyConflicts(to: &entries, using: cache)

        keybindEntries = entries
    }

    /// Update a keybind to a new trigger, identified by stableId. Re-runs conflict detection.
    @discardableResult
    func updateKeybind(stableId: String, trigger: KeyTrigger) -> KeyRecorderRecordResult {
        guard let index = keybindEntries.firstIndex(where: { $0.stableId == stableId }) else {
            return .rejected(.unavailableKeybind)
        }
        guard keybindEntries[index].isEditable else {
            return .rejected(.unavailableKeybind)
        }

        if let validationError = KeybindRegistry.validationError(for: trigger) {
            switch validationError {
            case .missingRequiredModifier:
                showStatus(KeybindRegistry.missingRequiredModifierValidationMessage, severity: .warning, duration: 3)
                return .rejected(.missingRequiredModifier)
            case .reservedFixedShortcut:
                showStatus(
                    KeybindRegistry.reservedFixedShortcutValidationMessage,
                    severity: .warning,
                    duration: 3
                )
                return .rejected(.reservedFixedShortcut)
            }
        }

        var entry = keybindEntries[index]
        entry.currentTrigger = trigger
        entry.isUserOverride = (trigger != entry.defaultTrigger)

        // Re-run conflict detection for the edited row using cached shortcuts.
        let cache = currentConflictShortcutCache()
        ConflictDetector.applyConflicts(to: &entry, using: cache)
        keybindEntries[index] = entry

        scheduleRealTimeConfigSync()
        // A duplicate stays allowed, because swapping two shortcuts passes through
        // one, but it is reported the moment it is recorded.
        if let duplicate = Self.duplicateKeybindEntry(of: entry, in: keybindEntries) {
            showStatus(
                "\(trigger.displayString) is also assigned to \(duplicate.displayName).",
                severity: .warning,
                duration: 5
            )
        }
        return .recorded
    }

    /// The first other entry bound to the same trigger, by key text or key code.
    static func duplicateKeybindEntry(of entry: KeybindEntry, in entries: [KeybindEntry]) -> KeybindEntry? {
        let trigger = entry.currentTrigger
        return entries.first { other in
            guard other.stableId != entry.stableId else { return false }
            let otherTrigger = other.currentTrigger
            guard otherTrigger.modifiers == trigger.modifiers else { return false }
            if otherTrigger.key.lowercased() == trigger.key.lowercased() { return true }
            if let keyCode = trigger.keyCode, let otherKeyCode = otherTrigger.keyCode {
                return keyCode == otherKeyCode
            }
            return false
        }
    }

    /// Reset a keybind to its default trigger, identified by stableId. Re-runs conflict detection.
    func resetKeybind(stableId: String) {
        guard let index = keybindEntries.firstIndex(where: { $0.stableId == stableId }) else { return }
        guard keybindEntries[index].isEditable else { return }
        var entry = keybindEntries[index]
        entry.currentTrigger = entry.defaultTrigger
        entry.isUserOverride = false

        // Re-run conflict detection for the edited row using cached shortcuts.
        let cache = currentConflictShortcutCache()
        ConflictDetector.applyConflicts(to: &entry, using: cache)
        keybindEntries[index] = entry

        scheduleRealTimeConfigSync()
    }

    // MARK: - Layout Application

    func applyLayout(_ layout: LayoutTemplate, controller targetController: BaseTerminalController? = nil) {
        layoutApplier.apply(layout, controller: targetController)
    }

}

// MARK: - ThemePreviewHost

extension SettingsController: ThemePreviewHost {
    var themePreviewConfigPath: String { configPath }

    var themePreviewSelectedTheme: String {
        get { selectedTheme }
        set { selectedTheme = newValue }
    }

    var themePreviewOriginalThemeName: String {
        get { originalThemeName }
        set { originalThemeName = newValue }
    }

    var themePreviewIsCatalogLoading: Bool { isThemeCatalogLoading }

    func themePreviewWriteConfig(_ contents: String) throws {
        try writeConfigFile(contents)
    }

    func themePreviewRemoveConfig() {
        try? FileManager.default.removeItem(atPath: configPath)
    }

    func themePreviewReloadSilently() {
        reloadTerminalConfigSilently()
    }

    func themePreviewRefreshSelectedThemeFromConfig() {
        refreshSelectedThemeFromConfig()
    }

    func themePreviewShowApplyFailure(_ message: String) {
        showStatus(message, severity: .error, duration: 4)
    }
}

// MARK: - Theme Catalog Paths

private struct ThemeCatalogPaths: Sendable {
    let userThemesDirectory: String
    let themesDirectory: String
    let bundledThemeManifestPath: String
    let bundledThemeTagsPath: String
}

#endif // os(macOS)
