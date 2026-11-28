import AppKit
import SwiftUI

@MainActor
final class TokenUsageMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// The menu-bar button: the token count, then the YEN mark after it.
    var statusButton: NSStatusBarButton? { item.button }
    private var panel: TokenPanel?
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private let snapshot = TokenMenuSnapshot()
    private let index: TokenUsageIndex
    private var watcher: TokenSourceWatcher?
    private var changes: [TokenTool: Set<URL>] = [:]
    private var worker: Task<TokenMenuReading, Never>?
    private var historian: Task<(days: [TokenTool: [Int]], rhythm: [Int])?, Never>?
    private var wantsHistory = false
    private var pending = Set<TokenTool>()
    private var delay: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var meterIndex = 0
    private var active = true
    private var displayedDay = Calendar.current.startOfDay(for: Date())
    /// Delivers plan limit alerts; the test host passes none, so a suite never posts one.
    private let alert: (@MainActor ([TokenLimitAlerts.Alert]) -> Void)?
    /// Where `yen usage` reads today's numbers; none in the test host.
    private let report: URL?

    /// Reads the user's records into the app's cache folder.
    nonisolated static var standardIndex: TokenUsageIndex {
        let fm = FileManager.default
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.yenchat.yen")
            .appendingPathComponent("TokenUsage")
        return TokenUsageIndex(home: fm.homeDirectoryForCurrentUser, directory: cache)
    }

    init(index: TokenUsageIndex = TokenUsageMenu.standardIndex,
         alert: (@MainActor ([TokenLimitAlerts.Alert]) -> Void)? = TokenUsageMenu.liveAlert,
         report: URL? = TokenUsageMenu.liveReport) {
        self.index = index
        self.alert = alert
        self.report = report
        super.init()
        item.autosaveName = "YENTokenUsage"
        item.isVisible = true
        let button = item.button
        let image = Bundle.main.url(forResource: "YENMenuMark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        image?.size = .init(width: 16, height: 16)
        image?.isTemplate = true
        button?.image = image
        button?.imagePosition = .imageTrailing
        button?.target = self
        button?.action = #selector(toggle)
        // A right-click or Control-click opens the item's menu instead of the panel.
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        historian?.cancel()
        rotation?.cancel()
        delay?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closePanel()
        NSStatusBar.system.removeStatusItem(item)
        if report != nil { TokenProjectUsage.shared.clear() }
        if let report { TokenUsageReport.remove(at: report) }
    }

    /// Alerts and the report belong to the app; the test host gets neither.
    nonisolated static var liveAlert: (@MainActor ([TokenLimitAlerts.Alert]) -> Void)? {
        if isRunningUnderXCTest() { return nil }
        return { alerts in deliver(alerts) }
    }

    nonisolated static var liveReport: URL? { isRunningUnderXCTest() ? nil : TokenUsageReport.url() }

    /// Posts each alert on the Usage Limits stream, which owns its sound and delivery mode.
    static func deliver(_ alerts: [TokenLimitAlerts.Alert]) {
        let now = Date()
        for alert in alerts {
            AppDelegate.deliverManagedLocalNotification(service: .usage, title: alert.title, body: alert.body(now: now),
                                                        identifier: alert.identifier, categoryIdentifier: nil,
                                                        userInfo: [TokenLimitAlerts.userInfoKey: true])
        }
    }

    /// Opens the panel below the status item, as a click on it does.
    func showPanel() {
        guard panel == nil else { return }
        openPanel()
    }

    @objc private func toggle() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            closePanel()
            // A menu set on the item opens where macOS places status menus; the click below shows
            // it and returns when it closes, and clearing it keeps a left click opening the panel.
            item.menu = contextMenu()
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if panel != nil { closePanel(); return }
        openPanel()
    }

    private func openPanel() {
        guard let button = item.button, let itemWindow = button.window else { return }
        let anchor = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = itemWindow.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        let visible = screen.visibleFrame
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
        let host = NSHostingView(rootView: TokenUsageOverview(snapshot: snapshot, mark: button.image,
            heightLimit: visible.height - 24,
            cycle: { [weak self] in self?.cycleDisplay() }, refresh: { [weak self] in self?.refreshAll() },
            loadHistory: { [weak self] in self?.loadHistory() })
            .fixedSize())
        window.contentView = host
        window.open(below: anchor, size: host.fittingSize, visible: visible)
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

    /// The right-click menu: the app and its version, Refresh, Check for Updates and Quit.
    /// Check for Updates has no target, so it reaches `AppDelegate.checkForUpdates(_:)`.
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let name = NSMenuItem(title: "YEN" + (version.map { " · v" + $0 } ?? ""), action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)
        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshAll), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: NSSelectorFromString("checkForUpdates:"), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit YEN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
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
            snapshot.history = nil
            snapshot.rhythm = nil
            snapshot.projects = [:]
            updateTitle()
        }
        // A source that was unreadable gets another try; finished days are never read again.
        if wantsHistory, snapshot.history?.count != TokenTool.allCases.count { loadHistory() }
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
            return TokenMenuReading(counts: counts,
                                    workspace: tools.contains(.openCode) ? TokenLocalPlans.openCodeWorkspace(home: index.home) : nil, plans: [
                .claude: TokenClaudeLimits.merged(TokenClaudeLimits.meters(home: index.home, now: now),
                                                  cache: TokenLocalPlans.claude(home: index.home, now: now)),
                .codex: (try? index.latestCodexPlan()) ?? [],
                .grok: TokenLocalPlans.grok(home: index.home, now: now)
            ], projects: (try? index.projects()) ?? [:])
        }
        worker = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.active else { return }
            self.worker = nil
            if day == self.displayedDay {
                var counts = self.snapshot.counts ?? [:]
                // A source that was readable and failed this time gets one more try: a lock or a
                // store in the middle of a write clears by itself, and no file event announces that.
                // A second failure waits for the next change, so an absent source costs no wakeups.
                let lost = tools.filter { counts[$0] != nil && result.counts[$0] == nil }
                if !lost.isEmpty { self.schedule(lost) }
                for tool in tools { counts[tool] = result.counts[tool] }
                if tools.contains(.openCode) { self.snapshot.workspace = result.workspace }
                self.snapshot.plans = result.plans
                self.snapshot.counts = counts
                self.snapshot.projects = result.projects
                self.publish(counts: counts, plans: result.plans, projects: result.projects)
                if let alert = self.alert {
                    let due = TokenLimitAlerts.evaluate(plans: result.plans)
                    if !due.isEmpty { alert(due) }
                }
                self.updateTitle()
            }
            if !self.pending.isEmpty && self.delay == nil { self.schedule([]) }
        }
    }

    /// Shares today's folders with the tab sidebar and writes the file `yen usage` prints.
    private func publish(counts: TokenUsageIndex.Counts, plans: [TokenTool: [TokenPlanMeter]],
                         projects: [String: TokenUsageIndex.Counts]) {
        guard let report else { return }
        TokenProjectUsage.shared.update(projects)
        let file = TokenUsageReport.make(counts: counts, plans: plans, projects: projects, now: Date())
        Task.detached(priority: .utility) { try? TokenUsageReport.write(file, to: report) }
    }

    /// The analytics view asks for the finished days once; the first read of a large history takes
    /// seconds on one core (`_docs/01-architecture.md` → Optional desktop integrations).
    private func loadHistory() {
        wantsHistory = true
        guard active, historian == nil else { return }
        let day = displayedDay
        let task = Task.detached(priority: .utility) { [index] () -> (days: [TokenTool: [Int]], rhythm: [Int])? in
            guard let days = try? index.history() else { return nil }
            return (days, (try? index.rhythm()) ?? [])
        }
        historian = task
        Task { [weak self] in
            let result = await task.value
            guard let self, self.active else { return }
            self.historian = nil
            if day == self.displayedDay {
                self.snapshot.history = result?.days ?? [:]
                self.snapshot.rhythm = result?.rhythm
            } else { self.loadHistory() }
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
        guard snapshot.display == .rotating else { return }
        rotation = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.meterIndex += 1
                self.updateTitle()
            }
        }
    }

    private func updateTitle() {
        let counts = snapshot.counts
        let sum = counts?.values.reduce(0, +) ?? 0
        let caption = snapshot.display.caption(counts: counts, plans: snapshot.plans, step: meterIndex, now: Date())
        // The mark trails the count, so the space separates the two.
        item.button?.title = caption.isEmpty ? "" : caption + " "
        let summary = counts == nil ? "Reading local token usage" : "Token usage today: \(sum.formatted()) from \(counts?.count ?? 0) of 4 sources"
        let title = snapshot.display == .rotating ? caption + ". " + summary : summary
        item.button?.toolTip = title
        item.button?.setAccessibilityLabel(title)
    }
}

private final class TokenPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss?() }

    private var placement: (topRight: CGPoint, minimumOrigin: CGPoint)?

    func open(below anchor: CGRect, size: CGSize, visible: CGRect) {
        let safe = visible.insetBy(dx: 8, dy: 8)
        let left = max(safe.minX, min(anchor.midX - size.width / 2, safe.maxX - size.width))
        let top = min(anchor.minY - 6, safe.maxY)
        setFrame(CGRect(x: left.rounded(), y: max(safe.minY, top - size.height).rounded(),
                        width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
        // AppKit aligns the opening frame to the screen. Pin the corner it actually displayed.
        placement = (CGPoint(x: frame.maxX, y: frame.maxY), safe.origin)
    }

    // The hosting view resizes its window when the layout changes. Keep the header under the pointer.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var next = frameRect
        if let placement {
            next.origin = CGPoint(x: max(placement.minimumOrigin.x, placement.topRight.x - next.width).rounded(),
                                  y: max(placement.minimumOrigin.y, placement.topRight.y - next.height).rounded())
        }
        super.setFrame(next, display: flag)
    }
}

private struct TokenMenuReading: Sendable {
    let counts: TokenUsageIndex.Counts
    let workspace: String?
    let plans: [TokenTool: [TokenPlanMeter]]
    let projects: [String: TokenUsageIndex.Counts]
}

enum TokenMenuDisplay: String, CaseIterable {
    case total = "Total tokens", provider = "Top provider", rotating = "Rotating limits", mark = "Icon only"
    static let key = "com.yenchat.yen.tokenUsage.display"
    static let columnsKey = "com.yenchat.yen.tokenUsage.twoColumns"

    /// The saved choice; v1.288 saved the rotating mode as "Plan limits".
    init(stored: String?) {
        self = stored == "Plan limits" ? .rotating : stored.flatMap(Self.init(rawValue:)) ?? .total
    }

    /// The menu bar text before the mark. Rotating shows today's total and one current plan
    /// reading, the next one at each `step`, such as "514M · Claude 64%".
    func caption(counts: TokenUsageIndex.Counts?, plans: [TokenTool: [TokenPlanMeter]], step: Int, now: Date) -> String {
        let sum = counts?.values.reduce(0, +) ?? 0
        let value = counts == nil ? "…" : counts?.isEmpty == true ? "—" : sum.formatted(.number.notation(.compactName))
        let total = value + ((1..<TokenTool.allCases.count).contains(counts?.count ?? 0) ? "*" : "")
        switch self {
        case .total: return total
        case .provider:
            let leader = TokenTool.allCases.max { (counts?[$0] ?? -1) < (counts?[$1] ?? -1) }
            guard let leader, let count = counts?[leader], count > 0 else { return value }
            return leader.rawValue + " " + count.formatted(.number.notation(.compactName))
        case .rotating:
            let limits = TokenTool.allCases.flatMap { tool in
                (plans[tool] ?? []).filter { $0.isCurrent(at: now) }.map { Self.limit(tool, $0) }
            }
            return limits.isEmpty ? total : total + " · " + limits[step % limits.count]
        case .mark: return ""
        }
    }

    /// A weekly pool needs no label, since most plans have only that one: "Claude 64%",
    /// "Claude 5h 12%", "Claude Opus 40%", "Grok 1%".
    static func limit(_ tool: TokenTool, _ meter: TokenPlanMeter) -> String {
        let pool: String
        switch meter.label {
        case "Weekly": pool = ""
        case "5-hour": pool = "5h"
        case _ where tool == .grok: pool = ""
        case _ where meter.label.hasSuffix(" weekly"): pool = String(meter.label.dropLast(" weekly".count))
        default: pool = meter.label
        }
        let name = tool == .claude ? "Claude" : tool.rawValue
        let percent = (meter.percent / 100).formatted(.percent.precision(.fractionLength(0)))
        return [name, pool, percent].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Reset All Settings forgets the menu bar display and the panel layout.
    static func reset(defaults: UserDefaults = .standard) {
        for key in [key, columnsKey] { defaults.removeObject(forKey: key) }
    }
}

@MainActor
final class TokenMenuSnapshot: ObservableObject {
    @Published var workspace: String?
    @Published var counts: TokenUsageIndex.Counts?
    /// Tokens for each finished day, oldest first; nil until the analytics view asks for them.
    @Published var history: [TokenTool: [Int]]?
    @Published var plans: [TokenTool: [TokenPlanMeter]] = [:]
    /// Today's tokens per working folder and tool.
    @Published var projects: [String: TokenUsageIndex.Counts] = [:]
    /// Tokens by weekday and hour over the analytics window (`TokenUsageIndex.rhythm`); nil until read.
    @Published var rhythm: [Int]?
    @Published var display = TokenMenuDisplay(stored: UserDefaults.standard.string(forKey: TokenMenuDisplay.key))
}
