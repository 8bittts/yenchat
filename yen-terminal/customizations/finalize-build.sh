#!/bin/bash
# Finalize YEN.app Build
#
# Creates release packages after `zig build` completes:
# 1. Signs the app with Developer ID
# 2. Notarizes with Apple
# 3. Creates DMG (primary distribution)
# 4. Generates checksum, uploads DMG to the version's GitHub Release
# 5. Generates appcast (Sparkle update feed) and uploads its deltas
#
# Output (local):
#   - yen-0XX.dmg (signed DMG containing signed/notarized app)
#   - yen-0XX.dmg.sha256
#   - appcast.xml (points to the GitHub Release DMG URL)
# Output (GitHub Release v<version> on 8bittts/yenchat):
#   - yen-0XX.dmg
#   - yen-0XX.dmg.sha256
#   - YENXXXX-YYYY.delta
#
# Usage: ./customizations/finalize-build.sh

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Verify REPO_ROOT points to yenchat/ root (guards against CWD drift after zig build)
if [ ! -f "$REPO_ROOT/package.json" ] || [ ! -d "$REPO_ROOT/yen-terminal" ]; then
    echo "ERROR: REPO_ROOT mismatch (expected yenchat/, got $REPO_ROOT)"
    echo "Check that build-release.sh returns to yen-terminal/ after 'cd ghostty'"
    exit 1
fi
source "$REPO_ROOT/scripts/lib/workflow-lock.sh"
source "$REPO_ROOT/scripts/lib/zip-notify.sh"
init_shared_workflow_lock "$REPO_ROOT"

LOCK_KEY=$(printf '%s\n' "$REPO_ROOT" | cksum | awk '{print $1}')
FINALIZE_LOCK_DIR="${TMPDIR:-/tmp}/yen-finalize-build-${LOCK_KEY}.lock"
FINALIZE_LOCK_ACQUIRED=false

release_finalize_lock() {
    release_shared_workflow_lock
    if [ "$FINALIZE_LOCK_ACQUIRED" = true ] && [ -d "$FINALIZE_LOCK_DIR" ]; then
        rm -rf "$FINALIZE_LOCK_DIR"
    fi
}

acquire_finalize_lock() {
    acquire_yen_process_lock \
        "$FINALIZE_LOCK_DIR" \
        FINALIZE_LOCK_ACQUIRED \
        "finalize-build.sh" \
        "ERROR: Another finalize-build.sh process is running (pid {pid})
Wait for it to finish before starting a new packaging run." \
        "ERROR: Finalize lock exists without a PID file: $FINALIZE_LOCK_DIR
If no packaging process is running, remove the stale lock and retry." \
        "ERROR: Could not acquire finalize lock: $FINALIZE_LOCK_DIR" || exit 1
}

trap 'FINALIZE_EXIT_CODE=$?; release_finalize_lock; exit "$FINALIZE_EXIT_CODE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_shared_workflow_lock "finalize-build" || exit 1
acquire_finalize_lock

require_finalize_source() {
    if [ ! -f "$1" ] || [ ! -r "$1" ]; then
        echo "ERROR: Finalize source missing or unreadable: $1" >&2
        exit 1
    fi
}

FINALIZE_BUILD_PHASES=(
    "01-preflight.sh"
    "02-services.sh"
    "03-sign.sh"
    "04-dmg.sh"
    "05-metadata.sh"
    "06-upload.sh"
    "07-appcast.sh"
)
for phase in "${FINALIZE_BUILD_PHASES[@]}"; do
    phase_path="$REPO_ROOT/scripts/lib/finalize-build-phases/$phase"
    require_finalize_source "$phase_path"
    source "$phase_path"
done

# ============================================================================
# DONE
# ============================================================================

DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
zip_notify "Release complete" "v$VERSION $DMG_FILENAME ($DMG_SIZE) uploaded; appcast published"
echo ""
echo "  Release packaged: v$VERSION ($DMG_FILENAME, $DMG_SIZE)"
