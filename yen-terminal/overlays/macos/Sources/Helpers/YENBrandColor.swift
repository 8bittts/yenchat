#if os(macOS)
import SwiftUI

extension Color {
    /// YEN brand orange — canonical value #ff5100 = rgb(255,81,0) = hsl(19 100% 50%).
    /// Must match `--brand` in `app/globals.css` (19 100% 50%) and the design
    /// system in `_docs/10-gtm.md`.
    static let yenBrand = Color(red: 1.0, green: 81.0 / 255.0, blue: 0.0)

    /// Solid fill for selected native chrome.
    /// Increased Contrast uses a darker orange so the fill still separates from
    /// both light and dark window backgrounds.
    static func overlayAccentFill(increasedContrast: Bool) -> Color {
        if increasedContrast {
            return Color(red: 0.70, green: 0.16, blue: 0.0)
        }
        return .yenBrand
    }

    /// Foreground for glyphs that sit on `overlayAccentFill`.
    /// Near-black instead of white so body-size text stays above WCAG AA on the
    /// brand orange fill.
    static let overlayAccentOnFill = Color(red: 0.10, green: 0.03, blue: 0.0)

    /// Shared accent color for overlay components that are not text-on-fill.
    static var overlayAccent: Color {
        .yenBrand
    }
}

/// Selected-row chrome derived from accessibility settings.
/// Outline is the non-color selected cue for Increased Contrast and
/// Differentiate Without Color.
struct OverlayAccentSelection: Equatable {
    let fill: Color
    let foreground: Color
    let showsOutline: Bool

    static func style(
        increasedContrast: Bool,
        differentiateWithoutColor: Bool
    ) -> OverlayAccentSelection {
        OverlayAccentSelection(
            fill: .overlayAccentFill(increasedContrast: increasedContrast),
            foreground: .overlayAccentOnFill,
            showsOutline: increasedContrast || differentiateWithoutColor
        )
    }
}
#endif // os(macOS)
