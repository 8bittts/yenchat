#if os(macOS)
import Foundation

struct NotificationServiceSettings: Equatable {
    var selectionID: String
    var deliveryMode: NotificationDeliveryMode
    var volume: Double

    @MainActor
    static func capture(for service: NotificationService) -> Self {
        let manager = NotificationSoundManager.shared
        return Self(
            selectionID: manager.soundName(for: service),
            deliveryMode: manager.deliveryMode(for: service),
            volume: manager.volume(for: service)
        )
    }

    @MainActor
    static func captureAll() -> [NotificationService: Self] {
        Dictionary(uniqueKeysWithValues: NotificationService.configurableCases.map { ($0, capture(for: $0)) })
    }
}

/// Persists edits from the controller's service accessors and focus toggles.
/// Observer posts use the controller's coalescing path.
/// Hydration suppresses persistence while the controller loads manager snapshots.
@MainActor
final class NotificationSoundStore {
    private unowned let controller: SettingsController

    /// Prevents hydration from writing preferences back to the manager.
    var suppressSoundManagerSync = false

    init(controller: SettingsController) {
        self.controller = controller
    }

    func syncSoundNamePreference(
        _ selectionID: String,
        oldValue: String,
        for service: NotificationService
    ) {
        guard !suppressSoundManagerSync, selectionID != oldValue else { return }
        NotificationSoundManager.shared.setSoundName(selectionID, for: service)
        controller.notifySoundsSettingsObservers()
    }

    func syncSoundDeliveryModePreference(
        _ mode: NotificationDeliveryMode,
        oldValue: NotificationDeliveryMode,
        for service: NotificationService
    ) {
        guard !suppressSoundManagerSync, mode != oldValue else { return }
        NotificationSoundManager.shared.setDeliveryMode(mode, for: service)
        controller.notifySoundsSettingsObservers()
    }

    func syncSoundVolumePreference(
        _ volume: Double,
        oldValue: Double,
        for service: NotificationService
    ) {
        guard !suppressSoundManagerSync, volume != oldValue else { return }
        NotificationSoundManager.shared.setVolume(volume, for: service)
        controller.notifySoundsSettingsObservers()
    }

    func syncSoundFocusBehaviorPreference(
        _ enabled: Bool,
        oldValue: Bool,
        keyPath: ReferenceWritableKeyPath<NotificationSoundManager, Bool>
    ) {
        guard !suppressSoundManagerSync, enabled != oldValue else { return }
        NotificationSoundManager.shared[keyPath: keyPath] = enabled
    }
}
#endif
