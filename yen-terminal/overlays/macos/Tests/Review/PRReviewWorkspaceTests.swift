import Testing
@testable import YEN

struct PullRequestReviewDiffParserTests {
    @Test func focusedDiffLookupUsesNamedFileListOrder() {
        let diff = """
        diff --git a/src/a.ts b/src/a.ts
        --- a/src/a.ts
        +++ b/src/a.ts
        @@ -1 +1 @@
        -old
        +new
        diff --git a/src/b.ts b/src/b.ts
        --- a/src/b.ts
        +++ b/src/b.ts
        @@ -3 +3 @@
        -before
        +after
        """

        let blocks = PullRequestReviewDiffParser.parse(diff)

        #expect(blocks.count == 2)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "src/a.ts", from: blocks)?.contains("+new") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "src/b.ts", from: blocks)?.contains("+after") == true)
    }

    @Test func renameDiffTracksOldAndNewPaths() {
        let diff = """
        diff --git a/old-name.swift b/new-name.swift
        similarity index 97%
        rename from old-name.swift
        rename to new-name.swift
        --- a/old-name.swift
        +++ b/new-name.swift
        @@ -1 +1 @@
        -old
        +new
        """

        let blocks = PullRequestReviewDiffParser.parse(diff)
        let index = PullRequestReviewDiffParser.index(from: blocks)

        #expect(blocks.count == 1)
        #expect(index.paths == ["new-name.swift"])
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "new-name.swift", from: blocks)?.contains("rename to new-name.swift") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "old-name.swift", from: blocks)?.contains("rename from old-name.swift") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "old-name.swift", from: index)?.contains("rename from old-name.swift") == true)
    }

    @Test func nonHunkDiffBlocksStayAddressableByChangedFilePath() {
        let diff = """
        diff --git a/assets/icon.png b/assets/icon.png
        new file mode 100644
        index 0000000..abc1234
        Binary files /dev/null and b/assets/icon.png differ
        diff --git a/docs/old.md b/docs/new.md
        similarity index 100%
        rename from docs/old.md
        rename to docs/new.md
        diff --git a/src/deleted.ts b/src/deleted.ts
        deleted file mode 100644
        index e69de29..0000000
        --- a/src/deleted.ts
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -old
        -gone
        diff --git a/scripts/run.sh b/scripts/run.sh
        old mode 100644
        new mode 100755
        """

        let blocks = PullRequestReviewDiffParser.parse(diff)

        #expect(blocks.count == 4)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "assets/icon.png", from: blocks)?.contains("Binary files") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "docs/new.md", from: blocks)?.contains("rename to docs/new.md") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "docs/old.md", from: blocks)?.contains("rename from docs/old.md") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "src/deleted.ts", from: blocks)?.contains("deleted file mode") == true)
        #expect(PullRequestReviewDiffParser.focusedDiff(for: "scripts/run.sh", from: blocks)?.contains("new mode 100755") == true)

        #expect(
            PullRequestReviewDiffParser.hunks(
                for: "assets/icon.png",
                repoRoot: "/tmp/repo",
                from: blocks
            ).isEmpty
        )
        #expect(
            PullRequestReviewDiffParser.hunks(
                for: "docs/new.md",
                repoRoot: "/tmp/repo",
                from: blocks
            ).isEmpty
        )
        #expect(
            PullRequestReviewDiffParser.hunks(
                for: "scripts/run.sh",
                repoRoot: "/tmp/repo",
                from: blocks
            ).isEmpty
        )

        let deleteHunks = PullRequestReviewDiffParser.hunks(
            for: "src/deleted.ts",
            repoRoot: "/tmp/repo",
            from: blocks
        )
        #expect(deleteHunks.count == 1)
        #expect(deleteHunks[0].location.target == "src/deleted.ts:1:1")
        #expect(deleteHunks[0].commentSide == .left)
    }

    @Test func diffIndexKeepsModeOnlyPathWithSpacesFromHeader() {
        let diff = """
        diff --git a/scripts dir/run file.sh b/scripts dir/run file.sh
        old mode 100644
        new mode 100755
        """

        let index = PullRequestReviewDiffParser.index(diff)

        #expect(index.paths == ["scripts dir/run file.sh"])
        #expect(
            PullRequestReviewDiffParser.focusedDiff(
                for: "scripts dir/run file.sh",
                from: index
            )?.contains("new mode 100755") == true
        )
        #expect(
            PullRequestReviewDiffParser.hunks(
                for: "scripts dir/run file.sh",
                repoRoot: "/tmp/repo",
                from: index
            ).isEmpty
        )
    }

    @Test func quotedDiffPathsNormalizeGitEscapes() {
        let diff = """
        diff --git "a/quote dir/file\\"name.txt" "b/quote dir/file\\"name.txt"
        index 5626abf..814f4a4 100644
        --- "a/quote dir/file\\"name.txt"\t
        +++ "b/quote dir/file\\"name.txt"\t
        @@ -1 +1,2 @@
         one
        +two
        diff --git "a/tabdir/file\\tname.txt" "b/tabdir/file\\tname.txt"
        old mode 100644
        new mode 100755
        diff --git "a/unicode/caf\\303\\251.txt" "b/unicode/caf\\303\\251.txt"
        old mode 100644
        new mode 100755
        """

        let index = PullRequestReviewDiffParser.index(diff)

        #expect(index.paths == [
            "quote dir/file\"name.txt",
            "tabdir/file\tname.txt",
            "unicode/caf\u{e9}.txt",
        ])
        #expect(
            PullRequestReviewDiffParser.focusedDiff(
                for: "quote dir/file\"name.txt",
                from: index
            )?.contains("+two") == true
        )
        #expect(
            PullRequestReviewDiffParser.focusedDiff(
                for: "tabdir/file\tname.txt",
                from: index
            )?.contains("new mode 100755") == true
        )
        #expect(
            PullRequestReviewDiffParser.focusedDiff(
                for: "unicode/caf\u{e9}.txt",
                from: index
            )?.contains("new mode 100755") == true
        )
    }

    @Test func prefixedSourceLinesDoNotReplaceFilePathsOrHunkTargets() {
        let diff = """
        diff --git a/docs/list.md b/docs/list.md
        --- a/docs/list.md
        +++ b/docs/list.md
        @@ -10,4 +10,4 @@
         context 10
         context 11
        --- old item
        +++ new item
         context 13
        """

        let blocks = PullRequestReviewDiffParser.parse(diff)
        let index = PullRequestReviewDiffParser.index(from: blocks)
        let hunks = PullRequestReviewDiffParser.hunks(
            for: "docs/list.md",
            repoRoot: "/tmp/repo",
            from: index
        )

        #expect(blocks.map(\.keys) == [["docs/list.md"]])
        #expect(index.paths == ["docs/list.md"])
        #expect(index.focusedDiff(for: "docs/list.md")?.contains("+++ new item") == true)
        #expect(hunks.count == 1)
        #expect(hunks.first?.location.target == "docs/list.md:12:1")
        #expect(hunks.first?.commentLine == 12)
        #expect(hunks.first?.commentSide == .right)
    }

    @Test func deletionOnlyHunkTargetsTheChangedLineAfterLeadingContext() {
        let diff = """
        diff --git a/docs/list.md b/docs/list.md
        --- a/docs/list.md
        +++ b/docs/list.md
        @@ -20,5 +20,4 @@
         context 20
         context 21
         context 22
        -deleted item
         context 24
        """

        let hunks = PullRequestReviewDiffParser.hunks(
            for: "docs/list.md",
            repoRoot: "/tmp/repo",
            diff: diff
        )

        #expect(hunks.count == 1)
        #expect(hunks.first?.location.target == "docs/list.md:23:1")
        #expect(hunks.first?.commentLine == 23)
        #expect(hunks.first?.commentSide == .left)
    }

    @Test func deletionAtEndOfHunkKeepsItsLeftSideCoordinate() {
        let diff = """
        diff --git a/docs/list.md b/docs/list.md
        --- a/docs/list.md
        +++ b/docs/list.md
        @@ -9,3 +9,2 @@
         context 9
         context 10
        -deleted last line
        """

        let hunks = PullRequestReviewDiffParser.hunks(
            for: "docs/list.md",
            repoRoot: "/tmp/repo",
            diff: diff
        )

        #expect(hunks.count == 1)
        #expect(hunks.first?.location.target == "docs/list.md:10:1")
        #expect(hunks.first?.commentLine == 11)
        #expect(hunks.first?.commentSide == .left)
    }

    @Test func hunkParsingAnchorsSemanticTargetsToFirstChangedLine() {
        let diff = """
        diff --git a/src/a.ts b/src/a.ts
        --- a/src/a.ts
        +++ b/src/a.ts
        @@ -1,4 +1,4 @@
        -oldTop
        +newTop
         line 2
         line 3
         line 4
        @@ -9,7 +9,7 @@ line 8
         line 9
         line 10
         line 11
        -line 12
        +line 12 updated
         line 13
         line 14
         line 15
        """

        let hunks = PullRequestReviewDiffParser.hunks(
            for: "src/a.ts",
            repoRoot: "/tmp/repo",
            diff: diff
        )

        #expect(hunks.count == 2)
        #expect(hunks[0].location.target == "src/a.ts:1:1")
        #expect(hunks[1].location.target == "src/a.ts:12:1")
        #expect(hunks[1].diff.contains("+line 12 updated"))
        #expect(hunks[1].diff.contains("+newTop") == false)
    }
}

@Suite(.serialized)
@MainActor
struct PullRequestReviewModelTests {
    @Test func requestLoadSelectsFirstFileAndSupportsAdjacentNavigation() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo/subdir")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.repositorySummary == "/tmp/repo")
        #expect(model.selectedFilePath == "src/a.ts")
        #expect(model.selectedFileLocation?.target == "src/a.ts")
        #expect(model.inlineDraftPath == "src/a.ts")
        #expect(model.focusedDiff == "diff-a")

        model.selectNextFile()
        #expect(model.selectedFilePath == "src/b.ts")
        #expect(model.focusedDiff == "diff-b")

        model.selectPreviousFile()
        #expect(model.selectedFilePath == "src/a.ts")
    }

    @Test func requestLoadSelectsFirstHunkAndCarriesTargetIntoInlineDrafts() async {
        let hunkedFile = makeHunkedFile(path: "src/a.ts", line: 12)
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [hunkedFile]),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.selectedFilePath == "src/a.ts")
        #expect(model.selectedHunk?.location.target == "src/a.ts:12:1")
        #expect(model.selectedReviewLocation?.target == "src/a.ts:12:1")
        #expect(model.focusedDiff.contains("line 12 updated"))

        model.useSelectedTargetForInlineDraft()
        #expect(model.inlineDraftPath == "src/a.ts")
        #expect(model.inlineDraftLine == "12")
        #expect(model.inlineDraftSide == .right)
    }

    @Test func selectedDeletedFileHunkPrefillsLeftSideInlineTarget() async {
        let hunk = PullRequestReviewDiffHunk(
            id: "src/deleted.ts#1",
            index: 1,
            header: "@@ -1,2 +0,0 @@",
            location: .repositoryLocation(
                repoRoot: "/tmp/repo",
                relativePath: "src/deleted.ts",
                line: 1,
                column: 1
            ),
            commentSide: .left,
            diff: "@@ -1,2 +0,0 @@\n-old\n-gone"
        )
        let file = PullRequestReviewFile(
            path: "src/deleted.ts",
            diff: hunk.diff,
            hunks: [hunk]
        )
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [file]),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)
        model.useSelectedTargetForInlineDraft()

        #expect(model.inlineDraftPath == "src/deleted.ts")
        #expect(model.inlineDraftLine == "1")
        #expect(model.inlineDraftSide == .left)
    }

    @Test func focusedDiffUsesRawFileAndHunkText() async {
        let rawHunkDiff = """
        diff --git a/src/a.ts b/src/a.ts
        --- a/src/a.ts
        +++ b/src/a.ts
        @@ -12 +12 @@
        -old line
        +new line
        """
        let hunk = PullRequestReviewDiffHunk(
            id: "src/a.ts#1",
            index: 1,
            header: "@@ -12 +12 @@",
            location: .repositoryLocation(repoRoot: "/tmp/repo", relativePath: "src/a.ts", line: 12, column: 1),
            diff: rawHunkDiff
        )
        let rawFileDiff = "diff --git a/src/a.ts b/src/a.ts\n-file old\n+file new"
        let rawSecondFileDiff = "diff --git a/src/b.ts b/src/b.ts\n-old\n+new"
        let files = [
            PullRequestReviewFile(
                path: "src/a.ts",
                diff: rawFileDiff,
                hunks: [hunk]
            ),
            PullRequestReviewFile(
                path: "src/b.ts",
                diff: rawSecondFileDiff
            ),
        ]
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: files),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.focusedDiff == rawHunkDiff)

        model.selectNextFile()
        #expect(model.focusedDiff == rawSecondFileDiff)
    }

    @Test func openingSelectedReviewLocationSurfacesStaleHunkTargets() async {
        let hunkedFile = makeHunkedFile(path: "src/a.ts", line: 12)
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [hunkedFile]),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        await model.openSelectedReviewLocationInEditor()

        #expect(model.stagingMessage == "Editor target no longer exists: src/a.ts:12:1")
    }

    @Test func openingSelectedReviewLocationClearsEarlierFailureAfterSuccessfulRetry() async {
        let hunkedFile = makeHunkedFile(path: "src/a.ts", line: 12)
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [hunkedFile]),
            evidenceContext: .empty
        )
        var shouldFail = true
        let model = PullRequestReviewModel(
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

        await model.openSelectedReviewLocationInEditor()
        #expect(model.stagingMessage == "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present.")

        shouldFail = false
        await model.openSelectedReviewLocationInEditor()

        #expect(model.stagingMessage == nil)
    }

    @Test func staleEditorCompletionDoesNotOverwriteNewerStagingStatus() async {
        let gate = PullRequestReviewAsyncGate()
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [makeHunkedFile(path: "src/a.ts", line: 12)]),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(
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
            await model.openSelectedReviewLocationInEditor()
        }
        await gate.waitUntilStarted()
        model.stageEvidenceDraft()
        let newerMessage = model.stagingMessage
        await gate.resume()
        await openTask.value

        #expect(newerMessage?.contains("Staged local evidence") == true)
        #expect(model.stagingMessage == newerMessage)
    }

    @Test func openingInlineDraftLocationSurfacesInjectedEditorFailures() async {
        let snapshot = PullRequestReviewSnapshot(
            repoRoot: "/tmp/repo",
            summary: PullRequestReviewSummary(
                number: 42,
                title: "Add review window",
                url: "https://example.com/pr/42",
                author: "eight",
                baseRefName: "main",
                headRefName: "feature/review",
                headRefOID: "abc123def456",
                changedFiles: 1,
                additions: 1,
                deletions: 0
            ),
            files: [PullRequestReviewFile(path: "src/a.ts", diff: "diff-a")]
        )
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: snapshot,
            evidenceContext: .empty
        )
        var capturedLocation: IDESemanticLocation?
        let model = PullRequestReviewModel(
            runner: runner,
            openInEditor: { location in
                capturedLocation = location
                return "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present."
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)
        model.inlineDraftPath = "src/a.ts"
        model.inlineDraftLine = "4"

        await model.openCurrentInlineDraftLocationInEditor()

        #expect(capturedLocation?.target == "src/a.ts:4:1")
        #expect(capturedLocation?.path == "/tmp/repo/src/a.ts")
        #expect(model.stagingMessage == "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present.")
    }

    @Test func openingInlineDraftLocationPassesResolvedTargetToInjectedEditorBridge() async {
        let snapshot = PullRequestReviewSnapshot(
            repoRoot: "/tmp/repo",
            summary: PullRequestReviewSummary(
                number: 42,
                title: "Add review window",
                url: "https://example.com/pr/42",
                author: "eight",
                baseRefName: "main",
                headRefName: "feature/review",
                headRefOID: "abc123def456",
                changedFiles: 1,
                additions: 1,
                deletions: 0
            ),
            files: [PullRequestReviewFile(path: "src/a.ts", diff: "diff-a")]
        )
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: snapshot,
            evidenceContext: .empty
        )
        var capturedLocation: IDESemanticLocation?
        let model = PullRequestReviewModel(
            runner: runner,
            openInEditor: { location in
                capturedLocation = location
                return nil
            }
        )

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)
        model.inlineDraftPath = "src/a.ts"
        model.inlineDraftLine = "4"

        await model.openCurrentInlineDraftLocationInEditor()

        #expect(model.stagingMessage == nil)
        #expect(capturedLocation?.target == "src/a.ts:4:1")
        #expect(capturedLocation?.path == "/tmp/repo/src/a.ts")
    }

    @Test func openingInlineDraftLocationClearsEarlierFailureAfterSuccessfulRetry() async {
        let snapshot = PullRequestReviewSnapshot(
            repoRoot: "/tmp/repo",
            summary: PullRequestReviewSummary(
                number: 42,
                title: "Add review window",
                url: "https://example.com/pr/42",
                author: "eight",
                baseRefName: "main",
                headRefName: "feature/review",
                headRefOID: "abc123def456",
                changedFiles: 1,
                additions: 1,
                deletions: 0
            ),
            files: [PullRequestReviewFile(path: "src/a.ts", diff: "diff-a")]
        )
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: snapshot,
            evidenceContext: .empty
        )
        var shouldFail = true
        let model = PullRequestReviewModel(
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
        model.inlineDraftPath = "src/a.ts"
        model.inlineDraftLine = "4"

        await model.openCurrentInlineDraftLocationInEditor()
        #expect(model.stagingMessage == "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present.")

        shouldFail = false
        await model.openCurrentInlineDraftLocationInEditor()

        #expect(model.stagingMessage == nil)
    }

    @Test func requestLoadSurfacesHelpfulRepositoryErrors() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: nil,
            snapshot: nil,
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/not-a-repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.snapshot == nil)
        #expect(model.loadErrorMessage == PullRequestReviewCommandError.notInGitRepository.errorDescription)
    }

    @Test func prepareForPresentationCancelsInFlightLoadForPreviousWorkingDirectory() async {
        let gate = PullRequestReviewAsyncGate()
        let staleSnapshot = makeSnapshot(files: [PullRequestReviewFile(path: "src/stale.ts", diff: "diff-stale")])
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo-a",
            snapshot: staleSnapshot,
            evidenceContext: .empty
        )
        runner.loadPullRequestHandler = { _, _ in
            await gate.signalStarted()
            await gate.wait()
            return staleSnapshot
        }
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo-a")
        model.requestLoad()
        await gate.waitUntilStarted()

        model.prepareForPresentation(workingDirectory: "/tmp/repo-b")
        await gate.resume()

        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()

        #expect(model.workingDirectorySummary == "/tmp/repo-b")
        #expect(model.snapshot == nil)
        #expect(model.repositorySummary == nil)
        #expect(model.isLoading == false)
        #expect(model.selectedFilePath == nil)
    }

    @Test func cancelLoadingDropsInFlightRequestWithoutApplyingSnapshot() async {
        let gate = PullRequestReviewAsyncGate()
        let staleSnapshot = makeSnapshot(files: [PullRequestReviewFile(path: "src/stale.ts", diff: "diff-stale")])
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: staleSnapshot,
            evidenceContext: .empty
        )
        runner.loadPullRequestHandler = { _, _ in
            await gate.signalStarted()
            await gate.wait()
            return staleSnapshot
        }
        let model = PullRequestReviewModel(runner: runner)

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
        #expect(model.loadErrorMessage == nil)
        #expect(model.selectedFilePath == nil)
    }

    @Test func cancelSubmissionDropsInFlightReviewActionWithoutApplyingResult() async {
        let gate = PullRequestReviewAsyncGate()
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        runner.submitHandler = { request in
            await gate.signalStarted()
            await gate.wait()
            return PullRequestReviewSubmissionResult(
                kind: request.kind,
                postedInlineDraftIDs: [],
                didPostEvidenceComment: false,
                didConsumeStagedEvidenceDraft: false,
                evidenceFilePath: nil,
                decisionFilePath: nil
            )
        }
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.reviewNote = "Keep this draft if submission is cancelled."
        model.requestSubmission(.decision(.comment))
        model.confirmSubmission(.decision(.comment))
        await gate.waitUntilStarted()

        #expect(model.isSubmitting)
        model.cancelSubmission()
        #expect(!model.isSubmitting)
        #expect(model.pendingSubmissionConfirmation == nil)

        await gate.resume()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await Task.yield()

        #expect(model.reviewNote == "Keep this draft if submission is cancelled.")
        #expect(model.submissionErrorMessage == nil)
        #expect(model.stagingMessage == nil)
    }

    @Test func stageCurrentInlineDraftUsesCLICompatiblePreview() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "42"
        model.inlineDraftBody = "Needs guard"

        #expect(model.canStageInlineDraft)
        model.stageCurrentInlineDraft()

        #expect(model.stagedDrafts.count == 1)
        guard case .inline(let draft) = model.stagedDrafts[0] else {
            Issue.record("Expected a staged inline draft")
            return
        }

        #expect(draft.path == "src/a.ts")
        #expect(draft.line == 42)
        #expect(draft.location.target == "src/a.ts:42:1")
        #expect(draft.side == .right)
        #expect(draft.body == "Needs guard")
        #expect(draft.preview.contains("Inline review comment for PR #42"))
        #expect(draft.preview.contains("- File: src/a.ts"))
        #expect(draft.preview.contains("- Line: 42"))
        #expect(draft.preview.contains("- Location: src/a.ts:42:1"))
        #expect(model.inlineDraftLine.isEmpty)
        #expect(model.inlineDraftBody.isEmpty)
        #expect(model.inlineDraftPath == "src/a.ts")
    }

    @Test func inlineCommentArgumentsPostReviewerBodyOnly() {
        let summary = PullRequestReviewSummary(
            number: 42,
            title: "Fix verification parity",
            url: "https://github.com/yenchat/yen/pull/42",
            author: "octocat",
            baseRefName: "main",
            headRefName: "feature/review",
            headRefOID: "deadbeef",
            changedFiles: 1,
            additions: 5,
            deletions: 1
        )
        let draft = PullRequestReviewInlineCommentDraft(
            id: "inline-1",
            path: "src/a.ts",
            line: 42,
            side: .right,
            body: "Needs guard",
            suggestedFileName: "pr-42-inline.md",
            preview: """
            Inline review comment for PR #42

            - File: src/a.ts
            - Line: 42
            - Side: RIGHT
            - URL: https://github.com/yenchat/yen/pull/42

            Needs guard
            """
        )

        let arguments = PullRequestReviewShellClient.inlineCommentArguments(
            repoSlug: "yenchat/yen",
            summary: summary,
            draft: draft
        )

        #expect(arguments.contains("body=Needs guard"))
        #expect(arguments.contains(where: { $0.contains("Inline review comment for PR #42") }) == false)
    }

    @Test func stageEvidenceDraftMirrorsEvidenceBundleShapeAndReplacesExistingBundle() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: PullRequestReviewEvidenceContext(
                ideStateDirectory: "/tmp/ide",
                latestVerifySummaryPath: "/tmp/ide/verify/latest.tsv",
                latestVerifySummaryContents: "step\tstatus\nbuild\tok",
                latestVerifySemanticPath: "/tmp/ide/verify/latest.semantic.tsv",
                latestVerifySemanticContents: "found\tpath\tline\tcol\tabsolute_path\tlocation\n1\tsrc/a.ts\t42\t1\t/tmp/repo/src/a.ts\tsrc/a.ts:42:1",
                latestVerifyStatus: PullRequestReviewVerifyStatusSnapshot(
                    latestStatus: "failing",
                    lastRunAt: "2026-03-07T09:00:00Z",
                    summaryReportPath: "/tmp/ide/verify/latest.tsv",
                    detailsReportPath: "/tmp/ide/verify/latest.log",
                    semanticReportPath: "/tmp/ide/verify/latest.semantic.tsv",
                    readinessStatus: "blocked",
                    readinessReason: "Latest local verify run has failures.",
                    mergeReady: false,
                    securityStatus: "warning",
                    securityReason: "Latest local security checks contain warnings or missing tools.",
                    securityStepCount: 2,
                    securityWarningSteps: 2,
                    securityFailingSteps: 0,
                    securitySteps: [
                        PullRequestReviewVerifySecurityStep(
                            id: "node-audit",
                            result: "warn",
                            exitCode: 1,
                            summary: "1 high severity vulnerability"
                        ),
                        PullRequestReviewVerifySecurityStep(
                            id: "osv-scanner",
                            result: "warn",
                            exitCode: 1,
                            summary: "1 vulnerability group(s) across 1 package(s) from 1 source(s)"
                        ),
                    ]
                ),
                recentTimelineEvents: [
                    "2026-03-07T09:00:00Z\tverify\t/tmp/repo\tfailures=0;warns=0\tsummary=/tmp/ide/verify/latest.tsv;semantic=/tmp/ide/verify/latest.semantic.tsv",
                    "2026-03-07T09:01:00Z\tpr-review\t/tmp/repo\tpr=42\tfile=src/a.ts",
                ]
            )
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.stageEvidenceDraft()

        #expect(model.stagedDrafts.count == 1)
        guard case .evidence(let draft) = model.stagedDrafts[0] else {
            Issue.record("Expected a staged evidence draft")
            return
        }

        #expect(draft.preview.contains("# YEN IDE PR Review Evidence"))
        #expect(draft.preview.contains("- PR: #42"))
        #expect(draft.preview.contains("- Focus file: src/a.ts"))
        #expect(draft.preview.contains("- Focus target: src/a.ts"))
        #expect(draft.preview.contains("## Latest Verify Readiness + Security Snapshot"))
        #expect(draft.preview.contains("- Security: warning"))
        #expect(draft.preview.contains("- Security step: node-audit | result=warn | exit=1 | 1 high severity vulnerability"))
        #expect(draft.preview.contains("## Latest Verify Summary Path"))
        #expect(draft.preview.contains("/tmp/ide/verify/latest.tsv"))
        #expect(draft.preview.contains("## Latest Verify Semantic Report Path"))
        #expect(draft.preview.contains("/tmp/ide/verify/latest.semantic.tsv"))
        #expect(draft.preview.contains("src/a.ts:42:1"))
        #expect(draft.preview.contains("```tsv"))
        #expect(draft.preview.contains("build\tok"))
        #expect(draft.preview.contains("## Recent IDE Timeline Events"))

        model.stageEvidenceDraft()
        #expect(model.stagedDrafts.count == 1)
    }

    @Test func reloadingSamePullRequestKeepsLocalDrafts() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "12"
        model.inlineDraftBody = "Carry this draft"
        model.stageCurrentInlineDraft()

        model.requestLoad()
        await waitForLoad(model)

        #expect(model.stagedDrafts.count == 1)
        guard case .inline(let draft) = model.stagedDrafts[0] else {
            Issue.record("Expected staged inline draft to persist")
            return
        }

        #expect(draft.body == "Carry this draft")
    }

    @Test func changingFocusedFileDoesNotRetargetNonEmptyInlineDraft() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.inlineDraftPath == "src/a.ts")

        model.inlineDraftLine = "18"
        model.inlineDraftBody = "Keep this draft pinned to the original file."
        model.selectedFilePath = "src/b.ts"

        #expect(model.inlineDraftPath == "src/a.ts")
        #expect(model.canStageInlineDraft)

        model.clearStagedDrafts()
        #expect(model.inlineDraftPath == "src/b.ts")
        #expect(model.inlineDraftLine.isEmpty)
        #expect(model.inlineDraftBody.isEmpty)
    }

    @Test func loadingDifferentPullRequestClearsLocalDrafts() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: .empty
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "24"
        model.inlineDraftBody = "Old PR note"
        model.stageCurrentInlineDraft()
        model.stageEvidenceDraft()
        #expect(model.stagedDrafts.count == 2)

        runner.snapshot = makeSnapshot(
            number: 43,
            title: "Different PR",
            files: [PullRequestReviewFile(path: "src/next.ts", diff: "diff-next")]
        )
        model.prReference = "43"
        model.requestLoad()
        await waitForLoad(model)

        #expect(model.snapshot?.summary.number == 43)
        #expect(model.stagedDrafts.isEmpty)
        #expect(model.inlineDraftPath == "src/next.ts")
        #expect(model.inlineDraftLine.isEmpty)
        #expect(model.inlineDraftBody.isEmpty)
    }

    @Test func submitInlineCommentsPostsOnlyInlineDraftsAndLeavesEvidenceStaged() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: PullRequestReviewEvidenceContext(
                ideStateDirectory: "/tmp/ide",
                latestVerifySummaryPath: nil,
                latestVerifySummaryContents: nil,
                latestVerifySemanticPath: nil,
                latestVerifySemanticContents: nil,
                recentTimelineEvents: []
            )
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "12"
        model.inlineDraftBody = "First inline note"
        model.stageCurrentInlineDraft()
        model.inlineDraftLine = "28"
        model.inlineDraftBody = "Second inline note"
        model.stageCurrentInlineDraft()
        model.stageEvidenceDraft()

        model.submit(.inlineComments)
        await waitForSubmission(model)

        #expect(runner.submittedRequests.count == 1)
        #expect(runner.submittedRequests[0].stagedInlineDrafts.count == 2)
        #expect(runner.submittedRequests[0].kind == .inlineComments)
        #expect(runner.submittedRequests[0].selectedFocusLocation?.target == "src/a.ts")
        #expect(model.stagedDrafts.count == 1)
        guard case .evidence = model.stagedDrafts[0] else {
            Issue.record("Expected the staged evidence draft to remain after posting inline comments.")
            return
        }
        #expect(model.stagingMessage?.contains("Posted 2 inline comments") == true)
    }

    @Test func decisionDraftPreviewAndSubmissionReuseCLIShape() async {
        let hunkedFile = makeHunkedFile(path: "src/a.ts", line: 41)
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(files: [hunkedFile]),
            evidenceContext: PullRequestReviewEvidenceContext(
                ideStateDirectory: "/tmp/ide",
                latestVerifySummaryPath: "/tmp/ide/verify/latest.tsv",
                latestVerifySummaryContents: "step\tstatus\nbuild\tok",
                latestVerifySemanticPath: "/tmp/ide/verify/latest.semantic.tsv",
                latestVerifySemanticContents: "found\tpath\tline\tcol\tabsolute_path\tlocation\n1\tsrc/a.ts\t41\t1\t/tmp/repo/src/a.ts\tsrc/a.ts:41:1",
                recentTimelineEvents: []
            )
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "41"
        model.inlineDraftBody = "Post with the decision"
        model.stageCurrentInlineDraft()
        model.stageEvidenceDraft()
        model.selectedDecisionMode = .requestChanges
        model.reviewNote = "Blocking on the missing tests."

        let preview = model.currentDecisionDraft?.preview ?? ""
        #expect(preview.contains("[Request Changes] PR #42: Add review window"))
        #expect(preview.contains("- Focus file: src/a.ts"))
        #expect(preview.contains("- Focus target: src/a.ts:41:1"))
        #expect(preview.contains("- Evidence bundle: /tmp/ide/evidence/"))
        #expect(preview.contains("Blocking on the missing tests."))
        #expect(preview.contains("PR: https://example.com/pr/42"))

        model.submit(.decision(.requestChanges))
        await waitForSubmission(model)

        #expect(runner.submittedRequests.count == 1)
        #expect(runner.submittedRequests[0].kind == .decision(.requestChanges))
        #expect(runner.submittedRequests[0].selectedFocusLocation?.target == "src/a.ts:41:1")
        #expect(runner.submittedRequests[0].reviewNote == "Blocking on the missing tests.")
        #expect(model.stagedDrafts.isEmpty)
        #expect(model.reviewNote.isEmpty)
        #expect(model.stagingMessage?.contains("Submitted request-changes review for PR #42") == true)
    }

    @Test func partialSubmissionErrorsRemoveAlreadyPostedInlineDraftsOnly() async {
        let runner = PullRequestReviewRunnerStub(
            resolvedRepoRoot: "/tmp/repo",
            snapshot: makeSnapshot(),
            evidenceContext: PullRequestReviewEvidenceContext(
                ideStateDirectory: "/tmp/ide",
                latestVerifySummaryPath: nil,
                latestVerifySummaryContents: nil,
                latestVerifySemanticPath: nil,
                latestVerifySemanticContents: nil,
                recentTimelineEvents: []
            )
        )
        let model = PullRequestReviewModel(runner: runner)

        model.prepareForPresentation(workingDirectory: "/tmp/repo")
        model.requestLoad()
        await waitForLoad(model)

        model.inlineDraftLine = "5"
        model.inlineDraftBody = "Already posted before failure"
        model.stageCurrentInlineDraft()
        model.inlineDraftLine = "18"
        model.inlineDraftBody = "Still pending after failure"
        model.stageCurrentInlineDraft()
        model.stageEvidenceDraft()
        model.reviewNote = "Keep this note for retry."

        let firstPostedDraftID = model.stagedInlineDrafts.last?.id ?? ""
        runner.submissionError = PullRequestReviewSubmissionError(
            message: "Unable to submit the review summary.",
            partialResult: PullRequestReviewSubmissionResult(
                kind: .decision(.comment),
                postedInlineDraftIDs: [firstPostedDraftID],
                didPostEvidenceComment: false,
                didConsumeStagedEvidenceDraft: false,
                evidenceFilePath: nil,
                decisionFilePath: nil
            )
        )

        model.submit(.decision(.comment))
        await waitForSubmission(model)

        #expect(model.submissionErrorMessage == "Unable to submit the review summary.")
        #expect(model.reviewNote == "Keep this note for retry.")
        #expect(model.stagedInlineDrafts.count == 1)
        #expect(model.stagedDrafts.count == 2)
        #expect(model.stagingMessage?.contains("Posted 1 inline comment") == true)
    }

    @Test func shellClientDerivesChangedFilesFromDiffBlocksWithoutNameOnly() async throws {
        let diff = Self.edgeCasePullRequestDiff

        try await withFakeGitHubCLI(diff: diff) { repoRoot, logURL in
            let snapshot = try await PullRequestReviewShellClient()
                .loadPullRequest(requestedPR: nil, repoRoot: repoRoot.path)
            let commandLog = try String(contentsOf: logURL, encoding: .utf8)

            #expect(snapshot.files.map(\.path) == [
                "assets/icon.png",
                "docs/new.md",
                "src/deleted.ts",
                "scripts/run.sh",
            ])
            #expect(!commandLog.contains("--name-only"))
            guard snapshot.files.count == 4 else { return }
            #expect(snapshot.files[0].diff.contains("Binary files"))
            #expect(snapshot.files[0].hunks.isEmpty)
            #expect(snapshot.files[1].diff.contains("rename to docs/new.md"))
            #expect(snapshot.files[1].hunks.isEmpty)
            #expect(snapshot.files[2].diff.contains("deleted file mode"))
            #expect(snapshot.files[2].hunks.map(\.location.target) == ["src/deleted.ts:1:1"])
            #expect(snapshot.files[3].diff.contains("new mode 100755"))
            #expect(snapshot.files[3].hunks.isEmpty)
        }
    }

    @Test func shellClientKeepsPrefixedSourceLinesUnderTheirRealFile() async throws {
        let diff = """
        diff --git a/docs/list.md b/docs/list.md
        --- a/docs/list.md
        +++ b/docs/list.md
        @@ -10,4 +10,4 @@
         context 10
         context 11
        --- old item
        +++ new item
         context 13
        """
        let metadata = """
        {
          "number": 42,
          "title": "Update a list",
          "url": "https://github.com/yenchat/yen/pull/42",
          "author": { "login": "eight" },
          "baseRefName": "main",
          "headRefName": "feature/list",
          "headRefOid": "abc123def456",
          "changedFiles": 1,
          "additions": 1,
          "deletions": 1
        }
        """

        try await withFakeGitHubCLI(metadata: metadata, diff: diff) { repoRoot, _ in
            let snapshot = try await PullRequestReviewShellClient()
                .loadPullRequest(requestedPR: nil, repoRoot: repoRoot.path)

            #expect(snapshot.files.map(\.path) == ["docs/list.md"])
            #expect(snapshot.files.first?.diff.contains("+++ new item") == true)
            #expect(snapshot.files.first?.hunks.first?.location.target == "docs/list.md:12:1")
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func shellClientDecisionSubmissionAppendsTimelineInPostingOrder(failCommand: Int) async throws {
        try await withFakeGitHubCLI(failCommand: failCommand) { repoRoot, logURL in
            let ideStateDirectory = repoRoot
                .appendingPathComponent(".yen-ide", isDirectory: true)
                .path
            let snapshot = makeSnapshot(
                repoRoot: repoRoot.path,
                files: [makeHunkedFile(path: "src/a.ts", line: 41)]
            )
            let focusLocation = IDESemanticLocation.repositoryLocation(
                repoRoot: repoRoot.path,
                relativePath: "src/a.ts",
                line: 41,
                column: 1
            )
            let request = PullRequestReviewSubmissionRequest(
                kind: .decision(.requestChanges),
                snapshot: snapshot,
                selectedFilePath: "src/a.ts",
                selectedFocusLocation: focusLocation,
                evidenceContext: PullRequestReviewEvidenceContext(
                    ideStateDirectory: ideStateDirectory,
                    latestVerifySummaryPath: nil,
                    latestVerifySummaryContents: nil,
                    latestVerifySemanticPath: nil,
                    latestVerifySemanticContents: nil,
                    recentTimelineEvents: []
                ),
                stagedInlineDrafts: [
                    PullRequestReviewInlineCommentDraft(
                        id: "inline-1",
                        path: "src/a.ts",
                        line: 41,
                        side: .right,
                        body: "First inline note",
                        suggestedFileName: "pr-42-inline-1.md",
                        preview: "inline one"
                    ),
                    PullRequestReviewInlineCommentDraft(
                        id: "inline-2",
                        path: "src/b.ts",
                        line: 9,
                        side: .left,
                        body: "Second inline note",
                        suggestedFileName: "pr-42-inline-2.md",
                        preview: "inline two"
                    ),
                ],
                stagedEvidenceDraft: PullRequestReviewEvidenceDraft(
                    suggestedFileName: "pr-42-evidence.md",
                    preview: "evidence body",
                    latestVerifySummaryPath: nil,
                    latestVerifySemanticPath: nil
                ),
                reviewNote: "Blocking on ordering proof."
            )

            if failCommand > 0 {
                do {
                    _ = try await PullRequestReviewShellClient().submit(request: request)
                    Issue.record("Expected the fake GitHub command to fail")
                } catch let error as PullRequestReviewSubmissionError {
                    let expectedIDs = Array(["inline-1", "inline-2"].prefix(failCommand - 1))
                    #expect((error.partialResult?.postedInlineDraftIDs ?? []) == expectedIDs)
                    #expect(error.partialResult?.didConsumeStagedEvidenceDraft != true)
                    #expect(error.partialResult?.decisionFilePath == nil)
                    let commands = try String(contentsOf: logURL, encoding: .utf8)
                        .split(whereSeparator: \.isNewline)
                    #expect(commands.count == failCommand)
                }
                return
            }

            let result = try await PullRequestReviewShellClient().submit(request: request)
            let timelineURL = URL(fileURLWithPath: ideStateDirectory)
                .appendingPathComponent("timeline.log")
            let timeline = try String(contentsOf: timelineURL, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let entries = timeline.map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            let events = entries.map { $0[1] }
            let details = entries.map { $0[4] }

            #expect(events == [
                "pr-inline-comment",
                "pr-inline-comment",
                "pr-evidence",
                "pr-decision",
                "pr-review",
            ])
            #expect(details[0] == "path=src/a.ts;line=41;location=src/a.ts:41:1;side=RIGHT")
            #expect(details[1] == "path=src/b.ts;line=9;location=src/b.ts:9:1;side=LEFT")
            #expect(details[2].contains("path=\(ideStateDirectory)/evidence/pr-42-evidence.md"))
            #expect(details[3] == "file=src/a.ts:41:1;post=1")
            #expect(details[4] == "file=src/a.ts:41:1;evidence=1;post=1")
            #expect(result.postedInlineDraftIDs == ["inline-1", "inline-2"])
            #expect(result.didConsumeStagedEvidenceDraft)
            #expect(result.evidenceFilePath == "\(ideStateDirectory)/evidence/pr-42-evidence.md")
            #expect(result.decisionFilePath?.hasPrefix("\(ideStateDirectory)/evidence/pr-42-decision-request-changes-") == true)
            #expect(result.decisionFilePath?.hasSuffix(".md") == true)
        }
    }

    @Test func adjacentSelectionClampsAtCollectionBounds() {
        let paths = ["a", "b", "c"]

        #expect(PullRequestReviewModel.adjacentSelection(from: paths, current: nil, direction: 1) == "a")
        #expect(PullRequestReviewModel.adjacentSelection(from: paths, current: "a", direction: -1) == "a")
        #expect(PullRequestReviewModel.adjacentSelection(from: paths, current: "c", direction: 1) == "c")
    }

    private func makeHunkedFile(path: String, line: Int) -> PullRequestReviewFile {
        let diff = """
        diff --git a/\(path) b/\(path)
        --- a/\(path)
        +++ b/\(path)
        @@ -\(line),3 +\(line),3 @@
        -line \(line)
        +line \(line) updated
         line \(line + 1)
         line \(line + 2)
        """

        let hunks = PullRequestReviewDiffParser.hunks(
            for: path,
            repoRoot: "/tmp/repo",
            diff: diff
        )

        return PullRequestReviewFile(
            path: path,
            diff: diff,
            hunks: hunks
        )
    }

    private func waitForLoad(_ model: PullRequestReviewModel) async {
        for _ in 0..<100 {
            if !model.isLoading { break }
            await Task.yield()
        }
        #expect(model.isLoading == false)
    }

    private func makeSnapshot(
        repoRoot: String = "/tmp/repo",
        number: Int = 42,
        title: String = "Add review window",
        files: [PullRequestReviewFile] = [
            PullRequestReviewFile(path: "src/a.ts", diff: "diff-a"),
            PullRequestReviewFile(path: "src/b.ts", diff: "diff-b"),
        ]
    ) -> PullRequestReviewSnapshot {
        PullRequestReviewSnapshot(
            repoRoot: repoRoot,
            summary: PullRequestReviewSummary(
                number: number,
                title: title,
                url: "https://example.com/pr/\(number)",
                author: "eight",
                baseRefName: "main",
                headRefName: "feature/review",
                headRefOID: "abc123def456",
                changedFiles: files.count,
                additions: 14,
                deletions: 3
            ),
            files: files
        )
    }

    private func waitForSubmission(_ model: PullRequestReviewModel) async {
        for _ in 0..<100 {
            if !model.isSubmitting { break }
            await Task.yield()
        }
        #expect(model.isSubmitting == false)
    }

    private static let edgeCasePullRequestDiff = """
    diff --git a/assets/icon.png b/assets/icon.png
    new file mode 100644
    index 0000000..abc1234
    Binary files /dev/null and b/assets/icon.png differ
    diff --git a/docs/old.md b/docs/new.md
    similarity index 100%
    rename from docs/old.md
    rename to docs/new.md
    diff --git a/src/deleted.ts b/src/deleted.ts
    deleted file mode 100644
    index e69de29..0000000
    --- a/src/deleted.ts
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -old
    -gone
    diff --git a/scripts/run.sh b/scripts/run.sh
    old mode 100644
    new mode 100755
    """

    private func withFakeGitHubCLI<Result>(
        metadata: String = """
        {
          "number": 42,
          "title": "Add review window",
          "url": "https://github.com/yenchat/yen/pull/42",
          "author": { "login": "eight" },
          "baseRefName": "main",
          "headRefName": "feature/review",
          "headRefOid": "abc123def456",
          "changedFiles": 4,
          "additions": 14,
          "deletions": 3
        }
        """,
        nameOnly: String = "",
        diff: String = "",
        failCommand: Int = 0,
        operation: (URL, URL) async throws -> Result
    ) async throws -> Result {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pr-review-gh-\(UUID().uuidString)", isDirectory: true)
        let binURL = tempRoot.appendingPathComponent("bin", isDirectory: true)
        let ghURL = binURL.appendingPathComponent("gh", isDirectory: false)
        let metadataURL = tempRoot.appendingPathComponent("metadata.json", isDirectory: false)
        let nameOnlyURL = tempRoot.appendingPathComponent("name-only.txt", isDirectory: false)
        let diffURL = tempRoot.appendingPathComponent("diff.txt", isDirectory: false)
        let logURL = tempRoot.appendingPathComponent("gh-commands.log", isDirectory: false)
        let originalEnvironment = ProcessInfo.processInfo.environment

        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        try nameOnly.write(to: nameOnlyURL, atomically: true, encoding: .utf8)
        try diff.write(to: diffURL, atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        if [ -n "$YEN_TEST_GH_LOG" ]; then
          printf '%s\\n' "$*" >> "$YEN_TEST_GH_LOG"
        fi
        if [ "$(wc -l < "$YEN_TEST_GH_LOG" | tr -d ' ')" = "\(failCommand)" ]; then
          printf '%s\\n' 'Injected GitHub command failure' >&2
          exit 1
        fi
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
          cat "$YEN_TEST_GH_METADATA"
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "diff" ] && [ "$3" = "--name-only" ]; then
          cat "$YEN_TEST_GH_NAME_ONLY"
          exit 0
        fi
        if [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
          cat "$YEN_TEST_GH_DIFF"
          exit 0
        fi
        exit 0
        """.write(to: ghURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ghURL.path)

        setenv("PATH", "\(binURL.path):\(originalEnvironment["PATH"] ?? "")", 1)
        setenv("YEN_TEST_GH_METADATA", metadataURL.path, 1)
        setenv("YEN_TEST_GH_NAME_ONLY", nameOnlyURL.path, 1)
        setenv("YEN_TEST_GH_DIFF", diffURL.path, 1)
        setenv("YEN_TEST_GH_LOG", logURL.path, 1)
        defer {
            if let originalPath = originalEnvironment["PATH"] {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
            for key in [
                "YEN_TEST_GH_METADATA",
                "YEN_TEST_GH_NAME_ONLY",
                "YEN_TEST_GH_DIFF",
                "YEN_TEST_GH_LOG",
            ] {
                if let originalValue = originalEnvironment[key] {
                    setenv(key, originalValue, 1)
                } else {
                    unsetenv(key)
                }
            }
            try? FileManager.default.removeItem(at: tempRoot)
        }

        return try await operation(tempRoot, logURL)
    }
}

@Suite(.serialized)
@MainActor
struct IDEEditorNavigatorTests {
    @Test func recognizedDefaultEditorsUseBundledCLIForLineAwareHandoff() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ide-editor-navigator-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempRoot.appendingPathComponent("src/a.ts")
        let appURL = tempRoot.appendingPathComponent("Visual Studio Code.app", isDirectory: true)
        let bundledCLIURL = tempRoot.appendingPathComponent("bin/yen")

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: bundledCLIURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "export const value = 1;\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: bundledCLIURL, atomically: true, encoding: .utf8)

        var capturedExecutable: URL?
        var capturedArguments: [String] = []
        var didUseWorkspaceFallback = false
        let environment = IDEEditorNavigatorEnvironment(
            defaultEditorResolver: { _ in appURL },
            bundledCLIResolver: { bundledCLIURL },
            processRunner: { executableURL, arguments in
                capturedExecutable = executableURL
                capturedArguments = arguments
                return IDEEditorCommandResult(terminationStatus: 0, stdout: "", stderr: "")
            },
            workspaceOpen: { _, _ in
                didUseWorkspaceFallback = true
            }
        )
        let location = IDESemanticLocation(
            path: fileURL.path,
            relativePath: "src/a.ts",
            line: 4,
            column: 1
        )

        let failure = await IDEEditorNavigator.open(location, environment: environment)

        #expect(failure == nil)
        #expect(capturedExecutable == bundledCLIURL)
        #expect(capturedArguments == [
            "ide",
            "open",
            "\(fileURL.path):4:1",
            "--editor",
            "/usr/bin/open -a 'Visual Studio Code'",
        ])
        #expect(didUseWorkspaceFallback == false)
    }

    @Test func recognizedDefaultEditorsSurfaceMissingBundledBridge() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ide-editor-navigator-missing-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempRoot.appendingPathComponent("src/a.ts")
        let appURL = tempRoot.appendingPathComponent("Visual Studio Code.app", isDirectory: true)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try "export const value = 1;\n".write(to: fileURL, atomically: true, encoding: .utf8)

        var didRunBridge = false
        var didUseWorkspaceFallback = false
        let environment = IDEEditorNavigatorEnvironment(
            defaultEditorResolver: { _ in appURL },
            bundledCLIResolver: { nil },
            processRunner: { _, _ in
                didRunBridge = true
                return IDEEditorCommandResult(terminationStatus: 0, stdout: "", stderr: "")
            },
            workspaceOpen: { _, _ in
                didUseWorkspaceFallback = true
            }
        )
        let location = IDESemanticLocation(
            path: fileURL.path,
            relativePath: "src/a.ts",
            line: 4,
            column: 1
        )

        let failure = await IDEEditorNavigator.open(location, environment: environment)

        #expect(failure == "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present.")
        #expect(didRunBridge == false)
        #expect(didUseWorkspaceFallback == false)
    }
}

private final class PullRequestReviewRunnerStub: @unchecked Sendable, PullRequestReviewRunning {
    let resolvedRepoRoot: String?
    var snapshot: PullRequestReviewSnapshot?
    var evidenceContext: PullRequestReviewEvidenceContext
    var submittedRequests: [PullRequestReviewSubmissionRequest] = []
    var submissionError: Error?
    var loadPullRequestHandler: (@Sendable (String?, String) async throws -> PullRequestReviewSnapshot)?
    var loadEvidenceContextHandler: (@Sendable (String) async -> PullRequestReviewEvidenceContext)?
    var submitHandler: (@Sendable (PullRequestReviewSubmissionRequest) async throws -> PullRequestReviewSubmissionResult)?

    init(
        resolvedRepoRoot: String?,
        snapshot: PullRequestReviewSnapshot?,
        evidenceContext: PullRequestReviewEvidenceContext
    ) {
        self.resolvedRepoRoot = resolvedRepoRoot
        self.snapshot = snapshot
        self.evidenceContext = evidenceContext
    }

    func resolveRepositoryRoot(for workingDirectory: String?) async throws -> String? {
        resolvedRepoRoot
    }

    func loadPullRequest(requestedPR: String?, repoRoot: String) async throws -> PullRequestReviewSnapshot {
        if let loadPullRequestHandler {
            return try await loadPullRequestHandler(requestedPR, repoRoot)
        }
        guard let snapshot else {
            throw PullRequestReviewCommandError.notInGitRepository
        }
        return snapshot
    }

    func loadEvidenceContext(repoRoot: String) async -> PullRequestReviewEvidenceContext {
        if let loadEvidenceContextHandler {
            return await loadEvidenceContextHandler(repoRoot)
        }
        return evidenceContext
    }

    func submit(request: PullRequestReviewSubmissionRequest) async throws -> PullRequestReviewSubmissionResult {
        submittedRequests.append(request)
        if let submitHandler {
            return try await submitHandler(request)
        }
        if let submissionError {
            throw submissionError
        }

        let evidencePath = request.stagedEvidenceDraft.map { draft in
            "\(request.evidenceContext.ideStateDirectory)/evidence/\(draft.suggestedFileName)"
        }
        let decisionPath: String?
        let didConsumeEvidence: Bool
        switch request.kind {
        case .decision(let mode):
            decisionPath = "\(request.evidenceContext.ideStateDirectory)/evidence/pr-\(request.snapshot.summary.number)-decision-\(mode.rawValue).md"
            didConsumeEvidence = request.stagedEvidenceDraft != nil
        case .evidenceComment:
            decisionPath = nil
            didConsumeEvidence = true
        case .inlineComments:
            decisionPath = nil
            didConsumeEvidence = false
        }

        return PullRequestReviewSubmissionResult(
            kind: request.kind,
            postedInlineDraftIDs: request.stagedInlineDrafts.map(\.id),
            didPostEvidenceComment: request.kind == .evidenceComment,
            didConsumeStagedEvidenceDraft: didConsumeEvidence,
            evidenceFilePath: evidencePath,
            decisionFilePath: decisionPath
        )
    }
}

private actor PullRequestReviewAsyncGate {
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
