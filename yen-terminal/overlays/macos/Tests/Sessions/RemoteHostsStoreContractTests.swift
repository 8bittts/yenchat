import Foundation
import Testing
@testable import YEN

// The Hosts store rules RemoteHostsStoreTests leaves open
// (_docs/01-architecture.md -> Hosts store).

/// Fake Tailscale and ssh whose status and listings can each be held open.
private actor HeldHostServices {
    private(set) var statusCalls = 0
    private(set) var listCalls: [String] = []
    private let status: TailscaleStatus
    private var holdStatus = false
    private var holdLists = false
    private var statusWaiters: [CheckedContinuation<Void, Never>] = []
    private var listWaiters: [CheckedContinuation<Void, Never>] = []

    init(status: TailscaleStatus) { self.status = status }

    func setHolds(status: Bool, lists: Bool) {
        holdStatus = status
        holdLists = lists
    }

    func releaseStatus() {
        holdStatus = false
        statusWaiters.forEach { $0.resume() }
        statusWaiters = []
    }

    func releaseLists() {
        holdLists = false
        listWaiters.forEach { $0.resume() }
        listWaiters = []
    }

    func nextStatus() async -> TailscaleStatus {
        statusCalls += 1
        if holdStatus { await withCheckedContinuation { statusWaiters.append($0) } }
        return status
    }

    func nextList(_ target: String) async -> RemoteSessionList {
        listCalls.append(target)
        if holdLists { await withCheckedContinuation { listWaiters.append($0) } }
        return .sessions([], complete: true)
    }

    nonisolated var services: RemoteHostsStore.Services {
        RemoteHostsStore.Services(
            status: { await self.nextStatus() },
            list: { await self.nextList($0) }
        )
    }
}

@MainActor
private final class InertTimer: RemoteHostsTimer {
    nonisolated func invalidate() {}
}

@MainActor
@Suite(.serialized)
struct RemoteHostsStoreContractTests {
    private func store(_ fake: HeldHostServices) -> RemoteHostsStore {
        RemoteHostsStore(services: fake.services, scheduler: { _, _ in InertTimer() })
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func peers(_ count: Int) -> [TailscalePeer] {
        (1...count).map { TailscalePeer(id: "n\($0)", displayName: "Mac \($0)", sshTarget: "mac-\($0).example.ts.net", isOnline: true) }
    }

    /// The surface appearing starts discovery by itself; nothing else asks.
    @Test func aSurfaceAppearingStartsARefresh() async {
        let fake = HeldHostServices(status: .running(peers: []))
        let store = store(fake)
        let surface = NSObject()
        store.surfaceDidAppear(surface)
        await settle()
        #expect(await fake.statusCalls == 1)
        store.surfaceDidDisappear(surface)
    }

    @Test func aPeerNeverListedShowsLoadingWhileItIsListed() async {
        let peer = peers(1)[0]
        let fake = HeldHostServices(status: .running(peers: [peer]))
        await fake.setHolds(status: false, lists: true)
        let store = store(fake)
        let refresh = store.refresh()
        await settle()
        #expect(store.snapshot.peerStates[peer.id] == .loading)
        await fake.releaseLists()
        await refresh.value
        #expect(store.snapshot.peerStates[peer.id] == .listed(.sessions([], complete: true)))
    }

    @Test func atMostFourListingsRunAtOnce() async {
        let all = peers(6)
        let fake = HeldHostServices(status: .running(peers: all))
        await fake.setHolds(status: false, lists: true)
        let store = store(fake)
        let refresh = store.refresh()
        await settle()
        #expect(await fake.listCalls.count == RemoteHostsStore.maxConcurrentListings)
        #expect(RemoteHostsStore.maxConcurrentListings == 4)
        await fake.releaseLists()
        // Each finished listing starts the next one, so release until all ran.
        for _ in 0..<10 {
            await settle()
            await fake.releaseLists()
        }
        await refresh.value
        #expect(await fake.listCalls.count == all.count)
        #expect(store.snapshot.peerStates.values.allSatisfy { $0 == .listed(.sessions([], complete: true)) })
    }

    @Test func aRefreshRunningWhenTheLastSurfaceHidesFinishes() async {
        let peer = peers(1)[0]
        let fake = HeldHostServices(status: .running(peers: [peer]))
        await fake.setHolds(status: true, lists: false)
        let store = store(fake)
        let surface = NSObject()
        store.surfaceDidAppear(surface)
        await settle()
        store.surfaceDidDisappear(surface)
        let running = store.refresh()
        await fake.releaseStatus()
        await running.value
        #expect(store.snapshot.status == .running(peers: [peer]))
        #expect(store.snapshot.peerStates[peer.id] == .listed(.sessions([], complete: true)))
        #expect(await fake.statusCalls == 1)
    }
}
