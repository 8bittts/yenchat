import AppKit
import Testing
@testable import YEN

private final class TerminalAuxiliaryAnchorTestIdentity {}

@MainActor
struct ScratchpadControllerTests {
    @Test func terminateFlushPreservesUnreadableExistingFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        let originalData = Data([0xFF, 0xFE])
        try originalData.write(to: fileURL)

        let controller = ScratchpadController(storage: ScratchpadStorage(fileURL: fileURL))
        controller.loadPersistedText()
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        #expect(try Data(contentsOf: fileURL) == originalData)
    }

    @Test func editingAfterLoadFailureAllowsReplacementToPersist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("scratchpad.txt", isDirectory: false)
        try Data([0xFF, 0xFE]).write(to: fileURL)

        let controller = ScratchpadController(storage: ScratchpadStorage(fileURL: fileURL))
        controller.loadPersistedText()
        controller.text = "replacement"
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "replacement")
    }

    @Test func animationDurationHonorsReduceMotion() {
        #expect(ScratchpadController.animationDuration(reduceMotion: false) == 0.2)
        #expect(ScratchpadController.animationDuration(reduceMotion: true) == 0)
    }

    @Test func shouldHandleCommandKeyWhenPanelHasTextViewResponder() {
        let shouldHandle = ScratchpadController.shouldHandleCommandKey(
            panelFirstResponderIsTextView: true,
            windowFirstResponderIsTextView: false
        )

        #expect(shouldHandle)
    }

    @Test func shouldHandleCommandKeyWhenWindowHasTextViewResponder() {
        let shouldHandle = ScratchpadController.shouldHandleCommandKey(
            panelFirstResponderIsTextView: false,
            windowFirstResponderIsTextView: true
        )

        #expect(shouldHandle)
    }

    @Test func shouldIgnoreCommandKeyWhenScratchpadIsNotResponder() {
        let shouldHandle = ScratchpadController.shouldHandleCommandKey(
            panelFirstResponderIsTextView: false,
            windowFirstResponderIsTextView: false
        )

        #expect(!shouldHandle)
    }

    @Test func clickInsideScratchpadDoesNotRequestClose() {
        let shouldClose = ScratchpadController.shouldCloseForClick(
            panelFrame: NSRect(x: 100, y: 100, width: 360, height: 480),
            screenPoint: NSPoint(x: 180, y: 220)
        )

        #expect(!shouldClose)
    }

    @Test func clickOutsideScratchpadRequestsClose() {
        let shouldClose = ScratchpadController.shouldCloseForClick(
            panelFrame: NSRect(x: 100, y: 100, width: 360, height: 480),
            screenPoint: NSPoint(x: 40, y: 220)
        )

        #expect(shouldClose)
    }

    @Test func outsideMouseDownRequestsClose() {
        let shouldClose = ScratchpadController.shouldCloseForMouseDown(
            eventType: .leftMouseDown,
            panelFrame: NSRect(x: 100, y: 100, width: 360, height: 480),
            screenPoint: NSPoint(x: 40, y: 220)
        )

        #expect(shouldClose)
    }

    @Test func outsideMouseUpDoesNotRequestClose() {
        let shouldClose = ScratchpadController.shouldCloseForMouseDown(
            eventType: .leftMouseUp,
            panelFrame: NSRect(x: 100, y: 100, width: 360, height: 480),
            screenPoint: NSPoint(x: 40, y: 220)
        )

        #expect(!shouldClose)
    }

    @Test func restFrameSitsFlushInsideTheWindowRightEdge() {
        // Always inside the content area, whatever room the screen has beside it.
        let frame = EdgeRevealPanelGeometry.restFrame(
            contentFrame: NSRect(x: 100, y: 80, width: 500, height: 392),
            edge: .trailing,
            width: 360
        )

        #expect(frame == NSRect(x: 240, y: 80, width: 360, height: 392))
    }

    @Test func restFrameRoundsOnlyTheOuterCornersItSharesWithTheWindow() {
        let window = NSRect(x: 100, y: 80, width: 500, height: 420)
        // Below a 28pt titlebar the panel shares only the window's bottom-right corner.
        let belowTitlebar = NSRect(x: 240, y: 80, width: 360, height: 392)
        #expect(EdgeRevealPanelGeometry.sharedWindowCorners(
            panelFrame: belowTitlebar,
            windowFrame: window,
            edge: .trailing
        ) == [.layerMaxXMinYCorner])
        // With no titlebar it also shares the top-right corner.
        let fullHeight = NSRect(x: 240, y: 80, width: 360, height: 420)
        #expect(EdgeRevealPanelGeometry.sharedWindowCorners(
            panelFrame: fullHeight,
            windowFrame: window,
            edge: .trailing
        ) == [.layerMaxXMinYCorner, .layerMaxXMaxYCorner])
    }

    @Test func revealParksContentOneFullWidthPastTheRightEdge() {
        let reveal = EdgeRevealView(edge: .trailing)
        reveal.frame = NSRect(x: 0, y: 0, width: 360, height: 400)
        let content = NSView()
        reveal.embed(content, extent: 360)

        reveal.park()
        #expect(reveal.slideOffset == 360)
        #expect(reveal.alphaValue == 0)
        #expect(content.frame.minX == 360)
        #expect(!reveal.isRevealed)

        reveal.showAtRest()
        #expect(reveal.slideOffset == 0)
        #expect(reveal.alphaValue == 1)
        #expect(content.frame == NSRect(x: 0, y: 0, width: 360, height: 400))
        #expect(reveal.isRevealed)
    }

    // First Cmd+Shift+H: `park()` forces the first SwiftUI layout while `visible` is
    // already true, and `makeNSView` registers the editor. Focusing there ordered the
    // panel front inside the layout pass and AttributeGraph aborted the app.
    @Test func firstLayoutRegistersEditorWithoutChangingFocus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let controller = ScratchpadController(
            storage: ScratchpadStorage(fileURL: root.appendingPathComponent("scratchpad.txt"))
        )

        controller.visible = true
        defer { controller.visible = false }
        let panel = controller.ensurePanel()
        defer { panel.orderOut(nil) }
        panel.setFrame(NSRect(x: 0, y: 0, width: ScratchpadController.panelWidth, height: 480), display: false)
        let reveal = try #require(controller.revealView)
        reveal.park()

        let textView = try #require(controller.textView)
        #expect(!panel.isVisible)
        #expect(!panel.isKeyWindow)
        #expect(panel.firstResponder !== textView)
    }

    @Test func auxiliaryAnchorPolicySkipsIneligiblePreferredWindowsBeforeFallback() {
        let helperPanel = TerminalAuxiliaryAnchorTestIdentity()
        let staleTerminal = TerminalAuxiliaryAnchorTestIdentity()
        let visibleTerminal = TerminalAuxiliaryAnchorTestIdentity()

        let selected = TerminalAuxiliaryAnchorPolicy.firstEligible(in: [
            TerminalAuxiliaryAnchorPolicy.Candidate(
                identity: ObjectIdentifier(helperPanel),
                window: "helper-panel",
                isEligible: TerminalAuxiliaryAnchorPolicy.canAnchor(
                    windowControllerIsTerminal: false,
                    isQuickTerminal: false,
                    isFullscreen: false,
                    isMiniaturized: false,
                    isVisible: true
                )
            ),
            TerminalAuxiliaryAnchorPolicy.Candidate(
                identity: ObjectIdentifier(staleTerminal),
                window: "stale-terminal",
                isEligible: TerminalAuxiliaryAnchorPolicy.canAnchor(
                    windowControllerIsTerminal: true,
                    isQuickTerminal: false,
                    isFullscreen: false,
                    isMiniaturized: false,
                    isVisible: false
                )
            ),
            TerminalAuxiliaryAnchorPolicy.Candidate(
                identity: ObjectIdentifier(visibleTerminal),
                window: "visible-terminal",
                isEligible: TerminalAuxiliaryAnchorPolicy.canAnchor(
                    windowControllerIsTerminal: true,
                    isQuickTerminal: false,
                    isFullscreen: false,
                    isMiniaturized: false,
                    isVisible: true
                )
            ),
        ])

        #expect(selected == "visible-terminal")
    }

    @Test func auxiliaryAnchorPolicyRejectsQuickTerminalFullscreenAndMiniaturizedWindows() {
        #expect(!TerminalAuxiliaryAnchorPolicy.canAnchor(
            windowControllerIsTerminal: true,
            isQuickTerminal: true,
            isFullscreen: false,
            isMiniaturized: false,
            isVisible: true
        ))
        #expect(!TerminalAuxiliaryAnchorPolicy.canAnchor(
            windowControllerIsTerminal: true,
            isQuickTerminal: false,
            isFullscreen: true,
            isMiniaturized: false,
            isVisible: true
        ))
        #expect(!TerminalAuxiliaryAnchorPolicy.canAnchor(
            windowControllerIsTerminal: true,
            isQuickTerminal: false,
            isFullscreen: false,
            isMiniaturized: true,
            isVisible: true
        ))
    }

    @Test func scratchpadPanelStaysRetainedAfterClose() {
        let panel = ScratchpadPanel()

        #expect(!panel.isReleasedWhenClosed)
    }

    @Test func validatesToggleMenuItemAgainstScratchpadPreference() {
        let key = ScratchpadController.scratchpadEnabledPreferenceKey
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let item = NSMenuItem(
            title: "Toggle Scratchpad",
            action: #selector(ScratchpadController.toggleAction(_:)),
            keyEquivalent: "j"
        )
        item.target = ScratchpadController.shared

        defaults.set(false, forKey: key)
        #expect(!ScratchpadController.shared.validateMenuItem(item))

        defaults.set(true, forKey: key)
        #expect(ScratchpadController.shared.validateMenuItem(item))
    }

    @Test func disabledToggleHotkeyConsumesCmdShiftJ() {
        let shouldConsume = ScratchpadController.shouldConsumeDisabledToggleHotkey(
            charactersIgnoringModifiers: "j",
            modifierFlags: [.command, .shift],
            scratchpadEnabled: false
        )

        #expect(shouldConsume)
    }

    @Test func disabledToggleHotkeyDoesNotConsumeWhenEnabled() {
        let shouldConsume = ScratchpadController.shouldConsumeDisabledToggleHotkey(
            charactersIgnoringModifiers: "j",
            modifierFlags: [.command, .shift],
            scratchpadEnabled: true
        )

        #expect(!shouldConsume)
    }

    /// Verify helpers are callable from nonisolated context (regression guard for
    /// event-monitor callbacks that run outside @MainActor).
    @Test func nonisolatedStaticHelpersCompile() {
        nonisolatedCallSite()
    }

    @Test func disabledToggleHotkeyIgnoresNonScratchpadShortcuts() {
        let wrongKey = ScratchpadController.shouldConsumeDisabledToggleHotkey(
            charactersIgnoringModifiers: "k",
            modifierFlags: [.command, .shift],
            scratchpadEnabled: false
        )
        let wrongModifiers = ScratchpadController.shouldConsumeDisabledToggleHotkey(
            charactersIgnoringModifiers: "j",
            modifierFlags: [.command],
            scratchpadEnabled: false
        )

        #expect(!wrongKey)
        #expect(!wrongModifiers)
    }
}

// MARK: - Nonisolated regression guard

/// Free function outside @MainActor — proves the static helpers stay nonisolated.
/// If someone removes `nonisolated` from shouldConsumeDisabledToggleHotkey,
/// isToggleHotkey, shouldCloseForClick, shouldCloseForMouseDown, or scratchpadEnabled,
/// this will fail to compile.
private func nonisolatedCallSite() {
    _ = ScratchpadController.shouldConsumeDisabledToggleHotkey(
        charactersIgnoringModifiers: "j",
        modifierFlags: [.command, .shift],
        scratchpadEnabled: ScratchpadController.scratchpadEnabled
    )
    _ = ScratchpadController.isToggleHotkey(
        charactersIgnoringModifiers: "j",
        modifierFlags: [.command, .shift]
    )
    _ = ScratchpadController.shouldCloseForClick(
        panelFrame: .zero,
        screenPoint: .zero
    )
    _ = ScratchpadController.shouldCloseForMouseDown(
        eventType: .leftMouseDown,
        panelFrame: .zero,
        screenPoint: .zero
    )
}
