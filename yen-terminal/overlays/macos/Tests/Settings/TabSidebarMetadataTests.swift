import AppKit
import Testing
@testable import YEN

@MainActor
struct TabSidebarMetadataTests {
    @Test func dockedFallbackTickKeepsUnchangedPathMetadataCached() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        let model = DockedTabSidebarModel()
        defer { model.setVisible(false); window.orderOut(nil); TabSidebarController.testingResetMetadataCache() }
        TabSidebarController.testingResetMetadataCache()
        model.attach(to: window)
        let initialCount = TabSidebarController.testingMetadataCacheBuildCount
        #expect(initialCount > 0)
        try await Task.sleep(for: .milliseconds(2600))
        #expect(TabSidebarController.testingMetadataCacheBuildCount == initialCount)
        #expect(model.tabs.count == 1)
    }

    @Test func dockedObserverCallbackDoesNotRescanMetadata() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        let model = DockedTabSidebarModel()
        defer { model.setVisible(false); window.orderOut(nil); TabSidebarController.testingResetMetadataCache() }
        model.attach(to: window)
        let scans = model.testingMetadataScanCount
        window.title = "Updated title"
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.tabs.first?.title == "Updated title")
        #expect(model.testingMetadataScanCount == scans + 1)
    }

    @Test func cachedPathsKeepGitRefreshAndBuildExpiryLive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = YEN.SurfaceConfiguration()
        config.command = "/bin/sleep 60"
        config.workingDirectory = directory.path
        let controller = TerminalController(try Self.requireAppDelegate().yen, withBaseConfig: config)
        defer {
            TabSidebarController.testingResetMetadataCache()
            Self.closeTerminalController(controller)
            try? FileManager.default.removeItem(at: directory)
        }
        let window = try #require(controller.window)
        let surface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = surface
        surface.pwd = directory.path
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let probe = SidebarSnapshotProbe()
        let git = TabSidebarGitContextCache(now: { clock }, resolve: { await probe.resolve($0) })
        var handler: ((Notification) -> Void)?
        let builds = TabSidebarBuildStatusStore(registerObserver: { _, callback in
            handler = callback
            return NSObject()
        }, removeObserver: { _ in }, now: { clock })
        builds.setup()
        let notifyBuild = try #require(handler)
        notifyBuild(Notification(name: .yenBuildNotification, object: "YEN Build completed",
            userInfo: [ServiceNotificationRouteMetadata.surfaceIDPayloadKey: surface.id.uuidString]))
        for _ in 0..<100 {
            if builds.signal(for: surface.id) != nil { break }
            await Task.yield()
        }
        #expect(builds.signal(for: surface.id)?.summary == "Build complete")
        TabSidebarController.testingResetMetadataCache()
        func row() -> TabSidebarItem? {
            TabSidebarController.items(for: window, referenceDate: clock,
                gitContextCache: git, buildStatusStore: builds).first
        }
        _ = row()
        for _ in 0..<100 {
            if row()?.gitSummary == "branch-1" { break }
            await Task.yield()
        }
        #expect(row()?.gitSummary == "branch-1")
        #expect(row()?.statusSummary == "Build complete")
        let cachedCount = TabSidebarController.testingMetadataCacheBuildCount
        surface.progressReport = YEN.Action.ProgressReport(state: .set, progress: 42)
        #expect(row()?.statusSummary == "Task 42%")
        #expect(TabSidebarController.testingMetadataCacheBuildCount == cachedCount)
        surface.progressReport = nil
        clock = clock.addingTimeInterval(14)
        #expect(row()?.gitSummary == "branch-1")
        #expect(await probe.calls == 1)
        clock = clock.addingTimeInterval(2)
        _ = row()
        for _ in 0..<100 {
            if row()?.gitSummary == "branch-2" { break }
            await Task.yield()
        }
        #expect(row()?.gitSummary == "branch-2")
        #expect(await probe.calls == 2)
        clock = Date(timeIntervalSince1970: 1_000_119)
        #expect(row()?.statusSummary == "Build complete")
        let beforeExpiry = TabSidebarController.testingMetadataCacheBuildCount
        clock = clock.addingTimeInterval(2)
        #expect(row()?.statusSummary == nil)
        #expect(TabSidebarController.testingMetadataCacheBuildCount == beforeExpiry)
        try FileManager.default.removeItem(at: directory)
        clock = clock.addingTimeInterval(15)
        #expect(row()?.cwdSummary == nil)
        #expect(TabSidebarController.testingMetadataCacheBuildCount > beforeExpiry)
    }

    @Test func sharedGitResolverPreservesSidebarStatusAndDetachedFallback() async {
        let runner = SidebarGitFixture(responses: [
            "status --porcelain=v2 -z --branch --untracked-files=no":
                "# branch.oid abc123\0# branch.head (detached)\0# branch.ab +3 -2\0"
                + "1 .M N... 100644 100644 100644 abc def file.swift\0",
            "rev-parse --short HEAD": "abc123",
        ])
        let snapshot = await TabSidebarGitSnapshotResolver.resolve(workingDirectory: "/repo/sub", runner: runner)
        #expect(snapshot?.summary == "detached@abc123 dirty ↑3 ↓2")
        #expect(await runner.commands == [
            "status --porcelain=v2 -z --branch --untracked-files=no",
            "rev-parse --short HEAD",
        ])
    }

    @Test func namedBranchUsesOneStatusCallAndMissingStatusIsNotClean() async {
        let runner = SidebarGitFixture(responses: [
            "status --porcelain=v2 -z --branch --untracked-files=no":
                "# branch.oid (initial)\0# branch.head main\0",
        ])
        let snapshot = await TabSidebarGitSnapshotResolver.resolve(workingDirectory: "/repo", runner: runner)
        #expect(snapshot?.summary == "main")
        #expect(await runner.commands.count == 1)
        let missing = await TabSidebarGitSnapshotResolver.resolve(
            workingDirectory: "/missing", runner: SidebarGitFixture(responses: [:]))
        #expect(missing == nil)
    }

	@Test func shortcutLabelsFollowNativeTabOrdering() {
		#expect(TabSidebarController.shortcutLabel(for: 0, totalTabs: 1) == "1")
		#expect(TabSidebarController.shortcutLabel(for: 7, totalTabs: 8) == "8")
		#expect(TabSidebarController.shortcutLabel(for: 8, totalTabs: 9) == "9")
	}

	@Test func shortcutLabelsSkipMiddleTabsBeyondCommandEight() {
		#expect(TabSidebarController.shortcutLabel(for: 8, totalTabs: 10) == nil)
		#expect(TabSidebarController.shortcutLabel(for: 9, totalTabs: 10) == "9")
		#expect(TabSidebarController.shortcutLabel(for: -1, totalTabs: 10) == nil)
	}

	@Test func buildStatusSignalsParseCompletedAndFailedTitles() {
		#expect(
			TabSidebarBuildStatusStore.signal(from: "YEN Build completed")
				== TabSidebarStatusSignal(summary: "Build complete", tone: .success)
		)
		#expect(
			TabSidebarBuildStatusStore.signal(from: "YEN Test Run failed (exit 1)")
				== TabSidebarStatusSignal(summary: "Test Run failed", tone: .error)
		)
	}

	@Test func buildStatusStoreInstallsObserverLazilyOnFirstRead() async {
		final class TestObserver: NSObject {}

		var registeredNames: [Notification.Name] = []
		var registeredHandler: ((Notification) -> Void)?
		let store = TabSidebarBuildStatusStore(
			registerObserver: { name, handler in
				registeredNames.append(name)
				registeredHandler = handler
				return TestObserver()
			},
			removeObserver: { _ in }
		)
		let surfaceID = UUID()

		#expect(store.signal(for: surfaceID) == nil)
		#expect(registeredNames == [.yenBuildNotification])

		registeredHandler?(
			Notification(
				name: .yenBuildNotification,
				object: "YEN Build completed",
				userInfo: [
					ServiceNotificationRouteMetadata.surfaceIDPayloadKey: surfaceID.uuidString,
				]
			)
		)
		await Task.yield()

		#expect(
			store.signal(for: surfaceID)
				== TabSidebarStatusSignal(summary: "Build complete", tone: .success)
		)
		#expect(registeredNames == [.yenBuildNotification])
	}

	@Test func metadataFallbackRefreshIntervalRemainsBounded() {
		#expect(TabSidebarController.metadataFallbackRefreshInterval == 2)
	}

	@Test func itemsReusePerWindowMetadataUntilInvalidated() {
		let firstWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let secondWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		defer {
			TabSidebarController.testingResetMetadataCache()
			firstWindow.orderOut(nil)
			secondWindow.orderOut(nil)
		}

		TabSidebarController.testingResetMetadataCache()

		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: firstWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 1)

		_ = TabSidebarController.items(for: secondWindow)
		_ = TabSidebarController.items(for: firstWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 2)

		TabSidebarController.testingInvalidateMetadataCache(for: firstWindow)
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 3)

		TabSidebarController.testingInvalidateMetadataCache(
			notificationName: .yenTabSidebarBuildStatusDidChange,
			object: nil
		)
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 5)
	}

	@Test func targetedSurfaceInvalidationEvictsOnlyMatchingCachedItems() throws {
		let firstController = TerminalController(try Self.requireAppDelegate().yen)
		let secondController = TerminalController(try Self.requireAppDelegate().yen)
		defer {
			TabSidebarController.testingResetMetadataCache()
			Self.closeTerminalController(firstController)
			Self.closeTerminalController(secondController)
		}
		let firstWindow = try #require(firstController.window)
		let secondWindow = try #require(secondController.window)
		let firstSurface = try #require(firstController.surfaceTree.first)
		let secondSurface = try #require(secondController.surfaceTree.first)
		firstController.focusedSurface = firstSurface
		secondController.focusedSurface = secondSurface

		TabSidebarController.testingResetMetadataCache()
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 2)

		TabSidebarController.testingInvalidateMetadataCache(
			notificationName: .yenTabSidebarBuildStatusDidChange,
			object: firstSurface.id
		)
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 3)
	}

	@Test func targetedWorkingDirectoryInvalidationEvictsOnlyMatchingCachedItems() throws {
		let firstDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let secondDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

		let firstController = TerminalController(try Self.requireAppDelegate().yen)
		let secondController = TerminalController(try Self.requireAppDelegate().yen)
		defer {
			TabSidebarController.testingResetMetadataCache()
			Self.closeTerminalController(firstController)
			Self.closeTerminalController(secondController)
			try? FileManager.default.removeItem(at: firstDirectory)
			try? FileManager.default.removeItem(at: secondDirectory)
		}
		let firstWindow = try #require(firstController.window)
		let secondWindow = try #require(secondController.window)
		let firstSurface = try #require(firstController.surfaceTree.first)
		let secondSurface = try #require(secondController.surfaceTree.first)
		firstSurface.pwd = firstDirectory.path
		secondSurface.pwd = secondDirectory.path
		firstController.focusedSurface = firstSurface
		secondController.focusedSurface = secondSurface

		TabSidebarController.testingResetMetadataCache()
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 2)

		TabSidebarController.testingInvalidateMetadataCache(
			notificationName: .yenTabSidebarGitContextDidChange,
			object: firstDirectory.resolvingSymlinksInPath().standardizedFileURL.path
		)
		_ = TabSidebarController.items(for: firstWindow)
		_ = TabSidebarController.items(for: secondWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == 3)
	}

	@Test func trustedWorkingDirectoryRequiresExistingLocalPath() {
		let existingPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
		let missingPath = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.path

		#expect(TabSidebarController.trustedWorkingDirectory(from: existingPath) == existingPath)
		#expect(TabSidebarController.trustedWorkingDirectory(from: "relative/path") == nil)
		#expect(TabSidebarController.trustedWorkingDirectory(from: missingPath) == nil)
	}

	@Test func trustedWorkingDirectoryCanonicalizesSymlinks() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let target = root.appendingPathComponent("target", isDirectory: true)
		let link = root.appendingPathComponent("link", isDirectory: true)

		try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
		defer {
			try? FileManager.default.removeItem(at: root)
		}

		#expect(
			TabSidebarController.trustedWorkingDirectory(from: link.path)
				== target.resolvingSymlinksInPath().standardizedFileURL.path
		)
	}

	private static func requireAppDelegate() throws -> AppDelegate {
		try #require(NSApp.delegate as? AppDelegate)
	}

	private static func closeTerminalController(_ controller: TerminalController) {
		controller.window?.close()
		RunLoop.main.run(until: Date().addingTimeInterval(0.02))
	}
}

private actor SidebarGitFixture: GitDrawerCommandRunning {
    let responses: [String: String]
    var commands: [String] = []
    init(responses: [String: String]) { self.responses = responses }
    func run(_ command: GitDrawerGitCommand, currentDirectory: String, timeout: TimeInterval,
             stdoutLimit: Int, stderrLimit: Int) async throws -> GitDrawerCommandOutput {
        #expect(command.isReadOnly)
        #expect(timeout == 2)
        let key = command.arguments.joined(separator: " ")
        commands.append(key)
        guard let response = responses[key] else { throw GitDrawerShellError.commandFailed(key) }
        return GitDrawerCommandOutput(stdout: response, stderr: "", wasTruncated: false)
    }
}

private actor SidebarSnapshotProbe {
    private(set) var calls = 0
    func resolve(_ directory: String) -> TabSidebarGitSnapshot {
        calls += 1
        return TabSidebarGitSnapshot(branch: "branch-\(calls)", dirty: false, ahead: 0, behind: 0)
    }
}
