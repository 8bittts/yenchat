import AppKit
import SwiftUI

/// Bar colors for the providers after the brand-colored first one, as sRGB components.
enum TokenBarTone {
    static func neutrals(dark: Bool) -> [[Double]] {
        // A light theme draws the panel on white, where the dark-theme tones fade into the track.
        dark ? [[0.78, 0.73, 0.65], [0.66, 0.70, 0.76], [0.54, 0.62, 0.57]]
             : [[0.60, 0.52, 0.40], [0.42, 0.48, 0.58], [0.33, 0.45, 0.38]]
    }

    /// Hover color for a label that opens a dashboard: brand orange, darkened on a light panel
    /// so small text keeps 4.5:1. The system accent does not, and it changes with the user's choice.
    static func link(dark: Bool) -> [Double] { dark ? [1.0, 81.0 / 255.0, 0.0] : [0.70, 0.16, 0.0] }
}

struct TokenUsageOverview: View {
    @ObservedObject var snapshot: TokenMenuSnapshot
    @ObservedObject var connection: TokenPlanConnection
    let mark: NSImage?
    let heightLimit: CGFloat
    let cycle: () -> Void
    let refresh: () -> Void
    let loadHistory: () -> Void
    @State private var showsConnection = false
    @State private var showsAnalytics = false
    @State private var apiKey = ""
    @AppStorage(TokenMenuDisplay.columnsKey) private var twoColumns = false
    private var counts: TokenUsageIndex.Counts { snapshot.counts ?? [:] }
    private var total: Int { counts.values.reduce(0, +) }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tones: [Color] {
        [.yenBrand] + TokenBarTone.neutrals(dark: scheme == .dark).map { Color(red: $0[0], green: $0[1], blue: $0[2]) }
    }
    var body: some View {
        // The analytics face takes the overview's size, so the panel never resizes on a flip.
        card(overview).allowsHitTesting(!showsAnalytics).accessibilityHidden(showsAnalytics)
            .modifier(TokenCardFlip(progress: showsAnalytics ? 1 : 0, back: card(analytics.frame(maxHeight: .infinity, alignment: .top))
                .allowsHitTesting(showsAnalytics).accessibilityHidden(!showsAnalytics)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: showsAnalytics)
            .task {
                while !Task.isCancelled {
                    connection.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    private func card(_ content: some View) -> some View {
        content.padding(14).frame(width: twoColumns ? 592 : 365)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.primary.opacity(0.14)))
    }

    private func header(_ title: String, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 6) {
            if let mark {
                Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 15, height: 15)
                    .foregroundStyle(Color.yenBrand).accessibilityHidden(true)
            }
            Text(title).font(.headline)
            Spacer()
            actions()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Token usage") {
                action(twoColumns ? "rectangle.split.1x2" : "rectangle.split.2x1",
                       twoColumns ? "Use one column" : "Use two columns") { twoColumns.toggle() }
                action("arrow.clockwise", "Refresh usage") { refresh(); connection.refresh(force: true) }
                action("chart.bar.xaxis", "Show analytics") { showsAnalytics = true; loadHistory() }
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
        }
    }

    private static let windows = [7, 30, 90]
    private static let compact = IntegerFormatStyle<Int>.number.notation(.compactName).precision(.significantDigits(1...3))

    private var analytics: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Token analytics") {
                action("arrow.uturn.backward", "Show today’s usage") { showsAnalytics = false }
            }
            Divider()
            if let history = snapshot.history {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 12) { totals(history); trend(history) }
                    totals(history)
                    ScrollView { totals(history) }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading 90 days of local records…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Divider()
            Text("Tokens from local records, today included").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Today's live count plus the finished days before it. Nil for a source that cannot be read.
    private func sum(_ tool: TokenTool, days: Int, _ history: [TokenTool: [Int]]) -> Int? {
        history[tool].map { $0.suffix(days - 1).reduce(counts[tool] ?? 0, +) }
    }

    private func amount(_ value: Int?) -> some View {
        Text(value.map { $0.formatted(Self.compact) } ?? "—").monospacedDigit()
            .help(value.map { $0.formatted() + " tokens" } ?? "Unavailable")
    }

    private func totals(_ history: [TokenTool: [Int]]) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
            GridRow {
                Text("Provider").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.windows, id: \.self) { Text(String($0) + " days") }
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(TokenTool.allCases.enumerated()), id: \.offset) { index, tool in
                GridRow {
                    HStack(spacing: 6) {
                        Circle().fill(tones[index]).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(tool.rawValue)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Self.windows, id: \.self) { amount(sum(tool, days: $0, history)) }
                }
            }
            Divider()
            GridRow {
                Text("All providers").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Self.windows, id: \.self) { days in
                    amount(history.isEmpty ? nil : TokenTool.allCases.compactMap { sum($0, days: days, history) }.reduce(0, +))
                }
            }.fontWeight(.semibold)
        }
    }

    private func trend(_ history: [TokenTool: [Int]]) -> some View {
        let tones = tones
        let days = (0...TokenUsageIndex.historyDays).map { day in
            TokenTool.allCases.map { day == TokenUsageIndex.historyDays ? counts[$0] ?? 0 : history[$0]?[day] ?? 0 }
        }
        let peak = days.map { $0.reduce(0, +) }.max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let step = size.width / CGFloat(days.count)
                for (index, day) in days.enumerated() where peak > 0 {
                    var top = size.height
                    for (tool, value) in day.enumerated() where value > 0 {
                        let height = size.height * CGFloat(value) / CGFloat(peak)
                        top -= height
                        context.fill(Path(CGRect(x: CGFloat(index) * step, y: top, width: max(1, step - 1), height: height)),
                                     with: .color(tones[tool]))
                    }
                }
            }.frame(minHeight: 44, maxHeight: 120).accessibilityLabel("Daily tokens for the last 90 days")
                .accessibilityValue("Busiest day " + peak.formatted())
            HStack {
                Text("Daily, last 90 days")
                Spacer()
                Text("Busiest day " + peak.formatted(Self.compact))
            }.font(.caption).foregroundStyle(.secondary)
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
        let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0...1))
        let meters = snapshot.meters(for: tool, connection: connection).filter { $0.isCurrent(at: now) }
        return VStack(alignment: .leading, spacing: 5) {
            Divider()
            HStack {
                link(tool.rawValue, tool).font(.headline)
                Spacer(minLength: 4)
                Text(count?.formatted() ?? (snapshot.counts == nil ? "Reading…" : "Unavailable")).monospacedDigit()
            }
            HStack(spacing: 7) {
                track(share, color: color)
                // Reserve the widest caption so the four tracks end on one line.
                Text(0.999.formatted(percent) + " of today").hidden()
                    .overlay(alignment: .trailing) { Text(count == nil || total == 0 ? "—" : share.formatted(percent) + " of today") }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("Share of counted tokens").accessibilityValue(count == nil || total == 0 ? "Unavailable" : share.formatted(.percent))
            if tool == .grok && !meters.contains(where: { $0.label.hasPrefix("Grok ") && !$0.label.hasPrefix("Grok Bot") }) {
                missingPool("Grok subscription", status: "No current reading")
            }
            ForEach(meters) { meter in
                HStack(spacing: 8) {
                    link(meter.label, tool).font(.caption).lineLimit(1).frame(width: 116, alignment: .leading)
                    track(meter.percent / 100, color: color.opacity(scheme == .dark ? 0.8 : 1))
                    Text((meter.percent / 100).formatted(percent))
                        .font(.caption.monospacedDigit()).frame(minWidth: 30, alignment: .trailing)
                }.accessibilityElement(children: .combine)
                    .help(meter.reset.map { "Plan usage · resets " + $0.formatted() } ?? "Plan usage")
            }
            if tool == .grok && !connection.connected && meters.contains(where: { snapshot.sharedPools.contains($0) }) {
                Text("Cursor plan readings via JPtheCat").font(.caption2).foregroundStyle(.secondary)
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
        }
    }

    private func missingPool(_ label: String, status: String) -> some View {
        HStack {
            link(label, .grok)
            Spacer()
            Text(status)
        }.font(.caption).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }

    /// A provider name or pool label opens the dashboard that owns its numbers.
    private func link(_ title: String, _ tool: TokenTool) -> TokenLinkLabel {
        switch tool {
        case .claude: return TokenLinkLabel(title: title, site: "Claude usage", address: "https://claude.ai/settings/usage")
        case .codex: return TokenLinkLabel(title: title, site: "Codex usage", address: "https://chatgpt.com/settings/usage?tab=overview")
        case .grok where title.hasPrefix("Grok Bot"):
            return TokenLinkLabel(title: title, site: "the Grok Bot dashboard", address: "https://grok.com/dashboard")
        case .grok where title.hasPrefix("Cursor"):
            return TokenLinkLabel(title: title, site: "Cursor spending", address: "https://cursor.com/dashboard/spending")
        case .grok: return TokenLinkLabel(title: title, site: "Grok usage", address: "https://grok.com/?_s=usage")
        case .openCode:
            return TokenLinkLabel(title: title, site: "the OpenCode console",
                                  address: "https://opencode.ai/console" + (snapshot.workspace.map { "/" + $0 + "/billing" } ?? ""))
        }
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
}

/// Text that opens its dashboard. Hover tints it, so the panel needs no separate link row.
private struct TokenLinkLabel: View {
    let title: String
    let site: String
    let address: String
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let tone = TokenBarTone.link(dark: scheme == .dark)
        return Button {
            if let url = URL(string: address) { openURL(url) }
        } label: {
            Text(title).foregroundStyle(hovering ? AnyShapeStyle(Color(red: tone[0], green: tone[1], blue: tone[2])) : AnyShapeStyle(.foreground))
        }.buttonStyle(.plain).onHover { hovering = $0 }.pointerStyle(.link)
            .help("Open " + site + " in your browser").accessibilityAddTraits(.isLink)
    }
}

/// Turns the card over on its vertical axis and swaps the face at the half turn.
private struct TokenCardFlip<Back: View>: ViewModifier, Animatable {
    var progress: Double
    let back: Back
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    private static var perspective: Double { 0.3 }

    func body(content: Content) -> some View {
        content.opacity(progress < 0.5 ? 1 : 0)
            .overlay { back.opacity(progress < 0.5 ? 0 : 1) }
            // The second half turns in from the far side, so the card rests unrotated and
            // its controls take clicks; a face left at a half turn receives none.
            .rotation3DEffect(.degrees((progress < 0.5 ? progress : progress - 1) * 180), axis: (x: 0, y: 1, z: 0), perspective: Self.perspective)
            // Perspective enlarges the near edge by up to 1 / (1 - perspective / 2); shrinking by the
            // same share keeps the turning card inside its window, which would clip it.
            .scaleEffect(1 - Self.perspective / 2 * sin(progress * .pi))
    }
}
