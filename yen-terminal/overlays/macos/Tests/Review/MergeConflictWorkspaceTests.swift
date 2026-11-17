import Foundation
import Testing
@testable import YEN

struct MergeConflictParserTests {
    @Test func parsesStandardConflictMarkers() throws {
        let file = try #require(
            MergeConflictParser.parse(
                path: "src/app.ts",
                content: """
                const value = 1
                <<<<<<< HEAD
                const branch = "ours"
                =======
                const branch = "theirs"
                >>>>>>> feature
                export default value
                """
            )
        )

        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].startLine == 2)
        #expect(file.hunks[0].oursHeader == "HEAD")
        #expect(file.hunks[0].theirsHeader == "feature")
        #expect(file.hunks[0].oursLines == ["const branch = \"ours\""])
        #expect(file.hunks[0].theirsLines == ["const branch = \"theirs\""])
    }

    @Test func parsesDiff3BaseSections() throws {
        let file = try #require(
            MergeConflictParser.parse(
                path: "src/app.ts",
                content: """
                <<<<<<< HEAD
                ours
                ||||||| base
                original
                =======
                theirs
                >>>>>>> feature
                """
            )
        )

        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].baseHeader == "base")
        #expect(file.hunks[0].baseLines == ["original"])
    }

    @Test func resolvedContentUsesSelectedChoice() throws {
        let file = try #require(
            MergeConflictParser.parse(
                path: "src/app.ts",
                content: """
                before
                <<<<<<< HEAD
                ours
                =======
                theirs
                >>>>>>> feature
                after
                """
            )
        )

        #expect(
            MergeConflictParser.resolvedContent(for: file, choices: [file.hunks[0].id: .ours])
                == "before\nours\nafter"
        )
        #expect(
            MergeConflictParser.resolvedContent(for: file, choices: [file.hunks[0].id: .theirs])
                == "before\ntheirs\nafter"
        )
        #expect(
            MergeConflictParser.resolvedContent(for: file, choices: [file.hunks[0].id: .both])
                == "before\nours\ntheirs\nafter"
        )
    }
}

@MainActor
struct MergeConflictResolutionModelTests {
    @Test func requestLoadSelectsFirstFileAndHunk() async {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo/subdir")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.repositorySummary == "/tmp/repo")
        #expect(model.selectedFilePath == "src/a.ts")
        #expect(model.selectedHunk?.index == 1)
        #expect(model.selectedFileLocation?.target == "src/a.ts")
        #expect(model.selectedHunkLocation?.target == "src/a.ts:2:1")
        #expect(model.selectedEditorLocation?.target == "src/a.ts:2:1")
        #expect(model.totalUnresolvedHunks == 3)
    }

    @Test func openingSelectedLocationSurfacesUnavailableDefaultEditorLauncher() async throws {
        let repoRoot = try makeTemporaryDirectory(prefix: "merge-editor-")
        let sourceFile = repoRoot.appendingPathComponent("src/a.ts")
        try write(
            """
            before
            <<<<<<< HEAD
            ours-a
            =======
            theirs-a
            >>>>>>> feature
            after
            """,
            to: sourceFile
        )

        let file = try #require(
            MergeConflictParser.parse(
                path: "src/a.ts",
                content: """
                before
                <<<<<<< HEAD
                ours-a
                =======
                theirs-a
                >>>>>>> feature
                after
                """
            )
        )
        let snapshot = MergeConflictSnapshot(repoRoot: repoRoot.path, files: [file])
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: repoRoot.path,
            snapshot: snapshot,
            postResolveSnapshot: snapshot
        )
        var didUseWorkspaceFallback = false
        let environment = IDEEditorNavigatorEnvironment(
            defaultEditorResolver: { _ in
                repoRoot.appendingPathComponent("Visual Studio Code.app", isDirectory: true)
            },
            bundledCLIResolver: { nil },
            processRunner: { _, _ in
                IDEEditorCommandResult(terminationStatus: 0, stdout: "", stderr: "")
            },
            workspaceOpen: { _, _ in
                didUseWorkspaceFallback = true
            }
        )
        let model = MergeConflictResolutionModel(
            runner: runner,
            openInEditor: { location in
                await IDEEditorNavigator.open(location, environment: environment)
            }
        )

        model.prepareForPresentation(workingDirectory: repoRoot.path)
        model.requestLoad()
        await waitForLoad(model)

        await model.openSelectedLocationInEditor()

        #expect(model.statusMessage == "Default editor launcher is unavailable: Visual Studio Code.")
        #expect(didUseWorkspaceFallback == false)
    }

    @Test func openingSelectedLocationClearsEarlierFailureAfterSuccessfulRetry() async {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        var shouldFail = true
        let model = MergeConflictResolutionModel(
            runner: runner,
            openInEditor: { _ in
                if shouldFail {
                    return "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present."
                }
                return nil
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        await model.openSelectedLocationInEditor()
        #expect(model.statusMessage == "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present.")

        shouldFail = false
        await model.openSelectedLocationInEditor()

        #expect(model.statusMessage == nil)
    }

    @Test func staleEditorCompletionDoesNotOverwriteNewerResolutionStatus() async {
        let gate = MergeConflictAsyncGate()
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        let model = MergeConflictResolutionModel(
            runner: runner,
            openInEditor: { _ in
                await gate.signalStarted()
                await gate.wait()
                return "late editor failure"
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        let openTask = Task { @MainActor in
            await model.openSelectedLocationInEditor()
        }
        await gate.waitUntilStarted()
        model.chooseResolution(.ours)
        let newerMessage = model.statusMessage
        await gate.resume()
        await openTask.value

        #expect(newerMessage?.contains("Selected ours") == true)
        #expect(model.statusMessage == newerMessage)
    }

    @Test func chooseResolutionUpdatesPreviewAndRecordsTimelineChoice() async throws {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        let selectedHunk = try #require(model.selectedHunk)
        model.chooseResolution(.ours)

        #expect(model.resolutionChoice(for: selectedHunk) == .ours)
        #expect(model.selectedFileResolvedPreview.contains("ours-a") == true)
        await waitForChoiceRequests(runner, expectedCount: 1)
        let choiceRequests = runner.choiceRequests
        #expect(choiceRequests.count == 1)
        #expect(choiceRequests[0].path == "src/a.ts")
        #expect(choiceRequests[0].line == 2)
        #expect(choiceRequests[0].choice == .ours)
    }

    @Test func chooseResolutionQueuesTimelineAuditWithoutBlockingMainActorState() async throws {
        let auditRecorder = MergeConflictChoiceAuditRecorder(delaysByHunkIndex: [1: 0.18, 2: 0.01])
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        runner.recordChoiceHandler = { request in
            auditRecorder.record(request)
        }
        let model = MergeConflictResolutionModel(
            runner: runner,
            renderDiffPreview: { diff in
                IDEDiffRenderedPreview(text: "rendered\n\(diff)", source: .plain)
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        let firstHunk = try #require(model.selectedHunk)
        let start = ContinuousClock.now
        model.chooseResolution(.ours)
        model.selectNextHunk()
        let secondHunk = try #require(model.selectedHunk)
        model.chooseResolution(.both)
        let elapsed = start.duration(to: .now)

        #expect(elapsed < .milliseconds(100))
        #expect(model.resolutionChoice(for: firstHunk) == .ours)
        #expect(model.resolutionChoice(for: secondHunk) == .both)
        #expect(model.selectedFileResolvedPreview.contains("ours-a") == true)
        #expect(model.selectedFileResolvedPreview.contains("ours-b\ntheirs-b") == true)
        await waitForPreview(model, contains: "+theirs-b")
        #expect(model.selectedHunkDiffPreview.contains("+ours-b") == true)
        #expect(model.selectedHunkDiffPreview.contains("+theirs-b") == true)
        #expect(model.statusMessage?.contains("Selected both") == true)
        #expect(model.statusMessage?.contains("0 unresolved hunks remain") == true)

        await waitForChoiceRequests(runner, expectedCount: 2)
        let choiceRequests = runner.choiceRequests
        #expect(choiceRequests.map(\.hunkIndex) == [1, 2])
        #expect(choiceRequests.map(\.choice) == [.ours, .both])
        #expect(auditRecorder.recordedMainThreadFlags == [false, false])
    }

    @Test func chooseResolutionSurfacesLatestTimelineAuditFailure() async throws {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        runner.recordChoiceHandler = { _ in
            throw MergeConflictTestError(message: "timeline unavailable")
        }
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        let selectedHunk = try #require(model.selectedHunk)
        model.chooseResolution(.theirs)

        await waitForErrorMessage(model, contains: "timeline unavailable")
        #expect(model.errorMessage?.contains("timeline unavailable") == true)
        #expect(model.resolutionChoice(for: selectedHunk) == .theirs)
        #expect(model.selectedFileResolvedPreview.contains("theirs-a") == true)
        #expect(model.statusMessage?.contains("Selected theirs") == true)
    }

    @Test func chooseResolutionDoesNotDropEarlierAuditFailureAfterLaterChoice() async throws {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        runner.recordChoiceHandler = { request in
            if request.hunkIndex == 1 {
                Thread.sleep(forTimeInterval: 0.05)
                throw MergeConflictTestError(message: "first audit failed")
            }
        }
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.chooseResolution(.ours)
        model.selectNextHunk()
        model.chooseResolution(.both)

        await waitForErrorMessage(model, contains: "first audit failed")
        await waitForChoiceRequests(runner, expectedCount: 1)
        #expect(model.errorMessage?.contains("first audit failed") == true)
        #expect(runner.choiceRequests.map(\.hunkIndex) == [2])
        #expect(model.statusMessage?.contains("Selected both") == true)
    }

    @Test func sameRepoReloadDoesNotSuppressChoiceAuditFailure() async throws {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        runner.recordChoiceHandler = { _ in
            Thread.sleep(forTimeInterval: 0.05)
            throw MergeConflictTestError(message: "old audit failed")
        }
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.chooseResolution(.ours)
        model.requestLoad()
        await waitForLoad(model)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await Task.yield()

        #expect(model.errorMessage?.contains("old audit failed") == true)
        #expect(model.snapshot?.repoRoot == "/tmp/repo")
    }

    @Test func chooseResolutionBuildsDeltaBackedPatchPreviewForSelectedHunk() async {
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            postResolveSnapshot: makeSnapshot()
        )
        let model = MergeConflictResolutionModel(
            runner: runner,
            renderDiffPreview: { diff in
                IDEDiffRenderedPreview(text: "delta-preview\n\(diff)", source: .delta)
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.selectedHunkDiffPreview == "Choose ours, theirs, or both to preview the patch for src/a.ts:2:1.")
        #expect(model.selectedHunkDiffPreviewSource == .plain)

        model.chooseResolution(.ours)
        await waitForPreview(model, contains: "delta-preview")

        #expect(model.selectedHunkDiffPreviewSource == .delta)
        #expect(model.selectedHunkDiffPreview.contains("delta-preview"))
        #expect(model.selectedHunkDiffPreview.contains("diff --git a/src/a.ts b/src/a.ts"))
        #expect(model.selectedHunkDiffPreview.contains("+ours-a"))
        #expect(model.selectedHunkDiffPreview.contains("-<<<<<<< HEAD"))
    }

    @Test func markResolvedRequiresExplicitConfirmationBeforeApplying() async {
        let initial = makeSnapshot()
        let afterResolve = MergeConflictSnapshot(
            repoRoot: "/tmp/repo",
            files: [initial.files[1]]
        )
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: initial,
            postResolveSnapshot: afterResolve
        )
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.chooseResolution(.ours)
        model.selectNextHunk()
        model.chooseResolution(.both)

        #expect(model.canMarkSelectedFileResolved)
        model.markSelectedFileResolved()

        #expect(model.pendingResolutionConfirmation?.path == "src/a.ts")
        #expect(model.isApplying == false)
        #expect(runner.resolveRequests.isEmpty)

        model.confirmPendingResolution()
        await waitForApply(model)

        #expect(runner.resolveRequests.count == 1)
        #expect(runner.resolveRequests[0].path == "src/a.ts")
        #expect(runner.resolveRequests[0].expectedSourceContent.contains("<<<<<<< HEAD") == true)
        #expect(runner.resolveRequests[0].resolvedContent.contains("ours-a") == true)
        #expect(runner.resolveRequests[0].resolvedContent.contains("ours-b\ntheirs-b") == true)
        #expect(model.snapshot?.files.count == 1)
        #expect(model.selectedFilePath == "src/b.ts")
    }

    @Test func cancelLoadingDropsInFlightSnapshotRequest() async {
        let gate = MergeConflictAsyncGate()
        let staleSnapshot = makeSnapshot()
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: staleSnapshot,
            postResolveSnapshot: staleSnapshot
        )
        runner.loadSnapshotHandler = { _ in
            await gate.signalStarted()
            await gate.wait()
            return staleSnapshot
        }
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await gate.waitUntilStarted()

        #expect(model.isLoading)
        model.cancelLoading()
        #expect(!model.isLoading)

        await gate.resume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()

        #expect(model.snapshot == nil)
        #expect(model.errorMessage == nil)
        #expect(model.selectedFilePath == nil)
    }

    @Test func cancelApplyingDropsInFlightResolveWithoutApplyingSnapshot() async {
        let gate = MergeConflictAsyncGate()
        let initial = makeSnapshot()
        let afterResolve = MergeConflictSnapshot(
            repoRoot: "/tmp/repo",
            files: [initial.files[1]]
        )
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: initial,
            postResolveSnapshot: afterResolve
        )
        runner.markResolvedHandler = { request in
            await gate.signalStarted()
            await gate.wait()
            return MergeConflictSnapshot(repoRoot: request.repoRoot, files: [initial.files[1]])
        }
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.chooseResolution(.ours)
        model.selectNextHunk()
        model.chooseResolution(.both)
        model.markSelectedFileResolved()
        model.confirmPendingResolution()
        await gate.waitUntilStarted()

        #expect(model.isApplying)
        model.cancelApplying()
        #expect(!model.isApplying)

        await gate.resume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()

        #expect(model.snapshot?.files.count == 2)
        #expect(model.selectedFilePath == "src/a.ts")
        #expect(model.pendingResolutionConfirmation == nil)
        #expect(model.statusMessage == nil)
    }

    @Test func unsupportedFilesCannotBeMarkedResolved() async {
        let unsupported = MergeConflictSnapshot(
            repoRoot: "/tmp/repo",
            files: [
                MergeConflictFileSnapshot(
                    path: "binary.dat",
                    sections: [],
                    unsupportedReason: "Binary conflict"
                )
            ]
        )
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: unsupported,
            postResolveSnapshot: unsupported
        )
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)
        model.markSelectedFileResolved()

        #expect(model.canMarkSelectedFileResolved == false)
        #expect(model.statusMessage?.contains("outside the merge-conflict workspace") == true)
        #expect(runner.resolveRequests.isEmpty)
    }

    @Test func malformedGitPathBytesCannotAliasAValidUnicodeFilename() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-merge-invalid-path-")
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init"], cwd: root)
        let replacementCharacterPath = "bad\u{FFFD}.txt"
        try write(
            """
            <<<<<<< HEAD
            valid alias
            =======
            must not be addressed
            >>>>>>> feature
            """,
            to: root.appendingPathComponent(replacementCharacterPath)
        )
        try addUnmergedIndexEntry(
            rawPath: Data([0x62, 0x61, 0x64, 0xFF, 0x2E, 0x74, 0x78, 0x74]),
            cwd: root
        )

        let snapshot = try await MergeConflictShellClient().loadSnapshot(repoRoot: root.path)
        let file = try #require(snapshot.files.first)

        #expect(snapshot.files.count == 1)
        #expect(file.path == "Non-UTF-8 path [62 61 64 FF 2E 74 78 74]")
        #expect(file.id != replacementCharacterPath)
        #expect(file.hunks.isEmpty)
        #expect(file.unsupportedReason?.contains("cannot address it safely") == true)
    }

    @Test func unreadableConflictDoesNotHideOtherResolvableFiles() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-merge-mixed-content-")
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init"], cwd: root)
        try addUnmergedIndexEntry(rawPath: Data("binary.dat".utf8), cwd: root)
        try addUnmergedIndexEntry(rawPath: Data("good.txt".utf8), cwd: root)
        try Data([0xD8, 0x00]).write(to: root.appendingPathComponent("binary.dat"))
        try write(
            """
            <<<<<<< HEAD
            ours
            =======
            theirs
            >>>>>>> feature
            """,
            to: root.appendingPathComponent("good.txt")
        )

        let snapshot = try await MergeConflictShellClient().loadSnapshot(repoRoot: root.path)
        let binary = try #require(snapshot.files.first(where: { $0.path == "binary.dat" }))
        let good = try #require(snapshot.files.first(where: { $0.path == "good.txt" }))

        #expect(snapshot.files.count == 2)
        #expect(binary.hunks.isEmpty)
        #expect(binary.unsupportedReason?.contains("supported text") == true)
        #expect(good.hunks.count == 1)
        #expect(good.unsupportedReason == nil)
    }

    @Test func utf16ConflictIsReportedUnsupportedInsteadOfOfferedAsUnresolvable() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-merge-utf16-")
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init"], cwd: root)
        try addUnmergedIndexEntry(rawPath: Data("utf16.txt".utf8), cwd: root)
        let contents = """
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>> feature
        """
        try #require(contents.data(using: .utf16)).write(
            to: root.appendingPathComponent("utf16.txt")
        )

        let snapshot = try await MergeConflictShellClient().loadSnapshot(repoRoot: root.path)
        let file = try #require(snapshot.files.first)

        #expect(file.path == "utf16.txt")
        #expect(file.hunks.isEmpty)
        #expect(file.unsupportedReason?.contains("supported text") == true)
    }

    @Test func staleResolveErrorLeavesFileUnchangedAndSurfacesReloadMessage() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-merge-shell-")
        defer { try? FileManager.default.removeItem(at: root) }

        try runGit(["init"], cwd: root)

        let filePath = root.appendingPathComponent("src/a.ts")
        let original = """
        before
        <<<<<<< HEAD
        ours
        =======
        theirs
        >>>>>>> feature
        after
        """
        try write(original, to: filePath)

        let parsed = try #require(MergeConflictParser.parse(path: "src/a.ts", content: original))
        let client = MergeConflictShellClient()
        let request = MergeConflictResolveRequest(
            repoRoot: root.path,
            path: "src/a.ts",
            expectedSourceContent: MergeConflictParser.originalContent(for: parsed),
            resolvedContent: MergeConflictParser.resolvedContent(for: parsed, choices: [parsed.hunks[0].id: .ours]),
            remainingFiles: 0
        )

        let changed = """
        before
        <<<<<<< HEAD
        ours-edited
        =======
        theirs
        >>>>>>> feature
        after
        """
        try write(changed, to: filePath)

        do {
            _ = try await client.markResolved(request: request)
            Issue.record("Expected stale on-disk conflict rejection")
        } catch let error as MergeConflictCommandError {
            switch error {
            case .conflictedFileChangedOnDisk(let path):
                #expect(path == "src/a.ts")
            default:
                Issue.record("Unexpected merge-conflict error: \(error.localizedDescription)")
            }
        }

        #expect(try String(contentsOf: filePath, encoding: .utf8) == changed)
    }

    @Test func releaseHeldStateDropsSnapshotAndPreviewState() async throws {
        let file = try #require(
            MergeConflictParser.parse(
                path: "src/a.ts",
                content: """
                before
                <<<<<<< HEAD
                ours-a
                =======
                theirs-a
                >>>>>>> feature
                after
                """
            )
        )
        let snapshot = MergeConflictSnapshot(repoRoot: "/tmp/repo", files: [file])
        let runner = MergeConflictRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: snapshot,
            postResolveSnapshot: snapshot
        )
        let model = MergeConflictResolutionModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.snapshot != nil)
        #expect(model.selectedFilePath == "src/a.ts")

        // The workspace controller is a process-lifetime singleton; closing its window
        // must drop the retained snapshot + rendered-preview cache instead of holding a
        // repo's conflict data forever.
        model.releaseHeldState()

        #expect(model.snapshot == nil)
        #expect(model.selectedFilePath == nil)
        #expect(model.selectedHunkID == nil)
        #expect(model.statusMessage == nil)
        #expect(model.errorMessage == nil)
        #expect(model.selectedHunkDiffPreview == "Select a conflicted hunk to preview its patch.")
    }

    private func waitForLoad(_ model: MergeConflictResolutionModel) async {
        for _ in 0..<30 {
            if !model.isLoading { return }
            await Task.yield()
        }
    }

    private func waitForApply(_ model: MergeConflictResolutionModel) async {
        for _ in 0..<30 {
            if !model.isApplying { return }
            await Task.yield()
        }
    }

    private func waitForChoiceRequests(_ runner: MergeConflictRunnerStub, expectedCount: Int) async {
        for _ in 0..<60 {
            if runner.choiceRequests.count >= expectedCount { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForPreview(_ model: MergeConflictResolutionModel, contains expectedText: String) async {
        for _ in 0..<60 {
            if model.selectedHunkDiffPreview.contains(expectedText) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitForErrorMessage(_ model: MergeConflictResolutionModel, contains expectedText: String) async {
        for _ in 0..<60 {
            if model.errorMessage?.contains(expectedText) == true { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeSnapshot() -> MergeConflictSnapshot {
        let fileA = MergeConflictParser.parse(
            path: "src/a.ts",
            content: """
            before
            <<<<<<< HEAD
            ours-a
            =======
            theirs-a
            >>>>>>> feature
            middle
            <<<<<<< HEAD
            ours-b
            =======
            theirs-b
            >>>>>>> feature
            after
            """
        )!

        let fileB = MergeConflictParser.parse(
            path: "src/b.ts",
            content: """
            <<<<<<< HEAD
            left
            =======
            right
            >>>>>>> topic
            """
        )!

        return MergeConflictSnapshot(repoRoot: "/tmp/repo", files: [fileA, fileB])
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runGit(_ arguments: [String], cwd: URL) throws {
        _ = try runGitData(arguments, cwd: cwd)
    }

    private func addUnmergedIndexEntry(rawPath: Data, cwd: URL) throws {
        let blobIDs = try ["base\n", "ours\n", "theirs\n"].map { contents in
            String(
                decoding: try runGitData(
                    ["hash-object", "-w", "--stdin"],
                    cwd: cwd,
                    standardInput: Data(contents.utf8)
                ),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var indexInput = Data()
        for (stage, blobID) in blobIDs.enumerated() {
            indexInput.append(Data("100644 \(blobID) \(stage + 1)\t".utf8))
            indexInput.append(rawPath)
            indexInput.append(0)
        }
        _ = try runGitData(
            ["update-index", "-z", "--index-info"],
            cwd: cwd,
            standardInput: indexInput
        )
    }

    private func runGitData(
        _ arguments: [String],
        cwd: URL,
        standardInput: Data? = nil
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", cwd.path] + arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe = standardInput.map { _ in Pipe() }
        process.standardInput = inputPipe
        try process.run()
        if let standardInput, let inputPipe {
            try inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
            try inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            throw MergeConflictTestError(
                message: "git \(arguments.joined(separator: " ")) failed: \(String(decoding: error, as: UTF8.self))"
            )
        }
        return output
    }
}

private final class MergeConflictRunnerStub: @unchecked Sendable, MergeConflictRunning {
    let resolvedRepoRoot: String?
    var snapshot: MergeConflictSnapshot
    let postResolveSnapshot: MergeConflictSnapshot
    private let lock = NSLock()
    private var choiceRequestStorage: [MergeConflictChoiceRequest] = []
    private var resolveRequestStorage: [MergeConflictResolveRequest] = []
    var loadSnapshotHandler: (@Sendable (String) async throws -> MergeConflictSnapshot)?
    var recordChoiceHandler: (@Sendable (MergeConflictChoiceRequest) throws -> Void)?
    var markResolvedHandler: (@Sendable (MergeConflictResolveRequest) async throws -> MergeConflictSnapshot)?

    var choiceRequests: [MergeConflictChoiceRequest] {
        lock.lock()
        defer { lock.unlock() }
        return choiceRequestStorage
    }

    var resolveRequests: [MergeConflictResolveRequest] {
        lock.lock()
        defer { lock.unlock() }
        return resolveRequestStorage
    }

    init(
        resolvedRepoRoot: String?,
        snapshot: MergeConflictSnapshot,
        postResolveSnapshot: MergeConflictSnapshot
    ) {
        self.resolvedRepoRoot = resolvedRepoRoot
        self.snapshot = snapshot
        self.postResolveSnapshot = postResolveSnapshot
    }

    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String? {
        resolvedRepoRoot
    }

    // NSLock is unavailable from async contexts, so async callers lock here.
    private func appendResolveRequest(_ request: MergeConflictResolveRequest) {
        lock.lock()
        defer { lock.unlock() }
        resolveRequestStorage.append(request)
    }

    func loadSnapshot(repoRoot: String) async throws -> MergeConflictSnapshot {
        if let loadSnapshotHandler {
            return try await loadSnapshotHandler(repoRoot)
        }
        return snapshot
    }

    func recordChoice(request: MergeConflictChoiceRequest) throws {
        if let recordChoiceHandler {
            try recordChoiceHandler(request)
        }
        lock.lock()
        choiceRequestStorage.append(request)
        lock.unlock()
    }

    func markResolved(request: MergeConflictResolveRequest) async throws -> MergeConflictSnapshot {
        appendResolveRequest(request)
        if let markResolvedHandler {
            let updatedSnapshot = try await markResolvedHandler(request)
            snapshot = updatedSnapshot
            return updatedSnapshot
        }
        snapshot = postResolveSnapshot
        return postResolveSnapshot
    }
}

private struct MergeConflictTestError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

private final class MergeConflictChoiceAuditRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let delaysByHunkIndex: [Int: TimeInterval]
    private var mainThreadFlags: [Bool] = []

    init(delaysByHunkIndex: [Int: TimeInterval]) {
        self.delaysByHunkIndex = delaysByHunkIndex
    }

    var recordedMainThreadFlags: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags
    }

    func record(_ request: MergeConflictChoiceRequest) {
        let delay = delaysByHunkIndex[request.hunkIndex] ?? 0
        Thread.sleep(forTimeInterval: delay)
        lock.lock()
        mainThreadFlags.append(Thread.isMainThread)
        lock.unlock()
    }
}

private actor MergeConflictAsyncGate {
    private var hasStarted = false
    private var isOpen = false
    private var waitContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func signalStarted() {
        hasStarted = true
        let continuations = startContinuations
        startContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func waitUntilStarted() async {
        if hasStarted {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
        }
    }

    func resume() {
        isOpen = true
        let continuation = waitContinuation
        waitContinuation = nil
        continuation?.resume()
    }
}
