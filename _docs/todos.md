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

Maintenance scope and approved exceptions are in [AGENTS.md](../AGENTS.md#maintenance-mode).
Routine releases and vendor updates run through `/update-yen`.

### Verify remote sessions on two Macs

Use a build containing the pending-check fixes on the attaching Mac and a disposable session on the peer.

- [ ] Under a due Tailscale SSH check, leave the pane waiting for at least one minute before approving.
  Confirm the link appears once, the same pane attaches, and a later link drop returns to the same running session.
  On a separate due check, deny approval and confirm the attach stops with exit 17.
- [ ] Through the peer's Tailscale SSH server, induce a partial listing in a disposable fixture.
  Confirm the valid rows remain visible and the listing reports an error.
- [ ] Drop the connection to a disposable session, end that session locally on the peer, and reconnect through Tailscale SSH.
  Keep the link down through the 30-second retry interval and check the tab's reconnecting indicator.
  Confirm the pane explains that the session ended and waits for Return once the link returns.
- [ ] Use a temporary known-hosts file with a mismatched key for the test peer.
  Confirm listing exits 15 and Hosts reports the change without modifying the user's trust settings.

Record the observed outcomes in the commit that closes each item.

---
## WATCH

- Check on occasion whether Ghostty has left GitHub (https://mitchellh.com/writing/ghostty-leaving-github); the `/update-yen` vendor phase breaks when it does, and `scripts/lib/upstream.sh` holds the forge plumbing.
