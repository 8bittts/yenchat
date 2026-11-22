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
        guard let identity, let command = attachCommand(for: identity) else {
            registry.withLock { $0.identities[paneID] = nil }
            return
        }
        config.command = command
        // Keep a failed attach on screen: the CLI's message says why.
        config.waitAfterCommand = true
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

    nonisolated static func attachCommand(for identity: RemotePaneIdentity) -> String? {
        guard let cliPath = cliPath() else { return nil }
        return RemoteSessions.attachCommandLine(host: identity.sshTarget, id: identity.sessionID, cliPath: cliPath)
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

    /// The title of a tab or window whose title surface is `surface`: the host
    /// first, so a remote shell is never mistaken for a local one, even under a
    /// typed tab title. Called from the engine's `computeTitle` (patch
    /// `remote-pane-tab-title`).
    @MainActor static func tabTitle(_ title: String, for surface: YEN.SurfaceView?) -> String {
        guard let surface, let identity = identity(for: surface.id) else { return title }
        return tabTitle(title, host: identity.displayName)
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

    /// The open pane already attached to this session, if any.
    @MainActor static func existingPane(
        for identity: RemotePaneIdentity,
        in controllers: [BaseTerminalController]? = nil
    ) -> YEN.SurfaceView? {
        for controller in controllers ?? TerminalController.all {
            for surface in controller.surfaceTree {
                if let other = Self.identity(for: surface.id), other.isSameSession(as: identity) { return surface }
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
