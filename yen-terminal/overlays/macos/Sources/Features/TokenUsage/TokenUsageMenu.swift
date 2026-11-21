import AppKit
import SwiftUI

@MainActor
final class TokenUsageMenu: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let snapshot = TokenMenuSnapshot()
    private let index: TokenUsageIndex
    private var watcher: TokenSourceWatcher?
    private var changes: [TokenTool: Set<URL>] = [:]
    private var worker: Task<TokenUsageIndex.Counts?, Never>?
    private var pending = Set<TokenTool>()
    private var delay: Task<Void, Never>?
    private var active = true
    private var displayedDay = Calendar.current.startOfDay(for: Date())

    override init() {
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yenchat.yen")
            .appendingPathComponent("TokenUsage")
        index = TokenUsageIndex(home: fm.homeDirectoryForCurrentUser, directory: cache)
        super.init()
        let button = item.button
        let image = Bundle.main.url(forResource: "YENMenuMark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        image?.size = .init(width: 16, height: 16)
        image?.isTemplate = true
        button?.image = image
        button?.imagePosition = .imageLeading
        button?.target = self
        button?.action = #selector(toggle)
        popover.delegate = self
        popover.behavior = .transient
        updateTitle()
        watcher = TokenSourceWatcher(home: index.home) { [weak self] tool, paths in
            guard let self else { return }
            if let paths, !self.pending.contains(tool) || self.changes[tool] != nil {
                self.changes[tool, default: []].formUnion(paths)
            } else { self.changes[tool] = nil }
            self.schedule([tool])
        }
        for name in [Notification.Name.NSCalendarDayChanged, NSNotification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshAll),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        refreshAll()
    }

    func stop() {
        active = false
        watcher?.stop()
        watcher = nil
        worker?.cancel()
        delay?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        popover.close()
        popover.contentViewController = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        popover.appearance = NSApp.keyWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        popover.contentViewController = NSHostingController(rootView: TokenUsageOverview(snapshot: snapshot, mark: item.button?.image))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        refreshAll()
    }

    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil }

    @objc private func refreshAll() {
        let day = Calendar.current.startOfDay(for: Date())
        if day != displayedDay {
            displayedDay = day
            snapshot.counts = nil
            updateTitle()
        }
        changes.removeAll()
        pending.formUnion(TokenTool.allCases)
        start()
    }

    private func schedule(_ tools: Set<TokenTool>) {
        guard active else { return }
        pending.formUnion(tools)
        guard delay == nil else { return }
        delay = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self else { return }
            self.delay = nil
            self.start()
        }
    }

    private func start() {
        guard active, worker == nil, !pending.isEmpty else { return }
        let paths = changes
        changes.removeAll()
        let tools = pending
        let day = displayedDay
        pending.removeAll()
        let task = Task.detached(priority: .utility) { [index] in try? index.read(tools: tools, changes: paths) }
        worker = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.active else { return }
            self.worker = nil
            if day == self.displayedDay {
                var counts = self.snapshot.counts ?? [:]
                for tool in tools { counts[tool] = result?[tool] }
                self.snapshot.counts = counts
                self.updateTitle()
            }
            if !self.pending.isEmpty && self.delay == nil { self.schedule([]) }
        }
    }

    private func updateTitle() {
        let counts = snapshot.counts
        let sum = counts?.values.reduce(0, +) ?? 0
        let value = counts == nil ? "…" : counts?.isEmpty == true ? "—" : sum.formatted(.number.notation(.compactName))
        let partial = (1..<TokenTool.allCases.count).contains(counts?.count ?? 0)
        item.button?.title = " " + value + (partial ? "*" : "")
        let title = counts == nil ? "Reading local token usage" : "Token usage today: \(sum.formatted()) from \(counts?.count ?? 0) of 4 sources"
        item.button?.toolTip = title
        item.button?.setAccessibilityLabel(title)
    }
}

@MainActor
private final class TokenMenuSnapshot: ObservableObject {
    @Published var counts: TokenUsageIndex.Counts?
}

private struct TokenUsageOverview: View {
    @ObservedObject var snapshot: TokenMenuSnapshot
    let mark: NSImage?
    @State private var expanded: TokenTool?
    private let tones: [Color] = [.yenBrand, Color(red: 0.78, green: 0.73, blue: 0.65),
                                   Color(red: 0.66, green: 0.70, blue: 0.76), Color(red: 0.54, green: 0.62, blue: 0.57)]

    var body: some View {
        let counts = snapshot.counts ?? [:]
        let total = counts.values.reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let mark {
                    Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 15, height: 15)
                        .foregroundStyle(Color.yenBrand).accessibilityHidden(true)
                }
                Text("Token usage").font(.headline)
                Spacer()
                Text("Today").foregroundStyle(.secondary)
            }
            Divider()
            Text(counts.count == 4 ? "All providers" : "Counted tokens").foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.counts == nil ? "…" : counts.isEmpty ? "—" : total.formatted(.number.notation(.compactName)))
                    .font(.largeTitle.weight(.medium)).monospacedDigit()
                Text("tokens").foregroundStyle(.secondary)
            }
            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(TokenTool.allCases.enumerated()), id: \.offset) { index, tool in
                            tones[index].frame(width: geometry.size.width * CGFloat(counts[tool] ?? 0) / CGFloat(total))
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 3))
                }.frame(height: 8).accessibilityHidden(true)
            }
            HStack {
                Text("Provider")
                Spacer()
                Text("Tokens")
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(Array(TokenTool.allCases.enumerated()), id: \.offset) { index, tool in
                Divider()
                DisclosureGroup(isExpanded: Binding(get: { expanded == tool }, set: { expanded = $0 ? tool : nil })) {
                    Text(detail(for: counts[tool], total: total)).font(.caption)
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Circle().fill(tones[index]).frame(width: 7, height: 7)
                        Text(tool.rawValue)
                        Spacer()
                        Text(counts[tool]?.formatted(.number.notation(.compactName)) ?? (snapshot.counts == nil ? "Reading…" : "Unavailable"))
                            .monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
            }
            Divider()
            Text(snapshot.counts == nil ? "Reading local sources…" : counts.isEmpty ? "No readable local sources" :
                    counts.count == 4 ? "4 local sources" : "Partial total · \(counts.count) of 4 local sources")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 320).background(Color(nsColor: .windowBackgroundColor))
    }

    private func detail(for count: Int?, total: Int) -> String {
        guard let count else { return snapshot.counts == nil ? "Reading local source…" : "No readable local source." }
        guard count > 0, total > 0 else { return "Local source available. No recorded tokens today." }
        let share = (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0...1)))
        return "\(count.formatted()) tokens · \(share) of counted usage"
    }
}
