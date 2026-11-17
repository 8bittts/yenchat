#!/bin/bash
# Generate appcast.xml for Sparkle updates
#
# This script:
# 1. Signs versioned DMG (e.g. yen-0999.dmg / yen-1000.dmg) with EdDSA key (stored in macOS Keychain)
# 2. Generates appcast.xml with version info and signature
#
# Usage: ./customizations/generate-appcast.sh
#
# Prerequisites:
# - Versioned DMG (e.g. yen-0999.dmg / yen-1000.dmg) must exist in public/stable/
# - version.json must exist in public/stable/
# - EdDSA private key must be in macOS Keychain (run tools/sparkle/bin/generate_keys once)

set -eo pipefail

# Paths (all release files live in public/stable/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/public/stable"
VERSION_JSON="$RELEASE_DIR/version.json"
APPCAST_FILE="$RELEASE_DIR/appcast.xml"
source "$REPO_ROOT/scripts/lib/release-constants.sh"
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/mount-utils.sh"

is_valid_min_os_version() {
    local min_os="$1"

    if [ -z "$min_os" ] || [ "$min_os" = "null" ]; then
        return 1
    fi

    # YEN currently supports macOS 13.0+. Support-floor changes must update the
    # desktop/vendor docs and release messaging in the same change.
    if printf '%s\n' "$min_os" | command grep -Eq '^(1[3-9]|[2-9][0-9])\.[0-9]+(\.[0-9]+)?$'; then
        return 0
    fi

    return 1
}

# Extract version to determine DMG filename
VERSION=$(get_version "$VERSION_JSON")

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "ERROR: Could not extract version from version.json"
    exit 1
fi

# Format version for filename using shared utility
VERSION_FILENAME=$(get_version_filename "$VERSION")
DMG_FILENAME="yen-${VERSION_FILENAME}.dmg"
DMG_FILE="$RELEASE_DIR/$DMG_FILENAME"
SIGN_TOOL="$REPO_ROOT/tools/sparkle/bin/sign_update"

# Check prerequisites
if [ ! -f "$DMG_FILE" ]; then
    echo "  ERROR: DMG not found: $DMG_FILENAME"
    exit 1
fi

if [ ! -f "$VERSION_JSON" ]; then
    echo "  ERROR: version.json not found"
    exit 1
fi

if [ ! -f "$SIGN_TOOL" ]; then
    echo "  ERROR: Sparkle sign_update tool not found"
    exit 1
fi

# Pre-check: Verify EdDSA key exists in keychain
if ! "$REPO_ROOT/tools/sparkle/bin/generate_keys" -p >/dev/null 2>&1; then
    echo "  ERROR: EdDSA private key not found in Keychain"
    exit 1
fi

# Extract version info from version.json (jq when available, grep/sed fallback).
RELEASE_DATE=$(get_version_json_string "$VERSION_JSON" "releaseDate")
MIN_OS=$(get_version_json_string "$VERSION_JSON" "minOS")
NOTES=$(get_version_json_string "$VERSION_JSON" "notes")

# DMGs are assets of the version's GitHub Release, not files in git.
DOWNLOAD_URL="$(github_release_asset_url "$VERSION" "$DMG_FILENAME")"
RELEASE_DOWNLOAD_PREFIX="$(github_release_download_prefix "$VERSION")"

# Validate version format (security: prevent injection)
if ! is_valid_release_version "$VERSION"; then
    echo "  ERROR: Invalid version format: $VERSION (expected X.XXX)"
    exit 1
fi

if ! is_valid_min_os_version "$MIN_OS"; then
    echo "  ERROR: Invalid minOS value in version.json: $MIN_OS (expected macOS 13.0 or newer dotted version)"
    exit 1
fi

# Get DMG file size
FILE_SIZE=$(stat -f%z "$DMG_FILE")

# Mount DMG to verify version
# First, ensure no stale YEN volumes exist (could cause mount to /Volumes/YEN 1)
detach_stale_yen_mounts

# Track mount point for cleanup on error
APPCAST_MOUNT_POINT=""
cleanup_appcast_mount() {
    if [ -n "$APPCAST_MOUNT_POINT" ] && [ -d "$APPCAST_MOUNT_POINT" ]; then
        hdiutil detach "$APPCAST_MOUNT_POINT" -force 2>/dev/null || true
    fi
}
trap cleanup_appcast_mount EXIT INT TERM

MOUNT_OUTPUT=$(hdiutil attach -nobrowse -readonly "$DMG_FILE" 2>&1)
# Parse mount point robustly - hdiutil output format: "/dev/diskX  Apple_HFS  /Volumes/YEN"
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)
APPCAST_MOUNT_POINT="$MOUNT_POINT"

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "  ERROR: Failed to mount DMG for version verification"
    exit 1
fi

DMG_INFO_PLIST="$MOUNT_POINT/YEN.app/Contents/Info.plist"
if [ ! -f "$DMG_INFO_PLIST" ]; then
    hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true
    echo "  ERROR: Info.plist not found in DMG"
    exit 1
fi

DMG_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DMG_INFO_PLIST" 2>/dev/null || echo "")
DMG_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$DMG_INFO_PLIST" 2>/dev/null || echo "")

hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1 || true
APPCAST_MOUNT_POINT=""  # Clear so cleanup trap doesn't try again

if [ -z "$DMG_VERSION" ] || [ -z "$DMG_BUILD" ]; then
    echo "  ERROR: Could not read version from DMG's Info.plist"
    exit 1
fi

if [ "$DMG_VERSION" != "$VERSION" ]; then
    echo "  ERROR: Version mismatch: DMG=$DMG_VERSION, expected=$VERSION"
    exit 1
fi

# Sign the DMG update and capture signature
SIGN_OUTPUT=$("$SIGN_TOOL" "$DMG_FILE" 2>&1)

# Extract signature from output (format: sparkle:edSignature="..." length="...")
ED_SIGNATURE=$(extract_sparkle_ed_signature "$SIGN_OUTPUT")

if [ -z "$ED_SIGNATURE" ]; then
    echo "  ERROR: Failed to sign $DMG_FILENAME"
    exit 1
fi

# Derive integer version for sparkle:version using shared utility
VERSION_INT=$(get_version_int "$VERSION")
if [ "$DMG_BUILD" != "$VERSION_INT" ]; then
    echo "  ERROR: Build number mismatch: DMG=$DMG_BUILD, expected=$VERSION_INT"
    exit 1
fi

# ----------------------------------------------------------------------------
# DELTA UPDATES (best-effort, never fatal — falls back to full-DMG-only exactly
# like today's behavior if anything here fails). Sparkle's vendored
# generate_appcast computes BinaryDelta patches from past DMGs; we only keep its
# <sparkle:deltas> fragment and splice it into our own hand-rolled appcast item,
# since our item needs custom styled notes + version/minOS validation that
# generate_appcast doesn't know how to produce.
# ----------------------------------------------------------------------------
DELTA_FRAGMENT=""
GENAPPCAST_TOOL="$REPO_ROOT/tools/sparkle/bin/generate_appcast"
DELTA_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/yen-appcast-deltas.XXXXXX" 2>/dev/null || true)"

# Clear any stale .delta files left in RELEASE_DIR from a prior/failed run before
# generating new ones — otherwise finalize-build.sh's upload glob would sweep up
# and publish deltas for a version that's no longer current.
find "$RELEASE_DIR" -maxdepth 1 -name '*.delta' -delete 2>/dev/null || true

if [ -x "$GENAPPCAST_TOOL" ] && [ -n "$DELTA_SCRATCH" ] && [ -d "$DELTA_SCRATCH" ]; then
    DELTA_ARCHIVES="$DELTA_SCRATCH/archives"
    mkdir -p "$DELTA_ARCHIVES"
    cp "$DMG_FILE" "$DELTA_ARCHIVES/$DMG_FILENAME"

    # Source past DMGs from the newest published GitHub Releases (tags v1.270,
    # v1.269, ...). A release without a DMG asset is skipped, and a failed
    # download only drops that delta source.
    MAX_DELTA_SOURCES=5
    PAST_TAGS=$(gh release list --repo "$GITHUB_RELEASES_REPO" --limit 30 \
        --exclude-drafts --exclude-pre-releases --json tagName --jq '.[].tagName' 2>/dev/null \
        | grep -E '^v[0-9]+\.[0-9]+$' \
        | grep -v -x "v${VERSION}" \
        | sort -rV \
        | head -n "$MAX_DELTA_SOURCES" || true)

    if [ -n "$PAST_TAGS" ]; then
        while IFS= read -r past_tag; do
            [ -n "$past_tag" ] || continue
            gh release download "$past_tag" --repo "$GITHUB_RELEASES_REPO" \
                --pattern 'yen-*.dmg' --dir "$DELTA_ARCHIVES" --skip-existing >/dev/null 2>&1 || true
        done <<< "$PAST_TAGS"
    fi

    DELTA_SOURCE_COUNT=$(find "$DELTA_ARCHIVES" -maxdepth 1 -name 'yen-*.dmg' ! -name "$DMG_FILENAME" | wc -l | tr -d ' ')

    if [ "$DELTA_SOURCE_COUNT" -gt 0 ]; then
        DELTA_APPCAST_OUT="$DELTA_SCRATCH/appcast.xml"
        if GENAPPCAST_OUTPUT=$("$GENAPPCAST_TOOL" \
            --maximum-versions 1 \
            --maximum-deltas 5 \
            --download-url-prefix "$RELEASE_DOWNLOAD_PREFIX" \
            -o "$DELTA_APPCAST_OUT" \
            "$DELTA_ARCHIVES" 2>&1); then

            if [ -f "$DELTA_APPCAST_OUT" ] && grep -q 'sparkle:deltas' "$DELTA_APPCAST_OUT"; then
                DELTA_FRAGMENT=$(awk '/<sparkle:deltas>/,/<\/sparkle:deltas>/' "$DELTA_APPCAST_OUT")
            fi

            if [ -n "$DELTA_FRAGMENT" ]; then
                mkdir -p "$RELEASE_DIR"
                find "$DELTA_ARCHIVES" -maxdepth 1 -name '*.delta' -exec mv {} "$RELEASE_DIR/" \;
                echo "  Delta(s) generated: $(find "$RELEASE_DIR" -maxdepth 1 -name '*.delta' | wc -l | tr -d ' ')"
            fi
        else
            echo "  WARNING: delta generation failed (non-fatal, shipping full-DMG-only): $GENAPPCAST_OUTPUT"
        fi
    else
        echo "  No past DMGs reachable — full-DMG-only update (no deltas), same as today"
    fi

    rm -rf "$DELTA_SCRATCH"
fi

# Purge Sparkle's extraction cache (never self-prunes; would otherwise accumulate
# one full app copy per archive ever processed). Safe to always clear since
# nothing depends on cross-run cache reuse for an infrequent release script.
rm -rf "$HOME/Library/Caches/Sparkle_generate_appcast"

if [ -n "$DELTA_FRAGMENT" ]; then
    # [CRITICAL] `<sparkle:deltas>` is a SIBLING of `<enclosure>`, both direct children
    # of `<item>` — it is NOT nested inside the enclosure. Sparkle reads deltas from the
    # item's children, so a nested block parses as well-formed XML and is then silently
    # ignored: every client downloads the full DMG (~103 MB) instead of its delta (~1 MB).
    # That is exactly the shape `generate_appcast` emits, which is why DELTA_FRAGMENT is
    # spliced in as-is rather than re-indented into the enclosure.
    ENCLOSURE_BLOCK="            <enclosure
                url=\"$DOWNLOAD_URL\"
                length=\"$FILE_SIZE\"
                type=\"application/x-apple-diskimage\"
                sparkle:edSignature=\"$ED_SIGNATURE\" />
$DELTA_FRAGMENT"
else
    ENCLOSURE_BLOCK="            <enclosure
                url=\"$DOWNLOAD_URL\"
                length=\"$FILE_SIZE\"
                type=\"application/x-apple-diskimage\"
                sparkle:edSignature=\"$ED_SIGNATURE\" />"
fi

# Convert release date to RFC 2822 format for pubDate
# Input: 2025-12-21, Output: Sun, 21 Dec 2025 12:00:00 +0000
if [ -n "$RELEASE_DATE" ]; then
    PUB_DATE=$(date -j -f "%Y-%m-%d" "$RELEASE_DATE" "+%a, %d %b %Y 12:00:00 +0000" 2>/dev/null || echo "")
else
    PUB_DATE=$(date "+%a, %d %b %Y %H:%M:%S %z")
fi

# Escape notes for XML CDATA (should be safe already, but just in case)
NOTES_ESCAPED=$(echo "$NOTES" | sed 's/]]>/]]]]><![CDATA[>/g')

cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>YEN Updates</title>
        <description>YEN Terminal updates via Sparkle.</description>
        <language>en</language>
        <item>
            <title>YEN $VERSION</title>
            <link>https://yen.chat</link>
            <sparkle:version>$VERSION_INT</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <description><![CDATA[
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 12px; }
                    h2 { font-size: 16px; margin: 0 0 8px 0; color: #ff5100; }
                    .quip { color: white; margin-bottom: 12px; }
                    .tech { background: #f5f5f5; padding: 8px 12px; border-radius: 6px; font-size: 13px; }
                    .tech strong { color: #333; }
                </style>
                <h2>YEN $VERSION</h2>
                <p class="quip">$NOTES_ESCAPED</p>
                <p class="tech"><strong>Full release notes:</strong> <a href="https://yen.chat/docs">yen.chat/docs</a></p>
            ]]></description>
            <pubDate>$PUB_DATE</pubDate>
$ENCLOSURE_BLOCK
            <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
        </item>
    </channel>
</rss>
EOF

chmod 644 "$APPCAST_FILE"

# Validate generated XML (xmllint ships with Xcode CLT, which is a build prerequisite)
if ! command -v xmllint &>/dev/null; then
    echo "  ERROR: xmllint not found — install Xcode Command Line Tools"
    exit 1
fi
XMLLINT_STATUS=0
XMLLINT_OUTPUT=$(xmllint --noout "$APPCAST_FILE" 2>&1) || XMLLINT_STATUS=$?
if [ "$XMLLINT_STATUS" -ne 0 ]; then
    echo "  ERROR: Appcast XML validation failed"
    echo "  $XMLLINT_OUTPUT"
    exit 1
fi
