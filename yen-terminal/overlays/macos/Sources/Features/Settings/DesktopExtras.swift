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
    private var menu: TokenUsageMenu?
    private var wallpaper: WallpaperControls?
    private let workspace = NSWorkspace.shared

    func restore() {
        setUsage(UserDefaults.standard.bool(forKey: Self.usageKey))
        setWallpaper(UserDefaults.standard.bool(forKey: Self.wallpaperKey))
    }

    func setUsage(_ enabled: Bool) {
        guard enabled != showsUsage else { return }
        showsUsage = enabled
        UserDefaults.standard.set(enabled, forKey: Self.usageKey)
        if enabled { menu = TokenUsageMenu() } else { menu?.stop(); menu = nil }
    }

    func setWallpaper(_ enabled: Bool) {
        guard showsWallpaper != enabled else { return }
        showsWallpaper = enabled
        UserDefaults.standard.set(enabled, forKey: Self.wallpaperKey)
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
            wallpaper = WallpaperControls()
        }
    }

    func openWallpaper(_ button: NSButton) { wallpaper?.open(from: button) }

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
            SettingsStudioLabel(title: "Show Token Usage", hint: "Experimental. Count local agent tokens in the menu bar.")
        }
        .accessibilityLabel("Show Token Usage")
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
                WallpaperMenuButton().fixedSize()
            }
        }
    }

    private struct WallpaperMenuButton: NSViewRepresentable {
        func makeNSView(context: Context) -> NSButton {
            let button = NSButton(title: "Wallpaper Controls…", target: context.coordinator, action: #selector(Coordinator.open(_:)))
            button.bezelStyle = .rounded
            return button
        }
        func updateNSView(_ view: NSButton, context: Context) {}
        func makeCoordinator() -> Coordinator { Coordinator() }
        @MainActor final class Coordinator: NSObject {
            @objc func open(_ sender: NSButton) { DesktopExtras.shared.openWallpaper(sender) }
        }
    }
}
