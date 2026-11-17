# Verify Phase (Steps 6-7)

## Step 6: Post-Build Verification

### 6a. Native Regression Slice, Only If Step 4 Did Not Run It (REQUIRED Decision)

A Ghostty vendor bump cleans `YENKit.xcframework`, so Step 4 cannot run the native `xcodebuild` slice and records `SKIP|xcode-regression|xcframework missing/incomplete`. Step 5 rebuilds it, so this is the only point in such a release where the slice can run at all; skipping it ships the command-palette, browser, keyboard, and utility-window suites unexecuted. When Step 4 did run the slice, the forced invocation re-runs all 17 component units and repeats Step 4 for no added coverage.

Run Step 6a only through VF-04, which makes the decision from Step 4's saved receipt (`tmp/skill-telemetry/yen-zip-components.out`, written by BD-02's `tee`):

```bash
bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/run-native-slice-if-needed.sh
```

- `SKIP|native-slice-6a|Step 4 already ran it: RAN|xcode-regression|suites=<n> executed=<N>` — the receipt is from this run, passed, and executed at least one test; quote the line and move on.
- `RAN|native-slice-6a|forcing the slice: <reason>` — any other state, including a `SKIP|xcode-regression|<reason>` line, no passing `RECEIPT`, no saved file, or a file older than this run's `begin`. The script then runs the forced gate:

```bash
YEN_COMPONENT_XCODE_REGRESSION_MODE=always bash $HOME/Documents/yenchat/scripts/03-verify-components.sh
```

Never type the forced invocation by hand after Step 4 recorded `RAN|xcode-regression`. Exit 0 required. A green failure-detection run below does NOT cover the native suites.

**Confirm, do not infer.** Step 4 ends with a `RECEIPT gate=03-verify-components ran=<n> skipped=<n> declared=<n> result=...` digest preceded by one `RAN|<unit>|...` or `SKIP|<unit>|<reason>` line per declared unit. The script reads those positive lines: it skips only on a `RAN|xcode-regression|` line with a non-zero `executed=` count, never because a `SKIP` string was absent. Truncation, a renamed marker, an unenumerated skip route, and a crash before the print all produce the same silence, and each one forces the slice.

### 6b. Failure Detection (7 categories)
```bash
bash $HOME/Documents/yenchat/scripts/05-detect-failures.sh
```

7 verification categories:
1. **Build Artifacts** — app exists, universal main binary (arm64 + x86_64), CLI and bundled file-browser tools exist, static config/flavors/bat-theme are valid, shell integration is present, legacy upstream-named shell/theme files are absent, release DMG/checksum/appcast/version signature exist, and DMG contract/trust/layout gates pass.
2. **Security** — hardened runtime, timestamp, Sparkle signed, app signature valid, `audio-input` entitlement present, and required bundled Mach-O binaries pass `codesign --verify --strict`.
3. **Critical Files** — key metadata and runtime files exist and are non-empty.
4. **Consistency** — download links match version metadata, and `appcast.xml` is well-formed with visible `xmllint` errors on failure.
5. **Artifact Credential/URL Scan** — release metadata and built artifacts are scanned for credential-like material and unexpected public URL domains. Mode: `YEN_ARTIFACT_URL_SCAN_GATE_MODE=off|report|enforce` (`enforce` default).
6. **Artifact Fingerprint Gate** — built app and release DMG payload are scanned for lineage/provenance residues across paths, code-signature metadata, Mach-O strings, the bundled shell CLI (`Contents/Resources/bin/yen`), and locale catalogs. Mode: `YEN_FINGERPRINT_GATE_MODE=off|report|enforce` (`enforce` default).
7. **Git State** — unstaged/staged summary, informational only. It reports a skip on a clean worktree, because the receipt framework fails any unit recording RAN with a bare zero quantity.


**Gate modes are not freely selectable.** `05-detect-failures.sh` refuses to run at all when `YEN_ARTIFACT_URL_SCAN_GATE_MODE`, `YEN_FINGERPRINT_GATE_MODE` or `YEN_DMG_LAYOUT_GATE_MODE` is anything other than `enforce`, unless `YEN_ALLOW_GATE_DOWNGRADE=1` is set explicitly (non-shipping use only). `report` is therefore not a quiet 'warning only' setting — without the acknowledgement it is a hard failure.

The script must exit 0. Any failure blocks the release.

`build-release.sh` already ran `04-verify-branding.sh` during Step 5. This verify phase focuses on artifact-level failure detection plus any AppleScript/workspace contract changes.

**Local mode:** skip this verify phase entirely. Local builds do not produce signing, notarization, DMG, staging, upload, or push artifacts.

### 6c. Conditional AppleScript / Workspace Verifier

Run the conditional AppleScript/workspace verifier:

```bash
set -o pipefail; bash $HOME/Documents/yenchat/scripts/manual/16-verify-applescript-if-needed.sh 2>&1 | tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-zip-applescript.out
```

The wrapper triggers on AppleScript/workspace contract paths changed in the worktree OR committed since the verified commit stamped in `yen-terminal/.applescript-verified`, and runs the verifier when that stamp is missing or unresolvable. It emits `RECEIPT gate=16-verify-applescript-if-needed`; read `SKIP|verifier|` versus `RAN|verifier|` in the saved `yen-zip-applescript.out` to tell a skip from a pass, never the exit code alone, because `eval-phase.sh` deletes a passing check's own log. When it must run, follow `_docs/05-infrastructure.md` -> "Validating the local `zig-out` build without quitting your own YEN.app": the verifier writes a temporary config override and fails closed if another YEN process is using an older config, so ask the operator to quit `YEN.app` or use the re-identified scratch bundle, never kill `/Applications/YEN.app`, and never launch `zig-out/YEN.app` by hand, because it shares `com.yenchat.yen` and LaunchServices activates the installed instance instead. Use `--keep-open` when AppleScript or workspace-shortcut handling changed and the final physical `Cmd + Option + 2` spot-check is wanted; AppleScript key injection bypasses the app-wide local key monitor, so it is not authoritative for that layout check.

## Step 7: Stage Release

### 7a. Stage Release Files
```bash
bash $HOME/Documents/yenchat/scripts/07-stage-release.sh
```

This stages:
- `public/stable/version.json`
- `public/stable/version.sig`
- `public/stable/appcast.xml`
- `public/stable/*.dmg.sha256`
- `package.json` (version bump)

### 7b. Agent Verification

```bash
bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/verify-agent-work.sh verify
```

Asserts that all five artifacts above are actually staged, and fails when any is missing.
Run it AFTER Step 7a — it is not a mid-phase probe.
It previously passed on both branches (staged, or "staging deferred"), so it could not fail for the reason it existed; `tests/120` now drives it in a sandbox to keep a failing path.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VF-01 | AppleScript verifier passes when its contract paths changed, receipt saved | `set -o pipefail; bash $HOME/Documents/yenchat/scripts/manual/16-verify-applescript-if-needed.sh 2>&1 \| tee $HOME/Documents/yenchat/tmp/skill-telemetry/yen-zip-applescript.out` |
| VF-02 | Post-build failure detection passes | `bash $HOME/Documents/yenchat/scripts/05-detect-failures.sh` |
| VF-03 | Release staging passes | `bash $HOME/Documents/yenchat/scripts/07-stage-release.sh` |
| VF-04 | Native slice covered exactly once: Step 6a forces it only when Step 4's saved receipt from this run shows it did not run | `bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/run-native-slice-if-needed.sh` |

**Commit any vendor bump BEFORE release Step 0.** `07-stage-release.sh` stages only `public/stable/*`, `version.json`, `version.sig`, `appcast.xml`, the DMG checksum and `package.json`. It does **not** stage `yen-terminal/.*-baseline`, `yen-terminal/VENDOR_INFO.txt` or `_docs/04-security.md`. If the vendor phase ran without its own commit first, the release ships from an engine whose baseline is untracked, and the release commit will look complete while those files sit dirty. Step V5 exists for exactly this — do not skip it just because the release follows.
