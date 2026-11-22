import Testing
@testable import YEN

@MainActor
struct SettingsDictationControlsTests {
    @Test func loginApprovalCopySaysWhatIsBlockedAndWhereToAllowIt() {
        #expect(
            SettingsGeneralPane.loginApprovalText
                == "Waiting for approval. YEN will not open at login until you allow it in Login Items."
        )
    }

    @Test func translationFallbackStateUsesExplicitUnavailableCopy() {
        #expect(
            SettingsPanel.translationTargetFallbackLabelForTesting(
                translationSupportedOnThisMac: true,
                availableTargetLanguages: []
            ) == "No compatible languages"
        )
        #expect(
            SettingsPanel.translationTargetFallbackLabelForTesting(
                translationSupportedOnThisMac: true,
                availableTargetLanguages: [
                    DictationTranslationLanguageOption(identifier: "fr", displayName: "French")
                ]
            ) == nil
        )
        // The row is hidden while translation is off, so there is nothing to explain.
        #expect(
            SettingsPanel.translationDetailTextsForTesting(
                translationSupportedOnThisMac: true,
                translateOnDictateEnabled: false,
                availableTargetLanguages: []
            ).isEmpty
        )
        #expect(
            SettingsPanel.translationDetailTextsForTesting(
                translationSupportedOnThisMac: true,
                translateOnDictateEnabled: true,
                availableTargetLanguages: []
            ) == [
                "No languages are available for your dictation language.",
                "If translation fails or times out, YEN types what you said."
            ]
        )
        #expect(
            SettingsPanel.translationDetailTextsForTesting(
                translationSupportedOnThisMac: true,
                translateOnDictateEnabled: true,
                availableTargetLanguages: [
                    DictationTranslationLanguageOption(identifier: "fr", displayName: "French")
                ]
            ) == [
                "If translation fails or times out, YEN types what you said."
            ]
        )
        #expect(
            SettingsPanel.translationDetailTextsForTesting(
                translationSupportedOnThisMac: false,
                translateOnDictateEnabled: true,
                availableTargetLanguages: []
            ) == ["Translation is unavailable on this Mac."]
        )
    }

    @Test func dictationPermissionsFooterNeverClaimsSpeechAlwaysStaysOnThisMac() {
        // On-device recognition is the normal path, and the legacy recognizer can
        // use Apple's service when it is unavailable, so the copy states a condition.
        #expect(SettingsDictationPane.permissionsFooter.contains("when on-device recognition is available"))
        #expect(SettingsDictationPane.permissionsFooter.hasPrefix("Hold ⌥Space to dictate."))
    }
}
