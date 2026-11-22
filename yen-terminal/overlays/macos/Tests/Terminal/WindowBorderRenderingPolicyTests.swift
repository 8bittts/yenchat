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

    // MARK: Effects

    private let bothEffects = WindowBorderEffects(sparkEnabled: true, auraEnabled: true, auraColorHex: "#22C55E")

    @Test func effectsMarkOnlyTheFocusedOutline() {
        #expect(
            WindowBorderRenderingPolicy.effectPlan(effects: bothEffects, isFocused: true, motionLimit: .none)
                == WindowBorderEffectPlan(showsSpark: true, showsAura: true, auraPulses: true)
        )
        #expect(
            WindowBorderRenderingPolicy.effectPlan(effects: bothEffects, isFocused: false, motionLimit: .none)
                == WindowBorderEffectPlan(showsSpark: false, showsAura: false, auraPulses: false)
        )
        #expect(
            WindowBorderRenderingPolicy.effectPlan(effects: .none, isFocused: true, motionLimit: .none)
                == WindowBorderEffectPlan(showsSpark: false, showsAura: false, auraPulses: false)
        )
        let sparkOnly = WindowBorderEffects(sparkEnabled: true, auraEnabled: false, auraColorHex: "#22C55E")
        #expect(
            WindowBorderRenderingPolicy.effectPlan(effects: sparkOnly, isFocused: true, motionLimit: .none)
                == WindowBorderEffectPlan(showsSpark: true, showsAura: false, auraPulses: false)
        )
    }

    @Test func aMotionLimitHidesTheSparkAndHoldsTheAuraStill() {
        for limit in [WindowBorderMotionLimit.reduceMotion, .lowPowerMode] {
            #expect(
                WindowBorderRenderingPolicy.effectPlan(effects: bothEffects, isFocused: true, motionLimit: limit)
                    == WindowBorderEffectPlan(showsSpark: false, showsAura: true, auraPulses: false)
            )
        }
    }

    @Test func reduceMotionAndLowPowerModeEachLimitMotion() {
        #expect(WindowBorderRenderingPolicy.motionLimit(reduceMotion: false, lowPowerMode: false) == .none)
        #expect(WindowBorderRenderingPolicy.motionLimit(reduceMotion: true, lowPowerMode: false) == .reduceMotion)
        #expect(WindowBorderRenderingPolicy.motionLimit(reduceMotion: false, lowPowerMode: true) == .lowPowerMode)
        // The accessibility setting is the one the hint names when both are on.
        #expect(WindowBorderRenderingPolicy.motionLimit(reduceMotion: true, lowPowerMode: true) == .reduceMotion)
    }

    @MainActor
    @Test func lowPowerMonitorFollowsThePowerStateNotification() {
        let center = NotificationCenter()
        var lowPower = false
        let monitor = LowPowerModeMonitor(readState: { lowPower }, center: center)
        #expect(!monitor.isLowPowerModeEnabled)

        lowPower = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(monitor.isLowPowerModeEnabled)

        lowPower = false
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(!monitor.isLowPowerModeEnabled)
    }

    @Test func auraPulseSpeedsRunFromSlowToFast() {
        let slow = WindowBorderRenderingPolicy.auraModel(lineWidth: 2, pulse: .slow)
        let medium = WindowBorderRenderingPolicy.auraModel(lineWidth: 2, pulse: .medium)
        let fast = WindowBorderRenderingPolicy.auraModel(lineWidth: 2, pulse: .fast)
        #expect(slow.pulseHalfPeriod > medium.pulseHalfPeriod)
        #expect(medium.pulseHalfPeriod > fast.pulseHalfPeriod)
        // Even the fast pulse stays under one flash a second.
        #expect(fast.pulseHalfPeriod * 2 >= 1)
        // Speed changes the timing only, never how bright the glow gets.
        #expect(slow.pulseHighOpacity == fast.pulseHighOpacity)
        #expect(slow.pulseLowOpacity == fast.pulseLowOpacity)
    }

    @Test func sparkKeepsOneSpeedBetweenItsLapLimits() throws {
        // 340 points a second: a 2040 point outline takes six seconds.
        let window = try #require(WindowBorderRenderingPolicy.sparkModel(perimeter: 2040, lineWidth: 2))
        #expect(abs(window.lapDuration - 6) < 0.0001)
        // Segments sit three points apart, so each one trails the next by 3/340 of a second.
        #expect(abs(window.segmentDelay - 3.0 / 340.0) < 0.0001)

        let smallPane = try #require(WindowBorderRenderingPolicy.sparkModel(perimeter: 300, lineWidth: 2))
        #expect(smallPane.lapDuration == 3)
        #expect(smallPane.tailLength <= 300 / 4)

        let largeWindow = try #require(WindowBorderRenderingPolicy.sparkModel(perimeter: 10_000, lineWidth: 2))
        #expect(largeWindow.lapDuration == 12)
        // The tail is whole segments, so it stops within one segment of its 160 point limit.
        #expect(largeWindow.tailLength <= 160)
        #expect(largeWindow.tailLength > 160 - WindowBorderRenderingPolicy.sparkSegmentSpacing)

        #expect(WindowBorderRenderingPolicy.sparkModel(perimeter: 0, lineWidth: 2) == nil)
        #expect(WindowBorderRenderingPolicy.sparkModel(perimeter: .infinity, lineWidth: 2) == nil)
    }

    @Test func sparkTailHasNoGapsOrBandsAtAnyWeight() throws {
        let spacing = WindowBorderRenderingPolicy.sparkSegmentSpacing
        for weight in SettingsBorderWeight.allCases {
            let model = try #require(
                WindowBorderRenderingPolicy.sparkModel(perimeter: 2400, lineWidth: CGFloat(weight.rawValue))
            )
            // A segment longer than the spacing leaves no gap, and a whole
            // multiple of it covers every point the same number of times.
            #expect(model.segmentLength > spacing)
            #expect(model.segmentLength.truncatingRemainder(dividingBy: spacing) == 0)
        }
    }

    @Test func pathMetricsMeasureLengthAndDirection() {
        let clockwise = CGMutablePath()
        clockwise.move(to: CGPoint(x: 0, y: 0))
        clockwise.addLine(to: CGPoint(x: 100, y: 0))
        clockwise.addLine(to: CGPoint(x: 100, y: 50))
        clockwise.addLine(to: CGPoint(x: 0, y: 50))
        clockwise.closeSubpath()
        let forward = WindowBorderRenderingPolicy.pathMetrics(of: clockwise)
        #expect(abs(forward.perimeter - 300) < 0.001)
        #expect(abs(forward.signedArea - 5000) < 0.001)

        let counterclockwise = CGMutablePath()
        counterclockwise.move(to: CGPoint(x: 0, y: 0))
        counterclockwise.addLine(to: CGPoint(x: 0, y: 50))
        counterclockwise.addLine(to: CGPoint(x: 100, y: 50))
        counterclockwise.addLine(to: CGPoint(x: 100, y: 0))
        counterclockwise.closeSubpath()
        #expect(abs(WindowBorderRenderingPolicy.pathMetrics(of: counterclockwise).signedArea + 5000) < 0.001)

        // A rounded outline is shorter than the rectangle around it and longer than the circle inside it.
        let geometry = WindowBorderEffectGeometry(cornerRadius: 10, inset: 1, lineWidth: 2)
        let rounded = WindowBorderRenderingPolicy.pathMetrics(of: geometry.path(in: CGRect(x: 0, y: 0, width: 202, height: 102)))
        #expect(rounded.perimeter < 600)
        #expect(rounded.perimeter > 2 * .pi * 50)
    }

    @MainActor
    @Test func sparkTravelsOnlyWhileItsViewIsInAWindowAndMatchesTheWeight() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = WindowBorderSparkLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let geometry = WindowBorderEffectGeometry(cornerRadius: 10, inset: 2, lineWidth: 4)

        view.configure(geometry: geometry, color: .white)
        #expect(!view.isTraveling)

        window.contentView?.addSubview(view)
        view.configure(geometry: geometry, color: .white)
        #expect(view.isTraveling)
        #expect(view.segmentSizeForTesting.height == 4)
        #expect(view.segmentCountForTesting > 1)

        view.configure(geometry: WindowBorderEffectGeometry(cornerRadius: 10, inset: 0.5, lineWidth: 1), color: .white)
        #expect(view.isTraveling)
        #expect(view.segmentSizeForTesting.height == 1)

        view.removeFromSuperview()
        #expect(!view.isTraveling)
    }

    @MainActor
    @Test func sparkStandsOutFromItsStrokeOnDarkAndLightBackdrops() {
        func luminance(_ color: NSColor) -> Double {
            WindowBorderGradientResolver.contrastRatioForTesting(of: color, against: .black) * 0.05 - 0.05
        }
        let sunrise = WindowBorderGradient(
            startColor: WindowBorderPalette.sunrise.startColor,
            endColor: WindowBorderPalette.sunrise.endColor
        )
        let stroke = NSColor(sunrise.startColor).blended(withFraction: 0.5, of: NSColor(sunrise.endColor)) ?? .orange

        // A light on a dark backdrop, ink on a light one.
        let onDark = WindowBorderOverlay.sparkColor(for: sunrise, backdropIsLight: false)
        let onLight = WindowBorderOverlay.sparkColor(for: sunrise, backdropIsLight: true)
        #expect(luminance(onDark) > luminance(stroke))
        #expect(luminance(onLight) < luminance(stroke))

        // Whatever the backdrop, the spark never vanishes into its stroke.
        let pale = WindowBorderGradient(startColor: .white, endColor: Color(white: 0.96))
        let ink = WindowBorderGradient(startColor: .black, endColor: Color(white: 0.06))
        for gradient in [sunrise, pale, ink] {
            let middle = NSColor(gradient.startColor).blended(withFraction: 0.5, of: NSColor(gradient.endColor)) ?? .gray
            for backdropIsLight in [false, true] {
                let spark = WindowBorderOverlay.sparkColor(for: gradient, backdropIsLight: backdropIsLight)
                #expect(
                    WindowBorderGradientResolver.contrastRatioForTesting(of: spark, against: middle)
                        >= WindowBorderOverlay.minimumSparkContrastRatio
                )
            }
        }
    }

    @MainActor
    @Test func sparkIsNotRebuiltWhenAnUpdateChangesNothing() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = WindowBorderSparkLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView?.addSubview(view)
        let geometry = WindowBorderEffectGeometry(cornerRadius: 10, inset: 1, lineWidth: 2)

        view.configure(geometry: geometry, color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        #expect(view.travelBuildCount == 1)

        // SwiftUI hands over a new color object on every update, sometimes in
        // another color space. The same color must not restart the spark.
        view.configure(geometry: geometry, color: NSColor(white: 1, alpha: 1))
        view.configure(geometry: geometry, color: .white)
        view.layout()
        #expect(view.travelBuildCount == 1)

        view.configure(geometry: geometry, color: .systemOrange)
        #expect(view.travelBuildCount == 2)
        #expect(view.isTraveling)
    }

    @MainActor
    @Test func auraGlowsWhenHeldAndPulsesAtTheChosenSpeed() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = WindowBorderAuraLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView?.addSubview(view)
        let geometry = WindowBorderEffectGeometry(cornerRadius: 10, inset: 1, lineWidth: 2)

        view.configure(geometry: geometry, color: .systemGreen, pulse: nil)
        #expect(view.hasGlowForTesting)
        #expect(!view.isPulsing)

        view.configure(geometry: geometry, color: .systemGreen, pulse: .slow)
        #expect(view.pulseHalfPeriod == WindowBorderAuraPulse.slow.halfPeriod)

        // A new speed takes effect at once, without another glow image.
        view.configure(geometry: geometry, color: .systemGreen, pulse: .fast)
        #expect(view.pulseHalfPeriod == WindowBorderAuraPulse.fast.halfPeriod)
        #expect(view.glowDrawCount == 1)

        view.configure(geometry: geometry, color: .systemGreen, pulse: nil)
        #expect(view.hasGlowForTesting)
        #expect(!view.isPulsing)
    }

    @MainActor
    @Test func auraResizesWithoutDrawingItsGlowAgain() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = WindowBorderAuraLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView?.addSubview(view)
        let geometry = WindowBorderEffectGeometry(cornerRadius: 10, inset: 1, lineWidth: 2)
        view.configure(geometry: geometry, color: .systemGreen, pulse: .medium)

        for width in stride(from: 420, through: 900, by: 60) {
            view.frame = NSRect(x: 0, y: 0, width: width, height: 300)
            view.layout()
        }
        #expect(view.glowDrawCount == 1)

        view.configure(geometry: geometry, color: .systemBlue, pulse: .medium)
        #expect(view.glowDrawCount == 2)
    }

    /// A stand-in for the terminal surface under the outline.
    private final class ClickTargetView: NSView {}

    private struct ClickTarget: NSViewRepresentable {
        func makeNSView(context: Context) -> ClickTargetView { ClickTargetView() }
        func updateNSView(_ view: ClickTargetView, context: Context) {}
    }

    @MainActor
    @Test func clicksPassThroughAnOutlineWithBothEffectsToTheTerminalBelow() throws {
        let overlay = WindowBorderOverlay(
            gradient: WindowBorderGradient(startColor: .orange, endColor: .yellow),
            width: 4,
            radius: 10,
            chromeMode: .native,
            isFocused: true,
            useDashedUnfocusedStyle: false,
            effects: bothEffects
        )
        let content = ZStack {
            ClickTarget()
            overlay.paneBorder(framed: false).allowsHitTesting(false)
        }
        .frame(width: 400, height: 300)
        .transaction { $0.disablesAnimations = true }
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        // The aura is mounted, so the hit tests below go through a real effect layer.
        #expect(descendants(of: hosting).contains { $0 is WindowBorderAuraLayerView })

        // The middle of the pane, a point on the stroke, and a point in the glow.
        for point in [NSPoint(x: 200, y: 150), NSPoint(x: 3, y: 150), NSPoint(x: 10, y: 150), NSPoint(x: 200, y: 3)] {
            let hit = try #require(hosting.hitTest(point))
            #expect(hit is ClickTargetView, "a click at \(point) landed on \(type(of: hit))")
        }
    }

    @MainActor
    @Test func effectLayersNeverTakeAClick() {
        let spark = WindowBorderSparkLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let aura = WindowBorderAuraLayerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(spark.hitTest(NSPoint(x: 200, y: 1)) == nil)
        #expect(aura.hitTest(NSPoint(x: 200, y: 1)) == nil)
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
