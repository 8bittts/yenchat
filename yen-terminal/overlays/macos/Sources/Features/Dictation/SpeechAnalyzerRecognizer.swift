#if os(macOS)
import AVFoundation
import Cocoa
import Speech

/// Drop-in replacement for `DictationRecognizer` using Apple's SpeechAnalyzer API (macOS 26+).
/// Removes the 60-second recognition limit and uses modern async/await internally,
/// bridged to the callback-based `DictationRecognizerProtocol` interface.
///
/// Automatically selected on macOS 26+; older systems fall back to `DictationRecognizer`.
/// Metrics are printed to console for latency profiling.
@available(macOS 26, *)
final class SpeechAnalyzerRecognizer: DictationRecognizerProtocol {
    private struct SupportedLocaleCacheState {
        var normalizedIdentifiers: Set<String> = []
        var didLoad = false
        var refreshInFlight = false
    }

    private final class SupportedLocaleCacheStore: @unchecked Sendable {
        private let lock = NSLock()
        private var state = SupportedLocaleCacheState()

        func beginRefreshIfNeeded(force: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            if force {
                state.refreshInFlight = true
                return true
            }
            if state.didLoad || state.refreshInFlight {
                return false
            }
            state.refreshInFlight = true
            return true
        }

        func finishRefresh(with normalizedIdentifiers: Set<String>) {
            lock.lock()
            state.normalizedIdentifiers = normalizedIdentifiers
            state.didLoad = true
            state.refreshInFlight = false
            lock.unlock()
        }

        func cachedLocaleSupport(for normalizedIdentifier: String) -> Bool? {
            lock.lock()
            defer { lock.unlock() }

            guard state.didLoad else { return nil }
            return state.normalizedIdentifiers.contains(normalizedIdentifier)
        }
    }

    private struct WarmStartContext {
        let localeIdentifier: String
        let transcriber: DictationTranscriber
        let analyzer: SpeechAnalyzer
        let analyzerFormat: AVAudioFormat
        let microphoneSampleRate: Double
        let microphoneChannelCount: AVAudioChannelCount
        let microphoneCommonFormat: AVAudioCommonFormat

        func matches(localeIdentifier: String, microphoneFormat: AVAudioFormat) -> Bool {
            self.localeIdentifier == localeIdentifier
                && microphoneSampleRate == microphoneFormat.sampleRate
                && microphoneChannelCount == microphoneFormat.channelCount
                && microphoneCommonFormat == microphoneFormat.commonFormat
        }
    }

    // MARK: - State

    private let audioTap = DictationAudioEngineTap()

    private var analyzer: SpeechAnalyzer?
    private var audioContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzeTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var finalizeTaskToken: UUID?
    private var stopTimeoutTask: Task<Void, Never>?

    private var onReady: (@MainActor @Sendable () -> Void)?
    private var onAudioLevel: (@MainActor @Sendable (Float) -> Void)?
    private var onPartialResult: (@MainActor @Sendable (String) -> Void)?
    private var onError: (@MainActor @Sendable (DictationRecognizer.RecognizerError) -> Void)?
    private var stopCompletion: (@MainActor @Sendable (DictationRecognizerStopResult) -> Void)?
    private var isStopping = false
    private var resultsTaskCompleted = false

    private var finalizedText = ""
    private var volatileText = ""
    private var partialCount = 0
    private var startTime: CFAbsoluteTime = 0
    private var firstPartialTime: CFAbsoluteTime?
    private var preparedModelLocaleID: String?
    private var activeSessionLocaleIdentifier = Locale.current.identifier
    private var reportedError = false
    private var stopMarkedAsFailure = false
    private var warmStartContext: WarmStartContext?
    private var warmStartTask: Task<Void, Never>?

    private let modelInstallTimeout: Duration = .seconds(180)
    private let modelPrepareTimeout: Duration = .seconds(20)
    nonisolated private static let localeSupportCache = SupportedLocaleCacheStore()

    private enum StartupTimeoutError: Error {
        case modelInstall
        case modelPrepare

        var message: String {
            switch self {
            case .modelInstall:
                return "Speech model installation timed out"
            case .modelPrepare:
                return "Speech model preparation timed out"
            }
        }
    }

    private enum ModelInstallError: Error {
        case requiresForegroundInstall
    }

    enum StopListeningPath: Equatable {
        case startupDidNotReachActivePipeline
        case completedResultsReadyForImmediateDelivery
        case finalizePendingAudio
    }

    init() {
        Self.refreshSupportedLocaleCacheIfNeeded()
    }

    // MARK: - DictationRecognizerProtocol

    func startListening(
        onReady: (@MainActor @Sendable () -> Void)?,
        onAudioLevel: @MainActor @Sendable @escaping (Float) -> Void,
        onPartialResult: @MainActor @Sendable @escaping (String) -> Void,
        onError: (@MainActor @Sendable (DictationRecognizer.RecognizerError) -> Void)? = nil
    ) {
        reset()

        self.onReady = onReady
        self.onAudioLevel = onAudioLevel
        self.onPartialResult = onPartialResult
        self.onError = onError
        self.finalizedText = ""
        self.volatileText = ""
        self.partialCount = 0
        self.startTime = CFAbsoluteTimeGetCurrent()
        self.firstPartialTime = nil
        self.reportedError = false
        self.activeSessionLocaleIdentifier = Locale.current.identifier

        guard AVCaptureDevice.default(for: .audio) != nil else {
            reportError(.noAudioInput)
            return
        }

        // Launch the async pipeline
        analyzeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await startAnalyzerPipeline()
            } catch {
                if error is CancellationError {
                    return
                }
                if !isStopping {
                    if let timeoutError = error as? StartupTimeoutError {
                        print("SpeechAnalyzerRecognizer: \(timeoutError.message)")
                    }
                    if error is ModelInstallError {
                        print("SpeechAnalyzerRecognizer: on-device model install requires YEN in the foreground")
                        reportError(.foregroundActivationRequired)
                        return
                    }
                    print("SpeechAnalyzerRecognizer: pipeline error — \(error)")
                    reportError(.taskFailed)
                }
            }
        }
    }

    var requiresSessionTimeout: Bool { false }
    var activeLocaleIdentifier: String { activeSessionLocaleIdentifier }
    private(set) var inputDeviceBinding: DictationInputDeviceBinding = .systemDefault

    func stopListening(completion: @MainActor @Sendable @escaping (DictationRecognizerStopResult) -> Void) {
        guard !isStopping else { return }

        let stopPath = Self.stopListeningPath(
            hasActiveAudioPipeline: resultsTask != nil || audioContinuation != nil || audioTap.isActive,
            resultsTaskCompleted: resultsTaskCompleted
        )

        switch stopPath {
        case .startupDidNotReachActivePipeline:
            // Startup never reached active audio/analyzer state (for example: key released while
            // model setup is in-flight). Cancel immediately and return without timeout delay.
            analyzeTask?.cancel()
            let stopResult = currentStopResult()
            reset()
            completion(stopResult)
            return
        case .completedResultsReadyForImmediateDelivery:
            break
        case .finalizePendingAudio:
            break
        }

        isStopping = true
        stopCompletion = completion
        stopMarkedAsFailure = false

        // Stop feeding audio
        audioContinuation?.finish()
        audioTap.teardown()

        if stopPath == .completedResultsReadyForImmediateDelivery {
            // If the results stream already ended (short utterances finish before
            // the user releases the key), deliver immediately — no finalization needed.
            deliverFinalResult()
            return
        }

        // Finalize the analyzer to process remaining buffered audio
        finalizeTask?.cancel()
        let analyzerToFinalize = analyzer
        let finalizeToken = UUID()
        finalizeTaskToken = finalizeToken
        finalizeTask = Task { @MainActor [weak self, analyzerToFinalize] in
            defer {
                if let self, self.finalizeTaskToken == finalizeToken {
                    self.finalizeTask = nil
                    self.finalizeTaskToken = nil
                }
            }
            do {
                try await analyzerToFinalize?.finalizeAndFinishThroughEndOfInput()
            } catch {
                if error is CancellationError {
                    return
                }
                print("SpeechAnalyzerRecognizer: finalization error — \(error)")
                self?.stopMarkedAsFailure = true
            }
            // IMPORTANT: Do NOT call deliverFinalResult() here.
            // finalizeAndFinishThroughEndOfInput() guarantees results are
            // *published* to the async sequence, but NOT that resultsTask
            // has *consumed* them yet. Calling deliverFinalResult() here
            // races with resultsTask — reset() cancels the task and
            // destroys buffered-but-unprocessed final segments (clipping).
            // Delivery comes from: (1) resultsTask completion (line ~357),
            // (2) short-utterance fast-path (line ~151), or (3) safety timeout.
        }

        // Safety timeout — if results never arrive, deliver what we have after 5 seconds
        stopTimeoutTask?.cancel()
        stopTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.stopMarkedAsFailure = true
            self?.deliverFinalResult()
        }
    }

    func cancel() {
        audioContinuation?.finish()

        // Capture analyzer before reset() nils it, so cancelAndFinishNow()
        // actually executes against the live instance.
        let analyzerToCancel = analyzer
        Task {
            await analyzerToCancel?.cancelAndFinishNow()
        }

        analyzeTask?.cancel()
        resultsTask?.cancel()
        reset()
        scheduleWarmStartIfPossible()
    }

    func startupIssue() -> DictationRecognizer.RecognizerError? {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            return .noAudioInput
        }
        switch startupLocaleSupportStatus() {
        case .some(true):
            return nil
        case .some(false):
            return .recognizerIsUnavailable
        case .none:
            return nil
        }
    }

    func startupLocaleSupportStatus() -> Bool? {
        Self.refreshSupportedLocaleCacheIfNeeded()
        let currentNormalizedLocale = Self.normalizedLocaleIdentifier(Locale.current.identifier)
        return Self.cachedLocaleSupport(for: currentNormalizedLocale)
    }

    nonisolated private static func normalizedLocaleIdentifier(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).minimalIdentifier
    }

    // MARK: - Async Pipeline

    @MainActor
    private func startAnalyzerPipeline() async throws {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            reportError(.recognizerIsUnavailable)
            return
        }
        activeSessionLocaleIdentifier = locale.identifier

        // Set up audio engine and format conversion.
        // [CRITICAL] Bind the selected microphone before reading the format below —
        // the format belongs to the bound device, so reading first would build the
        // converter and tap for the wrong one.
        let audioEngine = AVAudioEngine()
        inputDeviceBinding = DictationInputDeviceBinder.apply(to: audioEngine)
        let inputNode = audioEngine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)

        guard micFormat.sampleRate > 0 else {
            reportError(.noAudioInput)
            return
        }

        let resources = try await startResources(
            locale: locale,
            microphoneFormat: micFormat
        )
        guard !Task.isCancelled, !isStopping else { return }

        let transcriber = resources.transcriber
        let analyzer = resources.analyzer
        let analyzerFormat = resources.analyzerFormat
        self.analyzer = analyzer

        guard let converter = AVAudioConverter(from: micFormat, to: analyzerFormat) else {
            reportError(.taskFailed)
            return
        }
        converter.primeMethod = AVAudioConverterPrimeMethod.none

        // Create AsyncStream for AnalyzerInput
        let (audioStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.audioContinuation = continuation

        // Install audio tap — converts mic format to analyzer format, wraps in AnalyzerInput.
        // Capture converter as a local constant to avoid accessing self from the realtime audio thread.
        let tapConverter = converter
        audioTap.install(
            engine: audioEngine,
            bufferSize: 4096,
            format: micFormat,
            onAudioLevel: { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.onAudioLevel?(level)
                }
            }
        ) { [weak self] buffer, _ in
            let ratio = analyzerFormat.sampleRate / micFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let output = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: outputCapacity
            ) else {
                Task { @MainActor [weak self] in
                    self?.reportAudioConversionFailure()
                }
                return
            }

            var error: NSError?
            var consumed = false
            let status = tapConverter.convert(to: output, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if Self.didAudioConversionFail(status: status) {
                Task { @MainActor [weak self] in
                    self?.reportAudioConversionFailure()
                }
                return
            }
            if output.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: output))
            }
        }

        audioTap.observeConfigurationChanges { [weak self] in
            self?.reportError(.audioDeviceChanged)
        }

        audioEngine.prepare()
        try audioEngine.start()

        print("SpeechAnalyzerRecognizer: started (locale: \(activeSessionLocaleIdentifier))")

        // Task 1: Run analyzer pipeline off the main actor.
        let feedTask = Task(priority: .userInitiated) {
            try await Self.runAnalyzer(analyzer: analyzer, inputSequence: audioStream)
        }

        // Task 2: Consume results and publish UI updates on the main actor.
        resultsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }

                    self.partialCount += 1

                    if self.firstPartialTime == nil {
                        self.firstPartialTime = CFAbsoluteTimeGetCurrent()
                        let latency = (self.firstPartialTime! - self.startTime) * 1000
                        print("SpeechAnalyzerRecognizer: first partial at \(String(format: "%.0f", latency))ms")
                    }

                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        self.appendFinalizedSegment(text)
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }

                    let display = self.composedTranscript(includeVolatile: true)
                    if !display.isEmpty {
                        self.onPartialResult?(display)
                    }
                }
            } catch {
                if self.isStopping, !Task.isCancelled {
                    self.stopMarkedAsFailure = true
                    print("SpeechAnalyzerRecognizer: stop-phase results error — \(error)")
                } else if Self.shouldSurfaceResultStreamError(
                    isTaskCancelled: Task.isCancelled,
                    isStopping: self.isStopping
                ) {
                    print("SpeechAnalyzerRecognizer: results error — \(error)")
                    self.reportError(.taskFailed)
                }
            }

            let totalLatency = (CFAbsoluteTimeGetCurrent() - self.startTime) * 1000
            print("SpeechAnalyzerRecognizer: done — \(self.partialCount) partials, total \(String(format: "%.0f", totalLatency))ms")
            self.resultsTaskCompleted = true
            self.deliverFinalResult()
        }
        notifyReadyIfNeeded()

        // Wait for the feed task (completes when audio stream finishes)
        do {
            try await feedTask.value
        } catch {
            if !Task.isCancelled, !isStopping {
                print("SpeechAnalyzerRecognizer: analyzer feed error — \(error)")
                reportError(.taskFailed)
            }
        }
    }

    @MainActor
    private func startResources(
        locale: Locale,
        microphoneFormat: AVAudioFormat
    ) async throws -> (transcriber: DictationTranscriber, analyzer: SpeechAnalyzer, analyzerFormat: AVAudioFormat) {
        let resources: (transcriber: DictationTranscriber, analyzer: SpeechAnalyzer, analyzerFormat: AVAudioFormat)
        if let warmStartContext = takeWarmStartContextIfAvailable(
            localeIdentifier: locale.identifier,
            microphoneFormat: microphoneFormat
        ) {
            resources = (
                transcriber: warmStartContext.transcriber,
                analyzer: warmStartContext.analyzer,
                analyzerFormat: warmStartContext.analyzerFormat
            )
        } else {
            resources = try await makeColdStartResources(
                locale: locale,
                microphoneFormat: microphoneFormat
            )
        }

        try await resources.analyzer.setContext(Self.makeAnalysisContext())
        return resources
    }

    @MainActor
    private func makeColdStartResources(
        locale: Locale,
        microphoneFormat: AVAudioFormat
    ) async throws -> (transcriber: DictationTranscriber, analyzer: SpeechAnalyzer, analyzerFormat: AVAudioFormat) {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)

        if preparedModelLocaleID != locale.identifier {
            try await ensureSpeechModelReady(for: transcriber, localeID: locale.identifier)
            preparedModelLocaleID = locale.identifier
        }
        guard !Task.isCancelled, !isStopping else { throw CancellationError() }

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .processLifetime)
        )

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: microphoneFormat
        ) else {
            throw DictationRecognizer.RecognizerError.taskFailed
        }
        guard !Task.isCancelled, !isStopping else { throw CancellationError() }

        try await withDictationTimeout(modelPrepareTimeout, timeoutError: StartupTimeoutError.modelPrepare) {
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
        }
        guard !Task.isCancelled, !isStopping else { throw CancellationError() }

        return (transcriber: transcriber, analyzer: analyzer, analyzerFormat: analyzerFormat)
    }

    // MARK: - Private

    @MainActor
    private func ensureSpeechModelReady(for transcriber: DictationTranscriber, localeID: String) async throws {
        let statusBeforeInstall = await AssetInventory.status(forModules: [transcriber])
        print(
            "SpeechAnalyzerRecognizer: asset status before install check (\(localeID)) — \(statusBeforeInstall)"
        )
        if statusBeforeInstall >= .installed {
            return
        }
        if !NSApp.isActive {
            print(
                "SpeechAnalyzerRecognizer: deferring model install while app is backgrounded (\(localeID))"
            )
            throw ModelInstallError.requiresForegroundInstall
        }

        guard let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            let statusWithoutRequest = await AssetInventory.status(forModules: [transcriber])
            print(
                "SpeechAnalyzerRecognizer: no install request returned (\(localeID)); status \(statusWithoutRequest)"
            )
            return
        }

        try await downloadSpeechModelWithReservationRecovery(
            installRequest,
            localeID: localeID
        )
        let statusAfterInstall = await AssetInventory.status(forModules: [transcriber])
        print(
            "SpeechAnalyzerRecognizer: asset status after install (\(localeID)) — \(statusAfterInstall)"
        )
    }

    @MainActor
    private func downloadSpeechModelWithReservationRecovery(
        _ installRequest: AssetInstallationRequest,
        localeID: String
    ) async throws {
        do {
            try await downloadSpeechModel(installRequest, localeID: localeID)
        } catch {
            guard Self.isReservationCapacityError(error) else { throw error }
            print(
                "SpeechAnalyzerRecognizer: reservation cap reached (\(localeID)); releasing stale reserved locales"
            )
            let recovered = await recoverReservedLocaleCapacity(currentLocaleID: localeID)
            guard recovered else {
                print("SpeechAnalyzerRecognizer: reservation recovery failed; aborting install retry")
                throw error
            }
            print("SpeechAnalyzerRecognizer: reservation recovery succeeded; retrying model install")
            try await downloadSpeechModel(installRequest, localeID: localeID)
        }
    }

    private func recoverReservedLocaleCapacity(currentLocaleID: String) async -> Bool {
        let maximumReserved = AssetInventory.maximumReservedLocales
        var reservedLocales = await AssetInventory.reservedLocales
        guard !reservedLocales.isEmpty else { return false }

        let normalizedCurrent = Self.normalizedLocaleIdentifier(currentLocaleID)
        let staleLocales = reservedLocales.filter {
            Self.normalizedLocaleIdentifier($0.identifier) != normalizedCurrent
        }
        let candidates = staleLocales.isEmpty ? reservedLocales : staleLocales

        var releasedAny = false
        for locale in candidates {
            let released = await AssetInventory.release(reservedLocale: locale)
            print("SpeechAnalyzerRecognizer: release reserved locale \(locale.identifier) -> \(released)")
            if released {
                releasedAny = true
            }

            reservedLocales = await AssetInventory.reservedLocales
            if reservedLocales.count < maximumReserved {
                break
            }
        }

        print(
            "SpeechAnalyzerRecognizer: reserved locale count after recovery — \(reservedLocales.count)/\(maximumReserved)"
        )
        return releasedAny
    }

    private static func isReservationCapacityError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SFSpeechErrorDomain else { return false }
        guard let code = SFSpeechError.Code(rawValue: nsError.code) else { return false }
        return code == .tooManyAssetLocalesAllocated
    }

    @MainActor
    private func downloadSpeechModel(_ installRequest: AssetInstallationRequest, localeID: String) async throws {
        print("SpeechAnalyzerRecognizer: downloading language pack (\(localeID))")

        try await withDictationTimeout(modelInstallTimeout, timeoutError: StartupTimeoutError.modelInstall) {
            try await installRequest.downloadAndInstall()
        }
        print("SpeechAnalyzerRecognizer: language pack ready (\(localeID))")
    }

    @MainActor
    private func scheduleWarmStartIfPossible() {
        guard warmStartContext == nil else { return }
        guard warmStartTask == nil else { return }
        guard analyzer == nil else { return }
        guard !audioTap.isActive else { return }
        guard resultsTask == nil else { return }
        guard !isStopping else { return }

        warmStartTask = Task { @MainActor [weak self] in
            defer {
                self?.warmStartTask = nil
            }
            await self?.prepareWarmStartContext()
        }
    }

    @MainActor
    private func prepareWarmStartContext() async {
        guard AVCaptureDevice.default(for: .audio) != nil else { return }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) else { return }
        guard analyzer == nil, !audioTap.isActive, resultsTask == nil, !isStopping else { return }

        // Probe the device the real session will bind, not the system default.
        // `WarmStartContext.matches` compares sample rate, channel count, and common
        // format, so probing the wrong device cannot corrupt a session — it just
        // guarantees a miss. With an external microphone selected the warm start
        // would be discarded every time and the latency win would silently vanish.
        let probeEngine = AVAudioEngine()
        DictationInputDeviceBinder.apply(to: probeEngine)
        let microphoneFormat = probeEngine.inputNode.outputFormat(forBus: 0)
        guard microphoneFormat.sampleRate > 0 else { return }

        do {
            let resources = try await makeColdStartResources(
                locale: locale,
                microphoneFormat: microphoneFormat
            )
            guard analyzer == nil, !audioTap.isActive, resultsTask == nil, !isStopping else { return }
            warmStartContext = WarmStartContext(
                localeIdentifier: locale.identifier,
                transcriber: resources.transcriber,
                analyzer: resources.analyzer,
                analyzerFormat: resources.analyzerFormat,
                microphoneSampleRate: microphoneFormat.sampleRate,
                microphoneChannelCount: microphoneFormat.channelCount,
                microphoneCommonFormat: microphoneFormat.commonFormat
            )
        } catch is CancellationError {
            return
        } catch {
            print("SpeechAnalyzerRecognizer: warm start preparation failed — \(error)")
        }
    }

    @MainActor
    private func takeWarmStartContextIfAvailable(
        localeIdentifier: String,
        microphoneFormat: AVAudioFormat
    ) -> WarmStartContext? {
        guard let warmStartContext else { return nil }
        if warmStartContext.matches(
            localeIdentifier: localeIdentifier,
            microphoneFormat: microphoneFormat
        ) {
            self.warmStartContext = nil
            return warmStartContext
        }

        self.warmStartContext = nil
        return nil
    }

    nonisolated
    private static func runAnalyzer(
        analyzer: SpeechAnalyzer,
        inputSequence: AsyncStream<AnalyzerInput>
    ) async throws {
        try await analyzer.start(inputSequence: inputSequence)
    }

    private func appendFinalizedSegment(_ text: String) {
        guard !text.isEmpty else { return }
        finalizedText = Self.mergeTranscriptFragments(finalizedText, text)
    }

    private func composedTranscript(includeVolatile: Bool) -> String {
        Self.composeTranscript(
            finalizedText: finalizedText,
            volatileText: volatileText,
            includeVolatile: includeVolatile
        )
    }

    static func makeStopResult(
        finalizedText: String,
        volatileText: String,
        stopMarkedAsFailure: Bool = false
    ) -> DictationRecognizerStopResult {
        let finalText = finalizedText.dictationNormalized()
        let fallbackCandidate = Self.composeTranscript(
            finalizedText: finalizedText,
            volatileText: volatileText,
            includeVolatile: true
        ).dictationNormalized()
        let fallbackText = fallbackCandidate == finalText ? nil : fallbackCandidate
        return DictationRecognizerStopResult(
            finalText: finalText,
            fallbackText: fallbackText,
            stopMarkedAsFailure: stopMarkedAsFailure
        )
    }

    static func stopListeningPath(
        hasActiveAudioPipeline: Bool,
        resultsTaskCompleted: Bool
    ) -> StopListeningPath {
        guard hasActiveAudioPipeline else { return .startupDidNotReachActivePipeline }
        if resultsTaskCompleted {
            return .completedResultsReadyForImmediateDelivery
        }
        return .finalizePendingAudio
    }

    private func currentStopResult() -> DictationRecognizerStopResult {
        Self.makeStopResult(
            finalizedText: finalizedText,
            volatileText: volatileText,
            stopMarkedAsFailure: stopMarkedAsFailure
        )
    }

    @MainActor
    private func deliverFinalResult() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil

        let stopResult = currentStopResult()
        reset()
        scheduleWarmStartIfPossible()
        completion(stopResult)
    }

    private func reset() {
        isStopping = false
        resultsTaskCompleted = false
        stopCompletion = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        finalizeTaskToken = nil
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        finalizedText = ""
        volatileText = ""
        analyzeTask?.cancel()
        resultsTask?.cancel()
        analyzeTask = nil
        resultsTask = nil
        audioTap.teardown()
        audioTap.clear()
        analyzer = nil
        audioContinuation = nil
        onReady = nil
        onAudioLevel = nil
        onPartialResult = nil
        onError = nil
        reportedError = false
        stopMarkedAsFailure = false
    }

    @MainActor
    private func notifyReadyIfNeeded() {
        onReady?()
        onReady = nil
    }

    private func reportError(_ error: DictationRecognizer.RecognizerError) {
        guard !reportedError else { return }
        reportedError = true
        print("SpeechAnalyzerRecognizer: \(error.message)")
        onError?(error)
    }

    private func reportAudioConversionFailure() {
        guard !isStopping else { return }
        reportError(.taskFailed)
    }

    nonisolated static func didAudioConversionFail(
        status: AVAudioConverterOutputStatus
    ) -> Bool {
        status == .error
    }

    private static func refreshSupportedLocaleCacheIfNeeded(force: Bool = false) {
        let shouldRefresh = localeSupportCache.beginRefreshIfNeeded(force: force)
        guard shouldRefresh else { return }

        Task.detached(priority: .utility) {
            let locales = await DictationTranscriber.supportedLocales
            let normalized = Set(locales.map { normalizedLocaleIdentifier($0.identifier) })
            localeSupportCache.finishRefresh(with: normalized)
        }
    }

    private static func cachedLocaleSupport(for normalizedIdentifier: String) -> Bool? {
        localeSupportCache.cachedLocaleSupport(for: normalizedIdentifier)
    }

    private static func composeTranscript(
        finalizedText: String,
        volatileText: String,
        includeVolatile: Bool
    ) -> String {
        let finalized = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard includeVolatile else {
            return finalized
        }

        let volatile = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if volatile.isEmpty {
            return finalized
        }
        return mergeTranscriptFragments(finalized, volatile)
    }

    static func shouldSurfaceResultStreamError(
        isTaskCancelled: Bool,
        isStopping: Bool
    ) -> Bool {
        !isTaskCancelled && !isStopping
    }

    private static func makeAnalysisContext() -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = DictationRecognitionContext.contextualPhrases
        return context
    }

    static func mergeTranscriptFragments(_ leading: String, _ trailing: String) -> String {
        let left = leading.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = trailing.trimmingCharacters(in: .whitespacesAndNewlines)

        if left.isEmpty {
            return right
        }
        if right.isEmpty {
            return left
        }
        if shouldInsertSpaceBetweenTranscriptFragments(left: left, right: right) {
            return left + " " + right
        }
        return left + right
    }

    private static let noLeadingSpaceCharacters = CharacterSet(charactersIn: ".,!?;:%)]}\"'”’")
    private static let noTrailingSpaceCharacters = CharacterSet(charactersIn: "([{/\\\"“‘")

    private static func shouldInsertSpaceBetweenTranscriptFragments(
        left: String,
        right: String
    ) -> Bool {
        guard let leftScalar = left.unicodeScalars.last,
              let rightScalar = right.unicodeScalars.first else {
            return false
        }

        if CharacterSet.whitespacesAndNewlines.contains(leftScalar)
            || CharacterSet.whitespacesAndNewlines.contains(rightScalar) {
            return false
        }

        if noLeadingSpaceCharacters.contains(rightScalar) {
            return false
        }

        if noTrailingSpaceCharacters.contains(leftScalar) {
            return false
        }

        if shouldAvoidInsertedSpaceForCJKLikeScripts(
            leftScalar: leftScalar,
            rightScalar: rightScalar
        ) {
            return false
        }

        return true
    }

    private static func shouldAvoidInsertedSpaceForCJKLikeScripts(
        leftScalar: Unicode.Scalar,
        rightScalar: Unicode.Scalar
    ) -> Bool {
        isCJKLikeScalar(leftScalar) || isCJKLikeScalar(rightScalar)
    }

    private static func isCJKLikeScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2EFF,   // CJK Radicals Supplement
             0x2F00...0x2FDF,   // Kangxi Radicals
             0x3000...0x303F,   // CJK Symbols and Punctuation
             0x3040...0x309F,   // Hiragana
             0x30A0...0x30FF,   // Katakana
             0x31F0...0x31FF,   // Katakana Phonetic Extensions
             0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0xFF00...0xFFEF:   // Halfwidth and Fullwidth Forms
            return true
        default:
            return false
        }
    }
}

#endif // os(macOS)
