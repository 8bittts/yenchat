#!/bin/bash
# Vendor — Master Vendor Orchestration
#
# Checks and updates all vendored dependencies in one pass.
#
# Usage:
#   ./scripts/14-vendor.sh              # Check + update all vendors
#   ./scripts/14-vendor.sh --check      # Check only (no downloads)
#   ./scripts/14-vendor.sh --check --release  # Release gate: accept a Ghostty baseline
#                                       # pushed by the /update-yen vendor phase within the release window
#   ./scripts/14-vendor.sh --force      # Force re-download all
#   ./scripts/14-vendor.sh ghostty      # Update only Ghostty
#   ./scripts/14-vendor.sh yazi         # Update only Yazi
#   ./scripts/14-vendor.sh lazygit      # Update only lazygit
#   ./scripts/14-vendor.sh delta        # Update only delta
#   ./scripts/14-vendor.sh yazi --force # Update only Yazi (force)

set -e
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/workflow-lock.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"
source "$REPO_ROOT/scripts/lib/vendor-manifest.sh"
source "$REPO_ROOT/scripts/lib/zig-toolchain.sh"
source "$REPO_ROOT/scripts/lib/release-vendor-window.sh"
init_shared_workflow_lock "$REPO_ROOT"

require_python3 "for GitHub API JSON parsing" || exit 1

# Auto-detect GitHub token from gh CLI if not explicitly set (avoids rate limits)
if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    GITHUB_TOKEN=$(gh auth token 2>/dev/null) || true
fi

GITHUB_API_CACHE_DIR="${TMPDIR:-/tmp}/yen-github-api-cache"
GITHUB_API_CACHE_TTL_SECONDS="${YEN_GITHUB_API_CACHE_TTL_SECONDS:-300}"
VENDOR_STATUS_PREFETCH_CONCURRENCY="${YEN_VENDOR_STATUS_PREFETCH_CONCURRENCY:-4}"
VENDOR_STATUS_PREFETCH_DIR=""
GITHUB_API_RESPONSE_HTTP_CODE=""
GITHUB_API_RESPONSE_BODY=""
PREFETCH_STATUS_HTTP_CODE=""
PREFETCH_STATUS_VALUE=""
VENDOR_STATUS_PREFETCH_PIDS=()

case "$GITHUB_API_CACHE_TTL_SECONDS" in
    ''|*[!0-9]*) GITHUB_API_CACHE_TTL_SECONDS=300 ;;
esac

case "$VENDOR_STATUS_PREFETCH_CONCURRENCY" in
    ''|*[!0-9]*|0) VENDOR_STATUS_PREFETCH_CONCURRENCY=4 ;;
esac

mkdir -p "$GITHUB_API_CACHE_DIR" 2>/dev/null || true

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

CHECK_ONLY=false
RELEASE_CHECK=false
FORCE=false
TARGET=""  # empty = all vendors

for arg in "$@"; do
    case "$arg" in
        --check)  CHECK_ONLY=true ;;
        --release) RELEASE_CHECK=true ;;
        --force)  FORCE=true ;;
        ffmpeg)   echo "NOTE: ffmpeg removed — video previews use native yen-vidthumb now"; exit 0 ;;
        7zip|sevenzip) echo "NOTE: 7zip removed — archive preview/extract now use native bsdtar"; exit 0 ;;
        --help|-h)
            echo ""
            echo "Usage: ./scripts/14-vendor.sh [vendor] [options]"
            echo ""
            echo "Vendors:"
            # Generated from the manifest. The hand-maintained list this
            # replaced had already drifted: fd and btop are source-built, not
            # binary vendors, but were labelled "(binary vendor)".
            for help_key in $(vendor_manifest_keys); do
                printf '  %-10s %s (%s)\n' \
                    "$help_key" \
                    "$(vendor_manifest_field "$help_key" subtitle)" \
                    "$(vendor_manifest_field "$help_key" type)"
            done
            echo "  (ffmpeg removed — video previews use native yen-vidthumb)"
            echo "  (7zip removed — archive preview/extract use native bsdtar)"
            echo ""
            echo "Options:"
            echo "  --check    Check for updates only (no downloads)"
            echo "  --release  With --check: accept a Ghostty baseline that a vendor: commit pushed"
            echo "             within the ${RELEASE_VENDOR_WINDOW_HOURS}h release window (scripts/lib/release-vendor-window.sh)"
            echo "  --force    Force re-download even if current"
            echo "  --help     Show this help"
            echo ""
            echo "Environment:"
            echo "  GITHUB_TOKEN   Optional GitHub token for authenticated API requests (avoids rate limits)"
            echo "  YEN_GITHUB_API_CACHE_TTL_SECONDS=<n>     Override GitHub API cache TTL (default: 300)"
            echo "  YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1  Temporary integrity bypass (writes audit log)"
            echo "  YEN_VENDOR_INTEGRITY_BYPASS_REASON='...' Optional reason captured in audit log entries"
            echo "  YEN_VENDOR_INTEGRITY_AUDIT_LOG=<path>    Optional override for audit log path"
            echo "  YEN_VENDOR_STATUS_PREFETCH_CONCURRENCY=<n>  Override parallel status prefetch width (default: 4)"
            echo ""
            echo "Examples:"
            echo "  ./scripts/14-vendor.sh              # Check + update all"
            echo "  ./scripts/14-vendor.sh --check      # Check only"
            echo "  GITHUB_TOKEN=ghp_xxx ./scripts/14-vendor.sh --check"
            echo "  ./scripts/14-vendor.sh lazygit      # Update lazygit only"
            echo "  ./scripts/14-vendor.sh delta        # Update delta only"
            echo "  ./scripts/14-vendor.sh btop         # Update btop only"
            echo "  ./scripts/14-vendor.sh zmx          # Rebuild zmx against the vendored engine"
            echo "  ./scripts/14-vendor.sh fastfetch    # Update fastfetch only"
            echo "  ./scripts/14-vendor.sh resvg        # Update resvg only"
            echo "  ./scripts/14-vendor.sh yazi --force  # Force update Yazi"
            echo ""
            exit 0
            ;;
        *)
            # Any manifest key selects that vendor; everything else is an error.
            if vendor_manifest_has "$arg"; then
                TARGET="$arg"
            else
                echo "ERROR: Unknown argument: $arg"
                echo "Run ./scripts/14-vendor.sh --help for usage"
                exit 1
            fi
            ;;
    esac
done

# --release is a reading of the check, so it needs the check.
if [ "$RELEASE_CHECK" = true ] && [ "$CHECK_ONLY" != true ]; then
    echo "ERROR: --release requires --check; it changes how a Ghostty 'behind' is read, never what is downloaded."
    exit 1
fi

# --force is honoured by the binary vendors only. The Ghostty block keys off
# "upstream is ahead" and never reads FORCE, so `14-vendor.sh ghostty --force`
# printed "Mode: Force update" and then did nothing — the one combination where
# the announced mode was a lie. Re-materializing a pinned tree is a different
# operation with its own entry point, so point at it instead of pretending.
if [ "$FORCE" = true ] && [ "$TARGET" = "ghostty" ]; then
    echo "ERROR: --force is not supported for the ghostty source vendor."
    echo "  It only applies to binary vendors (re-download at the current tag)."
    echo "  To re-materialize the pinned tree, run the updater directly:"
    echo "    ./scripts/10-update-ghostty.sh \$(grep '^upstream_commit=' yen-terminal/.ghostty-baseline | cut -d= -f2)"
    exit 1
fi

LOCK_KEY=$(printf '%s\n' "$REPO_ROOT" | cksum | awk '{print $1}')
VENDOR_LOCK_DIR="${TMPDIR:-/tmp}/yen-vendor-${LOCK_KEY}.lock"
VENDOR_LOCK_ACQUIRED=false

release_vendor_lock() {
    release_shared_workflow_lock
    if [ -n "$VENDOR_STATUS_PREFETCH_DIR" ] && [ -d "$VENDOR_STATUS_PREFETCH_DIR" ]; then
        rm -rf "$VENDOR_STATUS_PREFETCH_DIR"
    fi
    if [ "$VENDOR_LOCK_ACQUIRED" = true ] && [ -d "$VENDOR_LOCK_DIR" ]; then
        rm -rf "$VENDOR_LOCK_DIR"
    fi
}

acquire_vendor_lock() {
    acquire_yen_process_lock \
        "$VENDOR_LOCK_DIR" \
        VENDOR_LOCK_ACQUIRED \
        "14-vendor.sh" \
        "ERROR: Another vendor run is in progress (pid {pid})
Wait for it to finish before starting a new /update-yen vendor phase or vendor gate." \
        "ERROR: Vendor lock exists without a PID file: $VENDOR_LOCK_DIR
If no vendor process is running, remove the stale lock and retry." \
        "ERROR: Could not acquire vendor lock: $VENDOR_LOCK_DIR" || exit 1
}

gate_begin 14-vendor release_vendor_lock
acquire_shared_workflow_lock "vendor" || exit 1
acquire_vendor_lock

echo ""
echo "============================================"
echo "  Vendor All"
echo "============================================"
echo ""

if [ "$CHECK_ONLY" = true ]; then
    FORCE=false  # --force is meaningless in check-only mode
    echo "  Mode: Check only (no downloads)"
    if [ "$RELEASE_CHECK" = true ]; then
        echo "  Release window: a Ghostty baseline pushed by a vendor: commit within ${RELEASE_VENDOR_WINDOW_HOURS}h is accepted"
    fi
elif [ "$FORCE" = true ]; then
    echo "  Mode: Force update"
else
    echo "  Mode: Check + update"
fi

if [ -n "$TARGET" ]; then
    echo "  Target: $TARGET"
else
    echo "  Target: All vendors"
fi

VENDOR_COUNT=0
UPDATE_COUNT=0
CURRENT_COUNT=0
ERROR_COUNT=0
BEHIND_COUNT=0
UNKNOWN_COUNT=0

# "We could not determine the status" is its own outcome. It used to be folded
# into CURRENT_COUNT in update mode, so a rate-limited or token-expired run
# printed "Up to date: 13 / Errors: 0" and exited 0 while verifying nothing —
# a silent freeze that gets likelier as vendor cadence rises. --check already
# routed unknown into BEHIND_COUNT (correct), which is why the release path was
# never affected; this makes a bare run behave the same way.
record_unknown_status() {
    UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    if [ "$CHECK_ONLY" = true ]; then
        BEHIND_COUNT=$((BEHIND_COUNT + 1))
    fi
}

LATEST_TAG_HTTP_CODE=""
LATEST_TAG_VALUE=""
GHOSTTY_BEHIND_COMMITS=""
RELEASE_WINDOW_UNIT_RAN=""
RELEASE_WINDOW_UNIT_SKIPPED="not a release check (--release absent)"

print_vendor_header() {
    local index="$1"
    local title="$2"
    local subtitle="$3"

    echo ""
    echo "--------------------------------------------"
    echo "  [$index] $title — $subtitle"
    echo "--------------------------------------------"
}


# Check the incoming immutable source pin before downloading the archive.
preflight_check_zig_version() {
    local target_commit="$1"
    local zon_file
    zon_file="$(mktemp)" || return 1
    if ! upstream_file_content "$target_commit" build.zig.zon > "$zon_file"; then
        rm -f "$zon_file"
        echo "  ! Cannot read the incoming Ghostty toolchain pin"
        return 1
    fi
    if [ -z "$(zig_toolchain_required_version "$zon_file")" ]; then
        rm -f "$zon_file"
        echo "  ! Incoming Ghostty toolchain pin is missing"
        return 1
    fi
    local status=0
    zig_toolchain_check "$zon_file" || status=$?
    rm -f "$zon_file"
    if [ "$status" = 0 ] && [ -z "$ZIG_TOOLCHAIN_HAVE" ]; then
        echo "  ! Cannot determine the local Zig version"
        return 1
    fi
    case "$status" in
        0) return 0 ;;
        2)
            echo "  WARNING: zig not found on PATH — Ghostty requires $ZIG_TOOLCHAIN_REQUIRED"
            echo "  Recovery: $(zig_toolchain_recovery_command "$ZIG_TOOLCHAIN_REQUIRED")"
            return 1
            ;;
    esac
    echo "  WARNING: local zig is $ZIG_TOOLCHAIN_HAVE, but Ghostty requires exactly $ZIG_TOOLCHAIN_REQUIRED"
    echo "  Recovery: $(zig_toolchain_recovery_command "$ZIG_TOOLCHAIN_REQUIRED")"
    echo "  Override: set YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT=1 to bypass"
    return 1
}

# Check the documented rollback ledger for commit ranges that overlap the
# current compare range (`current_commit...main`). In `--check` mode this
# surfaces a warning only; in update mode it blocks unless explicitly bypassed.
preflight_check_rollback_history() {
    local current_commit="$1"
    local audit_file="$REPO_ROOT/_docs/04-security.md"

    [ -f "$audit_file" ] || return 0
    command -v git >/dev/null 2>&1 || return 0

    github_api_get "$(upstream_compare_url "$current_commit" main)"
    [ "$GITHUB_API_RESPONSE_HTTP_CODE" = "200" ] || return 0

    # The compare body embeds every file patch, so a wide range overflows
    # ARG_MAX when passed through the environment. Hand it over as a file.
    local body_file
    body_file=$(mktemp "${TMPDIR:-/tmp}/yen-vendor-compare.XXXXXX") || {
        echo "  WARNING: Rollback-history check failed (no temp file); ledger not checked"
        if [ "${YEN_VENDOR_BLOCK_ON_ROLLBACK:-}" = "1" ]; then
            return 1
        fi
        return 0
    }
    printf '%s' "$GITHUB_API_RESPONSE_BODY" > "$body_file"

    local rollback_hits
    local rollback_status=0
    rollback_hits=$(python3 - "$audit_file" "$body_file" <<'PY'
import json
import pathlib
import re
import sys

audit_path = pathlib.Path(sys.argv[1])
audit_text = audit_path.read_text(encoding="utf-8")
payload = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8") or "{}")
commits = [entry.get("sha", "") for entry in payload.get("commits", [])]
row_re = re.compile(
    r'^\|\s*`([^`]+)`\s*\|\s*([^|]+)\|\s*Ghostty\s*\|\s*`([0-9a-f]+)\.\.([0-9a-f]+)`[^|]*\|\s*(.*?)\s*\|\s*$',
    re.MULTILINE,
)

matches = []
for rollback_commit, date, start, end, reason in row_re.findall(audit_text):
    if any(sha.startswith(start) or sha.startswith(end) for sha in commits):
        matches.append(f"{rollback_commit}\t{start}..{end}\t{reason.strip()}")

print("\n".join(matches))
PY
) || rollback_status=$?
    rm -f "$body_file"

    if [ "$rollback_status" -ne 0 ]; then
        echo "  WARNING: Rollback-history check failed (python3 exit $rollback_status); ledger not checked"
        if [ "${YEN_VENDOR_BLOCK_ON_ROLLBACK:-}" = "1" ]; then
            return 1
        fi
        return 0
    fi

    if [ -n "$rollback_hits" ]; then
        echo ""
        echo "  WARNING: Re-landing a previously-reverted Ghostty range."
        while IFS=$'\t' read -r rollback_commit rollback_range rollback_reason; do
            [ -n "$rollback_commit" ] || continue
            echo "    Rollback commit: $rollback_commit"
            echo "    Range: $rollback_range"
            echo "    Reason: $rollback_reason"
        done <<EOF
$rollback_hits
EOF
        echo "    See _docs/04-security.md → Ghostty Rollback History"
        echo "    This is INFORMATIONAL — the ledger records what was bad at rollback time, not what is bad now."
        echo "    Today's range may include the upstream fix. Audit Step 3 will catch regressions that survived."
        echo "    Hard-block: set YEN_VENDOR_BLOCK_ON_ROLLBACK=1 to turn this warning into a stop."
        echo ""
        if [ "${YEN_VENDOR_BLOCK_ON_ROLLBACK:-}" = "1" ]; then
            return 1
        fi
    fi
    return 0
}

is_valid_sha256() {
    local value="$1"
    echo "$value" | grep -Eq '^[0-9a-f]{64}$'
}

is_unsigned_integer() {
    echo "$1" | grep -Eq '^[0-9]+$'
}

github_api_cache_path() {
    local url="$1"
    local auth_scope="anon"

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        auth_scope="auth"
    fi

    echo "$GITHUB_API_CACHE_DIR/$(printf '%s\n' "${auth_scope}|${url}" | cksum | awk '{print $1}').cache"
}

write_github_api_cache() {
    local url="$1"
    local http_code="$2"
    local body="$3"
    local cache_file
    local tmp_file

    cache_file=$(github_api_cache_path "$url")
    mkdir -p "$GITHUB_API_CACHE_DIR" 2>/dev/null || return 0
    tmp_file=$(mktemp "$GITHUB_API_CACHE_DIR/.github-api-cache.XXXXXX" 2>/dev/null) || return 0

    {
        date +%s
        printf '%s\n' "$http_code"
        printf '%s' "$body"
    } > "$tmp_file"

    mv "$tmp_file" "$cache_file" 2>/dev/null || rm -f "$tmp_file"
}

read_github_api_cache() {
    local url="$1"
    local cache_file
    local cached_at
    local http_code
    local now

    cache_file=$(github_api_cache_path "$url")
    [ -f "$cache_file" ] || return 1

    cached_at=$(sed -n '1p' "$cache_file" 2>/dev/null || echo "")
    http_code=$(sed -n '2p' "$cache_file" 2>/dev/null || echo "")

    if ! is_unsigned_integer "$cached_at"; then
        return 1
    fi

    now=$(date +%s)
    if ! is_unsigned_integer "$now"; then
        return 1
    fi

    if [ $((now - cached_at)) -ge "$GITHUB_API_CACHE_TTL_SECONDS" ]; then
        return 1
    fi

    GITHUB_API_RESPONSE_HTTP_CODE="$http_code"
    GITHUB_API_RESPONSE_BODY=$(sed '1,2d' "$cache_file" 2>/dev/null || true)
    return 0
}

github_api_get() {
    local url="$1"
    local response
    local -a curl_headers

    GITHUB_API_RESPONSE_HTTP_CODE=""
    GITHUB_API_RESPONSE_BODY=""

    if read_github_api_cache "$url"; then
        return 0
    fi

    curl_headers=(-H "Accept: application/vnd.github+json")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    response=$(curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -s -w "\n%{http_code}" \
        "${curl_headers[@]}" \
        "$url" 2>/dev/null || echo "")

    GITHUB_API_RESPONSE_HTTP_CODE=$(echo "$response" | tail -1)
    GITHUB_API_RESPONSE_BODY=$(echo "$response" | sed '$d')

    if [ "$GITHUB_API_RESPONSE_HTTP_CODE" = "200" ]; then
        write_github_api_cache "$url" "$GITHUB_API_RESPONSE_HTTP_CODE" "$GITHUB_API_RESPONSE_BODY"
    fi
}

validate_binary_vendor_provenance_metadata() {
    local key="$1"
    local baseline_file="$2"
    local binary_path="$3"
    local companion_path="$4"
    local require_companion="$5"
    local expected_output_sha
    local actual_output_sha
    local expected_companion_sha
    local actual_companion_sha
    local provenance_method
    local source_sha_arm64
    local source_sha_x86_64
    local api_sha_arm64
    local api_sha_x86_64
    local source_commit

    if [ ! -f "$baseline_file" ]; then
        return 0
    fi

    provenance_method=$(baseline_value "provenance_verification" "$baseline_file")
    case "$provenance_method" in
        github-release-asset-digests)
            source_sha_arm64=$(baseline_value "source_sha256_arm64" "$baseline_file")
            source_sha_x86_64=$(baseline_value "source_sha256_x86_64" "$baseline_file")
            api_sha_arm64=$(baseline_value "source_api_sha256_arm64" "$baseline_file")
            api_sha_x86_64=$(baseline_value "source_api_sha256_x86_64" "$baseline_file")
            if ! is_valid_sha256 "$api_sha_arm64" || ! is_valid_sha256 "$api_sha_x86_64" || \
               [ "$api_sha_arm64" != "$source_sha_arm64" ] || [ "$api_sha_x86_64" != "$source_sha_x86_64" ]; then
                echo "  ! GitHub release-asset digest metadata is missing or mismatched"
                return 1
            fi
            ;;
        github-commit-bound-archive)
            source_commit=$(baseline_value "source_commit" "$baseline_file")
            if ! echo "$source_commit" | grep -Eq '^[0-9a-f]{40}$'; then
                echo "  ! Immutable source commit metadata is missing or invalid"
                return 1
            fi
            ;;
    esac

    expected_output_sha=$(baseline_value "output_sha256" "$baseline_file")
    if ! is_valid_sha256 "$expected_output_sha"; then
        echo "  ! Baseline provenance metadata missing/invalid: output_sha256"
        return 1
    fi

    if [ ! -f "$binary_path" ]; then
        echo "  ! Vendored binary missing while validating provenance digest: $binary_path"
        return 1
    fi

    actual_output_sha=$(shasum -a 256 "$binary_path" | awk '{print $1}')
    if [ "$actual_output_sha" != "$expected_output_sha" ]; then
        echo "  ! Baseline provenance digest mismatch for $key"
        echo "    expected output_sha256: $expected_output_sha"
        echo "    actual output_sha256:   $actual_output_sha"
        return 1
    fi

    if [ "$require_companion" = true ]; then
        expected_companion_sha=$(baseline_value "companion_output_sha256" "$baseline_file")
        if ! is_valid_sha256 "$expected_companion_sha"; then
            echo "  ! Baseline provenance metadata missing/invalid: companion_output_sha256"
            return 1
        fi
        if [ ! -f "$companion_path" ]; then
            echo "  ! Required companion missing while validating provenance digest: $companion_path"
            return 1
        fi
        actual_companion_sha=$(shasum -a 256 "$companion_path" | awk '{print $1}')
        if [ "$actual_companion_sha" != "$expected_companion_sha" ]; then
            echo "  ! Baseline companion provenance digest mismatch for $key"
            echo "    expected companion_output_sha256: $expected_companion_sha"
            echo "    actual companion_output_sha256:   $actual_companion_sha"
            return 1
        fi
    fi

    return 0
}

validate_ghostty_provenance_metadata() {
    local baseline_file="$1"
    local source_archive_sha
    source_archive_sha=$(baseline_value "source_archive_sha256" "$baseline_file")
    if ! is_valid_sha256 "$source_archive_sha"; then
        echo "  ! Baseline provenance metadata missing/invalid: source_archive_sha256"
        return 1
    fi
    if [ "$(baseline_value "provenance_verification" "$baseline_file")" != "github-verified-commit" ]; then
        echo "  ! Ghostty baseline lacks verified forge commit provenance"
        return 1
    fi
    return 0
}

fetch_latest_tag() {
    local repo="$1"
    local require_assets="${2:-false}"
    local url
    local http_code
    local body

    LATEST_TAG_HTTP_CODE=""
    LATEST_TAG_VALUE=""

    url="https://api.github.com/repos/$repo/releases/latest"
    github_api_get "$url"
    http_code="$GITHUB_API_RESPONSE_HTTP_CODE"
    body="$GITHUB_API_RESPONSE_BODY"

    LATEST_TAG_HTTP_CODE="$http_code"

    if [ "$http_code" != "200" ]; then
        return 0
    fi

    if [ "$require_assets" = true ]; then
        local latest_asset_count
        latest_asset_count=$(echo "$body" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('assets', [])))" 2>/dev/null || echo "0")
        if [ "${latest_asset_count:-0}" -eq 0 ]; then
            local releases_http_code
            local releases_body
            github_api_get "https://api.github.com/repos/$repo/releases?per_page=5"
            releases_http_code="$GITHUB_API_RESPONSE_HTTP_CODE"
            releases_body="$GITHUB_API_RESPONSE_BODY"

            if [ "$releases_http_code" = "200" ]; then
                LATEST_TAG_VALUE=$(echo "$releases_body" | python3 -c "import json,sys
releases=json.load(sys.stdin)
for release in releases:
    if release.get('assets') and release.get('tag_name'):
        print(release.get('tag_name'))
        break
" 2>/dev/null || echo "")
                if [ -n "$LATEST_TAG_VALUE" ]; then
                    return 0
                fi
            fi
        fi
    fi

    LATEST_TAG_VALUE=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))")
}

vendor_status_prefetch_path() {
    local key="$1"
    [ -n "$VENDOR_STATUS_PREFETCH_DIR" ] || return 1
    echo "$VENDOR_STATUS_PREFETCH_DIR/$key.prefetch"
}

write_vendor_status_prefetch() {
    local key="$1"
    local http_code="$2"
    local value="$3"
    local prefetch_file
    local tmp_file

    prefetch_file=$(vendor_status_prefetch_path "$key") || return 0
    tmp_file=$(mktemp "$VENDOR_STATUS_PREFETCH_DIR/${key}.XXXXXX" 2>/dev/null) || return 0

    {
        printf '%s\n' "$http_code"
        printf '%s\n' "$value"
    } > "$tmp_file"

    mv "$tmp_file" "$prefetch_file" 2>/dev/null || rm -f "$tmp_file"
}

load_vendor_status_prefetch() {
    local key="$1"
    local prefetch_file

    PREFETCH_STATUS_HTTP_CODE=""
    PREFETCH_STATUS_VALUE=""

    prefetch_file=$(vendor_status_prefetch_path "$key") || return 1
    [ -f "$prefetch_file" ] || return 1

    PREFETCH_STATUS_HTTP_CODE=$(sed -n '1p' "$prefetch_file" 2>/dev/null || echo "")
    PREFETCH_STATUS_VALUE=$(sed -n '2p' "$prefetch_file" 2>/dev/null || echo "")
    return 0
}

prefetch_binary_latest_tag() {
    local key="$1"
    local repo="$2"

    fetch_latest_tag "$repo" "true"
    write_vendor_status_prefetch "$key" "$LATEST_TAG_HTTP_CODE" "$LATEST_TAG_VALUE"
}

prefetch_ghostty_compare_status() {
    local commit="$1"
    local api_url
    local http_code
    local commits=""

    [ -n "$commit" ] || return 0

    api_url="$(upstream_compare_url "$commit" main)"
    github_api_get "$api_url"
    http_code="$GITHUB_API_RESPONSE_HTTP_CODE"

    if [ "$http_code" = "200" ]; then
        commits=$(echo "$GITHUB_API_RESPONSE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); tc=d.get('total_commits'); print(tc if tc is not None else 'PARSE_ERROR')" 2>/dev/null || echo "PARSE_ERROR")
    fi

    write_vendor_status_prefetch "ghostty" "$http_code" "$commits"
}

wait_for_prefetch_batch() {
    local pid

    [ "${#VENDOR_STATUS_PREFETCH_PIDS[@]}" -gt 0 ] || return 0

    set +e
    for pid in "${VENDOR_STATUS_PREFETCH_PIDS[@]}"; do
        wait "$pid" >/dev/null 2>&1
    done
    set -e

    VENDOR_STATUS_PREFETCH_PIDS=()
}

queue_status_prefetch() {
    "$@" &
    VENDOR_STATUS_PREFETCH_PIDS[${#VENDOR_STATUS_PREFETCH_PIDS[@]}]=$!

    if [ "${#VENDOR_STATUS_PREFETCH_PIDS[@]}" -ge "$VENDOR_STATUS_PREFETCH_CONCURRENCY" ]; then
        wait_for_prefetch_batch
    fi
}

start_vendor_status_prefetches() {
    local ghostty_baseline
    local ghostty_commit

    VENDOR_STATUS_PREFETCH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yen-vendor-status.XXXXXX" 2>/dev/null || echo "")
    [ -n "$VENDOR_STATUS_PREFETCH_DIR" ] || return 0

    if [ -z "$TARGET" ] || [ "$TARGET" = "ghostty" ]; then
        ghostty_baseline="$REPO_ROOT/yen-terminal/.ghostty-baseline"
        if [ -f "$ghostty_baseline" ]; then
            ghostty_commit=$(baseline_value "upstream_commit" "$ghostty_baseline")
            [ -n "$ghostty_commit" ] && queue_status_prefetch prefetch_ghostty_compare_status "$ghostty_commit"
        fi
    fi

    # Every non-source vendor, from the manifest. This replaced twelve
    # hand-written per-vendor blocks; a vendor missing from that list fell back
    # to a synchronous fetch with no warning, so the omission cost latency and
    # said nothing.
    for prefetch_key in $(vendor_manifest_keys); do
        [ "$(vendor_manifest_field "$prefetch_key" type)" != "source" ] || continue
        if [ -z "$TARGET" ] || [ "$TARGET" = "$prefetch_key" ]; then
            queue_status_prefetch prefetch_binary_latest_tag \
                "$prefetch_key" \
                "$(vendor_manifest_field "$prefetch_key" repo)"
        fi
    done

    wait_for_prefetch_batch
}

run_vendor_script() {
    local script_path="$1"
    local latest_tag="${2:-}"
    local vendor_output
    local vendor_status

    set +e
    if [ "$FORCE" = true ]; then
        if [ -n "$latest_tag" ]; then
            vendor_output=$(VENDOR_LATEST_TAG="$latest_tag" "$script_path" --force 2>&1)
        else
            vendor_output=$("$script_path" --force 2>&1)
        fi
        vendor_status=$?
    else
        if [ -n "$latest_tag" ]; then
            vendor_output=$(VENDOR_LATEST_TAG="$latest_tag" "$script_path" 2>&1)
        else
            vendor_output=$("$script_path" 2>&1)
        fi
        vendor_status=$?
    fi
    set -e

    echo "$vendor_output"

    if [ $vendor_status -ne 0 ]; then
        return 1
    fi
    return 0
}

handle_latest_tag_unavailable() {
    if [ "$LATEST_TAG_HTTP_CODE" = "403" ]; then
        echo "  ? GitHub API rate limited — status unknown"
    elif [ -n "$LATEST_TAG_HTTP_CODE" ] && [ "$LATEST_TAG_HTTP_CODE" != "200" ]; then
        echo "  ? GitHub API returned $LATEST_TAG_HTTP_CODE — status unknown"
    else
        echo "  ? Could not fetch latest release — status unknown"
    fi

    record_unknown_status
}

is_universal_binary() {
    local binary_path="$1"

    if [ ! -f "$binary_path" ]; then
        return 1
    fi

    file "$binary_path" | grep -q "universal"
}

process_binary_vendor() {
    local index="$1"
    local key="$2"
    local title="$3"
    local subtitle="$4"
    local repo="$5"
    local baseline_file="$6"
    local version_file="$7"
    local binary_path="$8"
    local script_path="$9"
    local companion_path="${10:-}"
    local require_companion="${11:-false}"
    local latest_tag_override="${12:-}"
    local pinned_reason="${13:-}"

    if [ -n "$TARGET" ] && [ "$TARGET" != "$key" ]; then
        return
    fi

    VENDOR_COUNT=$((VENDOR_COUNT + 1))
    print_vendor_header "$index" "$title" "$subtitle"

    local current=""
    if [ -f "$baseline_file" ]; then
        if ! grep -q "^upstream_version=" "$baseline_file" 2>/dev/null; then
            echo "  ! Baseline file corrupted or malformed (missing upstream_version)"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            return
        fi
        current=$(baseline_value "upstream_version" "$baseline_file")
        local sync
        sync=$(baseline_value "last_sync" "$baseline_file")
        echo "  Current: $current (synced $sync)"
    elif [ -f "$version_file" ]; then
        current=$(cat "$version_file")
        echo "  Current: $current (no baseline file)"
    else
        echo "  ! Not vendored"
    fi

    if [ -n "$pinned_reason" ]; then
        echo "  Policy: $pinned_reason"
    fi

    local installed_version=""
    [ ! -f "$version_file" ] || installed_version="$(cat "$version_file")"
    local stale_version=false
    if [ -n "$installed_version" ] && [ -n "$current" ] && [ "$installed_version" != "$current" ]; then
        stale_version=true
    fi
    local requires_download=false
    if [ -z "$current" ] || [ ! -f "$binary_path" ] || [ "$stale_version" = true ]; then
        requires_download=true
    elif [ "$require_companion" = true ] && [ -n "$companion_path" ] && [ ! -f "$companion_path" ]; then
        requires_download=true
    fi

    if [ "$requires_download" = true ]; then
        if [ ! -f "$binary_path" ]; then
            echo "  Binary missing — download required"
        elif [ "$require_companion" = true ] && [ ! -f "$companion_path" ]; then
            echo "  Required companion missing — download required"
        elif [ "$stale_version" = true ]; then
            echo "  Installed version $installed_version differs from baseline $current — download required"
        else
            echo "  Version metadata missing — download required"
        fi

        if [ "$CHECK_ONLY" = true ]; then
            echo "  (skipping — check only mode)"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            return
        fi

        echo "  Downloading..."
        if run_vendor_script "$script_path" "$current"; then
            UPDATE_COUNT=$((UPDATE_COUNT + 1))
        else
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo "  ! Download failed"
        fi
        return
    fi

    if ! validate_binary_vendor_provenance_metadata \
        "$key" \
        "$baseline_file" \
        "$binary_path" \
        "$companion_path" \
        "$require_companion"; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return
    fi

    local latest="$latest_tag_override"
    if [ -z "$latest" ]; then
        if load_vendor_status_prefetch "$key"; then
            LATEST_TAG_HTTP_CODE="$PREFETCH_STATUS_HTTP_CODE"
            LATEST_TAG_VALUE="$PREFETCH_STATUS_VALUE"
        else
            fetch_latest_tag "$repo" "true"
        fi
        latest="$LATEST_TAG_VALUE"
    fi

    if [ -z "$latest" ]; then
        handle_latest_tag_unavailable
        return
    fi

    local update_reason=""
    if [ "$FORCE" = true ]; then
        update_reason="Force re-download: $current"
    elif [ "$latest" != "$current" ]; then
        update_reason="Update available: $current -> $latest"
    else
        local needs_rebuild=false
        local rebuild_reason="Rebuild required for local universal binaries"

        if [ "$key" = "lazygit" ]; then
            local lazygit_config="$REPO_ROOT/yen-terminal/customizations/lazygit/config.yml"
            if [ ! -f "$lazygit_config" ]; then
                echo "  ! Missing lazygit customization config: $lazygit_config"
                ERROR_COUNT=$((ERROR_COUNT + 1))
                return
            fi
        fi

        if ! is_universal_binary "$binary_path"; then
            echo "  Current version exists but binary is non-universal. Rebuilding..."
            needs_rebuild=true
        fi

        # A vendor built from more than its source tarball (zmx compiles the
        # vendored engine) records build_input_id; the tag alone cannot show
        # that an engine bump made the bundled binary stale.
        local recorded_input_id=""
        recorded_input_id=$(baseline_value "build_input_id" "$baseline_file" 2>/dev/null) || true
        if [ -n "$recorded_input_id" ]; then
            local current_input_id=""
            current_input_id=$("$script_path" --print-input-id 2>/dev/null) || current_input_id=""
            if [ -z "$current_input_id" ]; then
                echo "  ! Could not compute the current build inputs for $key"
                ERROR_COUNT=$((ERROR_COUNT + 1))
                return
            fi
            if [ "$current_input_id" != "$recorded_input_id" ]; then
                echo "  Build inputs changed ($recorded_input_id -> $current_input_id). Rebuilding..."
                needs_rebuild=true
                rebuild_reason="Rebuild required: build inputs changed"
            fi
        fi

        if [ -n "$companion_path" ]; then
            if [ -f "$companion_path" ]; then
                if ! is_universal_binary "$companion_path"; then
                    echo "  Current version exists but companion is non-universal. Rebuilding..."
                    needs_rebuild=true
                fi
            elif [ "$require_companion" = true ]; then
                echo "  Current version exists but required companion is missing. Rebuilding..."
                needs_rebuild=true
            fi
        fi

        if [ "$needs_rebuild" = false ]; then
            echo "  Current ($current)"
            CURRENT_COUNT=$((CURRENT_COUNT + 1))
            return
        fi

        update_reason="$rebuild_reason"
    fi

    echo "  $update_reason"

    if [ "$CHECK_ONLY" = true ]; then
        echo "  (skipping — check only mode)"
        BEHIND_COUNT=$((BEHIND_COUNT + 1))
        return
    fi

    echo "  Updating..."
    if run_vendor_script "$script_path" "$latest"; then
        UPDATE_COUNT=$((UPDATE_COUNT + 1))
        echo "  Updated successfully"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo "  ! Update failed"
    fi
}

# ============================================================================
# VENDOR: GHOSTTY (Source Vendor)
#
# Type: Source code (tar.gz download, full rebuild)
# Baseline: yen-terminal/.ghostty-baseline
# Script: scripts/10-update-ghostty.sh
# Check: scripts/08-check-upstream.sh
# ============================================================================

start_vendor_status_prefetches

if [ -z "$TARGET" ] || [ "$TARGET" = "ghostty" ]; then
    VENDOR_COUNT=$((VENDOR_COUNT + 1))
    print_vendor_header "1" "Ghostty" "Terminal Engine"

    GHOSTTY_BASELINE="$REPO_ROOT/yen-terminal/.ghostty-baseline"

    if [ ! -f "$GHOSTTY_BASELINE" ]; then
        echo "  ! .ghostty-baseline not found"
        echo "  Run: ./scripts/10-update-ghostty.sh main"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        GHOSTTY_COMMIT=$(baseline_value "upstream_commit" "$GHOSTTY_BASELINE")
        GHOSTTY_VERSION=$(baseline_value "upstream_version" "$GHOSTTY_BASELINE")
        GHOSTTY_SYNC=$(baseline_value "last_sync" "$GHOSTTY_BASELINE")
        echo "  Current: ${GHOSTTY_COMMIT:0:12} ($GHOSTTY_VERSION, synced $GHOSTTY_SYNC)"

        if ! validate_ghostty_provenance_metadata "$GHOSTTY_BASELINE"; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
        else
            COMMITS=""
            if load_vendor_status_prefetch "ghostty"; then
                HTTP_CODE="$PREFETCH_STATUS_HTTP_CODE"
                COMMITS="$PREFETCH_STATUS_VALUE"
            else
                github_api_get "$(upstream_compare_url "$GHOSTTY_COMMIT" main)"
                HTTP_CODE="$GITHUB_API_RESPONSE_HTTP_CODE"
                if [ "$HTTP_CODE" = "200" ]; then
                    COMMITS=$(echo "$GITHUB_API_RESPONSE_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); tc=d.get('total_commits'); print(tc if tc is not None else 'PARSE_ERROR')" || echo "PARSE_ERROR")
                fi
            fi

            if [ "$HTTP_CODE" = "403" ]; then
                echo "  ? GitHub API rate limited — status unknown"
                record_unknown_status
            elif [ "$HTTP_CODE" != "200" ]; then
                echo "  ? GitHub API returned $HTTP_CODE — status unknown"
                record_unknown_status
            elif [ "$COMMITS" = "PARSE_ERROR" ]; then
                echo "  ? GitHub API returned 200 but response missing total_commits — status unknown"
                record_unknown_status
            elif [ "$COMMITS" -gt 0 ] 2>/dev/null; then
                echo "  Update available: $COMMITS commits ahead"

                if [ "$CHECK_ONLY" = true ]; then
                    # Surface rollback-history warning even in --check mode.
                    preflight_check_rollback_history "$GHOSTTY_COMMIT" || true
                    echo "  (skipping — check only mode)"
                    BEHIND_COUNT=$((BEHIND_COUNT + 1))
                    GHOSTTY_BEHIND_COMMITS="$COMMITS"
                else
                    # Preflight gates (abort before download on toolchain/rollback issues).
                    GHOSTTY_PREFLIGHT_OK=true
                    GHOSTTY_TARGET_COMMIT="$(upstream_verified_commit_sha main || true)"
                    if ! [[ "$GHOSTTY_TARGET_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
                        echo "  ! Cannot resolve a verified incoming Ghostty commit"
                        ERROR_COUNT=$((ERROR_COUNT + 1))
                        GHOSTTY_PREFLIGHT_OK=false
                    fi
                    if [ "$GHOSTTY_PREFLIGHT_OK" = true ] && [ "${YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT:-}" != "1" ]; then
                        if ! preflight_check_zig_version "$GHOSTTY_TARGET_COMMIT"; then
                            echo "  ! Toolchain preflight failed — not downloading"
                            ERROR_COUNT=$((ERROR_COUNT + 1))
                            GHOSTTY_PREFLIGHT_OK=false
                        fi
                    fi
                    if [ "$GHOSTTY_PREFLIGHT_OK" = true ]; then
                        if ! preflight_check_rollback_history "$GHOSTTY_COMMIT"; then
                            echo "  ! Rollback-history check blocked update; see warning above"
                            ERROR_COUNT=$((ERROR_COUNT + 1))
                            GHOSTTY_PREFLIGHT_OK=false
                        fi
                    fi
                    if [ "$GHOSTTY_PREFLIGHT_OK" = true ]; then
                        echo "  Updating..."
                        if "$REPO_ROOT/scripts/10-update-ghostty.sh" "$GHOSTTY_TARGET_COMMIT"; then
                            UPDATE_COUNT=$((UPDATE_COUNT + 1))
                            echo "  Updated successfully"
                        else
                            ERROR_COUNT=$((ERROR_COUNT + 1))
                            echo "  ! Update failed"
                        fi
                    fi
                fi
            else
                echo "  Current (no upstream changes)"
                CURRENT_COUNT=$((CURRENT_COUNT + 1))
            fi
        fi
    fi
fi

# ============================================================================
# BINARY VENDORS (Shared handler)
# ============================================================================

# Every non-source vendor, in manifest order. Replaces twelve hand-written
# call sites that each passed nine to eleven positional arguments; the run
# index, baseline path, .version path, binary path and script path are all
# derived from the record, so adding a vendor is one manifest line.
for vendor_key in $(vendor_manifest_keys); do
    [ "$(vendor_manifest_field "$vendor_key" type)" != "source" ] || continue

    vendor_companion=""
    if vendor_companion_path "$REPO_ROOT" "$vendor_key" >/dev/null 2>&1; then
        vendor_companion="$(vendor_companion_path "$REPO_ROOT" "$vendor_key")"
    fi

    process_binary_vendor \
        "$(vendor_manifest_index "$vendor_key")" \
        "$vendor_key" \
        "$(vendor_manifest_field "$vendor_key" title)" \
        "$(vendor_manifest_field "$vendor_key" subtitle)" \
        "$(vendor_manifest_field "$vendor_key" repo)" \
        "$(vendor_baseline_path "$REPO_ROOT" "$vendor_key")" \
        "$(vendor_version_path "$REPO_ROOT" "$vendor_key")" \
        "$(vendor_binary_path "$REPO_ROOT" "$vendor_key")" \
        "$(vendor_script_path "$REPO_ROOT" "$vendor_key")" \
        "$vendor_companion" \
        "$(vendor_manifest_field "$vendor_key" require_companion)"
done

# Keep canonical vendor audit snapshot metadata aligned with baselines.
if [ "$CHECK_ONLY" = false ] && [ "$ERROR_COUNT" -eq 0 ]; then
    echo ""
    echo "--------------------------------------------"
    echo "  Vendor Audit Snapshot Metadata"
    echo "--------------------------------------------"
    if ! "$REPO_ROOT/scripts/11-sync-vendor-audit.sh"; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo "  ! Failed to sync _docs/04-security.md"
    fi
fi

# ============================================================================
# RELEASE WINDOW (--check --release)
# ============================================================================

# Ghostty tracks a moving branch, so a vendor phase that finishes after the
# next upstream commit reads as "behind" to a plain check. The release gate
# accepts that one case when the committed baseline is audited, recent and
# published; scripts/lib/release-vendor-window.sh owns the rule.
UPSTREAM_BEHIND_RAW="$BEHIND_COUNT"
if [ "$RELEASE_CHECK" = true ]; then
    if [ -z "$GHOSTTY_BEHIND_COMMITS" ]; then
        RELEASE_WINDOW_UNIT_SKIPPED="ghostty not behind; nothing to accept"
    elif release_vendor_window_accepts_ghostty "$REPO_ROOT"; then
        echo ""
        echo "--------------------------------------------"
        echo "  Release Window"
        echo "--------------------------------------------"
        echo "  Accepted: Ghostty is $GHOSTTY_BEHIND_COMMITS commit(s) behind upstream, and the committed baseline"
        echo "  was audited and pushed by the vendor phase inside the ${RELEASE_VENDOR_WINDOW_HOURS}h window ($RELEASE_VENDOR_WINDOW_EVIDENCE)."
        echo "  The release ships that baseline; the newer upstream commits wait for the next /update-yen vendor phase."
        BEHIND_COUNT=$((BEHIND_COUNT - 1))
        RELEASE_WINDOW_UNIT_RAN="accepted_behind_commits=$GHOSTTY_BEHIND_COMMITS $RELEASE_VENDOR_WINDOW_EVIDENCE"
    else
        echo ""
        echo "--------------------------------------------"
        echo "  Release Window"
        echo "--------------------------------------------"
        echo "  Refused: $RELEASE_VENDOR_WINDOW_REASON"
        RELEASE_WINDOW_UNIT_SKIPPED="refused: $RELEASE_VENDOR_WINDOW_REASON"
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo ""
echo "  Vendors checked: $VENDOR_COUNT"
echo "  Up to date:      $CURRENT_COUNT"
echo "  Updated:         $UPDATE_COUNT"
echo "  Behind:          $BEHIND_COUNT"
echo "  Unknown:         $UNKNOWN_COUNT"
echo "  Errors:          $ERROR_COUNT"
echo ""

if [ "${YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS:-0}" = "1" ]; then
    echo "  [WARNING] Integrity bypass was ACTIVE this run (YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1)."
    echo "            Downloads were accepted WITHOUT checksum/pin verification."
    echo "            Unset it now so it cannot silently weaken future runs:"
    echo "              unset YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS YEN_VENDOR_INTEGRITY_BYPASS_REASON"
    if [ -f "$REPO_ROOT/tmp/vendor-integrity-audit.log" ]; then
        echo "            Audit log (tmp/vendor-integrity-audit.log) last 3 entries:"
        tail -3 "$REPO_ROOT/tmp/vendor-integrity-audit.log" 2>/dev/null | sed 's/^/              /' || true
    fi
    echo ""
fi

# Provenance health — surface vendors whose baseline records an unverified /
# override pin (trust-on-first-use, no independent oracle) so they are visible
# and auditable instead of silently trusted forever. Informational, not a gate.
PROVENANCE_FLAGGED=""
for _bf in "$REPO_ROOT"/yen-terminal/.*-baseline; do
    [ -f "$_bf" ] || continue
    _pv=$(grep -h '^provenance_verification=' "$_bf" 2>/dev/null | cut -d= -f2-)
    case "$_pv" in
        override-*|*unverified*)
            PROVENANCE_FLAGGED="${PROVENANCE_FLAGGED}\n              $(basename "$_bf" | sed 's/^\.//; s/-baseline$//') = ${_pv}"
            ;;
    esac
done
if [ -n "$PROVENANCE_FLAGGED" ]; then
    echo "  [NOTE] Unverified / override-pinned vendors (no published-checksum oracle):"
    printf '%b\n' "$PROVENANCE_FLAGGED"
    echo "         These are trust-on-first-use. Re-verify against an upstream checksum/"
    echo "         attestation when one becomes available; treat the pinned digest as the"
    echo "         ground truth until then."
    echo ""
fi

# VENDOR_COUNT is the roster size from scripts/lib/vendor-manifest.sh. An empty
# roster would make every loop below a no-op and every count zero -- "nothing was
# checked" rendering as "nothing was wrong".
if [ "${VENDOR_COUNT:-0}" -eq 0 ]; then
    echo "  X Vendor roster is empty — nothing was checked."
    gate_unit_skipped roster "vendor manifest resolved zero vendors"
    gate_unit_skipped upstream-status "not reached: empty roster"
    gate_end 1
fi
gate_unit_ran roster "vendors=$VENDOR_COUNT"
gate_unit_ran upstream-status "current=$CURRENT_COUNT behind=$UPSTREAM_BEHIND_RAW unknown=$UNKNOWN_COUNT errors=$ERROR_COUNT"
if [ -n "$RELEASE_WINDOW_UNIT_RAN" ]; then
    gate_unit_ran release-window "$RELEASE_WINDOW_UNIT_RAN"
else
    gate_unit_skipped release-window "$RELEASE_WINDOW_UNIT_SKIPPED"
fi

if [ "$ERROR_COUNT" -gt 0 ]; then
    gate_end 1
fi

if [ "$BEHIND_COUNT" -gt 0 ]; then
    echo "  $BEHIND_COUNT vendor(s) behind or unknown. Run /update-yen; its vendor phase updates them."
    gate_end 1
fi

# Update mode: unknown status must not read as success. --check has already
# exited above via BEHIND_COUNT, so this only fires on a bare/update run.
if [ "$UNKNOWN_COUNT" -gt 0 ]; then
    if [ "${YEN_VENDOR_ALLOW_UNKNOWN_STATUS:-0}" = "1" ]; then
        echo "  [WARNING] $UNKNOWN_COUNT vendor(s) had UNKNOWN upstream status;"
        echo "            accepted via YEN_VENDOR_ALLOW_UNKNOWN_STATUS=1. Those vendors"
        echo "            were NOT verified against upstream this run."
    else
        echo "  $UNKNOWN_COUNT vendor(s) had UNKNOWN upstream status — nothing was verified"
        echo "  for them. Usually a rate limit or an expired token: check \`gh auth status\`,"
        echo "  then re-run. Override with YEN_VENDOR_ALLOW_UNKNOWN_STATUS=1."
        gate_end 1
    fi
fi

gate_end 0
