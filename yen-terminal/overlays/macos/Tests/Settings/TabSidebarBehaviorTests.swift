import AppKit
import Combine
import SwiftUI
import Testing
@testable import YEN

private final class TerminalAuxiliaryAnchorTestIdentity {}

@MainActor
@Suite(.serialized)
struct TabSidebarBehaviorTests {
    @Test func surfaceMetadataBurstPublishesOneRefreshWithFinalValues() async throws {
        var config = YEN.SurfaceConfiguration()
        config.command = "/bin/sleep 60"
        config.workingDirectory = FileManager.default.temporaryDirectory.path
        let controller = TerminalController(try requireAppDelegate().yen, withBaseConfig: config)
        defer { closeTerminalController(controller) }
        let window = try #require(controller.window)
        let surface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = surface
        surface.pwd = FileManager.default.temporaryDirectory.path
        // The engine supplies a fallback title after 500 ms. Finish that unrelated
        // startup event before measuring the synchronous publisher burst.
        await waitUntil(description: "initial terminal title") { !surface.title.isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        var count = 0
        var observedProgress: UInt8?
        let session = TabSidebarObservationSession {
            count += 1
            observedProgress = surface.progressReport?.progress
        }
        defer { session.detach() }
        session.attach(to: window)
        count = 0
        surface.focusInstant = ContinuousClock.now
        surface.pwd = FileManager.default.temporaryDirectory.path
        surface.progressReport = YEN.Action.ProgressReport(state: .set, progress: 12)
        surface.progressReport = YEN.Action.ProgressReport(state: .set, progress: 42)
        try await Task.sleep(for: .milliseconds(200))
        #expect(count == 1)
        #expect(observedProgress == 42)
        let scans = session.testingMetadataScanCount
        #expect(scans == 2) // Initial attachment, then the coalesced surface burst.
        window.title = "Updated title"
        await waitUntil(description: "independent title refresh") { count == 2 }
        #expect(count == 2)
        session.detach()
        surface.progressReport = YEN.Action.ProgressReport(state: .set, progress: 60)
        try await Task.sleep(for: .milliseconds(100))
        #expect(count == 2)
    }

	@Test func transientPanelRestsFlushInsideTheWindowLeftEdge() {
		// Always inside the content area, even when the screen has room beside it.
		let content = NSRect(x: 500, y: 50, width: 900, height: 672)
		let frame = EdgeRevealPanelGeometry.restFrame(
			contentFrame: content,
			edge: .leading,
			width: TabSidebarController.panelWidth
		)

		#expect(frame == NSRect(x: 500, y: 50, width: TabSidebarController.panelWidth, height: 672))
		#expect(EdgeRevealPanelGeometry.sharedWindowCorners(
			panelFrame: frame,
			windowFrame: NSRect(x: 500, y: 50, width: 900, height: 700),
			edge: .leading
		) == [.layerMinXMinYCorner])
	}

	@Test func transientRevealParksContentOneFullWidthPastTheLeftEdge() {
		let reveal = EdgeRevealView(edge: .leading)
		let width = TabSidebarController.panelWidth
		reveal.frame = NSRect(x: 0, y: 0, width: width, height: 700)
		let content = NSView()
		reveal.embed(content, extent: width)

		reveal.park()
		#expect(reveal.slideOffset == -width)
		#expect(content.frame.maxX == 0)
		#expect(reveal.alphaValue == 0)

		// Duration 0 (Reduce Motion) runs the same slide and lands flush.
		reveal.slide(.entering, duration: 0)
		reveal.layoutSubtreeIfNeeded()
		#expect(reveal.isRevealed)
		#expect(content.frame == NSRect(x: 0, y: 0, width: width, height: 700))
	}

	@Test func sidebarHostingViewsUseAppKitOwnedFixedFrameSizing() {
		let model = TabSidebarController.shared
		let floating = TabSidebarHostingViewFactory.make(model: model, style: .floating)
		let docked = TabSidebarHostingViewFactory.make(model: model, style: .docked)
		let panelHeight: CGFloat = 700
		let panel = TabSidebarPanel()
		panel.setFrame(
			NSRect(x: 0, y: 0, width: TabSidebarController.panelWidth, height: panelHeight),
			display: false
		)
		panel.contentView = floating
		panel.contentView?.layoutSubtreeIfNeeded()

		if #available(macOS 13.0, *) {
			#expect(floating.sizingOptions.isEmpty)
			#expect(docked.sizingOptions.isEmpty)
		}
		#expect(floating.frame.height == panelHeight)
		#expect(floating.bounds.height == panelHeight)
	}

	@Test func toggleHotkeyMatchesCommandShiftB() {
		#expect(
			TabSidebarController.isToggleHotkey(
				charactersIgnoringModifiers: "b",
				modifierFlags: [.command, .shift]
			)
		)
		#expect(
			!TabSidebarController.isToggleHotkey(
				charactersIgnoringModifiers: "b",
				modifierFlags: [.command]
			)
		)
		#expect(
			!TabSidebarController.isToggleHotkey(
				charactersIgnoringModifiers: "j",
				modifierFlags: [.command, .shift]
			)
		)
	}

	@Test func disabledToggleHotkeyOnlyConsumesWhenSidebarIsDisabled() {
		#expect(
			TabSidebarController.shouldConsumeDisabledToggleHotkey(
				charactersIgnoringModifiers: "b",
				modifierFlags: [.command, .shift],
				tabSidebarEnabled: false
			)
		)
		#expect(
			!TabSidebarController.shouldConsumeDisabledToggleHotkey(
				charactersIgnoringModifiers: "b",
				modifierFlags: [.command, .shift],
				tabSidebarEnabled: true
			)
		)
	}

	@Test func observationSessionRefreshesWhenSplitTopologyChanges() async throws {
		let appDelegate = try requireAppDelegate()
		let controller = TerminalController(appDelegate.yen)
		defer { closeTerminalController(controller) }

		let window = try #require(controller.window)
		let undoManager = try #require(controller.undoManager)
		let focusedSurface = try #require(controller.surfaceTree.first)
		controller.focusedSurface = focusedSurface

		var onChangeCount = 0
		let session = TabSidebarObservationSession {
			onChangeCount += 1
		}

		session.attach(to: window)
		#expect(onChangeCount == 1)

		_ = try #require(
			performUndoableAction(undoManager) {
				controller.newSplit(at: focusedSurface, direction: .right)
			}
		)

		await waitUntil(description: "split topology refresh") {
			onChangeCount > 1 && Array(controller.surfaceTree).count == 2
		}
	}

	@Test func observationSessionInvalidatesForFocusedSurfaceMetadataPublishers() async throws {
		let appDelegate = try requireAppDelegate()
		let controller = TerminalController(appDelegate.yen)
		defer { closeTerminalController(controller) }

		let window = try #require(controller.window)
		let focusedSurface = try #require(controller.surfaceTree.first)
		controller.focusedSurface = focusedSurface

		var onChangeCount = 0
		let session = TabSidebarObservationSession {
			onChangeCount += 1
		}

		session.attach(to: window)
		#expect(onChangeCount == 1)

		focusedSurface.focusInstant = ContinuousClock.now
		await waitUntil(description: "focus metadata invalidation") {
			onChangeCount > 1
		}

		let focusBaseline = onChangeCount
		focusedSurface.pwd = FileManager.default.temporaryDirectory.path
		await waitUntil(description: "pwd metadata invalidation") {
			onChangeCount > focusBaseline
		}

		let pwdBaseline = onChangeCount
		focusedSurface.progressReport = YEN.Action.ProgressReport(state: .set, progress: 42)
		await waitUntil(description: "progress metadata invalidation") {
			onChangeCount > pwdBaseline
		}

		let progressBaseline = onChangeCount
		NotificationCenter.default.post(name: .yenBellDidRing, object: focusedSurface)
		await waitUntil(description: "bell metadata invalidation") {
			onChangeCount > progressBaseline
		}
	}

	@Test func observationSessionFiltersGitAndBuildNotificationsToObservedFocusedMetadata() async throws {
		let appDelegate = try requireAppDelegate()
		let controller = TerminalController(appDelegate.yen)
		defer { closeTerminalController(controller) }

		let window = try #require(controller.window)
		let focusedSurface = try #require(controller.surfaceTree.first)
		let trustedRoot = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let unrelatedRoot = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: trustedRoot, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: unrelatedRoot, withIntermediateDirectories: true)
		defer {
			try? FileManager.default.removeItem(at: trustedRoot)
			try? FileManager.default.removeItem(at: unrelatedRoot)
		}

		focusedSurface.pwd = trustedRoot.path
		controller.focusedSurface = focusedSurface

		let session = TabSidebarObservationSession {}
		session.attach(to: window)

		let canonicalTrustedRoot = trustedRoot.resolvingSymlinksInPath().standardizedFileURL.path
		let canonicalUnrelatedRoot = unrelatedRoot.resolvingSymlinksInPath().standardizedFileURL.path

		#expect(
			session.testingShouldHandle(
				notificationName: .yenTabSidebarGitContextDidChange,
				object: canonicalTrustedRoot
			)
		)
		#expect(
			!session.testingShouldHandle(
				notificationName: .yenTabSidebarGitContextDidChange,
				object: canonicalUnrelatedRoot
			)
		)
		#expect(
			session.testingShouldHandle(
				notificationName: .yenTabSidebarGitContextDidChange,
				object: nil
			)
		)
		#expect(
			session.testingShouldHandle(
				notificationName: .yenTabSidebarBuildStatusDidChange,
				object: focusedSurface.id
			)
		)
		#expect(
			!session.testingShouldHandle(
				notificationName: .yenTabSidebarBuildStatusDidChange,
				object: UUID()
			)
		)
		#expect(
			session.testingShouldHandle(
				notificationName: YEN.Notification.yenFocusSplit,
				object: nil
			)
		)

		session.detach()
		#expect(
			!session.testingShouldHandle(
				notificationName: .yenTabSidebarGitContextDidChange,
				object: canonicalTrustedRoot
			)
		)
	}

	@Test func dataSourceSkipsDuplicateTabPublishes() {
		final class TestDataSource: TabSidebarDataSource {}

		let dataSource = TestDataSource()
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let tab = TabSidebarItem(
			id: ObjectIdentifier(window),
			window: window,
			title: "Repo",
			shortcut: "1",
			color: .none,
			isSelected: true,
			cwdSummary: "~/Documents/yenchat",
			gitSummary: "main",
			statusSummary: nil,
			statusTone: .neutral
		)

		var publishCount = 0
		let cancellable = dataSource.objectWillChange.sink {
			publishCount += 1
		}

		dataSource.updateTabsIfNeeded([tab])
		dataSource.updateTabsIfNeeded([tab])

		#expect(publishCount == 1)
		withExtendedLifetime(cancellable) {}
	}

	@Test func inlineRenameResolverTreatsNoOpRenameAsNoOverride() {
		#expect(
			TabSidebarInlineRenameResolver.resolvedTitleOverride(
				draftTitle: "Repo",
				initialDraftTitle: "Repo",
				existingOverride: nil
			) == nil
		)
		#expect(
			TabSidebarInlineRenameResolver.resolvedTitleOverride(
				draftTitle: "Renamed",
				initialDraftTitle: "Repo",
				existingOverride: nil
			) == "Renamed"
		)
	}

	@Test func transientRenameUsesNativeWindowEditorWhilePersistentKeepsSidebarInlineRename() {
		#expect(TabSidebarRenameInteraction.resolve(for: .floating) == .nativeWindow)
		#expect(TabSidebarRenameInteraction.resolve(for: .docked) == .sidebarInline)
	}

	@Test func inlineRenameResolverPreservesExistingOverrideWhenUnchanged() {
		#expect(
			TabSidebarInlineRenameResolver.resolvedTitleOverride(
				draftTitle: "Pinned",
				initialDraftTitle: "Pinned",
				existingOverride: "Pinned"
			) == "Pinned"
		)
		#expect(
			TabSidebarInlineRenameResolver.resolvedTitleOverride(
				draftTitle: "",
				initialDraftTitle: "Pinned",
				existingOverride: "Pinned"
			) == nil
		)
	}

	@Test func rowAccessibilityDescriptorIncludesVisibleMetadataAndRenameAction() {
		let descriptor = TabSidebarRowAccessibilityDescriptor(
			tab: makeSidebarTabItem(
				title: "Repo",
				shortcut: "3",
				color: .teal,
				isSelected: true,
				cwdSummary: "~/src/yenchat",
				gitSummary: "main",
				statusSummary: "Building",
				statusTone: .running
			),
			isEditingTitle: false
		)

		#expect(descriptor.label == "Repo, ~/src/yenchat, main, Building, Command 3")
		#expect(descriptor.value == "Selected")
		#expect(descriptor.hint == "Opens this tab. Use the Rename action or context menu to rename.")
		#expect(descriptor.showsRenameAction)
		#expect(TabSidebarRowAccessibilityDescriptor.renameActionName == "Rename")
	}

	@Test func rowAccessibilityDescriptorSuppressesRenameActionWhileEditing() {
		let descriptor = TabSidebarRowAccessibilityDescriptor(
			tab: makeSidebarTabItem(title: "Pinned", isSelected: false),
			isEditingTitle: true
		)

		#expect(descriptor.label == "Pinned")
		#expect(descriptor.value == "Editing title")
		#expect(descriptor.hint == "Finish or cancel the rename to return to the tab list.")
		#expect(!descriptor.showsRenameAction)
	}

	@Test func colorControlAccessibilityDescriptorNamesCurrentColor() {
		let descriptor = TabSidebarColorControlAccessibilityDescriptor(color: .graphite)

		#expect(descriptor.label == "Tab color: Graphite")
		#expect(descriptor.hint == "Change tab color")
	}

	@MainActor
	@Test func detachedObservationSessionIgnoresGlobalNotifications() async {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		var onChangeCount = 0
		let session = TabSidebarObservationSession {
			onChangeCount += 1
		}

		session.attach(to: window)
		#expect(onChangeCount == 1)

		session.detach()
		NotificationCenter.default.post(name: YEN.Notification.yenFocusSplit, object: nil)
		await advanceMainQueueTurn()

		#expect(onChangeCount == 1)
	}

	@Test func transientEscapeDismissalYieldsToActiveFieldEditor() {
		let fieldEditor = NSTextView()
		fieldEditor.isFieldEditor = true

		#expect(
			!TabSidebarController.shouldDismissTransientPanelForEscape(panelFirstResponder: fieldEditor, activeTerminalFirstResponder: nil)
		)
		#expect(
			TabSidebarController.shouldDismissTransientPanelForEscape(panelFirstResponder: NSView(), activeTerminalFirstResponder: nil)
		)
		#expect(
			TabSidebarController.shouldDismissTransientPanelForEscape(panelFirstResponder: nil, activeTerminalFirstResponder: nil)
		)
	}

	@Test func transientEscapeDismissalYieldsToActiveTerminalFieldEditor() {
		let fieldEditor = NSTextView()
		fieldEditor.isFieldEditor = true

		#expect(
			!TabSidebarController.shouldDismissTransientPanelForEscape(
				panelFirstResponder: nil,
				activeTerminalFirstResponder: fieldEditor
			)
		)
		#expect(
			TabSidebarController.shouldDismissTransientPanelForEscape(
				panelFirstResponder: nil,
				activeTerminalFirstResponder: NSView()
			)
		)
	}

	@MainActor
	@Test func observationSessionIgnoresSameWindowReattachment() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		var onChangeCount = 0
		let session = TabSidebarObservationSession {
			onChangeCount += 1
		}

		session.attach(to: window)
		#expect(onChangeCount == 1)

		session.attach(to: window)
		#expect(onChangeCount == 1)
	}

	@MainActor
	@Test func observationSessionRescansTabbedWindowsWithoutReenteringOnChange() async {
		let primary = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let secondary = NSWindow(
			contentRect: NSRect(x: 40, y: 40, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		var onChangeCount = 0
		let session = TabSidebarObservationSession {
			onChangeCount += 1
		}

		session.attach(to: primary)
		#expect(onChangeCount == 1)

		primary.addTabbedWindow(secondary, ordered: .above)
		try? await Task.sleep(nanoseconds: 100_000_000)
		session.rescanObservedWindows()
		#expect(onChangeCount == 1)

		secondary.title = "Observed Secondary Tab"
		try? await Task.sleep(nanoseconds: 50_000_000)
		#expect(onChangeCount == 2)
	}

	@MainActor
	@Test func dockedSidebarModelAttachDoesNotRecurseOnSameWindowRefresh() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let model = DockedTabSidebarModel()

		defer {
			model.setVisible(false)
			model.attach(to: nil)
		}

		model.attach(to: window)
		#expect(model.tabs.count == 1)
	}

	@Test func dockedSidebarFailsClosedForFullscreenAndMiniaturizedWindows() {
		#expect(
			TabSidebarController.canShowDockedSidebar(
				windowControllerIsTerminal: true,
				isFullscreen: false,
				isMiniaturized: false
			)
		)
		#expect(
			!TabSidebarController.canShowDockedSidebar(
				windowControllerIsTerminal: true,
				isFullscreen: true,
				isMiniaturized: false
			)
		)
		#expect(
			!TabSidebarController.canShowDockedSidebar(
				windowControllerIsTerminal: true,
				isFullscreen: false,
				isMiniaturized: true
			)
		)
		#expect(
			!TabSidebarController.canShowDockedSidebar(
				windowControllerIsTerminal: false,
				isFullscreen: false,
				isMiniaturized: false
			)
		)
	}

	@Test func transientAnimationDurationDropsToZeroWhenReduceMotionIsEnabled() {
		#expect(
			TabSidebarController.transientAnimationDuration(reduceMotion: false)
				== TabSidebarController.defaultTransientAnimationDuration
		)
		#expect(TabSidebarController.transientAnimationDuration(reduceMotion: true) == 0)
		#expect(
			SlidingUtilityPanel.animationDuration(
				configuredDuration: 0.35,
				reduceMotion: false
			) == 0.35
		)
		#expect(
			SlidingUtilityPanel.animationDuration(
				configuredDuration: -1,
				reduceMotion: false
			) == 0
		)
		#expect(
			SlidingUtilityPanel.animationDuration(
				configuredDuration: 0.35,
				reduceMotion: true
			) == 0
		)
	}

	@Test func auxiliaryAnchorPolicyDeduplicatesIneligibleCandidatesBeforeFallback() {
		let first = TerminalAuxiliaryAnchorTestIdentity()
		let second = TerminalAuxiliaryAnchorTestIdentity()

		let selected = TerminalAuxiliaryAnchorPolicy.firstEligible(in: [
			TerminalAuxiliaryAnchorPolicy.Candidate(
				identity: ObjectIdentifier(first),
				window: "first-ineligible",
				isEligible: false
			),
			TerminalAuxiliaryAnchorPolicy.Candidate(
				identity: ObjectIdentifier(first),
				window: "first-later-eligible",
				isEligible: true
			),
			TerminalAuxiliaryAnchorPolicy.Candidate(
				identity: ObjectIdentifier(second),
				window: "second",
				isEligible: true
			),
		])

		#expect(selected == "second")
	}

	@Test func expandedFramePrefersGrowingIntoLeftMarginFirst() {
		let frame = NSRect(x: 520, y: 80, width: 900, height: 700)
		let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 900)

		let adjustment = DockedSidebarGeometry.expandedFrame(
			for: frame,
			visibleFrame: visibleFrame,
			sidebarWidth: 300
		)

		#expect(adjustment?.frame == NSRect(x: 220, y: 80, width: 1200, height: 700))
		#expect(adjustment?.expansion == DockedSidebarWindowExpansion(widthDelta: 300, originShift: 300))
	}

	@Test func expandedFrameUsesRightMarginWhenLeftSpaceIsLimited() {
		let frame = NSRect(x: 120, y: 80, width: 900, height: 700)
		let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 900)

		let adjustment = DockedSidebarGeometry.expandedFrame(
			for: frame,
			visibleFrame: visibleFrame,
			sidebarWidth: 300
		)

		#expect(adjustment?.frame == NSRect(x: 0, y: 80, width: 1200, height: 700))
		#expect(adjustment?.expansion == DockedSidebarWindowExpansion(widthDelta: 300, originShift: 120))
	}

	@Test func expandedFrameReturnsNilWhenNoScreenSpaceExists() {
		let frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
		let visibleFrame = NSRect(x: 0, y: 0, width: 1400, height: 900)

		#expect(
			DockedSidebarGeometry.expandedFrame(
				for: frame,
				visibleFrame: visibleFrame,
				sidebarWidth: 300
			) == nil
		)
	}

	@Test func contractedFrameReversesRecordedExpansion() {
		let frame = NSRect(x: 0, y: 80, width: 1200, height: 700)
		let expansion = DockedSidebarWindowExpansion(widthDelta: 300, originShift: 120)

		let contracted = DockedSidebarGeometry.contractedFrame(
			for: frame,
			expansion: expansion,
			minWidth: 400
		)

		#expect(contracted == NSRect(x: 120, y: 80, width: 900, height: 700))
	}

	@Test func rebalancedAdjustmentExpandsAgainWhenRoomIncreases() {
		let currentFrame = NSRect(x: 0, y: 80, width: 1000, height: 700)
		let existingExpansion = DockedSidebarWindowExpansion(widthDelta: 100, originShift: 100)
		let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 900)

		let adjustment = DockedSidebarGeometry.rebalancedAdjustment(
			for: currentFrame,
			existingExpansion: existingExpansion,
			visibleFrame: visibleFrame,
			sidebarWidth: 300,
			minWidth: 400
		)

		#expect(adjustment?.frame == NSRect(x: 0, y: 80, width: 1200, height: 700))
		#expect(adjustment?.expansion == DockedSidebarWindowExpansion(widthDelta: 300, originShift: 100))
	}

	@Test func rebalancedAdjustmentShrinksWhenScreenGetsTighter() {
		let currentFrame = NSRect(x: 220, y: 80, width: 1200, height: 700)
		let existingExpansion = DockedSidebarWindowExpansion(widthDelta: 300, originShift: 300)
		let visibleFrame = NSRect(x: 350, y: 0, width: 1070, height: 900)

		let adjustment = DockedSidebarGeometry.rebalancedAdjustment(
			for: currentFrame,
			existingExpansion: existingExpansion,
			visibleFrame: visibleFrame,
			sidebarWidth: 300,
			minWidth: 400
		)

		#expect(adjustment?.frame == NSRect(x: 350, y: 80, width: 1070, height: 700))
		#expect(adjustment?.expansion == DockedSidebarWindowExpansion(widthDelta: 170, originShift: 170))
	}

	@Test func dockedSidebarDefersWindowCompensationDuringFrameNotifications() async throws {
		try await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.persistent.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
			SettingsController.shared.loadWorkspacePreferences()
			TabSidebarController.shared.testingReloadVisibleStateFromPreferences()

			let visibleFrame = try #require(NSScreen.main?.visibleFrame)
			let baseWidth = min(CGFloat(720), visibleFrame.width - TabSidebarController.panelWidth - 80)
			try #require(baseWidth > 320)
			let baseHeight = min(CGFloat(520), visibleFrame.height - 160)
			try #require(baseHeight > 320)

			let container = makeDockedSidebarTestContainer(
				dockedSidebarVisibility: dockedSidebarVisibilityForMountedWindow
			)
			let window = CountingWindow(
				contentRect: NSRect(
					x: visibleFrame.minX + 60,
					y: visibleFrame.minY + 80,
					width: baseWidth,
					height: baseHeight
				)
			)

			defer {
				window.orderOut(nil)
				window.contentView = NSView()
				TabSidebarController.shared.testingResetState()
			}

			window.contentView = container
			window.orderFrontRegardless()
			await waitUntil(description: "docked sidebar compensated window") {
				container.subviews.count == 2 && window.setFrameCallCount > 0
			}

			let movedFrame = window.frame.offsetBy(dx: 20, dy: 0)
			window.setFrame(movedFrame, display: false)
			let userMoveFrameSetCount = window.setFrameCallCount

			NotificationCenter.default.post(
				name: NSWindow.didMoveNotification,
				object: window
			)

			await advanceMainQueueTurn()
			#expect(window.setFrameCallCount == userMoveFrameSetCount)
			await waitUntil(description: "deferred docked sidebar compensation") {
				window.setFrameCallCount > userMoveFrameSetCount && window.frame != movedFrame
			}
		}
	}

	@Test func terminalViewContainerReattachesWindowScopedObserversAcrossWindowMoves() async {
		var windowScopedUpdateCount = 0
		let container = TerminalViewContainer(
			dockedSidebarVisibility: { window in
				if window != nil {
					windowScopedUpdateCount += 1
				}
				return false
			}
		) {
			Text("Terminal")
				.frame(width: 900, height: 700)
		}

		let firstWindow = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		let secondWindow = NSWindow(
			contentRect: NSRect(x: 40, y: 40, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)

		defer {
			secondWindow.orderOut(nil)
			firstWindow.orderOut(nil)
			firstWindow.contentView = NSView()
			secondWindow.contentView = NSView()
		}

		firstWindow.contentView = container
		await waitUntil(description: "attach to first window") {
			container.window === firstWindow
		}
		await waitUntil(description: "first window attach evaluation") {
			windowScopedUpdateCount > 0
		}

		let firstBaseline = windowScopedUpdateCount
		NotificationCenter.default.post(
			name: NSWindow.didBecomeKeyNotification,
			object: firstWindow
		)
		await waitUntil(description: "first window scoped observer fire") {
			windowScopedUpdateCount == firstBaseline + 1
		}

		firstWindow.contentView = NSView()
		await waitUntil(description: "detach from first window") {
			container.window == nil
		}

		let detachedBaseline = windowScopedUpdateCount
		NotificationCenter.default.post(
			name: NSWindow.didBecomeKeyNotification,
			object: firstWindow
		)
		await advanceMainQueueTurn()
		#expect(windowScopedUpdateCount == detachedBaseline)

		secondWindow.contentView = container
		await waitUntil(description: "attach to second window") {
			container.window === secondWindow
		}
		await waitUntil(description: "second window attach evaluation") {
			windowScopedUpdateCount > detachedBaseline
		}

		let secondBaseline = windowScopedUpdateCount
		NotificationCenter.default.post(
			name: NSWindow.didBecomeKeyNotification,
			object: firstWindow
		)
		await advanceMainQueueTurn()
		#expect(windowScopedUpdateCount == secondBaseline)

		NotificationCenter.default.post(
			name: NSWindow.didBecomeKeyNotification,
			object: secondWindow
		)
		await waitUntil(description: "second window scoped observer fire") {
			windowScopedUpdateCount == secondBaseline + 1
		}
	}

	@Test func dockedSidebarMountPathInstallsAndTogglesInsideWindow() async {
		await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.persistent.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
			SettingsController.shared.loadWorkspacePreferences()
			TabSidebarController.shared.testingReloadVisibleStateFromPreferences()

			let container = makeDockedSidebarTestContainer(
				dockedSidebarVisibility: dockedSidebarVisibilityForMountedWindow
			)
			let baselineWidth = container.intrinsicContentSize.width
			#expect(baselineWidth > 0)

			let window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)

			defer {
				window.orderOut(nil)
				window.contentView = NSView()
			}

			window.contentView = container
			await waitUntil(description: "docked sidebar install") {
				container.subviews.count == 2
			}
			#expect(container.subviews.count == 2)
			#expect(container.intrinsicContentSize.width == baselineWidth + TabSidebarController.panelWidth)

			TabSidebarController.shared.toggle()
			await waitUntil(description: "docked sidebar removal") {
				container.subviews.count == 1
			}
			#expect(container.subviews.count == 1)
			#expect(container.intrinsicContentSize.width == baselineWidth)

			TabSidebarController.shared.toggle()
			await waitUntil(description: "docked sidebar reinstall") {
				container.subviews.count == 2
			}
			#expect(container.subviews.count == 2)
			#expect(container.intrinsicContentSize.width == baselineWidth + TabSidebarController.panelWidth)
		}
	}

	@Test func dockedSidebarRemountsAcrossFullscreenTransitions() async throws {
		await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.persistent.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			defaults.set(true, forKey: TabSidebarPreferences.persistentVisiblePreferenceKey)
			SettingsController.shared.loadWorkspacePreferences()
			TabSidebarController.shared.testingReloadVisibleStateFromPreferences()

			let container = makeDockedSidebarTestContainer(
				dockedSidebarVisibility: { window in
					guard let window else { return false }
					guard TabSidebarController.tabSidebarEnabled else { return false }
					guard TabSidebarController.presentationMode == .persistent else { return false }
					guard TabSidebarController.persistentVisible else { return false }
					return TabSidebarController.canShowDockedSidebar(
						windowControllerIsTerminal: true,
						isFullscreen: window.yenIsEffectivelyFullscreen,
						isMiniaturized: window.isMiniaturized
					)
				}
			)
			let window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)

			defer {
				window.orderOut(nil)
				window.contentView = NSView()
				TabSidebarController.shared.testingResetState()
			}

			window.contentView = container
			await waitUntil(description: "docked sidebar mount before fullscreen") {
				container.subviews.count == 2
			}
			#expect(container.subviews.count == 2)

			window.yenNativeFullscreenTransitionPhase = .entering

			await waitUntil(description: "docked sidebar hide for fullscreen") {
				container.subviews.count == 1
			}
			#expect(container.subviews.count == 1)

			window.yenNativeFullscreenTransitionPhase = .none

			await waitUntil(description: "docked sidebar remount after fullscreen") {
				container.subviews.count == 2
			}
			#expect(container.subviews.count == 2)
		}
	}

	@MainActor
	@Test func switchingFromVisibleTransientPanelToPersistentDismissesFloatingPanel() async {
		await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let controller = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			controller.testingConfigureFloatingPanel(panel, visible: true)

			defer {
				panel.orderOut(nil)
				controller.testingResetState()
			}

			controller.setPresentationMode(.persistent)

			#expect(TabSidebarController.presentationMode == .persistent)
			#expect(TabSidebarController.persistentVisible)
			#expect(controller.visible)
			#expect(!panel.isVisible)
		}
	}

	@MainActor
	@Test func immediateTransientDismissInvalidatesMetadataCache() throws {
		let terminalController = makeTerminalBackedController(title: "Dismiss Cache")
		let terminalWindow = try #require(terminalController.window)
		let sidebar = TabSidebarController.shared
		let panel = TabSidebarPanel()
		panel.orderFrontRegardless()
		sidebar.testingConfigureFloatingPanel(panel, visible: true)

		defer {
			panel.orderOut(nil)
			closeTerminalController(terminalController)
			sidebar.testingResetState()
			TabSidebarController.testingResetMetadataCache()
		}

		TabSidebarController.testingResetMetadataCache()
		_ = TabSidebarController.items(for: terminalWindow)
		let cachedBuildCount = TabSidebarController.testingMetadataCacheBuildCount
		#expect(cachedBuildCount > 0)

		_ = TabSidebarController.items(for: terminalWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount == cachedBuildCount)

		sidebar.testingResetState()
		_ = TabSidebarController.items(for: terminalWindow)
		#expect(TabSidebarController.testingMetadataCacheBuildCount > cachedBuildCount)
	}

	@MainActor
	@Test func transientFloatingPanelOrdersOutWhenNonTerminalWindowBecomesKey() async {
		await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let controller = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			controller.testingConfigureFloatingPanel(panel, visible: true)

			let settingsWindow = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)

			defer {
				settingsWindow.orderOut(nil)
				panel.orderOut(nil)
				controller.testingResetState()
			}

			controller.testingHandleWindowDidBecomeKey(settingsWindow)

			#expect(controller.visible)
			#expect(!panel.isVisible)
		}
	}

	@MainActor
	@Test func transientFloatingPanelOrdersOutWhenAnchorWindowMiniaturizes() async throws {
		try await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let sidebar = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			sidebar.testingConfigureFloatingPanel(panel, visible: true)

			let terminalController = makeTerminalBackedController(title: "Minimized Terminal")
			let terminalWindow = try #require(terminalController.window)

			defer {
				panel.orderOut(nil)
				closeTerminalController(terminalController)
				sidebar.testingResetState()
			}

			sidebar.testingHandleWindowDidBecomeKey(terminalWindow)
			#expect(sidebar.visible)
			#expect(panel.isVisible)

			sidebar.testingHandleWindowDidMiniaturize(terminalWindow)

			#expect(sidebar.visible)
			#expect(!panel.isVisible)
			#expect(sidebar.tabs.isEmpty)
		}
	}

	@MainActor
	@Test func transientFloatingPanelResumesWhenTerminalRegainsKeyAfterNonTerminalHide() async throws {
		try await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let controller = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			controller.testingConfigureFloatingPanel(panel, visible: true)

			let settingsWindow = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
			let terminalController = makeTerminalBackedController(title: "Resumed Terminal")
			let terminalWindow = try #require(terminalController.window)

			defer {
				settingsWindow.orderOut(nil)
				panel.orderOut(nil)
				closeTerminalController(terminalController)
				controller.testingResetState()
			}

			controller.testingHandleWindowDidBecomeKey(settingsWindow)
			#expect(controller.visible)
			#expect(!panel.isVisible)

			controller.testingHandleWindowDidBecomeKey(terminalWindow)

			#expect(controller.visible)
			#expect(panel.isVisible)
			#expect(controller.tabs.count == 1)
			#expect(controller.tabs.first?.window === terminalWindow)
		}
	}

	@MainActor
	@Test func transientFloatingPanelOrdersOutDuringNativeFullscreenTransitionAndResumesAfterExit() async throws {
		try await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let controller = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			controller.testingConfigureFloatingPanel(panel, visible: true)

			let terminalController = makeTerminalBackedController(title: "Fullscreen Transition")
			let terminalWindow = try #require(terminalController.window)

			defer {
				panel.orderOut(nil)
				closeTerminalController(terminalController)
				controller.testingResetState()
			}

			controller.testingHandleWindowDidBecomeKey(terminalWindow)
			#expect(panel.isVisible)

			terminalWindow.yenNativeFullscreenTransitionPhase = .entering
			controller.testingHandleNativeFullscreenStateChange(terminalWindow)
			#expect(!panel.isVisible)

			terminalWindow.yenNativeFullscreenTransitionPhase = .none
			controller.testingHandleNativeFullscreenStateChange(terminalWindow)
			#expect(panel.isVisible)
			#expect(controller.visible)
			#expect(controller.tabs.count == 1)
			#expect(controller.tabs.first?.window === terminalWindow)
		}
	}

	@MainActor
	@Test func transientFloatingPanelHandsOffToReplacementTerminalOnClose() async {
		await withIsolatedDockedSidebarPreferences {
			let defaults = UserDefaults.standard
			defaults.set(true, forKey: TabSidebarPreferences.enabledPreferenceKey)
			defaults.set(
				TabSidebarPresentationMode.transient.rawValue,
				forKey: TabSidebarPreferences.presentationModePreferenceKey
			)
			SettingsController.shared.loadWorkspacePreferences()

			let controller = TabSidebarController.shared
			let panel = TabSidebarPanel()
			panel.orderFrontRegardless()
			controller.testingConfigureFloatingPanel(panel, visible: true)

			let closingWindow = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
			closingWindow.title = "Closing"

			let replacementWindow = NSWindow(
				contentRect: NSRect(x: 40, y: 40, width: 900, height: 700),
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
			replacementWindow.title = "Replacement"

			defer {
				replacementWindow.orderOut(nil)
				closingWindow.orderOut(nil)
				panel.orderOut(nil)
				controller.testingResetState()
			}

			controller.testingHandleClosingWindow(closingWindow, replacementWindow: replacementWindow)

			#expect(controller.visible)
			#expect(panel.isVisible)
			#expect(controller.tabs.count == 1)
			#expect(controller.tabs.first?.window === replacementWindow)
		}
	}

	private func dockedSidebarVisibilityForMountedWindow(_ window: NSWindow?) -> Bool {
		guard let window else { return false }
		guard TabSidebarController.tabSidebarEnabled else { return false }
		guard TabSidebarController.presentationMode == .persistent else { return false }
		guard TabSidebarController.persistentVisible else { return false }
		return TabSidebarController.canShowDockedSidebar(
			windowControllerIsTerminal: true,
			isFullscreen: window.yenIsEffectivelyFullscreen,
			isMiniaturized: window.isMiniaturized
		)
	}

	private func waitUntil(
		timeout: TimeInterval = 1.0,
		description: String,
		condition: @escaping @MainActor () -> Bool
	) async {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if condition() {
				return
			}
			await advanceMainQueueTurn()
		}

		Issue.record("Timed out waiting for \(description)")
	}

	private func advanceMainQueueTurn() async {
		try? await Task.sleep(nanoseconds: 10_000_000)
		await Task.yield()
	}

	private func makeDockedSidebarTestContainer(
		dockedSidebarVisibility: @escaping (NSWindow?) -> Bool
	) -> TerminalViewContainer {
		let terminalView = FixedIntrinsicSizeView(
			intrinsicSize: NSSize(width: 900, height: 700)
		)
		let sidebarView = FixedIntrinsicSizeView(
			intrinsicSize: NSSize(width: TabSidebarController.panelWidth, height: 700)
		)
		let container = TerminalViewContainer(
			terminalContentView: terminalView,
			dockedSidebarVisibility: dockedSidebarVisibility,
			dockedSidebarHostingViewFactory: { _ in sidebarView }
		)
		container.initialContentSize = terminalView.intrinsicContentSize
		return container
	}

	private func withIsolatedDockedSidebarPreferences(
		_ operation: () async throws -> Void
	) async rethrows {
		try await TestExclusiveLock.withLock(named: "workspace-preferences") {
			let defaults = UserDefaults.standard
			let keys = [
				TabSidebarPreferences.enabledPreferenceKey,
				TabSidebarPreferences.presentationModePreferenceKey,
				TabSidebarPreferences.persistentVisiblePreferenceKey,
				ScratchpadController.scratchpadEnabledPreferenceKey,
				BackgroundImageScopePreferences.preferenceKey,
			]
			let controller = SettingsController.shared
			let originalState = controller.captureWorkspacePreferenceState()

			var originalValues: [String: Any] = [:]
			for key in keys {
				if let value = defaults.object(forKey: key) {
					originalValues[key] = value
				}
				defaults.removeObject(forKey: key)
			}

			defer {
				controller.restoreWorkspacePreferenceState(originalState)

				for key in keys {
					defaults.removeObject(forKey: key)
					if let original = originalValues[key] {
						defaults.set(original, forKey: key)
					}
				}
			}

			try await operation()
		}
	}

	private func requireAppDelegate() throws -> AppDelegate {
		try #require(NSApp.delegate as? AppDelegate)
	}

	private func performUndoableAction<T>(
		_ undoManager: UndoManager,
		_ body: () throws -> T
	) rethrows -> T {
		undoManager.beginUndoGrouping()
		defer { undoManager.endUndoGrouping() }
		return try body()
	}

	private func makeTerminalBackedController(title: String) -> TerminalController {
		guard let appDelegate = NSApp.delegate as? AppDelegate else {
			fatalError("Expected AppDelegate-backed test host.")
		}

		let controller = TerminalController(appDelegate.yen)
		controller.window?.title = title
		return controller
	}

	private func closeTerminalController(_ controller: TerminalController) {
		controller.window?.close()
		RunLoop.main.run(until: Date().addingTimeInterval(0.02))
	}

	private final class FixedIntrinsicSizeView: NSView {
		private let size: NSSize

		init(intrinsicSize: NSSize) {
			self.size = intrinsicSize
			super.init(frame: NSRect(origin: .zero, size: intrinsicSize))
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("init(coder:) has not been implemented")
		}

		override var intrinsicContentSize: NSSize {
			size
		}
	}

	private final class CountingWindow: NSWindow {
		var setFrameCallCount = 0

		init(contentRect: NSRect) {
			super.init(
				contentRect: contentRect,
				styleMask: [.titled, .closable, .resizable],
				backing: .buffered,
				defer: false
			)
		}

		override func setFrame(_ frameRect: NSRect, display flag: Bool) {
			setFrameCallCount += 1
			super.setFrame(frameRect, display: flag)
		}
	}

	private func makeSidebarTabItem(
		title: String,
		shortcut: String? = nil,
		color: TerminalTabColor = .none,
		isSelected: Bool,
		cwdSummary: String? = nil,
		gitSummary: String? = nil,
		statusSummary: String? = nil,
		statusTone: TabSidebarStatusTone = .neutral
	) -> TabSidebarItem {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: false
		)
		return TabSidebarItem(
			id: ObjectIdentifier(window),
			window: window,
			title: title,
			shortcut: shortcut,
			color: color,
			isSelected: isSelected,
			cwdSummary: cwdSummary,
			gitSummary: gitSummary,
			statusSummary: statusSummary,
			statusTone: statusTone
		)
	}

	@Test func gitContextCachePolicyEvictsStaleEntriesAndCapsToNewest() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		let interval: TimeInterval = 15
		// Eviction cutoff is referenceDate - 4× interval (= 60s): older entries are dropped.
		let retained = TabSidebarGitContextCachePolicy.retainedKeys(
			refreshDates: [
				"/fresh": now.addingTimeInterval(-10),
				"/edge": now.addingTimeInterval(-59),
				"/stale": now.addingTimeInterval(-61),
			],
			referenceDate: now,
			refreshInterval: interval,
			maximumEntries: 128
		)
		#expect(retained == ["/fresh", "/edge"])

		// Cap: three fresh entries with maximumEntries = 2 keeps the two most-recently-refreshed.
		let capped = TabSidebarGitContextCachePolicy.retainedKeys(
			refreshDates: [
				"/old": now.addingTimeInterval(-30),
				"/mid": now.addingTimeInterval(-20),
				"/new": now.addingTimeInterval(-10),
			],
			referenceDate: now,
			refreshInterval: interval,
			maximumEntries: 2
		)
		#expect(capped == ["/mid", "/new"])
	}
}
