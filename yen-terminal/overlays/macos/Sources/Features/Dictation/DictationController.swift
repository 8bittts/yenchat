import Cocoa
import Speech
import AVFoundation
import ApplicationServices
import Carbon
import ServiceManagement
import UserNotifications
import YENKit

enum DictationPreviewPreferences {
    static let liveTranscriptEnabledPreferenceKey = "com.yenchat.yen.dictationLiveTranscriptPreviewEnabled"
    static let liveTranscriptPreferenceDidChangeNotification = Notification.Name(
        "com.yenchat.yen.dictationLiveTranscriptPreviewDidChange"
    )
    static let liveTranscriptEnabledUserInfoKey = "enabled"

    static var liveTranscriptEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: liveTranscriptEnabledPreferenceKey) }
        set {
            let defaults = UserDefaults.standard
            let previousValue = defaults.bool(forKey: liveTranscriptEnabledPreferenceKey)
            guard previousValue != newValue else { return }
            defaults.set(newValue, forKey: liveTranscriptEnabledPreferenceKey)
            NotificationCenter.default.post(
                name: liveTranscriptPreferenceDidChangeNotification,
                object: nil,
                userInfo: [liveTranscriptEnabledUserInfoKey: newValue]
            )
        }
    }
}

/// Orchestrates speech-to-text dictation with Option + Space hotkey.
/// Uses SpeechAnalyzer (macOS 26+) or SFSpeechRecognizer (fallback) for speech-to-text conversion.
@MainActor
final class DictationController: NSObject, NSMenuDelegate {
    static let shared = DictationController()
    private static let pausedPreferenceKey = "com.yenchat.yen.dictationPaused"
    private static var startupLocalServiceIssueOverrideForTesting: (@MainActor () -> LocalServiceIssue?)?

    /// Whether Launch at Login is enabled — used to keep app alive after last window closes.
    /// Duplicated in SettingsController.launchAtLogin (getter) for SwiftUI binding.
    static var launchAtLoginStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var launchAtLoginNeedsApproval: Bool {
        launchAtLoginStatus == .requiresApproval
    }

    static var backgroundModeActive: Bool {
        switch launchAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    struct ScheduledWork {
        let cancelImpl: @Sendable @MainActor () -> Void

        @MainActor
        func cancel() {
            cancelImpl()
        }
    }

    typealias PermissionAuthorizer = @MainActor (
        _ allowNativePrompts: Bool,
        _ completion: @MainActor @escaping (Bool) -> Void
    ) -> Void
    typealias PrivacyDestinationProvider = @MainActor () -> [PrivacyDestination]
    typealias HotkeyPressedProvider = @MainActor () -> Bool
    typealias MaxDurationScheduler = @MainActor (
        _ interval: TimeInterval,
        _ handler: @escaping @Sendable @MainActor () -> Void
    ) -> ScheduledWork
    typealias StopWatchdogScheduler = @MainActor (
        _ delay: Duration,
        _ handler: @escaping @Sendable @MainActor () -> Void
    ) -> ScheduledWork
    typealias TranscriptInserter = @MainActor (_ text: String) -> InsertionOutcome
    typealias AppIsActiveProvider = @MainActor () -> Bool
    typealias FrontmostApplicationPIDProvider = @MainActor () -> pid_t?
    typealias FrontmostApplicationFocusedElementProvider = @MainActor (_ pid: pid_t) -> AXUIElement?
    typealias FrontmostApplicationFocusFingerprintProvider = @MainActor (_ pid: pid_t) -> Int?
    typealias SecureEventInputProvider = @MainActor () -> Bool
    typealias BackgroundRecoveryReporter = @MainActor (_ title: String, _ body: String) -> Void

    private var recognizer: DictationRecognizerProtocol
    /// Backing cache for the legacy `SFSpeechRecognizer`-based recognizer. On macOS 26
    /// it stays nil until the first fallback activation, so the process pays for neither
    /// the `SFSpeechRecognizer` nor its process-lifetime locale observer unless fallback
    /// actually runs; on pre-26 it holds the same instance already assigned to `recognizer`.
    private var legacyRecognizerInstance: DictationRecognizerProtocol?
    /// Lazily materializes (and caches) the legacy recognizer on first read. The class and
    /// its only reader (`activateLegacyRecognizerFallback`) are `@MainActor`, so the cache
    /// mutation inside this getter is race-free.
    private var legacyRecognizer: DictationRecognizerProtocol {
        if let legacyRecognizerInstance { return legacyRecognizerInstance }
        let created = DictationRecognizer()
        legacyRecognizerInstance = created
        return created
    }
    private var usingLegacyRecognizerFallback: Bool
    private let translationPostProcessor: DictationTranslationPostProcessor
    private let permissions: DictationPermissionController
    private let insertionCoordinator: DictationInsertionCoordinator
    private typealias CapturedInsertionTarget = DictationInsertionCoordinator.CapturedInsertionTarget
    private let overlay = DictationOverlay()
    private let hotkeyPressedProvider: HotkeyPressedProvider
    private let maxDurationScheduler: MaxDurationScheduler
    private let stopWatchdogScheduler: StopWatchdogScheduler
    private let appIsActiveProvider: AppIsActiveProvider
    private let suppressInteractiveUI: Bool
    private var livePreviewPreferenceObserver: NSObjectProtocol?

    enum SessionState: String, Equatable {
        case idle
        case starting
        case listening
        case stopping
        case inserting
        case failed
    }

    enum StopCause: String, Equatable {
        case hotkeyRelease
        case recognizerError
        case legacyTimeout
        case paused
        case watchdog
        case forcedReset

        var allowsFallbackTranscript: Bool {
            switch self {
            case .recognizerError, .watchdog, .forcedReset:
                return true
            case .hotkeyRelease, .legacyTimeout, .paused:
                return false
            }
        }
    }

    enum TranscriptInsertionSource: String, Equatable {
        case final
        case fallback
    }

    enum InsertionOutcome: String, Equatable {
        case directSurfacePaste = "direct-surface-paste"
        case responderChainPaste = "responder-chain-paste"
        case remoteCommandVPaste = "remote-command-v-paste"
        case manualRecoveryRequired = "manual-recovery-required"
    }

    private enum StopCompletionStrategy {
        case stopRecognizer
        case completeImmediatelyWithFallback
    }

    enum InsertionTargetGate: Equatable {
        case ready
        case missingStableTarget
        case invalidatedTarget
    }

    enum CapturedInsertionTargetDescriptor: Equatable {
        case terminalSurface(windowNumber: Int, responderIdentifier: ObjectIdentifier)
        case responderChain(windowNumber: Int, responderIdentifier: ObjectIdentifier)
        case syntheticCommandV(frontmostProcessIdentifier: pid_t, focusFingerprint: Int?)
    }

    struct InsertionValidationState: Equatable {
        let isYENActive: Bool
        let windowNumber: Int?
        let firstResponderIdentifier: ObjectIdentifier?
        let frontmostProcessIdentifier: pid_t?
        let frontmostFocusFingerprint: Int?
    }

    struct TranscriptInsertionDecision: Equatable {
        let text: String
        let source: TranscriptInsertionSource
    }

    private var captureSession = DictationCaptureSessionCoordinator()
    private var isListening: Bool {
        get { captureSession.isListening }
        set { captureSession.isListening = newValue }
    }
    private var stopSession: DictationCaptureSessionCoordinator.StopSession? {
        get { captureSession.stopSession }
        set { captureSession.stopSession = newValue }
    }
    private var isStopping: Bool { captureSession.isStopping }
    private var sessionState: SessionState = .idle
    private var activeSessionID: UUID? {
        get { captureSession.activeSessionID }
        set { captureSession.activeSessionID = newValue }
    }
    private var pendingStart: Bool {
        get { captureSession.pendingStart }
        set { captureSession.pendingStart = newValue }
    }
    private var pendingStopInsertionTarget: (token: UUID, target: CapturedInsertionTarget?)?
    private var maxDurationTimer: ScheduledWork?
    private var blinkTimer: Timer?
    private var indicatorVisible = true
    private var localServiceIssue: LocalServiceIssue?
    private var cachedStartupLocalServiceIssue: LocalServiceIssue?
    private var startupIssueLastRefreshedAt: CFAbsoluteTime = 0
    private var isPaused = UserDefaults.standard.bool(forKey: DictationController.pausedPreferenceKey)
    private var pausedOverlayDismissWorkItem: DispatchWorkItem?
    private var latestPartialTranscript: String?
    private var insertionQueueTask: Task<Void, Never>?
    private var insertionQueueTaskID: UUID?
    private var insertionQueueEpoch: UInt64 = 0
    private var stopWatchdogTask: ScheduledWork?
    private let livePreviewMinimumInterval: TimeInterval
    private lazy var livePreview = DictationLivePreviewController(
        minimumInterval: livePreviewMinimumInterval,
        canRender: { [weak self] in
            guard let self else { return false }
            return Self.shouldRenderLiveTranscriptPreview(
                liveTranscriptEnabled: DictationPreviewPreferences.liveTranscriptEnabled,
                isStopping: self.isStopping
            )
        },
        render: { [weak self] text in
            self?.updateOverlay(text: text, announceTranscript: true)
        }
    )
    private var overlayVisibleForTesting = false
    private var overlayTextForTesting: String?
    private var overlayUpdateCountForTesting = 0

    enum LocalServiceIssue: Equatable {
        case recognizerUnavailable
        case legacySystemDictationDisabled
        case noAudioInput
        case foregroundInstallRequired
        case runtimeFailure

        var detailTitle: String {
            switch self {
            case .recognizerUnavailable:
                return DictationCopy.localRecognizerUnavailableDetail
            case .legacySystemDictationDisabled:
                return DictationCopy.localLegacyDictationDisabledDetail
            case .noAudioInput:
                return DictationCopy.localNoAudioInputDetail
            case .foregroundInstallRequired:
                return DictationCopy.localForegroundInstallRequiredDetail
            case .runtimeFailure:
                return DictationCopy.localRuntimeFailureDetail
            }
        }

        var openActionTitle: String {
            switch self {
            case .recognizerUnavailable, .runtimeFailure:
                return DictationCopy.openSpeechRecognitionSettingsTitle
            case .legacySystemDictationDisabled:
                return DictationCopy.openSystemDictationSettingsTitle
            case .noAudioInput:
                return DictationCopy.openSoundInputSettingsTitle
            case .foregroundInstallRequired:
                return DictationCopy.activateYENTitle
            }
        }

        var openAction: MenuState.PrimaryAction {
            switch self {
            case .recognizerUnavailable, .runtimeFailure:
                return .openSpeechRecognitionSettings
            case .legacySystemDictationDisabled:
                return .openSystemDictationSettings
            case .noAudioInput:
                return .openSoundInputSettings
            case .foregroundInstallRequired:
                return .activateYEN
            }
        }
    }

    private lazy var statusSummaryItem: NSMenuItem = {
        let item = NSMenuItem(title: DictationCopy.enabledSummary, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var statusDetailItem: NSMenuItem = {
        let item = NSMenuItem(title: DictationCopy.enabledDetail, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }()

    private lazy var hotkeyConflictHintItem: NSMenuItem = {
        let item = NSMenuItem(
            title: DictationCopy.hotkeyConflictHint,
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        return item
    }()

    private lazy var pauseResumeItem: NSMenuItem = {
        let item = NSMenuItem(title: DictationCopy.pauseActionTitle, action: #selector(toggleDictationPaused), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var openMissingPermissionsItem: NSMenuItem = {
        let item = NSMenuItem(title: DictationCopy.openAllGrantedTitle, action: #selector(openPrimaryRecoveryAction), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var recheckPermissionsItem: NSMenuItem = {
        let item = NSMenuItem(title: DictationCopy.recheckPermissionsTitle, action: #selector(recheckPermissions), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var settingsItem: NSMenuItem = {
        let item = NSMenuItem(title: "Settings...", action: #selector(showSettingsPanel), keyEquivalent: ",")
        item.target = self
        return item
    }()

    private lazy var quitItem: NSMenuItem = {
        let item = NSMenuItem(title: "Quit YEN", action: #selector(quitApp), keyEquivalent: "q")
        item.target = self
        return item
    }()

    /// Persistent menu bar status item — toggled via `isVisible` to avoid
    /// WindowServer IPC churn and orphan leaks on rapid start/stop.
    private lazy var statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = recordingImage
            button.toolTip = "YEN Dictation active"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(statusSummaryItem)
        menu.addItem(statusDetailItem)
        menu.addItem(hotkeyConflictHintItem)
        menu.addItem(pauseResumeItem)
        menu.addItem(.separator())
        menu.addItem(openMissingPermissionsItem)
        menu.addItem(recheckPermissionsItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        item.menu = menu

        item.isVisible = false
        return item
    }()

    /// Cached recording icon — avoids repeated SF Symbol lookups during blink timer.
    /// Uses record.circle instead of mic.fill to avoid duplicating the macOS system
    /// microphone privacy indicator that appears automatically when AVAudioEngine is active.
    private let recordingImage = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Dictation active")

    /// Idle menu bar extra — template SF Symbol so it follows menu-bar tint.
    /// `waveform` avoids duplicating the system microphone privacy indicator.
    private lazy var idleImage: NSImage? = Self.makeIdleStatusImage()

    static func makeIdleStatusImage() -> NSImage? {
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "YEN Dictation")
        image?.isTemplate = true
        return image
    }

    /// Maximum dictation duration — safety limit for SFSpeechRecognizer fallback (macOS < 26)
    private let maxDurationSeconds: TimeInterval = 60.0

    /// Blink interval for recording indicator
    private let blinkIntervalSeconds: TimeInterval = 0.5
    private static let startupIssueRefreshIntervalSeconds: CFAbsoluteTime = 8.0

    // Production entry point. The DI init below already encodes every live default,
    // so this only computes the recognizer + legacy cache (the legacy recognizer stays
    // lazy on macOS 26), delegates, and binds hotkeys (the DI init deliberately does NOT
    // bind, so tests stay side-effect free).
    private override convenience init() {
        let recognizer: DictationRecognizerProtocol
        let legacyRecognizerInstance: DictationRecognizerProtocol?
        let usingLegacyRecognizerFallback: Bool
        if #available(macOS 26, *) {
            recognizer = SpeechAnalyzerRecognizer()
            legacyRecognizerInstance = nil        // materialized lazily at first fallback
            usingLegacyRecognizerFallback = false
        } else {
            let legacyRecognizer = DictationRecognizer()
            recognizer = legacyRecognizer
            legacyRecognizerInstance = legacyRecognizer  // active recognizer IS the legacy one
            usingLegacyRecognizerFallback = true
        }
        self.init(
            recognizer: recognizer,
            legacyRecognizer: legacyRecognizerInstance,
            usingLegacyRecognizerFallback: usingLegacyRecognizerFallback,
            suppressInteractiveUI: false
        )
        bindHotkeyCallbacks()
    }

    init(
        recognizer: DictationRecognizerProtocol,
        legacyRecognizer: DictationRecognizerProtocol? = nil,
        usingLegacyRecognizerFallback: Bool = false,
        translationPostProcessor: DictationTranslationPostProcessor = DictationTranslationPostProcessor(),
        clipboardRestoreScheduler: DictationClipboardRestoreScheduler? = nil,
        permissionAuthorizer: PermissionAuthorizer? = nil,
        privacyDestinationProvider: PrivacyDestinationProvider? = nil,
        hotkeyPressedProvider: @escaping HotkeyPressedProvider = { DictationHotKey.shared.isPressed },
        maxDurationScheduler: @escaping MaxDurationScheduler = DictationController.liveMaxDurationScheduler,
        stopWatchdogScheduler: @escaping StopWatchdogScheduler = DictationController.liveStopWatchdogScheduler,
        transcriptInserter: TranscriptInserter? = nil,
        appIsActiveProvider: @escaping AppIsActiveProvider = { NSApp.isActive },
        frontmostApplicationPIDProvider: @escaping FrontmostApplicationPIDProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        frontmostApplicationFocusedElementProvider: @escaping FrontmostApplicationFocusedElementProvider = DictationController.liveFrontmostApplicationFocusedElement,
        frontmostApplicationFocusFingerprintProvider: @escaping FrontmostApplicationFocusFingerprintProvider = DictationController.liveFrontmostApplicationFocusFingerprint,
        secureEventInputProvider: @escaping SecureEventInputProvider = DictationController.liveSecureEventInputEnabled,
        backgroundRecoveryReporter: BackgroundRecoveryReporter? = nil,
        suppressInteractiveUI: Bool = true,
        livePreviewMinimumInterval: TimeInterval = 0.12,
        syntheticEventSource: CGEventSource? = nil
    ) {
        self.recognizer = recognizer
        self.legacyRecognizerInstance = legacyRecognizer
        self.usingLegacyRecognizerFallback = usingLegacyRecognizerFallback
        self.translationPostProcessor = translationPostProcessor
        self.permissions = DictationPermissionController(
            permissionAuthorizer: permissionAuthorizer,
            privacyDestinationProvider: privacyDestinationProvider,
            backgroundRecoveryReporter: backgroundRecoveryReporter,
            suppressInteractiveUI: suppressInteractiveUI
        )
        self.hotkeyPressedProvider = hotkeyPressedProvider
        self.maxDurationScheduler = maxDurationScheduler
        self.stopWatchdogScheduler = stopWatchdogScheduler
        self.appIsActiveProvider = appIsActiveProvider
        self.suppressInteractiveUI = suppressInteractiveUI
        self.livePreviewMinimumInterval = livePreviewMinimumInterval
        self.insertionCoordinator = DictationInsertionCoordinator(
            clipboardRestoreScheduler: clipboardRestoreScheduler ?? DictationClipboardRestoreScheduler(),
            transcriptInserter: transcriptInserter,
            appIsActiveProvider: appIsActiveProvider,
            frontmostApplicationPIDProvider: frontmostApplicationPIDProvider,
            frontmostApplicationFocusedElementProvider: frontmostApplicationFocusedElementProvider,
            frontmostApplicationFocusFingerprintProvider: frontmostApplicationFocusFingerprintProvider,
            secureEventInputProvider: secureEventInputProvider,
            syntheticEventSource: syntheticEventSource ?? CGEventSource(stateID: .privateState)
        )
        super.init()
        configureLivePreviewPreferenceObserver()
    }

    deinit {
        if let livePreviewPreferenceObserver {
            NotificationCenter.default.removeObserver(livePreviewPreferenceObserver)
        }
    }

    private static func liveMaxDurationScheduler(
        interval: TimeInterval,
        handler: @escaping @Sendable @MainActor () -> Void
    ) -> ScheduledWork {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                handler()
            }
        }
        timer.tolerance = min(1.0, interval * 0.1)
        return ScheduledWork {
            timer.invalidate()
        }
    }

    private static func liveStopWatchdogScheduler(
        delay: Duration,
        handler: @escaping @Sendable @MainActor () -> Void
    ) -> ScheduledWork {
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            handler()
        }
        return ScheduledWork {
            task.cancel()
        }
    }

    private func bindHotkeyCallbacks() {
        DictationHotKey.shared.onHotkeyDown = { [weak self] in
            self?.handleHotkeyDown()
        }
        DictationHotKey.shared.onHotkeyUp = { [weak self] in
            self?.handleHotkeyUp()
        }
    }

    /// Call once at app launch to set up the hotkey listener.
    func setup() {
        DictationHotKey.shared.start()
        refreshPermissionState(showRevocationNotice: false)
        permissions.startMonitoring { [weak self] in
            self?.refreshPermissionState(showRevocationNotice: true)
        }
        updateIdlePresence()
        SettingsController.shared.validateDictationTranslationSelectionInBackground()
    }

    @objc private func showSettingsPanel() {
        SettingsController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openPrimaryRecoveryAction() {
        let missing = missingPrivacyDestinations()
        let state = Self.menuState(
            missing: missing,
            localServiceIssue: currentLocalServiceIssue,
            isPaused: isPaused,
            launchNeedsApproval: Self.launchAtLoginNeedsApproval
        )
        switch state.openPrimaryAction {
        case .none:
            return
        case .openMissingPermission:
            if let first = missing.first {
                openSettings(for: first)
            } else {
                SystemSettingsOpener.open(candidates: [
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                    "x-apple.systempreferences:com.apple.preference.security"
                ])
            }
        case .openSpeechRecognitionSettings:
            openSettings(for: .speechRecognition)
        case .openSystemDictationSettings:
            openSystemDictationSettings()
        case .openSoundInputSettings:
            openSoundInputSettings()
        case .activateYEN:
            NSApp.yenActivateCompat()
        }
    }

    @objc private func recheckPermissions() {
        refreshStartupLocalServiceIssueIfNeeded(force: true)
        if localServiceIssue != nil {
            localServiceIssue = cachedStartupLocalServiceIssue
        }
        refreshPermissionState(showRevocationNotice: false)
    }

    private func refreshDeferredStartupReadinessFallbackBeforeStartIfNeeded() {
        guard !Self.hasActiveCaptureSession(
            pendingStart: pendingStart,
            isListening: isListening,
            isStopping: isStopping
        ) else {
            return
        }
        guard currentLocalServiceIssue == .recognizerUnavailable else { return }
        guard #available(macOS 26, *) else { return }
        guard !usingLegacyRecognizerFallback else { return }
        guard !recognizer.requiresSessionTimeout else { return }

        refreshStartupLocalServiceIssueIfNeeded(force: true)
        if localServiceIssue != nil {
            localServiceIssue = cachedStartupLocalServiceIssue
        }
    }

    @objc private func toggleDictationPaused() {
        setPaused(!isPaused)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshPermissionState(showRevocationNotice: false)
    }

    /// Update menu bar presence based on Launch at Login/background mode state.
    func updateIdlePresence() {
        guard !isListening else { return }
        let missing = missingPrivacyDestinations()
        if DictationController.backgroundModeActive {
            statusItem.button?.image = idleImage
            let state = Self.menuState(
                missing: missing,
                localServiceIssue: currentLocalServiceIssue,
                isPaused: isPaused,
                launchNeedsApproval: Self.launchAtLoginNeedsApproval
            )
            statusItem.button?.toolTip = state.toolTip
            statusItem.button?.alphaValue = 1.0
            statusItem.isVisible = true
        } else {
            statusItem.isVisible = false
        }
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        UserDefaults.standard.set(paused, forKey: Self.pausedPreferenceKey)

        if paused {
            clearQueuedRestartAfterStop()
            if isListening {
                stopAndInsert(trigger: .paused)
            }
        }

        refreshPermissionState(showRevocationNotice: false)
    }

    private func showPausedAttemptOverlay() {
        pausedOverlayDismissWorkItem?.cancel()
        showOverlay()
        updateOverlay(text: DictationCopy.pausedAttemptOverlayLine)

        let dismissWork = DispatchWorkItem { [weak self] in
            guard let self, !self.isListening else { return }
            self.hideOverlay()
        }
        pausedOverlayDismissWorkItem = dismissWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: dismissWork)
    }

    private func clearQueuedRestartAfterStop() {
        captureSession.clearRestartAfterStop()
    }

    func handleHotkeyDown() {
        startListening()
    }

    func handleHotkeyUp() {
        stopAndInsert(trigger: .hotkeyRelease)
    }

    var testingSessionState: SessionState {
        sessionState
    }

    var testingActiveSessionID: UUID? {
        activeSessionID
    }

    var testingPendingStart: Bool {
        pendingStart
    }

    var testingIsStopping: Bool {
        isStopping
    }

    var testingPendingInsertionTargetDescriptor: CapturedInsertionTargetDescriptor? {
        pendingStopInsertionTarget?.target?.descriptor
    }

    var testingPendingInsertionTargetHasFocusedElement: Bool {
        pendingStopInsertionTarget?.target?.focusedElement != nil
    }

    var testingOverlayVisible: Bool {
        overlayVisibleForTesting
    }

    /// True once the legacy recognizer has actually been materialized. Guards the
    /// macOS 26 optimization that keeps it nil until the first fallback activation.
    var testingLegacyRecognizerMaterialized: Bool {
        legacyRecognizerInstance != nil
    }

    var testingOverlayText: String? {
        overlayTextForTesting
    }

    var testingOverlayAudioLevel: Float {
        overlay.testingAudioLevel
    }

    var testingOverlayUpdateCount: Int {
        overlayUpdateCountForTesting
    }

    func testingValidatePendingInsertionTarget() -> Bool? {
        guard let target = pendingStopInsertionTarget?.target else { return nil }
        return insertionCoordinator.isCapturedInsertionTargetValid(target)
    }

    func waitForInsertionQueueDrainForTesting() async {
        _ = await insertionQueueTask?.result
    }

    func refreshPermissionStateForTesting(showRevocationNotice: Bool = false) {
        refreshPermissionState(showRevocationNotice: showRevocationNotice)
    }

    func setPausedForTesting(_ paused: Bool) {
        setPaused(paused)
    }

    func triggerStopForTesting(_ trigger: StopCause) {
        stopAndInsert(trigger: trigger)
    }

    /// Start listening for speech input.
    private func startListening() {
        refreshDeferredStartupReadinessFallbackBeforeStartIfNeeded()
        switch captureSession.beginStartRequest() {
        case .queueRestartAfterStop:
            // If user re-presses during finalization, start immediately after stop completes.
            return
        case .ignore:
            return
        case .beginPermissionCheck(let sessionID):
            transitionSessionState(
                to: .starting,
                reason: "hotkey-down",
                sessionID: sessionID
            )
            logSessionEvent(
                "start_requested",
                sessionID: sessionID
            )

            let handleAuthorization: @MainActor (Bool) -> Void = { [weak self] authorized in
                self?.handleStartAuthorization(authorized, sessionID: sessionID)
            }

            authorizeForDictation(
                allowNativePrompts: appIsActiveProvider(),
                completion: handleAuthorization
            )
            return
        }
    }

    private func handleStartAuthorization(_ authorized: Bool, sessionID: UUID) {
        guard self.pendingStart else {
            // Key was released during permission check — cancel
            if Self.shouldAcceptSessionCallback(
                activeSessionID: self.activeSessionID,
                callbackSessionID: sessionID
            ) {
                self.logSessionEvent(
                    "start_cancelled_before_permission_resolution",
                    sessionID: sessionID
                )
                self.abortPendingStart(sessionID: sessionID, reason: "permission-check-cancelled")
            }
            return
        }
        guard Self.shouldAcceptSessionCallback(
            activeSessionID: self.activeSessionID,
            callbackSessionID: sessionID
        ) else { return }

        guard authorized else {
            self.captureSession.finishPendingStartPermissionCheck()
            self.logSessionEvent(
                "start_blocked_permissions",
                sessionID: sessionID
            )
            self.abortPendingStart(sessionID: sessionID, reason: "permissions-denied")
            self.showPermissionAlert()
            return
        }

        // Re-verify permissions haven't been revoked during async gap
        let currentMissing = self.missingPrivacyDestinations()
        guard currentMissing.isEmpty else {
            self.captureSession.finishPendingStartPermissionCheck()
            self.refreshPermissionState(showRevocationNotice: false)
            self.logSessionEvent(
                "start_blocked_permission_recheck",
                sessionID: sessionID
            )
            self.abortPendingStart(sessionID: sessionID, reason: "permissions-revoked-before-start")
            return
        }

        switch Self.hotkeyEligibility(
            isPaused: self.isPaused,
            localServiceIssue: self.currentLocalServiceIssue
        ) {
        case .paused:
            self.captureSession.finishPendingStartPermissionCheck()
            self.showPausedAttemptOverlay()
            self.refreshPermissionState(showRevocationNotice: false)
            self.abortPendingStart(sessionID: sessionID, reason: "paused")
            return
        case .blocked(let issue):
            self.captureSession.finishPendingStartPermissionCheck()
            self.localServiceIssue = issue
            self.refreshPermissionState(showRevocationNotice: false)
            if !self.appIsActiveProvider() {
                self.postLocalServiceNeededNotification(issue: issue)
            }
            self.abortPendingStart(sessionID: sessionID, reason: "local-service-blocked")
            return
        case .allowed:
            break
        }

        startAuthorizedCapture(sessionID: sessionID)
    }

    /// Finish an already-settled permission check after its recovery side effects.
    private func abortPendingStart(sessionID: UUID, reason: String) {
        transitionSessionState(to: .idle, reason: reason, sessionID: sessionID)
        _ = captureSession.clearActiveSessionIfMatching(sessionID)
    }

    private func startAuthorizedCapture(sessionID: UUID) {
        self.localServiceIssue = nil
        self.latestPartialTranscript = nil
        self.livePreview.reset()
        self.recognizer.startListening(
            onReady: { [weak self] in
                guard let self else { return }
                guard Self.shouldAcceptSessionCallback(
                    activeSessionID: self.activeSessionID,
                    callbackSessionID: sessionID
                ) else { return }
                self.captureSession.beginListening(sessionID: sessionID)
                self.transitionSessionState(
                    to: .listening,
                    reason: "recognizer-ready",
                    sessionID: sessionID
                )
                self.logSessionEvent(
                    "listening_started",
                    sessionID: sessionID
                )
                self.setRecordingIndicator(true)
                self.startSessionTimeoutIfNeeded()
                self.showOverlay()
                self.updateOverlay(text: DictationCopy.overlayListeningLine)
            },
            onAudioLevel: { [weak self] level in
                guard let self else { return }
                guard Self.shouldAcceptSessionCallback(
                    activeSessionID: self.activeSessionID,
                    callbackSessionID: sessionID
                ), self.isListening, !self.isStopping else { return }
                self.overlay.updateAudioLevel(level)
            },
            onPartialResult: { [weak self] partialText in
                guard let self else { return }
                guard Self.shouldAcceptSessionCallback(
                    activeSessionID: self.activeSessionID,
                    callbackSessionID: sessionID
                ) else { return }
                guard self.latestPartialTranscript != partialText else { return }
                guard let normalizedPreview = Self.normalizedLivePreviewText(partialText) else { return }
                self.latestPartialTranscript = partialText
                self.livePreview.queue(normalizedText: normalizedPreview)
            },
            onError: { [weak self] error in
                guard let self else { return }
                guard Self.shouldAcceptSessionCallback(
                    activeSessionID: self.activeSessionID,
                    callbackSessionID: sessionID
                ) else { return }
                let activatedLegacyFallback = self.tryActivateLegacyRecognizerFallback(
                    after: error
                )
                let notificationIssue: LocalServiceIssue?
                if activatedLegacyFallback {
                    self.localServiceIssue = self.startupLocalServiceIssue()
                    notificationIssue = self.localServiceIssue
                } else {
                    let mappedIssue = self.mapRecognizerErrorToLocalServiceIssue(error)
                    let startupIssue = self.startupLocalServiceIssue()
                    self.localServiceIssue = mappedIssue ?? startupIssue
                    notificationIssue = mappedIssue ?? startupIssue
                }
                self.refreshPermissionState(showRevocationNotice: false)
                if let issue = notificationIssue ?? self.currentLocalServiceIssue,
                   !self.appIsActiveProvider() {
                    self.postLocalServiceNeededNotification(issue: issue)
                }
                self.logSessionEvent(
                    "recognizer_error",
                    sessionID: sessionID,
                    stopCause: .recognizerError
                )
                self.stopAndInsert(
                    trigger: .recognizerError,
                    completionStrategy: activatedLegacyFallback
                        ? .completeImmediatelyWithFallback
                        : .stopRecognizer
                )
            }
        )
    }

    /// Stop listening and insert transcribed text at cursor.
    private func stopAndInsert(
        trigger: StopCause,
        completionStrategy: StopCompletionStrategy = .stopRecognizer
    ) {
        // Cancel pending start if permission check is still in flight
        if let sessionID = captureSession.cancelPendingStartOnStopRequest() {
            recognizer.cancel()
            latestPartialTranscript = nil
            livePreview.reset()
            setRecordingIndicator(false)
            hideOverlay()
            logSessionEvent(
                "start_cancelled_on_stop_request",
                sessionID: sessionID,
                stopCause: trigger
            )
            transitionSessionState(
                to: .idle,
                reason: "start-cancelled-on-stop",
                sessionID: sessionID
            )
            return
        }
        guard let stopRequest = captureSession.beginStop(
            trigger: trigger,
            now: CFAbsoluteTimeGetCurrent()
        ) else { return }
        pendingStopInsertionTarget = (
            token: stopRequest.token,
            target: insertionCoordinator.captureInsertionTarget()
        )
        cancelMaxDurationTimer()
        transitionSessionState(
            to: .stopping,
            reason: "stop-requested-\(trigger.rawValue)",
            sessionID: stopRequest.sessionID
        )
        livePreview.cancelPendingFrame()
        overlay.updateAudioLevel(0)
        updateOverlay(text: DictationCopy.overlayProcessingLine)
        logSessionEvent(
            "stop_requested",
            sessionID: stopRequest.sessionID,
            stopCause: trigger
        )

        switch completionStrategy {
        case .stopRecognizer:
            scheduleStopWatchdog(for: stopRequest.token)
            recognizer.stopListening { [weak self] stopResult in
                guard let self else { return }
                self.completeStopSession(
                    token: stopRequest.token,
                    stopResult: stopResult,
                    fallbackTranscript: self.latestPartialTranscript
                )
            }
        case .completeImmediatelyWithFallback:
            completeStopSession(
                token: stopRequest.token,
                stopResult: .empty,
                fallbackTranscript: latestPartialTranscript
            )
        }
    }

    private func completeStopSession(
        token: UUID,
        stopResult: DictationRecognizerStopResult,
        fallbackTranscript: String?
    ) {
        guard let outcome = captureSession.completeStop(
            token: token,
            stopResult: stopResult,
            fallbackTranscript: fallbackTranscript,
            hotkeyStillPressed: hotkeyPressedProvider()
        ) else {
            logSessionEvent(
                "stop_completion_ignored",
                sessionID: activeSessionID,
                stopCause: stopSession?.stopCause
            )
            return
        }
        let insertionTarget = takePendingStopInsertionTarget(for: token)
        cancelStopWatchdog(for: token)
        cancelMaxDurationTimer()
        livePreview.reset()
        setRecordingIndicator(false)
        let fallbackUsed = outcome.insertionDecision?.source == .fallback
        logSessionEvent(
            Self.stopCompletionEventName(
                hasInsertionDecision: outcome.insertionDecision != nil
            ),
            sessionID: outcome.sessionID,
            stopCause: outcome.stopCause,
            fallbackUsed: fallbackUsed,
            transcriptSource: outcome.insertionDecision?.source
        )

        if let decision = outcome.insertionDecision {
            transitionSessionState(
                to: .inserting,
                reason: "transcript-ready-\(decision.source.rawValue)",
                sessionID: outcome.sessionID
            )
            enqueueProcessedTranscriptInsertion(
                decision.text,
                insertionTarget: insertionTarget,
                sessionID: outcome.sessionID,
                stopCause: outcome.stopCause,
                stopRequestedAt: outcome.stopRequestedAt,
                fallbackUsed: fallbackUsed
            )
        } else {
            if outcome.shouldTransitionToFailed {
                transitionSessionState(
                    to: .failed,
                    reason: "stop-complete-no-transcript",
                    sessionID: outcome.sessionID
                )
            }
            logSessionEvent(
                "stop_completion_without_insert_finalized",
                sessionID: outcome.sessionID,
                stopCause: outcome.stopCause,
                fallbackUsed: false,
                keyUpToInsertLatencyMs: Self.keyUpToInsertLatencyMilliseconds(
                    stopCause: outcome.stopCause,
                    stopRequestedAt: outcome.stopRequestedAt,
                    insertedAt: CFAbsoluteTimeGetCurrent()
                )
            )
            hideOverlay()
            transitionSessionState(
                to: .idle,
                reason: "stop-complete",
                sessionID: outcome.sessionID
            )
        }
        latestPartialTranscript = nil

        guard outcome.shouldRestart else { return }
        hideOverlay()
        startListening()
    }

    private func enqueueProcessedTranscriptInsertion(
        _ text: String,
        insertionTarget: CapturedInsertionTarget?,
        sessionID: UUID,
        stopCause: StopCause,
        stopRequestedAt: CFAbsoluteTime,
        fallbackUsed: Bool
    ) {
        let postProcessor = translationPostProcessor
        let sourceLocaleIdentifier = Self.translationSourceLocaleIdentifier(
            recognizerLocaleIdentifier: recognizer.activeLocaleIdentifier,
            fallbackLocaleIdentifier: Locale.current.identifier
        )
        let processingPlan = postProcessor.processingPlan(
            finalText: text,
            sourceLocaleIdentifier: sourceLocaleIdentifier
        )
        let priorTask = insertionQueueTask
        let queueEpoch = insertionQueueEpoch
        if priorTask == nil, let immediateResult = processingPlan.immediateResult {
            finishTranscriptInsertion(
                immediateResult,
                insertionTarget: insertionTarget,
                sessionID: sessionID,
                stopCause: stopCause,
                stopRequestedAt: stopRequestedAt,
                fallbackUsed: fallbackUsed,
                queueEpoch: queueEpoch
            )
            return
        }
        let taskID = UUID()
        insertionQueueTaskID = taskID
        insertionQueueTask = Task(priority: .userInitiated) { [weak self] in
            defer { self?.completeQueuedInsertion(taskID: taskID) }
            _ = await priorTask?.result
            guard !Task.isCancelled else { return }
            let processed: DictationTranslationResult
            if let immediateResult = processingPlan.immediateResult {
                processed = immediateResult
            } else {
                processed = await postProcessor.process(plan: processingPlan)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.finishTranscriptInsertion(
                    processed,
                    insertionTarget: insertionTarget,
                    sessionID: sessionID,
                    stopCause: stopCause,
                    stopRequestedAt: stopRequestedAt,
                    fallbackUsed: fallbackUsed,
                    queueEpoch: queueEpoch
                )
            }
        }
    }

    private func finishTranscriptInsertion(
        _ processed: DictationTranslationResult,
        insertionTarget: CapturedInsertionTarget?,
        sessionID: UUID,
        stopCause: StopCause,
        stopRequestedAt: CFAbsoluteTime,
        fallbackUsed: Bool,
        queueEpoch: UInt64
    ) {
        guard insertionQueueEpoch == queueEpoch else {
            if activeSessionID == sessionID && sessionState == .inserting {
                hideOverlay()
                activeSessionID = nil
                transitionSessionState(
                    to: .idle,
                    reason: "insertion-cancelled",
                    sessionID: sessionID
                )
            }
            return
        }
        let insertionOutcome = insertionCoordinator.performTranscriptInsertion(
            processed.text,
            insertionTarget: insertionTarget
        ) { failure in
            switch failure {
            case .secureInput:
                postSecureInputFailureNotification()
            case .manualPaste:
                postPasteFailureNotification()
            }
        }
        logTranslationResult(
            processed,
            sessionID: sessionID,
            stopCause: stopCause
        )
        logSessionEvent(
            Self.insertSessionEventName(for: insertionOutcome),
            sessionID: sessionID,
            stopCause: stopCause,
            fallbackUsed: fallbackUsed,
            keyUpToInsertLatencyMs: Self.keyUpToInsertLatencyMilliseconds(
                stopCause: stopCause,
                stopRequestedAt: stopRequestedAt,
                insertedAt: CFAbsoluteTimeGetCurrent()
            ),
            insertionOutcome: insertionOutcome
        )

        if activeSessionID == sessionID {
            hideOverlay()
            activeSessionID = nil
            if sessionState == .inserting {
                transitionSessionState(
                    to: .idle,
                    reason: "insertion-complete",
                    sessionID: sessionID
                )
            }
        }

        logTranslationFallbackIfNeeded(processed.fallbackReason)
    }

    private func logTranslationResult(
        _ processed: DictationTranslationResult,
        sessionID: UUID,
        stopCause: StopCause
    ) {
        let event: String?
        if processed.translated {
            event = "translation_applied"
        } else {
            switch processed.fallbackReason {
            case .sameLanguage:
                event = "translation_skipped_same_language"
            case .assetsNotReady:
                event = "translation_assets_not_ready"
            case .unsupportedPair:
                event = "translation_pair_unsupported"
            case .failed:
                event = "translation_failed"
            case .timedOut:
                event = "translation_timed_out"
            case .disabled, .unsupportedOS, nil:
                event = nil
            }
        }

        guard let event else { return }
        logSessionEvent(
            event,
            sessionID: sessionID,
            stopCause: stopCause
        )
    }

    private func logTranslationFallbackIfNeeded(
        _ fallbackReason: DictationTranslationResult.FallbackReason?
    ) {
        switch fallbackReason {
        case .failed:
            print("DictationController: translation failed — pasted original transcript")
        case .timedOut:
            print("DictationController: translation timed out — pasted original transcript")
        case .assetsNotReady:
            print("DictationController: translation assets not ready — pasted original transcript")
        case .unsupportedPair:
            print("DictationController: translation pair unsupported — pasted original transcript")
        default:
            break
        }
    }

    /// Start timeout only for recognizers with fixed session limits (legacy fallback).
    private func startSessionTimeoutIfNeeded() {
        cancelMaxDurationTimer()
        guard recognizer.requiresSessionTimeout else { return }
        maxDurationTimer = maxDurationScheduler(maxDurationSeconds) { [weak self] in
            self?.stopAndInsert(trigger: .legacyTimeout)
        }
    }

    /// Cancel the max duration timer.
    private func cancelMaxDurationTimer() {
        maxDurationTimer?.cancel()
        maxDurationTimer = nil
    }

    private func completeQueuedInsertion(taskID: UUID) {
        guard insertionQueueTaskID == taskID else { return }
        insertionQueueTask = nil
        insertionQueueTaskID = nil
    }

    private func resetQueuedInsertions() {
        insertionQueueEpoch &+= 1
        insertionQueueTask?.cancel()
        insertionQueueTask = nil
        insertionQueueTaskID = nil
    }

    private func scheduleStopWatchdog(for token: UUID) {
        cancelStopWatchdog()
        stopWatchdogTask = stopWatchdogScheduler(.seconds(8)) { [weak self] in
            guard let self else { return }
            if Self.shouldForceStopWatchdog(
                isStopping: self.isStopping,
                stopTokenMatches: self.stopSession?.token == token
            ) {
                print("DictationController: stop watchdog triggered; forcing recognizer reset")
                self.forceStopFromWatchdog(token: token)
            }
        }
    }

    private func cancelStopWatchdog(for token: UUID? = nil) {
        if let token, stopSession?.token != token {
            return
        }
        stopWatchdogTask?.cancel()
        stopWatchdogTask = nil
    }

    private func forceStopFromWatchdog(token: UUID) {
        guard captureSession.markWatchdogTriggered(token: token) else { return }
        let fallbackTranscript = latestPartialTranscript
        livePreview.cancelPendingFrame()
        recognizer.cancel()
        completeStopSession(
            token: token,
            stopResult: .empty,
            fallbackTranscript: fallbackTranscript
        )
    }

    private func forceStopAndResetSession(reason: String) {
        print("DictationController: forcing stop reset (\(reason))")
        let resetSessionID = activeSessionID
        logSessionEvent(
            "force_stop_reset",
            sessionID: resetSessionID,
            stopCause: .forcedReset
        )
        transitionSessionState(
            to: .failed,
            reason: "force-reset-\(reason)",
            sessionID: resetSessionID
        )
        recognizer.cancel()
        cancelStopWatchdog()
        cancelMaxDurationTimer()
        livePreview.reset()
        resetQueuedInsertions()
        pendingStopInsertionTarget = nil
        captureSession.forceReset()
        latestPartialTranscript = nil
        hideOverlay()
        setRecordingIndicator(false)
        transitionSessionState(
            to: .idle,
            reason: "force-reset-complete",
            sessionID: resetSessionID
        )
    }

    private func forceStopForPermissionRevocation() {
        forceStopAndResetSession(reason: "permission-revoked")
    }

    private func transitionSessionState(
        to newState: SessionState,
        reason: String,
        sessionID: UUID? = nil
    ) {
        let previousState = sessionState
        if !Self.isValidSessionStateTransition(from: previousState, to: newState) {
            print(
                "DictationController: invalid_session_state_transition from=\(previousState.rawValue) to=\(newState.rawValue) reason=\(reason)"
            )
        }
        guard previousState != newState else { return }

        sessionState = newState
        print(
            "DictationController: session_state_transition session=\(sessionID?.uuidString ?? "none") from=\(previousState.rawValue) to=\(newState.rawValue) reason=\(reason) recognizer=\(activeRecognizerLabel)"
        )
    }

    private func logSessionEvent(
        _ event: String,
        sessionID: UUID? = nil,
        stopCause: StopCause? = nil,
        fallbackUsed: Bool? = nil,
        keyUpToInsertLatencyMs: Double? = nil,
        insertionOutcome: InsertionOutcome? = nil,
        transcriptSource: TranscriptInsertionSource? = nil
    ) {
        var fields: [String] = [
            "event=\(event)",
            "session=\(sessionID?.uuidString ?? "none")",
            "state=\(sessionState.rawValue)",
            "recognizer=\(activeRecognizerLabel)"
        ]

        if let stopCause {
            fields.append("stop_cause=\(stopCause.rawValue)")
        }
        if let fallbackUsed {
            fields.append("fallback_used=\(fallbackUsed)")
        }
        if let keyUpToInsertLatencyMs {
            fields.append("key_up_to_insert_ms=\(String(format: "%.0f", keyUpToInsertLatencyMs))")
        }
        if let insertionOutcome {
            fields.append("insertion_outcome=\(insertionOutcome.rawValue)")
        }
        if let transcriptSource {
            fields.append("transcript_source=\(transcriptSource.rawValue)")
        }

        print("DictationController: \(fields.joined(separator: " "))")
    }

    /// Why the most recent session fell back off the selected microphone, or `nil`
    /// when it used what was asked for. Settings reads this; leaving it unread is
    /// what made the original downgrade silent.
    var lastInputDeviceFallbackReason: String? {
        recognizer.inputDeviceBinding.fallbackReason
    }

    private var activeRecognizerLabel: String {
        recognizer.requiresSessionTimeout ? "SFSpeechRecognizer" : "SpeechAnalyzer"
    }

    private func tryActivateLegacyRecognizerFallback(
        after error: DictationRecognizer.RecognizerError
    ) -> Bool {
        guard #available(macOS 26, *) else { return false }
        guard Self.shouldActivateLegacyRecognizerFallback(
            usingLegacyRecognizerFallback: usingLegacyRecognizerFallback,
            isSpeechAnalyzerActive: !recognizer.requiresSessionTimeout,
            error: error
        ) else { return false }
        activateLegacyRecognizerFallback(reason: "runtime-\(error)")
        return true
    }

    private func activateLegacyRecognizerFallback(reason: String) {
        guard !usingLegacyRecognizerFallback else { return }
        print("DictationController: switching to legacy recognizer fallback (\(reason))")
        recognizer.cancel()
        recognizer = legacyRecognizer
        usingLegacyRecognizerFallback = true
    }

    private func showOverlay() {
        overlayVisibleForTesting = true
        guard !suppressInteractiveUI else { return }
        overlay.show()
    }

    private func updateOverlay(text: String, announceTranscript: Bool = false) {
        overlayVisibleForTesting = true
        overlayTextForTesting = text
        overlayUpdateCountForTesting += 1
        guard !suppressInteractiveUI else { return }
        overlay.update(text: text, announceTranscript: announceTranscript)
    }

    private func hideOverlay() {
        overlayVisibleForTesting = false
        overlayTextForTesting = nil
        guard !suppressInteractiveUI else { return }
        overlay.hide()
    }

    private func configureLivePreviewPreferenceObserver() {
        livePreviewPreferenceObserver = NotificationCenter.default.addObserver(
            forName: DictationPreviewPreferences.liveTranscriptPreferenceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled =
                notification.userInfo?[DictationPreviewPreferences.liveTranscriptEnabledUserInfoKey] as? Bool
                ?? DictationPreviewPreferences.liveTranscriptEnabled
            MainActor.assumeIsolated {
                self?.handleLiveTranscriptPreviewPreferenceChange(enabled: enabled)
            }
        }
    }

    private func handleLiveTranscriptPreviewPreferenceChange(enabled: Bool) {
        guard isListening, !isStopping else { return }

        if enabled {
            guard let latestPartial = Self.normalizedLivePreviewText(latestPartialTranscript) else {
                updateOverlay(text: DictationCopy.overlayListeningLine)
                return
            }
            livePreview.renderNow(normalizedText: latestPartial)
            return
        }

        livePreview.reset()
        updateOverlay(text: DictationCopy.overlayListeningLine)
    }

    private func postPasteFailureNotification() {
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "yen.dictation.paste-failure",
            title: "YEN Dictation Needs Manual Paste",
            body: "YEN couldn't safely paste automatically. Transcript was copied to your clipboard. Press Cmd+V in the target field.",
            logLabel: "Paste failure notification"
        )
    }

    private func postSecureInputFailureNotification() {
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "yen.dictation.secure-input",
            title: "YEN Dictation Blocked by Secure Input",
            body: "macOS Secure Input is active, so YEN did not write the transcript to the clipboard or paste automatically. Leave the secure field and try again.",
            logLabel: "Secure input notification"
        )
    }

    private func authorizeForDictation(
        allowNativePrompts: Bool,
        completion: @MainActor @escaping (Bool) -> Void
    ) {
        permissions.authorizeForDictation(
            allowNativePrompts: allowNativePrompts,
            refreshState: { self.refreshPermissionState(showRevocationNotice: false) },
            completion: completion
        )
    }

    struct MenuState: Equatable {
        enum PrimaryAction: Equatable {
            case none
            case openMissingPermission
            case openSpeechRecognitionSettings
            case openSystemDictationSettings
            case openSoundInputSettings
            case activateYEN
        }

        let summaryTitle: String
        let detailTitle: String
        let openPrimaryTitle: String
        let openPrimaryEnabled: Bool
        let openPrimaryAction: PrimaryAction
        let recheckTitle: String
        let recheckEnabled: Bool
        let pauseTitle: String
        let pauseEnabled: Bool
        let toolTip: String
    }

    enum HotkeyEligibility: Equatable {
        case allowed
        case paused
        case blocked(LocalServiceIssue)
    }

    enum HotkeyDownAction: Equatable {
        case queueRestartAfterStop
        case beginPermissionCheck
        case ignore
    }

    enum PasteInsertionStrategy: Equatable {
        case responderChain
        case syntheticCommandV
    }

    struct ClipboardRestorePlan: Equatable {
        let initialDelay: TimeInterval?
        let deferredDelay: TimeInterval?
    }

    nonisolated static func hasActiveCaptureSession(
        pendingStart: Bool,
        isListening: Bool,
        isStopping: Bool
    ) -> Bool {
        pendingStart || isListening || isStopping
    }

    nonisolated static func shouldShowRevocationNotice(
        previous: [PrivacyDestination]?,
        current: [PrivacyDestination],
        hasActiveCaptureSession: Bool
    ) -> Bool {
        guard hasActiveCaptureSession else { return false }
        guard let previous else { return false }
        return previous.isEmpty && !current.isEmpty
    }

    nonisolated static func shouldHardTeardownForPermissionRevocation(
        previous: [PrivacyDestination]?,
        current: [PrivacyDestination],
        hasActiveCaptureSession: Bool
    ) -> Bool {
        shouldShowRevocationNotice(
            previous: previous,
            current: current,
            hasActiveCaptureSession: hasActiveCaptureSession
        )
    }

    static func shouldForceStopWatchdog(
        isStopping: Bool,
        stopTokenMatches: Bool
    ) -> Bool {
        isStopping && stopTokenMatches
    }

    static func shouldActivateLegacyRecognizerFallback(
        usingLegacyRecognizerFallback: Bool,
        isSpeechAnalyzerActive: Bool,
        error: DictationRecognizer.RecognizerError
    ) -> Bool {
        guard !usingLegacyRecognizerFallback else { return false }
        guard isSpeechAnalyzerActive else { return false }
        return error == .recognizerIsUnavailable
    }

    static func shouldAcceptSessionCallback(
        activeSessionID: UUID?,
        callbackSessionID: UUID
    ) -> Bool {
        activeSessionID == callbackSessionID
    }

    static func shouldAcceptStopCompletion(
        activeStopToken: UUID?,
        completionToken: UUID
    ) -> Bool {
        activeStopToken == completionToken
    }

    static func shouldRenderLiveTranscriptPreview(
        liveTranscriptEnabled: Bool,
        isStopping: Bool
    ) -> Bool {
        liveTranscriptEnabled && !isStopping
    }

    static func normalizedLivePreviewText(_ text: String?) -> String? {
        text?.dictationNormalized()
    }

    static func isValidSessionStateTransition(
        from: SessionState,
        to: SessionState
    ) -> Bool {
        if from == to {
            return true
        }

        switch from {
        case .idle:
            return to == .starting || to == .failed
        case .starting:
            return to == .listening || to == .idle || to == .failed
        case .listening:
            return to == .stopping || to == .failed
        case .stopping:
            return to == .inserting || to == .idle || to == .failed
        case .inserting:
            return to == .idle || to == .starting || to == .failed
        case .failed:
            return to == .idle || to == .starting
        }
    }

    nonisolated static func shouldAllowFallbackTranscript(
        for stopCause: StopCause
    ) -> Bool {
        stopCause.allowsFallbackTranscript
    }

    static func hotkeyEligibility(
        isPaused: Bool,
        localServiceIssue: LocalServiceIssue?
    ) -> HotkeyEligibility {
        if let localServiceIssue {
            return .blocked(localServiceIssue)
        }
        if isPaused {
            return .paused
        }
        return .allowed
    }

    nonisolated static func hotkeyDownAction(
        isStopping: Bool,
        isListening: Bool,
        pendingStart: Bool
    ) -> HotkeyDownAction {
        if isStopping {
            return .queueRestartAfterStop
        }
        if isListening || pendingStart {
            return .ignore
        }
        return .beginPermissionCheck
    }

    nonisolated static func shouldRestartAfterStop(
        queuedRestart: Bool,
        hotkeyStillPressed: Bool
    ) -> Bool {
        queuedRestart && hotkeyStillPressed
    }

    nonisolated static func finalResultForInsertion(_ finalResult: String?) -> String? {
        guard let finalResult else { return nil }
        let trimmed = finalResult.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : finalResult
    }

    nonisolated static func transcriptForInsertion(
        stopResult: DictationRecognizerStopResult,
        fallbackTranscript: String?,
        stopCause: StopCause
    ) -> TranscriptInsertionDecision? {
        if let final = finalResultForInsertion(stopResult.finalText) {
            return TranscriptInsertionDecision(
                text: final,
                source: .final
            )
        }
        let allowFallback = shouldAllowFallbackTranscript(for: stopCause) || stopResult.stopMarkedAsFailure
        guard allowFallback else {
            return nil
        }
        let recognizerFallback = finalResultForInsertion(stopResult.fallbackText)
        let controllerFallback = finalResultForInsertion(fallbackTranscript)
        guard let fallback = recognizerFallback ?? controllerFallback else {
            return nil
        }
        return TranscriptInsertionDecision(
            text: fallback,
            source: .fallback
        )
    }

    static func keyUpToInsertLatencyMilliseconds(
        stopCause: StopCause,
        stopRequestedAt: CFAbsoluteTime,
        insertedAt: CFAbsoluteTime
    ) -> Double? {
        guard stopCause == .hotkeyRelease else { return nil }
        return max(0, (insertedAt - stopRequestedAt) * 1000)
    }

    static func isCapturedInsertionTargetValid(
        _ descriptor: CapturedInsertionTargetDescriptor,
        currentState: InsertionValidationState
    ) -> Bool {
        switch descriptor {
        case .terminalSurface(let windowNumber, let responderIdentifier),
             .responderChain(let windowNumber, let responderIdentifier):
            guard currentState.isYENActive else { return false }
            guard currentState.windowNumber == windowNumber else { return false }
            return currentState.firstResponderIdentifier == responderIdentifier
        case .syntheticCommandV(let frontmostProcessIdentifier, let focusFingerprint):
            guard !currentState.isYENActive else { return false }
            guard currentState.frontmostProcessIdentifier == frontmostProcessIdentifier else { return false }
            guard let focusFingerprint else { return true }
            return currentState.frontmostFocusFingerprint == focusFingerprint
        }
    }

    static func translationSourceLocaleIdentifier(
        recognizerLocaleIdentifier: String?,
        fallbackLocaleIdentifier: String
    ) -> String {
        guard let recognizerLocaleIdentifier else { return fallbackLocaleIdentifier }
        let trimmed = recognizerLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackLocaleIdentifier : trimmed
    }

    func currentTranslationSourceLocaleIdentifier() -> String {
        Self.translationSourceLocaleIdentifier(
            recognizerLocaleIdentifier: recognizer.activeLocaleIdentifier,
            fallbackLocaleIdentifier: Locale.current.identifier
        )
    }

    static func clipboardRestorePlan(
        for strategy: PasteInsertionStrategy,
        localDelay: TimeInterval
    ) -> ClipboardRestorePlan {
        DictationClipboardRestorePolicy.clipboardRestorePlan(
            for: strategy,
            localDelay: localDelay
        )
    }

    static func shouldRestorePasteboard(
        currentChangeCount: Int,
        expectedChangeCount: Int
    ) -> Bool {
        DictationClipboardRestorePolicy.shouldRestorePasteboard(
            currentChangeCount: currentChangeCount,
            expectedChangeCount: expectedChangeCount
        )
    }

    static func restoredPasteboardItemsForTesting(
        _ items: [NSPasteboardItem]?
    ) -> [NSPasteboardItem]? {
        let snapshot = DictationPasteboardSnapshot.capture(items: items)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("yen.dictation.tests.\(UUID().uuidString)"))
        snapshot.restore(to: pasteboard)
        return pasteboard.pasteboardItems
    }

    static func stopCompletionEventName(hasInsertionDecision: Bool) -> String {
        hasInsertionDecision
            ? "stop_completion_ready_for_insert"
            : "stop_completion_without_insert"
    }

    static func insertionTargetGate(
        hasCapturedTarget: Bool,
        isCapturedTargetValid: Bool
    ) -> InsertionTargetGate {
        guard hasCapturedTarget else { return .missingStableTarget }
        return isCapturedTargetValid ? .ready : .invalidatedTarget
    }

    static func insertSessionEventName(
        for insertionOutcome: InsertionOutcome
    ) -> String {
        switch insertionOutcome {
        case .manualRecoveryRequired:
            return "insert_manual_recovery_required"
        case .directSurfacePaste, .responderChainPaste, .remoteCommandVPaste:
            return "insert_completed"
        }
    }

    static func mapRecognizerErrorToLocalServiceIssue(_ error: DictationRecognizer.RecognizerError?) -> LocalServiceIssue? {
        guard let error else { return nil }
        switch error {
        case .recognizerIsUnavailable:
            return .recognizerUnavailable
        case .noAudioInput:
            return .noAudioInput
        case .foregroundActivationRequired:
            return .foregroundInstallRequired
        case .taskFailed:
            return .runtimeFailure
        case .audioDeviceChanged:
            // Not a local speech-service problem. The hardware moved under a running
            // session, and the next Option+Space rebinds cleanly. Mapping this to
            // `.runtimeFailure` would raise a speech-service recovery prompt that
            // sends the user to fix something that is not broken.
            return nil
        }
    }

    static func resolvedLocalServiceIssue(
        persistedIssue: LocalServiceIssue?,
        startupIssue: LocalServiceIssue?
    ) -> LocalServiceIssue? {
        guard let persistedIssue else { return startupIssue }
        guard persistedIssue == .runtimeFailure else { return persistedIssue }
        return startupIssue
    }

    static func localServiceRecoveryBody(for issue: LocalServiceIssue) -> String {
        DictationPermissionMenuPolicy.localServiceRecoveryBody(for: issue)
    }

    static func legacySystemDictationEnabled(
        hitoolboxDomain: [String: Any]?,
        assistantDomain: [String: Any]?
    ) -> Bool? {
        for key in ["DictationIMMasterDictationEnabled", "DictationIMEnabled", "AppleDictationAutoEnable"] {
            if let value = legacyBool(from: hitoolboxDomain?[key]) {
                return value
            }
        }

        for key in ["Dictation Enabled", "DictationEnabled"] {
            if let value = legacyBool(from: assistantDomain?[key]) {
                return value
            }
        }

        return nil
    }

    private static func legacyBool(from rawValue: Any?) -> Bool? {
        switch rawValue {
        case let value as Bool:
            return value
        case let value as Int:
            return value != 0
        case let value as NSNumber:
            return value.intValue != 0
        case let value as String:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "1", "true", "yes", "on", "enabled":
                return true
            case "0", "false", "no", "off", "disabled":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    static func menuState(
        missing: [PrivacyDestination],
        localServiceIssue: LocalServiceIssue?,
        isPaused: Bool,
        launchNeedsApproval: Bool
    ) -> MenuState {
        DictationPermissionMenuPolicy.menuState(
            missing: missing,
            localServiceIssue: localServiceIssue,
            isPaused: isPaused,
            launchNeedsApproval: launchNeedsApproval
        )
    }

    private func refreshPermissionState(showRevocationNotice: Bool) {
        refreshStartupLocalServiceIssueIfNeeded()
        let (previous, snapshot) = permissions.refreshSnapshot()
        updateMenuState(missing: snapshot.missing)

        let outcome = captureSession.permissionRefreshOutcome(
            previousMissing: previous?.missing,
            currentMissing: snapshot.missing
        )
        if outcome.shouldHardTeardown {
            forceStopForPermissionRevocation()
        }

        if showRevocationNotice,
           outcome.shouldShowRevocationNotice {
            showPermissionRevokedNotice(missing: snapshot.missing)
        }
    }

    private func updateMenuState(missing: [PrivacyDestination]) {
        let state = Self.menuState(
            missing: missing,
            localServiceIssue: currentLocalServiceIssue,
            isPaused: isPaused,
            launchNeedsApproval: Self.launchAtLoginNeedsApproval
        )
        statusSummaryItem.title = state.summaryTitle
        statusDetailItem.title = state.detailTitle
        openMissingPermissionsItem.title = state.openPrimaryTitle
        openMissingPermissionsItem.isEnabled = state.openPrimaryEnabled
        recheckPermissionsItem.title = state.recheckTitle
        recheckPermissionsItem.isEnabled = state.recheckEnabled
        pauseResumeItem.title = state.pauseTitle
        pauseResumeItem.isEnabled = state.pauseEnabled
        if !isListening || !missing.isEmpty {
            statusItem.button?.toolTip = state.toolTip
        }
    }

    private func showPermissionRevokedNotice(missing: [PrivacyDestination]) {
        guard !missing.isEmpty else { return }
        let names = missing.map(\.title).joined(separator: ", ")

        if appIsActiveProvider() {
            guard !suppressInteractiveUI else { return }
            let alert = NSAlert()
            alert.messageText = "Dictation Permissions Changed"
            alert.informativeText = "YEN can no longer dictate because \(names) permission was revoked while the app was running."
            for destination in missing {
                alert.addButton(withTitle: "Open \(destination.title)")
            }
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            let firstButton = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let index = Int(response.rawValue - firstButton)
            if index >= 0 && index < missing.count {
                openSettings(for: missing[index])
            }
            return
        }

        postPermissionRevokedNotification(missing: missing)
    }

    private func postPermissionRevokedNotification(missing: [PrivacyDestination]) {
        let names = missing.map(\.title).joined(separator: ", ")
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "yen.dictation.permissions",
            title: "YEN Dictation Permissions Revoked",
            body: "Missing: \(names). Open System Settings > Privacy & Security to re-enable \(DictationCopy.fixedHotkey).",
            logLabel: "Permission notification"
        )
    }

    private func postPermissionNeededNotification(missing: [PrivacyDestination]) {
        let names = missing.isEmpty
            ? "required permissions"
            : missing.map(\.title).joined(separator: ", ")
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "yen.dictation.permissions-needed",
            title: "YEN Dictation Requires Permissions",
            body: "Missing: \(names). Open System Settings > Privacy & Security to enable \(DictationCopy.fixedHotkey).",
            logLabel: "Permission-needed notification"
        )
    }

    private func postLocalServiceNeededNotification(issue: LocalServiceIssue) {
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "yen.dictation.local-service",
            title: "YEN Dictation Needs Attention",
            body: Self.localServiceRecoveryBody(for: issue),
            logLabel: "Local-service notification"
        )
    }

    enum PrivacyDestination {
        case speechRecognition
        case microphone
        case accessibility

        var title: String {
            switch self {
            case .speechRecognition: return "Speech Recognition"
            case .microphone: return "Microphone"
            case .accessibility: return "Accessibility"
            }
        }

        var urlCandidates: [String] {
            switch self {
            case .speechRecognition:
                return [
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                ]
            case .microphone:
                return [
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                ]
            case .accessibility:
                return [
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                    "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                ]
            }
        }
    }

    enum PermissionSettingsActionPlan: Equatable {
        case promptAccessibilityThenOpenPrivacySettings
        case openPrivacySettings
        case requestSpeechRecognitionAuthorization
        case requestMicrophoneAccess
    }

    static func permissionActionTitle(
        for destination: PrivacyDestination,
        speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus(),
        microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    ) -> String {
        DictationPermissionMenuPolicy.permissionActionTitle(
            for: destination,
            speechStatus: speechStatus,
            microphoneStatus: microphoneStatus
        )
    }

    static func permissionSettingsActionPlan(
        for destination: PrivacyDestination,
        speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus(),
        microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    ) -> PermissionSettingsActionPlan {
        DictationPermissionMenuPolicy.permissionSettingsActionPlan(
            for: destination,
            speechStatus: speechStatus,
            microphoneStatus: microphoneStatus
        )
    }

    static func shouldOpenPrivacySettingsAfterSpeechAuthorization(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> Bool {
        DictationPermissionMenuPolicy.shouldOpenPrivacySettingsAfterSpeechAuthorization(status)
    }

    static func shouldOpenPrivacySettingsAfterMicrophoneAuthorization(_ granted: Bool) -> Bool {
        DictationPermissionMenuPolicy.shouldOpenPrivacySettingsAfterMicrophoneAuthorization(granted)
    }

    /// Determine which privacy permissions are currently missing.
    private func missingPrivacyDestinations() -> [PrivacyDestination] {
        permissions.missingPrivacyDestinations()
    }

    // MARK: - Permission Status

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }
    var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    var isSpeechRecognitionGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    private func startupLocalServiceIssue() -> LocalServiceIssue? {
        if let override = Self.startupLocalServiceIssueOverrideForTesting {
            return override()
        }
        let issue = mapRecognizerErrorToLocalServiceIssue(recognizer.startupIssue())
        guard issue == .recognizerUnavailable else { return issue }
        guard #available(macOS 26, *) else { return issue }
        guard !usingLegacyRecognizerFallback else { return issue }
        guard !recognizer.requiresSessionTimeout else { return issue }
        if let analyzer = recognizer as? SpeechAnalyzerRecognizer,
           analyzer.startupLocaleSupportStatus() == nil {
            return nil
        }
        guard !Self.hasActiveCaptureSession(
            pendingStart: pendingStart,
            isListening: isListening,
            isStopping: isStopping
        ) else {
            return issue
        }

        activateLegacyRecognizerFallback(reason: "startup-readiness")
        return mapRecognizerErrorToLocalServiceIssue(recognizer.startupIssue())
    }

    private func mapRecognizerErrorToLocalServiceIssue(
        _ error: DictationRecognizer.RecognizerError?
    ) -> LocalServiceIssue? {
        let mapped = Self.mapRecognizerErrorToLocalServiceIssue(error)
        guard mapped == .recognizerUnavailable else { return mapped }
        if #available(macOS 26, *) {
            return mapped
        }
        let legacyEnabled = Self.legacySystemDictationEnabled(
            hitoolboxDomain: UserDefaults.standard.persistentDomain(forName: "com.apple.HIToolbox"),
            assistantDomain: UserDefaults.standard.persistentDomain(forName: "com.apple.assistant.support")
        )
        if legacyEnabled == false {
            return .legacySystemDictationDisabled
        }
        return mapped
    }

    var currentLocalServiceIssue: LocalServiceIssue? {
        Self.resolvedLocalServiceIssue(
            persistedIssue: localServiceIssue,
            startupIssue: cachedStartupLocalServiceIssue
        )
    }

    private func takePendingStopInsertionTarget(for token: UUID) -> CapturedInsertionTarget? {
        guard pendingStopInsertionTarget?.token == token else { return nil }
        defer { pendingStopInsertionTarget = nil }
        return pendingStopInsertionTarget?.target
    }

    private static func liveFrontmostApplicationFocusedElement(for pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let focusedElement else { return nil }
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focusedElement, to: AXUIElement.self)
    }

    private static func liveFrontmostApplicationFocusFingerprint(for pid: pid_t) -> Int? {
        guard let focusedElement = liveFrontmostApplicationFocusedElement(for: pid) else {
            return nil
        }
        return Int(CFHash(focusedElement))
    }

    private static func liveSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    private func refreshStartupLocalServiceIssueIfNeeded(force: Bool = false) {
        let now = CFAbsoluteTimeGetCurrent()
        if !force && (now - startupIssueLastRefreshedAt) < Self.startupIssueRefreshIntervalSeconds {
            return
        }
        cachedStartupLocalServiceIssue = startupLocalServiceIssue()
        startupIssueLastRefreshedAt = now
    }

    func recheckLocalSpeechService() {
        refreshStartupLocalServiceIssueIfNeeded(force: true)
        localServiceIssue = cachedStartupLocalServiceIssue
        updateMenuState(missing: missingPrivacyDestinations())
    }

    static func _testSetStartupLocalServiceIssueOverride(
        _ override: (@MainActor () -> LocalServiceIssue?)?
    ) {
        startupLocalServiceIssueOverrideForTesting = override
    }

    func _testResetLocalServiceIssueState() {
        localServiceIssue = nil
        cachedStartupLocalServiceIssue = nil
        startupIssueLastRefreshedAt = 0
        updateMenuState(missing: missingPrivacyDestinations())
    }

    /// Open the most specific System Settings pane available for the destination.
    /// For first-time speech/mic states, trigger the native permission prompt first
    /// so YEN is registered in the relevant Privacy list.
    func openSettings(for destination: PrivacyDestination) {
        NSApp.unhide(nil)
        NSApp.yenActivateCompat()

        switch Self.permissionSettingsActionPlan(for: destination) {
        case .promptAccessibilityThenOpenPrivacySettings:
            DictationHotKey.shared.requestAccessibilityPrompt()
            openPrivacySettings(for: destination)

        case .requestSpeechRecognitionAuthorization:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.refreshPermissionState(showRevocationNotice: false)
                    if Self.shouldOpenPrivacySettingsAfterSpeechAuthorization(status) {
                        self?.openPrivacySettings(for: destination)
                    }
                }
            }

        case .requestMicrophoneAccess:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.refreshPermissionState(showRevocationNotice: false)
                    if Self.shouldOpenPrivacySettingsAfterMicrophoneAuthorization(granted) {
                        self?.openPrivacySettings(for: destination)
                    }
                }
            }

        case .openPrivacySettings:
            openPrivacySettings(for: destination)
        }
    }

    private func openPrivacySettings(for destination: PrivacyDestination) {
        SystemSettingsOpener.open(candidates: destination.urlCandidates + [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "x-apple.systempreferences:com.apple.preference.security"
        ])
    }

    private func openSystemDictationSettings() {
        SystemSettingsOpener.openKeyboardDictationSettings()
    }

    private func openSoundInputSettings() {
        SystemSettingsOpener.open(candidates: [
            "x-apple.systempreferences:com.apple.Sound-Settings.extension?input",
            "x-apple.systempreferences:com.apple.preference.sound?Input",
            "x-apple.systempreferences:com.apple.preference.sound"
        ] + PrivacyDestination.microphone.urlCandidates)
    }

    /// Show or hide the menu bar recording indicator.
    /// When recording starts, swaps to the blinking record icon.
    /// When recording stops, returns to the idle ¥ icon (if background mode
    /// is enabled) or hides entirely.
    private func setRecordingIndicator(_ recording: Bool) {
        guard !suppressInteractiveUI else { return }
        if recording {
            statusItem.button?.image = recordingImage
            statusItem.button?.toolTip = "YEN Dictation active"
            statusItem.button?.alphaValue = 1.0
            statusItem.isVisible = true
            indicatorVisible = true
            startBlinkTimer()
        } else {
            stopBlinkTimer()
            if DictationController.backgroundModeActive {
                statusItem.button?.image = idleImage
                statusItem.button?.alphaValue = 1.0
                refreshPermissionState(showRevocationNotice: false)
            } else {
                statusItem.isVisible = false
            }
        }
    }

    /// Start the blink timer for recording indicator.
    private func startBlinkTimer() {
        stopBlinkTimer()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: blinkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleIndicator()
            }
        }
        blinkTimer?.tolerance = 0.05
    }

    /// Stop the blink timer.
    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    /// Toggle the recording indicator visibility (blink effect via alpha).
    private func toggleIndicator() {
        indicatorVisible.toggle()
        statusItem.button?.alphaValue = indicatorVisible ? 1.0 : 0.0
    }

    /// Show alert when permissions are denied.
    private func showPermissionAlert() {
        let missing = missingPrivacyDestinations()
        updateMenuState(missing: missing)

        guard appIsActiveProvider() else {
            postPermissionNeededNotification(missing: missing)
            return
        }

        guard !suppressInteractiveUI else { return }

        let alert = NSAlert()
        alert.messageText = "Dictation Requires Permissions"
        if missing.isEmpty {
            alert.informativeText = "Please enable required permissions in System Settings > Privacy & Security."
        } else {
            let names = missing.map(\.title).joined(separator: ", ")
            alert.informativeText = "Enable \(names) in System Settings > Privacy & Security."
        }
        alert.alertStyle = .warning
        for destination in missing {
            alert.addButton(withTitle: "Open \(destination.title)")
        }
        if missing.isEmpty {
            alert.addButton(withTitle: "Open Settings")
        }
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        let firstButton = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let index = Int(response.rawValue - firstButton)
        if index >= 0 && index < missing.count {
            openSettings(for: missing[index])
        } else if missing.isEmpty && index == 0 {
            SystemSettingsOpener.open(candidates: [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                "x-apple.systempreferences:com.apple.preference.security"
            ])
        }
    }
}
