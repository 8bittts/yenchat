import AppKit
import SwiftUI

/// Shared presentation and accessibility behavior for transient terminal toasts.
/// A new trigger restarts the dismissal timer and announces the current message
/// to VoiceOver, including when the toast is retriggered before it fades out.
struct MessageToast: View {
    @Binding var trigger: UUID?
    let message: String
    let iconName: String
    let tintColor: Color
    var actionTitle: String?
    var actionAccessibilityHint: String?
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var isVisible = false
    @State private var generation = 0

    // Renders only the toast pill (no screen-filling spacer / bottom padding);
    // positioning and vertical stacking of concurrent toasts is owned by the
    // shared TerminalToastStack container so multiple toasts never overlap.
    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .foregroundColor(tintColor)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(YENTypography.body.weight(.medium))
                        .foregroundColor(.primary)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.link)
                            .accessibilityHint(actionAccessibilityHint ?? "")
                        Button {
                            generation += 1
                            isVisible = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close notification")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            reduceTransparency
                                ? AnyShapeStyle(Color(NSColor.windowBackgroundColor))
                                : AnyShapeStyle(.ultraThinMaterial)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tintColor.opacity(0.28), lineWidth: 1)
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .onChange(of: trigger) { newTrigger in
            guard newTrigger != nil else { return }
            generation += 1
            let expected = generation

            MessageToastAccessibility.announce(message)
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.easeOut(duration: YENMotion.standard)) {
                    isVisible = true
                }
            }

            guard let dismissDelay = MessageToastAccessibility.autoDismissDelay(
                hasAction: action != nil,
                voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled,
                fullKeyboardAccessEnabled: NSApp.isFullKeyboardAccessEnabled
            ) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                guard generation == expected else { return }
                if reduceMotion {
                    isVisible = false
                } else {
                    withAnimation(.easeIn(duration: YENMotion.standard)) {
                        isVisible = false
                    }
                }
            }
        }
    }
}

enum MessageToastAccessibility {
    static func autoDismissDelay(
        hasAction: Bool,
        voiceOverEnabled: Bool,
        fullKeyboardAccessEnabled: Bool
    ) -> TimeInterval? {
        guard hasAction else { return 2 }
        if voiceOverEnabled || fullKeyboardAccessEnabled {
            return nil
        }
        return 8
    }

    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: announcementUserInfo(message)
        )
    }

    static func announcementUserInfo(_ message: String) -> [NSAccessibility.NotificationUserInfoKey: Any] {
        [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
    }
}
