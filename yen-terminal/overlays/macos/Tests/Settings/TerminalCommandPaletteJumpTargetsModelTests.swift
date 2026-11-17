import AppKit
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct TerminalCommandPaletteJumpTargetsModelTests {
    @Test func idlePaletteDoesNotPollTwicePerSecond() async throws {
        var loads = 0
        let model = TerminalCommandPaletteJumpTargetsModel(loadSnapshots: { loads += 1; return [] },
            notificationCenter: NotificationCenter())
        model.start()
        defer { model.stop() }
        try await Task.sleep(for: .milliseconds(900))
        #expect(loads == 1)
    }

    @Test func stopDiscardsAlreadyQueuedNotificationRefreshes() {
        let center = TestNotificationObserverCenter()
        var loads = 0
        var queued: [@MainActor () -> Void] = []
        let model = TerminalCommandPaletteJumpTargetsModel(loadSnapshots: { loads += 1; return [] },
            registerObserver: center.addObserver(forName:handler:), removeObserver: center.removeObserver(_:),
            scheduleRefresh: { queued.append($0) }, refreshInterval: nil)
        model.start()
        center.post(name: NSWindow.didBecomeKeyNotification)
        #expect(queued.count == 1)
        model.stop()
        queued.forEach { $0() }
        #expect(loads == 1)
    }

    @Test func restartedModelIgnoresCallbacksFromThePreviousSession() async throws {
        let center = TestNotificationObserverCenter()
        var loads = 0
        var queued: [@MainActor () -> Void] = []
        let model = TerminalCommandPaletteJumpTargetsModel(loadSnapshots: { loads += 1; return [] },
            registerObserver: center.addObserver(forName:handler:), removeObserver: center.removeObserver(_:),
            scheduleRefresh: { queued.append($0) }, refreshInterval: nil)
        model.start()
        center.post(name: NSWindow.didBecomeKeyNotification)
        model.stop()
        model.start()
        defer { model.stop() }
        queued.forEach { $0() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(loads == 2)
    }

    @Test func surfaceTitleAndDirectoryChangesRefreshWithoutPollingAndStopDetaches() async throws {
        let app = try #require(NSApp.delegate as? AppDelegate)
        var config = YEN.SurfaceConfiguration()
        config.command = "/bin/sleep 60"
        config.workingDirectory = FileManager.default.temporaryDirectory.path
        let controller = TerminalController(app.yen, withBaseConfig: config)
        defer { controller.window?.close() }
        let surface = try #require(controller.surfaceTree.first)
        surface.titleOverride = "Initial title"
        // Finish initial window setup before measuring observation-driven refreshes.
        try await Task.sleep(for: .milliseconds(600))
        var loads = 0
        let model = TerminalCommandPaletteJumpTargetsModel(loadSnapshots: {
            loads += 1
            return TerminalCommandPaletteView.loadJumpTargetSnapshots(controllers: [controller])
        }, notificationCenter: NotificationCenter(), refreshInterval: nil)
        model.start()
        defer { model.stop() }
        surface.titleOverride = "Updated title"
        surface.pwd = "/tmp/palette-updated-directory"
        await waitForLoadCount(expected: 2) { loads }
        #expect(model.snapshots.first?.title == "Updated title")
        #expect(model.snapshots.first?.subtitle == "/tmp/palette-updated-directory")
        try await Task.sleep(for: .milliseconds(100))
        let beforeBurst = loads
        surface.pwd = "/tmp/first-burst-directory"
        surface.pwd = "/tmp/final-burst-directory"
        await waitForLoadCount(expected: beforeBurst + 1) { loads }
        try await Task.sleep(for: .milliseconds(50))
        #expect(loads == beforeBurst + 1)
        #expect(model.snapshots.first?.subtitle == "/tmp/final-burst-directory")
        let afterRefresh = loads
        model.stop()
        surface.titleOverride = "After stop"
        surface.pwd = "/tmp/after-stop"
        try await Task.sleep(for: .milliseconds(100))
        #expect(loads == afterRefresh)
        #expect(model.snapshots.isEmpty)
    }

    @Test func startIsIdempotentAndRefreshRemainsExplicit() {
        var loadCount = 0
        let model = TerminalCommandPaletteJumpTargetsModel(
            loadSnapshots: {
                loadCount += 1
                return []
            },
            notificationCenter: NotificationCenter(),
            refreshInterval: nil
        )

        model.start()
        model.start()
        #expect(loadCount == 1)

        model.refresh()
        #expect(loadCount == 2)
    }

    @Test func notificationsRefreshActiveModelAndStopRemovesObservers() async {
        let center = TestNotificationObserverCenter()
        var loadCount = 0
        let model = TerminalCommandPaletteJumpTargetsModel(
            loadSnapshots: {
                loadCount += 1
                return []
            },
            registerObserver: center.addObserver(forName:handler:),
            removeObserver: center.removeObserver(_:),
            scheduleRefresh: { action in
                MainActor.assumeIsolated {
                    action()
                }
            },
            refreshInterval: nil
        )

        model.start()
        #expect(loadCount == 1)

        center.post(name: NSWindow.didBecomeKeyNotification)
        await waitForLoadCount(expected: 2) { loadCount }
        #expect(loadCount == 2)

        center.post(name: .yenTabSidebarStateDidChange)
        await waitForLoadCount(expected: 3) { loadCount }
        #expect(loadCount == 3)

        model.stop()
        center.post(name: NSWindow.didBecomeKeyNotification)
        center.post(name: .yenTabSidebarStateDidChange)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(loadCount == 3)
    }

    @MainActor
    private final class TestNotificationObserverCenter {
        final class Token: NSObject {
            let name: Notification.Name

            init(name: Notification.Name) {
                self.name = name
            }
        }

        private var handlers: [ObjectIdentifier: (name: Notification.Name, handler: () -> Void)] = [:]

        func addObserver(
            forName name: Notification.Name,
            handler: @escaping () -> Void
        ) -> NSObjectProtocol {
            let token = Token(name: name)
            handlers[ObjectIdentifier(token)] = (name, handler)
            return token
        }

        func removeObserver(_ observer: NSObjectProtocol) {
            guard let token = observer as? Token else { return }
            handlers.removeValue(forKey: ObjectIdentifier(token))
        }

        func post(name: Notification.Name) {
            for entry in handlers.values where entry.name == name {
                entry.handler()
            }
        }
    }

    private func waitForLoadCount(
        expected: Int,
        timeout: TimeInterval = 0.3,
        currentLoadCount: @escaping @MainActor () -> Int
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while currentLoadCount() < expected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
