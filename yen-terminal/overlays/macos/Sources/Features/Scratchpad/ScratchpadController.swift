#if os(macOS)
import Cocoa
import SwiftUI

/// Manages the floating scratchpad editor.
/// Singleton with one app-global text buffer shared across all windows/tabs.
@MainActor
final class ScratchpadController: NSObject, ObservableObject, NSMenuItemValidation, NSWindowDelegate {
    static let shared = ScratchpadController()
    private static let sizeKey = "com.yenchat.yen.scratchpadSize"
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
    var placingPanel = false
    var relativeCenter = CGPoint(x: 0.5, y: 0.5)

    var preferredPanelSize: CGSize? {
        let saved = UserDefaults.standard.dictionary(forKey: Self.sizeKey)
        guard let width = saved?["width"] as? CGFloat, let height = saved?["height"] as? CGFloat,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    func windowDidResize(_ notification: Notification) {
        guard !placingPanel, visible, let panel, notification.object as? NSWindow === panel else { return }
        UserDefaults.standard.set(["width": panel.frame.width, "height": panel.frame.height], forKey: Self.sizeKey)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }
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
            dismiss()
            return
        }

        guard Self.scratchpadEnabled else {
            NSSound.beep()
            DisabledFeatureToast.post(featureName: "Scratchpad")
            return
        }
        visible = false
        present()
    }

    // MARK: - Panel

    // Focus after the hosting view finishes its first layout.
    func registerTextView(_ textView: NSTextView) {
        self.textView = textView
    }

    func ensurePanel() -> ScratchpadPanel {
        if let existing = panel { return existing }
        let panel = ScratchpadPanel()
        let host = NSHostingView(rootView: ScratchpadView(controller: self))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self
        self.panel = panel
        return panel
    }

    func present() {
        guard !visible else { return }
        guard let terminalWindow = activeTerminalWindow() else { return }

        visible = true
        anchorWindow = terminalWindow
        installEscapeMonitor()

        let panel = ensurePanel()
        relativeCenter = CGPoint(x: 0.5, y: 0.5)
        positionPanel(panel, relativeTo: terminalWindow)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        focusTextEditor()
    }

    func dismiss(restoringFocus: Bool = true) {
        guard visible else { return }
        visible = false
        removeEscapeMonitor()
        flushPendingSave()
        panel?.orderOut(nil)
        if restoringFocus, let anchorWindow, anchorWindow.isVisible {
            anchorWindow.makeKeyAndOrderFront(nil)
        }
        anchorWindow = nil
    }

    func focusTextEditor() {
        guard visible, let panel, let textView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }
}
#endif
