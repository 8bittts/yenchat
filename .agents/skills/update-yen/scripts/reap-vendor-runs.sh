#!/bin/bash
# reap-vendor-runs.sh — /update-yen Step 0f (PF-06)
# Deletes leftover vendor scratch runs under tmp/vendor-runs/. Each run holds a full
# Ghostty mirror plus baselines, and nothing else ever removed one: two October runs
# were found by hand still holding 8.3 GB. A run directory is reaped only when no
# vendor or shared workflow lock is live and nothing inside it changed within
# YEN_VENDOR_RUN_REAP_MIN_AGE_MINUTES (default 1440, one day).
# Usage: reap-vendor-runs.sh
# Exit 0 after reaping or holding; exit 1 when a safety check refuses or a delete fails.
# Bash 3.2 compatible.

set -euo pipefail

# Resolve this script's own directory PHYSICALLY before walking up; the skill
# dirs are symlinked into ~/.claude and ~/.codex (see verify-agent-work.sh).
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)"
RUNS_REL="tmp/vendor-runs"
RUNS="$REPO_ROOT/$RUNS_REL"
MIN_AGE="${YEN_VENDOR_RUN_REAP_MIN_AGE_MINUTES:-1440}"
LOCK_KEY="$(printf '%s\n' "$REPO_ROOT" | cksum | awk '{print $1}')"

case "$MIN_AGE" in
    '' | *[!0-9]*)
        echo "[FAIL] YEN_VENDOR_RUN_REAP_MIN_AGE_MINUTES must be whole minutes, got '$MIN_AGE'"
        exit 1
        ;;
esac

if [ ! -e "$RUNS" ] && [ ! -L "$RUNS" ]; then
    echo "RECEIPT reaper=vendor-runs reaped=0 held=0 freed_kb=0 result=PASS (no $RUNS_REL)"
    exit 0
fi
if [ -L "$RUNS" ] || [ ! -d "$RUNS" ]; then
    echo "[FAIL] $RUNS_REL is not a plain directory; refusing to follow it"
    exit 1
fi
# Only ignored scratch is ever deleted. A folder git does not ignore, or one that
# holds a tracked file, is not scratch.
if ! git -C "$REPO_ROOT" check-ignore -q "$RUNS_REL/"; then
    echo "[FAIL] $RUNS_REL is not gitignored; refusing to delete it"
    exit 1
fi
if [ -n "$(git -C "$REPO_ROOT" ls-files -- "$RUNS_REL" | head -n 1)" ]; then
    echo "[FAIL] $RUNS_REL holds tracked files; refusing to delete it"
    exit 1
fi

# A live vendor run may be writing into any of these directories. A lock with no
# pid file is mid-acquire or unreadable, so it counts as live too.
for lock_name in yen-vendor yen-ghostty-vendor yen-workflow; do
    lock_dir="${TMPDIR:-/tmp}/${lock_name}-${LOCK_KEY}.lock"
    [ -d "$lock_dir" ] || continue
    pid=""
    if [ -f "$lock_dir/pid" ]; then
        pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    fi
    if [ -z "$pid" ] || kill -0 "$pid" 2>/dev/null; then
        echo "[held] every vendor run: the $lock_name lock is live (pid ${pid:-unknown})"
        echo "RECEIPT reaper=vendor-runs reaped=0 held=all freed_kb=0 result=PASS"
        exit 0
    fi
done

reaped=0
held=0
freed_kb=0
for dir in "$RUNS"/*; do
    # An empty folder leaves the glob literal.
    [ -e "$dir" ] || [ -L "$dir" ] || continue
    name="$(basename "$dir")"
    if [ -L "$dir" ] || [ ! -d "$dir" ]; then
        echo "[held] $name: not a plain directory"
        held=$((held + 1))
        continue
    fi
    if [ "$MIN_AGE" -gt 0 ] && [ -n "$(find "$dir" -mmin "-$MIN_AGE" -print -quit 2>/dev/null)" ]; then
        echo "[held] $name: changed within the last $MIN_AGE minutes"
        held=$((held + 1))
        continue
    fi
    kb="$(du -sk "$dir" | awk '{print $1}')"
    # Zig package caches mark directories read-only, which stops a plain rm -rf.
    if ! chmod -R u+w "$dir" || ! rm -rf -- "$dir" || [ -e "$dir" ]; then
        echo "[FAIL] $name: the delete did not finish"
        exit 1
    fi
    echo "[reaped] $name (${kb} KB)"
    reaped=$((reaped + 1))
    freed_kb=$((freed_kb + kb))
done

echo "RECEIPT reaper=vendor-runs reaped=$reaped held=$held freed_kb=$freed_kb result=PASS"
