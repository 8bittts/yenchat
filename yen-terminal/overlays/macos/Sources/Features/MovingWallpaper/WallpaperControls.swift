import AppKit

@MainActor
final class WallpaperControls {
    private let wallpaperManager: WallpaperManager
    private var picker: PhotosPickerController?
    private var active = true
    private var cleanup: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        wallpaperManager = WallpaperManager(persistenceStore: WallpaperPersistenceStore(userDefaults: defaults))
        let protected = wallpaperManager.referencedLocalPaths
        let start = Date()
        cleanup = Task.detached(priority: .background) {
            CacheJanitor.enforceDefaultPolicies(protecting: protected, modifiedBefore: start)
            guard !Task.isCancelled else { return }
            CacheJanitor.pruneUnreferencedPhotosCaches(referencedPaths: protected, modifiedBefore: start)
        }
    }

    func stop() {
        active = false
        cleanup?.cancel()
        picker?.cancel()
        wallpaperManager.tearDown()
    }

    /// The state the Settings buttons show. `onChange` reports each change.
    var state: WallpaperControlsState { wallpaperManager.controlsInput().state }

    var onChange: (() -> Void)? {
        get { wallpaperManager.onChange }
        set { wallpaperManager.onChange = newValue }
    }

    // MARK: - Actions

    // Each source applies to the current desktop of every display in Per
    // Desktop mode, and to every desktop otherwise.

    func playDemo() { wallpaperManager.playDemo() }
    func chooseFile() { wallpaperManager.selectFile() }
    func shufflePhotos() { wallpaperManager.shuffleFromPhotos() }
    func choosePhotos() { presentPhotosPicker(for: nil) }
    func remove() { wallpaperManager.clearCurrentWallpaper() }
    func cancelDownload() { wallpaperManager.cancelDownload() }
    func togglePause() { wallpaperManager.togglePause() }
    func toggleMute() { wallpaperManager.toggleMute() }
    func togglePerDesktop() { wallpaperManager.togglePerDesktop() }

    func pasteYouTube() {
        guard let urlString = promptForYouTubeURL() else { return }
        wallpaperManager.setYouTubeWallpaper(urlString: urlString)
    }

    private func promptForYouTubeURL() -> String? {
        WallpaperPresentation.withForegroundActivation {
            let alert = NSAlert()
            alert.messageText = "Paste YouTube URL"
            alert.informativeText = "Enter a YouTube video URL to use as your wallpaper."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
            input.placeholderString = "https://youtube.com/watch?v=..."
            // A pasted clipboard value hides the placeholder, so the field needs its own name.
            input.setAccessibilityLabel("YouTube URL")
            input.lineBreakMode = .byTruncatingMiddle
            input.usesSingleLineMode = true
            // Prefill only a YouTube URL: any other clipboard text is not what
            // this field is for and may be something private.
            if let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               YouTubeURLParser.isYouTubeURL(clip) {
                input.stringValue = clip
            }
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    /// Run the Photos picker and assign the pick (nil display = all).
    /// One picker at a time: a second request while one is open does nothing.
    private func presentPhotosPicker(for displayID: CGDirectDisplayID?) {
        guard picker == nil, active else { return }
        let controller = PhotosPickerController()
        picker = controller
        Task { [weak self] in
            let url = await controller.run()
            guard let self, self.active else { return }
            self.picker = nil
            guard let url else { return }
            self.wallpaperManager.setWallpaper(url: url, for: displayID)
        }
    }
}
