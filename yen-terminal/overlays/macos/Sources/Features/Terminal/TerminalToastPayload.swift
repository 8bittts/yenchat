import AppKit

/// Shared window routing and text normalization; callers own their fallback policy.
enum TerminalToastPayload {
    static func message(from notification: Notification, observedWindowNumbers: Set<Int>,
                        windowNumberKey: String, messageKey: String,
                        defaultMessage: String? = nil, allowsWindowObjectFallback: Bool = false) -> String? {
        guard !observedWindowNumbers.isEmpty else { return nil }
        // Integral NSNumber values bridge to Int. Never truncate a fractional window ID.
        let explicitNumber = notification.userInfo?[windowNumberKey] as? Int
        let target = explicitNumber ?? (allowsWindowObjectFallback
            ? (notification.object as? NSWindow)?.windowNumber : nil)
        guard let target, observedWindowNumbers.contains(target) else { return nil }
        let text = (notification.userInfo?[messageKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? defaultMessage : text
    }
}
