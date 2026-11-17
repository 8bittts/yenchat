#if os(macOS)
import Cocoa
import SwiftUI

enum WindowBorderGradientResolver {
    static func gradient(
        isFocused: Bool,
        colorMode: WindowBorderColorMode,
        activeThemeInfo: ThemeInfo?,
        focusedPalette: WindowBorderPalette,
        unfocusedPalette: WindowBorderPalette
    ) -> WindowBorderGradient {
        if colorMode == .matchTheme,
           let theme = activeThemeInfo {
            return matchThemeGradient(isFocused: isFocused, theme: theme)
        }

        let palette = isFocused ? focusedPalette : unfocusedPalette
        let start = palette.startColor
        let end = palette.endColor
        return WindowBorderGradient(startColor: start, endColor: end)
    }

    private static func matchThemeGradient(
        isFocused: Bool,
        theme: ThemeInfo
    ) -> WindowBorderGradient {
        if isFocused {
            let focusedFallback = Color(hex: WindowBorderPalette.defaultFocused.endHex) ?? theme.cursorColor
            let focusedContrastSafeEnd = colorMeetingContrastRequirement(
                candidate: theme.foregroundColor,
                against: theme.backgroundColor,
                fallback: focusedFallback,
                minimumContrastRatio: WindowBorderThemeContrast.minimumFocusedContrastRatio
            )
            let focusedDistinctEnd = colorDistinctFrom(
                reference: theme.cursorColor,
                candidate: focusedContrastSafeEnd,
                fallback: focusedFallback,
                minimumDistance: WindowBorderThemeContrast.minimumFocusedGradientDistance
            )
            return WindowBorderGradient(
                startColor: theme.cursorColor,
                endColor: colorMeetingContrastRequirement(
                    candidate: focusedDistinctEnd,
                    against: theme.backgroundColor,
                    fallback: focusedFallback,
                    minimumContrastRatio: WindowBorderThemeContrast.minimumFocusedContrastRatio
                )
            )
        }

        let defaultUnfocusedStart = Color(hex: WindowBorderPalette.defaultUnfocused.startHex)
            ?? theme.foregroundColor
        let defaultUnfocusedEnd = Color(hex: WindowBorderPalette.defaultUnfocused.endHex)
            ?? defaultUnfocusedStart

        return WindowBorderGradient(
            startColor: colorMeetingContrastRequirement(
                candidate: theme.foregroundColor.opacity(WindowBorderThemeContrast.unfocusedStartOpacity),
                against: theme.backgroundColor,
                fallback: defaultUnfocusedStart.opacity(0.9),
                minimumContrastRatio: WindowBorderThemeContrast.minimumUnfocusedContrastRatio
            ),
            endColor: colorMeetingContrastRequirement(
                candidate: theme.cursorColor.opacity(WindowBorderThemeContrast.unfocusedEndOpacity),
                against: theme.backgroundColor,
                fallback: defaultUnfocusedEnd.opacity(0.85),
                minimumContrastRatio: WindowBorderThemeContrast.minimumUnfocusedContrastRatio
            )
        )
    }

    private static func colorMeetingContrastRequirement(
        candidate: Color,
        against backgroundColor: Color,
        fallback: Color,
        minimumContrastRatio: Double
    ) -> Color {
        guard let candidateColor = nsColor(from: candidate),
              let background = nsColor(from: backgroundColor),
              let fallbackColor = nsColor(from: fallback) else {
            return candidate
        }

        if contrastRatio(of: candidateColor, against: background) >= minimumContrastRatio {
            return Color(candidateColor)
        }

        var lastCandidate = candidateColor
        for step in 1...6 {
            let blendAmount = CGFloat(step) / 6.0
            guard let blended = candidateColor.blended(withFraction: blendAmount, of: fallbackColor) else {
                continue
            }
            lastCandidate = blended
            if contrastRatio(of: blended, against: background) >= minimumContrastRatio {
                return Color(blended)
            }
        }

        return Color(lastCandidate)
    }

    private static func colorDistinctFrom(
        reference: Color,
        candidate: Color,
        fallback: Color,
        minimumDistance: Double
    ) -> Color {
        guard let referenceColor = nsColor(from: reference),
              let candidateColor = nsColor(from: candidate),
              let fallbackColor = nsColor(from: fallback) else {
            return candidate
        }

        if colorDistance(of: candidateColor, and: referenceColor) >= minimumDistance {
            return candidate
        }

        var lastCandidate = candidateColor
        for step in 1...6 {
            let blendAmount = CGFloat(step) / 6.0
            guard let blended = candidateColor.blended(withFraction: blendAmount, of: fallbackColor) else {
                continue
            }
            lastCandidate = blended
            if colorDistance(of: blended, and: referenceColor) >= minimumDistance {
                return Color(blended)
            }
        }

        return Color(lastCandidate)
    }

    private static func colorDistance(of lhs: NSColor, and rhs: NSColor) -> Double {
        guard let left = lhs.usingColorSpace(.deviceRGB),
              let right = rhs.usingColorSpace(.deviceRGB) else {
            return 0
        }
        let redDistance = abs(Double(left.redComponent - right.redComponent))
        let greenDistance = abs(Double(left.greenComponent - right.greenComponent))
        let blueDistance = abs(Double(left.blueComponent - right.blueComponent))
        let alphaDistance = abs(Double(left.alphaComponent - right.alphaComponent))
        return max(redDistance, greenDistance, blueDistance, alphaDistance)
    }

    private static func nsColor(from color: Color) -> NSColor? {
        NSColor(color).usingColorSpace(.extendedSRGB)
    }

    private static func contrastRatio(of foreground: NSColor, against background: NSColor) -> Double {
        let compositedForeground = composited(color: foreground, over: background)
        let opaqueBackground = composited(color: background, over: .black)
        let foregroundLuminance = relativeLuminance(of: compositedForeground)
        let backgroundLuminance = relativeLuminance(of: opaqueBackground)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func contrastRatioForTesting(of foreground: NSColor, against background: NSColor) -> Double {
        contrastRatio(of: foreground, against: background)
    }

    private static func composited(color foreground: NSColor, over background: NSColor) -> NSColor {
        guard let fg = foreground.usingColorSpace(.extendedSRGB),
              let bg = background.usingColorSpace(.extendedSRGB) else {
            return foreground
        }

        let alpha = fg.alphaComponent
        let red = fg.redComponent * alpha + bg.redComponent * (1 - alpha)
        let green = fg.greenComponent * alpha + bg.greenComponent * (1 - alpha)
        let blue = fg.blueComponent * alpha + bg.blueComponent * (1 - alpha)
        return NSColor(
            colorSpace: .extendedSRGB,
            components: [red, green, blue, 1],
            count: 4
        )
    }

    private static func relativeLuminance(of color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.extendedSRGB) else { return 0 }

        func transformedChannel(_ value: CGFloat) -> Double {
            let component = Double(value)
            if component <= 0.03928 {
                return component / 12.92
            }
            return pow((component + 0.055) / 1.055, 2.4)
        }

        return (
            0.2126 * transformedChannel(rgb.redComponent)
                + 0.7152 * transformedChannel(rgb.greenComponent)
                + 0.0722 * transformedChannel(rgb.blueComponent)
        )
    }
}

#endif
