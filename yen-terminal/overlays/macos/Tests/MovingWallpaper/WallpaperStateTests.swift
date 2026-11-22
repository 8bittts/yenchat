import CoreGraphics
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
}
