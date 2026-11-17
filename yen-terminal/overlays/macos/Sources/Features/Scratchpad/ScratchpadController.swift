#if os(macOS)
import Cocoa
import SwiftUI

/// Manages the right-side scratchpad panel.
/// Singleton with one app-global text buffer shared across all windows/tabs.
@MainActor
final class ScratchpadController: NSObject, ObservableObject, NSMenuItemValidation {
    static let shared = ScratchpadController()
    static let panelWidth: CGFloat = 360
    nonisolated static let scratchpadEnabledPreferenceKey = "com.yenchat.yen.scratchpadEnabled"

    @Published var text: String = "" {
        didSet {
            guard !isLoadingPersistedText else { return }
            scheduleSave()
        }
    }

    // Internal setter so tests can stage the first-open state without a terminal window.
    var visible: Bool = false

    // Extension-owned state. These stay internal only because the Scratchpad
    // controller is split across feature-local extension files.
    let storage: ScratchpadStorage
    var panel: ScratchpadPanel?
    var revealView: EdgeRevealView? { panel?.contentView as? EdgeRevealView }
    weak var textView: NSTextView?
    weak var anchorWindow: NSWindow?
    private var hasSetup = false
    var escapeMonitor: Any?
    var saveWorkItem: DispatchWorkItem?
    var isLoadingPersistedText = false
    var preserveExistingFileUntilEdit = false
    let persistenceQueue = DispatchQueue(
        label: "com.yenchat.yen.scratchpad-persistence",
        qos: .utility
    )

    private override init() {
        storage = .defaultStorage()
        super.init()
    }

    init(storage: ScratchpadStorage) {
        self.storage = storage
        super.init()
    }

    nonisolated static var scratchpadEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: scratchpadEnabledPreferenceKey) == nil {
            return true
        }
        return defaults.bool(forKey: scratchpadEnabledPreferenceKey)
    }

    nonisolated static func animationDuration(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) -> TimeInterval {
        SlidingUtilityPanel.animationDuration(reduceMotion: reduceMotion)
    }

    deinit {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    func setup() {
        guard !hasSetup else { return }
        hasSetup = true
        UserDefaults.standard.register(defaults: [Self.scratchpadEnabledPreferenceKey: true])

        loadPersistedText()

        installScratchpadMenuItem()
        registerScratchpadObservers()
    }

    func toggle() {
        if visible, panel?.isVisible != false {
            animateOut()
            return
        }

        guard Self.scratchpadEnabled else {
            NSSound.beep()
            DisabledFeatureToast.post(featureName: "Scratchpad")
            return
        }
        visible = false
        animateIn()
    }

    // MARK: - Panel

    /// Stores the editor only. SwiftUI calls this from `makeNSView` during the panel's
    /// first layout, which `EdgeRevealView.park()` forces synchronously; changing key
    /// window or first responder there re-enters that layout and AttributeGraph aborts
    /// the process. The reveal completion and re-anchor paths own focus.
    func registerTextView(_ textView: NSTextView) {
        self.textView = textView
    }

    func ensurePanel() -> ScratchpadPanel {
        if let existing = panel { return existing }
        let panel = ScratchpadPanel()
        let reveal = EdgeRevealView(edge: .trailing)
        reveal.embed(
            NSHostingView(rootView: ScratchpadView(controller: self)),
            extent: Self.panelWidth
        )
        panel.contentView = reveal
        self.panel = panel
        return panel
    }

    func animateIn() {
        guard !visible else { return }
        guard let terminalWindow = activeTerminalWindow() else { return }

        visible = true
        anchorWindow = terminalWindow
        installEscapeMonitor()

        let panel = ensurePanel()
        guard let reveal = revealView else { return }
        // Quick Terminal's sequence: rest frame, content parked behind the window's
        // right edge at alpha 0, then slide in. Focus only after the reveal completes.
        positionPanel(panel, relativeTo: terminalWindow)
        reveal.park()
        panel.orderFront(nil)
        reveal.slide(
            .entering,
            duration: SlidingUtilityPanel.currentAnimationDuration(),
            completion: { [weak self] in
                guard let self, self.visible else { return }
                self.focusTextEditor()
            }
        )
    }

    func animateOut(restoringFocus: Bool = true) {
        guard visible else { return }
        guard let panel else {
            visible = false
            anchorWindow = nil
            removeEscapeMonitor()
            return
        }

        visible = false
        removeEscapeMonitor()
        flushPendingSave()

        let restoreWindow = anchorWindow ?? activeTerminalWindow()
        guard let terminalWindow = restoreWindow, let reveal = revealView else {
            panel.orderOut(nil)
            anchorWindow = nil
            return
        }

        // Match Quick Terminal: slide back behind the edge, then orderOut synchronously
        // in the exit completion (no Task hop).
        reveal.slide(
            .exiting,
            duration: SlidingUtilityPanel.currentAnimationDuration(),
            completion: { [weak self] in
                guard let self else { return }
                guard !self.visible else { return }
                panel.orderOut(nil)
                if restoringFocus {
                    terminalWindow.makeKeyAndOrderFront(nil)
                }
                self.anchorWindow = nil
            }
        )
    }

    func focusTextEditor() {
        guard visible, let panel, let textView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }
}
#endif
