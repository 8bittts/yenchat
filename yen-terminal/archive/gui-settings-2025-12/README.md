# GUI Settings Archive — December 2025

This directory contains archived GUI Settings code that was deprecated in favor of the CLI TUI configuration system.

Current-state note: this archive is historical only. The shipped macOS app has a native Settings panel again, implemented from the overlay sources in `yen-terminal/overlays/macos/Sources/Features/Settings/`. Do not use this archive as current Settings architecture or UX guidance.

## Archive Date
December 21, 2025

## Reason for Archive
At the time of this archive, YEN had migrated to a CLI-first configuration approach using the `yen config` TUI command. The then-current GUI Settings interface was removed to:

1. **Simplify maintenance** — Single configuration interface (CLI TUI)
2. **Improve consistency** — All configuration through `config.yen` file
3. **Reduce complexity** — No GUI/CLI synchronization needed
4. **Better UX** — Terminal users prefer CLI configuration

## Archived Files

- `Settings/` — Complete Settings GUI implementation
  - `SettingsView.swift` — Main settings view (deprecated)
  - `SettingsModel.swift` — Full settings data model (archived, minimal stub remains for About window)
  - `ConfigManager.swift` — Full config file management (archived, minimal stub remains for first-launch init)
  - `Views/` — All settings category views (deprecated)
    - `AppearanceSettingsView.swift`
    - `FontSettingsView.swift`
    - `ColorSettingsView.swift`
    - `WindowSettingsView.swift`
    - `BehaviorSettingsView.swift`
    - `MacOSSettingsView.swift`
    - `AdvancedSettingsView.swift`
    - `CloudSyncPromptView.swift`

## Minimal Stubs Retained

The following minimal implementations remain in the codebase for compatibility:
- `yen-terminal/macos/Sources/Features/Config/ConfigManager.swift` — Only `ensureFirstLaunchConfig()` method (required for first launch)
- `yen-terminal/macos/Sources/Features/About/SettingsModel.swift` — Minimal stub for About window compatibility

These stubs are read-only and do not provide GUI editing capabilities.

## Migration Path

At archive time, users were directed to:
```bash
yen config  # Launch interactive TUI configuration
yen reload   # Reload configuration after changes
```

Configuration is managed via `~/.config/yen/config.yen` (or `~/Library/Application Support/com.yenchat.yen/config.yen` on macOS).

## Restoration

If GUI Settings need to be restored:
1. Copy files back to `yen-terminal/macos/Sources/Features/Settings/`
2. Restore menu integration in `AppDelegate.swift`
3. Update `Ghostty.App.swift` to restore `openConfig()` functionality
4. Rebuild and test

## Related Changes

- Menu items removed: "Open Config", "Reload Config" (Settings menu)
- Status bar menu: "Settings..." item removed
- CLI TUI: `yen config` command provides full configuration interface
