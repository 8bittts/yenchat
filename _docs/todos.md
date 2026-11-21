# YEN TODOs

---
## MUST FOLLOW RULES and PROTOCOLS:

1. Never remove, delete, or modify this list unless directed to do so.
2. Active work only. Completed work lives in git history.
3. `_docs/todos.md` is the only backlog file.
4. Keep clear separation of concerns with phase-based checklists and zero task duplication.
5. Validate, review, and test each phase before moving to the next phase.
6. Stage and commit only files touched for the active phase. Ignore unrelated edits from other agents.
7. Write durable findings into the `_docs/` file that owns the topic, replacing any sentence they contradict; history and research go only in `00-foundation.md`.
8. End every phase with a docs-alignment step that updates internal and public documentation and runs the project's declared gates.
9. Fix correctness, accuracy, and routing gaps before design polish or cleanup work.
10. Update Claude project memory for reusable operational findings when novel implementation decisions are made; memory stays outside this public repository.
11. Keep review-only evidence out of persistent scratch docs; active follow-ups belong here and durable subsystem decisions belong in the owner doc.

---
## ACTIVE

YEN is in maintenance mode (`_docs/00-foundation.md` → Decisions) with two operator-approved features below: always-on sessions and the token usage menu.
Apart from those features, this list holds only bug fixes and security work; other new features, redesigns, refactors, performance work and growth work stay out of scope unless the operator asks.
Vendor updates and desktop releases run through `/update-yen` and need no entry here.

### Always-on sessions: persistent panes, reachable from any Mac over Tailscale

Goal: a YEN pane keeps running when the app quits, crashes or updates, and the user can attach to it from another Mac on their tailnet.
Local shell persistence ships in v1.275; see `_docs/01-architecture.md` → Persistent sessions.
Facts the plan builds on:
- Each pane already persists a stable `UUID` in restore state (`SurfaceView_AppKit.swift` encodes `uuid`), so it can name a session.
- Upstream split drag-and-drop already exists (`TerminalSplitTreeView.swift` drop zones).
- The session backend is zmx (`_docs/00-foundation.md` → Decisions), vendored by `scripts/48-vendor-zmx.sh` against YEN's engine and bundled at `Contents/Resources/bin/zmx`; a zmx client works over any PTY, so remote attach can reuse it through SSH.
Product boundaries hold: no YEN account, no YEN relay, no terminal content sent to YEN; remote traffic goes only between the user's own machines over Tailscale.

#### Phase 3: Remote attach over Tailscale

- [ ] Discover peers from the installed Tailscale (`tailscale status --json`); do not embed Tailscale or `tsnet`.
- [ ] Attach to a remote Mac's sessions over Tailscale SSH, with YEN installed on both ends, and label remote panes and tabs with the host.
- [ ] Reconnect automatically after sleep, a network change or a dropped link, without losing the remote session.
- [ ] Add a Hosts view (palette and tab sidebar) that lists each peer's sessions.
- [ ] Write the threat model into `_docs/04-security.md`: who can attach, what the daemon socket exposes, and how Tailscale ACLs gate it.
- [ ] Document the Tailscale data flow in public `/docs`, `public/llms.txt`, privacy and terms.

#### Phase 4: Window chrome and split design pass

Owner docs: `_docs/02-design-system.md` and `_docs/13-desktop-features.md`.

- [ ] Show session state (live, detached, remote host) in tabs and the tab sidebar.

#### Phase 5: Docs and release

- [ ] Document and release remote attach and window changes when their phases are complete.

### Token usage in the macOS menu bar

Add one switch in Settings → General → Menu Bar, between Panes and Links.
When enabled, the YEN status item shows today's combined local token count and opens the provider breakdown.
The first four rows represent tools: Claude Code, Codex, Grok Build (labeled Grok), and OpenCode.
JP the Cat and YEN can run independently or together.

#### Phase 1: Choose the dropdown

- [ ] Review the [interactive designs](_design/token-menu/index.html) with populated, partial and empty sample data.
- [ ] Choose Overview (provider share), Activity (hourly counts), or Compact (exact counts).
- [ ] Approve the local calendar day, inclusion of cache tokens, and the distinction between a measured zero and an unavailable source.

#### Phase 2: Port local counting

Use the MIT-licensed readers and accounting tests from `8bittts/JPtheCat` at `90d87ee6` as the starting point.
Keep the upstream notice with copied sources and in the distributed app.
Port only the parsing, deduplication and cursor logic needed by these four rows into YEN's macOS overlays.

| Row | Local source and accounting |
| --- | --- |
| Claude Code | Stream assistant usage from project JSONL. Deduplicate replayed message and request IDs and count uncached input, output, cache writes and reads once. |
| Codex | Reconcile cumulative token snapshots from rollout JSONL. Preserve resume, fork and reset handling. Cached input and reasoning output are already subsets. |
| Grok | Read completed Grok Build turns from session updates. Preserve per-model deduplication and the reader's cache and reasoning rules. |
| OpenCode | Read assistant token columns from the local SQLite store in read-only mode. Support the legacy log where it supplies counts. Select one source and count each message once across gateways and model brands. |

- [ ] Test fixtures against the JP readers for repeated, partial, corrected, rotated and malformed records and both supported OpenCode table shapes.
- [ ] Group by recording tool, independent of model name or shell host, and reconcile the four rows to the exact total before display rounding.
- [ ] Use the user's local calendar for day boundaries, including midnight, sleep, timezone changes and daylight saving transitions.
- [ ] Distinguish a readable source with zero activity, a missing source, a temporarily locked or unreadable source, and a scan in progress.
- [ ] Read usage locally without a YEN account, JP installation, hooks, provider credentials, network requests or writes to either app's provider data.

#### Phase 3: Connect Settings and the status item

- [ ] Add one persisted switch, **Show Token Usage**, to the General pane in `SettingsStudioPanes.swift`, using YEN's preference and reset paths.
- [ ] Default to off. At first enable, create one YEN template-icon status item and start one cancelable collector after the UI responds.
- [ ] Show the last available snapshot while updating, label partial totals, and display an unavailable state when there are no readable sources.
- [ ] On disable, reset or quit, cancel pending work, release watchers, file handles and views, and discard late results after rapid off/on changes.
- [ ] Keep the status item independent of windows, panes, dictation's status item and JP's own defaults, cache, hooks, menu and updater.

#### Phase 4: Prove the resource budget and native behavior

- [ ] Compare a ReleaseFast control against feature-off, enabled idle, cold discovery, incremental updates and repeated enable/disable on the same Mac and fixture.
- [ ] Require zero feature-owned reads, watchers and timers while off. While enabled, watch the allowed roots once per app, coalesce changes, and discover newly created sources without rescanning history on a timer.
- [ ] Stream bounded batches on one utility worker. Checkpoint offsets and SQLite watermarks atomically with totals in YEN-owned storage. Bound deduplication state on disk and keep only display aggregates in memory.
- [ ] Profile physical footprint, wakeups, bytes read and terminal input-to-draw latency during large appends. Proposed targets above the control are at most 8 MiB at rest and 32 MiB during ingestion. Require a memory plateau across repeated toggles and typing latency within the control run’s variation. Record host load, repetitions and ranges before accepting the native implementation.
- [ ] In a re-identified running YEN build, verify settings order, relaunch, reset, keyboard and VoiceOver navigation, light/dark appearance, sleep/wake and coexistence with JP and dictation. Update the desktop, architecture, privacy and public feature docs and run the declared gates before release.

### Hand-written `copy-on-select = true` no longer reaches the system clipboard

Upstream `f08437b79` maps `true` to `primary` on macOS instead of `clipboard`, so a config line `copy-on-select = true` copies only to the private selection pasteboard and Cmd+V no longer receives the selection.
`parsedCopyOnSelect` in `SettingsController.swift` still shows that line as on; Settings itself writes `both` or `false`, so only hand-edited configs are affected.
Upstream also added the Config.zig test `copy-on-select default uses the selection clipboard on Linux and macOS`, which fails against YEN's `.both` default; no YEN gate runs it.

- [ ] Decide whether YEN treats `true` as `both` on macOS (patch or Settings migration), then add a test for the chosen behavior.

### An external config reload can discard a pending Settings edit

`handleExternalConfigReload` re-reads managed state from disk while a real-time config sync is still inside its 180 ms debounce, so the debounced write then persists the re-read values and the edit is lost.
The theme path is fixed (`ThemePreviewCoordinator.restorePendingSelection`); the real-time path is not.

- [ ] Flush the pending real-time config sync before the re-read, with a visible-window regression test.

### Third-party notices in the app bundle

Owner doc: `_docs/04-security.md`.

- [ ] Ship the MIT notices for Ghostty and the bundled tools inside `YEN.app`, because MIT requires the notice in every copy; reconcile it with the fingerprint gates, which reject the upstream name in the bundle.

---
## WAIT-GATED

Do not start these until the trigger fires.

- **Ghostty forge migration.** Destination/timeline still TBD (https://mitchellh.com/writing/ghostty-leaving-github). When announced, recover the one-shot plan from the private pre-open-source history (then-named `docs/00-todos.md`) and re-validate against the actual forge. Plumbing already lives in `scripts/lib/upstream.sh`. The `/update-yen` vendor phase stops working when upstream leaves GitHub, so this is maintenance work.
- **Scripted `send key` warnings.** Upstream does not derive `send key` text from the active keyboard layout and marks it with six `Issue.record(severity: .warning)` calls in `ScriptKeyEventCommandTests`, the whole 6-warning baseline of a clean native run. When a vendor bump makes the warnings disappear, update the baseline in `_docs/09-quality.md` → Native Test Suite.
