import AppKit
import Testing
@testable import YEN

@MainActor
struct GitDrawerRoutingTests {
    @Test func gitDrawerAllowsNormalTerminalWindow() {
        #expect(AppDelegate.canShowGitDrawer(
            windowControllerIsTerminal: true,
            isQuickTerminal: false,
            isFullscreen: false,
            isMiniaturized: false
        ))
    }

    @Test func gitDrawerRejectsUnsupportedWindows() {
        #expect(!AppDelegate.canShowGitDrawer(
            windowControllerIsTerminal: false,
            isQuickTerminal: false,
            isFullscreen: false,
            isMiniaturized: false
        ))
        #expect(!AppDelegate.canShowGitDrawer(
            windowControllerIsTerminal: true,
            isQuickTerminal: true,
            isFullscreen: false,
            isMiniaturized: false
        ))
        #expect(!AppDelegate.canShowGitDrawer(
            windowControllerIsTerminal: true,
            isQuickTerminal: false,
            isFullscreen: true,
            isMiniaturized: false
        ))
        #expect(!AppDelegate.canShowGitDrawer(
            windowControllerIsTerminal: true,
            isQuickTerminal: false,
            isFullscreen: false,
            isMiniaturized: true
        ))
    }
    @Test func shellAndAgentDirectoryChangesRetargetWithTheSidebarHidden() async throws {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        let defaults = UserDefaults.standard
        let key = TabSidebarController.tabSidebarEnabledPreferenceKey
        let originalPreference = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        TabSidebarController.shared.testingResetState()
        defer {
            if let originalPreference { defaults.set(originalPreference, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            TabSidebarController.shared.testingReloadVisibleStateFromPreferences()
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yen-drawer-cwd-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repositories = try ["shell", "changed", "agent"].map { name in
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["init", "--quiet", directory.path]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return directory.resolvingSymlinksInPath().path
        }
        var baseConfig = YEN.SurfaceConfiguration()
        baseConfig.workingDirectory = repositories[0]
        baseConfig.command = "/bin/sleep 60"
        let terminal = TerminalController(appDelegate.yen, withBaseConfig: baseConfig)
        defer { terminal.terminalViewContainer?.gitDrawerController?.close(); terminal.window?.close() }
        let surface = try #require(terminal.surfaceTree.first)
        terminal.focusedSurface = surface
        surface.pwd = repositories[0]
        #expect(appDelegate.toggleGitDrawer(for: terminal.window))
        let drawer = try #require(terminal.terminalViewContainer?.gitDrawerController)
        try #require(await waitForDirectory(repositories[0], drawer: drawer),
                 "Initial drawer: \(String(describing: drawer.presentationState)); pwd: \(String(describing: surface.pwd))")
        #expect(!TabSidebarController.shared.visible)
        surface.pwd = repositories[1]
        #expect(await waitForDirectory(repositories[1], drawer: drawer))
        let foregroundPID = try #require(surface.surfaceModel?.foregroundPID)
        AgentWorkingDirectoryReceiver.apply(
            .report(directory: repositories[2]), to: surface.agentWorkingDirectoryState,
            foregroundProcessID: foregroundPID
        )
        #expect(await waitForDirectory(repositories[2], drawer: drawer))
        #expect(!TabSidebarController.shared.visible)
    }

    private func waitForDirectory(_ directory: String, drawer: GitDrawerController) async -> Bool {
        // Foundation and git can spell the same temporary directory as /var or /private/var.
        let expected = URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardizedFileURL
        func matches() -> Bool {
            guard let path = drawer.presentationState?.repoRoot else { return false }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL == expected
        }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if matches() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return matches()
    }
}
