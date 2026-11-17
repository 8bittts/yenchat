import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsTypographyControlsTests {
    @Test func importedFontFamilyRefreshesPickerCatalogToKeepCurrentSelectionVisible() {
        TestExclusiveLock.withLock(named: "settings-typography") {
            let controller = SettingsController.shared
            let originalFontFamily = controller.fontFamily
            let originalFontSize = controller.fontSize
            let originalAvailableFonts = controller.availableFonts

            defer {
                controller.fontFamily = originalFontFamily
                controller.fontSize = originalFontSize
                controller.availableFonts = originalAvailableFonts
                SettingsController._testSetCachedMonospaceFonts(nil)
            }

            SettingsController._testSetCachedMonospaceFonts(["Menlo", "SF Mono"])
            controller.availableFonts = ["Menlo", "SF Mono"]

            controller.applyConfigContentsForTesting(
                """
                font-family = Custom Mono
                font-size = 14
                """
            )

            #expect(controller.fontFamily == "Custom Mono")
            #expect(controller.availableFonts == ["Custom Mono", "Menlo", "SF Mono"])

            controller.applyConfigContentsForTesting(
                """
                font-family = Menlo
                font-size = 14
                """
            )

            #expect(controller.fontFamily == "Menlo")
            #expect(controller.availableFonts == ["Menlo", "SF Mono"])
        }
    }

    @Test func fontSizeNormalizesImportedAndProgrammaticValuesToWholePointSteps() {
        TestExclusiveLock.withLock(named: "settings-typography") {
            let controller = SettingsController.shared
            let originalFontSize = controller.fontSize

            defer {
                controller.fontSize = originalFontSize
            }

            controller.applyConfigContentsForTesting(
                """
                font-size = 12.5
                """
            )

            #expect(controller.fontSize == 13)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "font-size" && value == "13"
                }
            )

            controller.fontSize = 17.5

            #expect(controller.fontSize == 18)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "font-size" && value == "18"
                }
            )
        }
    }
}
