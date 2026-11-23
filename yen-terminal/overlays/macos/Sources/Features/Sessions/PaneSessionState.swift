import Foundation
import os

/// Which panes run in a persistent session, recorded per pane UUID when the
/// pane's surface is created (`PersistentSessions.prepare`). Like the remote
/// identity it never changes for a pane's life, so session state is read from
/// these records without touching the file system or any process.
enum PaneSessionRecords {
    nonisolated private static let live = OSAllocatedUnfairLock(initialState: Set<UUID>())

    nonisolated static func setLive(_ paneID: UUID, _ isLive: Bool) {
        live.withLock { set in
            if isLive { set.insert(paneID) } else { set.remove(paneID) }
        }
    }

    nonisolated static func isLive(_ paneID: UUID) -> Bool {
        live.withLock { $0.contains(paneID) }
    }
}

/// The session state of one pane.
enum PaneSessionState: Equatable, Sendable {
    /// An ordinary pane: its shell ends when YEN quits.
    case local
    /// Runs in a persistent session, so it keeps running when YEN quits.
    case live
    /// Attached to a session on another Mac.
    case remote(RemotePaneIdentity)
    /// A remote pane whose client waits to reconnect to the other Mac.
    case reconnecting(RemotePaneIdentity)

    nonisolated static func of(paneID: UUID) -> PaneSessionState {
        of(paneID: paneID, report: nil)
    }

    /// `report` is the pane's published progress report; only a remote pane
    /// reads it, and only the CLI's mark means reconnecting.
    nonisolated static func of(paneID: UUID, report: YEN.Action.ProgressReport?) -> PaneSessionState {
        if let identity = RemotePanes.identity(for: paneID) {
            return RemotePanes.isReconnectReport(report) ? .reconnecting(identity) : .remote(identity)
        }
        return PaneSessionRecords.isLive(paneID) ? .live : .local
    }
}

extension RemotePanes {
    /// Set in a remote pane's environment, so its CLI writes the reconnecting
    /// mark (yen-cli/lib/sessions-remote.sh -> remote_mark).
    nonisolated static let reconnectMarkEnvironmentKey = "YEN_REMOTE_RECONNECT_MARK"

    /// The CLI's reconnecting mark: OSC 9;4;4;0, a progress report paused at
    /// 0%, which YEN reserves for it. Any other report, including a paused one
    /// at another value, is the remote program's own. The engine drops a
    /// report after 15 seconds, so the CLI renews it while it waits.
    nonisolated static func isReconnectReport(_ report: YEN.Action.ProgressReport?) -> Bool {
        guard let report else { return false }
        return report.state == .pause && report.progress == 0
    }
}

/// The session state a tab shows, from the states of its panes:
/// - remote when any pane is remote (a remote shell must never pass for a
///   local one, whichever pane has focus);
/// - live when every pane is live, because only then does the whole tab keep
///   running when YEN quits;
/// - nothing otherwise.
/// "Detached" (a session no pane shows) belongs to the Hosts session rows,
/// never to a tab.
enum TabSessionState: Equatable, Sendable {
    case live
    /// The distinct host display names, in tree order.
    case remote(hosts: [String])
    /// The Macs of the tab's reconnecting panes, in tree order.
    case reconnecting(hosts: [String])

    nonisolated static func of(_ panes: [PaneSessionState]) -> TabSessionState? {
        var hosts: [String] = []
        var reconnecting: [String] = []
        for pane in panes {
            switch pane {
            case .reconnecting(let identity):
                if !reconnecting.contains(identity.displayName) { reconnecting.append(identity.displayName) }
                if !hosts.contains(identity.displayName) { hosts.append(identity.displayName) }
            case .remote(let identity):
                if !hosts.contains(identity.displayName) { hosts.append(identity.displayName) }
            case .local, .live:
                break
            }
        }
        // Any reconnecting pane wins, naming only the Macs it waits for.
        if !reconnecting.isEmpty { return .reconnecting(hosts: reconnecting) }
        if !hosts.isEmpty { return .remote(hosts: hosts) }
        if !panes.isEmpty, panes.allSatisfy({ $0 == .live }) { return .live }
        return nil
    }

    nonisolated static func of(paneIDs: [UUID]) -> TabSessionState? {
        of(paneIDs.map(PaneSessionState.of(paneID:)))
    }

    @MainActor
    static func of(surfaces: [YEN.SurfaceView]) -> TabSessionState? {
        of(surfaces.map { PaneSessionState.of(paneID: $0.id, report: $0.progressReport) })
    }

    /// The same symbols the app already uses: Persistent Sessions in the
    /// palette, and the SSH pane activity. The shape is the non-color cue.
    var symbolName: String {
        switch self {
        case .live: "rectangle.stack"
        case .remote: "network"
        // The same globe, struck through while the link is down.
        case .reconnecting: "network.slash"
        }
    }

    private static func names(_ hosts: [String]) -> String {
        hosts.count <= 2
            ? hosts.joined(separator: " and ")
            : hosts.dropLast().joined(separator: ", ") + " and " + (hosts.last ?? "")
    }

    /// What VoiceOver reads and the tooltip shows.
    var label: String {
        switch self {
        case .live:
            return "Live session: keeps running when YEN quits"
        case .remote(let hosts):
            let names = Self.names(hosts)
            return hosts.count == 1 ? "Remote session on \(names)" : "Remote sessions on \(names)"
        case .reconnecting(let hosts):
            return "Reconnecting to \(Self.names(hosts))"
        }
    }
}
