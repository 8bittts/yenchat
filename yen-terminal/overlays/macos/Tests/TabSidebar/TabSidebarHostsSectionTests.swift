import Foundation
import Testing
@testable import YEN

private actor CountingHostServices {
    private(set) var statusCalls = 0
    private(set) var listCalls = 0
    let status: TailscaleStatus

    init(status: TailscaleStatus) { self.status = status }

    func nextStatus() -> TailscaleStatus {
        statusCalls += 1
        return status
    }

    func nextList() -> RemoteSessionList {
        listCalls += 1
        return .sessions([], complete: true)
    }

    nonisolated var services: RemoteHostsStore.Services {
        RemoteHostsStore.Services(status: { await self.nextStatus() }, list: { _ in await self.nextList() })
    }
}

@MainActor
private final class RecordingTimer: RemoteHostsTimer {
    private(set) var isValid = true
    nonisolated func invalidate() { MainActor.assumeIsolated { isValid = false } }
}

@MainActor
@Suite(.serialized)
struct TabSidebarHostsSectionTests {
    private let mini = TailscalePeer(id: "nMini", displayName: "Mini", sshTarget: "mini.example.ts.net", isOnline: true)

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func make(_ fake: CountingHostServices) -> (TabSidebarHostsSection, RemoteHostsStore, () -> [RecordingTimer]) {
        var timers: [RecordingTimer] = []
        let store = RemoteHostsStore(services: fake.services, scheduler: { _, _ in
            let timer = RecordingTimer()
            timers.append(timer)
            return timer
        })
        let section = TabSidebarHostsSection(store: store, isOpenHere: { _ in false })
        return (section, store, { timers })
    }

    @Test func aNewSidebarStartsCollapsedAndDiscoversNothing() async {
        #expect(!TabSidebarDataSource().hostsSection.isExpanded)
        let fake = CountingHostServices(status: .running(peers: [mini]))
        let (section, store, timers) = make(fake)
        section.setShowing(true)
        try? await Task.sleep(for: .milliseconds(50))
        await settle()
        #expect(!section.isExpanded)
        #expect(section.rows.isEmpty)
        #expect(!section.isDiscovering)
        #expect(!store.isSurfaceVisible)
        #expect(timers().isEmpty)
        #expect(await fake.statusCalls == 0)
        #expect(await fake.listCalls == 0)
    }

    @Test func discoveryRunsOnlyWhileExpandedAndShowing() async {
        #expect(TabSidebarHostsSection.wantsDiscovery(expanded: true, showing: true))
        #expect(!TabSidebarHostsSection.wantsDiscovery(expanded: true, showing: false))
        #expect(!TabSidebarHostsSection.wantsDiscovery(expanded: false, showing: true))
        // A docked rail counts only while its window is on screen.
        #expect(DockedTabSidebarModel.railShowsHosts(railVisible: true, hasWindow: true, windowOnScreen: true))
        #expect(!DockedTabSidebarModel.railShowsHosts(railVisible: true, hasWindow: true, windowOnScreen: false))
        #expect(!DockedTabSidebarModel.railShowsHosts(railVisible: false, hasWindow: true, windowOnScreen: true))
        #expect(!DockedTabSidebarModel.railShowsHosts(railVisible: true, hasWindow: false, windowOnScreen: true))
        // The transient panel hides while YEN is inactive but stays open.
        #expect(TabSidebarController.transientPanelShowsHosts(open: true, appIsActive: true))
        #expect(!TabSidebarController.transientPanelShowsHosts(open: true, appIsActive: false))
        #expect(!TabSidebarController.transientPanelShowsHosts(open: false, appIsActive: true))

        let fake = CountingHostServices(status: .running(peers: [mini]))
        let (section, store, timers) = make(fake)
        // Expanded in a hidden sidebar: nothing yet.
        section.setExpanded(true)
        await settle()
        #expect(await fake.statusCalls == 0)
        #expect(timers().isEmpty)

        section.setShowing(true)
        await store.refresh().value
        #expect(await fake.statusCalls == 1)
        #expect(timers().count == 1)
        #expect(section.rows.map(\.title).contains("Refresh Remote Sessions"))

        section.setExpanded(false)
        #expect(!(timers().last?.isValid ?? true))
        #expect(!store.isSurfaceVisible)

        section.setExpanded(true)
        #expect(store.isSurfaceVisible)
        section.setShowing(false)
        #expect(!store.isSurfaceVisible)
        #expect(!(timers().last?.isValid ?? true))
    }

    @Test func rowsAreThePaletteRowsWithoutTheirPrefix() async {
        let fake = CountingHostServices(status: .stopped)
        let (section, store, _) = make(fake)
        section.setShowing(true)
        section.setExpanded(true)
        await store.refresh().value
        await settle()
        #expect(section.rows.map(\.title) == ["Tailscale Is Turned Off"])
        let palette = RemoteHostsPaletteRows.entries(snapshot: store.snapshot, isOpenHere: { _ in false })
        #expect(section.rows.map(\.entry) == palette)
        #expect(TabSidebarHostsSection.displayTitle("Hosts: ~/src on Mini") == "~/src on Mini")
        let session = TabSidebarHostsSection.Row(entry: RemoteHostsPaletteEntry(
            id: "hosts:s", title: "Hosts: ~/src on Mini", subtitle: "Detached · started 5 minutes ago",
            description: "Attach to this session on Mini in a new tab", leadingIcon: "network", searchTags: [], action: .refresh
        ))
        #expect(TabSidebarHostsSection.accessibilityLabel(for: session) == "~/src on Mini, Detached · started 5 minutes ago")
        section.setExpanded(false)
    }

    @Test func aRefreshRowRefreshesTheStore() async {
        let fake = CountingHostServices(status: .stopped)
        let (section, store, _) = make(fake)
        section.setShowing(true)
        section.setExpanded(true)
        await store.refresh().value
        let row = TabSidebarHostsSection.Row(entry: RemoteHostsPaletteEntry(
            id: "hosts:refresh", title: "Hosts: Refresh Remote Sessions", subtitle: nil,
            description: "", leadingIcon: "arrow.clockwise", searchTags: [], action: .refresh
        ))
        section.perform(row, in: nil)
        await store.refresh().value
        #expect(await fake.statusCalls == 2)
        section.setExpanded(false)
    }
}
