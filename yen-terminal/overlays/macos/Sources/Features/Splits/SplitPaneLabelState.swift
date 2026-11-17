import AppKit
import Combine
import ObjectiveC

final class SplitPaneLabelState: ObservableObject {
    @Published private(set) var label: String?
    weak var surfaceView: YEN.SurfaceView?

    init(surfaceView: YEN.SurfaceView, label: String? = nil) {
        self.surfaceView = surfaceView
        self.label = YEN.SurfaceView.normalizedSplitPaneLabel(label)
    }

    func setLabel(_ rawValue: String?, invalidateRestorableState: Bool = true) {
        let normalized = YEN.SurfaceView.normalizedSplitPaneLabel(rawValue)
        guard label != normalized else { return }
        label = normalized

        if invalidateRestorableState {
            NSApp.invalidateRestorableState()
            surfaceView?.window?.invalidateRestorableState()
        }
    }
}

private var splitPaneLabelStateAssociationKey: UInt8 = 0

extension YEN.SurfaceView {
    private var existingSplitPaneLabelState: SplitPaneLabelState? {
        objc_getAssociatedObject(self, &splitPaneLabelStateAssociationKey) as? SplitPaneLabelState
    }

    var splitPaneLabelState: SplitPaneLabelState {
        if let state = existingSplitPaneLabelState {
            if state.surfaceView == nil {
                state.surfaceView = self
            }
            return state
        }

        let state = SplitPaneLabelState(surfaceView: self)
        objc_setAssociatedObject(
            self,
            &splitPaneLabelStateAssociationKey,
            state,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return state
    }

    var splitPaneLabel: String? {
        existingSplitPaneLabelState?.label
    }

    func setSplitPaneLabel(_ label: String?) {
        guard let normalized = Self.normalizedSplitPaneLabel(label) else {
            existingSplitPaneLabelState?.setLabel(nil)
            return
        }

        splitPaneLabelState.setLabel(normalized)
    }

    func restoreSplitPaneLabel(_ label: String?) {
        guard let normalized = Self.normalizedSplitPaneLabel(label) else {
            existingSplitPaneLabelState?.setLabel(nil, invalidateRestorableState: false)
            return
        }

        splitPaneLabelState.setLabel(normalized, invalidateRestorableState: false)
    }

    func promptSplitPaneLabel() {
        let alert = NSAlert()
        alert.messageText = "Change Split Label"
        alert.informativeText = "Leave blank to use the automatic pane label."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        // With worktree naming on, the pill already shows a name; seed the field with it so the
        // rename starts from what the user sees rather than an empty box.
        textField.stringValue = splitPaneLabel ?? automaticSplitPaneLabel() ?? ""
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = textField

        let completionHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.setSplitPaneLabel(textField.stringValue)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }

    /// The worktree-derived name this pane would show, or nil when the setting is off or the
    /// pane is not inside a repository.
    private func automaticSplitPaneLabel() -> String? {
        guard SplitPaneLabelSettings.shared.isWorktreeNamingEnabled else { return nil }
        return SplitPaneWorktreeLabelStore.shared.label(forWorkingDirectory: effectiveWorkingDirectory)
    }

    static func normalizedSplitPaneLabel(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SplitPaneLabelPersistence {
    static func snapshot(for tree: SplitTree<YEN.SurfaceView>) -> [String: String] {
        var result: [String: String] = [:]
        for surfaceView in tree {
            guard let label = surfaceView.splitPaneLabel else { continue }
            result[surfaceView.id.uuidString] = label
        }
        return result
    }

    static func restore(_ snapshot: [String: String], to tree: SplitTree<YEN.SurfaceView>) {
        for surfaceView in tree {
            surfaceView.restoreSplitPaneLabel(snapshot[surfaceView.id.uuidString])
        }
    }
}
