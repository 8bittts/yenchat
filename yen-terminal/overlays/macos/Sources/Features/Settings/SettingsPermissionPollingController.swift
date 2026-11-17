#if os(macOS)
import Foundation

/// Owns the Settings window-session permission-polling timer, extracted from
/// `SettingsController`. While the Notifications or Dictation pane is visible the timer re-checks
/// microphone / notification / local-speech authorization every few seconds so
/// the UI reflects grants made in System Settings without a reopen. The caller
/// owns the tab/visibility gating and supplies the per-tick refresh work; this
/// type only owns the `Timer` lifecycle.
@MainActor
final class SettingsPermissionPollingController {
    private var timer: Timer?

    /// True while the polling timer is scheduled.
    var isActive: Bool {
        timer != nil
    }

    /// (Re)start polling, invoking `onTick` on the main actor every interval.
    func start(interval: TimeInterval = 4.0, tolerance: TimeInterval = 0.6, onTick: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                onTick()
            }
        }
        timer.tolerance = tolerance
        // Common mode so the re-poll keeps firing during menu/scroll/resize tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
