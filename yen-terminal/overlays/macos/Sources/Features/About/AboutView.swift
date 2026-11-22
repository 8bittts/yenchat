import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let docsURL = URL(string: "https://yen.chat/#guide")
    private let bitcoinEmailURL = URL(string: "https://btc.email")

    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    private var copyright: String? { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            AboutMonitorIcon()

            VStack(alignment: .center, spacing: 6) {
                Text("YEN")
                    .font(.title2.weight(.semibold))

                Text("Fast, native, feature-rich terminal emulator.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 8) {
                if let version {
                    Text("v\(version)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let url = docsURL {
                    Button("Docs") {
                        openURL(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let url = bitcoinEmailURL {
                    Button("Bitcoin") {
                        openURL(url)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let copy = self.copyright {
                Text(copy)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .frame(minWidth: 240)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
    }
}

private struct AboutMonitorIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var icon: some View {
        Image("AppIconImage")
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    var body: some View {
        icon
            .overlay {
                // Bloom only the bright phosphor already present in the icon.
                let bloom = icon.blur(radius: 3).blendMode(.screen)
                if reduceMotion || activeState == .inactive {
                    bloom.opacity(0.30)
                } else {
                    PulsingPhosphor(content: bloom)
                }
            }
            .compositingGroup()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: SettingsCornerRadius.prominent, style: .continuous))
            .shadow(color: .green.opacity(0.16), radius: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("YEN app icon")
            .accessibilityAddTraits(.isImage)
    }

    private struct PulsingPhosphor<Content: View>: View {
        let content: Content
        @State private var bright = false

        var body: some View {
            content
                .opacity(bright ? 0.58 : 0.12)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        bright = true
                    }
                }
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
