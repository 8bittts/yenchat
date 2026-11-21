# Vendor Audit (Step V3) — 6-Layer Breaking Change Audit

The audit decides whether upstream changes break YEN's customizations. Record one `LAYER n: <finding>` line per layer in `$AUDIT_LOG` as you go; `verify-audit-layers.sh` fails closed without them.

## Layer 1: Overlay Health (Ghostty only)

**Question:** did every `apply-overlays.sh` patch apply, and does the script re-apply idempotently?

The update run already applied overlays once. Re-run it to prove idempotency, then run the overlay regression suite:

```bash
bash $HOME/Documents/yenchat/yen-terminal/apply-overlays.sh
bun test tests/45-overlay-patching.test.ts
```

`tests/45` proves apply/idempotence/fail-closed behavior. It does not replace semantic review when upstream touches AppKit hit testing, coordinate conversion, responder-chain focus, or local event monitors.

**If a patch failed (anchor drift):** repair with the smallest change that restores the gate, then re-run only Step V2.
- Read upstream's change from the forge compare range (`<baseline>...<new>`), not from the local tree.
- Anchor still exists in a new shape → update the `.old`/`.new` pair in `scripts/lib/patches/` and the `--marker`.
- Upstream now does what the patch did → retire it (checklist in Layer 6). If the retired patch protected an invariant, keep the invariant as a fail-closed assertion only when the gate needs it.
- Hardening beyond that (shared libraries, extra release gates, broader suites, tool refreshes) is not part of the vendor phase; name it in the run summary, because maintenance mode keeps it out of `_docs/todos.md`.

## Layer 2: Structural Changes (Ghostty only)

**Question:** did upstream rename, split, or move files our overlays depend on?

After overlays are applied, `ghostty/` equals `overlays/` for every overlaid file, so a post-overlay diff is always empty and proves nothing. Read the pre-overlay gate receipts from the update output instead:

```bash
OUT=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-update.out
/usr/bin/grep -E 'Overlay pairs: [0-9]+ tracked|build.zig: only YEN customization diverges|RAN\|structural-diff' "$OUT"
```

Then inventory targets, feature directories, and pbxproj membership (use `/usr/bin/...` paths — the operator shell aliases `sed`, `grep`, `find`, and `ls`):

```bash
xcodebuild -project $HOME/Documents/yenchat/yen-terminal/ghostty/macos/YEN.xcodeproj -list 2>/dev/null | /usr/bin/grep -A8 'Targets:'
/bin/ls $HOME/Documents/yenchat/yen-terminal/ghostty/macos/Sources/Features/
/usr/bin/grep -c 'PBXFileSystemSynchronizedBuildFileExceptionSet' $HOME/Documents/yenchat/yen-terminal/ghostty/macos/YEN.xcodeproj/project.pbxproj
/usr/bin/grep -E '^\t+[A-Za-z].*\.swift' $HOME/Documents/yenchat/yen-terminal/ghostty/macos/YEN.xcodeproj/project.pbxproj | /usr/bin/sed 's/[\",;]//g; s/^[[:space:]]*//' | sort -u | while read -r p; do [ -f "$HOME/Documents/yenchat/yen-terminal/ghostty/macos/Sources/$p" ] || echo "MISSING: Sources/$p"; done
```

New targets need signing in `finalize-build.sh`, branding validation, and overlay handling if they import types YEN defines. Fragile overlays to check by name: `TerminalCommandPaletteCatalog.swift` (action catalog), `AppDelegate.swift` (whole file), `YENCustomResources.zig`, `YENCustomNotifications.swift`, and every `patch_file` target in `apply-overlays.sh`.

## Layer 3: Branding Residue

```bash
bash $HOME/Documents/yenchat/scripts/04-verify-branding.sh
```

Read the receipt: `RECEIPT gate=04-verify-branding ... result=PASS` with `guarded-subjects present=N/N` and `upstream-path-manifest resolved=N/N`. Accepted residues are listed in `_docs/04-security.md` → Upstream Branding Residues.

## Layer 4: Config and Feature Audit

Review the compare range for new config keys (map in `config.yen`), changed defaults, removed features, and new keybind defaults. Then confirm the anchors YEN overrides are still present:

```bash
/usr/bin/grep -n 'window-save-state\|copy-on-select\|toggle_quick_terminal\|Shift+Enter' $HOME/Documents/yenchat/yen-terminal/ghostty/src/config/Config.zig
/usr/bin/grep -n 'Preserve the current selection state on right-click and\|\.@"context-menu"' $HOME/Documents/yenchat/yen-terminal/ghostty/src/Surface.zig
/usr/bin/grep -r 'toggle_\|new_\|show_' $HOME/Documents/yenchat/yen-terminal/ghostty/src/input/Binding.zig | head -20
```

If the range touched AppKit input routing, review the current source explicitly:

```bash
/usr/bin/grep -Rnw 'hitTest\|locationInWindow\|addLocalMonitorForEvents\|mouseDown\|mouseUp\|firstResponder\|becomeFirstResponder' $HOME/Documents/yenchat/yen-terminal/ghostty/macos/Sources 2>/dev/null | head -40
```

Confirm before continuing: every `NSPoint` is used in the coordinate space it was converted for; descendant hits inside a pane still belong to that pane; sibling overlays above a pane do not steal ownership unless intended; targeted coverage exists (`yen-terminal/overlays/macos/Tests/Splits/SplitFocusClickHitTestingTests.swift`, `tests/45-overlay-patching.test.ts`). Treat any change here as P1: the split-focus regression that motivated this check came from upstream reusing a surface-local point with `window.contentView.hitTest(...)`.

New command-palette actions merge into `TerminalCommandPaletteCatalog.swift`; preserve the overlay's `actionCatalog` / `PaletteActionDescriptor` groupings.

## Layer 5: Compile Gate Selection (HARD GATE)

After a Ghostty refresh, or whenever `YENKit.xcframework` is missing or incomplete, or the Xcode project or a linked package changed, Step V4's local smoke build is the compile gate. Do not run it here and again in Step V4.

For non-Ghostty updates with an intact xcframework, a standalone compile check is a valid early gate, judged by its positive result line and exit code — never by the absence of `error:`:

```bash
xcodebuild -project $HOME/Documents/yenchat/yen-terminal/ghostty/macos/YEN.xcodeproj -scheme YEN -configuration Debug -sdk macosx build 2>&1 | tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-xcodebuild.out | /usr/bin/grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*|error:'
```

`** BUILD SUCCEEDED **` is the pass. Common failures: Swift concurrency isolation (x86_64 is stricter), renamed upstream APIs, new `@MainActor` requirements, transient Zig fetch flakes (retry), and coordinate/responder bugs that compile cleanly (caught only in Layer 4).

## Layer 6: Decision and Documentation

1. `_docs/04-security.md` — `14-vendor.sh` already synced the snapshot metadata and overlap header via `11-sync-vendor-audit.sh`; run `bash $HOME/Documents/yenchat/scripts/12-verify-vendor-audit.sh` to confirm. Hand-edit the Source Patches table and overlap notes only when a patch, risk, or watch item changed.
2. Skill docs — if upstream-source, forge-adapter, parity-harness, or vendor-gate behavior changed, update the `/update-yen` `SKILL.md` and the affected `references/vendor-*.md` in the same commit.
3. Memory — a new pattern (anchor shape, API shift, retirement) goes into the `vendor-workflow` memory file, not the `MEMORY.md` index.
4. Baselines — already written by the vendor scripts.

### Overlay Retirement Checklist

When upstream adopts a patch's behavior (or a stricter equivalent), update these surfaces atomically in one commit:

| # | File | Change |
|---|------|--------|
| 1 | `yen-terminal/apply-overlays.sh` and `scripts/lib/overlay-phases/*.sh` | Replace the `apply_overlay_patch <name>` call (find it with `command grep -rn '<name>' scripts yen-terminal/*.sh`) with a `RETIRED:` comment naming the upstream commit and reason. Keep a fail-closed assertion only if the gate needs the invariant. |
| 1b | `scripts/lib/overlay-patch-plan.json` | Delete the operation entry. Removing only this entry fails the run with `unknown patch operation` while the call in row 1 remains. |
| 2 | `scripts/lib/patches/<name>.{old,new}` | Delete the payloads so a reintroduced label cannot resolve against a leftover block. |
| 3 | `scripts/04-verify-branding.sh` | If a check guarded the patch, retarget it to upstream's new shape instead of deleting it. If none existed, add one only when the invariant must hold at release time. |
| 4 | `_docs/04-security.md` | Remove or rewrite the row in the Source Patches table. |
| 5 | `tests/45-overlay-patching.test.ts` | Replace the wired/idempotent tests with one retirement-marker test asserting the label, anchors, and payloads are gone. Behavioral coverage of any replacement assertion goes in `tests/123`. |

Re-run `bun test tests/45-overlay-patching.test.ts` afterwards, and run `bun run check` before the commit: a hand-edited test file can fail Biome formatting, and `bunx biome format --write <file>` fixes it.

## Binary and Source-Built Vendors (Layers 3-6)

- **Yazi:** `for f in $HOME/Documents/yenchat/yen-terminal/customizations/yazi-config/plugins/*/*.lua; do luac -p "$f"; done`; `bun test tests/35-yazi-config.test.ts`; `$HOME/Documents/yenchat/yen-terminal/customizations/vendor/yazi/yazi --version`; `yazi` and `ya` update together; if upstream adds a native `<S-Enter>` binding, re-evaluate YEN's terminal-level Shift+Enter mapping.
- **CLI tools (fd, ripgrep, fzf, zoxide, bat, jq, lazygit, delta, resvg, btop, fastfetch, zmx):** flags used by Yazi plugins and shell scripts still valid; output formats consumed by preview plugins unchanged; `lipo -archs` lists both arm64 and x86_64 (the scripts enforce it); lazygit stays a pure vendor with `customizations/lazygit/config.yml` intact.
- Read the upstream release notes for the new version and record the impact in the audit log.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VA-01 | Overlays re-apply idempotently | `bash $HOME/Documents/yenchat/yen-terminal/apply-overlays.sh` |
| VA-02 | Overlay patch regression gate | `bun test tests/45-overlay-patching.test.ts` |
| VA-03 | Branding clean, with a `result=PASS` receipt | `bash $HOME/Documents/yenchat/scripts/04-verify-branding.sh` |
| VA-04 | Every required layer has a recorded finding | `bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/verify-audit-layers.sh <vendor> "$AUDIT_LOG"` |
