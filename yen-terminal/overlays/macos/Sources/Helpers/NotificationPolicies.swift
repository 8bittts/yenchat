#if os(macOS)
import Foundation
import UserNotifications

enum NotificationAuthorizationStatusPolicy {
    static func allowsDelivery(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func statusLabel(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Blocked"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }

    static func actionTitle(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Grant"
        case .denied:
            return "Fix"
        case .authorized, .provisional, .ephemeral:
            return "Open Settings"
        @unknown default:
            return "Open Settings"
        }
    }

    static func actionHint(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Requests notification permission"
        case .authorized, .provisional, .ephemeral, .denied:
            return "Opens notification settings"
        @unknown default:
            return "Opens notification settings"
        }
    }

    static func detailLine(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Notifications are enabled for YEN."
        case .notDetermined:
            return "Enable notifications to receive build updates."
        case .denied:
            return "Notifications are disabled for YEN. Open System Settings > Notifications to re-enable."
        @unknown default:
            return "Notification authorization status is unavailable."
        }
    }
}

enum NotificationSettingsDestination {
    case notifications

    var urlCandidates: [String] {
        switch self {
        case .notifications:
            return [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications"
            ]
        }
    }
}

struct ServiceNotificationRouteMetadata: Equatable {
    static let schemaVersionPayloadKey = "schema_version"
    static let servicePayloadKey = "service"
    static let surfaceIDPayloadKey = "surface_id"

    let schemaVersion: String?
    let service: String?
    let surfaceID: String?

    init(schemaVersion: String?, service: String?, surfaceID: String?) {
        self.schemaVersion = Self.normalizedValue(schemaVersion)
        self.service = Self.normalizedValue(service)
        self.surfaceID = Self.normalizedSurfaceID(surfaceID)
    }

    init(userInfo: [AnyHashable: Any]?) {
        func stringValue(_ key: String) -> String? {
            guard let value = userInfo?[key] else { return nil }
            if let string = value as? String {
                return string
            }
            return "\(value)"
        }

        self.init(
            schemaVersion: stringValue(Self.schemaVersionPayloadKey),
            service: stringValue(Self.servicePayloadKey),
            surfaceID: stringValue(Self.surfaceIDPayloadKey)
        )
    }

    private static func normalizedSurfaceID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard let uuid = UUID(uuidString: trimmed) else {
            return nil
        }
        return uuid.uuidString
    }

    private static func normalizedValue(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct ServiceNotificationEnvelope: Equatable {
    let title: String
    let body: String
    let routeMetadata: ServiceNotificationRouteMetadata

    static func decode(from notification: Notification, fallbackTitle: String) -> ServiceNotificationEnvelope? {
        guard let payload = notification.object as? String else { return nil }

        let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = parts.count > 0 && !parts[0].isEmpty ? String(parts[0]) : fallbackTitle
        let body = parts.count > 1 ? String(parts[1]) : ""
        return ServiceNotificationEnvelope(
            title: title,
            body: body,
            routeMetadata: ServiceNotificationRouteMetadata(userInfo: notification.userInfo)
        )
    }
}

struct BellNotificationDecision: Equatable {
    let requestAttention: Bool
    let playSound: Bool
    let setDockBadge: Bool
}

enum BellNotificationPolicy {
    static func decision(
        attentionEnabled: Bool,
        appIsActive: Bool,
        authorizationStatus: UNAuthorizationStatus,
        soundSetting: UNNotificationSetting,
        badgeSetting: UNNotificationSetting,
        deliveryMode: NotificationDeliveryMode,
        soundWhenFocused: Bool
    ) -> BellNotificationDecision {
        let requestAttention = attentionEnabled && !appIsActive
        let authorizationAllowsDelivery = NotificationAuthorizationStatusPolicy.allowsDelivery(
            authorizationStatus
        )
        let playSound =
            authorizationAllowsDelivery &&
            soundSetting == .enabled &&
            deliveryMode.allowsSound &&
            (!appIsActive || soundWhenFocused)
        let setDockBadge =
            requestAttention &&
            authorizationAllowsDelivery &&
            badgeSetting == .enabled

        return BellNotificationDecision(
            requestAttention: requestAttention,
            playSound: playSound,
            setDockBadge: setDockBadge
        )
    }
}

enum ManagedNotificationRecoveryAction: Equatable {
    case none
    case requestAttention
    case showInAppRecovery
}

enum ManagedNotificationRecoveryPolicy {
    static func action(
        authorizationStatus: UNAuthorizationStatus,
        appIsActive: Bool,
        hasRequestedAttentionRecovery: Bool,
        hasPresentedRecoveryUI: Bool
    ) -> ManagedNotificationRecoveryAction {
        guard authorizationStatus == .denied else { return .none }
        if appIsActive {
            return hasPresentedRecoveryUI ? .none : .showInAppRecovery
        }
        return hasRequestedAttentionRecovery ? .none : .requestAttention
    }
}

enum NotificationFallbackWindowTarget: Equatable {
    case keyTerminal
    case mainTerminal
    case preferredTerminal
    case quickTerminal
    case none
}

enum NotificationFallbackWindowPolicy {
    static func target(
        keyWindowIsTerminalHost: Bool,
        mainWindowIsTerminalHost: Bool,
        hasPreferredTerminalWindow: Bool,
        hasQuickTerminalWindow: Bool
    ) -> NotificationFallbackWindowTarget {
        if keyWindowIsTerminalHost {
            return .keyTerminal
        }
        if mainWindowIsTerminalHost {
            return .mainTerminal
        }
        if hasPreferredTerminalWindow {
            return .preferredTerminal
        }
        if hasQuickTerminalWindow {
            return .quickTerminal
        }
        return .none
    }
}

enum ServiceNotificationPresentationPolicy {
    static func adjustedForegroundOptions(
        _ options: UNNotificationPresentationOptions,
        isServiceManaged: Bool,
        showBannerWhenFocused: Bool
    ) -> UNNotificationPresentationOptions {
        guard isServiceManaged else {
            return options
        }

        var adjusted = options
        adjusted.remove(.sound)
        if showBannerWhenFocused {
            adjusted.insert(.banner)
        }
        return adjusted
    }
}

enum ServiceNotificationResponseRoutingDecision: Equatable {
    case focusSurface(UUID)
    case safeFallback
    case noop
    case passthrough
}

enum ServiceNotificationResponseRouter {
    static func routeSurfaceUUID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo[AppDelegate.routeSurfaceIDUserInfoKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    static func isServiceManagedRoute(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo[AppDelegate.routeServiceUserInfoKey] != nil ||
        userInfo[AppDelegate.routeSchemaVersionUserInfoKey] != nil ||
        userInfo[AppDelegate.routeSurfaceIDUserInfoKey] != nil
    }

    static func decision(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> ServiceNotificationResponseRoutingDecision {
        guard isServiceManagedRoute(userInfo) else {
            return .passthrough
        }

        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier, YEN.userNotificationActionShow:
            guard let uuid = routeSurfaceUUID(from: userInfo) else { return .safeFallback }
            return .focusSurface(uuid)
        default:
            return .noop
        }
    }
}
#endif
