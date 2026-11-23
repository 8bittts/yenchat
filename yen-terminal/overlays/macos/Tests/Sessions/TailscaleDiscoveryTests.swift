import Foundation
import Testing
@testable import YEN

struct TailscaleDiscoveryTests {
    /// Shaped like `tailscale status --json` (ipnstate.Status): Peer is keyed by
    /// node key, User by numeric user id, and DNS names end with a dot. Every
    /// peer is a full client with a peer API, so each is kept or dropped by the
    /// rule its test names (TailscaleEmbeddedNodeTests covers the peer API).
    private static let running = #"""
    {
      "Version": "1.90.0",
      "BackendState": "Running",
      "Self": {"ID": "nSelf", "HostName": "studio", "DNSName": "studio.example-tailnet.ts.net.", "OS": "macOS",
               "UserID": 1001, "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"], "Online": true},
      "Peer": {
        "nodekey:01": {"ID": "nMini", "HostName": "Mini", "DNSName": "mini.example-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.2", "fd7a:115c:a1e0::2"], "Online": true},
        "nodekey:02": {"ID": "nLinux", "HostName": "server", "DNSName": "server.example-tailnet.ts.net.", "OS": "linux", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.3"], "Online": true},
        "nodekey:03": {"ID": "nPhone", "HostName": "phone", "DNSName": "phone.example-tailnet.ts.net.", "OS": "iOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.4"], "Online": true},
        "nodekey:04": {"ID": "nOther", "HostName": "colleague", "DNSName": "colleague.example-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 2002, "TailscaleIPs": ["100.64.0.5"], "Online": true},
        "nodekey:05": {"ID": "nShared", "HostName": "shared-in", "DNSName": "shared-in.other-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.6"], "Online": true, "ShareeNode": true},
        "nodekey:06": {"ID": "nExpired", "HostName": "old-laptop", "DNSName": "old-laptop.example-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.7"], "Online": false, "Expired": true,
                       "KeyExpiry": "2026-01-01T00:00:00Z"},
        "nodekey:07": {"ID": "nNoDNS", "HostName": "air", "DNSName": "", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.8"], "Online": false},
        "nodekey:08": {"ID": "nHostile", "HostName": "evil\u001b]0;pwned\u0007\nname\u200b", "DNSName": "-oProxyCommand=sh.",
                       "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"], "UserID": 1001, "TailscaleIPs": ["100.64.0.9;id", "fd7a:115c:a1e0::9"], "Online": true},
        "nodekey:09": {"ID": "nUnusable", "HostName": "nothing", "DNSName": "a b.example-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["-x", "$(id)"], "Online": true},
        "nodekey:10": {"ID": "nSelf", "HostName": "studio-again", "DNSName": "studio.example-tailnet.ts.net.", "OS": "macOS", "PeerAPIURL": ["http://100.64.0.250:60000"],
                       "UserID": 1001, "TailscaleIPs": ["100.64.0.1"], "Online": true}
      },
      "User": {"1001": {"ID": 1001, "LoginName": "dev@example.com", "DisplayName": "Dev"},
               "2002": {"ID": 2002, "LoginName": "colleague@example.com", "DisplayName": "Colleague"}},
      "CurrentTailnet": {"Name": "example-tailnet", "MagicDNSSuffix": "example-tailnet.ts.net", "MagicDNSEnabled": true}
    }
    """#

    private func parse(_ json: String) -> TailscaleStatus? {
        TailscaleDiscovery.parseStatus(Data(json.utf8))
    }

    @Test func keepsOnlyTheSameUsersUnexpiredMacs() throws {
        guard case .running(let peers) = parse(Self.running) else {
            Issue.record("expected a running status")
            return
        }
        #expect(peers.map(\.id) == ["nNoDNS", "nHostile", "nMini"])
        let mini = try #require(peers.first { $0.id == "nMini" })
        #expect(mini == TailscalePeer(id: "nMini", displayName: "Mini", sshTarget: "mini.example-tailnet.ts.net", isOnline: true))
    }

    /// `DNSName` is filled from the netmap whether or not MagicDNS is on, but
    /// the name resolves only when `CurrentTailnet.MagicDNSEnabled` is true.
    @Test func usesTailscaleIPsWhenMagicDNSIsOff() throws {
        let off = Self.running.replacingOccurrences(of: #""MagicDNSEnabled": true"#, with: #""MagicDNSEnabled": false"#)
        let absent = Self.running.replacingOccurrences(
            of: #""CurrentTailnet": {"Name": "example-tailnet", "MagicDNSSuffix": "example-tailnet.ts.net", "MagicDNSEnabled": true}"#,
            with: #""CurrentTailnet": null"#
        )
        #expect(off != Self.running && absent != Self.running)
        for json in [off, absent] {
            guard case .running(let peers) = parse(json) else {
                Issue.record("expected a running status")
                return
            }
            #expect(peers.map(\.sshTarget) == ["100.64.0.8", "fd7a:115c:a1e0::9", "100.64.0.2"])
            #expect(peers.map(\.displayName) == ["air", "evil ]0;pwned name", "Mini"])
        }
    }

    @Test func fallsBackToTheFirstTailscaleIPWithoutAMagicDNSName() throws {
        guard case .running(let peers) = parse(Self.running) else {
            Issue.record("expected a running status")
            return
        }
        let air = try #require(peers.first { $0.id == "nNoDNS" })
        #expect(air.sshTarget == "100.64.0.8")
        #expect(air.displayName == "air")
        #expect(!air.isOnline)
    }

    @Test func hostileNamesNeverReachSSHOrALabel() throws {
        guard case .running(let peers) = parse(Self.running) else {
            Issue.record("expected a running status")
            return
        }
        let hostile = try #require(peers.first { $0.id == "nHostile" })
        // The dash-led DNS name and the IP with a metacharacter are skipped.
        #expect(hostile.sshTarget == "fd7a:115c:a1e0::9")
        #expect(hostile.displayName == "evil ]0;pwned name")
        for peer in peers {
            #expect(RemoteSessions.isValidTarget(peer.sshTarget))
            #expect(!peer.displayName.unicodeScalars.contains { $0.properties.generalCategory == .control })
        }
        #expect(!peers.contains { $0.id == "nUnusable" })
    }

    @Test func runningWithNoPeersListsNone() {
        #expect(parse(#"{"BackendState": "Running", "Self": {"ID": "nSelf", "UserID": 1, "OS": "macOS"}, "Peer": null}"#)
            == .running(peers: []))
        #expect(parse(#"{"BackendState": "Running", "Self": {"ID": "nSelf", "UserID": 1, "OS": "macOS"}}"#)
            == .running(peers: []))
    }

    @Test func backendStatesAreNormalStates() {
        #expect(parse(#"{"BackendState": "Stopped", "Self": {"ID": "nSelf", "UserID": 1}, "Peer": null}"#) == .stopped)
        #expect(parse(#"{"BackendState": "NeedsLogin", "Self": null}"#) == .needsLogin)
        #expect(parse(#"{"BackendState": "NeedsMachineAuth"}"#) == .needsLogin)
        #expect(parse(#"{"BackendState": "Starting"}"#) == .starting)
        #expect(parse(#"{"BackendState": "NoState"}"#) == .notRunning)
        #expect(parse(#"{"BackendState": "SomethingNew"}"#) == .unavailable)
    }

    @Test func outputThatIsNotStatusJSONIsNotParsed() {
        #expect(parse("") == nil)
        #expect(parse("Tailscale is stopped.") == nil)
        #expect(parse(#"{"Version": "1.90.0"}"#) == nil)
        #expect(parse(#"["Running"]"#) == nil)
    }

    @Test func mapsProcessOutcomes() {
        let empty = Data()
        #expect(TailscaleDiscovery.status(from: .init(status: 1, stdout: empty, timedOut: false)) == .notRunning)
        #expect(TailscaleDiscovery.status(from: .init(status: nil, stdout: empty, timedOut: false)) == .notRunning)
        #expect(TailscaleDiscovery.status(from: .init(status: 0, stdout: Data("garbage".utf8), timedOut: false)) == .unavailable)
        #expect(TailscaleDiscovery.status(from: .init(status: nil, stdout: empty, timedOut: true)) == .unavailable)
        let stopped = Data(#"{"BackendState": "Stopped"}"#.utf8)
        #expect(TailscaleDiscovery.status(from: .init(status: 0, stdout: stopped, timedOut: false)) == .stopped)
    }

    @Test func locatesTheCLI() {
        let all: (String) -> Bool = { _ in true }
        let none: (String) -> Bool = { _ in false }
        #expect(TailscaleDiscovery.cliPath(environment: [:], isExecutable: all) == TailscaleDiscovery.appExecutable)
        #expect(TailscaleDiscovery.cliPath(environment: [:], isExecutable: { $0 == "/opt/homebrew/bin/tailscale" })
            == "/opt/homebrew/bin/tailscale")
        #expect(TailscaleDiscovery.cliPath(environment: [:], isExecutable: none) == nil)
        let hook = [TailscaleDiscovery.binaryEnvironmentKey: "/Users/dev/fake-tailscale"]
        #expect(TailscaleDiscovery.cliPath(environment: hook, isExecutable: all) == "/Users/dev/fake-tailscale")
        // A hook that points nowhere never falls back to a real install.
        #expect(TailscaleDiscovery.cliPath(environment: hook, isExecutable: { $0 != "/Users/dev/fake-tailscale" }) == nil)
    }

    @Test func notInstalledWithoutACLI() async {
        let status = await TailscaleDiscovery.status(
            environment: [TailscaleDiscovery.binaryEnvironmentKey: "/nonexistent/tailscale"]
        )
        #expect(status == .notInstalled)
    }

    @Test func runsTheCLIAsACLIWithoutZmxVariables() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-tailscale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("status.json")
        try Self.running.write(to: fixture, atomically: true, encoding: .utf8)
        let script = directory.appendingPathComponent("tailscale")
        try """
        #!/bin/bash
        [[ "$*" == "status --json" && "$TAILSCALE_BE_CLI" == 1 && -z "${ZMX_SESSION:-}" ]] || exit 3
        cat '\(fixture.path)'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let status = await TailscaleDiscovery.status(environment: [
            TailscaleDiscovery.binaryEnvironmentKey: script.path,
            "ZMX_SESSION": "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C",
            "PATH": "/usr/bin:/bin",
        ])
        guard case .running(let peers) = status else {
            Issue.record("expected a running status, got \(status)")
            return
        }
        #expect(peers.count == 3)
    }
}
