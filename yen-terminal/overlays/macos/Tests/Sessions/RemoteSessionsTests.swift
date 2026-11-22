import Foundation
import Testing
@testable import YEN

struct RemoteSessionsTests {
    private let first = UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!
    private let second = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test func parsesVersionOnePorcelain() throws {
        let text = [
            "yen-sessions\t1",
            "\(first.uuidString)\tdetached\t1795380150\t/Users/dev/project",
            "\(second.uuidString.lowercased())\tattached\t-\t-\tfield-from-a-later-version",
            "",
        ].joined(separator: "\n")
        let parsed = try #require(RemoteSessions.parsePorcelain(text))
        #expect(parsed.dropped == 0)
        #expect(parsed.sessions == [
            RemoteSession(id: first, state: .detached, started: Date(timeIntervalSince1970: 1_795_380_150), directory: "/Users/dev/project"),
            RemoteSession(id: second, state: .attached, started: nil, directory: nil),
        ])
    }

    @Test func dropsRowsThatDoNotParse() throws {
        let rows = [
            "not-a-uuid\tdetached\t1\t/x",
            "\(first.uuidString)\trunning\t1\t/x",
            "\(first.uuidString)\tdetached\tsoon\t/x",
            "\(first.uuidString)\tdetached\t1",
            "\(first.uuidString)\tdetached\t1\t",
            "\(first.uuidString)x\tdetached\t1\t/x",
            "\(second.uuidString)\tunreachable\t-\t/Users/dev/\u{1B}]0;pwned\u{07}\u{2028}x",
        ]
        let parsed = try #require(RemoteSessions.parsePorcelain((["yen-sessions\t1"] + rows).joined(separator: "\n")))
        #expect(parsed.dropped == 6)
        #expect(parsed.sessions == [RemoteSession(id: second, state: .unreachable, started: nil, directory: "/Users/dev/?]0;pwned??x")])
    }

    @Test func refusesOutputWithoutTheVersionOneHeader() {
        #expect(RemoteSessions.parsePorcelain("") == nil)
        #expect(RemoteSessions.parsePorcelain("yen-sessions\t2\n") == nil)
        #expect(RemoteSessions.parsePorcelain("ID  STATE  STARTED  DIRECTORY\n") == nil)
        #expect(RemoteSessions.parsePorcelain("\(first.uuidString)\tdetached\t1\t/x\n") == nil)
    }

    @Test func mapsCLIExitCodesToStates() {
        let rows = Data("yen-sessions\t1\n\(first.uuidString)\tdetached\t-\t/x\n".utf8)
        let session = RemoteSession(id: first, state: .detached, started: nil, directory: "/x")
        func result(_ status: Int32?, _ stdout: Data = Data(), timedOut: Bool = false) -> RemoteSessionList {
            RemoteSessions.listResult(status: status, stdout: stdout, timedOut: timedOut)
        }
        #expect(result(0, rows) == .sessions([session], complete: true))
        #expect(result(1, rows) == .sessions([session], complete: false))
        #expect(result(0, Data("yen-sessions\t1\n".utf8)) == .sessions([], complete: true))
        #expect(result(10) == .unreachable)
        #expect(result(11) == .firstConnectionNeeded)
        #expect(result(12) == .yenNotInstalled)
        #expect(result(13) == .yenTooOld)
        #expect(result(15) == .hostKeyChanged)
        #expect(result(nil, timedOut: true) == .unreachable)
        #expect(result(nil) == .failed)
        #expect(result(2) == .failed)
        #expect(result(0, Data("garbage".utf8)) == .failed)
    }

    @Test(arguments: [
        "mini", "mini.example-tailnet.ts.net", "dev@mini", "dev.name@mini-2", "100.64.0.1", "fd7a:115c:a1e0::1",
        "fd7a:115c:a1e0:0:0:0:0:1",
    ])
    func acceptsTargets(_ target: String) {
        #expect(RemoteSessions.isValidTarget(target))
        #expect(RemoteSessions.listArguments(host: target) == ["sessions", "list", "--host", target, "--porcelain"])
    }

    @Test(arguments: [
        "", "-oProxyCommand=sh", "-p", "mini -oProxyCommand=sh", "mini;id", "$(id)", "`id`", "mini\nother",
        "user@-oProxyCommand=sh", "-user@mini", "mini.", "mini..ts.net", "mini_host", "ünicode", "@mini",
        String(repeating: "a", count: 254), "fd7a:115c:a1e0::1;id",
    ])
    func refusesTargets(_ target: String) {
        #expect(!RemoteSessions.isValidTarget(target))
        #expect(RemoteSessions.listArguments(host: target) == nil)
        #expect(RemoteSessions.attachArguments(host: target, id: first) == nil)
    }

    @Test func attachCommandQuotesTheBundledCLIPath() {
        let line = RemoteSessions.attachCommandLine(host: "mini", id: first, cliPath: "/Applications/YEN's copy.app/Contents/Resources/bin/yen")
        #expect(line == "'/Applications/YEN'\\''s copy.app/Contents/Resources/bin/yen' 'sessions' 'attach' '--host' 'mini' '\(first.uuidString)'")
        #expect(RemoteSessions.attachCommandLine(host: "-oProxyCommand=sh", id: first, cliPath: "/x/yen") == nil)
    }

    /// The listing runs the CLI it is given and reads its porcelain.
    @Test func listsThroughTheCLI() async throws {
        let cli = try script("""
        [[ "$*" == "sessions list --host mini --porcelain" && -z "${ZMX_SESSION:-}" ]] || exit 99
        printf 'yen-sessions\\t1\\n\(first.uuidString)\\tdetached\\t-\\t/Users/dev\\n'
        """)
        defer { try? FileManager.default.removeItem(atPath: cli) }
        let result = await RemoteSessions.list(
            host: "mini", cliPath: cli, environment: ["ZMX_SESSION": second.uuidString, "PATH": "/usr/bin:/bin"]
        )
        #expect(result == .sessions([RemoteSession(id: first, state: .detached, started: nil, directory: "/Users/dev")], complete: true))
    }

    @Test func aHostTheCLICannotReachIsUnreachable() async throws {
        let cli = try script("exit 10")
        defer { try? FileManager.default.removeItem(atPath: cli) }
        #expect(await RemoteSessions.list(host: "mini", cliPath: cli, environment: [:]) == .unreachable)
    }

    /// A hung ssh under the CLI must not hang the listing, even while it still
    /// holds the output pipe.
    @Test func aListingPastItsDeadlineIsUnreachable() async throws {
        let cli = try script("sleep 20")
        defer { try? FileManager.default.removeItem(atPath: cli) }
        let started = Date()
        let result = await RemoteSessions.list(host: "mini", cliPath: cli, environment: [:], timeout: .milliseconds(300))
        #expect(result == .unreachable)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func noBundledCLIFails() async {
        #expect(await RemoteSessions.list(host: "mini", cliPath: nil) == .failed)
        #expect(RemoteSessions.cliPath(resourcePath: "/nonexistent") == nil)
    }

    private func script(_ body: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yen-remote-cli-\(UUID().uuidString)")
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
