import ApplicationServices
import Foundation

struct DictationPasteExecutor {
    struct SyntheticCommandVEvents {
        let keyDown: CGEvent
        let keyUp: CGEvent
    }

    static func terminalSurfacePasteOutcome(
        surfaceAvailable: Bool
    ) -> DictationController.InsertionOutcome {
        surfaceAvailable ? .directSurfacePaste : .manualRecoveryRequired
    }

    static func responderChainPasteOutcome(
        didPaste: Bool
    ) -> DictationController.InsertionOutcome {
        didPaste ? .responderChainPaste : .manualRecoveryRequired
    }

    static func syntheticCommandVPasteOutcome(
        createdEvents: Bool
    ) -> DictationController.InsertionOutcome {
        createdEvents ? .remoteCommandVPaste : .manualRecoveryRequired
    }

    static func makeSyntheticCommandVEvents(
        source: CGEventSource?,
        virtualKey: CGKeyCode = 0x09
    ) -> SyntheticCommandVEvents? {
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        return SyntheticCommandVEvents(keyDown: keyDown, keyUp: keyUp)
    }

    static func shouldPostSyntheticCommandV(
        capturedFrontmostProcessIdentifier: pid_t,
        currentFrontmostProcessIdentifier: pid_t?,
        isYENActive: Bool
    ) -> Bool {
        guard !isYENActive else { return false }
        return currentFrontmostProcessIdentifier == capturedFrontmostProcessIdentifier
    }

    static func postSyntheticCommandV(_ events: SyntheticCommandVEvents) {
        events.keyDown.post(tap: .cghidEventTap)
        events.keyUp.post(tap: .cghidEventTap)
    }
}
