import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsAppearanceControlsTests {
    @Test func scrollbarNormalizesProgrammaticAndRawConfigValuesToSupportedTokens() {
        TestExclusiveLock.withLock(named: "settings-appearance-controls") {
            let controller = SettingsController.shared
            let originalScrollbarVisibility = controller.scrollbarVisibility

            defer {
                controller.scrollbarVisibility = originalScrollbarVisibility
            }

            controller.scrollbarVisibility = " NEVER "
            #expect(controller.scrollbarVisibility == "never")

            controller.scrollbarVisibility = "overlay"
            #expect(controller.scrollbarVisibility == "system")

            controller.applyConfigContentsForTesting(
                """
                scrollbar = LEGACY
                """
            )
            #expect(controller.scrollbarVisibility == "system")

            controller.applyConfigContentsForTesting(
                """
                scrollbar = NEVER
                """
            )
            #expect(controller.scrollbarVisibility == "never")
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "scrollbar" && value == "never"
                }
            )
        }
    }

    @Test func backgroundOpacityNormalizesImportedAndProgrammaticValuesToSliderSteps() {
        TestExclusiveLock.withLock(named: "settings-appearance-controls") {
            let controller = SettingsController.shared
            let originalBackgroundOpacity = controller.backgroundOpacity

            defer {
                controller.backgroundOpacity = originalBackgroundOpacity
            }

            controller.applyConfigContentsForTesting(
                """
                background-opacity = 0.625
                """
            )
            #expect(controller.backgroundOpacity == 0.65)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "background-opacity" && value == "0.65"
                }
            )

            controller.backgroundOpacity = 0.104
            #expect(controller.backgroundOpacity == 0.1)

            controller.backgroundOpacity = 0.876
            #expect(controller.backgroundOpacity == 0.9)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "background-opacity" && value == "0.90"
                }
            )
        }
    }
}
