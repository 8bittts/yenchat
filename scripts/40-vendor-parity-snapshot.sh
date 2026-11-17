#!/bin/bash
# Vendor Parity Snapshot
#
# Runs `14-vendor.sh --check` (read-only by definition) and emits a normalized,
# deterministic snapshot of the decision-relevant output. Used to prove that
# the Phase 0 refactor of upstream URL plumbing is a pure no-op transform —
# same baseline reading, same upstream comparison, same current/behind/error
# verdict per vendor.
#
# Usage:
#   ./scripts/40-vendor-parity-snapshot.sh                  # print normalized snapshot
#   ./scripts/40-vendor-parity-snapshot.sh --hash           # print SHA-256 of snapshot
#   ./scripts/40-vendor-parity-snapshot.sh --verify <path>  # diff snapshot vs baseline
#   ./scripts/40-vendor-parity-snapshot.sh --baseline <path>  # write snapshot to <path>
#
# Caller workflow for refactor-time parity:
#   1. ./scripts/40-vendor-parity-snapshot.sh --baseline /tmp/yen-vendor-parity.txt
#   2. <refactor scripts to use scripts/lib/upstream.sh>
#   3. ./scripts/40-vendor-parity-snapshot.sh --verify /tmp/yen-vendor-parity.txt
#
# Normalization strips run-to-run drift while preserving every decision signal:
#   - Numeric "N commits ahead" counts (upstream churn between runs)
#   - Trailing whitespace
#   - Cache-warming / timing artifacts (none currently emitted; future-proofed)
# HTTP error codes, version strings, sync dates, and current/behind verdicts
# remain literal — those ARE the parity contract.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
MODE="text"
ARG_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --hash) MODE="hash" ;;
        --verify)
            shift
            [ $# -gt 0 ] || { echo "ERROR: --verify requires a path" >&2; exit 1; }
            MODE="verify"
            ARG_PATH="$1"
            ;;
        --baseline)
            shift
            [ $# -gt 0 ] || { echo "ERROR: --baseline requires a path" >&2; exit 1; }
            MODE="baseline"
            ARG_PATH="$1"
            ;;
        --help|-h)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# `|| true` used to swallow every failure mode. With the shared workflow lock
# held by a concurrent /yen-zip, `14-vendor.sh --check` prints only
# "ERROR: Another workflow is running" and exits 1 — and this script then wrote
# that error string as the baseline, reported "[OK] Wrote vendor parity
# baseline", and on a later --verify compared the error string against itself
# and reported "[OK] matches baseline". Both exit 0. This is the harness used to
# PROVE a forge-swap is a no-op, so a false OK is the whole failure.
#
# --check exits 0 when everything is current and 1 when a vendor is behind or
# unknown; both are legitimate snapshot states. Anything else is a real error.
set +e
raw_output=$("$REPO_ROOT/scripts/14-vendor.sh" --check 2>&1)
vendor_status=$?
set -e

if [ "$vendor_status" -ne 0 ] && [ "$vendor_status" -ne 1 ]; then
    echo "ERROR: 14-vendor.sh --check exited $vendor_status — cannot take a parity snapshot." >&2
    printf '%s\n' "$raw_output" | tail -5 >&2
    exit 1
fi

# Structural floor: the snapshot must actually look like a vendor run. A lock
# error, a usage message, or a truncated run must never be recorded as parity.
if ! printf '%s\n' "$raw_output" | grep -q "Summary"; then
    echo "ERROR: vendor output has no Summary section — refusing to record it as a parity snapshot." >&2
    printf '%s\n' "$raw_output" | tail -5 >&2
    exit 1
fi

source "$REPO_ROOT/scripts/lib/vendor-manifest.sh"
expected_vendors=$(vendor_manifest_keys | wc -l | tr -d ' ')
seen_vendors=$(printf '%s\n' "$raw_output" | grep -cE '^  \[[0-9]+\] ' || true)
if [ "$seen_vendors" -ne "$expected_vendors" ]; then
    echo "ERROR: vendor output covered $seen_vendors of $expected_vendors manifest vendors." >&2
    echo "       A partial run is not a parity snapshot." >&2
    exit 1
fi

normalized=$(printf '%s\n' "$raw_output" \
    | sed -E 's/[0-9]+ commits ahead/<N> commits ahead/g' \
    | sed -E 's/[[:space:]]+$//' \
)

emit_snapshot() {
    printf '%s\n' "$normalized"
}

case "$MODE" in
    text)
        emit_snapshot
        ;;
    hash)
        emit_snapshot | shasum -a 256 | awk '{print $1}'
        ;;
    baseline)
        # `text` and `hash` above are DATA producers -- their stdout is piped
        # straight into `shasum` and diffed. A RECEIPT line there would corrupt
        # the hash, so only the two gate modes emit one.
        gate_begin 40-vendor-parity-snapshot
        emit_snapshot > "$ARG_PATH"
        SNAPSHOT_LINES=$(grep -c . "$ARG_PATH" 2>/dev/null || true)
        [ -n "$SNAPSHOT_LINES" ] || SNAPSHOT_LINES=0
        if [ "$SNAPSHOT_LINES" -eq 0 ]; then
            echo "ERROR: refusing to write an empty parity baseline to $ARG_PATH" >&2
            gate_unit_skipped snapshot "snapshot rendered zero lines"
            gate_unit_skipped baseline-compare "not reached: empty snapshot"
            gate_end 1
        fi
        echo "[OK] Wrote vendor parity baseline: $ARG_PATH"
        gate_unit_ran snapshot "lines=$SNAPSHOT_LINES"
        gate_unit_skipped baseline-compare "baseline mode writes, it does not compare"
        gate_end 0
        ;;
    verify)
        gate_begin 40-vendor-parity-snapshot
        if [ ! -f "$ARG_PATH" ]; then
            echo "ERROR: baseline file not found: $ARG_PATH" >&2
            gate_unit_skipped snapshot "baseline file not found"
            gate_unit_skipped baseline-compare "baseline file not found"
            gate_end 1
        fi
        actual=$(mktemp)
        emit_snapshot > "$actual"
        SNAPSHOT_LINES=$(grep -c . "$actual" 2>/dev/null || true)
        [ -n "$SNAPSHOT_LINES" ] || SNAPSHOT_LINES=0
        # An empty snapshot compared against an empty baseline would `diff` clean
        # and report parity over nothing at all.
        if [ "$SNAPSHOT_LINES" -eq 0 ]; then
            echo "[DRIFT] Vendor parity snapshot rendered zero lines -- nothing was compared." >&2
            rm -f "$actual"
            gate_unit_skipped snapshot "snapshot rendered zero lines"
            gate_unit_skipped baseline-compare "not reached: empty snapshot"
            gate_end 1
        fi
        gate_unit_ran snapshot "lines=$SNAPSHOT_LINES"
        if diff -u "$ARG_PATH" "$actual" >/dev/null 2>&1; then
            echo "[OK] Vendor parity snapshot matches baseline: $ARG_PATH"
            rm -f "$actual"
            gate_unit_ran baseline-compare "compared_lines=$SNAPSHOT_LINES drift=0"
            gate_end 0
        fi
        echo "[DRIFT] Vendor parity snapshot differs from baseline:" >&2
        diff -u "$ARG_PATH" "$actual" >&2 || true
        rm -f "$actual"
        gate_unit_ran baseline-compare "compared_lines=$SNAPSHOT_LINES drift=1"
        gate_end 1
        ;;
esac
