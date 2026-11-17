#if os(macOS)
import Foundation

/// Everything a reset changes, captured before the reset so a failed save can
/// put it back.
struct SettingsConfigurationRollbackState {
    struct NotificationServiceState {
        let service: NotificationService
        let soundSelectionID: String
        let deliveryMode: NotificationDeliveryMode
        let volume: Double
    }

    struct DictationState {
        let liveTranscriptPreviewEnabled: Bool
        let translateOnDictateEnabled: Bool
        let targetLanguageIdentifier: String
    }

    let configExisted: Bool
    let configContents: String?
    let workspaceState: WorkspacePreferenceState
    let windowBorderState: WindowBorderPreferenceState
    let dictation: DictationState
    let soundWhenFocused: Bool
    let bannerWhenFocused: Bool
    let notificationServices: [NotificationServiceState]
}

/// The reset transaction: capture, change, save, and restore when the save fails.
@MainActor
enum SettingsConfigurationReset {
    static func reset(
        captureRollback: () -> SettingsConfigurationRollbackState,
        mutate: () -> Void,
        persist: () -> Bool,
        restore: (SettingsConfigurationRollbackState) -> Void
    ) -> Bool {
        let rollback = captureRollback()
        mutate()
        guard persist() else {
            restore(rollback)
            return false
        }
        return true
    }

    static func captureRollbackState(
        configPath: String,
        workspace: WorkspacePreferenceState,
        dictation: SettingsConfigurationRollbackState.DictationState
    ) -> SettingsConfigurationRollbackState {
        let fileExists = FileManager.default.fileExists(atPath: configPath)
        let contents = fileExists
            ? (try? String(contentsOfFile: configPath, encoding: .utf8))
            : nil

        let manager = NotificationSoundManager.shared
        let serviceStates = NotificationService.configurableCases.map { service in
            SettingsConfigurationRollbackState.NotificationServiceState(
                service: service,
                soundSelectionID: manager.soundName(for: service),
                deliveryMode: manager.deliveryMode(for: service),
                volume: manager.volume(for: service)
            )
        }

        return SettingsConfigurationRollbackState(
            configExisted: fileExists,
            configContents: contents,
            workspaceState: workspace,
            windowBorderState: WindowBorderPreferences.state(),
            dictation: dictation,
            soundWhenFocused: manager.soundWhenFocused,
            bannerWhenFocused: manager.bannerWhenFocused,
            notificationServices: serviceStates
        )
    }

    static func restoreRollbackState(
        _ rollback: SettingsConfigurationRollbackState,
        configPath: String,
        writeConfigFile: (String) throws -> Void,
        restoreWorkspacePreferenceState: (WorkspacePreferenceState) -> Void,
        restoreDictation: (SettingsConfigurationRollbackState.DictationState) -> Void
    ) {
        if rollback.configExisted {
            if let contents = rollback.configContents {
                try? writeConfigFile(contents)
            }
        } else {
            try? FileManager.default.removeItem(atPath: configPath)
        }

        restoreWorkspacePreferenceState(rollback.workspaceState)
        storeWindowBorderState(rollback.windowBorderState)

        restoreDictation(rollback.dictation)

        let manager = NotificationSoundManager.shared
        manager.soundWhenFocused = rollback.soundWhenFocused
        manager.bannerWhenFocused = rollback.bannerWhenFocused
        for serviceState in rollback.notificationServices {
            manager.setSoundName(serviceState.soundSelectionID, for: serviceState.service)
            manager.setDeliveryMode(serviceState.deliveryMode, for: serviceState.service)
            manager.setVolume(serviceState.volume, for: serviceState.service)
        }
    }

    static func storeWindowBorderState(_ state: WindowBorderPreferenceState) {
        let normalizedState = WindowBorderPreferences.normalizedState(state)
        let defaults = UserDefaults.standard
        defaults.set(normalizedState.enabled, forKey: WindowBorderPreferences.enabledPreferenceKey)
        defaults.set(normalizedState.scope.rawValue, forKey: WindowBorderPreferences.scopePreferenceKey)
        defaults.set(normalizedState.width, forKey: WindowBorderPreferences.widthPreferenceKey)
        defaults.set(normalizedState.radius, forKey: WindowBorderPreferences.radiusPreferenceKey)
        defaults.set(normalizedState.colorMode.rawValue, forKey: WindowBorderPreferences.colorModePreferenceKey)
        defaults.set(normalizedState.focusedPalette.rawValue, forKey: WindowBorderPreferences.focusedPalettePreferenceKey)
        defaults.set(normalizedState.unfocusedPalette.rawValue, forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey)
    }

    static func resetNotificationPreferencesToDefaults() {
        let manager = NotificationSoundManager.shared
        for service in NotificationService.configurableCases {
            manager.setSoundName(NotificationSoundManager.silentSelectionID, for: service)
            manager.setDeliveryMode(.bannerAndSound, for: service)
            manager.setVolume(1.0, for: service)
        }
        manager.soundWhenFocused = true
        manager.bannerWhenFocused = false
    }
}
#endif
