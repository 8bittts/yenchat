import Foundation
import Testing
@testable import YEN

struct RemoteHostsPaletteRowsTests {
    private let mini = TailscalePeer(id: "nMini", displayName: "Mini", sshTarget: "mini.example.ts.net", isOnline: true)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let detached = RemoteSession(
        id: UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!,
        state: .detached,
        started: Date(timeIntervalSince1970: 1_800_000_000 - 7_200),
        directory: "/Users/dev/src/app"
    )

    private func rows(_ status: TailscaleStatus?, _ states: [String: RemoteHostsStore.PeerState] = [:], openHere: Set<UUID> = []) -> [RemoteHostsPaletteEntry] {
        var snapshot = RemoteHostsStore.Snapshot()
        snapshot.status = status
        snapshot.peerStates = states
        return RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { openHere.contains($0.sessionID) }, now: now)
    }

    private func only(_ status: TailscaleStatus?, _ states: [String: RemoteHostsStore.PeerState] = [:]) throws -> RemoteHostsPaletteEntry {
        let all = rows(status, states).filter { $0.id != "hosts:refresh" }
        try #require(all.count == 1)
        return all[0]
    }

    @Test func everyTailscaleStateHasItsOwnCopyAndChecksAgain() throws {
        let expected: [(TailscaleStatus?, String, String)] = [
            (nil, "Hosts: Looking for Your Macs", "Reading Tailscale status on this Mac"),
            (.notInstalled, "Hosts: Tailscale Is Not Installed", "Install Tailscale on this Mac and your other Macs and sign in to the same account, then select to check again"),
            (.notRunning, "Hosts: Tailscale Is Not Running", "Open the Tailscale app on this Mac, then select to check again"),
            (.stopped, "Hosts: Tailscale Is Turned Off", "Turn Tailscale on from its menu bar item, then select to check again"),
            (.needsLogin, "Hosts: Sign In to Tailscale", "Sign in to Tailscale on this Mac, or wait for your admin to approve it, then select to check again"),
            (.starting, "Hosts: Tailscale Is Starting", "Tailscale is still connecting; select to check again in a moment"),
            (.unavailable, "Hosts: Tailscale Did Not Answer", "Tailscale timed out or sent a reply YEN cannot read; select to check again"),
            (.running(peers: []), "Hosts: No Other Macs Found", "Sign in to Tailscale with the same account on your other Macs, then select to check again"),
        ]
        for (status, title, description) in expected {
            let row = try only(status)
            #expect(row.title == title)
            #expect(row.description == description)
            #expect(row.action == .refresh)
            #expect(row.searchTags.contains("hosts"))
        }
    }

    @Test func everyPeerStateNamesThePeerAndTheNextStep() throws {
        let running = TailscaleStatus.running(peers: [mini])
        let expected: [(RemoteHostsStore.PeerState, String, String, RemoteHostsPaletteAction)] = [
            (.loading, "Hosts: Mini", "Listing the sessions on Mini", .refresh),
            (.offline, "Hosts: Mini Is Offline", "Wake Mini and connect it to Tailscale, then select to check again", .refresh),
            (.listed(.unreachable), "Hosts: Cannot Reach Mini", "Check that Mini is awake and has Remote Login on in System Settings > General > Sharing, then select to check again", .refresh),
            (.listed(.firstConnectionNeeded), "Hosts: Trust the Host Key of Mini", "YEN has not seen the host key of Mini yet. Run ssh mini.example.ts.net once in a terminal on this Mac and confirm the key; select to type the command", .insertCommand("ssh mini.example.ts.net")),
            (.listed(.keySignInNeeded), "Hosts: Set Up Key Sign-In for Mini", "Mini asked for a password, and YEN signs in only with an SSH key that needs no prompt. Run ssh-copy-id mini.example.ts.net once in a terminal on this Mac; select to type the command", .insertCommand("ssh-copy-id mini.example.ts.net")),
            (.listed(.tailscaleCheckNeeded), "Hosts: Approve Mini in Tailscale", "Tailscale SSH on Mini asks you to approve this sign-in in a browser. Run ssh mini.example.ts.net once in a terminal on this Mac and open the link it shows; the approval lasts for your tailnet's check period. Select to type the command", .insertCommand("ssh mini.example.ts.net")),
            (.listed(.hostKeyChanged), "Hosts: Host Key of Mini Changed", "YEN will not connect: the key Mini presents no longer matches the one you trusted. If Mini was reinstalled, remove the old key with ssh-keygen -R mini.example.ts.net; otherwise someone may be intercepting the connection", .refresh),
            (.listed(.yenNotInstalled), "Hosts: YEN Is Not Installed on Mini", "Install YEN in the Applications folder on Mini, then select to check again", .refresh),
            (.listed(.yenTooOld), "Hosts: Update YEN on Mini", "Mini runs a YEN without remote sessions; update it there, then select to check again", .refresh),
            (.listed(.failed), "Hosts: Could Not List Sessions on Mini", "Run yen sessions list --host mini.example.ts.net in a terminal on this Mac to see the error; select to type the command", .insertCommand("yen sessions list --host mini.example.ts.net")),
            (.listed(.sessions([], complete: true)), "Hosts: No Sessions on Mini", "Turn on Keep Sessions Running in YEN on Mini and open a terminal there, then select to check again", .refresh),
        ]
        for (state, title, description, action) in expected {
            let row = try only(running, [mini.id: state])
            #expect(row.title == title)
            #expect(row.description == description)
            #expect(row.action == action)
            #expect(row.searchTags.contains("mini"))
        }
    }

    @Test func aRunningTailnetOffersARefreshRow() {
        let all = rows(.running(peers: [mini]), [mini.id: .offline])
        #expect(all.last?.id == "hosts:refresh")
        #expect(all.last?.title == "Hosts: Refresh Remote Sessions")
        #expect(all.last?.action == .refresh)
        #expect(rows(.stopped).allSatisfy { $0.id != "hosts:refresh" })
    }

    @Test func sessionRowsAttachOrFocusThePaneAlreadyShowingThem() throws {
        let identity = try #require(RemotePaneIdentity(peer: mini, session: detached))
        let list = RemoteHostsStore.PeerState.listed(.sessions([detached], complete: true))

        let attach = try only(.running(peers: [mini]), [mini.id: list])
        #expect(attach.title == "Hosts: ~/src/app on Mini")
        #expect(attach.subtitle == "Detached · started 2 hours ago")
        #expect(attach.description == "Attach to this session on Mini in a new tab")
        #expect(attach.leadingIcon == "network")
        #expect(attach.action == .attach(identity))

        let open = rows(.running(peers: [mini]), [mini.id: list], openHere: [detached.id]).first
        #expect(open?.subtitle == "Open in YEN · started 2 hours ago")
        #expect(open?.description == "Focus the tab attached to this session on Mini")
        #expect(open?.action == .attach(identity))
    }

    @Test func otherSessionStatesAndAnIncompleteListing() {
        let attachedElsewhere = RemoteSession(id: UUID(uuidString: "11111111-0000-4000-8000-000000000001")!, state: .attached, started: nil, directory: nil)
        let broken = RemoteSession(id: UUID(uuidString: "22222222-0000-4000-8000-000000000002")!, state: .unreachable, started: nil, directory: "/opt/work")
        let all = rows(.running(peers: [mini]), [mini.id: .listed(.sessions([attachedElsewhere, broken], complete: false))])
            .filter { $0.id != "hosts:refresh" }

        #expect(all.map(\.title) == [
            "Hosts: Session \(attachedElsewhere.id.uuidString.prefix(8)) on Mini",
            "Hosts: /opt/work on Mini",
            "Hosts: Some Sessions on Mini Could Not Be Read",
        ])
        #expect(all[0].subtitle == "Attached elsewhere")
        #expect(all[1].subtitle == "Unavailable")
        #expect(all[1].action == .refresh)
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func longPeerDirectoriesKeepTheirEnd() {
        let long = "/Volumes/Work/" + String(repeating: "deep/", count: 20) + "target"
        let shown = RemoteHostsPaletteRows.displayDirectory(long)
        #expect(shown.count == RemoteHostsPaletteRows.maxDirectoryLength)
        #expect(shown.hasPrefix("…"))
        #expect(shown.hasSuffix("/target"))
        #expect(RemoteHostsPaletteRows.displayDirectory("/Users/dev") == "~")
        #expect(RemoteHostsPaletteRows.displayDirectory("/Users/dev/a") == "~/a")
    }

    @Test func hostsRowsInvalidateTheActionCatalog() {
        func key(_ hosts: [RemoteHostsPaletteEntry]) -> TerminalCommandPaletteView.ActionCatalogInvalidationKey {
            TerminalCommandPaletteView.actionCatalogInvalidationKey(
                isPresented: true, workingDirectory: nil, isRepositoryWorkspace: false, jumpTargets: [],
                updateAction: nil, tabSidebarEnabled: false, splitPaneLabelsEnabled: false,
                hasActiveTerminalController: true, hasMultiplePanes: false, scratchpadEnabled: false,
                windowBorderEnabled: false, windowBorderScope: .window, windowBorderColorMode: .manual,
                windowBorderFocusedPalette: .aurora, windowBorderUnfocusedPalette: .aurora,
                windowBorderMatchThemeUsesManualFallback: false, windowBorderResolvedThemeName: nil,
                reduceMotion: false, differentiateWithoutColor: false, customCommands: [], hosts: hosts
            )
        }
        #expect(key(rows(nil)) != key(rows(.running(peers: [mini]), [mini.id: .offline])))
        #expect(key(rows(.stopped)) == key(rows(.stopped)))
    }

    // MARK: Hosts intent

    @Test func theHostsIntentRuleNeedsAHostsWordOfThreeLetters() {
        // "hosts" matches from three letters; the other tags only as whole
        // words, so typing "remove" or "tail" on the way to another command
        // starts nothing.
        for query in ["hosts", "Hosts: mini", "hos", "host", "remote", "ssh", "tailscale", "open ssh session", "HOSTS", "Remote mini"] {
            #expect(RemoteHostsIntent.matches(query), "\(query)")
        }
        for query in ["", " ", "h", "ho", "re", "rem", "remo", "remot", "remove", "ss", "tai", "tail", "tails", "btop", "localhost", "sshd", "tailx", "git status", "settings", "Remove Moving Wallpaper"] {
            #expect(!RemoteHostsIntent.matches(query), "\(query)")
        }
    }

    @Test func withoutHostsIntentThePaletteShowsOnlyTheStaticRow() {
        var never = RemoteHostsStore.Snapshot()
        never.status = nil
        #expect(RemoteHostsPaletteRows.catalogEntries(query: "", snapshot: never, isOpenHere: { _ in false }, now: now) == [RemoteHostsPaletteRows.staticRow])
        #expect(RemoteHostsPaletteRows.catalogEntries(query: "btop", snapshot: never, isOpenHere: { _ in false }, now: now) == [RemoteHostsPaletteRows.staticRow])

        // An empty query shows only the static row even after a discovery.
        var known = RemoteHostsStore.Snapshot()
        known.status = .running(peers: [mini])
        known.peerStates = [mini.id: .listed(.sessions([detached], complete: true))]
        #expect(RemoteHostsPaletteRows.catalogEntries(query: "", snapshot: known, isOpenHere: { _ in false }, now: now) == [RemoteHostsPaletteRows.staticRow])
        #expect(RemoteHostsPaletteRows.staticRow.action == .showHosts)
        #expect(RemoteHostsPaletteRows.staticRow.title == "Hosts: Show Sessions on Your Other Macs")
    }

    @Test func aPeerNameFindsTheLastSnapshotWithoutHostsIntent() {
        var known = RemoteHostsStore.Snapshot()
        known.status = .running(peers: [mini])
        known.peerStates = [mini.id: .listed(.sessions([detached], complete: true))]
        let rows = RemoteHostsPaletteRows.catalogEntries(query: "mini", snapshot: known, isOpenHere: { _ in false }, now: now)
        #expect(rows.first == RemoteHostsPaletteRows.staticRow)
        #expect(rows.contains { $0.title == "Hosts: ~/src/app on Mini" })
    }

    // MARK: Order

    private func session(_ id: String, minutesAgo: Double?, directory: String = "/Users/dev") -> RemoteSession {
        RemoteSession(
            id: UUID(uuidString: id)!,
            state: .detached,
            started: minutesAgo.map { now.addingTimeInterval(-$0 * 60) },
            directory: directory
        )
    }

    @Test func eachMacsSessionsComeNewestFirstWithTheIDAsTieBreak() {
        let old = session("A0000000-0000-4000-8000-000000000000", minutesAgo: 120, directory: "/Users/dev/old")
        let newB = session("B0000000-0000-4000-8000-000000000000", minutesAgo: 5, directory: "/Users/dev/b")
        let newA = session("0A000000-0000-4000-8000-000000000000", minutesAgo: 5, directory: "/Users/dev/a")
        let unknown = session("C0000000-0000-4000-8000-000000000000", minutesAgo: nil, directory: "/Users/dev/unknown")
        for listed in [[old, newB, unknown, newA], [unknown, newA, old, newB], [newB, newA, unknown, old]] {
            let titles = rows(.running(peers: [mini]), [mini.id: .listed(.sessions(listed, complete: true))])
                .filter { $0.id != "hosts:refresh" }
                .map(\.title)
            #expect(titles == ["Hosts: ~/a on Mini", "Hosts: ~/b on Mini", "Hosts: ~/old on Mini", "Hosts: ~/unknown on Mini"])
        }
    }

    @Test func sessionsComeFirstThenThingsToDoThenProblemsThenRefresh() {
        func peer(_ name: String) -> TailscalePeer {
            TailscalePeer(id: "n\(name)", displayName: name, sshTarget: "\(name.lowercased()).example.ts.net", isOnline: true)
        }
        let air = peer("Air"), box = peer("Box"), cube = peer("Cube"), desk = peer("Desk"), edge = peer("Edge"), fold = peer("Fold"), gate = peer("Gate"), hub = peer("Hub")
        let one = session("A0000000-0000-4000-8000-000000000000", minutesAgo: 10, directory: "/Users/dev/one")
        let two = session("B0000000-0000-4000-8000-000000000000", minutesAgo: 10, directory: "/Users/dev/two")
        let titles = rows(.running(peers: [air, box, cube, desk, edge, fold, gate, hub]), [
            air.id: .listed(.unreachable),
            box.id: .listed(.sessions([one], complete: true)),
            cube.id: .listed(.firstConnectionNeeded),
            desk.id: .offline,
            edge.id: .listed(.yenTooOld),
            fold.id: .listed(.sessions([two], complete: true)),
            gate.id: .listed(.keySignInNeeded),
            hub.id: .listed(.tailscaleCheckNeeded),
        ]).map(\.title)
        #expect(titles == [
            "Hosts: ~/one on Box",
            "Hosts: ~/two on Fold",
            "Hosts: Trust the Host Key of Cube",
            "Hosts: Update YEN on Edge",
            "Hosts: Set Up Key Sign-In for Gate",
            "Hosts: Approve Hub in Tailscale",
            "Hosts: Cannot Reach Air",
            "Hosts: Desk Is Offline",
            "Hosts: Refresh Remote Sessions",
        ])
    }

    @Test func twoSessionsThatWouldReadTheSameShowTheirShortIDs() {
        let first = session("77F56127-69FA-4B5D-80EC-1DAF6F3F6179", minutesAgo: 35)
        let second = session("B398DB9C-E86E-472B-B59B-BDEF46CBC06D", minutesAgo: 35.5)
        let other = session("C0000000-0000-4000-8000-000000000000", minutesAgo: 90, directory: "/Users/dev/src")
        let all = rows(.running(peers: [mini]), [mini.id: .listed(.sessions([first, second, other], complete: true))])
            .filter { $0.id != "hosts:refresh" }
        #expect(all.map(\.title) == ["Hosts: ~ on Mini", "Hosts: ~ on Mini", "Hosts: ~/src on Mini"])
        #expect(all.map(\.subtitle) == [
            "Detached · started 35 minutes ago · 77F56127",
            "Detached · started 35 minutes ago · B398DB9C",
            "Detached · started 1 hour ago",
        ])
    }

    @Test func thePaletteKeepsTheHostsOrderAndEveryOtherRowKeepsItsRank() {
        func peer(_ name: String) -> TailscalePeer {
            TailscalePeer(id: "n\(name)", displayName: name, sshTarget: "\(name.lowercased()).example.ts.net", isOnline: true)
        }
        let air = peer("Air"), mac = peer("Mac")
        let one = session("A0000000-0000-4000-8000-000000000000", minutesAgo: 10, directory: "/Users/dev/one")
        let hosts = rows(.running(peers: [air, mac]), [air.id: .listed(.unreachable), mac.id: .listed(.sessions([one], complete: true))])
        let others = [
            TerminalCommandPaletteActionSearchDescriptor(id: "a", title: "Aardvark", subtitle: nil, description: nil, searchTags: ["hosts"]),
            TerminalCommandPaletteActionSearchDescriptor(id: "h", title: "Hosts Map", subtitle: nil, description: nil, searchTags: ["hosts"]),
            TerminalCommandPaletteActionSearchDescriptor(id: "z", title: "Zebra", subtitle: nil, description: nil, searchTags: ["hosts"]),
        ]
        let hostsDescriptors = TerminalCommandPaletteView.hostsSearchDescriptors(hosts)
        let ranked = TerminalCommandPaletteSearchEngine.immediateResults(query: "hosts", context: .empty, actions: others + hostsDescriptors)
        let ids = ranked.compactMap { result -> String? in
            if case .action(let id) = result.execution { return id }
            return nil
        }
        // The Hosts rows keep the shared order: sessions, problems, Refresh.
        #expect(ids.filter { $0.hasPrefix("hosts:") } == hosts.map(\.id))
        // Every other row ranks where it would without any Hosts row.
        let alone = TerminalCommandPaletteSearchEngine.immediateResults(query: "hosts", context: .empty, actions: others)
        #expect(ids.filter { !$0.hasPrefix("hosts:") } == alone.compactMap { result -> String? in
            if case .action(let id) = result.execution { return id }
            return nil
        })
        // And relative to the Hosts block it stays where its title puts it.
        #expect(ids.first == "a")
        #expect(ids.last == "z")
        #expect(ids.firstIndex(of: "h")! < ids.firstIndex(where: { $0.hasPrefix("hosts:") })!)
    }

    @Test func hostsIntentShowsTheFullRowsInsteadOfTheStaticRow() {
        var known = RemoteHostsStore.Snapshot()
        known.status = .stopped
        let rows = RemoteHostsPaletteRows.catalogEntries(query: "hosts", snapshot: known, isOpenHere: { _ in false }, now: now)
        #expect(rows.map(\.title) == ["Hosts: Tailscale Is Turned Off"])
    }
}
