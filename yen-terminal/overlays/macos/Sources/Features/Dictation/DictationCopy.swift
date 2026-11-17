import Foundation

/// Canonical copy for dictation menu + settings surfaces.
enum DictationCopy {
    static let fixedHotkey = "Option + Space"

    static let enabledSummary = "Speech-to-Text is enabled"
    static let pausedSummary = "Speech-to-Text is paused"
    static let blockedSummary = "Speech-to-Text is blocked"
    static let launchAtLoginPendingSummary = "Launch at Login is pending approval"

    // Keep this copy limit-agnostic; legacy timeout behavior is handled by the recognizer path.
    static let enabledDetail = "Hold \(fixedHotkey) to dictate (fixed)"
    static let pausedDetail = "Paused: choose Resume Dictation to dictate"
    static let localRecognizerUnavailableDetail = "Blocked: local speech recognizer unavailable"
    static let localLegacyDictationDisabledDetail = "Blocked: local speech recognizer unavailable (System Dictation may be off)"
    static let localNoAudioInputDetail = "Blocked: no audio input device detected"
    static let localForegroundInstallRequiredDetail = "Blocked: bring YEN to the foreground to finish installing local speech"
    static let localRuntimeFailureDetail = "Blocked: local speech service failed"

    static let pauseActionTitle = "Pause Dictation"
    static let resumeActionTitle = "Resume Dictation"

    static let recheckPermissionsTitle = "Re-check Permissions"
    static let recheckLocalServiceTitle = "Re-check Local Speech Service"
    static let openAllGrantedTitle = "Open Missing Permission Settings (all granted)"
    static let openSpeechRecognitionSettingsTitle = "Open Speech Recognition Settings"
    static let openSystemDictationSettingsTitle = "Open Dictation Settings"
    static let openSoundInputSettingsTitle = "Open Sound Input Settings"
    static let activateYENTitle = "Bring YEN to Front"

    static let hotkeyConflictHint = "If \(fixedHotkey) conflicts, change it in Keyboard Shortcuts"
    static let overlayListeningLine = "Listening..."
    static let overlayProcessingLine = "Processing..."
    static let settingsLiveTranscriptPreviewLine = "Show live text in the overlay while recording. Inserted text is the finalized transcript."

    static let settingsMicrophoneLine = "Choose which microphone dictation records from. System Default follows System Settings > Sound > Input. A change applies to your next dictation."

    static let pausedAttemptOverlayLine = "Dictation is paused. Choose Resume Dictation in the menu."

    static func blockedPermissionsDetail(names: String) -> String {
        "Blocked: enable \(names)"
    }

    static func openPermissionSettingsTitle(_ permissionName: String) -> String {
        "Open \(permissionName) Settings"
    }

    static func enabledToolTip(launchNeedsApproval: Bool) -> String {
        launchNeedsApproval
            ? "YEN — Launch at Login pending approval in System Settings"
            : "YEN — \(fixedHotkey) to dictate"
    }

    static func pausedToolTip(launchNeedsApproval: Bool) -> String {
        launchNeedsApproval
            ? "YEN — Dictation paused; Launch at Login pending approval"
            : "YEN — Dictation paused"
    }

    static func blockedPermissionsToolTip(names: String, launchNeedsApproval: Bool) -> String {
        let suffix = launchNeedsApproval ? "; Launch at Login pending approval" : ""
        return "YEN — Dictation blocked (\(names)\(suffix))"
    }

    static func blockedLocalServiceToolTip(detail: String, launchNeedsApproval: Bool) -> String {
        let suffix = launchNeedsApproval ? "; Launch at Login pending approval" : ""
        return "YEN — Dictation blocked (\(detail)\(suffix))"
    }
}
