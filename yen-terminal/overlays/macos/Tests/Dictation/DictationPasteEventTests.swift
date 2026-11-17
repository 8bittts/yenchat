import CoreGraphics
import Testing
@testable import YEN

struct DictationPasteEventTests {
    @Test func syntheticCommandVPasteCreatesOneCommandKeyPair() throws {
        let events = try #require(DictationPasteExecutor.makeSyntheticCommandVEvents(source: nil))
        #expect(events.keyDown.type == .keyDown)
        #expect(events.keyUp.type == .keyUp)
        #expect(events.keyDown.flags.contains(.maskCommand))
        #expect(events.keyUp.flags.contains(.maskCommand))
        #expect(events.keyDown.getIntegerValueField(.keyboardEventKeycode) == 0x09)
        #expect(events.keyUp.getIntegerValueField(.keyboardEventKeycode) == 0x09)
    }
}
