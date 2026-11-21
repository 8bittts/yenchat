#if os(macOS)
import SwiftUI

/// Shared design tokens for YEN's native chrome so the same value is not
/// redeclared as an independent literal across sibling files (which lets the
/// surfaces silently drift apart).
enum YENDesignTokens {
    static let paneInset: CGFloat = 4
    static let toolbarInset: CGFloat = 8

    static let contentInset: CGFloat = 12
    static let secondaryLabel: Font = .caption
    static let paneTitle: Font = secondaryLabel.weight(.semibold)

    /// Continuous rounding shared by terminal panes and the tab sidebar.
    static let terminalFacingCornerRadius: CGFloat = 10
}
#endif // os(macOS)
