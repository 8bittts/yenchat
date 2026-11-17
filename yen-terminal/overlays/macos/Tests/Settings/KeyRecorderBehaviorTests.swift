import AppKit
import SwiftUI
import Testing
@testable import YEN

@MainActor
struct KeyRecorderBehaviorTests {
    @Test func cmdQAndCmdWAreCapturedByRecorder() {
        let recorder = KeyRecorderNSView()
        var captured: [KeyTrigger] = []
        recorder.onRecord = {
            captured.append($0)
            return .recorded
        }

        let cmdQ = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        )
        #expect(cmdQ != nil)
        guard let cmdQ else { return }
        #expect(recorder.processKeyEventForTesting(cmdQ) == nil)
        #expect(captured.count == 1)
        #expect(captured[0].key == "q")
        #expect(captured[0].modifiers == KeyModifiers(cmd: true))

        let cmdW = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )
        #expect(cmdW != nil)
        guard let cmdW else { return }
        #expect(recorder.processKeyEventForTesting(cmdW) == nil)
        #expect(captured.count == 2)
        #expect(captured[1].key == "w")
        #expect(captured[1].modifiers == KeyModifiers(cmd: true))
    }

    @Test func recorderRejectsShortcutWithoutRequiredModifier() {
        let recorder = KeyRecorderNSView()
        var captured: [KeyTrigger] = []
        var rejections: [KeyRecorderRejection] = []
        var announcements: [String] = []
        recorder.onRecord = {
            captured.append($0)
            return .recorded
        }
        recorder.onReject = { rejections.append($0) }
        recorder.testAnnouncementHandler = { announcements.append($0) }

        let plainA = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
        #expect(plainA != nil)
        guard let plainA else { return }
        #expect(recorder.processKeyEventForTesting(plainA) == nil)
        #expect(captured.isEmpty)
        #expect(rejections == [.missingRequiredModifier])
        #expect(announcements == ["Add Command, Control, or Option to record a shortcut."])
    }

    @Test func recorderRejectsUnsupportedKeyWithAccurateFeedback() throws {
        let recorder = KeyRecorderNSView()
        var rejections: [KeyRecorderRejection] = []
        var announcements: [String] = []
        recorder.onReject = { rejections.append($0) }
        recorder.testAnnouncementHandler = { announcements.append($0) }

        let unsupportedKey = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 255
        )
        let event = try #require(unsupportedKey)

        #expect(recorder.processKeyEventForTesting(event) == nil)
        #expect(rejections == [.unsupportedKey])
        #expect(announcements == ["That key can't be recorded."])
    }

    @Test func recorderAnnouncesListeningStateWhenRecordingStarts() {
        let recorder = KeyRecorderNSView()
        var announcements: [String] = []
        recorder.testAnnouncementHandler = { announcements.append($0) }

        recorder.startMonitoring()
        defer { recorder.stopMonitoring() }

        #expect(recorder.isMonitoring)
        #expect(announcements == ["Listening for a new shortcut. Press Escape to cancel."])
    }

    @Test func recorderAnnouncesTimeoutWhenRecordingExpires() {
        let recorder = KeyRecorderNSView()
        var announcements: [String] = []
        var cancelCount = 0
        recorder.testAnnouncementHandler = { announcements.append($0) }
        recorder.onCancel = { cancelCount += 1 }

        recorder.startMonitoring()
        recorder.fireTimeoutForTesting()

        #expect(recorder.isMonitoring == false)
        #expect(cancelCount == 1)
        #expect(
            announcements == [
                "Listening for a new shortcut. Press Escape to cancel.",
                "Shortcut recording timed out."
            ]
        )
    }

    @Test func keyDescriptorPrefersLayoutAwareTranslatedCharactersOverUSKeyCodeMap() {
        let descriptor = KeybindRegistry.keyDescriptor(
            forKeyCode: 12,
            translatedCharacters: "a",
            displayCharacters: "a"
        )

        #expect(descriptor.key == "a")
        #expect(descriptor.displayKey == nil)
    }

    @Test func keyDescriptorSeparatesCanonicalKeyFromLayoutAwareDisplayLabel() {
        let descriptor = KeybindRegistry.keyDescriptor(
            forKeyCode: 21,
            translatedCharacters: "'",
            displayCharacters: "4"
        )

        #expect(descriptor.key == "apostrophe")
        #expect(descriptor.displayKey == "4")

        let trigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true, shift: true),
            key: descriptor.key,
            displayKey: descriptor.displayKey
        )
        #expect(trigger.displayString == "Cmd + Shift + 4")
    }

    @Test func keyDescriptorNormalizesArrowGlyphLayoutCharacters() {
        let descriptor = KeybindRegistry.keyDescriptor(
            forKeyCode: 126,
            translatedCharacters: "↑",
            displayCharacters: "↑"
        )

        #expect(descriptor.key == "up")
        #expect(descriptor.displayKey == nil)
    }

    @Test func recorderCanonicalizesArrowGlyphEvents() {
        let recorder = KeyRecorderNSView()
        var captured: [KeyTrigger] = []
        recorder.onRecord = {
            captured.append($0)
            return .recorded
        }

        let arrowUp = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "↑",
            charactersIgnoringModifiers: "↑",
            isARepeat: false,
            keyCode: 126
        )
        #expect(arrowUp != nil)
        guard let arrowUp else { return }
        #expect(recorder.processKeyEventForTesting(arrowUp) == nil)
        #expect(captured.count == 1)
        #expect(captured[0].key == "up")
        #expect(captured[0].modifiers == KeyModifiers(cmd: true, option: true))
    }

    @Test func recorderButtonShowsInlineInvalidFeedbackWhenRecordCallbackRejectsShortcut() throws {
        var isRecording = true
        var invalidFeedbackCount = 0
        var capturedTrigger: KeyTrigger?
        var rejections: [KeyRecorderRejection] = []

        let button = KeyRecorderButton(
            isRecording: Binding(
                get: { isRecording },
                set: { isRecording = $0 }
            ),
            onRecord: { trigger in
                capturedTrigger = trigger
                return .rejected(.reservedFixedShortcut)
            },
            onReject: { rejections.append($0) },
            invalidRejectionDelayForTesting: 60,
            onInvalidRejectionForTesting: {
                invalidFeedbackCount += 1
            }
        )
        let host = NSHostingView(rootView: button)
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 32)
        host.layoutSubtreeIfNeeded()
        drainMainRunLoop()

        let recorder = try #require(host.firstSubview(ofType: KeyRecorderNSView.self))
        var announcements: [String] = []
        recorder.testAnnouncementHandler = { announcements.append($0) }
        let reservedScratchpadShortcut = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "j",
            charactersIgnoringModifiers: "j",
            isARepeat: false,
            keyCode: 38
        )
        let event = try #require(reservedScratchpadShortcut)

        #expect(recorder.processKeyEventForTesting(event) == nil)
        drainMainRunLoop()

        #expect(
            capturedTrigger
                == KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j", keyCode: 38)
        )
        #expect(invalidFeedbackCount == 1)
        #expect(isRecording)
        #expect(rejections == [.reservedFixedShortcut])
        #expect(announcements == [KeybindRegistry.reservedFixedShortcutValidationMessage])
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}

private extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstSubview(ofType: type) {
                return match
            }
        }
        return nil
    }
}
