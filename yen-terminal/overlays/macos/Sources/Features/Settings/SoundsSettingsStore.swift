import Foundation
import SwiftUI
#if canImport(Translation)
import Translation
#endif

@MainActor
final class SoundsSettingsStore: SettingsSnapshotStore<SoundsSettingsStore.Snapshot> {
    struct Snapshot: Equatable {
        struct Permissions: Equatable {
            let accessibilityGranted: Bool
            let microphoneGranted: Bool
            let speechRecognitionGranted: Bool
            let microphoneFixTitle: String
            let speechFixTitle: String
            let dictationLocalSpeechServiceReady: Bool
            let dictationLocalServiceIssueDetail: String
        }

        struct Dictation: Equatable {
            let liveTranscriptPreviewEnabled: Bool
            let inputDeviceOptions: [DictationInputDeviceOption]
            let selectedInputDeviceIdentifier: String
            let inputDeviceFallbackReason: String?
        }

        struct Translation: Equatable {
            let translationSupportedOnThisMac: Bool
            let translateOnDictateEnabled: Bool
            let targetLanguageIdentifier: String
            let availableTargetLanguages: [DictationTranslationLanguageOption]
            let preparationRequest: DictationTranslationPreparationRequest?
        }

        struct NotificationAccess: Equatable {
            let authorizationAllowsDelivery: Bool
            let authorizationStatusLabel: String
            let authorizationActionTitle: String
            let authorizationActionHint: String
            let authorizationDetailLine: String
        }

        struct CommandNotifications: Equatable {
            let notifyOnCommandFinish: String
            let notifyOnCommandFinishActionBell: Bool
            let notifyOnCommandFinishActionNotify: Bool
            let notifyOnCommandFinishAfterSeconds: Int
            let notificationAuthorizationAllowsDelivery: Bool
        }

        struct FocusBehavior: Equatable {
            let soundWhenFocused: Bool
            let bannerWhenFocused: Bool
        }

        struct NotificationServicePreference: Identifiable, Equatable {
            let service: NotificationService
            let selection: String
            let deliveryMode: NotificationDeliveryMode
            let volume: Double

            var id: NotificationService { service }
        }

        struct NotificationSoundLibrary: Equatable {
            let systemSounds: [NotificationSoundOption]
        }

        let permissions: Permissions
        let dictation: Dictation
        let translation: Translation
        let notificationAccess: NotificationAccess
        let commandNotifications: CommandNotifications
        let focusBehavior: FocusBehavior
        let notificationServicePreferences: [NotificationServicePreference]
        let notificationSoundLibrary: NotificationSoundLibrary

        @MainActor
        static func capture(from controller: SettingsController) -> Snapshot {
            Snapshot(
                permissions: Permissions(
                    accessibilityGranted: controller.accessibilityGranted,
                    microphoneGranted: controller.microphoneGranted,
                    speechRecognitionGranted: controller.speechRecognitionGranted,
                    microphoneFixTitle: DictationController.permissionActionTitle(for: .microphone),
                    speechFixTitle: DictationController.permissionActionTitle(for: .speechRecognition),
                    dictationLocalSpeechServiceReady: controller.dictationLocalSpeechServiceReady,
                    dictationLocalServiceIssueDetail: controller.dictationLocalServiceIssueDetail
                ),
                dictation: Dictation(
                    liveTranscriptPreviewEnabled: controller.dictationLiveTranscriptPreviewEnabled,
                    inputDeviceOptions: controller.dictationInputDeviceOptions,
                    selectedInputDeviceIdentifier: controller.dictationSelectedInputDeviceIdentifier,
                    inputDeviceFallbackReason: controller.dictationInputDeviceFallbackReason
                ),
                translation: Translation(
                    translationSupportedOnThisMac: controller.dictationTranslationSupportedOnThisMac,
                    translateOnDictateEnabled: controller.translateOnDictateEnabled,
                    targetLanguageIdentifier: controller.dictationTranslateTargetLanguageIdentifier,
                    availableTargetLanguages: controller.availableDictationTargetLanguages,
                    preparationRequest: controller.dictationTranslationPreparationRequest
                ),
                notificationAccess: NotificationAccess(
                    authorizationAllowsDelivery: controller.notificationAuthorizationAllowsDelivery,
                    authorizationStatusLabel: controller.notificationAuthorizationStatusLabel,
                    authorizationActionTitle: controller.notificationAuthorizationActionTitle,
                    authorizationActionHint: controller.notificationAuthorizationActionHint,
                    authorizationDetailLine: controller.notificationAuthorizationDetailLine
                ),
                commandNotifications: CommandNotifications(
                    notifyOnCommandFinish: controller.notifyOnCommandFinish,
                    notifyOnCommandFinishActionBell: controller.notifyOnCommandFinishActionBell,
                    notifyOnCommandFinishActionNotify: controller.notifyOnCommandFinishActionNotify,
                    notifyOnCommandFinishAfterSeconds: controller.notifyOnCommandFinishAfterSeconds,
                    notificationAuthorizationAllowsDelivery: controller.notificationAuthorizationAllowsDelivery
                ),
                focusBehavior: FocusBehavior(
                    soundWhenFocused: controller.soundWhenFocused,
                    bannerWhenFocused: controller.bannerWhenFocused
                ),
                notificationServicePreferences: NotificationService.configurableCases.map { service in
                    NotificationServicePreference(
                        service: service,
                        selection: controller.notificationSoundSelection(for: service),
                        deliveryMode: controller.notificationSoundDeliveryMode(for: service),
                        volume: controller.notificationSoundVolume(for: service)
                    )
                },
                notificationSoundLibrary: NotificationSoundLibrary(
                    systemSounds: controller.availableSystemSounds
                )
            )
        }
    }

    private let controller: SettingsController

    init(controller: SettingsController) {
        self.controller = controller
        super.init(
            notification: .yenSoundsSettingsDidChange,
            object: controller,
            capture: { Snapshot.capture(from: controller) }
        )
    }

    func setLiveTranscriptPreviewEnabled(_ value: Bool) {
        controller.dictationLiveTranscriptPreviewEnabled = value
    }

    func setSelectedInputDeviceIdentifier(_ value: String) {
        controller.dictationSelectedInputDeviceIdentifier = value
    }

    func startInputDeviceMonitoring() {
        controller.startDictationInputDeviceMonitoring()
    }

    func stopInputDeviceMonitoring() {
        controller.stopDictationInputDeviceMonitoring()
    }

    func setTranslateOnDictateEnabled(_ value: Bool) {
        controller.translateOnDictateEnabled = value
    }

    func setTargetLanguageIdentifier(_ value: String) {
        controller.dictationTranslateTargetLanguageIdentifier = value
    }

#if canImport(Translation)
    @available(macOS 26.0, *)
    func prepareDictationTranslationAssets(
        with session: TranslationSession,
        requestID: UUID
    ) async {
        await controller.prepareDictationTranslationAssets(
            with: session,
            requestID: requestID
        )
    }
#endif

    func handleNotificationAuthorizationAction() {
        controller.handleNotificationAuthorizationAction()
    }

    func setNotifyOnCommandFinish(_ value: String) {
        controller.notifyOnCommandFinish = value
    }

    func setNotifyOnCommandFinishActionBell(_ value: Bool) {
        controller.notifyOnCommandFinishActionBell = value
    }

    func setNotifyOnCommandFinishActionNotify(_ value: Bool) {
        controller.notifyOnCommandFinishActionNotify = value
    }

    func setNotifyOnCommandFinishAfterSeconds(_ value: Int) {
        controller.notifyOnCommandFinishAfterSeconds = value
    }

    func setSoundWhenFocused(_ value: Bool) {
        controller.soundWhenFocused = value
    }

    func setBannerWhenFocused(_ value: Bool) {
        controller.bannerWhenFocused = value
    }

    func displaySoundSelection(_ selectionID: String) -> String {
        controller.displaySoundSelection(selectionID)
    }

    func setNotificationSoundSelection(_ selection: String, for service: NotificationService) {
        controller.setNotificationSoundSelection(selection, for: service)
    }

    func setNotificationSoundDeliveryMode(
        _ deliveryMode: NotificationDeliveryMode,
        for service: NotificationService
    ) {
        controller.setNotificationSoundDeliveryMode(deliveryMode, for: service)
    }

    func setNotificationSoundVolume(_ volume: Double, for service: NotificationService) {
        controller.setNotificationSoundVolume(volume, for: service)
    }

    func previewSound(_ name: String, volume: Double) {
        controller.previewSound(name, volume: volume)
    }

}
