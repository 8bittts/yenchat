import AppKit

@MainActor
@available(macOS 27.0, *)
final class WallpaperControls: NSObject {
    private let wallpaperManager = WallpaperManager()
    private var picker: PhotosPickerController?
    private var active = true
    private var cleanup: Task<Void, Never>?

    override init() {
        super.init()
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

    func open(from button: NSButton) {
        makeMenu(MenuSnapshot.rows(from: wallpaperManager.menuInput()))
            .popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 3), in: button)
    }

    private func append(_ rows: [MenuRow], to menu: NSMenu) {
        for row in rows {
            menu.addItem(makeItem(row))
        }
    }

    private func makeItem(_ row: MenuRow) -> NSMenuItem {
        switch row {
        case .disabled(let title):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .separator:
            return .separator()
        case .sectionHeader(let title):
            return NSMenuItem.sectionHeader(title: title)
        case .command(let command):
            return makeCommandItem(command)
        case .submenu(let title, let checked, let rows):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = checked ? .on : .off
            item.submenu = makeMenu(rows)
            return item
        }
    }

    private func makeMenu(_ rows: [MenuRow]) -> NSMenu {
        let menu = NSMenu()
        // Playback state determines which commands are available.
        menu.autoenablesItems = false
        append(rows, to: menu)
        return menu
    }

    private func makeCommandItem(_ command: MenuCommand) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: selector(for: command.id),
            keyEquivalent: command.keyEquivalent
        )
        item.target = self
        item.isEnabled = command.enabled
        item.state = command.checked ? .on : .off
        if let displayID = command.displayID {
            item.tag = Int(displayID)
        }
        if let symbolName = command.symbolName {
            // Decorative: the title already names the action for VoiceOver.
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        }
        return item
    }

    private func selector(for id: MenuCommandID) -> Selector {
        switch id {
        case .cancelDownload: #selector(cancelDownload)
        case .chooseFile: #selector(chooseFile(_:))
        case .pasteYouTube: #selector(pasteYouTube(_:))
        case .choosePhotos: #selector(choosePhotos(_:))
        case .shufflePhotos: #selector(shufflePhotos(_:))
        case .clearAll: #selector(clearAllWallpapers)
        case .clearDisplay: #selector(clearDisplayWallpaper(_:))
        case .toggleMute: #selector(toggleMute)
        case .togglePause: #selector(togglePause)
        case .togglePerDesktop: #selector(togglePerDesktop)
        }
    }

    private func optionalDisplayID(_ sender: NSMenuItem) -> CGDirectDisplayID? {
        sender.tag == 0 ? nil : CGDirectDisplayID(sender.tag)
    }

    // MARK: - Actions

    @objc private func chooseFile(_ sender: NSMenuItem) {
        wallpaperManager.selectFile(for: optionalDisplayID(sender))
    }

    @objc private func clearDisplayWallpaper(_ sender: NSMenuItem) {
        guard let displayID = optionalDisplayID(sender) else { return }
        wallpaperManager.clearWallpaper(for: displayID)
    }

    @objc private func clearAllWallpapers() {
        wallpaperManager.clearAllWallpapers()
    }

    @objc private func togglePause() {
        wallpaperManager.togglePause()
    }

    @objc private func toggleMute() {
        wallpaperManager.toggleMute()
    }

    @objc private func togglePerDesktop() {
        wallpaperManager.togglePerDesktop()
    }

    @objc private func pasteYouTube(_ sender: NSMenuItem) {
        guard let urlString = promptForYouTubeURL() else { return }
        wallpaperManager.setYouTubeWallpaper(urlString: urlString, for: optionalDisplayID(sender))
    }

    @objc private func cancelDownload() {
        wallpaperManager.cancelDownload()
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

    @objc private func choosePhotos(_ sender: NSMenuItem) {
        presentPhotosPicker(for: optionalDisplayID(sender))
    }

    /// Foreground the app, run the Photos picker, and assign the pick (nil display = all).
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

    @objc private func shufflePhotos(_ sender: NSMenuItem) {
        wallpaperManager.shuffleFromPhotos(for: optionalDisplayID(sender))
    }

}
