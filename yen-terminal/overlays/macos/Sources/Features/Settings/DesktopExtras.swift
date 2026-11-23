import AppKit
import SwiftUI

@MainActor
final class DesktopExtras: ObservableObject {
    static let shared = DesktopExtras()
    static let usageKey = "com.yenchat.yen.showTokenUsage"
    static let wallpaperKey = "com.yenchat.yen.movingWallpaper.enabled"
    @Published private(set) var showsUsage = false
    @Published private(set) var showsWallpaper = false
    @Published private(set) var wallpaperSuspended = false
    @Published private(set) var wallpaperState = WallpaperControlsState()
    private var menu: TokenUsageMenu?
    private var wallpaper: WallpaperControls?
    private let workspace = NSWorkspace.shared
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restore() {
        setUsage(defaults.bool(forKey: Self.usageKey))
        setWallpaper(defaults.bool(forKey: Self.wallpaperKey))
    }

    func setUsage(_ enabled: Bool) {
        guard enabled != showsUsage else { return }
        showsUsage = enabled
        defaults.set(enabled, forKey: Self.usageKey)
        if enabled { menu = TokenUsageMenu() } else { menu?.stop(); menu = nil }
    }

    func setWallpaper(_ enabled: Bool) {
        guard showsWallpaper != enabled else { return }
        showsWallpaper = enabled
        defaults.set(enabled, forKey: Self.wallpaperKey)
        if enabled {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspace.notificationCenter.addObserver(self, selector: #selector(appChanged(_:)), name: name, object: nil)
            }
            reconcileWallpaper()
        } else {
            stopWallpaper()
        }
    }

    @objc private func appChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.8bittts.movingpaper" else { return }
        reconcileWallpaper()
    }

    private func reconcileWallpaper() {
        guard showsWallpaper else { return }
        wallpaperSuspended = NSRunningApplication.runningApplications(withBundleIdentifier: "com.8bittts.movingpaper")
            .contains { !$0.isTerminated }
        if wallpaperSuspended {
            wallpaper?.stop()
            wallpaper = nil
        } else if wallpaper == nil {
            let controls = WallpaperControls(defaults: defaults)
            controls.onChange = { [weak self] in self?.refreshWallpaperState() }
            wallpaper = controls
            refreshWallpaperState()
        }
    }

    private func refreshWallpaperState() {
        guard let state = wallpaper?.state, state != wallpaperState else { return }
        wallpaperState = state
    }

    /// Runs one Settings wallpaper button against the live engine.
    func wallpaperAction(_ action: (WallpaperControls) -> Void) {
        if let wallpaper { action(wallpaper) }
    }

    /// A click on a plan limit alert opens the token panel.
    func showUsagePanel() { menu?.showPanel() }

    private func stopWallpaper() {
        workspace.notificationCenter.removeObserver(self)
        wallpaper?.stop()
        wallpaper = nil
        wallpaperSuspended = false
    }

    func stop() {
        menu?.stop()
        menu = nil
        stopWallpaper()
    }
}

struct TokenUsagePreference: View {
    @ObservedObject private var extras = DesktopExtras.shared
    var body: some View {
        Toggle(isOn: Binding(get: { extras.showsUsage }, set: extras.setUsage)) {
            SettingsStudioLabel(title: "Show Token Usage", hint: "Count local agent tokens in the menu bar.")
        }
        .accessibilityLabel("Show Token Usage")
        if extras.showsUsage {
            ClaudePlanLimitsPreference()
            LimitAlertsPreference()
        }
    }
}

/// Alerts at 80% and 95% of a plan window, on the Usage Limits notification stream.
struct LimitAlertsPreference: View {
    @AppStorage(TokenLimitAlerts.enabledKey) private var enabled = true
    var body: some View {
        Toggle(isOn: $enabled) {
            SettingsStudioLabel(title: "Limit Alerts",
                                hint: "Notify at 80% and 95% of a plan limit. Notifications → Usage Limits sets the sound.")
        }
        .accessibilityLabel("Limit Alerts")
    }
}

/// Claude Code shows its live plan limits only to its statusline command, so this adds or
/// removes YEN's marked block in that script (`TokenClaudeLimits`). The script is the state.
struct ClaudePlanLimitsPreference: View {
    private let home = FileManager.default.homeDirectoryForCurrentUser
    @State private var state = TokenClaudeLimits.State.unavailable
    @State private var failed = false

    var body: some View {
        Toggle(isOn: Binding(get: { state == .active }, set: change)) {
            SettingsStudioLabel(title: "Claude Plan Limits", hint: hint)
        }
        .disabled(state == .unavailable)
        .accessibilityLabel("Claude Plan Limits")
        .onAppear { state = TokenClaudeLimits.state(home: home) }
    }

    private var hint: String {
        if failed { return "YEN could not change your Claude Code statusline script." }
        if state == .unavailable {
            return "Needs a Claude Code statusline script that reads its input, such as input=$(cat)."
        }
        return "Adds a marked block to your Claude Code statusline script that saves Claude’s live limits for this menu."
    }

    private func change(_ on: Bool) {
        do {
            if on { try TokenClaudeLimits.install(home: home) } else { try TokenClaudeLimits.uninstall(home: home) }
            failed = false
        } catch { failed = true }
        state = TokenClaudeLimits.state(home: home)
    }
}

struct MovingWallpaperPreference: View {
    @ObservedObject private var extras = DesktopExtras.shared
    var body: some View {
        Toggle(isOn: Binding(get: { extras.showsWallpaper }, set: extras.setWallpaper)) {
            SettingsStudioLabel(title: "Moving Wallpaper", hint: "Play a video or GIF behind your desktop icons.")
        }
        .accessibilityLabel("Moving Wallpaper")
        if extras.showsWallpaper {
            if extras.wallpaperSuspended {
                Text("Quit standalone MovingPaper to use YEN’s wallpaper controls.").foregroundStyle(.secondary)
            } else {
                WallpaperControlRows(state: extras.wallpaperState, run: extras.wallpaperAction)
            }
        }
    }
}

/// The wallpaper commands as buttons, shown while Moving Wallpaper is on.
private struct WallpaperControlRows: View {
    let state: WallpaperControlsState
    let run: ((WallpaperControls) -> Void) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: SettingsSpacing.controlSpacing),
        GridItem(.flexible(), spacing: SettingsSpacing.controlSpacing),
    ]

    var body: some View {
        if state.isDownloading {
            LabeledContent("Downloading…") {
                Button("Cancel") { run { $0.cancelDownload() } }
            }
        } else if let fileName = state.fileName {
            LabeledContent("Showing") {
                Text(fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }

        LazyVGrid(columns: columns, spacing: SettingsSpacing.controlSpacing) {
            command("Demo", symbol: "sparkles", help: "Play a random sample video from yen.chat.") { $0.playDemo() }
            command("Choose File…", symbol: "folder", help: "Choose a video or GIF on this Mac.") { $0.chooseFile() }
            command("YouTube URL…", symbol: "link", help: "Paste a YouTube link to download and play.") { $0.pasteYouTube() }
            command("From Photos…", symbol: "photo.on.rectangle", help: "Choose a video from Photos.") { $0.choosePhotos() }
            command("Shuffle Photos", symbol: "shuffle", help: "Play a random video from Photos.") { $0.shufflePhotos() }
            command("Remove", symbol: "trash", help: removeHelp) { $0.remove() }
                .disabled(state.fileName == nil)
            command(state.isPaused ? "Resume" : "Pause",
                    symbol: state.isPaused ? "play.fill" : "pause.fill",
                    help: "Pause or resume playback.") { $0.togglePause() }
                .disabled(!state.hasAnyWallpaper)
            command(state.isMuted ? "Sound On" : "Sound Off",
                    symbol: state.isMuted ? "speaker.wave.2" : "speaker.slash",
                    help: "Turn the wallpaper’s sound on or off.") { $0.toggleMute() }
        }

        Toggle(isOn: Binding(get: { state.perDesktop }, set: { _ in run { $0.togglePerDesktop() } })) {
            SettingsStudioLabel(title: "Wallpaper per Desktop",
                                hint: "Each desktop keeps its own wallpaper. The buttons change the desktop you are on.")
        }
        .accessibilityLabel("Wallpaper per Desktop")
    }

    private var removeHelp: String {
        state.perDesktop ? "Remove the wallpaper from the desktop you are on." : "Remove the moving wallpaper."
    }

    private func command(
        _ title: String,
        symbol: String,
        help: String,
        action: @escaping (WallpaperControls) -> Void
    ) -> some View {
        Button { run(action) } label: {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .help(help)
    }
}
