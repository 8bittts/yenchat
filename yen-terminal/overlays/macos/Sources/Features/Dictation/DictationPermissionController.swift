import AppKit
import AVFoundation
import ApplicationServices
import Speech

/// Owns permission acquisition, observation, and background recovery delivery.
/// Session transitions and foreground menu presentation remain with the caller.
@MainActor
final class DictationPermissionController {
    private let permissionAuthorizer: DictationController.PermissionAuthorizer?
    private let privacyDestinationProvider: DictationController.PrivacyDestinationProvider?
    private let backgroundRecoveryReporter: DictationController.BackgroundRecoveryReporter?
    private let suppressInteractiveUI: Bool
    private var permissionMonitorTimer: Timer?
    private var lastPermissionSnapshot: DictationPermissionSnapshot?
    private static let permissionMonitorIntervalSeconds: TimeInterval = 4.0

    init(
        permissionAuthorizer: DictationController.PermissionAuthorizer? = nil,
        privacyDestinationProvider: DictationController.PrivacyDestinationProvider? = nil,
        backgroundRecoveryReporter: DictationController.BackgroundRecoveryReporter? = nil,
        suppressInteractiveUI: Bool
    ) {
        self.permissionAuthorizer = permissionAuthorizer
        self.privacyDestinationProvider = privacyDestinationProvider
        self.backgroundRecoveryReporter = backgroundRecoveryReporter
        self.suppressInteractiveUI = suppressInteractiveUI
    }

    func missingPrivacyDestinations() -> [DictationController.PrivacyDestination] {
        DictationPermissionMenuPolicy.missingPrivacyDestinations(provider: privacyDestinationProvider)
    }

    func refreshSnapshot() -> (previous: DictationPermissionSnapshot?, current: DictationPermissionSnapshot) {
        let snapshot = DictationPermissionSnapshot(missing: missingPrivacyDestinations())
        let previous = lastPermissionSnapshot
        lastPermissionSnapshot = snapshot
        return (previous, snapshot)
    }

    func authorizeForDictation(
        allowNativePrompts: Bool,
        refreshState: @MainActor @escaping () -> Void,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        if let permissionAuthorizer {
            permissionAuthorizer(allowNativePrompts, completion)
            return
        }
        checkPermissions(allowNativePrompts: allowNativePrompts, refreshState: refreshState, completion: completion)
    }

    /// Check accessibility, speech recognition, and microphone permissions.
    /// Prompts are only allowed for explicit foreground user intent.
    private func checkPermissions(
        allowNativePrompts: Bool,
        refreshState: @MainActor @escaping () -> Void,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        guard AXIsProcessTrusted() else {
            refreshState()
            completion(false)
            return
        }
        checkSpeechPermission(allowPrompt: allowNativePrompts) { speechGranted in
            guard speechGranted else {
                refreshState()
                completion(false)
                return
            }
            self.checkMicrophonePermission(allowPrompt: allowNativePrompts) { granted in
                refreshState()
                completion(granted)
            }
        }
    }

    /// Check Speech authorization quickly via current status; only prompt if needed.
    private func checkSpeechPermission(
        allowPrompt: Bool,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            guard allowPrompt else {
                completion(false)
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    completion(status == .authorized)
                }
            }
        default:
            completion(false)
        }
    }

    /// Check microphone permission quickly via current status; only prompt if needed.
    private func checkMicrophonePermission(
        allowPrompt: Bool,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            guard allowPrompt else {
                completion(false)
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    func startMonitoring(refreshState: @MainActor @escaping () -> Void) {
        stopMonitoring()
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: Self.permissionMonitorIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self != nil else { return }
                refreshState()
            }
        }
        permissionMonitorTimer?.tolerance = 0.6
    }

    func stopMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }

    func deliverBackgroundRecoveryNotification(
        identifierPrefix: String,
        title: String,
        body: String,
        logLabel: String
    ) {
        if let backgroundRecoveryReporter {
            backgroundRecoveryReporter(title, body)
            return
        }
        guard !suppressInteractiveUI else { return }

        Task { @MainActor in
            AppDelegate.deliverManagedLocalNotification(
                service: .general,
                title: title,
                body: body,
                identifier: "\(identifierPrefix).\(UUID().uuidString)",
                logLabel: "dictation \(logLabel)"
            )
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

}
