/// The wallpaper controls shown in Settings. Equal values need no redraw.
struct WallpaperControlsState: Equatable {
    var isDownloading = false
    var perDesktop = false
    var isMuted = true
    var isPaused = false
    var hasAnyWallpaper = false
    /// The wallpaper the source buttons replace; nil when that desktop has none.
    var fileName: String?
}
