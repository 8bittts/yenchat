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

YEN is in maintenance mode (`_docs/00-foundation.md` → Decisions) with the operator-approved sessions work below.
Apart from that feature, this list holds only bug fixes and security work; other new features, redesigns, refactors, performance work and growth work stay out of scope unless the operator asks.
Vendor updates and desktop releases run through `/update-yen` and need no entry here.

### Always-on sessions: persistent panes, reachable from any Mac over Tailscale

A YEN pane keeps running when the app quits, crashes or updates, and the user attaches to it from another Mac on their tailnet (`_docs/01-architecture.md` → Persistent sessions; threat model in `_docs/04-security.md`).
Local persistence ships in v1.275; remote attach and everything built on it are on `main` for the next release.

- [ ] See the app's Hosts rows and an attach pane while a Tailscale SSH `check` approval is pending.
  The CLI's exit 17 has run on a real tailnet, and so has discovery from a Mac on the open-source `tailscaled` (`_docs/04-security.md` → Remote Attach Threat Model).
  The operator's plan allows only the default 12-hour check period, so run it once that period has passed since the last approval, from the app to a peer on Tailscale SSH under a `check` rule.

---
## WATCH

- Check on occasion whether Ghostty has left GitHub (https://mitchellh.com/writing/ghostty-leaving-github); the `/update-yen` vendor phase breaks when it does, and `scripts/lib/upstream.sh` holds the forge plumbing.
