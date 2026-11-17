# Vendor Build (Step V4) — Compile Gate and Project Gates

## Pre-Build Verification

```bash
set -o pipefail; bash $HOME/Documents/yenchat/scripts/03-verify-components.sh 2>&1 | tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-components.out
```

Pass = exit 0 and `RECEIPT gate=03-verify-components ... result=PASS`; read the unit counts from the receipt, never from a remembered number. Keep the `tee`: `eval-phase.sh` deletes a passing check's own log, and VB-05 below decides from this saved receipt. After a Ghostty refresh the `xcode-regression` unit reads `SKIP|xcode-regression|xcframework missing/incomplete`; that is expected, the smoke build below recreates `YENKit.xcframework` through `build-release.sh`, and VB-05 then runs the native slice this gate could not.

## Skip-Build Default for Non-Code Bumps

The release follows the vendor phase in the same `/yen-zip` run. When the bump is non-code (docs, locale files, colorscheme data, CI metadata, README, VOUCHED lists — touching NO Ghostty `*.swift`, `*.zig`, `build.zig`, Xcode project, package pin, or `overlays/` source), skipping the local smoke build is the default: release Step 5's clean build is the compile gate. Two guards override it: any code, project, or overlay change, or a run where the release is not following immediately, for example when the operator asked to stop after the vendor phase. Even when skipping the build, still run `12-verify-vendor-audit.sh`, `04-verify-branding.sh`, `manual/16-verify-applescript-if-needed.sh`, the project gates below, and the audit itself. A skipped build records no VB-02 and no VB-05; the eval summary then covers fewer IDs, never a stale one.

A third guard is the AppleScript verifier: a Ghostty refresh deletes `zig-out/YEN.app`, so when VB-04's trigger scan finds a contract path changed since the `yen-terminal/.applescript-verified` stamp, it prints `ERROR: App bundle not found` and fails. That is not a defect to retry. Run the smoke build below (VB-02, VB-05), then run VB-04 again; while `/Applications/YEN.app` is running, pass `--app` the re-identified scratch bundle from item 6 of Build Verification.

## Compile Gate (Detached) and Project Gates (Parallel)

Start the smoke build detached so the project gates run alongside it:

```bash
LOG=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-smoke.out
nohup bash -c 'bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local; echo "SMOKE_EXIT_CODE=$?"' > "$LOG" 2>&1 &
echo $! > "$LOG.pid"
```

`--local` builds incrementally with no signing, notarization, or DMG, defaults `YEN_PREBUILD_COMPONENT_GATE_MODE=off`, and skips the vendor gate (pass `--vendor` to re-check). Invoke it by absolute path from the repo root; never `cd yen-terminal`. It holds the shared `yen-workflow` lock, so `14-vendor.sh` cannot run until it finishes.

While it runs, in separate parallel calls from the repo root:

```bash
bun run check
bun run build
bun run test:policy
bun run test:prod
bunx react-doctor@latest . --verbose --scope changed --base main
bun test $(/bin/ls tests/*.test.ts tests/*.test.tsx | /usr/bin/grep -v '76-theme-contrast-gates')
```

`tests/76-theme-contrast-gates.test.ts` runs after the build, with the other Build Verification steps; every other suite is independent of the build tree. The glob must name both `*.test.ts` and `*.test.tsx`, or the three `.tsx` suites are skipped without any error. Confirm the run reports one file fewer than `/bin/ls tests/*.test.ts tests/*.test.tsx | wc -l`. Do not run `apply-overlays.sh` or anything else that writes `yen-terminal/ghostty/` while the build is running.

Wait for the process, not for a log line: `until ! command kill -0 "$(cat "$LOG.pid")" 2>/dev/null; do sleep 15; done` in a background call, or a bounded Monitor that emits only stage lines (`^\[[0-9]/9\]`, `RECEIPT`, `error:`, `SMOKE_EXIT_CODE`) and filters out the `Building... Nm NNs` heartbeats.

## Build Verification

Read positive evidence from the log and the tree. Every saved file must postdate this run's `begin` (`tmp/skill-telemetry/yen-vendor-eval-run.id`); a log or app left by an earlier run is not evidence, which is why VB-02 tests `-nt` against the run id file.

1. `/usr/bin/grep -c 'SMOKE_EXIT_CODE=0' "$LOG"` is `1`, `BUILD COMPLETE (local)` is present, and `yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen` is newer than the run id file. `build-release.sh` already ran `12-verify-vendor-audit.sh` and `04-verify-branding.sh`; quote their `RECEIPT ... result=PASS` lines.
2. Native slice, exactly once (VB-05): `bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/run-native-slice-if-needed.sh yen-vendor`. It reads the VB-01 receipt saved above. `SKIP|native-slice-vb05|Step 4 already ran it: RAN|xcode-regression|suites=<n> executed=<N>` means the pre-build gate executed the slice (a non-Ghostty bump with an intact xcframework); quote it and move on. `RAN|native-slice-vb05|forcing the slice: <reason>` means it did not, and the script runs the forced `YEN_COMPONENT_XCODE_REGRESSION_MODE=always` component gate. After a Ghostty refresh this is the only point before the commit where the command-palette, browser, keyboard, and utility-window suites execute. Never re-run the whole component gate by hand to get this coverage; the decider is the one path.
3. When a linked package changed, confirm the built app carries it. Sparkle: `plutil -p $HOME/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/Frameworks/Sparkle.framework/Resources/Info.plist | /usr/bin/grep CFBundleShortVersionString`.
4. `bun test tests/76-theme-contrast-gates.test.ts`
5. Fingerprint scan in report mode; pass = `RESULT total=N allowlisted=N remaining=0 scanned=M` with `M > 0`:

```bash
bash $HOME/Documents/yenchat/scripts/13-scan-artifact-fingerprints.sh --app $HOME/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app --gate-mode report --skip-codesig
```

6. `scripts/manual/16-verify-applescript-if-needed.sh`, run through VB-04, which tees its output to `tmp/skill-telemetry/yen-vendor-applescript.out`. It triggers on AppleScript/workspace contract paths changed in the worktree or committed since the `yen-terminal/.applescript-verified` stamp, and a missing stamp runs the verifier. Judge it by `RAN|verifier|` versus `SKIP|verifier|` in that saved receipt, not by exit 0; `eval-phase.sh` deletes a passing check's own log. When it must run, follow `_docs/05-infrastructure.md` -> "Validating the local `zig-out` build without quitting your own YEN.app": ask the operator to quit `YEN.app` or use the re-identified scratch bundle, never kill `/Applications/YEN.app`, and never point `--app` at `zig-out/YEN.app` while the installed app runs, because LaunchServices activates the installed instance and the checks pass against the wrong binary. `--keep-open` is for the physical `Cmd + Option + 2` follow-up.

## Common Build Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Swift concurrency error | x86_64 stricter isolation | Add `@MainActor`, `nonisolated`, or explicit types in the overlay source |
| "Cannot find type" | Overlay references a removed upstream API | Update the overlay to the new API |
| `uucode_build_tables: FileNotFound` | Shared or half-cleaned `.zig-cache` | Full `trash yen-terminal/ghostty/.zig-cache`, then rebuild (`references/vendor-troubleshooting.md`) |
| Zig fetch timeout | Transient network error | Auto-retried by `is_zig_retryable_flake()` |
| Lock exists | Parallel build running | Wait, or confirm the PID is dead with `command ps -p <pid>` |

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VB-01 | Components verified, with a `result=PASS` receipt saved for VB-05 | `set -o pipefail; bash $HOME/Documents/yenchat/scripts/03-verify-components.sh 2>&1 \| tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-components.out` |
| VB-02 | Compile gate passed in this run and the app is fresh | `RUN=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-eval-run.id; LOG=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-smoke.out; test "$LOG" -nt "$RUN" && /usr/bin/grep -q 'SMOKE_EXIT_CODE=0' "$LOG" && test $HOME/Documents/yenchat/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen -nt "$RUN"` |
| VB-03 | Project gates passed | each project gate above, recorded separately |
| VB-04 | AppleScript verifier (no-op unless contract paths changed), receipt saved | `set -o pipefail; bash $HOME/Documents/yenchat/scripts/manual/16-verify-applescript-if-needed.sh 2>&1 \| tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-applescript.out` |
| VB-05 | Native slice covered exactly once: forced after the build only when VB-01's saved receipt shows it did not run | `bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/run-native-slice-if-needed.sh yen-vendor` |
