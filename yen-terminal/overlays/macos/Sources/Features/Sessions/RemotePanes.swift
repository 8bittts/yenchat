import AppKit
import Foundation
import os

/// Which remote session a pane shows. Recorded per pane UUID when the pane's
/// surface is created, so labels, window restore and the tab sidebar read one
/// source (_docs/01-architecture.md -> Persistent sessions -> Remote panes).
struct RemotePaneIdentity: Codable, Equatable, Hashable, Sendable {
    /// What labels show: the peer's Tailscale host name, already free of
    /// control and format characters, at most `maxDisplayNameLength` long.
    let displayName: String
    /// What ssh connects to. Always passes `RemoteSessions.isValidTarget`.
    let sshTarget: String
    let sessionID: UUID

    static let maxDisplayNameLength = 32

    /// nil when the target is not a valid ssh target. Everything here can come
    /// from saved window state or from Tailscale, so it is checked again.
    init?(displayName: String, sshTarget: String, sessionID: UUID) {
        guard RemoteSessions.isValidTarget(sshTarget) else { return nil }
        let label = String(TailscaleDiscovery.displayLabel(displayName).prefix(Self.maxDisplayNameLength))
        let fallback = sshTarget.split(separator: ".").first.map(String.init) ?? sshTarget
        self.displayName = label.isEmpty ? String(fallback.prefix(Self.maxDisplayNameLength)) : label
        self.sshTarget = sshTarget
        self.sessionID = sessionID
    }

    init?(peer: TailscalePeer, session: RemoteSession) {
        self.init(displayName: peer.displayName, sshTarget: peer.sshTarget, sessionID: session.id)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, sshTarget, sessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let identity = Self(
            displayName: try container.decode(String.self, forKey: .displayName),
            sshTarget: try container.decode(String.self, forKey: .sshTarget),
            sessionID: try container.decode(UUID.self, forKey: .sessionID)
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .sshTarget, in: container, debugDescription: "invalid ssh target")
        }
        self = identity
    }

    /// The same session on the same peer, whatever the label says.
    func isSameSession(as other: RemotePaneIdentity) -> Bool {
        sshTarget.caseInsensitiveCompare(other.sshTarget) == .orderedSame && sessionID == other.sessionID
    }
}

/// Remote panes: the pane-creation hook, the per-pane record and the labels.
///
/// A remote pane is an ordinary local pane whose command is the bundled
/// `yen sessions attach --host <target> <id>`. It stays ephemeral locally
/// (`PersistentSessions.prepare` skips a pane with a command); the session
/// lives on the peer and the CLI reconnects.
enum RemotePanes {
    /// Carries the identity from the code that opens a remote pane to
    /// `prepare`, which always removes it, so a split or tab that inherits a
    /// parent's environment never becomes remote by accident.
    nonisolated static let markerEnvironmentKey = "YEN_REMOTE_PANE"

    private struct Registry {
        var identities: [UUID: RemotePaneIdentity] = [:]
        /// Identities read from window restore state, waiting for the restored
        /// pane's surface to be created.
        var pendingRestore: [UUID: RemotePaneIdentity] = [:]
        /// Test hook: the CLI path for attach commands.
        var cliPathOverride: String?
    }

    nonisolated private static let registry = OSAllocatedUnfairLock(initialState: Registry())

    // MARK: Pane creation

    /// Called for every new surface before its process starts
    /// (`PersistentSessions.prepare`). Sets the attach command for a pane
    /// opened by `open` or restored from saved state, and records its identity;
    /// any other pane is recorded as local.
    nonisolated static func prepare(_ config: inout YEN.SurfaceConfiguration, paneID: UUID) {
        let marker = config.environmentVariables.removeValue(forKey: markerEnvironmentKey)
        let restored = registry.withLock { $0.pendingRestore.removeValue(forKey: paneID) }
        let requested = marker.flatMap(decodeMarker)
        // A marker only counts on a pane that has no command of its own.
        let identity = requested.flatMap { config.command == nil ? $0 : nil } ?? (config.command == nil ? restored : nil)
        // A restored pane may start before the network or Tailscale is up,
        // so it keeps retrying an unreachable peer; an opened one reports it.
        let isRestore = requested == nil && restored != nil
        guard let identity, let command = attachCommand(for: identity, retryUnreachable: isRestore) else {
            registry.withLock { $0.identities[paneID] = nil }
            return
        }
        config.command = command
        // attachWrapper holds a failure on screen and lets a normal end close.
        config.waitAfterCommand = false
        registry.withLock { $0.identities[paneID] = identity }
    }

    nonisolated static func identity(for paneID: UUID) -> RemotePaneIdentity? {
        registry.withLock { $0.identities[paneID] }
    }

    nonisolated static func marker(for identity: RemotePaneIdentity) -> String? {
        guard let data = try? JSONEncoder().encode(identity) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func decodeMarker(_ text: String) -> RemotePaneIdentity? {
        try? JSONDecoder().decode(RemotePaneIdentity.self, from: Data(text.utf8))
    }

    /// The bundled CLI's path even when it is missing, so a broken install
    /// shows the error in a labeled pane instead of opening a local shell.
    nonisolated static func cliPath(resourcePath: String? = Bundle.main.resourcePath) -> String? {
        if let override = registry.withLock({ $0.cliPathOverride }) { return override }
        if let path = RemoteSessions.cliPath(resourcePath: resourcePath) { return path }
        return resourcePath.map { ($0 as NSString).appendingPathComponent("bin/yen") }
    }

    /// Runs the CLI's attach and decides what the pane does when it ends: a
    /// normal end (0) or Ctrl-C (130) closes the pane like a local shell that
    /// exits; any other status stays on screen under the CLI's own message
    /// until Return. The hold replaces this shell, so its argv no longer names
    /// the session (`isAttached`).
    nonisolated static let attachWrapper = #""$@"; s=$?; if [ "$s" -eq 0 ] || [ "$s" -eq 130 ]; then exit "$s"; fi; exec /bin/sh -c 'printf "\nThe remote session is not attached (exit %s). Press Return to close this pane.\n" "$1"; read -r _; exit "$1"' yen-remote-ended "$s""#

    nonisolated static func attachCommand(for identity: RemotePaneIdentity, retryUnreachable: Bool = false) -> String? {
        guard let cliPath = cliPath(),
              let arguments = RemoteSessions.attachArguments(
                  host: identity.sshTarget, id: identity.sessionID, retryUnreachable: retryUnreachable
              ) else { return nil }
        // The engine runs a command with `exec -l`, which would make a bare sh
        // a login shell that reads the user's profile; env starts sh plainly.
        let words = ["/usr/bin/env", "/bin/sh", "-c", attachWrapper, "yen-remote-attach", cliPath] + arguments
        return words.map(RemoteSessions.shellQuoted).joined(separator: " ")
    }

    /// True while some process in the tree under `rootPID` (it included, at
    /// most six levels down) carries `argument` in its argv.
    nonisolated static func processTree(under rootPID: pid_t, mentions argument: String) -> Bool {
        var frontier: [pid_t] = [rootPID]
        for _ in 0..<6 {
            var next: [pid_t] = []
            for pid in frontier where pid > 0 {
                if arguments(of: pid).contains(argument) { return true }
                next += children(of: pid)
            }
            if next.isEmpty { return false }
            frontier = next
        }
        return false
    }

    nonisolated private static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 64)
        // Returns a count of pids, not bytes (libproc.c).
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return Array(buffer.prefix(min(Int(count), buffer.count))).filter { $0 > 0 }
    }

    /// argv of a process the user owns, from KERN_PROCARGS2; empty when unreadable.
    nonisolated private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        // After argc: the executable path, NUL padding, then argv strings.
        var parts = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return [] }
        parts.removeFirst()
        return parts.prefix(argc).map { String(decoding: $0, as: UTF8.self) }
    }

    /// True while the pane's attach client still runs: its process tree names
    /// the session. A pane whose client ended (held on screen, or exited) does not.
    @MainActor static func isAttached(_ surface: YEN.SurfaceView) -> Bool {
        guard let identity = identity(for: surface.id), !surface.processExited,
              let pid = surface.surfaceModel?.foregroundPID, pid > 0 else { return false }
        return processTree(under: pid_t(pid), mentions: identity.sessionID.uuidString)
    }

    /// A pane left its tree; once undo can no longer bring it back and no
    /// window holds it, forget its identity.
    static func paneLeftTree(
        _ paneID: UUID,
        after delay: Duration,
        isStillPresent: @escaping @MainActor (UUID) -> Bool
    ) {
        guard identity(for: paneID) != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + PersistentSessions.seconds(delay)) {
            guard !isStillPresent(paneID) else { return }
            registry.withLock { $0.identities[paneID] = nil }
        }
    }

    nonisolated static func _testSetCLIPath(_ path: String?) {
        registry.withLock { $0.cliPathOverride = path }
    }

    // MARK: Window restore

    /// The remote identities of a tree's panes, keyed by pane UUID, for
    /// restore state. nil when the tree has no remote pane.
    static func snapshot(for tree: SplitTree<YEN.SurfaceView>) -> [String: RemotePaneIdentity]? {
        var result: [String: RemotePaneIdentity] = [:]
        for surface in tree {
            if let identity = identity(for: surface.id) { result[surface.id.uuidString] = identity }
        }
        return result.isEmpty ? nil : result
    }

    /// Decode a split tree with its remote identities already registered, so
    /// each restored remote pane is created with its attach command and never
    /// starts as a local shell. Entries for panes the tree does not contain
    /// are dropped afterwards.
    static func decodingTree<T>(
        restoring identities: [String: RemotePaneIdentity]?,
        _ decode: () throws -> T
    ) rethrows -> T {
        let pending = (identities ?? [:]).reduce(into: [UUID: RemotePaneIdentity]()) { result, entry in
            if let id = UUID(uuidString: entry.key) { result[id] = entry.value }
        }
        registry.withLock { $0.pendingRestore.merge(pending) { _, new in new } }
        defer {
            registry.withLock { state in
                for id in pending.keys { state.pendingRestore[id] = nil }
            }
        }
        return try decode()
    }

    /// Restore state stores identities in a lossy map: one bad entry must not
    /// drop the window.
    struct SavedIdentities: Codable, Equatable {
        let entries: [String: RemotePaneIdentity]

        init(_ entries: [String: RemotePaneIdentity]) {
            self.entries = entries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: LossyIdentity].self)
            entries = raw.compactMapValues(\.value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(entries)
        }

        private struct LossyIdentity: Decodable {
            let value: RemotePaneIdentity?

            init(from decoder: Decoder) throws {
                value = try? RemotePaneIdentity(from: decoder)
            }
        }
    }

    // MARK: Labels

    /// The title of a tab whose title comes from `surface`: the host first, so
    /// a remote shell is never mistaken for a local one. A local pane's title
    /// passes through unchanged.
    @MainActor static func tabTitle(_ title: String, for surface: YEN.SurfaceView?) -> String {
        guard let surface, let identity = identity(for: surface.id) else { return title }
        return tabTitle(title, host: identity.displayName)
    }

    /// The engine's title publisher (patch `remote-pane-tab-title`): labels
    /// the title of the pane it came from, which is the last focused pane
    /// while no pane has focus, and remembers that pane for a typed tab title.
    @MainActor static func tabTitle(_ title: String, for surface: YEN.SurfaceView?, in controller: BaseTerminalController) -> String {
        TitleSource.set(surface, on: controller)
        return tabTitle(title, for: surface)
    }

    /// A typed tab title (patch `remote-pane-tab-title`): labeled by the
    /// focused pane, else the pane the tab's title last came from.
    @MainActor static func tabTitle(_ title: String, in controller: BaseTerminalController) -> String {
        tabTitle(title, for: controller.focusedSurface ?? TitleSource.get(controller))
    }

    @MainActor private enum TitleSource {
        final class Box { weak var surface: YEN.SurfaceView? }
        nonisolated(unsafe) static var key: UInt8 = 0

        static func set(_ surface: YEN.SurfaceView?, on controller: BaseTerminalController) {
            let box = objc_getAssociatedObject(controller, &key) as? Box ?? Box()
            box.surface = surface
            objc_setAssociatedObject(controller, &key, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        static func get(_ controller: BaseTerminalController) -> YEN.SurfaceView? {
            (objc_getAssociatedObject(controller, &key) as? Box)?.surface
        }
    }

    nonisolated static func tabTitle(_ title: String, host: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // A remote title that already leads with the label is left alone, so a
        // restored title is not prefixed twice.
        if trimmed.isEmpty || trimmed == "YEN" || trimmed == host { return host }
        if trimmed.hasPrefix(host + titleSeparator) { return trimmed }
        return host + titleSeparator + trimmed
    }

    nonisolated static let titleSeparator = " · "

    // MARK: Opening

    enum OpenResult: Equatable {
        case focused
        case opened
        case failed
    }

    /// The open pane whose client is attached to this session, if any. A pane
    /// whose client ended stays as it is; selecting the session opens a new tab.
    @MainActor static func existingPane(
        for identity: RemotePaneIdentity,
        in controllers: [BaseTerminalController]? = nil
    ) -> YEN.SurfaceView? {
        for controller in controllers ?? TerminalController.all {
            for surface in controller.surfaceTree {
                if let other = Self.identity(for: surface.id), other.isSameSession(as: identity), isAttached(surface) {
                    return surface
                }
            }
        }
        return nil
    }

    /// Show a remote session: focus the pane that already shows it, else open
    /// it in a new tab beside `window`. A second client of the same session in
    /// one app only mirrors the first and resizes it, so YEN focuses instead.
    @MainActor static func open(_ identity: RemotePaneIdentity, from window: NSWindow?) -> OpenResult {
        if let surface = existingPane(for: identity) {
            NotificationCenter.default.post(name: YEN.Notification.yenPresentTerminal, object: surface)
            return .focused
        }
        guard let yen = AppDelegate.shared?.yen, let marker = marker(for: identity) else { return .failed }
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[markerEnvironmentKey] = marker
        return TerminalController.newTab(yen, from: window, withBaseConfig: config) == nil ? .failed : .opened
    }
}

extension YEN.SurfaceView {
    /// The remote session this pane shows, or nil for a local pane.
    var remotePaneIdentity: RemotePaneIdentity? {
        RemotePanes.identity(for: id)
    }
}
