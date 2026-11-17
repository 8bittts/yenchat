import SwiftUI
import AppKit

struct AdvancedSettingsView: View {
    @ObservedObject var settings: SettingsModel
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Configuration File") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Config Path:")
                        .font(.headline)
                    Text(settings.configPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)

                    Button("Open Config File") {
                        openConfigFile()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Actions") {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Reload Configuration") {
                        reloadConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Reload config and apply changes to all windows")

                    Button("Reset to Defaults") {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .help("Reset all settings to default values")
                }
            }

            Section("About YEN Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Visual settings interface for YEN Terminal")
                        .font(.body)

                    Text("These settings are saved to your YEN configuration file and can be edited manually if needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Configuration Documentation", destination: URL(string: "https://yen.chat/docs/configuration")!)
                        .font(.body)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset to Defaults?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                reloadConfiguration()
            }
        } message: {
            Text("This will reset all settings to their default values. This cannot be undone.")
        }
    }

    private func openConfigFile() {
        let configPath = settings.configPath
            .replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)

        let configURL = URL(fileURLWithPath: configPath)

        NSWorkspace.shared.open(configURL)
    }

    private func reloadConfiguration() {
        // Save current settings
        try? settings.saveToConfig()

        // Reload configuration in Yen
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        delegate.reloadConfig(nil)
    }
}
