import AppKit
import SwiftUI

/// Bar colors for the providers after the brand-colored first one, as sRGB components.
enum TokenBarTone {
    static func neutrals(dark: Bool) -> [[Double]] {
        // A light theme draws the panel on white, where the dark-theme tones fade into the track.
        dark ? [[0.78, 0.73, 0.65], [0.66, 0.70, 0.76], [0.54, 0.62, 0.57]]
             : [[0.60, 0.52, 0.40], [0.42, 0.48, 0.58], [0.33, 0.45, 0.38]]
    }
}

struct TokenUsageOverview: View {
    @ObservedObject var snapshot: TokenMenuSnapshot
    @ObservedObject var connection: TokenPlanConnection
    let mark: NSImage?
    let heightLimit: CGFloat
    let cycle: () -> Void
    let refresh: () -> Void
    @State private var showsConnection = false
    @State private var apiKey = ""
    @AppStorage(TokenMenuDisplay.columnsKey) private var twoColumns = false
    private var counts: TokenUsageIndex.Counts { snapshot.counts ?? [:] }
    private var total: Int { counts.values.reduce(0, +) }
    @Environment(\.colorScheme) private var scheme
    private var tones: [Color] {
        [.yenBrand] + TokenBarTone.neutrals(dark: scheme == .dark).map { Color(red: $0[0], green: $0[1], blue: $0[2]) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let mark {
                    Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 15, height: 15)
                        .foregroundStyle(Color.yenBrand).accessibilityHidden(true)
                }
                Text("Token usage").font(.headline)
                Spacer()
                action(twoColumns ? "rectangle.split.1x2" : "rectangle.split.2x1",
                       twoColumns ? "Use one column" : "Use two columns") { twoColumns.toggle() }
                action("arrow.clockwise", "Refresh usage") { refresh(); connection.refresh(force: true) }
                action("link", "Manage plan connection") { showsConnection.toggle(); apiKey = "" }
            }
            Divider()
            ViewThatFits(in: .vertical) {
                bodyContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { bodyContent }.frame(height: max(120, heightLimit - 108))
            }.frame(maxHeight: max(120, heightLimit - 108))
            Divider()
            HStack {
                Text(coverage).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: cycle) {
                    Label(snapshot.display.rawValue, systemImage: "arrow.triangle.2.circlepath")
                }.buttonStyle(.borderless).font(.caption)
                    .help("Cycle the menu bar display").accessibilityLabel("Cycle menu bar display")
                    .accessibilityValue(snapshot.display.rawValue)
            }
        }.padding(14).frame(width: twoColumns ? 592 : 365)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.primary.opacity(0.14)))
            .task {
                while !Task.isCancelled {
                    connection.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsConnection { connectionForm }
            HStack(alignment: .firstTextBaseline) {
                Text("Today’s tokens").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.counts == nil ? "Reading…" : counts.isEmpty ? "Unavailable" : total.formatted())
                    .font(.title2.weight(.semibold)).monospacedDigit()

            }
            TimelineView(.periodic(from: .now, by: 30)) { clock in
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
                    ForEach(0..<(twoColumns ? 2 : 4), id: \.self) { row in
                        GridRow {
                            ForEach(0..<(twoColumns ? 2 : 1), id: \.self) { column in
                                let index = row * (twoColumns ? 2 : 1) + column
                                provider(TokenTool.allCases[index], color: tones[index], now: clock.date)
                            }
                        }
                    }
                }
            }
        }
    }

    private func provider(_ tool: TokenTool, color: Color, now: Date) -> some View {
        let count = counts[tool]
        let share = total > 0 ? Double(count ?? 0) / Double(total) : 0
        let meters = snapshot.meters(for: tool, connection: connection).filter { $0.isCurrent(at: now) }
        return VStack(alignment: .leading, spacing: 5) {
            Divider()
            HStack {
                Text(tool.rawValue).font(.headline)
                Spacer(minLength: 4)
                Text(count?.formatted() ?? (snapshot.counts == nil ? "Reading…" : "Unavailable")).monospacedDigit()
            }
            HStack(spacing: 7) {
                track(share, color: color)
                Text(count == nil || total == 0 ? "—" : share.formatted(.percent.precision(.fractionLength(0...1))) + " of today")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Share of counted tokens").accessibilityValue(count == nil || total == 0 ? "Unavailable" : share.formatted(.percent))
            if tool == .grok && !meters.contains(where: { $0.label.hasPrefix("Grok ") && !$0.label.hasPrefix("Grok Bot") }) {
                missingPool("Grok subscription", status: "No current reading")
            }
            ForEach(meters) { meter in
                HStack(spacing: 8) {
                    Text(meter.label).font(.caption).frame(width: 100, alignment: .leading)
                    track(meter.percent / 100, color: color.opacity(scheme == .dark ? 0.8 : 1))
                    Text((meter.percent / 100).formatted(.percent.precision(.fractionLength(0...1))))
                        .font(.caption.monospacedDigit()).frame(minWidth: 30, alignment: .trailing)
                }.padding(.leading, 8).accessibilityElement(children: .combine)
                    .help(meter.reset.map { "Plan usage · resets " + $0.formatted() } ?? "Plan usage")
            }
            if tool == .grok && !connection.connected && meters.contains(where: { snapshot.sharedPools.contains($0) }) {
                Text("Cursor plan readings via JPtheCat").font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
            }
            if tool == .grok {
                let status = connection.loading ? "Reading…" : connection.connected ? "No current reading" : "Not connected"
                if !meters.contains(where: { $0.label.hasPrefix("Cursor ") }) {
                    missingPool("Cursor billing cycle", status: status)
                }
                if !meters.contains(where: { $0.label == "Grok Bot weekly" }) {
                    missingPool("Grok Bot weekly", status: status)
                }
            }
            HStack(spacing: 10) {
                ForEach(links(tool), id: \.1) { title, address in
                    Link(destination: URL(string: address)!) {
                        Label(title, systemImage: "arrow.up.right.square")
                    }.font(.caption).help("Open " + title + " in your browser")
                }
            }.padding(.top, 1)
        }
    }

    private func missingPool(_ label: String, status: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(status)
        }.font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
            .accessibilityElement(children: .combine)
    }

    private var coverage: String {
        guard snapshot.counts != nil else { return "Reading local sources…" }
        return counts.count == 4 ? "4 local sources" : "Partial total · " + String(counts.count) + " of 4 sources"
    }

    private func track(_ fraction: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule().fill(color).frame(width: geometry.size.width * fraction)
            }
        }.frame(height: 5).accessibilityHidden(true)
    }

    private func action(_ icon: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: icon).frame(width: 22, height: 22) }
            .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cursor & Grok Bot plans").font(.headline)
            if connection.connected {
                Button("Disconnect", action: connection.disconnect)
            } else {
                Text("Connect a personal Cursor API key to read included plan usage. YEN saves it in your Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    SecureField("Cursor API key", text: $apiKey).accessibilityLabel("Cursor API key")
                    Button("Connect") { connection.connect(apiKey); apiKey = "" }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.loading)
                }
                Link("Get a Cursor API key ↗", destination: URL(string: "https://cursor.com/dashboard/api")!)
                    .font(.caption)
            }
            if connection.loading { Text("Reading Cursor plan…").font(.caption) }
            if let message = connection.message { Text(message).font(.caption) }
            Divider()
        }
    }

    private func links(_ tool: TokenTool) -> [(String, String)] {
        switch tool {
        case .claude: return [("Claude usage", "https://claude.ai/settings/usage")]
        case .codex: return [("Codex usage", "https://chatgpt.com/settings/usage?tab=overview")]
        case .grok: return [("Grok", "https://grok.com/?_s=usage"), ("Cursor", "https://cursor.com/dashboard/spending"),
                            ("Grok Bot", "https://grok.com/dashboard")]
        case .openCode:
            if let workspace = snapshot.workspace {
                let console = "https://opencode.ai/console/" + workspace
                return [("Zen billing", console + "/billing"), ("Go usage", console + "/go")]
            }
            return [("OpenCode console", "https://opencode.ai/console")]
        }
    }
}
