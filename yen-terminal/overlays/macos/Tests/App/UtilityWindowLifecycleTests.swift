import AppKit
import Testing
@testable import YEN

@Suite(.serialized)
@MainActor
struct UtilityWindowLifecycleTests {
    @Test func closingAboutReleasesWindowAndRecreatesOnNextShow() {
        let controller = AboutController.shared
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
        }

        let originalWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        #expect(originalWindow?.contentView != nil)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(originalWindow?.contentView == nil)
        #expect(originalWindow?.delegate == nil)

        let recreatedWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        #expect(recreatedWindow?.contentView != nil)
        if let originalWindow, let recreatedWindow {
            #expect(recreatedWindow !== originalWindow)
        }
    }

    @Test func closingPullRequestReviewReleasesWindowAndRecreatesOnNextOpen() {
        let controller = PullRequestReviewController.shared
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
        }

        let originalWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(originalWindow?.contentView == nil)
        #expect(originalWindow?.delegate == nil)

        let recreatedWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        if let originalWindow, let recreatedWindow {
            #expect(recreatedWindow !== originalWindow)
        }
    }

    @Test func closingMergeConflictReviewReleasesWindowAndRecreatesOnNextOpen() {
        let controller = MergeConflictResolutionController.shared
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
        }

        let originalWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(originalWindow?.contentView == nil)
        #expect(originalWindow?.delegate == nil)

        let recreatedWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        if let originalWindow, let recreatedWindow {
            #expect(recreatedWindow !== originalWindow)
        }
    }

    @Test func reviewUtilitiesDiscardReleasedWindowShellsBeforeReuse() {
        let prController = PullRequestReviewController.shared
        prController._testResetState()
        defer {
            prController.hide()
            prController._testResetState()
        }

        let originalPRWindow = prController._testEnsureWindow()
        originalPRWindow?.contentView = nil

        let recreatedPRWindow = prController._testEnsureWindow()
        #expect(originalPRWindow?.delegate == nil)
        #expect(recreatedPRWindow?.contentView != nil)
        if let originalPRWindow, let recreatedPRWindow {
            #expect(recreatedPRWindow !== originalPRWindow)
        }

        let mergeController = MergeConflictResolutionController.shared
        mergeController._testResetState()
        defer {
            mergeController.hide()
            mergeController._testResetState()
        }

        let originalMergeWindow = mergeController._testEnsureWindow()
        originalMergeWindow?.contentView = nil

        let recreatedMergeWindow = mergeController._testEnsureWindow()
        #expect(originalMergeWindow?.delegate == nil)
        #expect(recreatedMergeWindow?.contentView != nil)
        if let originalMergeWindow, let recreatedMergeWindow {
            #expect(recreatedMergeWindow !== originalMergeWindow)
        }
    }

    @Test func closingWebPreviewReleasesWindowAndRecreatesOnNextOpen() {
        let controller = WebPreviewController.shared
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
        }

        let originalWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        #expect(originalWindow?.contentView != nil)
        #expect(originalWindow?.toolbar != nil)
        #expect(originalWindow?.isReleasedWhenClosed == false)

        controller.hide()
        drainMainRunLoop()

        #expect(!controller._testHasWindow)
        #expect(originalWindow?.contentView == nil)
        #expect(originalWindow?.delegate == nil)
        #expect(originalWindow?.toolbar == nil)
        #expect(originalWindow?.frameAutosaveName == "")

        let recreatedWindow = controller._testEnsureWindow()
        #expect(controller._testHasWindow)
        #expect(recreatedWindow?.contentView != nil)
        #expect(recreatedWindow?.toolbar != nil)
        if let originalWindow, let recreatedWindow {
            #expect(recreatedWindow !== originalWindow)
        }
    }

    @Test func webPreviewRestoresSavedWindowFrameOnReopen() {
        let controller = WebPreviewController.shared
        let autosaveName = WebPreviewController._testFrameAutosaveName
        let previousSavedFrame = UserDefaults.standard.object(forKey: windowFrameDefaultsKey(named: autosaveName))
        clearSavedWindowFrame(named: autosaveName)
        controller._testResetState()
        defer {
            controller.hide()
            controller._testResetState()
            restoreSavedWindowFrame(previousSavedFrame, named: autosaveName)
        }

        guard let originalWindow = controller._testEnsureWindow() else {
            #expect(controller._testHasWindow)
            return
        }

        #expect(originalWindow.frameAutosaveName == autosaveName)
        let savedFrame = savedFrameForWebPreviewAutosaveTest()
        originalWindow.setFrame(savedFrame, display: false)
        originalWindow.saveFrame(usingName: autosaveName)

        controller.hide()
        drainMainRunLoop()

        guard let recreatedWindow = controller._testEnsureWindow() else {
            #expect(controller._testHasWindow)
            return
        }

        #expect(recreatedWindow.frameAutosaveName == autosaveName)
        #expect(framesMatch(recreatedWindow.frame, savedFrame))
    }

    @Test func webPreviewStandardCloseShortcutOnlyMatchesPlainCommandW() {
        #expect(
            WebPreviewController.isStandardCloseShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: [.command]
            )
        )
        #expect(
            WebPreviewController.isStandardCloseShortcut(
                charactersIgnoringModifiers: "W",
                modifierFlags: [.command]
            )
        )
        #expect(
            !WebPreviewController.isStandardCloseShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: [.command, .shift]
            )
        )
        #expect(
            !WebPreviewController.isStandardCloseShortcut(
                charactersIgnoringModifiers: "q",
                modifierFlags: [.command]
            )
        )
        #expect(
            !WebPreviewController.isStandardCloseShortcut(
                charactersIgnoringModifiers: nil,
                modifierFlags: [.command]
            )
        )
    }

    private func clearSavedWindowFrame(named name: NSWindow.FrameAutosaveName) {
        restoreSavedWindowFrame(nil, named: name)
    }

    private func restoreSavedWindowFrame(_ value: Any?, named name: NSWindow.FrameAutosaveName) {
        let key = windowFrameDefaultsKey(named: name)
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }

    private func windowFrameDefaultsKey(named name: NSWindow.FrameAutosaveName) -> String {
        "NSWindow Frame \(name)"
    }

    private func savedFrameForWebPreviewAutosaveTest() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(CGFloat(920), max(CGFloat(840), visibleFrame.width - 80))
        let height = min(CGFloat(620), max(CGFloat(560), visibleFrame.height - 80))
        let minX = visibleFrame.minX + 20
        let maxX = visibleFrame.maxX - width - 20
        let minY = visibleFrame.minY + 20
        let maxY = visibleFrame.maxY - height - 20
        let proposedX = visibleFrame.midX - (width / 2) + 48
        let proposedY = visibleFrame.midY - (height / 2) - 36
        let x = maxX >= minX ? min(max(proposedX, minX), maxX) : visibleFrame.minX
        let y = maxY >= minY ? min(max(proposedY, minY), maxY) : visibleFrame.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
}
