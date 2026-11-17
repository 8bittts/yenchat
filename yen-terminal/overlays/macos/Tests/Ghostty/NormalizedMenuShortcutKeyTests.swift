import AppKit
import Testing
@testable import YEN

@Suite
struct NormalizedMenuShortcutKeyTests {
    typealias Key = YEN.MenuShortcutManager.MenuShortcutKey

    @Test func returnsNilForEmptyKeyEquivalent() {
        let key = Key(keyEquivalent: "", modifiers: .command)
        #expect(key == nil)
    }

    @Test func stripsNonShortcutModifiers() {
        let key = Key(keyEquivalent: "c", modifiers: [.command, .capsLock, .function])
        let expected = Key(keyEquivalent: "c", modifiers: .command)
        #expect(key == expected)
    }

    @Test func preservesShortcutModifiers() {
        let key = Key(keyEquivalent: "c", modifiers: [.shift, .control, .option, .command])
        let allMods: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        #expect(key?.modifiersRawValue == allMods.rawValue)
    }

    @Test func uppercaseLetterInsertsShift() {
        let key = Key(keyEquivalent: "A", modifiers: .command)
        let expected = NSEvent.ModifierFlags([.command, .shift]).rawValue
        #expect(key?.modifiersRawValue == expected)
    }

    @Test func lowercaseLetterDoesNotInsertShift() {
        let key = Key(keyEquivalent: "a", modifiers: .command)
        let expected = NSEvent.ModifierFlags.command.rawValue
        #expect(key?.modifiersRawValue == expected)
    }

    @Test func nonCaseSensitiveCharacterDoesNotInsertShift() {
        let key = Key(keyEquivalent: "1", modifiers: .command)
        let expected = NSEvent.ModifierFlags.command.rawValue
        #expect(key?.modifiersRawValue == expected)
    }

    @Test func sameKeyAndModsAreEqual() {
        let a = Key(keyEquivalent: "c", modifiers: .command)
        let b = Key(keyEquivalent: "c", modifiers: .command)
        #expect(a == b)
    }

    @Test func uppercaseAndLowercaseWithShiftAreEqual() {
        let fromUpper = Key(keyEquivalent: "C", modifiers: .command)
        let fromLowerWithShift = Key(keyEquivalent: "c", modifiers: [.command, .shift])
        #expect(fromUpper == fromLowerWithShift)
    }

    @Test func differentKeysAreNotEqual() {
        let a = Key(keyEquivalent: "a", modifiers: .command)
        let b = Key(keyEquivalent: "b", modifiers: .command)
        #expect(a != b)
    }

    @Test func physicalKeysUseKeyCodeIdentity() {
        let physical = Key(physicalKeyCode: 0x32, modifiers: .command)
        let same = Key(physicalKeyCode: 0x32, modifiers: .command)
        let different = Key(physicalKeyCode: 0x31, modifiers: .command)
        let unicode = Key(keyEquivalent: "`", modifiers: .command)

        #expect(physical == same)
        #expect(physical != different)
        #expect(physical != unicode)
    }

    @Test func differentModifiersAreNotEqual() {
        let a = Key(keyEquivalent: "c", modifiers: .command)
        let b = Key(keyEquivalent: "c", modifiers: .option)
        #expect(a != b)
    }

    @Test func canBeUsedAsDictionaryKey() {
        let key = Key(keyEquivalent: "c", modifiers: .command)!
        var dict: [Key: String] = [:]
        dict[key] = "copy"
        #expect(dict[key] == "copy")

        let key2 = Key(keyEquivalent: "c", modifiers: .command)!
        #expect(dict[key2] == "copy")
    }
}
