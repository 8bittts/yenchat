import Foundation
import Testing
@testable import YEN

struct PersistentSessionReaperTests {
    private let orphan = "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C"
    private let held = "11111111-2222-3333-4444-555555555555"
    private let attached = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesZmxListRowsAndSkipsUnreachableSockets() {
        let output = [
            "  name=\(orphan)\tpid=10\tclients=0\tcreated=1\tcwd=file://host/Users/dev\tcmd=/bin/zsh",
            "→ name=\(held)\tpid=11\tclients=2\tcreated=1",
            "name=dev\tpid=12\tclients=1\tcreated=1",
            "  name=\(attached)\terr=ConnectionRefused\tstatus=stale",
            "no sessions found in /Users/dev/.local/state/yen/zmx",
        ].joined(separator: "\n")

        #expect(PersistentSessionReaper.parseList(output) == [
            .init(name: orphan, clients: 0),
            .init(name: held, clients: 2),
            .init(name: "dev", clients: 1),
        ])
    }

    @Test func orphanIsRememberedOnFirstSightingAndEndedOnlyAfterTheGrace() {
        let sessions: [PersistentSessionReaper.Session] = [.init(name: orphan, clients: 0)]

        let first = PersistentSessionReaper.sweep(sessions: sessions, heldPaneIDs: [], firstSeen: [:], lastSweep: nil, now: start, grace: 60, interval: 10)
        #expect(first.kill.isEmpty)
        #expect(first.firstSeen == [orphan: start])

        let early = PersistentSessionReaper.sweep(sessions: sessions, heldPaneIDs: [], firstSeen: first.firstSeen, lastSweep: start + 50, now: start + 59, grace: 60, interval: 10)
        #expect(early.kill.isEmpty)
        #expect(early.firstSeen == [orphan: start])

        let due = PersistentSessionReaper.sweep(sessions: sessions, heldPaneIDs: [], firstSeen: first.firstSeen, lastSweep: start + 59, now: start + 60, grace: 60, interval: 10)
        #expect(due.kill == [orphan])
        #expect(due.firstSeen.isEmpty)
    }

    @Test func heldAttachedAndForeignSessionsAreNeverEndedAndForgetTheirSighting() {
        let sessions: [PersistentSessionReaper.Session] = [
            .init(name: held, clients: 0),
            .init(name: attached, clients: 1),
            .init(name: "dev", clients: 0),
        ]
        let stale = Date(timeIntervalSince1970: 0)

        let result = PersistentSessionReaper.sweep(
            sessions: sessions,
            heldPaneIDs: [held],
            firstSeen: [held: stale, attached: stale, "dev": stale],
            lastSweep: start - 5,
            now: start,
            grace: 60,
            interval: 10
        )

        #expect(result.kill.isEmpty)
        #expect(result.firstSeen.isEmpty)
    }

    @Test func aGapInSweepsRestartsObservationSoADetachedSessionIsNotEnded() {
        let sessions: [PersistentSessionReaper.Session] = [.init(name: orphan, clients: 0)]
        let longAgo = start - 3 * 24 * 60 * 60

        // YEN was quit for days: the sighting is stale and nothing watched in between.
        let afterGap = PersistentSessionReaper.sweep(
            sessions: sessions, heldPaneIDs: [], firstSeen: [orphan: longAgo],
            lastSweep: longAgo, now: start, grace: 60, interval: 10
        )
        #expect(afterGap.kill.isEmpty)
        #expect(afterGap.firstSeen == [orphan: start])

        // A first sweep ever has nothing to continue either.
        let firstEver = PersistentSessionReaper.sweep(
            sessions: sessions, heldPaneIDs: [], firstSeen: [orphan: longAgo],
            lastSweep: nil, now: start, grace: 60, interval: 10
        )
        #expect(firstEver.kill.isEmpty)
    }

    @Test func sessionRecordsAreStaleOnlyWhenTheirSocketIsGone() {
        let files = [orphan, "\(orphan).tty", "\(orphan).zmx", "\(held).tty", "\(held).zmx", "bin", "logs", "notes.txt", "notes.tty", "notes.zmx"]
        #expect(PersistentSessionReaper.staleSessionRecords(in: files) == ["\(held).tty", "\(held).zmx"])
    }

    @Test func newRecoveryRecordsHaveTimeToAcquireASocket() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let build = try #require(PersistentSessions.currentBinaryCopy(bundled: "/usr/bin/true", socketDirectory: directory.path))
        let record = directory.appendingPathComponent(UUID().uuidString + ".zmx")
        try build.write(to: record, atomically: true, encoding: .utf8)
        let written = try #require(record.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        PersistentSessionReaper.cleanRecoveryFiles(in: directory.path, bundled: "/usr/bin/true", now: written)
        #expect(manager.fileExists(atPath: record.path))
        PersistentSessionReaper.cleanRecoveryFiles(in: directory.path, bundled: "/usr/bin/true", now: written.addingTimeInterval(3600))
        #expect(!manager.fileExists(atPath: record.path))
        #expect(manager.isExecutableFile(atPath: build))
    }

    @Test func onlyUnrecordedNonCurrentZmxCopiesAreUnused() {
        let copies = ["/s/bin/zmx-aaaaaaaaaaaaaaaa", "/s/bin/zmx-bbbbbbbbbbbbbbbb", "/s/bin/zmx-cccccccccccccccc", "/s/bin/.zmx-staging", "/s/bin/zmx-notes", "/s/bin/notes"]
        let unused = PersistentSessionReaper.unusedBinaryCopies(copies, referenced: ["/s/bin/zmx-aaaaaaaaaaaaaaaa"], current: "/s/bin/zmx-cccccccccccccccc")
        #expect(unused == ["/s/bin/zmx-bbbbbbbbbbbbbbbb"])
    }

    @Test func adoptionReopensOnlyUnheldDetachedPaneSessionsUpToTheLimit() {
        let sessions: [PersistentSessionReaper.Session] = [
            .init(name: orphan, clients: 0),
            .init(name: held, clients: 0),
            .init(name: attached, clients: 1),
            .init(name: "dev", clients: 0),
        ]
        let picked = PersistentSessionReaper.adoptionCandidates(sessions: sessions, heldPaneIDs: [held])
        #expect(picked == [UUID(uuidString: orphan)!])

        let many = (0..<12).map { _ in PersistentSessionReaper.Session(name: UUID().uuidString, clients: 0) }
        #expect(PersistentSessionReaper.adoptionCandidates(sessions: many, heldPaneIDs: [], limit: 8).count == 8)
    }
}
