import Foundation
import Testing
@testable import YEN

@MainActor
struct DictationTranslationPreferencesTests {
    @Test func translationPreferencesPersistAndNormalizeValues() {
        withIsolatedTranslationPreferences {
            DictationTranslationPreferences.translateOnDictateEnabled = true
            #expect(DictationTranslationPreferences.translateOnDictateEnabled == true)

            DictationTranslationPreferences.translateOnDictateEnabled = false
            #expect(DictationTranslationPreferences.translateOnDictateEnabled == false)

            let normalizedTarget = DictationTranslationPreferences.normalizeLanguageIdentifier("  es-MX ")
            DictationTranslationPreferences.targetLanguageIdentifier = "  es-MX "
            #expect(DictationTranslationPreferences.targetLanguageIdentifier == normalizedTarget)
            #expect(
                UserDefaults.standard.string(
                    forKey: DictationTranslationPreferences.targetLanguagePreferenceKey
                ) == normalizedTarget
            )

            UserDefaults.standard.set("   ", forKey: DictationTranslationPreferences.targetLanguagePreferenceKey)
            let fallback = DictationTranslationPreferences.targetLanguageIdentifier
            #expect(!fallback.isEmpty)
            #expect(fallback == DictationTranslationPreferences.normalizeLanguageIdentifier(nil))
        }
    }

    @Test func validatedTargetIdentifierPrefersLanguageCodeMatches() {
        let currentLanguageMatch = DictationTranslationPreferences.validatedTargetIdentifier(
            currentIdentifier: "es-MX",
            supportedIdentifiers: ["en-US", "es-ES", "fr-FR"],
            preferredIdentifier: "en-US"
        )
        #expect(currentLanguageMatch == "es-ES")

        let preferredLanguageMatch = DictationTranslationPreferences.validatedTargetIdentifier(
            currentIdentifier: "pt-BR",
            supportedIdentifiers: ["en-US", "fr-CA"],
            preferredIdentifier: "fr-FR"
        )
        #expect(preferredLanguageMatch == "fr-CA")
    }

    @Test func sameLanguageComparisonIsScriptAware() {
        #expect(DictationTranslationPreferences.isSameLanguage("en-US", "en-GB") == true)
        #expect(DictationTranslationPreferences.isSameLanguage("zh-Hans", "zh-Hant") == false)
    }

    @Test func validatedTargetIdentifierPrefersScriptCompatibleMatches() {
        let validated = DictationTranslationPreferences.validatedTargetIdentifier(
            currentIdentifier: "zh-Hans-CN",
            supportedIdentifiers: ["zh-Hant", "zh-Hans"],
            preferredIdentifier: "zh-Hant"
        )
        #expect(validated == "zh-Hans")
    }

    @Test func languageCatalogFiltersUnsupportedAndEquivalentTargets() async {
        let options = await DictationTranslationLanguageCatalog.compatibleLanguageOptions(
            sourceLocaleIdentifier: "en-US",
            supportedLanguageIdentifiers: ["en-GB", "es-ES", "fr-FR", "de-DE", "   "]
        ) { _, target in
            let normalizedTarget = DictationTranslationPreferences.normalizeLanguageIdentifier(
                target.minimalIdentifier
            )
            switch normalizedTarget {
            case DictationTranslationPreferences.normalizeLanguageIdentifier("es-ES"):
                return .supported
            case DictationTranslationPreferences.normalizeLanguageIdentifier("fr-FR"):
                return .installed
            case DictationTranslationPreferences.normalizeLanguageIdentifier("de-DE"):
                return .unsupported
            default:
                return .installed
            }
        }

        #expect(Set(options.map(\.identifier)) == Set(["es", "fr"]))
    }

    @Test func dictationPreviewPreferencePersistsLiveTranscriptToggle() {
        withIsolatedDictationPreviewPreferences {
            DictationPreviewPreferences.liveTranscriptEnabled = true
            #expect(DictationPreviewPreferences.liveTranscriptEnabled == true)
            #expect(
                UserDefaults.standard.bool(
                    forKey: DictationPreviewPreferences.liveTranscriptEnabledPreferenceKey
                ) == true
            )

            DictationPreviewPreferences.liveTranscriptEnabled = false
            #expect(DictationPreviewPreferences.liveTranscriptEnabled == false)
        }
    }

    private func withIsolatedTranslationPreferences(_ operation: () -> Void) {
        let defaults = UserDefaults.standard
        let originalEnabled = defaults.object(
            forKey: DictationTranslationPreferences.enabledPreferenceKey
        )
        let originalTarget = defaults.object(
            forKey: DictationTranslationPreferences.targetLanguagePreferenceKey
        )

        defer {
            defaults.removeObject(forKey: DictationTranslationPreferences.enabledPreferenceKey)
            defaults.removeObject(forKey: DictationTranslationPreferences.targetLanguagePreferenceKey)

            if let originalEnabled {
                defaults.set(
                    originalEnabled,
                    forKey: DictationTranslationPreferences.enabledPreferenceKey
                )
            }
            if let originalTarget {
                defaults.set(
                    originalTarget,
                    forKey: DictationTranslationPreferences.targetLanguagePreferenceKey
                )
            }
        }

        defaults.removeObject(forKey: DictationTranslationPreferences.enabledPreferenceKey)
        defaults.removeObject(forKey: DictationTranslationPreferences.targetLanguagePreferenceKey)
        operation()
    }

    private func withIsolatedDictationPreviewPreferences(_ operation: () -> Void) {
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(
            forKey: DictationPreviewPreferences.liveTranscriptEnabledPreferenceKey
        )

        defer {
            defaults.removeObject(forKey: DictationPreviewPreferences.liveTranscriptEnabledPreferenceKey)
            if let originalValue {
                defaults.set(
                    originalValue,
                    forKey: DictationPreviewPreferences.liveTranscriptEnabledPreferenceKey
                )
            }
        }

        defaults.removeObject(forKey: DictationPreviewPreferences.liveTranscriptEnabledPreferenceKey)
        operation()
    }
}
