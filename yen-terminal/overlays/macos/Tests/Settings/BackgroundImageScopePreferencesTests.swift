import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct BackgroundImageScopePreferencesTests {
    @Test func backgroundImageScopeDefaultsAreRegisteredAndReadable() {
        withIsolatedBackgroundImageScopePreferences {
            BackgroundImageScopePreferences.registerDefaults()

            #expect(
                UserDefaults.standard.string(forKey: BackgroundImageScopePreferences.preferenceKey)
                    == BackgroundImageScopePreferences.defaultScope.rawValue
            )
            #expect(
                BackgroundImageScopePreferences.scope()
                    == BackgroundImageScopePreferences.defaultScope
            )
        }
    }

    @Test func backgroundImageScopeNormalizesInvalidStoredValues() {
        withIsolatedBackgroundImageScopePreferences {
            UserDefaults.standard.set(
                "not-a-scope",
                forKey: BackgroundImageScopePreferences.preferenceKey
            )

            #expect(
                BackgroundImageScopePreferences.scope()
                    == BackgroundImageScopePreferences.defaultScope
            )
        }
    }

    @Test func backgroundImageScopeControllerLoadsAndPersistsPreference() {
        withIsolatedBackgroundImageScopePreferences {
            let defaults = UserDefaults.standard
            defaults.set(
                BackgroundImageScope.wholeWindow.rawValue,
                forKey: BackgroundImageScopePreferences.preferenceKey
            )

            let controller = SettingsController.shared
            controller.loadWorkspacePreferences()
            #expect(controller.backgroundImageScope == .wholeWindow)

            controller.backgroundImageScope = .eachSplit
            #expect(
                defaults.string(forKey: BackgroundImageScopePreferences.preferenceKey)
                    == BackgroundImageScope.eachSplit.rawValue
            )
        }
    }

    private func withIsolatedBackgroundImageScopePreferences(_ operation: () throws -> Void) rethrows {
        try TestExclusiveLock.withLock(named: "workspace-preferences") {
            let defaults = UserDefaults.standard
            let key = BackgroundImageScopePreferences.preferenceKey
            let controller = SettingsController.shared
            let originalValue = defaults.object(forKey: key)
            let originalScope = controller.backgroundImageScope
            defaults.removeObject(forKey: key)

            defer {
                controller.backgroundImageScope = originalScope
                defaults.removeObject(forKey: key)
                if let originalValue {
                    defaults.set(originalValue, forKey: key)
                }
            }
            try operation()
        }
    }
}
