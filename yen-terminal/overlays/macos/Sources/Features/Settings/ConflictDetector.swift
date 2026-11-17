#if os(macOS)
import Cocoa

/// Detects conflicts between YEN keybinds and macOS system shortcuts / popular apps.
@MainActor
enum ConflictDetector {
    #if DEBUG
    private static let metricsLock = NSLock()
    private static var scanShortcutInvocationCount = 0
    private static var conflictEntryApplicationCount = 0
    private static var installedKnownAppBundleIDsOverride: Set<String>?
    #endif

    /// Cached scan results — reuse within a Settings session to avoid repeated I/O.
    struct CachedShortcuts {
        let systemShortcuts: [SystemShortcut]
        let appShortcuts: [AppShortcut]
        let installedKnownAppBundleIDs: Set<String>
        private let systemShortcutsByModifiers: [KeyModifiers: [SystemShortcut]]
        private let appShortcutsByModifiers: [KeyModifiers: [AppShortcut]]

        init(
            systemShortcuts: [SystemShortcut],
            appShortcuts: [AppShortcut],
            installedKnownAppBundleIDs: Set<String>
        ) {
            self.systemShortcuts = systemShortcuts
            self.appShortcuts = appShortcuts
            self.installedKnownAppBundleIDs = installedKnownAppBundleIDs
            self.systemShortcutsByModifiers = Dictionary(grouping: systemShortcuts) {
                $0.trigger.modifiers
            }
            self.appShortcutsByModifiers = Dictionary(grouping: appShortcuts) {
                $0.trigger.modifiers
            }
        }

        fileprivate func systemShortcuts(matching modifiers: KeyModifiers) -> [SystemShortcut] {
            systemShortcutsByModifiers[modifiers] ?? []
        }

        fileprivate func appShortcuts(matching modifiers: KeyModifiers) -> [AppShortcut] {
            appShortcutsByModifiers[modifiers] ?? []
        }

        #if DEBUG
        func _testSystemShortcutBucketCount(for modifiers: KeyModifiers) -> Int {
            systemShortcutsByModifiers[modifiers]?.count ?? 0
        }

        func _testAppShortcutBucketCount(for modifiers: KeyModifiers) -> Int {
            appShortcutsByModifiers[modifiers]?.count ?? 0
        }
        #endif
    }

    /// Scan system and app shortcuts (expensive — call once per Settings session).
    static func scanShortcuts() -> CachedShortcuts {
        #if DEBUG
        metricsLock.lock()
        scanShortcutInvocationCount += 1
        metricsLock.unlock()
        #endif
        let system = scanSystemShortcuts()
        let (apps, installedBundleIDs) = scanInstalledAppShortcuts()
        #if DEBUG
        print("ConflictDetector: found \(system.count) system + \(apps.count) app shortcut(s)")
        #endif
        return CachedShortcuts(
            systemShortcuts: system,
            appShortcuts: apps,
            installedKnownAppBundleIDs: installedBundleIDs
        )
    }

    #if DEBUG
    static func _testResetMetrics() {
        metricsLock.lock()
        scanShortcutInvocationCount = 0
        conflictEntryApplicationCount = 0
        metricsLock.unlock()
    }

    static var _testScanShortcutInvocationCount: Int {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return scanShortcutInvocationCount
    }

    static var _testConflictEntryApplicationCount: Int {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return conflictEntryApplicationCount
    }

    static func _testSetInstalledKnownAppBundleIDs(_ bundleIDs: Set<String>?) {
        installedKnownAppBundleIDsOverride = bundleIDs
    }
    #endif

    static func cacheMatchesCurrentInstallState(_ cache: CachedShortcuts) -> Bool {
        cache.installedKnownAppBundleIDs == currentInstalledKnownAppBundleIDs()
    }

    private static func currentInstalledKnownAppBundleIDs() -> Set<String> {
        #if DEBUG
        if let installedKnownAppBundleIDsOverride {
            return installedKnownAppBundleIDsOverride
        }
        #endif
        return Set(installedKnownApps().map { $0.0.bundleId })
    }

    /// Apply conflict detection to entries using cached scan results.
    static func applyConflicts(to entries: inout [KeybindEntry], using cache: CachedShortcuts) {
        for i in entries.indices {
            applyConflicts(to: &entries[i], using: cache)
        }
    }

    /// Apply conflict detection to one entry using cached scan results.
    static func applyConflicts(to entry: inout KeybindEntry, using cache: CachedShortcuts) {
        #if DEBUG
        metricsLock.lock()
        conflictEntryApplicationCount += 1
        metricsLock.unlock()
        #endif
        entry.conflicts = conflicts(for: entry.currentTrigger, using: cache)
    }

    /// Return conflicts for a single trigger using modifier-keyed candidate buckets.
    static func conflicts(for trigger: KeyTrigger, using cache: CachedShortcuts) -> [KeybindConflict] {
        var conflicts: [KeybindConflict] = []

        // Check system shortcuts
        for sys in cache.systemShortcuts(matching: trigger.modifiers) {
            if trigger.conflicts(with: sys.trigger) {
                conflicts.append(KeybindConflict(
                    source: .macOS(name: sys.name),
                    description: "macOS: \(sys.name) uses \(sys.trigger.displayString)"
                ))
            }
        }

        // Check app shortcuts
        for app in cache.appShortcuts(matching: trigger.modifiers) {
            if trigger.conflicts(with: app.trigger) {
                conflicts.append(KeybindConflict(
                    source: .app(bundleId: app.bundleId, name: app.appName, icon: app.icon),
                    description: "\(app.appName): \(app.actionName) uses \(app.trigger.displayString)"
                ))
            }
        }

        return conflicts
    }

    // MARK: - macOS Symbolic Hotkeys

    struct SystemShortcut {
        let name: String
        let trigger: KeyTrigger
    }

    /// Read macOS system keyboard shortcuts from symbolic hotkeys plist.
    private static func scanSystemShortcuts() -> [SystemShortcut] {
        guard let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let hotkeys = defaults.dictionary(forKey: "AppleSymbolicHotKeys") else {
            #if DEBUG
            print("ConflictDetector: could not read symbolic hotkeys plist")
            #endif
            return []
        }

        var shortcuts: [SystemShortcut] = []

        for (idStr, value) in hotkeys {
            guard let id = Int(idStr),
                  let dict = value as? [String: Any],
                  let enabled = dict["enabled"] as? Bool, enabled,
                  let params = dict["value"] as? [String: Any],
                  let parameters = params["parameters"] as? [Any],
                  parameters.count >= 3 else { continue }

            // Keep scanning even when we don't have a friendly label for this
            // symbolic hotkey ID yet; otherwise we can silently miss conflicts.
            let name = symbolicHotkeyName(for: id) ?? "System Shortcut \(id)"

            // parameters: [charCode, keyCode, carbonModifierFlags]
            let characterCode = (parameters[0] as? NSNumber)?.intValue
            let keyCode = (parameters[1] as? NSNumber)?.uint16Value ?? 0
            let symbolicHotkeyFlags = (parameters[2] as? NSNumber)?.intValue ?? 0

            let modifiers = KeyModifiers(symbolicHotkeyFlags: symbolicHotkeyFlags)
            let descriptor = KeybindRegistry.keyDescriptor(
                forSystemHotkeyKeyCode: keyCode,
                characterCode: characterCode
            )

            let trigger = KeyTrigger(
                modifiers: modifiers,
                key: descriptor.key,
                keyCode: keyCode,
                displayKey: descriptor.displayKey
            )
            shortcuts.append(SystemShortcut(name: name, trigger: trigger))
        }

        return shortcuts
    }

    /// Map well-known symbolic hotkey IDs to human-readable names.
    private static func symbolicHotkeyName(for id: Int) -> String? {
        switch id {
        // Mission Control
        case 32: return "Mission Control"
        case 33: return "Mission Control (Secondary)"
        case 34: return "Application Windows"
        case 35: return "Application Windows (Secondary)"
        case 36: return "Show Desktop"
        case 37: return "Show Desktop (Secondary)"

        // Spaces
        case 79: return "Move Left a Space"
        case 80: return "Move Right a Space"
        case 81: return "Move Left a Space (Secondary)"
        case 82: return "Move Right a Space (Secondary)"

        // Spotlight
        case 64: return "Spotlight Search"
        case 65: return "Finder Search"

        // Screenshots
        case 28: return "Screenshot to File"
        case 29: return "Screenshot to Clipboard"
        case 30: return "Screenshot Area to File"
        case 31: return "Screenshot Area to Clipboard"
        case 184: return "Screenshot and Recording"

        // Input Sources
        case 60: return "Select Previous Input Source"
        case 61: return "Select Next Input Source"

        // Accessibility
        case 162: return "Turn Dock Hiding On/Off"
        case 175: return "Turn VoiceOver On/Off"

        // Keyboard
        case 7: return "Move Focus to Menubar"
        case 8: return "Move Focus to Dock"
        case 9: return "Move Focus to Active Window"
        case 10: return "Move Focus to Window Toolbar"
        case 12: return "Move Focus to Status Menus"

        default: return nil
        }
    }

    // MARK: - Installed App Shortcuts

    struct AppShortcut {
        let bundleId: String
        let appName: String
        let actionName: String
        let trigger: KeyTrigger
        let icon: NSImage?
    }

    /// Check known default shortcuts for popular installed apps.
    private static func scanInstalledAppShortcuts() -> ([AppShortcut], Set<String>) {
        #if DEBUG
        if let installedKnownAppBundleIDsOverride {
            return ([], installedKnownAppBundleIDsOverride)
        }
        #endif
        let installedApps = installedKnownApps()
        var results: [AppShortcut] = []
        var installedBundleIDs: Set<String> = []

        for (app, appURL) in installedApps {
            installedBundleIDs.insert(app.bundleId)

            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)

            for shortcut in app.shortcuts {
                results.append(AppShortcut(
                    bundleId: app.bundleId,
                    appName: app.name,
                    actionName: shortcut.action,
                    trigger: shortcut.trigger,
                    icon: icon
                ))
            }
        }

        return (results, installedBundleIDs)
    }

    private static func installedKnownApps() -> [(KnownApp, URL)] {
        var installed: [(KnownApp, URL)] = []
        for app in knownApps {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else {
                continue
            }
            guard isInstalledApplicationBundle(at: appURL, expectedBundleID: app.bundleId) else {
                continue
            }
            installed.append((app, appURL))
        }
        return installed
    }

    private static func isInstalledApplicationBundle(
        at appURL: URL,
        expectedBundleID: String
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == expectedBundleID else {
            return false
        }
        return true
    }

    private struct KnownApp {
        let bundleId: String
        let name: String
        let shortcuts: [(action: String, trigger: KeyTrigger)]
    }

    /// Static database of popular app shortcuts that commonly conflict with terminal keybinds.
    private static let knownApps: [KnownApp] = [
        KnownApp(
            bundleId: "com.microsoft.VSCode",
            name: "VS Code",
            shortcuts: [
                (action: "Split Editor", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true), key: "backslash")),
                (action: "Toggle Sidebar", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "e")),
                (action: "Open Terminal", trigger: KeyTrigger(
                    modifiers: KeyModifiers(ctrl: true), key: "backquote")),
                (action: "Command Palette", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "p")),
            ]
        ),
        KnownApp(
            bundleId: "com.googlecode.iterm2",
            name: "iTerm2",
            shortcuts: [
                (action: "Split Horizontally", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true), key: "d")),
                (action: "Split Vertically", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "d")),
            ]
        ),
        KnownApp(
            bundleId: "com.raycast.macos",
            name: "Raycast",
            shortcuts: [
                (action: "Raycast Hotkey", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true), key: "space")),
                (action: "Clipboard History", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "v")),
            ]
        ),
        KnownApp(
            bundleId: "com.runningwithcrayons.Alfred",
            name: "Alfred",
            shortcuts: [
                (action: "Alfred Hotkey", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true), key: "space")),
                (action: "Clipboard History", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, option: true), key: "c")),
            ]
        ),
        KnownApp(
            bundleId: "com.1password.1password",
            name: "1Password",
            shortcuts: [
                (action: "Quick Access", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "space")),
                (action: "Autofill", trigger: KeyTrigger(
                    modifiers: KeyModifiers(cmd: true, shift: true), key: "x")),
            ]
        ),
    ]
}

#endif // os(macOS)
