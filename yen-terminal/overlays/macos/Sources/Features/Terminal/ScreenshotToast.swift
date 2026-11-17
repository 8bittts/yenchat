import SwiftUI
import AppKit

enum ScreenshotToastOutcome: String, Equatable {
    case savedAndCopied
    case saved
    case copiedOnly
    case failure

    static func resolve(fileSaved: Bool, copiedToClipboard: Bool) -> Self {
        if fileSaved && copiedToClipboard { return .savedAndCopied }
        if fileSaved { return .saved }
        if copiedToClipboard { return .copiedOnly }
        return .failure
    }

    var iconName: String {
        switch self {
        case .savedAndCopied:
            return "checkmark.circle.fill"
        case .saved:
            return "square.and.arrow.down.fill"
        case .copiedOnly:
            return "doc.on.clipboard.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .savedAndCopied:
            return Color(NSColor.systemGreen)
        case .saved:
            return Color(NSColor.systemBlue)
        case .copiedOnly:
            return Color(NSColor.systemOrange)
        case .failure:
            return Color(NSColor.systemRed)
        }
    }
}

struct ScreenshotToastEvent: Equatable {
    let message: String
    let outcome: ScreenshotToastOutcome

    static func from(notification: Notification, observedWindowNumbers: Set<Int>) -> ScreenshotToastEvent? {
        guard let message = TerminalToastPayload.message(
            from: notification, observedWindowNumbers: observedWindowNumbers,
            windowNumberKey: Notification.Name.yenScreenshotWindowNumberKey,
            messageKey: Notification.Name.yenScreenshotToastMessageKey,
            defaultMessage: "Screenshot saved", allowsWindowObjectFallback: true
        ) else { return nil }
        return ScreenshotToastEvent(message: message, outcome: outcome(from: notification.userInfo))
    }

    private static func outcome(from userInfo: [AnyHashable: Any]?) -> ScreenshotToastOutcome {
        if let rawValue = userInfo?[Notification.Name.yenScreenshotOutcomeKey] as? String,
           let outcome = ScreenshotToastOutcome(rawValue: rawValue)
        {
            return outcome
        }

        let fileSaved = userInfo?[Notification.Name.yenScreenshotSavedKey] as? Bool ?? false
        let copiedToClipboard = userInfo?[Notification.Name.yenScreenshotClipboardCopiedKey] as? Bool ?? false
        return ScreenshotToastOutcome.resolve(fileSaved: fileSaved, copiedToClipboard: copiedToClipboard)
    }
}

/// A toast notification that briefly shows screenshot outcome details.
///
/// Same pattern as ConfigReloadToast — callers set `trigger` to a new UUID
/// to show the toast. Auto-dismisses after 2 seconds.
struct ScreenshotToast: View {
    /// Set to a new `UUID()` each time the toast should appear.
    @Binding var trigger: UUID?
    @Binding var message: String
    @Binding var outcome: ScreenshotToastOutcome
    var body: some View {
        MessageToast(
            trigger: $trigger,
            message: message,
            iconName: outcome.iconName,
            tintColor: outcome.tintColor
        )
    }
}

#Preview {
    ScreenshotToast(
        trigger: .constant(UUID()),
        message: .constant("Screenshot saved"),
        outcome: .constant(.savedAndCopied)
    )
        .frame(width: 400, height: 300)
        .background(Color.gray.opacity(0.3))
}
