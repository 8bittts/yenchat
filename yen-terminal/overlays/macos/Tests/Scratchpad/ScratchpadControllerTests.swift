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

    @Test func floatingPanelCentersAndFitsTheAvailableWindow() {
        let bounds = CGRect(x: 30, y: 60, width: 900, height: 600)
        let center = CGPoint(x: 0.5, y: 0.5)
        let frame = ScratchpadController.panelFrame(in: bounds, preferred: nil, center: center)
        #expect(abs(frame.midX - bounds.midX) <= 1)
        #expect(abs(frame.midY - bounds.midY) <= 1)
        let custom = CGSize(width: 450, height: 290)
        #expect(ScratchpadController.panelFrame(in: bounds, preferred: custom, center: center).size == custom)
        let tiny = CGRect(x: 0, y: 0, width: 180, height: 140)
        #expect(tiny.contains(ScratchpadController.panelFrame(in: tiny, preferred: custom, center: center)))
    }

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
        panel.setFrame(NSRect(x: 0, y: 0, width: 520, height: 480), display: false)
        panel.contentView?.layoutSubtreeIfNeeded()

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
