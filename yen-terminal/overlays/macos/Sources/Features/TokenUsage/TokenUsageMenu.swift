import AppKit
import SwiftUI

@MainActor
final class TokenUsageMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: TokenPanel?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private let snapshot = TokenMenuSnapshot()
    private let connection = TokenPlanConnection()
    private let index: TokenUsageIndex
    private var watcher: TokenSourceWatcher?
    private var changes: [TokenTool: Set<URL>] = [:]
    private var worker: Task<TokenMenuReading, Never>?
    private var pending = Set<TokenTool>()
    private var delay: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var meterIndex = 0
    private var active = true
    private var displayedDay = Calendar.current.startOfDay(for: Date())

    override init() {
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yenchat.yen")
            .appendingPathComponent("TokenUsage")
        index = TokenUsageIndex(home: fm.homeDirectoryForCurrentUser, directory: cache)
        super.init()
        item.autosaveName = "YENTokenUsage"
        item.isVisible = true
        let button = item.button
        let image = Bundle.main.url(forResource: "YENMenuMark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        image?.size = .init(width: 16, height: 16)
        image?.isTemplate = true
        button?.image = image
        button?.imagePosition = .imageLeading
        button?.target = self
        button?.action = #selector(toggle)
        configureRotation()
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
        connection.stop()
        rotation?.cancel()
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
        let host = NSHostingView(rootView: TokenUsageOverview(snapshot: snapshot, connection: connection, mark: button.image,
            heightLimit: (button.window?.screen?.visibleFrame.height ?? 700) - 24,
            cycle: { [weak self] in self?.cycleDisplay() }, refresh: { [weak self] in self?.refreshAll() })
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
        let paths = changes.filter { snapshot.counts?[$0.key] != nil }
        changes.removeAll()
        let tools = pending
        let day = displayedDay
        pending.removeAll()
        let task = Task.detached(priority: .utility) { [index] in
            let counts = (try? index.read(tools: tools, changes: paths)) ?? [:]
            let now = Date()
            return TokenMenuReading(counts: counts, sharedPools: TokenLocalPlans.sharedCursorPools(home: index.home, now: now),
                                    workspace: tools.contains(.openCode) ? TokenLocalPlans.openCodeWorkspace(home: index.home) : nil, plans: [
                .claude: TokenLocalPlans.claude(home: index.home, now: now),
                .codex: (try? index.latestCodexPlan()) ?? [],
                .grok: TokenLocalPlans.grok(home: index.home, now: now)
            ])
        }
        worker = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.active else { return }
            self.worker = nil
            if day == self.displayedDay {
                var counts = self.snapshot.counts ?? [:]
                for tool in tools { counts[tool] = result.counts[tool] }
                self.snapshot.sharedPools = result.sharedPools
                if tools.contains(.openCode) { self.snapshot.workspace = result.workspace }
                self.snapshot.plans = result.plans
                self.snapshot.counts = counts
                self.updateTitle()
            }
            if !self.pending.isEmpty && self.delay == nil { self.schedule([]) }
        }
    }

    private func cycleDisplay() {
        let modes = TokenMenuDisplay.allCases
        let next = (modes.firstIndex(of: snapshot.display)! + 1) % modes.count
        snapshot.display = modes[next]
        UserDefaults.standard.set(snapshot.display.rawValue, forKey: TokenMenuDisplay.key)
        configureRotation()
        updateTitle()
    }

    private func configureRotation() {
        rotation?.cancel()
        meterIndex = 0
        guard snapshot.display == .limits else { return }
        rotation = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.connection.refresh()
                self.meterIndex += 1
                self.updateTitle()
            }
        }
    }

    private func updateTitle() {
        let counts = snapshot.counts
        let sum = counts?.values.reduce(0, +) ?? 0
        let value = counts == nil ? "…" : counts?.isEmpty == true ? "—" : sum.formatted(.number.notation(.compactName))
        let partial = (1..<TokenTool.allCases.count).contains(counts?.count ?? 0)
        let caption: String
        switch snapshot.display {
        case .total: caption = value + (partial ? "*" : "")
        case .provider:
            let leader = TokenTool.allCases.max { (counts?[$0] ?? -1) < (counts?[$1] ?? -1) }
            if let leader, let count = counts?[leader], count > 0 {
                caption = leader.rawValue + " " + count.formatted(.number.notation(.compactName))
            } else { caption = value }
        case .limits:
            let now = Date()
            let labels = TokenTool.allCases.flatMap { tool in
                let meters = snapshot.meters(for: tool, connection: connection)
                return meters.filter { $0.isCurrent(at: now) }.map { meter in
                    let name = tool == .grok ? meter.label : tool.rawValue + " " + meter.label
                    return name + " " + (meter.percent / 100).formatted(.percent)
                }
            }
            caption = labels.isEmpty ? "Limits —" : labels[meterIndex % labels.count]
        case .mark: caption = ""
        }
        item.button?.title = caption.isEmpty ? "" : " " + caption
        let summary = counts == nil ? "Reading local token usage" : "Token usage today: \(sum.formatted()) from \(counts?.count ?? 0) of 4 sources"
        let title = snapshot.display == .limits ? caption + ". " + summary : summary
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

private struct TokenMenuReading: Sendable {
    let counts: TokenUsageIndex.Counts
    let sharedPools: [TokenPlanMeter]
    let workspace: String?
    let plans: [TokenTool: [TokenPlanMeter]]
}

enum TokenMenuDisplay: String, CaseIterable {
    case total = "Total tokens", provider = "Top provider", limits = "Plan limits", mark = "Icon only"
    static let key = "com.yenchat.yen.tokenUsage.display"
    static let columnsKey = "com.yenchat.yen.tokenUsage.twoColumns"
}

@MainActor
final class TokenMenuSnapshot: ObservableObject {
    @Published var sharedPools: [TokenPlanMeter] = []
    @Published var workspace: String?
    func meters(for tool: TokenTool, connection: TokenPlanConnection) -> [TokenPlanMeter] {
        let local = plans[tool] ?? []
        guard tool == .grok else { return local }
        return local + (connection.connected ? connection.meters : sharedPools)
    }

    @Published var counts: TokenUsageIndex.Counts?
    @Published var plans: [TokenTool: [TokenPlanMeter]] = [:]
    @Published var display = TokenMenuDisplay(rawValue: UserDefaults.standard.string(forKey: TokenMenuDisplay.key) ?? "") ?? .total
}
