#if os(macOS)
import AppKit
import UserNotifications

private struct ManagedNotificationRequest {
    let service: NotificationService
    let title: String
    let subtitle: String?
    let body: String
    let identifier: String
    let categoryIdentifier: String?
    let userInfo: [AnyHashable: Any]
    let logLabel: String
}

private final class ManagedNotificationAuthorizationState {
    var pendingRequests: [ManagedNotificationRequest] = []
    var requestInFlight: Bool = false
    var hasRequestedDeniedAttentionRecovery: Bool = false
    var hasPresentedDeniedRecoveryUI: Bool = false
}

private enum ManagedNotificationQueuePolicy {
    static let maxPendingRequests = 16

    static func coalescingKey(for request: ManagedNotificationRequest) -> String {
        normalizedIdentifierPrefix(for: request.identifier)
    }

    private static func normalizedIdentifierPrefix(for identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return identifier }

        let components = trimmed.split(separator: ".")
        guard let last = components.last, UUID(uuidString: String(last)) != nil else {
            return trimmed
        }
        return components.dropLast().joined(separator: ".")
    }
}

/// Shared notification handler and authorization for app-managed notifications.
///
/// Each service's `@objc` handler calls handleServiceNotification with the appropriate
/// service enum value and fallback title. Sound resolution is delegated to
/// NotificationSoundManager. Sound plays only after verifying notification
/// authorization - prevents audio feedback when the user has denied permissions.
extension AppDelegate {
    /// Marks service notifications so foreground delivery can suppress system sound.
    static let serviceManagedSoundUserInfoKey = "YENServiceManagedSound"
    static let routeSchemaVersionUserInfoKey = "YENNotificationRouteSchemaVersion"
    static let routeServiceUserInfoKey = "YENNotificationRouteService"
    static let routeSurfaceIDUserInfoKey = "YENNotificationRouteSurfaceID"
    static let legacySurfaceIDUserInfoKey = "surface"
    static let legacyRequireFocusUserInfoKey = "requireFocus"

    private static let managedNotificationAuthorizationState = ManagedNotificationAuthorizationState()

    /// Centralize notification-center delegate ownership on AppDelegate.
    func installNotificationSoundPresentationHook() {
        UNUserNotificationCenter.current().delegate = self
    }

    static func requestNotificationAuthorizationIfNeeded() {
        Task { @MainActor in
            requestNotificationAuthorizationIfNeededOnMainActor()
        }
    }

    @MainActor
    static func openNotificationSystemSettings() {
        SystemSettingsOpener.open(candidates: NotificationSettingsDestination.notifications.urlCandidates)
    }

    /// Adjust foreground presentation options for service-managed notifications.
    func adjustPresentationOptions(
        _ options: UNNotificationPresentationOptions,
        for notification: UNNotification
    ) -> UNNotificationPresentationOptions {
        let isServiceManaged = (notification.request.content.userInfo[Self.serviceManagedSoundUserInfoKey] as? Bool) == true
        // Read directly from UserDefaults (thread-safe) to avoid crossing
        // actor boundaries in delegate callback closures.
        let showBanner = (UserDefaults.standard.object(forKey: NotificationSoundManager.bannerWhenFocusedKey) as? Bool) ?? false
        return ServiceNotificationPresentationPolicy.adjustedForegroundOptions(
            options,
            isServiceManaged: isServiceManaged,
            showBannerWhenFocused: showBanner
        )
    }

    static func deliverManagedLocalNotification(
        service: NotificationService = .general,
        title: String,
        subtitle: String? = nil,
        body: String,
        identifier: String? = nil,
        categoryIdentifier: String? = YEN.userNotificationCategory,
        userInfo: [AnyHashable: Any] = [:],
        logLabel: String? = nil
    ) {
        let request = ManagedNotificationRequest(
            service: service,
            title: title,
            subtitle: subtitle,
            body: body,
            identifier: identifier ?? makeNotificationRequestIdentifier(service: service),
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo,
            logLabel: logLabel ?? service.rawValue
        )
        deliverManagedNotification(request)
    }

    static func buildManagedSurfaceNotificationUserInfo(
        surfaceID: UUID,
        requireFocus: Bool
    ) -> [AnyHashable: Any] {
        [
            routeSurfaceIDUserInfoKey: surfaceID.uuidString,
            legacySurfaceIDUserInfoKey: surfaceID.uuidString,
            legacyRequireFocusUserInfoKey: requireFocus,
        ]
    }

    static func deliverManagedSurfaceNotification(
        surfaceView: YEN.SurfaceView,
        service: NotificationService = .general,
        title: String,
        subtitle: String? = nil,
        body: String,
        requireFocus: Bool = true,
        identifier: String? = nil,
        categoryIdentifier: String? = YEN.userNotificationCategory,
        logLabel: String? = nil
    ) {
        deliverManagedLocalNotification(
            service: service,
            title: title,
            subtitle: subtitle,
            body: body,
            identifier: identifier,
            categoryIdentifier: categoryIdentifier,
            userInfo: buildManagedSurfaceNotificationUserInfo(
                surfaceID: surfaceView.id,
                requireFocus: requireFocus
            ),
            logLabel: logLabel ?? service.rawValue
        )
    }

    func handleServiceNotification(
        _ notification: Notification,
        service: NotificationService,
        fallbackTitle: String,
        classifier: ((String, String) -> NotificationService)? = nil
    ) {
        guard let envelope = ServiceNotificationEnvelope.decode(from: notification, fallbackTitle: fallbackTitle) else { return }
        let resolvedService = classifier?(envelope.title, envelope.body) ?? service
        Self.deliverManagedNotification(
            ManagedNotificationRequest(
                service: resolvedService,
                title: envelope.title,
                subtitle: nil,
                body: envelope.body,
                identifier: Self.makeNotificationRequestIdentifier(service: resolvedService),
                categoryIdentifier: YEN.userNotificationCategory,
                userInfo: Self.buildServiceNotificationUserInfo(
                    resolvedService: resolvedService,
                    routeMetadata: envelope.routeMetadata
                ),
                logLabel: resolvedService.rawValue
            )
        )
    }

    static func buildServiceNotificationUserInfo(
        resolvedService: NotificationService,
        routeMetadata: ServiceNotificationRouteMetadata
    ) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            serviceManagedSoundUserInfoKey: true,
            routeServiceUserInfoKey: resolvedService.rawValue,
        ]

        if let schemaVersion = routeMetadata.schemaVersion {
            userInfo[routeSchemaVersionUserInfoKey] = schemaVersion
        }
        if let surfaceID = routeMetadata.surfaceID {
            userInfo[routeSurfaceIDUserInfoKey] = surfaceID
        }
        if let emittingService = routeMetadata.service {
            userInfo[ServiceNotificationRouteMetadata.servicePayloadKey] = emittingService
        }

        return userInfo
    }

    static func buildManagedNotificationUserInfo(
        service: NotificationService,
        existingUserInfo: [AnyHashable: Any]
    ) -> [AnyHashable: Any] {
        var userInfo = existingUserInfo
        userInfo[serviceManagedSoundUserInfoKey] = true

        let hasRouteMetadata =
            userInfo[routeServiceUserInfoKey] != nil ||
            userInfo[routeSchemaVersionUserInfoKey] != nil ||
            userInfo[routeSurfaceIDUserInfoKey] != nil
        if hasRouteMetadata && userInfo[routeServiceUserInfoKey] == nil {
            userInfo[routeServiceUserInfoKey] = service.rawValue
        }

        return userInfo
    }

    private static func deliverManagedNotification(_ request: ManagedNotificationRequest) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if NotificationAuthorizationStatusPolicy.allowsDelivery(settings.authorizationStatus) {
                let systemSoundEnabled = settings.soundSetting == .enabled
                let systemVisualEnabled = settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled
                Task { @MainActor in
                    managedNotificationAuthorizationState.hasRequestedDeniedAttentionRecovery = false
                    managedNotificationAuthorizationState.hasPresentedDeniedRecoveryUI = false
                    await presentManagedNotification(
                        request,
                        systemSoundEnabled: systemSoundEnabled,
                        systemVisualEnabled: systemVisualEnabled
                    )
                }
            } else if settings.authorizationStatus == .notDetermined {
                Task { @MainActor in
                    managedNotificationAuthorizationState.hasRequestedDeniedAttentionRecovery = false
                    managedNotificationAuthorizationState.hasPresentedDeniedRecoveryUI = false
                    enqueuePendingManagedNotification(request)
                    requestNotificationAuthorizationIfNeededOnMainActor()
                }
            } else if settings.authorizationStatus == .denied {
                Task { @MainActor in
                    handleDeniedManagedNotificationDelivery(settings.authorizationStatus)
                }
            }
        }
    }

    @MainActor
    private static func enqueuePendingManagedNotification(_ request: ManagedNotificationRequest) {
        let coalescingKey = ManagedNotificationQueuePolicy.coalescingKey(for: request)
        managedNotificationAuthorizationState.pendingRequests.removeAll {
            ManagedNotificationQueuePolicy.coalescingKey(for: $0) == coalescingKey
        }
        managedNotificationAuthorizationState.pendingRequests.append(request)
        let overflow =
            managedNotificationAuthorizationState.pendingRequests.count
            - ManagedNotificationQueuePolicy.maxPendingRequests
        if overflow > 0 {
            managedNotificationAuthorizationState.pendingRequests.removeFirst(overflow)
        }
    }

    @MainActor
    private static func requestNotificationAuthorizationIfNeededOnMainActor() {
        guard !managedNotificationAuthorizationState.requestInFlight else { return }
        managedNotificationAuthorizationState.requestInFlight = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                AppDelegate.logger.error("Notification auth error: \(error)")
            }

            Task { @MainActor in
                managedNotificationAuthorizationState.requestInFlight = false
                guard granted else {
                    managedNotificationAuthorizationState.pendingRequests.removeAll()
                    return
                }
                managedNotificationAuthorizationState.hasRequestedDeniedAttentionRecovery = false
                managedNotificationAuthorizationState.hasPresentedDeniedRecoveryUI = false
                replayPendingManagedNotifications()
            }
        }
    }

    @MainActor
    private static func replayPendingManagedNotifications() {
        let pendingRequests = managedNotificationAuthorizationState.pendingRequests
        managedNotificationAuthorizationState.pendingRequests.removeAll()
        for request in pendingRequests {
            deliverManagedNotification(request)
        }
    }

    @MainActor
    private static func presentManagedNotification(
        _ request: ManagedNotificationRequest,
        systemSoundEnabled: Bool,
        systemVisualEnabled: Bool
    ) async {
        let manager = NotificationSoundManager.shared
        let deliveryMode = manager.deliveryMode(for: request.service)
        if deliveryMode == .off {
            return
        }

        let modeAllowsVisual = (deliveryMode == .bannerAndSound || deliveryMode == .bannerOnly)
        let canPlaySound = systemSoundEnabled && deliveryMode.allowsSound
        let canPresentVisually = systemVisualEnabled && modeAllowsVisual
        guard canPlaySound || canPresentVisually else { return }

        let isFocused = NSApp.isActive
        let shouldPlaySound = canPlaySound && (!isFocused || manager.soundWhenFocused)
        if shouldPlaySound {
            _ = manager.resolveAndPlay(for: request.service)
        }

        guard canPresentVisually else { return }

        let content = UNMutableNotificationContent()
        content.title = request.title
        if let subtitle = request.subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = request.body
        if let categoryIdentifier = request.categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        content.userInfo = Self.buildManagedNotificationUserInfo(
            service: request.service,
            existingUserInfo: request.userInfo
        )

        let pendingRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(pendingRequest)
        } catch {
            AppDelegate.logger.error("\(request.logLabel) notification error: \(error)")
        }
    }

    static func makeNotificationRequestIdentifier(service: NotificationService) -> String {
        "yen-notification.\(service.rawValue).\(UUID().uuidString)"
    }

    static func pendingNotificationCoalescingKeyForTesting(identifier: String) -> String {
        ManagedNotificationQueuePolicy.coalescingKey(
            for: ManagedNotificationRequest(
                service: .general,
                title: "",
                subtitle: nil,
                body: "",
                identifier: identifier,
                categoryIdentifier: nil,
                userInfo: [:],
                logLabel: "test"
            )
        )
    }

    /// Returns true when the response is fully handled by service-routing logic.
    /// Returns false when legacy YEN core routing should handle the response.
    func handleServiceNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        let userInfo = response.notification.request.content.userInfo
        switch ServiceNotificationResponseRouter.decision(
            actionIdentifier: response.actionIdentifier,
            userInfo: userInfo
        ) {
        case .focusSurface(let uuid):
            guard let surface = findSurface(forUUID: uuid) else {
                applySafeNotificationResponseFallback()
                return true
            }
            focusSurfaceForNotification(surface)
            return true
        case .safeFallback:
            applySafeNotificationResponseFallback()
            return true
        case .noop:
            return true
        case .passthrough:
            return false
        }
    }

    @MainActor
    private static func handleDeniedManagedNotificationDelivery(_ authorizationStatus: UNAuthorizationStatus) {
        let action = ManagedNotificationRecoveryPolicy.action(
            authorizationStatus: authorizationStatus,
            appIsActive: NSApp.isActive,
            hasRequestedAttentionRecovery: managedNotificationAuthorizationState.hasRequestedDeniedAttentionRecovery,
            hasPresentedRecoveryUI: managedNotificationAuthorizationState.hasPresentedDeniedRecoveryUI
        )
        // .none is handled below as a no-op (was an unreachable case behind a
        // redundant early-return guard).
        switch action {
        case .none:
            break
        case .requestAttention:
            managedNotificationAuthorizationState.hasRequestedDeniedAttentionRecovery = true
            NSApp.requestUserAttention(.informationalRequest)
        case .showInAppRecovery:
            managedNotificationAuthorizationState.hasPresentedDeniedRecoveryUI = true
            let alert = NSAlert()
            alert.messageText = "Notifications Are Blocked"
            alert.informativeText =
                "YEN couldn't deliver this notification. Open Sounds settings to review notification permission and recovery actions."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Sounds")
            alert.addButton(withTitle: "Not Now")

            let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .alertFirstButtonReturn else { return }
                SettingsController.shared.showNotificationSettings()
            }

            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
                alert.beginSheetModal(for: window, completionHandler: handleResponse)
            } else {
                handleResponse(alert.runModal())
            }
        }
    }

    private func focusSurfaceForNotification(_ surface: YEN.SurfaceView) {
        NSApplication.shared.yenActivateCompat()
        // Resolve through split-tree ownership, not the view's `window`: a
        // notification can fire while AppKit is attaching or moving the surface's
        // native tab, when `window` is briefly nil or still the previous window.
        // Falling through to the else branch then focuses nothing.
        if let controller = BaseTerminalController.controller(owning: surface) {
            controller.focusSurface(surface)
        } else {
            surface.window?.makeKeyAndOrderFront(nil)
            YEN.moveFocus(to: surface)
        }
    }

    private func applySafeNotificationResponseFallback() {
        NSApplication.shared.yenActivateCompat()

        if let window = preferredNotificationFallbackWindow() {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func preferredNotificationFallbackWindow() -> NSWindow? {
        let keyWindow = NSApp.keyWindow
        let mainWindow = NSApp.mainWindow
        let preferredTerminalWindow = TerminalController.preferredParent?.window
        let quickTerminalWindow = existingQuickTerminalController?.window

        switch NotificationFallbackWindowPolicy.target(
            keyWindowIsTerminalHost: Self.isTerminalHostWindow(keyWindow),
            mainWindowIsTerminalHost: Self.isTerminalHostWindow(mainWindow),
            hasPreferredTerminalWindow: preferredTerminalWindow != nil,
            hasQuickTerminalWindow: quickTerminalWindow != nil
        ) {
        case .keyTerminal:
            return keyWindow
        case .mainTerminal:
            return mainWindow
        case .preferredTerminal:
            return preferredTerminalWindow
        case .quickTerminal:
            return quickTerminalWindow
        case .none:
            return nil
        }
    }

    private static func isTerminalHostWindow(_ window: NSWindow?) -> Bool {
        guard let controller = window?.windowController else { return false }
        return controller is BaseTerminalController || controller is QuickTerminalController
    }
}
#endif // os(macOS)
