import AVFoundation
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsNotificationSoundControlsTests {
    @Test func serviceEditsStayIsolatedAndPersistOnlyChangedValues() throws {
        let controller = SettingsController.shared
        let manager = NotificationSoundManager.shared
        let sound = try #require(manager.systemSounds.first)
        let services = NotificationService.configurableCases
        let managerBefore = NotificationServiceSettings.captureAll()
        let controllerBefore = Dictionary(uniqueKeysWithValues: services.map { service in
            (service, NotificationServiceSettings(
                selectionID: controller.notificationSoundSelection(for: service),
                deliveryMode: controller.notificationSoundDeliveryMode(for: service),
                volume: controller.notificationSoundVolume(for: service)
            ))
        })
        defer {
            for service in services {
                if let state = controllerBefore[service] {
                    controller.setNotificationSoundSelection(state.selectionID, for: service)
                    controller.setNotificationSoundDeliveryMode(state.deliveryMode, for: service)
                    controller.setNotificationSoundVolume(state.volume, for: service)
                }
                if let state = managerBefore[service] {
                    manager.setSoundName(state.selectionID, for: service)
                    manager.setDeliveryMode(state.deliveryMode, for: service)
                    manager.setVolume(state.volume, for: service)
                }
            }
            manager._testResetPreferenceMutationCounts()
        }

        for service in services {
            controller.setNotificationSoundSelection("none", for: service)
            controller.setNotificationSoundDeliveryMode(.off, for: service)
            controller.setNotificationSoundVolume(0.1, for: service)
        }
        manager._testResetPreferenceMutationCounts()

        for service in services {
            let othersBefore = NotificationServiceSettings.captureAll().filter { $0.key != service }
            controller.setNotificationSoundSelection(sound.id, for: service)
            controller.setNotificationSoundDeliveryMode(.soundOnly, for: service)
            controller.setNotificationSoundVolume(0.65, for: service)
            #expect(controller.notificationSoundSelection(for: service) == sound.id)
            #expect(controller.notificationSoundDeliveryMode(for: service) == .soundOnly)
            #expect(controller.notificationSoundVolume(for: service) == 0.65)
            #expect(NotificationServiceSettings.capture(for: service) == NotificationServiceSettings(
                selectionID: sound.id, deliveryMode: .soundOnly, volume: 0.65
            ))
            for (other, state) in othersBefore {
                #expect(NotificationServiceSettings.capture(for: other) == state)
                #expect(controller.notificationSoundSelection(for: other) == state.selectionID)
                #expect(controller.notificationSoundDeliveryMode(for: other) == state.deliveryMode)
                #expect(controller.notificationSoundVolume(for: other) == state.volume)
            }
        }
        #expect(manager._testPreferenceMutationCounts == NotificationSoundPreferenceMutationCounts(
            soundSelectionWrites: services.count,
            deliveryModeWrites: services.count,
            volumeWrites: services.count
        ))

        manager._testResetPreferenceMutationCounts()
        for service in services {
            controller.setNotificationSoundSelection(sound.id, for: service)
            controller.setNotificationSoundDeliveryMode(.soundOnly, for: service)
            controller.setNotificationSoundVolume(0.65, for: service)
        }
        let snapshot = NotificationServiceSettings.captureAll()
        #expect(Set(snapshot.keys) == Set(services))
        #expect(manager._testPreferenceMutationCounts == .zero)
    }

    @Test func deliveryModesExposeSoundControlAvailability() {
        #expect(NotificationDeliveryMode.bannerAndSound.allowsSound)
        #expect(NotificationDeliveryMode.bannerAndSound.allowsSoundSelection)

        #expect(!NotificationDeliveryMode.bannerOnly.allowsSound)
        #expect(NotificationDeliveryMode.bannerOnly.allowsSoundSelection)

        #expect(NotificationDeliveryMode.soundOnly.allowsSound)
        #expect(NotificationDeliveryMode.soundOnly.allowsSoundSelection)

        #expect(!NotificationDeliveryMode.off.allowsSound)
        #expect(!NotificationDeliveryMode.off.allowsSoundSelection)
    }

    @Test func selectingNoneCancelsPendingPreviewAndStopsCurrentPreviewImmediately() throws {
        let controller = SettingsController.shared
        let manager = NotificationSoundManager.shared
        let player = try AVAudioPlayer(contentsOf: firstSystemSoundURL(fileManager: .default))
        manager._testResetPlaybackState()
        defer { manager._testResetPlaybackState() }

        manager._testInjectPreviewSound(player)
        controller.previewSound("bundled:pending-preview", volume: 1.0)

        #expect(controller._testHasPendingNotificationPreview)
        #expect(manager.isPreviewPlaying)

        controller.previewSound("none", volume: 1.0)

        #expect(!controller._testHasPendingNotificationPreview)
        #expect(manager._testPreviewSound() == nil)
        #expect(!manager.isPreviewPlaying)
    }

    private func firstSystemSoundURL(fileManager: FileManager) throws -> URL {
        let root = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        guard let soundURL = urls.first(where: { ["aiff", "wav", "caf", "m4a"].contains($0.pathExtension.lowercased()) }) else {
            throw SettingsNotificationSoundControlsTestError.noSystemSoundFound
        }

        return soundURL
    }
}

private enum SettingsNotificationSoundControlsTestError: Error {
    case noSystemSoundFound
}
