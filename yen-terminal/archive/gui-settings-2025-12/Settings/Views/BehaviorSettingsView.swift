import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Mouse & Keyboard") {
                Toggle("Focus Follows Mouse", isOn: $settings.focusFollowsMouse)
                    .help("Automatically focus terminal when mouse enters")

                Toggle("Copy on Select", isOn: $settings.copyOnSelect)
                    .help("Automatically copy selected text to clipboard")

                Toggle("Hide Mouse While Typing", isOn: $settings.mouseHideWhileTyping)
                    .help("Hide mouse cursor when typing")
            }

            Section("Bell Features") {
                TextField("Bell Features", text: $settings.bellFeatures)
                    .help("Comma-separated list: system, audio, attention, title")

                Text("Options: system, audio, attention, title")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
