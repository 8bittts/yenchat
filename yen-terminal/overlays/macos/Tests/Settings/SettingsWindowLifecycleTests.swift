import AppKit
import Testing
@testable import YEN

@MainActor
struct SettingsWindowLifecycleTests {
    @Test func firstOpenWithoutPaneOverrideShowsAppearance() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show()

        #expect(controller.selectedSettingsPane == .appearance)
    }

    @Test func firstOpenWithRequestedPaneSelectsIt() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .appearance)

        #expect(controller.selectedSettingsPane == .appearance)
    }

    @Test func deepLinkRetargetsSelectedPaneWhileWindowIsAlreadyOpen() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)
        controller.show(pane: .shortcuts)

        #expect(controller.selectedSettingsPane == .shortcuts)
    }

    @Test func closeAndReopenPreservesSelectionWhenNoPaneOverrideProvided() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .dictation)
        controller.hide()
        drainMainRunLoop()
        controller.show()

        #expect(controller.selectedSettingsPane == .dictation)
    }

    @Test func visibleDeepLinkRetargetDoesNotScheduleSecondSessionBootstrap() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)
        waitForSettingsBootstrapToFinish(controller)

        let initialBootstrapCount = controller._testShowRefreshScheduleCount
        #expect(initialBootstrapCount == 1)
        #expect(!controller._testHasShowRefreshTask)

        controller.show(pane: .shortcuts)

        #expect(controller.selectedSettingsPane == .shortcuts)
        #expect(controller._testShowRefreshScheduleCount == initialBootstrapCount)
        #expect(!controller._testHasShowRefreshTask)
        #expect(controller._testHasDeferredKeybindReloadTask)
    }

    @Test func visibleDeepLinkRetargetWhileBootstrapIsPendingKeepsSingleBootstrap() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)

        let initialBootstrapCount = controller._testShowRefreshScheduleCount
        #expect(initialBootstrapCount == 1)
        #expect(controller._testHasShowRefreshTask)

        controller.show(pane: .shortcuts)

        #expect(controller.selectedSettingsPane == .shortcuts)
        #expect(controller._testShowRefreshScheduleCount == initialBootstrapCount)
        #expect(controller._testHasShowRefreshTask)

        waitForSettingsBootstrapToFinish(controller)

        #expect(!controller._testHasShowRefreshTask)
    }

    @Test func visibleDeepLinkRetargetFlushesPendingRealTimeConfigSync() throws {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.copyOnSelect = originalCopyOnSelect
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let baselineConfig = "copy-on-select = \(originalCopyOnSelect ? "clipboard" : "false")\n"
        try baselineConfig.write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting(baselineConfig)

        controller.show(pane: .general)
        waitForSettingsBootstrapToFinish(controller)

        controller.copyOnSelect = !originalCopyOnSelect
        #expect(controller._testHasPendingRealTimeConfigSync)

        controller.show(pane: .shortcuts)

        #expect(controller.selectedSettingsPane == .shortcuts)
        #expect(!controller._testHasPendingRealTimeConfigSync)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("copy-on-select = \((!originalCopyOnSelect) ? "both" : "false")"))
    }

    @Test func visibleDeepLinkRetargetFlushesPendingThemePreviewCommit() throws {
        let controller = SettingsController.shared
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let baselineConfig = "theme = Baseline\n"
        try baselineConfig.write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting(baselineConfig)

        controller.show(pane: .appearance)
        waitForSettingsBootstrapToFinish(controller)

        controller.applyTheme(ThemeInfo(name: "Final Theme", path: "/tmp/final.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)

        controller.show(pane: .general)

        #expect(controller.selectedSettingsPane == .general)
        #expect(!controller._testHasPendingThemeSelectionCommit)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("theme = Final Theme"))
    }

    @Test func commandPaletteDeepLinkFlushesPendingEditsBeforeVisibleRetarget() throws {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.copyOnSelect = originalCopyOnSelect
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let baselineConfig = """
        theme = Baseline
        copy-on-select = \(originalCopyOnSelect ? "clipboard" : "false")
        """
        try baselineConfig.write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting(baselineConfig)

        controller.show(pane: .appearance)
        waitForSettingsBootstrapToFinish(controller)

        controller.copyOnSelect = !originalCopyOnSelect
        controller.applyTheme(ThemeInfo(name: "Final Theme", path: "/tmp/final.yen", bundled: false))

        #expect(controller._testHasPendingRealTimeConfigSync)
        #expect(controller._testHasPendingThemeSelectionCommit)

        let deepLink = try #require(
            TerminalCommandPaletteView.settingsDeepLinkDefinitions.first(where: { $0.pane == .shortcuts })
        )
        TerminalCommandPaletteView.openSettingsDeepLink(deepLink)

        #expect(controller.selectedSettingsPane == .shortcuts)
        #expect(!controller._testHasPendingRealTimeConfigSync)
        #expect(!controller._testHasPendingThemeSelectionCommit)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("theme = Final Theme"))
        #expect(contents.contains("copy-on-select = \((!originalCopyOnSelect) ? "both" : "false")"))
    }

    @Test func reopeningHiddenWindowSchedulesFreshSessionBootstrap() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)
        waitForSettingsBootstrapToFinish(controller)

        let initialBootstrapCount = controller._testShowRefreshScheduleCount
        #expect(initialBootstrapCount == 1)

        controller.hide()
        drainMainRunLoop()
        #expect(!controller._testHasWindow)

        controller.show(pane: .dictation)

        #expect(controller.selectedSettingsPane == .dictation)
        #expect(controller._testHasWindow)
        #expect(controller._testShowRefreshScheduleCount == initialBootstrapCount + 1)
        #expect(controller._testHasShowRefreshTask)

        waitForSettingsBootstrapToFinish(controller)

        #expect(!controller._testHasShowRefreshTask)
    }

    @Test func toggleVisibilityHidesAndReopensSettingsWindow() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .appearance)
        #expect(controller.window?.isVisible == true)
        #expect(controller._testHasWindow)
        let originalWindow = controller.window

        controller.toggleVisibility()
        drainMainRunLoop()
        #expect(!controller._testHasWindow)

        controller.toggleVisibility()
        drainMainRunLoop()
        #expect(controller._testHasWindow)
        #expect(controller.window?.isVisible == true)
        #expect(controller.selectedSettingsPane == .appearance)
        if let originalWindow {
            #expect(controller.window !== originalWindow)
        }
    }

    @Test func closeAndReopenPreservesWindowFrame() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        let originalWindow = controller.window
        let expectedFrame = NSRect(x: 64, y: 72, width: 1040, height: 700)
        controller.window?.setFrame(expectedFrame, display: false)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(controller._testStoredWindowFrame == expectedFrame)

        controller.show(pane: .general)

        #expect(controller._testHasWindow)
        #expect(controller.window?.frame == expectedFrame)
        if let originalWindow {
            #expect(controller.window !== originalWindow)
        }
    }

    @Test func showRecreatesWindowWhenReusableInstanceLostContentView() throws {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        let originalWindow = try #require(controller.window)
        let expectedFrame = NSRect(x: 88, y: 96, width: 1020, height: 680)
        originalWindow.setFrame(expectedFrame, display: false)
        originalWindow.contentView = nil

        controller.show(pane: .notifications)
        drainMainRunLoop()

        let recreatedWindow = try #require(controller.window)
        #expect(recreatedWindow !== originalWindow)
        #expect(recreatedWindow.contentView != nil)
        #expect(recreatedWindow.frame == expectedFrame)
        #expect(recreatedWindow.isVisible)
        #expect(controller.selectedSettingsPane == .notifications)
    }

    @Test func defaultCloseReleasesWindowGraph() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        let originalWindow = controller.window
        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(controller._testStoredWindowFrame != nil)
        #expect(originalWindow?.contentView == nil)
        #expect(originalWindow?.delegate == nil)
    }

    @Test func benchmarkRetainModeKeepsClosedWindowForProfilingComparison() {
        let controller = SettingsController.shared
        reset(controller)
        defer {
            SettingsController._testSetWindowCloseMemoryModeOverride(nil)
            reset(controller)
        }

        SettingsController._testSetWindowCloseMemoryModeOverride(.retainWindowGraph)
        controller.show(pane: .general)
        controller.hide()
        drainMainRunLoop()

        #expect(controller._testHasWindow)
        #expect(controller.window?.isVisible == false)
        #expect(controller._testStoredWindowFrame != nil)
    }

    @Test func releaseModeDropsReachablePaneScrollViewState() throws {
        let controller = SettingsController.shared
        reset(controller)
        defer {
            SettingsController._testSetWindowCloseMemoryModeOverride(nil)
            reset(controller)
        }

        SettingsController._testSetWindowCloseMemoryModeOverride(.releaseWindowGraph)
        controller.show(pane: .dictation)
        waitForSettingsPaneScrollView(controller)

        _ = try #require(controller._testSettingsPaneScrollView)

        controller.hide()
        drainMainRunLoop(for: 0.08)

        #expect(!controller._testHasWindow)
        #expect(controller._testSettingsPaneScrollView == nil)
    }

    @Test func applyingSettingsWindowChromeSetsTitleBehavior() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        SettingsWindowFactory.applyChrome(window)

        // The preview fills the window under a transparent titlebar, and the
        // window is clear so the preview's opacity shows what is behind it.
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.hasShadow)
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == false)
        #expect(window.titlebarAccessoryViewControllers.isEmpty)
    }

    @Test func windowTitleFollowsTheVisiblePane() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        // The title is hidden in the window, and it is still what Mission
        // Control, the Window menu and VoiceOver read.
        controller.show(pane: .notifications)
        #expect(controller.window?.title == "Notifications")

        controller.selectedSettingsPane = .shortcuts
        #expect(controller.window?.title == "Shortcuts")
    }

    @Test func errorStatusStaysUntilDismissedAndEveryStatusIsAnnounced() {
        let controller = SettingsController.shared
        var announcements: [String] = []
        controller.testStatusAnnouncementHandler = { announcements.append($0) }
        defer {
            controller.testStatusAnnouncementHandler = nil
            controller._testResetStatusState()
            controller.dismissStatus()
        }

        controller._testShowStatus("Apply failed: disk full", severity: .error, duration: 0.01)

        #expect(controller.statusMessage == "Apply failed: disk full")
        #expect(controller._testStatusClearWorkItemIdentifier == nil)
        #expect(announcements == ["Apply failed: disk full"])

        controller._testShowStatus("Imported background image", severity: .success, duration: 5)
        #expect(controller._testStatusClearWorkItemIdentifier != nil)
        #expect(announcements == ["Apply failed: disk full", "Imported background image"])

        controller.dismissStatus()
        #expect(controller.statusMessage.isEmpty)
        #expect(controller._testStatusClearWorkItemIdentifier == nil)
    }

    @Test func windowFactoryConfiguresTitleMinSizeAndChrome() {
        let window = SettingsWindowFactory.makeWindow(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
            lastFrame: nil
        )

        #expect(window.title == "YEN Settings")
        #expect(window.minSize.width == SettingsSpacing.panelMinWidth)
        #expect(window.minSize.height == SettingsWindowFactory.minimumContentHeight)
        #expect(window.isReleasedWhenClosed == false)
        #expect(window.toolbar == nil)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        // The HIG dims a settings window's minimize and zoom buttons.
        #expect(!window.styleMask.contains(.miniaturizable))
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == false)
        #expect(window.styleMask.contains(.resizable))
        // Chrome applied at construction: full-size content, transparent titlebar.
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(!window.isOpaque)
    }

    @Test func windowFactoryRestoresProvidedFrame() {
        let storedFrame = NSRect(x: 120, y: 140, width: 1200, height: 800)
        let window = SettingsWindowFactory.makeWindow(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
            lastFrame: storedFrame
        )

        #expect(window.frame == storedFrame)
    }

    @Test func windowFactoryReleaseGraphDropsDelegateAndContentView() {
        final class ProbeDelegate: NSObject, NSWindowDelegate {}
        let delegate = ProbeDelegate()
        let window = SettingsWindowFactory.makeWindow(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)),
            lastFrame: nil
        )
        window.delegate = delegate
        #expect(window.contentView != nil)
        #expect(window.delegate != nil)

        SettingsWindowFactory.releaseWindowGraph(window)

        #expect(window.delegate == nil)
        #expect(window.contentView == nil)

        // Idempotent: releasing an already-released window is a no-op.
        SettingsWindowFactory.releaseWindowGraph(window)
        #expect(window.contentView == nil)
    }

    @Test func settingsWindowRejectsToolbarAttachment() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // No toolbar at construction.
        #expect(window.toolbar == nil)

        // The inspector's pane switcher is the navigation. A toolbar would add
        // a second strip above the preview, so SettingsWindow must drop it.
        let toolbar = NSToolbar(identifier: "test.injection")
        window.toolbar = toolbar
        #expect(window.toolbar == nil)
    }

    @Test func settingsWindowHasNoWindowToolbar() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        #expect(controller.window?.toolbar == nil)
    }

    @Test func settingsWindowMinimumWidthMatchesPanelMinimumWidth() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)

        #expect(controller.window?.minSize.width == SettingsSpacing.panelMinWidth)
        #expect(controller.window?.minSize.height == SettingsWindowFactory.minimumContentHeight)
        #expect(SettingsWindowFactory.minimumContentHeight == 620)
        #expect(SettingsSpacing.panelMinWidth == 980)
    }

    @Test func permissionPollingOnlyRunsForThePanesThatShowPermissions() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        drainMainRunLoop()
        #expect(!controller._testPermissionPollingActive)

        controller.selectedSettingsPane = .notifications
        drainMainRunLoop()
        #expect(controller._testPermissionPollingActive)

        controller.selectedSettingsPane = .dictation
        drainMainRunLoop()
        #expect(controller._testPermissionPollingActive)

        for pane in [SettingsPane.appearance, .general, .shortcuts] {
            controller.selectedSettingsPane = .dictation
            controller.selectedSettingsPane = pane
            drainMainRunLoop()
            #expect(!controller._testPermissionPollingActive)
        }
    }

    @Test func windowCloseCancelsPollingAndDeferredWork() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)
        drainMainRunLoop()
        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testPermissionPollingActive)
        #expect(!controller._testHasShowRefreshTask)
        #expect(!controller._testHasDeferredThemeLoadTask)
        #expect(!controller._testHasDeferredFontLoadTask)
        #expect(!controller._testHasDeferredKeybindReloadTask)
        #expect(!controller._testHasWindow)
        #expect(controller._testStoredWindowFrame != nil)
    }

    @Test func repeatedOpenCloseCyclesDoNotLeaveSessionRefreshWorkRunning() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let panes = SettingsPane.allCases

        for cycle in 0..<8 {
            controller.show(pane: panes[cycle % panes.count])
            drainMainRunLoop()
            controller.hide()
            drainMainRunLoop()

            #expect(!controller._testHasShowRefreshTask)
            #expect(!controller._testHasDeferredThemeLoadTask)
            #expect(!controller._testHasDeferredFontLoadTask)
            #expect(!controller._testHasDeferredKeybindReloadTask)
            #expect(!controller._testPermissionPollingActive)
        }

        #expect(!controller._testHasWindow)
    }

    @Test func closingSettingsPreservesSharedStateUsedOutsidePanel() {
        let controller = SettingsController.shared
        reset(controller)

        let originalCopyOnSelect = controller.copyOnSelect
        let originalSplitPaneLabelsEnabled = controller.splitPaneLabelsEnabled
        let originalTabSidebarEnabled = controller.tabSidebarEnabled
        let originalTabSidebarPresentationMode = controller.tabSidebarPresentationMode
        let originalPersistentSidebarVisible = TabSidebarController.persistentVisible
        let originalWindowBorderEnabled = controller.windowBorderEnabled
        let originalWindowBorderColorMode = controller.windowBorderColorMode

        defer {
            controller.copyOnSelect = originalCopyOnSelect
            controller.splitPaneLabelsEnabled = originalSplitPaneLabelsEnabled
            controller.tabSidebarEnabled = originalTabSidebarEnabled
            controller.tabSidebarPresentationMode = originalTabSidebarPresentationMode
            TabSidebarController.shared.setPersistentVisiblePreference(originalPersistentSidebarVisible)
            controller.windowBorderEnabled = originalWindowBorderEnabled
            controller.windowBorderColorMode = originalWindowBorderColorMode
            reset(controller)
        }

        controller.copyOnSelect = false
        controller.splitPaneLabelsEnabled = true
        controller.tabSidebarEnabled = true
        controller.tabSidebarPresentationMode = .persistent
        TabSidebarController.shared.setPersistentVisiblePreference(true)
        controller.windowBorderEnabled = true
        controller.windowBorderColorMode = .manual

        controller.show(pane: .dictation)
        controller.hide()
        drainMainRunLoop()
        controller.show(pane: .general)

        #expect(!controller.copyOnSelect)
        #expect(controller.splitPaneLabelsEnabled)
        #expect(controller.tabSidebarEnabled)
        #expect(controller.tabSidebarPresentationMode == .persistent)
        #expect(TabSidebarController.persistentVisible)
        #expect(controller.windowBorderEnabled)
        #expect(controller.windowBorderColorMode == .manual)
    }

    @Test func repeatedOpenCloseAndPaneSwitchLoopsPreserveSharedState() throws {
        let controller = SettingsController.shared
        reset(controller)

        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let fixtureConfig = fixtureRoot.appendingPathComponent("config.yen")
        try "copy-on-select = false\n".write(to: fixtureConfig, atomically: true, encoding: .utf8)
        SettingsController._testSetConfigPathOverride(fixtureConfig.path)

        let originalCopyOnSelect = controller.copyOnSelect
        let originalSplitPaneLabelsEnabled = controller.splitPaneLabelsEnabled
        let originalTabSidebarEnabled = controller.tabSidebarEnabled
        let originalTabSidebarPresentationMode = controller.tabSidebarPresentationMode
        let originalPersistentSidebarVisible = TabSidebarController.persistentVisible
        let originalWindowBorderEnabled = controller.windowBorderEnabled
        let originalWindowBorderColorMode = controller.windowBorderColorMode
        let panes = SettingsPane.allCases

        defer {
            controller.copyOnSelect = originalCopyOnSelect
            controller.splitPaneLabelsEnabled = originalSplitPaneLabelsEnabled
            controller.tabSidebarEnabled = originalTabSidebarEnabled
            controller.tabSidebarPresentationMode = originalTabSidebarPresentationMode
            TabSidebarController.shared.setPersistentVisiblePreference(originalPersistentSidebarVisible)
            controller.windowBorderEnabled = originalWindowBorderEnabled
            controller.windowBorderColorMode = originalWindowBorderColorMode
            reset(controller)
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: fixtureRoot)
        }

        // Prior tests can load values without persisting them. Reconcile the baseline
        // before assigning preferences whose didSet skips unchanged values.
        controller.loadConfigForTesting()
        controller.loadWorkspacePreferences()
        controller.loadWindowBorderPreferences()

        controller.copyOnSelect = false
        controller.splitPaneLabelsEnabled = true
        controller.tabSidebarEnabled = true
        controller.tabSidebarPresentationMode = .persistent
        TabSidebarController.shared.setPersistentVisiblePreference(true)
        controller.windowBorderEnabled = true
        controller.windowBorderColorMode = .manual

        for _ in 0..<30 {
            controller.show(pane: .general)
            for pane in panes {
                controller.show(pane: pane)
                drainMainRunLoop()
            }
            controller.hide()
            drainMainRunLoop()
        }

        #expect(!controller.copyOnSelect)
        #expect(controller.splitPaneLabelsEnabled)
        #expect(controller.tabSidebarEnabled)
        #expect(controller.tabSidebarPresentationMode == .persistent)
        #expect(TabSidebarController.persistentVisible)
        #expect(controller.windowBorderEnabled)
        #expect(controller.windowBorderColorMode == .manual)
    }

    @Test func aboutAndOnboardingRemainIndependentAfterSettingsClose() {
        let settings = SettingsController.shared
        let about = AboutController.shared
        let onboarding = OnboardingController.shared

        reset(settings)
        about._testResetState()
        onboarding._testResetState()
        defer {
            about.hide()
            about._testResetState()
            onboarding._testResetState()
            reset(settings)
        }

        settings.show(pane: .general)
        settings.hide()
        drainMainRunLoop()

        about.show()
        drainMainRunLoop()
        #expect(about._testHasWindow)
        about.hide()
        drainMainRunLoop()
        #expect(!about._testHasWindow)

        onboarding.show()
        drainMainRunLoop()
        #expect(onboarding._testHasWindow)
        onboarding.dismiss()
        drainMainRunLoop()
        #expect(!onboarding._testHasWindow)
    }

    @Test func configReloadRefreshesKeybindsImmediatelyWhenShortcutsPaneIsVisibleAndIdle() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.selectedSettingsPane = .shortcuts
        controller.keyboardRecordingActive = false

        #expect(controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(!controller.pendingKeybindReloadForTesting)
    }

    @Test func configReloadDefersKeybindRefreshWhileRecorderIsActive() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.selectedSettingsPane = .shortcuts
        controller.keyboardRecordingActive = true

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(controller.pendingKeybindReloadForTesting)
        #expect(!controller.consumePendingKeybindReloadIfReady(isSettingsVisible: true))

        controller.keyboardRecordingActive = false
        #expect(controller.consumePendingKeybindReloadIfReady(isSettingsVisible: true))
        #expect(!controller.pendingKeybindReloadForTesting)
    }

    @Test func endingKeyboardRecordingSchedulesDeferredReloadWhenRefreshIsPending() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .shortcuts)
        waitForSettingsBootstrapToFinish(controller)
        controller.resetKeybindReloadStateForTesting()
        controller.selectedSettingsPane = .shortcuts
        controller.keyboardRecordingActive = true

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(controller.pendingKeybindReloadForTesting)
        #expect(!controller._testHasDeferredKeybindReloadTask)

        controller.keyboardRecordingActive = false

        #expect(!controller.pendingKeybindReloadForTesting)
        #expect(controller._testHasDeferredKeybindReloadTask)
    }

    @Test func configReloadWhileRecorderActiveShowsDeferredReloadStatus() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller._testResetStatusState()
        controller.selectedSettingsPane = .shortcuts
        controller.keyboardRecordingActive = true

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(controller.keybindReloadPendingForUI)
        #expect(controller.statusMessage == "Config changed; list refreshes after recording.")
        #expect(controller.statusSeverity == .info)
    }

    @Test func configReloadDefersKeybindRefreshWhenShortcutsPaneIsNotSelected() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.selectedSettingsPane = .general
        controller.keyboardRecordingActive = false

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(controller.pendingKeybindReloadForTesting)

        controller.selectedSettingsPane = .shortcuts
        #expect(controller.consumePendingKeybindReloadIfReady(isSettingsVisible: true))
        #expect(!controller.pendingKeybindReloadForTesting)
    }

    @Test func selectingShortcutsPaneSchedulesDeferredReloadForPendingKeybindRefresh() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .general)
        waitForSettingsBootstrapToFinish(controller)
        controller.resetKeybindReloadStateForTesting()
        controller.selectedSettingsPane = .general
        controller.keyboardRecordingActive = false

        #expect(!controller.consumeConfigReloadForKeybinds(isSettingsVisible: true))
        #expect(controller.pendingKeybindReloadForTesting)
        #expect(!controller._testHasDeferredKeybindReloadTask)

        controller.selectedSettingsPane = .shortcuts

        #expect(!controller.pendingKeybindReloadForTesting)
        #expect(controller._testHasDeferredKeybindReloadTask)
    }

    @Test func keyboardRecorderStatusHelpersSetTheStatusMessage() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller._testResetStatusState()
        controller.showKeyboardRecorderRejectedStatus(.missingRequiredModifier)
        #expect(controller.statusMessage == KeybindRegistry.missingRequiredModifierValidationMessage)
        #expect(controller.statusSeverity == .warning)

        controller.showKeyboardRecorderRejectedStatus(.unsupportedKey)
        #expect(controller.statusMessage == "That key can't be recorded.")
        #expect(controller.statusSeverity == .warning)

        controller.showKeyboardRecorderRejectedStatus(.reservedFixedShortcut)
        #expect(controller.statusMessage == KeybindRegistry.reservedFixedShortcutValidationMessage)
        #expect(controller.statusSeverity == .warning)

        controller.showKeyboardRecorderStoppedForPaneSwitchStatus()
        #expect(controller.statusMessage == "Shortcut recording stopped.")
        #expect(controller.statusSeverity == .info)
    }

    @Test func reservedFixedShortcutRejectionShowsSharedWarningAndKeepsExistingBinding() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller._testResetStatusState()
        controller.keybindEntries = KeybindRegistry.defaults

        guard let editableEntry = controller.keybindEntries.first(where: {
            $0.action == "paste_from_clipboard" && $0.isEditable
        }) else {
            Issue.record("Missing editable paste_from_clipboard keybind entry")
            return
        }

        let originalTrigger = editableEntry.currentTrigger
        let reservedTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true, shift: true), key: "j")

        #expect(
            controller.updateKeybind(stableId: editableEntry.stableId, trigger: reservedTrigger)
                == .rejected(.reservedFixedShortcut)
        )
        #expect(
            controller.keybindEntries.first(where: { $0.stableId == editableEntry.stableId })?.currentTrigger
                == originalTrigger
        )
        #expect(controller.statusMessage == KeybindRegistry.reservedFixedShortcutValidationMessage)
        #expect(controller.statusSeverity == .warning)
    }

    @Test func resetKeybindIgnoresLockedEntries() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.keybindEntries = KeybindRegistry.defaults

        guard let lockedEntry = controller.keybindEntries.first(where: {
            $0.action == "yen_show_settings" && !$0.isEditable
        }) else {
            Issue.record("Missing locked yen_show_settings keybind entry")
            return
        }

        let lockedStableId = lockedEntry.stableId
        let mutatedTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "y")
        guard let lockedIndex = controller.keybindEntries.firstIndex(where: { $0.stableId == lockedStableId }) else {
            Issue.record("Missing locked yen_show_settings keybind index")
            return
        }

        controller.keybindEntries[lockedIndex].currentTrigger = mutatedTrigger
        controller.keybindEntries[lockedIndex].isUserOverride = true

        controller.resetKeybind(stableId: lockedStableId)

        #expect(
            controller.keybindEntries.first(where: { $0.stableId == lockedStableId })?.currentTrigger
                == mutatedTrigger
        )
        #expect(controller.keybindEntries.first(where: { $0.stableId == lockedStableId })?.isUserOverride == true)
    }

    @Test func loadKeybindsAcceptsLiteralEqualsShortcutOverrides() throws {
        let controller = SettingsController.shared
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "keybind = super+=equalize_splits\n".write(to: configURL, atomically: true, encoding: .utf8)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        controller.loadKeybinds()

        let equalizeEntry = controller.keybindEntries.first(where: { $0.action == "equalize_splits" })
        #expect(equalizeEntry?.currentTrigger == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "equal"))
        #expect(equalizeEntry?.isUserOverride == true)
    }

    @Test func statusNoticeTimerResetsWhenSameMessageIsShownAgain() {
        let controller = SettingsController.shared
        controller._testResetStatusState()
        defer { controller._testResetStatusState() }

        controller._testShowStatus(
            KeybindRegistry.missingRequiredModifierValidationMessage,
            severity: .warning,
            duration: 3
        )
        let firstTimer = controller._testStatusClearWorkItemIdentifier

        controller._testShowStatus(
            KeybindRegistry.missingRequiredModifierValidationMessage,
            severity: .warning,
            duration: 0.35
        )
        let secondTimer = controller._testStatusClearWorkItemIdentifier

        #expect(controller.statusMessage == KeybindRegistry.missingRequiredModifierValidationMessage)
        #expect(controller.statusSeverity == .warning)
        #expect(firstTimer != nil)
        #expect(secondTimer != nil)
        #expect(firstTimer != secondTimer)
    }

    @Test func applicationTerminationFlushesPendingRealTimeConfigSync() throws {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.copyOnSelect = originalCopyOnSelect
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        controller.show(pane: .general)
        drainMainRunLoop()

        controller.copyOnSelect = !originalCopyOnSelect
        #expect(controller._testHasPendingRealTimeConfigSync)

        controller.flushPendingRealTimeConfigSyncForApplicationTermination()

        #expect(!controller._testHasPendingRealTimeConfigSync)
        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("copy-on-select = \((!originalCopyOnSelect) ? "both" : "false")"))
    }


    @Test func externalConfigReloadKeepsAPendingRealTimeEdit() throws {
        // The debounced write reads the controller's values when it fires. An
        // external reload inside that window re-read them from disk, so the write
        // stored the old value and the edit was lost.
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        let originalThemeReloadHook = controller.testThemeNameOnConfigReload
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.testThemeNameOnConfigReload = originalThemeReloadHook
            controller.copyOnSelect = originalCopyOnSelect
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let baselineConfig = "copy-on-select = \(originalCopyOnSelect ? "both" : "false")\n"
        try baselineConfig.write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting(baselineConfig)
        let selectedTheme = controller.selectedTheme
        controller.testThemeNameOnConfigReload = { selectedTheme }

        controller.show(pane: .general)
        waitForSettingsBootstrapToFinish(controller)

        controller.copyOnSelect = !originalCopyOnSelect
        #expect(controller._testHasPendingRealTimeConfigSync)

        // Another writer changes a key Settings does not manage, and the app
        // reloads its config before the debounce ends.
        let externalLine = "mouse-hide-while-typing = true"
        let onDisk = try String(contentsOf: configURL, encoding: .utf8)
        try (onDisk + externalLine + "\n").write(to: configURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)

        // The edit is on disk before the re-read, so the re-read returns it and
        // no later write can replace it.
        #expect(controller.copyOnSelect == !originalCopyOnSelect)
        #expect(!controller._testHasPendingRealTimeConfigSync)

        let contents = try String(contentsOf: configURL, encoding: .utf8)
        #expect(contents.contains("copy-on-select = \((!originalCopyOnSelect) ? "both" : "false")"))
        #expect(contents.contains(externalLine))
    }

    @Test func rapidThemePreviewDoesNotSpamTheStatusNotice() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting("theme = Baseline\n")
        controller._testResetStatusState()

        controller.show(pane: .appearance)
        waitForSettingsBootstrapToFinish(controller)

        for index in 0..<8 {
            controller.applyTheme(
                ThemeInfo(name: "Burst Theme \(index)", path: "/tmp/burst-\(index).yen", bundled: false)
            )
        }
        #expect(controller._testHasPendingThemeSelectionCommit)
        controller.commitPendingThemeSelectionForTesting()
        drainMainRunLoop(for: 0.1)

        // Silent preview reload must not surface a config-reload status notice.
        #expect(!controller.statusMessage.localizedCaseInsensitiveContains("configuration reloaded"))
        #expect(!controller.statusMessage.localizedCaseInsensitiveContains("config reloaded"))
        // A successful burst should not leave an Apply failed status either.
        #expect(!controller.statusMessage.hasPrefix("Apply failed:"))
        #expect(!controller._testHasPendingThemeSelectionCommit)
    }

    @Test func soundPreviewPendingIsCancelledOnWindowClose() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show(pane: .notifications)
        waitForSettingsBootstrapToFinish(controller)

        controller.previewSound("Basso", volume: 0.4)
        #expect(controller._testHasPendingNotificationPreview)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasPendingNotificationPreview)
        #expect(!controller._testHasWindow)
    }

    @Test func closeReopenRestoresFrameAndSurvivesThemeThenSoundPreview() throws {
        let controller = SettingsController.shared
        let originalSelectedTheme = controller.selectedTheme
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)

        SettingsController._testSetConfigPathOverride(configURL.path)
        reset(controller)
        defer {
            controller.selectedTheme = originalSelectedTheme
            controller._testResetStatusState()
            SettingsController._testSetConfigPathOverride(nil)
            try? FileManager.default.removeItem(at: tempRoot)
            reset(controller)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try "theme = Baseline\n".write(to: configURL, atomically: true, encoding: .utf8)
        controller.applyConfigContentsForTesting("theme = Baseline\n")

        controller.show(pane: .appearance)
        waitForSettingsBootstrapToFinish(controller)
        let expectedFrame = NSRect(x: 120, y: 140, width: 1000, height: 720)
        controller.window?.setFrame(expectedFrame, display: false)

        controller.applyTheme(ThemeInfo(name: "Live Theme", path: "/tmp/live.yen", bundled: false))
        #expect(controller._testHasPendingThemeSelectionCommit)
        controller.commitPendingThemeSelectionForTesting()

        controller.show(pane: .notifications)
        controller.previewSound("Pop", volume: 0.5)
        #expect(controller._testHasPendingNotificationPreview)

        controller.hide()
        drainMainRunLoop()
        #expect(!controller._testHasWindow)
        #expect(!controller._testHasPendingNotificationPreview)
        #expect(controller._testStoredWindowFrame == expectedFrame)
        #expect(!controller._testHasPendingThemeSelectionCommit)

        controller.show(pane: .notifications)
        #expect(controller.window?.frame == expectedFrame)
        #expect(controller.selectedSettingsPane == .notifications)
        #expect(!controller.statusMessage.hasPrefix("Apply failed:"))
    }

    private func reset(_ controller: SettingsController) {
        SettingsController._testSetWindowCloseMemoryModeOverride(nil)
        controller.hide()
        drainMainRunLoop()
        controller._testResetWindowState()
        controller.selectedSettingsPane = .appearance
        controller.resetKeybindReloadStateForTesting()
    }

    private func waitForSettingsPaneScrollView(
        _ controller: SettingsController,
        timeout: TimeInterval = 0.35
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while controller._testSettingsPaneScrollView == nil && Date() < deadline {
            drainMainRunLoop()
        }
    }

    private func waitForSettingsBootstrapToFinish(
        _ controller: SettingsController,
        timeout: TimeInterval = 0.3
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while controller._testHasShowRefreshTask, Date() < deadline {
            drainMainRunLoop()
        }
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}

@MainActor
struct OnboardingWindowLifecycleTests {
    @Test func appLaunchAutoShowIsSuppressedUnderXCTest() throws {
        let controller = OnboardingController.shared
        reset(controller)
        defer { reset(controller) }

        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        #expect(isRunningUnderXCTest())
        #expect(OnboardingController.needsOnboarding)

        appDelegate.showOnboardingIfNeeded()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(OnboardingController.needsOnboarding)
    }

    @Test func initialTerminalWindowAutoShowIsSuppressedUnderXCTest() async throws {
        // Assert the DELTA, not a globally empty registry. Earlier suites in a
        // whole-target run leave windowless TerminalControllers in `.all` that no
        // amount of closing can deregister, so the old absolute assertion passed only
        // when this suite happened to run first. What this test actually claims is
        // narrower and order-independent: launching under XCTest must not ADD a
        // terminal window.
        await closeAllTerminalWindows()
        defer { TerminalController.all.forEach { $0.window?.close() } }

        let appDelegate = try #require(NSApp.delegate as? AppDelegate)
        #expect(isRunningUnderXCTest())
        let before = TerminalController.all.count

        appDelegate.launchInitialTerminalWindowIfNeeded()
        drainMainRunLoop()

        #expect(TerminalController.all.count == before)
        await closeAllTerminalWindows()
    }

    @Test func dismissCancelsPollingMarksDismissalAndReleasesWindow() throws {
        let controller = OnboardingController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show()
        let firstWindow = try #require(controller.window)
        #expect(controller._testPollingActive)
        #expect(controller._testHasWindow)

        controller.dismiss()
        drainMainRunLoop()

        #expect(!controller._testPollingActive)
        #expect(!controller._testHasWindow)
        #expect(firstWindow.contentView == nil)
        #expect(firstWindow.delegate == nil)
        #expect(
            UserDefaults.standard.bool(
                forKey: OnboardingController._testHasDismissedSetupKey
            )
        )
        #expect(
            !UserDefaults.standard.bool(
                forKey: OnboardingController._testHasCompletedSetupKey
            )
        )
        #expect(!OnboardingController.needsOnboarding)

        reset(controller)
        controller.show()
        let completedWindow = try #require(controller.window)
        controller.dismiss(markComplete: true)
        drainMainRunLoop()

        #expect(
            UserDefaults.standard.bool(
                forKey: OnboardingController._testHasCompletedSetupKey
            )
        )
        #expect(
            !UserDefaults.standard.bool(
                forKey: OnboardingController._testHasDismissedSetupKey
            )
        )
        #expect(!OnboardingController.needsOnboarding)
        #expect(!controller._testHasWindow)
        #expect(completedWindow.contentView == nil)
        #expect(completedWindow.delegate == nil)

        reset(controller)
        controller.show()
        let window = try #require(controller.window)
        window.performClose(nil)
        drainMainRunLoop()

        #expect(
            UserDefaults.standard.bool(
                forKey: OnboardingController._testHasDismissedSetupKey
            )
        )
        #expect(
            !UserDefaults.standard.bool(
                forKey: OnboardingController._testHasCompletedSetupKey
            )
        )
        #expect(!controller._testHasWindow)
        #expect(window.contentView == nil)
        #expect(window.delegate == nil)
    }

    @Test func preparingForSettingsOpenCancelsPendingFocusReassert() {
        let controller = OnboardingController.shared
        reset(controller)
        defer { reset(controller) }

        controller.show()

        #expect(controller._testHasPendingFocusReassert)
        controller._testPrepareForExternalSettingsTransition()
        #expect(!controller._testHasPendingFocusReassert)
    }

    @Test func completingAfterSkippingClearsTheDismissalPreference() {
        let controller = OnboardingController.shared
        reset(controller)
        defer { reset(controller) }
        controller.show()
        controller.dismiss()
        #expect(UserDefaults.yen.bool(forKey: OnboardingController._testHasDismissedSetupKey))
        controller.show()
        controller.dismiss(markComplete: true)
        #expect(UserDefaults.yen.bool(forKey: OnboardingController._testHasCompletedSetupKey))
        #expect(!UserDefaults.yen.bool(forKey: OnboardingController._testHasDismissedSetupKey))
        #expect(!OnboardingController.needsOnboarding)
    }

    @Test func visibleOnboardingRefreshesStalePermissionStatusFromTheLiveProvider() async {
        let controller = OnboardingController.shared
        reset(controller)
        defer { reset(controller) }
        let dictation = DictationController.shared
        let accessibility = dictation.isAccessibilityGranted
        let microphone = dictation.isMicrophoneGranted
        let speech = dictation.isSpeechRecognitionGranted
        controller.show()
        controller.accessibilityGranted = !accessibility
        controller.microphoneGranted = !microphone
        controller.speechRecognitionGranted = !speech
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if controller.accessibilityGranted == accessibility,
               controller.microphoneGranted == microphone,
               controller.speechRecognitionGranted == speech { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(controller.accessibilityGranted == accessibility)
        #expect(controller.microphoneGranted == microphone)
        #expect(controller.speechRecognitionGranted == speech)
        #expect(controller.allGranted == (accessibility && microphone && speech))
    }

    private func reset(_ controller: OnboardingController) {
        controller._testResetState()
        drainMainRunLoop()
    }

    private func closeAllTerminalWindows() async {
        TerminalController.all.forEach { $0.window?.close() }
        // Controllers deregister from `TerminalController.all` on an async hop, so a
        // fixed `RunLoop.main.run` drain both blocked the main actor and gave up too
        // early -- leaving live controllers behind for whichever suite ran next.
        var spins = 0
        while !TerminalController.all.isEmpty, spins < 200 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            spins += 1
        }
    }

    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
