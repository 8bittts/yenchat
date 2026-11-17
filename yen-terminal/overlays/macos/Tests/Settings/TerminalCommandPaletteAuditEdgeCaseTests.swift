import Foundation
import Testing
@testable import YEN

@MainActor
struct TerminalCommandPaletteAuditEdgeCaseTests {
    @Test func invalidWorkingDirectoriesFailClosed() {
        let missingPath = "/tmp/yen-palette-missing-\(UUID().uuidString)"

        #expect(TerminalCommandPaletteView.normalizedWorkingDirectory("http://example.com/repo") == nil)
        #expect(TerminalCommandPaletteView.normalizedWorkingDirectory(missingPath) == nil)
        #expect(
            !TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: "http://example.com/repo"
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: missingPath
            )
        )
    }

    @Test func deeplyNestedGitFileWorktreeRemainsEligible() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-deep-worktree-")
        let trustFile = root.appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }

        try write("gitdir: /tmp/fake-worktree\n", to: root.appendingPathComponent(".git"))
        try write("\(root.path)\n", to: trustFile)

        var nested = root
        for index in 0..<96 {
            nested.appendPathComponent("level-\(index)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(
            TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nested.path,
                workflowTrustFilePath: trustFile.path
            )
        )
    }

    @Test func permissionDeniedParentFailsClosed() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-permission-root-")
        let restricted = root.appendingPathComponent("restricted", isDirectory: true)
        let nested = restricted.appendingPathComponent("deep", isDirectory: true)
        let trustFile = root.appendingPathComponent("trusted-workflow-projects", isDirectory: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restricted.path)
            try? FileManager.default.removeItem(at: root)
        }

        try write("gitdir: /tmp/fake-worktree\n", to: root.appendingPathComponent(".git"))
        try write("\(root.path)\n", to: trustFile)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: restricted.path)

        #expect(
            !TerminalCommandPaletteView.shouldShowRepositoryWorkspaceActions(
                workingDirectory: nested.path,
                workflowTrustFilePath: trustFile.path
            )
        )
    }

    @Test func tabSidebarPaletteActionsDoNotSuppressTerminalRefocus() {
        #expect(
            !TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "workspace:toggle-tab-sidebar"
            )
        )
        #expect(
            !TerminalCommandPaletteView.shouldSuppressSurfaceRefocusOnDismiss(
                for: "search:action:workspace:toggle-tab-sidebar"
            )
        )
    }

    @Test func repositoryWorkspaceModelSettlesOnLatestStateAfterRapidMixedTransitions() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-rapid-repo-")
        let nested = root.appendingPathComponent("src", isDirectory: true)
        let nonRepo = try makeTemporaryDirectory(prefix: "yen-palette-rapid-nonrepo-")
        let symlinkRoot = try makeTemporaryDirectory(prefix: "yen-palette-rapid-link-")
        let symlink = symlinkRoot.appendingPathComponent("alias", isDirectory: true)
        let symlinkedNested = symlink.appendingPathComponent("src", isDirectory: true)
        let deleted = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-rapid-deleted-\(UUID().uuidString)", isDirectory: true)
        let trustFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-palette-rapid-trusted-workflow-\(UUID().uuidString)", isDirectory: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: nonRepo)
            try? FileManager.default.removeItem(at: symlinkRoot)
            try? FileManager.default.removeItem(at: deleted)
            try? FileManager.default.removeItem(at: trustFile)
        }

        try write("gitdir: /tmp/fake-worktree\n", to: root.appendingPathComponent(".git"))
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: root)
        try FileManager.default.createDirectory(at: deleted, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: deleted)
        try "\(root.path)\n".write(to: trustFile, atomically: true, encoding: .utf8)

        let model = TerminalCommandPaletteRepositoryWorkspaceModel(
            workflowTrustFilePathResolver: { trustFile.path }
        )
        let sequence: [String?] = [
            nested.path,
            nonRepo.path,
            symlinkedNested.path,
            deleted.path,
            nested.path,
            symlinkedNested.path,
        ]

        for workingDirectory in sequence {
            model.refresh(workingDirectory: workingDirectory)
        }

        await waitUntil(description: "repo eligibility after rapid transitions") {
            model.isRepositoryWorkspace
        }

        model.refresh(workingDirectory: nonRepo.path)
        await waitUntil(description: "non-repo eligibility after rapid transitions") {
            model.isRepositoryWorkspace == false
        }
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ value: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 1.5,
        description: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await advanceMainQueueTurn()
        }

        Issue.record("Timed out waiting for \(description)")
    }

    private func advanceMainQueueTurn() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
        await Task.yield()
    }
}
