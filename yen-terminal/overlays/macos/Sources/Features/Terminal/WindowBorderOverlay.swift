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
    // The window appearance follows the terminal background.
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var powerState = LowPowerModeMonitor.shared

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

    /// The spark must stand out from the stroke it runs on.
    static let minimumSparkContrastRatio = 1.6

    /// The spark is the outline's own color, lifted most of the way to white
    /// on a dark backdrop. On a light backdrop a pale spark reads as a gap in
    /// the outline, so it is deepened toward black instead. Either way, the
    /// other choice wins when the preferred one would vanish into the stroke.
    static func sparkColor(for gradient: WindowBorderGradient, backdropIsLight: Bool) -> NSColor {
        let start = NSColor(gradient.startColor).usingColorSpace(.sRGB) ?? .white
        let end = NSColor(gradient.endColor).usingColorSpace(.sRGB) ?? .white
        let middle = (start.blended(withFraction: 0.5, of: end) ?? start).withAlphaComponent(1)
        let lifted = middle.blended(withFraction: 0.8, of: .white) ?? .white
        let deepened = middle.blended(withFraction: 0.65, of: .black) ?? .black
        let preferred = backdropIsLight ? deepened : lifted
        let fallback = backdropIsLight ? lifted : deepened
        let contrast = WindowBorderGradientResolver.contrastRatio(of: preferred, against: middle)
        return contrast >= minimumSparkContrastRatio ? preferred : fallback
    }

    var body: some View {
        let stroke = strokeModel
        let cornerRadius = max(minimumCornerRadius, stroke.cornerRadius)
        let plan = WindowBorderRenderingPolicy.effectPlan(
            effects: effects,
            isFocused: isFocused,
            motionLimit: WindowBorderRenderingPolicy.motionLimit(
                reduceMotion: reduceMotion,
                lowPowerMode: powerState.isLowPowerModeEnabled
            )
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
                        pulse: plan.auraPulses ? effects.auraPulse : nil
                    )
                }
            }
            .overlay {
                if plan.showsSpark {
                    WindowBorderSparkView(
                        geometry: geometry,
                        color: Self.sparkColor(for: gradient, backdropIsLight: colorScheme == .light),
                        speed: effects.sparkSpeed
                    )
                }
            }
    }
}
