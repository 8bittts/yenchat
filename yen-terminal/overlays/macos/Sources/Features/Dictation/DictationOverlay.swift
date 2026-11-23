import Cocoa
import SwiftUI

/// Observable bridge so DictationPillView can react to transcript changes
/// without making DictationController an ObservableObject.
final class DictationTextStorage: ObservableObject {
    @Published var text: String = ""
    @Published var audioLevel: Float = 0
}

/// Floating pill overlay that shows live transcription during dictation.
/// Uses NSPanel with `.nonactivatingPanel` so it never steals focus.
final class DictationOverlay {
    private static let horizontalInset: CGFloat = 16
    private static let topInset: CGFloat = 8
    static let maxPreviewWidth: CGFloat = 600
    static let maxPreviewLineCount = 8
    static let maxPreviewCharacterCount = 280
    private var panel: NSPanel?
    private let textStorage = DictationTextStorage()
    private var recenterObservers: [ObserverToken] = []
    private var lastAnnouncementText: String?
    private var lastAnnouncementTime: TimeInterval = 0
#if DEBUG
    var testAnnouncementHandler: ((String) -> Void)?
#endif

    /// Incremented on every show() so a stale hide() completion becomes a no-op.
    private var showGeneration = 0

    enum AnimationPhase {
        case show
        case hide
    }

    struct PanelBehavior {
        let styleMask: NSWindow.StyleMask
        let collectionBehavior: NSWindow.CollectionBehavior
        let isFloatingPanel: Bool
        let level: NSWindow.Level
        let ignoresMouseEvents: Bool
        let backgroundColor: NSColor
        let isOpaque: Bool
        let hasShadow: Bool
        let isReleasedWhenClosed: Bool
    }

    struct ScreenPlacement: Equatable {
        let frame: NSRect
    }

    struct Presentation: Equatable {
        let eyebrowText: String?
        let bodyText: String
    }

    struct AccessibilityPresentation: Equatable {
        let label: String
        let value: String
    }

    private struct ObserverToken {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    init() {
        configureRecenterObservers()
    }

    deinit {
        recenterObservers.forEach { $0.center.removeObserver($0.token) }
    }

    /// Show the overlay pill at the top-center of the screen.
    func show() {
        showGeneration += 1
        textStorage.text = ""
        textStorage.audioLevel = 0
        lastAnnouncementText = nil
        lastAnnouncementTime = 0

        let panel = getOrCreatePanel()
        panel.alphaValue = 0
        centerPanel(panel)
        panel.orderFrontRegardless()

        let fadeInDuration = Self.animationDuration(
            reduceMotionEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            phase: .show
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Update the displayed transcript and re-center (width changes as text grows).
    func update(text: String, announceTranscript: Bool = false) {
        textStorage.text = text
        if !Self.shouldShowAudioMeter(for: text) {
            textStorage.audioLevel = 0
        }
        if announceTranscript {
            announceTranscriptIfNeeded(text)
        }
        if let panel = panel {
            // Allow SwiftUI to lay out before re-centering
            DispatchQueue.main.async {
                self.centerPanel(panel)
            }
        }
    }

    func updateAudioLevel(_ level: Float) {
        textStorage.audioLevel = Self.clampedAudioLevel(level)
    }

    var testingAudioLevel: Float {
        textStorage.audioLevel
    }

    private func announceTranscriptIfNeeded(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = ProcessInfo.processInfo.systemUptime
        guard Self.shouldAnnounceTranscript(
            text: normalized,
            previousText: lastAnnouncementText,
            elapsed: now - lastAnnouncementTime
        ) else { return }
        lastAnnouncementText = normalized
        lastAnnouncementTime = now
#if DEBUG
        testAnnouncementHandler?(normalized)
#endif
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: normalized,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    static func shouldAnnounceTranscript(
        text: String,
        previousText: String?,
        elapsed: TimeInterval
    ) -> Bool {
        text.count >= 3 && text != previousText && elapsed >= 2
    }

    /// Fade out and dismiss the overlay.
    func hide() {
        guard let panel = panel else { return }
        let generation = showGeneration
        let fadeOutDuration = Self.animationDuration(
            reduceMotionEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            phase: .hide
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeOutDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Skip orderOut if show() was called during the fade
            guard let self else { return }
            guard Self.shouldDismissAfterHide(
                completionGeneration: generation,
                currentGeneration: self.showGeneration
            ) else { return }
            panel.orderOut(nil)
        })
    }

    // MARK: - Private

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let pillView = DictationPillView(textStorage: textStorage)
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let behavior = Self.panelBehavior()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: behavior.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = behavior.isFloatingPanel
        panel.level = behavior.level
        panel.ignoresMouseEvents = behavior.ignoresMouseEvents
        panel.backgroundColor = behavior.backgroundColor
        panel.isOpaque = behavior.isOpaque
        panel.hasShadow = behavior.hasShadow
        panel.collectionBehavior = behavior.collectionBehavior
        panel.isReleasedWhenClosed = behavior.isReleasedWhenClosed

        panel.contentView = hostingView

        self.panel = panel
        return panel
    }

    /// Center the panel horizontally, pinned 8px below the top of the visible frame.
    /// Find the screen containing the mouse cursor (where the user is interacting).
    private func screenForOverlay() -> NSScreen? {
        let screens = NSScreen.screens
        let placements = screens.map {
            ScreenPlacement(frame: $0.frame)
        }
        let mainScreenIndex = NSScreen.main.flatMap { mainScreen in
            screens.firstIndex(where: { $0 == mainScreen })
        }
        guard let index = Self.preferredScreenIndex(
            mouseLocation: NSEvent.mouseLocation,
            screens: placements,
            mainScreenIndex: mainScreenIndex
        ) else { return nil }
        return screens[index]
    }

    /// Last frame applied by `centerPanel`, used to skip redundant `setFrame(display:)`
    /// redraws when a transcript update doesn't change the fitting size.
    private var lastCenteredFrame: NSRect?

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = screenForOverlay() else { return }

        // Let the hosting view size itself to fit the SwiftUI content
        panel.contentView?.layoutSubtreeIfNeeded()
        let contentSize = panel.contentView?.fittingSize ?? NSSize(width: 200, height: 40)
        let frame = Self.overlayFrame(
            contentSize: contentSize,
            visibleFrame: screen.visibleFrame
        )

        guard Self.shouldApplyCenteredFrame(
            currentPanelFrame: panel.frame,
            lastCenteredFrame: lastCenteredFrame,
            computedFrame: frame
        ) else { return }
        lastCenteredFrame = frame
        panel.setFrame(frame, display: true)
    }

    static func shouldApplyCenteredFrame(
        currentPanelFrame: NSRect,
        lastCenteredFrame: NSRect?,
        computedFrame: NSRect
    ) -> Bool {
        currentPanelFrame != computedFrame || lastCenteredFrame != computedFrame
    }

    private func configureRecenterObservers() {
        let screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recenterVisiblePanelIfNeeded()
        }
        recenterObservers.append(
            ObserverToken(center: .default, token: screenParametersObserver)
        )

        let activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recenterVisiblePanelIfNeeded()
        }
        recenterObservers.append(
            ObserverToken(center: NSWorkspace.shared.notificationCenter, token: activeSpaceObserver)
        )
    }

    private func recenterVisiblePanelIfNeeded() {
        guard let panel, panel.isVisible else { return }
        centerPanel(panel)
        panel.orderFrontRegardless()
    }

    static func overlayFrame(
        contentSize: NSSize,
        visibleFrame: NSRect,
        horizontalInset: CGFloat = DictationOverlay.horizontalInset,
        topInset: CGFloat = DictationOverlay.topInset
    ) -> NSRect {
        let safeHorizontalInset = max(0, horizontalInset)
        let safeTopInset = max(0, topInset)
        let maxWidth = max(0, visibleFrame.width - (safeHorizontalInset * 2))
        let width = min(contentSize.width, maxWidth)
        let height = min(contentSize.height, max(0, visibleFrame.height - safeTopInset))

        let centeredX = visibleFrame.midX - width / 2
        let minX = visibleFrame.minX + safeHorizontalInset
        let maxX = visibleFrame.maxX - safeHorizontalInset - width
        let x = min(max(centeredX, minX), maxX)
        let y = max(visibleFrame.minY, visibleFrame.maxY - safeTopInset - height)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func preferredScreenIndex(
        mouseLocation: NSPoint,
        screens: [ScreenPlacement],
        mainScreenIndex: Int?
    ) -> Int? {
        screens.firstIndex { NSMouseInRect(mouseLocation, $0.frame, false) } ?? mainScreenIndex
    }

    static func animationDuration(
        reduceMotionEnabled: Bool,
        phase: AnimationPhase
    ) -> TimeInterval {
        guard !reduceMotionEnabled else { return 0 }
        switch phase {
        case .show, .hide:
            return YENMotion.standard
        }
    }

    static func shouldUseOpaqueBackground(
        reduceTransparencyEnabled: Bool,
        workspaceReduceTransparencyEnabled: Bool
    ) -> Bool {
        reduceTransparencyEnabled || workspaceReduceTransparencyEnabled
    }

    static func shouldDismissAfterHide(
        completionGeneration: Int,
        currentGeneration: Int
    ) -> Bool {
        completionGeneration == currentGeneration
    }

    static func panelBehavior() -> PanelBehavior {
        PanelBehavior(
            styleMask: [.borderless, .nonactivatingPanel],
            collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary],
            isFloatingPanel: true,
            level: .statusBar,
            ignoresMouseEvents: true,
            backgroundColor: .clear,
            isOpaque: false,
            hasShadow: false,
            isReleasedWhenClosed: false
        )
    }

    static func recenterNotificationNames() -> [NSNotification.Name] {
        [
            NSApplication.didChangeScreenParametersNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
    }

    static func presentation(for rawText: String) -> Presentation {
        let resolvedText = rawText.isEmpty ? DictationCopy.overlayListeningLine : rawText
        guard !isStatusText(resolvedText) else {
            return Presentation(eyebrowText: nil, bodyText: resolvedText)
        }

        return Presentation(
            eyebrowText: "Live Transcript Preview",
            bodyText: previewTailText(resolvedText)
        )
    }

    static func shouldShowAudioMeter(for rawText: String) -> Bool {
        let resolvedText = rawText.isEmpty ? DictationCopy.overlayListeningLine : rawText
        return ![
            DictationCopy.overlayProcessingLine,
            DictationCopy.pausedAttemptOverlayLine,
        ].contains(resolvedText)
    }

    static func clampedAudioLevel(_ level: Float) -> Float {
        min(max(level.isFinite ? level : 0, 0), 1)
    }

    static func accessibilityPresentation(
        for presentation: Presentation
    ) -> AccessibilityPresentation {
        let value: String
        if let eyebrowText = presentation.eyebrowText {
            value = "\(eyebrowText): \(presentation.bodyText)"
        } else {
            value = presentation.bodyText
        }

        return AccessibilityPresentation(label: "Dictation", value: value)
    }

    static func previewTailText(
        _ text: String,
        maximumCharacters: Int = DictationOverlay.maxPreviewCharacterCount
    ) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximumCharacters else { return normalized }

        let clippedStart = normalized.index(
            normalized.endIndex,
            offsetBy: -maximumCharacters
        )
        var clipped = String(normalized[clippedStart...])
        if let firstBoundary = clipped.firstIndex(where: \.isWhitespace) {
            let nextIndex = clipped.index(after: firstBoundary)
            if nextIndex < clipped.endIndex {
                clipped = String(clipped[nextIndex...])
            }
        }

        return "…" + clipped
    }

    private static func isStatusText(_ text: String) -> Bool {
        [
            DictationCopy.overlayListeningLine,
            DictationCopy.overlayProcessingLine,
            DictationCopy.pausedAttemptOverlayLine,
        ].contains(text)
    }
}

// MARK: - SwiftUI Pill View

private struct DictationPillView: View {
    @ObservedObject var textStorage: DictationTextStorage
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var presentation: DictationOverlay.Presentation {
        DictationOverlay.presentation(for: textStorage.text)
    }

    private var shouldUseOpaqueBackground: Bool {
        DictationOverlay.shouldUseOpaqueBackground(
            reduceTransparencyEnabled: reduceTransparency,
            workspaceReduceTransparencyEnabled: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    var body: some View {
        let presentation = presentation
        let accessibility = DictationOverlay.accessibilityPresentation(for: presentation)
        HStack(alignment: .center, spacing: 10) {
            if DictationOverlay.shouldShowAudioMeter(for: textStorage.text) {
                DictationAudioLevelView(level: textStorage.audioLevel)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundColor(.overlayAccent)
                    .font(YENTypography.body.weight(.medium))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: presentation.eyebrowText == nil ? 0 : 4) {
                if let eyebrowText = presentation.eyebrowText {
                    Text(verbatim: eyebrowText)
                        .font(YENTypography.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(verbatim: presentation.bodyText)
                    .font(YENTypography.body.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(DictationOverlay.maxPreviewLineCount)
                    .truncationMode(.tail)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: DictationOverlay.maxPreviewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    shouldUseOpaqueBackground
                        ? AnyShapeStyle(Color(NSColor.windowBackgroundColor))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.overlayAccent.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibility.label))
        .accessibilityValue(Text(verbatim: accessibility.value))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct DictationAudioLevelView: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let meterWidth: CGFloat = 64
    static let meterHeight: CGFloat = 28
    static let waveCount = 4
    static let minimumAmplitude: CGFloat = 1.5
    static let responsiveAmplitude: CGFloat = 9
    private static let sampleCount = 48
    private static let spectrum = Gradient(colors: [
        .cyan,
        .blue,
        .purple,
        .pink,
        .orange,
        .yellow,
    ])

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2.2
                let amplitude = Self.minimumAmplitude
                    + (Self.responsiveAmplitude * CGFloat(level))
                let centerY = size.height / 2
                let start = CGPoint(x: 0, y: centerY)
                let end = CGPoint(x: size.width, y: centerY)

                for waveIndex in 0..<Self.waveCount {
                    var path = Path()
                    let layer = CGFloat(waveIndex)
                    let layerScale = 1 - (layer * 0.13)
                    let layerPhase = phase + (Double(waveIndex) * 0.72)

                    for sample in 0...Self.sampleCount {
                        let progress = CGFloat(sample) / CGFloat(Self.sampleCount)
                        let x = progress * size.width
                        let envelope = 0.28 + (0.72 * sin(.pi * progress))
                        let primary = sin((progress * .pi * 3.2) + layerPhase)
                        let detail = sin((progress * .pi * 6.4) - (layerPhase * 0.55)) * 0.22
                        let y = centerY + ((primary + detail) * amplitude * envelope * layerScale)

                        if sample == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    context.stroke(
                        path,
                        with: .linearGradient(Self.spectrum, startPoint: start, endPoint: end),
                        lineWidth: waveIndex == 0 ? 1.5 : 1
                    )
                }
            }
            .shadow(color: .cyan.opacity(0.55), radius: 3)
        }
        .frame(width: Self.meterWidth, height: Self.meterHeight)
        .clipped()
    }
}
