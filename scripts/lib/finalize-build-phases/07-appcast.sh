#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# APPCAST
# ============================================================================

echo "  Generating appcast..."
if [ -f "$SCRIPT_DIR/generate-appcast.sh" ]; then
    if APPCAST_OUTPUT=$("$SCRIPT_DIR/generate-appcast.sh" 2>&1); then
        :
    else
        APPCAST_STATUS=$?
        echo "  ERROR: Appcast generation failed (exit code $APPCAST_STATUS)"
        echo "$APPCAST_OUTPUT"
        exit 1
    fi
    echo "    Appcast generated"
else
    echo "  ERROR: generate-appcast.sh not found"
    exit 1
fi
echo ""

# ============================================================================
# UPLOAD DELTA UPDATES (best-effort; non-fatal — a delta 404 just makes that
# one upgrade path fall back to the full DMG, never a broken update)
# ============================================================================

echo "  Uploading delta updates (if any)..."

# Each release's deltas are assets of that release only, so a new release never
# inherits a stale delta from an earlier one.
DELTA_FILES=("$RELEASE_DIR"/*.delta)
if [ -e "${DELTA_FILES[0]:-}" ]; then
    for DELTA_FILE in "${DELTA_FILES[@]}"; do
        DELTA_NAME="$(basename "$DELTA_FILE")"
        if upload_github_release_asset_retry \
            "delta ($DELTA_NAME)" \
            "$DELTA_FILE" \
            "$RELEASE_TAG"; then
            echo "    Uploaded: $DELTA_NAME"
        else
            echo "    WARNING: delta upload failed (non-fatal, falls back to full DMG): $DELTA_NAME"
        fi
    done
else
    echo "    No delta files produced this run (full-DMG-only update)"
fi
echo ""
