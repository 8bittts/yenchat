import Foundation
import Testing
@testable import YEN

struct SurfaceRouteEnvironmentTests {
    @Test func routeEnvironmentKeyIsStable() {
        #expect(YEN.SurfaceConfiguration.surfaceRouteEnvironmentKey == "YEN_SURFACE_ID")
    }

    @Test func settingRouteEnvironmentIDAddsRouteWhenMissingAndPreservesOtherEnvironmentValues() {
        let routeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        var config = YEN.SurfaceConfiguration()
        config.environmentVariables = [
            "TERM": "xterm-256color",
            "LANG": "en_US.UTF-8",
        ]

        config.setRouteEnvironmentID(routeID)

        #expect(config.environmentVariables["TERM"] == "xterm-256color")
        #expect(config.environmentVariables["LANG"] == "en_US.UTF-8")
        #expect(config.environmentVariables[YEN.SurfaceConfiguration.surfaceRouteEnvironmentKey] == routeID.uuidString)
        #expect(config.environmentVariables.count == 3)
    }

    @Test func settingRouteEnvironmentIDPreservesInheritedRouteWhenAlreadyPresent() {
        let inheritedRouteID = "inherited-route-id"
        let attemptedRouteID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        var config = YEN.SurfaceConfiguration()
        config.environmentVariables = [
            "TERM": "xterm-256color",
            YEN.SurfaceConfiguration.surfaceRouteEnvironmentKey: inheritedRouteID,
        ]

        config.setRouteEnvironmentID(attemptedRouteID)

        #expect(config.environmentVariables["TERM"] == "xterm-256color")
        #expect(config.environmentVariables[YEN.SurfaceConfiguration.surfaceRouteEnvironmentKey] == inheritedRouteID)
        #expect(config.environmentVariables.count == 2)
    }
}
