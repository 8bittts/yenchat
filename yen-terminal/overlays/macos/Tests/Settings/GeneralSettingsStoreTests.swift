import AppKit
import Combine
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct GeneralSettingsStoreTests {
    @Test func storeDoesNotPublishForEqualSnapshotNotification() {
        let controller = SettingsController.shared
        let originalAvailableFonts = controller.availableFonts
        let originalFontFamily = controller.fontFamily
        let originalFontSize = controller.fontSize
        let originalCursorStyle = controller.cursorStyle
        let originalCursorBlink = controller.cursorBlink
        let originalCopyOnSelect = controller.copyOnSelect
        let originalScrollbarVisibility = controller.scrollbarVisibility
        let originalBackgroundOpacity = controller.backgroundOpacity
        let originalWindowPaddingX = controller.windowPaddingX
        let originalWindowPaddingY = controller.windowPaddingY
        defer {
            controller.availableFonts = originalAvailableFonts
            controller.fontFamily = originalFontFamily
            controller.fontSize = originalFontSize
            controller.cursorStyle = originalCursorStyle
            controller.cursorBlink = originalCursorBlink
            controller.copyOnSelect = originalCopyOnSelect
            controller.scrollbarVisibility = originalScrollbarVisibility
            controller.backgroundOpacity = originalBackgroundOpacity
            controller.windowPaddingX = originalWindowPaddingX
            controller.windowPaddingY = originalWindowPaddingY
        }

        controller.availableFonts = ["Audit Mono", "Menlo"]
        controller.fontFamily = "Audit Mono"
        controller.fontSize = 17
        controller.cursorStyle = "bar"
        controller.cursorBlink = false
        controller.copyOnSelect = true
        controller.scrollbarVisibility = "never"
        controller.backgroundOpacity = 0.72
        controller.windowPaddingX = 9
        controller.windowPaddingY = 11

        let store = GeneralSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenGeneralSettingsDidChange, object: controller)

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func storeTracksFontCatalogSelectionAndSize() {
        let controller = SettingsController.shared
        let originalAvailableFonts = controller.availableFonts
        let originalFontFamily = controller.fontFamily
        let originalFontSize = controller.fontSize

        defer {
            controller.availableFonts = originalAvailableFonts
            controller.fontFamily = originalFontFamily
            controller.fontSize = originalFontSize
        }

        controller.availableFonts = ["Menlo", "SF Mono"]
        controller.fontFamily = "Menlo"
        controller.fontSize = 14

        let store = GeneralSettingsStore(controller: controller)

        controller.availableFonts = ["Custom Mono", "Menlo", "SF Mono"]
        controller.fontFamily = "Custom Mono"
        controller.fontSize = 18

        #expect(store.snapshot.font.fonts.first == "Custom Mono")
        #expect(store.snapshot.font.fonts.contains("Menlo"))
        #expect(store.snapshot.font.fontFamily == "Custom Mono")
        #expect(store.snapshot.font.fontSize == 18)
    }

    @Test func storeTracksCursorState() {
        let controller = SettingsController.shared
        let originalCursorStyle = controller.cursorStyle
        let originalCursorBlink = controller.cursorBlink

        defer {
            controller.cursorStyle = originalCursorStyle
            controller.cursorBlink = originalCursorBlink
        }

        controller.cursorStyle = "block"
        controller.cursorBlink = true

        let store = GeneralSettingsStore(controller: controller)

        controller.cursorStyle = "bar"
        controller.cursorBlink = false

        #expect(store.snapshot.cursor.cursorStyle == "bar")
        #expect(!store.snapshot.cursor.cursorBlink)
    }

    @Test func storeTracksBehaviorState() {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        let originalScrollbarVisibility = controller.scrollbarVisibility

        defer {
            controller.copyOnSelect = originalCopyOnSelect
            controller.scrollbarVisibility = originalScrollbarVisibility
        }

        controller.copyOnSelect = true
        controller.scrollbarVisibility = "system"

        let store = GeneralSettingsStore(controller: controller)

        controller.copyOnSelect = false
        controller.scrollbarVisibility = "never"

        #expect(!store.snapshot.behavior.copyOnSelect)
        #expect(store.snapshot.behavior.scrollbarVisibility == "never")
    }

    @Test func storeTracksAppearanceStateAndBackgroundImageRefreshes() throws {
        let controller = SettingsController.shared
        let originalBackgroundOpacity = controller.backgroundOpacity
        let originalBackgroundImagePath = controller.backgroundImagePath
        let originalBackgroundImageScope = controller.backgroundImageScope
        let originalWindowPaddingX = controller.windowPaddingX
        let originalWindowPaddingY = controller.windowPaddingY
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-general-settings-store-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "font-size = 14\n".write(to: configURL, atomically: true, encoding: .utf8)
        let imageURL = try makeTestImage(named: "appearance.png", in: tempRoot)

        SettingsController._testSetConfigPathOverride(configURL.path)
        defer {
            controller.backgroundOpacity = originalBackgroundOpacity
            controller.backgroundImagePath = originalBackgroundImagePath
            controller.backgroundImageScope = originalBackgroundImageScope
            controller.windowPaddingX = originalWindowPaddingX
            controller.windowPaddingY = originalWindowPaddingY
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        controller.backgroundOpacity = 0.5
        controller.backgroundImagePath = imageURL.path
        controller.backgroundImageScope = .eachSplit
        controller.windowPaddingX = 6
        controller.windowPaddingY = 8

        let store = GeneralSettingsStore(controller: controller)
        let baselinePreviewVersion = store.snapshot.appearance.backgroundImagePreviewVersion

        try FileManager.default.removeItem(at: imageURL)
        controller.backgroundOpacity = 0.75
        controller.backgroundImageScope = .wholeWindow
        controller.windowPaddingX = 12
        controller.windowPaddingY = 14
        controller.backgroundImagePath = imageURL.path

        #expect(store.snapshot.appearance.backgroundOpacity == 0.75)
        #expect(store.snapshot.appearance.backgroundImageScope == .wholeWindow)
        #expect(store.snapshot.appearance.windowPaddingX == 12)
        #expect(store.snapshot.appearance.windowPaddingY == 14)
        #expect(
            store.snapshot.appearance.backgroundImageIssueDescription
                == "File missing. Replace or remove it."
        )
        #expect(store.snapshot.appearance.backgroundImagePreviewVersion > baselinePreviewVersion)
    }

    @Test func storeTracksMatchThemeAppearanceReloads() throws {
        let controller = SettingsController.shared
        let originalMode = controller.windowBorderColorMode
        let originalSelectedTheme = controller.selectedTheme
        let originalBackgroundImagePath = controller.backgroundImagePath
        let fixture = try makeThemeCatalogFixture()

        defer {
            controller.windowBorderColorMode = originalMode
            controller.selectedTheme = originalSelectedTheme
            controller.backgroundImagePath = originalBackgroundImagePath
            controller._testClearThemeCatalogPaths()
            SettingsController._testSetConfigPathOverride(nil)
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        let initialThemeName = "Store Theme A"
        let replacementThemeName = "Store Theme B"
        _ = try writeTheme(
            named: initialThemeName,
            contents: defaultThemeContents(cursor: "#5BC0EB"),
            to: fixture.userDirectory
        )
        _ = try writeTheme(
            named: replacementThemeName,
            contents: defaultThemeContents(cursor: "#FF6A3D"),
            to: fixture.userDirectory
        )
        try "theme = \(initialThemeName)\n".write(
            to: fixture.root.appendingPathComponent("config.yen", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        SettingsController._testSetConfigPathOverride(
            fixture.root.appendingPathComponent("config.yen", isDirectory: false).path
        )
        controller.selectedTheme = initialThemeName
        controller.windowBorderColorMode = .matchTheme
        controller.loadThemes()

        let store = GeneralSettingsStore(controller: controller)
        let baselineGradient = store.snapshot.appearance.windowBorderFocusedGradient

        controller.selectedTheme = replacementThemeName

        #expect(
            store.snapshot.appearance.windowBorderMatchThemeStatusMessage
                .contains(replacementThemeName)
        )
        #expect(!store.snapshot.appearance.windowBorderMatchThemeUsesManualFallback)
        #expect(store.snapshot.appearance.windowBorderFocusedGradient != baselineGradient)
    }

    @Test func storeTracksMatchThemeFallbackStatusWhenReloadDropsResolvedTheme() throws {
        let controller = SettingsController.shared
        let originalMode = controller.windowBorderColorMode
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture()

        defer {
            controller.windowBorderColorMode = originalMode
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            SettingsController._testSetConfigPathOverride(nil)
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        let themeName = "Store Theme A"
        let themeURL = try writeTheme(
            named: themeName,
            contents: defaultThemeContents(cursor: "#5BC0EB"),
            to: fixture.userDirectory
        )
        try "theme = \(themeName)\n".write(
            to: fixture.root.appendingPathComponent("config.yen", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        SettingsController._testSetConfigPathOverride(
            fixture.root.appendingPathComponent("config.yen", isDirectory: false).path
        )
        controller.selectedTheme = themeName
        controller.windowBorderColorMode = .matchTheme
        controller.loadThemes()

        let store = GeneralSettingsStore(controller: controller)

        try FileManager.default.removeItem(atPath: themeURL)
        controller.loadThemes()

        #expect(store.snapshot.appearance.windowBorderMatchThemeUsesManualFallback)
        #expect(
            store.snapshot.appearance.windowBorderMatchThemeStatusMessage
                == "Theme \"\(themeName)\" unavailable; using Manual palettes."
        )
    }

    private func makeThemeCatalogFixture(
        manifest: [String] = [],
        tags: [String: [String]] = [:]
    ) throws -> ThemeCatalogFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-general-theme-store-\(UUID().uuidString)", isDirectory: true)
        let userDirectory = root.appendingPathComponent("user", isDirectory: true)
        let bundledDirectory = root.appendingPathComponent("bundled", isDirectory: true)
        let fullDirectory = root.appendingPathComponent("full", isDirectory: true)
        let manifestPath = root.appendingPathComponent("theme-curated-manifest.txt")
        let tagsPath = root.appendingPathComponent("theme-curated-tags.txt")

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try manifest.joined(separator: "\n").write(to: manifestPath, atomically: true, encoding: .utf8)
        let tagLines = tags.map { key, value in
            "\(key)|\(value.joined(separator: ","))"
        }.sorted()
        try tagLines.joined(separator: "\n").write(to: tagsPath, atomically: true, encoding: .utf8)

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
        let path = directory.appendingPathComponent("\(name).yen").path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func defaultThemeContents(cursor: String) -> String {
        [
            "background = #101820",
            "foreground = #F8F9FA",
            "cursor-color = \(cursor)",
        ].joined(separator: "\n")
    }

    private func makeTestImage(named name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let imageData = try #require(bitmap.representation(using: .png, properties: [:]))
        try imageData.write(to: url, options: .atomic)
        return url
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
