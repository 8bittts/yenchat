#if os(macOS)
import Foundation
import OSLog

extension ScratchpadController {
    nonisolated private static let scratchpadPersistenceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yenchat.yen",
        category: "ScratchpadController"
    )

    func scheduleSave() {
        preserveExistingFileUntilEdit = false
        saveWorkItem?.cancel()
        let snapshot = text
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persistenceQueue.async { [storage = self.storage] in
                Self.persist(snapshot, to: storage)
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Write any pending edit now.
    ///
    /// `blocking` is only correct when the process is about to exit. Everywhere else
    /// it stalls the main thread on `createDirectory` plus an atomic write — and
    /// `persistenceQueue` is `.utility`, so a main-thread `sync` is also a priority
    /// inversion. The close path pays that cost on every app switch away from YEN,
    /// because `applicationDidResignActive` calls `dismiss`.
    ///
    /// The queue is serial, so the async write still lands in order.
    func flushPendingSave(blocking: Bool = false) {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard !preserveExistingFileUntilEdit else { return }
        let snapshot = text
        if blocking {
            persistenceQueue.sync { [storage] in
                Self.persist(snapshot, to: storage)
            }
        } else {
            persistenceQueue.async { [storage] in
                Self.persist(snapshot, to: storage)
            }
        }
    }

    func loadPersistedText() {
        isLoadingPersistedText = true
        do {
            text = try storage.load()
            preserveExistingFileUntilEdit = false
        } catch {
            preserveExistingFileUntilEdit = true
            Self.scratchpadPersistenceLogger.error(
                "Scratchpad load failed; preserving the existing file: \(error.localizedDescription, privacy: .public)"
            )
        }
        isLoadingPersistedText = false
    }

    nonisolated private static func persist(_ text: String, to storage: ScratchpadStorage) {
        do {
            try storage.save(text)
        } catch {
            scratchpadPersistenceLogger.error(
                "Scratchpad save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
#endif
