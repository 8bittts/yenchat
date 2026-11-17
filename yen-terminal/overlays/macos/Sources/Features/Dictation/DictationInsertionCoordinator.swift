import AppKit
import ApplicationServices

/// Owns synchronous target capture, validation, and transcript delivery.
/// Translation and session cancellation remain with the controller.
@MainActor
final class DictationInsertionCoordinator {
    typealias InsertionOutcome = DictationController.InsertionOutcome
    typealias CapturedInsertionTargetDescriptor = DictationController.CapturedInsertionTargetDescriptor
    typealias InsertionValidationState = DictationController.InsertionValidationState
    typealias ClipboardRestorePlan = DictationController.ClipboardRestorePlan

    enum Failure {
        case secureInput
        case manualPaste
    }

    private let clipboardRestoreScheduler: DictationClipboardRestoreScheduler
    private let transcriptInserter: DictationController.TranscriptInserter?
    private let appIsActiveProvider: DictationController.AppIsActiveProvider
    private let frontmostApplicationPIDProvider: DictationController.FrontmostApplicationPIDProvider
    private let frontmostApplicationFocusedElementProvider: DictationController.FrontmostApplicationFocusedElementProvider
    private let frontmostApplicationFocusFingerprintProvider: DictationController.FrontmostApplicationFocusFingerprintProvider
    private let secureEventInputProvider: DictationController.SecureEventInputProvider
    /// Reuse one private event source for synthetic Cmd+V.
    private let syntheticEventSource: CGEventSource?
    private let capturePasteboardSnapshot: (NSPasteboard) -> DictationPasteboardSnapshot
    private let responderWindowProvider: @MainActor () -> NSWindow?
    private let pasteThroughResponderChain: @MainActor () -> Bool
    private let clipboardRestoreLocal: TimeInterval = 0.3

    init(
        clipboardRestoreScheduler: DictationClipboardRestoreScheduler,
        transcriptInserter: DictationController.TranscriptInserter?,
        appIsActiveProvider: @escaping DictationController.AppIsActiveProvider,
        frontmostApplicationPIDProvider: @escaping DictationController.FrontmostApplicationPIDProvider,
        frontmostApplicationFocusedElementProvider: @escaping DictationController.FrontmostApplicationFocusedElementProvider,
        frontmostApplicationFocusFingerprintProvider: @escaping DictationController.FrontmostApplicationFocusFingerprintProvider,
        secureEventInputProvider: @escaping DictationController.SecureEventInputProvider,
        syntheticEventSource: CGEventSource?,
        capturePasteboardSnapshot: @escaping (NSPasteboard) -> DictationPasteboardSnapshot = DictationPasteboardSnapshot.capture(from:),
        responderWindowProvider: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow },
        pasteThroughResponderChain: @escaping @MainActor () -> Bool = {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        }
    ) {
        self.clipboardRestoreScheduler = clipboardRestoreScheduler
        self.transcriptInserter = transcriptInserter
        self.appIsActiveProvider = appIsActiveProvider
        self.frontmostApplicationPIDProvider = frontmostApplicationPIDProvider
        self.frontmostApplicationFocusedElementProvider = frontmostApplicationFocusedElementProvider
        self.frontmostApplicationFocusFingerprintProvider = frontmostApplicationFocusFingerprintProvider
        self.secureEventInputProvider = secureEventInputProvider
        self.syntheticEventSource = syntheticEventSource
        self.capturePasteboardSnapshot = capturePasteboardSnapshot
        self.responderWindowProvider = responderWindowProvider
        self.pasteThroughResponderChain = pasteThroughResponderChain
    }

    fileprivate final class WeakSurfaceReference {
        weak var surface: YEN.SurfaceView?

        init(_ surface: YEN.SurfaceView) {
            self.surface = surface
        }
    }

    struct CapturedInsertionTarget {
        let descriptor: CapturedInsertionTargetDescriptor
        fileprivate let surfaceReference: WeakSurfaceReference?
        let focusedElement: AXUIElement?
    }

    func performTranscriptInsertion(
        _ text: String,
        insertionTarget: CapturedInsertionTarget?,
        reportFailure: (Failure) -> Void
    ) -> InsertionOutcome {
        if let transcriptInserter {
            return transcriptInserter(text)
        }
        return insertTextAtCapturedTarget(text, insertionTarget: insertionTarget, reportFailure: reportFailure)
    }

    /// Insert text at the captured cursor position.
    /// The insertion target is frozen at stop time so translation/finalization delays
    /// can't redirect a transcript into a different field or application.
    private func insertTextAtCapturedTarget(
        _ text: String,
        insertionTarget: CapturedInsertionTarget?,
        reportFailure: (Failure) -> Void
    ) -> InsertionOutcome {
        guard !secureEventInputProvider() else {
            reportFailure(.secureInput)
            return .manualRecoveryRequired
        }

        let pasteboard = NSPasteboard.general
        let restorePlan = localRestorePlan(for: insertionTarget)
        let previousSnapshot = restorePlan.map { _ in capturePasteboardSnapshot(pasteboard) }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Validate again after clipboard writes before delivering to a captured target.
        let outcome = pasteAtCapturedTarget(insertionTarget)
        if outcome == .manualRecoveryRequired {
            reportFailure(.manualPaste)
        } else if let restorePlan, let previousSnapshot {
            // A newer user copy must win over the delayed restore.
            schedulePasteboardRestore(
                plan: restorePlan,
                pasteboard: pasteboard,
                previousSnapshot: previousSnapshot,
                expectedChangeCount: pasteboard.changeCount
            )
        }
        return outcome
    }

    private func localRestorePlan(for target: CapturedInsertionTarget?) -> ClipboardRestorePlan? {
        guard let target else { return nil }
        switch target.descriptor {
        case .syntheticCommandV:
            // Cross-app delivery cannot be verified, so retain the transcript.
            return nil
        case .terminalSurface:
            guard target.surfaceReference?.surface != nil else { return nil }
        case .responderChain:
            break
        }
        guard isCapturedInsertionTargetValid(target) else { return nil }
        return DictationClipboardRestorePolicy.clipboardRestorePlan(
            for: .responderChain,
            localDelay: clipboardRestoreLocal
        )
    }

    private func pasteAtCapturedTarget(_ target: CapturedInsertionTarget?) -> InsertionOutcome {
        guard let target else {
            print("DictationController: no stable insertion target available — transcript left on clipboard for manual paste")
            return .manualRecoveryRequired
        }
        guard isCapturedInsertionTargetValid(target) else {
            print("DictationController: insertion target changed before paste — transcript left on clipboard for manual paste")
            return .manualRecoveryRequired
        }
        switch target.descriptor {
        case .terminalSurface:
            guard let surface = target.surfaceReference?.surface else {
                print("DictationController: terminal surface deallocated before paste — transcript left on clipboard for manual paste")
                return DictationPasteExecutor.terminalSurfacePasteOutcome(surfaceAvailable: false)
            }
            surface.paste(nil)
            return DictationPasteExecutor.terminalSurfacePasteOutcome(surfaceAvailable: true)
        case .responderChain:
            let didPaste = pasteThroughResponderChain()
            let outcome = DictationPasteExecutor.responderChainPasteOutcome(didPaste: didPaste)
            if outcome == .manualRecoveryRequired {
                print("DictationController: responder-chain paste failed — transcript left on clipboard for manual paste")
            }
            return outcome
        case .syntheticCommandV(let frontmostProcessIdentifier, _):
            guard let events = DictationPasteExecutor.makeSyntheticCommandVEvents(source: syntheticEventSource) else {
                print("DictationController: CGEvent creation failed — transcript left on clipboard for manual paste")
                return DictationPasteExecutor.syntheticCommandVPasteOutcome(createdEvents: false)
            }
            guard DictationPasteExecutor.shouldPostSyntheticCommandV(
                capturedFrontmostProcessIdentifier: frontmostProcessIdentifier,
                currentFrontmostProcessIdentifier: frontmostApplicationPIDProvider(),
                isYENActive: appIsActiveProvider()
            ) else { return .manualRecoveryRequired }
            DictationPasteExecutor.postSyntheticCommandV(events)
            return DictationPasteExecutor.syntheticCommandVPasteOutcome(createdEvents: true)
        }
    }

    func captureInsertionTarget() -> CapturedInsertionTarget? {
        if appIsActiveProvider() {
            if let keyWindow = NSApp.keyWindow,
               let surface = keyWindowFocusedSurfaceForInsertion(keyWindow) {
                return CapturedInsertionTarget(
                    descriptor: .terminalSurface(
                        windowNumber: keyWindow.windowNumber,
                        responderIdentifier: ObjectIdentifier(surface)
                    ),
                    surfaceReference: WeakSurfaceReference(surface),
                    focusedElement: nil
                )
            }

            guard let responderWindow = responderWindowForInsertion(),
                  let firstResponder = responderWindow.firstResponder else {
                return nil
            }

            return CapturedInsertionTarget(
                descriptor: .responderChain(
                    windowNumber: responderWindow.windowNumber,
                    responderIdentifier: ObjectIdentifier(firstResponder)
                ),
                surfaceReference: nil,
                focusedElement: nil
            )
        }

        guard let frontmostProcessIdentifier = frontmostApplicationPIDProvider() else {
            return nil
        }
        if let focusedElement = frontmostApplicationFocusedElementProvider(frontmostProcessIdentifier) {
            return CapturedInsertionTarget(
                descriptor: .syntheticCommandV(
                    frontmostProcessIdentifier: frontmostProcessIdentifier,
                    focusFingerprint: Int(CFHash(focusedElement))
                ),
                surfaceReference: nil,
                focusedElement: focusedElement
            )
        }
        return CapturedInsertionTarget(
            descriptor: .syntheticCommandV(
                frontmostProcessIdentifier: frontmostProcessIdentifier,
                focusFingerprint: frontmostApplicationFocusFingerprintProvider(frontmostProcessIdentifier)
            ),
            surfaceReference: nil,
            focusedElement: nil
        )
    }

    private func responderWindowForInsertion() -> NSWindow? {
        responderWindowProvider()
    }

    private func keyWindowFocusedSurfaceForInsertion(_ window: NSWindow) -> YEN.SurfaceView? {
        guard let controller = window.windowController as? BaseTerminalController,
              let surface = controller.focusedSurface else {
            return nil
        }
        guard window.firstResponder === surface else { return nil }
        return surface
    }

    func isCapturedInsertionTargetValid(_ target: CapturedInsertionTarget) -> Bool {
        switch target.descriptor {
        case .syntheticCommandV(let expectedPID, let expectedFingerprint):
            guard !appIsActiveProvider(), frontmostApplicationPIDProvider() == expectedPID else { return false }
            if let expectedFocusedElement = target.focusedElement {
                guard let currentFocusedElement = frontmostApplicationFocusedElementProvider(expectedPID) else {
                    return false
                }
                return CFEqual(expectedFocusedElement, currentFocusedElement)
            }
            guard let expectedFingerprint else { return true }
            return frontmostApplicationFocusFingerprintProvider(expectedPID) == expectedFingerprint
        case .terminalSurface, .responderChain:
            let window = responderWindowForInsertion()
            return DictationController.isCapturedInsertionTargetValid(
                target.descriptor,
                currentState: InsertionValidationState(
                    isYENActive: appIsActiveProvider(),
                    windowNumber: window?.windowNumber,
                    firstResponderIdentifier: window?.firstResponder.map(ObjectIdentifier.init),
                    frontmostProcessIdentifier: nil,
                    frontmostFocusFingerprint: nil
                )
            )
        }
    }

    private func schedulePasteboardRestore(
        plan: ClipboardRestorePlan,
        pasteboard: NSPasteboard,
        previousSnapshot: DictationPasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        clipboardRestoreScheduler.scheduleRestore(
            plan: plan,
            pasteboard: pasteboard,
            previousSnapshot: previousSnapshot,
            expectedChangeCount: expectedChangeCount
        )
    }

}
