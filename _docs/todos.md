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

YEN is in maintenance mode (`_docs/00-foundation.md` → Decisions) except for the always-on sessions feature below.
Apart from that feature, this list holds only bug fixes and security work; other new features, redesigns, refactors, performance work and growth work stay out of scope unless the operator asks.
Vendor updates and desktop releases run through `/yen-zip` and need no entry here.

### Always-on sessions: persistent panes, reachable from any Mac over Tailscale

Goal: a YEN pane keeps running when the app quits, crashes or updates, and the user can attach to it from another Mac on their tailnet.
Today `window-save-state = always` restores windows, tabs, splits and working directories, but every shell is a child of the app process and dies with it.
Facts the plan builds on:
- Each pane already persists a stable `UUID` in restore state (`SurfaceView_AppKit.swift` encodes `uuid`), so it can name a session.
- Upstream split drag-and-drop already exists (`TerminalSplitTreeView.swift` drop zones).
- The session backend is zmx (`_docs/00-foundation.md` → Decisions); a zmx client works over any PTY, so remote attach can reuse it through SSH.
Product boundaries hold: no YEN account, no YEN relay, no terminal content sent to YEN; remote traffic goes only between the user's own machines over Tailscale.

#### Phase 1: Operator review of the backend decision

- [ ] The operator approves zmx as the backend (`_docs/00-foundation.md` → Decisions) before Phase 2 starts.

#### Phase 2: Local persistent sessions

- [ ] Vendor zmx as a pinned source build (`scripts/lib/vendor-manifest.sh`), bundled under `Contents/Resources/bin`, with its libghostty-vt built from YEN's vendored mirror so replay and rendering share one engine; reconcile the release fingerprint scan, because the spike binary carries the upstream name three times.
- [ ] Start every new pane as an attach to session `<pane UUID>`, and reattach on restore; the macOS layer must pass the restore `UUID`, because `YEN_SURFACE_ID` is a random per-run number (`Surface.zig`).
- [ ] Keep the session socket directory short: a Unix socket path caps at 104 bytes, and zmx refused a long `ZMX_DIR` with `NameTooLong`.
- [ ] Define lifecycle: closing a pane or tab ends its session; quitting, crashing or updating the app only detaches.
- [ ] Handle a session that the restore state no longer names (list it, then reap after a timeout) and a restore entry whose session died (start a fresh shell in the saved directory).
- [ ] Restore the pane title and working directory after reattach (the spike's relaunched pane showed the title `YEN`, not `~`, because replay restores the screen, not OSC state), and pass through shell integration, the `yen` CLI, dictation paste, Secure Input and the Quick Terminal.
- [ ] Handle a daemon/app version mismatch across `/yen-zip` updates without killing live sessions.
- [ ] Add `yen sessions` (list, attach, kill) to the bundled CLI and a Settings toggle.
- [ ] Prove it in a running re-identified `zig-out` copy: quit, force-kill and update each leave the session alive; add regression tests for lifecycle and restore mapping.

#### Phase 3: Remote attach over Tailscale

- [ ] Discover peers from the installed Tailscale (`tailscale status --json`); do not embed Tailscale or `tsnet`.
- [ ] Attach to a remote Mac's sessions over Tailscale SSH, with YEN installed on both ends, and label remote panes and tabs with the host.
- [ ] Reconnect automatically after sleep, a network change or a dropped link, without losing the remote session.
- [ ] Add a Hosts view (palette and tab sidebar) that lists each peer's sessions.
- [ ] Write the threat model into `_docs/04-security.md`: who can attach, what the daemon socket exposes, and how Tailscale ACLs gate it.

#### Phase 4: Window chrome and split design pass

Owner docs: `_docs/02-design-system.md` and `_docs/13-desktop-features.md`.

- [ ] Verify the upstream split drag-and-drop in the running app, then make the drag handle and drop zones easy to find.
- [ ] Design horizontal tabs and a tighter top bar that put the tab strip in the titlebar and give the terminal the reclaimed height.
- [ ] Show session state (live, detached, remote host) in tabs and the tab sidebar.

#### Phase 5: Docs and release

- [ ] Update public `/docs`, `public/llms.txt`, privacy and terms for the daemon, the LaunchAgent and the Tailscale data flow.
- [ ] Write release copy in `lib/release-notes/release-notes-copy.ts`, regenerate release notes, and ship through `/yen-zip`.

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

- **Ghostty forge migration.** Destination/timeline still TBD (https://mitchellh.com/writing/ghostty-leaving-github). When announced, recover the one-shot plan from the private pre-open-source history (then-named `docs/00-todos.md`) and re-validate against the actual forge. Plumbing already lives in `scripts/lib/upstream.sh`. The `/yen-zip` vendor phase stops working when upstream leaves GitHub, so this is maintenance work.
- **Scripted `send key` warnings.** Upstream does not derive `send key` text from the active keyboard layout and marks it with six `Issue.record(severity: .warning)` calls in `ScriptKeyEventCommandTests`, the whole 6-warning baseline of a clean native run. When a vendor bump makes the warnings disappear, update the baseline in `_docs/09-quality.md` → Native Test Suite.
