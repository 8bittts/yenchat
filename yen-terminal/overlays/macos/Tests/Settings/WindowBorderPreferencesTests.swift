import AppKit
import Foundation
import SwiftUI
import Testing
@testable import YEN

@MainActor
struct WindowBorderPreferencesTests {
    @Test func windowBorderDefaultsAreRegisteredAndReadable() {
        withIsolatedWindowBorderPreferences {
            WindowBorderPreferences.registerDefaults()
            let state = WindowBorderPreferences.state()
            let defaults = UserDefaults.standard

            #expect(state == WindowBorderPreferences.defaultState)
            #expect(
                defaults.object(forKey: WindowBorderPreferences.enabledPreferenceKey) as? Bool
                    == WindowBorderPreferences.defaultState.enabled
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.scopePreferenceKey)
                    == WindowBorderPreferences.defaultState.scope.rawValue
            )
            #expect(
                defaults.object(forKey: WindowBorderPreferences.widthPreferenceKey) as? Double
                    == WindowBorderPreferences.defaultState.width
            )
            #expect(
                defaults.object(forKey: WindowBorderPreferences.radiusPreferenceKey) as? Double
                    == WindowBorderPreferences.defaultState.radius
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.colorModePreferenceKey)
                    == WindowBorderPreferences.defaultState.colorMode.rawValue
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.focusedPalettePreferenceKey)
                    == WindowBorderPreferences.defaultState.focusedPalette.rawValue
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey)
                    == WindowBorderPreferences.defaultState.unfocusedPalette.rawValue
            )
        }
    }

    @Test func windowBorderStateClampsNumericValuesAndNormalizesPalettes() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: WindowBorderPreferences.enabledPreferenceKey)
            defaults.set("not-a-scope", forKey: WindowBorderPreferences.scopePreferenceKey)
            defaults.set(-99.0, forKey: WindowBorderPreferences.widthPreferenceKey)
            defaults.set(999.0, forKey: WindowBorderPreferences.radiusPreferenceKey)
            defaults.set("not-a-mode", forKey: WindowBorderPreferences.colorModePreferenceKey)
            defaults.set("not-a-palette", forKey: WindowBorderPreferences.focusedPalettePreferenceKey)
            defaults.set(WindowBorderPalette.ember.rawValue, forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey)

            let state = WindowBorderPreferences.state()
            #expect(state.enabled)
            #expect(state.scope == WindowBorderPreferences.defaultState.scope)
            #expect(state.width == WindowBorderPreferences.widthRange.lowerBound)
            #expect(state.radius == WindowBorderPreferences.radiusRange.upperBound)
            #expect(state.colorMode == WindowBorderPreferences.defaultState.colorMode)
            #expect(state.focusedPalette == WindowBorderPreferences.defaultState.focusedPalette)
            #expect(state.unfocusedPalette == .ember)
        }
    }

    @Test func windowBorderStateNormalizesSliderBackedNumericSteps() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            defaults.set(6.3, forKey: WindowBorderPreferences.widthPreferenceKey)
            defaults.set(12.6, forKey: WindowBorderPreferences.radiusPreferenceKey)

            let state = WindowBorderPreferences.state()
            #expect(state.width == 6.5)
            #expect(state.radius == 13.0)
        }
    }

    @Test func windowBorderClampingHelpersHonorBounds() {
        #expect(WindowBorderPreferences.clampedWidth(-10) == WindowBorderPreferences.widthRange.lowerBound)
        #expect(WindowBorderPreferences.clampedWidth(999) == WindowBorderPreferences.widthRange.upperBound)
        #expect(WindowBorderPreferences.clampedWidth(3.5) == 3.5)

        #expect(WindowBorderPreferences.clampedRadius(-1) == WindowBorderPreferences.radiusRange.lowerBound)
        #expect(WindowBorderPreferences.clampedRadius(999) == WindowBorderPreferences.radiusRange.upperBound)
        #expect(WindowBorderPreferences.clampedRadius(12) == 12)

    }

    @Test func windowBorderGradientEqualityTracksResolvedColorChanges() {
        let baseline = WindowBorderGradient(
            startColor: Color(red: 1.0, green: 0.25, blue: 0.2),
            endColor: Color(red: 0.15, green: 0.8, blue: 0.55)
        )
        let matching = WindowBorderGradient(
            startColor: Color(red: 1.0, green: 0.25, blue: 0.2),
            endColor: Color(red: 0.15, green: 0.8, blue: 0.55)
        )
        let changed = WindowBorderGradient(
            startColor: Color(red: 0.48, green: 0.78, blue: 0.99),
            endColor: Color(red: 0.15, green: 0.8, blue: 0.55)
        )

        #expect(baseline == matching)
        #expect(baseline != changed)
    }

    @Test func loadWindowBorderPreferencesHydratesControllerFromDefaults() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: WindowBorderPreferences.enabledPreferenceKey)
            defaults.set(WindowBorderScope.focusedSplit.rawValue, forKey: WindowBorderPreferences.scopePreferenceKey)
            defaults.set(6.0, forKey: WindowBorderPreferences.widthPreferenceKey)
            defaults.set(22.0, forKey: WindowBorderPreferences.radiusPreferenceKey)
            defaults.set(WindowBorderColorMode.matchTheme.rawValue, forKey: WindowBorderPreferences.colorModePreferenceKey)
            defaults.set(WindowBorderPalette.ocean.rawValue, forKey: WindowBorderPreferences.focusedPalettePreferenceKey)
            defaults.set(WindowBorderPalette.graphite.rawValue, forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey)

            let controller = SettingsController.shared
            controller.loadWindowBorderPreferences()

            #expect(controller.windowBorderEnabled)
            #expect(controller.windowBorderScope == .focusedSplit)
            #expect(controller.windowBorderWidth == 6.0)
            #expect(controller.windowBorderRadius == 22.0)
            #expect(controller.windowBorderColorMode == .matchTheme)
            #expect(controller.windowBorderFocusedPalette == .ocean)
            #expect(controller.windowBorderUnfocusedPalette == .graphite)
        }
    }

    @Test func windowBorderControllerWritesPreferencesOnChange() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared
            controller.loadWindowBorderPreferences()

            controller.windowBorderEnabled = true
            controller.windowBorderScope = .focusedSplit
            controller.windowBorderWidth = 7.5
            controller.windowBorderRadius = 18
            controller.windowBorderColorMode = .matchTheme
            controller.windowBorderFocusedPalette = .aurora
            controller.windowBorderUnfocusedPalette = .graphite

            #expect(defaults.bool(forKey: WindowBorderPreferences.enabledPreferenceKey))
            #expect(
                defaults.string(forKey: WindowBorderPreferences.scopePreferenceKey)
                    == WindowBorderScope.focusedSplit.rawValue
            )
            #expect(defaults.double(forKey: WindowBorderPreferences.widthPreferenceKey) == 7.5)
            #expect(defaults.double(forKey: WindowBorderPreferences.radiusPreferenceKey) == 18)
            #expect(
                defaults.string(forKey: WindowBorderPreferences.colorModePreferenceKey)
                    == WindowBorderColorMode.matchTheme.rawValue
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.focusedPalettePreferenceKey)
                    == WindowBorderPalette.aurora.rawValue
            )
            #expect(
                defaults.string(forKey: WindowBorderPreferences.unfocusedPalettePreferenceKey)
                    == WindowBorderPalette.graphite.rawValue
            )

            controller.windowBorderWidth = 99
            controller.windowBorderRadius = -5

            #expect(controller.windowBorderWidth == WindowBorderPreferences.widthRange.upperBound)
            #expect(controller.windowBorderRadius == WindowBorderPreferences.radiusRange.lowerBound)
        }
    }

    @Test func windowBorderControllerNormalizesSliderBackedValuesBeforePersisting() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared
            controller.loadWindowBorderPreferences()

            controller.windowBorderWidth = 6.3
            controller.windowBorderRadius = 12.6

            #expect(controller.windowBorderWidth == 6.5)
            #expect(controller.windowBorderRadius == 13.0)
            #expect(defaults.double(forKey: WindowBorderPreferences.widthPreferenceKey) == 6.5)
            #expect(defaults.double(forKey: WindowBorderPreferences.radiusPreferenceKey) == 13.0)
        }
    }

    @Test func windowBorderColorModePrecedenceMatchesThemeAndRestoresManualPalettes() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalFocusedPalette = controller.windowBorderFocusedPalette
        let originalUnfocusedPalette = controller.windowBorderUnfocusedPalette
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme

        defer {
            controller.windowBorderColorMode = originalMode
            controller.windowBorderFocusedPalette = originalFocusedPalette
            controller.windowBorderUnfocusedPalette = originalUnfocusedPalette
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
        }

        guard let themePath = try? makeTempThemeFile(contents: """
        background = #101820
        foreground = #22CC88
        cursor-color = #FF3B30
        """) else {
            Issue.record("Failed to create temp theme file for match-theme test")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: themePath) }

        let theme = ThemeInfo(name: "unit-theme", path: themePath, bundled: false)
        controller.availableThemes = [theme]
        controller.selectedTheme = theme.name
        controller.windowBorderFocusedPalette = .ocean
        controller.windowBorderUnfocusedPalette = .graphite

        controller.windowBorderColorMode = .manual
        let manualFocused = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        #expect(manualFocused == (14, 165, 233, 255))

        controller.windowBorderColorMode = .matchTheme
        let themedFocusedStart = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        let themedFocusedEnd = rgbaTuple(controller.windowBorderFocusedGradient.endColor)
        let themedUnfocusedStart = rgbaTuple(controller.windowBorderUnfocusedGradient.startColor)
        let themedUnfocusedEnd = rgbaTuple(controller.windowBorderUnfocusedGradient.endColor)
        let themeBackground = rgbaTuple(theme.backgroundColor)

        #expect(themedFocusedStart == (255, 59, 48, 255))
        #expect(themedFocusedEnd == (34, 204, 136, 255))
        #expect(
            contrastRatio(of: themedUnfocusedStart, against: themeBackground)
                >= WindowBorderThemeContrast.minimumUnfocusedContrastRatio - 0.02
        )
        #expect(
            contrastRatio(of: themedUnfocusedEnd, against: themeBackground)
                >= WindowBorderThemeContrast.minimumUnfocusedContrastRatio - 0.02
        )
        #expect(themedUnfocusedEnd.3 < 255)

        controller.windowBorderColorMode = .manual
        let manualFocusedAfter = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        #expect(manualFocusedAfter == manualFocused)
    }

    @Test func windowBorderMatchThemeUsesContrastFallbackForLowContrastThemes() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
        }

        guard let themePath = try? makeTempThemeFile(contents: """
        background = #121212
        foreground = #151515
        cursor-color = #171717
        """) else {
            Issue.record("Failed to create temp theme file for contrast fallback test")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: themePath) }

        let theme = ThemeInfo(
            name: "unit-low-contrast-theme-\(UUID().uuidString)",
            path: themePath,
            bundled: false
        )
        controller.availableThemes = [theme]
        controller.selectedTheme = theme.name
        controller.windowBorderColorMode = .matchTheme

        let background = rgbaTuple(theme.backgroundColor)
        let unfocusedStart = rgbaTuple(controller.windowBorderUnfocusedGradient.startColor)
        let unfocusedEnd = rgbaTuple(controller.windowBorderUnfocusedGradient.endColor)

        #expect(
            contrastRatio(of: unfocusedStart, against: background)
                >= WindowBorderThemeContrast.minimumUnfocusedContrastRatio - 0.02
        )
        #expect(
            contrastRatio(of: unfocusedEnd, against: background)
                >= WindowBorderThemeContrast.minimumUnfocusedContrastRatio - 0.02
        )
    }

    @Test func windowBorderMatchThemeEnsuresFocusedGradientEndpointsStayDistinct() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
        }

        guard let themePath = try? makeTempThemeFile(contents: """
        background = #121214
        foreground = #AF9A91
        cursor-color = #AF9A91
        """) else {
            Issue.record("Failed to create temp theme file for focused gradient distinctness test")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: themePath) }

        let theme = ThemeInfo(
            name: "unit-equal-focused-colors-\(UUID().uuidString)",
            path: themePath,
            bundled: false
        )
        controller.availableThemes = [theme]
        controller.selectedTheme = theme.name
        controller.windowBorderColorMode = .matchTheme

        let focusedStart = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        let focusedEnd = rgbaTuple(controller.windowBorderFocusedGradient.endColor)

        #expect(focusedStart == rgbaTuple(theme.cursorColor))
        #expect(focusedEnd != focusedStart)
        #expect(
            maxChannelDistance(between: focusedStart, and: focusedEnd)
                >= WindowBorderThemeContrast.minimumFocusedGradientDistance - 0.01
        )
    }

    @Test func windowBorderMatchThemeResolvesThemeNamesWithExtensionAndSeparatorVariants() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
        }

        guard let themePath = try? makeTempThemeFile(contents: """
        background = #201A23
        foreground = #F4EDEA
        cursor-color = #FF6A3D
        """) else {
            Issue.record("Failed to create temp theme file for lookup normalization test")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: themePath) }

        let theme = ThemeInfo(
            name: "Unit Blend Theme",
            path: themePath,
            bundled: false
        )
        controller.availableThemes = [theme]
        controller.selectedTheme = "\"unit-blend_theme.yentheme\""
        controller.windowBorderColorMode = .matchTheme

        #expect(controller.windowBorderResolvedThemeName != nil)
        #expect(!controller.windowBorderMatchThemeUsesManualFallback)
        #expect(rgbaTuple(controller.windowBorderFocusedGradient.startColor) == rgbaTuple(theme.cursorColor))
    }

    @Test func windowBorderMatchThemeNormalizesQuotedThemeName() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
        }

        guard let themePath = try? makeTempThemeFile(contents: """
        background = #0B132B
        foreground = #F7FFF7
        cursor-color = #5BC0EB
        """) else {
            Issue.record("Failed to create temp theme file for quoted theme-name test")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: themePath) }

        let theme = ThemeInfo(
            name: "unit-quoted-theme-\(UUID().uuidString)",
            path: themePath,
            bundled: false
        )
        controller.availableThemes = [theme]
        controller.selectedTheme = "\"\(theme.name)\""
        controller.windowBorderColorMode = .matchTheme

        #expect(rgbaTuple(controller.windowBorderFocusedGradient.startColor) == rgbaTuple(theme.cursorColor))
    }

    @Test func windowBorderMatchThemeRespondsToConfigReloadNotificationWhileSettingsIsClosed() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme
        let originalSelectedTab = controller.selectedSettingsPane
        let originalThemeReloadHook = controller.testThemeNameOnConfigReload

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
            controller.selectedSettingsPane = originalSelectedTab
            controller.testThemeNameOnConfigReload = originalThemeReloadHook
            controller.hide()
        }

        guard let themeAPath = try? makeTempThemeFile(contents: """
        background = #0B132B
        foreground = #F7FFF7
        cursor-color = #5BC0EB
        """),
        let themeBPath = try? makeTempThemeFile(contents: """
        background = #201A23
        foreground = #F4EDEA
        cursor-color = #FF6A3D
        """) else {
            Issue.record("Failed to create temp theme files for config reload test")
            return
        }
        defer {
            try? FileManager.default.removeItem(atPath: themeAPath)
            try? FileManager.default.removeItem(atPath: themeBPath)
        }

        let themeA = ThemeInfo(
            name: "unit-reload-theme-a-\(UUID().uuidString)",
            path: themeAPath,
            bundled: false
        )
        let themeB = ThemeInfo(
            name: "unit-reload-theme-b-\(UUID().uuidString)",
            path: themeBPath,
            bundled: false
        )

        controller.availableThemes = [themeA, themeB]
        controller.selectedTheme = themeA.name
        controller.windowBorderColorMode = .matchTheme
        controller.testThemeNameOnConfigReload = { themeB.name }
        controller.hide()

        let focusedBeforeReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let focusedAfterReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)

        #expect(controller.selectedTheme == themeB.name)
        #expect(focusedAfterReload == rgbaTuple(themeB.cursorColor))
        #expect(focusedBeforeReload != focusedAfterReload)
    }

    @Test func windowBorderMatchThemeRespondsToConfigReloadNotificationWhileSettingsIsVisible() {
        let controller = SettingsController.shared

        let originalMode = controller.windowBorderColorMode
        let originalThemes = controller.availableThemes
        let originalSelectedTheme = controller.selectedTheme
        let originalSelectedTab = controller.selectedSettingsPane
        let originalThemeReloadHook = controller.testThemeNameOnConfigReload

        defer {
            controller.windowBorderColorMode = originalMode
            controller.availableThemes = originalThemes
            controller.selectedTheme = originalSelectedTheme
            controller.selectedSettingsPane = originalSelectedTab
            controller.testThemeNameOnConfigReload = originalThemeReloadHook
            controller.hide()
        }

        guard let themeAPath = try? makeTempThemeFile(contents: """
        background = #102542
        foreground = #F7FFF7
        cursor-color = #7CC6FE
        """),
        let themeBPath = try? makeTempThemeFile(contents: """
        background = #1B1B1E
        foreground = #FBFFFE
        cursor-color = #F65A83
        """) else {
            Issue.record("Failed to create temp theme files for visible config reload test")
            return
        }
        defer {
            try? FileManager.default.removeItem(atPath: themeAPath)
            try? FileManager.default.removeItem(atPath: themeBPath)
        }

        let themeA = ThemeInfo(
            name: "unit-visible-reload-theme-a-\(UUID().uuidString)",
            path: themeAPath,
            bundled: false
        )
        let themeB = ThemeInfo(
            name: "unit-visible-reload-theme-b-\(UUID().uuidString)",
            path: themeBPath,
            bundled: false
        )

        controller.show(pane: .general)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        controller.availableThemes = [themeA, themeB]
        controller.selectedTheme = themeA.name
        controller.windowBorderColorMode = .matchTheme
        controller.testThemeNameOnConfigReload = { themeB.name }

        let focusedBeforeReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let focusedAfterReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)

        #expect(controller.window?.isVisible == true)
        #expect(controller.selectedTheme == themeB.name)
        #expect(focusedAfterReload == rgbaTuple(themeB.cursorColor))
        #expect(focusedBeforeReload != focusedAfterReload)
    }

    @Test func windowBorderMatchThemeReloadsUpdatedThemeContentsWhileSettingsIsClosed() throws {
        let controller = SettingsController.shared
        let originalMode = controller.windowBorderColorMode
        let originalSelectedTheme = controller.selectedTheme
        let originalSelectedTab = controller.selectedSettingsPane
        let fixture = try makeThemeCatalogFixture()
        let configURL = fixture.root.appendingPathComponent("config.yen", isDirectory: false)

        defer {
            controller.windowBorderColorMode = originalMode
            controller.selectedTheme = originalSelectedTheme
            controller.selectedSettingsPane = originalSelectedTab
            controller.hide()
            controller._testClearThemeCatalogPaths()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: fixture.root)
        }

        let themeName = "Reload Same Theme"
        let initialCursor = "#5BC0EB"
        let updatedCursor = "#FF6A3D"

        _ = try writeTheme(
            named: themeName,
            contents: defaultThemeContents(cursor: initialCursor),
            to: fixture.userDirectory
        )
        try "theme = \(themeName)\n".write(to: configURL, atomically: true, encoding: .utf8)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        SettingsController._testSetConfigPathOverride(configURL.path)
        controller.loadThemes()
        controller.selectedTheme = themeName
        controller.windowBorderColorMode = .matchTheme
        controller.hide()

        let originalDirectoryDate = try directoryModificationDate(fixture.userDirectory)
        _ = try writeTheme(
            named: themeName,
            contents: defaultThemeContents(cursor: updatedCursor),
            to: fixture.userDirectory
        )
        try FileManager.default.setAttributes(
            [.modificationDate: originalDirectoryDate],
            ofItemAtPath: fixture.userDirectory.path
        )

        let gradientBeforeReload = controller.windowBorderFocusedGradient
        let focusedBeforeReload = rgbaTuple(gradientBeforeReload.startColor)
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let gradientAfterReload = controller.windowBorderFocusedGradient
        let focusedAfterReload = rgbaTuple(gradientAfterReload.startColor)

        #expect(focusedBeforeReload == rgbaTuple(Color(hex: initialCursor) ?? .clear))
        #expect(focusedAfterReload == rgbaTuple(Color(hex: updatedCursor) ?? .clear))
        #expect(gradientBeforeReload != gradientAfterReload)
        #expect(focusedAfterReload != focusedBeforeReload)
    }

    @Test func windowBorderMatchThemeReloadsUpdatedThemeContentsWhileSettingsIsVisible() throws {
        let controller = SettingsController.shared
        let originalMode = controller.windowBorderColorMode
        let originalSelectedTheme = controller.selectedTheme
        let originalSelectedTab = controller.selectedSettingsPane
        let fixture = try makeThemeCatalogFixture()
        let configURL = fixture.root.appendingPathComponent("config.yen", isDirectory: false)

        defer {
            controller.windowBorderColorMode = originalMode
            controller.selectedTheme = originalSelectedTheme
            controller.selectedSettingsPane = originalSelectedTab
            controller.hide()
            controller._testClearThemeCatalogPaths()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: fixture.root)
        }

        let themeName = "Visible Reload Same Theme"
        let initialCursor = "#7CC6FE"
        let updatedCursor = "#F65A83"

        _ = try writeTheme(
            named: themeName,
            contents: defaultThemeContents(cursor: initialCursor),
            to: fixture.userDirectory
        )
        try "theme = \(themeName)\n".write(to: configURL, atomically: true, encoding: .utf8)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        SettingsController._testSetConfigPathOverride(configURL.path)
        controller.loadThemes()
        controller.show(pane: .general)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.selectedTheme = themeName
        controller.windowBorderColorMode = .matchTheme

        let originalDirectoryDate = try directoryModificationDate(fixture.userDirectory)
        _ = try writeTheme(
            named: themeName,
            contents: defaultThemeContents(cursor: updatedCursor),
            to: fixture.userDirectory
        )
        try FileManager.default.setAttributes(
            [.modificationDate: originalDirectoryDate],
            ofItemAtPath: fixture.userDirectory.path
        )

        let focusedBeforeReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let focusedAfterReload = rgbaTuple(controller.windowBorderFocusedGradient.startColor)

        #expect(controller.window?.isVisible == true)
        #expect(focusedBeforeReload == rgbaTuple(Color(hex: initialCursor) ?? .clear))
        #expect(focusedAfterReload == rgbaTuple(Color(hex: updatedCursor) ?? .clear))
        #expect(focusedAfterReload != focusedBeforeReload)
    }

    @Test func windowBorderQuickActionHelpersRespectColorModeAndPersist() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared
            controller.loadWindowBorderPreferences()

            controller.windowBorderColorMode = .manual
            controller.windowBorderFocusedPalette = .sunrise
            controller.windowBorderUnfocusedPalette = .graphite
            controller.windowBorderEnabled = false

            #expect(controller.cycleWindowBorderFocusedPalette())
            #expect(controller.windowBorderFocusedPalette == .ember)
            #expect(controller.cycleWindowBorderUnfocusedPalette())
            #expect(controller.windowBorderUnfocusedPalette == .sunrise)

            controller.toggleWindowBorderEnabled()

            #expect(controller.windowBorderEnabled)
            #expect(defaults.bool(forKey: WindowBorderPreferences.enabledPreferenceKey))

            controller.windowBorderColorMode = .matchTheme
            let focusedBefore = controller.windowBorderFocusedPalette
            let unfocusedBefore = controller.windowBorderUnfocusedPalette
            #expect(!controller.cycleWindowBorderFocusedPalette())
            #expect(!controller.cycleWindowBorderUnfocusedPalette())
            #expect(controller.windowBorderFocusedPalette == focusedBefore)
            #expect(controller.windowBorderUnfocusedPalette == unfocusedBefore)
        }
    }

    @Test func windowBorderScopeToggleSwitchesBetweenWindowAndFocusedSplitAndPersists() {
        withIsolatedWindowBorderPreferences {
            let defaults = UserDefaults.standard
            let controller = SettingsController.shared
            controller.loadWindowBorderPreferences()
            controller.windowBorderScope = .window

            controller.toggleWindowBorderScope()
            #expect(controller.windowBorderScope == .focusedSplit)
            #expect(
                defaults.string(forKey: WindowBorderPreferences.scopePreferenceKey)
                    == WindowBorderScope.focusedSplit.rawValue
            )

            controller.toggleWindowBorderScope()
            #expect(controller.windowBorderScope == .window)
            #expect(
                defaults.string(forKey: WindowBorderPreferences.scopePreferenceKey)
                    == WindowBorderScope.window.rawValue
            )
        }
    }

    private func withIsolatedWindowBorderPreferences(_ operation: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [
            WindowBorderPreferences.enabledPreferenceKey,
            WindowBorderPreferences.scopePreferenceKey,
            WindowBorderPreferences.widthPreferenceKey,
            WindowBorderPreferences.radiusPreferenceKey,
            WindowBorderPreferences.colorModePreferenceKey,
            WindowBorderPreferences.focusedPalettePreferenceKey,
            WindowBorderPreferences.unfocusedPalettePreferenceKey,
        ]

        var originalValues: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                originalValues[key] = value
            }
            defaults.removeObject(forKey: key)
        }

        defer {
            for key in keys {
                defaults.removeObject(forKey: key)
                if let original = originalValues[key] {
                    defaults.set(original, forKey: key)
                }
            }
        }

        try operation()
    }

    private func makeThemeCatalogFixture() throws -> ThemeCatalogFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-window-border-theme-catalog-\(UUID().uuidString)", isDirectory: true)
        let userDirectory = root.appendingPathComponent("user", isDirectory: true)
        let bundledDirectory = root.appendingPathComponent("bundled", isDirectory: true)
        let fullDirectory = root.appendingPathComponent("full", isDirectory: true)
        let manifestPath = root.appendingPathComponent("theme-curated-manifest.txt", isDirectory: false)
        let tagsPath = root.appendingPathComponent("theme-curated-tags.txt", isDirectory: false)

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try Data().write(to: manifestPath)
        try Data().write(to: tagsPath)

        return ThemeCatalogFixture(
            root: root,
            userDirectory: userDirectory,
            bundledDirectory: bundledDirectory,
            fullDirectory: fullDirectory,
            manifestPath: manifestPath,
            tagsPath: tagsPath
        )
    }

    @discardableResult
    private func writeTheme(
        named name: String,
        contents: String,
        to directory: URL
    ) throws -> String {
        let path = directory.appendingPathComponent("\(name).yen", isDirectory: false)
        try contents.write(to: path, atomically: true, encoding: .utf8)
        return path.path
    }

    private func defaultThemeContents(
        background: String = "#101820",
        foreground: String = "#F8F9FA",
        cursor: String
    ) -> String {
        [
            "background = \(background)",
            "foreground = \(foreground)",
            "cursor-color = \(cursor)",
        ].joined(separator: "\n")
    }

    private func directoryModificationDate(_ directory: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        return (attributes[.modificationDate] as? Date) ?? Date.distantPast
    }

    private func makeTempThemeFile(contents: String) throws -> String {
        let path = "\(NSTemporaryDirectory())/window-border-theme-\(UUID().uuidString).yentheme"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func rgbaTuple(_ color: Color) -> (Int, Int, Int, Int) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.black
        return (
            Int(round(nsColor.redComponent * 255.0)),
            Int(round(nsColor.greenComponent * 255.0)),
            Int(round(nsColor.blueComponent * 255.0)),
            Int(round(nsColor.alphaComponent * 255.0))
        )
    }

    private func maxChannelDistance(
        between lhs: (Int, Int, Int, Int),
        and rhs: (Int, Int, Int, Int)
    ) -> Double {
        let distances = [
            abs(lhs.0 - rhs.0),
            abs(lhs.1 - rhs.1),
            abs(lhs.2 - rhs.2),
            abs(lhs.3 - rhs.3),
        ]
        return Double(distances.max() ?? 0) / 255.0
    }

    private func contrastRatio(
        of foreground: (Int, Int, Int, Int),
        against background: (Int, Int, Int, Int)
    ) -> Double {
        let fgAlpha = Double(foreground.3) / 255.0
        let fgRed = Double(foreground.0) / 255.0
        let fgGreen = Double(foreground.1) / 255.0
        let fgBlue = Double(foreground.2) / 255.0

        let bgRed = Double(background.0) / 255.0
        let bgGreen = Double(background.1) / 255.0
        let bgBlue = Double(background.2) / 255.0

        let compositedRed = fgRed * fgAlpha + bgRed * (1.0 - fgAlpha)
        let compositedGreen = fgGreen * fgAlpha + bgGreen * (1.0 - fgAlpha)
        let compositedBlue = fgBlue * fgAlpha + bgBlue * (1.0 - fgAlpha)

        let foregroundLuminance = relativeLuminance(
            red: compositedRed,
            green: compositedGreen,
            blue: compositedBlue
        )
        let backgroundLuminance = relativeLuminance(
            red: bgRed,
            green: bgGreen,
            blue: bgBlue
        )

        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func channel(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        return (
            0.2126 * channel(red)
                + 0.7152 * channel(green)
                + 0.0722 * channel(blue)
        )
    }
}

private struct ThemeCatalogFixture {
    let root: URL
    let userDirectory: URL
    let bundledDirectory: URL
    let fullDirectory: URL
    let manifestPath: URL
    let tagsPath: URL
}
