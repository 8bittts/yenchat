import AppKit
import Foundation
import Testing
@testable import YEN

/// Shared by RemotePanesContractTests and RemoteHostsPaletteContractTests:
/// live terminal windows whose remote panes run a stand-in CLI, never ssh.
@MainActor
enum RemoteContractFixtures {
    // Live terminal controllers spawn their command; retain them for the
    // serialized suites (see TerminalRestorableVersionTests).
    static var retainedControllers: [TerminalController] = []

    nonisolated static let sessionID = UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!

    nonisolated static var identity: RemotePaneIdentity {
        RemotePaneIdentity(displayName: "Studio", sshTarget: "studio.example.invalid", sessionID: sessionID)!
    }

    /// A stand-in CLI that keeps running, like an attached client.
    nonisolated static let liveCLI: String = {
        let path = NSTemporaryDirectory() + "yen-remote-contract-live-cli-\(getpid()).sh"
        try? "#!/bin/sh\nsleep 600\n".write(toFile: path, atomically: true, encoding: .utf8)
        chmod(path, 0o755)
        return path
    }()

    static func markedConfig(_ identity: RemotePaneIdentity = identity) -> YEN.SurfaceConfiguration {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[RemotePanes.markerEnvironmentKey] = RemotePanes.marker(for: identity)
        return config
    }

    static func controller(_ config: YEN.SurfaceConfiguration?, cli: String = liveCLI) throws -> TerminalController {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate, "Expected AppDelegate-backed test host.")
        RemotePanes._testSetCLIPath(cli)
        defer { RemotePanes._testSetCLIPath(nil) }
        let controller = TerminalController(appDelegate.yen, withBaseConfig: config)
        retainedControllers.append(controller)
        return controller
    }

    static func withCLI<T>(_ path: String, _ body: () throws -> T) rethrows -> T {
        RemotePanes._testSetCLIPath(path)
        defer { RemotePanes._testSetCLIPath(nil) }
        return try body()
    }

    /// Let AppKit and SwiftUI deliver queued work.
    static func spin(_ seconds: TimeInterval = 0.5) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func waitUntil(_ condition: () -> Bool) {
        for _ in 0..<80 where !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
