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

/// One online peer whose listing is fixed.
private actor OnePeerServices {
    let peer: TailscalePeer
    let listing: RemoteSessionList

    init(peer: TailscalePeer, listing: RemoteSessionList) {
        self.peer = peer
        self.listing = listing
    }

    nonisolated var services: RemoteHostsStore.Services {
        RemoteHostsStore.Services(
            status: { .running(peers: [self.peer]) },
            list: { _ in self.listing }
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

    /// The tab sidebar's Hosts rows (TabSidebarHostsSection.perform) carry the
    /// same rule: a command row over a remote pane types nothing. The paste
    /// path writes the general pasteboard first, so an unchanged change count
    /// shows nothing was typed, without touching the clipboard when it holds.
    @Test func theSidebarTypesNoCommandIntoARemotePane() throws {
        let controller = try Fixtures.controller(Fixtures.markedConfig())
        let remote = try #require(controller.surfaceTree.first)
        controller.focusedSurfaceDidChange(to: remote)
        try #require(controller.focusedSurface?.remotePaneIdentity != nil)
        let rows = RemoteHostsPaletteRows.peerRows(
            mini, state: .listed(.keySignInNeeded), isOpenHere: { _ in false }, now: Date()
        ).map(TabSidebarHostsSection.Row.init)
        let row = try #require(rows.first)
        #expect(row.entry.action == .insertCommand("ssh-copy-id mini.example.ts.net"))

        let section = TabSidebarHostsSection(store: RemoteHostsStore(services: CountingHostServices().services, scheduler: { _, _ in NoTimer() }), isOpenHere: { _ in false })
        let before = NSPasteboard.general.changeCount
        section.perform(row, in: controller.window)
        Fixtures.spin(0.4)
        #expect(NSPasteboard.general.changeCount == before)
    }

    /// A peer whose install is broken (no zmx there) prints its porcelain
    /// header and exits 1, so its listing is incomplete with no rows. That is
    /// a failure to list, not a Mac without sessions: the row must not tell
    /// the user to turn on Keep Sessions Running.
    @Test func anIncompleteListingWithNoRowsIsAListingFailure() {
        let failed = RemoteHostsPaletteRows.peerRows(mini, state: .listed(.failed), isOpenHere: { _ in false }, now: Date())
        let empty = RemoteHostsPaletteRows.peerRows(
            mini, state: .listed(.sessions([], complete: false)), isOpenHere: { _ in false }, now: Date()
        )
        #expect(empty == failed)
        #expect(empty.map(\.title) == ["Hosts: Could Not List Sessions on Mini"])
        #expect(empty.first?.action == .insertCommand("yen sessions list --host mini.example.ts.net"))
        #expect(!empty.contains { $0.title.contains("No Sessions") })
    }

    @Test func anIncompleteListingWithRowsKeepsThemAndSaysSomeCouldNotBeRead() {
        let session = RemoteSession(id: Fixtures.sessionID, state: .detached, started: nil, directory: "/Users/dev/src")
        let rows = RemoteHostsPaletteRows.peerRows(
            mini, state: .listed(.sessions([session], complete: false)), isOpenHere: { _ in false }, now: Date()
        )
        #expect(rows.map(\.title) == [
            "Hosts: ~/src on Mini",
            "Hosts: Some Sessions on Mini Could Not Be Read",
        ])
        let complete = RemoteHostsPaletteRows.peerRows(
            mini, state: .listed(.sessions([], complete: true)), isOpenHere: { _ in false }, now: Date()
        )
        #expect(complete.map(\.title) == ["Hosts: No Sessions on Mini"])
    }

    /// The tab sidebar reads the same rows, so it inherits the rule.
    @Test func theSidebarShowsABrokenPeerAsAListingFailure() async {
        let fake = OnePeerServices(peer: mini, listing: .sessions([], complete: false))
        let store = RemoteHostsStore(services: fake.services, scheduler: { _, _ in NoTimer() })
        let section = TabSidebarHostsSection(store: store, isOpenHere: { _ in false })
        section.setExpanded(true)
        section.setShowing(true)
        await store.refresh().value
        for _ in 0..<20 { await Task.yield() }
        let titles = section.rows.map(\.title)
        #expect(titles.contains("Could Not List Sessions on Mini"), "\(titles)")
        #expect(!titles.contains { $0.contains("No Sessions") || $0.contains("Could Not Be Read") }, "\(titles)")
        section.setExpanded(false)
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
        // A fixed number of yields was too short under full-suite load.
        Fixtures.waitUntil { store.isSurfaceVisible && store.hasTimer }
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
