import AVFoundation
import ApplicationServices
import Speech

struct DictationPermissionSnapshot: Equatable {
    let missing: [DictationController.PrivacyDestination]
}

@MainActor
enum DictationPermissionMenuPolicy {
    static func localServiceRecoveryBody(for issue: DictationController.LocalServiceIssue) -> String {
        switch issue {
        case .recognizerUnavailable:
            return "Local speech recognizer unavailable. Open Speech Recognition Settings, then try \(DictationCopy.fixedHotkey) again."
        case .legacySystemDictationDisabled:
            return "System Dictation may be off. Open Dictation Settings, enable it, then try \(DictationCopy.fixedHotkey) again."
        case .noAudioInput:
            return "No audio input device detected. Open Sound Input Settings, select a microphone, then try \(DictationCopy.fixedHotkey) again."
        case .foregroundInstallRequired:
            return "Bring YEN to the foreground so macOS can finish installing the local speech model, then try \(DictationCopy.fixedHotkey) again."
        case .runtimeFailure:
            return "Local speech service failed. Open Speech Recognition Settings or use Re-check Local Speech Service in YEN."
        }
    }

    static func menuState(
        missing: [DictationController.PrivacyDestination],
        localServiceIssue: DictationController.LocalServiceIssue?,
        isPaused: Bool,
        launchNeedsApproval: Bool
    ) -> DictationController.MenuState {
        let pauseTitle = isPaused ? DictationCopy.resumeActionTitle : DictationCopy.pauseActionTitle
        if missing.isEmpty {
            if let localServiceIssue {
                return DictationController.MenuState(
                    summaryTitle: DictationCopy.blockedSummary,
                    detailTitle: localServiceIssue.detailTitle,
                    openPrimaryTitle: localServiceIssue.openActionTitle,
                    openPrimaryEnabled: true,
                    openPrimaryAction: localServiceIssue.openAction,
                    recheckTitle: DictationCopy.recheckLocalServiceTitle,
                    recheckEnabled: true,
                    pauseTitle: pauseTitle,
                    pauseEnabled: false,
                    toolTip: DictationCopy.blockedLocalServiceToolTip(
                        detail: localServiceIssue.detailTitle,
                        launchNeedsApproval: launchNeedsApproval
                    )
                )
            }

            if isPaused {
                return DictationController.MenuState(
                    summaryTitle: DictationCopy.pausedSummary,
                    detailTitle: DictationCopy.pausedDetail,
                    openPrimaryTitle: DictationCopy.openAllGrantedTitle,
                    openPrimaryEnabled: false,
                    openPrimaryAction: .none,
                    recheckTitle: DictationCopy.recheckPermissionsTitle,
                    recheckEnabled: true,
                    pauseTitle: pauseTitle,
                    pauseEnabled: true,
                    toolTip: DictationCopy.pausedToolTip(launchNeedsApproval: launchNeedsApproval)
                )
            }

            return DictationController.MenuState(
                summaryTitle: launchNeedsApproval
                    ? DictationCopy.launchAtLoginPendingSummary
                    : DictationCopy.enabledSummary,
                detailTitle: DictationCopy.enabledDetail,
                openPrimaryTitle: DictationCopy.openAllGrantedTitle,
                openPrimaryEnabled: false,
                openPrimaryAction: .none,
                recheckTitle: DictationCopy.recheckPermissionsTitle,
                recheckEnabled: true,
                pauseTitle: pauseTitle,
                pauseEnabled: true,
                toolTip: DictationCopy.enabledToolTip(launchNeedsApproval: launchNeedsApproval)
            )
        }

        let names = missing.map(\.title).joined(separator: ", ")
        return DictationController.MenuState(
            summaryTitle: DictationCopy.blockedSummary,
            detailTitle: DictationCopy.blockedPermissionsDetail(names: names),
            openPrimaryTitle: DictationCopy.openPermissionSettingsTitle(missing[0].title),
            openPrimaryEnabled: true,
            openPrimaryAction: .openMissingPermission,
            recheckTitle: DictationCopy.recheckPermissionsTitle,
            recheckEnabled: true,
            pauseTitle: pauseTitle,
            pauseEnabled: false,
            toolTip: DictationCopy.blockedPermissionsToolTip(
                names: names,
                launchNeedsApproval: launchNeedsApproval
            )
        )
    }

    static func permissionActionTitle(
        for destination: DictationController.PrivacyDestination,
        speechStatus: SFSpeechRecognizerAuthorizationStatus,
        microphoneStatus: AVAuthorizationStatus
    ) -> String {
        switch permissionSettingsActionPlan(
            for: destination,
            speechStatus: speechStatus,
            microphoneStatus: microphoneStatus
        ) {
        case .requestSpeechRecognitionAuthorization, .requestMicrophoneAccess:
            return "Grant"
        case .promptAccessibilityThenOpenPrivacySettings, .openPrivacySettings:
            return "Fix"
        }
    }

    static func permissionSettingsActionPlan(
        for destination: DictationController.PrivacyDestination,
        speechStatus: SFSpeechRecognizerAuthorizationStatus,
        microphoneStatus: AVAuthorizationStatus
    ) -> DictationController.PermissionSettingsActionPlan {
        switch destination {
        case .accessibility:
            return .promptAccessibilityThenOpenPrivacySettings
        case .speechRecognition:
            return speechStatus == .notDetermined
                ? .requestSpeechRecognitionAuthorization
                : .openPrivacySettings
        case .microphone:
            return microphoneStatus == .notDetermined
                ? .requestMicrophoneAccess
                : .openPrivacySettings
        }
    }

    static func shouldOpenPrivacySettingsAfterSpeechAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> Bool {
        status != .authorized
    }

    static func shouldOpenPrivacySettingsAfterMicrophoneAuthorization(_ granted: Bool) -> Bool {
        !granted
    }

    static func missingPrivacyDestinations(
        provider: DictationController.PrivacyDestinationProvider?
    ) -> [DictationController.PrivacyDestination] {
        if let provider {
            return provider()
        }

        var missing: [DictationController.PrivacyDestination] = []

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus != .authorized {
            missing.append(.speechRecognition)
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus != .authorized {
            missing.append(.microphone)
        }

        if !AXIsProcessTrusted() {
            missing.append(.accessibility)
        }

        return missing
    }
}
