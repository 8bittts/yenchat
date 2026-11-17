#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.

echo "[9/9] Creating release package..."

if [ "$BUILD_ONLY" = true ]; then
    if command -v codesign >/dev/null 2>&1; then
        echo "  Refreshing build-only ad-hoc signature metadata..."
        if ! codesign --force --deep --sign - "$BUILT_APP" >/dev/null 2>&1; then
            echo "  WARNING: Failed to refresh build-only ad-hoc signature metadata"
        fi
    fi
    if [ "$LOCAL_BUILD" = true ]; then
        echo "  Local mode — skipping release packaging (incremental build, not for distribution)"
        echo ""
        echo "BUILD COMPLETE (local)"
    else
        echo "  Build-only mode — skipping release packaging/Developer ID signing/notarization/upload"
        echo ""
        echo "BUILD COMPLETE (build-only)"
    fi
    echo "Test locally: open ghostty/zig-out/YEN.app"
    exit 0
fi

bash customizations/finalize-build.sh || {
    zip_notify "Release FAILED" "v$VERSION packaging/notarization/upload failed"
    echo "ERROR: Release package creation failed"
    exit 1
}

echo ""
echo "BUILD COMPLETE: v$VERSION"
echo "Test locally: open ghostty/zig-out/YEN.app"
