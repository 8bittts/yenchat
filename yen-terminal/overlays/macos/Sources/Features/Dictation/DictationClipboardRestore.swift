import AppKit

struct DictationPasteboardSnapshot {
    private enum Storage {
        case fullItems([NSPasteboardItem])
        case empty
    }

    private let storage: Storage

    static func capture(from pasteboard: NSPasteboard) -> DictationPasteboardSnapshot {
        capture(items: pasteboard.pasteboardItems)
    }

    static func capture(items: [NSPasteboardItem]?) -> DictationPasteboardSnapshot {
        guard let items, !items.isEmpty else {
            return DictationPasteboardSnapshot(storage: .empty)
        }
        var copiedItems: [NSPasteboardItem] = []
        copiedItems.reserveCapacity(items.count)

        for item in items {
            let copy = NSPasteboardItem()
            var copiedTypeCount = 0
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    copiedTypeCount += 1
                    continue
                }

                if let value = item.string(forType: type) {
                    copy.setString(value, forType: type)
                    copiedTypeCount += 1
                    continue
                }

                if let propertyList = item.propertyList(forType: type) {
                    copy.setPropertyList(propertyList, forType: type)
                    copiedTypeCount += 1
                }
            }

            if copiedTypeCount == 0 {
                continue
            }
            copiedItems.append(copy)
        }

        if copiedItems.isEmpty {
            return DictationPasteboardSnapshot(storage: .empty)
        }

        return DictationPasteboardSnapshot(storage: .fullItems(copiedItems))
    }

    func restore(to pasteboard: NSPasteboard) {
        switch storage {
        case .fullItems(let items):
            pasteboard.clearContents()
            if !items.isEmpty {
                _ = pasteboard.writeObjects(items)
            }
        case .empty:
            pasteboard.clearContents()
        }
    }
}

enum DictationClipboardRestorePolicy {
    static func clipboardRestorePlan(
        for strategy: DictationController.PasteInsertionStrategy,
        localDelay: TimeInterval
    ) -> DictationController.ClipboardRestorePlan {
        switch strategy {
        case .responderChain:
            return DictationController.ClipboardRestorePlan(initialDelay: localDelay, deferredDelay: nil)
        case .syntheticCommandV:
            return DictationController.ClipboardRestorePlan(initialDelay: nil, deferredDelay: nil)
        }
    }

    static func shouldRestorePasteboard(
        currentChangeCount: Int,
        expectedChangeCount: Int
    ) -> Bool {
        currentChangeCount == expectedChangeCount
    }
}

@MainActor
final class DictationClipboardRestoreScheduler {
    typealias Action = @MainActor () -> Void
    typealias Schedule = (_ delay: TimeInterval, _ action: @escaping Action) -> Void

    private let schedule: Schedule

    init(schedule: @escaping Schedule = DictationClipboardRestoreScheduler.liveSchedule) {
        self.schedule = schedule
    }

    func scheduleRestore(
        plan: DictationController.ClipboardRestorePlan,
        pasteboard: NSPasteboard,
        previousSnapshot: DictationPasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        guard let initialDelay = plan.initialDelay else { return }
        schedule(initialDelay) {
            guard DictationClipboardRestorePolicy.shouldRestorePasteboard(
                currentChangeCount: pasteboard.changeCount,
                expectedChangeCount: expectedChangeCount
            ) else { return }
            guard let deferredDelay = plan.deferredDelay else {
                previousSnapshot.restore(to: pasteboard)
                return
            }

            self.schedule(deferredDelay) {
                guard DictationClipboardRestorePolicy.shouldRestorePasteboard(
                    currentChangeCount: pasteboard.changeCount,
                    expectedChangeCount: expectedChangeCount
                ) else { return }
                previousSnapshot.restore(to: pasteboard)
            }
        }
    }

    // `nonisolated` so it matches the non-isolated `Schedule` type; the main
    // queue runs the action, so it asserts main-actor isolation synchronously.
    nonisolated private static func liveSchedule(
        delay: TimeInterval,
        action: @escaping Action
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                action()
            }
        }
    }
}
