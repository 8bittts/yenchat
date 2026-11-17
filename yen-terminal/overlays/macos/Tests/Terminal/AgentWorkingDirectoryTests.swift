import Combine
import Foundation
import Testing
@testable import YEN

@MainActor
struct AgentWorkingDirectoryTests {
    private let surfaceID = UUID()
    private let worktree = "/repos/yenchat/.worktrees/split-labels-7f3a"

    // MARK: - Effective directory

    @Test func aLiveReportWinsOverTheShellDirectory() {
        let report = AgentWorkingDirectoryReport(directory: worktree, ownerProcessID: 4242)

        #expect(
            AgentWorkingDirectoryRules.effectiveDirectory(
                report: report,
                foregroundProcessID: 4242,
                shellDirectory: "/repos/yenchat"
            ) == worktree
        )
    }

    @Test func theShellDirectoryReturnsOnceTheAgentLeavesTheForeground() {
        let report = AgentWorkingDirectoryReport(directory: worktree, ownerProcessID: 4242)

        // The shell's own process group is in front again, or nothing is.
        #expect(
            AgentWorkingDirectoryRules.effectiveDirectory(
                report: report,
                foregroundProcessID: 1001,
                shellDirectory: "/repos/yenchat"
            ) == "/repos/yenchat"
        )
        #expect(
            AgentWorkingDirectoryRules.effectiveDirectory(
                report: report,
                foregroundProcessID: nil,
                shellDirectory: "/repos/yenchat"
            ) == "/repos/yenchat"
        )
        #expect(
            AgentWorkingDirectoryRules.effectiveDirectory(
                report: nil,
                foregroundProcessID: 4242,
                shellDirectory: "/repos/yenchat"
            ) == "/repos/yenchat"
        )
    }

    // MARK: - Payload

    @Test func aReportIsCanonicalizedLikeTheShellDirectory() throws {
        let directory = try makeTemporaryDirectory()
        let payload = AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: directory.path))

        // NSTemporaryDirectory sits behind the /var -> /private/var symlink.
        #expect(payload?.surfaceID == surfaceID)
        #expect(payload?.change == .report(directory: directory.resolvingSymlinksInPath().path))
    }

    @Test func anEmptyDirectoryClearsTheReport() {
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: ""))?.change == .clear)
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: nil))?.change == .clear)
    }

    @Test func malformedPayloadsAreRejected() throws {
        let directory = try makeTemporaryDirectory().path
        let file = try makeTemporaryFile().path

        #expect(AgentWorkingDirectoryPayload.decode(userInfo: nil) == nil)
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: directory, schema: nil)) == nil)
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: directory, schema: "2")) == nil)
        #expect(
            AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: directory, surfaceID: "pane-7")) == nil
        )
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: "relative/path")) == nil)
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: "~/Documents")) == nil)
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: "/no/such/directory/here")) == nil)
        // A file is not a working directory; git would fail and the pane would lose its label.
        #expect(AgentWorkingDirectoryPayload.decode(userInfo: userInfo(directory: file)) == nil)
    }

    // MARK: - State and receiver

    @Test func aReportBindsToTheProcessInFrontOfThePane() {
        let state = AgentWorkingDirectoryState(shellDirectoryReports: Empty().eraseToAnyPublisher())

        AgentWorkingDirectoryReceiver.apply(.report(directory: worktree), to: state, foregroundProcessID: 4242)

        #expect(state.report == AgentWorkingDirectoryReport(directory: worktree, ownerProcessID: 4242))
    }

    @Test func aReportWithNothingInFrontIsDropped() {
        let state = AgentWorkingDirectoryState(shellDirectoryReports: Empty().eraseToAnyPublisher())

        // Nothing could ever end such a report, so it must not be stored.
        AgentWorkingDirectoryReceiver.apply(.report(directory: worktree), to: state, foregroundProcessID: nil)

        #expect(state.report == nil)
    }

    @Test func anExplicitClearDropsTheReport() {
        let state = AgentWorkingDirectoryState(shellDirectoryReports: Empty().eraseToAnyPublisher())
        AgentWorkingDirectoryReceiver.apply(.report(directory: worktree), to: state, foregroundProcessID: 4242)

        AgentWorkingDirectoryReceiver.apply(.clear, to: state, foregroundProcessID: 4242)

        #expect(state.report == nil)
    }

    @Test func theShellReportingItsDirectoryClearsTheAgentReport() async {
        let shellReports = PassthroughSubject<Void, Never>()
        let state = AgentWorkingDirectoryState(shellDirectoryReports: shellReports.eraseToAnyPublisher())
        AgentWorkingDirectoryReceiver.apply(.report(directory: worktree), to: state, foregroundProcessID: 4242)

        // The shell prints a prompt, and with it OSC 7, only after the agent exits.
        shellReports.send(())

        #expect(await waitUntil { state.report == nil })
    }

    @Test func aNewReportAfterShellDirectoryChangeSurvivesTheNextMainActorTurn() async {
        let shellReports = PassthroughSubject<Void, Never>()
        let state = AgentWorkingDirectoryState(shellDirectoryReports: shellReports.eraseToAnyPublisher())
        state.accept(AgentWorkingDirectoryReport(directory: "/old", ownerProcessID: 4242))
        shellReports.send(())
        state.accept(AgentWorkingDirectoryReport(directory: "/new", ownerProcessID: 4242))
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(state.report?.directory == "/new")
    }

    // MARK: - Helpers

    private func userInfo(
        directory: String?,
        schema: String? = AgentWorkingDirectoryPayload.supportedSchemaVersion,
        surfaceID rawSurfaceID: String? = nil
    ) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            AgentWorkingDirectoryPayload.surfaceIDKey: rawSurfaceID ?? surfaceID.uuidString,
        ]
        if let schema {
            info[AgentWorkingDirectoryPayload.schemaVersionKey] = schema
        }
        if let directory {
            info[AgentWorkingDirectoryPayload.directoryKey] = directory
        }
        return info
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-agent-cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTemporaryFile() throws -> URL {
        let url = try makeTemporaryDirectory().appendingPathComponent("not-a-directory.txt")
        try Data("x".utf8).write(to: url)
        return url
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
