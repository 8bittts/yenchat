import Combine
import Foundation
import Testing
import UserNotifications
@testable import YEN

@MainActor
@Suite(.serialized)
struct SoundsSettingsStoreTests {
    @Test func storeDoesNotPublishForEqualSnapshotNotification() {
        let controller = SettingsController.shared
        let originalAccessibilityGranted = controller.accessibilityGranted
        let originalMicrophoneGranted = controller.microphoneGranted
        let originalSpeechRecognitionGranted = controller.speechRecognitionGranted
        let originalNotifyOnCommandFinish = controller.notifyOnCommandFinish
        let originalNotifyOnCommandFinishActionBell = controller.notifyOnCommandFinishActionBell
        let originalNotifyOnCommandFinishActionNotify = controller.notifyOnCommandFinishActionNotify
        let originalNotifyOnCommandFinishAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        let originalSoundWhenFocused = controller.soundWhenFocused
        let originalBannerWhenFocused = controller.bannerWhenFocused
        let originalGeneralSound = controller.notificationSoundSelection(for: .general)
        let originalBuildDeliveryMode = controller.notificationSoundDeliveryMode(for: .build)
        let originalBuildVolume = controller.notificationSoundVolume(for: .build)
        let originalAvailableSystemSounds = controller.availableSystemSounds
        defer {
            controller.accessibilityGranted = originalAccessibilityGranted
            controller.microphoneGranted = originalMicrophoneGranted
            controller.speechRecognitionGranted = originalSpeechRecognitionGranted
            controller.notifyOnCommandFinish = originalNotifyOnCommandFinish
            controller.notifyOnCommandFinishActionBell = originalNotifyOnCommandFinishActionBell
            controller.notifyOnCommandFinishActionNotify = originalNotifyOnCommandFinishActionNotify
            controller.notifyOnCommandFinishAfterSeconds = originalNotifyOnCommandFinishAfterSeconds
            controller.soundWhenFocused = originalSoundWhenFocused
            controller.bannerWhenFocused = originalBannerWhenFocused
            controller.setNotificationSoundSelection(originalGeneralSound, for: .general)
            controller.setNotificationSoundDeliveryMode(originalBuildDeliveryMode, for: .build)
            controller.setNotificationSoundVolume(originalBuildVolume, for: .build)
            controller.availableSystemSounds = originalAvailableSystemSounds
        }

        let populatedSystemSound = NotificationSoundOption(id: "system:audit", name: "Audit")
        controller.accessibilityGranted = true
        controller.microphoneGranted = true
        controller.speechRecognitionGranted = true
        controller.notifyOnCommandFinish = "always"
        controller.notifyOnCommandFinishActionBell = true
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 7
        controller.soundWhenFocused = true
        controller.bannerWhenFocused = true
        controller.setNotificationSoundSelection(populatedSystemSound.id, for: .general)
        controller.setNotificationSoundDeliveryMode(.soundOnly, for: .build)
        controller.setNotificationSoundVolume(0.65, for: .build)
        controller.availableSystemSounds = [populatedSystemSound]

        let store = SoundsSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenSoundsSettingsDidChange, object: controller)

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func storeIgnoresOtherSettingsNotifications() {
        let controller = SettingsController.shared
        let store = SoundsSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenGeneralSettingsDidChange, object: controller)
        NotificationCenter.default.post(name: .yenKeyboardSettingsDidChange, object: controller)
        NotificationCenter.default.post(name: .yenThemesSettingsDidChange, object: controller)
        NotificationCenter.default.post(name: .yenWorkspaceSettingsDidChange, object: controller)
        NotificationCenter.default.post(name: .yenSoundsSettingsDidChange, object: NSObject())

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func storeTracksPermissionsAndNotificationAccess() {
        let controller = SettingsController.shared
        let originalAccessibilityGranted = controller.accessibilityGranted
        let originalMicrophoneGranted = controller.microphoneGranted
        let originalSpeechRecognitionGranted = controller.speechRecognitionGranted
        let originalNotificationAuthorizationStatus = controller.notificationAuthorizationStatus
        let originalLocalServiceIssueDetail = controller.dictationLocalServiceIssueDetail

        defer {
            controller.accessibilityGranted = originalAccessibilityGranted
            controller.microphoneGranted = originalMicrophoneGranted
            controller.speechRecognitionGranted = originalSpeechRecognitionGranted
            controller.notificationAuthorizationStatus = originalNotificationAuthorizationStatus
            controller.dictationLocalServiceIssueDetail = originalLocalServiceIssueDetail
        }

        controller.accessibilityGranted = false
        controller.microphoneGranted = false
        controller.speechRecognitionGranted = false
        controller.notificationAuthorizationStatus = .notDetermined
        controller.dictationLocalServiceIssueDetail = ""

        let store = SoundsSettingsStore(controller: controller)

        controller.accessibilityGranted = true
        controller.microphoneGranted = true
        controller.speechRecognitionGranted = true
        controller.notificationAuthorizationStatus = .denied
        controller.dictationLocalServiceIssueDetail = "Local speech unavailable."

        #expect(store.snapshot.permissions.accessibilityGranted)
        #expect(store.snapshot.permissions.microphoneGranted)
        #expect(store.snapshot.permissions.speechRecognitionGranted)
        #expect(store.snapshot.permissions.dictationLocalServiceIssueDetail == "Local speech unavailable.")
        #expect(!store.snapshot.permissions.dictationLocalSpeechServiceReady)
        #expect(
            store.snapshot.permissions.microphoneFixTitle
                == DictationController.permissionActionTitle(for: .microphone)
        )
        #expect(
            store.snapshot.permissions.speechFixTitle
                == DictationController.permissionActionTitle(for: .speechRecognition)
        )
        #expect(
            store.snapshot.notificationAccess.authorizationAllowsDelivery
                == controller.notificationAuthorizationAllowsDelivery
        )
        #expect(
            store.snapshot.notificationAccess.authorizationStatusLabel
                == controller.notificationAuthorizationStatusLabel
        )
        #expect(
            store.snapshot.notificationAccess.authorizationActionTitle
                == controller.notificationAuthorizationActionTitle
        )
        #expect(
            store.snapshot.notificationAccess.authorizationActionHint
                == controller.notificationAuthorizationActionHint
        )
        #expect(
            store.snapshot.notificationAccess.authorizationDetailLine
                == controller.notificationAuthorizationDetailLine
        )
    }

    @Test func storeTracksDictationAndTranslationState() {
        let controller = SettingsController.shared
        let originalLiveTranscriptPreviewEnabled = controller.dictationLiveTranscriptPreviewEnabled
        let originalTranslateOnDictateEnabled = controller.translateOnDictateEnabled
        let originalTargetLanguageIdentifier = controller.dictationTranslateTargetLanguageIdentifier
        let originalAvailableTargetLanguages = controller.availableDictationTargetLanguages

        defer {
            controller.dictationLiveTranscriptPreviewEnabled = originalLiveTranscriptPreviewEnabled
            controller.translateOnDictateEnabled = originalTranslateOnDictateEnabled
            controller.dictationTranslateTargetLanguageIdentifier = originalTargetLanguageIdentifier
            controller.availableDictationTargetLanguages = originalAvailableTargetLanguages
        }

        let english = DictationTranslationLanguageCatalog.option(for: "en")
        let spanish = DictationTranslationLanguageCatalog.option(for: "es")
        controller.dictationLiveTranscriptPreviewEnabled = false
        controller.translateOnDictateEnabled = false
        controller.dictationTranslateTargetLanguageIdentifier = english.identifier
        controller.availableDictationTargetLanguages = [english]

        let store = SoundsSettingsStore(controller: controller)

        controller.dictationLiveTranscriptPreviewEnabled = true
        controller.availableDictationTargetLanguages = [english, spanish]
        controller.dictationTranslateTargetLanguageIdentifier = spanish.identifier
        controller.translateOnDictateEnabled = true

        #expect(store.snapshot.dictation.liveTranscriptPreviewEnabled)
        #expect(
            store.snapshot.translation.availableTargetLanguages == [english, spanish]
        )
        #expect(
            store.snapshot.translation.targetLanguageIdentifier
                == controller.dictationTranslateTargetLanguageIdentifier
        )
        #expect(
            store.snapshot.translation.translateOnDictateEnabled
                == controller.translateOnDictateEnabled
        )
    }

    @Test func storeTracksCommandNotificationsAndFocusBehavior() {
        let controller = SettingsController.shared
        let originalNotifyOnCommandFinish = controller.notifyOnCommandFinish
        let originalNotifyOnCommandFinishActionBell = controller.notifyOnCommandFinishActionBell
        let originalNotifyOnCommandFinishActionNotify = controller.notifyOnCommandFinishActionNotify
        let originalNotifyOnCommandFinishAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        let originalSoundWhenFocused = controller.soundWhenFocused
        let originalBannerWhenFocused = controller.bannerWhenFocused

        defer {
            controller.notifyOnCommandFinish = originalNotifyOnCommandFinish
            controller.notifyOnCommandFinishActionBell = originalNotifyOnCommandFinishActionBell
            controller.notifyOnCommandFinishActionNotify = originalNotifyOnCommandFinishActionNotify
            controller.notifyOnCommandFinishAfterSeconds = originalNotifyOnCommandFinishAfterSeconds
            controller.soundWhenFocused = originalSoundWhenFocused
            controller.bannerWhenFocused = originalBannerWhenFocused
        }

        controller.notifyOnCommandFinish = "unfocused"
        controller.notifyOnCommandFinishActionBell = true
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 5
        controller.soundWhenFocused = true
        controller.bannerWhenFocused = true

        let store = SoundsSettingsStore(controller: controller)

        controller.notifyOnCommandFinish = "always"
        controller.notifyOnCommandFinishActionBell = false
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 42
        controller.soundWhenFocused = false
        controller.bannerWhenFocused = false

        #expect(store.snapshot.commandNotifications.notifyOnCommandFinish == "always")
        #expect(!store.snapshot.commandNotifications.notifyOnCommandFinishActionBell)
        #expect(store.snapshot.commandNotifications.notifyOnCommandFinishActionNotify)
        #expect(store.snapshot.commandNotifications.notifyOnCommandFinishAfterSeconds == 42)
        #expect(!store.snapshot.focusBehavior.soundWhenFocused)
        #expect(!store.snapshot.focusBehavior.bannerWhenFocused)
    }

    @Test func storeTracksNotificationServicePreferencesAndSystemOnlyLibraryState() {
        let controller = SettingsController.shared
        let originalGeneralSound = controller.notificationSoundSelection(for: .general)
        let originalBuildDeliveryMode = controller.notificationSoundDeliveryMode(for: .build)
        let originalBuildVolume = controller.notificationSoundVolume(for: .build)
        let originalAvailableSystemSounds = controller.availableSystemSounds

        defer {
            controller.setNotificationSoundSelection(originalGeneralSound, for: .general)
            controller.setNotificationSoundDeliveryMode(originalBuildDeliveryMode, for: .build)
            controller.setNotificationSoundVolume(originalBuildVolume, for: .build)
            controller.availableSystemSounds = originalAvailableSystemSounds
        }

        let initialSystem = NotificationSoundOption(id: "system:glass", name: "Glass")
        controller.setNotificationSoundSelection("none", for: .general)
        controller.setNotificationSoundDeliveryMode(.bannerOnly, for: .build)
        controller.setNotificationSoundVolume(0.4, for: .build)
        controller.availableSystemSounds = [initialSystem]

        let store = SoundsSettingsStore(controller: controller)

        let updatedSystem = NotificationSoundOption(id: "system:hero", name: "Hero")
        controller.setNotificationSoundSelection("system:hero", for: .general)
        controller.setNotificationSoundDeliveryMode(.soundOnly, for: .build)
        controller.setNotificationSoundVolume(0.75, for: .build)
        controller.availableSystemSounds = [updatedSystem]

        let preferences = Dictionary(
            uniqueKeysWithValues: store.snapshot.notificationServicePreferences.map { ($0.service, $0) }
        )
        #expect(preferences[.general]?.selection == "system:hero")
        #expect(preferences[.build]?.deliveryMode == .soundOnly)
        #expect(preferences[.build]?.volume == 0.75)
        #expect(store.snapshot.notificationSoundLibrary.systemSounds == [updatedSystem])
    }
}
