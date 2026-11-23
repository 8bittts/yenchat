#if os(macOS)
import SwiftUI

/// First-launch onboarding view guiding users through the three permissions
/// required for speech-to-text dictation.
struct OnboardingPanel: View {
    @ObservedObject var controller: OnboardingController

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // App icon + title
                VStack(spacing: 8) {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .accessibilityLabel("YEN app icon")
                    }
                    Text("Welcome to YEN")
                        .font(YENTypography.title.weight(.semibold))
                        .fontWeight(.bold)
                    Text("YEN needs three permissions for speech-to-text dictation.")
                        .font(YENTypography.secondary)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                // Permission rows
                VStack(spacing: 0) {
                    PermissionRow(
                        granted: controller.accessibilityGranted,
                        name: "Accessibility",
                        description: "Required for the Option + Space global hotkey",
                        actionHint: "Requests Accessibility trust and opens Accessibility settings",
                        action: { controller.openSettings(for: .accessibility) }
                    )
                    Divider().padding(.leading, 44)
                    PermissionRow(
                        granted: controller.microphoneGranted,
                        name: "Microphone",
                        description: "Required to capture speech audio",
                        actionHint: "Requests Microphone permission, or opens Microphone settings if already denied",
                        action: { controller.openSettings(for: .microphone) }
                    )
                    Divider().padding(.leading, 44)
                    PermissionRow(
                        granted: controller.speechRecognitionGranted,
                        name: "Speech Recognition",
                        description: "Required to convert speech to text",
                        actionHint: "Requests Speech Recognition permission, or opens Speech Recognition settings if already denied",
                        action: { controller.openSettings(for: .speechRecognition) }
                    )
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 24)

                Text("Click Grant for each missing permission. If macOS can prompt directly, YEN requests it first; otherwise YEN opens the exact Privacy pane.")
                    .font(YENTypography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 24)

                Spacer()

                // Footer
                VStack(spacing: 12) {
                    Text("Option + Space to dictate anywhere")
                        .font(YENTypography.caption)
                        .foregroundColor(.secondary)

                    Button(action: { controller.dismiss(markComplete: controller.allGranted) }) {
                        Text(controller.allGranted ? "Get Started" : "Skip for Now")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 480, height: 420)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
    }
}

/// A single permission row with status indicator, description, and grant button.
private struct PermissionRow: View {
    let granted: Bool
    let name: String
    let description: String
    let actionHint: String
    let action: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var statusColor: Color {
        if differentiateWithoutColor {
            return Color(NSColor.labelColor)
        }
        return granted ? Color(NSColor.systemGreen) : Color(NSColor.systemRed)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(statusColor)
                .font(YENTypography.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(YENTypography.body.weight(.medium))
                Text(description)
                    .font(YENTypography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !granted {
                Button("Grant") {
                    action()
                }
                .controlSize(.small)
                .accessibilityHint(actionHint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(granted ? "Granted" : "Not granted"). \(description)")
    }
}

#endif // os(macOS)
