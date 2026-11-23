import AppKit
import Foundation
import SwiftUI
import Testing
@testable import YEN

struct SessionStateTests {
    private let studio = RemotePaneIdentity(displayName: "Studio", sshTarget: "studio.example.invalid", sessionID: UUID())!
    private let mini = RemotePaneIdentity(displayName: "Mini", sshTarget: "mini.example.invalid", sessionID: UUID())!
    private let air = RemotePaneIdentity(displayName: "Air", sshTarget: "air.example.invalid", sessionID: UUID())!

    @Test func aTabIsLiveOnlyWhenEveryPaneIs() {
        #expect(TabSessionState.of([]) == nil)
        #expect(TabSessionState.of([.local]) == nil)
        #expect(TabSessionState.of([.live]) == .live)
        #expect(TabSessionState.of([.live, .live]) == .live)
        // A mixed tab does not keep running as a whole.
        #expect(TabSessionState.of([.live, .local]) == nil)
    }

    @Test func anyRemotePaneMakesTheTabRemote() {
        #expect(TabSessionState.of([.remote(studio)]) == .remote(hosts: ["Studio"]))
        #expect(TabSessionState.of([.local, .remote(studio)]) == .remote(hosts: ["Studio"]))
        #expect(TabSessionState.of([.live, .remote(studio), .remote(mini), .remote(studio)]) == .remote(hosts: ["Studio", "Mini"]))
    }

    @Test func eachStateHasASymbolAndALabel() {
        #expect(TabSessionState.live.symbolName == "rectangle.stack")
        #expect(TabSessionState.live.label == "Live session: keeps running when YEN quits")
        #expect(TabSessionState.remote(hosts: ["Studio"]).symbolName == "network")
        #expect(TabSessionState.remote(hosts: ["Studio"]).label == "Remote session on Studio")
        #expect(TabSessionState.remote(hosts: ["Studio", "Mini"]).label == "Remote sessions on Studio and Mini")
        #expect(TabSessionState.remote(hosts: ["Studio", "Mini", "Air"]).label == "Remote sessions on Studio, Mini and Air")
    }

    @Test func paneStatesComeFromTheRecordsMadeAtCreation() {
        let live = UUID(), ephemeral = UUID(), remote = UUID()
        var liveConfig = YEN.SurfaceConfiguration()
        PersistentSessions.prepare(
            &liveConfig, paneID: live, enabled: true, zmxAvailable: true,
            socketDirectory: "/tmp/yss", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        var commandConfig = YEN.SurfaceConfiguration()
        commandConfig.command = "/bin/echo"
        PersistentSessions.prepare(
            &commandConfig, paneID: ephemeral, enabled: true, zmxAvailable: true,
            socketDirectory: "/tmp/yss", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        var remoteConfig = YEN.SurfaceConfiguration()
        remoteConfig.environmentVariables[RemotePanes.markerEnvironmentKey] = RemotePanes.marker(for: studio)
        RemotePanes._testSetCLIPath("/usr/bin/true")
        PersistentSessions.prepare(
            &remoteConfig, paneID: remote, enabled: true, zmxAvailable: true,
            socketDirectory: "/tmp/yss", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        RemotePanes._testSetCLIPath(nil)

        #expect(PaneSessionState.of(paneID: live) == .live)
        #expect(PaneSessionState.of(paneID: ephemeral) == .local)
        #expect(PaneSessionState.of(paneID: remote) == .remote(studio))
        #expect(TabSessionState.of(paneIDs: [live, remote]) == .remote(hosts: ["Studio"]))
        #expect(TabSessionState.of(paneIDs: [live, ephemeral]) == nil)

        // Created again as an ordinary pane, the same UUID is no longer live.
        var again = YEN.SurfaceConfiguration()
        PersistentSessions.prepare(
            &again, paneID: live, enabled: false, zmxAvailable: true,
            socketDirectory: "/tmp/yss-none", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        #expect(PaneSessionState.of(paneID: live) == .local)
    }

    @Test @MainActor func aSidebarRowReadsTheStateAloud() {
        let window = NSWindow()
        let item = TabSidebarItem(
            id: ObjectIdentifier(window), window: window, title: "Studio · ~", shortcut: "1",
            color: .none, isSelected: true, cwdSummary: nil, gitSummary: nil,
            statusSummary: nil, statusTone: .neutral, sessionState: .remote(hosts: ["Studio"])
        )
        let descriptor = TabSidebarRowAccessibilityDescriptor(tab: item, isEditingTitle: false)
        #expect(descriptor.label == "Studio · ~, Remote session on Studio, Command 1")
    }

    // MARK: Reconnecting

    private func report(_ state: YEN.Action.ProgressReport.State, _ progress: UInt8?) -> YEN.Action.ProgressReport {
        YEN.Action.ProgressReport(state: state, progress: progress)
    }

    @Test func onlyTheCLIsPausedAtZeroReportMeansReconnecting() {
        #expect(RemotePanes.isReconnectReport(report(.pause, 0)))
        for other in [report(.pause, nil), report(.pause, 1), report(.pause, 100), report(.indeterminate, nil),
                      report(.set, 0), report(.error, 0), report(.remove, nil)] {
            #expect(!RemotePanes.isReconnectReport(other))
        }
        #expect(!RemotePanes.isReconnectReport(nil))
    }

    @Test func aRemotePaneWithTheReportIsReconnectingAndALocalPaneNeverIs() {
        let remote = UUID(), local = UUID()
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables[RemotePanes.markerEnvironmentKey] = RemotePanes.marker(for: studio)
        RemotePanes._testSetCLIPath("/usr/bin/true")
        PersistentSessions.prepare(
            &config, paneID: remote, enabled: false, zmxAvailable: true,
            socketDirectory: "/tmp/yss", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        RemotePanes._testSetCLIPath(nil)
        // The app asks the pane's CLI for the mark; a local pane gets nothing.
        #expect(config.environmentVariables[RemotePanes.reconnectMarkEnvironmentKey] == "1")
        var localConfig = YEN.SurfaceConfiguration()
        PersistentSessions.prepare(
            &localConfig, paneID: local, enabled: false, zmxAvailable: true,
            socketDirectory: "/tmp/yss", resolveBinary: { _, _ in nil }, recordOwner: { _, _ in }
        )
        #expect(localConfig.environmentVariables[RemotePanes.reconnectMarkEnvironmentKey] == nil)

        #expect(PaneSessionState.of(paneID: remote, report: report(.pause, 0)) == .reconnecting(studio))
        #expect(PaneSessionState.of(paneID: remote, report: report(.indeterminate, nil)) == .remote(studio))
        #expect(PaneSessionState.of(paneID: remote, report: nil) == .remote(studio))
        #expect(PaneSessionState.of(paneID: local, report: report(.pause, 0)) == .local)
    }

    @Test func aTabIsReconnectingWhenAnyRemotePaneIsAndNamesThoseMacs() {
        #expect(TabSessionState.of([.reconnecting(studio)]) == .reconnecting(hosts: ["Studio"]))
        #expect(TabSessionState.of([.live, .reconnecting(studio), .remote(mini)]) == .reconnecting(hosts: ["Studio"]))
        #expect(TabSessionState.of([.reconnecting(studio), .remote(mini), .reconnecting(air), .reconnecting(studio)])
            == .reconnecting(hosts: ["Studio", "Air"]))
        #expect(TabSessionState.of([.remote(studio), .remote(mini)]) == .remote(hosts: ["Studio", "Mini"]))
    }

    @Test func reconnectingHasItsOwnSymbolAndLabel() {
        #expect(TabSessionState.reconnecting(hosts: ["Studio"]).symbolName == "network.slash")
        #expect(TabSessionState.reconnecting(hosts: ["Studio"]).label == "Reconnecting to Studio")
        #expect(TabSessionState.reconnecting(hosts: ["Studio", "Mini"]).label == "Reconnecting to Studio and Mini")
        #expect(TabSessionState.reconnecting(hosts: ["Studio", "Mini", "Air"]).label == "Reconnecting to Studio, Mini and Air")
    }

    @Test func theSidebarShowsTheReconnectingStateNotAPausedTask() {
        #expect(TabSidebarController.terminalStatusSignal(for: report(.pause, 0), isRemote: true) == nil)
        #expect(TabSidebarController.terminalStatusSignal(for: report(.pause, 0), isRemote: false)?.summary == "Task paused")
        #expect(TabSidebarController.terminalStatusSignal(for: report(.pause, 40), isRemote: true)?.summary == "Task paused")
    }
}
