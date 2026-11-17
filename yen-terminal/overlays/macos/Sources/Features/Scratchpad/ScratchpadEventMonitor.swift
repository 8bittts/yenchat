#if os(macOS)
import Cocoa

extension ScratchpadController {
    func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.visible, let panel = self.panel, panel.isVisible else { return event }

            if Self.shouldCloseForMouseDown(
                eventType: event.type,
                panelFrame: panel.frame,
                screenPoint: NSEvent.mouseLocation
            ) {
                self.animateOut(restoringFocus: false)
                return nil
            }

            guard event.type == .keyDown else { return event }

            if self.handleScratchpadCommandKey(event, in: panel) {
                return nil
            }

            if event.keyCode == 0x35 { // Escape
                self.animateOut()
                return nil
            }
            return event
        }
    }

    func handleScratchpadCommandKey(_ event: NSEvent, in panel: NSPanel) -> Bool {
        guard let textView else { return false }
        let scratchpadHasFocus = Self.shouldHandleCommandKey(
            panelFirstResponderIsTextView: panel.firstResponder === textView,
            windowFirstResponderIsTextView: textView.window?.firstResponder === textView
        )
        guard scratchpadHasFocus else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command] else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        switch key {
        case "c":
            textView.copy(nil)
            return true
        case "v":
            textView.paste(nil)
            return true
        case "x":
            textView.cut(nil)
            return true
        case "a":
            textView.selectAll(nil)
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldHandleCommandKey(
        panelFirstResponderIsTextView: Bool,
        windowFirstResponderIsTextView: Bool
    ) -> Bool {
        panelFirstResponderIsTextView || windowFirstResponderIsTextView
    }

    nonisolated static func shouldCloseForClick(panelFrame: NSRect, screenPoint: NSPoint) -> Bool {
        !panelFrame.contains(screenPoint)
    }

    nonisolated static func shouldCloseForMouseDown(
        eventType: NSEvent.EventType,
        panelFrame: NSRect,
        screenPoint: NSPoint
    ) -> Bool {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return shouldCloseForClick(panelFrame: panelFrame, screenPoint: screenPoint)
        default:
            return false
        }
    }

    func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
#endif
