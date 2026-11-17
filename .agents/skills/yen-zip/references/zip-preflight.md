# Preflight Phase (Steps 0-1)

## Step 0: Pre-flight Checks

### 0a. CWD Guard
The invoking session may start in any directory, so enter the repo root first, then verify it:
```bash
cd $HOME/Documents/yenchat
[ "$(basename "$(pwd)")" = "yenchat" ] || { echo "Not in repo root"; exit 1; }
```

### 0b. Keychain Unlock
```bash
security unlock-keychain ~/Library/Keychains/login.keychain-db
```
If this prompts for password, enter it. A locked keychain causes misleading "timestamp service not available" errors during signing.

### 0c. Crash Triage
```bash
bash $HOME/Documents/yenchat/scripts/manual/12-check-recent-crashes.sh --days 3
```
- Exit 0: No untriaged crashes. Proceed.
- It scans macOS `.ips` reports and the bundled reporter's `~/.local/state/yen/crash/*.yencrash` files, counting a `.yencrash` only when its main executable is `/Applications/YEN.app`, and prints `Scanned <n> .ips and <n> .yencrash file(s)`. A framework abort writes only the `.yencrash`; read its JSON header with `head -c 4000` and the unified log near its timestamp to triage it.
- Exit 1: Crashes found. Triage each with `--triage <report>` or set `YEN_ALLOW_RECENT_CRASHES=1` for emergency override.

After triaging a crash report, mark it so later runs do not block on it: `bash $HOME/Documents/yenchat/scripts/manual/12-check-recent-crashes.sh --triage <report>.ips` (or `<report>.yencrash`) for one report, or `--triage-all` for every current report. Previously triaged reports are skipped automatically. `YEN_ALLOW_RECENT_CRASHES=1` is an emergency override only.

### 0d. Git State
```bash
git -C $HOME/Documents/yenchat status
```
Note any uncommitted changes. The release commit (Step 8) must include only release artifacts.

### 0e. GitHub Release Target

```bash
bash $HOME/Documents/yenchat/scripts/01-verify-release-target.sh
```

This gate verifies that `gh` is installed and signed in, that `8bittts/yenchat` is public, and that the session can push to it, which creating a release requires.

Do not wait for the post-notarization upload to discover a missing login or permission.

### 0f. Reap Leftover Vendor Runs

```bash
bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/reap-vendor-runs.sh
```

Each directory under the gitignored `tmp/vendor-runs/` holds a full Ghostty mirror plus baselines from a vendor run, about 4 GB, and nothing else removes it.
The script deletes a run directory only when no `yen-vendor`, `yen-ghostty-vendor` or `yen-workflow` lock is live and nothing inside it changed within the last day (`YEN_VENDOR_RUN_REAP_MIN_AGE_MINUTES`, default `1440`).
It prints `[reaped]` or `[held]` per directory and ends with a `RECEIPT reaper=vendor-runs` line.
It refuses, with exit 1, when the folder is a symlink, is not gitignored or holds a tracked file, and when a delete does not finish.
Step 1 takes the vendor locks itself, so the reap runs before it.

## Step 1: Vendor Status (HARD GATE)

```bash
bash $HOME/Documents/yenchat/scripts/14-vendor.sh --check --release
```

Checks every vendor in `scripts/lib/vendor-manifest.sh` for upstream updates. `--release` changes one reading: a Ghostty `behind` is accepted when the committed `.ghostty-baseline` was pushed by a `vendor:` commit within the 24h window in `scripts/lib/release-vendor-window.sh`, the vendor files are clean in the tree, and that commit is on `origin/main` after a fresh fetch. The output then carries a `Release Window` block and `RAN|release-window|accepted_behind_commits=N ...`; the release ships the audited baseline and the newer upstream commits wait for the next `/yen-zip` vendor phase. Unknown status, errors, a missing binary, a binary vendor behind, and a Ghostty baseline older than the window still block.

Default behavior:
- Exit 0: every vendor is current. Proceed to build phase.
- Missing vendor binary: run `bash $HOME/Documents/yenchat/scripts/14-vendor.sh`, then restart `/yen-zip` from Step 0.
- Behind/unknown vendor: run the vendor phase again (Steps V1 to V5, including its audit), then restart from Step 0.

Read a non-zero exit from the `Summary` block, because three different states produce it:
- `Behind: 1` for Ghostty with a `Release Window` block reading `Refused: <reason>` means upstream moved after the vendor phase ran and the baseline did not qualify: the reason names the dirty file, the non-`vendor:` subject, the age past the window, or the unpushed commit. Fix that condition or run the vendor phase again; there is no env override.
- `Unknown:` above zero is a GitHub API or token failure (`gh auth status`), not a vendor state; fix it and rerun the check.
- `ERROR: Another workflow is running` is the shared `yen-workflow` lock held by a live `14-vendor.sh`, `build-release.sh` or `finalize-build.sh`; wait for that PID, never remove a live lock.

Pinned-by-rollback exception:
- If a vendor is reported behind and the current baseline commit matches `_docs/04-security.md` -> `Ghostty Rollback History`, the pin is deliberate and `/yen-zip` may proceed from that materialized baseline. The ledger table is empty while no range is pinned, so the exception is dormant until a row exists; do not read an ordinary upstream-moved `Behind: 1` as this case.
- PF-04 records the raw check, so a run that proceeds under the exception carries a PF-04 FAIL into `summary`; re-record PF-04 with the ledger match as its command (a `grep` of the baseline commit against the ledger row) before continuing, or the final summary fails.
- No `YEN_ZIP_ALLOW_STALE_VENDORS` bypass exists. If a sub-script starts enforcing currency despite the documented pin, fix that script or add the row to the rollback ledger; do not invent an env override.
- Any other behind state blocks shipping.

Rollback-history warning:
- `14-vendor.sh --check` can warn when the fetched `current...main` range overlaps the rollback ledger.
- The warning is informational only. It records prior bad ranges, not a current hard block.
- `YEN_VENDOR_BLOCK_ON_ROLLBACK=1` makes that warning fail closed for update audits, but normal `/yen-zip` preflight treats it as a warning.

This is a HARD GATE. Do not proceed unless vendors are current, Ghostty is accepted by the release window, or the pinned-by-rollback exception applies.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| PF-01 | CWD is repo root | `[ "$(basename "$(pwd)")" = "yenchat" ]` |
| PF-02 | Keychain unlocked and signing identity usable | `TEST_BIN=$(mktemp) && echo 'int main(){return 0;}' | clang -x c -o "$TEST_BIN" - && source $HOME/Documents/yenchat/scripts/lib/signing-constants.sh && codesign --sign "$SIGNING_IDENTITY" "$TEST_BIN" >/dev/null 2>&1; rc=$?; rm -f "$TEST_BIN"; exit $rc` |
| PF-03 | No untriaged crashes | `bash $HOME/Documents/yenchat/scripts/manual/12-check-recent-crashes.sh --days 3` |
| PF-04 | Every vendor current, or Ghostty behind inside the release window, or pinned by rollback | `bash $HOME/Documents/yenchat/scripts/14-vendor.sh --check --release` |
| PF-05 | GitHub release target public and pushable | `bash $HOME/Documents/yenchat/scripts/01-verify-release-target.sh` |
| PF-06 | Leftover vendor runs reaped or held | `bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/reap-vendor-runs.sh` |
