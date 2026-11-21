import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

/// This delegate is notified of actions and property changes regarding the terminal view. This
/// delegate is optional and can be used by a TerminalView caller to react to changes such as
/// titles being set, cell sizes being changed, etc.
protocol TerminalViewDelegate: AnyObject {
    /// Called when the currently focused surface changed. This can be nil.
    func focusedSurfaceDidChange(to: YEN.SurfaceView?)

    /// The URL of the pwd should change.
    func pwdDidChange(to: URL?)

    /// The cell size changed.
    func cellSizeDidChange(to: NSSize)

    /// Perform an action. At the time of writing this is only triggered by the command palette.
    func performAction(_ action: String, on: YEN.SurfaceView)
    
    /// A split tree operation
    func performSplitAction(_ action: TerminalSplitOperation)
}

/// The view model is a required implementation for TerminalView callers. This contains
/// the main state between the TerminalView caller and SwiftUI. This abstraction is what
/// allows AppKit to own most of the data in SwiftUI.
protocol TerminalViewModel: ObservableObject {
    /// The tree of terminal surfaces (splits) within the view. This is mutated by TerminalView
    /// and children. This should be @Published.
    var surfaceTree: SplitTree<YEN.SurfaceView> { get set }

    /// The command palette state.
    var commandPaletteIsShowing: Bool { get set }
    
    /// The update overlay should be visible.
    var updateOverlayIsVisible: Bool { get }
}

/// The main terminal view. This terminal view supports splits.
struct TerminalView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var yen: YEN.App

    // The required view model
    @ObservedObject var viewModel: ViewModel
    @ObservedObject private var terminalPresentationSettings = TerminalPresentationSettings.shared
    @ObservedObject private var browserSplit = BrowserSplitController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    // An optional delegate to receive information about terminal changes.
    weak var delegate: (any TerminalViewDelegate)? = nil
    
    // The most recently focused surface, equal to focusedSurface when
    // it is non-nil.
    @State private var lastFocusedSurface: Weak<YEN.SurfaceView> = .init()

    // This seems like a crutch after switching from SwiftUI to AppKit lifecycle.
    @FocusState private var focused: Bool

    // Various state values sent back up from the currently focused terminals.
    @FocusedValue(\.yenSurfaceView) private var focusedSurface
    @FocusedValue(\.yenSurfacePwd) private var surfacePwd
    @FocusedValue(\.yenSurfaceCellSize) private var cellSize

    // Config reload toast trigger — new UUID per event guarantees onChange fires
    @State private var configReloadTrigger: UUID?

    // Screenshot toast trigger
    @State private var screenshotTrigger: UUID?
    @State private var screenshotToastMessage = "Screenshot saved"
    @State private var screenshotToastOutcome: ScreenshotToastOutcome = .savedAndCopied
    @State private var hotkeyDisabledTrigger: UUID?
    @State private var hotkeyDisabledMessage = ""
    @State private var layoutStatusTrigger: UUID?
    @State private var layoutStatusMessage = ""
    @State private var layoutStatusSeverity: LayoutStatusSeverity = .info
    @State private var hostingWindow: NSWindow?
    @State private var trackedWindowNumber: Int?
    @State private var windowIsFocused: Bool = false
    @State private var windowIsFullscreen: Bool = false
    @State private var terminalViewFrameInWindow: CGRect = .zero
    @State private var focusedSurfaceFrameTick: Int = 0
    @State var wholeWindowBackgroundRuntimeActive: Bool = false

    let settingsController = SettingsController.shared

    // The pwd of the focused surface as a URL
    private var pwdURL: URL? {
        guard let surfacePwd, surfacePwd != "" else { return nil }
        return URL(fileURLWithPath: surfacePwd)
    }

    var settingsSnapshot: TerminalPresentationSettings.Snapshot {
        terminalPresentationSettings.snapshot
    }

    private var shouldShowAnyWindowBorder: Bool {
        WindowBorderRenderingPolicy.shouldShowBorder(
            enabled: settingsSnapshot.windowBorderEnabled,
            hasHostingWindow: borderWindow != nil,
            isFullscreen: windowIsFullscreen,
            isPanelWindow: borderWindow is NSPanel,
            isQuickTerminalWindow: isQuickTerminalWindow
        )
    }

    private var shouldShowWindowScopedBorder: Bool {
        shouldShowAnyWindowBorder && settingsSnapshot.windowBorderScope == .window
    }

    private var shouldShowFocusedSplitBorder: Bool {
        shouldShowAnyWindowBorder && settingsSnapshot.windowBorderScope == .focusedSplit
    }

    private var trackedWindow: NSWindow? {
        guard let trackedWindowNumber else { return nil }
        return NSApp.window(withWindowNumber: trackedWindowNumber)
    }

    private var borderWindow: NSWindow? {
        hostingWindow ?? activeOrLastFocusedSurface?.window ?? trackedWindow
    }

    private var isQuickTerminalWindow: Bool {
        guard let borderWindow else { return false }
        if borderWindow is QuickTerminalWindow { return true }
        if borderWindow.identifier?.rawValue == "com.yenchat.yen.quickTerminal" { return true }
        guard let controller = borderWindow.windowController else { return false }
        return controller is QuickTerminalController
    }

    private var windowBorderChromeMode: WindowBorderChromeMode {
        let hasWindowDecorations = borderWindow?.styleMask.contains(.titled) ?? true
        return WindowBorderRenderingPolicy.chromeMode(
            titlebarStyle: yen.config.macosTitlebarStyle,
            hasWindowDecorations: hasWindowDecorations
        )
    }

    private var shouldIgnoreTopSafeArea: Bool {
        WindowBorderRenderingPolicy.shouldIgnoreTopSafeArea(titlebarStyle: yen.config.macosTitlebarStyle)
    }

    private var useDashedUnfocusedStyle: Bool {
        WindowBorderRenderingPolicy.shouldUseDashedUnfocusedStyle(
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    private var activeWindowBorderGradient: WindowBorderGradient {
        windowIsFocused
            ? settingsSnapshot.windowBorderFocusedGradient
            : settingsSnapshot.windowBorderUnfocusedGradient
    }

    private var activeOrLastFocusedSurface: YEN.SurfaceView? {
        focusedSurface ?? lastFocusedSurface.value
    }

    private var showsBorderOnSplitLeaf: Bool {
        guard shouldShowFocusedSplitBorder, let surface = activeOrLastFocusedSurface else { return false }
        let visibleRoot = viewModel.surfaceTree.zoomed ?? viewModel.surfaceTree.root
        return visibleRoot?.find(id: surface.id) != nil
    }

    private var nativeCornerRadius: CGFloat {
        guard let window = borderWindow, window.styleMask.contains(.titled) else { return 0 }
        return EdgeRevealPanelGeometry.windowCornerRadius(of: window)
    }

    private var borderOverlay: WindowBorderOverlay {
        WindowBorderOverlay(
            gradient: activeWindowBorderGradient,
            width: settingsSnapshot.windowBorderWidth,
            radius: settingsSnapshot.windowBorderRadius,
            chromeMode: windowBorderChromeMode,
            isFocused: windowIsFocused,
            useDashedUnfocusedStyle: useDashedUnfocusedStyle,
            minimumCornerRadius: nativeCornerRadius
        )
    }

    private var focusedSplitBorderFrame: CGRect? {
        guard shouldShowFocusedSplitBorder, !showsBorderOnSplitLeaf else { return nil }
        _ = focusedSurfaceFrameTick
        guard let surface = activeOrLastFocusedSurface else { return nil }
        guard !terminalViewFrameInWindow.isEmpty else { return nil }

        let surfaceFrameInWindow = surface.convert(surface.bounds, to: nil)
        return WindowBorderRenderingPolicy.focusedSplitBorderFrame(
            surfaceFrameInWindow: surfaceFrameInWindow,
            terminalFrameInWindow: terminalViewFrameInWindow
        )
    }

    private var shouldFallbackToWindowBorder: Bool {
        shouldShowFocusedSplitBorder && !showsBorderOnSplitLeaf && focusedSplitBorderFrame == nil
    }

    var shouldRenderWholeWindowBackgroundImage: Bool {
        settingsSnapshot.wholeWindowBackgroundImageEnabled
    }

    private var wholeWindowBackgroundColor: Color {
        yen.config.backgroundColor
    }

    var body: some View {
        switch yen.readiness {
        case .loading:
            Text("Loading")
        case .error:
            ErrorView()
        case .ready:
            ZStack {
                if shouldRenderWholeWindowBackgroundImage {
                    WholeWindowBackgroundView(
                        imagePath: settingsSnapshot.backgroundImagePath,
                        backgroundColor: wholeWindowBackgroundColor,
                        backgroundOpacity: settingsSnapshot.backgroundOpacity
                    )
                    // Always extend behind the titlebar so the wallpaper backs
                    // the chrome when surfaces are at background-opacity 0.
                    .ignoresSafeArea(.container, edges: .top)
                }

                terminalWithOptionalBrowserSplit
                    .padding(shouldShowWindowScopedBorder || shouldFallbackToWindowBorder ? borderOverlay.contentInset(framed: false) + 1 : 0)
                // Ignore safe area to extend up in to the titlebar region if we have the "hidden" titlebar style
                .ignoresSafeArea(.container, edges: shouldIgnoreTopSafeArea ? .top : [])

                if shouldShowWindowScopedBorder || shouldFallbackToWindowBorder {
                    borderOverlay
                    .padding(1)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.container, edges: shouldIgnoreTopSafeArea ? .top : [])
                    .transition(.opacity)
                }
                if let focusedSplitBorderFrame {
                    borderOverlay
                    .padding(1)
                    .frame(width: focusedSplitBorderFrame.width, height: focusedSplitBorderFrame.height)
                    .position(x: focusedSplitBorderFrame.midX, y: focusedSplitBorderFrame.midY)
                    // Split focus changes should snap to the newly focused pane.
                    .animation(nil, value: focusedSplitBorderFrame)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if viewModel.commandPaletteIsShowing, let surfaceView = lastFocusedSurface.value {
                    // Only mount the overlay while presented so the hidden palette does not
                    // keep a stale surface/window alive via its strong surfaceView reference.
                    TerminalCommandPaletteView(
                        surfaceView: surfaceView,
                        isPresented: $viewModel.commandPaletteIsShowing,
                        yenConfig: yen.config,
                        settingsController: settingsController,
                        updateViewModel: AppDelegate.shared?.updateViewModel) { action in
                        self.delegate?.performAction(action, on: surfaceView)
                    }
                }
                
                // Show update information above all else.
                if viewModel.updateOverlayIsVisible {
                    UpdateOverlay()
                }

                // Shared toast stack: the config-reload, screenshot, and
                // hotkey-disabled toasts render in one bottom-anchored column so
                // concurrent toasts stack vertically instead of overlapping at the
                // same bottom-center spot.
                VStack(spacing: 8) {
                    Spacer(minLength: 0)

                    // Config reload toast
                    ConfigReloadToast(trigger: $configReloadTrigger)

                    // Screenshot toast
                    ScreenshotToast(
                        trigger: $screenshotTrigger,
                        message: $screenshotToastMessage,
                        outcome: $screenshotToastOutcome
                    )

                    // Disabled-feature hotkey toast (⇧⌘B / ⇧⌘J while the feature is off)
                    HotkeyDisabledToast(
                        trigger: $hotkeyDisabledTrigger,
                        message: $hotkeyDisabledMessage
                    )

                    // Layout status, for when Settings is closed and its footer — the
                    // only place these messages used to appear — is not on screen.
                    // Its own view, NOT HotkeyDisabledToast: that one hardcodes an
                    // "Open Settings" action and an info tint, which gave every layout
                    // message a bogus button and made errors look like successes.
                    LayoutStatusToast(
                        trigger: $layoutStatusTrigger,
                        message: $layoutStatusMessage,
                        severity: $layoutStatusSeverity
                    )
                }
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: shouldShowAnyWindowBorder)
            .background(WindowReferenceReader(window: $hostingWindow, frameInWindow: $terminalViewFrameInWindow))
            .onAppear {
                BrowserSplitController.shared.registerTerminalWindow(borderWindow)
                syncWholeWindowBackgroundRuntime()
            }
            .onDisappear {
                BrowserSplitController.shared.unregisterTerminalWindow(borderWindow)
            }
            .onChange(of: hostingWindow) { window in
                BrowserSplitController.shared.registerTerminalWindow(window)
                trackWindowAndSyncState(window)
                // The tick exists only to recompute the focused-split border frame, so
                // skip it when that border is off (the default). didMoveNotification in
                // particular fires at display rate while dragging a window by its
                // titlebar, and WindowReferenceReader correctly emits nothing there
                // because frame-in-window is invariant under a move. Safe against
                // staleness: turning the border on republishes settingsSnapshot, which
                // re-evaluates the body and recomputes the frame.
                if shouldShowFocusedSplitBorder { focusedSurfaceFrameTick &+= 1 }
            }
            .onChange(of: viewModel.surfaceTree.structuralIdentity) { _ in
                syncWholeWindowBackgroundRuntime()
            }
            .onChange(of: settingsSnapshot.backgroundImagePath) { _ in
                syncWholeWindowBackgroundRuntime()
            }
            .onChange(of: settingsSnapshot.backgroundImageScope) { _ in
                syncWholeWindowBackgroundRuntime()
            }
            .onChange(of: settingsSnapshot.backgroundOpacity) { _ in
                syncWholeWindowBackgroundRuntime()
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenConfigDidReload)) { _ in
                configReloadTrigger = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenConfigDidChange)) { notification in
                guard notification.object == nil else { return }
                // Ghostty posts this config before replacing yen.config.
                syncWholeWindowBackgroundRuntime(
                    sourceConfig: notification.userInfo?[Notification.Name.YENConfigChangeKey] as? YEN.Config
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenScreenshotCopied)) { notification in
                guard let event = ScreenshotToastEvent.from(
                    notification: notification,
                    observedWindowNumbers: observedWindowNumbers
                ) else { return }
                screenshotToastMessage = event.message
                screenshotToastOutcome = event.outcome
                screenshotTrigger = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenHotkeyDisabledToast)) { notification in
                guard let message = TerminalToastPayload.message(
                    from: notification, observedWindowNumbers: observedWindowNumbers,
                    windowNumberKey: Notification.Name.yenHotkeyDisabledWindowNumberKey,
                    messageKey: Notification.Name.yenHotkeyDisabledMessageKey
                ) else { return }
                hotkeyDisabledMessage = message
                hotkeyDisabledTrigger = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenLayoutStatusToast)) { notification in
                guard let message = TerminalToastPayload.message(
                    from: notification, observedWindowNumbers: observedWindowNumbers,
                    windowNumberKey: Notification.Name.yenLayoutStatusWindowNumberKey,
                    messageKey: Notification.Name.yenLayoutStatusMessageKey
                ) else { return }
                let rawSeverity = notification.userInfo?[Notification.Name.yenLayoutStatusSeverityKey] as? String
                layoutStatusSeverity = LayoutStatusSeverity(rawValue: rawSeverity ?? "info") ?? .info
                layoutStatusMessage = message
                layoutStatusTrigger = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignMainNotification)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                syncWindowState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                syncWindowState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .yenNativeFullscreenTransitionDidChange)) { notification in
                guard let window = notification.object as? NSWindow, matchesObservedWindow(window) else { return }
                trackWindowAndSyncState(window)
                if shouldShowFocusedSplitBorder { focusedSurfaceFrameTick &+= 1 }
            }
            .onReceive(TerminalFrameEvents.publisher(
                enabled: shouldShowFocusedSplitBorder && !showsBorderOnSplitLeaf,
                surface: activeOrLastFocusedSurface,
                window: borderWindow
            )) { focusedSurfaceFrameTick &+= 1 }
        }
    }

    @ViewBuilder
    private var terminalWithOptionalBrowserSplit: some View {
        if browserSplit.isVisible(in: borderWindow) {
            HSplitView {
                terminalContent
                    .frame(minWidth: 260)
                BrowserSplitPane(model: browserSplit.model) {
                    BrowserSplitController.shared.close()
                }
            }
        } else {
            terminalContent
        }
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            // If we're running in debug mode we show a warning so that users
            // know that performance will be degraded.
            if (YEN.info.mode == YEN_BUILD_MODE_DEBUG || YEN.info.mode == YEN_BUILD_MODE_RELEASE_SAFE) {
                DebugBuildWarningView()
            }

            TerminalSplitTreeView(
                tree: viewModel.surfaceTree,
                alignsWithTabBar: yen.config.macosTitlebarStyle == .tabs && !windowIsFullscreen,
                action: { delegate?.performSplitAction($0) })
                .environment(\.focusedPaneOutline, showsBorderOnSplitLeaf ? activeOrLastFocusedSurface.map {
                    FocusedPaneOutline(surfaceID: $0.id, overlay: borderOverlay)
                } : nil)
                .environmentObject(yen)
                .focused($focused)
                .onAppear {
                    self.focused = true
                    activeOrLastFocusedSurface?.postsFrameChangedNotifications = true
                }
                .onChange(of: focusedSurface) { newValue in
                    // We want to keep track of our last focused surface so even if
                    // we lose focus we keep this set to the last non-nil value.
                    if newValue != nil {
                        lastFocusedSurface = .init(newValue)
                        self.delegate?.focusedSurfaceDidChange(to: newValue)
                    }
                    newValue?.postsFrameChangedNotifications = true
                    trackWindowAndSyncState(newValue?.window)
                    if shouldShowFocusedSplitBorder { focusedSurfaceFrameTick &+= 1 }
                }
                .onChange(of: pwdURL) { newValue in
                    self.delegate?.pwdDidChange(to: newValue)
                }
                .onChange(of: cellSize) { newValue in
                    guard let size = newValue else { return }
                    self.delegate?.cellSizeDidChange(to: size)
                }
                .frame(idealWidth: lastFocusedSurface.value?.initialSize?.width,
                       idealHeight: lastFocusedSurface.value?.initialSize?.height)
        }
    }

    private func trackWindow(_ window: NSWindow?) {
        guard let window else { return }
        BrowserSplitController.shared.registerTerminalWindow(window)
        trackedWindowNumber = window.windowNumber
    }

    private func trackWindowAndSyncState(_ window: NSWindow?) {
        trackWindow(window)
        syncWindowState()
    }

    private func syncWindowState() {
        let windowIsKey = borderWindow?.isKeyWindow ?? false
        let windowIsMain = borderWindow?.isMainWindow ?? false
        windowIsFocused = WindowBorderRenderingPolicy.isWindowFocused(
            windowIsKey: windowIsKey,
            windowIsMain: windowIsMain,
            appIsActive: NSApp.isActive
        )
        windowIsFullscreen = borderWindow?.yenIsEffectivelyFullscreen ?? false
    }

    private func matchesObservedWindow(_ window: NSWindow) -> Bool {
        WindowBorderRenderingPolicy.shouldHandleWindowNotification(
            observedWindowNumber: window.windowNumber,
            hostingWindowNumber: hostingWindow?.windowNumber,
            activeSurfaceWindowNumber: activeOrLastFocusedSurface?.window?.windowNumber,
            trackedWindowNumber: trackedWindowNumber
        )
    }

    private var observedWindowNumbers: Set<Int> {
        Set([
            hostingWindow?.windowNumber,
            activeOrLastFocusedSurface?.window?.windowNumber,
            trackedWindowNumber,
        ].compactMap { $0 })
    }
}

fileprivate struct UpdateOverlay: View {
    var body: some View {
        if let appDelegate = AppDelegate.shared {
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    UpdatePill(model: appDelegate.updateViewModel)
                        .padding(.bottom, 9)
                        .padding(.trailing, 9)
                }
            }
        }
    }
}

struct DebugBuildWarningView: View {
    @State private var isPopover = false

    var body: some View {
        HStack {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text("You're running a debug build of YEN! Performance will be degraded.")
                .padding(.all, 8)
                .popover(isPresented: $isPopover, arrowEdge: .bottom) {
                    Text("""
                    Debug builds of YEN are very slow and you may experience
                    performance problems. Debug builds are only recommended during
                    development.
                    """)
                    .padding(.all)
                }

            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Debug build warning")
        .accessibilityValue("Debug builds of YEN are very slow and you may experience performance problems. Debug builds are only recommended during development.")
        // The warning is tappable (it opens an explanatory popover), so it must
        // read as a button — not static text — and expose an action VoiceOver /
        // keyboard users can trigger.
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            isPopover = true
        }
        .onTapGesture {
            isPopover = true
        }
    }
}
