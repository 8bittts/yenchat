# Build Phase (Steps 2-5)

## Step 2: Update Version File

Before bumping, check whether `public/stable/version.json` was already prepared but never shipped. If `sha256` is empty or no matching versioned DMG checksum exists in `public/stable/`, reuse that version. Only bump when the current version was already shipped.

Update `public/stable/version.json`:
- Use display versions `X.XXX` consistently.
- Versions are three-decimal and increment by one thousandth: `1.157` -> `1.158`, and a milestone rolls over cleanly (`0.999` -> `1.000` -> `1.001`).
- `is_valid_release_version` in `scripts/lib/version-utils.sh` is the contract; check the current version in `public/stable/version.json` rather than assuming a milestone.
- Never derive filenames by stripping dots manually. `scripts/lib/version-utils.sh` maps `0.999` -> `0999`, `1.000` -> `1000`, and `1.001` -> `1001`.
- Update `notes` to a short release note (max 8 words, no upstream technology names).
- A bump also resets `url` to the new `yen-<mmmm>.dmg` and `sha256` to `""`; `build-release.sh` fills the checksum. Edit with `jq` into a scratch file, then copy it over, and read the result back with `jq .`.
- A vendor-only release takes its note from the user-visible effect of the vendor commit's upstream changes, never from the vendor name or commit range.

```bash
jq . $HOME/Documents/yenchat/public/stable/version.json
# Edit version/notes only when a bump is actually required.
```

## Step 3: Sync Versions

Auto-handled by `build-release.sh` when it detects a version mismatch. The script reads `version.json` and syncs to:
- `package.json`
- Xcode project
- Info.plist

No manual action is required, but this can still be run explicitly:

```bash
bash $HOME/Documents/yenchat/scripts/02-sync-versions.sh
```

## Step 4: Verify Components (17 declared units)

```bash
set -o pipefail; bash $HOME/Documents/yenchat/scripts/03-verify-components.sh 2>&1 | tee $HOME/Documents/yenchat/tmp/skill-telemetry/update-yen-components.out
```

Keep the `tee`: `eval-phase.sh` deletes a passing check's own log, so the saved file is the only copy of Step 4's receipt, and Step 6a decides from it.

Its pre-build source-only units, in roster order (`scripts/lib/units/03-verify-components.units`); item 10 covers two units, `regression-tests` and `xcode-regression`:
1. Shell compatibility (bash 3.x, BSD-compatible)
2. version.json validity
3. YEN CLI structure
4. YEN Terminal structure
5. Native helper sources
6. Lua plugin syntax
7. Yazi flavor assets
8. Yazi launch-surface simplicity
9. Removed GitHub CLI guard
10. Overlay + workspace + CLI alias regression tests, plus the process/gate guardrail suites that were previously invoked by nothing (`bun test tests/35-yazi-config.test.ts tests/45-overlay-patching.test.ts tests/51-cli-alias-parity.test.ts tests/46 tests/47 tests/119 tests/120 tests/123 tests/124 tests/127 tests/145 tests/169 tests/171`) plus a targeted `xcodebuild` slice for the command-palette, browser, keyboard, and utility-window suites when `YEN_COMPONENT_XCODE_REGRESSION_MODE=auto` sees native macOS changes since the latest `[deploy]` release; set `always` to force it or `off` to skip it
11. Privileged-action surface baseline
12. Non-concurrency warning allowlist
13. Weather removal regression guard
14. Curated theme manifest gate
15. SwiftUI view-modifier hygiene (`scripts/41-lint-swift-view-modifiers.sh`)
16. Overlay recurrence gates for non-DEBUG prints, timer tolerance, warning-only god-file line counts, and `apply-overlays.sh` Python heredoc inventory (`scripts/42-lint-overlay-recurrence-gates.sh`)

Exit 0 required to proceed.

Two skip states are expected. `SKIP|xcode-regression|xcframework missing/incomplete` means `yen-terminal/ghostty/macos/YENKit.xcframework` has not been rebuilt yet (every Ghostty vendor bump removes it). `SKIP|xcode-regression|no native macOS changes since latest [deploy]` means `YEN_COMPONENT_XCODE_REGRESSION_MODE=auto` found no tracked native path (`yen-terminal/overlays/**`, `apply-overlays.sh`, `.ghostty-baseline`, `VENDOR_INFO.txt`) changed since the latest `[deploy]` release commit, which is normal for release, docs, and test-lane work; set `always` to force it. In either skip state Step 5 is the compile gate, and Step 6a (`references/zip-verify.md`) runs the slice exactly once by reading this saved receipt, so never force it here by hand. Build-path mechanics live in `_docs/05-infrastructure.md` -> `Build Ownership and Toolchain Guardrails`.

## Step 5: Build

### Full Mode
```bash
YEN_PREBUILD_COMPONENT_GATE_MODE=off bash $HOME/Documents/yenchat/yen-terminal/customizations/build-release.sh --skip-vendor
```

### Local Mode
```bash
bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local
```

Key flags:
- `YEN_PREBUILD_COMPONENT_GATE_MODE=off` — Step 4 already ran verification
- `--skip-vendor` — Step 1 already confirmed vendor status
- `--local` — (local mode only) skips signing, notarization, DMG packaging

For local mode, the smoke helper applies the same non-shipping defaults automatically: vendor gate skipped, pre-build component gate off, local packaging path only.

**Build-phase single source:** the build-step list below is the only copy of it. `~/.claude/commands/update-yen.md` and its backup are pointers to this skill, so a step count, description, or skip-behavior change is made here and nowhere else; `_docs/05-infrastructure.md` owns the xcframework and Zig/Xcode workaround mechanics.

The build script prints 9 numbered steps, `[1/9]` to `[9/9]`:
1. Validate environment (Xcode, Zig, Go), signing access, and positive notarization credentials for shipping builds.
2. Skip the internal vendor gate when `--skip-vendor` is set, but always run vendor-audit doc validation and the configurable pre-build component gate.
3. Clean artifacts in full mode; local mode preserves caches but removes the prior local `YEN.app`.
4. Verify prerequisites and auto-sync version mirrors if mismatched.
5. Apply overlays.
6. Resolve Swift packages with visible errors on failure.
7. Build `YEN.app` with an arm64-only engine library (`-Dxcframework-target=native`) and post-build diagnostic log gates.
8. Verify built-app vendor inventory and run branding verification (`04-verify-branding.sh`, 2 declared units; reports `guarded subjects` present/total).
9. Package full releases: sign, notarize, create DMG, upload DMG/checksum to the version's GitHub Release, and generate checksum/appcast/version signature — appcast generation also computes Sparkle binary-delta patches against up to 5 prior versions when reachable (non-fatal, falls back to full-DMG-only), uploading any resulting `.delta` files. Every GitHub Release keeps its DMG, so older releases stay available as delta sources and nothing is pruned.

Timing receipt: `build-release.sh` ends with one `TIMING|build-release|01-preflight=<n>s ... 06-package=<n>s total=<n>s` line, also when a phase fails.
Inside step 9, `finalize-build.sh` prints `TIMING|finalize-build|...` for its seven phases, and the notarization line carries the seconds from submission to a valid staple.
Quote these lines for the Step 12 Build Time; they are the only durations a release log holds.

Milestone notifications: `scripts/lib/zip-notify.sh` posts macOS notifications (via the `com.yenchat.yen.buildNotification` DistributedNotification that YEN.app forwards to Notification Center) at major sections only — Build started (step 7), App verified (after step 8), Notarized, Release complete, and Release FAILED on packaging abort. Best-effort and never fail the build; silently dropped if YEN.app is not running. Disable with `YEN_ZIP_NOTIFY=off`. Per-command completion notifications remain owned by `.claude/hooks/notify-complete.sh`.

Toolchain hardening (Zig version check, `YEN_SKIP_ZIG_VERSION_CHECK=1`; stable Xcode policy, `YEN_ALLOW_PRERELEASE_XCODE=1`; SDK linker probe, `YEN_SKIP_ZIG_SDK_WORKAROUND=1`) is automatic inside `build-release.sh` and described once in `SKILL.md` -> Release Preflight Gates.

Local mode still runs the same source/build verification path; it only skips cleaning and release packaging/signing/upload. `build-release.sh` also owns xcframework recreation and the current Zig/Xcode workaround behavior; keep the detailed mechanics in `_docs/05-infrastructure.md` instead of duplicating them here.

**CWD:** Use absolute-path invocations for repo-root scripts, git commands, and the build command itself. Do not rely on `cd yen-terminal`.

**Test locally:** `open $HOME/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app`. Always test `zig-out/YEN.app`, never `/Applications/YEN.app`; if the two conflict, run `bash $HOME/Documents/yenchat/yen-terminal/customizations/clear-app-cache.sh`.

## Eval Checks

Run Step 4 through BD-02 on its first execution.

| Check ID | Description | Command |
|----------|-------------|---------|
| BD-01 | `version.json` bumped, format valid | `source $HOME/Documents/yenchat/scripts/lib/version-utils.sh && is_valid_release_version "$(get_version $HOME/Documents/yenchat/public/stable/version.json)"` |
| BD-02 | Component verification passes, receipt saved for Step 6a | `set -o pipefail; bash $HOME/Documents/yenchat/scripts/03-verify-components.sh 2>&1 \| tee $HOME/Documents/yenchat/tmp/skill-telemetry/update-yen-components.out` |
| BD-03 | Build artifacts exist and were built in this run | `test $HOME/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen -nt $HOME/Documents/yenchat/tmp/skill-telemetry/update-yen-eval-run.id` |
