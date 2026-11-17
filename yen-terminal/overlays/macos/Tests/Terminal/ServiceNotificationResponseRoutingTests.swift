import Foundation
import Testing
import UserNotifications
@testable import YEN

struct ServiceNotificationResponseRoutingTests {
    private let routeUUIDString = "11111111-1111-1111-1111-111111111111"

    @Test func routeSurfaceUUIDParsesValidUUID() {
        let userInfo: [AnyHashable: Any] = [
            AppDelegate.routeSurfaceIDUserInfoKey: routeUUIDString,
        ]
        #expect(ServiceNotificationResponseRouter.routeSurfaceUUID(from: userInfo)?.uuidString == routeUUIDString)
    }

    @Test func routeSurfaceUUIDRejectsInvalidUUID() {
        let userInfo: [AnyHashable: Any] = [
            AppDelegate.routeSurfaceIDUserInfoKey: "not-a-uuid",
        ]
        #expect(ServiceNotificationResponseRouter.routeSurfaceUUID(from: userInfo) == nil)
    }

    @Test func serviceManagedRouteDetectionRequiresRouteKeys() {
        #expect(!ServiceNotificationResponseRouter.isServiceManagedRoute([:]))
        #expect(
            ServiceNotificationResponseRouter.isServiceManagedRoute([
                AppDelegate.routeServiceUserInfoKey: NotificationService.build.rawValue,
            ])
        )
        #expect(
            !ServiceNotificationResponseRouter.isServiceManagedRoute([
                AppDelegate.serviceManagedSoundUserInfoKey: true,
            ])
        )
    }

    @Test func decisionUsesPassthroughForNonServiceNotifications() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [:]
        )
        #expect(decision == .passthrough)
    }

    @Test func decisionFocusesExactSurfaceForDefaultAction() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: NotificationService.build.rawValue,
                AppDelegate.routeSurfaceIDUserInfoKey: routeUUIDString,
            ]
        )
        #expect(decision == .focusSurface(UUID(uuidString: routeUUIDString)!))
    }

    @Test func decisionFocusesExactSurfaceForShowAction() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: YEN.userNotificationActionShow,
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: NotificationService.build.rawValue,
                AppDelegate.routeSurfaceIDUserInfoKey: routeUUIDString,
            ]
        )
        #expect(decision == .focusSurface(UUID(uuidString: routeUUIDString)!))
    }

    @Test func decisionUsesSafeFallbackWhenRouteMissing() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: "build",
            ]
        )
        #expect(decision == .safeFallback)
    }

    @Test func decisionUsesPassthroughWhenManagedMarkerExistsWithoutRoute() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                AppDelegate.serviceManagedSoundUserInfoKey: true,
            ]
        )
        #expect(decision == .passthrough)
    }

    @Test func decisionDismissActionWithRouteIsNoop() {
        // Dismiss is a no-op route (the looked-up-then-discarded dismissSurface scaffolding
        // was removed); a service-managed dismiss is handled without taking any action.
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: "build",
                AppDelegate.routeSurfaceIDUserInfoKey: routeUUIDString,
            ]
        )
        #expect(decision == .noop)
    }

    @Test func decisionDismissWithoutRouteIsNoop() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: NotificationService.build.rawValue,
            ]
        )
        #expect(decision == .noop)
    }

    @Test func decisionUnknownActionIsNoop() {
        let decision = ServiceNotificationResponseRouter.decision(
            actionIdentifier: "custom-action",
            userInfo: [
                AppDelegate.routeServiceUserInfoKey: "build",
                AppDelegate.routeSurfaceIDUserInfoKey: routeUUIDString,
            ]
        )
        #expect(decision == .noop)
    }
}
