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

YEN is in maintenance mode (`_docs/00-foundation.md` → Decisions) with the operator-approved sessions, token usage and experimental wallpaper work below.
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

- [ ] Measure idle and peak memory, wakeups and input-to-draw latency against a ReleaseFast control on representative large histories.
- [ ] Lower the cost of the first analytics read: a standalone harness took 29 s and peaked at 195 MB resident on 6.2 GB of Claude Code records, with Codex rollouts alone at 107 MB; later reads took under 0.1 s.
- [ ] Validate day rollover, locked databases, concurrent provider writes and repeated toggles in the release candidate.
- [ ] Connect a real personal Cursor API key in a signed build and confirm both Cursor pools, the Grok Bot pool and Disconnect; only mocked responses and a rejected key have run.

### Experimental moving wallpaper

- [ ] Verify Photos picker and shuffle permissions, multi-display Spaces and power-state changes before desktop release.

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

### IDE CLI tests time out on a loaded machine

`tests/84-ide-s3c-lsp-foundation.test.ts` and `tests/88-ide-s3d-devcontainer-vscode-ast.test.ts` each failed once in a full `bun test` run while the load average was 10 to 14, and each passes alone.
In 84 a `runYen` call returned `status: null` at the 5-second test limit; in 88 the `ide-temp` cleanup hook timed out after the test took 28 seconds.
`tests/100-ide-s3n-benchmark-harness.test.ts` failed the same way at load 14 ("benchmark status reports missing evidence on a fresh state dir": a hook timed out after 7.5 seconds) and passes alone.
`tests/75-ide-s2-controls.test.ts` failed the same way at load 9 ("merge-readiness reports a no-PR snapshot without inventing a second trust surface": a hook timed out after 8.8 seconds) and passes alone.

- [ ] Reproduce under generated load, then give the spawned CLI calls and the cleanup hook a limit that holds without hiding a real hang.

---
## WAIT-GATED

Do not start these until the trigger fires.

- **Ghostty forge migration.** Destination/timeline still TBD (https://mitchellh.com/writing/ghostty-leaving-github). When announced, recover the one-shot plan from the private pre-open-source history (then-named `docs/00-todos.md`) and re-validate against the actual forge. Plumbing already lives in `scripts/lib/upstream.sh`. The `/update-yen` vendor phase stops working when upstream leaves GitHub, so this is maintenance work.
