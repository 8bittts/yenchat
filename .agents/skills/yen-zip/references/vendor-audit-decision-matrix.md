# Audit Decision Matrix

Conflict resolution patterns for vendor update audits. Default to the smallest change that restores the gate; name any hardening idea in the run summary, because maintenance mode keeps it out of `_docs/todos.md`.

## Ghostty Source Updates

### Overlay Conflicts

| Conflict Type | Resolution | Priority |
|--------------|------------|----------|
| Upstream renamed or moved a file we overlay or patch | Update the overlay path or `patch_file` target in `apply-overlays.sh` | P0 — blocks build |
| Upstream changed a function signature in patched code | Re-anchor the `.old`/`.new` pair to the new signature | P0 — blocks build |
| Upstream split a file we overlay | Decide which fragment carries the overlay; update references | P0 — blocks build |
| Upstream rewrote a patch's anchor block (drift) | Re-anchor with the minimum edit; do not widen the patch | P1 — blocks vendor run |
| Upstream adopted an equivalent (or stricter) of an existing patch | Retire it via the Overlay Retirement Checklist in `vendor-audit.md` Layer 6 | P1 — blocks vendor run |
| Upstream changed hit-testing / responder-chain / event monitor code | Audit coordinate spaces and pane ownership; add or update targeted regression coverage before shipping | P1 — blocks functionality |
| Upstream added new "Ghostty" references | Add a branding rule or exclusion in `apply-overlays.sh` | P1 — blocks branding check |
| Upstream changed a config default we override | Confirm the override still applies; update `config.yen` mapping if needed | P2 — may affect UX |
| Upstream added a feature | Evaluate for YEN; document in the audit doc | P3 — informational |
| Upstream removed a feature we use | Assess impact; defensive guard or overlay | P1 — blocks functionality |

### Patch Priority Order

When multiple patches conflict: build-critical, then security (entitlements, signing, updater floor), then branding, then behavior, then cosmetic.

### Swift Concurrency Conflicts

| Pattern | Resolution |
|---------|------------|
| `@MainActor` isolation error | Add `@MainActor` to the class or method, or `nonisolated` to the callback, in the overlay source |
| `@Sendable` coercion warning | Use the async API variant (for example `UNUserNotificationCenter.add(request)`) |
| Static property initializer error | Use explicit type qualification, not `Self.` |
| x86_64-only error | The local smoke build catches it; the DockTilePlugin gate is arm64-only |

## Binary Vendor Updates

| Conflict Type | Resolution |
|--------------|------------|
| Binary interface changed | Confirm the CLI flags YEN's plugins and scripts use still work |
| New runtime dependency | Verify it is bundled or present on the deployment target |
| Minimum macOS raised | Compare against YEN's deployment target before adopting |
| Binary size grew materially | Record in `_docs/04-security.md`; decide whether acceptable |

## Decision Escalation

1. Change touches a file we overlay or patch → P0.
2. Change affects user-visible behavior → P1.
3. Change is purely internal → P3.
4. When in doubt, treat as P1 and investigate before proceeding.
