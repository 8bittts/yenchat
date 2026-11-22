import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

struct WindowBorderOverlay: View {
    let gradient: WindowBorderGradient
    let width: Double
    var radius: Double
    var chromeMode: WindowBorderChromeMode
    let isFocused: Bool
    let useDashedUnfocusedStyle: Bool

    // A terminal that meets the window edge must follow AppKit's clipping mask.
    var minimumCornerRadius: CGFloat = 0
    var effects: WindowBorderEffects = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var strokeModel: WindowBorderStrokeModel {
        WindowBorderRenderingPolicy.strokeModel(
            width: width,
            radius: radius,
            chromeMode: chromeMode,
            isFocused: isFocused,
            useDashedUnfocusedStyle: useDashedUnfocusedStyle
        )
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: strokeModel.lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: strokeModel.dashPattern
        )
    }

    /// A framed outline owns its frame. An unframed one meets the window's
    /// clipping edge and stays a point inside it.
    private func edgeGap(framed: Bool) -> CGFloat {
        framed ? 0 : 1
    }

    func contentInset(framed: Bool) -> CGFloat {
        let corner = framed ? YENDesignTokens.terminalFacingCornerRadius : max(minimumCornerRadius, strokeModel.cornerRadius)
        let stroke = strokeModel.lineWidth
        // Leave a clear pixel band inside the curve, even with zero terminal grid padding.
        return edgeGap(framed: framed) + ceil(stroke + max(0, corner - stroke) / 2) + 2
    }

    func paneBorder(framed: Bool) -> some View {
        var border = self
        if framed {
            border.radius = Double(YENDesignTokens.terminalFacingCornerRadius)
            border.chromeMode = .decorationNone
            border.minimumCornerRadius = YENDesignTokens.terminalFacingCornerRadius
        }
        return border.padding(edgeGap(framed: framed))
    }

    /// The spark is the outline's own color, lifted most of the way to white.
    static func sparkColor(for gradient: WindowBorderGradient) -> NSColor {
        let start = NSColor(gradient.startColor).usingColorSpace(.sRGB) ?? .white
        let end = NSColor(gradient.endColor).usingColorSpace(.sRGB) ?? .white
        let middle = start.blended(withFraction: 0.5, of: end) ?? start
        return (middle.blended(withFraction: 0.8, of: .white) ?? .white).withAlphaComponent(1)
    }

    var body: some View {
        let stroke = strokeModel
        let cornerRadius = max(minimumCornerRadius, stroke.cornerRadius)
        let plan = WindowBorderRenderingPolicy.effectPlan(
            effects: effects,
            isFocused: isFocused,
            reduceMotion: reduceMotion
        )
        let geometry = WindowBorderEffectGeometry(
            cornerRadius: cornerRadius,
            inset: stroke.inset,
            lineWidth: stroke.lineWidth
        )
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: stroke.inset)
            .stroke(
                LinearGradient(
                    colors: [gradient.startColor, gradient.endColor],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: strokeStyle
            )
            .background {
                if plan.showsAura {
                    WindowBorderAuraView(
                        geometry: geometry,
                        color: NSColor(effects.auraColor),
                        pulses: plan.auraPulses
                    )
                }
            }
            .overlay {
                if plan.showsSpark {
                    WindowBorderSparkView(geometry: geometry, color: Self.sparkColor(for: gradient))
                }
            }
    }
}
