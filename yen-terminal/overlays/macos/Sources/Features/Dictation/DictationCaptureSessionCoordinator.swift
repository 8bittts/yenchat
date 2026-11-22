#if os(macOS)

/// Headless coordination surface for dictation session lifecycle decisions.
/// Keeps dictation stop/restart/watchdog/revocation behavior testable without AppKit wiring.
struct DictationCaptureSessionCoordinator {
    struct StopSession: Equatable {
        let token: UUID
        let sessionID: UUID
        var stopCause: DictationController.StopCause
        let stopRequestedAt: CFAbsoluteTime
        var restartRequested: Bool
    }

    enum StartAction: Equatable {
        case queueRestartAfterStop
        case ignore
        case beginPermissionCheck(sessionID: UUID)
    }

    struct StopRequest: Equatable {
        let token: UUID
        let sessionID: UUID
    }

    struct StopCompletionOutcome: Equatable {
        let sessionID: UUID
        let stopCause: DictationController.StopCause
        let stopRequestedAt: CFAbsoluteTime
        let insertionDecision: DictationController.TranscriptInsertionDecision?
        let shouldTransitionToFailed: Bool
        let shouldRestart: Bool
    }

    struct PermissionRefreshOutcome: Equatable {
        let shouldHardTeardown: Bool
        let shouldShowRevocationNotice: Bool
    }

    var activeSessionID: UUID?
    var pendingStart = false
    var isListening = false
    var stopSession: StopSession?

    var isStopping: Bool { stopSession != nil }

    mutating func beginStartRequest() -> StartAction {
        switch DictationController.hotkeyDownAction(
            isStopping: isStopping,
            isListening: isListening,
            pendingStart: pendingStart
        ) {
        case .queueRestartAfterStop:
            requestRestartAfterStop()
            return .queueRestartAfterStop
        case .ignore:
            return .ignore
        case .beginPermissionCheck:
            let sessionID = UUID()
            activeSessionID = sessionID
            pendingStart = true
            return .beginPermissionCheck(sessionID: sessionID)
        }
    }

    mutating func requestRestartAfterStop() {
        guard var stopSession else { return }
        stopSession.restartRequested = true
        self.stopSession = stopSession
    }

    mutating func clearRestartAfterStop() {
        guard var stopSession else { return }
        stopSession.restartRequested = false
        self.stopSession = stopSession
    }

    mutating func cancelPendingStartOnStopRequest() -> UUID? {
        guard pendingStart else { return nil }
        pendingStart = false
        let sessionID = activeSessionID
        activeSessionID = nil
        return sessionID
    }

    mutating func beginListening(sessionID: UUID) {
        activeSessionID = sessionID
        pendingStart = false
        isListening = true
    }

    mutating func finishPendingStartPermissionCheck() {
        pendingStart = false
    }

    mutating func clearActiveSessionIfMatching(_ sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        activeSessionID = nil
        return true
    }

    mutating func beginStop(
        trigger: DictationController.StopCause,
        now: CFAbsoluteTime
    ) -> StopRequest? {
        guard isListening, !isStopping else { return nil }
        let sessionID = activeSessionID ?? UUID()
        activeSessionID = sessionID
        let stopToken = UUID()
        stopSession = StopSession(
            token: stopToken,
            sessionID: sessionID,
            stopCause: trigger,
            stopRequestedAt: now,
            restartRequested: false
        )
        return StopRequest(token: stopToken, sessionID: sessionID)
    }

    mutating func completeStop(
        token: UUID,
        stopResult: DictationRecognizerStopResult,
        fallbackTranscript: String?,
        hotkeyStillPressed: Bool
    ) -> StopCompletionOutcome? {
        guard stopSession?.token == token else { return nil }
        guard let activeStopSession = stopSession else { return nil }

        let decision = DictationController.transcriptForInsertion(
            stopResult: stopResult,
            fallbackTranscript: fallbackTranscript,
            stopCause: activeStopSession.stopCause
        )
        let shouldTransitionToFailed = (
            activeStopSession.stopCause == .recognizerError
                || activeStopSession.stopCause == .watchdog
                || activeStopSession.stopCause == .forcedReset
                || stopResult.stopMarkedAsFailure
        )
        let shouldRestart = DictationController.shouldRestartAfterStop(
            queuedRestart: activeStopSession.restartRequested,
            hotkeyStillPressed: hotkeyStillPressed
        )

        stopSession = nil
        isListening = false
        if decision == nil {
            _ = clearActiveSessionIfMatching(activeStopSession.sessionID)
        }

        return StopCompletionOutcome(
            sessionID: activeStopSession.sessionID,
            stopCause: activeStopSession.stopCause,
            stopRequestedAt: activeStopSession.stopRequestedAt,
            insertionDecision: decision,
            shouldTransitionToFailed: decision == nil && shouldTransitionToFailed,
            shouldRestart: shouldRestart
        )
    }

    mutating func markWatchdogTriggered(token: UUID) -> Bool {
        guard var stopSession, stopSession.token == token else { return false }
        stopSession.stopCause = .watchdog
        self.stopSession = stopSession
        return true
    }

    mutating func forceReset() {
        isListening = false
        stopSession = nil
        pendingStart = false
        activeSessionID = nil
    }

    func permissionRefreshOutcome(
        previousMissing: [DictationController.PrivacyDestination]?,
        currentMissing: [DictationController.PrivacyDestination]
    ) -> PermissionRefreshOutcome {
        let hasActiveCaptureSession = DictationController.hasActiveCaptureSession(
            pendingStart: pendingStart,
            isListening: isListening,
            isStopping: isStopping
        )
        let shouldHardTeardown = DictationController.shouldHardTeardownForPermissionRevocation(
            previous: previousMissing,
            current: currentMissing,
            hasActiveCaptureSession: hasActiveCaptureSession
        )
        let shouldShowRevocationNotice = DictationController.shouldShowRevocationNotice(
            previous: previousMissing,
            current: currentMissing,
            hasActiveCaptureSession: hasActiveCaptureSession
        )
        return PermissionRefreshOutcome(
            shouldHardTeardown: shouldHardTeardown,
            shouldShowRevocationNotice: shouldShowRevocationNotice
        )
    }
}

#endif // os(macOS)
