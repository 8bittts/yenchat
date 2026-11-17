import Combine
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct ThemesSettingsStoreTests {
    @Test func storeDoesNotPublishForEqualSnapshotNotification() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture(
            tags: [
                "Curated Theme": ["retro", "audit"],
                "Neon Theme": ["neon"],
            ]
        )
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Curated Theme", to: fixture.userDirectory)
        _ = try writeTheme(named: "Neon Theme", to: fixture.userDirectory)
        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.selectedTheme = "Curated Theme"
        controller.loadThemes()

        let store = ThemesSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        NotificationCenter.default.post(name: .yenThemesSettingsDidChange, object: controller)

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func storeIgnoresUnrelatedControllerChangesAndListsTheWholeCatalog() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let originalKeyboardRecordingActive = controller.keyboardRecordingActive
        let fixture = try makeThemeCatalogFixture(
            tags: [
                "Curated Theme": ["retro", "high-contrast"],
                "Neon Theme": ["neon"],
            ]
        )
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller.keyboardRecordingActive = originalKeyboardRecordingActive
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Curated Theme", to: fixture.userDirectory)
        _ = try writeTheme(named: "Neon Theme", to: fixture.userDirectory)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.selectedTheme = "Curated Theme"
        controller.loadThemes()

        let store = ThemesSettingsStore(controller: controller)
        let baseline = store.snapshot
        var emissionCount = 0
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        // A change on another pane posts its own notification, not the themes one.
        controller.keyboardRecordingActive = !originalKeyboardRecordingActive

        #expect(store.snapshot == baseline)
        #expect(emissionCount == 0)
        #expect(store.snapshot.themes.map(\.name) == ["Curated Theme", "Neon Theme"])
        #expect(store.snapshot.selectedTheme == "Curated Theme")
    }

    @Test func storeTracksSelectedThemeChangesAfterInitialization() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture()
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
            try? FileManager.default.removeItem(at: fixture.root)
        }

        _ = try writeTheme(named: "Curated Theme", to: fixture.userDirectory)
        _ = try writeTheme(named: "Neon Theme", to: fixture.userDirectory)

        controller._testSetThemeCatalogPaths(
            userThemesDirectory: fixture.userDirectory.path,
            themesDirectory: fixture.bundledDirectory.path,
            bundledThemeManifestPath: fixture.manifestPath.path,
            bundledThemeTagsPath: fixture.tagsPath.path
        )
        controller.selectedTheme = "Curated Theme"
        controller.loadThemes()

        let store = ThemesSettingsStore(controller: controller)
        #expect(store.snapshot.selectedTheme == "Curated Theme")

        controller.selectedTheme = "Neon Theme"

        #expect(store.snapshot.selectedTheme == "Neon Theme")
        #expect(store.snapshot.themes.count == 2)
    }

    @Test func storeTracksAsyncThemeReloadLifecycle() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let fixture = try makeThemeCatalogFixture()
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testClearThemeCatalogPaths()
            controller.loadThemes()
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

        let store = ThemesSettingsStore(controller: controller)
        #expect(store.snapshot.themes.count == 1)
        #expect(!store.snapshot.isThemeCatalogLoading)

        _ = try writeTheme(named: "Fresh Theme", to: fixture.userDirectory)
        controller.loadThemesAsync()

        #expect(store.snapshot.isThemeCatalogLoading)
        #expect(store.snapshot.themes.count == 1)

        controller.loadThemes()

        #expect(!store.snapshot.isThemeCatalogLoading)
        #expect(store.snapshot.themes.count == 2)
        #expect(store.snapshot.themes.map(\.name) == ["Baseline Theme", "Fresh Theme"])
    }

    private func makeThemeCatalogFixture(
        manifest: [String] = [],
        tags: [String: [String]] = [:]
    ) throws -> ThemeCatalogFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-theme-store-\(UUID().uuidString)", isDirectory: true)
        let userDirectory = root.appendingPathComponent("user", isDirectory: true)
        let bundledDirectory = root.appendingPathComponent("bundled", isDirectory: true)
        let manifestPath = root.appendingPathComponent("theme-curated-manifest.txt")
        let tagsPath = root.appendingPathComponent("theme-curated-tags.txt")

        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try manifest.joined(separator: "\n").write(to: manifestPath, atomically: true, encoding: .utf8)
        let tagLines = tags.map { key, value in
            "\(key)|\(value.joined(separator: ","))"
        }.sorted()
        try tagLines.joined(separator: "\n").write(to: tagsPath, atomically: true, encoding: .utf8)

        return ThemeCatalogFixture(
            root: root,
            userDirectory: userDirectory,
            bundledDirectory: bundledDirectory,
            manifestPath: manifestPath,
            tagsPath: tagsPath
        )
    }

    @discardableResult
    private func writeTheme(
        named name: String,
        to directory: URL
    ) throws -> String {
        let path = directory.appendingPathComponent("\(name).yen").path
        try defaultThemeContents().write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func defaultThemeContents() -> String {
        [
            "background = #101820",
            "foreground = #F8F9FA",
            "cursor-color = #FFB703",
        ].joined(separator: "\n")
    }
}

private struct ThemeCatalogFixture {
    let root: URL
    let userDirectory: URL
    let bundledDirectory: URL
    let manifestPath: URL
    let tagsPath: URL
}
