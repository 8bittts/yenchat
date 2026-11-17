import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

struct WindowBorderOverlay: View {
    let gradient: WindowBorderGradient
    let width: Double
    let radius: Double
    let chromeMode: WindowBorderChromeMode
    let isFocused: Bool
    let useDashedUnfocusedStyle: Bool

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

    var body: some View {
        RoundedRectangle(cornerRadius: strokeModel.cornerRadius, style: .continuous)
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
