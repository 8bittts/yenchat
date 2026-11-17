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

    @Test func gitDrawerHostAttachesAndRemovesBottomOverlay() async throws {
        let terminalContent = NSView()
        let container = TerminalViewContainer(
            terminalContentView: terminalContent,
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let drawer = NSView()

        container.setGitDrawerHostingView(drawer, preferredHeight: 600)
        container.layoutSubtreeIfNeeded()

        // The drawer now lives inside the layer-backed clip wrapper, which is the
        // topmost container subview (added `.above` the terminal view) and masks the
        // drawer's off-screen tail during the slide.
        let clip = try #require(container.subviews.last as? EdgeRevealView)
        #expect(clip.edge == .bottom)
        #expect(drawer.superview === clip)
        #expect(clip.superview === container)
        #expect(clip.layer?.masksToBounds == true)
        #expect(clip.isRevealed)
        #expect(clip.slideOffset == 0)
        #expect(container.gitDrawerHeight == 560)
        #expect(terminalContent.frame == container.bounds)
        // Clip wrapper is pinned to the bottom edge, full width, constant height H.
        #expect(clip.frame.minY == 0)
        #expect(clip.frame.height == 560)
        #expect(clip.frame.width == 1_000)
        // Duration 0 still uses the shared park→transition envelope and lands flush
        // inside the clip (slide constant 0), full height H, fully opaque.
        #expect(drawer.frame.minY == 0)
        #expect(drawer.frame.height == 560)
        #expect(clip.alphaValue == 1)

        container.setGitDrawerHostingView(nil, preferredHeight: 0)
        container.layoutSubtreeIfNeeded()

        // Teardown is DEFERRED to the shared `SlidingUtilityPanel.transition(.exiting)`
        // completion handler, per the native-first parity rule in `_docs/01-architecture.md`.
        // `NSAnimationContext.runAnimationGroup` fires that handler on a later runloop
        // turn even at duration 0, so the clip legitimately outlives this call. Await the
        // exit envelope instead of asserting synchronous removal: making the product tear
        // down synchronously to satisfy a synchronous assertion would break the parity rule
        // this suite exists to protect.
        var spins = 0
        while container.subviews.contains(where: { $0 is EdgeRevealView }), spins < 200 {
            try await Task.sleep(nanoseconds: 10_000_000)
            spins += 1
        }

        #expect(drawer.superview == nil)
        #expect(container.gitDrawerHeight == nil)
        #expect(terminalContent.frame == container.bounds)
        #expect(container.subviews.contains(where: { $0 is EdgeRevealView }) == false)
    }

    @Test func gitDrawerAnimatedAttachKeepsConstantHeightAndClips() throws {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let drawer = NSView()

        // Animated attach: the drawer must slide as a CONSTANT-height panel inside the
        // clip (not a height-growth accordion). A grow animation would start the
        // drawer height at 0; here it is pinned at H from the first frame.
        container.setGitDrawerHostingView(drawer, preferredHeight: 600, animationDuration: 0.2)
        container.layoutSubtreeIfNeeded()

        let clip = try #require(container.subviews.last as? EdgeRevealView)
        #expect(drawer.superview === clip)
        #expect(container.gitDrawerHeight == 560)
        #expect(drawer.frame.height == 560)
        // masksToBounds must hold, and must survive a backing-layer swap (the
        // makeBackingLayer override re-asserts it on screen/scale changes).
        #expect(clip.layer?.masksToBounds == true)
        #expect(clip.makeBackingLayer().masksToBounds == true)
    }

    @Test func gitDrawerReattachReplacesPreviousClipWrapper() throws {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)

        let first = NSView()
        container.setGitDrawerHostingView(first, preferredHeight: 600)
        container.layoutSubtreeIfNeeded()

        // Re-attaching a different hosting view tears down the prior clip so there is
        // never more than one EdgeRevealView alive.
        let second = NSView()
        container.setGitDrawerHostingView(second, preferredHeight: 600)
        container.layoutSubtreeIfNeeded()

        #expect(first.superview == nil)
        let clips = container.subviews.compactMap { $0 as? EdgeRevealView }
        #expect(clips.count == 1)
        #expect(second.superview === clips.first)
    }

}
