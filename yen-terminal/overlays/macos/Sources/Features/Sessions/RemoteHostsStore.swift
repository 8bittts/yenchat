import Combine
import Foundation

/// A cancellable repeating timer, injectable for tests.
protocol RemoteHostsTimer: AnyObject {
    func invalidate()
}

extension Timer: RemoteHostsTimer {}

/// The Tailscale status, the user's other Macs, and each Mac's sessions, for
/// the Hosts surfaces (the command palette now, the tab sidebar later).
///
/// Privacy and cost rule (_docs/01-architecture.md -> Persistent sessions ->
/// Hosts store): YEN never runs the Tailscale CLI or ssh at launch or in the
/// background. Discovery runs only while a Hosts surface is visible (when it
/// appears and data is older than `freshness`, then every `interval`) and on
/// an explicit refresh. With no surface visible the store holds no timer and
/// starts no process.
@MainActor
final class RemoteHostsStore: ObservableObject {
    static let shared = RemoteHostsStore()

    /// What one peer's row shows.
    enum PeerState: Equatable, Sendable {
        /// Never listed yet; a listing is in flight.
        case loading
        /// Tailscale reports the peer offline, so YEN does not ssh to it.
        case offline
        case listed(RemoteSessionList)
    }

    struct Snapshot: Equatable, Sendable {
        /// nil until the first Tailscale answer.
        var status: TailscaleStatus?
        var peerStates: [String: PeerState] = [:]
        var isRefreshing = false

        var peers: [TailscalePeer] {
            if case .running(let peers) = status { return peers }
            return []
        }
    }

    struct Services: Sendable {
        var status: @Sendable () async -> TailscaleStatus
        var list: @Sendable (_ sshTarget: String) async -> RemoteSessionList

        static let live = Services(
            status: { await TailscaleDiscovery.status() },
            list: { await RemoteSessions.list(host: $0) }
        )
    }

    typealias Scheduler = @MainActor (_ interval: TimeInterval, _ fire: @escaping @MainActor @Sendable () -> Void) -> RemoteHostsTimer

    static let liveScheduler: Scheduler = { interval, fire in
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { fire() }
        }
        timer.tolerance = interval * 0.2
        return timer
    }

    /// A surface that appears within this long of the last refresh reuses it.
    nonisolated static let defaultFreshness: TimeInterval = 30
    /// The refresh interval while a surface stays visible.
    nonisolated static let defaultInterval: TimeInterval = 30
    /// Peers listed at once; each listing is one ssh connection.
    nonisolated static let maxConcurrentListings = 4

    @Published private(set) var snapshot = Snapshot()

    private let services: Services
    private let scheduler: Scheduler
    private let now: () -> Date
    private let freshness: TimeInterval
    private let interval: TimeInterval
    private var visibleSurfaces: Set<ObjectIdentifier> = []
    private var timer: RemoteHostsTimer?
    private var inFlight: Task<Void, Never>?
    private var lastRefreshStarted: Date?

    init(
        services: Services = .live,
        scheduler: Scheduler? = nil,
        now: @escaping () -> Date = Date.init,
        freshness: TimeInterval = RemoteHostsStore.defaultFreshness,
        interval: TimeInterval = RemoteHostsStore.defaultInterval
    ) {
        self.services = services
        self.scheduler = scheduler ?? Self.liveScheduler
        self.now = now
        self.freshness = freshness
        self.interval = interval
    }

    var isSurfaceVisible: Bool { !visibleSurfaces.isEmpty }
    var hasTimer: Bool { timer != nil }

    /// A Hosts surface became visible. Idempotent per surface.
    func surfaceDidAppear(_ surface: AnyObject) {
        let (inserted, _) = visibleSurfaces.insert(ObjectIdentifier(surface))
        guard inserted, visibleSurfaces.count == 1 else { return }
        if let lastRefreshStarted, now().timeIntervalSince(lastRefreshStarted) < freshness {
            // Fresh enough; the timer picks up from here.
        } else {
            refresh()
        }
        timer = scheduler(interval) { [weak self] in
            guard let self, self.isSurfaceVisible else { return }
            self.refresh()
        }
    }

    /// A Hosts surface closed. The last one stops the timer; a refresh already
    /// running finishes, because its processes have their own deadlines.
    func surfaceDidDisappear(_ surface: AnyObject) {
        guard visibleSurfaces.remove(ObjectIdentifier(surface)) != nil, visibleSurfaces.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Refresh now. A refresh already in flight is reused, so overlapping
    /// requests never stack processes.
    @discardableResult
    func refresh() -> Task<Void, Never> {
        if let inFlight { return inFlight }
        lastRefreshStarted = now()
        snapshot.isRefreshing = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        inFlight = task
        return task
    }

    private func performRefresh() async {
        defer {
            inFlight = nil
            snapshot.isRefreshing = false
        }
        let status = await services.status()
        let peers: [TailscalePeer]
        if case .running(let running) = status { peers = running } else { peers = [] }

        // Keep each peer's last listing on screen while it is listed again.
        var states: [String: PeerState] = [:]
        for peer in peers {
            if !peer.isOnline {
                states[peer.id] = .offline
            } else if case .listed(let list)? = snapshot.peerStates[peer.id] {
                states[peer.id] = .listed(list)
            } else {
                states[peer.id] = .loading
            }
        }
        snapshot.status = status
        snapshot.peerStates = states

        let online = peers.filter(\.isOnline)
        let list = services.list
        await withTaskGroup(of: (String, RemoteSessionList).self) { group in
            var pending = online.makeIterator()
            func addNext() -> Bool {
                guard let peer = pending.next() else { return false }
                let id = peer.id, target = peer.sshTarget
                group.addTask { (id, await list(target)) }
                return true
            }
            for _ in 0..<Self.maxConcurrentListings {
                if !addNext() { break }
            }
            while let next = await group.next() {
                let (id, result) = next
                // The peer may have left the tailnet while it was listed.
                if snapshot.peerStates[id] != nil { snapshot.peerStates[id] = .listed(result) }
                _ = addNext()
            }
        }
    }
}
