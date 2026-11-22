import CoreGraphics
import Foundation

enum WindowBorderChromeMode: String, CaseIterable {
    case native
    case transparent
    case tabs
    case hidden
    case decorationNone
}

/// Where a window-scoped outline is drawn.
enum WindowOutlinePlacement: Equatable {
    /// Along the window's clipping edge, with the native corner radius and padded content.
    case windowEdge
    /// Along the outer edge of the framed pane grid, where a focused pane outline sits.
    case paneGrid
}

struct WindowBorderStrokeModel {
    let lineWidth: CGFloat
    let inset: CGFloat
    let cornerRadius: CGFloat
    let dashPattern: [CGFloat]
}

enum WindowBorderRenderingPolicy {
    static func chromeMode(titlebarStyle: YEN.Config.MacOSTitlebarStyle, hasWindowDecorations: Bool) -> WindowBorderChromeMode {
        guard hasWindowDecorations else { return .decorationNone }

        switch titlebarStyle {
        case .native:
            return .native
        case .tabs:
            return .tabs
        case .hidden:
            return .hidden
        case .transparent:
            return .transparent
        }
    }

    static func shouldShowBorder(
        enabled: Bool,
        hasHostingWindow: Bool,
        isFullscreen: Bool,
        isPanelWindow: Bool,
        isQuickTerminalWindow: Bool
    ) -> Bool {
        guard enabled else { return false }
        guard hasHostingWindow else { return false }
        guard !isFullscreen else { return false }
        guard !isPanelWindow else { return false }
        guard !isQuickTerminalWindow else { return false }
        return true
    }

    /// Framed panes already sit inside the window's corners, so the window outline
    /// shares their frame. Edge-to-edge panes and the browser split reach the
    /// clipping edge, where only the native corner radius stays visible.
    static func windowOutlinePlacement(panesAreFramed: Bool, browserSplitVisible: Bool) -> WindowOutlinePlacement {
        panesAreFramed && !browserSplitVisible ? .paneGrid : .windowEdge
    }

    static func shouldHandleWindowNotification(
        observedWindowNumber: Int,
        hostingWindowNumber: Int?,
        activeSurfaceWindowNumber: Int?,
        trackedWindowNumber: Int?
    ) -> Bool {
        if let hostingWindowNumber, observedWindowNumber == hostingWindowNumber {
            return true
        }
        if let activeSurfaceWindowNumber, observedWindowNumber == activeSurfaceWindowNumber {
            return true
        }
        if let trackedWindowNumber, observedWindowNumber == trackedWindowNumber {
            return true
        }
        return false
    }

    static func isWindowFocused(
        windowIsKey: Bool,
        windowIsMain: Bool,
        appIsActive: Bool
    ) -> Bool {
        guard appIsActive else { return false }
        return windowIsKey || windowIsMain
    }

    static func shouldIgnoreTopSafeArea(titlebarStyle: YEN.Config.MacOSTitlebarStyle) -> Bool {
        titlebarStyle == .hidden
    }

    static func shouldUseDashedUnfocusedStyle(differentiateWithoutColor: Bool) -> Bool {
        differentiateWithoutColor
    }

    static func lineWidth(for requestedWidth: Double) -> CGFloat {
        CGFloat(WindowBorderPreferences.clampedWidth(requestedWidth))
    }

    static func inset(forLineWidth lineWidth: CGFloat) -> CGFloat {
        lineWidth / 2
    }

    static func dashPattern(
        forLineWidth lineWidth: CGFloat,
        isFocused: Bool,
        useDashedUnfocusedStyle: Bool
    ) -> [CGFloat] {
        guard useDashedUnfocusedStyle, !isFocused else { return [] }
        let base = max(lineWidth * 2.0, 4.0)
        return [base, max(base * 0.8, 3.0)]
    }

    static func strokeModel(
        width: Double,
        radius: Double,
        chromeMode: WindowBorderChromeMode,
        isFocused: Bool,
        useDashedUnfocusedStyle: Bool
    ) -> WindowBorderStrokeModel {
        let lineWidth = lineWidth(for: width)
        return WindowBorderStrokeModel(
            lineWidth: lineWidth,
            inset: inset(forLineWidth: lineWidth),
            cornerRadius: effectiveCornerRadius(
                requestedRadius: radius,
                lineWidth: lineWidth,
                chromeMode: chromeMode
            ),
            dashPattern: dashPattern(
                forLineWidth: lineWidth,
                isFocused: isFocused,
                useDashedUnfocusedStyle: useDashedUnfocusedStyle
            )
        )
    }

    static func focusedSplitBorderFrame(
        surfaceFrameInWindow: CGRect,
        terminalFrameInWindow: CGRect
    ) -> CGRect? {
        guard !surfaceFrameInWindow.isEmpty, !terminalFrameInWindow.isEmpty else { return nil }

        // AppKit window coordinates use a bottom-left origin while SwiftUI view
        // placement uses top-left-style local coordinates, so Y must be flipped.
        let relativeFrame = CGRect(
            x: surfaceFrameInWindow.minX - terminalFrameInWindow.minX,
            y: terminalFrameInWindow.maxY - surfaceFrameInWindow.maxY,
            width: surfaceFrameInWindow.width,
            height: surfaceFrameInWindow.height
        )

        let terminalBounds = CGRect(origin: .zero, size: terminalFrameInWindow.size)
        let clipped = relativeFrame.intersection(terminalBounds)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }
        return clipped
    }

    static func effectiveCornerRadius(
        requestedRadius: Double,
        lineWidth: CGFloat,
        chromeMode: WindowBorderChromeMode
    ) -> CGFloat {
        let clampedRadius = CGFloat(WindowBorderPreferences.clampedRadius(requestedRadius))
        let inset = inset(forLineWidth: lineWidth)
        let modeOffset = clampedRadius >= inset ? chromeMode.cornerRadiusOffset : 0
        return max(clampedRadius + modeOffset - inset, 0)
    }

}

private extension WindowBorderChromeMode {
    var cornerRadiusOffset: CGFloat {
        switch self {
        case .tabs:
            // Upstream tabs windows render with a larger window corner radius.
            return 1.0
        case .native, .transparent, .hidden, .decorationNone:
            return 0
        }
    }
}
