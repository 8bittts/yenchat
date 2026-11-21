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

    func paneBorder(framed: Bool) -> some View {
        var border = self
        if framed {
            border.radius = Double(YENDesignTokens.terminalFacingCornerRadius)
            border.chromeMode = .decorationNone
            border.minimumCornerRadius = YENDesignTokens.terminalFacingCornerRadius
        }
        return border.padding(framed ? 0 : 1)
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
