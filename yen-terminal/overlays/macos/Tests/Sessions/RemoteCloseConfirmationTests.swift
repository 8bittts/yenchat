import AppKit
import Foundation
import Testing
import YENKit
@testable import YEN

/// Closing a remote pane ends only the local client; the session keeps
/// running on the other Mac, so no close path may warn that a process will be
/// killed. A local pane with a running process still asks.
@MainActor
@Suite(.serialized)
struct RemoteCloseConfirmationTests {
    private static var retainedControllers: [TerminalController] = []

    /// A client that keeps running, so the remote pane has a live process.
    private static let liveCLI: String = {
        let path = NSTemporaryDirectory() + "yen-remote-close-cli-\(getpid()).sh"
        try? "#!/bin/sh\nsleep 600\n".write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        return path
    }()

    private let identity = RemotePaneIdentity(
        displayName: "Studio",
        sshTarget: "studio.example.invalid",
        sessionID: UUID(uuidString: "0A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9")!
    )!

    private func remoteConfig() -> YEN.SurfaceConfiguration {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[RemotePanes.markerEnvironmentKey] = RemotePanes.marker(for: identity)
        return config
    }

    /// A local pane whose command keeps running.
    private func busyLocalConfig() -> YEN.SurfaceConfiguration {
        var config = YEN.SurfaceConfiguration()
        config.command = "/bin/sh -c 'sleep 600; :'"
        return config
    }

    private func controller(_ config: YEN.SurfaceConfiguration) throws -> TerminalController {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate, "Expected AppDelegate-backed test host.")
        RemotePanes._testSetCLIPath(Self.liveCLI)
        defer { RemotePanes._testSetCLIPath(nil) }
        let controller = TerminalController(appDelegate.yen, withBaseConfig: config)
        Self.retainedControllers.append(controller)
        _ = controller.window
        return controller
    }

    private func remoteSurface() throws -> YEN.SurfaceView {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        let app = try #require(appDelegate.yen.app)
        RemotePanes._testSetCLIPath(Self.liveCLI)
        defer { RemotePanes._testSetCLIPath(nil) }
        return YEN.SurfaceView(app, baseConfig: remoteConfig())
    }

    /// The engine's own answer, before YEN's close rule.
    private func engineNeedsConfirm(_ surface: YEN.SurfaceView) -> Bool {
        guard let handle = surface.surface else { return false }
        return yen_surface_needs_confirm_quit(handle)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<60 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func theRuleAsksOnlyForALocalPaneTheEngineAsksFor() throws {
        let remote = try remoteSurface()
        #expect(!RemotePanes.closeNeedsConfirmation(paneID: remote.id, engineNeedsConfirm: true))
        #expect(!RemotePanes.closeNeedsConfirmation(paneID: remote.id, engineNeedsConfirm: false))
        #expect(RemotePanes.closeNeedsConfirmation(paneID: UUID(), engineNeedsConfirm: true))
        #expect(!RemotePanes.closeNeedsConfirmation(paneID: UUID(), engineNeedsConfirm: false))
    }

    @Test func aRemoteTabClosesWithoutAsking() async throws {
        let controller = try controller(remoteConfig())
        let surface = try #require(controller.surfaceTree.first)
        #expect(surface.remotePaneIdentity == identity)
        await waitUntil { engineNeedsConfirm(surface) }
        // The engine sees a running process; YEN knows the session survives.
        #expect(engineNeedsConfirm(surface))
        #expect(!surface.needsConfirmQuit)
        #expect(controller.windowCanBeClosedWithoutConfirmation())
    }

    @Test func aMixedTabStillAsksForItsLocalProcess() async throws {
        let controller = try controller(busyLocalConfig())
        let local = try #require(controller.surfaceTree.first)
        let remote = try remoteSurface()
        controller.surfaceTree = try controller.surfaceTree.inserting(view: remote, at: local, direction: .right)
        await waitUntil { local.needsConfirmQuit && engineNeedsConfirm(remote) }

        #expect(local.needsConfirmQuit)
        #expect(engineNeedsConfirm(remote))
        #expect(!remote.needsConfirmQuit)
        #expect(controller.surfaceTree.contains(where: { $0.needsConfirmQuit }))
        #expect(!controller.windowCanBeClosedWithoutConfirmation())
    }

    @Test func closingARemotePaneDoesNotAskAndALocalBusyPaneDoes() async throws {
        let controller = try controller(busyLocalConfig())
        let local = try #require(controller.surfaceTree.first)
        let remote = try remoteSurface()
        controller.surfaceTree = try controller.surfaceTree.inserting(view: remote, at: local, direction: .right)
        await waitUntil { local.needsConfirmQuit }

        // The engine reports a live process for both; the remote pane goes at once.
        NotificationCenter.default.post(name: YEN.Notification.yenCloseSurface, object: remote, userInfo: ["process_alive": true])
        #expect(!controller.surfaceTree.contains(remote))
        #expect(controller.window?.attachedSheet == nil)

        // The local pane raises the "Close Terminal?" alert and stays until
        // the user answers.
        func alertPanels() -> [NSWindow] {
            NSApp.windows.filter { String(describing: type(of: $0)).contains("Alert") }
        }
        let before = Set(alertPanels().map(ObjectIdentifier.init))
        NotificationCenter.default.post(name: YEN.Notification.yenCloseSurface, object: local, userInfo: ["process_alive": true])
        await waitUntil { alertPanels().contains { !before.contains(ObjectIdentifier($0)) } }
        let raised = alertPanels().filter { !before.contains(ObjectIdentifier($0)) }
        #expect(raised.count == 1)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.surfaceTree.contains(local))
        // Cancel, which keeps the pane.
        for panel in raised {
            if let parent = panel.sheetParent {
                parent.endSheet(panel, returnCode: .alertSecondButtonReturn)
            } else {
                NSApp.stopModal(withCode: .alertSecondButtonReturn)
                panel.orderOut(nil)
            }
        }
    }
}
