#if os(macOS)
import AppKit
import QuartzCore

/// Quick Terminal's reveal, applied at a terminal window's edge.
///
/// Ghostty's Quick Terminal (`QuickTerminalPosition.setInitial`/`setFinal`) keeps
/// its full size, starts one full extent past the screen edge at alpha 0, and
/// slides rigidly to rest while fading in, so the screen edge hides it until it
/// arrives. The Git drawer, Scratchpad and transient Tab Sidebar rest inside a
/// terminal window, so this view supplies that edge: it clips to its bounds, parks
/// its content one full extent past `edge`, and slides it to rest through
/// `SlidingUtilityPanel.transition`, the same envelope Quick Terminal runs.
///
/// The content's extent is constant and never animates from zero, so SwiftUI lays
/// out once and only translates. `wantsLayer` is scoped to this view, never to a
/// terminal container, so the terminal's Metal compositing is untouched. Geometry
/// assumes the default non-flipped (bottom-left origin) coordinate system.
@MainActor
final class EdgeRevealView: NSView {
    /// The edge the content hides behind and emerges from.
    enum Edge {
        case bottom
        case leading
        case trailing
    }

    struct Corners: Equatable {
        var radius: CGFloat
        var mask: CACornerMask

        static let none = Corners(radius: 0, mask: [])
    }

    let edge: Edge
    private var extentConstraint: NSLayoutConstraint?
    private var slideConstraint: NSLayoutConstraint?
    private(set) var isRevealed = false

    /// Continuous rounding applied by the clip. The Git drawer rounds the top
    /// corners that face the terminal; a panel resting flush inside a window
    /// rounds the outer corners it shares with the window to the window's radius.
    var corners: Corners = .none {
        didSet { applyCorners(to: layer) }
    }

    override var isFlipped: Bool { false }

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        applyCorners(to: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EdgeRevealView does not support nib/storyboard instantiation")
    }

    // Re-assert the clip and corners when AppKit swaps the backing layer
    // (backing-scale changes when the window moves screens), even mid-slide.
    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.masksToBounds = true
        applyCorners(to: layer)
        return layer
    }

    /// Full size of the content along the slide axis: height for `.bottom`,
    /// width for `.leading` and `.trailing`.
    var extent: CGFloat { extentConstraint?.constant ?? 0 }

    /// The offset that parks the content one full extent past `edge`.
    var parkedOffset: CGFloat { edge == .trailing ? extent : -extent }

    var slideOffset: CGFloat { slideConstraint?.constant ?? 0 }

    /// Installs `content` at a constant `extent`, parked behind the edge at alpha 0.
    func embed(_ content: NSView, extent: CGFloat) {
        for subview in subviews where subview !== content {
            subview.removeFromSuperview()
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        if content.superview !== self {
            addSubview(content)
        }

        let extentConstraint: NSLayoutConstraint
        let slideConstraint: NSLayoutConstraint
        let crossAxis: [NSLayoutConstraint]
        switch edge {
        case .bottom:
            extentConstraint = content.heightAnchor.constraint(equalToConstant: extent)
            slideConstraint = content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -extent)
            crossAxis = [
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
            ]
        case .leading:
            extentConstraint = content.widthAnchor.constraint(equalToConstant: extent)
            slideConstraint = content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -extent)
            crossAxis = [
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        case .trailing:
            extentConstraint = content.widthAnchor.constraint(equalToConstant: extent)
            slideConstraint = content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: extent)
            crossAxis = [
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(crossAxis + [extentConstraint, slideConstraint])
        self.extentConstraint = extentConstraint
        self.slideConstraint = slideConstraint
        isRevealed = false
        alphaValue = 0
    }

    /// Resizes without moving: a resting surface stays flush, a parked one stays hidden.
    func setExtent(_ extent: CGFloat) {
        guard let extentConstraint, extentConstraint.constant != extent else { return }
        extentConstraint.constant = extent
        if !isRevealed {
            slideConstraint?.constant = parkedOffset
        }
    }

    /// Vendor `setInitial`: hidden behind the edge at alpha 0, laid out without animation.
    func park(layoutRoot: NSView? = nil) {
        isRevealed = false
        slideConstraint?.constant = parkedOffset
        alphaValue = 0
        (layoutRoot ?? self).layoutSubtreeIfNeeded()
    }

    /// At rest and opaque without animation, for re-anchoring a surface already on screen.
    func showAtRest(layoutRoot: NSView? = nil) {
        isRevealed = true
        slideConstraint?.constant = 0
        alphaValue = 1
        (layoutRoot ?? self).layoutSubtreeIfNeeded()
    }

    /// The only enter and exit motion for edge-revealed surfaces: one full extent
    /// of rigid travel plus the alpha fade, inside the shared Quick Terminal
    /// envelope. Reduce Motion passes a zero duration through this same path.
    func slide(
        _ phase: SlidingUtilityPanel.Phase,
        duration: TimeInterval,
        layoutRoot: NSView? = nil,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let entering = phase == .entering
        isRevealed = entering
        slideConstraint?.constant = entering ? 0 : parkedOffset
        let root = layoutRoot ?? self
        root.needsLayout = true
        SlidingUtilityPanel.transition(
            phase,
            duration: duration,
            changes: {
                self.animator().alphaValue = entering ? 1 : 0
                // `animator().layoutSubtreeIfNeeded()`, not a bare call, is what
                // plays the constraint change as an animation.
                root.animator().layoutSubtreeIfNeeded()
            },
            completion: completion
        )
    }

    private func applyCorners(to layer: CALayer?) {
        guard let layer else { return }
        layer.cornerRadius = corners.radius
        layer.cornerCurve = .continuous
        layer.maskedCorners = corners.mask
    }
}

/// Geometry for a utility panel that rests flush inside a terminal window's content
/// area, against one side edge, the way Quick Terminal rests against a screen edge.
enum EdgeRevealPanelGeometry {
    /// Ghostty's titled-window radius, used when AppKit does not expose the live one.
    static let fallbackWindowCornerRadius: CGFloat = 16

    /// The rest frame: full content-area height, `width` wide, flush with `edge`.
    static func restFrame(
        contentFrame: NSRect,
        edge: EdgeRevealView.Edge,
        width: CGFloat
    ) -> NSRect {
        let x = edge == .trailing ? contentFrame.maxX - width : contentFrame.minX
        return NSRect(x: x, y: contentFrame.minY, width: width, height: contentFrame.height)
    }

    /// The outer corners a panel at `panelFrame` shares with the window frame. They
    /// must take the window's own radius, or the panel's square corner shows past
    /// the window's rounded one.
    static func sharedWindowCorners(
        panelFrame: NSRect,
        windowFrame: NSRect,
        edge: EdgeRevealView.Edge
    ) -> CACornerMask {
        let tolerance: CGFloat = 0.5
        var mask: CACornerMask = []
        let touchesBottom = abs(panelFrame.minY - windowFrame.minY) <= tolerance
        let touchesTop = abs(panelFrame.maxY - windowFrame.maxY) <= tolerance
        switch edge {
        case .leading:
            if touchesBottom { mask.insert(.layerMinXMinYCorner) }
            if touchesTop { mask.insert(.layerMinXMaxYCorner) }
        case .trailing:
            if touchesBottom { mask.insert(.layerMaxXMinYCorner) }
            if touchesTop { mask.insert(.layerMaxXMaxYCorner) }
        case .bottom:
            break
        }
        return mask
    }

    @MainActor
    static func windowCornerRadius(of window: NSWindow) -> CGFloat {
        if window.responds(to: Selector(("_cornerRadius"))),
           let radius = window.value(forKey: "_cornerRadius") as? CGFloat,
           radius > 0 {
            return radius
        }
        return fallbackWindowCornerRadius
    }

    /// Positions `panel` at rest inside `window` against `edge`, and rounds the corners
    /// its `EdgeRevealView` content shares with the window.
    @MainActor
    static func place(
        _ panel: NSWindow,
        edge: EdgeRevealView.Edge,
        in window: NSWindow,
        width: CGFloat
    ) {
        let contentFrame = window.convertToScreen(window.contentLayoutRect)
        let frame = restFrame(contentFrame: contentFrame, edge: edge, width: width)
        panel.setFrame(frame, display: true)
        (panel.contentView as? EdgeRevealView)?.corners = .init(
            radius: windowCornerRadius(of: window),
            mask: sharedWindowCorners(panelFrame: frame, windowFrame: window.frame, edge: edge)
        )
    }
}
#endif
