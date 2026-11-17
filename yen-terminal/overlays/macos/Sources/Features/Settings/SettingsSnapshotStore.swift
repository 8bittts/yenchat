import Foundation

/// Shared scaffolding for the settings-tab snapshot stores. Each store observes
/// one `SettingsController` change notification, recaptures an immutable
/// `Snapshot`, and republishes only when the snapshot changed.
///
/// Change detection is `Snapshot`'s `Equatable`; a field that isn't cheaply or
/// meaningfully equatable (an `NSImage` preview, the raw `[KeybindEntry]` list)
/// is excluded via a custom `==` on the concrete `Snapshot`, mirroring
/// `GeneralSettingsStore.Snapshot.Appearance.PreviewImage`.
///
/// All settings-change notifications are posted on the main actor (they
/// originate from `@MainActor SettingsController` property `didSet` /
/// `loadWorkspacePreferences`), so the observer delivers via
/// `MainActor.assumeIsolated`.
@MainActor
class SettingsSnapshotStore<Snapshot: Equatable>: ObservableObject {
    @Published private(set) var snapshot: Snapshot

    private let makeSnapshot: @MainActor () -> Snapshot
    private var changeObserver: NSObjectProtocol?

    init(
        notification: Notification.Name,
        object: AnyObject?,
        capture: @escaping @MainActor () -> Snapshot
    ) {
        self.makeSnapshot = capture
        self.snapshot = capture()
        changeObserver = NotificationCenter.default.addObserver(
            forName: notification,
            object: object,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshIfNeeded()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    private func refreshIfNeeded() {
        let updatedSnapshot = makeSnapshot()
        guard updatedSnapshot != snapshot else { return }
        snapshot = updatedSnapshot
    }
}
