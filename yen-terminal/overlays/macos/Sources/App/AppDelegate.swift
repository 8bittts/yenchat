import AppKit
import ServiceManagement
import Speech
import SwiftUI
import UserNotifications
import OSLog
import Sparkle
import YENKit

func isRunningUnderXCTest() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestBundlePath"] != nil
}

class AppDelegate: NSObject,
                    ObservableObject,
                    NSApplicationDelegate,
                    UNUserNotificationCenterDelegate,
                    YENAppDelegate
{
    /// Shared accessor for the app delegate — was re-derived as
    ///  at ~12 call sites.
    static var shared: AppDelegate? { NSApp.delegate as? AppDelegate }

    /// Beep once (ignoring key-repeat) when a disabled-feature toggle hotkey
    /// should be consumed; returns whether it was consumed.
    private func consumeDisabledToggleHotkey(
        _ shouldConsume: Bool,
        featureName: String,
        event: NSEvent
    ) -> Bool {
        guard shouldConsume else { return false }
        if !event.isARepeat {
            NSSound.beep()
            // A bare beep is opaque (and, under the "flash screen on alert"
            // accessibility setting, silent) — pair it with a toast so the user
            // knows the feature is off rather than thinking the hotkey broke.
            DisabledFeatureToast.post(featureName: featureName)
        }
        return true
    }

    // The application logger. We should probably move this at some point to a dedicated
    // class/struct but for now it lives here! 🤷‍♂️
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yenchat.yen",
        category: String(describing: AppDelegate.self)
    )

    enum Appearance {
        case system
        case light
        case dark

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Various menu items so that we can programmatically sync the keyboard shortcut with the YEN config
    @IBOutlet private var menuAbout: NSMenuItem?
    @IBOutlet private var menuBitcoinEmail: NSMenuItem?
    @IBOutlet private var menuJPTheCat: NSMenuItem?
    @IBOutlet private var menuYENHelp: NSMenuItem?
    @IBOutlet private var menuServices: NSMenu?
    @IBOutlet private var menuCheckForUpdates: NSMenuItem?
    @IBOutlet private var menuOpenConfig: NSMenuItem?
    @IBOutlet private var menuReloadConfig: NSMenuItem?
    @IBOutlet private var menuSettings: NSMenuItem?
    @IBOutlet private var menuSecureInput: NSMenuItem?
    @IBOutlet private var menuQuit: NSMenuItem?

    @IBOutlet private var menuNewWindow: NSMenuItem?
    @IBOutlet private var menuNewTab: NSMenuItem?
    @IBOutlet private var menuOpenFileBrowser: NSMenuItem?
    @IBOutlet private var menuScreenshot: NSMenuItem?
    @IBOutlet private var menuSplitRight: NSMenuItem?
    @IBOutlet private var menuSplitLeft: NSMenuItem?
    @IBOutlet private var menuSplitDown: NSMenuItem?
    @IBOutlet private var menuSplitUp: NSMenuItem?
    @IBOutlet private var menuClose: NSMenuItem?
    @IBOutlet private var menuCloseTab: NSMenuItem?
    @IBOutlet private var menuCloseWindow: NSMenuItem?
    @IBOutlet private var menuCloseAllWindows: NSMenuItem?

    @IBOutlet private var menuUndo: NSMenuItem?
    @IBOutlet private var menuRedo: NSMenuItem?
    @IBOutlet private var menuCopy: NSMenuItem?
    @IBOutlet private var menuPaste: NSMenuItem?
    @IBOutlet private var menuPasteSelection: NSMenuItem?
    @IBOutlet private var menuSelectAll: NSMenuItem?
    @IBOutlet private var menuFindParent: NSMenuItem?
    @IBOutlet private var menuFind: NSMenuItem?
    @IBOutlet private var menuSelectionForFind: NSMenuItem?
    @IBOutlet private var menuScrollToSelection: NSMenuItem?
    @IBOutlet private var menuFindNext: NSMenuItem?
    @IBOutlet private var menuFindPrevious: NSMenuItem?
    @IBOutlet private var menuHideFindBar: NSMenuItem?
    @IBOutlet private var menuToggleVisibility: NSMenuItem?
    @IBOutlet private var menuToggleFullScreen: NSMenuItem?
    @IBOutlet private var menuBringAllToFront: NSMenuItem?
    @IBOutlet private var menuZoomSplit: NSMenuItem?
    @IBOutlet private var menuPreviousSplit: NSMenuItem?
    @IBOutlet private var menuNextSplit: NSMenuItem?
    @IBOutlet private var menuSelectSplitParent: NSMenuItem?
    @IBOutlet private var menuSelectSplitAbove: NSMenuItem?
    @IBOutlet private var menuSelectSplitBelow: NSMenuItem?
    @IBOutlet private var menuSelectSplitLeft: NSMenuItem?
    @IBOutlet private var menuSelectSplitRight: NSMenuItem?
    @IBOutlet private var menuReturnToDefaultSize: NSMenuItem?
    @IBOutlet private var menuFloatOnTop: NSMenuItem?
    @IBOutlet private var menuUseAsDefault: NSMenuItem?

    @IBOutlet private var menuIncreaseFontSize: NSMenuItem?
    @IBOutlet private var menuDecreaseFontSize: NSMenuItem?
    @IBOutlet private var menuResetFontSize: NSMenuItem?
    @IBOutlet private var menuChangeTitle: NSMenuItem?
    @IBOutlet private var menuChangeTabTitle: NSMenuItem?
    @IBOutlet private var menuReadonly: NSMenuItem?
    @IBOutlet private var menuQuickTerminal: NSMenuItem?
    @IBOutlet private var menuTerminalInspector: NSMenuItem?
    @IBOutlet private var menuCommandPalette: NSMenuItem?

    @IBOutlet private var menuResizeSplitParent: NSMenuItem?
    @IBOutlet private var menuEqualizeSplits: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerUp: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerDown: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerLeft: NSMenuItem?
    @IBOutlet private var menuMoveSplitDividerRight: NSMenuItem?

    /// The dock menu
    private var dockMenu: NSMenu = NSMenu()

    /// This is only true before application has become active.
    private var applicationHasBecomeActive: Bool = false

    /// This is set in applicationDidFinishLaunching with the system uptime so we can determine the
    /// seconds since the process was launched.
    private var applicationLaunchTime: TimeInterval = 0

    /// AppKit treats positional command-line arguments as documents to open. This
    /// filter consumes the corresponding open-file events for arguments following
    /// `-e`. It is initialized lazily because most launches never open a file.
    private lazy var commandLineOpenFileFilter = CommandLineOpenFileFilter(
        arguments: CommandLine.arguments,
        workingDirectory: FileManager.default.currentDirectoryPath,
        fileExists: { FileManager.default.fileExists(atPath: $0) }
    )

    /// This is the current configuration from the YEN configuration that we need.
    private var derivedConfig: DerivedConfig = DerivedConfig()

    /// The application appearance selected for this session.
    private(set) var appearanceOverride: Appearance?

    /// The yen global state. Only one per process.
    let yen: YEN.App

    /// The global undo manager for app-level state such as window restoration.
    lazy var undoManager = ExpiringUndoManager()

    /// The current state of the quick terminal.
    private var quickTerminalControllerState: QuickTerminalState = .uninitialized

    /// Whether the quick terminal has already been initialized.
    var quickControllerInitialized: Bool {
        if case .initialized = quickTerminalControllerState {
            return true
        }
        return false
    }

    /// Our quick terminal. This starts out uninitialized and only initializes if used.
    var quickController: QuickTerminalController {
        switch quickTerminalControllerState {
        case .initialized(let controller):
            return controller
            
        case .pendingRestore(let state):
            let controller = QuickTerminalController(
                yen,
                position: derivedConfig.quickTerminalPosition,
                baseConfig: state.baseConfig,
                restorationState: state
            )
            quickTerminalControllerState = .initialized(controller)
            return controller
            
        case .uninitialized:
            let controller = QuickTerminalController(
                yen,
                position: derivedConfig.quickTerminalPosition,
                restorationState: nil
            )
            quickTerminalControllerState = .initialized(controller)
            return controller
        }
    }

    /// Returns the quick terminal controller only when it already exists.
    var existingQuickTerminalController: QuickTerminalController? {
        guard case .initialized(let controller) = quickTerminalControllerState else {
            return nil
        }

        return controller
    }

    /// Manages updates
    let updateController = UpdateController()
    var updateViewModel: UpdateViewModel {
        updateController.viewModel
    }

    /// The elapsed time since the process was started
    var timeSinceLaunch: TimeInterval {
        return ProcessInfo.processInfo.systemUptime - applicationLaunchTime
    }

    /// Tracks the windows that we hid for toggleVisibility.
    private(set) var hiddenState: ToggleVisibilityState? = nil

    /// The observer for the app appearance.
    private var appearanceObserver: NSKeyValueObservation? = nil

    /// App-level local keyboard event monitor used when no terminal window is focused.
    private var localEventMonitor: Any?

    /// Signals
    private var signals: [DispatchSourceSignal] = []

    /// Delays global event tap activation during startup without letting stale config
    /// changes re-enable it after a later disable.
    private var pendingGlobalEventTapEnableWorkItem: DispatchWorkItem?

    /// The custom app icon image that is currently in use.
    @Published private(set) var appIcon: NSImage? = nil

    /// YEN menu items indexed by their normalized shortcut. This avoids traversing
    /// the entire menu tree on every key equivalent event.
    ///
    /// We store a weak reference so this cache can never be the owner of menu items.
    /// If multiple items map to the same shortcut, the most recent one wins.
    @MainActor private lazy var menuShortcutController = AppMenuShortcutController()

    override init() {
        // Must run before the engine reads config: a missing or stale `theme`
        // key otherwise reaches the first window as built-in colors or an error.
        if !isRunningUnderXCTest() {
            ThemeConfigRepair.repairConfigFile(in: .live())
        }
#if DEBUG
        yen = YEN.App(configPath: ProcessInfo.processInfo.environment["YEN_CONFIG_PATH"])
#else
        yen = YEN.App()
#endif
        super.init()

        yen.delegate = self
    }

    deinit {
        pendingGlobalEventTapEnableWorkItem?.cancel()
        tearDownLocalEventMonitor()
        appearanceObserver?.invalidate()
    }

    //MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            // Disable the automatic full screen menu item because we handle
            // it manually.
            "NSFullScreenMenuItemEverywhere": false,
            
            // On macOS 26 RC1, the autofill heuristic controller causes unusable levels
            // of slowdowns and CPU usage in the terminal window under certain [unknown]
            // conditions. We don't know exactly why/how. This disables the full heuristic
            // controller.
            //
            // Practically, this means things like SMS autofill don't work, but that is
            // a desirable behavior to NOT have happen for a terminal, so this is a win.
            // Manual autofill via the `Edit => AutoFill` menu item still work as expected.
            "NSAutoFillHeuristicControllerEnabled": false,
        ])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // End persistent sessions no pane holds any more, after restore settles.
        PersistentSessionReaper.start()
        DesktopExtras.shared.restore()

        // System settings overrides
        UserDefaults.standard.register(defaults: [
            // Disable this so that repeated key events make it through to our terminal views.
            "ApplePressAndHoldEnabled": false,
        ])

        // Store our start time
        applicationLaunchTime = ProcessInfo.processInfo.systemUptime

        // Check if secure input was enabled when we last quit.
        if (UserDefaults.standard.bool(forKey: "SecureInput") != SecureInput.shared.enabled) {
            toggleSecureInput(self)
        }

        // Initial config loading
        yenConfigDidChange(config: yen.config)

        // Start our update checker.
        updateController.startUpdater()

        // Register our service provider. This must happen after everything is initialized.
        NSApp.servicesProvider = ServiceProvider()

        // This registers the YEN => Services menu to exist.
        NSApp.servicesMenu = menuServices

        // Setup a local event monitor for app-level keyboard shortcuts. See
        // localEventHandler for more info why.
        installLocalEventMonitor()

        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(quickTerminalDidChangeVisibility),
            name: .quickTerminalDidChangeVisibility,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(yenConfigDidChange(_:)),
            name: .yenConfigDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardSelectionDidChange(_:)),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(yenBellDidRing(_:)),
            name: .yenBellDidRing,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(yenNewWindow(_:)),
            name: YEN.Notification.yenNewWindow,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(yenNewTab(_:)),
            name: YEN.Notification.yenNewTab,
            object: nil)

        // Configure user notifications
        let actions = [
            UNNotificationAction(identifier: YEN.userNotificationActionShow, title: "Show")
        ]

        let center = UNUserNotificationCenter.current()

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: YEN.userNotificationCategory,
                actions: actions,
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
        installNotificationSoundPresentationHook()

        // Observe our appearance so we can report the correct value to libyen.
        self.appearanceObserver = NSApplication.shared.observe(
            \.effectiveAppearance,
             options: [.new, .initial]
        ) { [weak self] _, change in
            guard let self else { return }
            guard let appearance = change.newValue else { return }
            guard let app = self.yen.app else { return }
            let scheme: yen_color_scheme_e
            if (appearance.isDark) {
                scheme = YEN_COLOR_SCHEME_DARK
            } else {
                scheme = YEN_COLOR_SCHEME_LIGHT
            }

            yen_app_set_color_scheme(app, scheme)
        }

        // Setup our menu
        setupMenuImages()

        // Setup dictation hotkey (Option+Space)
        DictationController.shared.setup()

        // Setup tab sidebar (Cmd+Shift+B)
        TabSidebarController.shared.setup()

        // Setup scratchpad panel (Cmd+Shift+J)
        ScratchpadController.shared.setup()

        // Setup layout shortcuts (Cmd+Option+1-0)
        LayoutShortcutController.shared.setup()

        // These distributed notifications are machine-wide, so a test host would also receive the
        // ones real agent hooks post while the suite runs. A build notification there raised the
        // modal "Notifications Are Blocked" alert and stalled the native suite until dismissed.
        // Tests drive these receivers directly instead.
        if !isRunningUnderXCTest() {
            // Listen for browser commands from `yen web`
            WebPreviewCommandReceiver.shared.setup()

            // Listen for agent working-directory reports from `yen pane cwd`
            AgentWorkingDirectoryReceiver.shared.setup()

            // Listen for build notifications from Claude Code hooks
            setupBuildNotificationObserver()
        }

        // Setup signal handlers
        setupSignals()

        switch YEN.launchSource {
        case .app:
            // Don't have to do anything.
            break
            
        case .zig_run, .cli:
            // Part of launch services (clicking an app, using `open`, etc.) activates
            // the application and brings it to the front. When using the CLI we don't
            // get this behavior, so we have to do it manually.
            
            // This never gets called until we click the dock icon. This forces it
            // activate immediately.
            applicationDidBecomeActive(.init(name: NSApplication.didBecomeActiveNotification))

            // We run in the background, this forces us to the front.
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.yenActivateCompat()
                NSApp.unhide(nil)
                NSApp.arrangeInFront(nil)
            }
        }

#if DEBUG
        SettingsMemoryBenchmark.maybeStart()
        MemoryFixesBenchmark.maybeStart()
#endif
        SettingsHitchBenchmark.maybeStart()
    }

    func applicationDidHide(_ notification: Notification) {
        // Keep track of our hidden state to restore properly
        self.hiddenState = .init()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If we're back manually then clear the hidden state because macOS handles it.
        self.hiddenState = nil

        // Clear the dock badge when the app becomes active
        self.setDockBadge(nil)

        // First launch stuff
        handleInitialActivationIfNeeded()
    }

    func handleInitialActivationIfNeeded() {
        guard !applicationHasBecomeActive else { return }
        applicationHasBecomeActive = true

        launchInitialTerminalWindowIfNeeded()

        // Present onboarding after initial activation/window setup so it
        // does not get buried behind startup windows.
        showOnboardingIfNeeded()
    }

    func launchInitialTerminalWindowIfNeeded() {
        // XCTest-hosted launches should not spawn real terminal windows or shells.
        guard !isRunningUnderXCTest() else { return }

        // Let's launch our first window. We only do this if we have no other windows. It
        // is possible to have other windows in a few scenarios:
        //   - if we're opening a URL since `application(_:openFile:)` is called before this.
        //   - if we're restoring from persisted state
        guard TerminalController.all.isEmpty, derivedConfig.initialWindow else { return }

        undoManager.disableUndoRegistration()
        defer { undoManager.enableUndoRegistration() }
        _ = TerminalController.newWindow(yen)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app alive for universal dictation when Launch at Login is enabled
        if DictationController.backgroundModeActive { return false }
        return derivedConfig.shouldQuitAfterLastWindowClosed
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let windows = NSApplication.shared.windows
        if (windows.isEmpty) { return .terminateNow }
        
        // If we've already accepted to install an update, then we don't need to
        // confirm quit. The user is already expecting the update to happen.
        //
        // This deliberately asks `shouldTerminateWithoutWarning` rather than
        // "is the state .installing at all". A silently auto-installed update
        // (`.installing` carrying an appcastItem) must STILL confirm quit,
        // because the user never asked for a restart and is not expecting one.
        // Only a manually-triggered install skips the confirmation.
        if updateController.shouldTerminateWithoutWarning {
            return .terminateNow
        }

        // If the user is shutting down, restarting, or logging out, we don't confirm quit.
        why: if let event = NSAppleEventManager.shared().currentAppleEvent {
            // If all YEN windows are in the background (i.e. you Cmd-Q from the Cmd-Tab
            // view), then this is null. I don't know why (pun intended) but we have to
            // guard against it.
            guard let keyword = AEKeyword("why?") else { break why }

            if let why = event.attributeDescriptor(forKeyword: keyword) {
                switch (why.typeCodeValue) {
                case kAEShutDown:
                    fallthrough

                case kAERestart:
                    fallthrough

                case kAEReallyLogOut:
                    return .terminateNow

                default:
                    break
                }
            }
        }

        // If our app says we don't need to confirm, we can exit now.
        if (!yen.needsConfirmQuit) { return .terminateNow }

        return terminate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopExtras.shared.stop()
        // From here on a pane teardown is the app leaving, so persistent
        // sessions detach instead of ending (PersistentSessions.paneDidClose).
        PersistentSessions.markTerminating()
        tearDownLocalEventMonitor()
        SettingsController.shared.flushPendingRealTimeConfigSyncForApplicationTermination()
    }

    /// This is called when the application is already open and someone double-clicks the icon
    /// or clicks the dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If we have visible windows then we allow macOS to do its default behavior
        // of focusing one of them.
        guard !flag else { return true }

        // If we have any windows in our terminal manager we don't do anything.
        // This is possible with flag set to false if there a race where the
        // window is still initializing and is not visible but the user clicked
        // the dock icon.
        guard TerminalController.all.isEmpty else { return true }

        // If the application isn't active yet then we don't want to process
        // this because we're not ready. This happens sometimes in Xcode runs
        // but I haven't seen it happen in releases. I'm unsure why.
        guard applicationHasBecomeActive else { return true }

        if #available(macOS 27.0, *) {
            // It seems that with macOS 27, running an App Intent against an already
            // running app (from Shortcuts, Spotlight, the `shortcuts` CLI, ...)
            // opens the app through LaunchServices in the background before the
            // intent is delivered, which we receive as a reopen event.
            //
            // Ignore reopens from the intents runner unless it asked for us to come to
            // the front to prevent creating two windows (upstream #14107).
            let appIntentsRunnerBundleIdentifiers: Set<String> = [
                "com.apple.WorkflowKit.BackgroundShortcutRunner",
                "com.apple.shortcuts",
                "com.apple.siriactionsd",
            ]

            if let event = NSAppleEventManager.shared().currentAppleEvent,
               let sender = event.senderBundleIdentifier,
               appIntentsRunnerBundleIdentifiers.contains(sender),
               !event.expectsActivation {
                AppDelegate.logger.info("reopen triggered by shortcuts (\(sender)), ignoring...")
                return true
            }
        }

        // No visible windows, open a new one.
        _ = TerminalController.newWindow(yen)
        return false
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // `-e` makes existing path arguments part of the child command, but
        // AppKit also reports those paths as documents to open. Only consume
        // matching command arguments so unrelated Finder or Dock requests work.
        if commandLineOpenFileFilter.shouldIgnore(filename) {
            Self.logger.debug("ignoring command argument open-file event path=\(filename, privacy: .public)")
            return true
        }

        // YEN will validate as well but we can avoid creating an entirely new
        // surface by doing our own validation here. We can also show a useful error
        // this way.
        
        var isDirectory = ObjCBool(true)
        guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDirectory) else { return false }
        
        // Set to true if confirmation is required before starting up the
        // new terminal.
        var requiresConfirm: Bool = false
        
        // Initialize the surface config which will be used to create the tab or window for the opened file.
        var config = YEN.SurfaceConfiguration()
        
        if (isDirectory.boolValue) {
            // When opening a directory, check the configuration to decide
            // whether to open in a new tab or new window.
            config.workingDirectory = filename
        } else {
            // Unconditionally require confirmation in the file execution case.
            // In the future I have ideas about making this more fine-grained if
            // we can not inherit of unsandboxed state. For now, we need to confirm
            // because there is a sandbox escape possible if a sandboxed application
            // somehow is tricked into `open`-ing a non-sandboxed application.
            requiresConfirm = true

            // Ported from upstream Ghostty (7597e85f...291fd050): refuse to
            // execute a file whose path contains control characters.
            //
            // We run the file by typing its quoted path into the shell (see
            // `initialInput` below). Quoting can't protect against control
            // characters, because they act as keys while being typed. For
            // example, a file named "Foo<Ctrl-U>ls<Return>" erases the quoted
            // path and runs `ls` instead. These characters are also invisible
            // in the confirmation dialog, so the user would be approving a
            // command they can't see. No legitimate file needs them, so we
            // reject the file outright. See
            // `YEN.Shell.containsControlCharacters` for more detail.
            guard !YEN.Shell.containsControlCharacters(filename) else {
                // `debugDescription` makes the hidden characters visible in the log.
                Self.logger.warning("refusing to execute file with control characters path=\(filename.debugDescription, privacy: .public)")
                let alert = NSAlert()
                alert.messageText = "Cannot Execute File"
                alert.informativeText = "This file's path contains hidden control characters, which could make YEN run a different command than the one shown."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .warning
                alert.runModal()
                return false
            }

            // When opening a file, we want to execute the file. To do this, we
            // don't override the command directly, because it won't load the
            // profile/rc files for the shell, which is super important on macOS
            // due to things like Homebrew. Instead, we set the command to
            // `<filename>; exit` which is what Terminal and iTerm2 do.
            config.initialInput = "\(YEN.Shell.quote(filename)); exit\n"
            
            // For commands executed directly, we want to ensure we wait after exit
            // because in most cases scripts don't block on exit and we don't want
            // the window to just flash closed once complete.
            config.waitAfterCommand = true
            
            // Set the parent directory to our working directory so that relative
            // paths in scripts work.
            config.workingDirectory = (filename as NSString).deletingLastPathComponent
        }
        
        if requiresConfirm {
            // Confirmation required. We use an app-wide NSAlert for now. In the future we
            // may want to show this as a sheet on the focused window (especially if we're
            // opening a tab). I'm not sure.
            let alert = NSAlert()
            alert.messageText = "Allow YEN to execute \"\(filename)\"?"
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            switch (alert.runModal()) {
            case .alertFirstButtonReturn:
                break
                
            default:
                return false
            }
        }
        
        switch yen.config.macosDockDropBehavior {
        case .new_tab:
            _ = TerminalController.newTab(
                yen,
                from: TerminalController.preferredParent?.window,
                withBaseConfig: config
            )
        case .new_window: _ = TerminalController.newWindow(yen, withBaseConfig: config)
        }
        
        return true
    }

    /// This is called for the dock right-click menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return dockMenu
    }

    /// Setup signal handlers
    private func setupSignals() {
        // Register a signal handler for config reloading. It appears that all
        // of this is required. I've commented each line because its a bit unclear.
        // Warning: signal handlers don't work when run via Xcode. They have to be
        // run on a real app bundle.

        // We need to ignore signals we register with makeSignalSource or they
        // don't seem to handle.
        signal(SIGUSR2, SIG_IGN)

        // Make the signal source and register our event handle. We keep a weak
        // ref to ourself so we don't create a retain cycle.
        let sigusr2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        sigusr2.setEventHandler { [weak self] in
            guard let self else { return }
            YEN.logger.info("reloading configuration in response to SIGUSR2")
            self.yen.reloadConfig()
            // Post notification to show toast in terminal windows
            NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
        }

        // The signal source starts unactivated, so we have to resume it once
        // we setup the event handler.
        sigusr2.resume()

        // We need to keep a strong reference to it so it isn't disabled.
        signals.append(sigusr2)
    }

    /// Setup all the images for our menu items.
    private func setupMenuImages() {
        // Note: This COULD Be done all in the xib file, but I find it easier to
        // modify this stuff as code.
        self.menuAbout?.setImageIfDesired(systemSymbolName: "info.circle")
        self.menuYENHelp?.setImageIfDesired(systemSymbolName: "lightbulb")
        self.menuJPTheCat?.setImageIfDesired(systemSymbolName: "pawprint")
        self.menuBitcoinEmail?.setImageIfDesired(systemSymbolName: "bitcoinsign.circle")
        self.menuCheckForUpdates?.setImageIfDesired(systemSymbolName: "square.and.arrow.down")
        self.menuSettings?.setImageIfDesired(systemSymbolName: "gearshape")
        self.menuOpenConfig?.setImageIfDesired(systemSymbolName: "gear")
        self.menuReloadConfig?.setImageIfDesired(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90")
        self.menuSecureInput?.setImageIfDesired(systemSymbolName: "lock.display")
        self.menuNewWindow?.setImageIfDesired(systemSymbolName: "macwindow.badge.plus")
        self.menuNewTab?.setImageIfDesired(systemSymbolName: "macwindow")
        self.menuOpenFileBrowser?.setImageIfDesired(systemSymbolName: "folder")
        self.menuScreenshot?.setImageIfDesired(systemSymbolName: "camera.viewfinder")
        self.menuSplitRight?.setImageIfDesired(systemSymbolName: "rectangle.righthalf.inset.filled")
        self.menuSplitLeft?.setImageIfDesired(systemSymbolName: "rectangle.leadinghalf.inset.filled")
        self.menuSplitUp?.setImageIfDesired(systemSymbolName: "rectangle.tophalf.inset.filled")
        self.menuSplitDown?.setImageIfDesired(systemSymbolName: "rectangle.bottomhalf.inset.filled")
        self.menuClose?.setImageIfDesired(systemSymbolName: "xmark")
        // Close Tab / Close Window sit two rows above Close All Windows, whose icon
        // AppKit supplies itself as a boxed xmark — so neither may use that glyph.
        self.menuCloseTab?.setImageIfDesired(systemSymbolName: "xmark.circle")
        self.menuCloseWindow?.setImageIfDesired(systemSymbolName: "rectangle.badge.xmark")
        self.menuPasteSelection?.setImageIfDesired(systemSymbolName: "doc.on.clipboard.fill")
        self.menuFind?.setImageIfDesired(systemSymbolName: "magnifyingglass")
        self.menuFindNext?.setImageIfDesired(systemSymbolName: "chevron.down")
        self.menuFindPrevious?.setImageIfDesired(systemSymbolName: "chevron.up")
        self.menuHideFindBar?.setImageIfDesired(systemSymbolName: "xmark")
        self.menuSelectionForFind?.setImageIfDesired(systemSymbolName: "text.magnifyingglass")
        self.menuScrollToSelection?.setImageIfDesired(systemSymbolName: "dot.viewfinder")
        self.menuIncreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.larger")
        self.menuResetFontSize?.setImageIfDesired(systemSymbolName: "textformat.size")
        self.menuDecreaseFontSize?.setImageIfDesired(systemSymbolName: "textformat.size.smaller")
        self.menuCommandPalette?.setImageIfDesired(systemSymbolName: "filemenu.and.selection")
        self.menuQuickTerminal?.setImageIfDesired(systemSymbolName: "apple.terminal")
        self.menuChangeTabTitle?.setImageIfDesired(systemSymbolName: "pencil.line")
        self.menuChangeTitle?.setImageIfDesired(systemSymbolName: "rectangle.and.pencil.and.ellipsis")
        self.menuTerminalInspector?.setImageIfDesired(systemSymbolName: "scope")
        self.menuReadonly?.setImageIfDesired(systemSymbolName: "eye.fill")
        self.menuToggleFullScreen?.setImageIfDesired(systemSymbolName: "square.arrowtriangle.4.outward")
        self.menuToggleVisibility?.setImageIfDesired(systemSymbolName: "eye")
        self.menuZoomSplit?.setImageIfDesired(systemSymbolName: "arrow.up.left.and.arrow.down.right")
        self.menuPreviousSplit?.setImageIfDesired(systemSymbolName: "chevron.backward.2")
        self.menuNextSplit?.setImageIfDesired(systemSymbolName: "chevron.forward.2")
        self.menuSelectSplitParent?.setImageIfDesired(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right")
        self.menuResizeSplitParent?.setImageIfDesired(systemSymbolName: "arrow.left.and.line.vertical.and.arrow.right")
        self.menuEqualizeSplits?.setImageIfDesired(systemSymbolName: "inset.filled.topleft.topright.bottomleft.bottomright.rectangle")
        self.menuSelectSplitLeft?.setImageIfDesired(systemSymbolName: "arrow.left")
        self.menuSelectSplitRight?.setImageIfDesired(systemSymbolName: "arrow.right")
        self.menuSelectSplitAbove?.setImageIfDesired(systemSymbolName: "arrow.up")
        self.menuSelectSplitBelow?.setImageIfDesired(systemSymbolName: "arrow.down")
        self.menuMoveSplitDividerUp?.setImageIfDesired(systemSymbolName: "arrow.up.to.line")
        self.menuMoveSplitDividerDown?.setImageIfDesired(systemSymbolName: "arrow.down.to.line")
        self.menuMoveSplitDividerLeft?.setImageIfDesired(systemSymbolName: "arrow.left.to.line")
        self.menuMoveSplitDividerRight?.setImageIfDesired(systemSymbolName: "arrow.right.to.line")
        self.menuReturnToDefaultSize?.setImageIfDesired(systemSymbolName: "arrow.counterclockwise")
        self.menuFloatOnTop?.setImageIfDesired(systemSymbolName: "square.filled.on.square")
        self.menuUseAsDefault?.setImageIfDesired(systemSymbolName: "pin.fill")
        // Not an overlapping-windows glyph: AppKit's own "Merge All Windows" and
        // YEN's "Float on Top" already use that shape in this same menu.
        self.menuBringAllToFront?.setImageIfDesired(systemSymbolName: "square.3.layers.3d.top.filled")
        self.menuFindParent?.setImageIfDesired(systemSymbolName: "text.page.badge.magnifyingglass")
    }

    /// Sync all of our menu item keyboard shortcuts with the YEN configuration.
    @MainActor private func syncMenuShortcuts(_ config: YEN.Config) {
        guard yen.readiness == .ready else { return }

        menuShortcutController.sync(
            config: config,
            menuItems: menuShortcutItems
        )

        // Dock menu
        reloadDockMenu()
    }

    private var menuShortcutItems: AppMenuShortcutController.MenuItems {
        AppMenuShortcutController.MenuItems(
            checkForUpdates: menuCheckForUpdates,
            openConfig: menuOpenConfig,
            reloadConfig: menuReloadConfig,
            quit: menuQuit,
            newWindow: menuNewWindow,
            newTab: menuNewTab,
            close: menuClose,
            closeTab: menuCloseTab,
            closeWindow: menuCloseWindow,
            closeAllWindows: menuCloseAllWindows,
            splitRight: menuSplitRight,
            splitLeft: menuSplitLeft,
            splitDown: menuSplitDown,
            splitUp: menuSplitUp,
            undo: menuUndo,
            redo: menuRedo,
            copy: menuCopy,
            paste: menuPaste,
            pasteSelection: menuPasteSelection,
            selectAll: menuSelectAll,
            find: menuFind,
            selectionForFind: menuSelectionForFind,
            scrollToSelection: menuScrollToSelection,
            findNext: menuFindNext,
            findPrevious: menuFindPrevious,
            zoomSplit: menuZoomSplit,
            previousSplit: menuPreviousSplit,
            nextSplit: menuNextSplit,
            selectSplitAbove: menuSelectSplitAbove,
            selectSplitBelow: menuSelectSplitBelow,
            selectSplitLeft: menuSelectSplitLeft,
            selectSplitRight: menuSelectSplitRight,
            moveSplitDividerUp: menuMoveSplitDividerUp,
            moveSplitDividerDown: menuMoveSplitDividerDown,
            moveSplitDividerLeft: menuMoveSplitDividerLeft,
            moveSplitDividerRight: menuMoveSplitDividerRight,
            equalizeSplits: menuEqualizeSplits,
            returnToDefaultSize: menuReturnToDefaultSize,
            increaseFontSize: menuIncreaseFontSize,
            decreaseFontSize: menuDecreaseFontSize,
            resetFontSize: menuResetFontSize,
            changeTitle: menuChangeTitle,
            changeTabTitle: menuChangeTabTitle,
            quickTerminal: menuQuickTerminal,
            toggleVisibility: menuToggleVisibility,
            floatOnTop: menuFloatOnTop,
            terminalInspector: menuTerminalInspector,
            commandPalette: menuCommandPalette,
            secureInput: menuSecureInput,
            settings: menuSettings
        )
    }

    nonisolated static func isReservedSettingsShortcut(
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        AppMenuShortcutController.isReservedSettingsShortcut(
            keyEquivalent: keyEquivalent,
            modifiers: modifiers
        )
    }

    @MainActor private func matchedYENMenuItem(for event: NSEvent) -> NSMenuItem? {
        menuShortcutController.matchedYENMenuItem(for: event)
    }

    @MainActor func yenMenuActionSelector(for event: NSEvent) -> Selector? {
        matchedYENMenuItem(for: event)?.action
    }

    /// Attempts to perform a menu key equivalent only for menu items that represent
    /// YEN keybind actions. This is important because it lets our surface dispatch
    /// bindings through the menu so they flash but also lets our surface override macOS built-ins
    /// like Cmd+H.
    @MainActor func performYENBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        guard let item = matchedYENMenuItem(for: event),
              let parentMenu = item.menu else {
            return false
        }

        let index = parentMenu.index(of: item)
        parentMenu.performActionForItem(at: index)
        return true
    }

    // MARK: Notifications and Events

    private func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown],
            handler: localEventHandler
        )
    }

    private func tearDownLocalEventMonitor() {
        guard let localEventMonitor else { return }
        NSEvent.removeMonitor(localEventMonitor)
        self.localEventMonitor = nil
    }

    /// This handles events from the NSEvent.addLocalEventMonitor. We use this so we can get
    /// events without any terminal windows open.
    private func localEventHandler(_ event: NSEvent) -> NSEvent? {
        return switch event.type {
        case .keyDown:
            localEventKeyDown(event)

        default:
            event
        }
    }

    private func localEventKeyDown(_ event: NSEvent) -> NSEvent? {
        // If the tab overview is visible and escape is pressed, close it.
        // This can't POSSIBLY be right and is probably a FirstResponder problem
        // that we should handle elsewhere in our program. But this works and it
        // is guarded by the tab overview currently showing.
        if event.keyCode == 0x35, // Escape key
           let window = NSApp.keyWindow,
           let tabGroup = window.tabGroup,
           tabGroup.isOverviewVisible {
            window.toggleTabOverview(nil)
            return nil
        }

        // Cmd+Shift+J / Cmd+Shift+B overlap Ghostty/terminal bindings; when the
        // target feature is disabled, consume and beep instead of falling through.
        if consumeDisabledToggleHotkey(
            ScratchpadController.shouldConsumeDisabledToggleHotkey(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags,
                scratchpadEnabled: ScratchpadController.scratchpadEnabled
            ),
            featureName: "Scratchpad",
            event: event
        ) {
            return nil
        }
        if consumeDisabledToggleHotkey(
            TabSidebarController.shouldConsumeDisabledToggleHotkey(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifierFlags: event.modifierFlags,
                tabSidebarEnabled: TabSidebarController.tabSidebarEnabled
            ),
            featureName: "Tab Sidebar",
            event: event
        ) {
            return nil
        }

        if WebPreviewController.isStandardCloseShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) {
            let closedBrowserSurface = MainActor.assumeIsolated {
                BrowserSplitController.shared.closeIfWebViewFocused(keyWindow: NSApp.keyWindow)
                    || WebPreviewController.shared.closeIfFocused(keyWindow: NSApp.keyWindow, sender: nil)
            }
            if closedBrowserSurface {
                return nil
            }
        }

        // If we have a main window then we don't process any of the keys
        // because we let it capture and propagate.
        guard NSApp.mainWindow == nil else { return event }

        // If this event as-is would result in a key binding then we send it.
        if let app = yen.app, let config = yen.config.config {
            var yenEvent = event.yenKeyEvent(YEN_ACTION_PRESS)
            let match = (event.characters ?? "").withCString { ptr in
                yenEvent.text = ptr
                if !yen_config_key_is_binding(config, yenEvent) {
                    return false
                }

                return yen_app_key(app, yenEvent)
            }

            // If the key was handled by YEN we stop the event chain. If
            // the key wasn't handled then we let it fall through and continue
            // processing. This is important because some bindings may have no
            // affect at this scope.
            if match {
                return nil
            }
        }

        // If this event would be handled by our menu then we do nothing.
        if let mainMenu = NSApp.mainMenu,
           mainMenu.performKeyEquivalent(with: event) {
            return nil
        }

        // If we reach this point then we try to process the key event
        // through the YEN key mechanism.

        // YEN must be loaded
        guard let yen = self.yen.app else { return event }

        // Build our event input and call yen
        if (yen_app_key(yen, event.yenKeyEvent(YEN_ACTION_PRESS))) {
            // The key was used so we want to stop it from going to our Mac app
            YEN.logger.debug("local key event handled event=\(event)")
            return nil
        }

        return event
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        syncFloatOnTopMenu(notification.object as? NSWindow)
    }

    @objc private func quickTerminalDidChangeVisibility(_ notification: Notification) {
        guard let quickController = notification.object as? QuickTerminalController else { return }
        self.menuQuickTerminal?.state = if (quickController.visible) { .on } else { .off }
    }

    @objc private func yenConfigDidChange(_ notification: Notification) {
        // We only care if the configuration is a global configuration, not a surface one.
        guard notification.object == nil else { return }

        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.YENConfigChangeKey
        ] as? YEN.Config else { return }

        yenConfigDidChange(config: config)
    }

    /// Retranslate menu shortcuts when the active keyboard layout changes.
    /// Ported from upstream Ghostty 6a508fd5 (#13888): physical menu shortcuts
    /// are translated through the current layout, so a layout switch has to
    /// re-sync them or the menus keep showing the previous layout's keys.
    @MainActor @objc private func keyboardSelectionDidChange(_ notification: Notification) {
        syncMenuShortcuts(yen.config)
        TerminalController.all.forEach { $0.relabelTabs() }
    }

    @objc private func yenBellDidRing(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let attentionEnabled = yen.config.bellFeatures.contains(.attention)
            let manager = NotificationSoundManager.shared
            let deliveryMode = manager.deliveryMode(for: .general)
            let settings = await UNUserNotificationCenter.current().notificationSettings()

            let decision = BellNotificationPolicy.decision(
                attentionEnabled: attentionEnabled,
                appIsActive: NSApp.isActive,
                authorizationStatus: settings.authorizationStatus,
                soundSetting: settings.soundSetting,
                badgeSetting: settings.badgeSetting,
                deliveryMode: deliveryMode,
                soundWhenFocused: manager.soundWhenFocused
            )

            if decision.playSound {
                _ = manager.resolveAndPlay(for: .general)
            }
            if decision.requestAttention {
                NSApp.requestUserAttention(.informationalRequest)
            }
            if decision.setDockBadge {
                setDockBadge()
            }
        }
    }

    @objc private func yenNewWindow(_ notification: Notification) {
        let configAny = notification.userInfo?[YEN.Notification.NewSurfaceConfigKey]
        let config = configAny as? YEN.SurfaceConfiguration
        _ = TerminalController.newWindow(yen, withBaseConfig: config)
    }

    @objc private func yenNewTab(_ notification: Notification) {
        guard let surfaceView = notification.object as? YEN.SurfaceView else { return }
        guard let window = surfaceView.window else { return }

        // We only want to listen to new tabs if the focused parent is
        // a regular terminal controller.
        guard window.windowController is TerminalController else { return }

        let configAny = notification.userInfo?[YEN.Notification.NewSurfaceConfigKey]
        let config = configAny as? YEN.SurfaceConfiguration

        _ = TerminalController.newTab(yen, from: window, withBaseConfig: config)
    }

    private func setDockBadge(_ label: String? = "•") {
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    private func yenConfigDidChange(config: YEN.Config) {
        // Update the config we need to store
        self.derivedConfig = DerivedConfig(config)

        // Depending on the "window-save-state" setting we have to set the NSQuitAlwaysKeepsWindows
        // configuration. This is the only way to carefully control whether macOS invokes the
        // state restoration system.
        switch (config.windowSaveState) {
        case "never": UserDefaults.standard.setValue(false, forKey: "NSQuitAlwaysKeepsWindows")
        case "always": UserDefaults.standard.setValue(true, forKey: "NSQuitAlwaysKeepsWindows")
        case "default": fallthrough
        default: UserDefaults.standard.removeObject(forKey: "NSQuitAlwaysKeepsWindows")
        }

        // Sync auto-update settings. When the user explicitly sets `auto-update`
        // in config, honor it. Otherwise let Sparkle manage its own defaults —
        // on first launch it shows a permission dialog asking the user to opt in,
        // and remembers the choice in UserDefaults.
        if let autoUpdate = config.autoUpdate {
            updateController.updater.automaticallyChecksForUpdates =
                autoUpdate != .off
            updateController.updater.automaticallyDownloadsUpdates =
                autoUpdate == .download
        }

        // Config could change keybindings, so update everything that depends on that.
        // Hopped to the main actor because upstream Ghostty 9886f481 made menu-shortcut
        // syncing main-actor-isolated while this handler stays nonisolated.
        DispatchQueue.main.async {
            self.syncMenuShortcuts(config)
        }
        TerminalController.all.forEach { $0.relabelTabs() }

        // Config could change window appearance. We wrap this in an async queue because when
        // this is called as part of application launch it can deadlock with an internal
        // AppKit mutex on the appearance.
        DispatchQueue.main.async { self.syncAppearance(config: config) }

        // Decide whether to hide/unhide app from dock and app switcher
        switch (config.macosHidden) {
        case .never:
            NSApp.setActivationPolicy(.regular)

        case .always:
            NSApp.setActivationPolicy(.accessory)
        }

        // If we have configuration errors, we need to show them.
        let c = ConfigurationErrorsController.sharedInstance
        c.errors = config.errors
        if (c.errors.count > 0 && !isRunningUnderXCTest()) {
            if (c.window == nil || !c.window!.isVisible) {
                c.showWindow(self)
            }
        }

        // We need to handle our global event tap depending on if there are global
        // events that we care about in YEN.
        pendingGlobalEventTapEnableWorkItem?.cancel()
        pendingGlobalEventTapEnableWorkItem = nil
        let hasGlobalKeybinds = if let app = yen.app {
            yen_app_has_global_keybinds(app)
        } else {
            false
        }
        if (hasGlobalKeybinds) {
            if (timeSinceLaunch > 5) {
                // If the process has been running for awhile we enable right away
                // because no windows are likely to pop up.
                GlobalEventTap.shared.enable()
            } else {
                // If the process just started, we wait a couple seconds to allow
                // the initial windows and so on to load so our permissions dialog
                // doesn't get buried.
                let workItem = DispatchWorkItem {
                    GlobalEventTap.shared.enable()
                }
                pendingGlobalEventTapEnableWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: workItem)
            }
        } else {
            GlobalEventTap.shared.disable()
        }
        Task {
            await updateAppIcon(from: config)
        }
    }

    /// Temporarily override the configured application appearance for this session.
    /// A nil appearance restores the configured appearance.
    func setAppearance(_ appearance: Appearance?) {
        appearanceOverride = appearance
        syncAppearance(config: yen.config)

        NSApplication.shared.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .forEach { $0.syncAppearance() }
    }

    /// Sync the appearance of our app with the theme specified in the config.
    private func syncAppearance(config: YEN.Config) {
        NSApplication.shared.appearance = if let appearanceOverride {
            appearanceOverride.nsAppearance
        } else {
            .init(yenConfig: config)
        }
    }

    // Using AppIconActor to ensure this work
    // happens synchronously in the background
    nonisolated static func bundledAppIcon(named assetName: String?) -> NSImage? {
        guard let assetName else { return nil }
        return NSImage(named: assetName)
    }

    @AppIconActor
    private func updateAppIcon(from config: YEN.Config) async  {
        var appIcon: NSImage?
        var appIconName: String? = config.macosIcon.rawValue

        switch (config.macosIcon) {
        case let icon where icon.assetName != nil:
            if let builtInIcon = Self.bundledAppIcon(named: icon.assetName) {
                appIcon = builtInIcon
            } else {
                appIconName = nil
                if let assetName = icon.assetName {
                    Self.logger.error("Built-in app icon asset missing: \(assetName, privacy: .public)")
                }
            }

        case .custom:
            if let userIcon = NSImage(contentsOfFile: config.macosCustomIcon) {
                appIcon = userIcon
                appIconName = config.macosCustomIcon
            } else {
                appIcon = nil // Revert back to official icon if invalid location
                appIconName = nil // Discard saved icon name
            }

        case .customStyle:
            // Discard saved icon name
            // if no valid colours were found
            appIconName = nil
            guard let ghostColor = config.macosIconGhostColor else { break }
            guard let screenColors = config.macosIconScreenColor else { break }
            guard let icon = ColorizedYENIcon(
                screenColors: screenColors,
                ghostColor: ghostColor,
                frame: config.macosIconFrame
            ).makeImage(in: Bundle.main) else { break }
            appIcon = icon
            let colorStrings = ([ghostColor] + screenColors).compactMap(\.hexString)
            appIconName = (colorStrings + [config.macosIconFrame.rawValue])
                .joined(separator: "_")

        default:
            // Discard saved icon name
            appIconName = nil
        }

        // Only change the icon if it has actually changed from the current one,
        // or if the app build has changed (e.g. after an update that reset the icon)
        let cachedIconName = UserDefaults.standard.string(forKey: "CustomYENIcon")
        let cachedIconBuild = UserDefaults.standard.string(forKey: "CustomYENIconBuild")
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let buildChanged = cachedIconBuild != currentBuild

        guard cachedIconName != appIconName || buildChanged else {
#if DEBUG
            if appIcon == nil {
                await MainActor.run {
                    // Changing the app bundle's icon will corrupt code signing.
                    // We only use the default blueprint icon for the dock,
                    // so developers don't need to clean and re-build every time.
                    NSApplication.shared.applicationIconImage = NSImage(named: "BlueprintImage")
                }
            }
#endif
            return
        }
        // make it immutable, so Swift 6 won't complain
        let newIcon = appIcon

        let appPath = Bundle.main.bundlePath
        guard NSWorkspace.shared.setIcon(newIcon, forFile: appPath, options: []) else { return }
        NSWorkspace.shared.noteFileSystemChanged(appPath)

        await MainActor.run {
            self.appIcon = newIcon
            NSApplication.shared.applicationIconImage = newIcon
        }

        UserDefaults.standard.set(appIconName, forKey: "CustomYENIcon")
        UserDefaults.standard.set(currentBuild, forKey: "CustomYENIconBuild")
    }

    //MARK: - Restorable State

    /// We support NSSecureCoding for restorable state. Required as of macOS Sonoma (14) but a good idea anyways.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func application(_ app: NSApplication, willEncodeRestorableState coder: NSCoder) {
        Self.logger.debug("application will save window state")
        
        guard yen.config.windowSaveState != "never" else { return }
        
        // Encode our quick terminal state if we have it.
        switch quickTerminalControllerState {
        case .initialized(let controller) where controller.restorable:
            let data = QuickTerminalRestorableState(from: controller)
            data.encode(with: coder)
            
        case .pendingRestore(let state):
            state.encode(with: coder)
            
        default:
            break
        }
    }

    func application(_ app: NSApplication, didDecodeRestorableState coder: NSCoder) {
        Self.logger.debug("application will restore window state")
        
        // Decode our quick terminal state.
        if yen.config.windowSaveState != "never",
            let state = QuickTerminalRestorableState(coder: coder) {
            quickTerminalControllerState = .pendingRestore(state)
        }
    }

    //MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive: UNNotificationResponse,
        withCompletionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if !handleServiceNotificationResponse(didReceive) {
                yen.handleUserNotification(response: didReceive)
            }
            withCompletionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent: UNNotification,
        withCompletionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            let shouldPresent = yen.shouldPresentNotification(notification: willPresent)
            let options: UNNotificationPresentationOptions = shouldPresent ? [.banner, .sound] : []
            withCompletionHandler(adjustPresentationOptions(options, for: willPresent))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in
            SettingsController.shared.showNotificationSettings()
        }
    }

    //MARK: - YENAppDelegate

    func findSurface(forUUID uuid: UUID) -> YEN.SurfaceView? {
        for c in TerminalController.all {
            for view in c.surfaceTree {
                if view.id == uuid {
                    return view
                }
            }
        }

        if case .initialized(let quickController) = quickTerminalControllerState {
            for view in quickController.surfaceTree where view.id == uuid {
                return view
            }
        }

        return nil
    }

    //MARK: - Dock Menu

    private func reloadDockMenu() {
        let newWindow = NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "")
        let newTab = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "")

        dockMenu.removeAllItems()
        dockMenu.addItem(newWindow)
        dockMenu.addItem(newTab)
    }

    //MARK: - Global State

    func setSecureInput(_ mode: YEN.SetSecureInput) {
        let input = SecureInput.shared
        switch (mode) {
        case .on:
            input.global = true

        case .off:
            input.global = false

        case .toggle:
            input.global.toggle()
        }
        self.menuSecureInput?.state = if (input.global) { .on } else { .off }
        UserDefaults.standard.set(input.global, forKey: "SecureInput")
    }

    //MARK: - IB Actions

    @IBAction func openConfig(_ sender: Any?) {
        yen.openConfig()
    }

    @IBAction func reloadConfig(_ sender: Any?) {
        yen.reloadConfig()
        // Post notification to show toast in terminal windows
        NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)
    }

    @IBAction func checkForUpdates(_ sender: Any?) {
        updateController.checkForUpdates()
        //UpdateSimulator.happyPath.simulate(with: updateViewModel)
    }

    @IBAction func newWindow(_ sender: Any?) {
        _ = TerminalController.newWindow(yen)
    }

    @IBAction func newTab(_ sender: Any?) {
        _ = TerminalController.newTab(
            yen,
            from: TerminalController.preferredParent?.window
        )
    }

    @IBAction func closeAllWindows(_ sender: Any?) {
        TerminalController.closeAllWindows()
        AboutController.shared.hide()
    }

    @IBAction func showAbout(_ sender: Any?) {
        AboutController.shared.show()
    }

    @IBAction func showHelp(_ sender: Any) {
        guard let url = URL(string: "https://yen.chat/docs") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func openJPTheCat(_ sender: Any?) {
        guard let url = URL(string: "https://jpthecat.com") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func openBitcoinEmail(_ sender: Any?) {
        guard let url = URL(string: "https://btc.email") else { return }
        NSWorkspace.shared.open(url)
    }

    @IBAction func toggleSecureInput(_ sender: Any) {
        setSecureInput(.toggle)
    }

    @IBAction func toggleQuickTerminal(_ sender: Any) {
        let controller = quickController
        controller.toggle()
        if controller.visible,
           let window = controller.window as? QuickTerminalWindow {
            window.applyTerminalFacingCorners(for: derivedConfig.quickTerminalPosition)
        }
    }

    /// Toggles visibility of all Ghosty Terminal windows. When hidden, activates YEN as the frontmost application
    @IBAction func toggleVisibility(_ sender: Any) {
        // If we have focus, then we hide all windows.
        if NSApp.isActive {
            // Toggle visibility doesn't do anything if the focused window is native
            // fullscreen. This is only relevant if YEN is active.
            guard let keyWindow = NSApp.keyWindow,
                  !keyWindow.yenIsEffectivelyFullscreen else { return }

            NSApp.hide(nil)
            return
        }

        // If we're not active, we want to become active
        NSApp.yenActivateCompat()

        // Bring all windows to the front. Note: we don't use NSApp.unhide because
        // that will unhide ALL hidden windows. We want to only bring forward the
        // ones that we hid.
        hiddenState?.restore()
        hiddenState = nil
    }

    @IBAction func bringAllToFront(_ sender: Any) {
        if !NSApp.isActive {
            NSApp.yenActivateCompat()
        }

        NSApplication.shared.arrangeInFront(sender)
    }

    @IBAction func undo(_ sender: Any?) {
        undoManager.undo()
    }

    @IBAction func redo(_ sender: Any?) {
        undoManager.redo()
    }

    private struct DerivedConfig {
        let initialWindow: Bool
        let shouldQuitAfterLastWindowClosed: Bool
        let quickTerminalPosition: QuickTerminalPosition

        init() {
            self.initialWindow = true
            self.shouldQuitAfterLastWindowClosed = false
            self.quickTerminalPosition = .top
        }

        init(_ config: YEN.Config) {
            self.initialWindow = config.initialWindow
            self.shouldQuitAfterLastWindowClosed = config.shouldQuitAfterLastWindowClosed
            self.quickTerminalPosition = config.quickTerminalPosition
        }
    }

    struct ToggleVisibilityState {
        let hiddenWindows: [Weak<NSWindow>]
        let keyWindow: Weak<NSWindow>?

        fileprivate init() {
            // We need to know the key window so that we can bring focus back to the
            // right window if it was hidden.
            self.keyWindow = if let keyWindow = NSApp.keyWindow {
                .init(keyWindow)
            } else {
                nil
            }

            // We need to keep track of the windows that were visible because we only
            // want to bring back these windows if we remove the toggle.
            //
            // We also ignore fullscreen windows because they don't hide anyways.
            var visibleWindows = [Weak<NSWindow>]()
            NSApp.windows.filter {
                $0.isVisible &&
                !$0.yenIsEffectivelyFullscreen
            }.forEach { window in
                // We only keep track of selectedWindow if it's in a tabGroup,
                // so we can keep its selection state when restoring
                let windowToHide = window.tabGroup?.selectedWindow ?? window
                if !visibleWindows.contains(where: { $0.value === windowToHide }) {
                    visibleWindows.append(Weak(windowToHide))
                }
            }
            self.hiddenWindows = visibleWindows
        }

        func restore() {
            hiddenWindows.forEach { $0.value?.orderFrontRegardless() }
            keyWindow?.value?.makeKey()
        }
    }
}

// MARK: Floating Windows

extension AppDelegate {
    func syncFloatOnTopMenu(_ window: NSWindow?) {
        guard let window = (window ?? NSApp.keyWindow) as? TerminalWindow else {
            // If some other window became key we always turn this off
            self.menuFloatOnTop?.state = .off
            return
        }

        self.menuFloatOnTop?.state = window.level == .floating ? .on : .off
    }

    @IBAction func floatOnTop(_ menuItem: NSMenuItem) {
        menuItem.state = menuItem.state == .on ? .off : .on
        guard let window = NSApp.keyWindow else { return }
        window.level = menuItem.state == .on ? .floating : .normal
    }

    @IBAction func useAsDefault(_ sender: NSMenuItem) {
        let ud = UserDefaults.standard
        let key = TerminalWindow.defaultLevelKey
        if (menuFloatOnTop?.state == .on) {
            ud.set(NSWindow.Level.floating, forKey: key)
        } else {
            ud.removeObject(forKey: key)
        }
    }
}

// MARK: NSMenuItemValidation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(floatOnTop(_:)),
            #selector(useAsDefault(_:)):
            // Float on top items only active if the key window is a primary
            // terminal window (not quick terminal).
            return NSApp.keyWindow is TerminalWindow

        case #selector(undo(_:)):
            if undoManager.canUndo {
                item.title = "Undo \(undoManager.undoActionName)"
            } else {
                item.title = "Undo"
            }
            return undoManager.canUndo

        case #selector(redo(_:)):
            if undoManager.canRedo {
                item.title = "Redo \(undoManager.redoActionName)"
            } else {
                item.title = "Redo"
            }
            return undoManager.canRedo

        default:
            return true
        }
    }
}

// MARK: - Termination Flow

extension AppDelegate {
    func terminate() -> NSApplication.TerminateReply {
        // A pane in a persistent session keeps running after quit, so only an
        // ephemeral pane with a running process makes quitting kill something.
        let controllersNeedConfirmation = NSApplication.shared.windows
            .compactMap { $0.windowController as? BaseTerminalController }
            .filter { controller in
                guard !controller.windowCanBeClosedWithoutConfirmation() else { return false }
                return controller.surfaceTree.contains { surface in
                    PersistentSessions.quitKillsProcess(needsConfirmQuit: surface.needsConfirmQuit, paneID: surface.id)
                }
            }

        guard !controllersNeedConfirmation.isEmpty else {
            return .terminateNow
        }

        if controllersNeedConfirmation.count == 1 {
            Task {
                let response = await controllersNeedConfirmation[0].confirmCloseAsync(
                    messageText: "Quit YEN?",
                    informativeText: "The terminal still has a running process. If you quit, the process will be killed.",
                    confirmButtonTitle: "Terminate",
                )

                if [.OK, .alertFirstButtonReturn].contains(response) {
                    await NSApp.reply(toApplicationShouldTerminate: true)
                } else {
                    await NSApp.reply(toApplicationShouldTerminate: false)
                }
            }

            return .terminateLater
        } else {
            let alert = NSAlert.reviewWindowsAlert(
                messageText: "You have \(controllersNeedConfirmation.count) windows with running processes. Do you want to review these windows before quitting?"
            )

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                reviewWindows(controllersNeedConfirmation)
                return .terminateLater
            case .alertSecondButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }
    }

    private func reviewWindows(_ controllers: [BaseTerminalController]) {
        Task {
            for controller in controllers {
                let response = await controller.confirmCloseAsync(
                    messageText: "Quit YEN?",
                    informativeText: "The terminal still has a running process. If you quit, the process will be killed.",
                    confirmButtonTitle: "Terminate",
                )

                if [.OK, .alertFirstButtonReturn].contains(response) {
                    // Close this window and until next review is cancelled
                    await controller.window?.close()
                    continue
                } else {
                    await NSApp.reply(toApplicationShouldTerminate: false)
                    // Cancel the review
                    return
                }
            }
            await NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}

/// Represents the state of the quick terminal controller.
private enum QuickTerminalState {
    /// Controller has not been initialized and has no pending restoration state.
    case uninitialized
    /// Restoration state is pending; controller will use this when first accessed.
    case pendingRestore(QuickTerminalRestorableState)
    /// Controller has been initialized.
    case initialized(QuickTerminalController)
}

@globalActor
fileprivate actor AppIconActor: GlobalActor {
    static let shared = AppIconActor()
}
