#if os(macOS)
import Foundation

/// Owns the debounced live-preview playback for notification-sound pickers,
///. Rapid selection changes coalesce into a
/// single `playPreview` so popover teardown / arrow-key scrubbing can't stack
/// overlapping plays. This is a preview scheduler only — persistence stays in
/// `NotificationSoundManager`, so it does not become a second sound owner.
@MainActor
final class NotificationSoundPreviewCoordinator {
    private var previewWork: DispatchWorkItem?

    /// True while a debounced preview is still waiting to play.
    var hasPendingPreview: Bool {
        previewWork != nil
    }

    /// Debounce a preview for `name`. `"none"` cancels any pending preview and
    /// stops current playback instead of scheduling.
    func preview(_ name: String, volume: Double) {
        previewWork?.cancel()
        previewWork = nil
        if name == "none" {
            NotificationSoundManager.shared.stopPreview()
            return
        }
        var work: DispatchWorkItem?
        work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer {
                if let work, self.previewWork === work {
                    self.previewWork = nil
                }
            }
            NotificationSoundManager.shared.playPreview(soundName: name, volume: volume)
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work!)
    }

    /// Cancel any pending preview and stop current playback (window close).
    func cancelAndStop() {
        previewWork?.cancel()
        previewWork = nil
        NotificationSoundManager.shared.stopPreview()
    }
}
#endif
