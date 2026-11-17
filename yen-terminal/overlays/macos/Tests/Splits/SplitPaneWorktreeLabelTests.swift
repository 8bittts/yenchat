import Foundation
import Testing
@testable import YEN

struct SplitPaneWorktreeLabelRulesTests {
    // MARK: - Naming rule

    @Test func worktreeFolderNameWins() {
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/Documents/yenchat/.worktrees/split-labels-7f3a",
                branch: "feat/split-labels"
            ) == "split-labels-7f3a"
        )
    }

    @Test func mainCheckoutUsesItsRepositoryFolderName() {
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/Documents/yenchat",
                branch: "main"
            ) == "yenchat"
        )
    }

    @Test func genericFolderNameFallsBackToBranch() {
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/Documents/yenchat/.worktrees/wt",
                branch: "feat/split-labels"
            ) == "feat/split-labels"
        )
    }

    @Test func genericFolderNameIsMatchedCaseInsensitively() {
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/scratch/TMP",
                branch: "main"
            ) == "main"
        )
    }

    @Test func dotDirectoryFallsBackToBranch() {
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/Documents/yenchat/.worktrees",
                branch: "main"
            ) == "main"
        )
    }

    @Test func genericFolderNameSurvivesWhenNoBranchResolves() {
        // An unborn branch resolves nothing, so a generic leaf still beats showing nothing.
        #expect(
            SplitPaneWorktreeLabelRules.label(
                worktreeRoot: "/Users/dev/scratch/tmp",
                branch: nil
            ) == "tmp"
        )
    }

    @Test func bareRepositoryWithoutWorktreeRootUsesBranch() {
        #expect(
            SplitPaneWorktreeLabelRules.label(worktreeRoot: nil, branch: "main") == "main"
        )
    }

    @Test func noRootAndNoBranchProducesNoLabel() {
        #expect(SplitPaneWorktreeLabelRules.label(worktreeRoot: nil, branch: nil) == nil)
        #expect(SplitPaneWorktreeLabelRules.label(worktreeRoot: "   ", branch: "  ") == nil)
    }

    @Test func filesystemRootIsNotAnInformativeName() {
        #expect(SplitPaneWorktreeLabelRules.isInformativeDirectoryName("/") == false)
        #expect(SplitPaneWorktreeLabelRules.isInformativeDirectoryName("") == false)
        #expect(SplitPaneWorktreeLabelRules.isInformativeDirectoryName("yenchat"))
    }

    // MARK: - Resolver

    @Test func informativeFolderDoesNotQueryAnUnusedBranch() async {
        let runner = FakeWorktreeGitRunner(outputs: [
            "rev-parse --show-toplevel": "/Users/dev/Documents/yenchat/.worktrees/split-labels-7f3a\n",
            "symbolic-ref --quiet --short HEAD": "feat/split-labels\n",
        ])

        let context = await SplitPaneWorktreeLabelResolver.resolve(
            workingDirectory: "/Users/dev/Documents/yenchat/.worktrees/split-labels-7f3a/app",
            runner: runner
        )

        #expect(context?.root == "/Users/dev/Documents/yenchat/.worktrees/split-labels-7f3a")
        #expect(await runner.invocations() == ["rev-parse --show-toplevel"])
        #expect(context?.label == "split-labels-7f3a")
    }

    @Test func detachedHeadResolvesToShortSha() async {
        let runner = FakeWorktreeGitRunner(
            outputs: [
                "rev-parse --show-toplevel": "/Users/dev/scratch/wt\n",
                "rev-parse --short HEAD": "9f8f975\n",
            ],
            failures: ["symbolic-ref --quiet --short HEAD"]
        )

        let context = await SplitPaneWorktreeLabelResolver.resolve(
            workingDirectory: "/Users/dev/scratch/wt",
            runner: runner
        )

        #expect(context?.branch == "detached@9f8f975")
        #expect(context?.label == "detached@9f8f975")
    }

    @Test func nonRepositoryDirectoryResolvesToNil() async {
        let runner = FakeWorktreeGitRunner(
            outputs: [:],
            failures: ["rev-parse --show-toplevel", "rev-parse --git-dir"]
        )

        let context = await SplitPaneWorktreeLabelResolver.resolve(
            workingDirectory: "/Users/dev/Downloads",
            runner: runner
        )

        #expect(context == nil)
        // A plain directory must not pay for the branch reads.
        let invocations = await runner.invocations()
        #expect(invocations == ["rev-parse --show-toplevel", "rev-parse --git-dir"])
    }

    @Test func bareRepositoryResolvesFromBranchAlone() async {
        let runner = FakeWorktreeGitRunner(
            outputs: [
                "rev-parse --git-dir": "/Users/dev/mirrors/yenchat.git\n",
                "symbolic-ref --quiet --short HEAD": "main\n",
            ],
            failures: ["rev-parse --show-toplevel"]
        )

        let context = await SplitPaneWorktreeLabelResolver.resolve(
            workingDirectory: "/Users/dev/mirrors/yenchat.git",
            runner: runner
        )

        #expect(context?.root == nil)
        #expect(context?.label == "main")
    }

    @Test func unbornBranchInARepositoryStillLabelsFromTheFolder() async {
        let runner = FakeWorktreeGitRunner(
            outputs: ["rev-parse --show-toplevel": "/Users/dev/new-project\n"],
            failures: ["symbolic-ref --quiet --short HEAD", "rev-parse --short HEAD"]
        )

        let context = await SplitPaneWorktreeLabelResolver.resolve(
            workingDirectory: "/Users/dev/new-project",
            runner: runner
        )

        #expect(context?.branch == nil)
        #expect(context?.label == "new-project")
    }
}

/// Records every command so a test can assert which git calls a directory actually costs.
private actor FakeWorktreeGitRunner: GitDrawerCommandRunning {
    private let outputs: [String: String]
    private let failures: Set<String>
    private var recorded: [String] = []

    init(outputs: [String: String], failures: Set<String> = []) {
        self.outputs = outputs
        self.failures = failures
    }

    func invocations() -> [String] {
        recorded
    }

    func run(
        _ command: GitDrawerGitCommand,
        currentDirectory: String,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> GitDrawerCommandOutput {
        let key = command.arguments.joined(separator: " ")
        recorded.append(key)
        if failures.contains(key) {
            throw GitDrawerShellError.commandFailed(key)
        }
        return GitDrawerCommandOutput(
            stdout: outputs[key] ?? "",
            stderr: "",
            wasTruncated: false
        )
    }
}

@Suite(.serialized)
@MainActor
struct SplitPaneWorktreeLabelStoreTests {
    @Test func repeatedLabelReadsAndWatcherShareOnePathResolution() async {
        var pathReads = 0
        let directory = NSTemporaryDirectory()
        let store = SplitPaneWorktreeLabelStore(normalizePath: { path in
            pathReads += 1
            return TabSidebarController.trustedWorkingDirectory(from: path)
        }, resolve: { SplitPaneWorktreeContext(root: $0, branch: "main") })
        for _ in 0..<100 { _ = store.label(forWorkingDirectory: directory) }
        let watcher = Task { await store.watch(workingDirectory: directory) }
        #expect(await waitUntil { store.isPolling })
        #expect(pathReads == 1)
        watcher.cancel()
        await watcher.value
        #expect(!store.isPolling)
    }

    @Test func cachedPathsExpireForSymlinkRetargetsAndDeletedDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        defer { try? FileManager.default.removeItem(at: root) }
        var clock = Date()
        let store = SplitPaneWorktreeLabelStore(now: { clock },
            resolve: { SplitPaneWorktreeContext(root: $0, branch: "main") })
        #expect(await waitForLabel(store, directory: link.path) == "first")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        #expect(store.label(forWorkingDirectory: link.path) == "first")
        clock = clock.addingTimeInterval(6)
        #expect(await waitForLabel(store, directory: link.path) == "second")
        try FileManager.default.removeItem(at: second)
        clock = clock.addingTimeInterval(6)
        #expect(store.label(forWorkingDirectory: link.path) == nil)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        #expect(store.label(forWorkingDirectory: link.path) == nil)
        clock = clock.addingTimeInterval(6)
        #expect(await waitForLabel(store, directory: link.path) == "second")
    }

    @Test func pathCacheEvictsOldEntriesAtTheConfiguredLimit() {
        var reads = 0
        var clock = Date()
        let store = SplitPaneWorktreeLabelStore(maximumEntries: 2, now: { clock }, normalizePath: { _ in
            reads += 1
            return nil
        }, resolve: { _ in nil })
        for path in ["/first", "/second", "/third"] {
            _ = store.label(forWorkingDirectory: path)
            clock = clock.addingTimeInterval(0.1)
        }
        _ = store.label(forWorkingDirectory: "/third")
        #expect(reads == 3)
        _ = store.label(forWorkingDirectory: "/first")
        #expect(reads == 4)
    }

    @Test func firstReadMissesThenCachesOneResolutionPerDirectory() async {
        let directory = NSTemporaryDirectory()
        #expect(TabSidebarController.trustedWorkingDirectory(from: directory) != nil)

        let counter = ResolveCounter()
        let store = SplitPaneWorktreeLabelStore(
            refreshInterval: 60,
            resolve: { _ in
                counter.increment()
                return SplitPaneWorktreeContext(
                    root: "/repos/yenchat/.worktrees/split-labels-7f3a",
                    branch: "feat/split-labels"
                )
            }
        )

        // Nothing is cached yet, so the pane keeps its own fallback for one frame.
        #expect(store.label(forWorkingDirectory: directory) == nil)

        let resolved = await waitForLabel(store, directory: directory)
        #expect(resolved == "split-labels-7f3a")
        #expect(store.label(forWorkingDirectory: directory) == "split-labels-7f3a")
        #expect(counter.value == 1)
    }

    @Test func repeatedReadsBeforeTheFirstResolutionLandsRunGitOnce() async {
        let directory = NSTemporaryDirectory()
        let counter = ResolveCounter()
        let store = SplitPaneWorktreeLabelStore(
            refreshInterval: 60,
            resolve: { _ in
                counter.increment()
                return SplitPaneWorktreeContext(root: "/repos/yenchat", branch: "main")
            }
        )

        // A re-render storm must not fan out into one git process per frame.
        for _ in 0..<5 {
            _ = store.label(forWorkingDirectory: directory)
        }

        #expect(await waitForLabel(store, directory: directory) == "yenchat")
        #expect(counter.value == 1)
    }

    @Test func aDirectoryChangeResolvesWithoutWaitingOutTheTTL() async {
        let home = NSHomeDirectory()
        let temporary = NSTemporaryDirectory()
        let store = SplitPaneWorktreeLabelStore(
            refreshInterval: 3600,
            resolve: { directory in
                SplitPaneWorktreeContext(root: directory, branch: "main")
            }
        )

        let firstLabel = await waitForLabel(store, directory: home)
        // A `cd` reads a different cache key, so the long TTL cannot pin the old value.
        let secondLabel = await waitForLabel(store, directory: temporary)

        #expect(firstLabel != nil)
        #expect(secondLabel != nil)
        #expect(firstLabel != secondLabel)
    }

    @Test func anUntrustedPathNeverReachesGit() async {
        let counter = ResolveCounter()
        let store = SplitPaneWorktreeLabelStore(
            resolve: { _ in
                counter.increment()
                return SplitPaneWorktreeContext(root: "/repos/yenchat", branch: "main")
            }
        )

        #expect(store.label(forWorkingDirectory: nil) == nil)
        #expect(store.label(forWorkingDirectory: "") == nil)
        #expect(store.label(forWorkingDirectory: "relative/path") == nil)
        #expect(store.label(forWorkingDirectory: "/no/such/directory/here") == nil)

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(counter.value == 0)
    }

    @Test func aWatchedDirectoryPicksUpABranchSwitchWithoutBeingRead() async {
        let directory = NSTemporaryDirectory()
        let branch = LockedBranch("feat/alpha")
        let store = SplitPaneWorktreeLabelStore(
            refreshInterval: 0.05,
            resolve: { _ in
                SplitPaneWorktreeContext(root: "/repos/yenchat/.worktrees/wt", branch: branch.value)
            }
        )

        #expect(await waitForLabel(store, directory: directory) == "feat/alpha")
        let watcher = Task { await store.watch(workingDirectory: directory) }
        let revisionBeforeSwitch = store.revision

        // Nothing reads the label from here on, exactly like an idle pane that never redraws,
        // so only the poll can notice the switch.
        branch.set("feat/beta")
        #expect(await waitUntil { store.revision > revisionBeforeSwitch })
        #expect(store.label(forWorkingDirectory: directory) == "feat/beta")

        watcher.cancel()
        await watcher.value
    }

    @Test func pollingRunsUntilTheLastLabelInADirectoryStopsWatching() async {
        let directory = NSTemporaryDirectory()
        let counter = ResolveCounter()
        let store = SplitPaneWorktreeLabelStore(
            refreshInterval: 0.05,
            resolve: { _ in
                counter.increment()
                return SplitPaneWorktreeContext(root: "/repos/yenchat", branch: "main")
            }
        )

        let first = Task { await store.watch(workingDirectory: directory) }
        let second = Task { await store.watch(workingDirectory: directory) }
        #expect(await waitUntil { store.isPolling })

        // One pane leaving must not stop the poll the other pane in that directory relies on.
        first.cancel()
        await first.value
        #expect(store.isPolling)
        let resolvesWithOneWatcher = counter.value
        #expect(await waitUntil { counter.value > resolvesWithOneWatcher })

        second.cancel()
        await second.value
        #expect(!store.isPolling)

        // Let a refresh the last tick already scheduled land, then prove git stays quiet.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let resolvesAfterStop = counter.value
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(counter.value == resolvesAfterStop)
    }

    @Test func anUntrustedPathNeverStartsPolling() async {
        let store = SplitPaneWorktreeLabelStore(resolve: { _ in nil })

        // Both return at once instead of parking, so a pane without a directory holds no poll.
        await store.watch(workingDirectory: nil)
        await store.watch(workingDirectory: "/no/such/directory/here")

        #expect(!store.isPolling)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    /// Polls until the store's background resolution lands. `Task.sleep` yields the main actor,
    /// which a `RunLoop.run` drain does not — the store's continuation is main-actor isolated.
    private func waitForLabel(
        _ store: SplitPaneWorktreeLabelStore,
        directory: String,
        timeout: TimeInterval = 5
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let label = store.label(forWorkingDirectory: directory) {
                return label
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return store.label(forWorkingDirectory: directory)
    }
}

/// A branch the test can switch while the store's resolver reads it from another thread.
private final class LockedBranch: @unchecked Sendable {
    private let lock = NSLock()
    private var branch: String

    init(_ branch: String) {
        self.branch = branch
    }

    func set(_ newValue: String) {
        lock.lock()
        branch = newValue
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return branch
    }
}

/// Counts resolver invocations from whatever thread the store's task runs on.
private final class ResolveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
