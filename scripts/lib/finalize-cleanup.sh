#!/bin/bash
# Install staging cleanup after the finalizer has created its private temp paths.

cleanup() {
    rm -rf "$STAGING_DIR"
    rm -f "$DMG_TEMP"
    rm -rf "$(dirname "$DMG_TEMP")"
    # Chain the finalize lock release so it is never dropped.
    release_finalize_lock
}
trap 'FINALIZE_EXIT_CODE=$?; cleanup; exit "$FINALIZE_EXIT_CODE"' EXIT
