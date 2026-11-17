#if os(macOS)
import Cocoa
import QuartzCore

/// Native Quick Terminal motion contract for every YEN sliding surface:
/// fixed geometry, rigid translation, alpha fade, 0.2 seconds, and ease-in in
/// both directions. Quick Terminal moves its window past the screen edge; the
/// Git drawer, Scratchpad and transient Tab Sidebar reveal from behind a
/// terminal window edge through `EdgeRevealView`.
@MainActor
enum SlidingUtilityPanel {
    enum Phase {
        case entering
        case exiting
    }

    nonisolated static let defaultAnimationDuration: TimeInterval = 0.2

    nonisolated static func animationDuration(
        configuredDuration: TimeInterval = defaultAnimationDuration,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> TimeInterval {
        reduceMotion ? 0 : max(0, configuredDuration)
    }

    static func currentAnimationDuration(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> TimeInterval {
        let configuredDuration = AppDelegate.shared?
            .yen.config.quickTerminalAnimationDuration ?? defaultAnimationDuration
        return animationDuration(
            configuredDuration: configuredDuration,
            reduceMotion: reduceMotion
        )
    }

    /// The only animation envelope used by Quick Terminal, Git Drawer,
    /// transient Tab Sidebar, and Scratchpad. Ghostty's Quick Terminal is the
    /// reference: both directions use one fixed geometry transition, alpha,
    /// and an ease-in curve. A zero-duration animation context preserves this
    /// exact sequence for Reduce Motion without invoking an animator proxy
    /// outside a context (which could pick up AppKit's default duration).
    static func transition(
        _ phase: Phase,
        duration: TimeInterval,
        changes: () -> Void,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        // AppKit calls the completion on the main thread. Assert that
        // synchronously instead of hopping through a Task, so exit teardown
        // stays synchronous with the end of the animation.
        let completionHandler: (@Sendable () -> Void)? = completion.map { handler in
            { @Sendable in MainActor.assumeIsolated { handler() } }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = timingFunction(for: phase)
            changes()
        }, completionHandler: completionHandler)
    }

    private static func timingFunction(for phase: Phase) -> CAMediaTimingFunction {
        switch phase {
        case .entering, .exiting:
            CAMediaTimingFunction(name: .easeIn)
        }
    }

}
#endif
