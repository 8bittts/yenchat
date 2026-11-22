import AppKit
import Foundation
import Testing
@testable import YEN

/// Preferences kept in memory. A named suite leaves an empty file in
/// `~/Library/Preferences` even after `removePersistentDomain`.
private final class MemoryDefaults: UserDefaults {
    private nonisolated(unsafe) var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

/// The switch in Settings must own the desktop panels: on shows them, off
/// removes every one, and nothing brings them back while it is off.
@MainActor
struct WallpaperToggleTests {
    private let defaults = MemoryDefaults()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let wallpaper: URL

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        wallpaper = folder.appendingPathComponent("loop.gif")
        // A one-pixel GIF: a real file the engine accepts, with no video decode.
        try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")).write(to: wallpaper)
    }

    private var store: WallpaperPersistenceStore { WallpaperPersistenceStore(userDefaults: defaults) }

    private var visiblePanels: Int {
        NSApp.windows.filter { $0 is WallpaperPanel && $0.isVisible }.count
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Standalone MovingPaper suspends YEN's engine, so no panel would appear.
    private nonisolated static var movingPaperIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.8bittts.movingpaper").isEmpty
    }

    @Test(.enabled(if: !movingPaperIsRunning))
    func theSwitchShowsAndRemovesTheWallpaperEveryTime() throws {
        defer { cleanUp() }
        var saved = WallpaperState()
        let displayID = try #require(NSScreen.screens.first?.displayID)
        saved.entries[DesktopKey(displayID: displayID)] = WallpaperEntry(localURL: wallpaper)
        store.save(mode: .allDesktops, isMuted: true, state: saved)
        let extras = DesktopExtras(defaults: defaults)
        defer { extras.stop() }

        for round in 1...10 {
            extras.setWallpaper(true)
            #expect(visiblePanels > 0, "round \(round): on shows the wallpaper")
            #expect(defaults.bool(forKey: DesktopExtras.wallpaperKey))

            extras.setWallpaper(false)
            #expect(visiblePanels == 0, "round \(round): off removes every panel")
            #expect(!defaults.bool(forKey: DesktopExtras.wallpaperKey))
        }

        // The next launch starts from the saved switch, which is off.
        let relaunched = DesktopExtras(defaults: defaults)
        defer { relaunched.stop() }
        relaunched.restore()
        #expect(!relaunched.showsWallpaper)
        #expect(visiblePanels == 0)
    }

    /// A file panel, a download or a Photos export can finish after the engine
    /// was stopped. Its result may be saved, but it must not show a wallpaper.
    @Test func aChoiceThatLandsAfterTheSwitchWentOffShowsNothing() throws {
        defer { cleanUp() }
        try #require(!NSScreen.screens.isEmpty)
        let manager = WallpaperManager(persistenceStore: store)
        manager.setWallpaper(url: wallpaper)
        #expect(visiblePanels > 0)

        manager.tearDown()
        #expect(visiblePanels == 0)

        manager.setWallpaper(url: wallpaper)
        #expect(visiblePanels == 0)
    }
}
