#if os(macOS)
import SwiftUI

/// Shared design tokens for YEN's native chrome so the same value is not
/// redeclared as an independent literal across sibling files (which lets the
/// surfaces silently drift apart).
enum YENDesignTokens {
    static let paneInset: CGFloat = 4

    static let contentInset: CGFloat = 12
    static let secondaryLabel: Font = YENTypography.caption
    static let paneTitle: Font = secondaryLabel.weight(.semibold)

    /// Continuous rounding shared by terminal panes and the tab sidebar.
    static let terminalFacingCornerRadius: CGFloat = 10
}

/// The one type scale for YEN's native chrome and Settings. Each role is a
/// system text style, so every surface follows the same steps and scales
/// together with the system text size. Views pick a role and, at most, a
/// weight (regular, medium or semibold); they never set a point size. A
/// view's weight never depends on its state, because a heavier face is
/// wider and the text would visibly change size on focus or selection.
enum YENTypography {
    /// 26 pt: the symbol in an empty state.
    static let largeTitle: Font = .largeTitle
    /// 17 pt: a window's own title and the command palette's query.
    static let title: Font = .title2
    /// 15 pt: Settings pane titles and empty-state titles.
    static let sectionTitle: Font = .title3
    /// 13 pt semibold: section headers and card titles.
    static let headline: Font = .body.weight(.semibold)
    /// 13 pt: rows, tab titles, toasts and messages.
    static let body: Font = .body
    /// 12 pt: notes and dense list text.
    static let callout: Font = .callout
    /// 11 pt: metadata, hints and captions.
    static let secondary: Font = .subheadline
    /// 10 pt: shortcut glyphs, counts and pane headers.
    static let caption: Font = .caption
}

/// The shared timings for YEN's own transitions. Things that appear or change
/// structure ease out; things that leave ease in. Edge panels keep their own
/// configurable envelope (`SlidingUtilityPanel`).
enum YENMotion {
    /// Hover, selection and disclosure feedback.
    static let quick: TimeInterval = 0.12
    /// Overlays, toasts, borders and split layout changes.
    static let standard: TimeInterval = 0.2

    static func appear(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: standard)
    }

    static func disappear(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeIn(duration: standard)
    }

    static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: quick)
    }
}
#endif // os(macOS)
