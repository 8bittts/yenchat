import Foundation
import Testing
import UserNotifications
@testable import YEN

struct ServiceNotificationPayloadTests {
    @Test func decodeLegacyPayloadWithoutMetadata() {
        let notification = Notification(
            name: Notification.Name("com.yenchat.yen.test"),
            object: "YEN Build\nzip finished"
        )

        let envelope = ServiceNotificationEnvelope.decode(
            from: notification,
            fallbackTitle: "YEN Terminal"
        )

        #expect(envelope?.title == "YEN Build")
        #expect(envelope?.body == "zip finished")
        #expect(envelope?.routeMetadata.schemaVersion == nil)
        #expect(envelope?.routeMetadata.service == nil)
        #expect(envelope?.routeMetadata.surfaceID == nil)
    }

    @Test func decodePayloadUsesFallbackTitleForEmptyTitle() {
        let notification = Notification(
            name: Notification.Name("com.yenchat.yen.test"),
            object: "\nBody only"
        )

        let envelope = ServiceNotificationEnvelope.decode(
            from: notification,
            fallbackTitle: "YEN Terminal"
        )

        #expect(envelope?.title == "YEN Terminal")
        #expect(envelope?.body == "Body only")
    }

    @Test func decodePayloadNormalizesRouteMetadataAndDropsInvalidSurfaceID() {
        let notification = Notification(
            name: Notification.Name("com.yenchat.yen.test"),
            object: "YEN Build\nzip finished",
            userInfo: [
                "schema_version": "1",
                "service": "build",
                "surface_id": "not-a-uuid",
            ]
        )

        let envelope = ServiceNotificationEnvelope.decode(
            from: notification,
            fallbackTitle: "YEN Terminal"
        )

        #expect(envelope?.routeMetadata.schemaVersion == "1")
        #expect(envelope?.routeMetadata.service == "build")
        #expect(envelope?.routeMetadata.surfaceID == nil)
    }

    @Test func buildServiceNotificationUserInfoAddsPropertyListSafeRouteKeys() {
        let metadata = ServiceNotificationRouteMetadata(
            schemaVersion: "1",
            service: "build",
            surfaceID: "11111111-1111-1111-1111-111111111111"
        )

        let userInfo = AppDelegate.buildServiceNotificationUserInfo(
            resolvedService: .build,
            routeMetadata: metadata
        )

        #expect(userInfo[AppDelegate.serviceManagedSoundUserInfoKey] as? Bool == true)
        #expect(userInfo[AppDelegate.routeServiceUserInfoKey] as? String == NotificationService.build.rawValue)
        #expect(userInfo[AppDelegate.routeSchemaVersionUserInfoKey] as? String == "1")
        #expect(userInfo[AppDelegate.routeSurfaceIDUserInfoKey] as? String == "11111111-1111-1111-1111-111111111111")
        #expect(userInfo[ServiceNotificationRouteMetadata.servicePayloadKey] as? String == "build")
    }

    @Test func buildManagedNotificationUserInfoDoesNotInventRouteKeysForLocalNotifications() {
        let userInfo = AppDelegate.buildManagedNotificationUserInfo(
            service: .general,
            existingUserInfo: [:]
        )

        #expect(userInfo[AppDelegate.serviceManagedSoundUserInfoKey] as? Bool == true)
        #expect(userInfo[AppDelegate.routeServiceUserInfoKey] == nil)
        #expect(userInfo[AppDelegate.routeSchemaVersionUserInfoKey] == nil)
        #expect(userInfo[AppDelegate.routeSurfaceIDUserInfoKey] == nil)
    }

    @Test func buildManagedNotificationUserInfoBackfillsRouteServiceWhenRouteMetadataExists() {
        let userInfo = AppDelegate.buildManagedNotificationUserInfo(
            service: .build,
            existingUserInfo: [
                AppDelegate.routeSurfaceIDUserInfoKey: "11111111-1111-1111-1111-111111111111",
            ]
        )

        #expect(userInfo[AppDelegate.serviceManagedSoundUserInfoKey] as? Bool == true)
        #expect(userInfo[AppDelegate.routeServiceUserInfoKey] as? String == NotificationService.build.rawValue)
        #expect(userInfo[AppDelegate.routeSurfaceIDUserInfoKey] as? String == "11111111-1111-1111-1111-111111111111")
    }

    @Test func buildManagedSurfaceNotificationUserInfoCarriesRouteAndLegacyFocusKeys() {
        let surfaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userInfo = AppDelegate.buildManagedSurfaceNotificationUserInfo(
            surfaceID: surfaceID,
            requireFocus: false
        )

        #expect(userInfo[AppDelegate.routeSurfaceIDUserInfoKey] as? String == surfaceID.uuidString)
        #expect(userInfo[AppDelegate.legacySurfaceIDUserInfoKey] as? String == surfaceID.uuidString)
        #expect(userInfo[AppDelegate.legacyRequireFocusUserInfoKey] as? Bool == false)
    }

    @Test func presentationPolicyForServiceManagedNotificationSuppressesSound() {
        let adjusted = ServiceNotificationPresentationPolicy.adjustedForegroundOptions(
            [.sound],
            isServiceManaged: true,
            showBannerWhenFocused: false
        )

        #expect(adjusted.contains(.sound) == false)
        #expect(adjusted.contains(.banner) == false)
    }

    @Test func presentationPolicyCanForceBannerWhenFocused() {
        let adjusted = ServiceNotificationPresentationPolicy.adjustedForegroundOptions(
            [],
            isServiceManaged: true,
            showBannerWhenFocused: true
        )

        #expect(adjusted.contains(.sound) == false)
        #expect(adjusted.contains(.banner))
    }

    @Test func notificationAuthorizationStatusPolicyMapsKeyStates() {
        #expect(NotificationAuthorizationStatusPolicy.allowsDelivery(.authorized))
        #expect(NotificationAuthorizationStatusPolicy.allowsDelivery(.provisional))
        #expect(!NotificationAuthorizationStatusPolicy.allowsDelivery(.notDetermined))
        #expect(!NotificationAuthorizationStatusPolicy.allowsDelivery(.denied))
        #expect(NotificationAuthorizationStatusPolicy.statusLabel(for: .denied) == "Blocked")
        #expect(NotificationAuthorizationStatusPolicy.actionTitle(for: .notDetermined) == "Grant")
        #expect(NotificationAuthorizationStatusPolicy.actionTitle(for: .authorized) == "Open Settings")
        #expect(NotificationAuthorizationStatusPolicy.actionHint(for: .notDetermined) == "Requests notification permission")
        #expect(NotificationAuthorizationStatusPolicy.actionHint(for: .denied) == "Opens notification settings")
    }

    @Test func notificationSettingsDestinationIncludesModernAndLegacyCandidates() {
        let candidates = NotificationSettingsDestination.notifications.urlCandidates

        #expect(candidates.first == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #expect(candidates.contains("x-apple.systempreferences:com.apple.preference.notifications"))
    }

    @Test func pendingNotificationCoalescingKeyStripsTrailingUUID() {
        let key = AppDelegate.pendingNotificationCoalescingKeyForTesting(
            identifier: "yen-notification.build.11111111-1111-1111-1111-111111111111"
        )

        #expect(key == "yen-notification.build")
    }

    @Test func pendingNotificationCoalescingKeyPreservesStableIdentifiers() {
        let key = AppDelegate.pendingNotificationCoalescingKeyForTesting(
            identifier: "com.yenchat.yen.build.completed"
        )

        #expect(key == "com.yenchat.yen.build.completed")
    }

    @Test func bellNotificationPolicySuppressesAttentionForActiveAppAndRespectsAuthorization() {
        let decision = BellNotificationPolicy.decision(
            attentionEnabled: true,
            appIsActive: true,
            authorizationStatus: .denied,
            soundSetting: .enabled,
            badgeSetting: .enabled,
            deliveryMode: .bannerAndSound,
            soundWhenFocused: true
        )

        #expect(!decision.requestAttention)
        #expect(!decision.playSound)
        #expect(!decision.setDockBadge)
    }

    @Test func bellNotificationPolicyAllowsBackgroundSoundAndBadgeWhenAuthorized() {
        let decision = BellNotificationPolicy.decision(
            attentionEnabled: true,
            appIsActive: false,
            authorizationStatus: .authorized,
            soundSetting: .enabled,
            badgeSetting: .enabled,
            deliveryMode: .soundOnly,
            soundWhenFocused: false
        )

        #expect(decision.requestAttention)
        #expect(decision.playSound)
        #expect(decision.setDockBadge)
    }

    @Test func managedNotificationRecoveryPolicyShowsUiOnlyOncePerDeniedState() {
        #expect(
            ManagedNotificationRecoveryPolicy.action(
                authorizationStatus: .denied,
                appIsActive: true,
                hasRequestedAttentionRecovery: false,
                hasPresentedRecoveryUI: false
            ) == .showInAppRecovery
        )
        #expect(
            ManagedNotificationRecoveryPolicy.action(
                authorizationStatus: .denied,
                appIsActive: false,
                hasRequestedAttentionRecovery: false,
                hasPresentedRecoveryUI: false
            ) == .requestAttention
        )
        #expect(
            ManagedNotificationRecoveryPolicy.action(
                authorizationStatus: .denied,
                appIsActive: true,
                hasRequestedAttentionRecovery: true,
                hasPresentedRecoveryUI: true
            ) == .none
        )
        #expect(
            ManagedNotificationRecoveryPolicy.action(
                authorizationStatus: .denied,
                appIsActive: true,
                hasRequestedAttentionRecovery: true,
                hasPresentedRecoveryUI: false
            ) == .showInAppRecovery
        )
    }

    @Test func notificationFallbackWindowPolicyPrefersFocusedTerminalHosts() {
        #expect(
            NotificationFallbackWindowPolicy.target(
                keyWindowIsTerminalHost: true,
                mainWindowIsTerminalHost: true,
                hasPreferredTerminalWindow: true,
                hasQuickTerminalWindow: true
            ) == .keyTerminal
        )
        #expect(
            NotificationFallbackWindowPolicy.target(
                keyWindowIsTerminalHost: false,
                mainWindowIsTerminalHost: true,
                hasPreferredTerminalWindow: true,
                hasQuickTerminalWindow: true
            ) == .mainTerminal
        )
    }

    @Test func notificationFallbackWindowPolicySkipsNonTerminalWindows() {
        #expect(
            NotificationFallbackWindowPolicy.target(
                keyWindowIsTerminalHost: false,
                mainWindowIsTerminalHost: false,
                hasPreferredTerminalWindow: true,
                hasQuickTerminalWindow: true
            ) == .preferredTerminal
        )
        #expect(
            NotificationFallbackWindowPolicy.target(
                keyWindowIsTerminalHost: false,
                mainWindowIsTerminalHost: false,
                hasPreferredTerminalWindow: false,
                hasQuickTerminalWindow: true
            ) == .quickTerminal
        )
        #expect(
            NotificationFallbackWindowPolicy.target(
                keyWindowIsTerminalHost: false,
                mainWindowIsTerminalHost: false,
                hasPreferredTerminalWindow: false,
                hasQuickTerminalWindow: false
            ) == .none
        )
    }
}
