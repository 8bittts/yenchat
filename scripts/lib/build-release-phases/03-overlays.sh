#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.

echo "[5/9] Applying overlays..."

# Quiet by default: apply-overlays.sh streams ~37 per-patch "Applied/idempotent
# skip" lines that drown the /update-yen log. Capture them and surface only warnings/
# errors plus a one-line summary. Full output streams on failure, or set
# YEN_VERBOSE_OVERLAYS=1 to see every patch line.
if [ "${YEN_VERBOSE_OVERLAYS:-0}" = "1" ]; then
    bash apply-overlays.sh || {
        echo "ERROR: apply-overlays.sh failed"
        exit 1
    }
else
    OVERLAY_LOG=$(mktemp)
    if bash apply-overlays.sh > "$OVERLAY_LOG" 2>&1; then
        grep -iE "warning|error|fail" "$OVERLAY_LOG" || true
        # Quote apply-overlays.sh's own tally rather than re-deriving one here.
        # Two greps over the same prose disagreed (46 here vs 44 elsewhere) and
        # neither came from the code doing the work, so the printed figure was
        # not evidence of anything. Fail closed if the tally is absent: a missing
        # summary means the run did not reach its end.
        OVERLAY_SUMMARY=$(grep -E '^  Overlays applied \(' "$OVERLAY_LOG" | tail -1 || true)
        if [ -z "$OVERLAY_SUMMARY" ]; then
            echo "ERROR: apply-overlays.sh printed no overlay tally — treating as an incomplete run"
            cat "$OVERLAY_LOG"
            rm -f "$OVERLAY_LOG"
            exit 1
        fi
        echo "$OVERLAY_SUMMARY"
        rm -f "$OVERLAY_LOG"
    else
        echo "ERROR: apply-overlays.sh failed"
        cat "$OVERLAY_LOG"
        rm -f "$OVERLAY_LOG"
        exit 1
    fi
fi

extract_expected_sparkle_key() {
    local key_tool="$1"
    "$key_tool" -p 2>&1 | awk '
        /OVERVIEW|Usage|Error/ { next }
        NF {
            gsub(/[[:space:]]/, "", $0)
            print
            exit
        }
    '
}

assert_su_public_ed_key() {
    local plist_path="$1"
    local expected_key="$2"
    local context_label="$3"
    local actual_key

    actual_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$plist_path" 2>/dev/null || echo "")
    if [ "$actual_key" != "$expected_key" ]; then
        echo "  ERROR: SUPublicEDKey mismatch in $context_label!"
        echo "    Expected: $expected_key"
        echo "    Actual: $actual_key"
        return 1
    fi
    return 0
}

SPARKLE_KEY_TOOL="$REPO_ROOT/tools/sparkle/bin/generate_keys"
EXPECTED_SUPUBLIC_EDKEY=""
if [ -x "$SPARKLE_KEY_TOOL" ]; then
    EXPECTED_SUPUBLIC_EDKEY=$(extract_expected_sparkle_key "$SPARKLE_KEY_TOOL")
fi

# Pre-build SUPublicEDKey check (catches key mismatch before 10-min build)
PRE_BUILD_PLIST="ghostty/macos/YEN-Info.plist"
if [ -f "$PRE_BUILD_PLIST" ] && [ -n "$EXPECTED_SUPUBLIC_EDKEY" ]; then
    if assert_su_public_ed_key "$PRE_BUILD_PLIST" "$EXPECTED_SUPUBLIC_EDKEY" "Info.plist (pre-build check)"; then
        echo "  SUPublicEDKey pre-build check passed"
    else
        exit 1
    fi
fi

echo ""
