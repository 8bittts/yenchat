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
    let mark: NSImage?
    let heightLimit: CGFloat
    let cycle: () -> Void
    let refresh: () -> Void
    let loadHistory: () -> Void
    @State private var showsAnalytics = false
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
            Text(title).font(YENTypography.headline)
            Spacer()
            actions()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Token usage") {
                action("menubar.rectangle", "Menu bar: " + snapshot.display.rawValue + ". Click for the next view.", perform: cycle)
                    .accessibilityLabel("Menu bar display").accessibilityValue(snapshot.display.rawValue)
                action(twoColumns ? "rectangle.split.1x2" : "rectangle.split.2x1",
                       twoColumns ? "Use one column" : "Use two columns") { twoColumns.toggle() }
                action("arrow.clockwise", "Refresh usage", perform: refresh)
                action("chart.bar.xaxis", "Show analytics") { showsAnalytics = true; loadHistory() }
            }
            Divider()
            ViewThatFits(in: .vertical) {
                bodyContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { bodyContent }.frame(height: max(120, heightLimit - 108))
            }.frame(maxHeight: max(120, heightLimit - 108))
            Divider()
            Text(coverage).font(YENTypography.caption).foregroundStyle(.secondary)
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
                // The chart takes every point the totals leave, so the face has no empty band;
                // a short overview gets a thinner chart without its caption.
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        totals(history); trend(history, caption: true)
                        if let rhythm = snapshot.rhythm, rhythm.count == 168 { TokenRhythmChart(bins: rhythm) }
                    }
                    VStack(alignment: .leading, spacing: 12) { totals(history); trend(history, caption: true) }
                    VStack(alignment: .leading, spacing: 12) { totals(history); trend(history, caption: false) }
                    VStack(spacing: 0) { totals(history); Spacer(minLength: 0) }
                    ScrollView { totals(history) }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading 90 days of local records…").font(YENTypography.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider()
            Text("Tokens from local records, today included").font(YENTypography.caption).foregroundStyle(.secondary)
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
            }.font(YENTypography.caption).foregroundStyle(.secondary)
            ForEach(Array(TokenTool.allCases.enumerated().filter { _, tool in
                (counts[tool] ?? 0) > 0 || history[tool]?.contains(where: { $0 > 0 }) == true
            }), id: \.element) { index, tool in
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

    private func trend(_ history: [TokenTool: [Int]], caption: Bool) -> some View {
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
            }.frame(minHeight: caption ? 44 : 16, maxHeight: .infinity).accessibilityLabel("Daily tokens for the last 90 days")
                .accessibilityValue("Busiest day " + peak.formatted())
            if caption {
                HStack {
                    Text("Daily, last 90 days")
                    Spacer()
                    Text("Busiest day " + peak.formatted(Self.compact))
                }.font(YENTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today’s tokens").font(YENTypography.secondary)
                    Text("Includes cached tokens").font(YENTypography.caption)
                }.foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.counts == nil ? "Reading…" : counts.isEmpty ? "Unavailable" : total.formatted())
                    .font(YENTypography.title.weight(.semibold)).monospacedDigit()

            }
            TimelineView(.periodic(from: .now, by: 30)) { clock in
                let active = TokenTool.allCases.enumerated().filter { _, tool in
                    tool.hasMenuActivity(tokens: counts[tool], meters: snapshot.plans[tool] ?? [], at: clock.date)
                }
                let columns = twoColumns ? 2 : 1
                if active.isEmpty, snapshot.counts != nil {
                    Text(counts.isEmpty ? "Usage unavailable" : "No recorded activity")
                        .font(YENTypography.caption).foregroundStyle(.secondary)
                }
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 12) {
                    ForEach(Array(stride(from: 0, to: active.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(Array(active[start..<min(start + columns, active.count)]), id: \.element) { index, tool in
                                provider(tool, color: tones[index], now: clock.date)
                            }
                        }
                    }
                }
            }
            folders
        }
    }

    static let folderLimit = 5

    /// Today's busiest working folders, all tools together, largest first.
    static func topFolders(_ projects: [String: TokenUsageIndex.Counts]) -> [(path: String, tokens: Int)] {
        projects.map { ($0.key, $0.value.values.reduce(0, +)) }.filter { $0.1 > 0 }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }.prefix(folderLimit).map { (path: $0.0, tokens: $0.1) }
    }

    @ViewBuilder private var folders: some View {
        let top = Self.topFolders(snapshot.projects)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Text("Top folders today").font(YENTypography.secondary).foregroundStyle(.secondary)
                ForEach(top, id: \.path) { folder in
                    HStack {
                        Text((folder.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(folder.tokens.formatted(Self.compact)).monospacedDigit()
                    }
                    .help((folder.path as NSString).abbreviatingWithTildeInPath + " · " + folder.tokens.formatted() + " tokens")
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func provider(_ tool: TokenTool, color: Color, now: Date) -> some View {
        let count = counts[tool]
        let percent = FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength(0...1))
        let meters = tool.menuMeters(snapshot.plans[tool] ?? [], at: now)
        return VStack(alignment: .leading, spacing: 5) {
            Divider()
            HStack {
                link(tool.rawValue, tool).font(YENTypography.headline)
                Spacer(minLength: 4)
                Text(count?.formatted() ?? (snapshot.counts == nil ? "Reading…" : "Unavailable")).monospacedDigit()
            }
            ForEach(meters) { meter in
                HStack(spacing: 8) {
                    // Each label takes the width of the provider's longest one, so its bars start
                    // together just after the words.
                    ZStack(alignment: .leading) {
                        ForEach(meters) { Text($0.menuLabel).hidden() }
                        link(meter.menuLabel, tool)
                    }.font(YENTypography.caption).lineLimit(1).fixedSize()
                    track(meter.percent / 100, color: color.opacity(scheme == .dark ? 0.8 : 1))
                    Text((meter.percent / 100).formatted(percent))
                        .font(YENTypography.caption.monospacedDigit()).frame(minWidth: 30, alignment: .trailing)
                }.accessibilityElement(children: .combine)
                    .help(meter.reset.map { "Plan usage · resets " + $0.formatted() } ?? "Plan usage")
            }
        }
    }

    /// A provider name or pool label opens the dashboard that owns its numbers.
    private func link(_ title: String, _ tool: TokenTool) -> TokenLinkLabel {
        switch tool {
        case .claude: return TokenLinkLabel(title: title, site: "Claude usage", address: "https://claude.ai/settings/usage")
        case .codex: return TokenLinkLabel(title: title, site: "Codex usage", address: "https://chatgpt.com/settings/usage?tab=overview")
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

/// Tokens by weekday and hour over the analytics window: one row per weekday, from the calendar's
/// first weekday, and one column per hour. A darker cell used more tokens.
struct TokenRhythmChart: View {
    let bins: [Int]
    /// One weekday row: a 10-point cell and a 1-point gap, tall enough for its caption label.
    static let rowHeight: CGFloat = 11

    /// Weekday rows in display order, as `Calendar` weekdays (1 is Sunday).
    static func weekdays(_ calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The busiest weekday and hour, or nil when no tokens were counted.
    static func busiest(_ bins: [Int]) -> (weekday: Int, hour: Int, tokens: Int)? {
        guard let peak = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[peak] > 0 else { return nil }
        return (peak / 24 + 1, peak % 24, bins[peak])
    }

    static func label(weekday: Int, hour: Int, _ calendar: Calendar = .current) -> String {
        let day = calendar.shortWeekdaySymbols[weekday - 1]
        let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()).map {
            $0.formatted(.dateTime.hour())
        } ?? String(hour)
        return day + " " + time
    }

    var body: some View {
        let peak = bins.max() ?? 0
        let rows = Self.weekdays()
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let busiest = Self.busiest(bins)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, weekday in
                        Text(symbols[weekday - 1]).frame(height: Self.rowHeight)
                    }
                }.font(YENTypography.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                Canvas { context, size in
                    let cell = CGSize(width: size.width / 24, height: size.height / 7)
                    for (row, weekday) in rows.enumerated() {
                        for hour in 0..<24 {
                            let value = bins[(weekday - 1) * 24 + hour]
                            let rect = CGRect(x: CGFloat(hour) * cell.width, y: CGFloat(row) * cell.height,
                                              width: max(1, cell.width - 1), height: max(1, cell.height - 1))
                            let shade = peak > 0 && value > 0 ? 0.18 + 0.82 * Double(value) / Double(peak) : 0
                            context.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                         with: .color(shade > 0 ? Color.yenBrand.opacity(shade) : Color.primary.opacity(0.07)))
                        }
                    }
                }.frame(height: Self.rowHeight * 7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tokens by weekday and hour for the last 90 days")
            .accessibilityValue(busiest.map { "Busiest " + Self.label(weekday: $0.weekday, hour: $0.hour) } ?? "No usage")
            HStack {
                Text("By hour, last 90 days")
                Spacer()
                if let busiest {
                    Text("Busiest " + Self.label(weekday: busiest.weekday, hour: busiest.hour))
                        .help(busiest.tokens.formatted() + " tokens")
                }
            }.font(YENTypography.caption).foregroundStyle(.secondary)
        }
    }
}
