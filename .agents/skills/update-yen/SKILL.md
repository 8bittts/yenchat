---
name: update-yen
description: Full YEN maintenance update and release cut. Update YEN's Bun packages and vendored Sparkle (the yenchat work /update-projs no longer does), then every vendored dependency (Ghostty source plus the tools in scripts/lib/vendor-manifest.sh) with a 6-layer breaking-change audit, then build, sign, notarize, and ship a new YEN desktop release and publish its blog.yen.chat release notes, with fail-fast gates and machine-evaluable verification. Runs on autopilot, taking majors and minors by default, with breaking-change review and fixes. Invoke with /update-yen or $update-yen for the deps phase, the vendor phase and a full release, or /update-yen local for an incremental compile and verify that ships nothing.
---

# YEN Update Skill

**One skill, one path.** `yenchat/.agents/skills/update-yen` is the file set. Claude discovers it as a project skill inside this repo and reaches it from any other directory through the global pointer command `~/.claude/commands/update-yen.md`; Codex reaches it through the `~/.codex/skills/update-yen` symlink. There is deliberately no `~/.claude/skills/update-yen` link, because a user-scope link into this repo lists the skill twice in the picker here, while a same-name command does not. The pointer carries no workflow content.

**Runs from any directory.** The invoking session may start in any project. Before Step D1, `cd $HOME/Documents/yenchat`; the CWD guard below then holds, and every script and git call already uses that absolute root.

**One entry point.** `/update-yen` is the only maintenance path for yenchat: the deps phase (Steps D1 to D6) runs first, then the vendor phase (Steps V1 to V5), then the release cut. `/update-projs` does not cover yenchat, and the retired `/yen-zip` and `/yen-vendor` names have no pointer, symlink or backup left. YEN is in maintenance mode (`AGENTS.md` → Maintenance Mode), and this skill is its update and release path.

**Mirror Update Rule:** Any change to `/update-yen` behavior, gates, counts, phase names, eval requirements, local/full mode routing, deps guidance, vendor guidance, or release guidance lands in `.agents/skills/update-yen/SKILL.md` and the affected `references/*` file in the same commit. `tests/119-vendor-process-guardrails.test.ts` pins the deps and vendor phases and `tests/120-zip-process-guardrails.test.ts` pins the release; when this rule itself changes, update `AGENTS.md` and those tests in the same commit.

**Runtime Sync Rule:** `~/.claude/commands/update-yen.md` is the one short pointer, and `8leeai/_global/claude-commands/update-yen.md` is its committed backup; refresh the backup in the same change (`cp`, then `cmp`) whenever the pointer text changes.

## Success Criteria

**Outcome:** every Bun package and the vendored Sparkle at their latest allowed versions with the `deps:` commit pushed, then every manifest vendor at its latest upstream with overlays verified and the `vendor:` commit pushed, then a signed, notarized, Sparkle-ready DMG uploaded to its GitHub Release with matching version metadata committed and pushed to main.

**Process:**
- 6-layer audit for Ghostty; layers 3-6 for binary and source-built vendors, with an audit log handed to `verify-audit-layers.sh`
- Every hard gate must pass before the next phase begins
- Eval checks run after each phase; any FAIL stops the workflow
- `verify-agent-work.sh` confirms the staged release set and the published, clean result
- Artifact fingerprint coverage includes paths, code-signature metadata, Mach-O strings, the bundled shell CLI (`Contents/Resources/bin/yen`), and locale catalogs

**Style:**
- Commit message format: `deps: <summary>` for the deps phase, `vendor: ...` for the vendor phase, `v<version>: <description> [deploy]` for the release
- Explicit file staging only (never `git add .` or `git add -A`)
- CWD guards respected (repo root for most steps; build entrypoints invoked by absolute path)
- Claude Code default-branch pushes must pass `dangerouslyDisableSandbox: true` on the Bash call; the sandbox heuristic can block `git push origin main` even when broad permissions are enabled.

**Efficiency:**
- **Minimal repair.** When an overlay anchor drifts, make the smallest change that restores the gate: re-anchor the `.old`/`.new` pair, or retire the patch with a marker test. Hardening the gate does not need — new shared libraries, extra release gates, broader suites, tool refreshes — stays out of the run and out of `_docs/todos.md`; name it in the final summary. Investigate only the compare-range files and the anchored file.
- **Parallel gates.** Step V4 detaches the smoke build, then runs the project gates alongside it (`references/vendor-build.md`); only `tests/76` waits for the build.
- **Native slice once per phase.** Step V4's VB-05 runs `run-native-slice-if-needed.sh yen-vendor` after the build; it forces the native `xcodebuild` slice only when VB-01's saved receipt shows the pre-build gate could not run it (a Ghostty refresh removes `YENKit.xcframework`). Never re-run the whole component gate by hand to get native coverage.
- **Skip-build default for non-code bumps.** The release follows the vendor phase, so a bump that touches no Ghostty `*.swift`, `*.zig`, `build.zig`, Xcode project, package pin or overlay source skips the Step V4 smoke build, and release Step 5 is its compile gate. Any code, project or overlay change still runs the smoke build, and so does a run where the release is not following immediately, or where VB-04's AppleScript verifier triggers and finds no `zig-out/YEN.app` (`references/vendor-build.md`).
- `/update-yen local` skips the deps phase, the vendor phase, signing, notarization, DMG, and upload, and uses `scripts/native/01-macos-smoke.sh --local` as the canonical non-shipping loop
- `YEN_PREBUILD_COMPONENT_GATE_MODE=off` when Step 4 already ran verification
- `YEN_COMPONENT_XCODE_REGRESSION_MODE=auto` runs Step 4's native `xcodebuild` slice only when native macOS files or the tracked Ghostty baseline changed since the latest `[deploy]` release; set `always` to force it. A cleaned xcframework skips it; Step 6a (VF-04) then forces the slice after Step 5, and only then: when Step 4's saved receipt shows `RAN|xcode-regression|`, 6a skips instead of re-running all 17 component units

## Mode Routing

| Invocation | Mode | Behavior |
|-----------|------|----------|
| `/update-yen` | full | Deps phase (Bun packages, `bun audit`, Sparkle, gates, `deps:` commit, push), then the vendor phase (check, update, audit, build, `vendor:` commit, push), then a new release cut: build + sign + notarize + DMG + upload + commit + push |
| `/update-yen local` | local | Incremental build only: compile + verify. No signing, no ship. |

Local mode uses `bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local` and never ships or updates packages or vendors. Vendor status alone, with no downloads, is `bash $HOME/Documents/yenchat/scripts/14-vendor.sh --check`; it is a read, not a mode.

## Phase Map

| Phase | Steps | Reference | Scripts Called |
|-------|-------|-----------|---------------|
| deps | D1-D6 | `references/deps-update.md` | `bunx npm-check-updates`, `bun audit`, Sparkle refresh, `bun run check:full`, git commit/push |
| vendor check | V1 | `references/vendor-check.md` | `14-vendor.sh --check` |
| vendor update | V2 | `references/vendor-update.md` | `14-vendor.sh`, individual vendor scripts |
| vendor audit | V3 | `references/vendor-audit.md` | 6-layer audit (Ghostty), layers 3-6 (others) |
| vendor build | V4 | `references/vendor-build.md` | `03-verify-components.sh` (teed), `scripts/native/01-macos-smoke.sh --local`, project gates in parallel, `run-native-slice-if-needed.sh yen-vendor`, `13-scan-artifact-fingerprints.sh`, `manual/16-verify-applescript-if-needed.sh` |
| vendor commit | V5 | `references/vendor-commit.md` | git add/commit/push, vendor summary, upstream changelog |
| preflight | 0-1 | `references/zip-preflight.md` | `manual/12-check-recent-crashes.sh`, `01-verify-release-target.sh`, `reap-vendor-runs.sh`, `14-vendor.sh --check --release` |
| build | 2-5 | `references/zip-build.md` | `03-verify-components.sh` (teed), `build-release.sh`, `scripts/native/01-macos-smoke.sh` |
| verify | 6-7 | `references/zip-verify.md` | `run-native-slice-if-needed.sh`, `manual/16-verify-applescript-if-needed.sh`, `05-detect-failures.sh`, `07-stage-release.sh` |
| release | 8-12 | `references/zip-release.md` | `scripts/gen-release-notes.ts`, `bun run build`, git commit/push (`finalize-build.sh` runs earlier, inside build-release.sh step [9/9]) |

Load only the reference file for the current phase. Do not preload all references.
Step D2 decides the deps phase: nothing outdated skips Steps D3 to D6 and goes to Step V1. Step V1 decides the vendor phase: exit 0 (all current) skips Steps V2 to V5 and goes straight to Step 0. Recovery patterns live in `references/vendor-troubleshooting.md`, and audit conflict resolution in `references/vendor-audit-decision-matrix.md`; Yazi title recovery follows the `ind-app-title` subscriber, not the retired static key.
Step 5 compiles the app for arm64 only, the one architecture macOS 27 runs on; a Swift isolation error surfaces there.

**Release notes are a required part of the release phase, not optional docs.** Step 8 prepares the version's factual line in `RELEASE_COPY` for the public SEO gate.
Step 11 creates or refreshes the current Monday-start `RELEASE_WEEK_COPY` story in `lib/release-notes/release-notes-copy.ts`. The weekly story must establish the meaningful theme, name the most important concrete improvements, and close on why the updates are better to use or worth downloading; do not concatenate every build into a feature inventory. It must be broken into blank-line-separated paragraphs (a literal `\n\n` in the string, rendered one `<p>` each — 2-3 paragraphs for a substantial week, 1-2 for a thin one) and written so the reader wants to try it: lead with the change a person would feel, in the second person, preferring one concrete detail over a category.
Step 11 then runs `scripts/gen-release-notes.ts` + `bun run build` and ships `docs: publish v<version> release notes [deploy]` as a short follow-up commit. Release evals therefore use Git history filtering to validate the newest matching versioned release commit, not `HEAD`. See `references/zip-release.md` Step 11 and `_docs/10-gtm.md` -> "Release Notes".
Verify the published manual on the homepage and the permanent redirect from the former docs route.

## Vendor Roster

`scripts/lib/vendor-manifest.sh` is the single roster; this skill does not restate it. Read it with `command grep -E '^[[:space:]]*"?[a-z]+\|' scripts/lib/vendor-manifest.sh`. Each record gives key, type, and update script; the baseline is `yen-terminal/.<key>-baseline` and binaries land in `yen-terminal/customizations/vendor/<key>/`. The human-readable table lives in `scripts/00-scripts-readme.md` → Vendor Registry.

## Vendor Phase Gates

Automatic fail-fast gates in `14-vendor.sh` and `10-update-ghostty.sh`:

- **Toolchain preflight** (`14-vendor.sh`, Ghostty branch, through `scripts/lib/zig-toolchain.sh`): resolves a verified target commit, reads its `build.zig.zon` through `scripts/lib/upstream.sh`, and compares the incoming pin with local `zig version` before downloading that same commit. Fetch failures, missing pins, and unreadable local versions fail closed. On mismatch, install the toolchain with the printed `zigup fetch` command instead of setting `YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT=1`. `validate-environment.sh` shares the pin comparison before each build.
- **Stale binary recovery** (`14-vendor.sh`): an installed `.version` differing from the baseline requires a verified download of the baseline version. Check mode reports it as missing readiness. Matching-version digest mismatches still fail closed, including with `--force`.
- **Upstream provenance** (`vendor-binary.sh`, `10-update-ghostty.sh`): binary assets must match GitHub release-asset digest metadata, source tags resolve to immutable commit archives, and Ghostty commits must carry verified forge status. A forge-verified new commit pins its archive digest on first fetch (`reason=pin-on-first-fetch` in `tmp/vendor-integrity-audit.log`); unavailable or mismatched provenance fails closed through the audited integrity override. The pin lives in `.ghostty-baseline`, which a rollback restores, so a retried fetch of the same commit is pinned again as a first fetch — compare the two `pin-on-first-fetch` digests in the audit log before trusting a retry.
- **Rollback-history check** (`14-vendor.sh`, Ghostty branch): compares the fetched `current...main` range against `_docs/04-security.md` → `Ghostty Rollback History` and warns on overlap. Warning-only by default; audit Layer 4 is the real gate. Hard block: `YEN_VENDOR_BLOCK_ON_ROLLBACK=1`. The compare body goes to the matcher as a file, never the environment, because a wide range overflows `ARG_MAX`; a check that cannot run prints `Rollback-history check failed` and blocks under the same flag.
- **Pre-overlay structural diff** (`10-update-ghostty.sh` `[3a/5]`, only when a fresh tree was downloaded): normalizes YEN's documented `overlays/build.zig` customizations (`YENCustomResources` block, `// YEN:` comments, `libyen-vt.a` / `yen-vt-static.lib`, `include/yen`, `<yen/vt.h>`) with `scripts/lib/normalize-overlay-buildzig.py`, diffs the result against pristine upstream `build.zig`, and enumerates file-replacing overlays that diverge — before `apply-overlays.sh` hides the drift. `build.zig` drift is a hard fail; bypass `YEN_VENDOR_SKIP_BUILDZIG_DRIFT=1`. Post-overlay diffs of `ghostty/` against `overlays/` are always empty and prove nothing; read the `[3a/5]` receipt lines instead.
- **Build-overlay upstream tripwire** (same phase): `yen-terminal/.overlay-upstream-pairs.txt` pins the SHA256 of upstream's copy of every file a whole-file overlay replaces (Swift, xib, and the Zig build files including `src/build/LibtoolStep.zig`). Read the live pair count with `command grep -cvE '^[[:space:]]*(#|$)' yen-terminal/.overlay-upstream-pairs.txt`, never `wc -l`. Structural breaks (overlay or upstream counterpart missing) are not waivable; content drift is, via `YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1` after review. Port drift from the forge compare range (`<baseline>...<new>`), never from a local diff, because an aborted run leaves the previous tree with overlays applied. Port the symbols upstream's tests need, not just the ones YEN renders, and say why in a comment. Immediately before Step V4 confirm the port survived with `git status --porcelain -- yen-terminal/overlays`; another agent can stash a dirty tree.
- **Patch-target preflight** (`apply-overlays.sh`): `patch_file` fails closed on a missing target (`--optional` is the only opt-out), and `GHOSTTY_PATCH_TARGETS` validates every declared target after branding so an upstream relocation reports every casualty at once. Count entries from the array, never from a remembered number. Guarded by `tests/45` → "upstream relocation guardrails".
- **Baseline snapshot/revert hint** (`scripts/native/01-macos-smoke.sh --local|--build-only`): snapshots `.ghostty-baseline`, `VENDOR_INFO.txt`, `_docs/04-security.md` before the build and prints the exact `git checkout --` command on failure. No auto-revert.
- **Ghostty upstream plumbing** (`scripts/lib/upstream.sh`): single source of Ghostty upstream coordinates (`forge_github` adapter today). `YEN_UPSTREAM_HOST` / `OWNER` / `REPO` / `FORGE` exist for parity testing and forge cutover only.
- **No-write parity snapshot** (`scripts/40-vendor-parity-snapshot.sh`): `--baseline <path>` before a no-op plumbing edit, `--verify <path>` after, to prove `14-vendor.sh --check` decisions did not drift.
- **fd source-build output pin** (`16-vendor-fd.sh`): a no-op run validates the bundled `fd` against `.fd-baseline` `output_sha256`; a missing or mismatched pin fails through the integrity gate.

## Release Preflight Gates

The release inherits the vendor phase's hardening via `build-release.sh` and `14-vendor.sh --check --release`:

- **GitHub release-target check** (`scripts/01-verify-release-target.sh`): verifies the release repository is reachable, public, and pushable by the current `gh` session before build and notarization.
- **Notarization credential check** (`build-release.sh`): requires successful, non-empty `notarytool history` output before compile work; `finalize-build.sh` repeats it as a packaging backstop.
- **Zig version check (toolchain preflight)** (`validate-environment.sh`, Step 1/9 of `build-release.sh`): compares local `zig version` to `yen-terminal/ghostty/build.zig.zon` `.minimum_zig_version`; fails fast with a `zigup fetch <version>` recovery command on mismatch. Replaces the previous cryptic `process has no member named 'EnvMap'` failure deep inside Step 5. Bypass: `YEN_SKIP_ZIG_VERSION_CHECK=1`.
- **Stable Xcode policy** (`validate-environment.sh`; guards the Step V4 smoke build and the release build, as the SDK linker probe does): rejects beta and release-candidate Xcode selections before any build work. Select `/Applications/Xcode.app`, or use `YEN_ALLOW_PRERELEASE_XCODE=1` only for an explicit non-release experiment.
- **SDK linker probe** (`build-release.sh`, before every `zig build`): compiles a trivial libSystem-using program to confirm the Xcode SDK resolves Zig's linker symbols; activates the synthetic-sysroot + xcrun-wrapper workaround on probe failure even when the top-`targets:` heuristic says the SDK looks fine. Bypass: `YEN_SKIP_ZIG_SDK_WORKAROUND=1`.
- **Rollback-history warning** (Step 1, `14-vendor.sh --check`): informational only — does not fail the hard gate. It means the fetched `current...main` range overlaps `_docs/04-security.md` → `Ghostty Rollback History`; audit Layer 4 in Step V3 remains the real breaking-change gate.
- **Release window** (Step 1, `14-vendor.sh --check --release`): a Ghostty `behind` is accepted when the committed baseline was pushed by a `vendor:` commit within the 24h window in `scripts/lib/release-vendor-window.sh`, the vendor files are clean, and the commit is on `origin/main`; the receipt reads `RAN|release-window|accepted_behind_commits=N ...`. Ghostty tracks a moving branch, so a plain check failed 4 of 12 releases whose vendor lap finished after the next upstream commit. Everything else that is behind, unknown, or missing still blocks, and the window is a constant, not an env override.
- **Pinned-by-rollback exception** (Step 1): if `14-vendor.sh --check` reports a vendor behind and the current baseline commit matches a documented rollback-history row, the pin is deliberate and `/update-yen` may proceed from the pinned baseline. Any other behind/missing vendor state blocks shipping until the vendor phase resolves it. No `YEN_ZIP_ALLOW_STALE_VENDORS` bypass exists; if a sub-script starts enforcing currency despite the documented pin, fix that script rather than reaching for an env override.
- **Baseline revert hint** (smoke wrapper only, `scripts/native/01-macos-smoke.sh --local|--build-only`): does NOT fire for shipping `/update-yen` Step 5 (`build-release.sh` is called directly). Step 1's hard vendor gate already prevents shipping builds from having in-flight vendor mutations.

## Eval Protocol

The deps phase, the vendor phase and the release keep separate eval namespaces, so a release restart from Step 0 never re-runs or borrows an earlier phase's evidence. `yen-deps` and `yen-vendor` name those phases' records and `tmp/skill-telemetry/yen-deps-*` and `yen-vendor-*` files; they are not skills.

```bash
E=$HOME/Documents/yenchat/.agents/skills/update-yen/scripts/eval-phase.sh
bash "$E" begin yen-deps                                         # once, at Step D1
bash "$E" check yen-deps <CHECK_ID> "<description>" "<command>"   # references/deps-update.md Eval Checks
bash "$E" summary yen-deps                                       # after Step D6, or after DP-03 when nothing is outdated
bash "$E" begin yen-vendor                                       # once, at Step V1
bash "$E" check yen-vendor <CHECK_ID> "<description>" "<command>" # the vendor reference's Eval Checks table
bash "$E" summary yen-vendor                                     # after Step V5, or after V1 when all vendors are current
bash "$E" begin update-yen                                          # once, at Step 0
bash "$E" check update-yen <CHECK_ID> "<description>" "<command>"   # the current phase's Eval Checks table
bash "$E" summary update-yen                                        # after Step 12
```

Each phase reference owns its checks in an Eval Checks table; run each operation through its check on its first execution, never a second time only to record it.
On any FAIL, stop the workflow; do not proceed to the next phase.
Release IDs match `^(PF|BD|VF|RL)-[0-9][0-9]$`, vendor IDs `^(VC|VU|VA|VB|VK)-[0-9][0-9]$` and deps IDs `^DP-[0-9][0-9]$`; each `summary` must print `Result: PASS`; it fails on an empty set, a missing file, or a failure carried over from before local midnight. A check that reads a saved file or a build product (DP-02, DP-05, VC-01, VU-01, VB-02, VB-05, BD-03, VF-04) first tests it `-nt` the run id file `begin` wrote, so an earlier run's artifact cannot pass this one. The skip-build default records no VB-02 and no VB-05.
`/update-yen local` runs PF-01 to PF-06 and BD-01 to BD-03 only, so its summary covers fewer IDs, never zero.
PF-06 reaps leftover `tmp/vendor-runs/` scratch in both modes (`references/zip-preflight.md` Step 0f).
The script prints `[RUN]`, a `[RUNNING]` heartbeat (`YEN_SKILL_EVAL_HEARTBEAT_SECONDS`; `0` disables it), and the output tail on failure; its header documents run scoping and JSON rules.

## Audit Verification

Append one `LAYER n: <finding>` line per audit layer to an audit log during Step V3, then hand it to the verifier — it fails closed without it:

```bash
bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/verify-audit-layers.sh <vendor> "$AUDIT_LOG"
```

Ghostty requires layers 1-6; binary and source-built vendors require 3-6.

## The 6-Layer Audit (Ghostty)

1. **Overlay health** — did every `apply-overlays.sh` patch apply, and does it re-apply idempotently?
2. **Structural changes** — did upstream rename, split, or move files overlays depend on? Read the `[3a/5]` receipts.
3. **Branding residue** — `04-verify-branding.sh` passes with its subject and manifest counts intact.
4. **Config and feature audit** — new keys, changed defaults, removed features, keybind conflicts, and every AppKit hit-test / coordinate / responder-chain / local-monitor change (P1 until reviewed).
5. **Compile gate selection** (HARD GATE) — Step V4 local smoke build after a Ghostty refresh or any project/Sparkle change; standalone `xcodebuild` only for non-Ghostty bumps with an intact xcframework, judged by `** BUILD SUCCEEDED **`.
6. **Decision and documentation** — `_docs/04-security.md` (snapshot metadata and overlap header auto-sync through `11-sync-vendor-audit.sh`; confirm with `12-verify-vendor-audit.sh`; hand-edit the patch table and overlap notes), memory files, and the retirement checklist when a patch retires.

Binary and source-built vendors run layers 3-6 plus the vendor-specific checks in `references/vendor-audit.md`.

## Agent Verification

```bash
bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/verify-agent-work.sh verify    # after Step 7a
bash $HOME/Documents/yenchat/.agents/skills/update-yen/scripts/verify-agent-work.sh release   # after Step 11
```

`verify` asserts that the five release artifacts are staged; `release` asserts the release commit format, remote `main` at `HEAD`, and a clean tree.

## CWD Guards

- **Default CWD:** the repo root (`$HOME/Documents/yenchat`) for every step; verify it before every script invocation.
- **During build (Step 5):** Full releases invoke `bash $HOME/Documents/yenchat/yen-terminal/customizations/build-release.sh ...`; local mode invokes `bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local`. Never `cd yen-terminal` for a build.
- **Repo-root scripts + git:** Use `bash $HOME/Documents/yenchat/scripts/...` and `git -C $HOME/Documents/yenchat ...` so post-failure investigation in subdirectories cannot drift later steps
- The operator shell aliases `sed`, `grep`, `find`, `ls`, `ps`, and `diff` on a terminal; in Bash-tool one-liners use `command <tool>` or `/usr/bin/<tool>`.

## Lock Handling

Scripts use directory-based locks in `$TMPDIR`:
- `yen-vendor-<cksum>.lock` and `yen-ghostty-vendor-<cksum>.lock` — held by `14-vendor.sh` and `10-update-ghostty.sh` during Steps V1 and V2
- `yen-workflow-<cksum>.lock` — shared by `14-vendor.sh`, `build-release.sh` and `finalize-build.sh`; Step 1's `14-vendor.sh --check` fails with `Another workflow is running` while any of them runs, which is a lock conflict, not a vendor state
- `yen-build-release-<cksum>.lock` — build phase
- `yen-finalize-build-<cksum>.lock` — held by `finalize-build.sh` during build-release.sh step [9/9]

If a lock exists, check if the owning PID is alive with `command ps -p <pid>` (the aliased `ps` rejects the flags and looks like "dead"). Stale locks (dead PID) are auto-cleaned. Never force-remove a live lock.

## Restart Policy

Deps phase: restart from the step that failed; once Step D6 pushed, the deps phase is done and a later failure does not repeat it. Vendor phase: restart from the step that failed. `10-update-ghostty.sh` re-checks upstream itself, so V1 is not repeated after an overlay repair. Once Step V5 pushed, the vendor phase is done; a later release failure does not repeat it, because Step 1's release window accepts the pushed `vendor:` baseline.

Release: on failure, restart from Step 0 (preflight). No mid-release resume. The release is atomic — partial results are not shippable. Exception: `/update-yen local` failures can be retried from the failed step since no external state is mutated.

## Output Files

| Artifact | Path |
|----------|------|
| Deps detection and gate output | `tmp/skill-telemetry/yen-deps-ncu.out`, `yen-deps-audit.out`, `yen-deps-gates.out` |
| Vendor check / update output | `tmp/skill-telemetry/yen-vendor-check.out`, `tmp/skill-telemetry/yen-vendor-update.out` |
| Vendor component gate and smoke build receipts | `tmp/skill-telemetry/yen-vendor-components.out`, `tmp/skill-telemetry/yen-vendor-smoke.out` |
| Integrity audit log | `tmp/vendor-integrity-audit.log` |
| Updated baselines | `yen-terminal/.*-baseline` |
| Eval results | `tmp/skill-telemetry/yen-deps-eval-<date>.jsonl`, `tmp/skill-telemetry/yen-vendor-eval-<date>.jsonl`, `tmp/skill-telemetry/update-yen-eval-<date>.jsonl` |
| Build log | `yen-terminal/ghostty/zig-out/` (transient) |
| DMG | Uploaded to the `v<version>` GitHub Release on `8bittts/yenchat` |
| Release metadata | `public/stable/version.json`, `version.sig`, `appcast.xml`, current DMG checksum |
