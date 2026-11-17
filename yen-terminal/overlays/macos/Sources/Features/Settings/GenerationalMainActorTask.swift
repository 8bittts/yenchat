#if os(macOS)
import Foundation

/// A single-slot, generation-guarded `@MainActor` task, extracted from the
/// several near-identical deferred-reload schedulers in `SettingsController`
/// (theme catalog, font catalog, keybind reload). Each scheduler previously
/// carried its own `Task<Void, Never>?` plus a `UInt64` generation counter and
/// repeated the same cancel / bump / `Task.yield()` / re-check bookkeeping.
///
/// `run` cancels any in-flight task, bumps the generation, and starts a fresh
/// task that — after an initial yield — invokes `body` only if it is still the
/// current generation, not cancelled, and `shouldProceed()` holds. `body`
/// receives an `isStillCurrent` probe so bodies with their own suspension points
/// (e.g. the font catalog's detached build) can re-validate before publishing
/// results.
@MainActor
final class GenerationalMainActorTask {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    /// True while a scheduled task has not yet completed or been cancelled.
    var isScheduled: Bool {
        task != nil
    }

    /// Cancel any in-flight task and clear the slot.
    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Cancel any in-flight run, then schedule a new one. After an initial
    /// `Task.yield()`, `body` runs only if this is still the current generation,
    /// the task is not cancelled, and `shouldProceed()` returns true.
    func run(
        shouldProceed: @escaping @MainActor () -> Bool,
        body: @escaping @MainActor (_ isStillCurrent: @escaping @MainActor () -> Bool) async -> Void
    ) {
        task?.cancel()
        generation &+= 1
        let generation = self.generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == generation {
                    self.task = nil
                }
            }
            await Task.yield()
            let isStillCurrent: @MainActor () -> Bool = { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled && self.generation == generation && shouldProceed()
            }
            guard isStillCurrent() else { return }
            await body(isStillCurrent)
        }
    }
}
#endif
