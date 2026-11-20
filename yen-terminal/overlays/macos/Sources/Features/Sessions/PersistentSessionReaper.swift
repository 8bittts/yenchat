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
/// continuously for `orphanGrace`. Sightings persist across launches but reset
/// when the previous sweep is older than `observationGap` intervals, because a
/// session detached while YEN was quit was never observed. Only an app with the
/// preference on sweeps, so a Debug build or test host sharing the socket
/// directory never ends the release app's sessions.
enum PersistentSessionReaper {
    struct Session: Equatable {
        let name: String
        let clients: Int
    }

    static let firstSeenDefaultsKey = "com.yenchat.yen.persistentSessionOrphansFirstSeen"
    static let lastSweepDefaultsKey = "com.yenchat.yen.persistentSessionReaperLastSweep"
    /// Sweeps further apart than this many intervals break continuous observation.
    static let observationGap: Double = 3
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
        lastSweep: Date?,
        now: Date,
        grace: TimeInterval,
        interval: TimeInterval
    ) -> (kill: [String], firstSeen: [String: Date]) {
        // Without an unbroken run of sweeps, no orphan was watched; start over.
        let watched = lastSweep.map { now.timeIntervalSince($0) <= interval * observationGap } ?? false
        let firstSeen = watched ? firstSeen : [:]
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

    /// `.tty` records whose session socket is gone: zmx deletes its socket when
    /// a shell exits but knows nothing of YEN's record beside it.
    nonisolated static func staleTtyRecords(in fileNames: [String]) -> [String] {
        let names = Set(fileNames)
        return fileNames.filter { file in
            file.hasSuffix(".tty") && !names.contains(String(file.dropLast(".tty".count)))
        }.sorted()
    }

    // MARK: - Runner

    @MainActor private static var timer: Timer?

    /// Start periodic sweeps; the first runs after restore has settled.
    @MainActor static func start() {
        let defaults = UserDefaults.standard
        guard timer == nil, PersistentSessions.isEnabled, PersistentSessions.zmxPath() != nil else { return }
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
        guard !PersistentSessions.isTerminating, PersistentSessions.isEnabled, let zmx = PersistentSessions.zmxPath() else { return }
        let directory = PersistentSessions.socketDirectory()
        guard FileManager.default.fileExists(atPath: directory) else { return }
        let grace = positive(UserDefaults.standard.double(forKey: graceDefaultsKey)) ?? defaultOrphanGrace
        let interval = positive(UserDefaults.standard.double(forKey: intervalDefaultsKey)) ?? defaultInterval

        Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for record in staleTtyRecords(in: files) {
                try? FileManager.default.removeItem(atPath: (directory as NSString).appendingPathComponent(record))
            }
            let sessions = parseList(run(zmx, ["ls"], directory))
            let kill: [String] = await MainActor.run {
                guard !PersistentSessions.isTerminating else { return [] }
                let held = Set(heldPaneIDs().map(\.uuidString))
                let defaults = UserDefaults.standard
                let firstSeen = (defaults.dictionary(forKey: firstSeenDefaultsKey) as? [String: Date]) ?? [:]
                let lastSweep = defaults.object(forKey: lastSweepDefaultsKey) as? Date
                let now = Date()
                let result = sweep(
                    sessions: sessions, heldPaneIDs: held, firstSeen: firstSeen,
                    lastSweep: lastSweep, now: now, grace: grace, interval: interval
                )
                defaults.set(result.firstSeen, forKey: firstSeenDefaultsKey)
                defaults.set(now, forKey: lastSweepDefaultsKey)
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
