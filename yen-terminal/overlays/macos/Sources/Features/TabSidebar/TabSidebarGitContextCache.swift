#if os(macOS)
import Cocoa
import Combine
import SwiftUI

struct TabSidebarGitSnapshot: Equatable, Sendable {
    let branch: String
    let dirty: Bool
    let ahead: Int
    let behind: Int

    var summary: String {
        var parts: [String] = [branch]
        if dirty {
            parts.append("dirty")
        }
        if ahead > 0 {
            parts.append("↑\(ahead)")
        }
        if behind > 0 {
            parts.append("↓\(behind)")
        }
        return parts.joined(separator: " ")
    }
}

/// Pure cache-eviction policy for `TabSidebarGitContextCache`, extracted so the prune/cap logic
/// is unit-testable without the @MainActor singleton.
enum TabSidebarGitContextCachePolicy {
    /// Keys to retain: entries refreshed within 4× the refresh interval, then capped to the
    /// `maximumEntries` most-recently-refreshed.
    static func retainedKeys(
        refreshDates: [String: Date],
        referenceDate: Date,
        refreshInterval: TimeInterval,
        maximumEntries: Int
    ) -> Set<String> {
        let cutoff = referenceDate.addingTimeInterval(-(refreshInterval * 4))
        let fresh = refreshDates.filter { $0.value >= cutoff }
        guard fresh.count > maximumEntries else { return Set(fresh.keys) }
        let newest = fresh.sorted { $0.value > $1.value }.prefix(maximumEntries)
        return Set(newest.map(\.key))
    }
}

@MainActor
enum TabSidebarGitStatusSemantics {
    nonisolated static var trackedOnlyStatusArguments: [String] {
        GitStatusPorcelainV2.arguments + ["--untracked-files=no"]
    }
}

@MainActor
final class TabSidebarGitContextCache {
    static let shared = TabSidebarGitContextCache()

    private struct CacheEntry {
        let snapshot: TabSidebarGitSnapshot?
        let refreshedAt: Date
    }

    private var entries: [String: CacheEntry] = [:]
    private var inFlight: Set<String> = []
    nonisolated static let refreshInterval: TimeInterval = 15
    private let now: @MainActor () -> Date
    private let resolve: @Sendable (String) async -> TabSidebarGitSnapshot?
    private let maximumEntries = 128

    init(
        now: @escaping @MainActor () -> Date = { Date() },
        resolve: @escaping @Sendable (String) async -> TabSidebarGitSnapshot? = { directory in
            await TabSidebarGitSnapshotResolver.resolve(workingDirectory: directory,
                runner: GitDrawerShellClient(disableOptionalLocks: true, terminationGracePeriod: 0.2))
        }
    ) {
        self.now = now
        self.resolve = resolve
    }

    /// Looks up (or kicks off a refresh for) the git snapshot of an already trust-resolved working
    /// directory. The caller must pass a path produced by `TabSidebarController.trustedWorkingDirectory(...)`,
    /// so this does NOT re-run the fileExists/symlink-resolution normalization on every read. Entries are
    /// pruned on every refresh write (see `refresh`), so there is no per-read prune.
    func snapshot(forTrustedDirectory workingDirectory: String?) -> TabSidebarGitSnapshot? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let referenceDate = now()

        if let cached = entries[workingDirectory],
           referenceDate.timeIntervalSince(cached.refreshedAt) < Self.refreshInterval {
            return cached.snapshot
        }

        refresh(for: workingDirectory)
        return entries[workingDirectory]?.snapshot
    }

    private func refresh(for workingDirectory: String) {
        guard !inFlight.contains(workingDirectory) else { return }
        inFlight.insert(workingDirectory)

        Task {
            let snapshot = await resolve(workingDirectory)
            let refreshedAt = now()
            self.entries[workingDirectory] = CacheEntry(snapshot: snapshot, refreshedAt: refreshedAt)
            self.pruneEntries(referenceDate: refreshedAt)
            self.inFlight.remove(workingDirectory)
            NotificationCenter.default.post(name: .yenTabSidebarGitContextDidChange, object: workingDirectory)
        }
    }

    private func pruneEntries(referenceDate: Date) {
        let retained = TabSidebarGitContextCachePolicy.retainedKeys(
            refreshDates: entries.mapValues(\.refreshedAt),
            referenceDate: referenceDate,
            refreshInterval: Self.refreshInterval,
            maximumEntries: maximumEntries
        )
        entries = entries.filter { retained.contains($0.key) }
    }

}

enum TabSidebarGitSnapshotResolver {
    static func resolve<Runner: GitDrawerCommandRunning>(
        workingDirectory: String,
        runner: Runner
    ) async -> TabSidebarGitSnapshot? {
        guard let output = try? await runner.run(
            GitDrawerGitCommand(arguments: TabSidebarGitStatusSemantics.trackedOnlyStatusArguments),
            currentDirectory: workingDirectory, timeout: 2,
            stdoutLimit: GitDrawerShellClient.defaultStdoutLimit,
            stderrLimit: GitDrawerShellClient.defaultStderrLimit),
              !output.wasTruncated, let metadata = GitStatusPorcelainV2(output.stdout) else { return nil }
        let branch = metadata.isDetached
            ? await GitBranchResolver.detached(in: workingDirectory, runner: runner) ?? "detached"
            : metadata.head
        return TabSidebarGitSnapshot(branch: branch, dirty: metadata.dirty,
            ahead: metadata.ahead, behind: metadata.behind)
    }

}
#endif
