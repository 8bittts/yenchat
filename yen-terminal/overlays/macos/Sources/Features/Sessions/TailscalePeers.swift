import Foundation

/// A Mac on the user's tailnet that may host YEN sessions.
struct TailscalePeer: Equatable, Sendable, Identifiable {
    /// Tailscale's stable node ID.
    let id: String
    /// The peer's host name, stripped of control characters, for labels.
    let displayName: String
    /// What `ssh` connects to: the MagicDNS name without its trailing dot when
    /// the tailnet has MagicDNS on, else the first Tailscale IP. Always passes
    /// `RemoteSessions.isValidTarget`.
    let sshTarget: String
    let isOnline: Bool
}

/// What the installed Tailscale reports. Everything except `.running` is a
/// normal state to describe in plain copy, not an error.
enum TailscaleStatus: Equatable, Sendable {
    /// No Tailscale CLI at any known path.
    case notInstalled
    /// The CLI ran but could not reach its daemon or network extension.
    case notRunning
    /// The user turned Tailscale off.
    case stopped
    /// This Mac is logged out or waits for login or admin approval.
    case needsLogin
    case starting
    /// Connected; the Macs of the same user, sorted by name.
    case running(peers: [TailscalePeer])
    /// The CLI timed out or printed something that is not its status JSON.
    case unavailable
}

/// Peer discovery from the installed Tailscale CLI (`tailscale status --json`).
/// YEN never embeds Tailscale or `tsnet` (_docs/01-architecture.md -> Persistent
/// sessions -> Remote attach).
///
/// Field names come from Tailscale's `ipn/ipnstate` `Status` and `PeerStatus`,
/// whose JSON keys are the Go field names (`BackendState`, `Self`, `Peer`,
/// `HostName`, `DNSName`, `OS`, `UserID`, `TailscaleIPs`, `Online`, `Expired`,
/// `ShareeNode`, and `CurrentTailnet.MagicDNSEnabled`). Everything in the
/// output is untrusted input.
enum TailscaleDiscovery {
    /// Test hook: the Tailscale CLI to run instead of the installed one.
    static let binaryEnvironmentKey = "YEN_TAILSCALE_BIN"

    /// The Mac App Store and standalone apps carry the CLI in the app
    /// executable; the standalone app can also install a launcher in
    /// /usr/local/bin. The open-source `tailscaled` build installs `tailscale`
    /// with Homebrew.
    static let appExecutable = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    static let candidatePaths = [appExecutable, "/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale"]

    /// Tailscale's `OS` value for a Mac.
    static let macOS = "macOS"

    nonisolated static func cliPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        if let override = environment[binaryEnvironmentKey], !override.isEmpty {
            return isExecutable(override) ? override : nil
        }
        return candidatePaths.first(where: isExecutable)
    }

    nonisolated static func status(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(5)
    ) async -> TailscaleStatus {
        guard let path = cliPath(environment: environment) else { return .notInstalled }
        // The app executable acts as the CLI only when it is told to; a GUI
        // launch from a background process is never wanted here.
        let outcome = await SessionsProcess.run(
            path, ["status", "--json"],
            environment: SessionsProcess.helperEnvironment(environment, adding: ["TAILSCALE_BE_CLI": "1"]),
            timeout: timeout
        )
        return status(from: outcome)
    }

    nonisolated static func status(from outcome: SessionsProcess.Outcome) -> TailscaleStatus {
        if outcome.timedOut { return .unavailable }
        // `status --json` prints the state even when stopped or logged out and
        // exits 0; a failure to reach the daemon prints no JSON and exits non-zero.
        if let parsed = parseStatus(outcome.stdout) { return parsed }
        return outcome.status == 0 ? .unavailable : .notRunning
    }

    private struct Status: Decodable {
        let backendState: String?
        let me: Node?
        let peers: [String: Node]?
        let tailnet: Tailnet?

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case me = "Self"
            case peers = "Peer"
            case tailnet = "CurrentTailnet"
        }
    }

    private struct Tailnet: Decodable {
        let magicDNSEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case magicDNSEnabled = "MagicDNSEnabled"
        }
    }

    private struct Node: Decodable {
        let id: String?
        let hostName: String?
        let dnsName: String?
        let os: String?
        let userID: Int64?
        let addresses: [String]?
        let online: Bool?
        let expired: Bool?
        let sharee: Bool?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case hostName = "HostName"
            case dnsName = "DNSName"
            case os = "OS"
            case userID = "UserID"
            case addresses = "TailscaleIPs"
            case online = "Online"
            case expired = "Expired"
            case sharee = "ShareeNode"
        }
    }

    /// nil when the data is not Tailscale's status JSON.
    nonisolated static func parseStatus(_ data: Data) -> TailscaleStatus? {
        guard let status = try? JSONDecoder().decode(Status.self, from: data),
              let backend = status.backendState else { return nil }
        switch backend {
        case "Running": break
        case "Stopped": return .stopped
        case "NeedsLogin", "NeedsMachineAuth": return .needsLogin
        case "Starting": return .starting
        case "NoState", "InUseOtherUser": return .notRunning
        default: return .unavailable
        }
        guard let me = status.me, let owner = me.userID else { return .running(peers: []) }
        // `DNSName` is filled from the netmap even with MagicDNS off, when the
        // name does not resolve. `CurrentTailnet` is nil when not connected.
        let namesResolve = status.tailnet?.magicDNSEnabled == true
        let peers = (status.peers ?? [:]).values.compactMap { node -> TailscalePeer? in
            guard node.os == macOS, node.userID == owner, node.sharee != true, node.expired != true,
                  let id = node.id, !id.isEmpty, id != me.id else { return nil }
            return peer(from: node, id: id, namesResolve: namesResolve)
        }
        return .running(peers: peers.sorted { ($0.displayName.lowercased(), $0.id) < ($1.displayName.lowercased(), $1.id) })
    }

    nonisolated private static func peer(from node: Node, id: String, namesResolve: Bool) -> TailscalePeer? {
        var target: String?
        if namesResolve, var name = node.dnsName, !name.isEmpty {
            if name.hasSuffix(".") { name.removeLast() }
            if RemoteSessions.isValidTarget(name) { target = name }
        }
        if target == nil {
            target = (node.addresses ?? []).first(where: RemoteSessions.isValidTarget)
        }
        guard let target else { return nil }
        let label = displayLabel(node.hostName ?? "")
        let fallback = target.split(separator: ".").first.map(String.init) ?? target
        return TailscalePeer(id: id, displayName: label.isEmpty ? fallback : label, sshTarget: target, isOnline: node.online == true)
    }

    /// A host name for display: control and format characters removed,
    /// whitespace collapsed, at most 63 characters.
    nonisolated static func displayLabel(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: " "
            default: Character(scalar)
            }
        }
        let words = String(scalars).split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(63))
    }
}
