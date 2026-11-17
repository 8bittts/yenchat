import Foundation

/// Throttles normalized display text without owning the authoritative transcript.
@MainActor
final class DictationLivePreviewController {
    typealias Schedule = (TimeInterval, DispatchWorkItem) -> Void

    private let minimumInterval: TimeInterval
    private let canRender: () -> Bool
    private let render: (String) -> Void
    private let now: () -> CFAbsoluteTime
    private let schedule: Schedule
    private var lastRenderedAt: CFAbsoluteTime = 0
    private var lastRenderedText: String?
    private var queuedText: String?
    private var queuedWorkItem: DispatchWorkItem?

    init(
        minimumInterval: TimeInterval,
        canRender: @escaping () -> Bool,
        render: @escaping (String) -> Void,
        now: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
        schedule: @escaping Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.minimumInterval = minimumInterval
        self.canRender = canRender
        self.render = render
        self.now = now
        self.schedule = schedule
    }

    func reset() {
        cancelPendingFrame()
        lastRenderedAt = 0
        lastRenderedText = nil
    }

    func cancelPendingFrame() {
        queuedWorkItem?.cancel()
        queuedWorkItem = nil
        queuedText = nil
    }

    /// Callers normalize once before storing or submitting display text.
    func queue(normalizedText: String) {
        guard canRender() else {
            cancelPendingFrame()
            return
        }
        if normalizedText == lastRenderedText {
            cancelPendingFrame()
            return
        }
        guard normalizedText != queuedText else { return }
        let timestamp = now()
        if let delay = Self.delayUntilNextFrame(
            now: timestamp,
            lastRenderedAt: lastRenderedAt,
            minimumInterval: minimumInterval
        ) {
            queuedText = normalizedText
            guard queuedWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.flushPendingFrame()
            }
            queuedWorkItem = work
            schedule(delay, work)
            return
        }
        renderFrame(normalizedText, at: timestamp)
    }

    func renderNow(normalizedText: String) {
        guard canRender() else { return }
        renderFrame(normalizedText, at: now())
    }

    private func flushPendingFrame() {
        queuedWorkItem = nil
        guard let text = queuedText else { return }
        queuedText = nil
        // A deferred frame must recheck the current preference and session state.
        queue(normalizedText: text)
    }

    private func renderFrame(_ text: String, at timestamp: CFAbsoluteTime) {
        cancelPendingFrame()
        guard text != lastRenderedText else { return }
        lastRenderedText = text
        lastRenderedAt = timestamp
        render(text)
    }

    static func delayUntilNextFrame(
        now: CFAbsoluteTime,
        lastRenderedAt: CFAbsoluteTime,
        minimumInterval: TimeInterval
    ) -> TimeInterval? {
        guard lastRenderedAt > 0 else { return nil }
        let elapsed = now - lastRenderedAt
        guard elapsed < minimumInterval else { return nil }
        return max(0, minimumInterval - elapsed)
    }
}
