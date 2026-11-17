#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.

echo "[8/9] Verifying built app + branding..."

# Verify YEN.app was created (basic check — finalize-build.sh does thorough verification)
BUILT_APP="ghostty/zig-out/YEN.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "  ERROR: YEN.app not found after build — zig build may have silently failed"
    exit 1
fi

# Enforce built app vendor inventory/signing expectations (post-build artifact gate).
if [ -f "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" ]; then
    bash "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" --app "$BUILT_APP" || {
        echo "  ERROR: Built app vendor audit check failed"
        echo "  Re-run: ./scripts/14-vendor.sh and rebuild YEN"
        exit 1
    }
else
    echo "  ERROR: scripts/12-verify-vendor-audit.sh not found"
    exit 1
fi

# Verify SUPublicEDKey preserved after build (zig packaging can corrupt the plist)
BUILT_PLIST="$BUILT_APP/Contents/Info.plist"
if [ -f "$BUILT_PLIST" ] && [ -n "$EXPECTED_SUPUBLIC_EDKEY" ]; then
    if ! assert_su_public_ed_key "$BUILT_PLIST" "$EXPECTED_SUPUBLIC_EDKEY" "built app"; then
        exit 1
    fi
fi

if [ -f "$REPO_ROOT/scripts/04-verify-branding.sh" ]; then
    bash "$REPO_ROOT/scripts/04-verify-branding.sh" || {
        echo "ERROR: Branding verification failed"
        exit 1
    }
else
    echo "ERROR: scripts/04-verify-branding.sh not found"
    exit 1
fi

zip_notify "App verified" "v$VERSION compiled; vendor audit + branding checks passed"

echo ""
