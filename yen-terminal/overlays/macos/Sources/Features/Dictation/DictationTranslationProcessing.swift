import Cocoa
#if canImport(Translation)
import Translation
#endif

enum DictationTranslationRuntime {
    static func supportsInstalledTranslationSession() -> Bool {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            // Runtime probe keeps settings/runtime parity and avoids assuming
            // Translation symbols are present just from OS version checks.
            return NSClassFromString("Translation.TranslationSession") != nil
                || NSClassFromString("TranslationSession") != nil
        }
        #endif
        return false
    }
}

enum DictationTranslationAvailability {
    case installed
    case supported
    case unsupported
}

protocol DictationTranslationEngine {
    func availability(
        source: Locale.Language,
        target: Locale.Language
    ) async -> DictationTranslationAvailability
    func translate(
        text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String
}

struct DictationTranslationResult: Equatable {
    let text: String
    let translated: Bool
    let fallbackReason: FallbackReason?

    enum FallbackReason: Equatable {
        case disabled
        case unsupportedOS
        case sameLanguage
        case assetsNotReady
        case unsupportedPair
        case failed
        case timedOut
    }
}

struct DictationTranslationPreparationRequest: Identifiable, Equatable {
    let id: UUID
    let sourceLocaleIdentifier: String
    let targetLanguageIdentifier: String

    var sourceLanguage: Locale.Language {
        Locale.Language(identifier: sourceLocaleIdentifier)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetLanguageIdentifier)
    }
}

enum DictationTranslationAssetPreparationPlan: Equatable {
    case terminal(DictationTranslationAssetPreparationOutcome)
    case request(DictationTranslationPreparationRequest)
}

struct TranslationFrameworkDictationEngine: DictationTranslationEngine {
    func availability(
        source: Locale.Language,
        target: Locale.Language
    ) async -> DictationTranslationAvailability {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let availability = LanguageAvailability()
            let status = await availability.status(from: source, to: target)
            switch status {
            case .installed:
                return .installed
            case .supported:
                return .supported
            case .unsupported:
                return .unsupported
            @unknown default:
                return .unsupported
            }
        }
        #endif
        return .unsupported
    }

    func translate(
        text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await withTaskCancellationHandler(operation: {
                try await session.translate(text)
            }, onCancel: {
                session.cancel()
            })
            return response.targetText
        }
        #endif
        throw TranslationProcessingError.unsupportedPlatform
    }

    private enum TranslationProcessingError: Error {
        case unsupportedPlatform
    }
}

enum DictationTranslationAssetPreparationOutcome: Equatable {
    case unsupportedOS
    case sameLanguage
    case alreadyInstalled
    case prepared
    case unsupportedPair
    case inactiveApp
    case failed
}

final class DictationTranslationAssetPreparer {
    private let engine: DictationTranslationEngine
    private let isTranslationSupported: () -> Bool

    init(
        engine: DictationTranslationEngine = TranslationFrameworkDictationEngine(),
        isTranslationSupported: @escaping () -> Bool = DictationTranslationPostProcessor.defaultSupportsTranslationRuntime
    ) {
        self.engine = engine
        self.isTranslationSupported = isTranslationSupported
    }

    func preparationPlan(
        sourceLocaleIdentifier: String,
        targetLanguageIdentifier: String,
        isAppActive: @escaping @MainActor () -> Bool = { NSApp.isActive }
    ) async -> DictationTranslationAssetPreparationPlan {
        guard isTranslationSupported() else {
            return .terminal(.unsupportedOS)
        }

        let normalizedSource = DictationTranslationPreferences.normalizeLanguageIdentifier(
            sourceLocaleIdentifier
        )
        let normalizedTarget = DictationTranslationPreferences.normalizeLanguageIdentifier(
            targetLanguageIdentifier
        )

        if DictationTranslationPreferences.isSameLanguage(
            normalizedSource,
            normalizedTarget
        ) {
            return .terminal(.sameLanguage)
        }

        let sourceLanguage = Locale.Language(identifier: normalizedSource)
        let targetLanguage = Locale.Language(identifier: normalizedTarget)
        let availability = await engine.availability(source: sourceLanguage, target: targetLanguage)

        switch availability {
        case .installed:
            return .terminal(.alreadyInstalled)
        case .unsupported:
            return .terminal(.unsupportedPair)
        case .supported:
            break
        }

        guard await isAppActive() else {
            return .terminal(.inactiveApp)
        }

        return .request(
            DictationTranslationPreparationRequest(
                id: UUID(),
                sourceLocaleIdentifier: normalizedSource,
                targetLanguageIdentifier: normalizedTarget
            )
        )
    }
}

final class DictationTranslationPostProcessor {
    struct ProcessingPlan {
        let finalText: String
        let sourceText: String
        let normalizedSourceLocaleIdentifier: String?
        let normalizedTargetLanguageIdentifier: String?
        let immediateResult: DictationTranslationResult?

        var requiresTranslation: Bool { immediateResult == nil }
    }

    private let engine: DictationTranslationEngine
    private let isTranslationSupported: () -> Bool
    private let translateOnDictateEnabled: () -> Bool
    private let targetLanguageIdentifier: () -> String
    private let translationTimeoutNanoseconds: UInt64

    init(
        engine: DictationTranslationEngine = TranslationFrameworkDictationEngine(),
        isTranslationSupported: @escaping () -> Bool = DictationTranslationPostProcessor.defaultSupportsTranslationRuntime,
        translateOnDictateEnabled: @escaping () -> Bool = {
            DictationTranslationPreferences.translateOnDictateEnabled
        },
        targetLanguageIdentifier: @escaping () -> String = {
            DictationTranslationPreferences.targetLanguageIdentifier
        },
        translationTimeoutNanoseconds: UInt64 = 2_500_000_000
    ) {
        self.engine = engine
        self.isTranslationSupported = isTranslationSupported
        self.translateOnDictateEnabled = translateOnDictateEnabled
        self.targetLanguageIdentifier = targetLanguageIdentifier
        self.translationTimeoutNanoseconds = translationTimeoutNanoseconds
    }

    func process(
        finalText: String,
        sourceLocaleIdentifier: String
    ) async -> DictationTranslationResult {
        let plan = processingPlan(
            finalText: finalText,
            sourceLocaleIdentifier: sourceLocaleIdentifier
        )
        return await process(plan: plan)
    }

    func processingPlan(
        finalText: String,
        sourceLocaleIdentifier: String
    ) -> ProcessingPlan {
        let sourceText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            return ProcessingPlan(
                finalText: finalText,
                sourceText: sourceText,
                normalizedSourceLocaleIdentifier: nil,
                normalizedTargetLanguageIdentifier: nil,
                immediateResult: DictationTranslationResult(
                    text: finalText,
                    translated: false,
                    fallbackReason: nil
                )
            )
        }

        guard translateOnDictateEnabled() else {
            return ProcessingPlan(
                finalText: finalText,
                sourceText: sourceText,
                normalizedSourceLocaleIdentifier: nil,
                normalizedTargetLanguageIdentifier: nil,
                immediateResult: DictationTranslationResult(
                    text: finalText,
                    translated: false,
                    fallbackReason: .disabled
                )
            )
        }

        guard isTranslationSupported() else {
            return ProcessingPlan(
                finalText: finalText,
                sourceText: sourceText,
                normalizedSourceLocaleIdentifier: nil,
                normalizedTargetLanguageIdentifier: nil,
                immediateResult: DictationTranslationResult(
                    text: finalText,
                    translated: false,
                    fallbackReason: .unsupportedOS
                )
            )
        }

        let normalizedSource = DictationTranslationPreferences.normalizeLanguageIdentifier(
            sourceLocaleIdentifier
        )
        let normalizedTarget = DictationTranslationPreferences.normalizeLanguageIdentifier(
            targetLanguageIdentifier()
        )

        if DictationTranslationPreferences.isSameLanguage(
            normalizedSource,
            normalizedTarget
        ) {
            return ProcessingPlan(
                finalText: finalText,
                sourceText: sourceText,
                normalizedSourceLocaleIdentifier: normalizedSource,
                normalizedTargetLanguageIdentifier: normalizedTarget,
                immediateResult: DictationTranslationResult(
                    text: finalText,
                    translated: false,
                    fallbackReason: .sameLanguage
                )
            )
        }

        return ProcessingPlan(
            finalText: finalText,
            sourceText: sourceText,
            normalizedSourceLocaleIdentifier: normalizedSource,
            normalizedTargetLanguageIdentifier: normalizedTarget,
            immediateResult: nil
        )
    }

    func process(plan: ProcessingPlan) async -> DictationTranslationResult {
        if let immediateResult = plan.immediateResult {
            return immediateResult
        }
        guard let normalizedSource = plan.normalizedSourceLocaleIdentifier,
              let normalizedTarget = plan.normalizedTargetLanguageIdentifier else {
            return DictationTranslationResult(
                text: plan.finalText,
                translated: false,
                fallbackReason: .failed
            )
        }

        let sourceLanguage = Locale.Language(identifier: normalizedSource)
        let targetLanguage = Locale.Language(identifier: normalizedTarget)

        do {
            return try await withDictationTimeout(.nanoseconds(Int(translationTimeoutNanoseconds)), timeoutError: TranslationProcessingError.timedOut) {
                let availability = await self.engine.availability(
                    source: sourceLanguage,
                    target: targetLanguage
                )
                switch availability {
                case .installed:
                    let translatedText = try await self.engine.translate(
                        text: plan.sourceText,
                        source: sourceLanguage,
                        target: targetLanguage
                    )
                    let trimmedTranslated = translatedText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !trimmedTranslated.isEmpty else {
                        return DictationTranslationResult(
                            text: plan.finalText,
                            translated: false,
                            fallbackReason: .failed
                        )
                    }
                    return DictationTranslationResult(
                        text: trimmedTranslated,
                        translated: true,
                        fallbackReason: nil
                    )
                case .supported:
                    return DictationTranslationResult(
                        text: plan.finalText,
                        translated: false,
                        fallbackReason: .assetsNotReady
                    )
                case .unsupported:
                    return DictationTranslationResult(
                        text: plan.finalText,
                        translated: false,
                        fallbackReason: .unsupportedPair
                    )
                }
            }
        } catch TranslationProcessingError.timedOut {
            return DictationTranslationResult(
                text: plan.finalText,
                translated: false,
                fallbackReason: .timedOut
            )
        } catch {
            return DictationTranslationResult(
                text: plan.finalText,
                translated: false,
                fallbackReason: .failed
            )
        }
    }

    private enum TranslationProcessingError: Error {
        case timedOut
    }

    static func defaultSupportsTranslationRuntime() -> Bool {
        DictationTranslationRuntime.supportsInstalledTranslationSession()
    }

}
