#if os(macOS)
import AppKit
import UserNotifications

/// Extension to handle build notifications from Claude Code hooks.
///
/// Uses the shared DistributedNotification → UNUserNotificationCenter pattern.
/// The distributed-notification identifier is centralized in YENCustomNotifications.swift
/// and must stay aligned with .claude/hooks/notify-complete.sh.
extension AppDelegate {
    /// Call from applicationDidFinishLaunching to start listening for build notifications.
    /// Authorization is requested contextually on first delivery or from Settings.
    func setupBuildNotificationObserver() {
        // AppDelegate is process-lifetime singleton and this setup runs once at launch.
        // Observer removal is intentionally omitted.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleBuildNotification(_:)),
            name: .yenBuildNotification,
            object: nil
        )
    }

    @MainActor
    @objc private func handleBuildNotification(_ notification: Notification) {
        handleServiceNotification(notification, service: .build, fallbackTitle: "YEN Terminal")
    }
}
#endif // os(macOS)
