import AppKit
import SwiftUI

@MainActor
final class TokenUsageMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: TokenPanel?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
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
        closePanel()
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func toggle() {
        if panel != nil { closePanel(); return }
        guard let button = item.button, button.window != nil else { return }
        let window = TokenPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.title = "YEN Token Usage"
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.appearance = NSApp.keyWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        window.dismiss = { [weak self] in self?.closePanel() }
        panel = window
        let host = NSHostingView(rootView: TokenUsageOverview(snapshot: snapshot, mark: button.image)
            .fixedSize().background(GeometryReader { geometry in
                Color.clear.preference(key: TokenPanelSize.self, value: geometry.size)
            }).onPreferenceChange(TokenPanelSize.self) { [weak self, weak window] size in
                DispatchQueue.main.async {
                    guard let self, let window, self.panel === window else { return }
                    self.position(size)
                }
            })
        window.contentView = host
        position(host.fittingSize)
        window.makeKeyAndOrderFront(nil)
        button.highlight(true)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.closePanel()
                return nil
            }
            guard event.window !== self.panel else { return event }
            if let itemWindow = self.item.button?.window, event.window === itemWindow { return event }
            self.closePanel()
            return event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.closePanel() }
        NotificationCenter.default.addObserver(self, selector: #selector(closePanel),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(closePanel),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        refreshAll()
    }

    private func position(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let panel, let button = item.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        let frame = TokenPanel.frame(below: anchor, size: size, visible: screen.visibleFrame)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    @objc private func closePanel() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        item.button?.highlight(false)
    }

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
        if panel != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let size = self.panel?.contentView?.fittingSize else { return }
                self.position(size)
            }
        }
    }
}

private final class TokenPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss?() }

    /// Match JPtheCat's six-point anchor gap and eight-point visible-display inset.
    static func frame(below anchor: CGRect, size: CGSize, visible: CGRect) -> CGRect {
        let safe = visible.insetBy(dx: 8, dy: 8)
        let x = max(safe.minX, min(anchor.midX - size.width / 2, safe.maxX - size.width))
        let top = min(anchor.minY - 6, safe.maxY)
        return CGRect(x: x.rounded(), y: max(safe.minY, top - size.height).rounded(), width: size.width, height: size.height)
    }
}

private struct TokenPanelSize: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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
        }.padding(16).frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.primary.opacity(0.14)))
    }

    private func detail(for count: Int?, total: Int) -> String {
        guard let count else { return snapshot.counts == nil ? "Reading local source…" : "No readable local source." }
        guard count > 0, total > 0 else { return "Local source available. No recorded tokens today." }
        let share = (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0...1)))
        return "\(count.formatted()) tokens · \(share) of counted usage"
    }
}
