import Foundation
import Testing
@testable import YEN

struct GitDrawerSnapshotParserTests {
    @Test func porcelainV2PreservesUnusualPathsAndSubmoduleModes() throws {
        let status = try #require(GitStatusPorcelainV2(joinedNul([
            "# branch.oid abc1234", "# branch.head main", "# branch.upstream origin/main",
            "# branch.ab +3 -2", "# future.header ignored",
            "2 R. N... 100644 100644 100644 abc def R100 new\tname\nwith spaces",
            "# branch.head fake-branch",
            "1 .M S.M. 160000 160000 160000 abc def nested/module",
            "1 D. N... 160000 000000 000000 abc def deleted-module",
            "u UU N... 100644 100644 100644 100644 abc def ghi conflicted file",
            "? new\nfile",
        ])))
        #expect(status.head == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 3 && status.behind == 2)
        #expect(status.entries.count == 5)
        #expect(status.entries[0].path == "new\tname\nwith spaces")
        #expect(status.entries[0].oldPath == "# branch.head fake-branch")
        #expect(status.entries[1].isSubmodule)
        #expect(status.entries[2].isSubmodule)
        #expect(status.entries[3].code == "UU")
        #expect(status.entries[4].path == "new\nfile")
    }

    @Test func porcelainV2RejectsIncompleteStatusInsteadOfReportingClean() {
        #expect(GitStatusPorcelainV2("") == nil)
        #expect(GitStatusPorcelainV2("# branch.head main\0") == nil)
        #expect(GitStatusPorcelainV2("# branch.oid abc\0# branch.head main") == nil)
        #expect(GitStatusPorcelainV2("# branch.oid abc\0# branch.head main\0# branch.ab +0 -9223372036854775809\0") == nil)
        #expect(GitStatusPorcelainV2("# branch.oid abc\0# branch.head main\02 R. N... 100644 100644 100644 abc def R100 dest\0") == nil)
    }

    @Test func statusMetadataMatchesRealGitWithSubmodulesAndUnusualPaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try runGit(["init", "-b", "main"], in: directory)
        try runGit(["config", "user.email", "test@example.invalid"], in: directory)
        try runGit(["config", "user.name", "YEN Test"], in: directory)
        try runGit(["commit", "--allow-empty", "-m", "base"], in: directory)
        try runGit(["branch", "baseline"], in: directory)
        try runGit(["branch", "--set-upstream-to=baseline"], in: directory)
        try runGit(["commit", "--allow-empty", "-m", "ahead"], in: directory)
        let client = GitDrawerShellClient()
        let oid = try await client.run(GitDrawerGitCommand(arguments: ["rev-parse", "HEAD"]),
            currentDirectory: directory.path, timeout: 10, stdoutLimit: 1024, stderrLimit: 1024)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["update-index", "--add", "--cacheinfo", "160000,\(oid),module"], in: directory)
        let unusual = "new\tfile\nwith spaces"
        try "hello".write(to: directory.appendingPathComponent(unusual), atomically: true, encoding: .utf8)
        let request = GitDrawerSnapshotRequest(workingDirectory: directory.path,
            targetID: "real", generation: 1, selectedPath: nil)
        let snapshot = try await GitDrawerSnapshotResolver.resolve(request, runner: client, timeout: 10)
        #expect(snapshot.branch == "main")
        #expect(snapshot.upstream == "baseline")
        #expect(snapshot.ahead == 1 && snapshot.behind == 0)
        #expect(snapshot.staged.first { $0.path == "module" }?.statPlaceholder == "submodule")
        #expect(snapshot.untracked.contains { $0.path == unusual })
        try runGit(["config", "core.abbrev", "12"], in: directory)
        try runGit(["checkout", "--detach", "HEAD"], in: directory)
        let detached = try await GitDrawerSnapshotResolver.resolve(request, runner: client, timeout: 10)
        #expect(detached.branch == "detached@\(oid.prefix(12))")
    }

    @Test func truncatedStatusCannotBecomeACleanSnapshot() async {
        let runner = FakeGitDrawerRunner(outputs: ["rev-parse --show-toplevel": "/repo"],
            truncated: ["status --porcelain=v2 -z --branch"])
        do {
            _ = try await GitDrawerSnapshotResolver.resolve(
                GitDrawerSnapshotRequest(workingDirectory: "/repo", targetID: "split", generation: 1, selectedPath: nil),
                runner: runner)
            Issue.record("Expected incomplete status to fail.")
        } catch let error as GitDrawerShellError {
            #expect(error == .commandFailed("Git status output is incomplete or invalid."))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func snapshotGroupsStatusRowsAndSummarizesCounts() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "feature/git-drawer",
            upstream: "origin/feature/git-drawer",
            aheadBehindOutput: "2\t3",
            statusPorcelainZ: joinedNul([
                "# branch.oid abc1234", "# branch.head feature/git-drawer", "# branch.upstream origin/feature/git-drawer", "# branch.ab +3 -2",
                "1 M. N... 100644 100644 100644 abc def staged.swift",
                "1 .M N... 100644 100644 100644 abc def unstaged.swift",
                "1 A. N... 100644 100644 100644 abc def added.swift",
                "? new-file.swift",
                "u UU N... 100644 100644 100644 100644 abc def ghi conflicted.swift",
                "2 R. N... 100644 100644 100644 abc def R100 old-name.swift",
                "new-name.swift",
            ]),
            unstagedNameStatusZ: joinedNul([
                "M",
                "unstaged.swift",
                "U",
                "conflicted.swift",
            ]),
            stagedNameStatusZ: joinedNul([
                "M",
                "staged.swift",
                "A",
                "added.swift",
                "R100",
                "old-name.swift",
                "new-name.swift",
            ]),
            unstagedNumstatZ: joinedNul([
                "5\t1\tunstaged.swift",
                "-\t-\tconflicted.swift",
            ]),
            stagedNumstatZ: joinedNul([
                "2\t0\tstaged.swift",
                "9\t1\tadded.swift",
                // Real `git diff --numstat -z` rename layout: counts token ends in a tab and the
                // from/to paths are SEPARATE NUL fields (not one tab-joined token).
                "4\t2\t",
                "old-name.swift",
                "new-name.swift",
            ]),
            stashListOutput: "stash@{0}: WIP\nstash@{1}: WIP\n"
        )

        #expect(snapshot.repoRoot == "/tmp/repo")
        #expect(snapshot.branch == "feature/git-drawer")
        #expect(snapshot.upstream == "origin/feature/git-drawer")
        #expect(snapshot.behind == 2)
        #expect(snapshot.ahead == 3)
        #expect(snapshot.stashCount == 2)
        #expect(snapshot.totalChangedFileCount == 6)
        #expect(snapshot.totalAdditions == 20)
        #expect(snapshot.totalDeletions == 4)

        #expect(snapshot.staged.map(\.displayPath) == [
            "staged.swift",
            "added.swift",
            "old-name.swift -> new-name.swift",
        ])
        #expect(snapshot.unstaged.map(\.path) == ["unstaged.swift"])
        #expect(snapshot.untracked.map(\.path) == ["new-file.swift"])
        #expect(snapshot.conflicted.map(\.path) == ["conflicted.swift"])
        #expect(snapshot.conflicted.first?.statPlaceholder == "binary")

        let renamed = snapshot.staged.last
        #expect(renamed?.status == .renamed)
        #expect(renamed?.oldPath == "old-name.swift")
        #expect(renamed?.path == "new-name.swift")
        #expect(renamed?.additions == 4)
        #expect(renamed?.deletions == 2)
    }

    @Test func binaryNumstatRowsUseExplicitPlaceholder() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .M N... 100644 100644 100644 abc def image.png"]),
            unstagedNameStatusZ: joinedNul(["M", "image.png"]),
            stagedNameStatusZ: "",
            unstagedNumstatZ: joinedNul(["-\t-\timage.png"]),
            stagedNumstatZ: "",
            stashListOutput: ""
        )

        #expect(snapshot.unstaged.first?.path == "image.png")
        #expect(snapshot.unstaged.first?.additions == nil)
        #expect(snapshot.unstaged.first?.deletions == nil)
        #expect(snapshot.unstaged.first?.statPlaceholder == "binary")
    }

    @Test func submoduleRowsUseExplicitPlaceholderInsteadOfMisleadingNumstat() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .M S.M. 160000 160000 160000 abc def vendor/toolkit"]),
            unstagedNameStatusZ: joinedNul(["M", "vendor/toolkit"]),
            stagedNameStatusZ: "",
            unstagedNumstatZ: joinedNul(["1\t1\tvendor/toolkit"]),
            stagedNumstatZ: "",
            stashListOutput: ""
        )

        #expect(snapshot.unstaged.first?.path == "vendor/toolkit")
        #expect(snapshot.unstaged.first?.additions == nil)
        #expect(snapshot.unstaged.first?.deletions == nil)
        #expect(snapshot.unstaged.first?.statPlaceholder == "submodule")
    }

    @Test func deletedRowsPreserveDeletedStatusAndNumstat() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .D N... 100644 100644 100644 abc def removed.swift"]),
            unstagedNameStatusZ: joinedNul(["D", "removed.swift"]),
            stagedNameStatusZ: "",
            unstagedNumstatZ: joinedNul(["0\t8\tremoved.swift"]),
            stagedNumstatZ: "",
            stashListOutput: ""
        )

        #expect(snapshot.unstaged.first?.path == "removed.swift")
        #expect(snapshot.unstaged.first?.status == .deleted)
        #expect(snapshot.unstaged.first?.additions == 0)
        #expect(snapshot.unstaged.first?.deletions == 8)
    }

    @Test func typeChangedRowsPreserveTypeChangedStatus() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .T N... 100644 100644 100644 abc def link-or-file"]),
            unstagedNameStatusZ: joinedNul(["T", "link-or-file"]),
            stagedNameStatusZ: "",
            unstagedNumstatZ: joinedNul(["0\t0\tlink-or-file"]),
            stagedNumstatZ: "",
            stashListOutput: ""
        )

        #expect(snapshot.unstaged.first?.status == .typeChanged)
        #expect(snapshot.unstaged.first?.path == "link-or-file")
    }

    @Test func porcelainRenameZKeepsDestinationAsPathAndSourceAsOldPath() {
        let entries = GitDrawerSnapshotParser.testingStatusEntries(
            joinedNul(["# branch.oid abc1234", "# branch.head main", "2 R. N... 100644 100644 100644 abc def R100 new-name.swift", "old-name.swift"])
        )

        #expect(entries.count == 1)
        #expect(entries.first?.status == .renamed)
        #expect(entries.first?.path == "new-name.swift")
        #expect(entries.first?.oldPath == "old-name.swift")
    }

    @Test func fileListCapPreservesConflictedRowsBeforeOtherGroups() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "u UU N... 100644 100644 100644 100644 abc def ghi conflict.swift"]),
            unstagedNameStatusZ: joinedNul(["M", "worktree.swift"]),
            stagedNameStatusZ: joinedNul(["M", "index.swift"]),
            unstagedNumstatZ: joinedNul(["1\t0\tworktree.swift", "2\t2\tconflict.swift"]),
            stagedNumstatZ: joinedNul(["1\t0\tindex.swift"]),
            stashListOutput: "",
            fileLimit: 1
        )

        #expect(snapshot.conflicted.map(\.path) == ["conflict.swift"])
        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.isFileListTruncated)
    }

    @Test func fileLimitCapsRowsAcrossGroupsAndMarksSnapshotTruncated() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul([
                "# branch.oid abc1234", "# branch.head main",
                "1 M. N... 100644 100644 100644 abc def staged-a.swift",
                "1 M. N... 100644 100644 100644 abc def staged-b.swift",
                "1 .M N... 100644 100644 100644 abc def unstaged-a.swift",
                "? untracked-a.swift",
            ]),
            unstagedNameStatusZ: joinedNul([
                "M",
                "unstaged-a.swift",
            ]),
            stagedNameStatusZ: joinedNul([
                "M",
                "staged-a.swift",
                "M",
                "staged-b.swift",
            ]),
            unstagedNumstatZ: joinedNul(["1\t1\tunstaged-a.swift"]),
            stagedNumstatZ: joinedNul([
                "1\t0\tstaged-a.swift",
                "2\t0\tstaged-b.swift",
            ]),
            stashListOutput: "",
            fileLimit: 2
        )

        #expect(snapshot.staged.map(\.path) == ["staged-a.swift", "staged-b.swift"])
        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.untracked.isEmpty)
        #expect(snapshot.isFileListTruncated)
    }

    @Test func cleanRepositoryKeepsPopulatedHeaderState() {
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: "origin/main",
            aheadBehindOutput: "1\t0",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "# branch.upstream origin/main", "# branch.ab +0 -1"]),
            unstagedNameStatusZ: "",
            stagedNameStatusZ: "",
            unstagedNumstatZ: "",
            stagedNumstatZ: "",
            stashListOutput: ""
        )

        #expect(snapshot.isClean)
        #expect(snapshot.totalChangedFileCount == 0)
        #expect(snapshot.branch == "main")
        #expect(snapshot.upstream == "origin/main")
        #expect(snapshot.behind == 1)
        #expect(snapshot.ahead == 0)
        #expect(snapshot.staged.isEmpty)
        #expect(snapshot.unstaged.isEmpty)
        #expect(snapshot.untracked.isEmpty)
        #expect(snapshot.conflicted.isEmpty)
    }

    @Test func aheadBehindOutputUsesBehindThenAheadOrder() {
        let counts = GitDrawerSnapshotParser.parseAheadBehind("7\t11")

        #expect(counts.behind == 7)
        #expect(counts.ahead == 11)
    }

    @Test func stashListAndFilesAreParsedForReadOnlyDisplay() {
        let entries = GitDrawerSnapshotParser.testingStashEntries(
            stashListOutput: "stash@{0}: WIP on main: abc1234 docs\nstash@{1}: On feature/git-drawer: polish\n",
            stashFileOutputsByRef: [
                "stash@{0}": joinedNul(["M", "README.md", "A", "docs/git.md"]),
                "stash@{1}": joinedNul(["R100", "old.swift", "new.swift"]),
            ]
        )

        #expect(GitDrawerSnapshotParser.stashRefs("stash@{0}: WIP\nstash@{1}: WIP\n") == [
            "stash@{0}",
            "stash@{1}",
        ])
        #expect(entries.map(\.ref) == ["stash@{0}", "stash@{1}"])
        #expect(entries.first?.message == "WIP on main: abc1234 docs")
        #expect(entries.first?.files.map(\.displayPath) == ["README.md", "docs/git.md"])
        #expect(entries.first?.files.map(\.status) == [.modified, .added])
        #expect(entries.last?.files.first?.displayPath == "old.swift -> new.swift")
    }

    @Test func stashEntriesAreCappedAndMarkedTruncated() {
        let stashLines = (0..<22)
            .map { "stash@{\($0)}: WIP \($0)" }
            .joined(separator: "\n")
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main"]),
            unstagedNameStatusZ: "",
            stagedNameStatusZ: "",
            unstagedNumstatZ: "",
            stagedNumstatZ: "",
            stashListOutput: stashLines,
            stashFileOutputsByRef: [
                "stash@{0}": joinedNul(["M", "README.md"]),
                "stash@{19}": joinedNul(["A", "last-loaded.md"]),
                "stash@{20}": joinedNul(["A", "not-loaded.md"]),
            ]
        )

        #expect(snapshot.stashCount == 22)
        #expect(snapshot.stashEntries.count == GitDrawerSnapshotParser.defaultStashEntryLimit)
        #expect(snapshot.stashEntries.first?.files.map(\.path) == ["README.md"])
        #expect(snapshot.stashEntries.last?.ref == "stash@{19}")
        #expect(snapshot.stashEntries.last?.files.map(\.path) == ["last-loaded.md"])
        #expect(snapshot.isStashListTruncated)
    }

    @Test func selectionPreservesListLimitsAndRejectsAnotherDirectorysSnapshot() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo",
            "stash list": (0..<22).map { "stash@{\($0)}: WIP" }.joined(separator: "\n"),
        ])
        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: "/repo", targetID: "split", generation: 1, selectedPath: nil), runner: runner)
        #expect(snapshot.isStashListTruncated)
        #expect(snapshot.stashEntries.count == 20)
        let count = await runner.commands.count
        let selected = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: "/repo", targetID: "split", generation: 2, selectedPath: "file", listSnapshot: snapshot), runner: runner)
        #expect(selected.isStashListTruncated)
        #expect(selected.stashEntries == snapshot.stashEntries)
        #expect(await runner.commands.count == count + 1)
        let retargeted = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: "/other", targetID: "split", generation: 3, selectedPath: nil, listSnapshot: selected), runner: runner)
        #expect(retargeted.workingDirectory == "/other")
        let commands = await runner.commands
        #expect(commands[count + 1].arguments == ["rev-parse", "--is-bare-repository"])
    }

    @Test func resolverExecutesOnlyReadOnlyStructuredCommands() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo",
            "stash list": "stash@{0}: WIP",
        ])
        _ = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: "/repo", targetID: "split", generation: 1, selectedPath: "Sources/App.swift"), runner: runner)
        let commands = await runner.commands
        #expect(commands.count == 10)
        #expect(commands.allSatisfy { $0.isReadOnly })
        #expect(commands.contains { $0.arguments == ["stash", "show", "--include-untracked", "--name-status", "-z", "stash@{0}"] })
        #expect(commands.last?.arguments == ["diff", "--no-ext-diff", "--minimal", "--no-color", "--", "Sources/App.swift"])
    }

    @Test func statusSurfacesKeepSummaryAndDetailSemanticsExplicit() async throws {
        let runner = FakeGitDrawerRunner(outputs: ["rev-parse --show-toplevel": "/repo"])
        _ = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: "/repo", targetID: "split", generation: 1, selectedPath: nil), runner: runner)
        let drawerStatusCommand = await runner.commands.map(\.arguments).first { $0.first == "status" }

        #expect(TabSidebarController.testingTrackedOnlyStatusArguments == [
            "status",
            "--porcelain=v2",
            "-z",
            "--branch",
            "--untracked-files=no",
        ])
        #expect(drawerStatusCommand == [
            "status",
            "--porcelain=v2",
            "-z",
            "--branch",
        ])
    }

    @Test func commandPlanRejectsMutatingGitSubcommands() {
        #expect(!GitDrawerGitCommand(arguments: ["status", "--porcelain=v2"]).isMutating)
        #expect(GitDrawerGitCommand(arguments: ["add", "."]).isMutating)
        #expect(GitDrawerGitCommand(arguments: ["commit", "-m", "msg"]).isMutating)
        #expect(!GitDrawerGitCommand(arguments: ["stash", "show", "--include-untracked", "--name-status", "-z", "stash@{0}"]).isMutating)
        #expect(GitDrawerGitCommand(arguments: ["stash", "push"]).isMutating)
        #expect(GitDrawerGitCommand(arguments: ["reset", "--hard"]).isMutating)
    }

    @Test func resolverBuildsSnapshotAndSelectedRawDiffFromRunnerOutputs() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo\n",
            "rev-parse --is-bare-repository": "false\n",
            "symbolic-ref --quiet --short HEAD": "feature/git-drawer",
            "rev-parse --short HEAD": "abc1234\n",
            "status --porcelain=v2 -z --branch": joinedNul([
                "# branch.oid abc1234", "# branch.head feature/git-drawer", "# branch.upstream origin/feature/git-drawer", "# branch.ab +2 -0",
                "1 .M N... 100644 100644 100644 abc def Sources/App.swift",
            ]),
            "diff --name-status -z --cached": "",
            "diff --name-status -z": joinedNul(["M", "Sources/App.swift"]),
            "diff --numstat -z --cached": "",
            "diff --numstat -z": joinedNul(["3\t1\tSources/App.swift"]),
            "stash list": "stash@{0}: WIP",
            "stash show --include-untracked --name-status -z stash@{0}": joinedNul(["M", "README.md", "A", "docs/git.md"]),
            "diff --no-ext-diff --minimal --no-color -- Sources/App.swift": "@@ -1 +1 @@\n-old\n+new",
        ])

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo/subdir",
                targetID: "split-a",
                generation: 7,
                selectedPath: "Sources/App.swift"
            ),
            runner: runner
        )

        #expect(snapshot.repoRoot == "/repo")
        #expect(snapshot.workingDirectory == "/repo/subdir")
        #expect(snapshot.branch == "feature/git-drawer")
        #expect(snapshot.upstream == "origin/feature/git-drawer")
        #expect(snapshot.ahead == 2)
        #expect(snapshot.behind == 0)
        #expect(snapshot.stashCount == 1)
        #expect(snapshot.stashEntries.first?.ref == "stash@{0}")
        #expect(snapshot.stashEntries.first?.files.map(\.path) == ["README.md", "docs/git.md"])
        #expect(snapshot.unstaged.map(\.path) == ["Sources/App.swift"])
        #expect(snapshot.totalAdditions == 3)
        #expect(snapshot.totalDeletions == 1)
        #expect(snapshot.selectedFile == "Sources/App.swift")
        #expect(snapshot.selectedDiff == "@@ -1 +1 @@\n-old\n+new")
        #expect(snapshot.generation == 7)


    }

    @Test func selectedDiffUsesPlainRawGitDiffCommandOnly() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo\n",
            "rev-parse --is-bare-repository": "false\n",
            "symbolic-ref --quiet --short HEAD": "main",
            "rev-parse --short HEAD": "abc1234\n",
            "status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .M N... 100644 100644 100644 abc def Sources/App.swift"]),
            "diff --name-status -z --cached": "",
            "diff --name-status -z": joinedNul(["M", "Sources/App.swift"]),
            "diff --numstat -z --cached": "",
            "diff --numstat -z": joinedNul(["1\t1\tSources/App.swift"]),
            "stash list": "",
            "diff --no-ext-diff --minimal --no-color -- Sources/App.swift": "raw unified diff",
        ])

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo",
                targetID: "split-a",
                generation: 1,
                selectedPath: "Sources/App.swift"
            ),
            runner: runner
        )

        #expect(snapshot.selectedDiff == "raw unified diff")
        let selectedDiffCommand = await runner.commands.last?.arguments
        #expect(selectedDiffCommand == [
            "diff",
            "--no-ext-diff",
            "--minimal",
            "--no-color",
            "--",
            "Sources/App.swift",
        ])
    }

    @Test func resolverTreatsDetachedHeadAndMissingUpstreamAsValidState() async throws {
        let runner = FakeGitDrawerRunner(
            outputs: [
                "rev-parse --show-toplevel": "/repo\n",
                "rev-parse --is-bare-repository": "false\n",
                "rev-parse --short HEAD": "abc1234\n",
                "status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head (detached)"]),
                "diff --name-status -z --cached": "",
                "diff --name-status -z": "",
                "diff --numstat -z --cached": "",
                "diff --numstat -z": "",
                "stash list": "",
            ],
            failures: [
                "symbolic-ref --quiet --short HEAD",
                "rev-parse --abbrev-ref --symbolic-full-name @{upstream}",
                "rev-list --left-right --count @{upstream}...HEAD",
            ]
        )

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo",
                targetID: "split-a",
                generation: 2,
                selectedPath: nil
            ),
            runner: runner
        )

        #expect(snapshot.branch == "detached@abc1234")
        #expect(snapshot.upstream == nil)
        #expect(snapshot.ahead == 0)
        #expect(snapshot.behind == 0)
        #expect(snapshot.isClean)
    }

    @Test func resolverHandlesLinkedWorktreeGitFileDirectories() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-worktree-\(UUID().uuidString)", isDirectory: true)
        let mainRepo = tempRoot.appendingPathComponent("main", isDirectory: true)
        let worktree = tempRoot.appendingPathComponent("linked-worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: mainRepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: mainRepo)
        try runGit(["config", "user.email", "test@example.invalid"], in: mainRepo)
        try runGit(["config", "user.name", "YEN Test"], in: mainRepo)
        try "initial\n".write(
            to: mainRepo.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], in: mainRepo)
        try runGit(["commit", "-m", "initial"], in: mainRepo)
        try runGit(["worktree", "add", worktree.path], in: mainRepo)
        try "initial\nworktree edit\n".write(
            to: worktree.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: worktree.path,
                targetID: "split-worktree",
                generation: 3,
                selectedPath: nil
            ),
            runner: GitDrawerShellClient(),
            timeout: 10
        )

        #expect(
            URL(fileURLWithPath: snapshot.repoRoot).resolvingSymlinksInPath().path
                == worktree.resolvingSymlinksInPath().path
        )
        #expect(snapshot.unstaged.map(\.path) == ["README.md"])
        #expect(snapshot.generation == 3)
    }

    @Test func resolverRejectsBareRepository() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --is-bare-repository": "true\n",
        ])

        await #expect(throws: GitDrawerShellError.bareRepository) {
            _ = try await GitDrawerSnapshotResolver.resolve(
                GitDrawerSnapshotRequest(
                    workingDirectory: "/repo",
                    targetID: "split-a",
                    generation: 1,
                    selectedPath: nil
                ),
                runner: runner
            )
        }
    }

    @Test func resolverRejectsBareRepositoryBeforeWorktreeRootLookup() async throws {
        let runner = FakeGitDrawerRunner(
            outputs: [
                "rev-parse --is-bare-repository": "true\n",
            ],
            failures: [
                "rev-parse --show-toplevel",
            ]
        )

        await #expect(throws: GitDrawerShellError.bareRepository) {
            _ = try await GitDrawerSnapshotResolver.resolve(
                GitDrawerSnapshotRequest(
                    workingDirectory: "/repo.git",
                    targetID: "split-bare",
                    generation: 1,
                    selectedPath: nil
                ),
                runner: runner
            )
        }
    }

    @Test func resolverPropagatesSelectedDiffTruncation() async throws {
        let runner = FakeGitDrawerRunner(
            outputs: [
                "rev-parse --show-toplevel": "/repo",
                "rev-parse --is-bare-repository": "false",
                "symbolic-ref --quiet --short HEAD": "main",
                "rev-parse --short HEAD": "abc1234",
                "status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head main", "1 .M N... 100644 100644 100644 abc def large.swift"]),
                "diff --name-status -z --cached": "",
                "diff --name-status -z": joinedNul(["M", "large.swift"]),
                "diff --numstat -z --cached": "",
                "diff --numstat -z": joinedNul(["100\t10\tlarge.swift"]),
                "stash list": "",
                "diff --no-ext-diff --minimal --no-color -- large.swift": "@@\n" + String(repeating: "+line\n", count: 20),
            ],
            truncated: [
                "diff --no-ext-diff --minimal --no-color -- large.swift",
            ]
        )

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo",
                targetID: "split-a",
                generation: 1,
                selectedPath: "large.swift"
            ),
            runner: runner
        )

        #expect(snapshot.selectedFile == "large.swift")
        #expect(snapshot.isDiffTruncated)
    }

    @Test func renameNumstatZAttachesStatsToDestinationPath() {
        // Mirrors real `git diff --numstat -z` bytes for a rename-with-edit:
        // "1\t0\t" \0 "old.txt" \0 "new.txt" \0 — the counts token carries an EMPTY inline path
        // field and the from/to paths arrive as two separate NUL tokens.
        let snapshot = GitDrawerSnapshotParser.snapshot(
            repoRoot: "/tmp/repo",
            branch: "main",
            upstream: nil,
            aheadBehindOutput: "",
            statusPorcelainZ: joinedNul(["# branch.oid abc1234", "# branch.head main", "2 R. N... 100644 100644 100644 abc def R100 old.txt", "new.txt"]),
            unstagedNameStatusZ: "",
            stagedNameStatusZ: joinedNul(["R100", "old.txt", "new.txt"]),
            unstagedNumstatZ: "",
            stagedNumstatZ: joinedNul(["1\t0\t", "old.txt", "new.txt"]),
            stashListOutput: ""
        )

        let renamed = snapshot.staged.first
        #expect(renamed?.status == .renamed)
        #expect(renamed?.oldPath == "old.txt")
        #expect(renamed?.path == "new.txt")
        #expect(renamed?.additions == 1)
        #expect(renamed?.deletions == 0)
        #expect(snapshot.totalAdditions == 1)
        #expect(snapshot.totalDeletions == 0)
    }

    @Test func selectedDiffArgumentsAreStageAwareAndReadOnly() {
        func change(_ path: String, _ stage: GitDrawerChangeStage, _ status: GitDrawerFileStatus) -> GitDrawerFileChange {
            GitDrawerFileChange(path: path, oldPath: nil, status: status, stage: stage, additions: nil, deletions: nil)
        }
        func snapshot(staged: [String] = [], unstaged: [String] = [], untracked: [String] = []) -> GitDrawerSnapshot {
            GitDrawerSnapshot(
                repoRoot: "/repo", branch: "main", upstream: nil, ahead: 0, behind: 0,
                staged: staged.map { change($0, .staged, .modified) },
                unstaged: unstaged.map { change($0, .unstaged, .modified) },
                untracked: untracked.map { change($0, .untracked, .untracked) },
                conflicted: [], stashCount: 0, selectedFile: nil, selectedDiff: nil,
                isDiffTruncated: false, generation: 0
            )
        }
        let base = ["diff", "--no-ext-diff", "--minimal", "--no-color"]

        #expect(GitDrawerSnapshotResolver.selectedDiffArguments(for: "s.txt", in: snapshot(staged: ["s.txt"]))
            == base + ["--cached", "--", "s.txt"])
        #expect(GitDrawerSnapshotResolver.selectedDiffArguments(for: "u.txt", in: snapshot(untracked: ["u.txt"]))
            == base + ["--no-index", "--", "/dev/null", "u.txt"])
        #expect(GitDrawerSnapshotResolver.selectedDiffArguments(for: "w.txt", in: snapshot(unstaged: ["w.txt"]))
            == base + ["--", "w.txt"])
        // Staged AND unstaged (MM): compare against HEAD so the pane contains both staged and
        // unstaged hunks instead of showing only the worktree-vs-index portion.
        #expect(GitDrawerSnapshotResolver.selectedDiffArguments(for: "mm.txt", in: snapshot(staged: ["mm.txt"], unstaged: ["mm.txt"]))
            == base + ["HEAD", "--", "mm.txt"])
        // MM on an UNBORN repo (no commits): `git diff HEAD` would fail with exit 128 and throw out
        // of the whole resolve, so the combined view must degrade to the worktree diff.
        #expect(GitDrawerSnapshotResolver.selectedDiffArguments(for: "mm.txt", in: snapshot(staged: ["mm.txt"], unstaged: ["mm.txt"]), hasCommits: false)
            == base + ["--", "mm.txt"])
        // Every stage variant must stay read-only.
        let mixed = snapshot(staged: ["s.txt"], unstaged: ["w.txt"], untracked: ["u.txt"])
        for path in ["s.txt", "w.txt", "u.txt"] {
            let args = GitDrawerSnapshotResolver.selectedDiffArguments(for: path, in: mixed)
            #expect(GitDrawerGitCommand(arguments: args).isReadOnly)
        }
    }

    @Test func resolverUsesCachedDiffForStagedOnlyFile() async throws {
        // The worktree `diff -- staged-new.swift` key is intentionally absent: if the resolver
        // failed to switch to `--cached`, the fake returns "" and the assertion below fails.
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo",
            "rev-parse --is-bare-repository": "false",
            "symbolic-ref --quiet --short HEAD": "main",
            "rev-parse --short HEAD": "abc1234",
            "status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head main", "1 A. N... 100644 100644 100644 abc def staged-new.swift"]),
            "diff --name-status -z --cached": joinedNul(["A", "staged-new.swift"]),
            "diff --name-status -z": "",
            "diff --numstat -z --cached": joinedNul(["2\t0\tstaged-new.swift"]),
            "diff --numstat -z": "",
            "stash list": "",
            "diff --no-ext-diff --minimal --no-color --cached -- staged-new.swift": "@@ -0,0 +1,2 @@\n+hello\n+world",
        ])

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo", targetID: "s", generation: 1, selectedPath: "staged-new.swift"
            ),
            runner: runner
        )

        #expect(snapshot.staged.map(\.path) == ["staged-new.swift"])
        #expect(snapshot.selectedDiff == "@@ -0,0 +1,2 @@\n+hello\n+world")
    }

    @Test func resolverUsesNoIndexDiffForUntrackedFile() async throws {
        let runner = FakeGitDrawerRunner(outputs: [
            "rev-parse --show-toplevel": "/repo",
            "rev-parse --is-bare-repository": "false",
            "symbolic-ref --quiet --short HEAD": "main",
            "rev-parse --short HEAD": "abc1234",
            "status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head main", "? fresh.swift"]),
            "diff --name-status -z --cached": "",
            "diff --name-status -z": "",
            "diff --numstat -z --cached": "",
            "diff --numstat -z": "",
            "stash list": "",
            "diff --no-ext-diff --minimal --no-color --no-index -- /dev/null fresh.swift":
                "diff --git a/fresh.swift b/fresh.swift\n@@ -0,0 +1 @@\n+content",
        ])

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo", targetID: "u", generation: 1, selectedPath: "fresh.swift"
            ),
            runner: runner
        )

        #expect(snapshot.untracked.map(\.path) == ["fresh.swift"])
        #expect(snapshot.selectedDiff?.contains("+content") == true)
    }

    @Test func resolverRendersUnbornBranchInsteadOfFailing() async throws {
        // Fresh `git init`, no commits: `rev-parse --short HEAD` fails (exit 128) but `symbolic-ref`
        // still resolves the default branch name, so the drawer must render the file list.
        let runner = FakeGitDrawerRunner(
            outputs: [
                "rev-parse --show-toplevel": "/repo",
                "rev-parse --is-bare-repository": "false",
                "symbolic-ref --quiet --short HEAD": "main",
                "status --porcelain=v2 -z --branch": joinedNul([
                    "# branch.oid (initial)", "# branch.head main", "1 A. N... 100644 100644 100644 abc def staged.txt", "? untracked.txt",
                ]),
                "diff --name-status -z --cached": joinedNul(["A", "staged.txt"]),
                "diff --name-status -z": "",
                "diff --numstat -z --cached": joinedNul(["1\t0\tstaged.txt"]),
                "diff --numstat -z": "",
                "stash list": "",
            ],
            failures: [
                "rev-parse --short HEAD",
                "rev-parse --abbrev-ref --symbolic-full-name @{upstream}",
                "rev-list --left-right --count @{upstream}...HEAD",
            ]
        )

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: "/repo", targetID: "unborn", generation: 4, selectedPath: nil
            ),
            runner: runner
        )

        #expect(snapshot.branch == "main")
        #expect(snapshot.staged.map(\.path) == ["staged.txt"])
        #expect(snapshot.untracked.map(\.path) == ["untracked.txt"])
    }

    @Test func resolverRendersUntrackedFileDiffViaRealGit() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-untracked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.invalid"], in: tempRoot)
        try runGit(["config", "user.name", "YEN Test"], in: tempRoot)
        try "seed\n".write(to: tempRoot.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "seed.txt"], in: tempRoot)
        try runGit(["commit", "-m", "seed"], in: tempRoot)
        try "fresh untracked line\n".write(
            to: tempRoot.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8
        )

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: tempRoot.path, targetID: "u", generation: 9, selectedPath: "new.txt"
            ),
            runner: GitDrawerShellClient(),
            timeout: 10
        )

        #expect(snapshot.untracked.map(\.path) == ["new.txt"])
        let diff = try #require(snapshot.selectedDiff)
        #expect(diff.contains("fresh untracked line"))
    }

    @Test func resolverIncludesUntrackedFilesStoredInRealGitStash() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-stash-untracked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.invalid"], in: tempRoot)
        try runGit(["config", "user.name", "YEN Test"], in: tempRoot)
        try "tracked\n".write(to: tempRoot.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: tempRoot)
        try runGit(["commit", "-m", "seed"], in: tempRoot)
        try "tracked\nedited\n".write(to: tempRoot.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "fresh\n".write(to: tempRoot.appendingPathComponent("fresh.txt"), atomically: true, encoding: .utf8)
        try runGit(["stash", "push", "-u", "-m", "tracked and untracked"], in: tempRoot)

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: tempRoot.path,
                targetID: "stash-u",
                generation: 11,
                selectedPath: nil
            ),
            runner: GitDrawerShellClient(),
            timeout: 10
        )

        let filesByPath = Dictionary(
            uniqueKeysWithValues: (snapshot.stashEntries.first?.files ?? []).map { ($0.path, $0.status) }
        )
        #expect(filesByPath["tracked.txt"] == .modified)
        #expect(filesByPath["fresh.txt"] == .added)
    }

    @Test func resolverRendersUnbornRepositoryViaRealGit() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-unborn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.invalid"], in: tempRoot)
        try runGit(["config", "user.name", "YEN Test"], in: tempRoot)
        try "staged\n".write(to: tempRoot.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "staged.txt"], in: tempRoot)
        try "untracked\n".write(to: tempRoot.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let runner = CountingGitRunner()
        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: tempRoot.path, targetID: "unborn", generation: 11, selectedPath: nil
            ),
            runner: runner,
            timeout: 10
        )

        #expect(await runner.count == 8)

        // symbolic-ref resolves the default branch name on an unborn branch, so this is NOT a failure.
        #expect(!snapshot.branch.isEmpty)
        #expect(snapshot.branch != "no commits yet")
        #expect(snapshot.staged.map(\.path) == ["staged.txt"])
        #expect(snapshot.untracked.contains { $0.path == "untracked.txt" })
    }

    @Test func resolverRendersStagedAndModifiedFileOnUnbornRepoViaRealGit() async throws {
        // Regression: a staged-then-modified file (AM) on an unborn repo would route the selected
        // diff through `git diff HEAD`, which exits 128 with no HEAD and threw out of the whole
        // resolve — flipping the drawer to an error when that file was selected. The combined view
        // must degrade to the worktree diff so the resolve succeeds and the pane is non-blank.
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-unborn-mm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try runGit(["init"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.invalid"], in: tempRoot)
        try runGit(["config", "user.name", "YEN Test"], in: tempRoot)
        try "one\n".write(to: tempRoot.appendingPathComponent("mm.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "mm.txt"], in: tempRoot)
        try "one\ntwo\n".write(to: tempRoot.appendingPathComponent("mm.txt"), atomically: true, encoding: .utf8)

        let snapshot = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(
                workingDirectory: tempRoot.path, targetID: "unborn-mm", generation: 12, selectedPath: "mm.txt"
            ),
            runner: GitDrawerShellClient(),
            timeout: 10
        )

        #expect(snapshot.staged.contains { $0.path == "mm.txt" })
        #expect(snapshot.unstaged.contains { $0.path == "mm.txt" })
        let diff = try #require(snapshot.selectedDiff)
        #expect(diff.contains("two"))
        #expect(!snapshot.hasCommits)
        let selected = try await GitDrawerSnapshotResolver.resolve(
            GitDrawerSnapshotRequest(workingDirectory: tempRoot.path, targetID: "unborn-mm", generation: 13, selectedPath: "mm.txt", listSnapshot: snapshot),
            runner: GitDrawerShellClient(), timeout: 10)
        #expect(selected.selectedDiff == snapshot.selectedDiff)
        #expect(!selected.hasCommits)
        #expect(selected.generation == 13)

    }
}

private func joinedNul(_ fields: [String]) -> String {
    fields.joined(separator: "\0") + "\0"
}

private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path] + arguments

    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        throw NSError(
            domain: "GitDrawerSnapshotParserTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(errorText)"]
        )
    }
}

private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private actor FakeGitDrawerRunner: GitDrawerCommandRunning {
    let outputs: [String: String]
    var failures: Set<String> = []
    var truncated: Set<String> = []
    private(set) var commands: [GitDrawerGitCommand] = []

    init(outputs: [String: String], failures: Set<String> = [], truncated: Set<String> = []) {
        self.outputs = ["status --porcelain=v2 -z --branch": joinedNul(["# branch.oid abc1234", "# branch.head main"])].merging(outputs) { _, value in value }
        self.failures = failures
        self.truncated = truncated
    }

    func run(
        _ command: GitDrawerGitCommand,
        currentDirectory: String,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> GitDrawerCommandOutput {
        commands.append(command)
        let key = command.arguments.joined(separator: " ")
        if failures.contains(key) {
            throw GitDrawerShellError.commandFailed(key)
        }
        return GitDrawerCommandOutput(
            stdout: outputs[key] ?? "",
            stderr: "",
            wasTruncated: truncated.contains(key)
        )
    }
}

private actor CountingGitRunner: GitDrawerCommandRunning {
    private(set) var count = 0
    func run(_ command: GitDrawerGitCommand, currentDirectory: String, timeout: TimeInterval,
             stdoutLimit: Int, stderrLimit: Int) async throws -> GitDrawerCommandOutput {
        count += 1
        return try await GitDrawerShellClient().run(command, currentDirectory: currentDirectory,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
    }
}
