import AppKit
import CoreServices
import Testing
@testable import YEN

@MainActor
struct GitDrawerControllerTests {
    @Test func observableDrawerRefreshesWhenRepositoryFileChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "--quiet", directory.path]
        try git.run()
        git.waitUntilExit()
        #expect(git.terminationStatus == 0)
        let container = TerminalViewContainer(terminalContentView: NSView(), dockedSidebarVisibility: { _ in false })
        // The native test host can be permanently occluded by the desktop session.
        // Control only visibility; use the actual drawer, Git client and filesystem.
        var observable = true
        let controller = GitDrawerController(container: container, focusedDirectory: { directory.path },
            backgroundRefreshEligibility: { observable })
        defer { controller.close() }
        controller.show()
        await controller.testingWaitForRefresh()
        await controller.testingWaitForWatcher()
        try #require(controller.testingHasRepositoryWatcher)
        #expect(controller.testingFallbackRefreshInterval == 60)
        // Let the startup catch-up finish before writing the file under test.
        try await Task.sleep(for: .milliseconds(900))
        await controller.testingWaitForRefresh()
        #expect(controller.presentationState?.emptyMessage == "Working tree clean")
        try "changed".write(to: directory.appendingPathComponent("event.txt"), atomically: true, encoding: .utf8)
        await waitUntil(timeout: 3) {
            controller.presentationState?.groups.flatMap(\.rows).contains { $0.repoRelativePath == "event.txt" } == true
        }
        #expect(controller.presentationState?.groups.flatMap(\.rows).contains { $0.repoRelativePath == "event.txt" } == true)
        try await Task.sleep(for: .milliseconds(900))
        let settledCount = controller.testingRefreshStartCount
        NotificationCenter.default.post(name: .yenTabSidebarGitContextDidChange, object: directory.path)
        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.testingRefreshStartCount == settledCount)
        observable = false
        try "hidden".write(to: directory.appendingPathComponent("hidden.txt"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.testingRefreshStartCount == settledCount)
        observable = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await waitUntil(timeout: 3) {
            controller.presentationState?.groups.flatMap(\.rows).contains { $0.repoRelativePath == "hidden.txt" } == true
        }
        #expect(controller.presentationState?.groups.flatMap(\.rows).contains { $0.repoRelativePath == "hidden.txt" } == true)
        controller.close()
        #expect(!controller.testingHasRepositoryWatcher)
    }

    @Test func linkedWorktreeWatcherIncludesSharedMetadataAndStopsCallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("checkout")
        let common = directory.appendingPathComponent("shared")
        let gitDirectory = common.appendingPathComponent("worktrees/topic")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "gitdir: ../shared/worktrees/topic\n".write(to: root.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "../..\n".write(to: gitDirectory.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        let paths = try #require(await Task.detached {
            GitDrawerRepositoryWatchPaths.resolve(repositoryRoot: root.path)
        }.value)
        let canonicalCommon = common.resolvingSymlinksInPath().path
        let canonicalGit = gitDirectory.resolvingSymlinksInPath().path
        #expect(Set(paths.paths) == [root.resolvingSymlinksInPath().path, canonicalCommon])
        #expect(paths.gitDirectories == [canonicalCommon, canonicalGit])
        #expect(!paths.shouldRefresh(path: canonicalGit + "/index.lock", flags: 0))
        #expect(paths.shouldRefresh(path: canonicalGit + "/index", flags: 0))
        #expect(!paths.shouldRefresh(path: canonicalGit + "/index", flags: UInt32(kFSEventStreamEventFlagOwnEvent)))
        #expect(paths.shouldRefresh(path: canonicalGit + "/index", flags: UInt32(kFSEventStreamEventFlagOwnEvent | kFSEventStreamEventFlagMustScanSubDirs)))
        var events = 0
        let watcher = try #require(GitDrawerRepositoryWatcher(paths: paths) { events += 1 })
        defer { watcher.stop() }
        try "first".write(to: common.appendingPathComponent("packed-refs"), atomically: true, encoding: .utf8)
        await waitUntil(timeout: 3) { events > 0 }
        #expect(events > 0)
        watcher.stop()
        let stoppedCount = events
        try "second".write(to: gitDirectory.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(900))
        #expect(events == stoppedCount)
    }

    @Test func retargetingStopsEventsFromThePreviousRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var current = first.path
        let container = TerminalViewContainer(terminalContentView: NSView(), dockedSidebarVisibility: { _ in false })
        let controller = GitDrawerController(container: container, focusedDirectory: { current },
            backgroundRefreshEligibility: { true }, resolver: emptySnapshot)
        defer { controller.close() }
        controller.show()
        await controller.testingWaitForRefresh()
        await controller.testingWaitForWatcher()
        current = second.path
        #expect(controller.retargetIfNeeded())
        await controller.testingWaitForRefresh()
        await controller.testingWaitForWatcher()
        try #require(controller.testingHasRepositoryWatcher)
        try await Task.sleep(for: .milliseconds(900))
        await controller.testingWaitForRefresh()
        let count = controller.testingRefreshStartCount
        try "old".write(to: first.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.testingRefreshStartCount == count)
        try "new".write(to: second.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        await waitUntil(timeout: 3) { controller.testingRefreshStartCount > count }
        #expect(controller.testingRefreshStartCount > count)
        controller.close()
        let closedCount = controller.testingRefreshStartCount
        try "closed".write(to: second.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(900))
        #expect(controller.testingRefreshStartCount == closedCount)
    }

    @Test func selectingAFileReadsOnlyItsDiffFromTheRealRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "--quiet", directory.path]
        try git.run()
        git.waitUntilExit()
        #expect(git.terminationStatus == 0)
        try "first\n".write(to: directory.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        try "second\n".write(to: directory.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        let runner = SelectionCommandRecorder()
        let container = TerminalViewContainer(terminalContentView: NSView(), dockedSidebarVisibility: { _ in false })
        let controller = GitDrawerController(container: container, focusedDirectory: { directory.path }, resolver: { request in
            try await GitDrawerSnapshotResolver.resolve(request, runner: runner)
        })
        defer { controller.close() }
        controller.show()
        await waitUntil(timeout: 5) { controller.presentationState?.groups.first?.rows.count == 2 }
        #expect(controller.presentationState?.groups.first?.rows.count == 2)
        let before = await runner.commands.count
        controller.select(path: "first.txt")
        await waitUntil(timeout: 5) { controller.presentationState?.selectedDiffText.contains("+first") == true }
        #expect(controller.presentationState?.selectedDiffText.contains("+first") == true)
        let after = await runner.commands
        #expect(after.count - before == 1)
        #expect(after.last == ["diff", "--no-ext-diff", "--minimal", "--no-color", "--no-index", "--", "/dev/null", "first.txt"])
        controller.select(path: "second.txt")
        await waitUntil(timeout: 5) { controller.presentationState?.selectedDiffText.contains("+second") == true }
        #expect(controller.presentationState?.selectedDiffText.contains("+second") == true)
        #expect(await runner.commands.count - after.count == 1)
    }

    @Test func unchangedBackgroundRefreshDoesNotShowLoadingOrReplaceThePresentation() async {
        let container = TerminalViewContainer(terminalContentView: NSView(), dockedSidebarVisibility: { _ in false })
        let controller = GitDrawerController(container: container, focusedDirectory: { "/repo" }, resolver: emptySnapshot)
        defer { controller.close() }
        controller.show()
        await controller.testingWaitForRefresh()
        let count = controller.testingPresentationUpdateCount
        let state = controller.presentationState
        #expect(controller.refresh(background: true))
        #expect(!controller.isLoading)
        #expect(controller.testingPresentationUpdateCount == count)
        await controller.testingWaitForRefresh()
        #expect(controller.presentationState == state)
        #expect(controller.testingPresentationUpdateCount == count)
        #expect(controller.refresh())
        #expect(controller.isLoading)
        await controller.testingWaitForRefresh()
        #expect(!controller.isLoading)
        #expect(controller.testingPresentationUpdateCount == count + 2)
    }

    @Test func showAttachesLoadingDrawerThenAppliesSnapshot() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in
                GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: "main",
                    upstream: "origin/main",
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: nil,
                    selectedDiff: nil,
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )
        defer { controller.close() }

        controller.show()

        #expect(controller.isVisible)
        #expect(abs((container.gitDrawerHeight ?? 0) - GitDrawerHeightPolicy.defaultHeight(for: 800)) < 0.01)

        await waitUntil {
            controller.presentationState?.header.title == "repo // main"
        }

        #expect(controller.presentationState?.emptyMessage == "Working tree clean")
    }

    @Test func closeRemovesDrawerAndCancelsVisibility() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in emptySnapshot(request: request) }
        )

        controller.show()
        controller.close()

        #expect(!controller.isVisible)
        await waitUntil {
            container.gitDrawerHeight == nil
        }
    }

    @Test func showAndClosePreserveTerminalFirstResponder() async {
        let terminalView = TestFocusableView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let container = TerminalViewContainer(
            terminalContentView: terminalView,
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeFirstResponder(terminalView)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in emptySnapshot(request: request) }
        )

        controller.show()

        #expect(window.firstResponder === terminalView)

        await waitUntil {
            controller.presentationState?.header.title == "repo // main"
        }
        controller.close()

        #expect(window.firstResponder === terminalView)
    }


    @Test func retargetRefreshesWhenFocusedDirectoryChanges() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        var focusedDirectory = "/repo-a"
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { focusedDirectory },
            resolver: { request in
                GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: URL(fileURLWithPath: request.workingDirectory).lastPathComponent,
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: nil,
                    selectedDiff: nil,
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil {
            controller.presentationState?.header.title == "repo-a // repo-a"
        }

        focusedDirectory = "/repo-b"
        #expect(controller.retargetIfNeeded())
        await waitUntil {
            controller.presentationState?.header.title == "repo-b // repo-b"
        }
    }

    @Test func staleResolveAfterRetargetDoesNotRepaintNewerDrawer() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        var focusedDirectory = "/repo-a"
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { focusedDirectory },
            resolver: { request in
                if request.workingDirectory == "/repo-a" {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                return GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: request.workingDirectory == "/repo-a" ? "old" : "new",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: nil,
                    selectedDiff: nil,
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        focusedDirectory = "/repo-b"
        #expect(controller.retargetIfNeeded())

        await waitUntil {
            controller.presentationState?.repoRoot == "/repo-b"
        }
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(controller.presentationState?.header.title == "repo-b // new")
        #expect(controller.presentationState?.repoRoot == "/repo-b")
    }

    @Test func tabSidebarStateNotificationRetargetsFocusedDirectoryWithoutPolling() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        var focusedDirectory = "/repo-a"
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { focusedDirectory },
            resolver: { request in
                GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: URL(fileURLWithPath: request.workingDirectory).lastPathComponent,
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: nil,
                    selectedDiff: nil,
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil {
            controller.presentationState?.header.title == "repo-a // repo-a"
        }

        focusedDirectory = "/repo-b"
        NotificationCenter.default.post(name: .yenTabSidebarStateDidChange, object: nil)

        await waitUntil {
            controller.presentationState?.header.title == "repo-b // repo-b"
        }
    }

    @Test func gitContextNotificationRefreshesCurrentWorkingDirectoryOnly() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let recorder = GitDrawerRequestedPathRecorder()
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo-a" },
            resolver: { request in
                await recorder.append(request.selectedPath)
                let count = await recorder.paths.count
                return GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: "refresh-\(count)",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: request.selectedPath,
                    selectedDiff: nil,
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil {
            controller.presentationState?.header.title == "repo-a // refresh-1"
        }

        NotificationCenter.default.post(name: .yenTabSidebarGitContextDidChange, object: "/other-repo")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(controller.presentationState?.header.title == "repo-a // refresh-1")

        NotificationCenter.default.post(name: .yenTabSidebarGitContextDidChange, object: "/repo-a")

        await waitUntil {
            controller.presentationState?.header.title == "repo-a // refresh-2"
        }
    }

    @Test func multipleVisibleDrawersKeepIndependentWindowState() async {
        let firstContainer = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        let secondContainer = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        firstContainer.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        secondContainer.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        var firstFocusedDirectory = "/repo-a"
        var secondFocusedDirectory = "/repo-b"
        let resolver: GitDrawerController.Resolver = { request in
            GitDrawerSnapshot(
                repoRoot: request.workingDirectory,
                branch: URL(fileURLWithPath: request.workingDirectory).lastPathComponent,
                upstream: nil,
                ahead: 0,
                behind: 0,
                staged: [],
                unstaged: [],
                untracked: [],
                conflicted: [],
                stashCount: 0,
                selectedFile: nil,
                selectedDiff: nil,
                isDiffTruncated: false,
                generation: request.generation
            )
        }
        let firstController = GitDrawerController(
            container: firstContainer,
            focusedDirectory: { firstFocusedDirectory },
            resolver: resolver
        )
        let secondController = GitDrawerController(
            container: secondContainer,
            focusedDirectory: { secondFocusedDirectory },
            resolver: resolver
        )

        firstController.show()
        secondController.show()
        await waitUntil {
            firstController.presentationState?.header.title == "repo-a // repo-a"
                && secondController.presentationState?.header.title == "repo-b // repo-b"
        }

        firstFocusedDirectory = "/repo-c"
        #expect(firstController.retargetIfNeeded())
        await waitUntil {
            firstController.presentationState?.header.title == "repo-c // repo-c"
        }

        #expect(firstController.presentationState?.repoRoot == "/repo-c")
        #expect(secondController.presentationState?.header.title == "repo-b // repo-b")
        #expect(secondController.presentationState?.repoRoot == "/repo-b")
        #expect(secondController.isVisible)

        secondFocusedDirectory = "/repo-d"
        #expect(secondController.retargetIfNeeded())
        await waitUntil {
            secondController.presentationState?.header.title == "repo-d // repo-d"
        }

        #expect(firstController.presentationState?.repoRoot == "/repo-c")
        #expect(secondController.presentationState?.repoRoot == "/repo-d")
    }

    @Test func selectingPathRefreshesSelectedFileDiff() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let recorder = GitDrawerRequestedPathRecorder()
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in
                await recorder.append(request.selectedPath)
                return GitDrawerSnapshot(
                    repoRoot: request.workingDirectory,
                    branch: "main",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [
                        GitDrawerFileChange(
                            path: "Sources/App.swift",
                            oldPath: nil,
                            status: .modified,
                            stage: .staged,
                            additions: 3,
                            deletions: 1
                        ),
                    ],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: request.selectedPath,
                    selectedDiff: request.selectedPath.map { "diff --git a/\($0) b/\($0)" },
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil {
            controller.presentationState?.header.title == "repo // main"
        }

        controller.select(path: "Sources/App.swift")
        await waitUntil {
            controller.presentationState?.selectedPath == "Sources/App.swift"
        }

        #expect(await recorder.paths == [nil, "Sources/App.swift"])
        #expect(controller.presentationState?.selectedDiffText == "diff --git a/Sources/App.swift b/Sources/App.swift")
    }

    @Test func manualRefreshPreservesSelectedPathAndDiff() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let recorder = GitDrawerRequestedPathRecorder()
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in
                await recorder.append(request.selectedPath)
                return GitDrawerSnapshot(
                    repoRoot: "/repo",
                    branch: "main",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [
                        GitDrawerFileChange(
                            path: "Sources/App.swift",
                            oldPath: nil,
                            status: .modified,
                            stage: .staged,
                            additions: 3,
                            deletions: 1
                        ),
                    ],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: request.selectedPath,
                    selectedDiff: request.selectedPath.map { "diff \($0)" },
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil { controller.presentationState?.header.title == "repo // main" }
        controller.select(path: "Sources/App.swift")
        await waitUntil { controller.presentationState?.selectedDiffText == "diff Sources/App.swift" }

        #expect(controller.refresh())
        await waitUntilAsync {
            await recorder.paths.filter { $0 == "Sources/App.swift" }.count >= 2
        }

        let recordedPaths = await recorder.paths
        #expect(recordedPaths.first != nil)
        #expect(recordedPaths.first! == nil)
        #expect(recordedPaths.filter { $0 == "Sources/App.swift" }.count >= 2)
    }

    @Test func deletedSelectedFileCannotOpenOrReveal() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yen-git-drawer-deleted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let deletedPath = "Sources/Removed.swift"

        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { tempRoot.path },
            resolver: { request in
                GitDrawerSnapshot(
                    repoRoot: tempRoot.path,
                    branch: "main",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [
                        GitDrawerFileChange(
                            path: deletedPath,
                            oldPath: nil,
                            status: .deleted,
                            stage: .unstaged,
                            additions: 0,
                            deletions: 8
                        ),
                    ],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: request.selectedPath,
                    selectedDiff: request.selectedPath.map { "deleted diff \($0)" },
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )

        controller.show()
        await waitUntil { controller.presentationState?.header.title.hasSuffix(" // main") == true }
        controller.select(path: deletedPath)
        await waitUntil { controller.presentationState?.selectedPath == deletedPath }

        #expect(controller.presentationState?.canOpenSelectedPath == false)
        #expect(!controller.openSelectedFile(workspace: .shared))
        #expect(!controller.revealSelectedFile(workspace: .shared))
    }

    @Test func copySelectedPathAndDiffUsePlainTextPasteboard() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { request in
                GitDrawerSnapshot(
                    repoRoot: "/repo",
                    branch: "main",
                    upstream: nil,
                    ahead: 0,
                    behind: 0,
                    staged: [],
                    unstaged: [],
                    untracked: [],
                    conflicted: [],
                    stashCount: 0,
                    selectedFile: request.selectedPath,
                    selectedDiff: request.selectedPath.map { "@@\n+\($0)" },
                    isDiffTruncated: false,
                    generation: request.generation
                )
            }
        )
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("yen.git-drawer.tests.\(UUID().uuidString)"))

        controller.show()
        await waitUntil {
            controller.presentationState?.header.title == "repo // main"
        }
        controller.select(path: "Sources/App.swift")
        await waitUntil {
            controller.presentationState?.selectedPath == "Sources/App.swift"
        }

        #expect(controller.copySelectedPath(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "Sources/App.swift")
        #expect(controller.copy(path: "README.md", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "README.md")
        #expect(controller.copySelectedDiff(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "@@\n+Sources/App.swift")
    }

    @Test func hiddenDrawerDoesNotRetarget() {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        var focusedDirectory = "/repo-a"
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { focusedDirectory },
            resolver: { request in emptySnapshot(request: request) }
        )

        focusedDirectory = "/repo-b"

        #expect(!controller.retargetIfNeeded())
        #expect(controller.presentationState == nil)
    }

    @Test func missingFocusedDirectoryShowsNoRepoState() {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { nil },
            resolver: { request in emptySnapshot(request: request) }
        )

        controller.show()

        #expect(controller.presentationState?.header.title == "No Git repository")
        #expect(controller.presentationState?.notice?.title == "No Git repository here")
        #expect(controller.presentationState?.notice?.actionText?.contains("git init") == true)
        #expect(!controller.isLoading)
    }

    @Test func failedRefreshShowsGitReadErrorState() async {
        let container = TerminalViewContainer(
            terminalContentView: NSView(),
            dockedSidebarVisibility: { _ in false }
        )
        container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let controller = GitDrawerController(
            container: container,
            focusedDirectory: { "/repo" },
            resolver: { _ in throw GitDrawerShellError.commandFailed("status") }
        )

        controller.show()

        await waitUntil {
            controller.presentationState?.notice?.title == "Unable to read this worktree"
        }

        #expect(controller.presentationState?.header.title == "No Git repository")
        #expect(controller.presentationState?.notice?.actionText?.contains("permissions") == true)
        #expect(!controller.isLoading)
        let count = controller.testingPresentationUpdateCount
        #expect(controller.refresh(background: true))
        await controller.testingWaitForRefresh()
        #expect(controller.testingPresentationUpdateCount == count)
        controller.close()
    }

    @Test func failedRefreshShowsSpecificShellErrorState() async {
        let cases: [(GitDrawerShellError, String, String)] = [
            (.missingGit, "Git is not available", "/usr/bin/git"),
            (.timedOut, "Git is taking too long", "Refresh again"),
            (.bareRepository, "Bare repositories are not supported", "working tree checkout"),
            (.mutatingCommandRejected(["add", "."]), "Read-only drawer blocked a mutating command", "intentional write"),
        ]

        for (error, expectedTitle, expectedActionFragment) in cases {
            let container = TerminalViewContainer(
                terminalContentView: NSView(),
                dockedSidebarVisibility: { _ in false }
            )
            container.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
            let controller = GitDrawerController(
                container: container,
                focusedDirectory: { "/repo" },
                resolver: { _ in throw error }
            )

            controller.show()

            await waitUntil {
                controller.presentationState?.notice?.title == expectedTitle
            }

            #expect(controller.presentationState?.header.title == "No Git repository")
            #expect(controller.presentationState?.notice?.actionText?.contains(expectedActionFragment) == true)
            #expect(!controller.isLoading)
        }
    }

    @Test func escapeClosePredicateIsScopedToDrawerWindow() {
        let drawerWindow = NSWindow()
        let otherWindow = NSWindow()

        #expect(GitDrawerController.shouldCloseForKeyDown(
            keyCode: 0x35,
            eventWindow: drawerWindow,
            containerWindow: drawerWindow
        ))
        #expect(!GitDrawerController.shouldCloseForKeyDown(
            keyCode: 0x35,
            eventWindow: otherWindow,
            containerWindow: drawerWindow
        ))
        #expect(!GitDrawerController.shouldCloseForKeyDown(
            keyCode: 0x24,
            eventWindow: drawerWindow,
            containerWindow: drawerWindow
        ))
    }

    @Test func animationDurationUsesTransientReduceMotionPolicy() {
        #expect(GitDrawerController.animationDuration(reduceMotion: false) == TabSidebarController.transientAnimationDuration(reduceMotion: false))
        #expect(GitDrawerController.animationDuration(reduceMotion: true) == 0)
    }
}

private func emptySnapshot(request: GitDrawerSnapshotRequest) -> GitDrawerSnapshot {
    GitDrawerSnapshot(
        repoRoot: request.workingDirectory,
        branch: "main",
        upstream: nil,
        ahead: 0,
        behind: 0,
        staged: [],
        unstaged: [],
        untracked: [],
        conflicted: [],
        stashCount: 0,
        selectedFile: nil,
        selectedDiff: nil,
        isDiffTruncated: false,
        generation: request.generation
    )
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

private func waitUntilAsync(
    timeout: TimeInterval = 1,
    condition: @escaping () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

private actor GitDrawerRequestedPathRecorder {
    private var values: [String?] = []

    var paths: [String?] {
        values
    }

    func append(_ value: String?) {
        values.append(value)
    }
}

@MainActor
private final class TestFocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private actor SelectionCommandRecorder: GitDrawerCommandRunning {
    private(set) var commands: [[String]] = []
    func run(_ command: GitDrawerGitCommand, currentDirectory: String, timeout: TimeInterval, stdoutLimit: Int, stderrLimit: Int) async throws -> GitDrawerCommandOutput {
        commands.append(command.arguments)
        return try await GitDrawerShellClient().run(command, currentDirectory: currentDirectory, timeout: timeout, stdoutLimit: stdoutLimit, stderrLimit: stderrLimit)
    }
}
