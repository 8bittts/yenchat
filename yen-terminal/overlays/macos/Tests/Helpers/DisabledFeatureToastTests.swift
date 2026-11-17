import AppKit
import Combine
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct DisabledFeatureToastTests {
    /// The disabled-feature toast is the only user-facing feedback (besides the
    /// beep) that a swallowed ⇧⌘B / ⇧⌘J did anything. Guard the emission contract:
    /// the notification name, the feature-named copy, and the window-number key
    /// TerminalView filters on — a drift in any of these silently breaks the toast.
    ///
    /// Subscribes via the same Combine publisher path TerminalView uses so the
    /// test exercises the real delivery surface (and avoids the @Sendable capture
    /// of a raw NotificationCenter observer block).
    @Test func postEmitsNamedNotificationWithFeatureCopyAndWindowNumberKey() throws {
        var received: Notification?
        let cancellable = NotificationCenter.default
            .publisher(for: .yenHotkeyDisabledToast)
            .sink { received = $0 }
        defer { cancellable.cancel() }

        DisabledFeatureToast.post(featureName: "Tab Sidebar")

        let userInfo = try #require(received?.userInfo)
        let message = userInfo[Notification.Name.yenHotkeyDisabledMessageKey] as? String
        #expect(message == "Tab Sidebar is off — enable it in Settings › Workspace")
        // Window number is always present (falls back to 0 when no key/main window),
        // because TerminalView's observed-window filter reads it unconditionally.
        #expect(userInfo[Notification.Name.yenHotkeyDisabledWindowNumberKey] is Int)
        // The post must not retain a window — object is intentionally nil.
        #expect(received?.object == nil)
    }

    @Test func postInterpolatesEachFeatureNameIntoTheSharedCopy() {
        var messages: [String] = []
        let cancellable = NotificationCenter.default
            .publisher(for: .yenHotkeyDisabledToast)
            .sink { note in
                if let message = note.userInfo?[Notification.Name.yenHotkeyDisabledMessageKey] as? String {
                    messages.append(message)
                }
            }
        defer { cancellable.cancel() }

        DisabledFeatureToast.post(featureName: "Scratchpad")
        DisabledFeatureToast.post(featureName: "Tab Sidebar")

        #expect(messages == [
            "Scratchpad is off — enable it in Settings › Workspace",
            "Tab Sidebar is off — enable it in Settings › Workspace",
        ])
    }

    @Test func sharedToastAnnouncementUsesMessageAndHighPriority() {
        let userInfo = MessageToastAccessibility.announcementUserInfo(
            "Tab Sidebar is off — enable it in Settings › Workspace"
        )

        #expect(
            userInfo[.announcement] as? String
                == "Tab Sidebar is off — enable it in Settings › Workspace"
        )
        #expect(
            userInfo[.priority] as? Int
                == NSAccessibilityPriorityLevel.high.rawValue
        )
    }

    @Test func actionableToastDismissalHonorsAssistiveNavigation() {
        #expect(MessageToastAccessibility.autoDismissDelay(
            hasAction: false,
            voiceOverEnabled: true,
            fullKeyboardAccessEnabled: true
        ) == 2)
        #expect(MessageToastAccessibility.autoDismissDelay(
            hasAction: true,
            voiceOverEnabled: false,
            fullKeyboardAccessEnabled: false
        ) == 8)
        #expect(MessageToastAccessibility.autoDismissDelay(
            hasAction: true,
            voiceOverEnabled: true,
            fullKeyboardAccessEnabled: false
        ) == nil)
        #expect(MessageToastAccessibility.autoDismissDelay(
            hasAction: true,
            voiceOverEnabled: false,
            fullKeyboardAccessEnabled: true
        ) == nil)
    }
}
