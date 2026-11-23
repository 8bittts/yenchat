import AppKit
import Foundation
import SwiftUI
import Testing
@testable import YEN

// The palette's Hosts rows, for what RemoteHostsPaletteRowsTests leaves open:
// when the palette starts discovery, where a row's action goes, and which
// sessions read Open in YEN (_docs/13-desktop-features.md -> Hosts;
// _docs/04-security.md -> When YEN starts a process).

private typealias Fixtures = RemoteContractFixtures

private actor CountingHostServices {
    private(set) var statusCalls = 0

    func nextStatus() -> TailscaleStatus {
        statusCalls += 1
        return .running(peers: [])
    }

    nonisolated var services: RemoteHostsStore.Services {
        RemoteHostsStore.Services(
            status: { await self.nextStatus() },
            list: { _ in .sessions([], complete: true) }
        )
    }
}

@MainActor
private final class NoTimer: RemoteHostsTimer {
    nonisolated func invalidate() {}
}

@MainActor
@Suite(.serialized)
struct RemoteHostsPaletteContractTests {
    private let mini = TailscalePeer(id: "nMini", displayName: "Mini", sshTarget: "mini.example.ts.net", isOnline: true)

    private struct Recorded {
        var opened: [RemotePaneIdentity] = []
        var refreshes = 0
        var showHosts = 0
        var inserted: [String] = []
    }

    private func perform(_ action: RemoteHostsPaletteAction, overRemotePane: Bool) -> Recorded {
        var recorded = Recorded()
        RemoteHostsPaletteActions.perform(action, overRemotePane: overRemotePane, effects: .init(
            open: { recorded.opened.append($0) },
            refresh: { recorded.refreshes += 1 },
            showHosts: { recorded.showHosts += 1 },
            insert: { recorded.inserted.append($0) }
        ))
        return recorded
    }

    @Test func aCommandIsTypedOnlyIntoALocalPane() {
        #expect(perform(.insertCommand("ssh mini.example.ts.net"), overRemotePane: false).inserted == ["ssh mini.example.ts.net"])
        let remote = perform(.insertCommand("ssh-copy-id mini.example.ts.net"), overRemotePane: true)
        #expect(remote.inserted.isEmpty)
        #expect(remote.opened.isEmpty && remote.refreshes == 0 && remote.showHosts == 0)
    }

    @Test func eachRowActionReachesItsEffect() {
        let identity = Fixtures.identity
        for overRemotePane in [false, true] {
            #expect(perform(.attach(identity), overRemotePane: overRemotePane).opened == [identity])
            #expect(perform(.refresh, overRemotePane: overRemotePane).refreshes == 1)
            #expect(perform(.showHosts, overRemotePane: overRemotePane).showHosts == 1)
        }
    }

    @Test func onlyARunningClientCountsAsOpenHere() throws {
        let live = try Fixtures.controller(Fixtures.markedConfig())
        let held = try Fixtures.controller(Fixtures.markedConfig(), cli: "/usr/bin/false")
        let local = try Fixtures.controller(nil)
        let liveSurface = try #require(live.surfaceTree.first)
        let heldSurface = try #require(held.surfaceTree.first)
        let surfaces = [liveSurface, heldSurface, try #require(local.surfaceTree.first)]
        Fixtures.waitUntil { RemotePanes.isAttached(liveSurface) && !RemotePanes.isAttached(heldSurface) }
        #expect(RemoteHostsPaletteActions.openHere(surfaces) == [Fixtures.identity])
    }

    @Test func theRefreshAndLoadingRowsSayWhatIsHappening() {
        var snapshot = RemoteHostsStore.Snapshot()
        let loading = RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { _ in false })
        #expect(loading.first?.subtitle == "Checking Tailscale")
        snapshot.status = .running(peers: [mini])
        snapshot.peerStates = [mini.id: .offline]
        #expect(RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { _ in false }).last?.subtitle == nil)
        snapshot.isRefreshing = true
        let refreshing = RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { _ in false })
        #expect(refreshing.last?.id == "hosts:refresh")
        #expect(refreshing.last?.subtitle == "Refreshing")
    }

    /// Opening the palette starts no discovery; opening it on the Hosts query
    /// does, and closing it stops the timer (_docs/04-security.md -> When YEN
    /// starts a process).
    @Test func thePaletteDiscoversOnlyWithHostsIntent() async throws {
        let controller = try Fixtures.controller(nil)
        let surface = try #require(controller.surfaceTree.first)
        let fake = CountingHostServices()
        let store = RemoteHostsStore(services: fake.services, scheduler: { _, _ in NoTimer() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func show(seed: String?) -> NSHostingView<TerminalCommandPaletteView> {
            if let seed { RemoteHostsPaletteSeed.set(seed) }
            let view = TerminalCommandPaletteView(
                surfaceView: surface,
                isPresented: .constant(true),
                yenConfig: YEN.Config(config: nil),
                settingsController: SettingsController.shared,
                updateViewModel: nil,
                hostsStore: store,
                onAction: { _ in }
            )
            let host = NSHostingView(rootView: view)
            window.contentView = host
            window.orderFront(nil)
            Fixtures.spin()
            return host
        }

        _ = show(seed: nil)
        await Task.yield()
        #expect(await fake.statusCalls == 0)
        #expect(!store.isSurfaceVisible)
        window.contentView = nil
        Fixtures.spin()

        _ = show(seed: RemoteHostsIntent.tags[0])
        for _ in 0..<20 { await Task.yield() }
        #expect(store.isSurfaceVisible)
        #expect(store.hasTimer)
        #expect(await fake.statusCalls == 1)

        window.contentView = nil
        Fixtures.waitUntil { !store.isSurfaceVisible }
        #expect(!store.isSurfaceVisible)
        #expect(!store.hasTimer)
    }
}
