import SwiftUI

struct FontSettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Font Family") {
                TextField("Font Family", text: $settings.fontFamily)
                    .help("Leave empty for system default")

                TextField("Bold Font", text: $settings.fontFamilyBold)
                    .help("Optional: Override bold font")

                TextField("Italic Font", text: $settings.fontFamilyItalic)
                    .help("Optional: Override italic font")
            }

            Section("Font Size") {
                Stepper(value: $settings.fontSize, in: 6...72) {
                    Text("Font Size: \(settings.fontSize)")
                }
            }

            Section("Font Style") {
                Toggle("Font Thicken (macOS)", isOn: $settings.fontThicken)
                    .help("Make fonts appear bolder on macOS")

                Picker("Synthetic Style", selection: $settings.fontSyntheticStyle) {
                    Text("Bold + Italic").tag("bold-italic")
                    Text("Bold").tag("bold")
                    Text("Italic").tag("italic")
                    Text("None").tag("none")
                }
                .help("Allow synthetic font styles when specific font variants aren't available")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
