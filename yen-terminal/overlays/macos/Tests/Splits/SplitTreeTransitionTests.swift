import AppKit
import QuartzCore
import Testing
@testable import YEN

/// A split opening, closing, moving or zooming crossfades the window content
/// instead of swapping the layout in one frame.
@MainActor
struct SplitTreeTransitionTests {
    @Test func aStructureChangeFadesOverTheStandardDuration() throws {
        let fade = try #require(SplitTreeTransition.transition(reduceMotion: false, windowIsVisible: true))
        #expect(fade.type == .fade)
        #expect(fade.duration == YENMotion.standard)
    }

    @Test func reduceMotionAndHiddenWindowsChangeWithoutAFade() {
        #expect(SplitTreeTransition.transition(reduceMotion: true, windowIsVisible: true) == nil)
        #expect(SplitTreeTransition.transition(reduceMotion: false, windowIsVisible: false) == nil)
    }

    @Test func crossfadeAddsTheFadeToTheVisibleWindowsContentLayer() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView?.wantsLayer = true
        window.orderFront(nil)
        SplitTreeTransition.crossfade(window, reduceMotion: false)
        let layer = try #require(window.contentView?.layer)
        #expect(layer.animation(forKey: SplitTreeTransition.animationKey) is CATransition)
    }
}
