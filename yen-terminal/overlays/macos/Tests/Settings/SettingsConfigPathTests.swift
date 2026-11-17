import Foundation
import Testing
@testable import YEN

struct SettingsConfigPathTests {
    @Test func configPathHonorsEnvironmentOverride() {
        let resolved = SettingsController.resolveConfigPath(
            environment: ["YEN_CONFIG_PATH": "/tmp/yen-tests/config.yen"],
            homeDirectory: "/Users/test"
        )
        #expect(resolved == "/tmp/yen-tests/config.yen")
    }

    @Test func configPathFallsBackToApplicationSupport() {
        let resolved = SettingsController.resolveConfigPath(
            environment: [:],
            homeDirectory: "/Users/test"
        )
        #expect(resolved == "/Users/test/Library/Application Support/com.yenchat.yen/config.yen")
    }

    @Test func blankEnvironmentOverrideIsIgnored() {
        let resolved = SettingsController.resolveConfigPath(
            environment: ["YEN_CONFIG_PATH": "  \n"],
            homeDirectory: "/Users/test"
        )
        #expect(resolved == "/Users/test/Library/Application Support/com.yenchat.yen/config.yen")
    }

    // The test host must never resolve to the operator's real config.yen: with no
    // visible Settings window every managed-property mutation persists synchronously,
    // and running this suite on a release build once reset the operator's padding.
    @Test func testHostNeverTargetsRealUserConfig() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let realUserConfig = "\(home)/Library/Application Support/com.yenchat.yen/config.yen"

        #expect(environment["YEN_CONFIG_PATH"]?.isEmpty == false)
        #expect(
            SettingsController.resolveConfigPath(environment: environment, homeDirectory: home)
                != realUserConfig
        )
    }
}
