#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MergeConflictResolutionController: NSWindowController, NSWindowDelegate {
    static let shared = MergeConflictResolutionController()

    let model: MergeConflictResolutionModel

    private init() {
        self.model = MergeConflictResolutionModel()
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(workingDirectory: String?) {
        ensureWindowAvailable()
        model.prepareForPresentation(workingDirectory: workingDirectory)
        NSApp.unhide(nil)
        NSApp.yenActivateCompat()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        model.requestLoad()
    }

    func hide() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Release the model's retained snapshot + rendered-preview cache on close so
        // the singleton does not hold a repo's conflict data for the process lifetime.
        model.releaseHeldState()
        yenReleaseOwnedUtilityWindow(from: notification)
    }

    private func ensureWindowAvailable() {
        yenDiscardReleasedUtilityWindowIfNeeded()
        if window == nil {
            createWindow()
        }
    }

    private func createWindow() {
        let hostingView = NSHostingView(rootView: MergeConflictResolutionView(model: model))
        self.window = makeReviewUtilityWindow(
            title: "Merge Conflicts",
            contentSize: NSSize(width: 1480, height: 860),
            minSize: NSSize(width: 1220, height: 700),
            contentView: hostingView,
            delegate: self
        )
    }
}

#if DEBUG
extension MergeConflictResolutionController {
    var _testHasWindow: Bool {
        window != nil
    }

    @discardableResult
    func _testEnsureWindow() -> NSWindow? {
        ensureWindowAvailable()
        return window
    }

    func _testResetState() {
        model.cancelLoading()
        model.cancelApplying()
        yenReleaseOwnedUtilityWindow()
    }
}
#endif
#endif
