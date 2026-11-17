#if os(macOS)
import AppKit

/// Controller-side surface the theme-preview coordinator drives.
///
/// Implemented by `SettingsController` as thin wrappers so the controller's
/// stored state stays private while the coordinator owns all preview
/// bookkeeping (in-flight debounce, snapshot-of-original config, pending
/// selection). Every member is `@MainActor`-isolated because preview writes
/// config.yen and mutates `@Published` UI state.
@MainActor
protocol ThemePreviewHost: AnyObject {
    var themePreviewConfigPath: String { get }
    var themePreviewSelectedTheme: String { get set }
    var themePreviewOriginalThemeName: String { get set }
    var themePreviewIsCatalogLoading: Bool { get }

    func themePreviewWriteConfig(_ contents: String) throws
    func themePreviewRemoveConfig()
    func themePreviewReloadSilently()
    func themePreviewRefreshSelectedThemeFromConfig()
    func themePreviewShowApplyFailure(_ message: String)
}

/// Owns the theme live-preview lifecycle previously inlined in
/// `SettingsController`: debounce a rapid burst of theme clicks into a single
/// config write + silent reload, auto-commit the last selection, and revert the
/// on-disk config back to its pre-preview snapshot when the window closes
/// without a commit. The pure config-transform helpers stay static on
/// `SettingsController` (and are exercised directly by tests); this type only
/// holds the mutable, per-session preview state and orchestration.
@MainActor
final class ThemePreviewCoordinator {
    private weak var host: ThemePreviewHost?

    /// Snapshot of config.yen taken on the first preview write of a session so
    /// an un-committed preview can be rolled back exactly. `nil` with
    /// `originalConfigWasMissing == false` means no preview is active.
    private var originalConfig: String?
    /// Set when the first preview happened while config.yen did not yet exist,
    /// so revert removes the file instead of restoring stale contents.
    private var originalConfigWasMissing = false
    private var debounceWork: DispatchWorkItem?
    private var debounceGeneration = 0
    private var pendingSelection: ThemeInfo?

    init(host: ThemePreviewHost) {
        self.host = host
    }

    /// True while an un-committed preview is modifying config.yen on disk.
    var isPreviewActive: Bool {
        originalConfig != nil || originalConfigWasMissing
    }

    /// True while a debounced theme selection is still waiting to be written.
    var hasPendingCommit: Bool {
        debounceWork != nil
    }

    // MARK: - Selection

    /// Select a theme and schedule a debounced preview write. Only the last
    /// theme in a rapid burst triggers a config write + silent reload.
    func applyTheme(_ theme: ThemeInfo) {
        guard let host, !host.themePreviewIsCatalogLoading else { return }
        host.themePreviewSelectedTheme = theme.configReference
        pendingSelection = theme

        debounceWork?.cancel()
        debounceGeneration += 1
        let generation = debounceGeneration
        // Capture only a value-type generation token (never the work item itself):
        // capturing the local `work` box strong-referenced the DispatchWorkItem that
        // owns the block, forming an item -> block -> box -> item cycle that leaked one
        // work item + closure per superseded/fired preview during theme browsing.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.debounceGeneration == generation else { return }
            self.debounceWork = nil
            self.restorePendingSelection()
            self.performPreviewWriteAndAutoCommit()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Flush a debounced-but-not-yet-written selection immediately (deep-link
    /// reopen, window close). No-op when nothing is pending.
    func commitPendingIfNeeded() {
        guard debounceWork != nil else { return }
        debounceWork?.cancel()
        debounceWork = nil
        debounceGeneration += 1
        restorePendingSelection()
        performPreviewWriteAndAutoCommit()
    }

    /// Put the clicked theme back on the host before it is written, then clear it.
    ///
    /// The click is the latest intent, but the write reads the host's selection
    /// when the debounce ends. A config reload inside that window re-reads `theme`
    /// from disk into the host, which made the write a no-op and dropped the click.
    private func restorePendingSelection() {
        let selection = pendingSelection
        pendingSelection = nil
        guard let host, let selection else { return }
        if host.themePreviewSelectedTheme != selection.configReference {
            host.themePreviewSelectedTheme = selection.configReference
        }
    }

    private func performPreviewWriteAndAutoCommit() {
        guard let host else { return }
        do {
            try executeThemePreview()
            // Auto-commit: theme selection persists immediately (no Save button).
            // Clear preview state so windowWillClose won't revert it.
            host.themePreviewOriginalThemeName = host.themePreviewSelectedTheme
            originalConfig = nil
            originalConfigWasMissing = false
        } catch {
            handlePreviewFailure(error)
        }
    }

    // MARK: - Preview write / revert

    /// Write the selected theme to config.yen and reload silently for instant
    /// preview, snapshotting the original config on the first write.
    private func executeThemePreview() throws {
        guard let host else { return }
        let selectedTheme = host.themePreviewSelectedTheme
        guard !selectedTheme.isEmpty else { return }
        let configPath = host.themePreviewConfigPath

        let snapshot = try SettingsController.themePreviewConfigSnapshot(
            fileExists: { FileManager.default.fileExists(atPath: configPath) },
            readContents: { try String(contentsOfFile: configPath, encoding: .utf8) }
        )

        if originalConfig == nil && !originalConfigWasMissing {
            if snapshot.wasMissing {
                originalConfigWasMissing = true
            } else {
                originalConfig = snapshot.contents
            }
        }

        let contents = snapshot.contents
        let newConfig = SettingsController.configByApplyingTheme(selectedTheme, to: contents)
        guard newConfig != contents else { return }

        try host.themePreviewWriteConfig(newConfig)
        host.themePreviewReloadSilently()
    }

    /// Revert config.yen to its pre-preview state and reload. No-op when no
    /// preview is active.
    func revert() {
        guard let host, isPreviewActive else { return }
        let configPath = host.themePreviewConfigPath
        let rollback = buildRollbackResult()
        do {
            if rollback.hasChanges {
                if let contents = rollback.contents {
                    try host.themePreviewWriteConfig(contents)
                } else {
                    host.themePreviewRemoveConfig()
                }
            }
        } catch {
            YEN.logger.error("ThemePreviewCoordinator: preview revert write failed: \(error)")
        }
        originalConfig = nil
        originalConfigWasMissing = false
        if let rollbackContents = rollback.contents {
            host.themePreviewSelectedTheme = SettingsController.extractThemeName(from: rollbackContents)
        } else {
            do {
                let snapshot = try SettingsController.themePreviewConfigSnapshot(
                    fileExists: { FileManager.default.fileExists(atPath: configPath) },
                    readContents: { try String(contentsOfFile: configPath, encoding: .utf8) }
                )
                host.themePreviewSelectedTheme = snapshot.wasMissing
                    ? host.themePreviewOriginalThemeName
                    : SettingsController.extractThemeName(from: snapshot.contents)
            } catch {
                YEN.logger.error("ThemePreviewCoordinator: preview revert read failed: \(error)")
                host.themePreviewSelectedTheme = host.themePreviewOriginalThemeName
            }
        }
        host.themePreviewReloadSilently()
    }

    /// Cancel any in-flight preview and restore the original config, then reset
    /// the committed baseline to the current selection. Used before a full
    /// persist so preview-stripped keys are not permanently lost.
    func cancelAndRestore() {
        guard let host else { return }
        debounceWork?.cancel()
        debounceWork = nil
        // The full persist that follows writes the host's own selection. A
        // reset or import that ran after the click is the later intent, so the
        // pending click is dropped here and never restored over it.
        pendingSelection = nil
        let rollback = buildRollbackResult()
        if rollback.hasChanges {
            if let contents = rollback.contents {
                try? host.themePreviewWriteConfig(contents)
            } else {
                host.themePreviewRemoveConfig()
            }
        }
        originalConfig = nil
        originalConfigWasMissing = false
        host.themePreviewOriginalThemeName = host.themePreviewSelectedTheme
    }

    /// Cancel a pending debounced preview without restoring config. Used when
    /// the caller reverts immediately afterward.
    func cancelPendingPreview() {
        debounceWork?.cancel()
        debounceWork = nil
        pendingSelection = nil
    }

    private func handlePreviewFailure(_ error: Error) {
        guard let host else { return }
        originalConfig = nil
        originalConfigWasMissing = false
        host.themePreviewRefreshSelectedThemeFromConfig()
        host.themePreviewOriginalThemeName = host.themePreviewSelectedTheme
        host.themePreviewShowApplyFailure("Apply failed: \(error.localizedDescription)")
    }

    /// Build a merge-safe rollback result for the active preview state. Only
    /// restores keys that still look preview-modified so concurrent external
    /// config edits are not clobbered.
    private func buildRollbackResult() -> (contents: String?, hasChanges: Bool) {
        guard let host, isPreviewActive else { return (nil, false) }
        let configPath = host.themePreviewConfigPath
        let fileExists = FileManager.default.fileExists(atPath: configPath)
        let currentContents = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let rolledBack = SettingsController.configByRollingBackThemePreview(
            currentContents: currentContents,
            baselineContents: originalConfig,
            baselineWasMissing: originalConfigWasMissing,
            previewThemeName: host.themePreviewSelectedTheme
        )

        if let rolledBack {
            let shouldWrite: Bool
            if fileExists {
                shouldWrite = rolledBack != currentContents
            } else {
                shouldWrite = !rolledBack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return (rolledBack, shouldWrite)
        }
        return (nil, fileExists)
    }
}
#endif
