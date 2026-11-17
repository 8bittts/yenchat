#!/bin/bash
# Vendor Audit Verification
#
# Validates the canonical vendor audit doc against tracked baselines.
# Optional --app verifies that the built app bundle still matches inventory.
#
# Usage:
#   ./scripts/12-verify-vendor-audit.sh
#   ./scripts/12-verify-vendor-audit.sh --app yen-terminal/ghostty/zig-out/YEN.app

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
source "$REPO_ROOT/scripts/lib/vendor-manifest.sh"
source "$REPO_ROOT/scripts/lib/signature-utils.sh"
DOC_PATH="$REPO_ROOT/_docs/04-security.md"
APP_PATH=""

source "$REPO_ROOT/scripts/lib/required-app-bins.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            shift
            if [ $# -eq 0 ]; then
                echo "ERROR: --app requires a path"
                exit 1
            fi
            APP_PATH="$1"
            ;;
        --help|-h)
            echo "Usage: ./scripts/12-verify-vendor-audit.sh [--app /path/to/YEN.app]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            exit 1
            ;;
    esac
    shift
done

fail() {
    echo "ERROR: $1"
    exit 1
}

gate_begin 12-verify-vendor-audit

snapshot_value() {
    local key="$1"
    local line
    line=$(grep "^${key}=" "$DOC_PATH" | head -1 || true)
    if [ -z "$line" ]; then
        echo ""
    else
        echo "${line#*=}"
    fi
}


verify_overlap_commit_references() {
    local snapshot_commit="$1"
    local overlap_commit
    local saw_ref=false
    local ref_commit

    overlap_commit=$(sed -n 's/^Audit of YEN customizations against upstream Ghostty (commit `\([0-9a-f]\{7,40\}\)`).*/\1/p' "$DOC_PATH" | head -1)
    [ -n "$overlap_commit" ] || fail "Missing overlap assessment commit reference in _docs/04-security.md"

    if [ "$overlap_commit" != "$snapshot_commit" ] && [[ "$snapshot_commit" != "$overlap_commit"* ]]; then
        fail "Overlap assessment commit mismatch (overlap=$overlap_commit snapshot=$snapshot_commit)"
    fi

    while IFS= read -r ref_commit; do
        [ -z "$ref_commit" ] && continue
        saw_ref=true
        if [ "$ref_commit" != "$snapshot_commit" ]; then
            fail "ghostty_commit reference drift detected (ref=$ref_commit snapshot=$snapshot_commit)"
        fi
    done < <(grep -oE 'ghostty_commit=[0-9a-f]{7,40}' "$DOC_PATH" | cut -d'=' -f2 | sort -u)

    [ "$saw_ref" = true ] || fail "Missing ghostty_commit references in _docs/04-security.md"
}

if [ ! -f "$DOC_PATH" ]; then
    fail "Canonical vendor audit doc missing: _docs/04-security.md"
fi

grep -q "^## Upstream Ghostty Overlap Assessment$" "$DOC_PATH" || fail "Missing overlap assessment section in _docs/04-security.md"
grep -q "^## Bundled Binary Inventory (Resources/bin/)$" "$DOC_PATH" || fail "Missing bundled binary inventory section in _docs/04-security.md"

SNAPSHOT_DATE=$(snapshot_value "snapshot_date")
[ -z "$SNAPSHOT_DATE" ] && fail "Missing snapshot_date in _docs/04-security.md"
echo "$SNAPSHOT_DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || fail "Invalid snapshot_date format (expected YYYY-MM-DD)"

# Baseline files to validate.
# Derived from scripts/lib/vendor-manifest.sh so a new vendor cannot be missed
# here — a baseline absent from this list is simply never verified, which is a
# silent gap rather than a failure.
BASELINES=()
for _vendor_key in $(vendor_manifest_keys); do
    BASELINES+=("$(vendor_baseline_path "$REPO_ROOT" "$_vendor_key")")
done

for baseline in "${BASELINES[@]}"; do
    [ -f "$baseline" ] || fail "Missing baseline file: ${baseline#$REPO_ROOT/}"
done

DOC_GHOSTTY_COMMIT=$(snapshot_value "ghostty_commit")
DOC_GHOSTTY_VERSION=$(snapshot_value "ghostty_version")
DOC_GHOSTTY_UPSTREAM_REPO=$(snapshot_value "ghostty_upstream_repo")
[ -z "$DOC_GHOSTTY_COMMIT" ] && fail "Missing ghostty_commit in _docs/04-security.md"
[ -z "$DOC_GHOSTTY_VERSION" ] && fail "Missing ghostty_version in _docs/04-security.md"
[ -z "$DOC_GHOSTTY_UPSTREAM_REPO" ] && fail "Missing ghostty_upstream_repo in _docs/04-security.md"

BASE_GHOSTTY_COMMIT=$(baseline_value "upstream_commit" "$REPO_ROOT/yen-terminal/.ghostty-baseline")
BASE_GHOSTTY_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.ghostty-baseline")
BASE_GHOSTTY_UPSTREAM_REPO=$(baseline_value "upstream_repo" "$REPO_ROOT/yen-terminal/.ghostty-baseline")

[ "$DOC_GHOSTTY_COMMIT" = "$BASE_GHOSTTY_COMMIT" ] || fail "ghostty_commit mismatch (doc=$DOC_GHOSTTY_COMMIT baseline=$BASE_GHOSTTY_COMMIT)"
[ "$DOC_GHOSTTY_VERSION" = "$BASE_GHOSTTY_VERSION" ] || fail "ghostty_version mismatch (doc=$DOC_GHOSTTY_VERSION baseline=$BASE_GHOSTTY_VERSION)"
[ "$DOC_GHOSTTY_UPSTREAM_REPO" = "$BASE_GHOSTTY_UPSTREAM_REPO" ] || fail "ghostty_upstream_repo mismatch (doc=$DOC_GHOSTTY_UPSTREAM_REPO baseline=$BASE_GHOSTTY_UPSTREAM_REPO)"
verify_overlap_commit_references "$DOC_GHOSTTY_COMMIT"

check_vendor_version() {
    local vendor_key="$1"
    local baseline_file="$2"
    local doc_value
    local baseline_version

    doc_value=$(snapshot_value "$vendor_key")
    [ -z "$doc_value" ] && fail "Missing ${vendor_key} in _docs/04-security.md"

    baseline_version=$(baseline_value "upstream_version" "$baseline_file")
    [ "$doc_value" = "$baseline_version" ] || fail "${vendor_key} mismatch (doc=$doc_value baseline=$baseline_version)"
}

# Derived from the manifest so a new vendor cannot be added without its version
# being cross-checked against the audit doc. A vendor absent from this list was
# simply never verified — a silent gap, not a failure.
for _vendor_key in $(vendor_manifest_keys); do
    [ "$(vendor_manifest_field "$_vendor_key" type)" != "source" ] || continue
    check_vendor_version "${_vendor_key}_version" "$(vendor_baseline_path "$REPO_ROOT" "$_vendor_key")"
done

LATEST_SYNC="$SNAPSHOT_DATE"
for baseline in "${BASELINES[@]}"; do
    sync_value=$(baseline_value "last_sync" "$baseline")
    echo "$sync_value" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || fail "Invalid last_sync in ${baseline#$REPO_ROOT/}"
    if [ "$sync_value" \> "$LATEST_SYNC" ]; then
        LATEST_SYNC="$sync_value"
    fi
done

if [ "$SNAPSHOT_DATE" \< "$LATEST_SYNC" ]; then
    fail "Vendor audit snapshot is stale (snapshot_date=$SNAPSHOT_DATE, newest baseline sync=$LATEST_SYNC)"
fi

set_required_app_bins
for bin_name in "${REQUIRED_APP_BINS[@]}"; do
    grep -Eq "^\|[[:space:]]*${bin_name}[[:space:]]*\|" "$DOC_PATH" || fail "Bundled binary inventory missing entry for ${bin_name}"
done

gate_unit_ran doc-inventory "required_bins=${#REQUIRED_APP_BINS[@]}"

if [ -n "$APP_PATH" ]; then
    if [ ! -d "$APP_PATH" ]; then
        fail "--app path does not exist: $APP_PATH"
    fi
    APP_BINS_VERIFIED=0

    BIN_DIR="$APP_PATH/Contents/Resources/bin"
    [ -d "$BIN_DIR" ] || fail "Bundled app missing Resources/bin directory"

    for app_bin in "${REQUIRED_APP_BINS[@]}"; do
        app_bin_path=$(required_app_bin_path "$app_bin")
        [ -f "$BIN_DIR/$app_bin_path" ] || fail "Bundled app missing binary: $app_bin_path"
        [ -x "$BIN_DIR/$app_bin_path" ] || fail "Bundled app binary is not executable: $app_bin_path"
        # lipo -archs, not `file | grep universal` — the latter also passes an
        # arm64+arm64e fat binary with no x86_64 slice at all.
        assert_universal_binary "$BIN_DIR/$app_bin_path" \
            || fail "Bundled app binary is not universal (needs arm64 + x86_64): $app_bin"
        APP_BINS_VERIFIED=$((APP_BINS_VERIFIED + 1))
    done
    gate_unit_ran app-bundle "verified_bins=$APP_BINS_VERIFIED/${#REQUIRED_APP_BINS[@]}"
else
    # --app is optional, but its absence must be an explicit token rather than an
    # absence. Both invocations previously printed the IDENTICAL summary line, so
    # a doc-only run and a full bundle verification were indistinguishable.
    gate_unit_skipped app-bundle "--app not requested (doc-only run)"
fi

echo "  ✓ Vendor audit doc verified (_docs/04-security.md)"
gate_end 0
