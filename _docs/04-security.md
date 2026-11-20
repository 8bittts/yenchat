# Security

Upstream overlap, fail-closed vendor gate contracts and the bundled binary inventory that make up the supply-chain posture of YEN; the product privacy boundary is in AGENTS.md.

The `/yen-zip` vendor phase owns the procedure; this file owns what each bump is checked against.
Yazi runtime and plugin behavior live in `_docs/14-file-browser.md`.

## Sources of truth

- `scripts/lib/vendor-manifest.sh` — the single vendor roster.
- `yen-terminal/.*-baseline` — pinned versions and integrity fields; written by the vendor scripts, never by hand.
- `scripts/lib/upstream.sh` — every Ghostty upstream URL.
- `yen-terminal/apply-overlays.sh`, `scripts/lib/patch-file.py`, `scripts/lib/patches/` — source patches.
- `yen-terminal/.overlay-upstream-pairs.txt` — upstream SHA-256 of every file a whole-file overlay replaces.
- `scripts/lib/fingerprint-allowlist.txt` — accepted artifact residues.
- `scripts/lib/gate-roster.txt` and `scripts/lib/units/` — the gate receipt roster.

`scripts/11-sync-vendor-audit.sh` rewrites the snapshot block and the overlap commit sentence.
`scripts/12-verify-vendor-audit.sh` fails the build when either drifts from the baselines.
Hand-edit only the tables and watch items.

## Snapshot Metadata (Script-Validated)

```
snapshot_date=2026-11-20
ghostty_commit=9ad3c422222e45b32c5f9ab9f4cd32e0e3694ef7
ghostty_version=9ad3c422222e45b32c5f9ab9f4cd32e0e3694ef7
ghostty_upstream_repo=https://github.com/ghostty-org/ghostty.git
yazi_version=v26.9.1
fd_version=v10.5.2
ripgrep_version=15.2.0
fzf_version=v0.75.0
zoxide_version=v0.10.0
bat_version=v0.26.1
jq_version=jq-1.8.2
lazygit_version=v0.66.3
delta_version=0.21.2
resvg_version=v0.50.0
btop_version=v1.4.8
fastfetch_version=2.71.0
zmx_version=v1.0.1
```

`ghostty_upstream_repo` is gated so a forge change cannot silently move the upstream source of truth.

## Upstream Coordinates

Every Ghostty URL in `/yen-zip` resolves through the `upstream_*` helpers in `scripts/lib/upstream.sh`.
`YEN_UPSTREAM_HOST`, `YEN_UPSTREAM_OWNER`, `YEN_UPSTREAM_REPO` and `YEN_UPSTREAM_FORGE` exist only for parity tests and a forge cutover.
`forge_github` is the only adapter; the forge migration is wait-gated in `_docs/todos.md`.
Before any upstream-plumbing change, run `scripts/40-vendor-parity-snapshot.sh --baseline <path>`, then `--verify <path>` after it.
Contract test: `tests/124-upstream-lib-contract.test.ts`.

## Ghostty Rollback History

`14-vendor.sh` warns when the fetched `current...main` range overlaps a row here; `YEN_VENDOR_BLOCK_ON_ROLLBACK=1` turns the warning into a stop.
Record the oldest SHA prefix of the reverted range so the `commits ahead` matcher can detect overlap.
Delete a row once the range has re-landed cleanly.

| Rollback commit | Date | Vendor | Rolled-back range | Reason |
|-----------------|------|--------|--------------------|--------|

## Upstream Ghostty Overlap Assessment

Audit of YEN customizations against upstream Ghostty (commit `9ad3c422`). Classification: [SAFE] no conflict, [WATCH] monitor upstream changes, [ACTION] needs work.

Per-bump assessments live in the vendor commit messages, not here.

### Config Default Overrides

| Key | YEN value | Upstream | Status |
|-----|-----------|----------|--------|
| `window-save-state` | `always` | `default` | [SAFE] Idempotent patch |
| `copy-on-select` (macOS) | `both`; Settings can write `false` | `primary` | [SAFE] |
| `scrollbar` (macOS) | `system`; Settings can write `never` | `system` | [SAFE] Visibility policy only, never a scroller-style control |
| `notify-on-command-finish` | `never`; Settings can write `unfocused` or `always` | `never` | [WATCH] `.claude/hooks/notify-complete.sh` self-suppresses only on `always` above threshold, so `unfocused` needs physical smoke for build-like workflows |
| Quick Terminal keybind | `Ctrl + Backtick` (global) | none | [WATCH] Conflicts if upstream adds a default `toggle_quick_terminal` bind |
| Shift + Enter | sends `\r` | raw escape sequence | [WATCH] Remove the injection if upstream adds first-class behavior |

### Source Patches (apply-overlays.sh anchors)

Exact block replacements use `scripts/lib/patch-file.py` with payloads in `scripts/lib/patches/`.
Structural patches use named helpers in `scripts/lib/`, never inline heredocs.
`scripts/42-lint-overlay-recurrence-gates.sh` fails if an inline `python3 - <<` heredoc returns to `apply-overlays.sh`; its allowlist stays empty.
Every anchor fails closed on drift; retire a patch with the checklist in `.agents/skills/yen-zip/references/vendor-audit.md`.

| Patch | Anchor | Risk | Retire or watch condition |
|-------|--------|------|---------------------------|
| `YEN_BIN_DIR` | `bin_dir` setup in `Exec.zig` | MEDIUM | Upstream refactors CLI path setup |
| Cursor style reload | `changeConfig()` in `stream_handler.zig` appends `terminal.setCursorStyle(.default)` | LOW | Keep permanently; upstream moved this guard three times |
| Runtime padding reload | `self.config = derived;` in `Surface.updateConfig()` | MEDIUM | Uses enum `WindowPaddingBalance` (`!= .false`) and 2-arg `balancePadding` |
| Selection repaint on release | copy-on-select release block in `Surface.mouseButtonCallback()` | MEDIUM | Retire if upstream adds an equivalent render wakeup |
| Right-click context-menu selection | `.@"context-menu"` right-click branch | MEDIUM | Self-contained, with a stale-block self-heal |
| Split-focus hit testing | `SurfaceView_AppKit.localEventLeftMouseDown()` + `SplitFocusClickHitTesting` | MEDIUM | Upstream adopted the coordinate conversion; retire when it accepts descendant hits (`isDescendant(of:)`) |
| Clipboard image bridge + paste routing | `NSPasteboard+Extension.swift` + `performKeyEquivalent(with:)` | MEDIUM | Images go to a private pruned temp root; `Cmd + V` routes through the resolved menu action |
| Surface route env | `SurfaceConfiguration` init block | MEDIUM | Stamps `YEN_SURFACE_ID` for notification routing |
| Command-finish managed delivery | `Ghostty.App.swift` notification helper | MEDIUM | Routes through `AppDelegate.deliverManagedSurfaceNotification(...)` |
| Terminal browser-link routing | `Ghostty.App.swift` hyperlink helper | MEDIUM | Keeps link decisions in YEN's browser-link policy |
| Notification callback cleanup | `SurfaceView_AppKit.swift` notification scheduling | MEDIUM | Captures `self` weakly |
| Undo-timeout default | `Ghostty.Config.swift` `undoTimeout` | LOW | Retire if the Swift bridge honors the missing-key fallback |
| Tab title restore invalidation | `titleOverride` didSet in `BaseTerminalController.swift` | MEDIUM | Retire if upstream dirties restorable state on rename |
| Resign-key focus deferral | `BaseTerminalController.windowDidResignKey(_:)` | MEDIUM | Defers `yen_surface_set_focus` to avoid re-entering the focus lock |
| Native fullscreen transition guard | `Fullscreen.swift`, `TerminalController`, `BaseTerminalController` delegates | MEDIUM | Also refuses `resizeWindow` while `window.yenIsEffectivelyFullscreen`; `NativeFullscreenTransitionTests` |
| MenuShortcutKey test access | `modifiersRawValue` in `Ghostty.MenuShortcutManager.swift` | LOW | Test-only; retire when upstream widens access |
| Tiered CLI action policy | `src/cli/yen.zig` policy block + `src/cli/help.zig` filter | MEDIUM | Fails closed on block-shape drift |
| Extra resource provenance URLs | `src/extra/vim.zig`, `src/extra/bash.zig` | LOW | [SAFE] |
| Transient file exclusions | `find` sweeps in `apply-overlays.sh` | LOW | [SAFE] Skips `.!*` and `._*` |
| `INFOPLIST_PREPROCESS` | pbxproj key | LOW | [SAFE] |
| Sparkle runtime floor | `XCRemoteSwiftPackageReference "Sparkle"`, parsed by `scripts/lib/sparkle-runtime-floor.sh` | LOW | Assertion only; fails closed below `SPARKLE_RUNTIME_FLOOR` |
| AppDelegate method parity | non-`AppDelegate` `appDelegate.method()` call sites | LOW | Fails if the method left `AppDelegate*.swift` |

### Upstream API Couplings (No Patch)

Overlays call these upstream interfaces directly; a signature change breaks the build or, worse, the behavior.

| Coupling | Caller | Breaks if |
|----------|--------|-----------|
| `appDelegate.yen.reloadConfig()` | `SettingsController.swift` | `Ghostty.App.reloadConfig(soft:)` changes |
| `surfaceModel?.sendKeyEvent()`, `YEN.Input.KeyEvent` | `AppDelegate+FileBrowser.swift` | The `KeyEvent` struct or `SurfaceView` model API changes |
| `MainMenu.xib` outlets | `MainMenu.xib` overlay | Upstream adds `@IBOutlet` menu items |
| `showOnboardingIfNeeded()` injection | `apply-overlays.sh` → `AppDelegate.swift` | `applicationDidFinishLaunching` or its `setupMenuImages()` chain moves |
| Window border hooks | `TerminalView.swift`, `TerminalViewBackgroundRuntime.swift` | Terminal view layering, window ownership, or key/fullscreen notification flow changes |
| Structural helpers | `scripts/lib/{apple-script-action-policy,native-fullscreen-helper,remove-wrapper-sendable,rewrite-pbxproj-membership-exclusions}.py` | An accepted source shape changes; each helper must fail closed, never skip |

### Swift Overlay Features vs Upstream

Pure YEN additions, no upstream counterpart: Dictation, Tab Sidebar, Screenshot, Onboarding, Layout Shortcuts, message toasts, Chromatic Window Border.
Upstream's only border behavior is per-surface `bell-features = border`, so the border remains overlay-only.

| Feature | Upstream | Watch |
|---------|----------|-------|
| Settings | `ConfigurationErrors` only | `apply-overlays.sh` rewrites the synchronized Xcode member list and emits the `YEN.ConfigTypes.swift` and `YENPackageMeta.swift` aliases DockTilePlugin needs |
| Command Palette | base palette | Whole-file `CommandPalette.swift` must keep symbols upstream tests reference (`CommandOptionMatch`, `filteredAndSorted`, `String.matchedIndices`) even though YEN never renders them; dropping them breaks only the test target |
| About window | upstream window | Overridden UI |

Merge new upstream palette actions into `TerminalCommandPaletteCatalog.swift` groupings each bump.
`move_tab_to_new_window` stays out of the palette because upstream marks it GTK-only.

### AppleScript Vendor Posture

YEN keeps upstream's AppleScript surface branded (`YEN.sdef`, `YENScript*`) and enabled (`macos-applescript = true`), with no Settings toggle.
The supported command set is the compatibility boundary for bumps; it is listed in `_docs/12-commands.md` → macOS AppleScript.
`perform action` uses the same allowlist as App Intents, so layout presets, scratchpad, tab sidebar and PR review are not AppleScript API.
Keep `yen-terminal/overlays/macos/YEN.sdef` identical to the branded build-tree dictionary.

### Persistent Memory-Leak Hardening (Vendor-Adjacent)

Re-check each of these when the owning file is re-synced:

- Bash shell integration deduplicates hooks with `__yen_append_unique_hook`.
- Bash and zsh shell integration delete the per-invocation SSH `ControlPath` temp directory.
- `pdf-native.yazi` and `video-native.yazi` bound their metadata caches to 512 entries.
- `git.yazi` caps tracked directory state at 2048 entries and prunes orphaned repo caches.
- `code-guard.yazi` downgrades very large or minified files to plain wrapped preview.

### Upstream Branding Residues (Accepted)

| Residue | Location | Why accepted |
|---------|----------|--------------|
| `Ghostty*.swift` filenames | `macos/Sources/YEN/` (count with `find ... -name 'Ghostty*.swift'`) | Content is branded; names keep pbxproj compatibility |
| `CustomIconGhost` asset | `Assets.xcassets/Custom Icon/` | Shown only with `macos-icon = custom-style` |
| `macos-icon-ghost-color` key, `ghostColor` property, "The color of the ghost" doc | `Config.zig`, icon Swift files | Renaming breaks config compatibility; not in normal UI |

### Public Documentation Branding

`scripts/04-verify-branding.sh` check 8d requires the in-app manual (`app/docs`) to remain lineage-neutral.
YEN is open source under MIT, so `README.md`, `public/README.md` and `public/llms.txt` credit Ghostty by name and are outside that check.
Internal engineering documentation and required artifact provenance are outside that copy boundary.

### Artifact Fingerprint Allowlist (Release Gate)

`scripts/13-scan-artifact-fingerprints.sh` runs from `scripts/05-detect-failures.sh` in `enforce` mode.
Any non-allowlisted `ghostty`, `com.mitchellh.ghostty`, upstream URL or provenance residue fails the release.
Allowlist entries are category- and path-scoped, and use `[0-9]+` for offsets so vendor bumps do not need edits.

| Path | Category | Why allowed |
|------|----------|-------------|
| `Resources/bin/lazygit` | `binary:ghostty` | `tcell` terminfo tables |
| `Resources/bin/yazi` | `binary:ghostty` | Terminal-brand detection table |
| `Resources/bin/fastfetch` | `binary:ghostty`, `binary:com_mitchellh_ghostty` | Terminal and font detection; the config path never resolves for YEN |
| `MacOS/yen` | `binary:ghostty` | Terminfo detection table |
| `MacOS/yen` | `binary:zig_global_cache` | Zig embeds cache paths |

A new Go binary built on `tcell` or Bubble Tea will need its own entry.

### High-Priority Watch Items

- **Targets.** YEN is macOS-only; upstream deleted the iOS target. DockTilePlugin is the only embedded target; a new upstream target needs signing in `finalize-build.sh`.
- **Anchor discipline.** Keep `apply-overlays.sh` on canonical upstream anchor shapes; never add compatibility branches for older shapes.
- **Whole-file overlays.** They are the most fragile overlays. The pairs tripwire catches upstream edits; port drift from the forge compare range, never from a local diff.
- **Build path.** `build-release.sh` owns `YENKit.xcframework` recreation and the Zig/Xcode workarounds. `yen-terminal/overlays/build.zig`, `yen-terminal/overlays/src/build/main.zig` and `yen-terminal/overlays/src/build/LibtoolStep.zig` are whole-file build-system overlays; `LibtoolStep.zig` must flatten `.a` inputs before `libtool -static`. A missing xcframework is not a Settings regression.
- **Provenance.** Binary assets must match GitHub release-asset SHA-256 metadata, source tags resolve to immutable archives, and Ghostty commits need verified forge status. A local first-download digest is not provenance.
- **pbxproj exception sets.** Branding renames `Ghostty*` paths in exception sets while files keep the `Ghostty` prefix; `apply-overlays.sh` restores them and needs new patterns when upstream adds files.
- **Shell integration resources.** Bundled scripts read `YEN_RESOURCES_DIR` only and fail closed without it; never restore `GHOSTTY_RESOURCES_DIR`. Judge branding from the built `Contents/Resources/yen/shell-integration/`, not the gitignored source.
- **Support floor.** While YEN supports macOS 13, stay on the Ghostty 1.3-compatible line.
- **Exposure gaps.** Settings exposes generic title editing, not upstream's separate window/tab title actions. Command palette border actions do not switch scope.
- **Theme discovery.** Runtime themes come from `~/.config/yen/themes` and bundled `Resources/yen/themes`; never restore migration from `~/.yen/themes`.
- **Stale verifier.** When a check fails after a bump, confirm the checked symbol did not just move in a YEN refactor before blaming upstream.
- **zmx builds against the vendored engine.** `scripts/48-vendor-zmx.sh` points zmx's engine dependency at a clone of `yen-terminal/ghostty`, records the engine commit plus a digest of the tracked YEN inputs that shape engine Zig sources (Zig overlays, engine-source patch blocks, the branding phases) as `build_input_id`, and builds stripped from one fixed path so the output pin reproduces; an engine bump rebuilds zmx and re-records the pin.
  The script also patches zmx to record each session's pty path in `<UUID>.tty` (password detection) and to send soft-wrapped rows unwrapped in its attach snapshot, so a new pane can reflow early output; `tests/164-zmx-snapshot-unwrap.test.ts` runs the vendored binary and fails if a zmx bump undoes the second.
  `14-vendor.sh` compares the recorded id with `48-vendor-zmx.sh --print-input-id`, because the zmx tag alone stays current across an engine bump; `tests/119-vendor-process-guardrails.test.ts` fails when the committed id drifts from the tree.
  After a pull that changes the zmx pin, the integrity gate refuses the old local binary until `./scripts/48-vendor-zmx.sh --force` rebuilds it; the build reproduces the pinned digest.
- **Source-built Rust vendors.** `fd` and `delta` dropped Intel macOS assets, so `scripts/16-vendor-fd.sh` and `scripts/35-vendor-delta.sh` cross-compile both slices and `lipo` them. If upstream restores `x86_64-apple-darwin` assets, return them to the `vendor-binary.sh` wrapper pattern and drop their `14-vendor.sh` prefetch entries.

### Fail-Closed Gate Contracts (Do Not Regress)

Every `/yen-zip` vendor and release gate is on `scripts/lib/gate-roster.txt`.
A gate declares its units in `scripts/lib/units/<gate>.units` and cannot print a passing `RECEIPT` unless each unit records `RAN|` with a measurement or `SKIP|` with a reason.
A skip route nobody anticipated fails because its unit goes unaccounted for.
`tests/145-gate-receipt-contract.test.ts` fails any roster entry not on the contract and fails on an empty roster.

Contracts the receipts do not cover by themselves:

| Gate | Contract | Guard |
|------|----------|-------|
| `10-update-ghostty.sh` | Runs `04-verify-branding.sh` before the baseline write, aborts if the verifier is missing, and restores `ghostty.backup` on failure. The `[3a/5]` structural diff runs only on a freshly downloaded tree | `tests/119` |
| `03-verify-components.sh` | Check 10 runs the process and gate guardrail suites (`tests/46`, `47`, `119`, `120`, `123`, `124`, `127`, `145`), so they execute on a release path | Check 10 itself |
| `40-vendor-parity-snapshot.sh` | Captures the real exit status and requires the Summary banner plus one header per manifest vendor | `tests/119` |
| `build.zig` drift | Hard fail after `scripts/lib/normalize-overlay-buildzig.py` reverses only the documented YEN customizations (`YENCustomResources`, `// YEN:` comments, branded `libyen-vt` / `include/yen` / `<yen/vt.h>` literals); bypass `YEN_VENDOR_SKIP_BUILDZIG_DRIFT=1` | `tests/45`, `tests/152` |
| Overlay pairs tripwire | `.overlay-upstream-pairs.txt` is generated from a pristine upstream tarball, never from `yen-terminal/ghostty/`. A missing path is not waivable; a changed hash is, with `YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1` after review | `tests/45` |
| `patch_file` | Fails on a missing target; `--optional` is the only opt-out. `verify_overlay_patch_targets` (`scripts/lib/overlay-patch-preflight.sh`) checks every target in `scripts/lib/overlay-patch-targets.txt` before any patch applies and reports all missing ones in one run | `tests/45` |
| `scripts/lib/ghostty-paths.sh` | Declares every upstream path the branding gate guards, literal or indirect; an empty manifest returns non-zero | `tests/123` |
| Universal binaries | `assert_universal_binary` checks `lipo -archs` for both slices before any baseline write; `file \| grep universal` passes arm64+arm64e | `tests/123` |
| `14-vendor.sh` | UNKNOWN upstream status is its own non-zero outcome; override `YEN_VENDOR_ALLOW_UNKNOWN_STATUS=1` | `tests/119` |
| `05-detect-failures.sh` | Refuses non-`enforce` security modes unless `YEN_ALLOW_GATE_DOWNGRADE=1` | `tests/120` |
| `13-scan-artifact-fingerprints.sh` | Fails on an empty scan set or a missing `file` binary | `tests/123` |
| Appcast | `sparkle:edSignature` is verified against the DMG; a missing `Sparkle.framework` fails | `tests/123` |
| `apply-overlays.sh` | Prints `Overlays applied (N patched, M idempotent skips)` from one tally; `build-release.sh` fails if the line is absent | `tests/45` |
| Source-built no-op | `vendor-binary.sh` prints `Output digest revalidated against baseline pin` before `Already current` | `tests/119` |
| `verify-audit-layers.sh` | Requires the audit log and one finding per required layer | `tests/119`, `tests/120` |
| `eval-phase.sh` | `begin` opens a run; `summary` counts only that run; JSONL uses `json_escape` | `tests/119` |

## IDE Lifecycle Vendor Posture

YEN bundles no language servers, no `devcontainer` CLI, and no sharing transport into `Resources/bin/`.
`yen ide lsp install` installs TypeScript/JavaScript, Python and Go servers into `~/.config/yen/ide/lsp-tools`; Swift and Rust stay toolchain-managed.
`yen ide devcontainer` runs the `devcontainer` CLI from `PATH` or `YEN_IDE_DEVCONTAINER_CMD`.
`yen ide share` prefers `upterm`, falls back to `tmate`, resolves both from `PATH` or `YEN_IDE_SHARE_UPTERM_CMD` / `YEN_IDE_SHARE_TMATE_CMD`, and keeps tokens in `~/.config/yen/ide/share/`.

## Bundled Binary Inventory (Resources/bin/)

`scripts/lib/required-app-bins.sh` is the enforced list; keep this table aligned with it.
Before adding a binary, prefer a native macOS framework.
Record a material size change here with its decision.

One row per binary, name unquoted: `12-verify-vendor-audit.sh` matches `| <name> |` for every required binary.

| Binary | Purpose | Why not native |
|--------|---------|----------------|
| lazygit | Git TUI | Interactive UX; about 41 MiB in the bundle and 16 MiB in the DMG, kept deliberately |
| yazi | File browser | Interactive UX |
| ya | Yazi companion | Paired with yazi |
| bat | Syntax-highlighting pager | Pager UX |
| delta | Git diff renderer | Syntax-aware diffs; no top-level YEN alias |
| fzf | Fuzzy finder | Interactive UX |
| rg | Content search | `.gitignore`-aware regex |
| fd | File finder | `.gitignore`-aware search |
| zoxide | Directory jumper | Frecency |
| jq | JSON processor | Yazi calls it directly |
| btop | System monitor | Interactive UX |
| fastfetch | System info | Output parity |
| zmx | Session persistence | No macOS framework keeps a PTY and its screen state alive after the app exits; built against the vendored engine |
| resvg | SVG fallback | `.svgz` and CSS-variable edge cases |
| yen-svgthumb | SVG thumbnails | Native (AppKit) |
| yen-vidthumb | Video thumbnails | Native (AVFoundation) |
| yen-pdfthumb | PDF thumbnails | Native (PDFKit) |

Wrapper scripts `browse`, `yen`, `yen-quicklook` and `yen-yazi-edit` also ship here.
The artifact fingerprint gate force-scans the bundled shell CLI at `Contents/Resources/bin/yen` even though it is not Mach-O.
`lazygit` ships unmodified; YEN behavior comes from `yen-terminal/customizations/lazygit/config.yml` and the `yengit`, `gitlazy` and `gityen` wrappers, and bundling fails if the retired in-binary patch marker reappears.
`lazygit` and `delta` resolve the bundled binary and fall back to the system copy only with `YEN_ALLOW_SYSTEM_BIN_FALLBACK=1`.
