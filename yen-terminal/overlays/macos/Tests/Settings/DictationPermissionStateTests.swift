import AppKit
import Foundation
import ApplicationServices
import CoreGraphics
import AVFoundation
import Speech
import SwiftUI
import Testing
@preconcurrency @testable import YEN

private struct FakeTranslationEngine: DictationTranslationEngine {
    let availabilityImpl: (Locale.Language, Locale.Language) async -> DictationTranslationAvailability
    let translateImpl: (String, Locale.Language, Locale.Language) async throws -> String

    init(
        availabilityResult: DictationTranslationAvailability,
        translateImpl: @escaping (String, Locale.Language, Locale.Language) async throws -> String
    ) {
        self.availabilityImpl = { _, _ in availabilityResult }
        self.translateImpl = translateImpl
    }

    init(
        availabilityImpl: @escaping (Locale.Language, Locale.Language) async -> DictationTranslationAvailability,
        translateImpl: @escaping (String, Locale.Language, Locale.Language) async throws -> String
    ) {
        self.availabilityImpl = availabilityImpl
        self.translateImpl = translateImpl
    }

    func availability(
        source: Locale.Language,
        target: Locale.Language
    ) async -> DictationTranslationAvailability {
        await availabilityImpl(source, target)
    }

    func translate(
        text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String {
        try await translateImpl(text, source, target)
    }
}

private func fakeTranslateToHolaMundo(
    _ text: String,
    _ source: Locale.Language,
    _ target: Locale.Language
) async throws -> String {
    "hola mundo"
}

@MainActor
private final class FakeDictationRecognizer: DictationRecognizerProtocol {
    var requiresSessionTimeout: Bool
    var activeLocaleIdentifier: String
    var inputDeviceBinding: DictationInputDeviceBinding = .systemDefault
    var startupIssueValue: DictationRecognizer.RecognizerError?
    var startCallCount = 0
    var stopCallCount = 0
    var cancelCallCount = 0
    var autoReady = true
    var stopBehavior: ((@escaping @MainActor @Sendable (DictationRecognizerStopResult) -> Void) -> Void)?

    private(set) var onReady: (@MainActor @Sendable () -> Void)?
    private(set) var onAudioLevel: (@MainActor @Sendable (Float) -> Void)?
    private(set) var onPartialResult: (@MainActor @Sendable (String) -> Void)?
    private(set) var onError: (@MainActor @Sendable (DictationRecognizer.RecognizerError) -> Void)?
    private var stopCompletion: (@MainActor @Sendable (DictationRecognizerStopResult) -> Void)?
    private var lastStopCompletion: (@MainActor @Sendable (DictationRecognizerStopResult) -> Void)?

    init(
        requiresSessionTimeout: Bool,
        activeLocaleIdentifier: String = "en-US",
        startupIssueValue: DictationRecognizer.RecognizerError? = nil
    ) {
        self.requiresSessionTimeout = requiresSessionTimeout
        self.activeLocaleIdentifier = activeLocaleIdentifier
        self.startupIssueValue = startupIssueValue
    }

    func startListening(
        onReady: (@MainActor @Sendable () -> Void)?,
        onAudioLevel: @MainActor @Sendable @escaping (Float) -> Void,
        onPartialResult: @MainActor @Sendable @escaping (String) -> Void,
        onError: (@MainActor @Sendable (DictationRecognizer.RecognizerError) -> Void)?
    ) {
        startCallCount += 1
        self.onReady = onReady
        self.onAudioLevel = onAudioLevel
        self.onPartialResult = onPartialResult
        self.onError = onError
        if autoReady {
            self.onReady?()
            self.onReady = nil
        }
    }

    func stopListening(completion: @MainActor @Sendable @escaping (DictationRecognizerStopResult) -> Void) {
        stopCallCount += 1
        lastStopCompletion = completion
        if let stopBehavior {
            stopBehavior(completion)
            return
        }
        stopCompletion = completion
    }

    func cancel() {
        cancelCallCount += 1
    }

    func startupIssue() -> DictationRecognizer.RecognizerError? {
        startupIssueValue
    }

    func emitPartial(_ text: String) {
        onPartialResult?(text)
    }

    func emitAudioLevel(_ level: Float) {
        onAudioLevel?(level)
    }

    func emitError(_ error: DictationRecognizer.RecognizerError) {
        onError?(error)
    }

    func deliverStop(_ result: DictationRecognizerStopResult) {
        let completion = stopCompletion
        stopCompletion = nil
        completion?(result)
    }

    func replayLastStop(_ result: DictationRecognizerStopResult) {
        lastStopCompletion?(result)
    }

    func emitReady() {
        let ready = onReady
        onReady = nil
        ready?()
    }
}

@MainActor
private final class WatchdogHandlerCapture {
    var handler: (@Sendable @MainActor () -> Void)?
}

private actor SequencedTranslationCoordinator {
    private var pendingFirstContinuation: CheckedContinuation<String, Error>?
    private var hasBufferedFirstResume = false
    private let firstResult: String
    private let laterResults: [String]
    private var callCount = 0

    init(firstResult: String, laterResults: [String]) {
        self.firstResult = firstResult
        self.laterResults = laterResults
    }

    func translate(text: String) async throws -> String {
        callCount += 1
        if callCount == 1 {
            if hasBufferedFirstResume {
                hasBufferedFirstResume = false
                return firstResult
            }
            return try await withCheckedThrowingContinuation { continuation in
                pendingFirstContinuation = continuation
            }
        }
        let laterIndex = min(callCount - 2, max(laterResults.count - 1, 0))
        guard !laterResults.isEmpty else { return text }
        return laterResults[laterIndex]
    }

    func resumeFirst() {
        let continuation = pendingFirstContinuation
        pendingFirstContinuation = nil
        if let continuation {
            continuation.resume(returning: firstResult)
        } else {
            hasBufferedFirstResume = true
        }
    }
}

@MainActor
private func makeHeadlessDictationController(
    recognizer: FakeDictationRecognizer,
    legacyRecognizer: DictationRecognizerProtocol? = nil,
    hotkeyPressed: @escaping DictationController.HotkeyPressedProvider = { false },
    translationPostProcessor: DictationTranslationPostProcessor = DictationTranslationPostProcessor(
        translateOnDictateEnabled: { false }
    ),
    permissionAuthorizer: DictationController.PermissionAuthorizer? = nil,
    privacyDestinationProvider: DictationController.PrivacyDestinationProvider? = nil,
    maxDurationScheduler: @escaping DictationController.MaxDurationScheduler = { _, _ in
        DictationController.ScheduledWork(cancelImpl: {})
    },
    stopWatchdogScheduler: @escaping DictationController.StopWatchdogScheduler = { _, _ in
        DictationController.ScheduledWork(cancelImpl: {})
    },
    transcriptInserter: DictationController.TranscriptInserter? = nil,
    appIsActiveProvider: @escaping DictationController.AppIsActiveProvider = { true },
    frontmostApplicationPIDProvider: @escaping DictationController.FrontmostApplicationPIDProvider = { nil },
    frontmostApplicationFocusedElementProvider: @escaping DictationController.FrontmostApplicationFocusedElementProvider = { _ in nil },
    frontmostApplicationFocusFingerprintProvider: @escaping DictationController.FrontmostApplicationFocusFingerprintProvider = { _ in nil },
    secureEventInputProvider: @escaping @MainActor () -> Bool = { false },
    backgroundRecoveryReporter: DictationController.BackgroundRecoveryReporter? = nil,
    livePreviewMinimumInterval: TimeInterval = 0.12
) -> DictationController {
    DictationController(
        recognizer: recognizer,
        legacyRecognizer: legacyRecognizer,
        usingLegacyRecognizerFallback: false,
        translationPostProcessor: translationPostProcessor,
        permissionAuthorizer: permissionAuthorizer ?? { _, completion in
            completion(true)
        },
        privacyDestinationProvider: privacyDestinationProvider ?? { [] },
        hotkeyPressedProvider: hotkeyPressed,
        maxDurationScheduler: maxDurationScheduler,
        stopWatchdogScheduler: stopWatchdogScheduler,
        transcriptInserter: transcriptInserter,
        appIsActiveProvider: appIsActiveProvider,
        frontmostApplicationPIDProvider: frontmostApplicationPIDProvider,
        frontmostApplicationFocusedElementProvider: frontmostApplicationFocusedElementProvider,
        frontmostApplicationFocusFingerprintProvider: frontmostApplicationFocusFingerprintProvider,
        secureEventInputProvider: secureEventInputProvider,
        backgroundRecoveryReporter: backgroundRecoveryReporter,
        suppressInteractiveUI: true,
        livePreviewMinimumInterval: livePreviewMinimumInterval
    )
}

@Suite(.serialized)
@MainActor
struct DictationPermissionStateTests {
    @Test func permissionSnapshotsRetainPreviousStateAcrossProviderChanges() {
        var missing: [DictationController.PrivacyDestination] = []
        let permissions = DictationPermissionController(
            privacyDestinationProvider: { missing },
            suppressInteractiveUI: true
        )
        let initial = permissions.refreshSnapshot()
        #expect(initial.previous == nil)
        #expect(initial.current.missing.isEmpty)
        missing = [.microphone]
        let revoked = permissions.refreshSnapshot()
        #expect(revoked.previous == initial.current)
        #expect(revoked.current.missing == [.microphone])
        missing = []
        let restored = permissions.refreshSnapshot()
        #expect(restored.previous == revoked.current)
        #expect(restored.current.missing.isEmpty)
    }

    @Test func permissionOverridePreservesPromptIntentAndRecoveryReporter() {
        var promptIntents: [Bool] = []
        var outcomes: [Bool] = []
        var refreshCount = 0
        var messages: [String] = []
        let permissions = DictationPermissionController(
            permissionAuthorizer: { allowPrompts, completion in
                promptIntents.append(allowPrompts)
                completion(allowPrompts)
            },
            backgroundRecoveryReporter: { title, body in messages.append(title + body) },
            suppressInteractiveUI: true
        )
        for allowPrompts in [false, true] {
            permissions.authorizeForDictation(
                allowNativePrompts: allowPrompts,
                refreshState: { refreshCount += 1 },
                completion: { outcomes.append($0) }
            )
        }
        #expect(promptIntents == [false, true])
        #expect(outcomes == [false, true])
        #expect(refreshCount == 0)
        permissions.deliverBackgroundRecoveryNotification(
            identifierPrefix: "test", title: "Recovery", body: " required", logLabel: "test"
        )
        #expect(messages == ["Recovery required"])
    }

    @Test func liveTranscriptAnnouncementsRequireMaterialThrottledChanges() {
        #expect(!DictationOverlay.shouldAnnounceTranscript(text: "", previousText: nil, elapsed: 10))
        #expect(!DictationOverlay.shouldAnnounceTranscript(text: "hi", previousText: nil, elapsed: 10))
        #expect(!DictationOverlay.shouldAnnounceTranscript(text: "hello", previousText: nil, elapsed: 1.9))
        #expect(!DictationOverlay.shouldAnnounceTranscript(text: "hello", previousText: "hello", elapsed: 3))
        #expect(DictationOverlay.shouldAnnounceTranscript(text: "hello world", previousText: "hello", elapsed: 2))
    }

    @Test func showingOverlayStartsFreshTranscriptAnnouncementSession() {
        let overlay = DictationOverlay()
        var announcements: [String] = []
        overlay.testAnnouncementHandler = { announcements.append($0) }

        overlay.show()
        overlay.update(text: "hello world", announceTranscript: true)
        overlay.update(text: "hello world", announceTranscript: true)

        overlay.show()
        overlay.update(text: "hello world", announceTranscript: true)
        overlay.hide()

        #expect(announcements == ["hello world", "hello world"])
    }

    @Test func menuStateShowsEnabledCopyWhenAllPermissionsGranted() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: nil,
            isPaused: false,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.enabledSummary)
        #expect(state.detailTitle == DictationCopy.enabledDetail)
        #expect(state.openPrimaryTitle == DictationCopy.openAllGrantedTitle)
        #expect(state.openPrimaryEnabled == false)
        #expect(state.pauseTitle == DictationCopy.pauseActionTitle)
        #expect(state.pauseEnabled == true)
        #expect(state.toolTip == DictationCopy.enabledToolTip(launchNeedsApproval: false))
    }

    @Test func menuStateShowsPendingApprovalCopyWhenLoginItemNeedsApproval() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: nil,
            isPaused: false,
            launchNeedsApproval: true
        )

        #expect(state.summaryTitle == DictationCopy.launchAtLoginPendingSummary)
        #expect(state.openPrimaryEnabled == false)
        #expect(state.toolTip == DictationCopy.enabledToolTip(launchNeedsApproval: true))
    }

    @Test func menuStateShowsBlockedReasonAndRecoveryAction() {
        let state = DictationController.menuState(
            missing: [.accessibility, .microphone],
            localServiceIssue: nil,
            isPaused: false,
            launchNeedsApproval: true
        )

        #expect(state.summaryTitle == DictationCopy.blockedSummary)
        #expect(state.detailTitle == "Blocked: enable Accessibility, Microphone")
        #expect(state.openPrimaryTitle == "Open Accessibility Settings")
        #expect(state.openPrimaryEnabled == true)
        #expect(state.openPrimaryAction == .openMissingPermission)
        #expect(state.pauseEnabled == false)
        #expect(state.toolTip == "YEN — Dictation blocked (Accessibility, Microphone; Launch at Login pending approval)")
    }

    @Test func menuStateShowsPausedStatusAndResumeAction() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: nil,
            isPaused: true,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.pausedSummary)
        #expect(state.detailTitle == DictationCopy.pausedDetail)
        #expect(state.pauseTitle == DictationCopy.resumeActionTitle)
        #expect(state.pauseEnabled == true)
        #expect(state.openPrimaryEnabled == false)
        #expect(state.toolTip == DictationCopy.pausedToolTip(launchNeedsApproval: false))
    }

    @Test func blockedStateOverridesPausedStatus() {
        let state = DictationController.menuState(
            missing: [.microphone],
            localServiceIssue: .runtimeFailure,
            isPaused: true,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.blockedSummary)
        #expect(state.detailTitle == "Blocked: enable Microphone")
        #expect(state.pauseTitle == DictationCopy.resumeActionTitle)
        #expect(state.pauseEnabled == false)
    }

    @Test func localServiceFailureMapsToDedicatedBlockedCopyAndActions() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: .noAudioInput,
            isPaused: false,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.blockedSummary)
        #expect(state.detailTitle == DictationCopy.localNoAudioInputDetail)
        #expect(state.openPrimaryTitle == DictationCopy.openSoundInputSettingsTitle)
        #expect(state.openPrimaryEnabled == true)
        #expect(state.openPrimaryAction == .openSoundInputSettings)
        #expect(state.recheckTitle == DictationCopy.recheckLocalServiceTitle)
        #expect(state.pauseEnabled == false)
    }

    @Test func foregroundInstallRequirementMapsToBringAppForwardRecovery() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: .foregroundInstallRequired,
            isPaused: false,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.blockedSummary)
        #expect(state.detailTitle == DictationCopy.localForegroundInstallRequiredDetail)
        #expect(state.openPrimaryTitle == DictationCopy.activateYENTitle)
        #expect(state.openPrimaryEnabled == true)
        #expect(state.openPrimaryAction == .activateYEN)
        #expect(state.recheckTitle == DictationCopy.recheckLocalServiceTitle)
        #expect(state.pauseEnabled == false)
    }

    @Test func legacySystemDictationDisabledIssueMapsToDedicatedRecoveryAction() {
        let state = DictationController.menuState(
            missing: [],
            localServiceIssue: .legacySystemDictationDisabled,
            isPaused: false,
            launchNeedsApproval: false
        )

        #expect(state.summaryTitle == DictationCopy.blockedSummary)
        #expect(state.detailTitle == DictationCopy.localLegacyDictationDisabledDetail)
        #expect(state.openPrimaryTitle == DictationCopy.openSystemDictationSettingsTitle)
        #expect(state.openPrimaryAction == .openSystemDictationSettings)
        #expect(state.recheckTitle == DictationCopy.recheckLocalServiceTitle)
        #expect(state.pauseEnabled == false)
    }

    @Test func hotkeyEligibilityPrioritizesLocalBlockThenPause() {
        #expect(
            DictationController.hotkeyEligibility(
                isPaused: false,
                localServiceIssue: nil
            ) == .allowed
        )
        #expect(
            DictationController.hotkeyEligibility(
                isPaused: true,
                localServiceIssue: nil
            ) == .paused
        )
        #expect(
            DictationController.hotkeyEligibility(
                isPaused: true,
                localServiceIssue: .runtimeFailure
            ) == .blocked(.runtimeFailure)
        )
    }

    @Test func hotkeyDownActionQueuesRestartDuringFinalize() {
        #expect(
            DictationController.hotkeyDownAction(
                isStopping: true,
                isListening: true,
                pendingStart: false
            ) == .queueRestartAfterStop
        )
    }

    @Test func hotkeyDownActionIgnoresWhenAlreadyListeningOrPendingStart() {
        #expect(
            DictationController.hotkeyDownAction(
                isStopping: false,
                isListening: true,
                pendingStart: false
            ) == .ignore
        )
        #expect(
            DictationController.hotkeyDownAction(
                isStopping: false,
                isListening: false,
                pendingStart: true
            ) == .ignore
        )
    }

    @Test func hotkeyDownActionStartsPermissionCheckWhenIdle() {
        #expect(
            DictationController.hotkeyDownAction(
                isStopping: false,
                isListening: false,
                pendingStart: false
            ) == .beginPermissionCheck
        )
    }

    @Test func hotkeyUpSynthesisTriggersWhenSpaceIsNoLongerHeldDuringRecovery() {
        #expect(
            DictationHotKey.shouldSynthesizeHotkeyUp(
                isHotkeyPressed: true,
                isSpaceKeyDown: false,
                keyboardFlags: [.maskAlternate]
            ) == true
        )
        #expect(
            DictationHotKey.shouldSynthesizeHotkeyUp(
                isHotkeyPressed: true,
                isSpaceKeyDown: false,
                keyboardFlags: []
            ) == true
        )
    }

    @Test func hotkeyEventResolutionConsumesInitialPressAndKeyRepeat() {
        #expect(
            DictationHotKey.hotkeyEventResolution(
                type: .keyDown,
                keyCode: 0x31,
                reducedFlags: [.maskAlternate],
                isHotkeyPressed: false
            ) == DictationHotKey.HotkeyEventResolution(
                shouldBeginPress: true,
                releaseReason: nil,
                consumeEvent: true
            )
        )
        #expect(
            DictationHotKey.hotkeyEventResolution(
                type: .keyDown,
                keyCode: 0x31,
                reducedFlags: [.maskAlternate],
                isHotkeyPressed: true
            ) == DictationHotKey.HotkeyEventResolution(
                shouldBeginPress: false,
                releaseReason: nil,
                consumeEvent: true
            )
        )
    }

    @Test func hotkeyEventResolutionHandlesSpaceAndModifierReleaseOrdering() {
        #expect(
            DictationHotKey.hotkeyEventResolution(
                type: .keyUp,
                keyCode: 0x31,
                reducedFlags: [.maskAlternate],
                isHotkeyPressed: true
            ) == DictationHotKey.HotkeyEventResolution(
                shouldBeginPress: false,
                releaseReason: .spaceKeyUp,
                consumeEvent: true
            )
        )
        #expect(
            DictationHotKey.hotkeyEventResolution(
                type: .flagsChanged,
                keyCode: 0x3A,
                reducedFlags: [],
                isHotkeyPressed: true
            ) == DictationHotKey.HotkeyEventResolution(
                shouldBeginPress: false,
                releaseReason: .modifierFlagsChanged,
                consumeEvent: false
            )
        )
    }

    @Test func hotkeyTapRecoveryQueuesPressedStateOnlyForActiveChord() {
        #expect(
            DictationHotKey.shouldQueuePressedStateRecovery(
                isHotkeyPressed: true
            ) == true
        )
        #expect(
            DictationHotKey.shouldQueuePressedStateRecovery(
                isHotkeyPressed: false
            ) == false
        )
    }

    @Test func hotkeyUpSynthesisIgnoresModifierDriftWhileSpaceRemainsHeld() {
        #expect(
            DictationHotKey.shouldSynthesizeHotkeyUp(
                isHotkeyPressed: true,
                isSpaceKeyDown: true,
                keyboardFlags: [.maskAlternate, .maskShift]
            ) == false
        )
    }

    @Test func hotkeyUpSynthesisStaysDisabledWhileExactOptionSpaceIsStillHeld() {
        #expect(
            DictationHotKey.shouldSynthesizeHotkeyUp(
                isHotkeyPressed: false,
                isSpaceKeyDown: false,
                keyboardFlags: []
            ) == false
        )
        #expect(
            DictationHotKey.shouldSynthesizeHotkeyUp(
                isHotkeyPressed: true,
                isSpaceKeyDown: true,
                keyboardFlags: [.maskAlternate]
            ) == false
        )
    }

    @Test func accessibilityTrustLossEmitsHotkeyUpOnlyWhenPressWasActive() {
        #expect(
            DictationHotKey.shouldEmitHotkeyUpOnAccessibilityTrustLoss(
                isHotkeyPressed: true
            ) == true
        )
        #expect(
            DictationHotKey.shouldEmitHotkeyUpOnAccessibilityTrustLoss(
                isHotkeyPressed: false
            ) == false
        )
    }

    @Test func restartAfterStopRequiresQueuedRestartAndPressedHotkey() {
        #expect(
            DictationController.shouldRestartAfterStop(
                queuedRestart: true,
                hotkeyStillPressed: true
            ) == true
        )
        #expect(
            DictationController.shouldRestartAfterStop(
                queuedRestart: true,
                hotkeyStillPressed: false
            ) == false
        )
        #expect(
            DictationController.shouldRestartAfterStop(
                queuedRestart: false,
                hotkeyStillPressed: true
            ) == false
        )
    }

    @Test func finalResultForInsertionTrimsWhitespaceAndDropsEmptyValues() {
        #expect(DictationController.finalResultForInsertion(nil) == nil)
        #expect(DictationController.finalResultForInsertion("   ") == nil)
        #expect(DictationController.finalResultForInsertion(" hello ") == " hello ")
    }

    @Test func sessionStateTransitionContractMatchesExpectedFlow() {
        #expect(DictationController.isValidSessionStateTransition(from: .idle, to: .starting) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .idle, to: .failed) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .starting, to: .listening) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .listening, to: .stopping) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .stopping, to: .inserting) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .inserting, to: .idle) == true)
        #expect(DictationController.isValidSessionStateTransition(from: .listening, to: .starting) == false)
        #expect(DictationController.isValidSessionStateTransition(from: .idle, to: .listening) == false)
    }

    @Test func fallbackTranscriptPolicyMatchesStopCauseContract() {
        #expect(DictationController.shouldAllowFallbackTranscript(for: .hotkeyRelease) == false)
        #expect(DictationController.shouldAllowFallbackTranscript(for: .legacyTimeout) == false)
        #expect(DictationController.shouldAllowFallbackTranscript(for: .paused) == false)
        #expect(DictationController.shouldAllowFallbackTranscript(for: .recognizerError) == true)
        #expect(DictationController.shouldAllowFallbackTranscript(for: .watchdog) == true)
        #expect(DictationController.shouldAllowFallbackTranscript(for: .forcedReset) == true)
    }

    @Test func sessionCallbackAcceptanceRequiresMatchingSessionID() {
        let active = UUID()
        let stale = UUID()

        #expect(
            DictationController.shouldAcceptSessionCallback(
                activeSessionID: active,
                callbackSessionID: active
            ) == true
        )
        #expect(
            DictationController.shouldAcceptSessionCallback(
                activeSessionID: active,
                callbackSessionID: stale
            ) == false
        )
        #expect(
            DictationController.shouldAcceptSessionCallback(
                activeSessionID: nil,
                callbackSessionID: stale
            ) == false
        )
    }

    @Test func stopCompletionAcceptanceRequiresMatchingStopToken() {
        let active = UUID()
        let stale = UUID()

        #expect(
            DictationController.shouldAcceptStopCompletion(
                activeStopToken: active,
                completionToken: active
            ) == true
        )
        #expect(
            DictationController.shouldAcceptStopCompletion(
                activeStopToken: active,
                completionToken: stale
            ) == false
        )
        #expect(
            DictationController.shouldAcceptStopCompletion(
                activeStopToken: nil,
                completionToken: stale
            ) == false
        )
    }

    @Test func stopCompletionAcceptanceIsExactlyOncePerTokenLifecycle() {
        let token = UUID()
        var activeToken: UUID? = token

        #expect(
            DictationController.shouldAcceptStopCompletion(
                activeStopToken: activeToken,
                completionToken: token
            ) == true
        )

        activeToken = nil
        #expect(
            DictationController.shouldAcceptStopCompletion(
                activeStopToken: activeToken,
                completionToken: token
            ) == false
        )
    }

    @Test func liveTranscriptPreviewRendersOnlyWhenEnabledAndActivelyListening() {
        #expect(
            DictationController.shouldRenderLiveTranscriptPreview(
                liveTranscriptEnabled: true,
                isStopping: false
            ) == true
        )
        #expect(
            DictationController.shouldRenderLiveTranscriptPreview(
                liveTranscriptEnabled: false,
                isStopping: false
            ) == false
        )
        #expect(
            DictationController.shouldRenderLiveTranscriptPreview(
                liveTranscriptEnabled: true,
                isStopping: true
            ) == false
        )
    }

    @Test func previewEquivalentFrameSuppressionMatchesTextIdentity() {
        var rendered: [String] = []
        let preview = DictationLivePreviewController(
            minimumInterval: 0,
            canRender: { true },
            render: { rendered.append($0) }
        )
        for text in ["hello world", "hello world", " hello world  "] {
            if let normalized = DictationController.normalizedLivePreviewText(text) {
                preview.queue(normalizedText: normalized)
            }
        }
        #expect(rendered == ["hello world"])
        preview.queue(normalizedText: "different text")
        #expect(rendered == ["hello world", "different text"])
    }

    @Test func normalizedLivePreviewTextTrimsWhitespaceAndRejectsEmptyFrames() {
        #expect(DictationController.normalizedLivePreviewText(nil) == nil)
        #expect(DictationController.normalizedLivePreviewText("  \n\t  ") == nil)
        #expect(
            DictationController.normalizedLivePreviewText("  preview text  \n") == "preview text"
        )
    }

    @Test func previewThrottleDelayOnlyAppliesInsideMinimumInterval() {
        let minimumInterval: TimeInterval = 0.12
        #expect(
            DictationLivePreviewController.delayUntilNextFrame(
                now: 10.0,
                lastRenderedAt: 0,
                minimumInterval: minimumInterval
            ) == nil
        )
        #expect(
            DictationLivePreviewController.delayUntilNextFrame(
                now: 10.20,
                lastRenderedAt: 10.0,
                minimumInterval: minimumInterval
            ) == nil
        )
        let delayed = DictationLivePreviewController.delayUntilNextFrame(
            now: 10.05,
            lastRenderedAt: 10.0,
            minimumInterval: minimumInterval
        )
        #expect(delayed != nil)
        #expect(delayed! > 0)
        #expect(delayed! < minimumInterval)
    }

    @Test func dictationOverlayFramePinsToTopCenterOfVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1200, height: 800)
        let frame = DictationOverlay.overlayFrame(
            contentSize: NSSize(width: 400, height: 52),
            visibleFrame: visibleFrame
        )

        #expect(frame.origin.x == 500)
        #expect(frame.origin.y == 790)
        #expect(frame.width == 400)
        #expect(frame.height == 52)
    }

    @Test func dictationOverlayFrameClampsToVisibleWidthInsets() {
        let visibleFrame = NSRect(x: 40, y: 20, width: 300, height: 140)
        let frame = DictationOverlay.overlayFrame(
            contentSize: NSSize(width: 600, height: 60),
            visibleFrame: visibleFrame
        )

        #expect(frame.origin.x == 56)
        #expect(frame.origin.y == 92)
        #expect(frame.width == 268)
        #expect(frame.height == 60)
    }

    @Test func dictationOverlayFrameClampsTallContentToVisibleHeight() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 320, height: 90)
        let frame = DictationOverlay.overlayFrame(
            contentSize: NSSize(width: 240, height: 200),
            visibleFrame: visibleFrame
        )

        #expect(frame.origin.x == 40)
        #expect(frame.origin.y == 0)
        #expect(frame.width == 240)
        #expect(frame.height == 82)
    }

    @Test func dictationOverlayRecenterSkipRequiresActualPanelFrameToMatch() {
        let centeredFrame = NSRect(x: 100, y: 200, width: 320, height: 64)
        let driftedPanelFrame = NSRect(x: 140, y: 160, width: 320, height: 64)

        #expect(
            !DictationOverlay.shouldApplyCenteredFrame(
                currentPanelFrame: centeredFrame,
                lastCenteredFrame: centeredFrame,
                computedFrame: centeredFrame
            )
        )
        #expect(
            DictationOverlay.shouldApplyCenteredFrame(
                currentPanelFrame: driftedPanelFrame,
                lastCenteredFrame: centeredFrame,
                computedFrame: centeredFrame
            )
        )
        #expect(
            DictationOverlay.shouldApplyCenteredFrame(
                currentPanelFrame: centeredFrame,
                lastCenteredFrame: nil,
                computedFrame: centeredFrame
            )
        )
    }

    @Test func dictationOverlayScreenSelectionPrefersMouseDisplay() {
        let screens = [
            DictationOverlay.ScreenPlacement(
                frame: NSRect(x: 0, y: 0, width: 1440, height: 900),

            ),
            DictationOverlay.ScreenPlacement(
                frame: NSRect(x: 1440, y: 0, width: 1512, height: 982),

            ),
        ]

        let selectedIndex = DictationOverlay.preferredScreenIndex(
            mouseLocation: NSPoint(x: 1700, y: 500),
            screens: screens,
            mainScreenIndex: 0
        )

        #expect(selectedIndex == 1)
    }

    @Test func dictationOverlayScreenSelectionFallsBackToMainDisplay() {
        let screens = [
            DictationOverlay.ScreenPlacement(
                frame: NSRect(x: 0, y: 0, width: 1440, height: 900),

            ),
            DictationOverlay.ScreenPlacement(
                frame: NSRect(x: 1440, y: 0, width: 1512, height: 982),

            ),
        ]

        let selectedIndex = DictationOverlay.preferredScreenIndex(
            mouseLocation: NSPoint(x: -400, y: -200),
            screens: screens,
            mainScreenIndex: 1
        )

        #expect(selectedIndex == 1)
    }

    @Test func dictationOverlayPanelBehaviorStaysNonActivatingAndClickThrough() {
        let behavior = DictationOverlay.panelBehavior()

        #expect(behavior.styleMask.contains(.borderless))
        #expect(behavior.styleMask.contains(.nonactivatingPanel))
        #expect(behavior.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(behavior.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(behavior.isFloatingPanel == true)
        #expect(behavior.level == .statusBar)
        #expect(behavior.ignoresMouseEvents == true)
        #expect(behavior.isReleasedWhenClosed == false)
    }

    @Test func dictationOverlayAccessibilityPoliciesHonorReduceMotionAndTransparency() {
        #expect(
            DictationOverlay.animationDuration(
                reduceMotionEnabled: false,
                phase: .show
            ) == 0.2
        )
        #expect(
            DictationOverlay.animationDuration(
                reduceMotionEnabled: false,
                phase: .hide
            ) == 0.15
        )
        #expect(
            DictationOverlay.animationDuration(
                reduceMotionEnabled: true,
                phase: .show
            ) == 0
        )
        #expect(
            DictationOverlay.shouldUseOpaqueBackground(
                reduceTransparencyEnabled: false,
                workspaceReduceTransparencyEnabled: false
            ) == false
        )
        #expect(
            DictationOverlay.shouldUseOpaqueBackground(
                reduceTransparencyEnabled: true,
                workspaceReduceTransparencyEnabled: false
            ) == true
        )
        #expect(
            DictationOverlay.shouldUseOpaqueBackground(
                reduceTransparencyEnabled: false,
                workspaceReduceTransparencyEnabled: true
            ) == true
        )
        #expect(
            DictationOverlay.recenterNotificationNames() == [
                NSApplication.didChangeScreenParametersNotification,
                NSWorkspace.activeSpaceDidChangeNotification,
            ]
        )
    }

    @Test func dictationOverlayHideCompletionOnlyDismissesMatchingGeneration() {
        #expect(
            DictationOverlay.shouldDismissAfterHide(
                completionGeneration: 4,
                currentGeneration: 4
            ) == true
        )
        #expect(
            DictationOverlay.shouldDismissAfterHide(
                completionGeneration: 4,
                currentGeneration: 5
            ) == false
        )
    }

    @Test func dictationOverlayPresentationKeepsStatusCopyMinimal() {
        #expect(
            DictationOverlay.presentation(for: DictationCopy.overlayListeningLine)
                == DictationOverlay.Presentation(
                    eyebrowText: nil,
                    bodyText: DictationCopy.overlayListeningLine
                )
        )
        #expect(
            DictationOverlay.presentation(for: DictationCopy.overlayProcessingLine)
                == DictationOverlay.Presentation(
                    eyebrowText: nil,
                    bodyText: DictationCopy.overlayProcessingLine
                )
        )
        #expect(
            DictationOverlay.presentation(for: DictationCopy.pausedAttemptOverlayLine)
                == DictationOverlay.Presentation(
                    eyebrowText: nil,
                    bodyText: DictationCopy.pausedAttemptOverlayLine
                )
        )
    }

    @Test func dictationOverlayAudioMeterTracksListeningAndClampsSignalLevel() {
        #expect(DictationOverlay.shouldShowAudioMeter(for: ""))
        #expect(DictationOverlay.shouldShowAudioMeter(for: DictationCopy.overlayListeningLine))
        #expect(DictationOverlay.shouldShowAudioMeter(for: "live transcript preview"))
        #expect(!DictationOverlay.shouldShowAudioMeter(for: DictationCopy.overlayProcessingLine))
        #expect(!DictationOverlay.shouldShowAudioMeter(for: DictationCopy.pausedAttemptOverlayLine))
        #expect(DictationOverlay.clampedAudioLevel(-0.5) == 0)
        #expect(DictationOverlay.clampedAudioLevel(0.42) == 0.42)
        #expect(DictationOverlay.clampedAudioLevel(2) == 1)
        #expect(DictationOverlay.clampedAudioLevel(.nan) == 0)

        let overlay = DictationOverlay()
        overlay.updateAudioLevel(0.65)
        #expect(overlay.testingAudioLevel == 0.65)
        overlay.update(text: DictationCopy.overlayProcessingLine)
        #expect(overlay.testingAudioLevel == 0)
    }

    @Test func dictationAudioLevelNormalizationMapsSilenceAndFullScale() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32) else {
            Issue.record("Failed to create audio-level test buffer")
            return
        }
        buffer.frameLength = 32
        guard let samples = buffer.floatChannelData?[0] else {
            Issue.record("Missing float samples")
            return
        }

        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 0
        }
        #expect(DictationAudioEngineTap.normalizedAudioLevel(buffer: buffer) == 0)

        for index in 0..<Int(buffer.frameLength) {
            samples[index] = 1
        }
        #expect(DictationAudioEngineTap.normalizedAudioLevel(buffer: buffer) == 1)
    }

    @Test func dictationAudioMeterUsesProminentLayeredWaveGeometry() {
        #expect(DictationAudioLevelView.meterWidth == 64)
        #expect(DictationAudioLevelView.meterHeight == 28)
        #expect(DictationAudioLevelView.waveCount == 4)
        #expect(DictationAudioLevelView.minimumAmplitude == 1.5)
        #expect(DictationAudioLevelView.responsiveAmplitude == 9)
    }

    @MainActor @Test func dictationAudioMeterRendersAtProminentSize() throws {
        let hostingView = NSHostingView(
            rootView: DictationAudioLevelView(level: 0.78)
                .frame(
                    width: DictationAudioLevelView.meterWidth,
                    height: DictationAudioLevelView.meterHeight
                )
        )
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: DictationAudioLevelView.meterWidth,
                height: DictationAudioLevelView.meterHeight
            )
        )
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            Issue.record("Failed to create the dictation meter render buffer")
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        #expect(representation.pixelsWide >= 64)
        #expect(representation.pixelsHigh >= 28)

        if let snapshotPath = ProcessInfo.processInfo.environment["YEN_DICTATION_METER_SNAPSHOT_PATH"] {
            let imageData = try #require(
                representation.representation(using: .png, properties: [:])
            )
            try imageData.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }
    }

    @Test func headlessControllerShowsLiveAudioLevelOnlyWhileListening() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false }
        )

        controller.handleHotkeyDown()
        recognizer.emitAudioLevel(0.6)
        #expect(controller.testingOverlayAudioLevel == 0.6)

        controller.handleHotkeyUp()
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        #expect(controller.testingOverlayAudioLevel == 0)
        recognizer.deliverStop(.empty)
    }

    @Test func dictationOverlayPresentationShowsPreviewEyebrowAndTailCapsLongText() {
        let previewText = Array(repeating: "segment", count: 60).joined(separator: " ")
        let presentation = DictationOverlay.presentation(for: previewText)

        #expect(presentation.eyebrowText == "Live Transcript Preview")
        #expect(presentation.bodyText.hasPrefix("…"))
        #expect(presentation.bodyText.contains("segment segment"))
        #expect(presentation.bodyText.count <= DictationOverlay.maxPreviewCharacterCount + 1)
        #expect(
            DictationOverlay.maxPreviewWidth == 600
        )
        #expect(
            DictationOverlay.maxPreviewLineCount == 8
        )
    }

    @Test func dictationOverlayAccessibilityPresentationUsesStableLabelAndCurrentValue() {
        let listening = DictationOverlay.presentation(for: DictationCopy.overlayListeningLine)
        #expect(
            DictationOverlay.accessibilityPresentation(for: listening)
                == DictationOverlay.AccessibilityPresentation(
                    label: "Dictation",
                    value: DictationCopy.overlayListeningLine
                )
        )

        let preview = DictationOverlay.presentation(for: "ship the accessibility update")
        #expect(
            DictationOverlay.accessibilityPresentation(for: preview)
                == DictationOverlay.AccessibilityPresentation(
                    label: "Dictation",
                    value: "Live Transcript Preview: ship the accessibility update"
                )
        )
    }

    @Test func transcriptForInsertionPrefersFinalResultAndLimitsFallbackToFailurePaths() {
        #expect(
            DictationController.transcriptForInsertion(
                stopResult: DictationRecognizerStopResult(
                    finalText: "final text",
                    fallbackText: "partial text"
                ),
                fallbackTranscript: "partial text",
                stopCause: .hotkeyRelease
            ) == DictationController.TranscriptInsertionDecision(
                text: "final text",
                source: .final
            )
        )
        #expect(
            DictationController.transcriptForInsertion(
                stopResult: DictationRecognizerStopResult(
                    finalText: nil,
                    fallbackText: "partial text"
                ),
                fallbackTranscript: "partial text",
                stopCause: .hotkeyRelease
            ) == nil
        )
        #expect(
            DictationController.transcriptForInsertion(
                stopResult: DictationRecognizerStopResult(
                    finalText: nil,
                    fallbackText: "partial text"
                ),
                fallbackTranscript: "partial text",
                stopCause: .watchdog
            ) == DictationController.TranscriptInsertionDecision(
                text: "partial text",
                source: .fallback
            )
        )
        #expect(
            DictationController.transcriptForInsertion(
                stopResult: DictationRecognizerStopResult(
                    finalText: "   ",
                    fallbackText: "   "
                ),
                fallbackTranscript: "   ",
                stopCause: .recognizerError
            ) == nil
        )
    }

    @Test func transcriptFallbackIsRejectedForNormalStopCauses() {
        let normalStopCauses: [DictationController.StopCause] = [
            .hotkeyRelease,
            .legacyTimeout,
            .paused,
        ]

        for stopCause in normalStopCauses {
            #expect(
                DictationController.transcriptForInsertion(
                    stopResult: DictationRecognizerStopResult(
                        finalText: nil,
                        fallbackText: "partial text"
                    ),
                    fallbackTranscript: "partial text",
                    stopCause: stopCause
                ) == nil
            )
        }
    }

    @Test func transcriptFallbackIsAllowedOnlyForFailureStopCauses() {
        let failureStopCauses: [DictationController.StopCause] = [
            .recognizerError,
            .watchdog,
            .forcedReset,
        ]

        for stopCause in failureStopCauses {
            #expect(
                DictationController.transcriptForInsertion(
                    stopResult: DictationRecognizerStopResult(
                        finalText: nil,
                        fallbackText: "partial text"
                    ),
                    fallbackTranscript: "partial text",
                    stopCause: stopCause
                ) == DictationController.TranscriptInsertionDecision(
                    text: "partial text",
                    source: .fallback
                )
            )
        }
    }

    @Test func keyUpToInsertLatencyIsReportedOnlyForHotkeyStops() {
        let hotkeyLatency = DictationController.keyUpToInsertLatencyMilliseconds(
            stopCause: .hotkeyRelease,
            stopRequestedAt: 100,
            insertedAt: 100.125
        )
        #expect(hotkeyLatency == 125)

        let watchdogLatency = DictationController.keyUpToInsertLatencyMilliseconds(
            stopCause: .watchdog,
            stopRequestedAt: 100,
            insertedAt: 100.125
        )
        #expect(watchdogLatency == nil)
    }

    @Test func recognizerErrorsMapToLocalServiceIssues() {
        #expect(
            DictationController.mapRecognizerErrorToLocalServiceIssue(.recognizerIsUnavailable)
            == .recognizerUnavailable
        )
        #expect(
            DictationController.mapRecognizerErrorToLocalServiceIssue(.noAudioInput)
            == .noAudioInput
        )
        #expect(
            DictationController.mapRecognizerErrorToLocalServiceIssue(.foregroundActivationRequired)
            == .foregroundInstallRequired
        )
        #expect(
            DictationController.mapRecognizerErrorToLocalServiceIssue(.taskFailed)
            == .runtimeFailure
        )
        #expect(DictationController.mapRecognizerErrorToLocalServiceIssue(nil) == nil)
    }

    @Test func translationSourceLocaleUsesRecognizerSessionLocaleWhenAvailable() {
        #expect(
            DictationController.translationSourceLocaleIdentifier(
                recognizerLocaleIdentifier: "fr-FR",
                fallbackLocaleIdentifier: "en-US"
            ) == "fr-FR"
        )
    }

    @Test func translationSourceLocaleFallsBackWhenRecognizerLocaleMissingOrEmpty() {
        #expect(
            DictationController.translationSourceLocaleIdentifier(
                recognizerLocaleIdentifier: nil,
                fallbackLocaleIdentifier: "en-US"
            ) == "en-US"
        )
        #expect(
            DictationController.translationSourceLocaleIdentifier(
                recognizerLocaleIdentifier: "   ",
                fallbackLocaleIdentifier: "en-US"
            ) == "en-US"
        )
    }

    @Test func clipboardRestorePlanRestoresLocalPasteAndPreservesRemoteClipboard() {
        let localPlan = DictationController.clipboardRestorePlan(
            for: .responderChain,
            localDelay: 0.3
        )
        let remotePlan = DictationController.clipboardRestorePlan(
            for: .syntheticCommandV,
            localDelay: 0.3
        )

        #expect(localPlan.initialDelay == 0.3)
        #expect(localPlan.deferredDelay == nil)
        #expect(remotePlan.initialDelay == nil)
        #expect(remotePlan.deferredDelay == nil)
    }

    @Test func pasteboardRestoreGuardSkipsRestoreAfterUserClipboardChange() {
        #expect(
            DictationController.shouldRestorePasteboard(
                currentChangeCount: 4,
                expectedChangeCount: 4
            ) == true
        )
        #expect(
            DictationController.shouldRestorePasteboard(
                currentChangeCount: 5,
                expectedChangeCount: 4
            ) == false
        )
    }

    @Test func pasteboardSnapshotRestoresRichItemsWithoutLoss() {
        let richType = NSPasteboard.PasteboardType("com.yen.dictation.rich")
        let plistType = NSPasteboard.PasteboardType("com.yen.dictation.plist")
        let item = NSPasteboardItem()
        item.setString("hello", forType: .string)
        item.setData(Data([0xDE, 0xAD, 0xBE, 0xEF]), forType: richType)
        item.setPropertyList(["language": "en", "count": 2], forType: plistType)

        let restoredItems = DictationController.restoredPasteboardItemsForTesting([item])

        #expect(restoredItems?.count == 1)
        #expect(restoredItems?.first?.string(forType: .string) == "hello")
        #expect(restoredItems?.first?.data(forType: richType) == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let propertyList = restoredItems?.first?.propertyList(forType: plistType) as? [String: Any]
        #expect(propertyList?["language"] as? String == "en")
        #expect(propertyList?["count"] as? Int == 2)
    }

    @Test func clipboardRestoreSchedulerDefersRestoreUntilSecondScheduledStep() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("yen.dictation.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let previousSnapshot = DictationPasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let expectedChangeCount = pasteboard.changeCount

        var scheduled: [(TimeInterval, DictationClipboardRestoreScheduler.Action)] = []
        let scheduler = DictationClipboardRestoreScheduler { delay, action in
            scheduled.append((delay, action))
        }

        scheduler.scheduleRestore(
            plan: DictationController.ClipboardRestorePlan(initialDelay: 0.1, deferredDelay: 0.2),
            pasteboard: pasteboard,
            previousSnapshot: previousSnapshot,
            expectedChangeCount: expectedChangeCount
        )

        #expect(scheduled.map(\.0) == [0.1])
        scheduled.removeFirst().1()
        #expect(pasteboard.string(forType: .string) == "dictated")
        #expect(scheduled.map(\.0) == [0.2])
        scheduled.removeFirst().1()
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func clipboardRestoreSchedulerRestoresSingleStepPlanAfterInitialDelay() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("yen.dictation.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let previousSnapshot = DictationPasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let expectedChangeCount = pasteboard.changeCount

        var scheduled: [(TimeInterval, DictationClipboardRestoreScheduler.Action)] = []
        let scheduler = DictationClipboardRestoreScheduler { delay, action in
            scheduled.append((delay, action))
        }

        scheduler.scheduleRestore(
            plan: DictationController.ClipboardRestorePlan(initialDelay: 0.1, deferredDelay: nil),
            pasteboard: pasteboard,
            previousSnapshot: previousSnapshot,
            expectedChangeCount: expectedChangeCount
        )

        #expect(scheduled.map(\.0) == [0.1])
        scheduled.removeFirst().1()
        #expect(scheduled.isEmpty)
        #expect(pasteboard.string(forType: .string) == "previous")
    }

    @Test func clipboardRestoreSchedulerSkipsDeferredRestoreAfterUserClipboardChange() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("yen.dictation.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let previousSnapshot = DictationPasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated", forType: .string)
        let expectedChangeCount = pasteboard.changeCount

        var scheduled: [(TimeInterval, DictationClipboardRestoreScheduler.Action)] = []
        let scheduler = DictationClipboardRestoreScheduler { delay, action in
            scheduled.append((delay, action))
        }

        scheduler.scheduleRestore(
            plan: DictationController.ClipboardRestorePlan(initialDelay: 0.1, deferredDelay: 0.2),
            pasteboard: pasteboard,
            previousSnapshot: previousSnapshot,
            expectedChangeCount: expectedChangeCount
        )

        scheduled.removeFirst().1()
        pasteboard.clearContents()
        pasteboard.setString("user copied later", forType: .string)
        scheduled.removeFirst().1()

        #expect(pasteboard.string(forType: .string) == "user copied later")
    }

    @Test func insertionTargetGateRequiresStableCapturedTarget() {
        #expect(
            DictationController.insertionTargetGate(
                hasCapturedTarget: false,
                isCapturedTargetValid: false
            ) == .missingStableTarget
        )
        #expect(
            DictationController.insertionTargetGate(
                hasCapturedTarget: true,
                isCapturedTargetValid: false
            ) == .invalidatedTarget
        )
        #expect(
            DictationController.insertionTargetGate(
                hasCapturedTarget: true,
                isCapturedTargetValid: true
            ) == .ready
        )
    }

    @Test func pasteExecutionContractsFailClosedToManualRecovery() {
        #expect(
            DictationPasteExecutor.terminalSurfacePasteOutcome(surfaceAvailable: true)
            == .directSurfacePaste
        )
        #expect(
            DictationPasteExecutor.terminalSurfacePasteOutcome(surfaceAvailable: false)
            == .manualRecoveryRequired
        )
        #expect(
            DictationPasteExecutor.responderChainPasteOutcome(didPaste: true)
            == .responderChainPaste
        )
        #expect(
            DictationPasteExecutor.responderChainPasteOutcome(didPaste: false)
            == .manualRecoveryRequired
        )
        #expect(
            DictationPasteExecutor.syntheticCommandVPasteOutcome(createdEvents: true)
            == .remoteCommandVPaste
        )
        #expect(
            DictationPasteExecutor.syntheticCommandVPasteOutcome(createdEvents: false)
            == .manualRecoveryRequired
        )
    }

    @Test func secureInputSkipsPasteboardWriteAndReportsRecovery() async {
        let pasteboard = NSPasteboard.general
        let previousSnapshot = DictationPasteboardSnapshot.capture(from: pasteboard)
        defer {
            previousSnapshot.restore(to: pasteboard)
        }
        pasteboard.clearContents()
        pasteboard.setString("sentinel-before-secure-input", forType: .string)

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        recognizer.stopBehavior = { completion in
            completion(
                DictationRecognizerStopResult(
                    finalText: "private dictated transcript",
                    fallbackText: nil
                )
            )
        }
        var notices: [(String, String)] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            appIsActiveProvider: { false },
            frontmostApplicationPIDProvider: { 42 },
            frontmostApplicationFocusFingerprintProvider: { _ in 100 },
            secureEventInputProvider: { true },
            backgroundRecoveryReporter: { title, body in
                notices.append((title, body))
            }
        )

        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(pasteboard.string(forType: .string) == "sentinel-before-secure-input")
        #expect(notices.count == 1)
        #expect(notices.first?.0 == "YEN Dictation Blocked by Secure Input")
        #expect(notices.first?.1.contains("did not write the transcript") == true)
    }

    @Test func stopCompletionEventNameDifferentiatesInsertAndNoInsert() {
        #expect(
            DictationController.stopCompletionEventName(
                hasInsertionDecision: true
            ) == "stop_completion_ready_for_insert"
        )
        #expect(
            DictationController.stopCompletionEventName(
                hasInsertionDecision: false
            ) == "stop_completion_without_insert"
        )
    }

    @Test func insertSessionEventNameUsesDedicatedManualRecoveryEvent() {
        #expect(
            DictationController.insertSessionEventName(
                for: .directSurfacePaste
            ) == "insert_completed"
        )
        #expect(
            DictationController.insertSessionEventName(
                for: .responderChainPaste
            ) == "insert_completed"
        )
        #expect(
            DictationController.insertSessionEventName(
                for: .remoteCommandVPaste
            ) == "insert_completed"
        )
        #expect(
            DictationController.insertSessionEventName(
                for: .manualRecoveryRequired
            ) == "insert_manual_recovery_required"
        )
    }

    @Test func capturedLocalInsertionTargetRequiresSameWindowAndResponder() {
        let responder = NSObject()
        let otherResponder = NSObject()
        let descriptor = DictationController.CapturedInsertionTargetDescriptor.responderChain(
            windowNumber: 7,
            responderIdentifier: ObjectIdentifier(responder)
        )

        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: true,
                    windowNumber: 7,
                    firstResponderIdentifier: ObjectIdentifier(responder),
                    frontmostProcessIdentifier: nil,
                    frontmostFocusFingerprint: nil
                )
            ) == true
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: true,
                    windowNumber: 8,
                    firstResponderIdentifier: ObjectIdentifier(responder),
                    frontmostProcessIdentifier: nil,
                    frontmostFocusFingerprint: nil
                )
            ) == false
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: true,
                    windowNumber: 7,
                    firstResponderIdentifier: ObjectIdentifier(otherResponder),
                    frontmostProcessIdentifier: nil,
                    frontmostFocusFingerprint: nil
                )
            ) == false
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: false,
                    windowNumber: 7,
                    firstResponderIdentifier: ObjectIdentifier(responder),
                    frontmostProcessIdentifier: 42,
                    frontmostFocusFingerprint: nil
                )
            ) == false
        )
    }

    @Test func capturedRemoteInsertionTargetRequiresSameFrontmostProcess() {
        let descriptor = DictationController.CapturedInsertionTargetDescriptor.syntheticCommandV(
            frontmostProcessIdentifier: 42,
            focusFingerprint: 100
        )

        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: false,
                    windowNumber: nil,
                    firstResponderIdentifier: nil,
                    frontmostProcessIdentifier: 42,
                    frontmostFocusFingerprint: 100
                )
            ) == true
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: false,
                    windowNumber: nil,
                    firstResponderIdentifier: nil,
                    frontmostProcessIdentifier: 42,
                    frontmostFocusFingerprint: 101
                )
            ) == false
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: false,
                    windowNumber: nil,
                    firstResponderIdentifier: nil,
                    frontmostProcessIdentifier: 7,
                    frontmostFocusFingerprint: 100
                )
            ) == false
        )
        #expect(
            DictationController.isCapturedInsertionTargetValid(
                descriptor,
                currentState: DictationController.InsertionValidationState(
                    isYENActive: true,
                    windowNumber: 3,
                    firstResponderIdentifier: nil,
                    frontmostProcessIdentifier: 42,
                    frontmostFocusFingerprint: 100
                )
            ) == false
        )
    }

    @Test func syntheticCommandVPrePostGateRequiresSameFrontmostProcessAtPostTime() {
        #expect(
            DictationPasteExecutor.shouldPostSyntheticCommandV(
                capturedFrontmostProcessIdentifier: 42,
                currentFrontmostProcessIdentifier: 42,
                isYENActive: false
            ) == true
        )
        #expect(
            DictationPasteExecutor.shouldPostSyntheticCommandV(
                capturedFrontmostProcessIdentifier: 42,
                currentFrontmostProcessIdentifier: 99,
                isYENActive: false
            ) == false
        )
        #expect(
            DictationPasteExecutor.shouldPostSyntheticCommandV(
                capturedFrontmostProcessIdentifier: 42,
                currentFrontmostProcessIdentifier: nil,
                isYENActive: false
            ) == false
        )
        #expect(
            DictationPasteExecutor.shouldPostSyntheticCommandV(
                capturedFrontmostProcessIdentifier: 42,
                currentFrontmostProcessIdentifier: 42,
                isYENActive: true
            ) == false
        )
    }

    @Test func stopRequestCapturesRemoteInsertionTargetAtHotkeyReleaseTime() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var frontmostPID: pid_t? = 42
        var focusFingerprint: Int? = 100
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            appIsActiveProvider: { false },
            frontmostApplicationPIDProvider: { frontmostPID },
            frontmostApplicationFocusFingerprintProvider: { _ in focusFingerprint }
        )

        controller.handleHotkeyDown()
        #expect(controller.testingSessionState == .listening)

        controller.handleHotkeyUp()
        #expect(
            controller.testingPendingInsertionTargetDescriptor
                == .syntheticCommandV(frontmostProcessIdentifier: 42, focusFingerprint: 100)
        )

        frontmostPID = 99
        focusFingerprint = 200
        #expect(
            controller.testingPendingInsertionTargetDescriptor
                == .syntheticCommandV(frontmostProcessIdentifier: 42, focusFingerprint: 100)
        )
    }

    @Test func stopRequestCapturesProcessOnlyRemoteInsertionTargetWhenFocusIsUnreadable() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var frontmostPID: pid_t? = 42
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            appIsActiveProvider: { false },
            frontmostApplicationPIDProvider: { frontmostPID },
            frontmostApplicationFocusedElementProvider: { _ in nil },
            frontmostApplicationFocusFingerprintProvider: { _ in nil }
        )

        controller.handleHotkeyDown()
        #expect(controller.testingSessionState == .listening)

        controller.handleHotkeyUp()
        #expect(controller.testingPendingInsertionTargetDescriptor != nil)
        #expect(controller.testingValidatePendingInsertionTarget() == true)

        frontmostPID = 99
        #expect(controller.testingValidatePendingInsertionTarget() == false)
    }

    @Test func insertionRestoresLocalPasteButSkipsInvalidatedLocalTargetSnapshot() throws {
        let pasteboard = NSPasteboard.general
        let original = DictationPasteboardSnapshot.capture(from: pasteboard)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        window.contentView = editor
        defer {
            window.close()
            original.restore(to: pasteboard)
        }
        #expect(window.makeFirstResponder(editor))
        var snapshots = 0
        var failures = 0
        var restoreActions: [DictationClipboardRestoreScheduler.Action] = []
        let insertion = DictationInsertionCoordinator(
            clipboardRestoreScheduler: DictationClipboardRestoreScheduler { delay, action in
                #expect(delay == 0.3)
                restoreActions.append(action)
            },
            transcriptInserter: nil,
            appIsActiveProvider: { true },
            frontmostApplicationPIDProvider: { nil },
            frontmostApplicationFocusedElementProvider: { _ in nil },
            frontmostApplicationFocusFingerprintProvider: { _ in nil },
            secureEventInputProvider: { false },
            syntheticEventSource: nil,
            capturePasteboardSnapshot: { board in
                snapshots += 1
                return DictationPasteboardSnapshot.capture(from: board)
            },
            responderWindowProvider: { window },
            pasteThroughResponderChain: {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: editor, from: nil)
            }
        )
        let target = try #require(insertion.captureInsertionTarget())
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        let outcome = insertion.performTranscriptInsertion("local transcript", insertionTarget: target) { _ in failures += 1 }
        #expect(outcome == .responderChainPaste)
        #expect(editor.string == "local transcript")
        #expect(snapshots == 1)
        #expect(restoreActions.count == 1)
        let restore = try #require(restoreActions.first)
        restore()
        #expect(pasteboard.string(forType: .string) == "original clipboard")

        #expect(window.makeFirstResponder(nil))
        let staleOutcome = insertion.performTranscriptInsertion("stale target transcript", insertionTarget: target) { _ in failures += 1 }
        #expect(staleOutcome == .manualRecoveryRequired)
        #expect(pasteboard.string(forType: .string) == "stale target transcript")
        #expect(snapshots == 1)
        #expect(failures == 1)
        #expect(restoreActions.count == 1)
    }

    @Test func insertionSkipsClipboardSnapshotWhenNoLocalRestoreIsPossible() {
        let pasteboard = NSPasteboard.general
        let original = DictationPasteboardSnapshot.capture(from: pasteboard)
        defer { original.restore(to: pasteboard) }
        var pid: pid_t? = 42
        var snapshots = 0
        var failures = 0
        var restores = 0
        let insertion = DictationInsertionCoordinator(
            clipboardRestoreScheduler: DictationClipboardRestoreScheduler { _, _ in restores += 1 },
            transcriptInserter: nil,
            appIsActiveProvider: { false },
            frontmostApplicationPIDProvider: { pid },
            frontmostApplicationFocusedElementProvider: { _ in nil },
            frontmostApplicationFocusFingerprintProvider: { _ in nil },
            secureEventInputProvider: { false },
            syntheticEventSource: nil,
            capturePasteboardSnapshot: { board in
                snapshots += 1
                return DictationPasteboardSnapshot.capture(from: board)
            }
        )
        let remoteTarget = insertion.captureInsertionTarget()
        #expect(remoteTarget != nil)
        pid = 99
        let remoteOutcome = insertion.performTranscriptInsertion("remote transcript", insertionTarget: remoteTarget) { _ in failures += 1 }
        #expect(remoteOutcome == .manualRecoveryRequired)
        #expect(pasteboard.string(forType: .string) == "remote transcript")
        let missingOutcome = insertion.performTranscriptInsertion("missing target transcript", insertionTarget: nil) { _ in failures += 1 }
        #expect(missingOutcome == .manualRecoveryRequired)
        #expect(pasteboard.string(forType: .string) == "missing target transcript")
        #expect(failures == 2)
        #expect(restores == 0)
        #expect(snapshots == 0)
    }

    @Test func remoteInsertionValidationUsesFocusedElementEqualityWhenAvailable() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var currentFocusedElement: AXUIElement? = AXUIElementCreateApplication(42)
        var focusFingerprint: Int? = 100
        var fingerprintReads = 0
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            appIsActiveProvider: { false },
            frontmostApplicationPIDProvider: { 42 },
            frontmostApplicationFocusedElementProvider: { _ in currentFocusedElement },
            frontmostApplicationFocusFingerprintProvider: { _ in
                fingerprintReads += 1
                return focusFingerprint
            }
        )

        controller.handleHotkeyDown()
        #expect(controller.testingSessionState == .listening)

        controller.handleHotkeyUp()
        #expect(controller.testingPendingInsertionTargetHasFocusedElement == true)

        focusFingerprint = 999
        #expect(controller.testingValidatePendingInsertionTarget() == true)

        currentFocusedElement = AXUIElementCreateApplication(99)
        #expect(controller.testingValidatePendingInsertionTarget() == false)

        currentFocusedElement = nil
        focusFingerprint = 100
        #expect(controller.testingValidatePendingInsertionTarget() == false)
        #expect(fingerprintReads == 0)
    }

    @Test func legacySystemDictationEnabledUsesHitoolboxPreferenceWhenPresent() {
        let enabled = DictationController.legacySystemDictationEnabled(
            hitoolboxDomain: ["DictationIMMasterDictationEnabled": 1],
            assistantDomain: ["Dictation Enabled": 0]
        )
        let disabled = DictationController.legacySystemDictationEnabled(
            hitoolboxDomain: ["DictationIMMasterDictationEnabled": 0],
            assistantDomain: ["Dictation Enabled": 1]
        )

        #expect(enabled == true)
        #expect(disabled == false)
    }

    @Test func legacySystemDictationEnabledFallsBackToAssistantDomain() {
        let enabled = DictationController.legacySystemDictationEnabled(
            hitoolboxDomain: [:],
            assistantDomain: ["Dictation Enabled": "on"]
        )
        let disabled = DictationController.legacySystemDictationEnabled(
            hitoolboxDomain: nil,
            assistantDomain: ["DictationEnabled": "off"]
        )

        #expect(enabled == true)
        #expect(disabled == false)
    }

    @Test func legacySystemDictationEnabledReturnsNilWhenNoSupportedKeysExist() {
        let unknown = DictationController.legacySystemDictationEnabled(
            hitoolboxDomain: ["Unrelated": 1],
            assistantDomain: ["Nope": true]
        )
        #expect(unknown == nil)
    }

    @Test func localeChangeActionDefersRefreshUntilSessionEndWhenLegacyRecognizerActive() {
        #expect(
            DictationRecognizer.localeChangeAction(hasActiveSession: true) == .deferUntilSessionEnd
        )
        #expect(
            DictationRecognizer.localeChangeAction(hasActiveSession: false) == .refreshImmediately
        )
    }

    @Test func speechAnalyzerResultErrorsAreSuppressedOnlyForStopOrCancellation() {
        guard #available(macOS 26, *) else { return }
        #expect(
            SpeechAnalyzerRecognizer.shouldSurfaceResultStreamError(
                isTaskCancelled: false,
                isStopping: false
            ) == true
        )
        #expect(
            SpeechAnalyzerRecognizer.shouldSurfaceResultStreamError(
                isTaskCancelled: true,
                isStopping: false
            ) == false
        )
        #expect(
            SpeechAnalyzerRecognizer.shouldSurfaceResultStreamError(
                isTaskCancelled: false,
                isStopping: true
            ) == false
        )
    }

    @Test func speechAnalyzerStopListeningPathSeparatesStartupImmediateDeliveryAndFinalize() {
        guard #available(macOS 26, *) else { return }

        #expect(
            SpeechAnalyzerRecognizer.stopListeningPath(
                hasActiveAudioPipeline: false,
                resultsTaskCompleted: false
            ) == .startupDidNotReachActivePipeline
        )
        #expect(
            SpeechAnalyzerRecognizer.stopListeningPath(
                hasActiveAudioPipeline: true,
                resultsTaskCompleted: true
            ) == .completedResultsReadyForImmediateDelivery
        )
        #expect(
            SpeechAnalyzerRecognizer.stopListeningPath(
                hasActiveAudioPipeline: true,
                resultsTaskCompleted: false
            ) == .finalizePendingAudio
        )
    }

    @Test func speechAnalyzerStopResultKeepsVolatileTailOutOfAuthoritativeFinalText() {
        guard #available(macOS 26, *) else { return }

        let result = SpeechAnalyzerRecognizer.makeStopResult(
            finalizedText: "final text",
            volatileText: "preview tail"
        )

        #expect(result.finalText == "final text")
        #expect(result.fallbackText == "final text preview tail")

        let finalOnly = SpeechAnalyzerRecognizer.makeStopResult(
            finalizedText: "final text",
            volatileText: ""
        )
        #expect(finalOnly.finalText == "final text")
        #expect(finalOnly.fallbackText == nil)

        let previewOnly = SpeechAnalyzerRecognizer.makeStopResult(
            finalizedText: "",
            volatileText: "preview tail"
        )
        #expect(previewOnly.finalText == nil)
        #expect(previewOnly.fallbackText == "preview tail")
    }

    @Test func speechAnalyzerAudioConversionErrorsBecomeRecoverableRecognizerFailures() {
        guard #available(macOS 26, *) else { return }

        #expect(
            SpeechAnalyzerRecognizer.didAudioConversionFail(status: .error)
        )
        #expect(
            SpeechAnalyzerRecognizer.didAudioConversionFail(status: .haveData) == false
        )
    }

    @Test func speechAnalyzerFragmentMergeAvoidsExtraSpaceBeforePunctuation() {
        guard #available(macOS 26, *) else { return }

        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("hello", "world")
            == "hello world"
        )
        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("hello", "!")
            == "hello!"
        )
        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("hello,", "world")
            == "hello, world"
        )
        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("it", "'s")
            == "it's"
        )
        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("你好", "世界")
            == "你好世界"
        )
        #expect(
            SpeechAnalyzerRecognizer.mergeTranscriptFragments("テスト", "です")
            == "テストです"
        )
    }

    @Test func legacyRecognizerStopResultKeepsPreviewOutOfAuthoritativeFinalText() {
        let previewOnly = DictationRecognizer.makeStopResult(
            finalTranscript: "",
            previewTranscript: "partial text"
        )
        #expect(previewOnly.finalText == nil)
        #expect(previewOnly.fallbackText == "partial text")

        let finalized = DictationRecognizer.makeStopResult(
            finalTranscript: "final text",
            previewTranscript: "final text"
        )
        #expect(finalized.finalText == "final text")
        #expect(finalized.fallbackText == nil)

        let trimmed = DictationRecognizer.makeStopResult(
            finalTranscript: "  final text  ",
            previewTranscript: "\nfinal text\n"
        )
        #expect(trimmed.finalText == "final text")
        #expect(trimmed.fallbackText == nil)
    }

    @Test func activeCaptureSessionDetectionMatchesLifecycleFlags() {
        #expect(
            DictationController.hasActiveCaptureSession(
                pendingStart: false,
                isListening: false,
                isStopping: false
            ) == false
        )
        #expect(
            DictationController.hasActiveCaptureSession(
                pendingStart: true,
                isListening: false,
                isStopping: false
            ) == true
        )
        #expect(
            DictationController.hasActiveCaptureSession(
                pendingStart: false,
                isListening: true,
                isStopping: false
            ) == true
        )
        #expect(
            DictationController.hasActiveCaptureSession(
                pendingStart: false,
                isListening: false,
                isStopping: true
            ) == true
        )
    }

    @Test func revocationNoticeOnlyTriggersForActiveGrantedToBlockedTransition() {
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: nil,
                current: [.microphone],
                hasActiveCaptureSession: true
            ) == false
        )
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: [],
                current: [],
                hasActiveCaptureSession: true
            ) == false
        )
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: [],
                current: [.microphone],
                hasActiveCaptureSession: false
            ) == false
        )
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: [],
                current: [.microphone],
                hasActiveCaptureSession: true
            ) == true
        )
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: [.microphone],
                current: [.microphone],
                hasActiveCaptureSession: true
            ) == false
        )
        #expect(
            DictationController.shouldShowRevocationNotice(
                previous: [.microphone],
                current: [],
                hasActiveCaptureSession: true
            ) == false
        )
    }

    @Test func permissionRevocationHardTeardownRequiresActiveCaptureOrStopPhase() {
        #expect(
            DictationController.shouldHardTeardownForPermissionRevocation(
                previous: nil,
                current: [.microphone],
                hasActiveCaptureSession: true
            ) == false
        )
        #expect(
            DictationController.shouldHardTeardownForPermissionRevocation(
                previous: [],
                current: [],
                hasActiveCaptureSession: true
            ) == false
        )
        #expect(
            DictationController.shouldHardTeardownForPermissionRevocation(
                previous: [],
                current: [.microphone],
                hasActiveCaptureSession: false
            ) == false
        )
        #expect(
            DictationController.shouldHardTeardownForPermissionRevocation(
                previous: [],
                current: [.microphone],
                hasActiveCaptureSession: true
            ) == true
        )
    }

    @Test func transcriptFallbackIsAllowedWhenRecognizerMarksNormalStopAsFailed() {
        #expect(
            DictationController.transcriptForInsertion(
                stopResult: DictationRecognizerStopResult(
                    finalText: nil,
                    fallbackText: "partial text",
                    stopMarkedAsFailure: true
                ),
                fallbackTranscript: nil,
                stopCause: .hotkeyRelease
            ) == DictationController.TranscriptInsertionDecision(
                text: "partial text",
                source: .fallback
            )
        )
    }

    @Test func captureSessionCoordinatorQueuesRestartWhenHotkeyRepressesDuringStop() {
        var coordinator = DictationCaptureSessionCoordinator(
            activeSessionID: UUID(),
            pendingStart: false,
            isListening: false,
            stopSession: .init(
                token: UUID(),
                sessionID: UUID(),
                stopCause: .hotkeyRelease,
                stopRequestedAt: 10,
                restartRequested: false
            )
        )

        #expect(coordinator.beginStartRequest() == .queueRestartAfterStop)
        #expect(coordinator.stopSession?.restartRequested == true)
    }

    @Test func captureSessionCoordinatorBeginStartRequestTracksPendingSession() {
        var coordinator = DictationCaptureSessionCoordinator()

        let action = coordinator.beginStartRequest()

        guard case .beginPermissionCheck(let sessionID) = action else {
            Issue.record("Expected beginPermissionCheck action")
            return
        }

        #expect(coordinator.pendingStart == true)
        #expect(coordinator.activeSessionID == sessionID)
        #expect(coordinator.isListening == false)
        #expect(coordinator.stopSession == nil)
    }

    @Test func captureSessionCoordinatorCancelPendingStartClearsSessionState() {
        let sessionID = UUID()
        var coordinator = DictationCaptureSessionCoordinator(
            activeSessionID: sessionID,
            pendingStart: true,
            isListening: false,
            stopSession: nil
        )

        #expect(coordinator.cancelPendingStartOnStopRequest() == sessionID)
        #expect(coordinator.pendingStart == false)
        #expect(coordinator.activeSessionID == nil)
        #expect(coordinator.isListening == false)
    }

    @Test func captureSessionCoordinatorStopCompletionPreservesInsertionTailAndRequestsRestart() {
        let sessionID = UUID()
        let token = UUID()
        var coordinator = DictationCaptureSessionCoordinator(
            activeSessionID: sessionID,
            pendingStart: false,
            isListening: true,
            stopSession: .init(
                token: token,
                sessionID: sessionID,
                stopCause: .hotkeyRelease,
                stopRequestedAt: 25,
                restartRequested: true
            )
        )

        let outcome = coordinator.completeStop(
            token: token,
            stopResult: DictationRecognizerStopResult(
                finalText: "final text",
                fallbackText: "final text preview tail"
            ),
            fallbackTranscript: "final text preview tail",
            hotkeyStillPressed: true
        )

        #expect(outcome?.insertionDecision == DictationController.TranscriptInsertionDecision(
            text: "final text",
            source: .final
        ))
        #expect(outcome?.shouldRestart == true)
        #expect(coordinator.activeSessionID == sessionID)
        #expect(coordinator.isListening == false)
        #expect(coordinator.stopSession == nil)
    }

    @Test func captureSessionCoordinatorWatchdogRequiresMatchingStopToken() {
        let token = UUID()
        var coordinator = DictationCaptureSessionCoordinator(
            activeSessionID: UUID(),
            pendingStart: false,
            isListening: true,
            stopSession: .init(
                token: token,
                sessionID: UUID(),
                stopCause: .hotkeyRelease,
                stopRequestedAt: 50,
                restartRequested: false
            )
        )

        #expect(coordinator.markWatchdogTriggered(token: UUID()) == false)
        #expect(coordinator.stopSession?.stopCause == .hotkeyRelease)
        #expect(coordinator.markWatchdogTriggered(token: token) == true)
        #expect(coordinator.stopSession?.stopCause == .watchdog)
    }

    @Test func captureSessionCoordinatorPermissionRefreshDistinguishesActiveAndIdleStates() {
        let currentMissing: [DictationController.PrivacyDestination] = [.microphone]
        let idleCoordinator = DictationCaptureSessionCoordinator()
        let activeCoordinator = DictationCaptureSessionCoordinator(
            activeSessionID: UUID(),
            pendingStart: false,
            isListening: true,
            stopSession: nil
        )

        let idleOutcome = idleCoordinator.permissionRefreshOutcome(
            previousMissing: [],
            currentMissing: currentMissing
        )
        let activeOutcome = activeCoordinator.permissionRefreshOutcome(
            previousMissing: [],
            currentMissing: currentMissing
        )

        #expect(idleOutcome.shouldHardTeardown == false)
        #expect(idleOutcome.shouldShowRevocationNotice == false)
        #expect(activeOutcome.shouldHardTeardown == true)
        #expect(activeOutcome.shouldShowRevocationNotice == true)
    }

    @Test func headlessControllerShortUtteranceFastPathInsertsImmediately() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        recognizer.stopBehavior = { completion in
            completion(
                DictationRecognizerStopResult(
                    finalText: "final text",
                    fallbackText: nil
                )
            )
        }
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(recognizer.startCallCount == 1)
        #expect(recognizer.stopCallCount == 1)
        #expect(insertedTexts == ["final text"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerPassthroughInsertionCompletesWithoutQueueDrain() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        recognizer.stopBehavior = { completion in
            completion(
                DictationRecognizerStopResult(
                    finalText: "instant text",
                    fallbackText: nil
                )
            )
        }
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            translationPostProcessor: DictationTranslationPostProcessor(
                engine: FakeTranslationEngine(
                    availabilityResult: .installed,
                    translateImpl: { text, _, _ in
                        try await Task.sleep(nanoseconds: 200_000_000)
                        return "\(text)-translated"
                    }
                ),
                isTranslationSupported: { true },
                translateOnDictateEnabled: { false },
                targetLanguageIdentifier: { "es" },
                translationTimeoutNanoseconds: 20_000_000
            ),
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        controller.handleHotkeyUp()

        #expect(insertedTexts == ["instant text"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func passthroughInsertionIsImmediateAfterTranslatedQueueDrains() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var translationEnabled = true
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            translationPostProcessor: DictationTranslationPostProcessor(
                engine: FakeTranslationEngine(availabilityResult: .installed, translateImpl: fakeTranslateToHolaMundo),
                isTranslationSupported: { true },
                translateOnDictateEnabled: { translationEnabled },
                targetLanguageIdentifier: { "es" }
            ),
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )
        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "hello world", fallbackText: nil))
        await controller.waitForInsertionQueueDrainForTesting()
        #expect(insertedTexts == ["hola mundo"])

        translationEnabled = false
        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "instant follow-up", fallbackText: nil))
        #expect(insertedTexts == ["hola mundo", "instant follow-up"])
        #expect(controller.testingSessionState == .idle)
        await controller.waitForInsertionQueueDrainForTesting()
    }

    @Test func earlierInsertionCompletionCannotClearNewerQueuedWork() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let firstGate = SequencedTranslationCoordinator(firstResult: "uno", laterResults: [])
        let secondGate = SequencedTranslationCoordinator(firstResult: "dos", laterResults: [])
        var translationEnabled = true
        var insertedTexts: [String] = []
        let insertionEvents = AsyncStream<Void>.makeStream()
        defer { insertionEvents.continuation.finish() }
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            translationPostProcessor: DictationTranslationPostProcessor(
                engine: FakeTranslationEngine(availabilityResult: .installed, translateImpl: { text, _, _ in
                    if text == "one" { return try await firstGate.translate(text: text) }
                    return try await secondGate.translate(text: text)
                }),
                isTranslationSupported: { true },
                translateOnDictateEnabled: { translationEnabled },
                targetLanguageIdentifier: { "es" }
            ),
            transcriptInserter: { text in
                insertedTexts.append(text)
                insertionEvents.continuation.yield(())
                return .responderChainPaste
            }
        )
        func submit(_ text: String) {
            controller.handleHotkeyDown()
            controller.handleHotkeyUp()
            recognizer.deliverStop(.init(finalText: text, fallbackText: nil))
        }
        submit("one")
        submit("two")
        await firstGate.resumeFirst()
        var events = insertionEvents.stream.makeAsyncIterator()
        _ = await events.next()
        #expect(insertedTexts == ["uno"])

        translationEnabled = false
        submit("three")
        #expect(insertedTexts == ["uno"])
        await secondGate.resumeFirst()
        await controller.waitForInsertionQueueDrainForTesting()
        #expect(insertedTexts == ["uno", "dos", "three"])
        #expect(controller.testingSessionState == .idle)
    }

    @Test func headlessControllerIgnoresDuplicateStopCompletionAfterNormalRelease() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "first result", fallbackText: nil))
        await controller.waitForInsertionQueueDrainForTesting()

        recognizer.replayLastStop(.init(finalText: "duplicate result", fallbackText: nil))

        #expect(insertedTexts == ["first result"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
    }

    @Test func headlessControllerSkipsLegacyTimeoutForSpeechAnalyzerSessions() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var scheduledTimeouts: [TimeInterval] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            maxDurationScheduler: { interval, _ in
                scheduledTimeouts.append(interval)
                return DictationController.ScheduledWork(cancelImpl: {})
            }
        )

        controller.handleHotkeyDown()

        #expect(recognizer.startCallCount == 1)
        #expect(scheduledTimeouts.isEmpty)
        #expect(controller.testingSessionState == .listening)
    }

    @Test func headlessControllerWaitsForRecognizerReadyBeforeListening() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        recognizer.autoReady = false
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.handleHotkeyDown()

        #expect(recognizer.startCallCount == 1)
        #expect(controller.testingSessionState == .starting)
        #expect(controller.testingPendingStart == true)

        recognizer.emitReady()

        #expect(controller.testingSessionState == .listening)
        #expect(controller.testingPendingStart == false)
    }

    @Test func headlessControllerDisablingLivePreviewRevertsOverlayToListeningImmediately() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("preview text")

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview text")

        DictationPreviewPreferences.liveTranscriptEnabled = false
        await Task.yield()
        await Task.yield()

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayListeningLine)
    }

    @Test func headlessControllerEnablingLivePreviewShowsLatestPartialImmediately() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = false
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("preview text")

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayListeningLine)

        DictationPreviewPreferences.liveTranscriptEnabled = true
        await Task.yield()
        await Task.yield()

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview text")
    }

    @Test func headlessControllerPausedHotkeyAttemptShowsPausedOverlayWithoutStartingCapture() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.setPausedForTesting(true)
        defer {
            controller.setPausedForTesting(false)
        }

        controller.handleHotkeyDown()

        #expect(recognizer.startCallCount == 0)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.pausedAttemptOverlayLine)
    }

    @Test func headlessControllerNormalizesLivePreviewBeforeRendering() {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("  preview text  \n")

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview text")
    }

    @Test func headlessControllerSuppressesWhitespaceOnlyAndEquivalentLivePreviewFrames() {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.handleHotkeyDown()
        let listeningUpdateCount = controller.testingOverlayUpdateCount

        recognizer.emitPartial("preview text")
        let firstPreviewUpdateCount = controller.testingOverlayUpdateCount

        #expect(firstPreviewUpdateCount == listeningUpdateCount + 1)
        #expect(controller.testingOverlayText == "preview text")

        recognizer.emitPartial("preview text")
        recognizer.emitPartial("  preview text  \n")
        recognizer.emitPartial("  \n\t ")

        #expect(controller.testingOverlayUpdateCount == firstPreviewUpdateCount)
        #expect(controller.testingOverlayText == "preview text")
    }

    @Test func previewPipelineReadsRenderPermissionOncePerSubmittedOrDeferredFrame() throws {
        var timestamp: CFAbsoluteTime = 100
        var permissionReads = 0
        var rendered: [String] = []
        var scheduled: [DispatchWorkItem] = []
        let preview = DictationLivePreviewController(
            minimumInterval: 0.2,
            canRender: { permissionReads += 1; return true },
            render: { rendered.append($0) },
            now: { timestamp },
            schedule: { _, work in scheduled.append(work) }
        )
        preview.queue(normalizedText: "first")
        #expect(permissionReads == 1)
        #expect(rendered == ["first"])
        timestamp = 100.01
        preview.queue(normalizedText: "second")
        preview.queue(normalizedText: "latest")
        #expect(permissionReads == 3)
        #expect(scheduled.count == 1)
        timestamp = 100.21
        let work = try #require(scheduled.first)
        work.perform()
        #expect(permissionReads == 4)
        #expect(rendered == ["first", "latest"])
    }

    @Test func previewPipelineRejectsDisabledDeferredFrameAndCancelsResetWork() throws {
        var timestamp: CFAbsoluteTime = 100
        var enabled = true
        var rendered: [String] = []
        var scheduled: [DispatchWorkItem] = []
        let preview = DictationLivePreviewController(
            minimumInterval: 0.2,
            canRender: { enabled },
            render: { rendered.append($0) },
            now: { timestamp },
            schedule: { _, work in scheduled.append(work) }
        )
        preview.queue(normalizedText: "first")
        preview.queue(normalizedText: "disabled pending")
        enabled = false
        timestamp = 100.21
        let disabledWork = try #require(scheduled.first)
        disabledWork.perform()
        #expect(rendered == ["first"])

        enabled = true
        preview.reset()
        preview.queue(normalizedText: "new session")
        preview.queue(normalizedText: "canceled pending")
        let canceledWork = try #require(scheduled.last)
        preview.reset()
        #expect(canceledWork.isCancelled)
        canceledWork.perform()
        #expect(rendered == ["first", "new session"])
    }

    @Test func headlessControllerDropsQueuedPreviewWhenLatestPartialMatchesRenderedText() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer { DictationPreviewPreferences.liveTranscriptEnabled = originalPreference }
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            livePreviewMinimumInterval: 0.05
        )
        controller.handleHotkeyDown()
        recognizer.emitPartial("current text")
        let renderedCount = controller.testingOverlayUpdateCount
        recognizer.emitPartial("superseded text")
        recognizer.emitPartial("current text")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(controller.testingOverlayText == "current text")
        #expect(controller.testingOverlayUpdateCount == renderedCount)
    }

    @Test func headlessControllerCoalescesRapidLivePreviewFramesWithinThrottleWindow() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            livePreviewMinimumInterval: 0.2
        )

        controller.handleHotkeyDown()
        let listeningUpdateCount = controller.testingOverlayUpdateCount

        recognizer.emitPartial("preview one")

        #expect(controller.testingOverlayUpdateCount == listeningUpdateCount + 1)
        #expect(controller.testingOverlayText == "preview one")

        recognizer.emitPartial("preview two")
        recognizer.emitPartial("preview three")
        recognizer.emitPartial("preview latest")

        #expect(controller.testingOverlayUpdateCount == listeningUpdateCount + 1)
        #expect(controller.testingOverlayText == "preview one")

        try? await Task.sleep(nanoseconds: 300_000_000)
        await Task.yield()

        #expect(controller.testingOverlayUpdateCount == listeningUpdateCount + 2)
        #expect(controller.testingOverlayText == "preview latest")
    }

    @Test func headlessControllerKeepsProcessingOverlayStableDuringTranslatedInsertion() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let translationCoordinator = SequencedTranslationCoordinator(
            firstResult: "translated tail",
            laterResults: []
        )
        let postProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, source, target in
                    try await translationCoordinator.translate(text: text)
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" }
        )
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            translationPostProcessor: postProcessor,
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("live preview")

        #expect(controller.testingOverlayText == "live preview")

        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "tail text", fallbackText: nil))
        await Task.yield()

        #expect(controller.testingSessionState == .inserting)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        let processingUpdateCount = controller.testingOverlayUpdateCount

        await translationCoordinator.resumeFirst()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["translated tail"])
        #expect(controller.testingOverlayUpdateCount == processingUpdateCount)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerKeepsProcessingOverlayStableWhenTranslationAssetsAreMissing() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let postProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityImpl: { _, _ in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    return .supported
                },
                translateImpl: { _, _, _ in
                    Issue.record("Translation should not run when assets are not installed")
                    return "unexpected"
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" }
        )
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            translationPostProcessor: postProcessor,
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("live preview")

        #expect(controller.testingOverlayText == "live preview")

        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "tail text", fallbackText: nil))
        await Task.yield()

        #expect(controller.testingSessionState == .inserting)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        let processingUpdateCount = controller.testingOverlayUpdateCount

        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["tail text"])
        #expect(controller.testingOverlayUpdateCount == processingUpdateCount)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerRuntimeFallbackCompletesErroredSessionWithoutStoppingLegacyRecognizer() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let speechAnalyzerRecognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let legacyRecognizer = FakeDictationRecognizer(requiresSessionTimeout: true)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: speechAnalyzerRecognizer,
            legacyRecognizer: legacyRecognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        speechAnalyzerRecognizer.emitPartial("fallback preview")

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "fallback preview")

        speechAnalyzerRecognizer.emitError(.recognizerIsUnavailable)
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(speechAnalyzerRecognizer.cancelCallCount == 1)
        #expect(speechAnalyzerRecognizer.stopCallCount == 0)
        #expect(legacyRecognizer.stopCallCount == 0)
        #expect(insertedTexts == ["fallback preview"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)

        controller.handleHotkeyDown()

        #expect(legacyRecognizer.startCallCount == 1)
        #expect(speechAnalyzerRecognizer.startCallCount == 1)
        #expect(controller.testingSessionState == .listening)
    }

    @Test func headlessControllerDoesNotMaterializeLegacyRecognizerWithoutFallback() {
        // The legacy SFSpeechRecognizer is only ever read by activateLegacyRecognizerFallback,
        // so a controller that is not injected a legacy recognizer and never falls back must
        // never construct one — the macOS 26 optimization that defers its SFSpeechRecognizer
        // and process-lifetime locale observer until fallback actually runs.
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let controller = makeHeadlessDictationController(recognizer: recognizer, legacyRecognizer: nil)
        #expect(controller.testingLegacyRecognizerMaterialized == false)
    }

    @Test func headlessControllerDefersStartupReadinessFallbackUntilIdle() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let speechAnalyzerRecognizer = FakeDictationRecognizer(
            requiresSessionTimeout: false,
            startupIssueValue: .recognizerIsUnavailable
        )
        let legacyRecognizer = FakeDictationRecognizer(requiresSessionTimeout: true)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: speechAnalyzerRecognizer,
            legacyRecognizer: legacyRecognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        speechAnalyzerRecognizer.emitPartial("preview text")
        controller.refreshPermissionStateForTesting()

        #expect(speechAnalyzerRecognizer.cancelCallCount == 0)
        #expect(legacyRecognizer.startCallCount == 0)
        #expect(controller.testingSessionState == .listening)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview text")

        controller.handleHotkeyUp()
        speechAnalyzerRecognizer.deliverStop(.init(finalText: "final text", fallbackText: nil))
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["final text"])
        #expect(controller.testingSessionState == .idle)

        controller.handleHotkeyDown()

        #expect(legacyRecognizer.startCallCount == 1)
        #expect(speechAnalyzerRecognizer.startCallCount == 1)
        #expect(controller.testingSessionState == .listening)
    }

    @Test func headlessControllerCancelsRecognizerStartupWhenHotkeyReleasesBeforeReady() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        recognizer.autoReady = false
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false }
        )

        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        recognizer.emitReady()

        #expect(recognizer.startCallCount == 1)
        #expect(recognizer.stopCallCount == 0)
        #expect(recognizer.cancelCallCount == 1)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingPendingStart == false)
        #expect(controller.testingActiveSessionID == nil)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerRestartsCleanlyWhenHotkeyRepressesDuringStop() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        var hotkeyPressed = false
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { hotkeyPressed },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        hotkeyPressed = true
        controller.handleHotkeyDown()
        let firstSessionID = controller.testingActiveSessionID

        hotkeyPressed = false
        controller.handleHotkeyUp()
        #expect(controller.testingSessionState == .stopping)

        hotkeyPressed = true
        controller.handleHotkeyDown()
        recognizer.deliverStop(
            DictationRecognizerStopResult(
                finalText: "first session",
                fallbackText: nil
            )
        )
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(recognizer.startCallCount == 2)
        #expect(insertedTexts == ["first session"])
        #expect(controller.testingActiveSessionID != firstSessionID)
        #expect(controller.testingSessionState == .listening)
    }

    @Test func headlessControllerRestartHidesPriorProcessingOverlayUntilNextReady() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let translationCoordinator = SequencedTranslationCoordinator(
            firstResult: "primer reinicio",
            laterResults: []
        )
        let postProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, source, target in
                    try await translationCoordinator.translate(text: text)
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" }
        )
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        recognizer.autoReady = false
        var hotkeyPressed = false
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { hotkeyPressed },
            translationPostProcessor: postProcessor,
            transcriptInserter: { _ in .responderChainPaste }
        )

        hotkeyPressed = true
        controller.handleHotkeyDown()
        recognizer.emitReady()
        recognizer.emitPartial("first preview")

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "first preview")

        hotkeyPressed = false
        controller.handleHotkeyUp()

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)

        hotkeyPressed = true
        controller.handleHotkeyDown()
        recognizer.deliverStop(.init(finalText: "first session", fallbackText: nil))

        #expect(controller.testingSessionState == .starting)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)

        recognizer.emitReady()

        #expect(controller.testingSessionState == .listening)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayListeningLine)

        await translationCoordinator.resumeFirst()
        await controller.waitForInsertionQueueDrainForTesting()
    }

    @Test func headlessControllerSerializesInsertionAcrossRestartedSessions() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let translationCoordinator = SequencedTranslationCoordinator(
            firstResult: "uno",
            laterResults: ["dos"]
        )
        let postProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, source, target in
                    try await translationCoordinator.translate(text: text)
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" }
        )
        var insertedTexts: [String] = []
        var hotkeyPressed = false
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { hotkeyPressed },
            translationPostProcessor: postProcessor,
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        hotkeyPressed = true
        controller.handleHotkeyDown()
        hotkeyPressed = false
        controller.handleHotkeyUp()

        hotkeyPressed = true
        controller.handleHotkeyDown()
        recognizer.deliverStop(.init(finalText: "one", fallbackText: nil))
        await Task.yield()

        #expect(recognizer.startCallCount == 2)
        #expect(insertedTexts.isEmpty)
        #expect(controller.testingSessionState == .listening)

        hotkeyPressed = false
        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "two", fallbackText: nil))
        await Task.yield()

        #expect(recognizer.stopCallCount == 2)
        #expect(insertedTexts.isEmpty)

        await translationCoordinator.resumeFirst()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["uno", "dos"])
        #expect(controller.testingSessionState == .idle)
    }

    @Test func headlessControllerAllowsFallbackOnlyWhenStopIsMarkedFailed() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("preview only")
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview only")
        controller.handleHotkeyUp()
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        recognizer.deliverStop(
            DictationRecognizerStopResult(
                finalText: nil,
                fallbackText: "preview only",
                stopMarkedAsFailure: false
            )
        )
        await controller.waitForInsertionQueueDrainForTesting()
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
        #expect(controller.testingSessionState == .idle)

        controller.handleHotkeyDown()
        recognizer.emitPartial("preview only")
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "preview only")
        controller.handleHotkeyUp()
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        recognizer.deliverStop(
            DictationRecognizerStopResult(
                finalText: nil,
                fallbackText: "preview only",
                stopMarkedAsFailure: true
            )
        )
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["preview only"])
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
        #expect(controller.testingSessionState == .idle)
    }

    @Test func headlessControllerLegacyTimeoutUsesProcessingOverlayAndFinalOnlyInsertion() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: true)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("preview only")

        #expect(controller.testingOverlayText == "preview only")

        controller.triggerStopForTesting(.legacyTimeout)

        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)

        recognizer.deliverStop(
            DictationRecognizerStopResult(
                finalText: "legacy timeout final",
                fallbackText: "preview only"
            )
        )
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(insertedTexts == ["legacy timeout final"])
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerWatchdogCancelsRecognizerAndUsesFallback() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let watchdogCapture = WatchdogHandlerCapture()
        var insertedTexts: [String] = []
        let captureWatchdog: DictationController.StopWatchdogScheduler = { _, handler in
            watchdogCapture.handler = handler
            return DictationController.ScheduledWork(cancelImpl: {})
        }
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            stopWatchdogScheduler: captureWatchdog,
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("watchdog fallback")
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "watchdog fallback")
        controller.handleHotkeyUp()
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        watchdogCapture.handler?()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(recognizer.cancelCallCount == 1)
        #expect(insertedTexts == ["watchdog fallback"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerIgnoresLateRecognizerStopAfterWatchdogFallback() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let watchdogCapture = WatchdogHandlerCapture()
        var insertedTexts: [String] = []
        let captureWatchdog: DictationController.StopWatchdogScheduler = { _, handler in
            watchdogCapture.handler = handler
            return DictationController.ScheduledWork(cancelImpl: {})
        }
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            stopWatchdogScheduler: captureWatchdog,
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("watchdog fallback")
        controller.handleHotkeyUp()
        watchdogCapture.handler?()
        await controller.waitForInsertionQueueDrainForTesting()

        recognizer.replayLastStop(.init(finalText: "late recognizer result", fallbackText: nil))

        #expect(insertedTexts == ["watchdog fallback"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
    }

    @Test func headlessControllerPermissionRevocationForcesResetDuringStartup() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var missingPermissions: [DictationController.PrivacyDestination] = []
        var pendingPermissionCompletion: ((Bool) -> Void)?
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            permissionAuthorizer: { _, completion in
                pendingPermissionCompletion = completion
            },
            privacyDestinationProvider: { missingPermissions }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()

        #expect(controller.testingSessionState == .starting)
        #expect(controller.testingPendingStart == true)

        missingPermissions = [.microphone]
        controller.refreshPermissionStateForTesting()

        #expect(recognizer.cancelCallCount == 1)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingPendingStart == false)
        #expect(controller.testingActiveSessionID == nil)
        #expect(pendingPermissionCompletion != nil)
    }

    @Test(arguments: [false, true])
    func stalePermissionReplyCannotAbortOrStartNewerSession(authorized: Bool) {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var permissionReplies: [(Bool) -> Void] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            permissionAuthorizer: { _, completion in permissionReplies.append(completion) }
        )
        controller.handleHotkeyDown()
        let firstSession = controller.testingActiveSessionID
        controller.handleHotkeyUp()
        controller.handleHotkeyDown()
        let secondSession = controller.testingActiveSessionID
        #expect(firstSession != secondSession)
        #expect(permissionReplies.count == 2)

        permissionReplies[0](authorized)
        #expect(controller.testingActiveSessionID == secondSession)
        #expect(controller.testingSessionState == .starting)
        #expect(controller.testingPendingStart)
        #expect(recognizer.startCallCount == 0)

        permissionReplies[1](true)
        #expect(controller.testingActiveSessionID == secondSession)
        #expect(controller.testingSessionState == .listening)
        #expect(recognizer.startCallCount == 1)
        controller.handleHotkeyUp()
    }

    @Test(arguments: [false, true])
    func failedPermissionReplyOrRecheckAbortsBeforeRecognizerStarts(revokedDuringCheck: Bool) {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var reply: ((Bool) -> Void)?
        var missing: [DictationController.PrivacyDestination] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            permissionAuthorizer: { _, completion in reply = completion },
            privacyDestinationProvider: { missing }
        )
        controller.handleHotkeyDown()
        #expect(controller.testingPendingStart)
        if revokedDuringCheck { missing = [.microphone] }
        reply?(revokedDuringCheck)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
        #expect(!controller.testingPendingStart)
        #expect(!controller.testingOverlayVisible)
        #expect(recognizer.startCallCount == 0)
    }

    @Test func headlessControllerCancelsPendingPermissionCheckWhenHotkeyReleasesEarly() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var pendingPermissionCompletion: ((Bool) -> Void)?
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            permissionAuthorizer: { _, completion in
                pendingPermissionCompletion = completion
            }
        )

        controller.handleHotkeyDown()

        #expect(controller.testingSessionState == .starting)
        #expect(controller.testingPendingStart == true)

        controller.handleHotkeyUp()

        #expect(recognizer.cancelCallCount == 1)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingPendingStart == false)
        #expect(controller.testingActiveSessionID == nil)

        pendingPermissionCompletion?(true)

        #expect(recognizer.startCallCount == 0)
        #expect(controller.testingSessionState == .idle)
    }

    @Test func headlessControllerIgnoresDuplicateStopCompletionAfterRecognizerError() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitPartial("partial failure tail")
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "partial failure tail")
        recognizer.emitError(.taskFailed)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)
        recognizer.deliverStop(
            .init(
                finalText: nil,
                fallbackText: "partial failure tail",
                stopMarkedAsFailure: true
            )
        )
        await controller.waitForInsertionQueueDrainForTesting()

        recognizer.replayLastStop(.init(finalText: "late duplicate", fallbackText: nil))

        #expect(insertedTexts == ["partial failure tail"])
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerReportsBackgroundRecoveryWhenStartupIssueBlocksHotkey() {
        let recognizer = FakeDictationRecognizer(
            requiresSessionTimeout: false,
            startupIssueValue: .noAudioInput
        )
        var notices: [(String, String)] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            appIsActiveProvider: { false },
            backgroundRecoveryReporter: { title, body in
                notices.append((title, body))
            }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()

        #expect(recognizer.startCallCount == 0)
        #expect(controller.testingSessionState == .idle)
        #expect(notices.count == 1)
        guard let notice = notices.first else { return }
        #expect(notice.0 == "YEN Dictation Needs Attention")
        #expect(notice.1 == DictationController.localServiceRecoveryBody(for: .noAudioInput))
    }

    @Test func headlessControllerLocalSpeechFailureDoesNotShowPreviewOverlay() {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(
            requiresSessionTimeout: false,
            startupIssueValue: .noAudioInput
        )
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()

        #expect(recognizer.startCallCount == 0)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerReportsBackgroundRecoveryWhenRecognizerFailsBeforeReady() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        recognizer.autoReady = false
        var notices: [(String, String)] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            appIsActiveProvider: { false },
            backgroundRecoveryReporter: { title, body in
                notices.append((title, body))
            }
        )

        controller.handleHotkeyDown()
        recognizer.emitError(.taskFailed)

        #expect(recognizer.startCallCount == 1)
        #expect(recognizer.cancelCallCount == 1)
        #expect(controller.testingSessionState == .idle)
        #expect(notices.count == 1)
        guard let notice = notices.first else { return }
        #expect(notice.0 == "YEN Dictation Needs Attention")
        #expect(notice.1 == DictationController.localServiceRecoveryBody(for: .runtimeFailure))
    }

    @Test func headlessForegroundPermissionRevocationDoesNotOpenModalAlert() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var missing: [DictationController.PrivacyDestination] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            privacyDestinationProvider: { missing },
            appIsActiveProvider: { true }
        )
        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()
        #expect(controller.testingSessionState == .listening)
        missing = [.microphone]
        controller.refreshPermissionStateForTesting(showRevocationNotice: true)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
        #expect(!controller.testingOverlayVisible)
    }

    @Test func headlessControllerPermissionRevocationForcesResetDuringActiveCapture() {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var missingPermissions: [DictationController.PrivacyDestination] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { true },
            privacyDestinationProvider: { missingPermissions }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()
        recognizer.emitPartial("stale preview")

        #expect(controller.testingSessionState == .listening)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == "stale preview")

        missingPermissions = [.microphone]
        controller.refreshPermissionStateForTesting()

        #expect(recognizer.cancelCallCount == 1)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerPermissionRevocationForcesResetDuringStopFinalization() async {
        let originalPreference = DictationPreviewPreferences.liveTranscriptEnabled
        DictationPreviewPreferences.liveTranscriptEnabled = true
        defer {
            DictationPreviewPreferences.liveTranscriptEnabled = originalPreference
        }

        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var missingPermissions: [DictationController.PrivacyDestination] = []
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            privacyDestinationProvider: { missingPermissions },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()
        recognizer.emitPartial("stale preview")
        controller.handleHotkeyUp()

        #expect(controller.testingIsStopping == true)
        #expect(controller.testingOverlayVisible == true)
        #expect(controller.testingOverlayText == DictationCopy.overlayProcessingLine)

        missingPermissions = [.microphone]
        controller.refreshPermissionStateForTesting()
        recognizer.deliverStop(.init(finalText: "stale stop", fallbackText: nil))
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(recognizer.cancelCallCount == 1)
        #expect(insertedTexts.isEmpty)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
        #expect(controller.testingOverlayVisible == false)
        #expect(controller.testingOverlayText == nil)
    }

    @Test func headlessControllerIdlePermissionRefreshDoesNotForceReset() {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        var missingPermissions: [DictationController.PrivacyDestination] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            privacyDestinationProvider: { missingPermissions }
        )

        controller.refreshPermissionStateForTesting()
        missingPermissions = [.microphone]
        controller.refreshPermissionStateForTesting()

        #expect(recognizer.cancelCallCount == 0)
        #expect(controller.testingSessionState == .idle)
        #expect(controller.testingActiveSessionID == nil)
    }

    @Test func headlessControllerPermissionRefreshDoesNotDropPostCaptureInsertionTail() async {
        let recognizer = FakeDictationRecognizer(requiresSessionTimeout: false)
        let translationCoordinator = SequencedTranslationCoordinator(
            firstResult: "translated tail",
            laterResults: []
        )
        let postProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, source, target in
                    try await translationCoordinator.translate(text: text)
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" }
        )
        var missingPermissions: [DictationController.PrivacyDestination] = []
        var insertedTexts: [String] = []
        let controller = makeHeadlessDictationController(
            recognizer: recognizer,
            hotkeyPressed: { false },
            translationPostProcessor: postProcessor,
            privacyDestinationProvider: { missingPermissions },
            transcriptInserter: { text in
                insertedTexts.append(text)
                return .responderChainPaste
            }
        )

        controller.refreshPermissionStateForTesting()
        controller.handleHotkeyDown()
        controller.handleHotkeyUp()
        recognizer.deliverStop(.init(finalText: "tail text", fallbackText: nil))
        await Task.yield()

        #expect(controller.testingSessionState == .inserting)
        #expect(insertedTexts.isEmpty)

        missingPermissions = [.microphone]
        controller.refreshPermissionStateForTesting()
        await translationCoordinator.resumeFirst()
        await controller.waitForInsertionQueueDrainForTesting()

        #expect(recognizer.cancelCallCount == 0)
        #expect(insertedTexts == ["translated tail"])
        #expect(controller.testingSessionState == .idle)
    }

    @Test func stopWatchdogRequiresActiveStopAndMatchingToken() {
        #expect(DictationController.shouldForceStopWatchdog(isStopping: true, stopTokenMatches: true) == true)
        #expect(DictationController.shouldForceStopWatchdog(isStopping: true, stopTokenMatches: false) == false)
        #expect(DictationController.shouldForceStopWatchdog(isStopping: false, stopTokenMatches: true) == false)
    }

    @Test func recognizerFallbackActivatesOnlyForSpeechAnalyzerFailures() {
        #expect(
            DictationController.shouldActivateLegacyRecognizerFallback(
                usingLegacyRecognizerFallback: false,
                isSpeechAnalyzerActive: true,
                error: .recognizerIsUnavailable
            ) == true
        )
        #expect(
            DictationController.shouldActivateLegacyRecognizerFallback(
                usingLegacyRecognizerFallback: false,
                isSpeechAnalyzerActive: true,
                error: .taskFailed
            ) == false
        )
        #expect(
            DictationController.shouldActivateLegacyRecognizerFallback(
                usingLegacyRecognizerFallback: true,
                isSpeechAnalyzerActive: true,
                error: .taskFailed
            ) == false
        )
        #expect(
            DictationController.shouldActivateLegacyRecognizerFallback(
                usingLegacyRecognizerFallback: false,
                isSpeechAnalyzerActive: false,
                error: .taskFailed
            ) == false
        )
    }

    @Test func runtimeFailureDoesNotLatchWhenStartupProbeRecovers() {
        #expect(
            DictationController.resolvedLocalServiceIssue(
                persistedIssue: .runtimeFailure,
                startupIssue: nil
            ) == nil
        )
        #expect(
            DictationController.resolvedLocalServiceIssue(
                persistedIssue: .runtimeFailure,
                startupIssue: .recognizerUnavailable
            ) == .recognizerUnavailable
        )
    }

    @Test func localServiceRecoveryBodyProvidesIssueSpecificGuidance() {
        #expect(
            DictationController.localServiceRecoveryBody(for: .recognizerUnavailable)
                == "Local speech recognizer unavailable. Open Speech Recognition Settings, then try Option + Space again."
        )
        #expect(
            DictationController.localServiceRecoveryBody(for: .legacySystemDictationDisabled)
                == "System Dictation may be off. Open Dictation Settings, enable it, then try Option + Space again."
        )
        #expect(
            DictationController.localServiceRecoveryBody(for: .noAudioInput)
                == "No audio input device detected. Open Sound Input Settings, select a microphone, then try Option + Space again."
        )
        #expect(
            DictationController.localServiceRecoveryBody(for: .runtimeFailure)
                == "Local speech service failed. Open Speech Recognition Settings or use Re-check Local Speech Service in YEN."
        )
    }

    @Test func accessibilityPrivacyCandidatesPreferAccessibilityWithListenEventFallback() {
        let candidates = DictationController.PrivacyDestination.accessibility.urlCandidates

        #expect(candidates.first == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        #expect(candidates.contains("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))
        #expect(candidates.last == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @Test func microphoneAndSpeechCandidatesPreferDirectPrivacyPanes() {
        let micCandidates = DictationController.PrivacyDestination.microphone.urlCandidates
        let speechCandidates = DictationController.PrivacyDestination.speechRecognition.urlCandidates

        #expect(micCandidates.first == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")
        #expect(speechCandidates.first == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_SpeechRecognition")
    }

    @Test func permissionActionTitlesUseSharedGrantVsFixPolicy() {
        #expect(
            DictationController.permissionActionTitle(
                for: .accessibility,
                speechStatus: .denied,
                microphoneStatus: .authorized
            ) == "Fix"
        )
        #expect(
            DictationController.permissionActionTitle(
                for: .speechRecognition,
                speechStatus: .notDetermined,
                microphoneStatus: .authorized
            ) == "Grant"
        )
        #expect(
            DictationController.permissionActionTitle(
                for: .speechRecognition,
                speechStatus: .denied,
                microphoneStatus: .authorized
            ) == "Fix"
        )
        #expect(
            DictationController.permissionActionTitle(
                for: .microphone,
                speechStatus: .authorized,
                microphoneStatus: .notDetermined
            ) == "Grant"
        )
        #expect(
            DictationController.permissionActionTitle(
                for: .microphone,
                speechStatus: .authorized,
                microphoneStatus: .denied
            ) == "Fix"
        )
    }

    @Test func permissionActionPlansMatchPermissionState() {
        #expect(
            DictationController.permissionSettingsActionPlan(
                for: .accessibility,
                speechStatus: .notDetermined,
                microphoneStatus: .notDetermined
            ) == .promptAccessibilityThenOpenPrivacySettings
        )
        #expect(
            DictationController.permissionSettingsActionPlan(
                for: .speechRecognition,
                speechStatus: .notDetermined,
                microphoneStatus: .authorized
            ) == .requestSpeechRecognitionAuthorization
        )
        #expect(
            DictationController.permissionSettingsActionPlan(
                for: .speechRecognition,
                speechStatus: .restricted,
                microphoneStatus: .authorized
            ) == .openPrivacySettings
        )
        #expect(
            DictationController.permissionSettingsActionPlan(
                for: .microphone,
                speechStatus: .authorized,
                microphoneStatus: .notDetermined
            ) == .requestMicrophoneAccess
        )
        #expect(
            DictationController.permissionSettingsActionPlan(
                for: .microphone,
                speechStatus: .authorized,
                microphoneStatus: .denied
            ) == .openPrivacySettings
        )
    }

    @Test func permissionActionFollowUpPoliciesOnlyOpenSettingsForFailedAuth() {
        #expect(
            !DictationController.shouldOpenPrivacySettingsAfterSpeechAuthorization(.authorized)
        )
        #expect(
            DictationController.shouldOpenPrivacySettingsAfterSpeechAuthorization(.denied)
        )
        #expect(
            DictationController.shouldOpenPrivacySettingsAfterSpeechAuthorization(.restricted)
        )
        #expect(
            !DictationController.shouldOpenPrivacySettingsAfterMicrophoneAuthorization(true)
        )
        #expect(
            DictationController.shouldOpenPrivacySettingsAfterMicrophoneAuthorization(false)
        )
    }

    @Test func translateOnDictateDisabledPassthroughsOriginalText() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(availabilityResult: .installed, translateImpl: { text, _, _ in text }),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { false },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 50_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .disabled)
    }

    @Test func translateOnDictateDisabledUsesImmediatePassthroughPlan() {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, _, _ in text }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { false },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 50_000_000
        )

        let plan = processor.processingPlan(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(plan.requiresTranslation == false)
        #expect(plan.immediateResult?.text == "hello world")
        #expect(plan.immediateResult?.fallbackReason == .disabled)
    }

    @Test func translateOnDictateUsesTranslatedTextWhenSuccessful() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: fakeTranslateToHolaMundo
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 0
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hola mundo")
        #expect(result.translated == true)
        #expect(result.fallbackReason == nil)
    }

    @Test func translateOnDictateBuildsTranslationPlanWhenFeatureIsEnabled() {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: fakeTranslateToHolaMundo
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 0
        )

        let plan = processor.processingPlan(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(plan.requiresTranslation == true)
        #expect(plan.immediateResult == nil)
        #expect(plan.normalizedSourceLocaleIdentifier == "en")
        #expect(plan.normalizedTargetLanguageIdentifier == "es")
    }

    @Test func translateOnDictateFallsBackWhenUnsupportedOnCurrentOS() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { false },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .unsupportedOS)
    }

    @Test func translateOnDictateSkipsWhenSourceAndTargetMatch() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "en" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .sameLanguage)
    }

    @Test func translateOnDictateFallsBackOnFailureAndTimeout() async {
        struct ExpectedFailure: Error {}

        let failedProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { _, _, _ in throw ExpectedFailure() }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let failedResult = await failedProcessor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )
        #expect(failedResult.text == "hello world")
        #expect(failedResult.translated == false)
        #expect(
            failedResult.fallbackReason == .failed ||
            failedResult.fallbackReason == .timedOut
        )

        let timedOutProcessor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { text, _, _ in
                    try await Task.sleep(nanoseconds: 200_000_000)
                    return "\(text)-translated"
                }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 20_000_000
        )

        let timeoutResult = await timedOutProcessor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )
        #expect(timeoutResult.text == "hello world")
        #expect(timeoutResult.translated == false)
        #expect(timeoutResult.fallbackReason == .timedOut)
    }

    @Test func translateOnDictateTimesOutWhenAvailabilityCheckStalls() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityImpl: { _, _ in
                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch {
                        return .installed
                    }
                    return .installed
                },
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 20_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .timedOut)
    }

    @Test func translateOnDictateFallsBackWhenLanguagePairUnsupported() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .unsupported,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "fr" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .unsupportedPair)
    }

    @Test func translateOnDictateFallsBackWhenAssetsNotInstalledYet() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .supported,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "fr" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let result = await processor.process(
            finalText: "hello world",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "hello world")
        #expect(result.translated == false)
        #expect(result.fallbackReason == .assetsNotReady)
    }

    @Test func translateOnDictatePassthroughsWhitespaceTranscript() async {
        let processor = DictationTranslationPostProcessor(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true },
            translateOnDictateEnabled: { true },
            targetLanguageIdentifier: { "es" },
            translationTimeoutNanoseconds: 1_000_000_000
        )

        let result = await processor.process(
            finalText: "   ",
            sourceLocaleIdentifier: "en-US"
        )

        #expect(result.text == "   ")
        #expect(result.translated == false)
        #expect(result.fallbackReason == nil)
    }

    @Test func translationAssetPreparerBuildsViewScopedPreparationRequestsOnlyForForegroundPairs() async {
        let preparer = DictationTranslationAssetPreparer(
            engine: FakeTranslationEngine(
                availabilityResult: .supported,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true }
        )

        let foregroundPlan = await preparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "es",
            isAppActive: { true }
        )
        let inactivePlan = await preparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "fr",
            isAppActive: { false }
        )

        switch foregroundPlan {
        case .request(let request):
            #expect(request.sourceLocaleIdentifier == "en")
            #expect(request.targetLanguageIdentifier == "es")
        case .terminal(let outcome):
            Issue.record("Expected a preparation request, got terminal outcome: \(outcome)")
        }

        #expect(inactivePlan == .terminal(.inactiveApp))
    }

    @Test func translationAssetPreparerReturnsTerminalOutcomesForNonRequestableCases() async {
        let installedPreparer = DictationTranslationAssetPreparer(
            engine: FakeTranslationEngine(
                availabilityResult: .installed,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true }
        )
        let unsupportedPreparer = DictationTranslationAssetPreparer(
            engine: FakeTranslationEngine(
                availabilityResult: .unsupported,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { true }
        )
        let unsupportedOSPreparer = DictationTranslationAssetPreparer(
            engine: FakeTranslationEngine(
                availabilityResult: .supported,
                translateImpl: { _, _, _ in "never-used" }
            ),
            isTranslationSupported: { false }
        )

        let sameLanguagePlan = await installedPreparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "en-GB",
            isAppActive: { true }
        )
        let installedPlan = await installedPreparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "es",
            isAppActive: { true }
        )
        let unsupportedPlan = await unsupportedPreparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "fr",
            isAppActive: { true }
        )
        let unsupportedOSPlan = await unsupportedOSPreparer.preparationPlan(
            sourceLocaleIdentifier: "en-US",
            targetLanguageIdentifier: "de",
            isAppActive: { true }
        )

        #expect(sameLanguagePlan == .terminal(.sameLanguage))
        #expect(installedPlan == .terminal(.alreadyInstalled))
        #expect(unsupportedPlan == .terminal(.unsupportedPair))
        #expect(unsupportedOSPlan == .terminal(.unsupportedOS))
    }
}
