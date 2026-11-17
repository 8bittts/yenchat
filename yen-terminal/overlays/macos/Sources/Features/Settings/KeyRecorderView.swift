#if os(macOS)
import SwiftUI
import Cocoa

enum KeyRecorderRejection: Equatable {
    case missingRequiredModifier
    case unsupportedKey
    case reservedFixedShortcut
    case unavailableKeybind

	@MainActor var visibleMessage: String {
        switch self {
        case .missingRequiredModifier:
            return KeybindRegistry.missingRequiredModifierValidationMessage
        case .unsupportedKey:
            return "That key can't be recorded."
        case .reservedFixedShortcut:
            return KeybindRegistry.reservedFixedShortcutValidationMessage
        case .unavailableKeybind:
            return "That shortcut can't be changed."
        }
    }

	@MainActor var accessibilityAnnouncement: String {
        switch self {
        case .missingRequiredModifier:
            return "Add Command, Control, or Option to record a shortcut."
        default:
            return visibleMessage
        }
    }
}

enum KeyRecorderRecordResult: Equatable {
    case recorded
    case rejected(KeyRecorderRejection)
}

/// A key recorder that captures keyboard shortcuts via NSEvent monitoring.
/// Wraps an AppKit NSView for reliable key capture in a SwiftUI context.
struct KeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (KeyTrigger) -> KeyRecorderRecordResult
    let onReject: ((KeyRecorderRejection) -> Void)?

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = { isRecording = false }
        view.onReject = onReject
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        if isRecording && !nsView.isMonitoring {
            nsView.startMonitoring()
        } else if !isRecording && nsView.isMonitoring {
            nsView.stopMonitoring()
        }
    }
}

/// AppKit view that installs a local key event monitor for shortcut capture.
@MainActor
class KeyRecorderNSView: NSView {
    var onRecord: ((KeyTrigger) -> KeyRecorderRecordResult)?
    var onCancel: (() -> Void)?
    var onReject: ((KeyRecorderRejection) -> Void)?
    private(set) var isMonitoring = false
    private var monitor: Any?
    private var timeoutWork: DispatchWorkItem?
#if DEBUG
    var testAnnouncementHandler: ((String) -> Void)?
#endif

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        postAccessibilityAnnouncement("Listening for a new shortcut. Press Escape to cancel.")

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyEvent(event)
        }

        // Auto-cancel after 10 seconds to prevent stuck state
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isMonitoring else { return }
            self.stopMonitoring()
            self.postAccessibilityAnnouncement("Shortcut recording timed out.")
            self.onCancel?()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func stopMonitoring() {
        timeoutWork?.cancel()
        timeoutWork = nil
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isMonitoring = false
    }

    deinit {
        // Capture locals — deinit is nonisolated so self access is unsafe.
        let pendingMonitor = monitor
        let pendingWork = timeoutWork
        pendingWork?.cancel()
        // NSEvent.removeMonitor must be called on the main thread.
        if let m = pendingMonitor {
            if Thread.isMainThread {
                NSEvent.removeMonitor(m)
            } else {
                DispatchQueue.main.async {
                    NSEvent.removeMonitor(m)
                }
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent, requireKeyWindow: Bool = true) -> NSEvent? {
        // The monitor is app-wide, so an armed recorder used to swallow every keystroke
        // aimed at ANY YEN window. Click record, then click a terminal, and typing went
        // nowhere for up to 10 seconds — and the first modified keystroke (Cmd+V, say)
        // got mis-captured as the new binding. Only consume events destined for the
        // window that owns the recorder. Mirrors LayoutShortcutController's guard.
        // processKeyEventForTesting skips this: the hook is "an event already aimed at us".
        if requireKeyWindow {
            guard window?.isKeyWindow == true else { return event }
        }

        // Escape cancels recording
        if event.keyCode == 53 {
            stopMonitoring()
            postAccessibilityAnnouncement("Shortcut recording cancelled.")
            onCancel?()
            return nil
        }

        let modifiers = KeyModifiers(flags: event.modifierFlags)

        // Require at least one modifier (Cmd, Ctrl, or Option) for valid shortcuts
        guard modifiers.hasRequiredModifier else {
            reject(.missingRequiredModifier)
            return nil
        }

        let keyDescriptor = KeybindRegistry.keyDescriptor(forKeyCode: event.keyCode, event: event)
        guard !keyDescriptor.key.hasPrefix("unknown_") else {
            reject(.unsupportedKey)
            return nil
        }
        let trigger = KeyTrigger(
            modifiers: modifiers,
            key: keyDescriptor.key,
            keyCode: event.keyCode,
            displayKey: keyDescriptor.displayKey
        )

        let result = onRecord?(trigger) ?? .recorded
        switch result {
        case .recorded:
            stopMonitoring()
        case let .rejected(rejection):
            reject(rejection)
        }
        return nil
    }

    private func reject(_ rejection: KeyRecorderRejection) {
        postAccessibilityAnnouncement(rejection.accessibilityAnnouncement)
        onReject?(rejection)
    }

    func processKeyEventForTesting(_ event: NSEvent) -> NSEvent? {
        handleKeyEvent(event, requireKeyWindow: false)
    }

    func fireTimeoutForTesting() {
        timeoutWork?.perform()
    }

    private func postAccessibilityAnnouncement(_ message: String) {
#if DEBUG
        testAnnouncementHandler?(message)
#endif
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

// MARK: - Key Recorder Button

/// Inline recorder button for a keybind row. Tap to start recording, press a shortcut to set.
struct KeyRecorderButton: View {
    @Binding var isRecording: Bool
    /// Names the shortcut in the accessibility labels. Every row used to read
    /// "Record shortcut", with nothing to tell one row from the next.
    let actionName: String
    /// The current shortcut, shown as the button itself: click the shortcut to
    /// record a new one. Empty shows a record symbol instead.
    let shortcutTitle: String
    let onRecord: (KeyTrigger) -> KeyRecorderRecordResult
    let onReject: (KeyRecorderRejection) -> Void
#if DEBUG
    let invalidRejectionDelayForTesting: TimeInterval?
    let onInvalidRejectionForTesting: (() -> Void)?
#endif

    @State private var showRejection = false
    @State private var rejectionResetWorkItem: DispatchWorkItem?

#if DEBUG
    init(
        isRecording: Binding<Bool>,
        actionName: String = "",
        shortcutTitle: String = "",
        onRecord: @escaping (KeyTrigger) -> KeyRecorderRecordResult,
        onReject: @escaping (KeyRecorderRejection) -> Void,
        invalidRejectionDelayForTesting: TimeInterval? = nil,
        onInvalidRejectionForTesting: (() -> Void)? = nil
    ) {
        self._isRecording = isRecording
        self.actionName = actionName
        self.shortcutTitle = shortcutTitle
        self.onRecord = onRecord
        self.onReject = onReject
        self.invalidRejectionDelayForTesting = invalidRejectionDelayForTesting
        self.onInvalidRejectionForTesting = onInvalidRejectionForTesting
    }
#else
    init(
        isRecording: Binding<Bool>,
        actionName: String = "",
        shortcutTitle: String = "",
        onRecord: @escaping (KeyTrigger) -> KeyRecorderRecordResult,
        onReject: @escaping (KeyRecorderRejection) -> Void
    ) {
        self._isRecording = isRecording
        self.actionName = actionName
        self.shortcutTitle = shortcutTitle
        self.onRecord = onRecord
        self.onReject = onReject
    }
#endif

    var body: some View {
        ZStack {
            if isRecording {
                // The same small bordered button as the idle state, so a row
                // keeps its height and alignment while it records. Clicking it
                // cancels.
                Button(action: cancelRecording) {
                    Label(
                        showRejection ? "Not Allowed" : "Press Keys…",
                        systemImage: showRejection ? "exclamationmark.triangle.fill" : "record.circle"
                    )
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(showRejection ? Color(NSColor.systemOrange) : Color(NSColor.systemRed))
                .help("Press the new shortcut. Click or press Esc to cancel.")
                .accessibilityLabel(Self.accessibilityLabel("Cancel shortcut recording", actionName: actionName))

                // Hidden recorder view for event monitoring
                KeyRecorderView(
                    isRecording: $isRecording,
                    onRecord: { trigger in
                        cancelRejectionReset()
                        let result = onRecord(trigger)
                        if result == .recorded {
                            isRecording = false
                            showRejection = false
                        }
                        return result
                    },
                    onReject: { rejection in
                        cancelRejectionReset()
                        onReject(rejection)
                        showInvalidRejection()
                    }
                )
                .frame(width: 0, height: 0)
            } else if shortcutTitle.isEmpty {
                Button(action: startRecording) {
                    Image(systemName: "record.circle")
                }
                .controlSize(.small)
                .help("Record shortcut (Esc cancels)")
                .accessibilityLabel(Self.accessibilityLabel("Record shortcut", actionName: actionName))
            } else {
                // Idle state: the shortcut is the button.
                Button(shortcutTitle, action: startRecording)
                    .controlSize(.small)
                    .help("Click, then press the new shortcut. Esc cancels.")
                    .accessibilityLabel(Self.accessibilityLabel("Record shortcut", actionName: actionName))
                    .accessibilityValue(shortcutTitle)
            }
        }
        .onDisappear {
            cancelRejectionReset()
        }
    }

    static func accessibilityLabel(_ base: String, actionName: String) -> String {
        actionName.isEmpty ? base : "\(base) for \(actionName)"
    }

    private func startRecording() {
        cancelRejectionReset()
        showRejection = false
        isRecording = true
    }

    private func cancelRecording() {
        cancelRejectionReset()
        showRejection = false
        isRecording = false
    }

    private func cancelRejectionReset() {
        rejectionResetWorkItem?.cancel()
        rejectionResetWorkItem = nil
    }

    private func showInvalidRejection() {
        cancelRejectionReset()
        showRejection = true
#if DEBUG
        onInvalidRejectionForTesting?()
#endif
        let work = DispatchWorkItem {
            showRejection = false
            rejectionResetWorkItem = nil
        }
        rejectionResetWorkItem = work
#if DEBUG
        let rejectionDelay = invalidRejectionDelayForTesting ?? 1.5
#else
        let rejectionDelay = 1.5
#endif
        DispatchQueue.main.asyncAfter(
            deadline: .now() + rejectionDelay,
            execute: work
        )
    }
}

#endif // os(macOS)
