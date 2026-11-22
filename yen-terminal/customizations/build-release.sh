#!/bin/bash
# YEN Build Release
#
# Complete workflow: validate → apply overlays → build → verify → package
#
# Local testing: open ghostty/zig-out/YEN.app (no need to install to /Applications)
#   CRITICAL: Always use ghostty/zig-out/YEN.app for local testing, not /Applications/YEN.app
#   If versions conflict, run: ./customizations/clear-app-cache.sh
# Production: git push → Sparkle notifies users → Check for Updates
#
# Build structure (mirrored Ghostty):
#   ghostty/     - Exact upstream Ghostty mirror
#   overlays/    - YEN customizations (build.zig, main.zig, etc.)
#   apply-overlays.sh - Applies branding + copies overlays
#
# With YENCustomResources integration, the Zig build now handles:
# - Icon replacement (615KB pre-compiled)
# - CLI bundling (bin/yen standalone CLI)
# - Commands and lib bundling
# - Version info patching
# - Theme renaming
# - Code signing
#
# finalize-build.sh verifies, creates the release package (DMG + checksum + appcast),
# and uploads the DMG artifacts to the version's GitHub Release.
#
# Usage: ./customizations/build-release.sh [--build-only] [--local] [--skip-vendor]

set -e
set -o pipefail

BUILD_ONLY=false
LOCAL_BUILD=false
SKIP_VENDOR=false

for arg in "$@"; do
    case "$arg" in
        --local)
            LOCAL_BUILD=true
            BUILD_ONLY=true  # local builds never ship
            ;;
        --build-only|--no-package)
            BUILD_ONLY=true
            ;;
        --skip-vendor)
            SKIP_VENDOR=true
            ;;
        --help|-h)
            echo "Usage: ./customizations/build-release.sh [--build-only] [--local] [--skip-vendor]"
            echo ""
            echo "Options:"
            echo "  --build-only, --no-package   Build only (skip packaging/Developer ID signing/notarization/upload)"
            echo "  --local                      Incremental local build (skip cache wipes + packaging)"
            echo "  --skip-vendor                Skip vendor gate (use when caller already validated)"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Run ./customizations/build-release.sh --help for usage"
            exit 1
            ;;
    esac
done

# Change to yen-terminal root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Calculate REPO_ROOT early for consistent path handling
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/workflow-lock.sh"
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"
source "$REPO_ROOT/scripts/lib/zip-notify.sh"
source "$REPO_ROOT/scripts/lib/zig-sdk-workaround.sh"
init_shared_workflow_lock "$REPO_ROOT"

# Keep Zig's global cache project-scoped to avoid cross-process cache conflicts.
if [ -z "$ZIG_GLOBAL_CACHE_DIR" ]; then
    ZIG_GLOBAL_CACHE_DIR="$PWD/ghostty/.yen-zig-global-cache"
fi
export ZIG_GLOBAL_CACHE_DIR

LOCK_KEY=$(printf '%s\n' "$REPO_ROOT" | cksum | awk '{print $1}')
BUILD_LOCK_DIR="${TMPDIR:-/tmp}/yen-build-release-${LOCK_KEY}.lock"
BUILD_LOCK_ACQUIRED=false
ZIG_BUILD_LOG_PATH=""
CONCURRENCY_GATE_MODE="${YEN_CONCURRENCY_GATE_MODE:-report}"
APP_INTENTS_GATE_MODE="${YEN_APP_INTENTS_GATE_MODE:-report}"
NON_CONCURRENCY_WARNING_ALLOWLIST_FILE="${YEN_NON_CONCURRENCY_WARNING_ALLOWLIST_FILE:-$REPO_ROOT/scripts/lib/non-concurrency-warning-allowlist.txt}"
PREBUILD_COMPONENT_GATE_MODE="${YEN_PREBUILD_COMPONENT_GATE_MODE:-enforce}"

release_build_lock() {
    # Clean up zig build log temp file on exit
    if [ -n "$ZIG_BUILD_LOG_PATH" ] && [ -f "$ZIG_BUILD_LOG_PATH" ]; then
        rm -f "$ZIG_BUILD_LOG_PATH"
    fi
    # Clean up synthetic sysroot and xcrun wrapper dirs created during x86_64 cross-compile
    local tmpbase="${TMPDIR:-/tmp}"
    if [ -d "$tmpbase/yen-zig-sysroot" ]; then
        rm -rf "$tmpbase/yen-zig-sysroot"
    fi
    if [ -d "$tmpbase/yen-zig-xcrun-wrapper" ]; then
        rm -rf "$tmpbase/yen-zig-xcrun-wrapper"
    fi
    release_shared_workflow_lock
    if [ "$BUILD_LOCK_ACQUIRED" = true ] && [ -d "$BUILD_LOCK_DIR" ]; then
        rm -rf "$BUILD_LOCK_DIR"
    fi
}

acquire_build_lock() {
    acquire_yen_process_lock \
        "$BUILD_LOCK_DIR" \
        BUILD_LOCK_ACQUIRED \
        "build-release.sh" \
        "ERROR: Another build-release.sh process is running (pid {pid})
Wait for it to finish before starting a new build." \
        "ERROR: Build lock exists without a PID file: $BUILD_LOCK_DIR
If no build is running, remove the stale lock and retry." \
        "ERROR: Could not acquire build lock: $BUILD_LOCK_DIR" || exit 1
}

# Phase timing receipt. Each phase is sourced and may exit, so the EXIT trap
# closes the phase that was running and prints one line for the whole run:
#   TIMING|build-release|01-preflight=4s 02-prepare=2s ... total=612s
# Without it a release log holds no durations, and a slow step cannot be told
# from a fast one after the run.
PHASE_TIMING_RECEIPT=""
PHASE_TIMING_CURRENT=""
PHASE_TIMING_STARTED=0
PHASE_TIMING_RUN_STARTED=$(date +%s)
phase_timing_open() {
    phase_timing_close
    PHASE_TIMING_CURRENT="$1"
    PHASE_TIMING_STARTED=$(date +%s)
}
phase_timing_close() {
    [ -n "$PHASE_TIMING_CURRENT" ] || return 0
    PHASE_TIMING_RECEIPT="${PHASE_TIMING_RECEIPT}${PHASE_TIMING_CURRENT}=$(( $(date +%s) - PHASE_TIMING_STARTED ))s "
    PHASE_TIMING_CURRENT=""
}
phase_timing_print() {
    phase_timing_close
    [ -n "$PHASE_TIMING_RECEIPT" ] || return 0
    echo "TIMING|build-release|${PHASE_TIMING_RECEIPT}total=$(( $(date +%s) - PHASE_TIMING_RUN_STARTED ))s"
}

# Preserve failures and give interrupted builds a nonzero exit after cleanup.
trap 'build_exit_code=$?; phase_timing_print; release_build_lock; exit "$build_exit_code"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_shared_workflow_lock "build-release" || exit 1
acquire_build_lock

echo "YEN Build"

# Keep release phases in one shell so locks and cleanup traps remain active.
BUILD_RELEASE_PHASES=(
    "01-preflight.sh"
    "02-prepare.sh"
    "03-overlays.sh"
    "04-build.sh"
    "05-verify.sh"
    "06-package.sh"
)
for phase in "${BUILD_RELEASE_PHASES[@]}"; do
    phase_path="$REPO_ROOT/scripts/lib/build-release-phases/$phase"
    if [ ! -f "$phase_path" ] || [ ! -r "$phase_path" ]; then
        echo "ERROR: Build phase missing or unreadable: $phase_path" >&2
        exit 1
    fi
    phase_timing_open "${phase%.sh}"
    source "$phase_path"
done
