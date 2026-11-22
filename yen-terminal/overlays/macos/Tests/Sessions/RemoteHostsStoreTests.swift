import Foundation
import Testing
@testable import YEN

/// Fake Tailscale and ssh: counts every call and can hold a call open until
/// the test releases it.
private actor FakeHostServices {
    private(set) var statusCalls = 0
    private(set) var listCalls: [String] = []
    private var status: TailscaleStatus
    private var lists: [String: RemoteSessionList]
    private var holdStatus = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(status: TailscaleStatus, lists: [String: RemoteSessionList] = [:]) {
        self.status = status
        self.lists = lists
    }

    func setStatus(_ value: TailscaleStatus) { status = value }
    func setList(_ value: RemoteSessionList, for target: String) { lists[target] = value }
    func hold() { holdStatus = true }

    func release() {
        holdStatus = false
        waiting.forEach { $0.resume() }
        waiting = []
    }

    func nextStatus() async -> TailscaleStatus {
        statusCalls += 1
        if holdStatus { await withCheckedContinuation { waiting.append($0) } }
        return status
    }

    func nextList(_ target: String) -> RemoteSessionList {
        listCalls.append(target)
        return lists[target] ?? .sessions([], complete: true)
    }

    var services: RemoteHostsStore.Services {
        RemoteHostsStore.Services(
            status: { await self.nextStatus() },
            list: { await self.nextList($0) }
        )
    }
}

@MainActor
private final class FakeTimer: RemoteHostsTimer {
    let interval: TimeInterval
    let fire: @MainActor @Sendable () -> Void
    private(set) var isValid = true

    init(interval: TimeInterval, fire: @escaping @MainActor @Sendable () -> Void) {
        self.interval = interval
        self.fire = fire
    }

    nonisolated func invalidate() {
        MainActor.assumeIsolated { isValid = false }
    }
}

@MainActor
private final class FakeScheduler {
    private(set) var timers: [FakeTimer] = []

    var scheduler: RemoteHostsStore.Scheduler {
        { [unowned self] interval, fire in
            let timer = FakeTimer(interval: interval, fire: fire)
            self.timers.append(timer)
            return timer
        }
    }
}

@MainActor
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
@Suite(.serialized)
struct RemoteHostsStoreTests {
    private let mini = TailscalePeer(id: "nMini", displayName: "Mini", sshTarget: "mini.example.ts.net", isOnline: true)
    private let air = TailscalePeer(id: "nAir", displayName: "Air", sshTarget: "100.64.0.8", isOnline: false)
    private let session = RemoteSession(id: UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!, state: .detached, started: nil, directory: "/Users/dev/project")

    private func makeStore(_ fake: FakeHostServices, _ scheduler: FakeScheduler, _ clock: Clock) async -> RemoteHostsStore {
        RemoteHostsStore(services: await fake.services, scheduler: scheduler.scheduler, now: { clock.now })
    }

    /// Let queued main-actor work and detached fakes run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func doesNothingWhileNoSurfaceIsVisible() async {
        let fake = FakeHostServices(status: .running(peers: [mini]))
        let scheduler = FakeScheduler()
        let store = await makeStore(fake, scheduler, Clock())

        try? await Task.sleep(for: .milliseconds(50))
        await settle()

        #expect(await fake.statusCalls == 0)
        #expect(await fake.listCalls.isEmpty)
        #expect(scheduler.timers.isEmpty)
        #expect(!store.hasTimer)
        #expect(store.snapshot == RemoteHostsStore.Snapshot())
    }

    @Test func appearingRefreshesAndTheLastDisappearanceStopsTheTimer() async {
        let fake = FakeHostServices(status: .running(peers: [mini]), lists: [mini.sshTarget: .sessions([session], complete: true)])
        let scheduler = FakeScheduler()
        let store = await makeStore(fake, scheduler, Clock())
        let first = NSObject(), second = NSObject()

        store.surfaceDidAppear(first)
        await store.refresh().value
        #expect(await fake.statusCalls == 1)
        #expect(scheduler.timers.count == 1)
        #expect(scheduler.timers[0].interval == RemoteHostsStore.defaultInterval)
        #expect(store.snapshot.peerStates[mini.id] == .listed(.sessions([session], complete: true)))

        // A second surface shares the timer; appearing twice is idempotent.
        store.surfaceDidAppear(second)
        store.surfaceDidAppear(first)
        #expect(scheduler.timers.count == 1)

        store.surfaceDidDisappear(first)
        #expect(scheduler.timers[0].isValid)
        store.surfaceDidDisappear(second)
        #expect(!scheduler.timers[0].isValid)
        #expect(!store.hasTimer)

        // A timer that fires late, after the last surface closed, does no work.
        scheduler.timers[0].fire()
        await settle()
        #expect(await fake.statusCalls == 1)
    }

    @Test func theTimerRefreshesWhileVisible() async {
        let fake = FakeHostServices(status: .running(peers: []))
        let scheduler = FakeScheduler()
        let store = await makeStore(fake, scheduler, Clock())
        let surface = NSObject()

        store.surfaceDidAppear(surface)
        await store.refresh().value
        scheduler.timers[0].fire()
        await store.refresh().value
        #expect(await fake.statusCalls == 2)
        store.surfaceDidDisappear(surface)
    }

    @Test func reopeningWithinTheFreshnessWindowReusesTheLastRefresh() async {
        let fake = FakeHostServices(status: .running(peers: []))
        let scheduler = FakeScheduler()
        let clock = Clock()
        let store = await makeStore(fake, scheduler, clock)
        let surface = NSObject()

        store.surfaceDidAppear(surface)
        await store.refresh().value
        store.surfaceDidDisappear(surface)

        clock.now += RemoteHostsStore.defaultFreshness - 1
        store.surfaceDidAppear(surface)
        await settle()
        #expect(await fake.statusCalls == 1)
        store.surfaceDidDisappear(surface)

        clock.now += 2
        store.surfaceDidAppear(surface)
        await store.refresh().value
        #expect(await fake.statusCalls == 2)
        store.surfaceDidDisappear(surface)
    }

    @Test func overlappingRefreshesShareOneInFlightRefresh() async {
        let fake = FakeHostServices(status: .running(peers: [mini]))
        await fake.hold()
        let scheduler = FakeScheduler()
        let store = await makeStore(fake, scheduler, Clock())
        let surface = NSObject()

        store.surfaceDidAppear(surface)
        let first = store.refresh()
        let second = store.refresh()
        await settle()
        scheduler.timers[0].fire()
        await settle()
        #expect(store.snapshot.isRefreshing)
        #expect(await fake.statusCalls == 1)

        await fake.release()
        await first.value
        await second.value
        #expect(!store.snapshot.isRefreshing)
        #expect(await fake.statusCalls == 1)
        #expect(await fake.listCalls == [mini.sshTarget])
        store.surfaceDidDisappear(surface)
    }

    @Test func listsOnlyOnlinePeersAndKeepsTheLastListingWhileRefreshing() async {
        let fake = FakeHostServices(
            status: .running(peers: [air, mini]),
            lists: [mini.sshTarget: .sessions([session], complete: true)]
        )
        let scheduler = FakeScheduler()
        let store = await makeStore(fake, scheduler, Clock())

        await store.refresh().value
        #expect(await fake.listCalls == [mini.sshTarget])
        #expect(store.snapshot.peerStates == [
            air.id: .offline,
            mini.id: .listed(.sessions([session], complete: true)),
        ])

        // The next refresh shows the previous listing until the new one lands.
        await fake.hold()
        await fake.setList(.firstConnectionNeeded, for: mini.sshTarget)
        let again = store.refresh()
        await settle()
        #expect(store.snapshot.peerStates[mini.id] == .listed(.sessions([session], complete: true)))
        await fake.release()
        await again.value
        #expect(store.snapshot.peerStates[mini.id] == .listed(.firstConnectionNeeded))
    }

    @Test func theStatusIsUnknownUntilTailscaleAnswersAndPeersThatLeaveAreDropped() async {
        let fake = FakeHostServices(status: .running(peers: [mini]))
        await fake.hold()
        let store = await makeStore(fake, FakeScheduler(), Clock())

        let refresh = store.refresh()
        await settle()
        #expect(store.snapshot.status == nil)
        await fake.release()
        await refresh.value
        #expect(store.snapshot.status == .running(peers: [mini]))

        await fake.setStatus(.stopped)
        await store.refresh().value
        #expect(store.snapshot.status == .stopped)
        #expect(store.snapshot.peerStates.isEmpty)
        #expect(store.snapshot.peers.isEmpty)
    }
}
