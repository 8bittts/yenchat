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
- [ ] Lower the cost of the first analytics read: a standalone harness took 29 s and peaked at 195 MB resident on 6.2 GB of Claude Code records, with Codex rollouts alone at 107 MB and a 97 MB scan database in the temporary folder; later reads took under 0.1 s.
- [ ] Validate day rollover, locked databases, concurrent provider writes and repeated toggles in the release candidate.

### Experimental moving wallpaper

- [ ] Verify the Photos picker, multi-display Spaces and power-state changes before desktop release.

---
## WAIT-GATED

Do not start these until the trigger fires.

- **Ghostty forge migration.** Destination/timeline still TBD (https://mitchellh.com/writing/ghostty-leaving-github). When announced, recover the one-shot plan from the private pre-open-source history (then-named `docs/00-todos.md`) and re-validate against the actual forge. Plumbing already lives in `scripts/lib/upstream.sh`. The `/update-yen` vendor phase stops working when upstream leaves GitHub, so this is maintenance work.
