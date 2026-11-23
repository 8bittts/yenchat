# Security

Upstream overlap, fail-closed vendor gate contracts and the bundled binary inventory that make up the supply-chain posture of YEN, and the remote attach threat model; the product privacy boundary is in AGENTS.md.

The `/update-yen` vendor phase owns the procedure; this file owns what each bump is checked against.
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
snapshot_date=2026-11-23
ghostty_commit=74241405fe457d6a569a110cffe9d75a1c9a53b7
ghostty_version=74241405fe457d6a569a110cffe9d75a1c9a53b7
ghostty_upstream_repo=https://github.com/ghostty-org/ghostty.git
yazi_version=v26.9.1
fd_version=v10.5.2
ripgrep_version=16.0.0
lazygit_version=v0.66.3
btop_version=v1.4.8
fastfetch_version=2.71.0
zmx_version=v1.0.1
```

`ghostty_upstream_repo` is gated so a forge change cannot silently move the upstream source of truth.

## Upstream Coordinates

Every Ghostty URL in `/update-yen` resolves through the `upstream_*` helpers in `scripts/lib/upstream.sh`.
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

Audit of YEN customizations against upstream Ghostty (commit `74241405`). Classification: [SAFE] no conflict, [WATCH] monitor upstream changes, [ACTION] needs work.

Per-bump assessments live in the vendor commit messages, not here.

### Config Default Overrides

| Key | YEN value | Upstream | Status |
|-----|-----------|----------|--------|
| `window-save-state` | `always` | `default` | [SAFE] Idempotent patch |
| `copy-on-select` (macOS) | `both`; Settings can write `false`; the legacy value `true` also resolves to `both` | `primary`, and `true` resolves to `primary` | [SAFE] `05-detect-failures.sh` asks the built binary what `true` resolves to |
| `scrollbar` (macOS) | `system`; Settings can write `never` | `system` | [SAFE] Visibility policy only, never a scroller-style control |
| `notify-on-command-finish` | `never`; Settings can write `unfocused` or `always` | `never` | [WATCH] `.claude/hooks/notify-complete.sh` self-suppresses only on `always` above threshold, so `unfocused` needs physical smoke for build-like workflows |
| Quick Terminal keybind | `Ctrl + Backtick` (global) | none | [WATCH] Conflicts if upstream adds a default `toggle_quick_terminal` bind |
| Shift + Enter | sends `\r` | raw escape sequence | [WATCH] Remove the injection if upstream adds first-class behavior |

### Source Patches (apply-overlays.sh anchors)

Exact block replacements use `scripts/lib/patch-file.py` with payloads in `scripts/lib/patches/`.
Structural patches use named helpers in `scripts/lib/`, never inline heredocs.
`scripts/42-lint-overlay-recurrence-gates.sh` fails if an inline `python3 - <<` heredoc returns to `apply-overlays.sh`; its allowlist stays empty.
Every anchor fails closed on drift; retire a patch with the checklist in `.agents/skills/update-yen/references/vendor-audit.md`.

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
| Native config ownership | `Ghostty.Config.swift` deinitializer | LOW | Retire when upstream frees the final native config directly |
| Undo-timeout default | `Ghostty.Config.swift` `undoTimeout` | LOW | Retire if the Swift bridge honors the missing-key fallback |
| Tab title restore invalidation | `titleOverride` didSet in `BaseTerminalController.swift` | MEDIUM | Retire if upstream dirties restorable state on rename |
| Remote pane tab title | the title publisher's `.map` in `BaseTerminalController.focusedSurfaceDidChange(to:)` and the `titleOverride` argument in `applyTitleToWindow()` call `RemotePanes.tabTitle` | LOW | Two one-line redirects; all logic is in the overlay. A local pane's title passes through unchanged (`RemotePanesTests`) |
| Remote pane close confirmation | `needsConfirmQuit` in `SurfaceView_AppKit.swift` and the `withConfirmation:` argument in `BaseTerminalController.yenDidCloseSurface(_:)` call `RemotePanes.closeNeedsConfirmation` | LOW | Two one-line redirects. A remote pane's process is only the local client, so closing a remote pane, tab or window never asks; a local pane keeps the engine's answer, so a mixed tab still asks for its local process. Retire if the engine learns which panes are remote. |
| Resign-key focus deferral | `BaseTerminalController.windowDidResignKey(_:)` | MEDIUM | Defers `yen_surface_set_focus` to avoid re-entering the focus lock |
| Horizontal titlebar tabs | Native tab accessory in `TerminalWindow.swift` and track geometry in `TitlebarTabsTahoeTerminalWindow.swift` | MEDIUM | On an AppKit update, verify selection, close and drag after resizing; the pane count and the Command reveal live in the tab accessory and find the engine's shortcut label as its only text field, so check both after an engine update. The accessory also relies on AppKit's private tab layout: the `_titleContainerView` and `_closeButton` identifiers, a tab stack that keeps a hidden view's slot (so the close button is detached by visibility priority), and a tab label drawn from `NSWindowTab.attributedTitle`; `WorkspaceTabPillTests` fails when any of these moves |
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

### Third-Party License Notices

MIT and Apache-2.0 require their notice in every copy, so `YEN.app` carries one text file per bundled third-party component in `Contents/Resources/Notices/`.
The sources are `yen-terminal/customizations/notices/*.txt`, each the upstream license file at the vendored version under a name and URL header.
The vendor baselines are the list of components: `yen-terminal/.<name>-baseline` requires `<name>.txt`, and a new vendored tool fails the build until its notice exists.
The engine's notice is `TerminalEngine.txt`, because the fingerprint gate rejects the upstream name in a bundle path and in the code signature's resource list.
Its text names the upstream project and copyright holder, as MIT requires; the gate reads paths, Mach-O payloads, the bundled shell CLI and locale catalogs, so a text notice passes without an allowlist entry.
`scripts/lib/third-party-notices.sh` owns both checks: `03-verify-components.sh` requires a notice for every baseline in its terminal structure unit, and `05-detect-failures.sh` requires each tracked notice in the built app, byte for byte.
`tests/171-third-party-notices.test.ts` proves both checks fail closed and that a notice file named after the upstream engine still fails the scan.
The notices cover the engine and the vendored tools, not the libraries those projects link.

### High-Priority Watch Items

- **Targets.** YEN is macOS-only; upstream deleted the iOS target. DockTilePlugin is the only embedded target; a new upstream target needs signing in `finalize-build.sh`.
- **Anchor discipline.** Keep `apply-overlays.sh` on canonical upstream anchor shapes; never add compatibility branches for older shapes.
- **Whole-file overlays.** They are the most fragile overlays. The pairs tripwire catches upstream edits; port drift from the forge compare range, never from a local diff.
- **Build path.** `build-release.sh` owns `YENKit.xcframework` recreation and the Zig/Xcode workarounds. `yen-terminal/overlays/build.zig`, `yen-terminal/overlays/src/build/main.zig` and `yen-terminal/overlays/src/build/LibtoolStep.zig` are whole-file build-system overlays; `LibtoolStep.zig` must flatten `.a` inputs before `libtool -static`. A missing xcframework is not a Settings regression.
- **Provenance.** Binary assets must match GitHub release-asset SHA-256 metadata, source tags resolve to immutable archives, and Ghostty commits need verified forge status; the vendor gate targets the newest signed commit on `main`, since a rebase merge leaves the head unsigned. A local first-download digest is not provenance.
- **pbxproj exception sets.** Branding renames `Ghostty*` paths in exception sets while files keep the `Ghostty` prefix; `apply-overlays.sh` restores them and needs new patterns when upstream adds files.
- **Shell integration resources.** Bundled scripts read `YEN_RESOURCES_DIR` only and fail closed without it; never restore `GHOSTTY_RESOURCES_DIR`. Judge branding from the built `Contents/Resources/yen/shell-integration/`, not the gitignored source.
- **Ghostty updates.** The vendor check compares the pinned commit with upstream `main`.
  The [YEN deployment target](05-infrastructure.md#requirements-and-toolchain) applies independently of Ghostty’s minimum.
- **Exposure gaps.** Settings exposes generic title editing, not upstream's separate window/tab title actions. Command palette border actions do not switch scope.
- **Theme discovery.** Runtime themes come from `~/.config/yen/themes` and bundled `Resources/yen/themes`; never restore migration from `~/.yen/themes`.
- **Stale verifier.** When a check fails after a bump, confirm the checked symbol did not just move in a YEN refactor before blaming upstream.
- **zmx builds against the vendored engine.** `scripts/48-vendor-zmx.sh` points zmx's engine dependency at a clone of `yen-terminal/ghostty`, records the engine commit plus a digest of the tracked YEN inputs that shape engine Zig sources (Zig overlays, engine-source patch blocks, the branding phases) as `build_input_id`, and builds stripped from one fixed path so the output pin reproduces; an engine bump rebuilds zmx and re-records the pin.
  The script also patches zmx to record each session's pty path in `<UUID>.tty` (password detection) and to send soft-wrapped rows unwrapped in its attach snapshot, so a new pane can reflow early output; `tests/164-zmx-snapshot-unwrap.test.ts` runs the vendored binary and fails if a zmx bump undoes the second.
  It also carries upstream f5d604e (#316, after v1.0.1): zmx v1.0.1 freed the caller-owned socket path with the daemon's post-fork C allocator, so every session daemon aborted with SIGABRT at shutdown and left a `zmx*.ips` report. The edit's anchor fails closed once the pinned tag contains the fix, and the edit is then dropped. `tests/181-zmx-daemon-shutdown.test.ts` ends real sessions of the vendored binary and fails unless every daemon exits 0.
  `14-vendor.sh` compares the recorded id with `48-vendor-zmx.sh --print-input-id`, because the zmx tag alone stays current across an engine bump; `tests/119-vendor-process-guardrails.test.ts` fails when the committed id drifts from the tree.
  An edit to one of those inputs outside a vendor run lands with its own rebuild: `VENDOR_LATEST_TAG=<pinned tag> ./scripts/48-vendor-zmx.sh` keeps the zmx version and rewrites only `build_input_id` and `output_sha256` in `.zmx-baseline`.
  After a pull that changes the zmx pin, the integrity gate refuses the old local binary until `./scripts/48-vendor-zmx.sh --force` rebuilds it; the build reproduces the pinned digest.
- **arm64-only vendors.** YEN requires macOS 27, which runs only on Apple silicon, so every vendored binary and thumbnail helper holds the arm64 slice and nothing else.
  A baseline records `architecture=arm64`, and an output pin binds only a baseline with that value, so a baseline from the universal era does not fail a correct reinstall.
  `14-vendor.sh` still fails closed on a digest mismatch at the same version, so after a pull that changes a pin, reinstall with the vendor script and `--force`; the reinstall must reproduce the pinned digest.
  `fastfetch` ships one universal asset; `vendor_install_arm64` keeps its arm64 slice, which carries its own signature.

### Fail-Closed Gate Contracts (Do Not Regress)

Every `/update-yen` vendor and release gate is on `scripts/lib/gate-roster.txt`.
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
| arm64-only binaries | `assert_arm64_only_binary` requires `lipo -archs` to print exactly `arm64`, before any baseline write and for every required bundled binary in `05` and `12`; `file \| grep arm64` passes a fat binary | `tests/123`, `tests/162` |
| `14-vendor.sh` | UNKNOWN upstream status is its own non-zero outcome; override `YEN_VENDOR_ALLOW_UNKNOWN_STATUS=1` | `tests/119` |
| `05-detect-failures.sh` | Refuses non-`enforce` security modes unless `YEN_ALLOW_GATE_DOWNGRADE=1` | `tests/120` |
| `13-scan-artifact-fingerprints.sh` | Fails on an empty scan set or a missing `file` binary | `tests/123` |
| `scripts/lib/third-party-notices.sh` | Fails when it finds no vendor baseline or no tracked notice, and when a notice is missing, empty or altered in the bundle | `tests/171` |
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
| lazygit | Git TUI | Interactive UX; about 19 MiB in the bundle, the largest binary with `yazi` (18 MiB), kept deliberately |
| yazi | File browser | Interactive UX |
| ya | Yazi companion | Paired with yazi |
| rg | Content search | Yazi runs it for content search; `.gitignore`-aware regex |
| fd | File finder | Yazi runs it for name search; `.gitignore`-aware search |
| btop | System monitor | Interactive UX |
| fastfetch | System info | Output parity |
| zmx | Session persistence | No macOS framework keeps a PTY and its screen state alive after the app exits; built against the vendored engine |
| yen-svgthumb | SVG thumbnails, including gzip-compressed `.svgz` | Native (AppKit, Compression) |
| yen-vidthumb | Video thumbnails | Native (AVFoundation) |
| yen-pdfthumb | PDF thumbnails | Native (PDFKit) |

Wrapper scripts `browse`, `yen`, `yen-quicklook` and `yen-yazi-edit` also ship here.
The artifact fingerprint gate force-scans the bundled shell CLI at `Contents/Resources/bin/yen` even though it is not Mach-O.
`lazygit` ships unmodified; YEN behavior comes from `yen-terminal/customizations/lazygit/config.yml` and the `yengit`, `gitlazy` and `gityen` wrappers, and bundling fails if the retired in-binary patch marker reappears.
`lazygit` resolves the bundled binary and falls back to the system copy only with `YEN_ALLOW_SYSTEM_BIN_FALLBACK=1`.

`Resources/bin` holds about 57 MiB: eight arm64-only vendored binaries and three native helpers.

Deliberately not bundled: `bat`, `delta`, `fzf`, `jq`, `resvg` and `zoxide`, because nothing in YEN fails without them.
Text files open in the system `less`, diffs render as plain or natively colored text, and `yen-svgthumb` inflates `.svgz` itself.
Yazi runs `fzf` and `zoxide` for `z` and `Z` only when the user has them on `PATH`; YEN does not feed the `zoxide` database, so a bundled copy finds no history on a clean Mac.
Bundle one of them only with a caller inside YEN that fails without it.

## Remote Attach Threat Model

Who can reach a persistent session from another Mac, what each input is trusted for, and what is left over.
The mechanics live in [01-architecture.md](01-architecture.md) → Persistent sessions (Remote attach, Hosts store, Remote panes); this section cites them and does not restate them.
Between two real Macs over the LAN, listing, attach, typing, a window resize, a killed connection, a frozen connection, a Wi-Fi outage on the peer, every `--host` exit code from 10 to 16 except 15, and a pane that a YEN app on the peer created (attached before and after that app ended) have run.
Over a real tailnet with the Tailscale app on both Macs, discovery, the first-connection step, listing, attach from the CLI and from the app (palette and sidebar), typing, and a killed connection have run, a frozen connection and an outage (Tailscale switched off and on at the peer) have run, and the peer's older installed YEN showed the update-YEN-there state.
With MagicDNS off for the whole tailnet, discovery chose the peer's Tailscale address and listed its session; with Tailscale DNS off on this Mac only, discovery chooses the address too (before `TailscaleDiscovery.usableNames` it reported the peer unreachable), and listing, attach and a killed connection by Tailscale address have run.
Against Tailscale SSH, with the open-source `tailscaled` from Homebrew and `tailscale up --ssh` on the peer, discovery and an outage (`tailscale down` then `up` at the peer) ran before the in-band status, and listing, attach from the CLI, and the not-installed, update-YEN-there and unknown-session states have run with it, including a target given as the peer's tailnet address; a partial listing and a reconnect that finds the session gone have not run there.
The Reconnecting marker was seen on real hardware from the app to a second Mac over Tailscale SSH on a real tailnet: it appeared when Tailscale was switched off at the peer and cleared on reattach with the session still running; the growing waits and the long wait were seen only on the loopback fixture.
It has never run against an ACL `check` rule that demands a browser approval at connection time, or with discovery on a Mac whose own Tailscale is the open-source daemon: the attaching Mac has only run the Tailscale app.
The automated evidence is `tests/172-cli-sessions-remote.test.ts` with `tests/fixtures/fake-ssh.sh`, `tests/176-cli-sessions-remote-contract.test.ts`, `tests/177-cli-sessions-remote-listing-attach.test.ts`, `tests/178-cli-sessions-directory-repair.test.ts`, `tests/179-cli-sessions-inherited-zmx-session.test.ts`, `tests/180-cli-sessions-subshell-exits.test.ts`, `tests/182-cli-sessions-status-dropping-transport.test.ts`, `tests/183-cli-sessions-reconnect-mark.test.ts`, `tests/184-cli-sessions-tailscale-check.test.ts`, `scripts/manual/35-verify-remote-attach-loopback.sh` against a private loopback sshd, and the Swift suites `RemoteSessionsTests`, `TailscaleDiscoveryTests`, `RemoteHostsStoreTests`, `RemotePanesTests`, `RemoteHostsPaletteRowsTests`, `RemoteDiscoveryContractTests`, `RemoteHostsStoreContractTests`, `RemotePanesContractTests`, `RemoteHostsPaletteContractTests`, `SessionDirectoryRepairTests`, `SessionStateTests`, `TabSidebarHostsSectionTests` and `RemoteCloseConfirmationTests`.

### Who can attach

- SSH on the peer authenticates every connection, and YEN adds no authentication of its own. The peer's ssh server is macOS Remote Login, or Tailscale SSH where the peer runs the open-source `tailscaled`; the Mac App Store and standalone Tailscale apps cannot be a Tailscale SSH server ([Tailscale macOS variants](https://tailscale.com/kb/1065/macos-variants)).
- YEN opens no listener and runs no relay. The only network client is `/usr/bin/ssh` (`REMOTE_SSH_BIN` in `yen-cli/lib/sessions-remote.sh`), started by the bundled CLI on the Mac that attaches.
- On the peer, the ssh user's login shell runs fixed text (`remote_command`), which runs that user's own `Contents/Resources/bin/yen sessions list|attach`. A person who can already sign in to the peer as that user gains nothing: the same command, and the sessions' sockets, were already theirs.
- An attached client is a full zmx client: it sees the screen and scrollback and types into the shell. Attach access is shell access as the peer user.
- Nothing ends a peer's session remotely: `yen sessions kill` refuses `--host` (`tests/172`, "kill takes no --host"), so a session ends from a shell inside it.

### What the session directory exposes

- Sessions live in `~/.local/state/yen/zmx` (`PersistentSessions.socketDirectory`). Each has a Unix socket named by its pane UUID and three records: `<UUID>.tty` (the inner pty path), `<UUID>.zmx` (the zmx build that started it) and `<UUID>.owner` (bundle identifier, bundle path and process id of the copy that shows it).
- `<ZMX_DIR>/logs` holds zmx's diagnostic logs. They keep working directories and environment payloads after the session ends, and YEN never deletes them.
- A local process running as the same user can connect to any socket and attach, list, or end sessions, and can rewrite the records. The `.zmx` record names a binary that `yen sessions attach` and `kill` run (`session_zmx`), while the listing helper runs only a digest-named copy whose SHA-256 matches its name (`yen-cli/lib/list-pane-sessions.sh`). This is not a boundary: that process can already run anything as the user.
- Another local account cannot attach: the sockets have no group or other write bit, and macOS `connect(2)` needs write access to the socket.
- The directory, `logs/` and `bin/` are private to the user. Every path that runs zmx passes `ZMX_DIR_MODE=0700`: the engine's pane (`PersistentSessions.prepare`), the app's own zmx calls (`PersistentSessions.zmxEnvironment`), and the CLI and its listing helper (`export ZMX_DIR_MODE=0700` in `yen-cli/commands/core/sessions` and `yen-cli/lib/list-pane-sessions.sh`). zmx's own default would be 0750.
- An existing directory is repaired: `PersistentSessions.secureSocketDirectory` (run from `PersistentSessions.claim` and the reaper's sweep) and the CLI's `secure_sessions_dir` take group and other access off the directory, `logs/` and `bin/`. Both skip a symlink and anything the user does not own, never add a permission, and never stop a session when the repair fails.
- Log files are 0640 and the `.zmx` and `.owner` records 0644, so the directory mode is the only thing that keeps other accounts out of them.

### How Tailscale gates it

- The tailnet's access policy decides whether this Mac can reach the peer's port 22 at all. ACLs are deny-by-default rules about which devices reach which ports ([Tailscale ACLs](https://tailscale.com/kb/1018/acls)), and the default policy allows everything. A blocked connection fails ssh's `ConnectTimeout=10` and shows as unreachable (exit 10).
- With Tailscale SSH on the peer, the policy's `ssh` rules (`accept`, or `check` with periodic reauthentication) decide who signs in as which user ([Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh)). Tailscale SSH on a macOS peer runs each command under macOS `login`, which exits 0 whatever the command's status was (Tailscale issue 18256), so the peer reports its status in-band ([01-architecture.md](01-architecture.md) → Remote attach).
- Under a `check` rule whose approval is due, Tailscale SSH holds sign-in for up to 30 minutes and sends a per-connection approval link in an auth banner; `yen sessions list --host` stops at that banner with exit 17 (`REMOTE_EXIT_CHECK_REQUIRED`, `lib/sessions-remote-watch.sh`) and never prints the link, and an attach shows it only in the user's own pane. YEN never opens the link and never answers the server: the user approves in a browser after running `ssh <target>`, and a denied or expired check fails sign-in like any refusal.
- A peer or a man in the middle cannot use the banner to get more than a misleading message: it arrives before sign-in, which host key checking already gates, and the CLI only matches its text to choose an exit code (`classify_ssh_failure`).
- While a check holds sign-in during a reconnect, the CLI's watcher renews the pane's reconnecting mark every 10 seconds until sign-in; like the CLI's own mark, it writes only to that pane.
- A peer can print its own `yen-remote-status` lines, but the CLI reads only the last one, which the fixed snippet prints after the peer's CLI exits, and only after it has classified ssh's own failures (`take_remote_status` in `remote_list`); so a peer can misreport only the outcome of its own listing (0, 1, 12 or 13), as it already could with its exit status, and cannot fake an unreachable host or a host key state. An attach under `login` holds its failure message on the peer; a peer can show any text in its own pane, as before.
- YEN lists only peers that `TailscaleDiscovery.parseStatus` keeps: `OS` is `macOS`, `UserID` equals `Self.UserID`, the node is neither `ShareeNode` nor `Expired`, and it runs Tailscale's peer API (a non-empty `PeerAPIURL`), which a node another app embeds (tsnet) does not. A real client whose peer API failed to start is hidden the same way. A device shared in from another tailnet has another owner and is not listed ([Tailscale sharing](https://tailscale.com/kb/1084/sharing)); an expired node cannot connect until it reauthenticates ([Tailscale key expiry](https://tailscale.com/kb/1028/key-expiry)). Offline peers are never contacted (`RemoteHostsStore.performRefresh`).
- The filter shapes the list, not the transport. `yen sessions list|attach --host` accepts any target that passes `valid_remote_target`, on or off the tailnet, and then relies on ssh and the peer as above.

### Untrusted input

| Input | Where it goes | Handling |
|-------|---------------|----------|
| `tailscale status --json` | Peer list, labels, ssh target | Decoded into fixed fields only; an unknown `BackendState` is `.unavailable`; a target must pass `RemoteSessions.isValidTarget` or the peer is dropped; a MagicDNS name is the ssh target only when it resolves on this Mac to one of that peer's own `TailscaleIPs`, compared as addresses (`TailscaleDiscovery.usableNames`); a name that does not resolve here, resolves to any other address, or misses its 1-second deadline is not used, and the peer's first valid Tailscale IP is the target instead; the label goes through `TailscaleDiscovery.displayLabel` (`TailscalePeers.swift`) |
| Host target | The ssh argv | `valid_remote_target` (CLI, byte-wise under `LC_ALL=C`) and `RemoteSessions.isValidTarget` (app): `[user@]host`, no leading `-`, no spaces or metacharacters; ssh gets `--` before it (`remote_list`, `remote_attach`) |
| Session id | The remote command | UUID only (`valid_session_id`), checked before ssh runs; the remote command is otherwise fixed text (`remote_command`) |
| Remote listing | The CLI table and the palette | Only rows after the `yen-sessions<TAB>1` header that pass `read_porcelain` survive, re-sanitized by `porcelain_row`; the app parses them again (`RemoteSessions.parsePorcelain`) and replaces control and format characters (`RemoteSessions.sanitized`) |
| ssh and peer stderr | The terminal | `print_remote_errors` replaces C0 and C1 control characters; an attached pane shows the remote terminal's output as ssh would |
| Saved window state | A restored remote pane's command | `RemotePaneIdentity` re-validates the target and label when decoding; a bad entry is dropped on its own (`RemotePanes.SavedIdentities`) |
| `YEN_REMOTE_PANE` | A new pane's command | Carries only a random one-time token that `RemotePanes.open` registered in this process; `RemotePanes.prepare` always removes the variable and ignores a token it did not issue or already used, so AppleScript or the New Terminal App Intent cannot create a labeled remote pane with it |
| Terminal progress report (OSC 9;4) | A remote tab's Reconnecting marker | A remote pane's CLI reports that it is reconnecting by writing a terminal progress report (`OSC 9;4;4;0`) to its own pane, and clears it with `OSC 9;4;0` (`remote_mark`, `remote_wait`, the `LocalCommand`). The app reads the report only for remote panes (`RemotePanes.isReconnectReport`). A peer, or any program in a remote session, can write the same sequence while connected; that can show or hide the Reconnecting marker on its own tab only, cannot affect another pane or another tab, and carries no data |
| `YEN_SSH_BIN`, `YEN_REMOTE_APP`, `YEN_SSH_RETRY_MAX_DELAY`, `YEN_TAILSCALE_BIN` | Which ssh and Tailscale CLI run, which YEN.app the peer runs, the backoff cap | Test hooks the app never sets; `YEN_REMOTE_APP` must be an absolute path of safe characters and the delay a whole number |

Whoever can set the app's environment, write its preferences or saved state, or drive it through Automation already runs code as the user, so these inputs are checked for robustness, not as a privilege boundary.

### What YEN never does

- It never relaxes host key checking: no `StrictHostKeyChecking` and no known-hosts file are passed (`remote_ssh_options`), and a changed key stops the listing and the reconnect loop (exit 15).
- It never forwards the agent, X11 or ports (`ForwardAgent=no`, `ForwardX11=no`, `ClearAllForwardings=yes`), and never shares a connection (`ControlMaster=no`, `ControlPath=none`). Command-line `-o` options win over the user's `~/.ssh/config`.
- It never stores, reads or prompts for a password. A listing runs with `BatchMode=yes` and stdin from `/dev/null`; an attach lets ssh prompt in the pane, and the user answers ssh directly.
- It never relays traffic or sends terminal content, host names or session data to YEN; the bytes travel only between the two Macs over ssh.

### When YEN starts a process

- Discovery runs `tailscale status --json` and, for each online peer, one `yen sessions list --host` only while a Hosts surface is visible: in the command palette, that means while the query has Hosts intent (`RemoteHostsIntent`), refreshed when it appears and every 30 seconds while it stays (`RemoteHostsStore.surfaceDidAppear`). Opening the palette for anything else starts nothing.
- The tab sidebar's Hosts section is the second Hosts surface. It starts collapsed in every new sidebar, and counts as visible only while it is expanded and its sidebar is on screen (`TabSidebarHostsSection.wantsDiscovery`, `TabSidebarController.transientPanelShowsHosts`, `DockedTabSidebarModel.railShowsHosts`): the transient panel while it is open and YEN is active, or a docked or fullscreen rail while its window is on screen. An open sidebar alone starts nothing.
- An explicit refresh (`Hosts: Refresh Remote Sessions`, or `Refresh Remote Sessions` in the sidebar) runs once at once.
- Selecting a session row in either surface opens a pane that runs `yen sessions attach --host` (`RemotePanes.open`).
- At launch, a remote pane restored from saved window state runs its attach with `--retry-unreachable` (`RemotePanes.prepare`). This is the only ssh YEN starts at launch, and only for panes the user opened.
- `Hosts: Trust the Host Key of <Mac>` types `ssh <target>` and `Hosts: Set Up Key Sign-In for <Mac>` types `ssh-copy-id <target>` at a local prompt; neither runs anything, and neither types into a remote pane.

### Residual risks and non-goals

- Unverified: an ACL `check` rule that demands a browser approval at connection time, and discovery on a Mac whose own Tailscale is the open-source daemon, have never been run.
- The Tailscale check state is built from Tailscale's source (ssh/tailssh, 1.104.7) and a stand-in, and has not been seen on a real tailnet; its first line is the control server's wording, which Tailscale can change, and an ssh config with `LogLevel` below `INFO` hides it, so the listing then waits for the app's deadline and shows the Mac as unreachable.
- Through Tailscale SSH on a Mac, a failed remote attach exits 0 after the user presses Return on the peer's message, so the app shows no local exit code for it and the pane closes.
- With Tailscale DNS off on this Mac ("Use Tailscale DNS settings" off in the Tailscale app, or `--accept-dns=false`), discovery's lookup of each online peer's MagicDNS name goes to the system resolver, so that resolver sees the tailnet's device names (`<mac>.<tailnet>.ts.net`) on every refresh while a Hosts surface is open, as it already did whenever ssh was given the name; with Tailscale DNS on, the lookup stays with Tailscale's resolver.
- A Mac re-joined to the tailnet appears as a second device with the same host name, one online and one offline, and Hosts lists both under that one name. YEN does not yet tell them apart by device name.
- A listing runs under `BatchMode=yes`, so a peer that accepts only passwords never lists: the CLI reports it as needing key sign-in (exit 16, `REMOTE_EXIT_KEY_REQUIRED`), and remote sessions need an SSH key that signs in without a prompt, or Tailscale SSH.
- First connection is trust on first use: the user confirms the peer's host key in `ssh <target>`. If name resolution is redirected at that moment, the user can trust the wrong key; YEN never sees or pins the key.
- Remote Login turns on the macOS ssh server for every network the Mac uses, not only the tailnet, because macOS's `sshd_config` sets no `ListenAddress`. Its Allow access for setting (All users or Only these users) decides which accounts may sign in ([Apple: allow a remote computer to access your Mac](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)). YEN does not narrow either.
- The user's `~/.ssh/config` still applies (`ProxyJump`, `ProxyCommand`, `Match exec`, identity files), and so do the peer user's shell startup files.
- A host label is display text, not identity: the ssh target and its host key are what authenticate. A caller with Automation permission for YEN can still open a pane that runs any command, including `ssh`, though not a labeled remote pane. Saved window state is validated but not authenticated, so whoever can write it as the user chooses what a restored remote pane connects to.
- A session directory written by an older YEN stays group-readable until a YEN with the repair runs on that Mac: a persistent pane, the reaper's sweep, or any `yen sessions` command.
- Discovery runs the first executable of `/Applications/Tailscale.app/Contents/MacOS/Tailscale`, `/usr/local/bin/tailscale` and `/opt/homebrew/bin/tailscale` (`TailscaleDiscovery.candidatePaths`). Whoever can write those paths chooses what YEN runs on Hosts intent.
- `tailscale status --json` is a format Tailscale marks as subject to change ([Tailscale CLI](https://tailscale.com/kb/1080/cli)); a change shows as `.unavailable` or an empty list, never as a crash.

## Optional local usage and wallpaper sources

The usage reader takes counts from local provider records without provider credentials or requests.
Its cache holds record identifiers, source paths, read positions and counts.
The desktop wallpaper picker grants access to selected media, while random Photos selection requests library permission.
YouTube playback fetches its downloader from a pinned GitHub release and verifies its SHA-256 before execution.
Only a chosen YouTube video or restoration of that choice can start a media download.
The app bundles the MIT notices for the adapted JP the Cat readers and MovingPaper engine, beside the notices that Third-Party License Notices describes.
