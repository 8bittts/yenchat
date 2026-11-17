import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsCursorControlsTests {
    @Test func cursorStyleNormalizesProgrammaticAndImportedValuesToSupportedTokens() {
        TestExclusiveLock.withLock(named: "settings-cursor-controls") {
            let controller = SettingsController.shared
            let originalCursorStyle = controller.cursorStyle
            let originalCursorBlink = controller.cursorBlink

            defer {
                controller.cursorStyle = originalCursorStyle
                controller.cursorBlink = originalCursorBlink
            }

            controller.cursorStyle = " UnderLine "
            #expect(controller.cursorStyle == "underline")

            controller.cursorStyle = "beam"
            #expect(controller.cursorStyle == "block")

            controller.applyConfigContentsForTesting(
                """
                cursor-style = BAR
                cursor-style-blink = true
                """
            )

            #expect(controller.cursorStyle == "bar")
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "cursor-style" && value == "bar"
                }
            )
        }
    }

    @Test func cursorBlinkDefaultsInvalidRawConfigToEnabled() {
        TestExclusiveLock.withLock(named: "settings-cursor-controls") {
            let controller = SettingsController.shared
            let originalCursorStyle = controller.cursorStyle
            let originalCursorBlink = controller.cursorBlink

            defer {
                controller.cursorStyle = originalCursorStyle
                controller.cursorBlink = originalCursorBlink
            }

            controller.cursorBlink = false
            controller.applyConfigContentsForTesting(
                """
                cursor-style = block
                cursor-style-blink = maybe
                """
            )

            #expect(controller.cursorBlink)

            controller.applyConfigContentsForTesting(
                """
                cursor-style = block
                cursor-style-blink = FALSE
                """
            )

            #expect(!controller.cursorBlink)
            #expect(
                controller.managedSettingsListForTesting().contains { key, value in
                    key == "cursor-style-blink" && value == "false"
                }
            )
        }
    }
}
