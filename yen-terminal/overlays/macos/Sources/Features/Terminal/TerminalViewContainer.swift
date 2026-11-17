import AppKit
import SwiftUI

struct DockedSidebarWindowExpansion: Equatable {
	let widthDelta: CGFloat
	let originShift: CGFloat
}

struct DockedSidebarFrameAdjustment: Equatable {
	let frame: NSRect
	let expansion: DockedSidebarWindowExpansion
}

enum DockedSidebarGeometry {
	static func expandedFrame(
		for frame: NSRect,
		visibleFrame: NSRect,
		sidebarWidth: CGFloat
	) -> DockedSidebarFrameAdjustment? {
		let availableLeft = max(0, frame.minX - visibleFrame.minX)
		let availableRight = max(0, visibleFrame.maxX - frame.maxX)
		let widthDelta = min(sidebarWidth, availableLeft + availableRight)
		guard widthDelta > 0 else { return nil }

		let originShift = min(widthDelta, availableLeft)
		var expanded = frame
		expanded.origin.x -= originShift
		expanded.size.width += widthDelta

		return .init(
			frame: expanded,
			expansion: .init(widthDelta: widthDelta, originShift: originShift)
		)
	}

	static func contractedFrame(
		for frame: NSRect,
		expansion: DockedSidebarWindowExpansion,
		minWidth: CGFloat
	) -> NSRect {
		let widthDelta = min(expansion.widthDelta, max(0, frame.width - minWidth))
		guard widthDelta > 0 else { return frame }

		var contracted = frame
		contracted.size.width -= widthDelta
		contracted.origin.x += min(expansion.originShift, widthDelta)
		return contracted
	}

	static func rebalancedAdjustment(
		for frame: NSRect,
		existingExpansion: DockedSidebarWindowExpansion?,
		visibleFrame: NSRect,
		sidebarWidth: CGFloat,
		minWidth: CGFloat
	) -> DockedSidebarFrameAdjustment? {
		let baselineFrame: NSRect
		if let existingExpansion {
			baselineFrame = contractedFrame(
				for: frame,
				expansion: existingExpansion,
				minWidth: minWidth
			)
		} else {
			baselineFrame = frame
		}

		return expandedFrame(
			for: baselineFrame,
			visibleFrame: visibleFrame,
			sidebarWidth: sidebarWidth
		)
	}
}

/// Use this container to achieve a glass effect at the window level.
/// Modifying `NSThemeFrame` can sometimes be unpredictable.
class TerminalViewContainer: NSView {
	private let terminalView: NSView
	private let shouldShowDockedSidebarInWindow: (NSWindow?) -> Bool
	private let makeDockedSidebarHostingView: (DockedTabSidebarModel) -> NSView
	private var terminalLeadingConstraint: NSLayoutConstraint?
	private var terminalBottomConstraint: NSLayoutConstraint?
	private var dockedSidebarWidthConstraint: NSLayoutConstraint?
	private var dockedSidebarHostingView: NSView?
	private var dockedSidebarModel: DockedTabSidebarModel?
	private var dockedSidebarWindowExpansion: DockedSidebarWindowExpansion?
	private var dockedSidebarWindowCompensationSuppressed = false
	private var dockedSidebarUpdateScheduled = false
	private var dockedSidebarLayoutScheduled = false
	private var dockedSidebarActivationScheduled = false
	private var dockedSidebarWindowCompensationWorkItem: DispatchWorkItem?
	#if DEBUG
	var testingHasPendingSidebarCompensation: Bool { dockedSidebarWindowCompensationWorkItem != nil }
	#endif
	/// The reused drawer hosting view (owned by `GitDrawerController`, re-passed on
	/// every refresh). nil when no drawer is attached.
	private var gitDrawerHostingView: NSView?
	/// The bottom-edge reveal that clips the sliding drawer. Lives only while a drawer
	/// is attached; inserted `.above` the terminal view.
	private var gitDrawerClipView: EdgeRevealView?
	/// Height of the clip (== resting drawer height `H`). This is what
	/// `gitDrawerHeight` reports. Pinned at `H` for the drawer's whole lifetime; it
	/// never animates to or from 0, so there is no accordion.
	private var gitDrawerClipHeightConstraint: NSLayoutConstraint?
	/// Guards the slide-out completion against a re-open racing in on a fresh drawer:
	/// each close bumps this, and the deferred teardown only runs if its captured
	/// generation still matches.
	private var gitDrawerCloseGeneration = 0
	/// True while an animated slide-out is in flight. Makes `gitDrawerHeight` report
	/// `nil` immediately on close so the open/closed contract matches the controller's
	/// `isVisible` rather than lagging by the animation duration.
	private var gitDrawerClosing = false
	/// The Git drawer controller hosted in this container, if one has been opened.
	/// Owned here (not on AppDelegate) so it deallocates with the container —
	/// running `GitDrawerController.deinit` to cancel its refresh task, invalidate
	/// its 15s fallback timer, and remove its observers + key monitor. Keying a
	/// process-lifetime map by `ObjectIdentifier(container)` previously leaked these
	/// per closed window and could collide on a recycled container address.
	var gitDrawerController: GitDrawerController?
	private var sidebarObservers: [NSObjectProtocol] = []
	private var windowScopedObservers: [NSObjectProtocol] = []
	private weak var observedWindow: NSWindow?

	private static let dockedSidebarWindowCompensationDelay: TimeInterval = 0.08

	/// Background color applied with glass effect
	private(set) var glassEffectView: NSView?
	private var derivedConfig: DerivedConfig?

	var windowThemeFrameView: NSView? {
		window?.contentView?.superview
	}

	var windowCornerRadius: CGFloat? {
		guard let window, window.responds(to: Selector(("_cornerRadius"))) else {
			return nil
		}

		return window.value(forKey: "_cornerRadius") as? CGFloat
	}

	convenience init<Root: View>(
		dockedSidebarVisibility: @escaping (NSWindow?) -> Bool = { window in
			MainActor.assumeIsolated {
				TabSidebarController.shouldShowDockedSidebar(in: window)
			}
		},
		dockedSidebarHostingViewFactory: @escaping (DockedTabSidebarModel) -> NSView = TerminalViewContainer.defaultDockedSidebarHostingView,
		@ViewBuilder rootView: () -> Root
	) {
		let terminalView = NSHostingView(rootView: rootView())
		self.init(
			terminalContentView: terminalView,
			dockedSidebarVisibility: dockedSidebarVisibility,
			dockedSidebarHostingViewFactory: dockedSidebarHostingViewFactory
		)
	}

	init(
		terminalContentView: NSView,
		dockedSidebarVisibility: @escaping (NSWindow?) -> Bool = { window in
			MainActor.assumeIsolated {
				TabSidebarController.shouldShowDockedSidebar(in: window)
			}
		},
		dockedSidebarHostingViewFactory: @escaping (DockedTabSidebarModel) -> NSView = TerminalViewContainer.defaultDockedSidebarHostingView
	) {
		self.terminalView = terminalContentView
		self.shouldShowDockedSidebarInWindow = dockedSidebarVisibility
		self.makeDockedSidebarHostingView = dockedSidebarHostingViewFactory
		super.init(frame: .zero)
		setup()
		installDockedSidebarObservers()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		dockedSidebarWindowCompensationWorkItem?.cancel()
		reverseDockedSidebarWindowCompensationIfNeeded()
		MainActor.assumeIsolated {
			dockedSidebarModel?.setVisible(false)
			dockedSidebarModel?.attach(to: nil)
		}
		let center = NotificationCenter.default
		for observer in windowScopedObservers {
			center.removeObserver(observer)
		}
		for observer in sidebarObservers {
			center.removeObserver(observer)
		}
	}

	/// The initial content size to use as a fallback before the SwiftUI
	/// view hierarchy has completed layout (i.e. before @FocusedValue
	/// propagates `lastFocusedSurface`). Once the hosting view reports
	/// a valid intrinsic size, this fallback is no longer used.
	var initialContentSize: NSSize?

	/// To make ``TerminalController/DefaultSize/contentIntrinsicSize``
	/// work in ``TerminalController/windowDidLoad()``,
	/// we override this to provide the correct size.
	override var intrinsicContentSize: NSSize {
		let hostingSize = terminalView.intrinsicContentSize
		var size: NSSize
		if let initialContentSize,
		   hostingSize.width < initialContentSize.width || hostingSize.height < initialContentSize.height {
			size = initialContentSize
		} else {
			size = hostingSize
		}
		if dockedSidebarHostingView != nil {
			size.width += TabSidebarController.panelWidth
		}
		return size
	}

	private func setup() {
		addSubview(terminalView)
		terminalView.translatesAutoresizingMaskIntoConstraints = false
		let leading = terminalView.leadingAnchor.constraint(equalTo: leadingAnchor)
		terminalLeadingConstraint = leading
		let bottom = terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
		terminalBottomConstraint = bottom

		NSLayoutConstraint.activate([
			terminalView.topAnchor.constraint(equalTo: topAnchor),
			leading,
			bottom,
			terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])
	}

	var gitDrawerHeight: CGFloat? {
		gitDrawerClosing ? nil : gitDrawerClipHeightConstraint?.constant
	}

	func setGitDrawerHostingView(
		_ hostingView: NSView?,
		preferredHeight: CGFloat,
		animationDuration: TimeInterval = 0
	) {
		if let hostingView {
			let height = CGFloat(GitDrawerHeightPolicy.clampedHeight(
				Double(preferredHeight),
				windowHeight: Double(max(bounds.height, 1))
			))

			// FIRST ATTACH for THIS hosting view: build the clip + drawer hierarchy and
			// play the slide-in. This is the ONLY place the slide-in plays. Reduce Motion
			// still parks then runs the same envelope at duration 0 (no second path).
			if gitDrawerHostingView !== hostingView {
				// Invalidate any in-flight close BEFORE tearing down, so a stale slide-out
				// completion can't yank out the fresh drawer we're about to attach.
				gitDrawerCloseGeneration += 1
				gitDrawerClosing = false
				if gitDrawerClipView != nil {
					teardownGitDrawer()
				}

				let clip = EdgeRevealView(edge: .bottom)
				clip.translatesAutoresizingMaskIntoConstraints = false
				// The drawer rises from the bottom, so only its top corners face the
				// terminal; the window's own rounded corners clip the bottom ones.
				clip.corners = .init(
					radius: YENDesignTokens.terminalFacingCornerRadius,
					mask: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
				)
				addSubview(clip, positioned: .above, relativeTo: terminalView)
				gitDrawerClipView = clip

				let clipHeight = clip.heightAnchor.constraint(equalToConstant: height)
				gitDrawerClipHeightConstraint = clipHeight
				NSLayoutConstraint.activate([
					clip.leadingAnchor.constraint(equalTo: leadingAnchor),
					clip.trailingAnchor.constraint(equalTo: trailingAnchor),
					clip.bottomAnchor.constraint(equalTo: bottomAnchor),
					clipHeight,
				])

				// Embed at constant height `H`, then park one full height below the edge
				// at alpha 0 (vendor setInitial) and slide to rest (vendor setFinal).
				// Reduce Motion runs the same reveal at duration 0.
				clip.embed(hostingView, extent: height)
				gitDrawerHostingView = hostingView
				clip.park(layoutRoot: self)
				window?.invalidateRestorableState()
				clip.slide(.entering, duration: animationDuration, layoutRoot: self)
				return
			}

			// REFRESH of the SAME hosting view (content reload / 15s fallback / resize).
			// Only react to an actual height change; NEVER touch the slide or alpha, so
			// an async refresh landing mid-slide cannot snap the animation to its end.
			// `H` depends only on window height, so it is unchanged except on resize.
			if gitDrawerClipHeightConstraint?.constant != height {
				gitDrawerClipHeightConstraint?.constant = height
				gitDrawerClipView?.setExtent(height)
				needsLayout = true
				layoutSubtreeIfNeeded()
			}
			window?.invalidateRestorableState()
			return
		}

		// REMOVAL (close).
		guard let clip = gitDrawerClipView, gitDrawerHostingView != nil else {
			// Nothing attached: make sure we are fully torn down.
			teardownGitDrawer()
			window?.invalidateRestorableState()
			return
		}
		// Slide back behind the bottom edge and fade out, then tear down on completion.
		gitDrawerCloseGeneration += 1
		gitDrawerClosing = true
		let generation = gitDrawerCloseGeneration
		clip.slide(.exiting, duration: animationDuration, layoutRoot: self, completion: { [weak self] in
			guard let self, self.gitDrawerCloseGeneration == generation else { return }
			self.teardownGitDrawer()
			self.needsLayout = true
			self.layoutSubtreeIfNeeded()
			self.window?.invalidateRestorableState()
		})
		window?.invalidateRestorableState()
	}

	private func teardownGitDrawer() {
		gitDrawerHostingView?.removeFromSuperview()
		gitDrawerHostingView = nil
		// Removing the clip view drops all of its nested constraints (clip height,
		// drawer height, slide, edges) automatically.
		gitDrawerClipView?.removeFromSuperview()
		gitDrawerClipView = nil
		gitDrawerClipHeightConstraint = nil
		gitDrawerClosing = false
	}

	private func installDockedSidebarObservers() {
		let center = NotificationCenter.default

		// Window-independent: posted with object: nil by TabSidebarController
		sidebarObservers.append(
			center.addObserver(
				forName: .yenTabSidebarStateDidChange,
				object: nil,
				queue: .main
			) { [weak self] _ in
				self?.scheduleDockedSidebarUpdate()
			}
		)
	}

	private func installWindowScopedObservers(for window: NSWindow) {
		removeWindowScopedObservers()
		observedWindow = window
		let center = NotificationCenter.default

		let scheduleNames: [Notification.Name] = [
			NSWindow.didBecomeKeyNotification,
			NSWindow.didResignKeyNotification,
			.yenNativeFullscreenTransitionDidChange,
			NSWindow.didMiniaturizeNotification,
			NSWindow.didDeminiaturizeNotification,
		]
		for name in scheduleNames {
			windowScopedObservers.append(
				center.addObserver(
					forName: name,
					object: window,
					queue: .main
				) { [weak self] _ in
					self?.scheduleDockedSidebarUpdate()
				}
			)
		}

		let recomputeNames: [Notification.Name] = [
			NSWindow.didMoveNotification,
			NSWindow.didResizeNotification,
			NSWindow.didChangeScreenNotification,
		]
		for name in recomputeNames {
			windowScopedObservers.append(
				center.addObserver(
					forName: name,
					object: window,
					queue: .main
				) { [weak self] _ in
					self?.scheduleDockedSidebarWindowCompensation()
				}
			)
		}
	}

	private func removeWindowScopedObservers() {
		dockedSidebarWindowCompensationWorkItem?.cancel()
		dockedSidebarWindowCompensationWorkItem = nil
		let center = NotificationCenter.default
		for observer in windowScopedObservers {
			center.removeObserver(observer)
		}
		windowScopedObservers.removeAll()
		observedWindow = nil
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if let window {
			if window !== observedWindow {
				installWindowScopedObservers(for: window)
			}
		} else {
			removeWindowScopedObservers()
		}
		scheduleDockedSidebarUpdate()
		updateGlassEffectIfNeeded()
		updateGlassEffectTopInsetIfNeeded()
	}

	override func layout() {
		super.layout()
		updateGlassEffectTopInsetIfNeeded()
	}

	func yenConfigDidChange(_ config: YEN.Config, preferredBackgroundColor: NSColor?) {
		let newValue = DerivedConfig(config: config, preferredBackgroundColor: preferredBackgroundColor, cornerRadius: windowCornerRadius)
		guard newValue != derivedConfig else { return }
		derivedConfig = newValue

		// Attach the glass effect synchronously if missing to prevent flicker when a new tab appears.
		// Existing updates remain deferred, as they can occur during SwiftUI rendering.
		if glassEffectView == nil {
			updateGlassEffectIfNeeded()
		} else {
			DispatchQueue.main.async(execute: updateGlassEffectIfNeeded)
		}
	}

	private func updateDockedSidebarIfNeeded() {
		guard shouldShowDockedSidebarInWindow(window) else {
			removeDockedSidebarIfNeeded()
			return
		}

		if ensureDockedSidebarIfNeeded() {
			// Let AppKit finish mounting the hosting view before we publish tab state into it.
			scheduleDockedSidebarActivation()
			return
		}

		activateDockedSidebarIfNeeded()
	}

	@discardableResult
	private func ensureDockedSidebarIfNeeded() -> Bool {
		guard dockedSidebarHostingView == nil else { return false }

		let model = dockedSidebarModel ?? DockedTabSidebarModel()
		dockedSidebarModel = model

		let hostingView = makeDockedSidebarHostingView(model)
		hostingView.translatesAutoresizingMaskIntoConstraints = false
		hostingView.setContentHuggingPriority(.required, for: .horizontal)
		hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
		dockedSidebarHostingView = hostingView

		addSubview(hostingView)

		terminalLeadingConstraint?.isActive = false
		let terminalLeading = terminalView.leadingAnchor.constraint(equalTo: hostingView.trailingAnchor)
		terminalLeadingConstraint = terminalLeading
		let widthConstraint = hostingView.widthAnchor.constraint(equalToConstant: TabSidebarController.panelWidth)
		dockedSidebarWidthConstraint = widthConstraint

		NSLayoutConstraint.activate([
			hostingView.topAnchor.constraint(equalTo: topAnchor),
			hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
			hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
			widthConstraint,
			terminalLeading,
		])

		invalidateIntrinsicContentSize()
		needsLayout = true
		scheduleDockedSidebarLayoutIfNeeded()
		window?.invalidateRestorableState()
		return true
	}

	private func removeDockedSidebarIfNeeded() {
		guard dockedSidebarHostingView != nil else {
			dockedSidebarModel?.setVisible(false)
			dockedSidebarModel?.attach(to: nil)
			dockedSidebarModel = nil
			return
		}

		dockedSidebarWindowCompensationSuppressed = true
		defer { dockedSidebarWindowCompensationSuppressed = false }
		reverseDockedSidebarWindowCompensationIfNeeded()
		dockedSidebarModel?.setVisible(false)
		dockedSidebarModel?.attach(to: nil)
		dockedSidebarModel = nil
		dockedSidebarHostingView?.removeFromSuperview()
		dockedSidebarHostingView = nil
		dockedSidebarWidthConstraint?.isActive = false
		dockedSidebarWidthConstraint = nil

		terminalLeadingConstraint?.isActive = false
		let leading = terminalView.leadingAnchor.constraint(equalTo: leadingAnchor)
		terminalLeadingConstraint = leading
		leading.isActive = true

		invalidateIntrinsicContentSize()
		needsLayout = true
		scheduleDockedSidebarLayoutIfNeeded()
		window?.invalidateRestorableState()
	}

	private func scheduleDockedSidebarUpdate() {
		guard !dockedSidebarUpdateScheduled else { return }
		dockedSidebarUpdateScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.dockedSidebarUpdateScheduled = false
			self.updateDockedSidebarIfNeeded()
		}
	}

	private func scheduleDockedSidebarLayoutIfNeeded() {
		guard !dockedSidebarLayoutScheduled else { return }
		dockedSidebarLayoutScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.dockedSidebarLayoutScheduled = false
			self.layoutSubtreeIfNeeded()
		}
	}

	private func scheduleDockedSidebarActivation() {
		guard !dockedSidebarActivationScheduled else { return }
		dockedSidebarActivationScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.dockedSidebarActivationScheduled = false
			self.activateDockedSidebarIfNeeded()
		}
	}

	private func scheduleDockedSidebarWindowCompensation() {
		guard dockedSidebarHostingView != nil else { return }
		dockedSidebarWindowCompensationWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.dockedSidebarWindowCompensationWorkItem = nil
			self.recomputeDockedSidebarWindowCompensationIfNeeded()
		}
		dockedSidebarWindowCompensationWorkItem = workItem
		DispatchQueue.main.asyncAfter(
			deadline: .now() + Self.dockedSidebarWindowCompensationDelay,
			execute: workItem
		)
	}

	private func activateDockedSidebarIfNeeded() {
		guard shouldShowDockedSidebarInWindow(window) else { return }
		guard dockedSidebarHostingView != nil else { return }
		dockedSidebarModel?.attach(to: window)
		recomputeDockedSidebarWindowCompensationIfNeeded()
		invalidateIntrinsicContentSize()
		needsLayout = true
		scheduleDockedSidebarLayoutIfNeeded()
		window?.invalidateRestorableState()
	}

	private func recomputeDockedSidebarWindowCompensationIfNeeded() {
		guard dockedSidebarHostingView != nil else { return }
		guard !dockedSidebarWindowCompensationSuppressed else { return }
		guard let window, window.isVisible else { return }
		guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
		let minWidth = max(window.minSize.width, 1)
		guard let adjustment = DockedSidebarGeometry.rebalancedAdjustment(
			for: window.frame,
			existingExpansion: dockedSidebarWindowExpansion,
			visibleFrame: visibleFrame,
			sidebarWidth: TabSidebarController.panelWidth,
			minWidth: minWidth
		) else {
			if let expansion = dockedSidebarWindowExpansion {
				let baselineFrame = DockedSidebarGeometry.contractedFrame(
					for: window.frame,
					expansion: expansion,
					minWidth: minWidth
				)
				if window.frame != baselineFrame {
					applyDockedSidebarWindowFrame(baselineFrame, to: window)
				}
				dockedSidebarWindowExpansion = nil
			}
			return
		}

		if window.frame != adjustment.frame {
			applyDockedSidebarWindowFrame(adjustment.frame, to: window)
		}
		dockedSidebarWindowExpansion = adjustment.expansion
	}

	private func applyDockedSidebarWindowFrame(_ frame: NSRect, to window: NSWindow) {
		dockedSidebarWindowCompensationWorkItem?.cancel()
		dockedSidebarWindowCompensationWorkItem = nil
		dockedSidebarWindowCompensationSuppressed = true
		window.setFrame(frame, display: true)
		DispatchQueue.main.async { [weak self] in
			self?.dockedSidebarWindowCompensationSuppressed = false
		}
	}

	private func reverseDockedSidebarWindowCompensationIfNeeded() {
		guard let expansion = dockedSidebarWindowExpansion else { return }
		guard let window else {
			dockedSidebarWindowExpansion = nil
			return
		}

		let minWidth = max(window.minSize.width, 1)
		let contractedFrame = DockedSidebarGeometry.contractedFrame(
			for: window.frame,
			expansion: expansion,
			minWidth: minWidth
		)
		window.setFrame(contractedFrame, display: true)
		window.constrainToScreen()
		dockedSidebarWindowExpansion = nil
	}

	private static func defaultDockedSidebarHostingView(_ model: DockedTabSidebarModel) -> NSView {
		TabSidebarHostingViewFactory.make(model: model, style: .docked)
	}
}

// MARK: - BaseTerminalController + terminalViewContainer

extension BaseTerminalController {
	var terminalViewContainer: TerminalViewContainer? {
		window?.contentView as? TerminalViewContainer
	}
}

// MARK: Glass

/// An `NSView` that contains a liquid glass background effect.
#if compiler(>=6.2)
@available(macOS 26.0, *)
private class TerminalGlassView: NSView, ObservableObject {
	struct GlassBackground: View {
		@ObservedObject var model: GlassViewModel

		var body: some View {
			model.color
				.glassEffect(
					model.glass,
					in: RoundedRectangle(cornerRadius: model.cornerRadius)
				)
		}
	}

	class GlassViewModel: ObservableObject {
		@Published var backgroundColor: Color = .clear
		@Published var backgroundOpacity: Double = 0
		@Published var cornerRadius: CGFloat = 0
		@Published var glass: Glass = .identity

		var color: Color {
			backgroundColor.opacity(backgroundOpacity)
		}
	}

	private let glassEffectView: NSView
	private var topConstraint: NSLayoutConstraint!
	private let glassViewModel: GlassViewModel

	init(topOffset: CGFloat) {
		let viewModel = GlassViewModel()
		self.glassEffectView = NSHostingView(rootView: GlassBackground(model: viewModel))
		self.glassViewModel = viewModel
		super.init(frame: .zero)

		translatesAutoresizingMaskIntoConstraints = false

		// Glass effect view fills this view.
		glassEffectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(glassEffectView)
		topConstraint = glassEffectView.topAnchor.constraint(
			equalTo: topAnchor,
			constant: topOffset
		)
		NSLayoutConstraint.activate([
			topConstraint,
			glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// Configures the glass, tint color, and corner radius.
	func configure(
		glass: Glass,
		backgroundColor: NSColor,
		backgroundOpacity: Double,
		cornerRadius: CGFloat?
	) {
		glassViewModel.backgroundColor = Color(backgroundColor)
		glassViewModel.backgroundOpacity = backgroundOpacity
		glassViewModel.cornerRadius = cornerRadius ?? 0
		glassViewModel.glass = glass
	}

	/// Updates the top inset offset for the glass effect.
	/// Call this when the safe area insets change (e.g., during layout).
	func updateTopInset(_ offset: CGFloat) {
		topConstraint.constant = offset
	}
}
#endif // compiler(>=6.2)

extension TerminalViewContainer {
#if compiler(>=6.2)
	@available(macOS 26.0, *)
	private func addGlassEffectViewIfNeeded() -> TerminalGlassView? {
		if let existed = glassEffectView as? TerminalGlassView {
			updateGlassEffectTopInsetIfNeeded()
			return existed
		}
		guard let themeFrameView = windowThemeFrameView else {
			return nil
		}
		let effectView = TerminalGlassView(topOffset: -themeFrameView.safeAreaInsets.top)
		addSubview(effectView, positioned: .below, relativeTo: terminalView)
		NSLayoutConstraint.activate([
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])
		glassEffectView = effectView
		return effectView
	}
#endif // compiler(>=6.2)

	private func updateGlassEffectIfNeeded() {
#if compiler(>=6.2)
		guard #available(macOS 26.0, *), let derivedConfig else {
			glassEffectView?.removeFromSuperview()
			glassEffectView = nil
			return
		}
		guard let effectView = addGlassEffectViewIfNeeded() else {
			return
		}

		effectView.configure(
			glass: derivedConfig.glass.official,
			backgroundColor: derivedConfig.backgroundColor,
			backgroundOpacity: derivedConfig.backgroundOpacity,
			cornerRadius: derivedConfig.cornerRadius
		)
#endif // compiler(>=6.2)
	}

	private func updateGlassEffectTopInsetIfNeeded() {
#if compiler(>=6.2)
		guard
			#available(macOS 26.0, *),
			let effectView = glassEffectView as? TerminalGlassView,
			let themeFrameView = windowThemeFrameView
		else {
			return
		}
		effectView.updateTopInset(-themeFrameView.safeAreaInsets.top)
#endif // compiler(>=6.2)
	}

	struct DerivedConfig: Equatable {
		let glass: BackportGlass
		let backgroundColor: NSColor
		let backgroundOpacity: Double
		let cornerRadius: CGFloat?

		init?(config: YEN.Config, preferredBackgroundColor: NSColor?, cornerRadius: CGFloat?) {
			switch config.backgroundBlur {
			case .macosGlassRegular:
				glass = .regular
			case .macosGlassClear:
				glass = .clear
			default:
				return nil
			}
			self.backgroundColor = preferredBackgroundColor ?? NSColor(config.backgroundColor)
			self.backgroundOpacity = config.backgroundOpacity
			self.cornerRadius = cornerRadius
		}
	}
}
