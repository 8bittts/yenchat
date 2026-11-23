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

    @Test @MainActor func theTabAccessoryShowsTheStateAndKeepsItWhenNarrow() {
        let host = PaneTabIconAccessory(rootView: PaneTabSplitCount(count: 1, session: .remote(hosts: ["Studio"])))
        #expect(host.showsSessionMarker)
        host.rootView = PaneTabSplitCount(count: 3)
        #expect(!host.showsSessionMarker)
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
}
