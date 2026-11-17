#if os(macOS)
    import Foundation

    extension String {
        /// Trim surrounding whitespace/newlines; returns nil when the result is
        /// empty. The single dictation transcript normalizer — it replaces four
        /// near-identical copies, one of which (`DictationRecognizerStopResult`)
        /// returned the *raw* untrimmed text on the non-empty path and could
        /// insert leading/trailing whitespace at the cursor.
        func dictationNormalized() -> String? {
            let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
#endif
