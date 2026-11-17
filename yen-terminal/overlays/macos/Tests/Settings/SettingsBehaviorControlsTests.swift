import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsBehaviorControlsTests {
    @Test func copyOnSelectNormalizesRawConfigValuesToSupportedToggleStates() {
        TestExclusiveLock.withLock(named: "settings-behavior-controls") {
            let controller = SettingsController.shared
            let originalCopyOnSelect = controller.copyOnSelect

            defer {
                controller.copyOnSelect = originalCopyOnSelect
            }

            controller.copyOnSelect = true
            controller.applyConfigContentsForTesting(
                """
                copy-on-select = FALSE
                """
            )

            #expect(!controller.copyOnSelect)

            controller.applyConfigContentsForTesting(
                """
                copy-on-select = clipboard
                """
            )

            #expect(controller.copyOnSelect)

            controller.copyOnSelect = false
            controller.applyConfigContentsForTesting(
                """
                copy-on-select = invalid
                """
            )

            #expect(!controller.copyOnSelect)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "copy-on-select" && value == "false"
                }
            )
        }
    }
}
