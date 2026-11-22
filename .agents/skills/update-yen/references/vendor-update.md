# Vendor Update (Step V2)

## Download and Update

Binary downloads must match GitHub release-asset digest metadata before extraction. Source-built vendors download the immutable commit archive resolved from the release tag. Ghostty requires verified forge commit status before its exact-commit archive is accepted; a forge-verified new commit pins its archive digest on first fetch (`reason=pin-on-first-fetch` in `tmp/vendor-integrity-audit.log`). Unavailable or mismatched provenance fails closed through the audited integrity override.

Keep the output; the eval reads it, and VU-01 requires the file to postdate this run's `begin` so an earlier run's receipt cannot stand in for this one.

```bash
OUT=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-update.out
bash $HOME/Documents/yenchat/scripts/14-vendor.sh > "$OUT" 2>&1; echo "exit=$?"
```

### Ghostty (source vendor)

`14-vendor.sh` first resolves a verified target commit and checks its incoming Zig pin.
It passes that same commit to the updater; missing pins or failed reads stop before archive download.
Install the reported Zig version before retrying.

`14-vendor.sh` delegates to `bash $HOME/Documents/yenchat/scripts/10-update-ghostty.sh`, which:

1. Checks upstream through `scripts/lib/upstream.sh` (uses `GITHUB_TOKEN` from `gh auth token` while GitHub is the forge).
2. Downloads the exact-commit tarball with `--retry 3` and verifies it against the integrity pin.
3. Neutralizes upstream agent-instruction files (`[2b/5]`).
4. Runs the pre-overlay structural diff and pair tripwire (`[3a/5]`) on the pristine tree.
5. Replaces `yen-terminal/ghostty/` and runs `apply-overlays.sh` (branding, patches, renames, assertions).
6. Runs `04-verify-branding.sh` BEFORE writing `.ghostty-baseline` and `VENDOR_INFO.txt`; any failure restores `ghostty.backup` and writes nothing.

Skipped download when already at the upstream commit (`SKIP_DOWNLOAD=1`); there is no tarball cache beyond that.

### Non-Ghostty Vendors

An installed `.version` that differs from the baseline requires a verified download of the baseline version.
After a pull that changes a pin at the same version, reinstall with the vendor script and `--force`; the result must reproduce the pinned digest.
Check mode reports the required download without modifying files.
A digest mismatch at the same version remains an integrity failure, even with `--force`.

Each manifest record names a thin wrapper in `scripts/` over `scripts/lib/vendor-binary.sh` (or a source-build script for btop, zmx). It downloads or builds an arm64-only binary, verifies `lipo -archs` and exec-liveness, installs it under `yen-terminal/customizations/vendor/<key>/`, and writes `yen-terminal/.<key>-baseline` plus `.version`.

## When the Update Fails

- `apply-overlays.sh` anchor drift → `10-update-ghostty.sh` restores the previous tree and exits 1. Repair per `references/vendor-audit.md` Layer 1 (minimal repair), then re-run only the update phase.
- Because the rollback restores `.ghostty-baseline`, the retried fetch of the same commit is pinned again as a first fetch. Before trusting the retry, confirm both `pin-on-first-fetch` lines for that commit in `tmp/vendor-integrity-audit.log` carry the same digest.
- Integrity gate on a commit that already matches the baseline but with a different digest: treat as corrupt or tampered; do not bypass.

### Repair Loop

A fresh-tree failure stops at the first problem, so expect one round per layer: `[3a/5]` `build.zig` drift, then `apply-overlays.sh` anchor drift. Each failed run restores the previous tree.
- `build.zig` content drift: port upstream's hunks from the forge compare range into `yen-terminal/overlays/build.zig`, then re-run with `YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1` to re-pin. Port before the first run when the compare range lists `build.zig`.
- Anchor drift: repair per `references/vendor-audit.md` Layer 1; to retire a patch, follow its Overlay Retirement Checklist so the call and the plan entry both go.
- Call every script by absolute path; a hook refuses a relative `bash scripts/...` line.

## Integrity Bypass

`YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1` with `YEN_VENDOR_INTEGRITY_BYPASS_REASON='<specific reason>'` is logged to `tmp/vendor-integrity-audit.log`. Verify author and commit through the forge first. The variable is read live on every call, so `unset` both afterwards; `14-vendor.sh` prints a loud summary warning whenever it was active.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VU-01 | The update run passed in this run; a rolled-back run fails, a stale output file fails, and baseline presence alone never proves an update | `OUT=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-update.out; test "$OUT" -nt $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-eval-run.id && grep -Eq 'RECEIPT gate=14-vendor .*result=PASS' "$OUT"` |
| VU-02 | Every manifest key has a non-empty baseline | `for k in $(command grep -E '^[[:space:]]*"?[a-z]+\|' $HOME/Documents/yenchat/scripts/lib/vendor-manifest.sh \| cut -d'\|' -f1 \| tr -d ' "'); do test -s $HOME/Documents/yenchat/yen-terminal/.$k-baseline \|\| exit 1; done` |
