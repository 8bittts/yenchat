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

A YEN pane keeps running when the app quits, crashes or updates, and the user attaches to it from another Mac on their tailnet (`_docs/01-architecture.md` → Persistent sessions; threat model in `_docs/04-security.md`).
Local persistence ships in v1.275; remote attach, Hosts and the tab session icons are on `main` for the next release.

- [ ] Show on a remote tab and its sidebar row that the pane is reconnecting.
  The CLI's reconnect loop needs to signal the app without a per-render process or file read.
- [ ] Run remote attach on the Tailscale setups it has never met: MagicDNS off (the IP-address target), Tailscale SSH on the peer, an ACL `check` rule, and the open-source `tailscaled`.
  Each needs a change to the operator's tailnet or to the peer's Tailscale install, so the operator chooses which to stage.

### Experimental moving wallpaper

- [ ] Keep a Per Desktop wallpaper on an external display across an unplug and replug.
  After a replug macOS gives the display a new Space id, and the assignment keyed to the old id shows nothing; All Desktops mode is untested with a replug.
  Verify the fix with a real unplug in a signed copy.

---
## WAIT-GATED

Do not start these until the trigger fires.

- **Ghostty forge migration.** Destination/timeline still TBD (https://mitchellh.com/writing/ghostty-leaving-github). When announced, recover the one-shot plan from the private pre-open-source history (then-named `docs/00-todos.md`) and re-validate against the actual forge. Plumbing already lives in `scripts/lib/upstream.sh`. The `/update-yen` vendor phase stops working when upstream leaves GitHub, so this is maintenance work.
