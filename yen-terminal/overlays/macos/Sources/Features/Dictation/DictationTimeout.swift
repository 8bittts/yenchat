#if os(macOS)
    import Foundation

    /// Run `operation` racing a timeout. A `.zero` duration bypasses the race
    /// entirely — the translation path passes zero in tests to assert the
    /// success path deterministically. Shared by SpeechAnalyzerRecognizer and
    /// DictationTranslationProcessing (each supplies its own timeout error).
    func withDictationTimeout<T: Sendable>(
        _ duration: Duration,
        timeoutError: any Error & Sendable,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        if duration == .zero {
            return try await operation()
        }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw timeoutError
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
#endif
