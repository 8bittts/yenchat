#!/bin/bash
# Stage Release Files Script
# Used in /yen-zip Step 7: Stage Release
#
# Stages release metadata and version bump files for commit.
# DMG is hosted on GitHub Releases (uploaded by finalize-build.sh).
#
# Usage: ./scripts/07-stage-release.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
cd "$REPO_ROOT"

# Source shared utilities
source "$REPO_ROOT/scripts/lib/version-utils.sh"

gate_begin 07-stage-release

echo ""
echo "Stage Release"

# Get versioned filename from version.json
VERSION_JSON="public/stable/version.json"
VERSION_SIG="public/stable/version.sig"
if [ ! -f "$VERSION_JSON" ]; then
    echo "  X version.json not found"
    gate_unit_skipped staged-artifacts "precondition failed"
    gate_end 1
fi
if [ ! -f "$VERSION_SIG" ]; then
    echo "  X version.sig not found"
    echo "  Run: ./yen-terminal/customizations/finalize-build.sh"
    gate_unit_skipped staged-artifacts "precondition failed"
    gate_end 1
fi

VERSION=$(get_version "$VERSION_JSON")
if [ -z "$VERSION" ]; then
    echo "  X Could not extract version from version.json"
    gate_unit_skipped staged-artifacts "precondition failed"
    gate_end 1
fi

DMG_FILENAME=$(get_dmg_filename "$VERSION")

echo "  v$VERSION"

# Remove any tracked DMG files from git (DMGs never belong in the repository)
OLD_DMGS_REMOVED=0
for OLD_DMG in $(git ls-files 'public/stable/yen-*.dmg' 2>/dev/null); do
    if git rm --quiet "$OLD_DMG" 2>/dev/null; then
        OLD_DMGS_REMOVED=$((OLD_DMGS_REMOVED + 1))
    fi
done

# Remove old sha256 files (keep only current version)
for OLD_SHA in $(git ls-files 'public/stable/yen-*.dmg.sha256' 2>/dev/null); do
    BASENAME=$(basename "$OLD_SHA")
    if [ "$BASENAME" = "${DMG_FILENAME}.sha256" ]; then
        continue
    fi
    git rm --quiet "$OLD_SHA" 2>/dev/null || true
done

# Stage release metadata (DMG is on GitHub Releases, not in git)
if [ -f "public/stable/${DMG_FILENAME}.sha256" ]; then
    git add "public/stable/${DMG_FILENAME}.sha256"
else
    echo "  X ${DMG_FILENAME}.sha256 not found — checksum is required before staging release"
    echo "  Run: ./yen-terminal/customizations/finalize-build.sh"
    gate_unit_skipped staged-artifacts "precondition failed"
    gate_end 1
fi
# Verify appcast references current version
if ! grep -q "$DMG_FILENAME" public/stable/appcast.xml; then
    echo "  ERROR: appcast.xml does not reference current DMG ($DMG_FILENAME)"
    gate_unit_skipped staged-artifacts "precondition failed"
    gate_end 1
fi

git add public/stable/version.json public/stable/version.sig public/stable/appcast.xml

# Stage version bump files (package.json only - CLI reads version dynamically)
git add package.json

# Summary
gate_unit_ran staged-artifacts "files=$(git -C "$REPO_ROOT" diff --cached --name-only | grep -c . || true)"

echo "Staged:"
if [ "$OLD_DMGS_REMOVED" -gt 0 ]; then
    echo "  - Removed $OLD_DMGS_REMOVED old DMG file(s) from git"
fi
echo "  - Checksum: ${DMG_FILENAME}.sha256"
echo "  - Metadata: version.json, version.sig, appcast.xml"
echo "  - Version files: package.json"
echo "  - DMG: hosted on GitHub Releases (not in git)"
echo ""

git diff --cached --stat

echo ""
echo "Ready to commit:"
echo "  git -C \"$REPO_ROOT\" commit -m \"v${VERSION}: Brief description [deploy]\""
echo "  git -C \"$REPO_ROOT\" push origin main"
echo ""

gate_end 0
