import SwiftUI

struct MacOSSettingsView: View {
    @ObservedObject var settings: SettingsModel
    @AppStorage("YENShowMenuBarIcon") private var showMenuBarIcon: Bool = true

    var body: some View {
        Form {
            // NOTE: App Icon section intentionally removed
            // YEN uses custom bundled icons, not YEN's macos-icon setting

            Section("Menu Bar") {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                    .help("Show YEN icon in the macOS menu bar for quick access")
                    .onChange(of: showMenuBarIcon) { newValue in
                        // StatusBarController listens to UserDefaults changes
                        // Trigger notification manually since it doesn't use KVO
                        NotificationCenter.default.post(
                            name: NSNotification.Name("YENMenuBarIconToggled"),
                            object: nil,
                            userInfo: ["visible": newValue]
                        )
                    }
            }

            Section("Display") {
                Picker("Window Colorspace", selection: $settings.windowColorspace) {
                    Text("sRGB").tag("srgb")
                    Text("Display P3").tag("display-p3")
                }
                .help("Color space for terminal rendering")

                Toggle("VSync", isOn: $settings.windowVSync)
                    .help("Synchronize rendering with display refresh rate")
            }

            Section("Window State") {
                Picker("Save Window State", selection: $settings.windowSaveState) {
                    Text("Default").tag("default")
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }
                .help("Save and restore window position and size")
            }

            Section("Quick Terminal") {
                Picker("Quick Terminal Position", selection: $settings.quickTerminalPosition) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                }
                .help("Position of quick terminal overlay")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
