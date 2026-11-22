# Desktop Features

Owns the contracts and invariants of YEN's native desktop surfaces: Settings, window rules, sounds and notifications, workspace panels, and terminal behavior changes.
Commands and shortcuts are listed in `_docs/12-commands.md`; dictation, themes, file browser and browser preview have their own owner docs.
Code lives under `yen-terminal/overlays/macos/Sources/Features/<Feature>/` with tests under `yen-terminal/overlays/macos/Tests/`.

## Window Rules

Overlay-owned utility windows (Settings, About, Onboarding, PR Review, Merge Conflict) follow AppKit defaults:

- A standard titled `NSWindow` with `titlebarAppearsTransparent = false` and a visible title; never `.hidden` with the `.preference` toolbar style, which leaves an empty title row.
- Remove `.fullSizeContentView` explicitly; hosting views can add it silently.
- Create singleton utility windows programmatically, release them on close, and recreate them on reopen. A controller clears the window's `delegate` and `contentView` before dropping it.
- No `NSTitlebarAccessoryViewController` and no manual traffic-light placement.
- `NSPanel` is only for auxiliary non-activating surfaces.

Intentional deltas, not templates for new windows:

- Standard terminal windows default to native titlebar tabs.
  Horizontal tabs align to the right and expand to the left.
  They prefer 240 points each and compress at the window edge, where AppKit manages overflow.
  The title leads each tab when AppKit exposes its title stack.
  A tab with splits shows its pane count at the trailing edge, and narrow tabs hide the count to keep the title readable.
  Holding Command alone swaps every count for the tab's `Cmd + 1-9` shortcut; the zoom control also sits at the trailing edge.
  The selected tab uses a muted pill tinted from the theme's label color, and other titles use the secondary label color.
  An explicit `macos-titlebar-style` overrides either default.
- Quick Terminal is a non-activating `NSPanel` with its own space and fullscreen policy.
- Tab Sidebar and the dictation overlay are borderless non-activating panels so the terminal keeps focus; Onboarding floats during first run; Configuration Errors uses an elevated level.
- Native fullscreen is tracked as an in-flight transition, and overlay consumers read effective fullscreen (`styleMask.contains(.fullScreen)` or a transition in flight); the patch is in `_docs/04-security.md`.
- Settings is a full-size-content window with a transparent, hidden titlebar and a clear, non-opaque background, because its content is a live terminal preview with floating glass panels (see Settings below). The title is still set to the pane name for Mission Control, the Window menu and VoiceOver.

Shared rules:

- Auxiliary panels anchor through one policy: scan key, main, preferred parent, ordered, then app windows, skipping helper panels, Quick Terminal, fullscreen, miniaturized and hidden windows; with no standard terminal, present nothing.
- `BaseTerminalController.windowWillResize` caps a standard window's size to `screen.visibleFrame` through `YENGeometryClamp`, because repeated Fill then Center cycles accumulate rounding drift; the origin is never clamped.
- A disabled feature invoked by shortcut or palette plays the system alert, shows a VoiceOver-announced terminal toast with an Open Settings action, and grays its menu item (`DisabledFeatureToast` over `MessageToast`).
- Overlay-owned warnings in smoke logs, such as an invalid SF Symbol name, are regressions even when the control renders.
- Native chrome uses shared tokens, never per-file literals: `YENDesignTokens.terminalFacingCornerRadius` (10pt), `Color.yenBrand` (`#ff5100`, matching web `--brand`), `SettingsCornerRadius`, `SettingsSpacing`, `SettingsTypography`, `ReviewChrome` and `WebPreviewChromeMetrics`. Panel text uses system text styles or `settingsScaledSystemFont`, so it follows Dynamic Type.

Audit with `rg -n "NSTitlebarAccessory|titlebarAppearsTransparent\\s*=\\s*true|fullSizeContentView|\\.nonactivatingPanel|window\\.level\\s*=" yen-terminal/overlays/macos/Sources`.

## Help Menu and About

**Help menu** (`MainMenu.xib`, `AppDelegate.setupMenuImages`): YEN Help (`lightbulb`, `https://yen.chat/#guide`), JP the Cat (`pawprint`, `https://jpthecat.com`), Bitcoin Email (`bitcoinsign.circle`, `https://btc.email`). Order is fixed in the XIB; external links use `NSWorkspace.shared.open`.

**About** (`AboutView`): bordered small buttons beside the version label open Docs (`https://yen.chat/#guide`) and Bitcoin (`https://btc.email`) through SwiftUI `openURL`.
The rounded monitor icon pulses while About is active and shows a steady glow with Reduce Motion or when the window is inactive.

## Settings

**Shell.** `Cmd + ,` toggles the window and is reserved: config-synced shortcuts never claim it, and `AppDelegate` keeps it in the direct key-equivalent index because local event monitors do not see menu-tracking loops.
The window is a live terminal preview (`SettingsStudioPreview`) that draws the current theme, font, cursor, padding, opacity, background image and border.
Two Liquid Glass panels float above it: an inspector on the right with a five-segment pane switcher (Appearance, General, Notifications, Dictation, Shortcuts), and a theme dock bottom-left that shows every catalog theme as a swatch and appears only on Appearance.
Glass sits on the control layer only, as the HIG asks; the forms inside the inspector are standard grouped `Form`s with a hidden scroll background, and their top margin is trimmed to `SettingsSpacing.formTopMargin`.
Every spacing and text style in the Settings views comes from `SettingsSpacing` and `SettingsTypography`; the inspector header uses `contentInset`, the grouped form's own section inset, so the header lines up with the sections.
[CRITICAL] A switcher that spans a row uses `SettingsSegmentedControl` (an `NSSegmentedControl` with `.fillEqually` that takes the offered width), never a segmented SwiftUI `Picker`. On macOS that `Picker` keeps its natural width: it never stretches and never shrinks, and the five shortcut groups measured 395 pt, which pushed the Shortcuts pane past the inspector's right edge.
The inspector is 380 pt wide so a permission row fits its name, status and button on one line.
`settingsGlassPanel()` uses `glassEffect`.
The preview cursor blinks through a `TimelineView` that stops under Reduce Motion.
The preview outline (`SettingsStudioPreviewOutline`) draws the runtime `WindowBorderOverlay` with `WindowBorderRenderingPolicy.windowOutlinePlacement`, so weight, corner and frame match a terminal window in the current pane style.
It sits inside the safe area, below the titlebar band, as it does over terminal content; drawn over the full preview it crowded the window controls.
The preview's ANSI accents come from `palette = 1` through `6` in the theme file, parsed once per path by `SettingsStudioPalette`.
There is no search, no import or export, no per-pane reset and no footer: the whole settings set fits in five short panes, so nothing needs to be hunted for.
`SettingsWindow.toolbar` forces `nil`, because a toolbar would add a strip above the preview.
The window title is the visible pane (`SettingsWindowFactory.title(for:)`), and the minimize and zoom buttons are dimmed as the HIG asks: the style mask has no `.miniaturizable`, and `dimZoomButton` runs at creation and again when the window becomes key.
The window stays an AppKit-managed singleton rather than a SwiftUI `Settings {}` scene, for its lifecycle, deep links and benchmark hooks.
The default pane is Appearance; every pane has a command palette deep link.

**Controls that map onto stored settings.** The panes expose fewer controls than the stored model, and these mappings are the contract:

- Padding is one stepper (step 2) that writes both `window-padding-x` and `window-padding-y`.
- Border shows On, Color (Theme writes Match Theme, Accent writes manual), Outline (Window or Focused Pane, writes the scope) and Weight (Thin 1, Regular 2, Thick 4); a stored width snaps to the nearest weight.
- `SettingsAppearancePane.borderRows` lists the child rows, and `SettingsPaneTests` fails when one goes missing.
- Scope and palettes are also reachable from the command palette's Window Border actions; radius has no control and keeps its stored value.
- Tab Sidebar is one pop-up: Off clears the enabled flag, Floating is transient mode, Docked is persistent mode.
- Each alert stream is one sound pop-up. It shows None whenever the stream is silent (no sound, a delivery mode without sound, or zero volume). Choosing a sound raises Banner Only or Off to Banner + Sound, raises a zero volume to 100%, and previews it; choosing None changes only the sound.
- Background image scope appears only while an image is set.

**Config.** Settings writes `~/Library/Application Support/com.yenchat.yen/config.yen`.
The runtime reads only `~/.config/yen/config(.yen)` and that Application Support path, never a Ghostty path.
`ManagedConfigDocument.merged(intoExistingLines:)` deduplicates non-repeatable keys; for keys in `repeatableKeys` a managed value replaces only the first occurrence, so a `font-family` fallback chain survives.
`shell-integration-features` always gains `no-cursor` so shell integration cannot override the chosen cursor; other features are preserved.
Every write emits the whole managed list, so a key in `SettingsController.rawPreservableConfigKeys` keeps its hand-written value (`font-size = 13.5`, `window-padding-x = 2,4`, `cursor-style = block_hollow`) until the panel changes or resets that setting.
The value is recorded on load only when the key appears once and differs from what Settings would write; a reset discards the keys it resets.
`window-save-state` is a forced constant, not a preserved value.
Keybind remaps are written as replacement pairs (default unbound, new bound); key tables, key sequences and standalone `keybind = <default>=unbind` lines survive a save, and Settings rewrites `global:` only for registry entries with `isGlobal`.
Preferences outside `config.yen` live in `UserDefaults` under `com.yenchat.yen.*` and `YENNotification*` (see `SettingsPreferenceTypes.swift`).

`KeybindConfigMerger` owns keybind reconciliation and value parsing for config writes.

**Applying changes.** Config-backed edits write in real time (debounced) and call `yen.reloadConfig()` in process; theme, workspace and notification choices apply immediately.
Theme previews read the existing file first: a missing file is empty, but an unreadable file fails with a status error instead of being overwritten.
State changed while the window is hidden persists immediately, and reopening or deep-linking flushes pending debounced edits before rehydration.
`SettingsController.init()` hydrates config-backed state at launch because `ScratchpadView`, `GitDrawerDiffTextView` and `TerminalPresentationSettings` read it.
[CRITICAL] That launch `loadConfig()` stays inside `suppressRealTimeConfigSync`; with no window, each differing key would otherwise trigger a synchronous parse-merge-write of `config.yen` on the main thread.
Cursor style and blink apply live but show only when the terminal is focused; `background-opacity` needs an app restart; `Cmd + Option + 1-0` is ignored while Settings is key.

**Reset.** Reset All Settings (General) and Restore Default Shortcuts (Shortcuts) each confirm in a sheet that names what they remove and that they cannot be undone.
`SettingsConfigurationReset` runs both as one transaction: capture a rollback snapshot (config file, workspace and window border preferences, dictation state, notification choices), change, save, and restore the snapshot when the save fails.
Restore Default Shortcuts changes only keybinds.

**Status.** `showStatus` renders a notice at the bottom of the inspector only while there is a message; there is no permanent status bar.
It posts each message to VoiceOver as an announcement, and an error stays until it is dismissed or replaced while other severities clear on their timer.
Status text uses a label color and the symbol carries the severity color, because colored text on its own tint measured about 2:1 in a light appearance.
Anything reachable from the File menu, a hotkey or the palette reports through `showLayoutStatus`, which mirrors to the terminal toast stack.
`windowWillClose` resets `statusMessage`, `statusSeverity` and `statusClearActiveGeneration` along with cancelling the clear timer, or a frozen notice survives into the next open.

**Lifetime and memory.** `SettingsController.shared` is app-wide live state; closing never clears it.
Closing stores the frame, flushes writes, cancels panel-only work and releases the window graph; a window that lost its `contentView` is recreated, never reused.
`scripts/manual/27-run-settings-memory-benchmark.sh` compares release-on-close with `YEN_SETTINGS_MEMORY_BENCHMARK_MODE=retain`; `YEN_MEMORY_FIXES_BENCHMARK=1` runs the background-image cache and merge-conflict release scenarios.
Correctness is proven by `SettingsWindowLifecycleTests`, `OnboardingWindowLifecycleTests` and `UtilityWindowLifecycleTests`, not by the benchmark.

**Performance guardrails.** Settings is already render-optimized; keep it that way:

- Show the window first, then hydrate through cancelable deferred tasks (`SettingsPresentationCoordinator`, `GenerationalMainActorTask` for theme, font and keybind reloads).
- Each pane reads one snapshot store (`GeneralSettingsStore`, `WorkspaceSettingsStore`, `SoundsSettingsStore`, `ThemesSettingsStore`, `KeyboardSettingsStore`); never let a pane body observe the whole controller.
- Runtime status (permissions, notification authorization, speech readiness) lives in its own store; permission polling runs only while Settings is visible on Notifications or Dictation, every 4s with 0.6s `Timer.tolerance`, owned by `SettingsPermissionPollingController`.
- Conflict-scan results are cached per session and invalidated on app install changes and on close.
- With Settings hidden, a config reload rescans the theme catalog only for Match Theme. With Settings visible it always rescans and re-resolves the active theme, because the preview shows the theme on every pane.
- A visible retarget reuses an in-flight bootstrap; only first open and hidden reopen bootstrap a full session.
- Use stable ids for shortcut rows and theme swatches, and keep per-row UI state below the host layer.
- Cancel every timer and task in `windowWillClose` and in test reset hooks.

Tried and reverted, do not retry without new evidence:

- Deferring the launch theme-catalog build needs a new single-theme resolution path that exactly reproduces name normalization and curated-versus-user precedence, or a Match Theme border flips color after the first frame. Measured cost was about 3.5 ms.

### Optional menu and desktop features

General → Menu Bar → Show Token Usage enables the experimental agent token counter.
Click its YEN status item to open the local day’s overview beneath the icon on the same display.
The panel takes the app appearance, which follows the terminal theme, so a light theme opens a light panel.
Each provider shows its exact daily count and share of counted tokens.
Current plan readings appear below the daily share and each percentage belongs to its named pool.
A plan reading stays until its reset time.
A provider name or a pool label opens the dashboard that owns its numbers, and the pointer tints it; the panel has no separate link row.
Plan labels start at the provider name’s left edge.
The chart button turns the card over to the analytics view, which keeps the overview’s size.
That view shows token totals for the last 7, 30 and 90 days for each provider and for all providers, today included, above a daily chart of the 90 days.
It shows tokens, not money; YEN holds no price table.
The layout button switches between one and two columns.
Bars use darker tones on a light theme so each stays at 3:1 contrast against the panel (`TokenBarTone`).
The footer cycles the menu bar through total tokens, the leading provider, rotating plan limits and the YEN icon.
A source label identifies plan readings supplied by an existing JPtheCat opt-in.
The connection button accepts a personal Cursor API key for Cursor and Grok Bot plan usage and offers Disconnect.
An asterisk marks partial coverage.
A readable source with no usage contributes zero, and an unavailable source is omitted from the total.
Turning the switch off cancels collection and removes the item.
The [architecture](01-architecture.md) owns the reader and cache boundaries.

On macOS 27 or newer, General → Experimental → Moving Wallpaper exposes Wallpaper Controls inside Settings.
Select a local movie or GIF, a YouTube link, a video from Photos or a random Photos video.
Playback starts muted and supports pause, sound and per-desktop assignments.
YEN owns only its background windows and saved selections.
Turning it off reveals the system wallpaper and keeps assignments for the next enable.
The wallpaper engine yields while standalone MovingPaper runs.
Open YEN at Login remains the single startup control.
Both features default to off and a successful Reset All Settings switches both off.
Reset All Settings also removes the saved Cursor key and the token menu’s layout and display choices.

### Settings hitch benchmark

[CRITICAL] Only the operator runs the recording, with no agent session active: a live agent session measured `100.6%` CPU, more than a busy browser, so numbers recorded from inside one are indicative only.
An agent may edit the harness, read `summary.csv` and do the re-pin arithmetic.

`scripts/manual/29-run-settings-hitch-benchmark.sh` first rebuilds `zig-out` through `01-macos-smoke.sh --build-only` (skip with `--skip-build`), never touches the installed app, and launches `yen-terminal/ghostty/zig-out/YEN.app` once per scenario under `xcrun xctrace record --template "Animation Hitches" --launch -- "$YEN_TRACE_EXE"`, driving the scenario through `YEN_SETTINGS_HITCH_SCENARIO` and discarding rows before the `YEN_SETTINGS_HITCH_START_FILE` start-file release point.
That app is a `ReleaseFast` build, so `SettingsHitchBenchmark.maybeStart()` stays compiled into Release on purpose, unlike the two `#if DEBUG` memory benchmarks beside it; wrapping it in `#if DEBUG` silently breaks the benchmark.
It exports hitches with `xcrun xctrace export --xpath '//trace-toc[1]/run[1]/data[1]/table[62]'` and hangs with `--xpath '//trace-toc[1]/run[1]/data[1]/table[19]'`.
The comparator is `tests/fixtures/settings-hitches/2026-03-05-summary.csv`, the tracked copy of `tmp/perf/settings-hitches/2026-03-05/summary.csv`, with this schema:

```csv
scenario,hitches_rows,hitches_max_ms,hitches_p95_ms,hitches_over100ms,expensive_updates,expensive_renders,potential_hangs,potential_hang_max_ms
```

Scenarios: `first-open` (cold launch, open Settings once), `reopen` (close and reopen without quitting), `rapid-tabs` (20 pane switches), `sounds-refresh` (open on Notifications, refresh status, switch to Dictation).
The budgets were recorded against the previous sidebar panel; re-pin them from the first operator recording of the Studio panel.
A run fails when any scenario exceeds its budget:

| Scenario | `hitches_rows` | `hitches_max_ms` | `hitches_p95_ms` | `hitches_over100ms` | `expensive_updates` | `expensive_renders` | `potential_hangs` | `potential_hang_max_ms` |
|----------|----------------|------------------|------------------|---------------------|---------------------|---------------------|-------------------|-------------------------|
| `first-open` | hitches_rows<=32 | hitches_max_ms<=391.67 | hitches_p95_ms<=100 | hitches_over100ms<=3 | expensive_updates<=8 | expensive_renders<=3 | potential_hangs<=14 | potential_hang_max_ms<=233.65 |
| `reopen` | hitches_rows<=40 | hitches_max_ms<=383.33 | hitches_p95_ms<=66.67 | hitches_over100ms<=3 | expensive_updates<=8 | expensive_renders<=4 | potential_hangs<=11 | potential_hang_max_ms<=234.70 |
| `rapid-tabs` | hitches_rows<=72 | hitches_max_ms<=641.66 | hitches_p95_ms<=200 | hitches_over100ms<=8 | expensive_updates<=9 | expensive_renders<=2 | potential_hangs<=26 | potential_hang_max_ms<=543.57 |
| `sounds-refresh` | hitches_rows<=30 | hitches_max_ms<=583.33 | hitches_p95_ms<=508.33 | hitches_over100ms<=5 | expensive_updates<=3 | expensive_renders<=2 | potential_hangs<=19 | potential_hang_max_ms<=680.86 |

It also fails on a missing scenario, missing column, non-numeric metric, missing XML export, or zero-byte XML export.

Trace contamination rule:

- A valid trace records the exact bundle path, executable, PID, signing identity and scenario.
- Do not close, quit, or retarget any existing `/Applications/YEN.app` process; if the target cannot be isolated to one `zig-out` PID, stop.
- Machine load is part of the trace: the run aborts above `--max-load` (default `4.0`) and records `conditions.txt` before and after each scenario. Five back-to-back runs once drove load from `3.23` to `9.94` and `rapid-tabs` max from `8.33` to `1266.67` with no code change, so keep `--cooldown-sec` and use `--prune-traces` for repeated sessions.
- A video call (`avconferenced`, `cameracaptured`, `VTEncoderXPCService`) contends for the same GPU path and invalidates a run.

## Keyboard Shortcut Settings

Settings > Shortcuts lists every `KeybindRegistry` entry in five groups (`SettingsShortcutGroup`: Terminal holds terminal, navigation, font and search; Windows; Tabs; Splits; YEN holds the custom entries), with conflict detection against macOS symbolic hotkeys and known apps (VS Code, iTerm2, Raycast, Alfred, 1Password).
Each shortcut is its own small bordered button, drawn as menu glyphs (`KeyTrigger.glyphString`, Control, Option, Shift, Command order); clicking it records a new one, and while recording the same button turns red and cancels on click. A locked shortcut is the same button, disabled, beside a lock glyph.
Recorder capture and conflict scans use the current keyboard layout through `UCKeyTranslate`, so non-US layouts match their real logical keys.
Entries sharing an action and the fixed YEN shortcuts (`Cmd + ,`, `Option + Space`, `Cmd + Shift + O`, `Cmd + Shift + S`, `Cmd + Shift + B`, `Cmd + Shift + G`, `Cmd + Shift + J`, `Cmd + Option + 1-0`) are read-only with a lock glyph; each entry's identity is its `stableId` (default trigger plus action).
The recorder requires Cmd, Ctrl or Option, treats shift-only shortcuts as read-only, cancels on Esc, times out after 10 seconds, and can capture `Cmd + Q` and `Cmd + W`; switching group or pane stops it.
A duplicate trigger stays allowed, because swapping two shortcuts passes through one; it raises a status warning when it is recorded, and each affected row says so on a second line with a symbol.
The pane's catalog follows `KeyboardSettingsStore` through its publisher, never through a view closure: a single-parameter `onChange` closure captures the values from before the change, which once left the list empty on first visit and one edit behind after it.
`KeyboardSettingsStoreTests` drives that path through `SettingsShortcutsPane._TestCatalogProbe`.
When a config-backed YEN item claims a built-in menu shortcut, the built-in item's displayed key equivalent is cleared so one shortcut never shows two owners.

[CRITICAL] Shift-optional symbols stay dual-indexed.
The engine binds some shifted symbols without Shift (`increase_font_size` is `super++`), while a US keyboard types `+` as `Cmd + Shift + =`.
`AppMenuShortcutController.MenuShortcutKey` indexes every `shiftOptionalSymbols` entry with and without Shift; without it `Cmd + +` silently does nothing. `AppMenuShortcutControllerTests` guards it.

## Sounds and Notifications

Notification sounds are system-only, for two streams (`General`, `Build`):

- Sound: `None` or a macOS system sound from `/System/Library/Sounds`.
- Delivery: `Banner + Sound`, `Banner Only`, `Sound Only`, or `Off`; stored per stream, with no Settings control (see the sound pop-up mapping under Settings).
- Volume: stored per stream from 0 to 1, with no Settings control.
- While YEN is active: play sounds and show banners independently.

`NotificationSoundManager` is the only owner of persistence, normalization, discovery and playback.
`Helpers/NotificationPolicies.swift` owns authorization, presentation, recovery, and response-routing decisions; `AppDelegate+NotificationSound.swift` owns delivery and AppKit integration.
Settings reads snapshots through `SoundsSettingsStore`; the controller stores one `NotificationServiceSettings` value per configurable service.
`NotificationSoundStore` forwards edits to the manager; bulk hydration reads every service without forwarding snapshots back through preference setters.
`NotificationSoundPreviewCoordinator` debounces one preview and stops it on close.
Stored ids are `none` or `system:<encodedName>`.
`NotificationSoundManager.canonicalSoundSelectionID` maps a system sound missing on this Mac, any retired `custom:` or `bundled:` id, and malformed ids to `none`; it is the single choke point behind lookup, display and playback.
Old `sounds/` and `sound-packs/` folders under Application Support stay inert: never scanned, deleted or surfaced.

Custom imports and sound packs are retired.
The Notifications pane shows notification access, command-finish controls, one sound pop-up per stream, and focused behavior; speech permissions, the microphone and translation are on the Dictation pane.
No release artifact, `public/stable/yen-sound-packs-*` file, or GitHub Release `yen-sound-packs-*` asset may exist, and public docs never advertise custom sounds.
The retired archive is GitHub release `sound-packs-archive-2026-05-03`.

Routing:

- Every surface carries `YEN_SURFACE_ID`; service notifications decode `schema_version`, `service` and `surface_id`, keep `userInfo` property-list safe, route a click to the originating surface, and fall back safely when the route is stale.
- Command-finish notifications use the same managed delivery path as service notifications.
- Build, check and test notifications from `.claude/hooks/notify-complete.sh` carry task type, command summary and exit status.
- A bell bounces the Dock icon only while YEN is inactive, sets a badge only when badges are authorized, clears it on activation, and follows the managed delivery policy for sound.

## Workspace Panels

Quick Terminal and the transient Tab Sidebar share the motion contract in `_docs/01-architecture.md` → Native Patterns.

**Tab Sidebar** (`Cmd + Shift + B`).
Observation, docked presentation, Git context caching, build status, and shared row data each have a separate source file.
`TabSidebarController` coordinates the floating panel and shared metadata.
Both presentations retain the two-second fallback tick without clearing every cached path.
Canonical paths expire after 15 seconds; Git refreshes and build-status expiry remain independent of that cache.
Surface publishers coalesce on the main run loop, and observer callbacks render without repeating the metadata scan.
Sidebar Git reads use `GitDrawerShellClient` with optional locks disabled, a two-second timeout, and forced termination after a 200 ms grace period.
Sidebar status reads branch metadata through `GitStatusPorcelainV2`; detached names use the shared `GitBranchResolver` helper.
Split-pane labels resolve a branch only when the worktree folder cannot supply an informative name.
By default a transient panel slides in over the terminal from the window's left edge; an opt-in persistent mode docks a fixed-width rail inside standard terminal windows and stays hidden in minimized windows and Quick Terminal.
Native fullscreen has leading controls to toggle the rail for the current tab group and leave fullscreen.
The fullscreen rail uses the available window width and does not write the windowed visibility preference.
- Both hosts come from `TabSidebarHostingViewFactory`, which sets `sizingOptions = []`; default content sizing shrinks or centers a short rail.
- Startup and restore show the docked rail only when the feature is enabled and the stored `persistentVisible` is true.
- Switching to persistent dismisses any live transient panel before persisting the mode.
- The transient panel orders out when a non-terminal window becomes key and resumes when a terminal regains key; on terminal close it rebuilds from the explicit replacement window.
- Window movement schedules compensation only while a docked sidebar host exists.
- `TerminalViewContainer` installs the docked host before publishing state, coalesces activation to the next run-loop turn, adjusts the window frame through `DockedSidebarGeometry`, and tears down the model and timer with the host.
- Rows switch on single click; rename uses the inline editor when docked and the native title editor when floating (the panel stays non-key). A no-op edit must not pin the current title as an override, and Escape yields to an active field first.
- Metadata shows cwd and git only for trusted paths (symlinks canonicalized) and live status only from real progress, recent build notifications or bell attention; the build-status observer installs lazily on first read.

**Scratchpad** (`Cmd + Shift + J`).
One app-global buffer, persisted locally, seeded with helper text on first run.
The panel opens centered in the terminal content area and sizes to fit the window.
Drag its title bar to move it or drag an edge to resize it.
The next open restores the chosen size within the available space.
Escape, the close button, and a click outside dismiss it.
Highlight-to-copy writes plain text, and selected-text dragging is disabled so a highlight never becomes a drag or rich payload.

**Split layouts** (`Cmd + Option + 1-0`, File menu, palette).
Ten presets, all through `SettingsController.applyLayout`, which delegates targeting, confirmation, tree replacement, and zoom remapping to `SettingsLayoutApplier`.
The focused pane must belong to the target tree before new terminal surfaces are created.
`Single Pane` is destructive and needs a second invocation.
Shortcuts need exact Cmd + Option and a foreground terminal window; new panes inherit the focused split's baseline, zoom identity is preserved where possible, and one undo restores the whole layout.

**Split pane style and labels.**
Settings → General → Panes offers two styles that update open splits immediately.
Comfortable is the default and gives each pane a rounded border and a gutter.
Compact places panes edge to edge with a draggable divider.
The top row shares one edge below the toolbar in single, split, and zoomed layouts.
Each outlined pane reserves space for its stroke and corner curve around the terminal grid and header.
A window outline around framed panes reserves the same space in every pane.
Changing focus keeps the terminal grid size stable.

Each split header shows an activity icon, title and working directory above the terminal.
It uses the pane background and balances the space above and below the icon and title.
Click the header to focus the pane, drag it to a highlighted edge to move it, or click the pencil to rename it.
The existing Pane Labels preference controls headers and defaults to on.
Small and zoomed panes preserve terminal space, and the engine drag-handle setting can disable dragging.
On supported macOS versions, horizontal tabs center vertically in the toolbar and grow left from its right edge.
After a tab moves to another window, switching between the remaining tabs keeps the strip width stable.
The icon uses the local foreground executable and falls back to a recognized terminal title or a terminal symbol.
"Rename Split Label" sets a label that survives layout rewrites, undo, restore and relaunch (a `UUID -> label` sidecar in terminal and Quick Terminal restore state).
Without a custom label, the header prefers the worktree name (if enabled), recognized agent name, surface title, working directory name, then "Terminal".
Worktree naming (default off) uses the worktree root's folder name, or the branch when the name is generic (`wt`, `tmp`, a dot-directory) or the repository is bare; a typed label always wins.
Resolution runs git off the main actor and is cached per directory.
Label reads and watcher setup share path normalization, capped at 128 entries with five-second expiry.
Missing paths also expire, so newly created directories and changed symlinks are checked again.
An informative folder name skips the branch query.
Each visible header registers with `SplitPaneWorktreeLabelStore.watch(workingDirectory:)`.
One loop checks the watched directories every five seconds and stops when the last header hides.

**Agent worktrees.** A coding agent works in a worktree while its pane's shell stays in the checkout, and agents emit no OSC 7, so `pwd`, the agent's own cwd and its session file all keep the launch directory.
The agent reports its directory with `yen pane cwd`, which posts `com.yenchat.yen.agentWorkingDirectory` with the pane's `YEN_SURFACE_ID`.
`AgentWorkingDirectoryReceiver` binds the report to the pane's foreground process group; `effectiveWorkingDirectory` honors it only while that group stays in front, and the next shell OSC 7 clears it.
Split labels and the tab sidebar read `effectiveWorkingDirectory`; new splits, the palette and the engine keep the shell's `pwd`.
Claude Code reports through a user-level `CwdChanged` hook running `"$YEN_BIN_DIR/yen" pane cwd --hook` when `TERM_PROGRAM` is `yen` (`yen pane --help` has the guarded command); a hook's `terminalSequence` cannot carry OSC 7.
Codex hooks expose only the session `cwd`, so Codex agents do not report a worktree directory.

**Quick Terminal** (`Ctrl + Backtick`, global, shown in the Window menu).
Upstream ships no default binding.
Restorable state is versioned and persists the focused surface, split tree, per-display native frames and pane labels; a one-time geometry version bump drops frames from the retired YEN anchor path.

## Terminal Behavior

**Keep Sessions Running.** Settings > General > Keep Sessions Running stores `com.yenchat.yen.persistentSessions`; it is on by default in the release app and off in every other identity (Debug, test host, verify copy) unless set. New panes read it when they are created, and a pane whose session is still alive keeps attaching after it is turned off.
Below the switch, `PersistentSessionsStatusRow` shows how many session sockets exist and End All Sessions, which confirms and then ends every one, open panes included; it is hidden while none run.
The General pane owns the 3-second refresh on the switch itself, because a `.task` on a row hidden at zero never starts and the count would never appear.
`yen sessions` lists, attaches and ends sessions (`_docs/12-commands.md`); the contract is `_docs/01-architecture.md` → Persistent sessions.

**Copy on Select.** Settings > General > Copy on Select (`both` or `false`) covers terminal surfaces, the scratchpad, and the shared diff view in PR Review and Merge Conflict.
Upstream defaults to a private selection clipboard; YEN patches the default to `both`.
`NSTextView` surfaces copy through `CopyOnSelectClipboard` from `textViewDidChangeSelection`, writing plain text, and an empty selection never clobbers the clipboard.
Never drive this from a global `.leftMouseUp` monitor (text views and SwiftUI selection gestures hide the mouse-up) or from `NSTextView.copy(_:)` (rich payloads).
Hold Shift to select inside TUIs that capture the mouse.
`yen-yazi-edit` opens `micro` with `-ruler false -softwrap true -wordwrap true` so copied selections stay gutter-free.

**Cmd + V.** Paste goes through the native paste action.
File URLs paste as paths, and image-only clipboards become private temp files under a pruned YEN-owned root; remapped non-paste bindings are never taken.

**Restoration.** `window-save-state = always`, so every launch restores windows, tabs, splits and positions, not only after a crash.

**Cursor and config reload.** A config reload always reapplies the configured cursor style, and a successful reload shows a toast.
Screenshot, disabled-feature, and layout toasts share integral window-ID routing and trimmed message parsing.
Only screenshots allow a window-object target or a default message; other toast sources require an explicit target and nonempty text.

**Screenshot** (`Cmd + Shift + S`).
ScreenCaptureKit captures only YEN’s own window at native pixel size without a Screen Recording grant.
Encoding runs off the main thread, files are allocated exclusively so concurrent captures never overwrite, and the toast in that window reports the real outcome (saved, copied, partial, failed).

**Background image scope** (Settings > Appearance > Image Fills, shown while an image is set).
`Each Split` (default) keeps upstream per-surface wallpaper.
`TerminalView` composes separate background image loading, whole-window background, border, and window-reference helpers.
`Whole Window` is overlay-owned, not a config key: a transient runtime config zeroes `background-opacity` and `background-image-opacity` on surfaces while one `WholeWindowBackgroundView` renders behind the split tree.
One parsed runtime config is shared across windows, keyed by settings snapshot, source config generation, runtime path, and override mode.
Use the incoming `.yenConfigDidChange` config as the generation token; Ghostty posts it before replacing `yen.config`.
Failed loads remain retryable, and each window still applies the parsed config to its own surfaces.
- The view extends behind the titlebar (`.ignoresSafeArea(.container, edges: .top)`), or a transparent surface exposes the desktop.
- Images load through `NSImage(data:)` to bypass the path cache, and reload only on `imagePath` change, never on `.yenConfigDidReload`, which caused reload storms.
- Failed loads retry existing files and ubiquitous items after 1s, 2s, 4s, and 8s; a missing local file fails at once.
- Leaving `Whole Window`, replacing the image or clearing it rewrites the runtime config to a visible state before removing it.
- New, restored and re-laid-out splits inherit the scope, and screenshots render the wallpaper once.

**Chromatic window border** (Settings > Appearance > Border; scope also through the palette's `Window Border: Toggle Focused Split`, palettes through its other Window Border actions).
Scope `Window` or `Focused Split` (falls back to the window when no split frame exists); manual or Match Theme colors.
- In the Comfortable pane style both scopes share one frame: the window outline follows the outer edge of the pane frames with the pane corner radius and adds no padding, so the terminal grid does not move when the scope changes.
- In the Compact pane style, or while the browser split is open, the window outline follows the native corner radius inside the clipping edge and pads the content clear of it; `WindowBorderRenderingPolicy.windowOutlinePlacement` owns the choice.
- In split layouts the focused outline surrounds the pane, including its header, and follows focus as panes move or resize.
- A single or zoomed surface supplies its AppKit frame. Frame observers subscribe only to that surface and window when needed.
- Settings apply across the tab group, including new tabs. The command palette, update pill and toasts stay above the border.
- Hidden in fullscreen and Quick Terminal; focused styling requires `NSApp.isActive`.
- Match Theme normalizes quoted names, separators and extensions, and says so when it falls back to manual colors.
- Differentiate Without Color dashes the unfocused border, and the palette's Window Border actions link to the system setting.

**Permission onboarding.** First activation shows live status for Accessibility, Microphone and Speech Recognition with Grant buttons.
"Skip for Now" or closing is stored as dismissal and "Get Started" as completion; recovery stays in Settings > Dictation > Permissions.
`apply-overlays.sh` injects `showOnboardingIfNeeded()` after `DictationController.shared.setup()` and fails if it cannot.

**Welcome banner.** Shown once per shell session tree, suppressed through `YEN_WELCOME_SHOWN`.

## Command Palette

`Cmd + Shift + P`: an empty query lists actions; a query searches actions, files, content, diagnostics and history through the IDE search contract.
`TerminalCommandPaletteSearchEngine` coordinates shared decoded-text caching and ranking.
The session cache retains decoded text and lowercase lines under a 16 MiB accounting cap and 3,000-entry limit.
Size, modification time, inode, and permissions invalidate cached text and symbol snapshots.
Only complete content scans narrow extending queries; changed files and previously unreadable files remain eligible.
Empty queries, directory changes, and dismissal clear the cache and reject late writes from earlier sessions.
Text reads stop at the one-MiB file limit even if a file grows during the read.
Project context computes its history and diagnostics hash once; indexed file and symbol fields retain their lowercase search forms.
Project context, file and symbol indexing, each result source, and the observable search model have separate owners.
Project discovery runs off main and lists each ancestor once, reusing the root listing for runtime and tooling tags.
Directory changes and dismissal cancel discovery; generations prevent late results from replacing the current project.
Local path normalization is shared, while sidebar callers retain their whitespace-trimming and absolute-path requirements.
The field focuses on open; submit, Escape, an outside click or an app switch dismisses it, and in-window dismissal restores terminal focus.
Visible jump targets observe surface titles, working directories, and window titles, coalescing metadata bursts on the main run loop.
A five-second fallback catches missed topology changes; stopping removes observers and rejects queued work from earlier sessions.
File indexing skips excluded directories and nonregular entries before resolving file paths, while preserving root containment.
`Review Pull Request` and `Resolve Merge Conflicts` appear only for a repo root trusted with `yen ide workflow trust`, and the trust is re-checked at execution.
PR Review drafts inline comments, stages evidence, and posts comments and decisions only on explicit action; Merge Conflict handles marker-based text conflicts per hunk (`ours`, `theirs`, `both`), revalidates on disk and stages the file.
PR review source separates shared types, diff parsing, draft formatting, local evidence loading, audit writing, and shell execution into `PRReview*.swift` files.
`PRReviewWorkspace.swift` owns the observable model and coordinates those helpers.
The shell client dispatches inline, evidence, and decision submissions separately, sharing one progress result and error boundary.
Failed submissions retain completed inline IDs so retrying does not repost those drafts.
Build executable catalog actions from the current view state.
The invalidation key tracks search descriptions, not execution callback or update-model identity, so it must not cache executable closures.
