//
//  TerminalViewContainerTests.swift
//  YEN
//
//  Created by Lukas on 26.02.2026.
//

import SwiftUI
import Testing
@testable import YEN

@MainActor
final class MockTerminalViewContainer: TerminalViewContainer {
    var _windowCornerRadius: CGFloat?

    override var windowThemeFrameView: NSView? {
        NSView()
    }

    override var windowCornerRadius: CGFloat? {
        _windowCornerRadius
    }
}

final class MockConfig: YEN.Config {
    internal init(backgroundBlur: YEN.Config.BackgroundBlur, backgroundColor: Color, backgroundOpacity: Double) {
        self._backgroundBlur = backgroundBlur
        self._backgroundColor = backgroundColor
        self._backgroundOpacity = backgroundOpacity
        super.init(config: nil)
    }

    var _backgroundBlur: YEN.Config.BackgroundBlur
    var _backgroundColor: Color
    var _backgroundOpacity: Double

    override var backgroundBlur: YEN.Config.BackgroundBlur {
        _backgroundBlur
    }

    override var backgroundColor: Color {
        _backgroundColor
    }

    override var backgroundOpacity: Double {
        _backgroundOpacity
    }
}

@MainActor
struct TerminalViewContainerTests {
    @Test func windowMoveWithoutDockedSidebarDoesNotScheduleCompensation() {
        let container = TerminalViewContainer(terminalContentView: NSView(), dockedSidebarVisibility: { _ in false })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = container
        defer { window.contentView = nil; window.orderOut(nil) }
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: window)
        #expect(!container.testingHasPendingSidebarCompensation)
    }

    @Test func glassAvailability() async throws {
        let view = MockTerminalViewContainer {
            EmptyView()
        }

        let config = MockConfig(backgroundBlur: .macosGlassRegular, backgroundColor: .clear, backgroundOpacity: 1)
        view.yenConfigDidChange(config, preferredBackgroundColor: nil)
        try await Task.sleep(nanoseconds: UInt64(1e8))

        let hasGlassEffectView = view.glassEffectView != nil
        if #available(macOS 26.0, *) {
            #expect(hasGlassEffectView)
        } else {
            #expect(!hasGlassEffectView)
        }
    }

}
