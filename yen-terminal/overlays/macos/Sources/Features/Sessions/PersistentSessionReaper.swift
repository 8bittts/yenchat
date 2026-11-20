import AppKit
import Foundation

/// Ends persistent sessions that no pane holds any more (_docs/01-architecture.md
/// -> Persistent sessions).
///
/// An orphan is a session named by a pane UUID, with no attached client, that
/// no terminal window holds. On the first sweep after launch, orphans are
/// reopened in windows (`adoptionCandidates`), so a crash or lost restore state
/// does not strand them; only the ones that stay orphaned are ended later. It appears when restore state is lost, the
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

    static let recordSuffixes = [".tty", ".zmx"]

    /// `.tty` and `.zmx` records whose session socket is gone: zmx deletes its
    /// socket when a shell exits but knows nothing of YEN's records beside it.
    nonisolated static func staleSessionRecords(in fileNames: [String]) -> [String] {
        let names = Set(fileNames)
        return fileNames.filter { file in
            guard let suffix = recordSuffixes.first(where: { file.hasSuffix($0) }) else { return false }
            return !names.contains(String(file.dropLast(suffix.count)))
        }.sorted()
    }

    /// zmx copies under `bin/` that no live session records and that are not
    /// the current build.
    nonisolated static func unusedBinaryCopies(_ copies: [String], referenced: Set<String>, current: String?) -> [String] {
        copies.filter { path in
            (path as NSString).lastPathComponent.hasPrefix("zmx-") && !referenced.contains(path) && path != current
        }.sorted()
    }

    /// Most windows reopened for orphans at one launch; the rest wait for the reaper.
    static let adoptionLimit = 8

    /// Orphans to reopen in windows on the first sweep after launch. A crash or
    /// lost restore state leaves live sessions with no pane; reopening each in
    /// a window under its own UUID reattaches it instead of letting it age out.
    nonisolated static func adoptionCandidates(
        sessions: [Session],
        heldPaneIDs: Set<String>,
        limit: Int = adoptionLimit
    ) -> [UUID] {
        Array(
            sessions
                .filter { $0.clients == 0 && !heldPaneIDs.contains($0.name) }
                .compactMap { UUID(uuidString: $0.name) }
                .sorted { $0.uuidString < $1.uuidString }
                .prefix(limit)
        )
    }

    // MARK: - Runner

    @MainActor private static var adoptedThisLaunch = false

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
            let manager = FileManager.default
            let files = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
            for record in staleSessionRecords(in: files) {
                try? manager.removeItem(atPath: (directory as NSString).appendingPathComponent(record))
            }
            let remaining = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
            let referenced = Set(remaining.filter { $0.hasSuffix(".zmx") }.compactMap { record in
                (try? String(contentsOfFile: (directory as NSString).appendingPathComponent(record), encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            })
            let binDirectory = PersistentSessions.binaryDirectory(socketDirectory: directory)
            let copies = ((try? manager.contentsOfDirectory(atPath: binDirectory)) ?? [])
                .map { (binDirectory as NSString).appendingPathComponent($0) }
            let current = PersistentSessions.currentBinaryCopy(bundled: zmx, socketDirectory: directory)
            for copy in unusedBinaryCopies(copies, referenced: referenced, current: current) {
                try? manager.removeItem(atPath: copy)
            }
            guard let resources = Bundle.main.resourceURL else { return }
            let helper = resources.appendingPathComponent("lib/list-pane-sessions.sh").path
            guard let listing = run("/bin/bash", [helper, directory, zmx], directory, accepting: [0, 2]) else { return }
            let sessions = parseList(listing)
            let kill: [String] = await MainActor.run {
                guard !PersistentSessions.isTerminating else { return [] }
                if !adoptedThisLaunch {
                    adoptedThisLaunch = true
                    let held = Set(heldPaneIDs().map(\.uuidString))
                    for paneID in adoptionCandidates(sessions: sessions, heldPaneIDs: held) {
                        reopen(paneID)
                    }
                }
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
                let binary = UUID(uuidString: name).flatMap {
                    PersistentSessions.recordedBinary(for: $0, socketDirectory: directory)
                } ?? zmx
                guard run(binary, ["kill", name], directory) != nil else { continue }
                for suffix in recordSuffixes {
                    try? FileManager.default.removeItem(atPath: (directory as NSString).appendingPathComponent(name + suffix))
                }
            }
        }
    }

    /// Open a window whose pane has the session's UUID; `PersistentSessions.prepare`
    /// then attaches it to that session.
    @MainActor static func reopen(_ paneID: UUID) {
        guard let yen = (NSApp.delegate as? AppDelegate)?.yen, let app = yen.app else { return }
        let view = YEN.SurfaceView(app, baseConfig: nil, uuid: paneID)
        _ = TerminalController.newWindow(yen, tree: SplitTree(view: view))
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
    nonisolated private static func run(_ path: String, _ arguments: [String], _ directory: String, accepting statuses: Set<Int32> = [0]) -> String? {
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
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, statuses.contains(process.terminationStatus) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
