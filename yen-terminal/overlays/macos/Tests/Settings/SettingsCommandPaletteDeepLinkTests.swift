import Testing
@testable import YEN

@MainActor
struct SettingsCommandPaletteDeepLinkTests {
    @Test func settingsDeepLinkCatalogRemainsStableAndComplete() {
        let deepLinks = TerminalCommandPaletteView.settingsDeepLinkDefinitions

        #expect(deepLinks.map(\.title) == [
            "Settings: Appearance",
            "Settings: General",
            "Settings: Pane Labels",
            "Settings: Notifications",
            "Settings: Dictation",
            "Settings: Shortcuts",
        ])
        #expect(deepLinks.map(\.pane) == [.appearance, .general, .general, .notifications, .dictation, .shortcuts])
        #expect(Set(deepLinks.map(\.title)).count == deepLinks.count)
        #expect(Set(deepLinks.map(\.id)).count == deepLinks.count)
        // Every pane can be opened from the command palette.
        #expect(Set(deepLinks.map(\.pane)) == Set(SettingsPane.allCases))
    }

    @Test func settingsDeepLinkActionsRouteToExpectedTabs() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        for deepLink in TerminalCommandPaletteView.settingsDeepLinkDefinitions {
            // Start on a different pane so the route is what selects the target.
            controller.selectedSettingsPane = deepLink.pane == .appearance ? .shortcuts : .appearance
            TerminalCommandPaletteView.openSettingsDeepLink(deepLink)
            #expect(controller.selectedSettingsPane == deepLink.pane)
        }
    }

    @Test func scratchpadCommandVisibilityFollowsWorkspaceToggleState() {
        #expect(TerminalCommandPaletteView.shouldShowScratchpadCommand(scratchpadEnabled: true))
        #expect(!TerminalCommandPaletteView.shouldShowScratchpadCommand(scratchpadEnabled: false))
    }

    @Test func tabSidebarCommandVisibilityFollowsWorkspaceToggleState() {
        #expect(TerminalCommandPaletteView.shouldShowTabSidebarCommand(tabSidebarEnabled: true))
        #expect(!TerminalCommandPaletteView.shouldShowTabSidebarCommand(tabSidebarEnabled: false))
    }

    @Test func splitLabelCommandVisibilityRequiresEnabledSettingAndSplitContext() {
        #expect(
            TerminalCommandPaletteView.shouldShowSplitLabelCommand(
                splitPaneLabelsEnabled: true,
                hasMultiplePanes: true
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldShowSplitLabelCommand(
                splitPaneLabelsEnabled: false,
                hasMultiplePanes: true
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldShowSplitLabelCommand(
                splitPaneLabelsEnabled: true,
                hasMultiplePanes: false
            )
        )
    }

    @Test func surfaceRefocusSuppressionTargetsPanelLaunchingPaletteActions() {
        #expect(
            TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "workspace:rename-split-label"
            )
        )
        #expect(
            TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "workspace:toggle-scratchpad"
            )
        )
        #expect(
            TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "search:action:workspace:toggle-scratchpad"
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "settings:open"
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "search:file:verify-guide.md"
            )
        )
    }

    @Test func notificationSettingsRouteTargetsTheNotificationsPane() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.selectedSettingsPane = .general
        controller.showNotificationSettings()
        #expect(controller.selectedSettingsPane == .notifications)
    }

    @Test func windowBorderCommandPaletteActionsRemainStable() {
        let actions = TerminalCommandPaletteView.windowBorderActionSnapshotsForTesting(
            borderEnabled: false,
            colorMode: .manual,
            focusedPalette: .aurora,
            unfocusedPalette: .graphite,
            matchThemeUsesManualFallback: false,
            resolvedThemeName: nil,
            reduceMotion: false,
            differentiateWithoutColor: false
        )

        #expect(actions.map(\.id) == [
            "window-border:toggle",
            "window-border:match-theme",
            "window-border:scope",
            "window-border:cycle-focused",
            "window-border:cycle-unfocused",
            "window-border:reduce-motion",
            "window-border:differentiate-without-color",
        ])
        #expect(actions.map(\.title) == [
            "Window Border: Toggle",
            "Window Border: Toggle Match Theme",
            "Window Border: Toggle Focused Split",
            "Window Border: Cycle Focused Palette",
            "Window Border: Cycle Unfocused Palette",
            "Window Border: Open Reduce Motion Settings",
            "Window Border: Open Differentiate Without Color Settings",
        ])
    }

    @Test func windowBorderCommandPaletteDescriptionsTrackThemeAndAccessibilityState() {
        let manualActions = TerminalCommandPaletteView.windowBorderActionSnapshotsForTesting(
            borderEnabled: true,
            colorMode: .manual,
            focusedPalette: .ocean,
            unfocusedPalette: .graphite,
            matchThemeUsesManualFallback: false,
            resolvedThemeName: nil,
            reduceMotion: true,
            differentiateWithoutColor: true
        )
        let manualLookup = Dictionary(uniqueKeysWithValues: manualActions.map { ($0.id, $0) })

        #expect(
            manualLookup["window-border:cycle-focused"]?.description
                == "Focused palette: Ocean"
        )
        #expect(
            manualLookup["window-border:cycle-unfocused"]?.description
                == "Unfocused palette: Graphite"
        )
        #expect(
            manualLookup["window-border:differentiate-without-color"]?.description
                == "Differentiate Without Color is enabled, so unfocused borders currently use dashed outlines."
        )

        let themedActions = TerminalCommandPaletteView.windowBorderActionSnapshotsForTesting(
            borderEnabled: true,
            colorMode: .matchTheme,
            focusedPalette: .ocean,
            unfocusedPalette: .graphite,
            matchThemeUsesManualFallback: true,
            resolvedThemeName: nil,
            reduceMotion: false,
            differentiateWithoutColor: false
        )
        let themedLookup = Dictionary(uniqueKeysWithValues: themedActions.map { ($0.id, $0) })

        #expect(
            themedLookup["window-border:match-theme"]?.description
                == "Match Theme is on, but the theme is unresolved; currently using manual fallback colors"
        )
        #expect(
            themedLookup["window-border:cycle-focused"]?.description
                == "Unavailable in Match Theme mode"
        )
        #expect(
            themedLookup["window-border:differentiate-without-color"]?.description
                == "Open macOS Accessibility > Display to control dashed unfocused border outlines."
        )
    }

    @Test func windowBorderMatchThemeCommandUsesResolvedThemeNameWhenAvailable() {
        let actions = TerminalCommandPaletteView.windowBorderActionSnapshotsForTesting(
            borderEnabled: true,
            colorMode: .matchTheme,
            focusedPalette: .aurora,
            unfocusedPalette: .graphite,
            matchThemeUsesManualFallback: false,
            resolvedThemeName: "Nebula Glow",
            reduceMotion: false,
            differentiateWithoutColor: false
        )
        let lookup = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })

        #expect(
            lookup["window-border:match-theme"]?.description
                == "Using active theme (Nebula Glow); switch to manual focused/unfocused palettes"
        )
        #expect(
            lookup["window-border:reduce-motion"]?.searchTags
                == ["window", "border", "reduce motion", "accessibility"]
        )
    }

    @Test func windowBorderCommandPaletteSearchTagsIncludeModeAndPaletteLabels() {
        let actions = TerminalCommandPaletteView.windowBorderActionSnapshotsForTesting(
            borderEnabled: true,
            colorMode: .manual,
            focusedPalette: .aurora,
            unfocusedPalette: .graphite,
            matchThemeUsesManualFallback: false,
            resolvedThemeName: nil,
            reduceMotion: false,
            differentiateWithoutColor: false
        )
        let lookup = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.searchTags) })

        #expect(lookup["window-border:match-theme"]?.contains("manual") == true)
        #expect(lookup["window-border:match-theme"]?.contains("match theme") == true)
        #expect(lookup["window-border:cycle-focused"]?.contains("aurora") == true)
        #expect(lookup["window-border:cycle-unfocused"]?.contains("graphite") == true)
    }

    private func reset(_ controller: SettingsController) {
        controller.hide()
        controller.selectedSettingsPane = .general
    }
}
