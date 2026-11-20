import AppKit
import Foundation

/// Ends persistent sessions that no pane holds any more (_docs/01-architecture.md
/// -> Persistent sessions).
///
/// An orphan is a session named by a pane UUID, with no attached client, that
/// no terminal window holds. It appears when restore state is lost, the
/// preference is turned off before a relaunch, or the app crashes between a
/// close and its delayed kill. A detached session may still be running work the
/// user cares about, so an orphan is ended only after it has been seen orphaned
/// continuously for `orphanGrace`; the first sighting is remembered across
/// launches.
enum PersistentSessionReaper {
    struct Session: Equatable {
        let name: String
        let clients: Int
    }

    static let firstSeenDefaultsKey = "com.yenchat.yen.persistentSessionOrphansFirstSeen"
    static let graceDefaultsKey = "com.yenchat.yen.persistentSessionOrphanGraceSeconds"
    static let intervalDefaultsKey = "com.yenchat.yen.persistentSessionReaperIntervalSeconds"
    static let defaultOrphanGrace: TimeInterval = 24 * 60 * 60
    static let defaultInterval: TimeInterval = 10 * 60
    /// Restore recreates windows asynchronously; give it time before the first sweep.
    static let launchSettle: TimeInterval = 30

    /// Parse `zmx ls`. Rows carrying `err=` describe a socket zmx could not
    /// reach and are skipped, so an unreachable session is never ended here.
    nonisolated static func parseList(_ output: String) -> [Session] {
        output.split(separator: "\n").compactMap { line in
            guard let start = line.range(of: "name=") else { return nil }
            var fields: [String: String] = [:]
            for field in line[start.lowerBound...].split(separator: "\t") {
                guard let eq = field.firstIndex(of: "=") else { continue }
                fields[String(field[..<eq])] = String(field[field.index(after: eq)...])
            }
            guard fields["err"] == nil,
                  let name = fields["name"], !name.isEmpty,
                  let clients = fields["clients"].flatMap(Int.init) else { return nil }
            return Session(name: name, clients: clients)
        }
    }

    /// Decide which sessions to end and the first-seen record to keep.
    nonisolated static func sweep(
        sessions: [Session],
        heldPaneIDs: Set<String>,
        firstSeen: [String: Date],
        now: Date,
        grace: TimeInterval
    ) -> (kill: [String], firstSeen: [String: Date]) {
        var next: [String: Date] = [:]
        var kill: [String] = []
        for session in sessions {
            // Only YEN pane sessions; anything else in the directory is not ours to end.
            guard UUID(uuidString: session.name) != nil else { continue }
            guard session.clients == 0, !heldPaneIDs.contains(session.name) else { continue }
            let seen = firstSeen[session.name] ?? now
            if now.timeIntervalSince(seen) >= grace {
                kill.append(session.name)
            } else {
                next[session.name] = seen
            }
        }
        return (kill.sorted(), next)
    }

    // MARK: - Runner

    @MainActor private static var timer: Timer?

    /// Start periodic sweeps; the first runs after restore has settled.
    @MainActor static func start() {
        let defaults = UserDefaults.standard
        guard timer == nil, PersistentSessions.zmxPath() != nil else { return }
        let interval = positive(defaults.double(forKey: intervalDefaultsKey)) ?? defaultInterval
        DispatchQueue.main.asyncAfter(deadline: .now() + min(launchSettle, interval)) {
            runOnce()
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { runOnce() }
            }
            // A sweep minutes apart needs no precision; let the system coalesce it.
            timer?.tolerance = interval * 0.2
        }
    }

    @MainActor static func runOnce() {
        guard !PersistentSessions.isTerminating, let zmx = PersistentSessions.zmxPath() else { return }
        let directory = PersistentSessions.socketDirectory()
        guard FileManager.default.fileExists(atPath: directory) else { return }
        let grace = positive(UserDefaults.standard.double(forKey: graceDefaultsKey)) ?? defaultOrphanGrace

        Task.detached(priority: .utility) {
            let sessions = parseList(run(zmx, ["ls"], directory))
            let kill: [String] = await MainActor.run {
                guard !PersistentSessions.isTerminating else { return [] }
                let held = Set(heldPaneIDs().map(\.uuidString))
                let defaults = UserDefaults.standard
                let firstSeen = (defaults.dictionary(forKey: firstSeenDefaultsKey) as? [String: Date]) ?? [:]
                let result = sweep(sessions: sessions, heldPaneIDs: held, firstSeen: firstSeen, now: Date(), grace: grace)
                defaults.set(result.firstSeen, forKey: firstSeenDefaultsKey)
                return result.kill
            }
            for name in kill where !PersistentSessions.isTerminating {
                run(zmx, ["kill", name], directory)
            }
        }
    }

    @MainActor static func heldPaneIDs() -> [UUID] {
        NSApp.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .flatMap { controller in controller.surfaceTree.map(\.id) }
    }

    nonisolated private static func positive(_ value: Double) -> TimeInterval? {
        value > 0 ? value : nil
    }

    @discardableResult
    nonisolated private static func run(_ path: String, _ arguments: [String], _ directory: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            [PersistentSessions.socketDirectoryEnvironmentKey: directory]
        ) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
