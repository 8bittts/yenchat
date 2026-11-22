import AppKit
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct RemotePanesTests {
    // Live terminal controllers spawn their command; retain them for the
    // serialized suite (see TerminalRestorableVersionTests).
    private static var retainedControllers: [TerminalController] = []

    /// `/usr/bin/true` stands in for the bundled CLI so no test pane runs ssh.
    private static let fakeCLI = "/usr/bin/true"
    private let sessionID = UUID(uuidString: "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C")!

    private var identity: RemotePaneIdentity {
        RemotePaneIdentity(displayName: "Studio", sshTarget: "studio.example.invalid", sessionID: sessionID)!
    }

    private var expectedCommand: String {
        "'\(Self.fakeCLI)' 'sessions' 'attach' '--host' 'studio.example.invalid' '\(sessionID.uuidString)'"
    }

    private func markedConfig(_ identity: RemotePaneIdentity) -> YEN.SurfaceConfiguration {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[RemotePanes.markerEnvironmentKey] = RemotePanes.marker(for: identity)
        return config
    }

    private func withFakeCLI<T>(_ body: () throws -> T) rethrows -> T {
        RemotePanes._testSetCLIPath(Self.fakeCLI)
        defer { RemotePanes._testSetCLIPath(nil) }
        return try body()
    }

    // MARK: Identity

    @Test func identityRefusesAnInvalidTargetAndCapsItsLabel() throws {
        #expect(RemotePaneIdentity(displayName: "x", sshTarget: "-oProxyCommand=sh", sessionID: sessionID) == nil)
        #expect(RemotePaneIdentity(displayName: "x", sshTarget: "host name", sessionID: sessionID) == nil)

        let hostile = try #require(RemotePaneIdentity(
            displayName: "evil\u{1B}]0;pwned\u{07}\nname\u{200B}" + String(repeating: "w", count: 100),
            sshTarget: "evil.example.invalid",
            sessionID: sessionID
        ))
        #expect(hostile.displayName.count == RemotePaneIdentity.maxDisplayNameLength)
        #expect(hostile.displayName.unicodeScalars.allSatisfy { $0.properties.generalCategory != .control && $0.properties.generalCategory != .format })

        let unnamed = try #require(RemotePaneIdentity(displayName: "\u{07}", sshTarget: "mini.example.invalid", sessionID: sessionID))
        #expect(unnamed.displayName == "mini")
    }

    @Test func savedIdentitiesDropOnlyTheEntriesThatFailValidation() throws {
        let json = """
        {"\(UUID().uuidString)": {"displayName": "Studio", "sshTarget": "studio.example.invalid", "sessionID": "\(sessionID.uuidString)"},
         "\(UUID().uuidString)": {"displayName": "Bad", "sshTarget": "-oProxyCommand=sh", "sessionID": "\(sessionID.uuidString)"},
         "\(UUID().uuidString)": {"displayName": "Broken"}}
        """
        let decoded = try JSONDecoder().decode(RemotePanes.SavedIdentities.self, from: Data(json.utf8))
        #expect(Array(decoded.entries.values) == [identity])
    }

    // MARK: Pane creation

    @Test func aMarkedPaneGetsTheAttachCommandAndIsRecorded() {
        let paneID = UUID()
        var config = markedConfig(identity)
        withFakeCLI { RemotePanes.prepare(&config, paneID: paneID) }

        #expect(config.command == expectedCommand)
        #expect(config.waitAfterCommand)
        #expect(config.environmentVariables[RemotePanes.markerEnvironmentKey] == nil)
        #expect(RemotePanes.identity(for: paneID) == identity)
    }

    @Test func aMarkerNeverReachesAPaneThatHasItsOwnCommand() {
        let paneID = UUID()
        var config = markedConfig(identity)
        config.command = "/bin/echo local"
        withFakeCLI { RemotePanes.prepare(&config, paneID: paneID) }

        #expect(config.command == "/bin/echo local")
        #expect(config.environmentVariables[RemotePanes.markerEnvironmentKey] == nil)
        #expect(RemotePanes.identity(for: paneID) == nil)
    }

    @Test func anInvalidOrInheritedMarkerLeavesALocalPane() {
        let paneID = UUID()
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[RemotePanes.markerEnvironmentKey] = #"{"displayName":"x","sshTarget":"-oProxyCommand=sh","sessionID":"\#(sessionID.uuidString)"}"#
        withFakeCLI { RemotePanes.prepare(&config, paneID: paneID) }

        #expect(config.command == nil)
        #expect(config.environmentVariables[RemotePanes.markerEnvironmentKey] == nil)
        #expect(RemotePanes.identity(for: paneID) == nil)
    }

    @Test func persistentSessionsLeaveARemotePaneEphemeral() {
        let paneID = UUID()
        var config = markedConfig(identity)
        withFakeCLI {
            PersistentSessions.prepare(
                &config, paneID: paneID, enabled: true, zmxAvailable: true,
                socketDirectory: "/tmp/yen-remote-test", resolveBinary: { _, _ in "/z/zmx" }, recordOwner: { _, _ in Issue.record("a remote pane must not claim a local session") }
            )
        }

        #expect(config.command == expectedCommand)
        #expect(config.environmentVariables[PersistentSessions.environmentKey] == nil)
        #expect(RemotePanes.identity(for: paneID) == identity)
    }

    @Test func restoreIdentitiesApplyOnlyWhileTheirTreeDecodes() {
        let paneID = UUID()
        var during = YEN.SurfaceConfiguration()
        withFakeCLI {
            RemotePanes.decodingTree(restoring: [paneID.uuidString: identity]) {
                RemotePanes.prepare(&during, paneID: paneID)
            }
        }
        #expect(during.command == expectedCommand)
        #expect(RemotePanes.identity(for: paneID) == identity)

        // The same pane UUID created later is a new local pane.
        var after = YEN.SurfaceConfiguration()
        withFakeCLI { RemotePanes.prepare(&after, paneID: paneID) }
        #expect(after.command == nil)
        #expect(RemotePanes.identity(for: paneID) == nil)
    }

    @Test func quittingNeedsNoConfirmationForARemotePane() {
        let paneID = UUID()
        var config = markedConfig(identity)
        withFakeCLI { RemotePanes.prepare(&config, paneID: paneID) }
        #expect(!PersistentSessions.quitKillsProcess(needsConfirmQuit: true, paneID: paneID, hasSession: { _ in false }))
        #expect(PersistentSessions.quitKillsProcess(needsConfirmQuit: true, paneID: UUID(), hasSession: { _ in false }))
    }

    // MARK: Labels

    @Test func tabTitlesLeadWithTheHostOnce() {
        #expect(RemotePanes.tabTitle("~/src", host: "Studio") == "Studio · ~/src")
        #expect(RemotePanes.tabTitle("", host: "Studio") == "Studio")
        #expect(RemotePanes.tabTitle("YEN", host: "Studio") == "Studio")
        #expect(RemotePanes.tabTitle("Studio · vim", host: "Studio") == "Studio · vim")
        #expect(RemotePanes.tabTitle("Build Logs", host: "Studio") == "Studio · Build Logs")
    }

    @Test func splitHeadersNameTheHostInsteadOfTheLocalDirectory() {
        #expect(SplitPaneLabelRules.secondaryText(remoteHost: "Studio", workingDirectory: "/Users/dev/local") == "Studio")
        #expect(SplitPaneLabelRules.secondaryText(remoteHost: nil, workingDirectory: nil) == nil)
        #expect(SplitPaneLabelRules.accessibilityLabel(title: "vim", remoteHost: "Studio") == "Focus pane: vim, on Studio")
        #expect(SplitPaneLabelRules.accessibilityLabel(title: "vim", remoteHost: nil) == "Focus pane: vim")
    }

    @Test func remotePanesShowTheSSHActivity() throws {
        let controller = try makeController(with: markedConfig(identity))
        let surface = try #require(controller.surfaceTree.first)
        #expect(PaneActivity.current(surface) == .ssh)
        #expect(RemotePanes.tabTitle("~", for: surface) == "Studio · ~")
    }

    // MARK: Windows

    @Test func aRemoteTabTitleAndItsJumpRowNameTheHost() throws {
        let controller = try makeController(with: markedConfig(identity))
        let surface = try #require(controller.surfaceTree.first)
        #expect(surface.remotePaneIdentity == identity)

        let rows = TerminalCommandPaletteView.loadJumpTargetSnapshots(controllers: [controller])
        #expect(rows.first?.title.hasPrefix("Studio") == true)
        #expect(rows.first?.subtitle == nil)
    }

    @Test func openingAnAttachedSessionFindsTheExistingPane() throws {
        let controller = try makeController(with: markedConfig(identity))
        let surface = try #require(controller.surfaceTree.first)
        let other = try #require(RemotePaneIdentity(displayName: "Elsewhere", sshTarget: "STUDIO.example.invalid", sessionID: sessionID))

        #expect(RemotePanes.existingPane(for: other, in: [controller]) === surface)
        let unrelated = try #require(RemotePaneIdentity(displayName: "Studio", sshTarget: "studio.example.invalid", sessionID: UUID()))
        #expect(RemotePanes.existingPane(for: unrelated, in: [controller]) == nil)
    }

    @Test func windowRestoreReattachesRemotePanesAndKeepsLocalPanesLocal() throws {
        let remote = try makeController(with: markedConfig(identity))
        let remoteSurface = try #require(remote.surfaceTree.first)
        #expect(remote.window?.isRestorable == true)
        let local = try makeController(with: nil)
        let localSurface = try #require(local.surfaceTree.first)

        let remoteState = try #require(decodeRestored(TerminalRestorableState(from: remote)))
        let restoredRemote = try #require(remoteState.surfaceTree.first)
        #expect(restoredRemote !== remoteSurface)
        #expect(restoredRemote.id == remoteSurface.id)
        #expect(restoredRemote.remotePaneIdentity == identity)
        #expect(remoteState.remotePanes?.entries == [remoteSurface.id.uuidString: identity])

        let localState = try #require(decodeRestored(TerminalRestorableState(from: local)))
        #expect(localState.remotePanes == nil)
        #expect(localState.surfaceTree.first?.id == localSurface.id)
        #expect(localState.surfaceTree.first?.remotePaneIdentity == nil)
    }

    @Test func quickTerminalRestoreReattachesRemotePanes() throws {
        let remote = try makeController(with: markedConfig(identity))
        let remoteSurface = try #require(remote.surfaceTree.first)
        let payload = QuickTerminalRestorableState(
            focusedSurface: nil,
            surfaceTree: remote.surfaceTree,
            screenStateEntries: [:],
            remotePanes: RemotePanes.snapshot(for: remote.surfaceTree).map(RemotePanes.SavedIdentities.init)
        )
        let restored = try #require(decodeRestored(payload))
        #expect(restored.surfaceTree.first?.id == remoteSurface.id)
        #expect(restored.surfaceTree.first?.remotePaneIdentity == identity)
    }

    // MARK: Helpers

    private func makeController(with config: YEN.SurfaceConfiguration?) throws -> TerminalController {
        let appDelegate = try #require(NSApp.delegate as? AppDelegate, "Expected AppDelegate-backed test host.")
        let controller = withFakeCLI { TerminalController(appDelegate.yen, withBaseConfig: config) }
        Self.retainedControllers.append(controller)
        return controller
    }

    /// Archive and restore the way AppKit window restoration does, with the
    /// fake CLI so restored remote panes never run ssh.
    private func decodeRestored<Restorable: TerminalRestorable>(_ payload: Restorable) -> Restorable? {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(Restorable.version, forKey: Restorable.versionKey)
        archiver.encode(CodableBridge(payload), forKey: Restorable.selfKey)
        archiver.finishEncoding()
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else { return nil }
        defer { unarchiver.finishDecoding() }
        unarchiver.requiresSecureCoding = true
        return withFakeCLI { Restorable(coder: unarchiver) }
    }
}
