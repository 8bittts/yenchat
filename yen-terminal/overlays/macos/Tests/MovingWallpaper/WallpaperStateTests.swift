import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import YEN

struct WallpaperStateTests {
    private let entry = WallpaperEntry(localURL: URL(filePath: "/Users/dev/Movies/loop.mp4"))

    /// A wallpaper saved while only an external display was connected must
    /// appear on the built-in display when that is the one connected now.
    @Test func allDesktopsWallpaperFollowsTheConnectedDisplays() {
        var state = WallpaperState()
        state.entries[DesktopKey(displayID: 99)] = entry
        let changed = state.reconcileAllDesktops(connectedDisplayIDs: [1])

        #expect(changed)
        #expect(state.entries == [DesktopKey(displayID: 1): entry])
    }

    /// With every display gone there is nowhere to move the wallpaper, and
    /// dropping it would lose the user's choice for good once that is saved.
    @Test func allDesktopsWallpaperSurvivesAMomentWithNoDisplay() {
        var state = WallpaperState()
        state.entries[DesktopKey(displayID: 1)] = entry
        let changed = state.reconcileAllDesktops(connectedDisplayIDs: [])

        #expect(!changed)
        #expect(state.entries == [DesktopKey(displayID: 1): entry])
    }
    /// The order of a display's Spaces is the only thing that survives macOS
    /// renumbering them, so the snapshot must keep it as the system lists it.
    @Test func snapshotKeepsTheSystemOrderOfEachDisplaysSpaces() {
        let snapshot = ManagedDisplaySpacesSnapshot.from(
            rawEntries: [[
                "Display Identifier": "UUID-4",
                "Current Space": ["id64": NSNumber(value: 30)],
                "Spaces": [30, 10, 20].map { ["id64": NSNumber(value: $0)] },
            ]],
            screensByDisplayIdentifier: ["UUID-4": 4, "UUID-1": 1],
            fallbackGlobalSpaceID: 7
        )

        #expect(snapshot.orderedSpacesByDisplayID == [4: [30, 10, 20]])
    }

    /// A Space the user removed while its siblings stay is not a renumbering:
    /// its wallpaper must not jump to the desktop that took its place.
    @Test func aRemovedSpaceMovesNothingWhileAnotherAssignedSpaceLives() {
        var state = WallpaperState()
        let gone = DesktopKey(displayID: 4, spaceID: 11)
        let kept = DesktopKey(displayID: 4, spaceID: 12)
        state.entries = [gone: entry, kept: entry]
        state.spacePositions = [gone: 0, kept: 1]
        state.followSpaces([4: [12, 13]]) { _ in 12 }

        #expect(Set(state.entries.keys) == [gone, kept])
    }

    /// Renumbering one display never moves another display's wallpaper.
    @Test func renumberingOneDisplayLeavesTheOtherAlone() {
        var state = WallpaperState()
        let builtIn = DesktopKey(displayID: 1, spaceID: 1)
        let external = DesktopKey(displayID: 4, spaceID: 1501)
        state.entries = [builtIn: entry, external: entry]
        state.spacePositions = [builtIn: 0, external: 0]
        state.followSpaces([1: [1, 2], 4: [2198]]) { _ in 1 }

        #expect(Set(state.entries.keys) == [builtIn, DesktopKey(displayID: 4, spaceID: 2198)])
    }

    /// A video resumes where it was after it follows its desktop.
    @Test func playbackPositionMovesWithTheWallpaper() {
        var state = WallpaperState()
        let old = DesktopKey(displayID: 4, spaceID: 1501)
        let time = CMTime(seconds: 42, preferredTimescale: 600)
        state.entries = [old: entry]
        state.playbackPositions = [old: time]
        state.followSpaces([4: [2198]]) { _ in 2198 }

        #expect(state.playbackPositions == [DesktopKey(displayID: 4, spaceID: 2198): time])
    }

    /// The position is saved, so a restart can follow the desktop too.
    @Test func spacePositionSurvivesSaveAndLoad() {
        let defaults = WallpaperMemoryDefaults()
        let store = WallpaperPersistenceStore(
            userDefaults: defaults,
            fileExists: { _ in true },
            displayIdentity: DisplayIdentity(uuid: { _ in nil }, connectedDisplayID: { _ in nil })
        )
        var state = WallpaperState()
        let key = DesktopKey(displayID: 4, spaceID: 1502)
        state.entries = [key: entry]
        state.spacePositions = [key: 1]
        store.save(mode: .perDesktop, isMuted: true, state: state)

        #expect(store.load().state.spacePositions == [key: 1])
    }
}
