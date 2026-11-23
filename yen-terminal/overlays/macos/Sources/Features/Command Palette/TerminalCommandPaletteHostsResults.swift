// YEN Overlay: command palette Hosts rows (remote sessions over Tailscale and ssh).

import Foundation

/// What selecting a Hosts row does.
enum RemoteHostsPaletteAction: Equatable {
    /// Focus the pane showing the session, else open it in a new tab.
    case attach(RemotePaneIdentity)
    /// Run discovery again; the next palette open shows the result.
    case refresh
    /// Type a command at the prompt of the terminal the palette opened over,
    /// without running it.
    case insertCommand(String)
    /// Reopen the palette with the query `hosts`, which starts discovery.
    case showHosts
}

/// When the palette query asks for Hosts. A word of the query (letters and
/// digits only) either starts "hosts" with at least three characters ("hos",
/// "host", "hosts") or is exactly "remote", "ssh" or "tailscale". Prefixes of
/// those three never match, so typing "remove" or "tail" on the way to another
/// command starts nothing. Discovery runs only while this holds.
enum RemoteHostsIntent {
    static let tags = ["hosts", "remote", "ssh", "tailscale"]
    static let prefixTag = "hosts"
    static let minimumPrefixLength = 3

    static func matches(_ query: String) -> Bool {
        query.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .contains { word in
                (word.count >= minimumPrefixLength && prefixTag.hasPrefix(word)) || tags.contains(String(word))
            }
    }
}

/// What selecting a Hosts row does. The effects are passed in so the routing,
/// including the rule that a command is only typed into a local pane, is
/// testable without a palette window.
@MainActor
enum RemoteHostsPaletteActions {
    struct Effects {
        var open: (RemotePaneIdentity) -> Void
        var refresh: () -> Void
        var showHosts: () -> Void
        var insert: (String) -> Void
    }

    static func perform(_ action: RemoteHostsPaletteAction, overRemotePane: Bool, effects: Effects) {
        switch action {
        case .attach(let identity):
            effects.open(identity)
        case .refresh:
            effects.refresh()
        case .showHosts:
            effects.showHosts()
        case .insertCommand(let command):
            // The command is for this Mac; never type it into a remote shell.
            guard !overRemotePane else { return }
            effects.insert(command)
        }
    }

    /// The sessions a palette shows as Open in YEN: remote panes whose client
    /// still runs. A pane whose client ended does not count.
    static func openHere(_ surfaces: [YEN.SurfaceView]) -> [RemotePaneIdentity] {
        surfaces.compactMap { surface -> RemotePaneIdentity? in
            guard let identity = surface.remotePaneIdentity, RemotePanes.isAttached(surface) else { return nil }
            return identity
        }
    }
}

/// The query a palette opened by the static Hosts row starts with.
@MainActor
enum RemoteHostsPaletteSeed {
    private static var pending: String?

    static func set(_ query: String) { pending = query }

    static func take() -> String? {
        defer { pending = nil }
        return pending
    }
}

/// One Hosts row. Pure data, so the catalog invalidates only when a row changes
/// and every state's copy is testable without a window.
struct RemoteHostsPaletteEntry: Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let description: String
    let leadingIcon: String
    let searchTags: [String]
    let action: RemoteHostsPaletteAction
}

/// The copy for every Hosts state (_docs/13-desktop-features.md -> Command
/// Palette -> Hosts). Each non-happy state names the next action.
enum RemoteHostsPaletteRows {
    static let titlePrefix = "Hosts: "
    static let maxDirectoryLength = 60
    private static let baseTags = ["hosts", "remote", "ssh", "tailscale", "sessions", "attach", "mac"]

    static func entries(
        snapshot: RemoteHostsStore.Snapshot,
        isOpenHere: (RemotePaneIdentity) -> Bool,
        now: Date = Date()
    ) -> [RemoteHostsPaletteEntry] {
        guard let status = snapshot.status else {
            return [statusRow("loading", "Looking for Your Macs", "Reading Tailscale status on this Mac", icon: "arrow.clockwise", subtitle: "Checking Tailscale")]
        }
        switch status {
        case .notInstalled:
            return [statusRow("not-installed", "Tailscale Is Not Installed", "Install Tailscale on this Mac and your other Macs and sign in to the same account, then select to check again", icon: "network.slash")]
        case .notRunning:
            return [statusRow("not-running", "Tailscale Is Not Running", "Open the Tailscale app on this Mac, then select to check again", icon: "network.slash")]
        case .stopped:
            return [statusRow("stopped", "Tailscale Is Turned Off", "Turn Tailscale on from its menu bar item, then select to check again", icon: "network.slash")]
        case .needsLogin:
            return [statusRow("needs-login", "Sign In to Tailscale", "Sign in to Tailscale on this Mac, or wait for your admin to approve it, then select to check again", icon: "person.crop.circle.badge.exclamationmark")]
        case .starting:
            return [statusRow("starting", "Tailscale Is Starting", "Tailscale is still connecting; select to check again in a moment", icon: "arrow.clockwise")]
        case .unavailable:
            return [statusRow("unavailable", "Tailscale Did Not Answer", "Tailscale timed out or sent a reply YEN cannot read; select to check again", icon: "exclamationmark.triangle")]
        case .running(let peers):
            guard !peers.isEmpty else {
                return [statusRow("no-peers", "No Other Macs Found", "Sign in to Tailscale with the same account on your other Macs, then select to check again", icon: "desktopcomputer")]
            }
            // One order for the palette and the sidebar: every Mac's sessions,
            // then Macs with something to do, then Macs that are offline or
            // cannot be reached, then Refresh. Peers keep Tailscale's name order
            // within each group.
            var groups = [[RemoteHostsPaletteEntry]](repeating: [], count: PeerGroup.allCases.count)
            for peer in peers {
                let state = snapshot.peerStates[peer.id] ?? .loading
                groups[PeerGroup(state).rawValue] += peerRows(peer, state: state, isOpenHere: isOpenHere, now: now)
            }
            var rows = groups.flatMap { $0 }
            rows.append(statusRow(
                "refresh",
                "Refresh Remote Sessions",
                "List the sessions on your other Macs again",
                icon: "arrow.clockwise",
                subtitle: snapshot.isRefreshing ? "Refreshing" : nil
            ))
            return rows
        }
    }

    /// The palette's tie-break key for the Hosts row at `index` in this
    /// order. It replaces the title only between rows with the same score and
    /// starts with the title prefix, so against any other row it compares
    /// exactly as the "Hosts: " title did.
    static func orderKey(_ index: Int) -> String {
        titlePrefix + String(format: "%05d", index)
    }

    /// Where a Mac's rows go in the Hosts order.
    enum PeerGroup: Int, CaseIterable {
        /// Sessions, or a listing still in flight.
        case sessions
        /// The user can fix it: trust the key, set up key sign-in, update or
        /// install YEN, start a session, read the error.
        case toDo
        /// Offline or cannot be reached.
        case problem

        init(_ state: RemoteHostsStore.PeerState) {
            switch state {
            case .loading: self = .sessions
            case .offline: self = .problem
            case .listed(.unreachable): self = .problem
            case .listed(.sessions(let sessions, _)): self = sessions.isEmpty ? .toDo : .sessions
            case .listed: self = .toDo
            }
        }
    }

    /// Newest first; a session with no start time last; the id breaks ties,
    /// so a listing in any order shows the same rows in the same order.
    static func sessionOrder(_ lhs: RemoteSession, _ rhs: RemoteSession) -> Bool {
        switch (lhs.started, rhs.started) {
        case let (l?, r?) where l != r: return l > r
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static let staticRow = RemoteHostsPaletteEntry(
        id: "hosts:show",
        title: titlePrefix + "Show Sessions on Your Other Macs",
        subtitle: nil,
        description: "List your other Macs on Tailscale and their sessions",
        leadingIcon: "network",
        searchTags: baseTags,
        action: .showHosts
    )

    /// The Hosts rows for a palette query. With Hosts intent: every row for the
    /// store's state. Without it: the static row, plus the rows of the last
    /// discovery for a non-empty query, so a typed peer name still finds them;
    /// none of this starts discovery.
    static func catalogEntries(
        query: String,
        snapshot: RemoteHostsStore.Snapshot,
        isOpenHere: (RemotePaneIdentity) -> Bool,
        now: Date = Date()
    ) -> [RemoteHostsPaletteEntry] {
        if RemoteHostsIntent.matches(query) {
            return entries(snapshot: snapshot, isOpenHere: isOpenHere, now: now)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, snapshot.status != nil else { return [staticRow] }
        return [staticRow] + entries(snapshot: snapshot, isOpenHere: isOpenHere, now: now)
    }

    static func peerRows(
        _ peer: TailscalePeer,
        state: RemoteHostsStore.PeerState,
        isOpenHere: (RemotePaneIdentity) -> Bool,
        now: Date
    ) -> [RemoteHostsPaletteEntry] {
        let name = peer.displayName
        let target = peer.sshTarget
        func row(_ key: String, _ title: String, _ description: String, icon: String, action: RemoteHostsPaletteAction = .refresh, subtitle: String? = nil) -> RemoteHostsPaletteEntry {
            RemoteHostsPaletteEntry(
                id: "hosts:\(peer.id):\(key)",
                title: titlePrefix + title,
                subtitle: subtitle,
                description: description,
                leadingIcon: icon,
                searchTags: baseTags + [name.lowercased(), target.lowercased()],
                action: action
            )
        }
        switch state {
        case .loading:
            return [row("loading", name, "Listing the sessions on \(name)", icon: "arrow.clockwise", subtitle: "Loading sessions")]
        case .offline:
            return [row("offline", "\(name) Is Offline", "Wake \(name) and connect it to Tailscale, then select to check again", icon: "moon.zzz")]
        case .listed(let list):
            switch list {
            case .unreachable:
                return [row("unreachable", "Cannot Reach \(name)", "Check that \(name) is awake and has Remote Login on in System Settings > General > Sharing, then select to check again", icon: "exclamationmark.triangle")]
            case .firstConnectionNeeded:
                return [row(
                    "first-connection",
                    "Trust the Host Key of \(name)",
                    "YEN has not seen the host key of \(name) yet. Run ssh \(target) once in a terminal on this Mac and confirm the key; select to type the command",
                    icon: "lock.shield",
                    action: .insertCommand("ssh \(target)"),
                    subtitle: "ssh \(target)"
                )]
            case .keySignInNeeded:
                return [row(
                    "key-sign-in",
                    "Set Up Key Sign-In for \(name)",
                    "\(name) asked for a password, and YEN signs in only with an SSH key that needs no prompt. Run ssh-copy-id \(target) once in a terminal on this Mac; select to type the command",
                    icon: "key",
                    action: .insertCommand("ssh-copy-id \(target)"),
                    subtitle: "ssh-copy-id \(target)"
                )]
            case .tailscaleCheckNeeded:
                return [row(
                    "tailscale-check",
                    "Approve \(name) in Tailscale",
                    "Tailscale SSH on \(name) asks you to approve this sign-in in a browser. Run ssh \(target) once in a terminal on this Mac and open the link it shows; the approval lasts for your tailnet's check period. Select to type the command",
                    icon: "checkmark.shield",
                    action: .insertCommand("ssh \(target)"),
                    subtitle: "ssh \(target)"
                )]
            case .hostKeyChanged:
                return [row("host-key-changed", "Host Key of \(name) Changed", "YEN will not connect: the key \(name) presents no longer matches the one you trusted. If \(name) was reinstalled, remove the old key with ssh-keygen -R \(target); otherwise someone may be intercepting the connection", icon: "exclamationmark.shield")]
            case .yenNotInstalled:
                return [row("yen-not-installed", "YEN Is Not Installed on \(name)", "Install YEN in the Applications folder on \(name), then select to check again", icon: "exclamationmark.triangle")]
            case .yenTooOld:
                return [row("yen-too-old", "Update YEN on \(name)", "\(name) runs a YEN without remote sessions; update it there, then select to check again", icon: "arrow.down.circle")]
            case .failed:
                return [row(
                    "failed",
                    "Could Not List Sessions on \(name)",
                    "Run yen sessions list --host \(target) in a terminal on this Mac to see the error; select to type the command",
                    icon: "exclamationmark.triangle",
                    action: .insertCommand("yen sessions list --host \(target)")
                )]
            case .sessions(let sessions, let complete):
                // An incomplete listing with no rows is a peer that failed
                // before listing anything (a YEN there without zmx prints its
                // header and exits 1), not a Mac without sessions.
                if sessions.isEmpty && !complete {
                    return peerRows(peer, state: .listed(.failed), isOpenHere: isOpenHere, now: now)
                }
                var rows: [RemoteHostsPaletteEntry] = []
                if sessions.isEmpty {
                    rows.append(row("no-sessions", "No Sessions on \(name)", "Turn on Keep Sessions Running in YEN on \(name) and open a terminal there, then select to check again", icon: "rectangle.stack"))
                }
                rows += distinguished(sessions.sorted(by: sessionOrder).compactMap { session in
                    sessionRow(session, peer: peer, isOpenHere: isOpenHere, now: now).map { ($0, session.id) }
                })
                if !complete {
                    rows.append(row("incomplete", "Some Sessions on \(name) Could Not Be Read", "Run yen sessions list on \(name) to see them all; select to check again", icon: "exclamationmark.triangle"))
                }
                return rows
            }
        }
    }

    static func sessionRow(
        _ session: RemoteSession,
        peer: TailscalePeer,
        isOpenHere: (RemotePaneIdentity) -> Bool,
        now: Date
    ) -> RemoteHostsPaletteEntry? {
        guard let identity = RemotePaneIdentity(peer: peer, session: session) else { return nil }
        let name = identity.displayName
        let place = session.directory.map(displayDirectory) ?? "Session \(session.id.uuidString.prefix(8))"
        let started = session.started.map { startedText($0, now: now) }
        let state: String
        let description: String
        let action: RemoteHostsPaletteAction
        if session.state == .unreachable {
            state = "Unavailable"
            description = "\(name) cannot attach to this session: its zmx build is missing there. Select to check again"
            action = .refresh
        } else if isOpenHere(identity) {
            state = "Open in YEN"
            description = "Focus the tab attached to this session on \(name)"
            action = .attach(identity)
        } else {
            state = session.state == .attached ? "Attached elsewhere" : "Detached"
            description = "Attach to this session on \(name) in a new tab"
            action = .attach(identity)
        }
        return RemoteHostsPaletteEntry(
            id: "hosts:\(peer.id):session:\(session.id.uuidString)",
            title: "\(titlePrefix)\(place) on \(name)",
            subtitle: [state, started].compactMap { $0 }.joined(separator: " · "),
            description: description,
            leadingIcon: "network",
            searchTags: baseTags + [name.lowercased(), peer.sshTarget.lowercased()],
            action: action
        )
    }

    /// Two sessions of one Mac that would read the same (same place, same
    /// state, started the same minute) end their subtitles with the first
    /// eight characters of their session id, so one press never picks the
    /// other by mistake. Rows that already differ stay short.
    static func distinguished(_ rows: [(RemoteHostsPaletteEntry, UUID)]) -> [RemoteHostsPaletteEntry] {
        func reading(_ entry: RemoteHostsPaletteEntry) -> String { entry.title + "\n" + (entry.subtitle ?? "") }
        var counts: [String: Int] = [:]
        for (entry, _) in rows { counts[reading(entry), default: 0] += 1 }
        return rows.map { entry, id in
            guard counts[reading(entry), default: 0] > 1 else { return entry }
            return RemoteHostsPaletteEntry(
                id: entry.id,
                title: entry.title,
                subtitle: [entry.subtitle, String(id.uuidString.prefix(8))].compactMap { $0 }.joined(separator: " · "),
                description: entry.description,
                leadingIcon: entry.leadingIcon,
                searchTags: entry.searchTags,
                action: entry.action
            )
        }
    }

    private static func statusRow(_ key: String, _ title: String, _ description: String, icon: String, subtitle: String? = nil) -> RemoteHostsPaletteEntry {
        RemoteHostsPaletteEntry(
            id: "hosts:\(key)",
            title: titlePrefix + title,
            subtitle: subtitle,
            description: description,
            leadingIcon: icon,
            searchTags: baseTags,
            action: .refresh
        )
    }

    /// A peer path for a title: a macOS home folder shown as `~`, then at most
    /// `maxDirectoryLength` characters, keeping the end, which names the place.
    static func displayDirectory(_ path: String) -> String {
        var display = path
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count >= 3, parts[0].isEmpty, parts[1] == "Users", !parts[2].isEmpty {
            display = (["~"] + parts.dropFirst(3)).joined(separator: "/")
        }
        guard display.count > maxDirectoryLength else { return display }
        return "…" + display.suffix(maxDirectoryLength - 1)
    }

    static func startedText(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "started " + formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}
