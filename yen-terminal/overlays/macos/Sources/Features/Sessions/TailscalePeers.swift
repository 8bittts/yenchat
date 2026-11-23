import Foundation
import os

/// A Mac on the user's tailnet that may host YEN sessions.
struct TailscalePeer: Equatable, Sendable, Identifiable {
    /// Tailscale's stable node ID.
    let id: String
    /// The peer's host name, stripped of control characters, for labels.
    let displayName: String
    /// What `ssh` connects to: the MagicDNS name without its trailing dot when
    /// it resolves on this Mac to one of the peer's own Tailscale IPs, else
    /// the first valid Tailscale IP. Always passes `RemoteSessions.isValidTarget`.
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
/// `ShareeNode`, `PeerAPIURL`, and `CurrentTailnet.MagicDNSEnabled`).
/// Everything in the output is untrusted input.
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

    /// The addresses a host name resolves to on this Mac, empty when it does
    /// not resolve. Injected so tests need no network.
    typealias Resolver = @Sendable (_ name: String) async -> [String]

    nonisolated static func status(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(5),
        resolve: @escaping Resolver = TailscaleDiscovery.resolveOnThisMac,
        resolveTimeout: Duration = .seconds(1)
    ) async -> TailscaleStatus {
        guard let path = cliPath(environment: environment) else { return .notInstalled }
        // The app executable acts as the CLI only when it is told to; a GUI
        // launch from a background process is never wanted here.
        let outcome = await SessionsProcess.run(
            path, ["status", "--json"],
            environment: SessionsProcess.helperEnvironment(environment, adding: ["TAILSCALE_BE_CLI": "1"]),
            timeout: timeout
        )
        let usable = outcome.timedOut
            ? []
            : await usableNames(nameCandidates(outcome.stdout), resolve: resolve, within: resolveTimeout)
        return status(from: outcome, usableNames: usable)
    }

    /// `usableNames` is the set of MagicDNS names that resolve here to their
    /// peer's own address; nil skips that check (tests of the parser alone).
    nonisolated static func status(from outcome: SessionsProcess.Outcome, usableNames: Set<String>? = nil) -> TailscaleStatus {
        if outcome.timedOut { return .unavailable }
        // `status --json` prints the state even when stopped or logged out and
        // exits 0; a failure to reach the daemon prints no JSON and exits non-zero.
        if let parsed = parseStatus(outcome.stdout, usableNames: usableNames) { return parsed }
        return outcome.status == 0 ? .unavailable : .notRunning
    }

    // MARK: Which name is usable

    /// `CurrentTailnet.MagicDNSEnabled` is the tailnet's setting, not this
    /// Mac's: with "Use Tailscale DNS settings" off in the Tailscale app
    /// (`CorpDNS: false`) it still reads true and every peer keeps its
    /// `DNSName`, but the name does not resolve here. So a name becomes the
    /// ssh target only when it resolves on this Mac to one of the peer's own
    /// `TailscaleIPs`; an answer with any other address (split-horizon or
    /// spoofed) is never used. Only online peers are resolved: an offline
    /// one is never contacted and keeps its IP until a refresh finds it.
    nonisolated static func nameCandidates(_ data: Data) -> [(name: String, addresses: [String])] {
        guard let status = try? JSONDecoder().decode(Status.self, from: data),
              status.backendState == "Running", status.tailnet?.magicDNSEnabled == true,
              let me = status.me, let owner = me.userID else { return [] }
        return (status.peers ?? [:]).values.compactMap { node in
            guard node.online == true, isListed(node, owner: owner, selfID: me.id),
                  let name = magicDNSName(node) else { return nil }
            return (name, node.addresses ?? [])
        }
    }

    /// The names that resolve, each within `within`, all at once.
    nonisolated static func usableNames(
        _ candidates: [(name: String, addresses: [String])],
        resolve: @escaping Resolver,
        within: Duration
    ) async -> Set<String> {
        await withTaskGroup(of: String?.self) { group in
            for (name, addresses) in candidates {
                group.addTask {
                    let own = Set(addresses.compactMap(numericAddress))
                    let answer = await firstAnswer(name, resolve: resolve, within: within)
                    return answer.contains { numericAddress($0).map(own.contains) == true } ? name : nil
                }
            }
            var usable: Set<String> = []
            for await name in group { if let name { usable.insert(name) } }
            return usable
        }
    }

    /// The resolver's answer, or nothing once `within` has passed. A resolver
    /// that ignores cancellation keeps running in the background.
    nonisolated private static func firstAnswer(_ name: String, resolve: @escaping Resolver, within: Duration) async -> [String] {
        await withCheckedContinuation { continuation in
            let done = OSAllocatedUnfairLock(initialState: false)
            func finish(_ answer: [String]) {
                let first = done.withLock { claimed in
                    defer { claimed = true }
                    return !claimed
                }
                if first { continuation.resume(returning: answer) }
            }
            Task.detached(priority: .utility) { finish(await resolve(name)) }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: within)
                finish([])
            }
        }
    }

    /// The bytes of a numeric IPv4 or IPv6 address, so two spellings of one
    /// address compare equal; nil for anything else. A zone suffix is dropped.
    nonisolated static func numericAddress(_ text: String) -> Data? {
        let bare = String(text.split(separator: "%", maxSplits: 1).first ?? "")
        var v4 = in_addr()
        if inet_pton(AF_INET, bare, &v4) == 1 { return withUnsafeBytes(of: &v4) { Data($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, bare, &v6) == 1 { return withUnsafeBytes(of: &v6) { Data($0) } }
        return nil
    }

    /// The system resolver on this Mac, off the main thread.
    nonisolated static let resolveOnThisMac: Resolver = { name in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var list: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(name, nil, &hints, &list) == 0 else {
                    continuation.resume(returning: [])
                    return
                }
                defer { freeaddrinfo(list) }
                var addresses: [String] = []
                var entry = list
                while let current = entry {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        addresses.append(String(cString: host))
                    }
                    entry = current.pointee.ai_next
                }
                continuation.resume(returning: addresses)
            }
        }
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
        let peerAPI: [String]?

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
            case peerAPI = "PeerAPIURL"
        }
    }

    /// nil when the data is not Tailscale's status JSON.
    nonisolated static func parseStatus(_ data: Data, usableNames: Set<String>? = nil) -> TailscaleStatus? {
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
            guard isListed(node, owner: owner, selfID: me.id), let id = node.id else { return nil }
            return peer(from: node, id: id, namesResolve: namesResolve, usableNames: usableNames)
        }
        return .running(peers: peers.sorted { ($0.displayName.lowercased(), $0.id) < ($1.displayName.lowercased(), $1.id) })
    }

    /// True for a full Tailscale client, which a Mac that can host YEN runs.
    /// A node another app embeds (tsnet) reports the user's `OS` and `UserID`
    /// too, but runs no peer API and no ssh server, so it is not listed.
    ///
    /// Tailscale fills `PeerStatus.PeerAPIURL` from the peer's
    /// `Hostinfo.Services` (the `peerapi4` and `peerapi6` ports;
    /// `LocalBackend.populatePeerStatusLocked` and `peerAPIPorts` in ipn/ipnlocal/local.go),
    /// not from whether the peer is online, and `OS` comes from the same
    /// Hostinfo; so an offline Mac that still reads `OS: macOS` keeps its
    /// peer API addresses and still shows as offline. `TaildropTarget` cannot
    /// tell the two apart: `taildropTargetStatus` in feature/taildrop/ext.go
    /// reports Offline (5) before NoPeerAPI (8), and MissingCap (4) for every
    /// peer when file sharing is off. Source read at tailscale/tailscale
    /// af9bfa07c3425b144330f6fa61bc0221f930dd95.
    nonisolated private static func isFullClient(_ node: Node) -> Bool {
        !(node.peerAPI ?? []).isEmpty
    }

    /// The user's own Macs that run a full Tailscale client, never this Mac.
    nonisolated private static func isListed(_ node: Node, owner: Int64, selfID: String?) -> Bool {
        guard node.os == macOS, node.userID == owner, node.sharee != true, node.expired != true,
              isFullClient(node), let id = node.id, !id.isEmpty, id != selfID else { return false }
        return true
    }

    /// The peer's MagicDNS name without its trailing dot, when it is a valid target.
    nonisolated private static func magicDNSName(_ node: Node) -> String? {
        guard var name = node.dnsName, !name.isEmpty else { return nil }
        if name.hasSuffix(".") { name.removeLast() }
        return RemoteSessions.isValidTarget(name) ? name : nil
    }

    nonisolated private static func peer(from node: Node, id: String, namesResolve: Bool, usableNames: Set<String>?) -> TailscalePeer? {
        var target: String?
        if namesResolve, let name = magicDNSName(node), usableNames?.contains(name) ?? true {
            target = name
        }
        if target == nil {
            target = (node.addresses ?? []).first(where: RemoteSessions.isValidTarget)
        }
        guard let target else { return nil }
        let label = displayLabel(node.hostName ?? "")
        // An unnamed peer reachable only by IP still reads as its tailnet name.
        let named = magicDNSName(node) ?? target
        let fallback = named.split(separator: ".").first.map(String.init) ?? named
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
