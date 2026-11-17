#if os(macOS)

/// Explicit stop payload so the controller can distinguish authoritative final text
/// from preview-only fallback candidates.
struct DictationRecognizerStopResult: Equatable {
    let finalText: String?
    let fallbackText: String?
    let stopMarkedAsFailure: Bool

    static let empty = Self(finalText: nil, fallbackText: nil, stopMarkedAsFailure: false)

    init(finalText: String?, fallbackText: String?, stopMarkedAsFailure: Bool = false) {
        self.finalText = finalText?.dictationNormalized()
        self.fallbackText = fallbackText?.dictationNormalized()
        self.stopMarkedAsFailure = stopMarkedAsFailure
    }
}

/// Shared interface for speech-to-text recognizers.
/// Both `DictationRecognizer` (SFSpeechRecognizer, fallback) and `SpeechAnalyzerRecognizer`
/// (macOS 26+ SpeechAnalyzer, default) conform to this protocol.
/// Selection is automatic via `#available(macOS 26, *)`.
@MainActor
protocol DictationRecognizerProtocol: AnyObject {
    /// Whether this recognizer needs a hard timeout to avoid losing transcript data.
    /// `SFSpeechRecognizer` needs it (`true`), `SpeechAnalyzer` does not (`false`).
    var requiresSessionTimeout: Bool { get }

    /// Locale identifier associated with the most recent active/startup recognition session.
    /// Used for downstream locale-sensitive post-processing (for example translation source locale).
    var activeLocaleIdentifier: String { get }

    /// Which microphone the most recent session actually bound, and why it differs
    /// from the saved choice when it does. Required on the protocol so both
    /// recognizers report the fallback the same way and neither can downgrade to the
    /// built-in microphone silently.
    var inputDeviceBinding: DictationInputDeviceBinding { get }

    /// Start listening and transcribing live audio.
    /// - Parameters:
    ///   - onReady: Called on the main thread once the recognizer is actively capturing audio.
    ///   - onPartialResult: Called on the main thread with each partial transcription.
    ///   - onError: Called on the main thread if recognition fails.
    func startListening(
        onReady: (@MainActor @Sendable () -> Void)?,
        onAudioLevel: @MainActor @Sendable @escaping (Float) -> Void,
        onPartialResult: @MainActor @Sendable @escaping (String) -> Void,
        onError: (@MainActor @Sendable (DictationRecognizer.RecognizerError) -> Void)?
    )

    /// Stop listening and return the recognizer's authoritative final text plus
    /// any preview-only fallback candidate for failure paths.
    /// - Parameter completion: Called on the main thread with the stop result.
    func stopListening(completion: @MainActor @Sendable @escaping (DictationRecognizerStopResult) -> Void)

    /// Cancel current recognition without returning results.
    func cancel()

    /// Fast local readiness probe — returns the issue preventing startup, or nil if ready.
    func startupIssue() -> DictationRecognizer.RecognizerError?
}

#endif // os(macOS)
