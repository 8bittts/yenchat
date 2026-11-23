import Foundation
import Testing
@testable import YEN

// Tailscale discovery and helper processes, for what TailscaleDiscoveryTests
// and RemoteSessionsTests leave open (_docs/01-architecture.md -> Remote
// attach), and the reaper reading a listing made under an inherited
// ZMX_SESSION.

private func script(_ body: String) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("yen-contract-\(UUID().uuidString)")
    try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

struct RemoteDiscoveryContractTests {
    private static func status(_ peers: String, magicDNS: Bool = true) -> String {
        """
        {"BackendState": "Running",
         "Self": {"ID": "nSelf", "HostName": "studio", "OS": "macOS", "UserID": 1},
         "Peer": {\(peers)},
         "CurrentTailnet": {"MagicDNSEnabled": \(magicDNS)}}
        """
    }

    private static func node(_ id: String, hostName: String, dnsName: String) -> String {
        """
        "nodekey:\(id)": {"ID": "\(id)", "HostName": "\(hostName)", "DNSName": "\(dnsName)", "OS": "macOS",
                          "UserID": 1, "TailscaleIPs": ["100.64.0.2"], "Online": true,
                          "PeerAPIURL": ["http://100.64.0.2:60000"]}
        """
    }

    /// An app launched from a persistent pane inherits its ZMX_SESSION, and
    /// the vendored `zmx ls` then marks that session's row with an arrow
    /// instead of two spaces (measured; tests/179 runs the real zmx). The
    /// reaper must read it like any other row, or it would never end it.
    @Test func theReaperReadsTheRowZmxMarksAsTheCurrentSession() {
        let output = [
            "  name=0B1C2D3E-0A4E-4F5A-9B8C-1D2E3F4A5B6C\tpid=41\tclients=0\tcreated=1795399610\tcwd=file://mac/Users/dev",
            "\u{2192} name=1C2D3E4F-0A4E-4F5A-9B8C-1D2E3F4A5B6C\tpid=42\tclients=1\tcreated=1795399611\tcwd=file://mac/Users/dev",
            "",
        ].joined(separator: "\n")
        #expect(PersistentSessionReaper.parseList(output) == [
            PersistentSessionReaper.Session(name: "0B1C2D3E-0A4E-4F5A-9B8C-1D2E3F4A5B6C", clients: 0),
            PersistentSessionReaper.Session(name: "1C2D3E4F-0A4E-4F5A-9B8C-1D2E3F4A5B6C", clients: 1),
        ])
    }

    @Test func aBackendInUseByAnotherUserIsNotRunning() {
        #expect(TailscaleDiscovery.parseStatus(Data(#"{"BackendState": "InUseOtherUser"}"#.utf8)) == .notRunning)
    }

    @Test func aLabelIsAtMost63CharactersAndFallsBackToTheTargetsFirstName() throws {
        let long = String(repeating: "w", count: 100)
        let json = Self.status([
            Self.node("nLong", hostName: long, dnsName: "long.example.ts.net."),
            Self.node("nBlank", hostName: "", dnsName: "mini.example.ts.net."),
        ].joined(separator: ","))
        guard case .running(let peers) = TailscaleDiscovery.parseStatus(Data(json.utf8)) else {
            Issue.record("expected a running status")
            return
        }
        let longPeer = try #require(peers.first { $0.id == "nLong" })
        #expect(longPeer.displayName == String(repeating: "w", count: 63))
        let blank = try #require(peers.first { $0.id == "nBlank" })
        #expect(blank.displayName == "mini")
        #expect(blank.sshTarget == "mini.example.ts.net")
    }

    /// The Tailscale CLI gets five seconds, then the status is unavailable.
    @Test func aTailscaleCLIThatHangsIsUnavailableAfterFiveSeconds() async throws {
        let cli = try script("sleep 20")
        defer { try? FileManager.default.removeItem(atPath: cli) }
        let started = Date()
        let status = await TailscaleDiscovery.status(environment: [
            TailscaleDiscovery.binaryEnvironmentKey: cli, "PATH": "/usr/bin:/bin",
        ])
        let elapsed = Date().timeIntervalSince(started)
        #expect(status == .unavailable)
        #expect(elapsed > 4.5 && elapsed < 9, "\(elapsed)")
    }

    /// A helper that ignores SIGTERM is killed, so the listing still ends.
    @Test func aHelperThatIgnoresTermIsKilledAtTheDeadline() async throws {
        let cli = try script("trap '' TERM\nsleep 20")
        defer { try? FileManager.default.removeItem(atPath: cli) }
        let started = Date()
        let result = await RemoteSessions.list(host: "mini", cliPath: cli, environment: [:], timeout: .milliseconds(300))
        #expect(result == .unreachable)
        #expect(Date().timeIntervalSince(started) < 4)
    }

    /// A CLI that cannot start is a failure of this Mac, not an unreachable peer.
    @Test func aCLIThatCannotStartFails() async {
        #expect(await RemoteSessions.list(host: "mini", cliPath: "/etc/hosts", environment: [:]) == .failed)
    }
}


// MARK: - Which peers are Macs to attach to

/// Shaped like `tailscale status --json` from the Tailscale 1.104 Mac app: a
/// real client carries its peer API addresses and is a Taildrop target (1, or
/// 5 while offline), while a node another app embeds (tsnet) reports no peer
/// API (`TaildropTarget` 8, `TaildropTargetNoPeerAPI`). Names, keys and
/// addresses are invented.
struct TailscaleEmbeddedNodeTests {
    private static func peer(
        _ id: String, hostName: String, ip: String, online: Bool,
        peerAPI: String, taildrop: Int, capabilities: String = "[]"
    ) -> String {
        """
        "nodekey:\(id)": {
          "ID": "\(id)", "PublicKey": "nodekey:\(id)", "HostName": "\(hostName)",
          "DNSName": "\(hostName).example-tailnet.ts.net.", "OS": "macOS", "UserID": 4242,
          "TailscaleIPs": ["\(ip)", "fd7a:115c:a1e0::\(ip.split(separator: ".").last ?? "1")"],
          "AllowedIPs": ["\(ip)/32"], "Addrs": null, "CurAddr": "", "Relay": "sfo", "PeerRelay": "",
          "RxBytes": 0, "TxBytes": 0, "Created": "2026-10-01T00:00:00Z", "LastWrite": "0001-01-01T00:00:00Z",
          "LastSeen": "2026-11-20T00:00:00Z", "LastHandshake": "0001-01-01T00:00:00Z",
          "Online": \(online), "ExitNode": false, "ExitNodeOption": false, "Active": false,
          \(peerAPI)"InNetworkMap": true, "InMagicSock": true, "InEngine": false,
          "TaildropTarget": \(taildrop), "NoFileSharingReason": "", "Capabilities": \(capabilities),
          "KeyExpiry": "2027-05-01T00:00:00Z"
        }
        """
    }

    private static let realMac = peer(
        "nMini", hostName: "mini", ip: "100.64.0.2", online: true,
        peerAPI: #""PeerAPIURL": ["http://100.64.0.2:60123", "http://[fd7a:115c:a1e0::2]:60123"], "#,
        taildrop: 1, capabilities: #"["https://tailscale.com/cap/file-sharing", "https://tailscale.com/cap/ssh"]"#
    )
    private static let offlineMac = peer(
        "nAir", hostName: "air", ip: "100.64.0.3", online: false,
        peerAPI: #""PeerAPIURL": ["http://100.64.0.3:60124", "http://[fd7a:115c:a1e0::3]:60124"], "#,
        taildrop: 5, capabilities: #"["https://tailscale.com/cap/file-sharing"]"#
    )
    /// Embedded by an app on another Mac: no PeerAPIURL at all.
    private static let embeddedElsewhere = peer(
        "nBuildRex", hostName: "build-rex", ip: "100.64.0.4", online: true, peerAPI: "", taildrop: 8
    )
    /// Embedded by an app on this very Mac: an empty PeerAPIURL.
    private static let embeddedHere = peer(
        "nStudioRex", hostName: "studio-rex", ip: "100.64.0.5", online: true,
        peerAPI: #""PeerAPIURL": [], "#, taildrop: 8
    )

    /// Every top-level key the real output has, with plausible values.
    private static func status(_ peers: [String]) -> Data {
        Data("""
        {
          "Version": "1.104.7-t0000000-g0000000", "TUN": true, "BackendState": "Running",
          "HaveNodeKey": true, "AuthURL": "", "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
          "Self": {
            "ID": "nStudio", "PublicKey": "nodekey:nStudio", "HostName": "studio",
            "DNSName": "studio.example-tailnet.ts.net.", "OS": "macOS", "UserID": 4242,
            "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"], "Online": true,
            "PeerAPIURL": ["http://100.64.0.1:60125"], "Capabilities": ["https://tailscale.com/cap/file-sharing"],
            "CapMap": {"https://tailscale.com/cap/file-sharing": null}, "InNetworkMap": true
          },
          "Health": ["Some health warning text"],
          "MagicDNSSuffix": "example-tailnet.ts.net",
          "CurrentTailnet": {"Name": "dev@example.com", "MagicDNSSuffix": "example-tailnet.ts.net", "MagicDNSEnabled": true},
          "CertDomains": ["studio.example-tailnet.ts.net"],
          "Peer": {\(peers.joined(separator: ","))},
          "User": {"4242": {"ID": 4242, "LoginName": "dev@example.com", "DisplayName": "Dev", "ProfilePicURL": ""}},
          "ClientVersion": {"RunningLatest": true},
          "ExtraRecords": null
        }
        """.utf8)
    }

    private func peers(_ json: Data) -> [TailscalePeer]? {
        guard case .running(let peers) = TailscaleDiscovery.parseStatus(json) else { return nil }
        return peers
    }

    @Test func theFullRealShapeParses() throws {
        let listed = try #require(peers(Self.status([Self.realMac])))
        #expect(listed == [TailscalePeer(id: "nMini", displayName: "mini", sshTarget: "mini.example-tailnet.ts.net", isOnline: true)])
    }

    @Test func aNodeAnotherAppEmbedsIsNotListed() throws {
        let listed = try #require(peers(Self.status([Self.realMac, Self.embeddedElsewhere, Self.embeddedHere])))
        #expect(listed.map(\.id) == ["nMini"])
    }

    @Test func aRealMacThatIsOfflineStillShowsAsOffline() throws {
        let listed = try #require(peers(Self.status([Self.offlineMac, Self.embeddedElsewhere])))
        #expect(listed == [TailscalePeer(id: "nAir", displayName: "air", sshTarget: "air.example-tailnet.ts.net", isOnline: false)])
    }

    /// An embedded node keeps no peer API while offline either, because
    /// Tailscale reads it from the node's Hostinfo services, which it never had.
    @Test func anOfflineEmbeddedNodeIsNotListedEither() throws {
        let offlineEmbedded = Self.peer(
            "nOldRex", hostName: "old-rex", ip: "100.64.0.6", online: false, peerAPI: "", taildrop: 5
        )
        let listed = try #require(peers(Self.status([Self.offlineMac, offlineEmbedded])))
        #expect(listed.map(\.id) == ["nAir"])
    }

    @Test func aTailnetOfOnlyEmbeddedNodesFindsNoOtherMacs() throws {
        let status = TailscaleDiscovery.parseStatus(Self.status([Self.embeddedElsewhere, Self.embeddedHere]))
        #expect(status == .running(peers: []))
        var snapshot = RemoteHostsStore.Snapshot()
        snapshot.status = status
        let rows = RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { _ in false })
        #expect(rows.map(\.title) == ["Hosts: No Other Macs Found"])
    }
}

// MARK: - Which ssh target a peer gets

/// Records each name discovery resolves and answers from a fixed table.
private actor FakeResolver {
    private(set) var asked: [String] = []
    private let answers: [String: [String]]
    private let hang: Bool

    init(_ answers: [String: [String]] = [:], hang: Bool = false) {
        self.answers = answers
        self.hang = hang
    }

    func resolve(_ name: String) async -> [String] {
        asked.append(name)
        if hang { try? await Task.sleep(for: .seconds(30)) }
        return answers[name] ?? []
    }

    nonisolated var resolver: TailscaleDiscovery.Resolver { { await self.resolve($0) } }
}

/// `CurrentTailnet.MagicDNSEnabled` is the tailnet's setting, not this Mac's:
/// with "Use Tailscale DNS settings" off in the Tailscale app (`CorpDNS:
/// false`) it still reads true and every peer keeps its `DNSName`, but the
/// name does not resolve here. A name is the ssh target only when it
/// resolves on this Mac to one of that peer's own `TailscaleIPs`.
@Suite(.serialized)
struct TailscaleNameResolutionTests {
    private static func node(_ id: String, name: String, ips: [String], online: Bool = true) -> String {
        let quoted = ips.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        "nodekey:\(id)": {"ID": "\(id)", "HostName": "\(name)", "DNSName": "\(name).example-tailnet.ts.net.",
          "OS": "macOS", "UserID": 4242, "TailscaleIPs": [\(quoted)], "Online": \(online),
          "PeerAPIURL": ["http://100.64.0.250:60000"]}
        """
    }

    private static let mini = node("nMini", name: "mini", ips: ["100.64.0.2", "fd7a:115c:a1e0::2"])

    /// A Tailscale CLI that prints a status with these peers and MagicDNS on.
    private func discover(_ peers: [String], _ fake: FakeResolver, deadline: Duration = .seconds(1)) async throws -> [TailscalePeer] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yen-dns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {"BackendState": "Running", "Self": {"ID": "nSelf", "HostName": "studio", "OS": "macOS", "UserID": 4242},
         "Peer": {\(peers.joined(separator: ","))},
         "MagicDNSSuffix": "example-tailnet.ts.net",
         "CurrentTailnet": {"Name": "dev@example.com", "MagicDNSSuffix": "example-tailnet.ts.net", "MagicDNSEnabled": true}}
        """
        let fixture = directory.appendingPathComponent("status.json")
        try json.write(to: fixture, atomically: true, encoding: .utf8)
        let cli = directory.appendingPathComponent("tailscale")
        try "#!/bin/bash\ncat '\(fixture.path)'\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let status = await TailscaleDiscovery.status(
            environment: [TailscaleDiscovery.binaryEnvironmentKey: cli.path, "PATH": "/usr/bin:/bin"],
            resolve: fake.resolver, resolveTimeout: deadline
        )
        guard case .running(let listed) = status else {
            Issue.record("expected a running status, got \(status)")
            return []
        }
        return listed
    }

    @Test func aNameThatDoesNotResolveUsesTheTailscaleIP() async throws {
        let fake = FakeResolver()
        let peers = try await discover([Self.mini], fake)
        #expect(peers == [TailscalePeer(id: "nMini", displayName: "mini", sshTarget: "100.64.0.2", isOnline: true)])
        #expect(await fake.asked == ["mini.example-tailnet.ts.net"])
    }

    @Test func aNameThatResolvesToAnotherAddressUsesTheTailscaleIP() async throws {
        let fake = FakeResolver(["mini.example-tailnet.ts.net": ["203.0.113.7", "2001:db8::7"]])
        let peers = try await discover([Self.mini], fake)
        #expect(peers.map(\.sshTarget) == ["100.64.0.2"])
    }

    @Test func aNameThatResolvesToThePeersOwnAddressIsKept() async throws {
        for answer in [["100.64.0.2"], ["fd7a:115c:a1e0:0:0:0:0:2"], ["203.0.113.7", "fd7a:115c:a1e0::2"]] {
            let fake = FakeResolver(["mini.example-tailnet.ts.net": answer])
            let peers = try await discover([Self.mini], fake)
            #expect(peers.map(\.sshTarget) == ["mini.example-tailnet.ts.net"], "\(answer)")
        }
    }

    @Test func aResolverThatHangsFallsBackToTheIPWithinItsDeadline() async throws {
        let others = (3...6).map { Self.node("nMac\($0)", name: "mac-\($0)", ips: ["100.64.0.\($0)"]) }
        let fake = FakeResolver(hang: true)
        let started = Date()
        let peers = try await discover([Self.mini] + others, fake, deadline: .milliseconds(400))
        let elapsed = Date().timeIntervalSince(started)
        #expect(peers.count == 5)
        #expect(peers.allSatisfy { $0.sshTarget.hasPrefix("100.64.0.") })
        // Names resolve in parallel: five hung names cost one deadline, not five.
        #expect(elapsed < 1.6, "\(elapsed)")
    }

    @Test func aPeerWithNoValidIPAndAnUnresolvableNameIsDropped() async throws {
        let broken = Self.node("nBroken", name: "broken", ips: ["-x", "$(id)"])
        let peers = try await discover([Self.mini, broken], FakeResolver())
        #expect(peers.map(\.id) == ["nMini"])
    }

    @Test func offlinePeersAreNotResolved() async throws {
        let air = Self.node("nAir", name: "air", ips: ["100.64.0.3"], online: false)
        let fake = FakeResolver(["mini.example-tailnet.ts.net": ["100.64.0.2"], "air.example-tailnet.ts.net": ["100.64.0.3"]])
        let peers = try await discover([Self.mini, air], fake)
        #expect(await fake.asked == ["mini.example-tailnet.ts.net"])
        #expect(peers.first { $0.id == "nAir" }?.sshTarget == "100.64.0.3")
        #expect(peers.first { $0.id == "nMini" }?.sshTarget == "mini.example-tailnet.ts.net")
    }

    /// With the IP as target, a Mac whose key is trusted only under its name
    /// lists as a first connection, named by its host name, never as unreachable.
    @Test func anIPTargetIsLabeledByItsHostNameAndOffersSSHToTheIP() {
        let peer = TailscalePeer(id: "nMini", displayName: "mini", sshTarget: "100.64.0.2", isOnline: true)
        let rows = RemoteHostsPaletteRows.peerRows(peer, state: .listed(.firstConnectionNeeded), isOpenHere: { _ in false }, now: Date())
        #expect(rows.map(\.title) == ["Hosts: Trust the Host Key of mini"])
        #expect(rows.first?.action == .insertCommand("ssh 100.64.0.2"))
        #expect(!rows.contains { $0.title.contains("Cannot Reach") })
    }
}
