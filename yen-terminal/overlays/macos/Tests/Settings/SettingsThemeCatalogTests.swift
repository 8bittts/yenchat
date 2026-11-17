import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsThemeCatalogTests {
    @Test func retiredFullCatalogThemesAreIgnoredWithoutAdditionalDirectoryScans() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture(manifest: ["curated-theme"])
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            SettingsThemeCatalog._testResetMetrics()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Curated Theme", to: fixture.bundledDirectory)
        _ = try writeTheme(named: "Retired Full", to: fixture.retiredFullDirectory)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.selectedTheme = ""
        controller.loadThemes()

        let visibleThemeNames = Set(controller.availableThemes.map(\.name))
        #expect(visibleThemeNames.contains("Curated Theme"))
        #expect(!visibleThemeNames.contains("Retired Full"))

        SettingsThemeCatalog._testResetMetrics()
        controller.selectedTheme = "Retired Full"
        for _ in 0..<8 {
            controller.refreshResolvedActiveThemeInfoForTesting()
        }

        #expect(controller.windowBorderResolvedThemeName == nil)
        #expect(SettingsThemeCatalog._testDirectoryScanCount == 0)
    }

    @Test func themeCatalogSnapshotPrefersUserOverridesAndOmitsNonCuratedBundledThemes() throws {
        let fixture = try makeThemeCatalogFixture(
            manifest: [
                "shared-name",
                "curated-only",
            ]
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let userOverridePath = try writeTheme(
            named: "Shared Name",
            contents: defaultThemeContents(cursor: "#FFAA00"),
            to: fixture.userDirectory
        )
        _ = try writeTheme(
            named: "Shared Name",
            contents: defaultThemeContents(cursor: "#00AAFF"),
            to: fixture.bundledDirectory
        )
        _ = try writeTheme(named: "Curated Only", to: fixture.bundledDirectory)
        _ = try writeTheme(named: "Non Curated", to: fixture.bundledDirectory)
        _ = try writeTheme(named: "Retired Full", to: fixture.retiredFullDirectory)

        SettingsThemeCatalog._testResetMetrics()
        let snapshot = SettingsThemeCatalog.buildSnapshot(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )

        #expect(SettingsThemeCatalog._testDirectoryScanCount == 2)
        #expect(
            SettingsThemeCatalog.resolveThemeInfo(named: "Shared Name", in: snapshot)?.path
                == userOverridePath
        )
        #expect(SettingsThemeCatalog.resolveThemeInfo(named: "Non Curated", in: snapshot) == nil)
        #expect(snapshot.visibleThemes.map(\.name) == ["Shared Name", "Curated Only"])
    }

    @Test func refreshResolvedActiveThemeInfoRebuildsSnapshotAfterDirectoryMutation() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture()
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            SettingsThemeCatalog._testResetMetrics()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Curated Theme", to: fixture.bundledDirectory)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.selectedTheme = ""
        controller.loadThemes()

        SettingsThemeCatalog._testResetMetrics()
        _ = try writeTheme(named: "Fresh User", to: fixture.userDirectory)
        controller.selectedTheme = "Fresh User"
        controller.refreshResolvedActiveThemeInfoForTesting()

        #expect(controller.windowBorderResolvedThemeName == "Fresh User")
        #expect(SettingsThemeCatalog._testDirectoryScanCount == 2)
    }

    @Test func themeSelectionMatchesQuotedAndExtendedConfigNames() {
        #expect(
            SettingsController.themeSelectionMatches(
                selectedTheme: "\"Curated Theme.yen\"",
                catalogThemeName: "Curated Theme"
            )
        )
        #expect(
            SettingsController.themeSelectionMatches(
                selectedTheme: "Curated Theme.yentheme",
                catalogThemeName: "Curated Theme"
            )
        )
        #expect(
            !SettingsController.themeSelectionMatches(
                selectedTheme: "Another Theme",
                catalogThemeName: "Curated Theme"
            )
        )
    }

    @Test func themeGalleryApplyDebounceCommitsOnlyTheLastSelection() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-theme-apply-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try """
        theme = Baseline
        background = #111111
        foreground = #eeeeee
        """.write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller._testResetStatusState()
        controller._testClearThemeCatalogPaths()
        controller.loadThemes()
        controller.selectedTheme = "Baseline"

        controller.applyTheme(ThemeInfo(name: "First Theme", path: "/tmp/first.yen", bundled: false))
        controller.applyTheme(ThemeInfo(name: "Final Theme", path: "/tmp/final.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)
        controller.commitPendingThemeSelectionForTesting()

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(controller.selectedTheme == "Final Theme")
        #expect(contents.contains("theme = Final Theme"))
        #expect(!contents.contains("theme = First Theme"))
        #expect(!contents.contains("background ="))
        #expect(!contents.contains("foreground ="))
    }

    @Test func userThemeSavedWithSuffixAppliesTheFileNameTheEngineResolves() throws {
        // The engine opens `<themes dir>/<theme value>` verbatim. A user theme saved
        // as `Name.yen` showed in the picker as `Name`, and applying it wrote
        // `theme = Name`, which the engine reports as not found.
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture(manifest: ["bundled-theme"])
        let configURL = fixture.root.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Suffixed User", to: fixture.userDirectory)
        try defaultThemeContents().write(
            toFile: fixture.bundledDirectory.appendingPathComponent("Bundled Theme").path,
            atomically: true,
            encoding: .utf8
        )
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller._testResetStatusState()
        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.loadThemes()
        controller.selectedTheme = "Baseline"

        let suffixed = try #require(controller.availableThemes.first { $0.name == "Suffixed User" })
        let bundled = try #require(controller.availableThemes.first { $0.name == "Bundled Theme" })
        #expect(suffixed.configReference == "Suffixed User.yen")
        #expect(bundled.configReference == "Bundled Theme")

        controller.applyTheme(suffixed)
        controller.commitPendingThemeSelectionForTesting()

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("theme = Suffixed User.yen"))
        // The picker and Match Theme still resolve the suffixed reference to its tile.
        #expect(
            SettingsController.themeSelectionMatches(
                selectedTheme: controller.selectedTheme,
                catalogThemeName: suffixed.name
            )
        )
        controller.refreshResolvedActiveThemeInfoForTesting()
        #expect(controller.windowBorderResolvedThemeName == "Suffixed User")
    }

    @Test func pendingThemeClickSurvivesAConfigReloadInsideTheDebounce() throws {
        // The write reads the controller's selection when the debounce ends. A
        // reload inside that window re-read `theme` from disk into the controller,
        // so the write became a no-op and the click was dropped.
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let originalThemeReloadHook = controller.testThemeNameOnConfigReload
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-theme-reload-race-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            controller.testThemeNameOnConfigReload = originalThemeReloadHook
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller.testThemeNameOnConfigReload = nil
        controller._testResetStatusState()
        controller._testClearThemeCatalogPaths()
        controller.loadThemes()
        controller.selectedTheme = "Baseline"

        controller.applyTheme(ThemeInfo(name: "Clicked Theme", path: "/tmp/clicked.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)

        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        #expect(controller.selectedTheme == "Baseline")
        #expect(controller._testHasPendingThemeSelectionCommit)

        controller.commitPendingThemeSelectionForTesting()

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(controller.selectedTheme == "Clicked Theme")
        #expect(contents.contains("theme = Clicked Theme"))
        #expect(!contents.contains("theme = Baseline"))
    }

    @Test func resetAfterAPendingThemeClickIsNotOverriddenByThatClick() throws {
        // A full persist drops the pending click instead of restoring it: the
        // reset ran after the click, so the reset is the later intent.
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let baselineState = controller.captureSettingsStateForTesting()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-theme-reset-order-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            // Reset All also changes preferences outside the config file.
            controller.restoreSettingsStateForTesting(baselineState)
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller._testResetStatusState()
        controller._testClearThemeCatalogPaths()
        controller.loadThemes()
        controller.selectedTheme = "Baseline"

        controller.applyTheme(ThemeInfo(name: "Clicked Theme", path: "/tmp/clicked.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)

        controller.resetAllSettingsToDefaultsForTesting()

        #expect(!controller._testHasPendingThemeSelectionCommit)
        #expect(controller.selectedTheme.isEmpty)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(!contents.contains("theme ="))
    }

    @Test func resetSelectsTheDefaultThemeWhenTheBuildShipsIt() throws {
        // Removing the `theme` key left the terminal on the engine's built-in
        // colors with no tile selected. A reset selects the default theme instead.
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let baselineState = controller.captureSettingsStateForTesting()
        let fixture = try makeThemeCatalogFixture(manifest: ["yen", "other-theme"])
        let configURL = fixture.root.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            // Reset All also changes preferences outside the config file.
            controller.restoreSettingsStateForTesting(baselineState)
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        for name in ["YEN", "Other Theme"] {
            try defaultThemeContents().write(
                toFile: fixture.bundledDirectory.appendingPathComponent(name).path,
                atomically: true,
                encoding: .utf8
            )
        }
        try "theme = Other Theme\nbackground = #111111\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller._testResetStatusState()
        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.loadThemes()
        controller.selectedTheme = "Other Theme"

        controller.resetAllSettingsToDefaultsForTesting()

        #expect(controller.selectedTheme == "YEN")
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("theme = YEN"))
        #expect(!contents.contains("background ="))
    }

    @Test func themeGalleryApplyFailureRestoresDiskSelectionAndShowsErrorStatus() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-theme-apply-failure-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempRoot.path)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        controller._testResetStatusState()
        controller._testClearThemeCatalogPaths()
        controller.loadThemes()
        controller.selectedTheme = "Baseline"

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempRoot.path)
        controller.applyTheme(ThemeInfo(name: "Broken Theme", path: "/tmp/broken.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)
        controller.commitPendingThemeSelectionForTesting()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempRoot.path)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(controller.selectedTheme == "Baseline")
        #expect(contents == "theme = Baseline\n")
        #expect(controller.statusMessage.hasPrefix("Apply failed:"))
        #expect(controller.statusSeverity == .error)
    }

    @Test func themeCatalogReloadStartsInLoadingStateWithoutDiscardingVisibleResults() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture()
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            controller._testResetStatusState()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Baseline Theme", to: fixture.userDirectory)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.loadThemes()
        #expect(controller.availableThemes.map(\.name) == ["Baseline Theme"])

        _ = try writeTheme(named: "Fresh Theme", to: fixture.userDirectory)

        controller.loadThemesAsync()

        #expect(controller.isThemeCatalogLoading)
        #expect(controller.availableThemes.map(\.name) == ["Baseline Theme"])
        controller.loadThemes()
        #expect(controller.availableThemes.map(\.name) == ["Baseline Theme", "Fresh Theme"])
        #expect(!controller.isThemeCatalogLoading)
    }

    private func makeThemeCatalogFixture(
        manifest: [String] = [],
        tags: [String: [String]] = [:]
    ) throws -> ThemeCatalogFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-theme-catalog-\(UUID().uuidString)", isDirectory: true)
        let userDirectory = root.appendingPathComponent("user", isDirectory: true)
        let bundledDirectory = root.appendingPathComponent("bundled", isDirectory: true)
        let retiredFullDirectory = root.appendingPathComponent("retired-full", isDirectory: true)
        let manifestPath = root.appendingPathComponent("theme-curated-manifest.txt")
        let tagsPath = root.appendingPathComponent("theme-curated-tags.txt")

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: retiredFullDirectory, withIntermediateDirectories: true)
        try manifest.joined(separator: "\n").write(to: manifestPath, atomically: true, encoding: .utf8)
        let tagLines = tags.map { key, value in
            "\(key)|\(value.joined(separator: ","))"
        }.sorted()
        try tagLines.joined(separator: "\n").write(to: tagsPath, atomically: true, encoding: .utf8)

        return ThemeCatalogFixture(
            root: root,
            userDirectory: userDirectory,
            bundledDirectory: bundledDirectory,
            retiredFullDirectory: retiredFullDirectory,
            manifestPath: manifestPath,
            tagsPath: tagsPath
        )
    }

    @discardableResult
    private func writeTheme(
        named name: String,
        contents: String? = nil,
        to directory: URL
    ) throws -> String {
        let path = directory.appendingPathComponent("\(name).yen").path
        try (contents ?? defaultThemeContents()).write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func defaultThemeContents(
        background: String = "#101820",
        foreground: String = "#F8F9FA",
        cursor: String = "#FFB703"
    ) -> String {
        [
            "background = \(background)",
            "foreground = \(foreground)",
            "cursor-color = \(cursor)",
        ].joined(separator: "\n")
    }
}

private struct ThemeCatalogFixture {
    let root: URL
    let userDirectory: URL
    let bundledDirectory: URL
    let retiredFullDirectory: URL
    let manifestPath: URL
    let tagsPath: URL
}
