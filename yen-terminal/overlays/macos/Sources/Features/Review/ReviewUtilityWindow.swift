#if os(macOS)
    import AppKit
    import SwiftUI

    /// Shared chrome for the two review utility windows (PR Review + Merge
    /// Conflict) so their status banner and split-pane widths stay in sync
    /// instead of drifting as byte-duplicated copies.
    enum ReviewChrome {
        // Shared three-pane split widths.
        static let fileListMinWidth: CGFloat = 250
        static let fileListIdealWidth: CGFloat = 290
        static let detailMinWidth: CGFloat = 480
        static let detailIdealWidth: CGFloat = 620
        static let sidebarMinWidth: CGFloat = 360
        static let sidebarIdealWidth: CGFloat = 400

        /// Status/error banner shared by both review windows.
        static func statusBanner(message: String, isError: Bool) -> some View {
            HStack(spacing: 8) {
                Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
                    .font(YENTypography.secondary.weight(.semibold))
                Text(message)
                    .font(YENTypography.secondary)
                    .lineLimit(6)
                Spacer(minLength: 0)
            }
            .foregroundColor(isError ? .red : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background((isError ? Color.red : Color.secondary).opacity(isError ? 0.08 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Shared window factory for the review utility windows (PR Review, Merge
    /// Conflict Resolution), which had byte-identical `NSWindow` setup differing
    /// only by title and sizes.
    @MainActor
    func makeReviewUtilityWindow(
        title: String,
        contentSize: NSSize,
        minSize: NSSize,
        contentView: NSView,
        delegate: NSWindowDelegate
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = contentView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.titlebarAppearsTransparent = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = minSize
        window.toolbarStyle = .automatic
        return window
    }
#endif
