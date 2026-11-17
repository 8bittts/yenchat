import Speech
import AVFoundation

enum DictationRecognitionContext {
    /// App-specific terms to improve recognition biasing.
    /// Keep this list short and specific per Apple guidance.
    static let contextualPhrases: [String] = [
        "YEN",
        "YEN Terminal",
        "zsh",
        "bash",
        "fish",
        "tmux",
        "GitHub",
        "IntelliJ",
        "VS Code"
    ]
}

/// Wrapper around SFSpeechRecognizer for live audio transcription on macOS.
/// Based on Apple's TranscriptionKit pattern, adapted for macOS (no AVAudioSession).
final class DictationRecognizer: NSObject, DictationRecognizerProtocol {
    enum LocaleChangeAction: Equatable {
        case refreshImmediately
        case deferUntilSessionEnd
    }

    enum RecognizerError: Error {
        case recognizerIsUnavailable
        case noAudioInput
        case foregroundActivationRequired
        case taskFailed
        /// The bound microphone or its format changed mid-session, so the installed
        /// tap no longer matches the hardware.
        case audioDeviceChanged

        var message: String {
            switch self {
            case .recognizerIsUnavailable: return "Recognizer is unavailable"
            case .noAudioInput: return "No audio input device available"
            case .foregroundActivationRequired: return "Speech model install requires YEN in the foreground"
            case .taskFailed: return "Speech recognition task failed"
            case .audioDeviceChanged: return "Microphone changed during dictation"
            }
        }
    }

    private let audioTap = DictationAudioEngineTap()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var recognizerLocaleIdentifier: String?
    private var activeSessionLocaleIdentifier: String
    private var localeDidChangeObserver: NSObjectProtocol?
    private var shouldRefreshLocaleAfterActiveSession = false

    private var finalTranscript = ""
    private var previewTranscript = ""
    private var onReady: (@MainActor @Sendable () -> Void)?
    private var onAudioLevel: (@MainActor @Sendable (Float) -> Void)?
    private var onPartialResult: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (RecognizerError) -> Void)?

    /// Completion handler stored when stopListening is called, delivered when delegate signals completion.
    private var stopCompletion: (@MainActor @Sendable (DictationRecognizerStopResult) -> Void)?
    private var isStopping = false

    override init() {
        activeSessionLocaleIdentifier = Locale.current.identifier
        super.init()
        configureRecognizer(for: Locale.current)
        observeLocaleChanges()
    }

    deinit {
        if let localeDidChangeObserver {
            NotificationCenter.default.removeObserver(localeDidChangeObserver)
        }
    }

    var requiresSessionTimeout: Bool { true }
    var activeLocaleIdentifier: String { activeSessionLocaleIdentifier }
    private(set) var inputDeviceBinding: DictationInputDeviceBinding = .systemDefault

    /// Start listening and transcribing live audio.
    func startListening(
        onReady: (@MainActor @Sendable () -> Void)?,
        onAudioLevel: @MainActor @Sendable @escaping (Float) -> Void,
        onPartialResult: @MainActor @Sendable @escaping (String) -> Void,
        onError: (@MainActor @Sendable (RecognizerError) -> Void)? = nil
    ) {
        // Clean up any lingering state from a previous session
        reset()

        self.onReady = onReady
        self.onAudioLevel = onAudioLevel
        self.onPartialResult = onPartialResult
        self.onError = onError
        finalTranscript = ""
        previewTranscript = ""
        ensureRecognizerLocaleCurrent()
        activeSessionLocaleIdentifier = recognizerLocaleIdentifier ?? Locale.current.identifier

        guard let recognizer = recognizer, recognizer.isAvailable else {
            reportError(.recognizerIsUnavailable)
            return
        }

        do {
            let req = try prepareEngine()
            self.request = req

            self.task = recognizer.recognitionTask(with: req, delegate: self)
            self.onReady?()
            self.onReady = nil
        } catch {
            reset()
            reportError(error as? RecognizerError ?? .taskFailed)
        }
    }

    /// Stop listening and return final transcription.
    /// Uses Apple's finish lifecycle: endAudio() + task.finish() + delegate completion.
    func stopListening(completion: @MainActor @Sendable @escaping (DictationRecognizerStopResult) -> Void) {
        guard !isStopping else { return }

        // Nothing active (startup failure or natural completion) — return immediately.
        if request == nil && task == nil {
            let stopResult = deliveredStopResult()
            reset()
            completion(stopResult)
            return
        }

        isStopping = true
        stopCompletion = completion

        // Apple buffer-recognition best practice (mirrors the SpokenWord sample):
        // 1) tear down the audio tap first (removes tap + stops the engine) so no
        //    buffer arrives after endAudio() and gets silently dropped
        // 2) endAudio() to mark no more audio
        // 3) finish() to complete recognition over the buffered audio
        audioTap.teardown()
        request?.endAudio()
        task?.finish()
    }

    /// Cancel current recognition without returning results.
    func cancel() {
        reset()
    }

    /// Fast local readiness probe used for "Re-check Local Speech Service".
    func startupIssue() -> RecognizerError? {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            return .recognizerIsUnavailable
        }
        guard AVCaptureDevice.default(for: .audio) != nil else {
            return .noAudioInput
        }
        return nil
    }

    // MARK: - Private

    /// Deliver transcript to stored completion handler after recognition task completion.
    private func deliverFinalResultIfNeeded() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil

        let stopResult = deliveredStopResult()
        reset()
        completion(stopResult)
    }

    private func prepareEngine() throws -> SFSpeechAudioBufferRecognitionRequest {
        let audioEngine = AVAudioEngine()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = DictationRecognitionContext.contextualPhrases

        request.addsPunctuation = true

        // Use on-device recognition if available (privacy, works offline)
        if let recognizer = recognizer, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        // Check for audio input device before accessing inputNode (which can throw
        // an ObjC exception on Macs with no microphone — Mac Mini, Mac Pro without USB audio)
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw RecognizerError.noAudioInput
        }

        // [CRITICAL] Bind the selected microphone before reading the format below —
        // the format belongs to the bound device, so reading first would install the
        // tap for the wrong one.
        inputDeviceBinding = DictationInputDeviceBinder.apply(to: audioEngine)
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw RecognizerError.noAudioInput
        }

        audioTap.install(
            engine: audioEngine,
            bufferSize: 1024,
            format: recordingFormat,
            onAudioLevel: { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.onAudioLevel?(level)
                }
            }
        ) { buffer, _ in
            request.append(buffer)
        }

        audioTap.observeConfigurationChanges { [weak self] in
            self?.reportError(.audioDeviceChanged)
        }

        audioEngine.prepare()
        try audioEngine.start()

        return request
    }

    private func reset() {
        isStopping = false
        stopCompletion = nil
        finalTranscript = ""
        previewTranscript = ""
        task?.cancel()
        task = nil
        audioTap.teardown()
        audioTap.clear()
        request = nil
        onReady = nil
        onAudioLevel = nil
        onPartialResult = nil
        onError = nil
    }

    private func reportError(_ error: RecognizerError) {
        print("DictationRecognizer: \(error.message)")
        onError?(error)
    }

    static func makeStopResult(
        finalTranscript: String,
        previewTranscript: String,
        stopMarkedAsFailure: Bool = false
    ) -> DictationRecognizerStopResult {
        let normalizedFinal = finalTranscript.dictationNormalized()
        let normalizedPreview = previewTranscript.dictationNormalized()
        let fallbackText = normalizedPreview == normalizedFinal ? nil : normalizedPreview
        return DictationRecognizerStopResult(
            finalText: normalizedFinal,
            fallbackText: fallbackText,
            stopMarkedAsFailure: stopMarkedAsFailure
        )
    }

    private func deliveredStopResult() -> DictationRecognizerStopResult {
        Self.makeStopResult(finalTranscript: finalTranscript, previewTranscript: previewTranscript)
    }


    private func updatePreviewTranscript(_ value: String) {
        previewTranscript = value
        onPartialResult?(value)
    }

    private func updateFinalTranscript(_ value: String) {
        finalTranscript = value
        previewTranscript = value
        onPartialResult?(value)
    }

    private func isCurrentTask(_ candidate: SFSpeechRecognitionTask) -> Bool {
        candidate === task
    }

    private func ensureRecognizerLocaleCurrent() {
        let currentIdentifier = Locale.current.identifier
        guard recognizerLocaleIdentifier != currentIdentifier else { return }
        configureRecognizer(for: Locale.current)
    }

    private func configureRecognizer(for locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.delegate = self
        recognizer?.defaultTaskHint = .dictation
        recognizerLocaleIdentifier = locale.identifier
    }

    private func observeLocaleChanges() {
        localeDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLocaleDidChange()
            }
        }
    }

    @MainActor
    private func handleLocaleDidChange() {
        switch Self.localeChangeAction(hasActiveSession: task != nil || request != nil || isStopping) {
        case .refreshImmediately:
            configureRecognizer(for: Locale.current)
            activeSessionLocaleIdentifier = recognizerLocaleIdentifier ?? Locale.current.identifier
        case .deferUntilSessionEnd:
            shouldRefreshLocaleAfterActiveSession = true
        }
    }

    private func applyDeferredLocaleRefreshIfNeeded() {
        guard shouldRefreshLocaleAfterActiveSession else { return }
        shouldRefreshLocaleAfterActiveSession = false
        configureRecognizer(for: Locale.current)
        activeSessionLocaleIdentifier = recognizerLocaleIdentifier ?? Locale.current.identifier
    }

    static func localeChangeAction(hasActiveSession: Bool) -> LocaleChangeAction {
        hasActiveSession ? .deferUntilSessionEnd : .refreshImmediately
    }
}

// MARK: - Speech Delegates

extension DictationRecognizer: SFSpeechRecognizerDelegate {
    /// Monitor recognizer availability changes while running.
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let recognizer = self.recognizer, recognizer === speechRecognizer else { return }
            guard !available else { return }
            guard !self.isStopping, self.task != nil || self.request != nil else { return }

            self.reportError(.recognizerIsUnavailable)
        }
    }
}

extension DictationRecognizer: SFSpeechRecognitionTaskDelegate {
    /// Partial hypothesis callback for live overlay updates.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentTask(task) else { return }
            self.updatePreviewTranscript(transcription.formattedString)
        }
    }

    /// Final recognition hypothesis callback.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentTask(task) else { return }
            self.updateFinalTranscript(recognitionResult.bestTranscription.formattedString)
        }
    }

    /// Task lifecycle completion callback.
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentTask(task) else { return }

            let completionError = task.error

            // Mark task-level completion and release task/request references.
            self.task = nil
            self.request = nil
            self.audioTap.teardown()

            if self.isStopping {
                self.applyDeferredLocaleRefreshIfNeeded()
                self.deliverFinalResultIfNeeded()
                return
            }

            if !successfully || completionError != nil {
                if let completionError {
                    print("DictationRecognizer: recognition task failed — \(completionError.localizedDescription)")
                }
                self.onError?(.taskFailed)
            }

            self.applyDeferredLocaleRefreshIfNeeded()
        }
    }
}
