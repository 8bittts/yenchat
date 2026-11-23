import AppKit
import SwiftUI
import Testing
@testable import YEN

@MainActor
struct SettingsPaneTests {
    @Test func panesRemainStableAndOrdered() {
        #expect(SettingsPane.allCases == [.appearance, .general, .notifications, .dictation, .shortcuts])
        #expect(SettingsPane.allCases.map(\.rawValue) == [
            "Appearance", "General", "Notifications", "Dictation", "Shortcuts",
        ])
    }

    @Test func everyPaneHasItsOwnSymbol() {
        let symbols = SettingsPane.allCases.map(\.symbolName)
        #expect(Set(symbols).count == SettingsPane.allCases.count)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func windowTitleNamesThePane() {
        for pane in SettingsPane.allCases {
            #expect(SettingsWindowFactory.title(for: pane) == pane.rawValue)
        }
    }

    @Test func tabSidebarChoiceMapsTheEnabledFlagAndTheMode() {
        #expect(SettingsTabSidebarChoice(enabled: false, mode: .transient) == .off)
        #expect(SettingsTabSidebarChoice(enabled: false, mode: .persistent) == .off)
        #expect(SettingsTabSidebarChoice(enabled: true, mode: .transient) == .floating)
        #expect(SettingsTabSidebarChoice(enabled: true, mode: .persistent) == .docked)
    }

    @Test func borderWeightSnapsAStoredWidthToTheNearestSegment() {
        #expect(SettingsBorderWeight.nearest(to: 1.0) == .thin)
        #expect(SettingsBorderWeight.nearest(to: 2.0) == .regular)
        #expect(SettingsBorderWeight.nearest(to: 4.0) == .thick)
        // Widths an older build could store still select a segment.
        #expect(SettingsBorderWeight.nearest(to: 1.4) == .thin)
        #expect(SettingsBorderWeight.nearest(to: 2.5) == .regular)
        #expect(SettingsBorderWeight.nearest(to: 8.0) == .thick)
        for weight in SettingsBorderWeight.allCases {
            #expect(WindowBorderPreferences.widthRange.contains(weight.rawValue))
        }
    }

    @Test func borderHintNamesWhatTheStoredScopeOutlines() {
        #expect(SettingsAppearancePane.borderHint(scope: .window) == "Outlines the window.")
        #expect(SettingsAppearancePane.borderHint(scope: .focusedSplit) == "Outlines the focused pane.")
    }

    @Test func borderSectionOffersScopeWhenTheBorderIsOn() {
        #expect(
            SettingsAppearancePane.borderRows(enabled: true, sparkEnabled: false, auraEnabled: false)
                == [.color, .scope, .weight, .spark, .aura]
        )
        #expect(SettingsAppearancePane.borderRows(enabled: false, sparkEnabled: false, auraEnabled: false).isEmpty)
        #expect(SettingsBorderScopeChoice.allCases.map(\.scope) == [.window, .focusedSplit])
        #expect(SettingsBorderScopeChoice.allCases.map(\.title) == ["Window", "Focused Pane"])
    }

    @Test func borderEffectsSitBelowWeightAndTheAuraOwnsItsColorRow() {
        let rows = SettingsAppearancePane.borderRows(enabled: true, sparkEnabled: false, auraEnabled: true)
        #expect(rows == [.color, .scope, .weight, .spark, .aura, .auraColor, .auraPulse])
        #expect(WindowBorderAuraPulse.allCases.map(\.displayName) == ["Slow", "Medium", "Fast"])
        // A hidden border hides its effects, whatever they are set to.
        #expect(SettingsAppearancePane.borderRows(enabled: false, sparkEnabled: true, auraEnabled: true).isEmpty)
    }

    @Test func theSparkOwnsItsSpeedRowWithFiveSpeeds() {
        #expect(
            SettingsAppearancePane.borderRows(enabled: true, sparkEnabled: true, auraEnabled: false)
                == [.color, .scope, .weight, .spark, .sparkSpeed, .aura]
        )
        #expect(
            SettingsAppearancePane.borderRows(enabled: true, sparkEnabled: true, auraEnabled: true)
                == [.color, .scope, .weight, .spark, .sparkSpeed, .aura, .auraColor, .auraPulse]
        )
        #expect(
            WindowBorderSparkSpeed.allCases.map(\.displayName)
                == ["Slowww", "Slow", "Medium", "Fast", "Fffast"]
        )
    }

    @MainActor
    @Test func everyPaneSegmentedControlHasTheHeightOfASegmentedPicker() {
        // The Border rows mix SwiftUI segmented pickers (Color, Outline,
        // Weight) with SettingsSegmentedControl (Spark Speed); a pane control
        // must stand exactly as tall as the pickers beside it.
        let picker = NSHostingView(rootView: Picker("Weight", selection: .constant(1)) {
            Text("Thin").tag(0)
            Text("Regular").tag(1)
        }
        .pickerStyle(.segmented)
        .labelsHidden())
        let control = NSHostingView(rootView: SettingsSegmentedControl(
            accessibilityLabel: "Border Spark Speed",
            segments: WindowBorderSparkSpeed.allCases.map { SettingsSegment(value: $0, title: $0.displayName) },
            selection: .constant(WindowBorderSparkSpeed.medium)
        )
        .frame(width: 320))
        #expect(picker.fittingSize.height > 0)
        #expect(control.fittingSize.height == picker.fittingSize.height)
    }

    @Test func borderEffectHintsNameTheSettingThatStopsTheMotion() {
        #expect(SettingsAppearancePane.sparkHint(limit: .none) == "A light travels around the outline.")
        #expect(SettingsAppearancePane.sparkHint(limit: .reduceMotion) == "Reduce Motion is on, so the light is hidden.")
        #expect(SettingsAppearancePane.sparkHint(limit: .lowPowerMode) == "Low Power Mode is on, so the light is hidden.")
        #expect(SettingsAppearancePane.auraHint(limit: .none) == "A soft glow pulses around the outline.")
        #expect(SettingsAppearancePane.auraHint(limit: .reduceMotion) == "Reduce Motion is on, so the glow holds still.")
        #expect(SettingsAppearancePane.auraHint(limit: .lowPowerMode) == "Low Power Mode is on, so the glow holds still.")
    }

    @Test func alertSoundShowsNoneWheneverTheStreamIsSilent() {
        let silent = NotificationSoundManager.silentSelectionID
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: "system:Glass", deliveryMode: .bannerAndSound, volume: 1.0
        ) == "system:Glass")
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: "system:Glass", deliveryMode: .soundOnly, volume: 0.4
        ) == "system:Glass")
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: "system:Glass", deliveryMode: .bannerOnly, volume: 1.0
        ) == silent)
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: "system:Glass", deliveryMode: .off, volume: 1.0
        ) == silent)
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: "system:Glass", deliveryMode: .bannerAndSound, volume: 0.0
        ) == silent)
        #expect(SettingsNotificationsPane.displayedSoundSelection(
            selection: silent, deliveryMode: .bannerAndSound, volume: 1.0
        ) == silent)
    }

    @Test func choosingASoundRaisesADeliveryModeThatBlocksSound() {
        let silent = NotificationSoundManager.silentSelectionID
        #expect(SettingsNotificationsPane.deliveryMode(afterChoosing: "system:Glass", current: .bannerOnly) == .bannerAndSound)
        #expect(SettingsNotificationsPane.deliveryMode(afterChoosing: "system:Glass", current: .off) == .bannerAndSound)
        #expect(SettingsNotificationsPane.deliveryMode(afterChoosing: "system:Glass", current: .soundOnly) == .soundOnly)
        #expect(SettingsNotificationsPane.deliveryMode(afterChoosing: "system:Glass", current: .bannerAndSound) == .bannerAndSound)
        // None never changes how banners are delivered.
        for mode in NotificationDeliveryMode.allCases {
            #expect(SettingsNotificationsPane.deliveryMode(afterChoosing: silent, current: mode) == mode)
        }
    }

    @Test func everyAlertStreamHasATitle() {
        let titles = NotificationService.configurableCases.map(SettingsNotificationsPane.serviceTitle)
        #expect(titles == ["General", "Build Finished", "Usage Limits"])
    }

    @Test func resetAllAlertNamesTheBackgroundImageOnlyWhenThereIsOne() {
        let plain = SettingsController.resetAllAlertMessage(hasBackgroundImage: false)
        let withImage = SettingsController.resetAllAlertMessage(hasBackgroundImage: true)
        #expect(!plain.contains("background image"))
        #expect(withImage.contains("removes the stored background image"))
        for message in [plain, withImage] {
            #expect(message.contains("cannot undo"))
            // Export is gone, so the alert must not point at it.
            #expect(!message.localizedCaseInsensitiveContains("export"))
        }
    }

    @Test func statusNoticeHasASymbolForEverySeverity() {
        let severities: [SettingsStatusSeverity] = [.success, .info, .warning, .error]
        let symbols = severities.map(SettingsStudioStatusNotice.symbolName)
        #expect(Set(symbols).count == severities.count)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func themePaletteParsesTheSixAccentColorsAndKeepsFallbacks() {
        let contents = """
        background = #101010
        palette = 0=#000000
        palette = 1=#ff0000
        palette = 2 = #00ff00
        palette = 6=#00ffff
        palette = 7=#ffffff
        palette = 3=not-a-color
        """
        let colors = SettingsStudioPalette.parse(contents: contents)
        #expect(colors.count == 6)
        #expect(rgb(colors[0]) == [255, 0, 0])
        #expect(rgb(colors[1]) == [0, 255, 0])
        #expect(rgb(colors[5]) == [0, 255, 255])
        // Missing and malformed entries keep the fallback at that position.
        #expect(rgb(colors[2]) == rgb(SettingsStudioPalette.fallback[2]))
        #expect(rgb(colors[3]) == rgb(SettingsStudioPalette.fallback[3]))
        #expect(SettingsStudioPalette.parse(contents: "").map(rgb) == SettingsStudioPalette.fallback.map(rgb))
    }

    @Test func previewThemeFallsBackWhenTheSelectionIsNotInTheCatalog() {
        #expect(SettingsStudioTheme.resolve(selectedTheme: "No Such Theme", in: []) == .fallback)
        #expect(SettingsStudioTheme.resolve(selectedTheme: "", in: []) == .fallback)
    }

    @Test func overlayAccentSelectionOutlinesWhenContrastOrDifferentiateWithoutColor() {
        let defaultStyle = OverlayAccentSelection.style(
            increasedContrast: false,
            differentiateWithoutColor: false
        )
        let increasedContrast = OverlayAccentSelection.style(
            increasedContrast: true,
            differentiateWithoutColor: false
        )
        let differentiateWithoutColor = OverlayAccentSelection.style(
            increasedContrast: false,
            differentiateWithoutColor: true
        )

        #expect(defaultStyle.showsOutline == false)
        #expect(increasedContrast.showsOutline == true)
        #expect(differentiateWithoutColor.showsOutline == true)
        #expect(defaultStyle.foreground == Color.overlayAccentOnFill)
        #expect(increasedContrast.fill != defaultStyle.fill)
    }

    private func rgb(_ color: Color) -> [Int] {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return [] }
        return [nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent].map {
            Int(($0 * 255).rounded())
        }
    }
}
