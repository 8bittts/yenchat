#!/bin/bash
# Version Synchronization Script
#
# Automatically syncs version from public/stable/version.json (canonical source)
# to all other version locations in the codebase.
#
# Usage: ./scripts/02-sync-versions.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
VERSION_JSON="$REPO_ROOT/public/stable/version.json"

# Source shared utilities
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/python-utils.sh"

require_python3 "for JSON version syncing" || exit 1

# Check if version.json exists
if [ ! -f "$VERSION_JSON" ]; then
    echo "ERROR: version.json not found"
    exit 1
fi

# Extract version using shared utilities
gate_begin 02-sync-versions

VERSION=$(get_version "$VERSION_JSON")

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "ERROR: Could not extract version"
    gate_unit_skipped version-validation "precondition failed"
    gate_unit_skipped file-sync "not reached"
    gate_end 1
fi

# Validate version format before syncing it into bundle metadata.
if ! is_valid_release_version "$VERSION"; then
    echo "ERROR: Invalid version format: $VERSION (expected X.XXX)"
    gate_unit_skipped version-validation "precondition failed"
    gate_unit_skipped file-sync "not reached"
    gate_end 1
fi

# Calculate derived versions using shared utilities
VERSION_INT=$(get_version_int "$VERSION")

echo ""
echo "Version Sync: $VERSION"

UPDATED=()
SKIPPED=()

# 1. Update package.json
if [ -f "$REPO_ROOT/package.json" ]; then
    OLD_VER=$(get_version "$REPO_ROOT/package.json" 2>/dev/null || echo "")
    python3 "$REPO_ROOT/scripts/lib/json-utils.py" set "$REPO_ROOT/package.json" version "$VERSION" || {
        echo "ERROR: Failed to update package.json"
        gate_unit_skipped version-validation "precondition failed"
        gate_unit_skipped file-sync "not reached"
        gate_end 1
    }
    if [ "$OLD_VER" != "$VERSION" ]; then
        UPDATED+=("package.json: $OLD_VER → $VERSION")
    fi
fi

# Note: CLI version is now dynamic (reads from bundled version.json at runtime)
# No need to update yen-cli/lib/common.sh or yen-cli/bin/yen

# 2. Update Xcode project
XCODE_PROJECT="$REPO_ROOT/yen-terminal/ghostty/macos/YEN.xcodeproj/project.pbxproj"
if [ -f "$XCODE_PROJECT" ]; then
    sed -i '' "s/MARKETING_VERSION = [0-9][0-9]*\.[0-9][0-9]*/MARKETING_VERSION = $VERSION/g" "$XCODE_PROJECT"
    sed -i '' "s/INFOPLIST_KEY_CFBundleShortVersionString = \"[0-9][0-9]*\.[0-9][0-9]*\"/INFOPLIST_KEY_CFBundleShortVersionString = \"$VERSION\"/g" "$XCODE_PROJECT"
    sed -i '' "s/INFOPLIST_KEY_CFBundleVersion = [0-9][0-9]*;/INFOPLIST_KEY_CFBundleVersion = $VERSION_INT;/g" "$XCODE_PROJECT"
    # Update CURRENT_PROJECT_VERSION (integer build number)
    sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*/CURRENT_PROJECT_VERSION = $VERSION_INT/g" "$XCODE_PROJECT"
    # Verify MARKETING_VERSION updated (always present in pbxproj)
    if ! grep -q "MARKETING_VERSION = $VERSION" "$XCODE_PROJECT"; then
        echo "ERROR: Failed to update MARKETING_VERSION in pbxproj"
        gate_unit_skipped version-validation "precondition failed"
        gate_unit_skipped file-sync "not reached"
        gate_end 1
    fi
    # Verify optional keys if they exist in this project
    if grep -q "INFOPLIST_KEY_CFBundleShortVersionString" "$XCODE_PROJECT" && \
       ! grep -q "INFOPLIST_KEY_CFBundleShortVersionString = \"$VERSION\"" "$XCODE_PROJECT"; then
        echo "ERROR: Failed to update CFBundleShortVersionString in pbxproj"
        gate_unit_skipped version-validation "precondition failed"
        gate_unit_skipped file-sync "not reached"
        gate_end 1
    fi
    if grep -q "INFOPLIST_KEY_CFBundleVersion" "$XCODE_PROJECT" && \
       ! grep -q "INFOPLIST_KEY_CFBundleVersion = $VERSION_INT;" "$XCODE_PROJECT"; then
        echo "ERROR: Failed to update CFBundleVersion in pbxproj"
        gate_unit_skipped version-validation "precondition failed"
        gate_unit_skipped file-sync "not reached"
        gate_end 1
    fi
    UPDATED+=("Xcode project")
else
    SKIPPED+=("Xcode project (not found)")
fi

# 3. Update YEN-Info.plist
INFO_PLIST="$REPO_ROOT/yen-terminal/ghostty/macos/YEN-Info.plist"
if [ -f "$INFO_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST" 2>/dev/null || \
        sed -i '' '/<key>CFBundleShortVersionString<\/key>/{n;s#<string>[^<]*</string>#<string>'"$VERSION"'</string>#;}' "$INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION_INT" "$INFO_PLIST" 2>/dev/null || \
        sed -i '' '/<key>CFBundleVersion<\/key>/{n;s/<string>[0-9][0-9]*<\/string>/<string>'"$VERSION_INT"'<\/string>/;}' "$INFO_PLIST"
    UPDATED+=("Info.plist")
else
    SKIPPED+=("Info.plist (not found)")
fi

# Note: Download links in home-client.tsx are now dynamic (computed from version prop)
# No longer need to update them here

gate_unit_ran version-validation "version=$VERSION"
if [ ${#UPDATED[@]} -gt 0 ]; then
    gate_unit_ran file-sync "updated=${#UPDATED[@]} skipped=${#SKIPPED[@]}"
else
    # Nothing updated means every target was absent or already current. An
    # all-skipped sync must not read as "versions are in sync".
    gate_unit_skipped file-sync "no target file was updated (skipped=${#SKIPPED[@]})"
fi

# Output summary
if [ ${#UPDATED[@]} -gt 0 ]; then
    echo "Updated: ${UPDATED[*]}"
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo "Skipped: ${SKIPPED[*]}"
fi
echo ""

gate_end 0
