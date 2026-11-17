#if os(macOS)
import CoreGraphics

/// Shared design tokens for YEN's native chrome so the same value is not
/// redeclared as an independent literal across sibling files (which lets the
/// surfaces silently drift apart).
enum YENDesignTokens {
    /// Continuous corner radius applied to the terminal-facing edge of the four
    /// sliding surfaces (Quick Terminal, Local Git Drawer, Tab Sidebar,
    /// Scratchpad). See `_docs/01-architecture.md` → "Native-First Interaction
    /// Parity".
    static let terminalFacingCornerRadius: CGFloat = 10
}
#endif // os(macOS)
