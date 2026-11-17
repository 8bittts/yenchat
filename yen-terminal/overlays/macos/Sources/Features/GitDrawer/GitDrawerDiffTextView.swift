#if os(macOS)
import AppKit
import SwiftUI

enum SelectableDiffTextRenderingMode: Equatable, Sendable {
    case unifiedDiff
    case plain
}

struct SelectableDiffTextLineClassifier: Sendable {
    private var unifiedDiffClassifier = GitDrawerDiffLineClassifier.Stream()

    mutating func role(
        for line: String,
        renderingMode: SelectableDiffTextRenderingMode
    ) -> GitDrawerDiffLineRole {
        switch renderingMode {
        case .unifiedDiff:
            return unifiedDiffClassifier.role(for: line)
        case .plain:
            return .context
        }
    }
}

/// Read-only, selectable AppKit text view for unified diffs or plain source text.
///
/// Shared read-only diff surface used by the Git drawer, PR Review, and Merge
/// Conflict previews (adopt it via the feature-neutral `SelectableDiffTextView`
/// alias below). Replaces a SwiftUI `Text(.textSelection(.enabled))` diff so the
/// surface is backed by a real `NSTextView`. That makes "Copy on Select" work:
/// selection lives in the AppKit responder chain and copying is driven by the
/// text view's own selection delegate (`textViewDidChangeSelection`) — the same
/// hook the Scratchpad uses — instead of a global mouse monitor that never sees
/// the selection-terminating mouse-up of a SwiftUI `Text`. Diff text is
/// naturally pinned to the top-leading corner, satisfying the Scrollable Text
/// Surface Alignment standard in `_docs/01-architecture.md`.
struct GitDrawerDiffTextView: NSViewRepresentable {
    let diffText: String
    let accessibilityLabel: String
    /// Stable identity of the selected repository target. This is separate from
    /// the accessibility label because two hunks can have identical content and
    /// the same user-facing side label while still requiring a fresh viewport.
    let renderIdentity: String
    var renderingMode: SelectableDiffTextRenderingMode = .unifiedDiff
    /// Only the Git drawer needs a focus probe (to suppress j/k file navigation
    /// while the diff holds first responder). PR Review / Merge Conflict adopt
    /// the view without one, so it is optional.
    var focusProbe: GitDrawerDiffFocusProbe? = nil
    @ScaledMetric(relativeTo: .body) private var scaledFontSize: CGFloat = 12

    private static let inset: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = GitDrawerSemanticColors.diffBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        // Never wrap: wide diff lines scroll horizontally instead of reflowing.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        focusProbe?.textView = textView
        apply(diffText, to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        focusProbe?.textView = textView
        if Self.requiresRender(
            renderedDiff: context.coordinator.renderedDiff,
            renderedAccessibilityLabel: context.coordinator.renderedAccessibilityLabel,
            renderedIdentity: context.coordinator.renderedIdentity,
            renderedMode: context.coordinator.renderingMode,
            renderedFontSize: context.coordinator.renderedFontSize,
            diffText: diffText,
            accessibilityLabel: accessibilityLabel,
            renderIdentity: renderIdentity,
            renderingMode: renderingMode,
            fontSize: scaledFontSize
        ) {
            apply(diffText, to: textView, coordinator: context.coordinator)
        }
    }

    nonisolated static func requiresRender(
        renderedDiff: String?,
        renderedAccessibilityLabel: String?,
        renderedIdentity: String?,
        renderedMode: SelectableDiffTextRenderingMode?,
        renderedFontSize: CGFloat?,
        diffText: String,
        accessibilityLabel: String,
        renderIdentity: String,
        renderingMode: SelectableDiffTextRenderingMode,
        fontSize: CGFloat
    ) -> Bool {
        renderedDiff != diffText
            || renderedAccessibilityLabel != accessibilityLabel
            || renderedIdentity != renderIdentity
            || renderedMode != renderingMode
            || renderedFontSize != fontSize
    }

    private func apply(_ diffText: String, to textView: NSTextView, coordinator: Coordinator) {
        textView.textStorage?.setAttributedString(
            GitDrawerDiffAttributedString.make(
                diffText,
                font: .monospacedSystemFont(ofSize: scaledFontSize, weight: .regular),
                renderingMode: renderingMode
            )
        )
        Self.resetSelectionAndViewport(in: textView)
        textView.setAccessibilityLabel(accessibilityLabel)
        coordinator.renderedDiff = diffText
        coordinator.renderedAccessibilityLabel = accessibilityLabel
        coordinator.renderedIdentity = renderIdentity
        coordinator.renderingMode = renderingMode
        coordinator.renderedFontSize = scaledFontSize
    }

    /// A new file/hunk must open at its first line even when the previous target
    /// was scrolled or selected. Reset both axes explicitly because replacing an
    /// NSTextView's storage does not reset its enclosing clip-view bounds.
    @MainActor
    static func resetSelectionAndViewport(in textView: NSTextView) {
        // An empty range never triggers a copy-on-select clipboard write.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        guard let scrollView = textView.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var renderedDiff: String?
        var renderedAccessibilityLabel: String?
        var renderedIdentity: String?
        var renderingMode: SelectableDiffTextRenderingMode?
        var renderedFontSize: CGFloat?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MainActor.assumeIsolated {
                _ = CopyOnSelectClipboard.copyIfEnabled(
                    textView,
                    enabled: SettingsController.shared.copyOnSelect
                )
            }
        }
    }
}

/// Feature-neutral names for the shared read-only diff surface. The canonical
/// implementation lives here for historical reasons; non-GitDrawer call sites
/// (PR Review, Merge Conflict) reference these aliases instead of the
/// GitDrawer-prefixed type so the shared intent reads clearly at the call site.
typealias SelectableDiffTextView = GitDrawerDiffTextView
typealias SelectableDiffFocusProbe = GitDrawerDiffFocusProbe

/// Lets the SwiftUI Git drawer ask, at keypress time, whether the AppKit diff
/// `NSTextView` currently holds first responder — so `j`/`k` file navigation is
/// suppressed while the user is reading/selecting the diff (restoring the focus
/// scoping the SwiftUI `Text` diff had via `.focused(_:equals:.diff)`).
///
/// Pull-based (queried when a shortcut fires, not pushed on focus change) so it
/// can never wedge in a stale "focused" state if a resign callback is missed.
final class GitDrawerDiffFocusProbe {
    weak var textView: NSTextView?

    @MainActor
    var isDiffFirstResponder: Bool {
        guard let textView, let window = textView.window else { return false }
        return window.firstResponder === textView
    }
}

/// Builds the colored diff attributed string, mapping each line to its
/// `GitDrawerDiffLineRole` foreground color. Pure and synchronously testable.
enum GitDrawerDiffAttributedString {
    nonisolated static func make(
        _ diffText: String,
        font: NSFont,
        renderingMode: SelectableDiffTextRenderingMode = .unifiedDiff
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = diffText.split(separator: "\n", omittingEmptySubsequences: false)
        var lineClassifier = SelectableDiffTextLineClassifier()
        for (offset, line) in lines.enumerated() {
            if offset > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
            let lineString = String(line)
            let role = lineClassifier.role(for: lineString, renderingMode: renderingMode)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: GitDrawerSemanticColors.diffTextColor(for: role),
            ]
            result.append(NSAttributedString(string: lineString, attributes: attributes))
        }
        return result
    }
}
#endif
