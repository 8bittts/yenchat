import Foundation

/// One parsed runtime config shared by all windows on the main actor.
@MainActor
final class TerminalBackgroundRuntimeConfigCache {
    static let shared = TerminalBackgroundRuntimeConfigCache()

    private struct Entry {
        // Retain the source object so a later generation cannot reuse its identity.
        let sourceConfig: YEN.Config
        let snapshot: TerminalPresentationSettings.Snapshot
        let runtimePath: String
        let useWholeWindowOverride: Bool
        let value: YEN.Config
    }
    private var entry: Entry?

    func resolve(sourceConfig: YEN.Config, snapshot: TerminalPresentationSettings.Snapshot,
                 runtimePath: String, useWholeWindowOverride: Bool,
                 load: () throws -> YEN.Config) rethrows -> YEN.Config {
        if let entry, entry.sourceConfig === sourceConfig, entry.snapshot == snapshot,
           entry.runtimePath == runtimePath, entry.useWholeWindowOverride == useWholeWindowOverride {
            return entry.value
        }
        entry = nil
        let value = try load()
        // Failed loads must be retried after the underlying file or write recovers.
        if value.loaded {
            entry = Entry(sourceConfig: sourceConfig, snapshot: snapshot, runtimePath: runtimePath,
                useWholeWindowOverride: useWholeWindowOverride, value: value)
        }
        return value
    }
}
