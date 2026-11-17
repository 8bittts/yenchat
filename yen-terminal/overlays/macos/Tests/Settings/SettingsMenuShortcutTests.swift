import AppKit
import Testing
@testable import YEN

struct SettingsMenuShortcutTests {
    @Test func commandCommaRemainsReservedForSettings() {
        #expect(AppDelegate.isReservedSettingsShortcut(keyEquivalent: ",", modifiers: [.command]))
        #expect(!AppDelegate.isReservedSettingsShortcut(keyEquivalent: ",", modifiers: [.command, .shift]))
        #expect(!AppDelegate.isReservedSettingsShortcut(keyEquivalent: ",", modifiers: [.command, .option]))
        #expect(!AppDelegate.isReservedSettingsShortcut(keyEquivalent: ".", modifiers: [.command]))
    }
}
