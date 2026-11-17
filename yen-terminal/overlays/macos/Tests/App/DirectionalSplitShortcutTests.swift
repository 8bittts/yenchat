import AppKit
import Testing

@testable import YEN

struct DirectionalSplitShortcutTests {
    @Test(arguments: [
        (keyCode: UInt16(123), direction: DirectionalSplitDirection.left),
        (keyCode: UInt16(124), direction: DirectionalSplitDirection.right),
        (keyCode: UInt16(125), direction: DirectionalSplitDirection.down),
        (keyCode: UInt16(126), direction: DirectionalSplitDirection.up),
    ])
    func cmdDUsesTheHeldArrowDirection(keyCode: UInt16, direction: DirectionalSplitDirection) {
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "d",
            modifierFlags: .command,
            pressedKeyCodes: [keyCode]
        ) == direction)
    }

    @Test func chordRequiresCmdDAndExactlyOneArrow() {
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "d",
            modifierFlags: [],
            pressedKeyCodes: [123]
        ) == nil)
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "d",
            modifierFlags: [.command, .shift],
            pressedKeyCodes: [123]
        ) == nil)
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "x",
            modifierFlags: .command,
            pressedKeyCodes: [123]
        ) == nil)
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "d",
            modifierFlags: .command,
            pressedKeyCodes: []
        ) == nil)
        #expect(DirectionalSplitShortcut.direction(
            charactersIgnoringModifiers: "d",
            modifierFlags: .command,
            pressedKeyCodes: [123, 126]
        ) == nil)
    }
}
