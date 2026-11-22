# Architecture

Component boundaries, cross-component contracts, native interaction and input patterns of YEN.

Feature behavior lives in its owner doc; see `_docs/00-docs-map.md`.

## Components

Each component builds and ships independently; never mix concerns between them.

| Component | Location | Owns | Owner docs |
|-----------|----------|------|------------|
| Web | `app/`, `components/`, `lib/`, `public/`, `proxy.ts` | Next.js site on Vercel, `/download`, release metadata hosting | `10-gtm`, `08-growth`, `05-infrastructure` |
| Upstream engine | `yen-terminal/ghostty/` | Generated upstream mirror: rendering, input, config system | `04-security`, `05-infrastructure` |
| Native customizations | `yen-terminal/overlays/`, `yen-terminal/customizations/`, `scripts/lib/patches/` | Branding, overlays, source patches, shell integration, bundled resources | `13-desktop-features`, `05-infrastructure` |
| CLI | `yen-cli/` | The `yen` command, bundled at `Contents/Resources/bin/yen` | `12-commands` |
| Native helpers | `yen-vidthumb/`, `yen-pdfthumb/`, `yen-svgthumb/` | Universal Swift thumbnailers built from source for file-browser previews | `14-file-browser` |

Hard boundaries:

- Never edit `yen-terminal/ghostty/`; change it through overlays, `apply-overlays.sh` patches, or branding automation.
- Never put CLI behavior in upstream source, and never bundle web code into the desktop app.
- The bundled shell CLI at `Contents/Resources/bin/yen` stays inside the release artifact fingerprint scan even though it is not Mach-O.
- Every user-facing binary in `Resources/bin/` is registered in the CLI; the checklist is `_docs/12-commands.md` → Adding New Commands.
- Chat, mail and calendar are fully removed. No runtime, route, binary or Go source remains; restore work starts from git history, never from compatibility code.

## Cross-Component Contracts

**Release distribution.**
`public/stable/version.json` is the public release source.
`app/download/route.ts` reads it once per instance and 302-redirects only to the canonical `github.com/8bittts/yenchat/releases/download/*.dmg` URL it declares (`lib/release-host.ts`).
Prefetch requests return `204` and a missing manifest returns `404` before any redirect.
The route records nothing and sends no email.
`appcast.xml`, `version.sig` and checksums are served from `public/stable/`; the DMGs and deltas are GitHub Release assets ([05-infrastructure.md](05-infrastructure.md) → Release Hosting).
The site has no database and Vercel functions run in `pdx1`.

**Engine to customizations.**
`apply-overlays.sh` brands upstream text, copies overlays, and applies fail-closed patches; the result survives every vendor bump.
`build-release.sh` assembles `ghostty/zig-out/YEN.app` and bundles the CLI, helpers and vendored binaries.

**Persistent sessions.**
A persistent pane runs inside the bundled zmx (`Contents/Resources/bin/zmx`, vendored by `scripts/48-vendor-zmx.sh`), so its shell keeps running when the app quits, crashes or updates.
Settings > General > Keep Sessions Running stores `com.yenchat.yen.persistentSessions`. It is on by default only in the release app (`com.yenchat.yen`), so the Debug build, its test host and the verify copy never start sessions in the user's state directory unless the preference is set.
- The app only marks a pane. `PersistentSessions.prepare` sets `YEN_PERSISTENT_SESSION=<pane UUID>`, `ZMX_DIR=~/.local/state/yen/zmx` and `ZMX_DIR_MODE=0700`, and always overwrites or removes an inherited marker, because a split or tab inherits its parent's environment.
- The engine wraps the final command in `src/termio/yen_session.zig` after shell integration, as `zmx attach <UUID> /bin/bash --noprofile --norc -c 'exec -l <shell>'`, so integration and login semantics apply to the shell zmx starts; the marker never reaches the child.
  The engine also drops an inherited `ZMX_SESSION` from every pane, because an app launched from a persistent pane inherits that pane's value and zmx refuses an attach under it as nested.
- A restored pane keeps its UUID, so restore reattaches to the same session and zmx replays the screen and scrollback.
- A pane with an explicit command (AppleScript, palette actions, file openers) stays ephemeral, and so does a pane whose socket path would pass 103 bytes.
- zmx stores local diagnostic logs under `<ZMX_DIR>/logs`.
  These can retain working directories and connection environment details after the session ends.
- Closing a pane ends its session: `paneLeftTree` checks once undo can no longer bring the pane back and kills the session unless a terminal window holds it again. Ghostty can keep a closed pane alive long after that, so `SurfaceView.deinit` is only the fast path.
- Quitting only detaches: `applicationWillTerminate` sets `PersistentSessions.markTerminating()`, and quit confirmation skips panes with a live session (`quitKillsProcess`).
  A pane closed inside the undo window before the quit is the exception: `endDepartedPanes` ends its session first, because the delayed check never runs after a quit and the session would reopen in a window at the next launch.
- A restored pane whose session died gets a fresh shell in its saved directory, because `zmx attach` creates a missing session.
- A persistent pane's `YEN_SURFACE_ID` is its UUID (the app's route stamp wins over the engine's per-launch id), so `yen pane cwd` and notification routes still reach the pane after a restore. The Quick Terminal saves its split tree, so its pane reattaches when toggled after a relaunch.
- Each session is listed, attached and ended with the zmx build that created it, because a Sparkle update or vendor bump can ship a zmx with another protocol. The app keeps digest-named copies of the bundled zmx in `<ZMX_DIR>/bin/zmx-<digest>`, records the copy that started each session in `<UUID>.zmx`, and passes it to the engine as `YEN_PERSISTENT_SESSION_ZMX`; the reaper deletes copies no record uses.
  The CLI and the reaper run `yen-cli/lib/list-pane-sessions.sh`, which gives each build a private temporary directory of links to its own sockets for `zmx ls`.
  Sockets without a build record use the bundled client.
  Sessions with an unusable record appear as unreachable and are excluded from automatic recovery and cleanup.
- Password-prompt detection reads the session's inner pty. The pane's own pty belongs to the zmx client, which runs raw, so `canonical and !echo` never shows there. `scripts/48-vendor-zmx.sh` patches the zmx daemon to record its pty path in `<ZMX_DIR>/<UUID>.tty` (`zmx ls` skips non-socket files). The engine's termios poll opens that `/dev/tty*` path, reads its mode and closes it at once, because holding the slave open would keep the pty alive. Closing a pane asks its recorded backend to end the session.
  The reaper keeps recovery records while the socket exists and gives new records one normal sweep interval to acquire a socket.
- Each session records the copy of the app that shows it. `PersistentSessions.prepare` writes the bundle identifier, the bundle path and the process identifier to `<ZMX_DIR>/<UUID>.owner`, and a restored or reopened pane rewrites the record.
- After a crash, a session survives but macOS may have saved no window to restore. On the first sweep after launch, `PersistentSessionReaper` reopens each orphan this copy was showing (at most 8) in a new window under its own UUID, so it reattaches.
  An orphan qualifies only when its owner record names the same bundle identifier and bundle path and a process that is no longer running.
  A session that another copy started, such as a local build or a verification copy sharing the socket directory, opens no window; `yen sessions` lists it and the sweep below ends it.
- `PersistentSessionReaper` ends orphans: UUID-named sessions with no client that no terminal window holds. It runs only in an app whose preference is on, so a Debug build or test host sharing the socket directory never ends the release app's sessions. It sweeps 30 seconds after launch and every 10 minutes, and ends an orphan only after watching it orphaned for 24 hours without a gap: a sweep more than three intervals after the last one restarts observation, because a session detached while YEN was quit was never watched.

## Native Patterns

### Native-First Interaction Parity

When a YEN surface has a native analog, mirror the analog's mechanism, curve, duration and secondary effects exactly.
Surfaces with no analog (layout templates, dictation) define their own interaction.

Quick Terminal slides from the screen edge.
The transient Tab Sidebar slides from the terminal edge.

- One motion runner: `SlidingUtilityPanel.transition`.
- Constant geometry and rigid translation of one full extent; never animate a constraint from zero, which reflows content like an accordion.
- `.easeIn` in both directions at `quick-terminal-animation-duration` (default `0.2s`), with a synchronized alpha fade.
- Park hidden past the edge at alpha 0, animate to rest, then exit with synchronous `orderOut` or teardown; no controller-local `Task` hop.
- Reduce Motion passes a zero duration through the same envelope instead of a second code path.
- A shared **10pt** continuous corner radius on the edge facing the terminal.
- Floating panels set `animationBehavior = .none` so AppKit's own show/hide cannot stack on the envelope.
- The slide plays only on open and close, never on a content refresh.

Quick Terminal keeps upstream geometry, screen state, dock handling, focus restoration and lifecycle unchanged.
A fail-closed patch replaces only its two `NSAnimationContext` calls with `SlidingUtilityPanel.transition`, and `applyTerminalFacingCorners` runs only after the native controller establishes the window.

The transient Tab Sidebar uses `EdgeRevealView`, which applies Quick Terminal's `setInitial`/`setFinal` to content instead of a window.
It clips to its bounds, parks its content one full extent past its edge, and slides it to rest inside the shared envelope.
The sidebar hosts this view inside its panel.
The sidebar rests flush inside the window's content area (`contentLayoutRect`, below the titlebar) and keeps a fixed frame.
The sidebar uses its host window’s corner radius and has no separate window shadow.
The scratchpad uses an AppKit utility panel with a native title bar, resize handles, and window shadow.
Its first layout registers the text editor before the panel gives it keyboard focus.

### Scrollable Text Surface Alignment

Any scroll view showing code, diffs, logs or selectable text pins content top-leading in every branch, including empty states.
In SwiftUI use `.frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)`; a bare `minWidth` centers short content.
Read-only diff text uses the shared `NSTextView` surface (`SelectableDiffTextView`), which is top-leading by construction and honors Copy on Select.

### Terminal Input Patterns

| Need | Pattern | Why |
|------|---------|-----|
| Insert text at the cursor | Save the pasteboard, set the text, `NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)`, restore after 0.3s | Goes through `SurfaceView.paste(_:)`, which honors bracketed paste in every TUI |
| Run a command | Resolve the focused `SurfaceView`, send `Ctrl + C` if a clean prompt is required, then each character and Enter through `surfaceModel.sendKeyEvent` | Real keystrokes bypass bracketed paste |

Never use `sendText` for printable characters: zsh's bracketed paste wraps it in `\e[200~` sequences that leak into the prompt.
`TerminalSurfaceCommandLauncher.swift` is the shared command dispatcher; cross-app dictation paste is owned by `_docs/11-speech-to-text.md`.
A new feature is an `AppDelegate+FeatureName.swift` extension with its menu item and shortcut in `MainMenu.xib`.

### Vendor-Don't-Fork

The upstream engine is vendored as source and every other tool as a pinned binary or source build, each tracked by a git-tracked `.<name>-baseline` and listed once in `scripts/lib/vendor-manifest.sh`.
Vendor artifacts are gitignored; baselines are committed with each update.
Adding a vendor: `scripts/00-scripts-readme.md` → Adding a Vendor.
Gate contracts and overlap watch items: `_docs/04-security.md`.

## Testing

Test lanes and the test philosophy: `tests/00-tests-readme.md`.
Gate scripts: `scripts/00-scripts-readme.md`.
Native test rules (TCC, real config, green-but-empty runs): `_docs/09-quality.md` → Native Test Suite.

## Optional desktop integrations

The token status item owns a cancelable utility worker and filesystem notifications for local Claude Code, Codex, Grok Build and OpenCode records.
Counts belong to the recording tool and use the local calendar day.
JSONL cursors and event contributions commit together in a YEN-owned SQLite cache.
The reader skips a record over 8 MB, because usage records are small and image, tool and compaction payloads are not.
A provider directory can be a symbolic link.
OpenCode reads its database in read-only mode and prefers the current copy of a message during schema migration.
OpenCode uses cumulative session counters only when the store has no dated assistant usage across its history.
Each legacy session belongs to its creation day.
The index ranks duplicate snapshots by output and then total tokens.
Codex corrections reconcile input, cached input and output independently within a rollout.
Grok uses completed turns, and OpenCode includes all gateways in its store.
The analytics view reads the 89 finished days before today once, into a scratch index in the temporary folder, and keeps each day’s total per provider in `history.sqlite` beside the day cache.
A finished day is never read again, so its total survives the removal of its source records.
Only a gap in the saved days starts a new read, from the first missing day.
The menu reads Claude’s account-matched usage cache, Codex’s account limits in token-count events and Grok Build’s latest billing log reading.
Codex records its limits only while it runs, so the index also reads the newest rollout from an earlier day.
A plan reading stays until its own reset time, and a percentage outside 0 to 100 is clamped.
When JPtheCat has an enabled plan cache, YEN can read its local Cursor and Grok Bot readings.
Once the optional Cursor connection is active, it replaces the JPtheCat readings for Cursor and Grok Bot.
The optional Cursor connection exchanges a user-supplied API key for a temporary access token on api2.cursor.sh.
The same host supplies Cursor’s current billing-cycle pools and Grok Bot’s weekly included pool.
YEN saves only the user-supplied key in its own Keychain item and deletes that item on disconnect.
A failed Cursor request keeps the last reading, and a rejected key clears it.
Disabling the token menu cancels requests.
Terminal panes and the renderer do not subscribe to usage updates.

The experimental wallpaper feature hosts MovingPaper-derived AppKit panels behind desktop icons.
Video playback uses AVFoundation and animated GIFs use ImageIO.
GIF frames decode into IOSurfaces on a background task, because the main thread also handles terminal input.
`CGAnimateImageAtURLWithBlock` decodes on the main queue, and a bitmap frame is still copied and color-matched at commit, so the view uses neither.
The wallpaper engine suspends occluded playback and responds to power and thermal pressure.
Its cache, preferences and controls belong to YEN, independent of standalone MovingPaper.
Reset and disable tear down feature-owned workers, observers and windows.
Stopping the wallpaper engine is final: after `WallpaperManager.tearDown`, a file choice, download or Photos export that finishes late is saved but cannot rebuild a panel.
