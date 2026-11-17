#if os(macOS)
import Foundation

struct GitDrawerSnapshotRequest: Equatable, Sendable {
    let workingDirectory: String
    let targetID: String
    let generation: Int
    let selectedPath: String?
    var listSnapshot: GitDrawerSnapshot? = nil
}

struct GitDrawerGitCommand: Equatable, Sendable {
    static let mutatingSubcommands: Set<String> = [
        "add", "am", "apply", "bisect", "checkout", "cherry-pick", "clean", "commit",
        "merge", "mv", "pull", "push", "rebase", "reset", "restore", "revert", "rm",
        "stash", "switch", "tag", "worktree",
    ]

    let arguments: [String]

    var subcommand: String? {
        arguments.first
    }

    var isMutating: Bool {
        guard let subcommand else { return true }
        if subcommand == "stash" {
            guard let stashSubcommand = arguments.dropFirst().first else { return true }
            return !["list", "show"].contains(stashSubcommand)
        }
        return Self.mutatingSubcommands.contains(subcommand)
    }

    var isReadOnly: Bool {
        !isMutating
    }
}

struct GitDrawerCommandOutput: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let wasTruncated: Bool
}

enum GitDrawerShellError: Error, Equatable {
    case missingGit
    case mutatingCommandRejected([String])
    case commandFailed(String)
    case timedOut
    case bareRepository
}

protocol GitDrawerCommandRunning: Sendable {
    func run(
        _ command: GitDrawerGitCommand,
        currentDirectory: String,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> GitDrawerCommandOutput
}

struct GitDrawerShellClient: GitDrawerCommandRunning {
    var disableOptionalLocks = false
    var terminationGracePeriod: TimeInterval? = nil

    nonisolated static let defaultTimeout: TimeInterval = 2
    nonisolated static let defaultStdoutLimit = 256 * 1024
    nonisolated static let defaultStderrLimit = 16 * 1024
    nonisolated static let gitExecutableURL = URL(fileURLWithPath: "/usr/bin/git")

    func run(
        _ command: GitDrawerGitCommand,
        currentDirectory: String,
        timeout: TimeInterval = Self.defaultTimeout,
        stdoutLimit: Int = Self.defaultStdoutLimit,
        stderrLimit: Int = Self.defaultStderrLimit
    ) async throws -> GitDrawerCommandOutput {
        guard command.isReadOnly else {
            throw GitDrawerShellError.mutatingCommandRejected(command.arguments)
        }
        guard FileManager.default.isExecutableFile(atPath: Self.gitExecutableURL.path) else {
            throw GitDrawerShellError.missingGit
        }

        // `git diff --no-index` (used to render an untracked file against /dev/null) exits 1 when
        // the inputs differ — which is the normal "here is the diff" case, not a failure.
        let allowedExitCodes: Set<Int32> = command.arguments.contains("--no-index") ? [0, 1] : [0]

        return try await withThrowingTaskGroup(of: GitDrawerCommandOutput.self) { group in
            group.addTask {
                let output = try await IDEBlockingProcessRunner.run(
                    executableURL: Self.gitExecutableURL,
                    arguments: ["-C", currentDirectory] + command.arguments,
                    currentDirectory: currentDirectory,
                    environment: nonInteractiveGitEnvironment(),
                    allowedExitCodes: allowedExitCodes,
                    terminationGracePeriod: terminationGracePeriod,
                    stdoutLimit: stdoutLimit,
                    stderrLimit: stderrLimit,
                    toolUnavailable: GitDrawerShellError.missingGit,
                    commandFailed: { GitDrawerShellError.commandFailed($0) }
                )
                return GitDrawerCommandOutput(
                    stdout: output.stdout, stderr: output.stderr,
                    wasTruncated: output.wasTruncated
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GitDrawerShellError.timedOut
            }

            let result = try await group.next()
            group.cancelAll()
            return result ?? GitDrawerCommandOutput(stdout: "", stderr: "", wasTruncated: false)
        }
    }

    private func nonInteractiveGitEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        if disableOptionalLocks { environment["GIT_OPTIONAL_LOCKS"] = "0" }
        return environment
    }
}

enum GitDrawerSnapshotResolver {
    static func resolve<Runner: GitDrawerCommandRunning>(
        _ request: GitDrawerSnapshotRequest,
        runner: Runner,
        timeout: TimeInterval = GitDrawerShellClient.defaultTimeout,
        stdoutLimit: Int = GitDrawerShellClient.defaultStdoutLimit,
        stderrLimit: Int = GitDrawerShellClient.defaultStderrLimit
    ) async throws -> GitDrawerSnapshot {
        if let snapshot = request.listSnapshot,
           snapshot.workingDirectory == request.workingDirectory {
            return try await resolveSelection(request, snapshot: snapshot, runner: runner,
                timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        }

        let bare = try await runOptionalLine(
            ["rev-parse", "--is-bare-repository"],
            in: request.workingDirectory,
            runner: runner,
            timeout: timeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit
        )
        guard bare != "true" else {
            throw GitDrawerShellError.bareRepository
        }

        let repoRoot = try await runLine(
            ["rev-parse", "--show-toplevel"],
            in: request.workingDirectory,
            runner: runner,
            timeout: timeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit
        )

        async let statusTask = run(
            GitStatusPorcelainV2.arguments,
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        async let stagedNameStatusTask = run(
            ["diff", "--name-status", "-z", "--cached"],
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        async let unstagedNameStatusTask = run(
            ["diff", "--name-status", "-z"],
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        async let stagedNumstatTask = run(
            ["diff", "--numstat", "-z", "--cached"],
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        async let unstagedNumstatTask = run(
            ["diff", "--numstat", "-z"],
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        async let stashListTask = run(
            ["stash", "list"],
            in: repoRoot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)

        let statusOutput = try await statusTask
        guard !statusOutput.wasTruncated, let metadata = GitStatusPorcelainV2(statusOutput.stdout) else {
            throw GitDrawerShellError.commandFailed("Git status output is incomplete or invalid.")
        }
        // Keep Git's configured unique abbreviation for detached HEADs.
        let branch = metadata.isDetached
            ? await GitBranchResolver.detached(in: repoRoot, runner: runner) ?? "detached"
            : metadata.head
        let status = statusOutput.stdout
        let stagedNameStatus = try await stagedNameStatusTask.stdout
        let unstagedNameStatus = try await unstagedNameStatusTask.stdout
        let stagedNumstat = try await stagedNumstatTask.stdout
        let unstagedNumstat = try await unstagedNumstatTask.stdout
        let stashList = try await stashListTask.stdout
        let stashFileOutputsByRef = await stashFileOutputs(
            stashListOutput: stashList,
            repoRoot: repoRoot,
            runner: runner,
            timeout: timeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit
        )

        let parsed = GitDrawerSnapshotParser.snapshot(
            repoRoot: repoRoot,
            branch: branch,
            upstream: metadata.upstream,
            aheadBehindOutput: "\(metadata.behind) \(metadata.ahead)",
            statusPorcelainZ: status,
            parsedStatusEntries: metadata.entries,
            unstagedNameStatusZ: unstagedNameStatus,
            stagedNameStatusZ: stagedNameStatus,
            unstagedNumstatZ: unstagedNumstat,
            stagedNumstatZ: stagedNumstat,
            stashListOutput: stashList,
            stashFileOutputsByRef: stashFileOutputsByRef
        )

        let snapshot = GitDrawerSnapshot(
            repoRoot: parsed.repoRoot,
            workingDirectory: request.workingDirectory,
            branch: parsed.branch, upstream: parsed.upstream,
            ahead: parsed.ahead, behind: parsed.behind,
            staged: parsed.staged, unstaged: parsed.unstaged,
            untracked: parsed.untracked, conflicted: parsed.conflicted,
            stashCount: parsed.stashCount, stashEntries: parsed.stashEntries,
            isStashListTruncated: parsed.isStashListTruncated,
            selectedFile: nil, selectedDiff: nil, isDiffTruncated: false,
            isFileListTruncated: parsed.isFileListTruncated,
            generation: request.generation, hasCommits: metadata.hasCommits
        )
        return try await resolveSelection(request, snapshot: snapshot, runner: runner,
            timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
    }

    private static func resolveSelection<Runner: GitDrawerCommandRunning>(
        _ request: GitDrawerSnapshotRequest,
        snapshot: GitDrawerSnapshot,
        runner: Runner,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> GitDrawerSnapshot {
        let output: GitDrawerCommandOutput?
        if let path = request.selectedPath, !path.isEmpty {
            output = try await run(
                selectedDiffArguments(for: path, in: snapshot, hasCommits: snapshot.hasCommits),
                in: snapshot.repoRoot, runner: runner,
                timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
        } else {
            output = nil
        }
        return GitDrawerSnapshot(
            repoRoot: snapshot.repoRoot, workingDirectory: snapshot.workingDirectory,
            branch: snapshot.branch, upstream: snapshot.upstream,
            ahead: snapshot.ahead, behind: snapshot.behind,
            staged: snapshot.staged, unstaged: snapshot.unstaged,
            untracked: snapshot.untracked, conflicted: snapshot.conflicted,
            stashCount: snapshot.stashCount, stashEntries: snapshot.stashEntries,
            isStashListTruncated: snapshot.isStashListTruncated,
            selectedFile: request.selectedPath, selectedDiff: output?.stdout,
            isDiffTruncated: output?.wasTruncated ?? false,
            isFileListTruncated: snapshot.isFileListTruncated,
            generation: request.generation, hasCommits: snapshot.hasCommits
        )
    }

    /// Stage-aware raw-diff command for the selected file. Unstaged/conflicted rows use the
    /// worktree-vs-index diff; a staged-only row uses `--cached`; a row with BOTH staged and
    /// unstaged changes uses `git diff HEAD` for the combined view; an untracked row is diffed
    /// against `/dev/null` with `--no-index` (which exits 1 when content differs — the shell
    /// client tolerates that exit code). Always plain raw git diff, never `delta`.
    ///
    /// `hasCommits` MUST be false on an unborn branch (fresh `git init`, no commits): `git diff
    /// HEAD` fails with exit 128 when HEAD does not resolve, which would throw out of the whole
    /// resolve and flip the drawer to an error when a staged+modified file is selected. On an
    /// unborn repo the combined view degrades to the worktree diff (still non-blank).
    static func selectedDiffArguments(
        for path: String,
        in snapshot: GitDrawerSnapshot,
        hasCommits: Bool = true
    ) -> [String] {
        let base = ["diff", "--no-ext-diff", "--minimal", "--no-color"]
        let hasUnstaged = snapshot.unstaged.contains(where: { $0.path == path })
        let hasStaged = snapshot.staged.contains(where: { $0.path == path })
        if hasUnstaged && hasStaged {
            return hasCommits ? base + ["HEAD", "--", path] : base + ["--", path]
        }
        if hasUnstaged {
            return base + ["--", path]
        }
        if hasStaged {
            return base + ["--cached", "--", path]
        }
        if snapshot.untracked.contains(where: { $0.path == path }) {
            return base + ["--no-index", "--", "/dev/null", path]
        }
        return base + ["--", path]
    }

    private static func run<Runner: GitDrawerCommandRunning>(
        _ arguments: [String],
        in currentDirectory: String,
        runner: Runner,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> GitDrawerCommandOutput {
        try await runner.run(
            GitDrawerGitCommand(arguments: arguments),
            currentDirectory: currentDirectory,
            timeout: timeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit
        )
    }

    private static func runLine<Runner: GitDrawerCommandRunning>(
        _ arguments: [String],
        in currentDirectory: String,
        runner: Runner,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> String {
        try await run(
            arguments,
            in: currentDirectory,
            runner: runner,
            timeout: timeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: stderrLimit
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runOptionalLine<Runner: GitDrawerCommandRunning>(
        _ arguments: [String],
        in currentDirectory: String,
        runner: Runner,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async throws -> String? {
        do {
            return try await runLine(
                arguments,
                in: currentDirectory,
                runner: runner,
                timeout: timeout,
                stdoutLimit: stdoutLimit,
                stderrLimit: stderrLimit
            )
        } catch GitDrawerShellError.commandFailed {
            return nil
        }
    }

    private static func stashFileOutputs<Runner: GitDrawerCommandRunning>(
        stashListOutput: String,
        repoRoot: String,
        runner: Runner,
        timeout: TimeInterval,
        stdoutLimit: Int,
        stderrLimit: Int
    ) async -> [String: String] {
        let refs = Array(GitDrawerSnapshotParser.stashRefs(stashListOutput)
            .prefix(GitDrawerSnapshotParser.defaultStashEntryLimit))
        return await withTaskGroup(of: (String, String).self) { group in
            for ref in refs {
                group.addTask {
                    do {
                        let output = try await run(
                            ["stash", "show", "--include-untracked", "--name-status", "-z", ref],
                            in: repoRoot,
                            runner: runner,
                            timeout: timeout,
                            stdoutLimit: stdoutLimit,
                            stderrLimit: stderrLimit
                        )
                        return (ref, output.stdout)
                    } catch {
                        return (ref, "")
                    }
                }
            }

            var outputs: [String: String] = [:]
            for await (ref, output) in group {
                outputs[ref] = output
            }
            return outputs
        }
    }
}
#endif
