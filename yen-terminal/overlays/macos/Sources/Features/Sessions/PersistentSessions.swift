import AppKit
import CryptoKit
import Foundation

/// Persistent sessions: a pane runs inside the bundled zmx so its shell keeps
/// running when the app quits, crashes or updates (_docs/01-architecture.md ->
/// Persistent sessions).
///
/// The app only marks a pane. `prepare` sets `YEN_PERSISTENT_SESSION=<pane UUID>`
/// and the socket directory; the engine (`src/termio/yen_session.zig`) wraps the
/// final shell command in `zmx attach <pane UUID>` after shell integration, so
/// integration still applies to the shell zmx starts. A restored pane keeps its
/// UUID, so the same call reattaches it.
///
/// Lifecycle: closing a pane ends its session; quitting, crashing or updating
/// the app only detaches. A pane that leaves its split tree or window
/// (`paneLeftTree`) is checked once the undo-close window has expired, and its
/// session ends if no terminal window holds it any more. Ghostty can keep a
/// closed pane alive long after that, so `SurfaceView.deinit` is only the fast
/// path (`paneDidClose`). Both are ignored after `applicationWillTerminate`, and
/// a crash runs neither.
enum PersistentSessions {
    static let enabledDefaultsKey = "com.yenchat.yen.persistentSessions"
    static let environmentKey = "YEN_PERSISTENT_SESSION"
    static let socketDirectoryEnvironmentKey = "ZMX_DIR"
    static let socketDirectoryModeEnvironmentKey = "ZMX_DIR_MODE"
    static let socketDirectoryMode = "0700"
    /// The zmx build that attaches this pane's session (yen_session.zig).
    static let binaryEnvironmentKey = "YEN_PERSISTENT_SESSION_ZMX"

    /// A Unix socket path holds at most 104 bytes including its terminator on
    /// macOS; zmx refuses a longer `<dir>/<name>` with `NameTooLong`.
    static let maxSocketPathLength = 103

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    /// Sessions live under the user's state directory, not `$TMPDIR` or `/tmp`,
    /// which macOS clears of old files on a schedule.
    nonisolated static func socketDirectory(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent(".local/state/yen/zmx")
    }

    nonisolated static func zmxPath(resourcePath: String? = Bundle.main.resourcePath) -> String? {
        guard let resourcePath else { return nil }
        let path = (resourcePath as NSString).appendingPathComponent("bin/zmx")
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    nonisolated static func sessionName(for paneID: UUID) -> String {
        paneID.uuidString
    }

    /// The patched zmx daemon records a session's inner pty path here; the
    /// engine reads it for password-prompt detection (yen_session.zig).
    nonisolated static func ttyRecordPath(for paneID: UUID, socketDirectory: String) -> String {
        socketPath(for: paneID, socketDirectory: socketDirectory) + ".tty"
    }

    /// Which zmx build started a session. A Sparkle update or vendor bump can
    /// ship a zmx with another protocol, so a session is always attached and
    /// ended with the build that created it.
    nonisolated static func binaryRecordPath(for paneID: UUID, socketDirectory: String) -> String {
        socketPath(for: paneID, socketDirectory: socketDirectory) + ".zmx"
    }

    nonisolated static func binaryDirectory(socketDirectory: String) -> String {
        (socketDirectory as NSString).appendingPathComponent("bin")
    }

    nonisolated static func recordedBinary(for paneID: UUID, socketDirectory: String) -> String? {
        let record = binaryRecordPath(for: paneID, socketDirectory: socketDirectory)
        guard let path = try? String(contentsOfFile: record, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    nonisolated(unsafe) private static var binaryCopyCache: [String: String] = [:]
    private static let binaryCopyLock = NSLock()

    /// A digest-named copy of the bundled zmx under the socket directory. It
    /// outlives the app bundle, so an update cannot remove the build a running
    /// session needs.
    nonisolated static func currentBinaryCopy(bundled: String, socketDirectory: String) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: bundled)
        let stamp = "\((attributes?[.size] as? NSNumber)?.int64Value ?? -1):\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1)"
        let key = [bundled, stamp, socketDirectory].joined(separator: "\u{0}")
        if let cached = binaryCopyLock.withLock({ binaryCopyCache[key] }),
           FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: bundled), options: .mappedIfSafe) else { return nil }
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let directory = binaryDirectory(socketDirectory: socketDirectory)
        let target = (directory as NSString).appendingPathComponent("zmx-\(digest)")
        let manager = FileManager.default
        if !manager.isExecutableFile(atPath: target) {
            do {
                try manager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let staging = (directory as NSString).appendingPathComponent(".zmx-\(UUID().uuidString)")
                try manager.copyItem(atPath: bundled, toPath: staging)
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging)
                if rename(staging, target) != 0 {
                    try? manager.removeItem(atPath: staging)
                    guard manager.isExecutableFile(atPath: target) else { return nil }
                }
            } catch {
                return nil
            }
        }
        binaryCopyLock.withLock { binaryCopyCache[key] = target }
        return target
    }

    /// The build that should attach this pane. A live session keeps the build
    /// recorded for it; a session without a record predates the record and uses
    /// the current build; a new session records the current build.
    nonisolated static func sessionBinary(
        for paneID: UUID,
        socketDirectory: String,
        bundled: String? = zmxPath()
    ) -> String? {
        if hasSession(paneID, socketDirectory: socketDirectory),
           let recorded = recordedBinary(for: paneID, socketDirectory: socketDirectory) {
            return recorded
        }
        guard let bundled, let current = currentBinaryCopy(bundled: bundled, socketDirectory: socketDirectory) else {
            return nil
        }
        if !hasSession(paneID, socketDirectory: socketDirectory) {
            try? current.write(
                toFile: binaryRecordPath(for: paneID, socketDirectory: socketDirectory),
                atomically: true,
                encoding: .utf8
            )
        }
        return current
    }

    nonisolated static func socketPath(for paneID: UUID, socketDirectory: String) -> String {
        (socketDirectory as NSString).appendingPathComponent(sessionName(for: paneID))
    }

    /// Mark a new or restored pane to run inside its own session.
    ///
    /// The marker is always overwritten or removed: a split or tab inherits its
    /// parent's environment, and an inherited marker would attach the new pane
    /// to the parent's session.
    static func prepare(
        _ config: inout YEN.SurfaceConfiguration,
        paneID: UUID,
        enabled: Bool = isEnabled,
        zmxAvailable: Bool = zmxPath() != nil,
        socketDirectory: String = socketDirectory(),
        resolveBinary: (UUID, String) -> String? = { sessionBinary(for: $0, socketDirectory: $1) }
    ) {
        config.environmentVariables.removeValue(forKey: environmentKey)
        config.environmentVariables.removeValue(forKey: binaryEnvironmentKey)

        // A pane started for an explicit command (AppleScript, a palette
        // action, a file opener) stays ephemeral: its command is the point.
        guard enabled, zmxAvailable, config.command == nil else { return }
        guard socketPath(for: paneID, socketDirectory: socketDirectory).utf8.count <= maxSocketPathLength else { return }

        config.environmentVariables[environmentKey] = sessionName(for: paneID)
        config.environmentVariables[socketDirectoryEnvironmentKey] = socketDirectory
        config.environmentVariables[socketDirectoryModeEnvironmentKey] = socketDirectoryMode
        if let binary = resolveBinary(paneID, socketDirectory) {
            config.environmentVariables[binaryEnvironmentKey] = binary
        }
    }

    /// True when the pane runs inside a live session, which survives a quit.
    nonisolated static func hasSession(_ paneID: UUID, socketDirectory: String = socketDirectory()) -> Bool {
        FileManager.default.fileExists(atPath: socketPath(for: paneID, socketDirectory: socketDirectory))
    }

    /// Quitting kills a pane's process only when the pane is not in a live
    /// session; a session survives the quit, so it needs no confirmation.
    nonisolated static func quitKillsProcess(
        needsConfirmQuit: Bool,
        paneID: UUID,
        hasSession: (UUID) -> Bool = { hasSession($0) }
    ) -> Bool {
        needsConfirmQuit && !hasSession(paneID)
    }

    // MARK: - Lifecycle

    private static let terminationLock = NSLock()
    nonisolated(unsafe) private static var terminating = false

    /// Called from `applicationWillTerminate`: from here on a pane teardown is
    /// the app going away, not the user closing the pane.
    nonisolated static func markTerminating() {
        terminationLock.withLock { terminating = true }
    }

    nonisolated static var isTerminating: Bool {
        terminationLock.withLock { terminating }
    }

    /// End the session of a pane the user closed. Safe from any thread and for
    /// a pane that never had a session: it only acts when the session's socket
    /// exists.
    nonisolated static func paneDidClose(
        _ paneID: UUID,
        socketDirectory: String = socketDirectory(),
        zmxPath: String? = zmxPath(),
        terminating: Bool = isTerminating,
        run: (String, [String], [String: String]) -> Void = launchDetached
    ) {
        guard !terminating, let zmxPath else { return }
        guard hasSession(paneID, socketDirectory: socketDirectory) else { return }
        let binary = recordedBinary(for: paneID, socketDirectory: socketDirectory) ?? zmxPath
        run(binary, ["kill", sessionName(for: paneID)], [socketDirectoryEnvironmentKey: socketDirectory])
        try? FileManager.default.removeItem(atPath: ttyRecordPath(for: paneID, socketDirectory: socketDirectory))
        try? FileManager.default.removeItem(atPath: binaryRecordPath(for: paneID, socketDirectory: socketDirectory))
    }

    /// Grace added to the undo timeout before a departed pane is judged closed.
    static let closeGrace: Duration = .seconds(2)

    /// A pane left its split tree or its window closed. Once undo can no longer
    /// bring it back, end its session unless a terminal window holds it again
    /// (an undone close, or a pane moved to another window).
    static func paneLeftTree(
        _ paneID: UUID,
        undoExpiration: Duration,
        socketDirectory: String = socketDirectory(),
        isStillPresent: @escaping @MainActor (UUID) -> Bool = paneIsInAnyTerminalWindow,
        close: @escaping @MainActor (UUID) -> Void = { paneDidClose($0) }
    ) {
        guard hasSession(paneID, socketDirectory: socketDirectory) else { return }
        let delay = seconds(undoExpiration + closeGrace)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !isTerminating, !isStillPresent(paneID) else { return }
            close(paneID)
        }
    }

    /// A terminal window is closing; each of its panes is judged like a pane
    /// that left its tree, because undo can reopen the window.
    static func panesLeftClosingWindow(_ paneIDs: [UUID], undoExpiration: Duration) {
        for paneID in paneIDs {
            paneLeftTree(paneID, undoExpiration: undoExpiration)
        }
    }

    static func paneIsInAnyTerminalWindow(_ paneID: UUID) -> Bool {
        NSApp.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .contains { controller in controller.surfaceTree.contains { $0.id == paneID } }
    }

    nonisolated static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    nonisolated private static func launchDetached(_ path: String, _ arguments: [String], _ environment: [String: String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
