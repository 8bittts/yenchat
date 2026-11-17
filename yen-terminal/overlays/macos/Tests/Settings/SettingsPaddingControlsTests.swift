import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsPaddingControlsTests {
    @Test func windowPaddingNormalizesProgrammaticAndImportedValuesToSupportedRange() {
        TestExclusiveLock.withLock(named: "settings-padding-controls") {
            let controller = SettingsController.shared
            let originalWindowPaddingX = controller.windowPaddingX
            let originalWindowPaddingY = controller.windowPaddingY

            defer {
                controller.windowPaddingX = originalWindowPaddingX
                controller.windowPaddingY = originalWindowPaddingY
            }

            controller.windowPaddingX = -4
            #expect(controller.windowPaddingX == 0)

            controller.windowPaddingY = 72
            #expect(controller.windowPaddingY == 50)

            controller.applyConfigContentsForTesting(
                """
                window-padding-x = -3
                window-padding-y = 999
                """
            )

            #expect(controller.windowPaddingX == 0)
            #expect(controller.windowPaddingY == 50)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "window-padding-x" && value == "0"
                }
            )
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "window-padding-y" && value == "50"
                }
            )
        }
    }

    @Test func windowPaddingDefaultsInvalidRawConfigToBaseline() {
        TestExclusiveLock.withLock(named: "settings-padding-controls") {
            let controller = SettingsController.shared
            let originalWindowPaddingX = controller.windowPaddingX
            let originalWindowPaddingY = controller.windowPaddingY

            defer {
                controller.windowPaddingX = originalWindowPaddingX
                controller.windowPaddingY = originalWindowPaddingY
            }

            controller.applyConfigContentsForTesting(
                """
                window-padding-x = nope
                window-padding-y = ??? 
                """
            )

            #expect(controller.windowPaddingX == 2)
            #expect(controller.windowPaddingY == 2)
        }
    }
}
