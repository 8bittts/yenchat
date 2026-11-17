#!/bin/bash
# Vendor delta Binary (Universal)
#
# delta does not publish x86_64 macOS binaries (dropped in v0.19.0, PR #2074).
# This script compiles delta from source for arm64 and x86_64, then combines
# them with lipo. Same pattern as 34-vendor-btop.sh and 16-vendor-fd.sh — all
# three share the vendor_source_build() scaffolding in lib/vendor-binary.sh and
# supply only a tiny build callback.
#
# Stores at yen-terminal/customizations/vendor/delta/
#
# Usage: ./scripts/35-vendor-delta.sh
#        ./scripts/35-vendor-delta.sh --force
#        VENDOR_LATEST_TAG=vX.Y.Z ./scripts/35-vendor-delta.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/35-vendor-delta.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

require_tool "cargo"
require_tool "rustup"
require_tool "curl"
require_tool "tar"
require_tool "lipo"
require_tool "file"
require_tool "python3"

# Ensure x86_64 target is available (idempotent)
rustup target add x86_64-apple-darwin 2>/dev/null || true
if ! rustup target list --installed | grep -q "x86_64-apple-darwin"; then
    echo "ERROR: x86_64-apple-darwin Rust target not available after rustup target add"
    echo "Run: rustup target add x86_64-apple-darwin"
    exit 1
fi

# Build callback: compile arm64 + x86_64 in parallel, print the two binary paths
# to STDOUT (arm64 first, x86_64 second), all progress to STDERR. See the
# BUILD_FN contract in lib/vendor-binary.sh.
build_delta() {
    local source_dir="$1"

    echo "  Building arm64 and x86_64 (parallel)..." >&2
    # Background BARE cargo (not `cargo | tail`) so `wait` returns cargo's real exit
    # status. Piping into tail made `wait` see tail's status (always 0), masking
    # build failures and risking a stale prior binary passing the -f checks upstream.
    local ARM64_BUILD_LOG X86_BUILD_LOG
    ARM64_BUILD_LOG=$(mktemp)
    X86_BUILD_LOG=$(mktemp)
    cargo build --manifest-path "$source_dir/Cargo.toml" --release --target aarch64-apple-darwin > "$ARM64_BUILD_LOG" 2>&1 &
    local PID_ARM64=$!
    cargo build --manifest-path "$source_dir/Cargo.toml" --release --target x86_64-apple-darwin > "$X86_BUILD_LOG" 2>&1 &
    local PID_X86=$!

    local FAIL=0
    wait $PID_ARM64 || { FAIL=1; echo "  arm64 build failed (tail of log):" >&2; tail -5 "$ARM64_BUILD_LOG" >&2; }
    wait $PID_X86 || { FAIL=1; echo "  x86_64 build failed (tail of log):" >&2; tail -5 "$X86_BUILD_LOG" >&2; }
    rm -f "$ARM64_BUILD_LOG" "$X86_BUILD_LOG"

    if [ "$FAIL" -ne 0 ]; then
        echo "ERROR: One or both architecture builds failed" >&2
        return 1
    fi

    echo "$source_dir/target/aarch64-apple-darwin/release/delta"
    echo "$source_dir/target/x86_64-apple-darwin/release/delta"
}

vendor_source_build "delta" "dandavison/delta" "delta" ".delta-baseline" "delta" build_delta "$FORCE" "source (cargo cross-compile)"
