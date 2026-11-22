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

/// Which effects an outline draws right now.
struct WindowBorderEffectPlan: Equatable {
    let showsSpark: Bool
    let showsAura: Bool
    let auraPulses: Bool
}

/// The system setting that stops outline motion, if one is on.
enum WindowBorderMotionLimit: Equatable {
    case none
    case reduceMotion
    case lowPowerMode
}

/// The spark: a head and a fading tail of short segments that follow the outline.
struct WindowBorderSparkModel: Equatable {
    /// Seconds for one lap.
    let lapDuration: Double
    let segmentLength: CGFloat
    let segmentCount: Int
    /// Seconds between one segment and the next one behind it.
    let segmentDelay: Double
    let headGlowDiameter: CGFloat

    var tailLength: CGFloat {
        CGFloat(segmentCount) * WindowBorderRenderingPolicy.sparkSegmentSpacing
    }
}

/// The aura: a blurred stroke in one color, held or pulsing.
struct WindowBorderAuraModel: Equatable {
    let blurRadius: CGFloat
    let restingOpacity: Float
    let pulseLowOpacity: Float
    let pulseHighOpacity: Float
    /// Seconds from the low opacity to the high one.
    let pulseHalfPeriod: Double
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

    // MARK: Effects

    /// Reduce Motion is an accessibility choice, so it is named first when both are on.
    static func motionLimit(reduceMotion: Bool, lowPowerMode: Bool) -> WindowBorderMotionLimit {
        if reduceMotion { return .reduceMotion }
        return lowPowerMode ? .lowPowerMode : .none
    }

    /// Effects mark the focused outline only, so background windows stay still.
    /// A motion limit hides the spark and holds the aura at one opacity: the
    /// motion is decoration, and it would redraw the window all day.
    static func effectPlan(
        effects: WindowBorderEffects,
        isFocused: Bool,
        motionLimit: WindowBorderMotionLimit
    ) -> WindowBorderEffectPlan {
        let moves = motionLimit == .none
        return WindowBorderEffectPlan(
            showsSpark: isFocused && effects.sparkEnabled && moves,
            showsAura: isFocused && effects.auraEnabled,
            auraPulses: isFocused && effects.auraEnabled && moves
        )
    }

    /// Points along the outline between one spark segment and the next.
    static let sparkSegmentSpacing: CGFloat = 3
    static let sparkSpeed: CGFloat = 340
    static let sparkLapDurationRange: ClosedRange<Double> = 3...12
    static let sparkTailLengthRange: ClosedRange<CGFloat> = 48...160

    /// The spark keeps one speed on any outline, within a lap time that never
    /// races around a small pane or crawls around a large window.
    static func sparkModel(perimeter: CGFloat, lineWidth: CGFloat) -> WindowBorderSparkModel? {
        guard perimeter.isFinite, perimeter > 0, lineWidth > 0 else { return nil }
        let lapDuration = min(
            max(Double(perimeter / sparkSpeed), sparkLapDurationRange.lowerBound),
            sparkLapDurationRange.upperBound
        )
        let wantedTail = min(max(perimeter * 0.07, sparkTailLengthRange.lowerBound), sparkTailLengthRange.upperBound)
        // A tail never covers more than a quarter of the outline.
        let tailLength = min(wantedTail, perimeter / 4)
        let segmentCount = max(Int((tailLength / sparkSegmentSpacing).rounded(.down)), 1)
        return WindowBorderSparkModel(
            lapDuration: lapDuration,
            // Two segments cover every point, so the tail has no gaps and no bands.
            segmentLength: sparkSegmentSpacing * 2,
            segmentCount: segmentCount,
            segmentDelay: lapDuration * Double(sparkSegmentSpacing / perimeter),
            headGlowDiameter: max(lineWidth * 5, 8)
        )
    }

    static func auraModel(lineWidth: CGFloat, pulse: WindowBorderAuraPulse) -> WindowBorderAuraModel {
        WindowBorderAuraModel(
            blurRadius: 6 + lineWidth * 2,
            restingOpacity: 0.8,
            pulseLowOpacity: 0.5,
            pulseHighOpacity: 1,
            pulseHalfPeriod: pulse.halfPeriod
        )
    }

    /// The length of a closed path and its signed area. The area is positive
    /// when the path runs clockwise in a coordinate space whose y axis points down.
    static func pathMetrics(of path: CGPath) -> (perimeter: CGFloat, signedArea: CGFloat) {
        var perimeter: CGFloat = 0
        var doubledArea: CGFloat = 0
        var start = CGPoint.zero
        var previous = CGPoint.zero
        func addLine(to point: CGPoint) {
            perimeter += hypot(point.x - previous.x, point.y - previous.y)
            doubledArea += previous.x * point.y - point.x * previous.y
            previous = point
        }
        path.flattened(threshold: 0.25).applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                start = element.pointee.points[0]
                previous = start
            case .addLineToPoint:
                addLine(to: element.pointee.points[0])
            case .closeSubpath:
                addLine(to: start)
            default:
                break
            }
        }
        return (perimeter, doubledArea / 2)
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
