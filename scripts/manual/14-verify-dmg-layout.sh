#!/bin/bash
# Verify DMG Layout and Installer UX
#
# Automated checks:
# 1) Local DMG resource assets exist and match expected dimensions.
# 2) Target DMG passes hdiutil integrity verification.
# 3) Mounted DMG contains required installer structure:
#    - YEN.app bundle
#    - Applications symlink -> /Applications
#    - Hidden .background folder with expected assets
#    - No visible .fseventsd metadata folder
#    - No shipped .metadata_never_index staging marker
#    - .DS_Store present with background metadata markers
# 4) Finder layout metadata matches frozen spec (optional in headless mode).
#
# Manual checks (printed at end):
# - Retina and non-Retina visual alignment
# - Label readability
# - Drag-to-install behavior
#
# Usage:
#   ./scripts/manual/14-verify-dmg-layout.sh
#   ./scripts/manual/14-verify-dmg-layout.sh --dmg /path/to/yen-0XXX.dmg
#   ./scripts/manual/14-verify-dmg-layout.sh --skip-finder-check
#
# Exit codes:
#   0 = all automated checks passed
#   1 = one or more checks failed

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/public/stable"
VERSION_JSON="$RELEASE_DIR/version.json"
DMG_RESOURCES_DIR="$REPO_ROOT/yen-terminal/customizations/dmg-resources"

EXPECTED_BG_1X="600x600"
EXPECTED_BG_2X="1200x1200"
EXPECTED_WINDOW_SIZE="600x660"
EXPECTED_ICON_SIZE="108"
EXPECTED_TEXT_SIZE="12"
EXPECTED_ARRANGEMENT="not arranged"
EXPECTED_APP_POS="300,241"
EXPECTED_APPLICATIONS_POS="300,420"
EXPECTED_APPLICATIONS_TARGET="/Applications"

DMG_PATH=""
SKIP_FINDER_CHECK=0
FAILURES=0
MOUNT_DIR=""
MOUNTED=0

source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/mount-utils.sh"

usage() {
    cat <<EOF
Usage: $0 [--dmg /path/to/yen-0XXX.dmg] [--skip-finder-check]

Options:
  --dmg PATH             Verify a specific DMG file.
  --skip-finder-check    Skip Finder AppleScript geometry checks (headless mode).
  -h, --help             Show this help text.
EOF
}

pass() {
    echo "  OK: $1"
}

fail() {
    echo "  X: $1"
    FAILURES=$((FAILURES + 1))
}

warn() {
    echo "  !: $1"
}

register_mount_with_finder() {
    local mount_dir="$1"
    local disk_name="$2"
    local attempt
    local finder_disks

    open "$mount_dir" >/dev/null 2>&1 || true

    for attempt in 1 2 3 4 5; do
        finder_disks=$(osascript -e 'tell application "Finder" to get name of every disk' 2>/dev/null || true)
        if printf '%s\n' "$finder_disks" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -Fxq "$disk_name"; then
            return 0
        fi
        sleep 1
        open "$mount_dir" >/dev/null 2>&1 || true
    done

    return 1
}

get_png_dimensions() {
    local file_path="$1"
    sips -g pixelWidth -g pixelHeight "$file_path" 2>/dev/null | awk '
        /pixelWidth:/ { w=$2 }
        /pixelHeight:/ { h=$2 }
        END {
            if (w == "" || h == "") exit 1
            print w "x" h
        }
    '
}

check_png_dimensions() {
    local file_path="$1"
    local expected="$2"
    local label="$3"
    local actual

    if [ ! -f "$file_path" ]; then
        fail "$label missing: $file_path"
        return
    fi

    if ! actual=$(get_png_dimensions "$file_path"); then
        fail "$label has unreadable dimensions: $file_path"
        return
    fi

    if [ "$actual" != "$expected" ]; then
        fail "$label dimensions mismatch (expected $expected, got $actual)"
        return
    fi

    pass "$label dimensions match ($actual)"
}

cleanup() {
    if [ "$MOUNTED" -eq 1 ] && [ -n "$MOUNT_DIR" ]; then
        hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dmg)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --dmg requires a path"
                exit 1
            fi
            DMG_PATH="$1"
            ;;
        --skip-finder-check)
            SKIP_FINDER_CHECK=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "$DMG_PATH" ]; then
    if [ ! -f "$VERSION_JSON" ]; then
        echo "ERROR: version.json not found: $VERSION_JSON"
        exit 1
    fi
    VERSION=$(get_version "$VERSION_JSON")
    VERSION_FILENAME=$(get_version_filename "$VERSION")
    DMG_PATH="$RELEASE_DIR/yen-${VERSION_FILENAME}.dmg"
fi

echo ""
echo "---------------"
echo "DMG Layout Verification"
echo "---------------"
echo "DMG: $DMG_PATH"
echo ""

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found: $DMG_PATH"
    exit 1
fi

echo "[1/6] Checking local DMG resource assets..."
check_png_dimensions "$DMG_RESOURCES_DIR/background.png" "$EXPECTED_BG_1X" "background.png"
check_png_dimensions "$DMG_RESOURCES_DIR/background@2x.png" "$EXPECTED_BG_2X" "background@2x.png"

echo ""
echo "[2/6] Verifying DMG integrity..."
if hdiutil verify "$DMG_PATH" >/dev/null 2>&1; then
    pass "hdiutil verify passed"
else
    fail "hdiutil verify failed for $DMG_PATH"
fi

echo ""
echo "[3/6] Mounting DMG and validating installer structure..."
detach_stale_yen_mounts
if ! MOUNT_OUTPUT=$(hdiutil attach -readonly -nobrowse "$DMG_PATH" 2>&1); then
    fail "failed to mount DMG: $MOUNT_OUTPUT"
else
    MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)
    if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
        fail "failed to resolve DMG mount path"
    else
        MOUNTED=1
        pass "mounted at $MOUNT_DIR"
    fi
fi

if [ "$MOUNTED" -eq 1 ]; then
    if [ -d "$MOUNT_DIR/YEN.app" ]; then
        pass "YEN.app present"
    else
        fail "YEN.app missing at DMG root"
    fi

    if [ -L "$MOUNT_DIR/Applications" ]; then
        APP_LINK_TARGET=$(readlink "$MOUNT_DIR/Applications" 2>/dev/null || true)
        if [ "$APP_LINK_TARGET" = "$EXPECTED_APPLICATIONS_TARGET" ]; then
            pass "Applications symlink points to $EXPECTED_APPLICATIONS_TARGET"
        else
            fail "Applications symlink target mismatch (expected $EXPECTED_APPLICATIONS_TARGET, got ${APP_LINK_TARGET:-<empty>})"
        fi
    else
        fail "Applications symlink missing at DMG root"
    fi

    if [ -d "$MOUNT_DIR/.background" ]; then
        pass ".background directory present"
        if ls -ldO "$MOUNT_DIR/.background" 2>/dev/null | grep -q "hidden"; then
            pass ".background has hidden flag"
        else
            fail ".background missing hidden flag"
        fi
    else
        fail ".background directory missing"
    fi

    check_png_dimensions "$MOUNT_DIR/.background/background.png" "$EXPECTED_BG_1X" "mounted background.png"
    check_png_dimensions "$MOUNT_DIR/.background/background@2x.png" "$EXPECTED_BG_2X" "mounted background@2x.png"

    if [ -e "$MOUNT_DIR/.fseventsd" ]; then
        fail ".fseventsd should not be present in mounted DMG root"
    else
        pass ".fseventsd absent from mounted DMG root"
    fi

    if [ -e "$MOUNT_DIR/.metadata_never_index" ]; then
        fail ".metadata_never_index should not be present in mounted DMG root"
    else
        pass ".metadata_never_index absent from mounted DMG root"
    fi
fi

echo ""
echo "[4/6] Validating Finder metadata artifacts..."
if [ "$MOUNTED" -eq 1 ]; then
    if [ -f "$MOUNT_DIR/.DS_Store" ]; then
        pass ".DS_Store present"
        DS_STRINGS=$(strings "$MOUNT_DIR/.DS_Store" 2>/dev/null || true)
        if echo "$DS_STRINGS" | grep -q ".background"; then
            pass ".DS_Store references .background"
        else
            fail ".DS_Store missing .background reference"
        fi
        # background.png must appear in the persisted Finder metadata for the
        # current release workflow. When it does not, the DMG opens with the
        # default white background even though the asset files are present.
        # RGBA PNGs cause Finder to silently write color metadata instead of
        # an image alias — backgrounds must be opaque RGB to persist reliably.
        if echo "$DS_STRINGS" | grep -q "background.png"; then
            pass ".DS_Store references background.png"
        else
            fail ".DS_Store missing background.png reference"
        fi
        if echo "$DS_STRINGS" | grep -q "Applications"; then
            pass ".DS_Store references Applications item"
        else
            warn ".DS_Store missing explicit Applications string (non-fatal)"
        fi
    else
        fail ".DS_Store missing from mounted DMG root"
    fi
fi

echo ""
echo "[5/6] Validating Finder layout geometry..."
if [ "$MOUNTED" -eq 1 ]; then
    if [ "$SKIP_FINDER_CHECK" -eq 1 ]; then
        echo "  ! Finder geometry check skipped (--skip-finder-check)"
    else
        DISK_NAME=$(basename "$MOUNT_DIR")
        FINDER_OUTPUT=""
        FINDER_STATUS=0
        if ! register_mount_with_finder "$MOUNT_DIR" "$DISK_NAME"; then
            FINDER_STATUS=1
            FINDER_OUTPUT="Finder did not register mounted disk \"$DISK_NAME\" at $MOUNT_DIR"
        else
            FINDER_OUTPUT=$(osascript <<EOF 2>&1
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        delay 0.5
        set w to container window
        set vo to icon view options of w
        set b to bounds of w
        set p1 to position of item "YEN.app" of w
        set p2 to position of item "Applications" of w
        return "bounds=" & (item 1 of b as text) & "," & (item 2 of b as text) & "," & (item 3 of b as text) & "," & (item 4 of b as text) & linefeed & "icon_size=" & (icon size of vo) & linefeed & "text_size=" & (text size of vo) & linefeed & "arrangement=" & (arrangement of vo as text) & linefeed & "app_pos=" & (item 1 of p1 as text) & "," & (item 2 of p1 as text) & linefeed & "applications_pos=" & (item 1 of p2 as text) & "," & (item 2 of p2 as text)
    end tell
end tell
EOF
            ) || FINDER_STATUS=$?
        fi

        if [ "$FINDER_STATUS" -ne 0 ]; then
            fail "Finder geometry read failed: $FINDER_OUTPUT"
        else
            BOUNDS=$(echo "$FINDER_OUTPUT" | awk -F= '/^bounds=/{print $2}')
            ICON_SIZE=$(echo "$FINDER_OUTPUT" | awk -F= '/^icon_size=/{print $2}')
            TEXT_SIZE=$(echo "$FINDER_OUTPUT" | awk -F= '/^text_size=/{print $2}')
            ARRANGEMENT=$(echo "$FINDER_OUTPUT" | awk -F= '/^arrangement=/{print $2}')
            APP_POS=$(echo "$FINDER_OUTPUT" | awk -F= '/^app_pos=/{print $2}')
            APPLICATIONS_POS=$(echo "$FINDER_OUTPUT" | awk -F= '/^applications_pos=/{print $2}')
            BOUNDS_SIZE=$(echo "$BOUNDS" | awk -F, 'NF==4 { print ($3 - $1) "x" ($4 - $2) }')

            [ "$BOUNDS_SIZE" = "$EXPECTED_WINDOW_SIZE" ] && pass "window size matches ($BOUNDS_SIZE)" || fail "window size mismatch (expected $EXPECTED_WINDOW_SIZE, got ${BOUNDS_SIZE:-<empty>}; raw bounds ${BOUNDS:-<empty>})"
            [ "$ICON_SIZE" = "$EXPECTED_ICON_SIZE" ] && pass "icon size matches ($ICON_SIZE)" || fail "icon size mismatch (expected $EXPECTED_ICON_SIZE, got ${ICON_SIZE:-<empty>})"
            [ "$TEXT_SIZE" = "$EXPECTED_TEXT_SIZE" ] && pass "text size matches ($TEXT_SIZE)" || fail "text size mismatch (expected $EXPECTED_TEXT_SIZE, got ${TEXT_SIZE:-<empty>})"
            [ "$ARRANGEMENT" = "$EXPECTED_ARRANGEMENT" ] && pass "arrangement matches ($ARRANGEMENT)" || fail "arrangement mismatch (expected '$EXPECTED_ARRANGEMENT', got '${ARRANGEMENT:-<empty>}')"
            [ "$APP_POS" = "$EXPECTED_APP_POS" ] && pass "YEN.app position matches ($APP_POS)" || fail "YEN.app position mismatch (expected $EXPECTED_APP_POS, got ${APP_POS:-<empty>})"
            [ "$APPLICATIONS_POS" = "$EXPECTED_APPLICATIONS_POS" ] && pass "Applications position matches ($APPLICATIONS_POS)" || fail "Applications position mismatch (expected $EXPECTED_APPLICATIONS_POS, got ${APPLICATIONS_POS:-<empty>})"
        fi
    fi
fi

echo ""
echo "[6/6] Manual QA checklist (run before shipping):"
echo "  [ ] On Retina display: open DMG and verify keyboard art is crisp (no stretching/clipping)."
echo "  [ ] On non-Retina display: open DMG and verify composition remains aligned and legible."
echo "  [ ] Verify YEN.app and Applications labels are readable and not overlapping artwork."
echo "  [ ] Drag YEN.app to Applications and confirm install succeeds."
echo "  [ ] Reopen DMG and confirm layout remains deterministic."

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "DMG layout verification failed ($FAILURES issue(s))."
    exit 1
fi

echo "DMG layout verification passed."
exit 0
