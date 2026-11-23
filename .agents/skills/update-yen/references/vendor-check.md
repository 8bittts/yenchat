# Vendor Check (Step V1)

## Check Upstream Status

Run `eval-phase.sh begin yen-vendor` first, then run the check once and keep its output. The eval reads the saved file instead of re-running the check, so the upstream APIs are hit once per phase; it accepts the file only when it is newer than the run id file `begin` wrote.

```bash
OUT=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-check.out
mkdir -p "$(dirname "$OUT")"
bash $HOME/Documents/yenchat/scripts/14-vendor.sh --check > "$OUT" 2>&1; code=$?; echo "$code" > "$OUT.code"
```

The script reads each `yen-terminal/.*-baseline`, resolves Ghostty through `scripts/lib/upstream.sh` (`forge_github` today; `YEN_UPSTREAM_*` only for parity or cutover work), queries GitHub release APIs for the other vendors, and prints one status block per vendor plus a `Summary` banner.

## Reading the Result

Decide from positive fields, never from an absent string:

- `Behind:` and `Unknown:` counts in the Summary say what needs an update.
- `Errors:` must be `0`.
- Exit code `0` = all current: record VC-01, skip Steps V2 to V5, and start the release at Step 0. `1` = one or more behind or unknown: continue to Step V2. Anything else, or no `Summary` banner, is a check failure.

`RECEIPT gate=14-vendor ... result=FAIL` is expected in check mode whenever a vendor is behind; Step V2 turns it green.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VC-01 | Check ran in this run and reported cleanly (exit 0 all current, 1 updates available) | `OUT=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-check.out; test "$OUT" -nt $HOME/Documents/yenchat/tmp/skill-telemetry/yen-vendor-eval-run.id && code=$(cat "$OUT.code") && grep -q 'Summary' "$OUT" && grep -Eq 'Errors:[[:space:]]*0' "$OUT" && [ "$code" -eq 0 -o "$code" -eq 1 ]` — the exit code is read from `$OUT.code` because every Bash-tool call is a fresh shell, and the `-nt` test rejects a file left by an earlier run. |
