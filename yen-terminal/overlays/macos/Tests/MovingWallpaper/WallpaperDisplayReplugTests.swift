import AppKit
import Foundation
import Testing
@testable import YEN

/// macOS gives a display new Space ids when it is plugged in again, and when
/// the app starts after that happened. A Per Desktop wallpaper must follow its
/// desktop onto the new ids instead of being lost.
@MainActor
struct WallpaperDisplayReplugTests {
    private let defaults = WallpaperMemoryDefaults()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let wallpaper: URL
    private let otherWallpaper: URL

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // One-pixel GIFs: real files the engine accepts, with no video decode.
        let gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        wallpaper = folder.appendingPathComponent("loop.gif")
        otherWallpaper = folder.appendingPathComponent("other.gif")
        try gif.write(to: wallpaper)
        try gif.write(to: otherWallpaper)
    }

    private var store: WallpaperPersistenceStore { WallpaperPersistenceStore(userDefaults: defaults) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// What one display shows: its visible wallpaper panels, and the file the
    /// manager assigns to the display's current Space (All Desktops: its slot).
    private func shown(on displayID: CGDirectDisplayID, by manager: WallpaperManager) -> (panels: Int, file: String?) {
        let frame = NSScreen.screens.first { $0.displayID == displayID }?.frame
        let panels = NSApp.windows.filter { $0 is WallpaperPanel && $0.isVisible && $0.frame == frame }.count
        return (panels, manager.controlsState.fileName)
    }

    /// The managed-spaces snapshot macOS would report: the display's Spaces in
    /// Mission Control order, the first one current.
    private static func snapshot(
        displayID: CGDirectDisplayID,
        spaces: [UInt64],
        current: UInt64? = nil
    ) -> ManagedDisplaySpacesSnapshot {
        let identifier = "TEST-DISPLAY-UUID"
        return ManagedDisplaySpacesSnapshot.from(
            rawEntries: [[
                "Display Identifier": identifier,
                "Current Space": ["id64": NSNumber(value: current ?? spaces[0])],
                "Spaces": spaces.map { ["id64": NSNumber(value: $0)] },
            ]],
            screensByDisplayIdentifier: [identifier: displayID],
            fallbackGlobalSpaceID: 1
        )
    }

    private func savedEntries() -> [DesktopKey: String] {
        store.load().state.entries.mapValues(\.localURL.lastPathComponent)
    }

    /// Screen-change observers run from the main queue.
    private func postScreenChange() async {
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func perDesktopWallpaperFollowsItsDisplayAcrossAReplug() async throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1501)] = WallpaperEntry(localURL: wallpaper)
        store.save(mode: .perDesktop, isMuted: true, state: saved)

        var live = Self.snapshot(displayID: displayID, spaces: [1501])
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }
        try #require(shown(on: displayID, by: manager) == (1, "loop.gif"))

        // Plugged back in: same display, every Space id new.
        live = Self.snapshot(displayID: displayID, spaces: [2198])
        await postScreenChange()

        #expect(shown(on: displayID, by: manager) == (1, "loop.gif"))
        #expect(savedEntries() == [DesktopKey(displayID: displayID, spaceID: 2198): "loop.gif"])
    }

    /// Two desktops keep their own wallpapers: each lands on the new Space at
    /// its old position, whatever Space is current.
    @Test func eachDesktopKeepsItsPositionAcrossAReplug() async throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1501)] = WallpaperEntry(localURL: wallpaper)
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1502)] = WallpaperEntry(localURL: otherWallpaper)
        store.save(mode: .perDesktop, isMuted: true, state: saved)

        var live = Self.snapshot(displayID: displayID, spaces: [1501, 1502])
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }

        live = Self.snapshot(displayID: displayID, spaces: [2198, 2199], current: 2199)
        await postScreenChange()

        #expect(shown(on: displayID, by: manager) == (1, "other.gif"))
        #expect(savedEntries() == [
            DesktopKey(displayID: displayID, spaceID: 2198): "loop.gif",
            DesktopKey(displayID: displayID, spaceID: 2199): "other.gif",
        ])
    }

    /// The app was not running when the display came back with new Space ids.
    @Test func perDesktopWallpaperFollowsItsDisplayAcrossARestart() throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1501)] = WallpaperEntry(localURL: wallpaper)
        store.save(mode: .perDesktop, isMuted: true, state: saved)

        let live = Self.snapshot(displayID: displayID, spaces: [2198])
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }

        #expect(shown(on: displayID, by: manager) == (1, "loop.gif"))
        #expect(savedEntries() == [DesktopKey(displayID: displayID, spaceID: 2198): "loop.gif"])
    }

    /// A wallpaper the user set on a live Space is never replaced by one that
    /// lost its Space.
    @Test func aWallpaperOnALiveSpaceIsNeverOverwritten() throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID, spaceID: 1501)] = WallpaperEntry(localURL: wallpaper)
        saved.entries[DesktopKey(displayID: displayID, spaceID: 2198)] = WallpaperEntry(localURL: otherWallpaper)
        store.save(mode: .perDesktop, isMuted: true, state: saved)

        let live = Self.snapshot(displayID: displayID, spaces: [2198])
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }

        #expect(shown(on: displayID, by: manager) == (1, "other.gif"))
        #expect(savedEntries()[DesktopKey(displayID: displayID, spaceID: 2198)] == "other.gif")
    }

    /// All Desktops pins one wallpaper per display, not per Space, so new
    /// Space ids change nothing.
    @Test func allDesktopsWallpaperStaysAcrossAReplug() async throws {
        defer { cleanUp() }
        let displayID = try #require(NSScreen.screens.first?.displayID)
        var saved = WallpaperState()
        saved.entries[DesktopKey(displayID: displayID)] = WallpaperEntry(localURL: wallpaper)
        store.save(mode: .allDesktops, isMuted: true, state: saved)

        var live = Self.snapshot(displayID: displayID, spaces: [1501])
        let manager = WallpaperManager(persistenceStore: store, spacesSnapshot: { live })
        defer { manager.tearDown() }
        try #require(shown(on: displayID, by: manager) == (1, "loop.gif"))

        live = Self.snapshot(displayID: displayID, spaces: [2198])
        await postScreenChange()

        #expect(shown(on: displayID, by: manager) == (1, "loop.gif"))
        #expect(savedEntries()[DesktopKey(displayID: displayID)] == "loop.gif")
    }
}
