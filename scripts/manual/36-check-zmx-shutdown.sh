#!/bin/bash
# Check that zmx session daemons exit cleanly when their session ends.
#
# Usage: scripts/manual/36-check-zmx-shutdown.sh [--runs N] [--binary <zmx>]
#
# zmx v1.0.1 freed the caller-owned socket path with its post-fork C allocator
# at daemon shutdown, so every ended session aborted with SIGABRT and left a
# zmx-*.ips crash report (fixed upstream in f5d604e, carried by
# scripts/48-vendor-zmx.sh). This ends N session daemons (default 20) through
# `zmx kill` and through a command that exits, keeps one counter session up
# throughout, and reports each daemon's exit status plus the crash reports
# naming its pid. The binary runs as a uniquely named copy, so its reports are
# told apart from any other zmx on this Mac. Exits 0 only when every daemon
# ended with status 0 and the counter session survived with the same shell.
set -u
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
zmx="$repo/yen-terminal/customizations/vendor/zmx/zmx"
runs=20
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs) runs="${2:?--runs needs a number}"; shift 2 ;;
        --binary) zmx="${2:?--binary needs a path}"; shift 2 ;;
        *) echo "usage: $0 [--runs N] [--binary <zmx>]" >&2; exit 2 ;;
    esac
done
[[ -x "$zmx" ]] || { echo "FAIL: zmx missing at $zmx" >&2; exit 1; }
for name in $(env | sed -n 's/^\(ZMX_[A-Za-z_]*\)=.*/\1/p'); do unset "$name"; done

# Short: a Unix socket path caps at 103 bytes.
base="$(mktemp -d /tmp/yzs.XXXXXXXX)"
copy="$base/zmxshut$$"
cleanup() {
    local s
    for s in $(ZMX_DIR="$base/s" "$copy" ls --short 2> /dev/null); do
        ZMX_DIR="$base/s" "$copy" kill "$s" > /dev/null 2>&1
    done
    rm -r -f "$base"
}
trap cleanup EXIT
cp "$zmx" "$copy"
echo "binary: $zmx (sha256 $(shasum -a 256 "$zmx" | cut -d' ' -f1)), runs as $(basename "$copy")"
python3 -I "$repo/scripts/manual/36-zmx-shutdown-probe.py" "$copy" "$base/s" "$runs" --reports
