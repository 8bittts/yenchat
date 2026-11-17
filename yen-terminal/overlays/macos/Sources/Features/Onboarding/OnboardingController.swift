#if os(macOS)
import Cocoa
import SwiftUI
import Speech
import AVFoundation

/// Controls the first-launch onboarding window that guides users through
/// granting the three permissions required for speech-to-text dictation.
@MainActor
final class OnboardingController: NSWindowController, NSWindowDelegate, ObservableObject, PermissionRefreshing {
    static let shared = OnboardingController()

    private static let hasCompletedSetupKey = "com.yenchat.yen.hasCompletedSetup"
    private static let hasDismissedSetupKey = "com.yenchat.yen.hasDismissedSetup"

    private enum CloseDisposition {
        case dismissed
        case completed
    }

    /// Whether onboarding should be shown (first launch, not yet completed).
    ///
    /// Reads the suite-aware store, like every other YEN preference. Reading
    /// `UserDefaults.yen` directly made this the one preference that ignored
    /// `YEN_USER_DEFAULTS_SUITE`, so an isolated run could not control it.
    ///
    /// An explicit suite means an automated run (UI tests set one per case). First-run
    /// onboarding is modal and takes focus, so showing it there hijacks whatever the
    /// harness is driving and every subsequent query hits the wrong window.
    static var needsOnboarding: Bool {
        guard UserDefaults.yenSuite == nil else { return false }
        let defaults = UserDefaults.yen
        return !defaults.bool(forKey: hasCompletedSetupKey)
            && !defaults.bool(forKey: hasDismissedSetupKey)
    }

    // MARK: - Published Properties (for SwiftUI binding)

    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false
    @Published var speechRecognitionGranted = false

    var allGranted: Bool {
        accessibilityGranted && microphoneGranted && speechRecognitionGranted
    }

    private var pollTimer: Timer?
    private var focusReassertWorkItem: DispatchWorkItem?
    private var closeDisposition: CloseDisposition = .dismissed

    // MARK: - Initialization

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Management

    func show() {
        ensureWindowAvailable()
        closeDisposition = .dismissed
        refreshPermissions()
        startPolling()
        cancelPendingFocusReassert()
        NSApp.unhide(nil)
        NSApp.yenActivateCompat()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        // Startup window choreography can still reorder windows one runloop later.
        // Re-assert focus once to keep onboarding discoverable on first launch.
        let workItem = DispatchWorkItem { [weak self] in
            defer { self?.focusReassertWorkItem = nil }
            guard let window = self?.window, window.isVisible, NSApp.isActive else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        focusReassertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func dismiss(markComplete: Bool = false) {
        closeDisposition = markComplete ? .completed : .dismissed
        stopPolling()
        cancelPendingFocusReassert()
        window?.close()
    }

    func openSettings(for destination: DictationController.PrivacyDestination) {
        cancelPendingFocusReassert()
        DictationController.shared.openSettings(for: destination)
    }

    private func ensureWindowAvailable() {
        yenDiscardReleasedUtilityWindowIfNeeded()
        if window == nil {
            createWindow()
        }
    }

    private func createWindow() {
        let contentView = OnboardingPanel(controller: self)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to YEN"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        self.window = window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        persistCloseDisposition()
        stopPolling()
        cancelPendingFocusReassert()
        yenReleaseOwnedUtilityWindow(from: notification)
        closeDisposition = .dismissed
    }

    // MARK: - Permission Polling

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
        pollTimer?.tolerance = 0.2
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func cancelPendingFocusReassert() {
        focusReassertWorkItem?.cancel()
        focusReassertWorkItem = nil
    }

    // MARK: - Completion

    private func persistCloseDisposition() {
        let defaults = UserDefaults.yen
        switch closeDisposition {
        case .dismissed:
            defaults.set(true, forKey: Self.hasDismissedSetupKey)
        case .completed:
            defaults.set(true, forKey: Self.hasCompletedSetupKey)
            defaults.removeObject(forKey: Self.hasDismissedSetupKey)
        }
    }
}

#if DEBUG
extension OnboardingController {
    var _testPollingActive: Bool {
        pollTimer != nil
    }

    var _testHasPendingFocusReassert: Bool {
        focusReassertWorkItem != nil
    }

    var _testHasWindow: Bool {
        window != nil
    }

    static var _testHasCompletedSetupKey: String {
        hasCompletedSetupKey
    }

    static var _testHasDismissedSetupKey: String {
        hasDismissedSetupKey
    }

    func _testPrepareForExternalSettingsTransition() {
        cancelPendingFocusReassert()
    }

    func _testResetState() {
        cancelPendingFocusReassert()
        stopPolling()
        closeDisposition = .dismissed
        yenReleaseOwnedUtilityWindow()
        accessibilityGranted = false
        microphoneGranted = false
        speechRecognitionGranted = false
        UserDefaults.yen.removeObject(forKey: Self.hasCompletedSetupKey)
        UserDefaults.yen.removeObject(forKey: Self.hasDismissedSetupKey)
    }
}
#endif
#endif // os(macOS)
