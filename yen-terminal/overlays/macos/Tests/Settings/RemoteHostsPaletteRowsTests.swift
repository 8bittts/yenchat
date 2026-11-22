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
            (.listed(.firstConnectionNeeded), "Hosts: Connect to Mini Once", "Run ssh mini.example.ts.net once in a terminal on this Mac to trust its host key and sign in; select to type the command", .insertCommand("ssh mini.example.ts.net")),
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
        let attachedElsewhere = RemoteSession(id: UUID(), state: .attached, started: nil, directory: nil)
        let broken = RemoteSession(id: UUID(), state: .unreachable, started: nil, directory: "/opt/work")
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
}
