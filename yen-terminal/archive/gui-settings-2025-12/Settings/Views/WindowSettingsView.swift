import SwiftUI

struct WindowSettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Window Size (in cells)") {
                Stepper(value: $settings.windowWidth, in: 20...300) {
                    Text("Width: \(settings.windowWidth) cells")
                }

                Stepper(value: $settings.windowHeight, in: 10...100) {
                    Text("Height: \(settings.windowHeight) cells")
                }
            }

            Section("Window Padding") {
                Stepper(value: $settings.windowPaddingX, in: 0...50) {
                    Text("Horizontal Padding: \(settings.windowPaddingX)px")
                }

                Stepper(value: $settings.windowPaddingY, in: 0...50) {
                    Text("Vertical Padding: \(settings.windowPaddingY)px")
                }

                Toggle("Balance Padding", isOn: $settings.windowPaddingBalance)
                    .help("Automatically balance padding for centering")
            }

            Section("Window Decoration") {
                Toggle("Show Window Decorations", isOn: $settings.windowDecoration)
                    .help("Enable native window titlebar and controls")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
