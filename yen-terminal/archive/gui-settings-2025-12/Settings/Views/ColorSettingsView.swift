import SwiftUI

struct ColorSettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section("Cursor") {
                ColorPicker("Cursor Color", selection: Binding(
                    get: { Color(hex: settings.cursorColor) ?? Color(hex: "#ff5100")! },
                    set: { settings.cursorColor = $0.toHex() }
                ))

                VStack(alignment: .leading) {
                    Text("Cursor Opacity: \(Int(settings.cursorOpacity * 100))%")
                    Slider(value: $settings.cursorOpacity, in: 0...1)
                }

                ColorPicker("Cursor Text", selection: Binding(
                    get: { Color(hex: settings.cursorText) ?? .white },
                    set: { settings.cursorText = $0.toHex() }
                ))

                Picker("Cursor Style", selection: $settings.cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
            }

            Section("Selection") {
                ColorPicker("Selection Background", selection: Binding(
                    get: { Color(hex: settings.selectionBackground) ?? Color(hex: "#ff5100")! },
                    set: { settings.selectionBackground = $0.toHex() }
                ))

                ColorPicker("Selection Foreground", selection: Binding(
                    get: { Color(hex: settings.selectionForeground) ?? .white },
                    set: { settings.selectionForeground = $0.toHex() }
                ))
            }

            Section("Standard Colors (0-7)") {
                ForEach(0..<8, id: \.self) { index in
                    ColorPicker(colorName(for: index), selection: Binding(
                        get: { Color(hex: settings.palette[index]) ?? .black },
                        set: { settings.palette[index] = $0.toHex() }
                    ))
                }
            }

            Section("Bright Colors (8-15)") {
                ForEach(8..<16, id: \.self) { index in
                    ColorPicker(colorName(for: index), selection: Binding(
                        get: { Color(hex: settings.palette[index]) ?? .black },
                        set: { settings.palette[index] = $0.toHex() }
                    ))
                }
            }

            Section("Extended Colors (16-21) - YEN Brand Orange Spectrum") {
                ForEach(0..<6, id: \.self) { index in
                    ColorPicker("Orange \(index + 1)", selection: Binding(
                        get: { Color(hex: settings.extendedPalette[index]) ?? Color(hex: "#ff5100")! },
                        set: { settings.extendedPalette[index] = $0.toHex() }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func colorName(for index: Int) -> String {
        switch index {
        case 0: return "Black"
        case 1: return "Red"
        case 2: return "Green"
        case 3: return "Yellow"
        case 4: return "Blue"
        case 5: return "Magenta"
        case 6: return "Cyan"
        case 7: return "White"
        case 8: return "Bright Black"
        case 9: return "Bright Red"
        case 10: return "Bright Green"
        case 11: return "Bright Yellow"
        case 12: return "Bright Blue"
        case 13: return "Bright Magenta"
        case 14: return "Bright Cyan"
        case 15: return "Bright White"
        default: return "Color \(index)"
        }
    }
}
