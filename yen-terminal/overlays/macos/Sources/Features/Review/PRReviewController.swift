#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class PullRequestReviewController: NSWindowController, NSWindowDelegate {
    static let shared = PullRequestReviewController()

    let model: PullRequestReviewModel

    private init() {
        self.model = PullRequestReviewModel()
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
        // Releases the snapshot and diffs; keeps staged drafts and the review note so a
        // reopen restores unsubmitted work. Also covers the two cancels this used to do.
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
        let hostingView = NSHostingView(rootView: PullRequestReviewView(model: model))
        self.window = makeReviewUtilityWindow(
            title: "PR Review",
            contentSize: NSSize(width: 1440, height: 860),
            minSize: NSSize(width: 1180, height: 680),
            contentView: hostingView,
            delegate: self
        )
    }
}

#if DEBUG
extension PullRequestReviewController {
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
        model.cancelSubmission()
        yenReleaseOwnedUtilityWindow()
    }
}
#endif
#endif
