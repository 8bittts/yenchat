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
                          "UserID": 1, "TailscaleIPs": ["100.64.0.2"], "Online": true}
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

