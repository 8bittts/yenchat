import AppKit
import CoreGraphics
import Combine
import SwiftUI
import Testing
@testable import YEN

struct WindowBorderRenderingPolicyTests {
    @MainActor
    @Test func focusedFrameEventsIgnoreOtherViewsAndWindows() {
        let center = NotificationCenter()
        let surface = NSView()
        let unrelatedSurface = NSView()
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        let unrelatedWindow = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        unrelatedWindow.isReleasedWhenClosed = false
        defer { window.close(); unrelatedWindow.close() }
        var received = 0
        let subscription = TerminalFrameEvents.publisher(enabled: true, surface: surface, window: window, center: center)
            .sink { received += 1 }
        for _ in 0..<100 {
            center.post(name: NSView.frameDidChangeNotification, object: unrelatedSurface)
            center.post(name: NSWindow.didResizeNotification, object: unrelatedWindow)
            center.post(name: NSWindow.didMoveNotification, object: unrelatedWindow)
        }
        #expect(received == 0)
        center.post(name: NSView.frameDidChangeNotification, object: surface)
        center.post(name: NSWindow.didResizeNotification, object: window)
        center.post(name: NSWindow.didMoveNotification, object: window)
        #expect(received == 3)
        subscription.cancel()
        center.post(name: NSView.frameDidChangeNotification, object: surface)
        #expect(received == 3)
    }

    @MainActor
    @Test func disabledAndUnboundFrameEventsNeverObserveGlobalNotifications() {
        let center = NotificationCenter()
        let surface = NSView()
        var received = 0
        let disabled = TerminalFrameEvents.publisher(enabled: false, surface: surface, window: nil, center: center)
            .sink { received += 1 }
        let unbound = TerminalFrameEvents.publisher(enabled: true, surface: nil, window: nil, center: center)
            .sink { received += 1 }
        center.post(name: NSView.frameDidChangeNotification, object: surface)
        center.post(name: NSView.frameDidChangeNotification, object: nil)
        center.post(name: NSWindow.didResizeNotification, object: nil)
        center.post(name: NSWindow.didMoveNotification, object: nil)
        #expect(received == 0)
        disabled.cancel()
        unbound.cancel()
    }

    @MainActor
    @Test func windowReferenceReaderEmitsLifecycleMetricsWithoutUpdateWriteFallback() {
        let metrics = WindowReferenceReaderTesting.metricsForLifecycleEvents()

        #expect(metrics.contains { $0.hasWindow && $0.frameInWindow == CGRect(x: 20, y: 30, width: 120, height: 80) })
        #expect(metrics.contains { $0.hasWindow && $0.frameInWindow == CGRect(x: 20, y: 30, width: 140, height: 90) })
        #expect(metrics.filter { $0.hasWindow && $0.frameInWindow.size == CGSize(width: 140, height: 90) }.count >= 2)
        #expect(metrics.last == WindowReferenceReaderMetric(hasWindow: false, frameInWindow: .zero))
    }

    @Test func chromeModeResolvesKnownTitlebarStyles() {
        #expect(WindowBorderChromeMode.allCases == [
            .native,
            .transparent,
            .tabs,
            .hidden,
            .decorationNone,
        ])
        #expect(
            WindowBorderRenderingPolicy.chromeMode(titlebarStyle: .native, hasWindowDecorations: true)
                == .native
        )
        #expect(
            WindowBorderRenderingPolicy.chromeMode(titlebarStyle: .transparent, hasWindowDecorations: true)
                == .transparent
        )
        #expect(
            WindowBorderRenderingPolicy.chromeMode(titlebarStyle: .tabs, hasWindowDecorations: true)
                == .tabs
        )
        #expect(
            WindowBorderRenderingPolicy.chromeMode(titlebarStyle: .hidden, hasWindowDecorations: true)
                == .hidden
        )
    }

    @Test func chromeModeUsesDecorationNoneWhenWindowDecorationsAreDisabled() {
        #expect(
            WindowBorderRenderingPolicy.chromeMode(titlebarStyle: .tabs, hasWindowDecorations: false)
                == .decorationNone
        )
    }

    @Test func shouldShowBorderHonorsWindowStateGates() {
        #expect(
            WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: true,
                hasHostingWindow: true,
                isFullscreen: false,
                isPanelWindow: false,
                isQuickTerminalWindow: false
            )
        )

        #expect(
            !WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: false,
                hasHostingWindow: true,
                isFullscreen: false,
                isPanelWindow: false,
                isQuickTerminalWindow: false
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: true,
                hasHostingWindow: false,
                isFullscreen: false,
                isPanelWindow: false,
                isQuickTerminalWindow: false
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: true,
                hasHostingWindow: true,
                isFullscreen: true,
                isPanelWindow: false,
                isQuickTerminalWindow: false
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: true,
                hasHostingWindow: true,
                isFullscreen: false,
                isPanelWindow: true,
                isQuickTerminalWindow: false
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldShowBorder(
                enabled: true,
                hasHostingWindow: true,
                isFullscreen: false,
                isPanelWindow: false,
                isQuickTerminalWindow: true
            )
        )
    }

    @Test func shouldIgnoreTopSafeAreaTracksHiddenTitlebarStyle() {
        #expect(WindowBorderRenderingPolicy.shouldIgnoreTopSafeArea(titlebarStyle: .hidden))
        #expect(!WindowBorderRenderingPolicy.shouldIgnoreTopSafeArea(titlebarStyle: .tabs))
    }

    @Test func isWindowFocusedRequiresActiveAppAndFocusedWindowRole() {
        #expect(
            WindowBorderRenderingPolicy.isWindowFocused(
                windowIsKey: true,
                windowIsMain: false,
                appIsActive: true
            )
        )
        #expect(
            WindowBorderRenderingPolicy.isWindowFocused(
                windowIsKey: false,
                windowIsMain: true,
                appIsActive: true
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.isWindowFocused(
                windowIsKey: false,
                windowIsMain: false,
                appIsActive: true
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.isWindowFocused(
                windowIsKey: false,
                windowIsMain: true,
                appIsActive: false
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.isWindowFocused(
                windowIsKey: true,
                windowIsMain: false,
                appIsActive: false
            )
        )
    }

    @Test func shouldHandleWindowNotificationAcceptsTrackedWindowFallbackForTabTransitions() {
        #expect(
            WindowBorderRenderingPolicy.shouldHandleWindowNotification(
                observedWindowNumber: 22,
                hostingWindowNumber: 11,
                activeSurfaceWindowNumber: 33,
                trackedWindowNumber: 22
            )
        )
        #expect(
            WindowBorderRenderingPolicy.shouldHandleWindowNotification(
                observedWindowNumber: 33,
                hostingWindowNumber: 11,
                activeSurfaceWindowNumber: 33,
                trackedWindowNumber: 22
            )
        )
        #expect(
            WindowBorderRenderingPolicy.shouldHandleWindowNotification(
                observedWindowNumber: 11,
                hostingWindowNumber: 11,
                activeSurfaceWindowNumber: nil,
                trackedWindowNumber: nil
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldHandleWindowNotification(
                observedWindowNumber: 44,
                hostingWindowNumber: 11,
                activeSurfaceWindowNumber: 33,
                trackedWindowNumber: 22
            )
        )
    }

    @Test func focusedSplitBorderFrameFlipsWindowYCoordinates() {
        let terminalFrameInWindow = CGRect(x: 100, y: 200, width: 900, height: 600)
        let topPaneFrameInWindow = CGRect(x: 400, y: 500, width: 300, height: 300)
        let bottomPaneFrameInWindow = CGRect(x: 400, y: 200, width: 300, height: 300)

        guard let topLocal = WindowBorderRenderingPolicy.focusedSplitBorderFrame(
            surfaceFrameInWindow: topPaneFrameInWindow,
            terminalFrameInWindow: terminalFrameInWindow
        ) else {
            Issue.record("Expected a valid local frame for top pane")
            return
        }
        guard let bottomLocal = WindowBorderRenderingPolicy.focusedSplitBorderFrame(
            surfaceFrameInWindow: bottomPaneFrameInWindow,
            terminalFrameInWindow: terminalFrameInWindow
        ) else {
            Issue.record("Expected a valid local frame for bottom pane")
            return
        }

        #expect(topLocal.origin.x == 300)
        #expect(topLocal.origin.y == 0)
        #expect(bottomLocal.origin.y == 300)
        #expect(topLocal.minY < bottomLocal.minY)
    }

    @Test func focusedSplitBorderFrameClipsAndRejectsTinyResults() {
        let terminalFrameInWindow = CGRect(x: 100, y: 200, width: 900, height: 600)

        let partlyOutsideTop = CGRect(x: 100, y: 750, width: 900, height: 200)
        guard let clipped = WindowBorderRenderingPolicy.focusedSplitBorderFrame(
            surfaceFrameInWindow: partlyOutsideTop,
            terminalFrameInWindow: terminalFrameInWindow
        ) else {
            Issue.record("Expected clipped frame for partially visible pane")
            return
        }
        #expect(clipped.origin.x == 0)
        #expect(clipped.origin.y == 0)
        #expect(clipped.size.width == 900)
        #expect(clipped.size.height == 50)

        let topSliver = CGRect(x: 100, y: 799, width: 900, height: 2)
        #expect(
            WindowBorderRenderingPolicy.focusedSplitBorderFrame(
                surfaceFrameInWindow: topSliver,
                terminalFrameInWindow: terminalFrameInWindow
            ) == nil
        )
    }

    @Test func focusedSplitBorderFrameIsStableAcrossRapidFocusCycle() {
        let terminalFrameInWindow = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let panes: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 400, height: 900),
            "centerTop": CGRect(x: 400, y: 450, width: 400, height: 450),
            "centerBottom": CGRect(x: 400, y: 0, width: 400, height: 450),
            "right": CGRect(x: 800, y: 0, width: 400, height: 900),
        ]
        let expectedLocal: [String: CGRect] = [
            "left": CGRect(x: 0, y: 0, width: 400, height: 900),
            "centerTop": CGRect(x: 400, y: 0, width: 400, height: 450),
            "centerBottom": CGRect(x: 400, y: 450, width: 400, height: 450),
            "right": CGRect(x: 800, y: 0, width: 400, height: 900),
        ]
        let rapidCycleOrder = [
            "centerTop",
            "centerBottom",
            "right",
            "left",
            "centerTop",
            "right",
            "centerBottom",
        ]

        var resolvedFrames: [CGRect] = []
        for pane in rapidCycleOrder {
            guard let paneFrame = panes[pane] else {
                Issue.record("Missing pane frame for \(pane)")
                return
            }
            guard let localFrame = WindowBorderRenderingPolicy.focusedSplitBorderFrame(
                surfaceFrameInWindow: paneFrame,
                terminalFrameInWindow: terminalFrameInWindow
            ) else {
                Issue.record("Expected local frame for pane \(pane)")
                return
            }
            guard let expectedFrame = expectedLocal[pane] else {
                Issue.record("Missing expected local frame for \(pane)")
                return
            }
            #expect(localFrame == expectedFrame)
            resolvedFrames.append(localFrame)
        }

        // Re-visiting the same pane in a fast cycle should keep frame mapping identical.
        #expect(resolvedFrames[0] == resolvedFrames[4])
    }

    @Test func windowOutlineTracesFramedPanesLikeTheFocusedPaneOutline() {
        // Framed panes already sit inside the window's corners, so the window
        // outline shares their frame and curve and adds no padding of its own.
        #expect(WindowBorderRenderingPolicy.windowOutlinePlacement(
            panesAreFramed: true,
            browserSplitVisible: false
        ) == .paneGrid)
    }

    @Test func windowOutlineStaysAtTheWindowEdgeWithoutAFramedPaneGrid() {
        // Edge-to-edge panes and the browser split reach the window's clipping edge.
        #expect(WindowBorderRenderingPolicy.windowOutlinePlacement(
            panesAreFramed: false,
            browserSplitVisible: false
        ) == .windowEdge)
        #expect(WindowBorderRenderingPolicy.windowOutlinePlacement(
            panesAreFramed: true,
            browserSplitVisible: true
        ) == .windowEdge)
    }

    @Test func effectiveCornerRadiusUsesInsetAndChromeModeOffsets() {
        let lineWidth: CGFloat = WindowBorderRenderingPolicy.lineWidth(for: 2.0)
        let inset = WindowBorderRenderingPolicy.inset(forLineWidth: lineWidth)

        let native = WindowBorderRenderingPolicy.effectiveCornerRadius(
            requestedRadius: 10,
            lineWidth: lineWidth,
            chromeMode: .native
        )
        let tabs = WindowBorderRenderingPolicy.effectiveCornerRadius(
            requestedRadius: 10,
            lineWidth: lineWidth,
            chromeMode: .tabs
        )

        #expect(native == 10 - inset)
        #expect(tabs == native + 1.0)
    }

    @Test func effectiveCornerRadiusNeverGoesNegative() {
        let lineWidth: CGFloat = WindowBorderRenderingPolicy.lineWidth(for: 8.0)
        let smallRadius = WindowBorderRenderingPolicy.effectiveCornerRadius(
            requestedRadius: 0.5,
            lineWidth: lineWidth,
            chromeMode: .tabs
        )
        let zeroRadius = WindowBorderRenderingPolicy.effectiveCornerRadius(
            requestedRadius: 0,
            lineWidth: lineWidth,
            chromeMode: .tabs
        )

        #expect(smallRadius == 0)
        #expect(zeroRadius == 0)
    }

    @Test func dashPatternOnlyAppliesToUnfocusedDifferentiateMode() {
        let lineWidth: CGFloat = 2.0

        #expect(
            WindowBorderRenderingPolicy.dashPattern(
                forLineWidth: lineWidth,
                isFocused: true,
                useDashedUnfocusedStyle: true
            ).isEmpty
        )
        #expect(
            WindowBorderRenderingPolicy.dashPattern(
                forLineWidth: lineWidth,
                isFocused: false,
                useDashedUnfocusedStyle: false
            ).isEmpty
        )

        let pattern = WindowBorderRenderingPolicy.dashPattern(
            forLineWidth: lineWidth,
            isFocused: false,
            useDashedUnfocusedStyle: true
        )
        #expect(pattern.count == 2)
        #expect(abs(pattern[0] - 4.0) < 0.0001)
        #expect(abs(pattern[1] - 3.2) < 0.0001)
    }

    @Test func dashedStyleFollowsAccessibilityState() {
        #expect(
            WindowBorderRenderingPolicy.shouldUseDashedUnfocusedStyle(
                differentiateWithoutColor: true
            )
        )
        #expect(
            !WindowBorderRenderingPolicy.shouldUseDashedUnfocusedStyle(
                differentiateWithoutColor: false
            )
        )
    }

    private func rgbaTuple(_ color: Color) -> (Int, Int, Int, Int) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.black
        return (
            Int(round(nsColor.redComponent * 255.0)),
            Int(round(nsColor.greenComponent * 255.0)),
            Int(round(nsColor.blueComponent * 255.0)),
            Int(round(nsColor.alphaComponent * 255.0))
        )
    }
}
