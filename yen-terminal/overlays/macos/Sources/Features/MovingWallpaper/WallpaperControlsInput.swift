import CoreGraphics
import Foundation

/// Live wallpaper state the Settings controls read.
/// Built by `WallpaperManager`; rendered by `MovingWallpaperPreference`.
struct WallpaperControlsInput: Equatable {
    var downloadProgress: Double?
    var mode: WallpaperMode
    var isMuted: Bool
    var isPaused: Bool
    var hasAnyWallpaper: Bool
    var sharedFileName: String?
    var displays: [DisplayControlsInput]

    /// What the buttons show: the file they act on, and which playback
    /// commands apply. Equal values never redraw the Settings row.
    var state: WallpaperControlsState {
        let fileName = mode == .allDesktops
            ? sharedFileName
            : displays.first?.spaces.first(where: \.isCurrent)?.fileName
        return WallpaperControlsState(
            isDownloading: downloadProgress != nil,
            perDesktop: mode == .perDesktop,
            isMuted: isMuted,
            isPaused: isPaused,
            hasAnyWallpaper: hasAnyWallpaper,
            fileName: fileName
        )
    }
}

struct DisplayControlsInput: Equatable {
    var id: CGDirectDisplayID
    var name: String
    var spaces: [SpaceControlsInput]
}

struct SpaceControlsInput: Equatable {
    var fileName: String?
    var isCurrent: Bool
}

struct WallpaperControlsState: Equatable {
    var isDownloading = false
    var perDesktop = false
    var isMuted = true
    var isPaused = false
    var hasAnyWallpaper = false
    /// The wallpaper the source buttons replace; nil when that desktop has none.
    var fileName: String?
}
