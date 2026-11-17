#if os(macOS)

/// Shared permission refresh logic — used by SettingsController and OnboardingController.
@MainActor
protocol PermissionRefreshing: AnyObject {
    var accessibilityGranted: Bool { get set }
    var microphoneGranted: Bool { get set }
    var speechRecognitionGranted: Bool { get set }
}

extension PermissionRefreshing {
    func refreshPermissions() {
        let dc = DictationController.shared
        let newAccessibilityGranted = dc.isAccessibilityGranted
        if accessibilityGranted != newAccessibilityGranted {
            accessibilityGranted = newAccessibilityGranted
        }

        let newMicrophoneGranted = dc.isMicrophoneGranted
        if microphoneGranted != newMicrophoneGranted {
            microphoneGranted = newMicrophoneGranted
        }

        let newSpeechRecognitionGranted = dc.isSpeechRecognitionGranted
        if speechRecognitionGranted != newSpeechRecognitionGranted {
            speechRecognitionGranted = newSpeechRecognitionGranted
        }
    }
}

#endif // os(macOS)
