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

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory)

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == paneID.uuidString)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryEnvironmentKey] == socketDirectory)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryModeEnvironmentKey] == "0700")
        #expect(config.environmentVariables["TERM"] == "xterm-256color")
    }

    @Test func splitInheritingParentMarkerGetsItsOwnSession() {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory)

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == paneID.uuidString)
    }

    @Test func disabledOrUnavailableRemovesAnInheritedMarker() {
        for (enabled, zmxAvailable) in [(false, true), (true, false)] {
            var config = YEN.SurfaceConfiguration()
            config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

            PersistentSessions.prepare(&config, paneID: paneID, enabled: enabled, zmxAvailable: zmxAvailable, socketDirectory: socketDirectory)

            #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
        }
    }

    @Test func paneStartedForAnExplicitCommandStaysEphemeral() {
        var config = YEN.SurfaceConfiguration()
        config.command = "/usr/bin/top"
        config.environmentVariables[PersistentSessions.environmentKey] = parentID.uuidString

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: socketDirectory)

        #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
        #expect(config.environmentVariables[PersistentSessions.socketDirectoryEnvironmentKey] == nil)
    }

    @Test func socketPathOverTheUnixLimitStaysEphemeral() {
        let longDirectory = "/Users/" + String(repeating: "u", count: 70) + "/.local/state/yen/zmx"
        var config = YEN.SurfaceConfiguration()

        PersistentSessions.prepare(&config, paneID: paneID, enabled: true, zmxAvailable: true, socketDirectory: longDirectory)

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
