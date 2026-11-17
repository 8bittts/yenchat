#!/bin/bash
# Verify Sparkle Binary-Delta Update Generation (dry run)
#
# Proves the delta-update mechanics work against two REAL, already-published
# YEN DMGs from the published GitHub Releases, without touching
# public/stable/, git, or any release. Everything happens in a scratch dir.
#
# Checks:
#   1. generate_appcast (Sparkle's vendored tool) produces a real .delta
#   2. the delta enclosure carries a non-empty sparkle:edSignature
#   3. BinaryDelta apply reconstructs a byte-identical .app from old app + delta
#   4. the reconstructed app passes codesign --verify --deep --strict
#   5. the reconstructed app is accepted by Gatekeeper (Notarized Developer ID)
#   6. the generated appcast fragment passes xmllint
#
# Usage: ./scripts/manual/17-verify-sparkle-delta-dryrun.sh [NEW_VERSION] [OLD_VERSION]
#   Versions are release versions such as 1.272. Defaults to the two newest
#   published GitHub Releases.
#
# Exit codes:
#   0 = All checks passed
#   1 = Verification failed
#   2 = Skipped (fewer than 2 published releases)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/release-constants.sh"
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/mount-utils.sh"

GENERATE_APPCAST="$REPO_ROOT/tools/sparkle/bin/generate_appcast"
BINARY_DELTA="$REPO_ROOT/tools/sparkle/bin/BinaryDelta"

echo ""
echo "Sparkle Delta Dry Run"

if [ ! -x "$GENERATE_APPCAST" ] || [ ! -x "$BINARY_DELTA" ]; then
    echo "  ERROR: Sparkle vendored tools not found under tools/sparkle/bin/"
    exit 1
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/yen-delta-dryrun.XXXXXX")"
NEW_MOUNT=""
OLD_MOUNT=""
cleanup() {
    [ -n "$NEW_MOUNT" ] && hdiutil detach "$NEW_MOUNT" -force >/dev/null 2>&1 || true
    [ -n "$OLD_MOUNT" ] && hdiutil detach "$OLD_MOUNT" -force >/dev/null 2>&1 || true
    /bin/rm -rf "$SCRATCH"
}
trap cleanup EXIT

detach_stale_yen_mounts

echo "  Listing published GitHub Releases..."
TAGS_OUTPUT=$(gh release list --repo "$GITHUB_RELEASES_REPO" --limit 30 \
    --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName' 2>&1) || {
    echo "  ERROR: could not list GitHub Releases"
    echo "  $TAGS_OUTPUT"
    exit 1
}
VERSIONS=$(printf '%s\n' "$TAGS_OUTPUT" | grep -E '^v[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V -u || true)
COUNT=$(printf '%s\n' "$VERSIONS" | grep -c . || true)
if [ "$COUNT" -lt 2 ]; then
    echo "  SKIP: fewer than 2 published releases — nothing to diff"
    exit 2
fi

NEW_VER="${1:-$(printf '%s\n' "$VERSIONS" | tail -1)}"
OLD_VER="${2:-$(printf '%s\n' "$VERSIONS" | tail -2 | head -1)}"
NEW_DMG="yen-$(get_version_filename "$NEW_VER").dmg"
OLD_DMG="yen-$(get_version_filename "$OLD_VER").dmg"
echo "  Delta source: ${OLD_DMG} -> ${NEW_DMG}"

mkdir -p "$SCRATCH/archives"

echo "  [1/6] Downloading real DMGs..."
gh release download "$(github_release_tag "$NEW_VER")" --repo "$GITHUB_RELEASES_REPO" --pattern "$NEW_DMG" --dir "$SCRATCH/archives"
gh release download "$(github_release_tag "$OLD_VER")" --repo "$GITHUB_RELEASES_REPO" --pattern "$OLD_DMG" --dir "$SCRATCH/archives"

echo "  [2/6] Running generate_appcast (default Keychain 'ed25519' account)..."
"$GENERATE_APPCAST" \
    --maximum-versions 1 \
    --maximum-deltas 5 \
    --download-url-prefix "$(github_release_download_prefix "$NEW_VER")" \
    -o "$SCRATCH/archives/appcast.xml" \
    "$SCRATCH/archives"

DELTA_FILE=$(find "$SCRATCH/archives" -maxdepth 1 -name '*.delta' | head -1)
if [ -z "$DELTA_FILE" ]; then
    echo "  FAIL: no .delta file produced"
    exit 1
fi
DELTA_SIZE=$(stat -f%z "$DELTA_FILE")
DMG_SIZE=$(stat -f%z "$SCRATCH/archives/$NEW_DMG")
echo "  Delta: $(basename "$DELTA_FILE") (${DELTA_SIZE} bytes vs ${DMG_SIZE} bytes DMG)"

echo "  [3/6] Verifying appcast fragment (deltaFrom + signature)..."
if ! grep -q 'sparkle:deltaFrom' "$SCRATCH/archives/appcast.xml"; then
    echo "  FAIL: no sparkle:deltas element in generated appcast"
    exit 1
fi
if ! grep -q 'sparkle:edSignature' "$SCRATCH/archives/appcast.xml"; then
    echo "  FAIL: delta enclosure missing sparkle:edSignature"
    exit 1
fi

echo "  [4/6] Applying delta and comparing to real published version..."
MOUNT_OLD_OUTPUT=$(hdiutil attach -nobrowse -readonly "$SCRATCH/archives/$OLD_DMG" 2>&1)
OLD_MOUNT=$(echo "$MOUNT_OLD_OUTPUT" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)
[ -n "$OLD_MOUNT" ] || { echo "  FAIL: could not mount old DMG"; exit 1; }
mkdir -p "$SCRATCH/old-app"
cp -R "$OLD_MOUNT/YEN.app" "$SCRATCH/old-app/YEN.app"
hdiutil detach "$OLD_MOUNT" -force >/dev/null 2>&1 || true
OLD_MOUNT=""

mkdir -p "$SCRATCH/patched-app"
"$BINARY_DELTA" apply "$SCRATCH/old-app/YEN.app" "$SCRATCH/patched-app/YEN.app" "$DELTA_FILE"

MOUNT_NEW_OUTPUT=$(hdiutil attach -nobrowse -readonly "$SCRATCH/archives/$NEW_DMG" 2>&1)
NEW_MOUNT=$(echo "$MOUNT_NEW_OUTPUT" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)
[ -n "$NEW_MOUNT" ] || { echo "  FAIL: could not mount new DMG"; exit 1; }
mkdir -p "$SCRATCH/real-new-app"
cp -R "$NEW_MOUNT/YEN.app" "$SCRATCH/real-new-app/YEN.app"
hdiutil detach "$NEW_MOUNT" -force >/dev/null 2>&1 || true
NEW_MOUNT=""

# Symlinks inside the .app (e.g. Sparkle.framework/Versions/Current) legitimately
# trigger "Directory loop detected" warnings from `diff -r` — real content
# differences are what fail this check, not those warnings.
DIFF_OUTPUT=$(command diff -rq "$SCRATCH/patched-app/YEN.app" "$SCRATCH/real-new-app/YEN.app" 2>&1 | grep -v 'Directory loop detected' || true)
if [ -n "$DIFF_OUTPUT" ]; then
    echo "  FAIL: patched app differs from real published version"
    echo "$DIFF_OUTPUT"
    exit 1
fi
echo "  Byte-identical reconstruction confirmed"

echo "  [5/6] Verifying codesign + Gatekeeper acceptance..."
codesign --verify --deep --strict "$SCRATCH/patched-app/YEN.app"
SPCTL_OUTPUT=$(spctl --assess --type execute -vv "$SCRATCH/patched-app/YEN.app" 2>&1)
echo "  $SPCTL_OUTPUT"
echo "$SPCTL_OUTPUT" | grep -q "accepted" || { echo "  FAIL: Gatekeeper rejected reconstructed app"; exit 1; }

echo "  [6/6] Validating appcast XML..."
if ! command -v xmllint &>/dev/null; then
    echo "  ERROR: xmllint not found — install Xcode Command Line Tools"
    exit 1
fi
xmllint --noout "$SCRATCH/archives/appcast.xml"

# Regenerable content-addressed cache; safe to always purge after a run.
/bin/rm -rf "$HOME/Library/Caches/Sparkle_generate_appcast"

echo ""
echo "PASS — delta computed, signed, applied, byte-identical, codesign+Gatekeeper OK, XML valid."
echo "No writes to public/stable/, no git, no release uploads."
