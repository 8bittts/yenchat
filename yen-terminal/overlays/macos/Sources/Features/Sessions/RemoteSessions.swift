import Foundation

/// A persistent session on another Mac, from its `yen sessions list --porcelain`.
struct RemoteSession: Equatable, Sendable, Identifiable {
    enum State: String, Equatable, Sendable {
        case attached, detached, unreachable
    }

    let id: UUID
    let state: State
    let started: Date?
    /// The session's working directory on the peer, an absolute path, with
    /// control characters already replaced.
    let directory: String?
}

/// The outcome of listing a peer's sessions, one case per state the app shows.
enum RemoteSessionList: Equatable, Sendable {
    /// `complete` is false when the peer reported a listing error or sent rows
    /// that did not parse; the sessions shown are still real.
    case sessions([RemoteSession], complete: Bool)
    /// Offline, unknown to DNS, refusing connections, or too slow to answer.
    case unreachable
    /// The host key is not known yet or no key signs in under BatchMode; the
    /// user runs `ssh <host>` once in a terminal.
    case firstConnectionNeeded
    /// The known host key no longer matches. YEN does not connect until the
    /// user fixes known_hosts.
    case hostKeyChanged
    case yenNotInstalled
    /// The peer's YEN predates remote sessions or speaks another format version.
    case yenTooOld
    /// The bundled CLI is missing, did not start, or exited in a way no case covers.
    case failed
}

/// Remote sessions over ssh, through the bundled CLI. The CLI owns the transport,
/// the reconnect loop and the exit codes (_docs/01-architecture.md -> Persistent
/// sessions -> Remote attach); the app only runs it and maps its result.
enum RemoteSessions {
    /// The first line of `yen sessions list --porcelain`.
    static let porcelainHeader = "yen-sessions\t1"

    /// `yen sessions ... --host` exit codes (yen-cli/lib/sessions-remote.sh).
    enum ExitCode {
        static let unreachable: Int32 = 10
        static let firstConnection: Int32 = 11
        static let notInstalled: Int32 = 12
        static let tooOld: Int32 = 13
        static let noSession: Int32 = 14
        static let hostKeyChanged: Int32 = 15
    }

    /// The CLI's own limit is ssh's 10-second connect timeout plus the listing.
    static let listTimeout: Duration = .seconds(25)

    /// `[user@]host`: a DNS name without a trailing dot, an IPv4 address or an
    /// IPv6 address. Mirrors `valid_remote_target` in the CLI, which checks again.
    nonisolated static func isValidTarget(_ target: String) -> Bool {
        // Printable ASCII only, checked byte-wise: a Character-based regex
        // could treat a letter with a combining mark as one letter.
        guard !target.isEmpty, target.utf8.count <= 253, !target.hasPrefix("-"),
              target.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return false }
        var host = Substring(target)
        if let at = target.lastIndex(of: "@") {
            let user = target[..<at]
            host = target[target.index(after: at)...]
            guard user.wholeMatch(of: /[A-Za-z0-9_][A-Za-z0-9._-]{0,63}/) != nil else { return false }
        }
        if host.contains(":") {
            guard host.utf8.count <= 39 else { return false }
            return (host.wholeMatch(of: /[0-9A-Fa-f:]+/) != nil && host.contains("::"))
                || host.wholeMatch(of: /([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}/) != nil
        }
        return host.wholeMatch(of: /[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*/) != nil
    }

    /// Parse porcelain output strictly. nil when the version 1 header is missing.
    /// Rows that do not parse are counted in `dropped`, never guessed at.
    nonisolated static func parsePorcelain(_ text: String) -> (sessions: [RemoteSession], dropped: Int)? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last == "" { lines.removeLast() }
        guard let first = lines.first, first == porcelainHeader else { return nil }
        var sessions: [RemoteSession] = []
        var dropped = 0
        for line in lines.dropFirst() where !line.isEmpty {
            if let session = parseRow(line) {
                sessions.append(session)
            } else {
                dropped += 1
            }
        }
        return (sessions, dropped)
    }

    nonisolated private static func parseRow(_ line: Substring) -> RemoteSession? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        // Version 1 readers ignore extra trailing fields.
        guard fields.count >= 4,
              fields[0].wholeMatch(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) != nil,
              let id = UUID(uuidString: String(fields[0])),
              let state = RemoteSession.State(rawValue: String(fields[1])),
              !fields[3].isEmpty else { return nil }
        var started: Date?
        if fields[2] != "-" {
            guard fields[2].wholeMatch(of: /[0-9]{1,12}/) != nil, let seconds = TimeInterval(fields[2]) else { return nil }
            started = Date(timeIntervalSince1970: seconds)
        }
        let directory = fields[3] == "-" ? nil : sanitized(String(fields[3]))
        return RemoteSession(id: id, state: state, started: started, directory: directory)
    }

    /// The CLI already replaces control characters; a label must not depend on it.
    nonisolated static func sanitized(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: "?"
            default: scalar
            }
        }))
    }

    nonisolated static func listResult(status: Int32?, stdout: Data, timedOut: Bool) -> RemoteSessionList {
        if timedOut { return .unreachable }
        guard let status else { return .failed }
        switch status {
        case ExitCode.unreachable: return .unreachable
        case ExitCode.firstConnection: return .firstConnectionNeeded
        case ExitCode.hostKeyChanged: return .hostKeyChanged
        case ExitCode.notInstalled: return .yenNotInstalled
        case ExitCode.tooOld: return .yenTooOld
        case 0, 1:
            guard let parsed = parsePorcelain(String(decoding: stdout, as: UTF8.self)) else { return .failed }
            return .sessions(parsed.sessions, complete: status == 0 && parsed.dropped == 0)
        default: return .failed
        }
    }

    /// The bundled CLI, `Contents/Resources/bin/yen`.
    nonisolated static func cliPath(resourcePath: String? = Bundle.main.resourcePath) -> String? {
        guard let resourcePath else { return nil }
        let path = (resourcePath as NSString).appendingPathComponent("bin/yen")
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    nonisolated static func listArguments(host: String) -> [String]? {
        guard isValidTarget(host) else { return nil }
        return ["sessions", "list", "--host", host, "--porcelain"]
    }

    /// The command of a pane attached to a remote session. The pane stays
    /// ephemeral locally; the session lives on the peer, and the CLI reconnects.
    /// `retryUnreachable` keeps retrying a peer that cannot be reached from the
    /// first attempt (a restored pane at launch, before the network is up).
    nonisolated static func attachArguments(host: String, id: UUID, retryUnreachable: Bool = false) -> [String]? {
        guard isValidTarget(host) else { return nil }
        return ["sessions", "attach", "--host", host] + (retryUnreachable ? ["--retry-unreachable"] : []) + [id.uuidString]
    }

    /// `attachArguments` as one shell command line for a pane's `command`.
    nonisolated static func attachCommandLine(host: String, id: UUID, cliPath: String, retryUnreachable: Bool = false) -> String? {
        guard let arguments = attachArguments(host: host, id: id, retryUnreachable: retryUnreachable) else { return nil }
        return ([cliPath] + arguments).map(shellQuoted).joined(separator: " ")
    }

    nonisolated static func shellQuoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// List a peer's sessions with the bundled CLI, off the main thread.
    nonisolated static func list(
        host: String,
        cliPath: String? = cliPath(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = listTimeout
    ) async -> RemoteSessionList {
        guard let cliPath, let arguments = listArguments(host: host) else { return .failed }
        let outcome = await SessionsProcess.run(
            cliPath, arguments,
            environment: SessionsProcess.helperEnvironment(environment),
            timeout: timeout
        )
        return listResult(status: outcome.status, stdout: outcome.stdout, timedOut: outcome.timedOut)
    }
}
