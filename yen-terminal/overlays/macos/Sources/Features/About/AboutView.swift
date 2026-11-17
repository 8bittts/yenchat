import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let docsURL = URL(string: "https://yen.chat/docs")
    private let bitcoinEmailURL = URL(string: "https://btc.email")

    private var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    private var copyright: String? { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 96)
                .accessibilityLabel("YEN app icon")

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

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
