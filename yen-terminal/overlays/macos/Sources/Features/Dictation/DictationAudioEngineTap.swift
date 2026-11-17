#if os(macOS)
    import Accelerate
    import AVFoundation

    /// Owns the dictation `AVAudioEngine` and its input-node tap lifecycle. The
    /// `stopEngine()` teardown (remove-tap-if-installed + stop-if-running) was
    /// byte-identical across `SpeechAnalyzerRecognizer` and `DictationRecognizer`;
    /// this centralizes that, the `hasInstalledTap` bookkeeping, and the engine
    /// storage. The tap body itself stays with each recognizer — buffer sizes and
    /// per-buffer handling diverge — and is passed in via `install`.
    final class DictationAudioEngineTap {
        private static let levelUpdateInterval: CFTimeInterval = 1.0 / 15.0
        private(set) var engine: AVAudioEngine?
        private var hasInstalledTap = false
        private var lastLevelUpdateTime: CFTimeInterval = 0
        private var configurationObserver: NSObjectProtocol?

        /// True once an engine is installed and not yet cleared — the recognizers
        /// use this as their "audio pipeline active" sentinel.
        var isActive: Bool { engine != nil }

        /// Install `block` as an input tap on `engine`'s input node and take
        /// ownership of the engine. Callers prepare/start the engine themselves
        /// (the analyzer path interleaves other async setup around this).
        func install(
            engine: AVAudioEngine,
            bufferSize: AVAudioFrameCount,
            format: AVAudioFormat,
            onAudioLevel: (@Sendable (Float) -> Void)? = nil,
            block: @escaping AVAudioNodeTapBlock
        ) {
            lastLevelUpdateTime = 0
            engine.inputNode.installTap(
                onBus: 0,
                bufferSize: bufferSize,
                format: format
            ) { [weak self] buffer, time in
                if let self,
                   let onAudioLevel,
                   let level = self.audioLevelIfDue(buffer: buffer) {
                    onAudioLevel(level)
                }
                block(buffer, time)
            }
            hasInstalledTap = true
            self.engine = engine
        }

        private func audioLevelIfDue(buffer: AVAudioPCMBuffer) -> Float? {
            let now = CACurrentMediaTime()
            guard now - lastLevelUpdateTime >= Self.levelUpdateInterval else { return nil }
            lastLevelUpdateTime = now
            return Self.normalizedAudioLevel(buffer: buffer)
        }

        static func normalizedAudioLevel(buffer: AVAudioPCMBuffer) -> Float {
            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else { return 0 }

            var rootMeanSquare: Float = 0
            vDSP_rmsqv(
                channelData[0],
                1,
                &rootMeanSquare,
                vDSP_Length(buffer.frameLength)
            )
            let decibels = 20 * log10(max(rootMeanSquare, 0.000_01))
            return min(max((decibels + 50) / 50, 0), 1)
        }

        /// Report a mid-session audio configuration change for the installed engine.
        ///
        /// macOS posts `AVAudioEngineConfigurationChange` when the bound device or its
        /// format changes under a running engine — pulling a USB microphone mid-
        /// sentence is the common case. The tap is already invalid at that point, so
        /// the recognizer stops the session and reports it rather than restarting on
        /// whichever device macOS fell back to. Splicing a second microphone into one
        /// transcript would silently change the audio source mid-sentence, which is
        /// the failure this feature exists to remove, not a recovery from it.
        ///
        /// Call after `install`. `teardown()` removes the observer.
        func observeConfigurationChanges(_ handler: @escaping @MainActor @Sendable () -> Void) {
            guard let engine, configurationObserver == nil else { return }
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { _ in
                Task { @MainActor in handler() }
            }
        }

        /// Remove the tap (if installed) and stop the engine (if running). Safe to
        /// call repeatedly and when nothing is installed. Guards against double-stop.
        func teardown() {
            if let configurationObserver {
                NotificationCenter.default.removeObserver(configurationObserver)
                self.configurationObserver = nil
            }
            if hasInstalledTap {
                engine?.inputNode.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            if engine?.isRunning == true {
                engine?.stop()
            }
        }

        /// Release the engine reference. Call from `reset()` after `teardown()`.
        func clear() {
            engine = nil
            lastLevelUpdateTime = 0
        }
    }
#endif
