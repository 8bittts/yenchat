import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Colors") {
                ColorPicker("Background", selection: Binding(
                    get: { Color(hex: settings.background) ?? .black },
                    set: { settings.background = $0.toHex() }
                ))

                ColorPicker("Foreground", selection: Binding(
                    get: { Color(hex: settings.foreground) ?? .white },
                    set: { settings.foreground = $0.toHex() }
                ))
            }

            Section("Transparency") {
                VStack(alignment: .leading) {
                    Text("Opacity: \(Int(settings.backgroundOpacity * 100))%")
                    Slider(value: $settings.backgroundOpacity, in: 0...1)
                }

                Toggle("Background Blur", isOn: $settings.backgroundBlur)
                    .help("Enable background blur effect")
            }

            Section("Theme") {
                Picker("Window Theme", selection: $settings.windowTheme) {
                    Text("Auto").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Split View") {
                VStack(alignment: .leading) {
                    Text("Unfocused Split Opacity: \(Int(settings.unfocusedSplitOpacity * 100))%")
                    Slider(value: $settings.unfocusedSplitOpacity, in: 0...1)
                }
                .help("Opacity of unfocused split panes")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
