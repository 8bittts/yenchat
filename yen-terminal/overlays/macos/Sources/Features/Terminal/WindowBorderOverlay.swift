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

    var body: some View {
        RoundedRectangle(cornerRadius: max(minimumCornerRadius, strokeModel.cornerRadius), style: .continuous)
            .inset(by: strokeModel.inset)
            .stroke(
                LinearGradient(
                    colors: [gradient.startColor, gradient.endColor],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: strokeStyle
            )
    }
}
