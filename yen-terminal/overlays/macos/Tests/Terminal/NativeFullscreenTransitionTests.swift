import AppKit
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct NativeFullscreenTransitionTests {
    @Test func effectiveFullscreenIncludesTransitionState() {
        let window = FullscreenTestWindow()
        defer { cleanup(window: window) }

        #expect(!window.yenIsEffectivelyFullscreen)

        window.yenNativeFullscreenTransitionPhase = .entering
        #expect(window.yenIsEffectivelyFullscreen)

        window.yenNativeFullscreenTransitionPhase = .none
        #expect(!window.yenIsEffectivelyFullscreen)

        window.yenTestingSettledFullscreen = true
        #expect(window.yenIsEffectivelyFullscreen)
    }

    @Test func coordinatorIgnoresReentrantNativeToggleWhileEntering() {
        let window = FullscreenTestWindow()
        defer { cleanup(window: window) }

        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)
        #expect(window.yenNativeFullscreenTransitionPhase == .entering)

        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)

        NativeFullscreenTransitionCoordinator.setPhase(
            .entering,
            boundary: "windowWillEnterFullScreen",
            window: window
        )
        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)

        setSettledNativeFullscreen(true, for: window)
        NativeFullscreenTransitionCoordinator.setPhase(
            .none,
            boundary: "windowDidEnterFullScreen",
            window: window
        )
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 2)
    }

    @Test func coordinatorIgnoresReentrantNativeToggleWhileExiting() {
        let window = FullscreenTestWindow()
        defer { cleanup(window: window) }
        window.yenTestingSettledFullscreen = true

        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)
        #expect(window.yenNativeFullscreenTransitionPhase == .exiting)

        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)

        NativeFullscreenTransitionCoordinator.setPhase(
            .exiting,
            boundary: "windowWillExitFullScreen",
            window: window
        )
        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 1)

        window.yenTestingSettledFullscreen = false
        NativeFullscreenTransitionCoordinator.setPhase(
            .none,
            boundary: "windowDidExitFullScreen",
            window: window
        )
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        issueNativeToggleRequest(window)
        #expect(window.toggleFullscreenCallCount == 2)
    }

    @Test func failureCallbacksClearInFlightTransitionState() {
        let window = FullscreenTestWindow()
        defer { cleanup(window: window) }

        issueNativeToggleRequest(window)
        #expect(window.yenNativeFullscreenTransitionPhase == .entering)
        #expect(window.yenIsEffectivelyFullscreen)

        NativeFullscreenTransitionCoordinator.setPhase(
            .none,
            boundary: "windowDidFailToEnterFullScreen",
            window: window
        )
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(!window.yenIsEffectivelyFullscreen)

        setSettledNativeFullscreen(true, for: window)
        issueNativeToggleRequest(window)
        #expect(window.yenNativeFullscreenTransitionPhase == .exiting)
        #expect(window.yenIsEffectivelyFullscreen)

        setSettledNativeFullscreen(true, for: window)
        NativeFullscreenTransitionCoordinator.setPhase(
            .none,
            boundary: "windowDidFailToExitFullScreen",
            window: window
        )
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(window.yenIsEffectivelyFullscreen)
    }

    @Test func failureCallbacksRestoreTitlebarSeparatorToSettledState() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let window = FullscreenTestWindow()
        retain(controller: controller)
        defer { cleanup(window: window) }
        controller.window = window

        window.titlebarSeparatorStyle = .none
        NativeFullscreenTransitionCoordinator.setPhase(
            .entering,
            boundary: "testWillEnterFailure",
            window: window
        )
        controller.windowDidFailToEnterFullScreen(window)
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(window.titlebarSeparatorStyle == .automatic)

        setSettledNativeFullscreen(true, for: window)
        window.titlebarSeparatorStyle = .automatic
        NativeFullscreenTransitionCoordinator.setPhase(
            .exiting,
            boundary: "testWillExitFailure",
            window: window
        )
        controller.windowDidFailToExitFullScreen(window)
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(window.titlebarSeparatorStyle == .none)
    }

    @Test func toggleFullscreenNotificationHandlingStaysSingleShotAcrossEnterTransitionAndExitInFlightState() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let window = FullscreenTestWindow()
        retain(controller: controller)
        defer { cleanup(window: window) }
        controller.window = window
        controller.focusedSurface = controller.surfaceTree.first
        let surface = try #require(controller.focusedSurface)
        let notification = makeToggleFullscreenNotification(for: surface)

        controller.handleToggleFullscreenNotification(notification)
        #expect(window.toggleFullscreenCallCount == 1)
        #expect(window.yenNativeFullscreenTransitionPhase == .entering)

        controller.handleToggleFullscreenNotification(notification)
        #expect(window.toggleFullscreenCallCount == 1)

        controller.windowWillEnterFullScreen(
            Notification(name: NSWindow.willEnterFullScreenNotification, object: window)
        )
        controller.handleToggleFullscreenNotification(notification)
        #expect(window.toggleFullscreenCallCount == 1)

        controller.windowDidFailToEnterFullScreen(window)
        controller.handleToggleFullscreenNotification(notification)
        #expect(window.toggleFullscreenCallCount == 2)
        #expect(window.yenNativeFullscreenTransitionPhase == .entering)

        controller.windowWillEnterFullScreen(
            Notification(name: NSWindow.willEnterFullScreenNotification, object: window)
        )
        setSettledNativeFullscreen(true, for: window)
        controller.windowDidEnterFullScreen(
            Notification(name: NSWindow.didEnterFullScreenNotification, object: window)
        )
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(window.yenIsEffectivelyFullscreen)

        NativeFullscreenTransitionCoordinator.setPhase(
            .exiting,
            boundary: "testSyntheticExitInFlight",
            window: window
        )
        controller.handleToggleFullscreenNotification(notification)
        #expect(window.yenNativeFullscreenTransitionPhase == .exiting)
        #expect(window.toggleFullscreenCallCount == 2)

        controller.handleToggleFullscreenNotification(notification)
        #expect(window.yenNativeFullscreenTransitionPhase == .exiting)

        controller.windowDidFailToExitFullScreen(window)
        #expect(window.yenNativeFullscreenTransitionPhase == .none)
        #expect(window.yenIsEffectivelyFullscreen)
    }

    // CSI 8 t (`vt-window-resize-allowed`) reaches `resizeWindow`, whose upstream
    // guard checks only `fullscreenStyle?.isFullscreen`. During a native
    // transition the style mask has no `.fullScreen` yet, so without the YEN
    // guard a program could resize the window mid-animation.
    @Test func resizeWindowRefusesWhileNativeFullscreenIsInFlight() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let window = FullscreenTestWindow()
        retain(controller: controller)
        defer { cleanup(window: window) }
        controller.window = window
        let surface = try #require(controller.surfaceTree.first)
        let size = NSSize(width: 640, height: 400)

        NativeFullscreenTransitionCoordinator.setPhase(
            .entering,
            boundary: "testResizeWhileEntering",
            window: window
        )
        let frameBeforeResize = window.frame
        #expect(!controller.resizeWindow(surface, to: size))
        #expect(window.frame == frameBeforeResize)

        NativeFullscreenTransitionCoordinator.setPhase(
            .none,
            boundary: "testResizeAfterFailedEnter",
            window: window
        )
        setSettledNativeFullscreen(true, for: window)
        #expect(!controller.resizeWindow(surface, to: size))

        // Positive control: every other guard condition holds, so the refusals
        // above come from the fullscreen state alone.
        setSettledNativeFullscreen(false, for: window)
        #expect(controller.resizeWindow(surface, to: size))
    }

    private func requireAppDelegate() throws -> AppDelegate {
        try #require(NSApp.delegate as? AppDelegate)
    }

    private func cleanup(window: NSWindow) {
        window.yenNativeFullscreenTransitionPhase = .none
        setSettledNativeFullscreen(false, for: window)
        window.contentView = nil
        window.orderOut(nil)
    }

    private func retain(controller: BaseTerminalController) {
        retainedFullscreenTestControllers.append(controller)
    }

    private func issueNativeToggleRequest(_ window: FullscreenTestWindow) {
        if !NativeFullscreenTransitionCoordinator.shouldIgnoreToggleRequest(mode: .native, window: window) {
            NativeFullscreenTransitionCoordinator.logToggleRequest(mode: .native, window: window)
            if window.yenIsEffectivelyFullscreen {
                NativeFullscreenTransitionCoordinator.setPhase(
                    .exiting,
                    boundary: "testToggleRequest",
                    window: window
                )
            } else {
                NativeFullscreenTransitionCoordinator.setPhase(
                    .entering,
                    boundary: "testToggleRequest",
                    window: window
                )
            }
            window.toggleFullScreen(nil)
        }
    }

    private func makeToggleFullscreenNotification(for surface: YEN.SurfaceView) -> Notification {
        Notification(
            name: YEN.Notification.yenToggleFullscreen,
            object: surface,
            userInfo: [YEN.Notification.FullscreenModeKey: FullscreenMode.native]
        )
    }

    private func setSettledNativeFullscreen(_ isFullscreen: Bool, for window: NSWindow) {
        window.yenTestingSettledFullscreen = isFullscreen
        if let window = window as? FullscreenTestWindow {
            window.testingSettledNativeFullscreen = isFullscreen
        }
    }
}

@MainActor
private var retainedFullscreenTestControllers: [BaseTerminalController] = []

private final class FullscreenTestWindow: NSWindow {
    var toggleFullscreenCallCount = 0
    var testingSettledNativeFullscreen = false

    override var styleMask: NSWindow.StyleMask {
        get {
            var mask = super.styleMask
            if testingSettledNativeFullscreen {
                mask.insert(.fullScreen)
            }
            return mask
        }
        set {
            super.styleMask = newValue
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override func toggleFullScreen(_ sender: Any?) {
        toggleFullscreenCallCount += 1
    }
}
