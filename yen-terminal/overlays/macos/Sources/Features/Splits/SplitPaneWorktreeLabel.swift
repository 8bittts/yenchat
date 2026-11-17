// Worktree-derived split pane labels.
//
// When "Name Panes After Worktree" is on, a split pane whose working directory sits inside a
// git worktree labels itself after that worktree instead of the surface title. The value slots
// BELOW a hand-typed label in `SplitPaneLabelRules.displayTitle`, so renaming a pane still wins
// and clearing the label hands the pane back to automatic naming.
//
// Resolution is cached per directory and runs git off the main actor through the same read-only,
// timeout-bounded client the git drawer uses. Every directory a visible label shows is polled, so
// a branch switch or a removed worktree reaches the pill without waiting for an unrelated redraw.
#if os(macOS)
import Combine
import Foundation

/// Pure naming rules. Kept free of git and AppKit so the label text is testable on its own.
enum SplitPaneWorktreeLabelRules {
    /// Directory names that describe a worktree's role rather than its work. `git worktree add`
    /// accepts any path, and a scratch `wt` or `tmp` directory tells the reader nothing, so the
    /// branch is the better label there.
    static let uninformativeDirectoryNames: Set<String> = [
        "checkout",
        "clone",
        "code",
        "repo",
        "repos",
        "src",
        "temp",
        "tmp",
        "work",
        "worktree",
        "worktrees",
        "wt",
    ]

    /// A leaf is informative when it names the work. Dot-directories, path separators, and the
    /// generic names above are not.
    static func isInformativeDirectoryName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/", !trimmed.hasPrefix(".") else { return false }
        return !uninformativeDirectoryNames.contains(trimmed.lowercased())
    }

    /// Worktree folder name, with the branch as the fallback when the folder name says nothing.
    ///
    /// A bare repository reports no worktree root, so it labels from the branch. When neither
    /// source is usable the caller gets `nil` and the pane keeps its existing fallback chain.
    static func label(worktreeRoot: String?, branch: String?) -> String? {
        let normalizedBranch = normalized(branch)
        guard let root = normalized(worktreeRoot) else { return normalizedBranch }

        let leaf = URL(fileURLWithPath: root).lastPathComponent
        if isInformativeDirectoryName(leaf) {
            return leaf
        }
        return normalizedBranch ?? normalized(leaf)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// What git reported for one working directory.
struct SplitPaneWorktreeContext: Equatable, Sendable {
    let root: String?
    let branch: String?

    var label: String? {
        SplitPaneWorktreeLabelRules.label(worktreeRoot: root, branch: branch)
    }
}

enum SplitPaneWorktreeLabelResolver {
    /// Read only the root when its folder already supplies the label.
    /// Generic folders and bare repositories also need a branch read.
    static func resolve<Runner: GitDrawerCommandRunning>(
        workingDirectory: String,
        runner: Runner
    ) async -> SplitPaneWorktreeContext? {
        let root = await optionalLine(["rev-parse", "--show-toplevel"], in: workingDirectory, runner: runner)
        if root == nil {
            let gitDirectory = await optionalLine(
                ["rev-parse", "--git-dir"],
                in: workingDirectory,
                runner: runner
            )
            guard gitDirectory != nil else { return nil }
        }

        if let root, SplitPaneWorktreeLabelRules.isInformativeDirectoryName(
            URL(fileURLWithPath: root).lastPathComponent) {
            return SplitPaneWorktreeContext(root: root, branch: nil)
        }

        let branch = await GitBranchResolver.resolve(in: workingDirectory, runner: runner)
        guard root != nil || branch != nil else { return nil }
        return SplitPaneWorktreeContext(root: root, branch: branch)
    }

    private static func optionalLine<Runner: GitDrawerCommandRunning>(
        _ arguments: [String],
        in workingDirectory: String,
        runner: Runner
    ) async -> String? {
        do {
            let output = try await runner.run(
                GitDrawerGitCommand(arguments: arguments),
                currentDirectory: workingDirectory,
                timeout: GitDrawerShellClient.defaultTimeout,
                stdoutLimit: 8 * 1024,
                stderrLimit: 4 * 1024
            )
            let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}

/// Per-directory cache of worktree labels, refreshed off the main actor.
///
/// A pane that changes directory reads a different cache key, so a `cd` refreshes immediately.
/// A pane that stays put cannot rely on reads: SwiftUI only re-reads the label when something
/// else redraws the pill, and an idle pane never does. Visible labels therefore `watch` their
/// directory, and one poll loop re-resolves every watched directory each `refreshInterval`.
@MainActor
final class SplitPaneWorktreeLabelStore: ObservableObject {
    static let shared = SplitPaneWorktreeLabelStore()

    private struct PathEntry {
        let directory: String?
        let refreshedAt: Date
    }

    private struct CacheEntry {
        let label: String?
        let refreshedAt: Date
    }

    /// Bumped whenever a resolution changes a label, so observing labels recompute.
    @Published private(set) var revision: Int = 0

    private let refreshInterval: TimeInterval
    private let maximumEntries: Int
    private let normalizePath: @MainActor (String?) -> String?
    private let now: @MainActor () -> Date
    private var paths: [String: PathEntry] = [:]
    private let resolve: @Sendable (String) async -> SplitPaneWorktreeContext?

    private var entries: [String: CacheEntry] = [:]
    private var inFlight: Set<String> = []
    /// How many visible labels show each directory. Two panes in one directory share one poll.
    private var watcherCounts: [String: Int] = [:]
    private var pollTask: Task<Void, Never>?

    /// True while at least one visible label is watching a directory.
    var isPolling: Bool {
        pollTask != nil
    }

    init(
        refreshInterval: TimeInterval = 5,
        maximumEntries: Int = 128,
        now: @escaping @MainActor () -> Date = { Date() },
        normalizePath: @escaping @MainActor (String?) -> String? = { TabSidebarController.trustedWorkingDirectory(from: $0) },
        resolve: @escaping @Sendable (String) async -> SplitPaneWorktreeContext? = { directory in
            await SplitPaneWorktreeLabelResolver.resolve(
                workingDirectory: directory,
                runner: GitDrawerShellClient()
            )
        }
    ) {
        self.refreshInterval = refreshInterval
        self.maximumEntries = maximumEntries
        self.normalizePath = normalizePath
        self.now = now
        self.resolve = resolve
    }

    /// Cached label for a pane's working directory, scheduling a refresh when it is missing or
    /// stale. Returns nil until the first resolution lands, so the pane shows its usual fallback
    /// rather than flickering through a placeholder.
    ///
    /// A watched directory is refreshed by the poll alone. A pane running an agent redraws many
    /// times a second, and a read-triggered refresh on top of the poll would double its git calls.
    func label(forWorkingDirectory rawPath: String?) -> String? {
        guard let directory = cachedDirectory(rawPath) else {
            return nil
        }

        if let cached = entries[directory],
           watcherCounts[directory] != nil
            || Date().timeIntervalSince(cached.refreshedAt) < refreshInterval {
            return cached.label
        }

        refresh(directory)
        return entries[directory]?.label
    }

    /// Rendering and watcher setup share bounded normalization, including missing paths.
    private func cachedDirectory(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let referenceDate = now()
        if let cached = paths[rawPath], referenceDate.timeIntervalSince(cached.refreshedAt) < refreshInterval {
            return cached.directory
        }
        let directory = normalizePath(rawPath)
        paths[rawPath] = PathEntry(directory: directory, refreshedAt: referenceDate)
        let retained = TabSidebarGitContextCachePolicy.retainedKeys(
            refreshDates: paths.mapValues(\.refreshedAt), referenceDate: referenceDate,
            refreshInterval: refreshInterval, maximumEntries: maximumEntries)
        paths = paths.filter { retained.contains($0.key) }
        return directory
    }

    /// Keeps `rawPath` polled until the calling task is cancelled.
    ///
    /// A label view runs this from `.task(id:)`, which SwiftUI cancels when the pill leaves the
    /// screen, the pane changes directory, or worktree naming turns off. Git therefore only runs
    /// for directories a visible label shows, and polling stops with the last one.
    func watch(workingDirectory rawPath: String?) async {
        guard let directory = cachedDirectory(rawPath) else {
            return
        }

        startWatching(directory)
        defer { stopWatching(directory) }

        // Park until cancelled. A cancelled sleep throws at once, so teardown is not delayed.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    /// Re-resolves every watched directory. `store` only bumps `revision` when a label changes,
    /// so a quiet poll costs git calls but never a redraw.
    func pollWatchedDirectories() {
        for directory in watcherCounts.keys {
            refresh(directory)
        }
    }

    private func startWatching(_ directory: String) {
        watcherCounts[directory, default: 0] += 1
        guard pollTask == nil else { return }

        let interval = Duration.seconds(refreshInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: interval / 5)
                guard !Task.isCancelled else { return }
                self?.pollWatchedDirectories()
            }
        }
    }

    private func stopWatching(_ directory: String) {
        guard let count = watcherCounts[directory] else { return }
        watcherCounts[directory] = count > 1 ? count - 1 : nil
        guard watcherCounts.isEmpty else { return }

        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh(_ directory: String) {
        guard !inFlight.contains(directory) else { return }
        inFlight.insert(directory)

        let resolve = resolve
        Task { [weak self] in
            let context = await resolve(directory)
            await MainActor.run {
                self?.store(context?.label, for: directory)
            }
        }
    }

    private func store(_ label: String?, for directory: String) {
        inFlight.remove(directory)
        let previous = entries[directory]?.label
        entries[directory] = CacheEntry(label: label, refreshedAt: Date())
        prune()
        guard previous != label || revision == 0 else { return }
        revision &+= 1
    }

    private func prune() {
        let retained = TabSidebarGitContextCachePolicy.retainedKeys(
            refreshDates: entries.mapValues(\.refreshedAt),
            referenceDate: Date(),
            refreshInterval: refreshInterval,
            maximumEntries: maximumEntries
        )
        entries = entries.filter { retained.contains($0.key) }
    }
}
#endif
