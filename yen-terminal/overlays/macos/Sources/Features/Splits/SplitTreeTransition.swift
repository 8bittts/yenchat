import AppKit
import QuartzCore

/// Crossfades a terminal window's content when its split structure changes: a
/// pane opens, closes, moves, or zooms. Without it the layout swaps in one
/// frame, the pane headers appear or vanish, and the remaining text jumps.
///
/// The fade is a Core Animation transition on the window's content layer, so
/// the window server blends the last frame into the new layout, Metal surfaces
/// included. No surface resizes per frame and no shell sees extra resizes.
/// Divider drags change only ratios, which keep the structural identity, so
/// they never fade.
enum SplitTreeTransition {
    /// Core Animation files every transition under this key, whatever key is passed.
    static let animationKey = kCATransition

    /// Returns the transition for a structure change, or nil when the window
    /// should change without one.
    static func transition(reduceMotion: Bool, windowIsVisible: Bool) -> CATransition? {
        guard !reduceMotion, windowIsVisible else { return nil }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = YENMotion.standard
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return fade
    }

    @MainActor
    static func crossfade(_ window: NSWindow?, reduceMotion: Bool) {
        guard let window, let layer = window.contentView?.layer,
              let fade = transition(reduceMotion: reduceMotion, windowIsVisible: window.isVisible) else { return }
        layer.add(fade, forKey: animationKey)
    }
}
