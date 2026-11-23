import AppKit
import Foundation
import SwiftUI
import Testing
@testable import YEN

// Contract checks for remote panes that RemotePanesTests leaves open
// (_docs/01-architecture.md -> Remote panes; _docs/13-desktop-features.md ->
// Remote pane labels).

private typealias Fixtures = RemoteContractFixtures

@MainActor
@Suite(.serialized)
struct RemotePanesContractTests {
    private var identity: RemotePaneIdentity { Fixtures.identity }

    // MARK: Opening

    @Test func openFocusesThePaneAlreadyAttachedToTheSession() throws {
        let controller = try Fixtures.controller(Fixtures.markedConfig())
        let surface = try #require(controller.surfaceTree.first)
        Fixtures.waitUntil { RemotePanes.isAttached(surface) }
        var presented: [AnyObject] = []
        let observer = NotificationCenter.default.addObserver(
            forName: YEN.Notification.yenPresentTerminal, object: nil, queue: nil
        ) { presented.append($0.object as AnyObject) }
        defer { NotificationCenter.default.removeObserver(observer) }

        let result = RemotePanes.open(identity, from: nil, controllers: [controller]) { _ in
            Issue.record("an attached session must not open a second tab")
            return true
        }
        #expect(result == .focused)
        #expect(presented.count == 1)
        #expect(presented.first === surface)
    }

    @Test func openCreatesATabWhosePaneIsRemoteAndForgetsAnUnusedToken() throws {
        let other = try #require(RemotePaneIdentity(displayName: "Mini", sshTarget: "mini.example.invalid", sessionID: UUID()))
        RemotePanes._testSetCLIPath("/usr/bin/true")
        defer { RemotePanes._testSetCLIPath(nil) }

        // The tab's pane is prepared while the tab is created, as newTab does.
        let createdID = UUID()
        let opened = RemotePanes.open(other, from: nil, controllers: []) { config in
            var created = config
            RemotePanes.prepare(&created, paneID: createdID)
            return true
        }
        #expect(opened == .opened)
        #expect(RemotePanes.identity(for: createdID) == other)

        // A tab that never used its token leaves nothing a later pane could claim.
        var unused: YEN.SurfaceConfiguration?
        let notUsed = RemotePanes.open(other, from: nil, controllers: []) { config in
            unused = config
            return true
        }
        #expect(notUsed == .opened)
        var later = try #require(unused)
        let laterID = UUID()
        RemotePanes.prepare(&later, paneID: laterID)
        #expect(later.command == nil)
        #expect(RemotePanes.identity(for: laterID) == nil)

        var failedConfig: YEN.SurfaceConfiguration?
        let failed = RemotePanes.open(other, from: nil, controllers: []) { config in
            failedConfig = config
            return false
        }
        #expect(failed == .failed)
        var afterFailure = try #require(failedConfig)
        RemotePanes.prepare(&afterFailure, paneID: UUID())
        #expect(afterFailure.command == nil)
    }

    // MARK: The attach command

    /// The engine runs a pane command with `exec -l`; the command must not
    /// make sh a login shell that reads the user's profile.
    @Test func theAttachCommandUnderExecDashLReadsNoProfile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("yen-remote-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let marker = home.appendingPathComponent("profile-ran").path
        try "touch '\(marker)'\n".write(to: home.appendingPathComponent(".profile"), atomically: true, encoding: .utf8)

        RemotePanes._testSetCLIPath("/usr/bin/true")
        defer { RemotePanes._testSetCLIPath(nil) }
        let command = try #require(RemotePanes.attachCommand(for: identity))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "exec -l \(command)"]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    // MARK: Titles

    @Test func aTitleThatIsTheHostOrPaddedIsLabeledOnce() {
        #expect(RemotePanes.tabTitle("Studio", host: "Studio") == "Studio")
        #expect(RemotePanes.tabTitle("  vim  ", host: "Studio") == "Studio · vim")
        #expect(RemotePanes.tabTitle("\n", host: "Studio") == "Studio")
    }

    @Test func aTypedTabTitleIsLabeledByTheRemotePaneTheTitleCameFrom() throws {
        let controller = try Fixtures.controller(Fixtures.markedConfig())
        let remote = try #require(controller.surfaceTree.first)
        controller.focusedSurfaceDidChange(to: remote)
        controller.titleOverride = "Build"
        #expect(controller.window?.title == "Studio · Build")
        // No pane has focus: the label still comes from the pane the title came from.
        controller.focusedSurfaceDidChange(to: nil)
        controller.titleOverride = "Deploy"
        #expect(controller.window?.title == "Studio · Deploy")
        controller.titleOverride = nil
    }

    @Test func aRingingRemoteTabKeepsTheBellOutermost() throws {
        let controller = try Fixtures.controller(Fixtures.markedConfig())
        let remote = try #require(controller.surfaceTree.first)
        try #require(controller.yen.config.bellFeatures.contains(.title))
        controller.focusedSurfaceDidChange(to: remote)
        NotificationCenter.default.post(name: .yenBellDidRing, object: remote)
        Fixtures.waitUntil { controller.window?.title.hasPrefix("🔔") == true }
        let title = try #require(controller.window?.title)
        #expect(title.hasPrefix("🔔 Studio"), "\(title)")
    }

    // MARK: Restore and forgetting

    @Test func aMalformedRemotePanesValueStillRestoresTheWindow() throws {
        let local = try Fixtures.controller(nil)
        let pane = try #require(local.surfaceTree.first)

        struct Forged: Encodable {
            let surfaceTree: SplitTree<YEN.SurfaceView>
            let tabColor: TerminalTabColor
            let remotePanes: String
        }
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        try archiver.encodeEncodable(
            Forged(surfaceTree: local.surfaceTree, tabColor: .none, remotePanes: "not a map"),
            forKey: "value"
        )
        archiver.finishEncoding()
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        let restored = Fixtures.withCLI("/usr/bin/true") {
            unarchiver.decodeDecodable(TerminalRestorableState.self, forKey: "value")
        }
        let state = try #require(restored)
        #expect(state.remotePanes == nil)
        #expect(state.surfaceTree.first?.id == pane.id)
        #expect(state.surfaceTree.first?.remotePaneIdentity == nil)
    }

    @Test func closingARemotePaneForgetsItsIdentityThroughTheSessionsPath() async throws {
        let paneID = UUID()
        var config = Fixtures.markedConfig()
        Fixtures.withCLI("/usr/bin/true") { RemotePanes.prepare(&config, paneID: paneID) }
        #expect(RemotePanes.identity(for: paneID) == identity)
        PersistentSessions.paneLeftTree(
            paneID, undoExpiration: .zero, socketDirectory: "/tmp/yen-no-such-dir",
            isStillPresent: { _ in false }, close: { _ in }
        )
        try await Task.sleep(for: PersistentSessions.closeGrace + .milliseconds(800))
        #expect(RemotePanes.identity(for: paneID) == nil)
    }
}
