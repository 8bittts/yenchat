import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
@testable import YEN

/// The Tab Sidebar once re-derived its background from the Settings theme
/// catalog by exact name. Any state the engine resolves differently then drew
/// a rail that did not match the terminal: no `theme` line, a name that differs
/// only in case, an explicit `background`, or a theme given by path.
@MainActor
@Suite(.serialized)
struct TerminalChromeAppearanceTests {
    @Test func startsFromTheEngineResolvedBackground() throws {
        let config = try TemporaryConfig("background = #112233\n")
        let appearance = TerminalChromeAppearance(
            config: config,
            notificationCenter: NotificationCenter()
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x11, green: 0x22, blue: 0x33))
    }

    @Test func explicitBackgroundWinsWithoutAnyTheme() throws {
        // No `theme` key at all: the catalog lookup had nothing to match and fell
        // back to the system window color while the terminal drew this one.
        let config = try TemporaryConfig("background = #0a0b0c\nforeground = #ffffff\n")
        let appearance = TerminalChromeAppearance(
            config: config,
            notificationCenter: NotificationCenter()
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x0a, green: 0x0b, blue: 0x0c))
    }

    @Test func followsAppLevelConfigChanges() throws {
        let center = NotificationCenter()
        let appearance = TerminalChromeAppearance(
            config: try TemporaryConfig("background = #112233\n"),
            notificationCenter: center
        )
        var emissionCount = 0
        let cancellable = appearance.objectWillChange.sink { emissionCount += 1 }
        defer { cancellable.cancel() }

        let updated = try TemporaryConfig("background = #445566\n")
        center.post(
            name: .yenConfigDidChange,
            object: nil,
            userInfo: [Notification.Name.YENConfigChangeKey: updated]
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x44, green: 0x55, blue: 0x66))
        #expect(emissionCount == 1)

        // An unchanged color must not republish; the rail would redraw on every reload.
        center.post(
            name: .yenConfigDidChange,
            object: nil,
            userInfo: [Notification.Name.YENConfigChangeKey: updated]
        )

        #expect(emissionCount == 1)
    }

    @Test func ignoresSurfaceLevelConfigChanges() throws {
        let center = NotificationCenter()
        let appearance = TerminalChromeAppearance(
            config: try TemporaryConfig("background = #112233\n"),
            notificationCenter: center
        )

        // A surface-level change carries its surface as the object. One pane's
        // config must not recolor chrome shared by the whole window.
        center.post(
            name: .yenConfigDidChange,
            object: NSObject(),
            userInfo: [
                Notification.Name.YENConfigChangeKey: try TemporaryConfig("background = #ff0000\n"),
            ]
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x11, green: 0x22, blue: 0x33))
    }

    @Test func fallsBackToTheSystemWindowColorWithoutAConfig() {
        let appearance = TerminalChromeAppearance(
            config: nil,
            notificationCenter: NotificationCenter()
        )

        #expect(appearance.backgroundColor == Color(NSColor.windowBackgroundColor))
    }

    private struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func rgb(_ color: Color) -> RGB? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGB(
            red: Int((converted.redComponent * 255).rounded()),
            green: Int((converted.greenComponent * 255).rounded()),
            blue: Int((converted.blueComponent * 255).rounded())
        )
    }
}
