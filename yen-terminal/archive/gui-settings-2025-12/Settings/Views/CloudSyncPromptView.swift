import SwiftUI

/// Registration prompt shown when user saves settings but isn't logged in
/// Presented as a sheet (not modal) — matches macOS patterns
/// File location: settings-gui/Views/CloudSyncPromptView.swift
struct CloudSyncPromptView: View {
    @Binding var isPresented: Bool
    @AppStorage("hideCloudSyncPrompt") private var hidePrompt = false

    // YEN brand orange (matches UnifiedAboutView)
    private let brandOrange = Color(red: 1.0, green: 0.318, blue: 0.0)

    var body: some View {
        VStack(spacing: 20) {
            // Header icon
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundColor(brandOrange)

            // Title
            Text("Sync Your Settings")
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            Text("Sign up for a free YEN account to sync your terminal settings across all your Macs.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // Features list
            VStack(alignment: .leading, spacing: 8) {
                CloudSyncFeatureRow(icon: "paintbrush", text: "Sync appearance settings", brandColor: brandOrange)
                CloudSyncFeatureRow(icon: "brain", text: "Keep learned patterns", brandColor: brandOrange)
                CloudSyncFeatureRow(icon: "doc.text", text: "Custom knowledgebase", brandColor: brandOrange)
            }
            .padding(.vertical)

            // Buttons
            HStack(spacing: 12) {
                Button("Not Now") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Sign Up Free") {
                    NSWorkspace.shared.open(URL(string: "https://yen.chat/api/auth/login?provider=google&next=/settings")!)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .tint(brandOrange)
            }

            // Don't show again checkbox
            Toggle("Don't show this again", isOn: Binding(
                get: { hidePrompt },
                set: { newValue in
                    hidePrompt = newValue
                    if newValue {
                        isPresented = false
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 360)
    }
}

/// Feature row component for the cloud sync prompt
private struct CloudSyncFeatureRow: View {
    let icon: String
    let text: String
    let brandColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(brandColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

struct CloudSyncPromptView_Previews: PreviewProvider {
    static var previews: some View {
        CloudSyncPromptView(isPresented: .constant(true))
    }
}
