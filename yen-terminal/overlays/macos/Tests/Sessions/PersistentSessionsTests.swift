import Foundation
import Testing
@testable import YEN

struct PersistentSessionsTests {
    private let paneID = UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!
    private let parentID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let socketDirectory = "/Users/dev/.local/state/yen/zmx"

    @Test func preparedPaneCarriesItsOwnSessionAndSocketDirectory() {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables = ["TERM": "xterm-256color"]

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory, resolveBinary: { _, _ in "/z/zmx-test" })

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == paneID.uuidString)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryEnvironmentKey] == socketDirectory)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryModeEnvironmentKey] == "0700")
        #expect(config.environmentVariables[PersistentSessions.binaryEnvironmentKey] == "/z/zmx-test")
        #expect(config.environmentVariables["TERM"] == "xterm-256color")
    }

    @Test func splitInheritingParentMarkerGetsItsOwnSession() {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory, resolveBinary: { _, _ in "/z/zmx-test" })

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == paneID.uuidString)
    }

    @Test func disabledOrUnavailableRemovesAnInheritedMarker() {
        for (enabled, zmxAvailable) in [(false, true), (true, false)] {
            var config = YEN.SurfaceConfiguration()
            config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

            PersistentSessions.prepare(&config, paneID: paneID, enabled: enabled, zmxAvailable: zmxAvailable, socketDirectory: socketDirectory, resolveBinary: { _, _ in "/z/zmx-test" })

            #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
        }
    }

    @Test func paneStartedForAnExplicitCommandStaysEphemeral() {
        var config = YEN.SurfaceConfiguration()
        config.command = "/usr/bin/top"
        config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory, resolveBinary: { _, _ in "/z/zmx-test" })

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryEnvironmentKey] == nil)
    }

    @Test func socketPathOverTheUnixLimitStaysEphemeral() {
        let longDirectory = "/Users/" + String(repeating: "u", count: 70) + "/.local/state/yen/zmx"
        var config = YEN.SurfaceConfiguration()

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: longDirectory, resolveBinary: { _, _ in "/z/zmx-test" })

        #expect(PersistentSessions.socketPath(for: paneID, socketDirectory: longDirectory).utf8.count > PersistentSessions.maxSocketPathLength)
        #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
    }

    @MainActor @Test func departedPaneEndsAfterUndoUnlessAWindowHoldsItAgain() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-persistent-left-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let undoneID = UUID()
        let closedID = UUID()
        let ephemeralID = UUID()
        for id in [undoneID, closedID] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(id.uuidString).path, contents: Data())
        }

        var closed: [UUID] = []
        for id in [undoneID, closedID, ephemeralID] {
            PersistentSessions.paneLeftTree(
                id,
                undoExpiration: .zero,
                socketDirectory: directory.path,
                isStillPresent: { $0 == undoneID },
                close: { closed.append($0) }
            )
        }

        #expect(closed.isEmpty)
        try await Task.sleep(for: PersistentSessions.closeGrace + .milliseconds(800))
        #expect(closed == [closedID])
    }

    @MainActor @Test func quittingInsideTheUndoWindowEndsTheSessionOfAClosedPane() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-persistent-quit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let closedID = UUID()
        let undoneID = UUID()
        for id in [closedID, undoneID] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(id.uuidString).path, contents: Data())
        }

        // Both panes left their windows a moment ago; undo brought one back.
        var closed: [UUID] = []
        for id in [closedID, undoneID] {
            PersistentSessions.paneLeftTree(
                id,
                undoExpiration: .seconds(600),
                socketDirectory: directory.path,
                isStillPresent: { _ in false },
                close: { closed.append($0) }
            )
        }

        // The app quits before the undo window ends, so the delayed check never runs.
        PersistentSessions.endDepartedPanes(isStillPresent: { $0 == undoneID }, close: { closed.append($0) })
        #expect(closed == [closedID])

        // Each departed pane is judged once.
        PersistentSessions.endDepartedPanes(isStillPresent: { _ in false }, close: { closed.append($0) })
        #expect(closed == [closedID])
    }

    @Test func aNewSessionRecordsTheCurrentBuildAndALiveOneKeepsItsRecordedBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yen-zmx-binary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appendingPathComponent("bundled-zmx").path
        FileManager.default.createFile(atPath: bundled, contents: Data("zmx build one".utf8), attributes: [.posixPermissions: 0o755])
        let socketDirectory = root.appendingPathComponent("zmx").path
        try FileManager.default.createDirectory(atPath: socketDirectory, withIntermediateDirectories: true)

        // New pane: the current build is copied out of the bundle and recorded.
        let first = try #require(PersistentSessions.sessionBinary(for: paneID, socketDirectory: socketDirectory, bundled: bundled))
        #expect(first.hasPrefix(PersistentSessions.binaryDirectory(socketDirectory: socketDirectory) + "/zmx-"))
        #expect(PersistentSessions.recordedBinary(for: paneID, socketDirectory: socketDirectory) == first)

        // The session is live and the app updates to another zmx build.
        FileManager.default.createFile(atPath: PersistentSessions.socketPath(for: paneID, socketDirectory: socketDirectory), contents: Data())
        try Data("zmx build two, longer".utf8).write(to: URL(fileURLWithPath: bundled))
        let afterUpdate = try #require(PersistentSessions.sessionBinary(for: paneID, socketDirectory: socketDirectory, bundled: bundled))
        #expect(afterUpdate == first)

        // A new pane after the update gets the new build.
        let newPane = UUID()
        let second = try #require(PersistentSessions.sessionBinary(for: newPane, socketDirectory: socketDirectory, bundled: bundled))
        #expect(second != first)
        #expect(FileManager.default.isExecutableFile(atPath: second))
    }

    @Test func onlyTheReleaseAppKeepsSessionsByDefaultAndAnExplicitChoiceWins() throws {
        let suite = "yen-persistent-sessions-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: "com.yenchat.yen"))
        #expect(!PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: "com.yenchat.yen.debug"))
        #expect(!PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: "com.yenchat.yenverify"))
        #expect(!PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: nil))

        defaults.set(false, forKey: PersistentSessions.enabledDefaultsKey)
        #expect(!PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: "com.yenchat.yen"))
        defaults.set(true, forKey: PersistentSessions.enabledDefaultsKey)
        #expect(PersistentSessions.isEnabled(defaults: defaults, bundleIdentifier: "com.yenchat.yen.debug"))
    }

    @Test func turningThePreferenceOffKeepsAttachingALiveSession() throws {
        // Short on purpose: a socket path over 103 bytes keeps a pane ephemeral.
        let directory = URL(fileURLWithPath: "/tmp/yps-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appendingPathComponent(paneID.uuidString).path, contents: Data())

        var restored = YEN.SurfaceConfiguration()
        PersistentSessions.prepare(
            &restored, paneID: paneID, enabled: false, zmxAvailable: true,
            socketDirectory: directory.path, resolveBinary: { _, _ in "/z/zmx-test" }
        )
        #expect(restored.environmentVariables[PersistentSessions.environmentKey] == paneID.uuidString)

        var fresh = YEN.SurfaceConfiguration()
        PersistentSessions.prepare(
            &fresh, paneID: UUID(), enabled: false, zmxAvailable: true,
            socketDirectory: directory.path, resolveBinary: { _, _ in "/z/zmx-test" }
        )
        #expect(fresh.environmentVariables[PersistentSessions.environmentKey] == nil)
    }

    @Test func onlyPaneSessionSocketsCountAsSessions() {
        let names = [paneID.uuidString, "\(paneID.uuidString).tty", "\(parentID.uuidString).zmx", "bin", "dev", "notes.txt"]
        #expect(PersistentSessions.sessionIDs(in: names) == [paneID])
    }

    @Test func endAllEndsEverySessionSocketAndSkipsPlainFiles() throws {
        // Short on purpose: a Unix socket path must stay under 104 bytes.
        let directory = "/tmp/yps-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let live = [paneID, parentID]
        var sockets: [Int32] = []
        for id in live {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = PersistentSessions.socketPath(for: id, socketDirectory: directory)
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.copyBytes(from: Array(path.utf8) + [0])
            }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            #expect(bound == 0)
            sockets.append(fd)
        }
        defer { sockets.forEach { close($0) } }
        // A plain file with a session name is not a session.
        let plain = UUID()
        FileManager.default.createFile(atPath: "\(directory)/\(plain.uuidString)", contents: Data())

        var killed: [String] = []
        let ended = PersistentSessions.endAllSessions(socketDirectory: directory, zmxPath: "/z/zmx") { _, arguments, _ in
            killed.append(arguments.last ?? "")
        }

        #expect(ended == 2)
        #expect(killed.sorted() == live.map(\.uuidString).sorted())
    }

    @Test func failedSessionEndPreservesRecoveryRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let socket = directory.appendingPathComponent(paneID.uuidString)
        try Data().write(to: socket)
        let binary = socket.appendingPathExtension("zmx")
        let tty = socket.appendingPathExtension("tty")
        try "/usr/bin/false".write(to: binary, atomically: true, encoding: .utf8)
        try "/dev/tty".write(to: tty, atomically: true, encoding: .utf8)

        PersistentSessions.paneDidClose(paneID, socketDirectory: directory.path, zmxPath: "/usr/bin/false", terminating: false)
        #expect(FileManager.default.fileExists(atPath: binary.path))
        #expect(FileManager.default.fileExists(atPath: tty.path))
    }

    @Test func quittingAsksOnlyAboutPanesWithoutALiveSession() {
        #expect(PersistentSessions.quitKillsProcess(needsConfirmQuit: true, paneID: paneID) { _ in false })
        #expect(!PersistentSessions.quitKillsProcess(needsConfirmQuit: true, paneID: paneID) { _ in true })
        #expect(!PersistentSessions.quitKillsProcess(needsConfirmQuit: false, paneID: paneID) { _ in false })
    }

    @Test func closingAPaneEndsOnlyAnExistingSessionAndNeverDuringQuit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-persistent-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var calls: [(String, [String], [String: String])] = []
        let record: (String, [String], [String: String]) -> Void = { calls.append(($0, $1, $2)) }

        PersistentSessions.paneDidClose(paneID, socketDirectory: directory.path, zmxPath: "/z/zmx", terminating: false, run: record)
        #expect(calls.isEmpty)

        FileManager.default.createFile(atPath: directory.appendingPathComponent(paneID.uuidString).path, contents: Data())

        PersistentSessions.paneDidClose(paneID, socketDirectory: directory.path, zmxPath: "/z/zmx", terminating: true, run: record)
        #expect(calls.isEmpty)

        PersistentSessions.paneDidClose(paneID, socketDirectory: directory.path, zmxPath: "/z/zmx", terminating: false, run: record)
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "/z/zmx")
        #expect(calls.first?.1 == ["kill", paneID.uuidString])
        #expect(calls.first?.2 == [PersistentSessions.socketDirectoryEnvironmentKey: directory.path])
    }
}
