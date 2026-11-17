#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.


BUILD_CLEANUP_HELPER="$REPO_ROOT/scripts/lib/build-cleanup.sh"
if [ ! -f "$BUILD_CLEANUP_HELPER" ] || [ ! -r "$BUILD_CLEANUP_HELPER" ]; then
    echo "ERROR: Build cleanup helper missing or unreadable: $BUILD_CLEANUP_HELPER" >&2
    exit 1
fi
source "$BUILD_CLEANUP_HELPER"

if [ "$LOCAL_BUILD" = true ]; then
    echo "[3/9] Skipping clean (local mode — incremental build)..."
    # Keep build caches for speed, but always rebuild app bundle payload fresh so
    # stale _CodeSignature metadata and removed resource paths cannot linger.
    remove_dir_robust ghostty/zig-out/YEN.app
else
    echo "[3/9] Cleaning artifacts..."

    rm -rf ghostty/zig-cache ghostty/.zig-cache ghostty/.zig-global-cache ghostty/.yen-zig-global-cache ghostty/macos/build
    remove_dir_robust ghostty/zig-out
    rm -rf ghostty/macos/*.xcframework
    rm -rf "$ZIG_GLOBAL_CACHE_DIR"
    remove_project_derived_data "$PWD/ghostty/macos/YEN.xcodeproj" "$HOME/Library/Developer/Xcode/DerivedData"
    # Verify xcframework actually removed (stale xcframeworks cause exit code 70 on rebuild)
    if ls ghostty/macos/*.xcframework 1>/dev/null 2>&1; then
        echo "  ERROR: Failed to remove stale xcframework — delete manually and retry"
        exit 1
    fi
    echo "  Cleaned caches"
fi

echo ""
echo "[4/9] Verifying prerequisites..."

VERSION_JSON="$REPO_ROOT/public/stable/version.json"
VERSION_SEMVER=""
if [ -f "$VERSION_JSON" ]; then
    VERSION=$(get_version "$VERSION_JSON")

    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        echo "  ERROR: Could not extract version from version.json"
        exit 1
    elif ! is_valid_release_version "$VERSION"; then
        echo "  ERROR: Invalid version format: $VERSION (expected X.XXX)"
        exit 1
    else
        if [ -f "$REPO_ROOT/package.json" ]; then
            PACKAGE_VERSION=$(python3 "$REPO_ROOT/scripts/lib/json-utils.py" get "$REPO_ROOT/package.json" version)
            if [ "$PACKAGE_VERSION" != "$VERSION" ]; then
                echo "  package.json version mismatch ($PACKAGE_VERSION vs $VERSION) — auto-syncing..."
                SYNC_SCRIPT="$REPO_ROOT/scripts/02-sync-versions.sh"
                if [ -x "$SYNC_SCRIPT" ]; then
                    bash "$SYNC_SCRIPT"
                    echo "  Versions synced to $VERSION"
                else
                    echo "  ERROR: sync script not found at $SYNC_SCRIPT"
                    exit 1
                fi
            else
                echo "  package.json matches version.json ($VERSION)"
            fi
        else
            echo "  ERROR: package.json not found"
            exit 1
        fi
    fi
else
    echo "  ERROR: version.json not found"
    exit 1
fi

VERSION_SEMVER=$(get_version_semver "$VERSION" 2>/dev/null || echo "")
if ! echo "$VERSION_SEMVER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "  ERROR: Invalid semantic version override: $VERSION_SEMVER"
    exit 1
fi

if [ ! -d "ghostty" ]; then
    echo "  ERROR: ghostty/ directory not found"
    echo "  Run: $REPO_ROOT/scripts/10-update-ghostty.sh main"
    echo "  (or fetch a specific commit: $(upstream_tarball_url '<commit>'))"
    exit 1
fi

if [ ! -f "ghostty/build.zig" ]; then
    echo "  ERROR: ghostty/build.zig not found - directory may be incomplete"
    exit 1
fi

echo ""
