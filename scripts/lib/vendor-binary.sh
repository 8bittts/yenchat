#!/bin/bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vendor-manifest.sh"
# Shared Vendor Binary Library
#
# Provides vendor_binary() for downloading, verifying, and creating
# universal binaries from GitHub releases.
#
# Requires bash 3.x compatibility (macOS ships with bash 3.2).
#
# vendor_binary parameters (positional):
#   $1  DISPLAY_NAME                     e.g. "fd", "ripgrep"
#   $2  GITHUB_REPO                      e.g. "sharkdp/fd"
#   $3  BINARY_NAME                      default binary name
#   $4  VENDOR_SUBDIR                    e.g. "fd", "ripgrep"
#   $5  BASELINE_NAME                    e.g. ".fd-baseline"
#   $6  ASSET_ARM64_PATTERN              e.g. "fd-{VERSION}-aarch64-apple-darwin.tar.gz"
#   $7  ASSET_X86_64_PATTERN             e.g. "fd-{VERSION}-x86_64-apple-darwin.tar.gz"
#       Pass the same pattern for $6 and $7 when upstream ships one
#       pre-merged universal asset (fastfetch 2.70+): it is installed
#       directly instead of lipo-merged, and the lipo -archs gate below
#       still verifies both slices are present.
#   $8  FORCE                            true/false (optional, default false)
#   $9  MODE                             tar.gz|zip|direct (optional, default tar.gz)
#   $10 ARCHIVE_BINARY_NAME              binary name inside extracted assets (optional)
#   $11 OUTPUT_BINARY_NAME               output file name in vendor dir (optional)
#
# Companion binary (yazi's `ya`) is configured via environment variables set as
# prefix assignments on the vendor_binary call (scoped to that call only):
#   VENDOR_COMPANION_ARCHIVE_BINARY_NAME  optional companion binary inside assets
#   VENDOR_COMPANION_OUTPUT_BINARY_NAME   optional companion output file name
#       (defaults to VENDOR_COMPANION_ARCHIVE_BINARY_NAME)
#   VENDOR_REQUIRE_COMPANION              true/false (optional, default false)
#
# Pattern variables:
#   {VERSION} - Full tag (e.g. v10.2.0)
#   {VNUM}    - Tag without v prefix (e.g. 10.2.0)
#
# Environment:
#   GITHUB_TOKEN - Optional token for authenticated GitHub API release checks
#   VENDOR_LATEST_TAG - Optional latest release tag supplied by caller to skip API fetch
#   YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS - Set to 1 to temporarily bypass
#       provenance failures (writes audit log entry).
#   YEN_VENDOR_INTEGRITY_BYPASS_REASON - Optional freeform reason string
#       recorded in provenance audit logs.
#   YEN_VENDOR_INTEGRITY_AUDIT_LOG - Optional audit log path override.
#
# require_tool parameters (positional):
#   $1  TOOL_NAME   command that must be on PATH; prints ERROR and exits 1 if missing.
#
# vendor_source_build parameters (positional) — shared scaffolding for the
# source-compiled vendors (fd, btop, zmx) whose upstreams publish no
# x86_64 macOS release binaries. Downloads the tagged source tarball, runs the
# same fail-closed source-pin / output-pin / universal validation as
# vendor_binary, and delegates the actual compile to a caller-supplied callback:
#   $1  DISPLAY_NAME        e.g. "fd", "btop" (also the source dir prefix)
#   $2  GITHUB_REPO         e.g. "sharkdp/fd"
#   $3  VENDOR_SUBDIR       vendor dir under yen-terminal/customizations/vendor/
#   $4  BASELINE_NAME       e.g. ".fd-baseline"
#   $5  OUTPUT_BINARY_NAME  output file name written into the vendor dir
#   $6  BUILD_FN            name of the build callback function (see contract)
#   $7  FORCE               true/false (optional, default false)
#   $8  BUILD_METHOD        baseline build_method value; empty => that line omitted
#
# Optional environment for vendor_source_build:
#   VENDOR_BUILD_INPUT_ID  identity of build inputs beyond the source tarball
#       (zmx compiles YEN's vendored engine, so it passes the engine commit).
#       Recorded as build_input_id in the baseline. The output digest pin only
#       applies while the recorded id matches; a changed id forces a rebuild and
#       re-records the pin, because new inputs legitimately change the output.
#
# BUILD_FN contract: invoked as `"$BUILD_FN" "$SOURCE_DIR" "$TEMP_DIR"`. It must
# build both architectures and print EXACTLY two lines to STDOUT — line 1 the
# arm64 binary path, line 2 the x86_64 binary path — with ALL progress routed to
# STDERR (>&2). It must return non-zero on build failure. vendor_source_build
# then validates existence, per-arch `file` architecture, universal lipo output,
# the pinned output digest, and a --version/-v/-V/version liveness check before
# persisting .version and the baseline.

# shellcheck source=scripts/lib/version-utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version-utils.sh"

parse_force_flag() {
    if [ "$#" -eq 0 ]; then
        echo "false"
        return 0
    fi

    if [ "$#" -eq 1 ] && [ "$1" = "--force" ]; then
        echo "true"
        return 0
    fi

    echo "Usage: $(basename "$0") [--force]" >&2
    return 2
}


is_valid_sha256() {
    local value="$1"
    echo "$value" | grep -Eq '^[0-9a-f]{64}$'
}

# Fetch the latest published release tag for a GitHub repo. Previously copied
# byte-identical into the source-build scripts.
# Usage: LATEST_TAG="$(vendor_fetch_latest_release_tag "$GITHUB_REPO")" || exit 1
vendor_fetch_latest_release_tag() {
    local repo="$1"
    local -a curl_headers
    curl_headers=(-H "Accept: application/vnd.github+json")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    local response
    response=$(curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -s -w "\n%{http_code}" \
        "${curl_headers[@]}" \
        "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null || echo "")

    local http_code
    local body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        if [ "$http_code" = "403" ]; then
            echo "ERROR: GitHub API rate limited while fetching latest release"
        elif [ -n "$http_code" ]; then
            echo "ERROR: GitHub API returned HTTP $http_code while fetching latest release"
        else
            echo "ERROR: Could not reach GitHub API while fetching latest release"
        fi
        return 1
    fi

    echo "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name", ""))'
}

# Emit the upstream release date (YYYY-MM-DD) for a tag, or empty on failure.
vendor_release_published_date() {
    local repo="$1" tag="$2"
    local -a curl_headers
    curl_headers=(-H "Accept: application/vnd.github+json")
    [ -n "${GITHUB_TOKEN:-}" ] && curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl --retry 2 --retry-delay 1 --max-time 20 --connect-timeout 10 -sfL \
        "${curl_headers[@]}" "https://api.github.com/repos/$repo/releases/tags/$tag" 2>/dev/null \
      | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin).get("published_at",""); print(d[:10] if d else "")
except Exception: print("")'
}

# Return GitHub's provider-side SHA-256 digest for one named release asset.
vendor_release_asset_sha256() {
    local repo="$1" tag="$2" asset="$3"
    local -a curl_headers
    curl_headers=(-H "Accept: application/vnd.github+json")
    [ -n "${GITHUB_TOKEN:-}" ] && curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -sfL \
        "${curl_headers[@]}" "https://api.github.com/repos/$repo/releases/tags/$tag" 2>/dev/null \
      | python3 -c 'import json,sys
asset_name=sys.argv[1]
for item in json.load(sys.stdin).get("assets", []):
    if item.get("name") == asset_name:
        print((item.get("digest") or "").removeprefix("sha256:"))
        break' "$asset"
}

# Resolve a tag to the immutable commit which owns the downloaded source tree.
vendor_resolve_tag_commit() {
    local repo="$1" tag="$2"
    local -a curl_headers
    curl_headers=(-H "Accept: application/vnd.github+json")
    [ -n "${GITHUB_TOKEN:-}" ] && curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -sfL \
        "${curl_headers[@]}" "https://api.github.com/repos/$repo/commits/$tag" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha", ""))'
}

vendor_allow_unverified_downloads() {
    [ "${YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS:-0}" = "1" ]
}

vendor_integrity_audit_log_path() {
    local repo_root="$1"
    if [ -n "${YEN_VENDOR_INTEGRITY_AUDIT_LOG:-}" ]; then
        echo "$YEN_VENDOR_INTEGRITY_AUDIT_LOG"
    else
        echo "$repo_root/tmp/vendor-integrity-audit.log"
    fi
}

vendor_append_integrity_audit_log() {
    local repo_root="$1"
    local context="$2"
    local detail="$3"
    local reason="${YEN_VENDOR_INTEGRITY_BYPASS_REASON:-unspecified}"
    local log_path
    local log_dir
    local timestamp

    log_path="$(vendor_integrity_audit_log_path "$repo_root")"
    # Fail closed on a malformed audit-log path instead of mkdir -p'ing it. A
    # caller that captures another function's stdout into the path (or into
    # $repo_root) yields a multi-line, non-absolute string, and mkdir -p would
    # silently build that whole tree relative to the current directory.
    if [ -z "$log_path" ] || [ "$log_path" != "${log_path%%$'\n'*}" ]; then
        echo "  ERROR: Malformed integrity audit-log path (empty or multi-line)"
        return 1
    fi
    case "$log_path" in
        /*) ;;
        *)
            echo "  ERROR: Integrity audit-log path must be absolute: $log_path"
            return 1
            ;;
    esac
    log_dir="$(dirname "$log_path")"
    if ! mkdir -p "$log_dir"; then
        echo "  ERROR: Could not create integrity audit-log directory: $log_dir"
        return 1
    fi
    if ! timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ'); then
        echo "  ERROR: Could not timestamp integrity bypass audit entry"
        return 1
    fi

    if ! printf '%s|context=%s|reason=%s|detail=%s\n' \
        "$timestamp" "$context" "$reason" "$detail" >> "$log_path"; then
        echo "  ERROR: Could not append integrity bypass audit log: $log_path"
        return 1
    fi
    echo "  Audit log: $log_path"
}

vendor_fail_or_bypass_integrity() {
    local repo_root="$1"
    local context="$2"
    local detail="$3"

    if vendor_allow_unverified_downloads; then
        echo "  WARNING: Integrity gate bypassed via YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1"
        if ! vendor_append_integrity_audit_log "$repo_root" "$context" "$detail"; then
            echo "  ERROR: Refusing unaudited integrity-gate bypass"
            return 1
        fi
        return 0
    fi

    echo "  ERROR: Integrity verification failed: $detail"
    echo "  Set YEN_VENDOR_ALLOW_UNVERIFIED_DOWNLOADS=1 to bypass temporarily."
    echo "  Include YEN_VENDOR_INTEGRITY_BYPASS_REASON='<why>' for auditability."
    return 1
}

vendor_binary() {
    local DISPLAY_NAME="$1"
    local GITHUB_REPO="$2"
    local BINARY_NAME="$3"
    local VENDOR_SUBDIR="$4"
    local BASELINE_NAME="$5"
    local ASSET_ARM64_PATTERN="$6"
    local ASSET_X86_64_PATTERN="$7"
    local FORCE="${8:-false}"
    local MODE="${9:-tar.gz}"
    local ARCHIVE_BINARY_NAME="${10:-$BINARY_NAME}"
    local OUTPUT_BINARY_NAME="${11:-$BINARY_NAME}"
    local COMPANION_ARCHIVE_BINARY_NAME="${VENDOR_COMPANION_ARCHIVE_BINARY_NAME:-}"
    local COMPANION_OUTPUT_BINARY_NAME="${VENDOR_COMPANION_OUTPUT_BINARY_NAME:-$COMPANION_ARCHIVE_BINARY_NAME}"
    local REQUIRE_COMPANION="${VENDOR_REQUIRE_COMPANION:-false}"

    local REPO_ROOT
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    local VENDOR_DIR="$REPO_ROOT/yen-terminal/customizations/vendor/$VENDOR_SUBDIR"
    local VERSION_FILE="$VENDOR_DIR/.version"
    local BASELINE_FILE="$REPO_ROOT/yen-terminal/$BASELINE_NAME"

    echo ""
    echo "Vendor $DISPLAY_NAME (Universal Binary)"

    if [ "$MODE" != "tar.gz" ] && [ "$MODE" != "zip" ] && [ "$MODE" != "direct" ]; then
        echo "  ERROR: Unsupported mode '$MODE'"
        return 1
    fi

    local LATEST_TAG
    LATEST_TAG="${VENDOR_LATEST_TAG:-}"
    if [ -n "$LATEST_TAG" ]; then
        echo "  Latest release: $LATEST_TAG (provided by caller)"
    else
        # Fetch latest release tag
        echo "  Fetching latest release..."
        local RELEASE_RESPONSE
        local curl_headers
        curl_headers=(-H "Accept: application/vnd.github+json")
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            curl_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
        fi

        RELEASE_RESPONSE=$(curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -s -w "\n%{http_code}" \
            "${curl_headers[@]}" \
            "https://api.github.com/repos/$GITHUB_REPO/releases/latest" 2>/dev/null || echo "")

        local RELEASE_HTTP
        local RELEASE_BODY
        RELEASE_HTTP=$(echo "$RELEASE_RESPONSE" | tail -1)
        RELEASE_BODY=$(echo "$RELEASE_RESPONSE" | sed '$d')

        if [ "$RELEASE_HTTP" != "200" ]; then
            if [ "$RELEASE_HTTP" = "403" ]; then
                echo "  ERROR: GitHub API rate limited while fetching latest release"
            elif [ -n "$RELEASE_HTTP" ]; then
                echo "  ERROR: GitHub API returned HTTP $RELEASE_HTTP while fetching latest release"
            else
                echo "  ERROR: Could not reach GitHub API while fetching latest release"
            fi
            return 1
        fi

        LATEST_TAG=$(echo "$RELEASE_BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))")

        if [ -z "$LATEST_TAG" ]; then
            echo "  ERROR: Could not fetch latest release tag"
            return 1
        fi

        echo "  Latest release: $LATEST_TAG"
    fi

    # Skip-if-current check
    local CURRENT_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    fi

    local BASELINE_PIN_VERSION=""
    local BASELINE_PIN_ASSET_ARM64=""
    local BASELINE_PIN_ASSET_X86_64=""
    local BASELINE_PIN_SHA256_ARM64=""
    local BASELINE_PIN_SHA256_X86_64=""
    local BASELINE_PIN_OUTPUT_SHA256=""
    local BASELINE_PIN_COMPANION_SHA256=""
    if [ -f "$BASELINE_FILE" ]; then
        BASELINE_PIN_VERSION=$(baseline_value "upstream_version" "$BASELINE_FILE")
        BASELINE_PIN_ASSET_ARM64=$(baseline_value "source_asset_arm64" "$BASELINE_FILE")
        BASELINE_PIN_ASSET_X86_64=$(baseline_value "source_asset_x86_64" "$BASELINE_FILE")
        BASELINE_PIN_SHA256_ARM64=$(baseline_value "source_sha256_arm64" "$BASELINE_FILE")
        BASELINE_PIN_SHA256_X86_64=$(baseline_value "source_sha256_x86_64" "$BASELINE_FILE")
        BASELINE_PIN_OUTPUT_SHA256=$(baseline_value "output_sha256" "$BASELINE_FILE")
        BASELINE_PIN_COMPANION_SHA256=$(baseline_value "companion_output_sha256" "$BASELINE_FILE")
    fi

    local PRIMARY_OUTPUT_PATH="$VENDOR_DIR/$OUTPUT_BINARY_NAME"
    local COMPANION_OUTPUT_PATH=""
    if [ -n "$COMPANION_OUTPUT_BINARY_NAME" ]; then
        COMPANION_OUTPUT_PATH="$VENDOR_DIR/$COMPANION_OUTPUT_BINARY_NAME"
    fi

    if [ "$FORCE" = false ] && [ "$CURRENT_VERSION" = "$LATEST_TAG" ] && [ -f "$PRIMARY_OUTPUT_PATH" ]; then
        # lipo -archs is authoritative; `file | grep universal` also passes for an
        # arm64+arm64e fat binary that LACKS x86_64. Only treat as "already current
        # and universal" when both required arches are present (matches vendor_source_build).
        local PRIMARY_OUTPUT_ARCHS
        PRIMARY_OUTPUT_ARCHS=$(lipo -archs "$PRIMARY_OUTPUT_PATH" 2>/dev/null || echo "")
        if echo " $PRIMARY_OUTPUT_ARCHS " | grep -q " arm64 " && echo " $PRIMARY_OUTPUT_ARCHS " | grep -q " x86_64 "; then
            if [ -z "$COMPANION_OUTPUT_PATH" ]; then
                echo "  Already current ($CURRENT_VERSION) and universal. Use --force to re-download."
                echo ""
                echo "Done."
                return 0
            fi

            local COMPANION_OUTPUT_ARCHS
            COMPANION_OUTPUT_ARCHS=$(lipo -archs "$COMPANION_OUTPUT_PATH" 2>/dev/null || echo "")
            if [ -f "$COMPANION_OUTPUT_PATH" ] &&
                echo " $COMPANION_OUTPUT_ARCHS " | grep -q " arm64 " &&
                echo " $COMPANION_OUTPUT_ARCHS " | grep -q " x86_64 "; then
                echo "  Already current ($CURRENT_VERSION) and universal. Use --force to re-download."
                echo ""
                echo "Done."
                return 0
            fi

            echo "  Current version exists but companion is missing or non-universal. Rebuilding..."
        else
            echo "  Current version exists but is not universal. Rebuilding..."
        fi
    fi

    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_TAG" ]; then
        echo "  Updating: $CURRENT_VERSION -> $LATEST_TAG"
    fi

    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
        echo "  ERROR: Could not create temporary directory"
        return 1
    fi

    local PREV_EXIT_TRAP PREV_INT_TRAP PREV_TERM_TRAP
    PREV_EXIT_TRAP=$(trap -p EXIT || true)
    PREV_INT_TRAP=$(trap -p INT || true)
    PREV_TERM_TRAP=$(trap -p TERM || true)

    cleanup_vendor_binary_temp_dir() {
        if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
            rm -rf "$TEMP_DIR"
        fi
    }
    trap cleanup_vendor_binary_temp_dir EXIT INT TERM

    local STATUS=0

    while :; do
        local VERSION_NUM="${LATEST_TAG#v}"
        local ASSET_ARM64="${ASSET_ARM64_PATTERN//\{VERSION\}/$LATEST_TAG}"
        ASSET_ARM64="${ASSET_ARM64//\{VNUM\}/$VERSION_NUM}"
        local ASSET_X86_64="${ASSET_X86_64_PATTERN//\{VERSION\}/$LATEST_TAG}"
        ASSET_X86_64="${ASSET_X86_64//\{VNUM\}/$VERSION_NUM}"

        local ARM64_DOWNLOAD_PATH="$TEMP_DIR/$ASSET_ARM64"
        local X86_64_DOWNLOAD_PATH="$TEMP_DIR/$ASSET_X86_64"

        echo "  Downloading arm64..."
        local DOWNLOAD_URL_ARM64="https://github.com/$GITHUB_REPO/releases/download/$LATEST_TAG/$ASSET_ARM64"
        if ! curl --retry 3 --retry-delay 1 --max-time 120 --connect-timeout 10 -sfL -o "$ARM64_DOWNLOAD_PATH" "$DOWNLOAD_URL_ARM64"; then
            echo "  ERROR: arm64 download failed for asset: $ASSET_ARM64"
            echo "  URL: $DOWNLOAD_URL_ARM64"
            echo "  Hint: release assets may have been renamed or removed upstream"
            STATUS=1
            break
        fi

        echo "  Downloading x86_64..."
        local DOWNLOAD_URL_X86_64="https://github.com/$GITHUB_REPO/releases/download/$LATEST_TAG/$ASSET_X86_64"
        if ! curl --retry 3 --retry-delay 1 --max-time 120 --connect-timeout 10 -sfL -o "$X86_64_DOWNLOAD_PATH" "$DOWNLOAD_URL_X86_64"; then
            echo "  ERROR: x86_64 download failed for asset: $ASSET_X86_64"
            echo "  URL: $DOWNLOAD_URL_X86_64"
            echo "  Hint: release assets may have been renamed or removed upstream"
            STATUS=1
            break
        fi

        if [ ! -s "$ARM64_DOWNLOAD_PATH" ] || [ ! -s "$X86_64_DOWNLOAD_PATH" ]; then
            echo "  ERROR: Downloaded files are empty"
            STATUS=1
            break
        fi

        local ARM64_SHA256
        local X86_SHA256
        ARM64_SHA256=$(get_sha256 "$ARM64_DOWNLOAD_PATH")
        X86_SHA256=$(get_sha256 "$X86_64_DOWNLOAD_PATH")
        echo "  Computing SHA256 checksums..."
        echo "    arm64:  $ARM64_SHA256"
        echo "    x86_64: $X86_SHA256"

        local CHECKSUM_FILE=""
        local CHECKSUM_NAME=""
        local CHECKSUM_NAME_USED=""
        local CHECKSUM_FILE_SHA256=""
        local CHECKSUM_VERIFY_ERROR=""
        local CHECKSUM_TARGETS_FOUND=false
        local CHECKSUM_URL
        local PROVENANCE_VERIFIED=false
        local PROVENANCE_METHOD="none"
        local OUTPUT_VERIFICATION="verified"
        local INTEGRITY_CONTEXT="$DISPLAY_NAME:$LATEST_TAG"
        local INTEGRITY_DETAIL=""
        local API_SHA256_ARM64=""
        local API_SHA256_X86_64=""
        local CHECKSUM_CANDIDATES=(
            "checksums.txt"
            "SHA256SUMS"
            "sha256sums.txt"
            "sha256sum.txt"
            "${DISPLAY_NAME}-${LATEST_TAG}-checksums.txt"
            "${DISPLAY_NAME}-${VERSION_NUM}-checksums.txt"
            "${DISPLAY_NAME}_${LATEST_TAG}_checksums.txt"
            "${DISPLAY_NAME}_${VERSION_NUM}_checksums.txt"
        )
        for CHECKSUM_NAME in "${CHECKSUM_CANDIDATES[@]}"; do
            CHECKSUM_URL="https://github.com/$GITHUB_REPO/releases/download/$LATEST_TAG/$CHECKSUM_NAME"
            if curl --retry 2 --retry-delay 1 --max-time 10 --connect-timeout 5 -sfL "$CHECKSUM_URL" > "$TEMP_DIR/checksums.txt" 2>/dev/null; then
                CHECKSUM_FILE="$TEMP_DIR/checksums.txt"
                CHECKSUM_NAME_USED="$CHECKSUM_NAME"
                CHECKSUM_FILE_SHA256=$(get_sha256 "$CHECKSUM_FILE")
                echo "  Found published checksums: $CHECKSUM_NAME"
                break
            fi
        done

        API_SHA256_ARM64="$(vendor_release_asset_sha256 "$GITHUB_REPO" "$LATEST_TAG" "$ASSET_ARM64" || true)"
        API_SHA256_X86_64="$(vendor_release_asset_sha256 "$GITHUB_REPO" "$LATEST_TAG" "$ASSET_X86_64" || true)"
        if is_valid_sha256 "$API_SHA256_ARM64" && is_valid_sha256 "$API_SHA256_X86_64"; then
            if [ "$API_SHA256_ARM64" != "$ARM64_SHA256" ] || [ "$API_SHA256_X86_64" != "$X86_SHA256" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" "$INTEGRITY_CONTEXT" \
                    "GitHub release-asset digest mismatch"; then
                    STATUS=1
                    break
                fi
                PROVENANCE_VERIFIED=true
                PROVENANCE_METHOD="override-api-digest-mismatch"
            else
                PROVENANCE_VERIFIED=true
                PROVENANCE_METHOD="github-release-asset-digests"
                echo "  GitHub release-asset digest verification passed"
            fi
        fi

        if [ "$PROVENANCE_VERIFIED" != true ] && [ -n "$CHECKSUM_FILE" ]; then
            if grep -Fq "$ASSET_ARM64" "$CHECKSUM_FILE" && grep -Fq "$ASSET_X86_64" "$CHECKSUM_FILE"; then
                CHECKSUM_TARGETS_FOUND=true
                echo "  Verifying against published checksums..."
                awk -v arm64="$ASSET_ARM64" -v x86="$ASSET_X86_64" \
                    'index($0, arm64) > 0 || index($0, x86) > 0' \
                    "$CHECKSUM_FILE" > "$TEMP_DIR/verify.txt"
                if CHECKSUM_VERIFY_ERROR=$(cd "$TEMP_DIR" && shasum -a 256 -c "verify.txt" 2>&1); then
                    PROVENANCE_VERIFIED=true
                    PROVENANCE_METHOD="published-checksums:$CHECKSUM_NAME"
                    echo "$CHECKSUM_VERIFY_ERROR"
                    echo "  Checksum verification passed"
                else
                    echo "$CHECKSUM_VERIFY_ERROR"
                    CHECKSUM_VERIFY_ERROR=$(echo "$CHECKSUM_VERIFY_ERROR" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-200)
                fi
            else
                echo "  WARNING: Published checksum file found but missing one or both target assets"
            fi
        fi

        if [ "$PROVENANCE_VERIFIED" != true ]; then
            if [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ] && \
               [ "$BASELINE_PIN_ASSET_ARM64" = "$ASSET_ARM64" ] && \
               [ "$BASELINE_PIN_ASSET_X86_64" = "$ASSET_X86_64" ] && \
               is_valid_sha256 "$BASELINE_PIN_SHA256_ARM64" && \
               is_valid_sha256 "$BASELINE_PIN_SHA256_X86_64" && \
               [ "$BASELINE_PIN_SHA256_ARM64" = "$ARM64_SHA256" ] && \
               [ "$BASELINE_PIN_SHA256_X86_64" = "$X86_SHA256" ]; then
                PROVENANCE_VERIFIED=true
                PROVENANCE_METHOD="baseline-pinned"
                echo "  Baseline pinned digests matched"
            fi
        fi

        if [ "$PROVENANCE_VERIFIED" != true ]; then
            if [ -n "$CHECKSUM_FILE" ] && [ "$CHECKSUM_TARGETS_FOUND" = true ] && [ -n "$CHECKSUM_VERIFY_ERROR" ]; then
                INTEGRITY_DETAIL="published checksum mismatch ($CHECKSUM_VERIFY_ERROR)"
            elif [ -n "$CHECKSUM_FILE" ] && [ "$CHECKSUM_TARGETS_FOUND" != true ]; then
                INTEGRITY_DETAIL="published checksum file missing target assets (${CHECKSUM_NAME_USED:-unknown})"
            elif [ -n "$CHECKSUM_FILE" ]; then
                INTEGRITY_DETAIL="published checksum verification unavailable (${CHECKSUM_NAME_USED:-unknown})"
            elif [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ]; then
                INTEGRITY_DETAIL="baseline pinned digest metadata missing or mismatched for current version"
            else
                INTEGRITY_DETAIL="no published checksums and no pinned baseline digests for this version"
            fi

            if ! vendor_fail_or_bypass_integrity "$REPO_ROOT" "$INTEGRITY_CONTEXT" "$INTEGRITY_DETAIL"; then
                STATUS=1
                break
            fi
            PROVENANCE_METHOD="override-unverified"
        fi

        echo "  Extracting..."
        mkdir -p "$TEMP_DIR/arm64" "$TEMP_DIR/x86_64"

        if [ "$MODE" = "tar.gz" ]; then
            if ! tar -xzf "$ARM64_DOWNLOAD_PATH" -C "$TEMP_DIR/arm64"; then
                echo "  ERROR: Failed to extract arm64 archive"
                STATUS=1
                break
            fi
            if ! tar -xzf "$X86_64_DOWNLOAD_PATH" -C "$TEMP_DIR/x86_64"; then
                echo "  ERROR: Failed to extract x86_64 archive"
                STATUS=1
                break
            fi
        elif [ "$MODE" = "zip" ]; then
            if ! unzip -q -o "$ARM64_DOWNLOAD_PATH" -d "$TEMP_DIR/arm64"; then
                echo "  ERROR: Failed to extract arm64 zip"
                STATUS=1
                break
            fi
            if ! unzip -q -o "$X86_64_DOWNLOAD_PATH" -d "$TEMP_DIR/x86_64"; then
                echo "  ERROR: Failed to extract x86_64 zip"
                STATUS=1
                break
            fi
        else
            cp "$ARM64_DOWNLOAD_PATH" "$TEMP_DIR/arm64/$ARCHIVE_BINARY_NAME"
            cp "$X86_64_DOWNLOAD_PATH" "$TEMP_DIR/x86_64/$ARCHIVE_BINARY_NAME"
            chmod 755 "$TEMP_DIR/arm64/$ARCHIVE_BINARY_NAME" "$TEMP_DIR/x86_64/$ARCHIVE_BINARY_NAME"
        fi

        local PRIMARY_ARM64
        local PRIMARY_X86_64
        PRIMARY_ARM64=$(find "$TEMP_DIR/arm64" -name "$ARCHIVE_BINARY_NAME" -type f | head -1)
        PRIMARY_X86_64=$(find "$TEMP_DIR/x86_64" -name "$ARCHIVE_BINARY_NAME" -type f | head -1)

        if [ -z "$PRIMARY_ARM64" ] || [ -z "$PRIMARY_X86_64" ]; then
            echo "  ERROR: $ARCHIVE_BINARY_NAME not found in downloaded assets"
            echo "  Hint: archive structure or binary names may have changed upstream"
            STATUS=1
            break
        fi

        echo "  Validating architectures..."
        if ! file "$PRIMARY_ARM64" | grep -q "arm64"; then
            echo "  ERROR: arm64 binary is not actually arm64 architecture"
            echo "  $(file "$PRIMARY_ARM64")"
            STATUS=1
            break
        fi
        if ! file "$PRIMARY_X86_64" | grep -q "x86_64"; then
            echo "  ERROR: x86_64 binary is not actually x86_64 architecture"
            echo "  $(file "$PRIMARY_X86_64")"
            STATUS=1
            break
        fi

        echo "  Creating universal binary..."
        mkdir -p "$VENDOR_DIR"

        if [ "$ASSET_ARM64" = "$ASSET_X86_64" ]; then
            # One pre-merged universal asset for both patterns: both
            # extractions hold the same fat binary and lipo -create rejects
            # fat inputs, so install it directly.
            if ! cp "$PRIMARY_ARM64" "$PRIMARY_OUTPUT_PATH"; then
                echo "  ERROR: Failed to install universal $OUTPUT_BINARY_NAME"
                STATUS=1
                break
            fi
        elif ! lipo -create -output "$PRIMARY_OUTPUT_PATH" "$PRIMARY_ARM64" "$PRIMARY_X86_64"; then
            echo "  ERROR: Failed to create universal $OUTPUT_BINARY_NAME"
            STATUS=1
            break
        fi
        chmod 755 "$PRIMARY_OUTPUT_PATH"

        if [ -n "$COMPANION_ARCHIVE_BINARY_NAME" ]; then
            local COMPANION_ARM64
            local COMPANION_X86_64
            COMPANION_ARM64=$(find "$TEMP_DIR/arm64" -name "$COMPANION_ARCHIVE_BINARY_NAME" -type f | head -1)
            COMPANION_X86_64=$(find "$TEMP_DIR/x86_64" -name "$COMPANION_ARCHIVE_BINARY_NAME" -type f | head -1)

            if [ -n "$COMPANION_ARM64" ] && [ -n "$COMPANION_X86_64" ]; then
                if [ "$ASSET_ARM64" = "$ASSET_X86_64" ]; then
                    # Same pre-merged universal asset as the primary above.
                    if ! cp "$COMPANION_ARM64" "$COMPANION_OUTPUT_PATH"; then
                        echo "  ERROR: Failed to install universal $COMPANION_OUTPUT_BINARY_NAME"
                        STATUS=1
                        break
                    fi
                elif ! lipo -create -output "$COMPANION_OUTPUT_PATH" "$COMPANION_ARM64" "$COMPANION_X86_64"; then
                    echo "  ERROR: Failed to create universal $COMPANION_OUTPUT_BINARY_NAME"
                    STATUS=1
                    break
                fi
                chmod 755 "$COMPANION_OUTPUT_PATH"
                echo "  Created universal companion binary: $COMPANION_OUTPUT_BINARY_NAME"
            else
                if [ "$REQUIRE_COMPANION" = true ]; then
                    echo "  ERROR: Companion binary $COMPANION_ARCHIVE_BINARY_NAME missing from one or both archives"
                    echo "  Hint: one architecture asset may be missing the companion executable"
                    STATUS=1
                    break
                fi
                echo "  Companion binary $COMPANION_ARCHIVE_BINARY_NAME not found in both archives; skipping"
            fi
        fi

        local PRIMARY_OUTPUT_SHA256
        local COMPANION_OUTPUT_SHA256="none"
        PRIMARY_OUTPUT_SHA256=$(get_sha256 "$PRIMARY_OUTPUT_PATH")
        if [ -n "$COMPANION_OUTPUT_PATH" ] && [ -f "$COMPANION_OUTPUT_PATH" ]; then
            COMPANION_OUTPUT_SHA256=$(get_sha256 "$COMPANION_OUTPUT_PATH")
        fi

        if [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ] && is_valid_sha256 "$BASELINE_PIN_OUTPUT_SHA256"; then
            if [ "$PRIMARY_OUTPUT_SHA256" != "$BASELINE_PIN_OUTPUT_SHA256" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "universal output digest mismatch vs baseline pin"; then
                    STATUS=1
                    break
                fi
                OUTPUT_VERIFICATION="override-output-mismatch"
            fi
        fi

        # Same version guard as the primary output above: the companion pin only
        # asserts a reproducible rebuild of the SAME upstream tag. Without the
        # version check every legitimate version bump trips the gate and has to
        # be waved through with an integrity override.
        if [ "$REQUIRE_COMPANION" = true ] && [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ] && is_valid_sha256 "$BASELINE_PIN_COMPANION_SHA256"; then
            if [ "$COMPANION_OUTPUT_SHA256" != "$BASELINE_PIN_COMPANION_SHA256" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "companion output digest mismatch vs baseline pin"; then
                    STATUS=1
                    break
                fi
                OUTPUT_VERIFICATION="override-companion-output-mismatch"
            fi
        fi

        # Verify the universal binary is genuinely arm64+x86_64 BEFORE persisting
        # the baseline/.version, so a failed run never leaves a baseline asserting
        # success. lipo -archs is authoritative; `file | grep universal` passes for
        # arm64+arm64e fat binaries that lack x86_64.
        OUTPUT_ARCHS=$(lipo -archs "$PRIMARY_OUTPUT_PATH" 2>/dev/null || echo "")
        if ! echo " $OUTPUT_ARCHS " | grep -q " arm64 " || ! echo " $OUTPUT_ARCHS " | grep -q " x86_64 "; then
            echo "  ERROR: output is not a universal arm64+x86_64 binary (archs: ${OUTPUT_ARCHS:-none})"
            echo "  $(file "$PRIMARY_OUTPUT_PATH")"
            STATUS=1
            break
        fi

        # Functional liveness test — a vendored CLI that responds to none of the
        # standard version flags is almost certainly broken (corrupt download,
        # wrong arch). Fatal by default, run BEFORE the baseline write. Binaries
        # that macOS kills until re-signing because they were byte-patched
        # post-download opt out via VENDOR_BINARY_ALLOW_EXEC_FAILURE=1.
        local exec_test_output=""
        if exec_test_output=$("$PRIMARY_OUTPUT_PATH" --version 2>&1) || exec_test_output=$("$PRIMARY_OUTPUT_PATH" -V 2>&1) || exec_test_output=$("$PRIMARY_OUTPUT_PATH" version 2>&1); then
            echo "  Execution test: passed"
        elif [ "${VENDOR_BINARY_ALLOW_EXEC_FAILURE:-0}" = "1" ]; then
            echo "  WARNING: did not respond to --version/-V/version — exec test waived (VENDOR_BINARY_ALLOW_EXEC_FAILURE=1)"
            [ -n "$exec_test_output" ] && echo "  Output: $exec_test_output"
        else
            echo "  ERROR: binary did not respond to --version/-V/version (broken / wrong-arch?)"
            echo "  Set VENDOR_BINARY_ALLOW_EXEC_FAILURE=1 for tools with non-standard flags or post-patch unsigned binaries."
            [ -n "$exec_test_output" ] && echo "  Output: $exec_test_output"
            STATUS=1
            break
        fi

        echo "$LATEST_TAG" > "$VERSION_FILE"

        local LAST_SYNC
        LAST_SYNC=$(vendor_release_published_date "$GITHUB_REPO" "$LATEST_TAG")
        if ! echo "$LAST_SYNC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            LAST_SYNC=$(baseline_value "last_sync" "$BASELINE_FILE" 2>/dev/null)
            echo "$LAST_SYNC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || LAST_SYNC=$(date +%Y-%m-%d)
        fi

        cat > "$BASELINE_FILE" <<EOF_BASELINE
# $DISPLAY_NAME Baseline Tracking
upstream_repo=https://github.com/$GITHUB_REPO
upstream_version=$LATEST_TAG
last_sync=$LAST_SYNC
architecture=universal (arm64 + x86_64)
source_asset_arm64=$ASSET_ARM64
source_asset_x86_64=$ASSET_X86_64
source_sha256_arm64=$ARM64_SHA256
source_sha256_x86_64=$X86_SHA256
source_api_sha256_arm64=${API_SHA256_ARM64:-none}
source_api_sha256_x86_64=${API_SHA256_X86_64:-none}
source_checksums_file=${CHECKSUM_NAME_USED:-none}
source_checksums_sha256=${CHECKSUM_FILE_SHA256:-none}
provenance_verification=$PROVENANCE_METHOD
output_verification=$OUTPUT_VERIFICATION
output_sha256=$PRIMARY_OUTPUT_SHA256
companion_output_sha256=$COMPANION_OUTPUT_SHA256
EOF_BASELINE
        chmod 644 "$BASELINE_FILE"

        echo ""
        echo "  Installed: $PRIMARY_OUTPUT_PATH"
        echo "  Version: $LATEST_TAG"
        echo "  Size: $(du -h "$PRIMARY_OUTPUT_PATH" | cut -f1)"
        echo "  Type: $(file "$PRIMARY_OUTPUT_PATH" | sed 's/.*: //')"

        if [ -n "$COMPANION_OUTPUT_PATH" ] && [ -f "$COMPANION_OUTPUT_PATH" ]; then
            echo "  Companion: $COMPANION_OUTPUT_PATH"
            echo "  Companion Type: $(file "$COMPANION_OUTPUT_PATH" | sed 's/.*: //')"
        fi

        break
    done

    cleanup_vendor_binary_temp_dir
    if [ -n "$PREV_EXIT_TRAP" ]; then eval "$PREV_EXIT_TRAP"; else trap - EXIT; fi
    if [ -n "$PREV_INT_TRAP" ]; then eval "$PREV_INT_TRAP"; else trap - INT; fi
    if [ -n "$PREV_TERM_TRAP" ]; then eval "$PREV_TERM_TRAP"; else trap - TERM; fi

    if [ "$STATUS" -ne 0 ]; then
        return 1
    fi

    echo ""
    echo "Done."
    return 0
}

# Require a tool on PATH or abort. Shared by the source-build vendor scripts.
require_tool() {
    local tool_name="$1"
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        echo "ERROR: Required tool not found: $tool_name"
        exit 1
    fi
}

# Shared source-build scaffolding for fd/btop/zmx. See the header comment for
# the full parameter list and the BUILD_FN callback contract. Fail-closed by
# design: every source-pin, output-pin, and universal-arch check aborts the run
# rather than record a bad baseline.
vendor_source_build() {
    local DISPLAY_NAME="$1"
    local GITHUB_REPO="$2"
    local VENDOR_SUBDIR="$3"
    local BASELINE_NAME="$4"
    local OUTPUT_BINARY_NAME="$5"
    local BUILD_FN="$6"
    local FORCE="${7:-false}"
    local BUILD_METHOD="${8:-}"

    local REPO_ROOT
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    local VENDOR_DIR="$REPO_ROOT/yen-terminal/customizations/vendor/$VENDOR_SUBDIR"
    local VERSION_FILE="$VENDOR_DIR/.version"
    local BASELINE_FILE="$REPO_ROOT/yen-terminal/$BASELINE_NAME"
    local OUTPUT_BINARY="$VENDOR_DIR/$OUTPUT_BINARY_NAME"

    echo ""
    echo "Vendor $DISPLAY_NAME (Universal Binary — Source Build)"

    local LATEST_TAG
    LATEST_TAG="${VENDOR_LATEST_TAG:-}"
    if [ -n "$LATEST_TAG" ]; then
        echo "  Latest release: $LATEST_TAG (from orchestrator)"
    else
        echo "  Fetching latest release..."
        LATEST_TAG="$(vendor_fetch_latest_release_tag "$GITHUB_REPO")"
        if [ -z "$LATEST_TAG" ]; then
            echo "ERROR: Could not fetch latest release tag"
            return 1
        fi
        echo "  Latest release: $LATEST_TAG"
    fi

    local INTEGRITY_CONTEXT="$DISPLAY_NAME:$LATEST_TAG"

    local CURRENT_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
    fi

    local BASELINE_PIN_VERSION=""
    local BASELINE_PIN_SOURCE_SHA256=""
    local BASELINE_PIN_OUTPUT_SHA256=""
    if [ -f "$BASELINE_FILE" ]; then
        # Callers run under `set -euo pipefail`; baseline_value is a grep|head|cut
        # pipeline, so a missing key makes grep exit 1 and pipefail would abort
        # this bare command-substitution assignment. `|| true` preserves the
        # historical "" fallback (downstream integrity gates emit their own clear
        # messages on empty pins) exactly as under plain `set -e`.
        BASELINE_PIN_VERSION=$(baseline_value "upstream_version" "$BASELINE_FILE") || true
        BASELINE_PIN_SOURCE_SHA256=$(baseline_value "source_tarball_sha256" "$BASELINE_FILE") || true
        BASELINE_PIN_OUTPUT_SHA256=$(baseline_value "output_sha256" "$BASELINE_FILE") || true
    fi

    # Build inputs beyond the source tarball (see VENDOR_BUILD_INPUT_ID above).
    # Without the variable both sides are empty and every pin check below runs
    # exactly as before.
    local BUILD_INPUT_ID="${VENDOR_BUILD_INPUT_ID:-}"
    local BASELINE_PIN_INPUT_ID=""
    if [ -n "$BUILD_INPUT_ID" ] && [ -f "$BASELINE_FILE" ]; then
        BASELINE_PIN_INPUT_ID=$(baseline_value "build_input_id" "$BASELINE_FILE") || true
    fi
    local OUTPUT_PIN_APPLIES=false
    if [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ] && [ "$BASELINE_PIN_INPUT_ID" = "$BUILD_INPUT_ID" ]; then
        OUTPUT_PIN_APPLIES=true
    fi
    if [ -n "$BUILD_INPUT_ID" ] && [ "$BASELINE_PIN_INPUT_ID" != "$BUILD_INPUT_ID" ]; then
        echo "  Build inputs changed (${BASELINE_PIN_INPUT_ID:-none} -> $BUILD_INPUT_ID); rebuilding and re-recording the output pin"
        FORCE=true
    fi

    # No-op path: current + universal. Revalidate the pinned output digest of the
    # bundled binary BEFORE declaring it current, so a tampered/stale artifact
    # fails closed instead of silently passing (three fail-closed branches; keep
    # this revalidation BEFORE the "Already current" message — a guardrail test
    # asserts that ordering).
    if [ "$FORCE" = false ] && [ "$CURRENT_VERSION" = "$LATEST_TAG" ] && [ -f "$OUTPUT_BINARY" ]; then
        # lipo -archs is authoritative; `file | grep universal` also passes for an
        # arm64+arm64e fat binary that LACKS x86_64. Only treat the bundled artifact
        # as "current and universal" when its slice set contains BOTH required archs.
        local NOOP_OUTPUT_ARCHS
        NOOP_OUTPUT_ARCHS=$(lipo -archs "$OUTPUT_BINARY" 2>/dev/null || echo "")
        if echo " $NOOP_OUTPUT_ARCHS " | grep -q " arm64 " && echo " $NOOP_OUTPUT_ARCHS " | grep -q " x86_64 "; then
            if [ "$BASELINE_PIN_VERSION" != "$LATEST_TAG" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "no pinned output digest for current version $LATEST_TAG"; then
                    return 1
                fi
            elif ! is_valid_sha256 "$BASELINE_PIN_OUTPUT_SHA256"; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "missing baseline output_sha256 for current version"; then
                    return 1
                fi
            else
                local ACTUAL_OUTPUT_SHA256
                ACTUAL_OUTPUT_SHA256=$(get_sha256 "$OUTPUT_BINARY")
                if [ "$ACTUAL_OUTPUT_SHA256" != "$BASELINE_PIN_OUTPUT_SHA256" ]; then
                    if ! vendor_fail_or_bypass_integrity \
                        "$REPO_ROOT" \
                        "$INTEGRITY_CONTEXT" \
                        "current output digest mismatch vs baseline pin"; then
                        return 1
                    fi
                else
                    # State the pass. This branch is the only thing standing
                    # between a tampered bundled binary and a "current" verdict,
                    # and it used to succeed in total silence -- indistinguishable
                    # in the log from the branch never having run.
                    echo "  Output digest revalidated against baseline pin (${ACTUAL_OUTPUT_SHA256:0:12}...)"
                fi
            fi

            echo "  Already current ($CURRENT_VERSION) and universal. Use --force to rebuild."
            echo ""
            echo "Done."
            return 0
        fi
        echo "  Current version exists but is not universal. Rebuilding..."
    fi

    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$LATEST_TAG" ]; then
        echo "  Updating: $CURRENT_VERSION -> $LATEST_TAG"
    fi

    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
        echo "  ERROR: Could not create temporary directory"
        return 1
    fi

    local PREV_EXIT_TRAP PREV_INT_TRAP PREV_TERM_TRAP
    PREV_EXIT_TRAP=$(trap -p EXIT || true)
    PREV_INT_TRAP=$(trap -p INT || true)
    PREV_TERM_TRAP=$(trap -p TERM || true)

    cleanup_vendor_source_build_temp_dir() {
        if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
            rm -rf "$TEMP_DIR"
        fi
    }
    trap cleanup_vendor_source_build_temp_dir EXIT INT TERM

    local STATUS=0

    while :; do
        local SOURCE_TARBALL="$TEMP_DIR/${LATEST_TAG}.tar.gz"
        local SOURCE_COMMIT=""
        SOURCE_COMMIT="$(vendor_resolve_tag_commit "$GITHUB_REPO" "$LATEST_TAG" || true)"
        if ! echo "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
            echo "ERROR: Could not resolve $LATEST_TAG to an immutable upstream commit"
            STATUS=1
            break
        fi
        local SOURCE_URL="https://github.com/$GITHUB_REPO/archive/${SOURCE_COMMIT}.tar.gz"
        local PROVENANCE_VERIFICATION="github-commit-bound-archive"

        echo "  Downloading source..."
        if ! curl --retry 3 --retry-delay 1 --max-time 120 --connect-timeout 10 -sfL -o "$SOURCE_TARBALL" "$SOURCE_URL"; then
            echo "ERROR: Failed to download source archive"
            echo "URL: $SOURCE_URL"
            STATUS=1
            break
        fi
        local SOURCE_TARBALL_SHA256
        SOURCE_TARBALL_SHA256=$(get_sha256 "$SOURCE_TARBALL")
        echo "  Source SHA256: $SOURCE_TARBALL_SHA256"

        if [ "$BASELINE_PIN_VERSION" = "$LATEST_TAG" ]; then
            if is_valid_sha256 "$BASELINE_PIN_SOURCE_SHA256"; then
                if [ "$SOURCE_TARBALL_SHA256" != "$BASELINE_PIN_SOURCE_SHA256" ]; then
                    if ! vendor_fail_or_bypass_integrity \
                        "$REPO_ROOT" \
                        "$INTEGRITY_CONTEXT" \
                        "source tarball digest mismatch vs baseline pin"; then
                        STATUS=1
                        break
                    fi
                    PROVENANCE_VERIFICATION="override-source-mismatch"
                else
                    echo "  Baseline pinned source digest matched"
                fi
            else
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "missing baseline source_tarball_sha256 for current version"; then
                    STATUS=1
                    break
                fi
                PROVENANCE_VERIFICATION="override-missing-pin"
            fi
        else
            echo "  Source tag resolved to immutable commit $SOURCE_COMMIT"
        fi

        echo "  Extracting source..."
        if ! tar -xzf "$SOURCE_TARBALL" -C "$TEMP_DIR"; then
            echo "ERROR: Failed to extract source archive"
            STATUS=1
            break
        fi

        local SOURCE_DIR
        # `find | head -1` can leave find killed by SIGPIPE (exit 141) once head
        # closes the pipe; under pipefail that would abort this assignment. `|| true`
        # keeps the captured value, which the following `-z`/`-d` check validates.
        SOURCE_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "${DISPLAY_NAME}-*" | head -1) || true
        if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
            echo "ERROR: Could not locate extracted $DISPLAY_NAME source directory"
            STATUS=1
            break
        fi

        # Delegate the compile to the caller. Capture WITHOUT masking status so a
        # failed build (return non-zero) fails closed instead of leaving a stale
        # prior binary passing the checks below.
        local BUILD_OUT
        if ! BUILD_OUT=$("$BUILD_FN" "$SOURCE_DIR" "$TEMP_DIR"); then
            echo "ERROR: One or both architecture builds failed"
            STATUS=1
            break
        fi

        local ARM64_BINARY X86_64_BINARY
        ARM64_BINARY=$(echo "$BUILD_OUT" | sed -n '1p')
        X86_64_BINARY=$(echo "$BUILD_OUT" | sed -n '2p')

        if [ -z "$ARM64_BINARY" ] || [ ! -f "$ARM64_BINARY" ]; then
            echo "ERROR: arm64 $DISPLAY_NAME binary not found after build"
            STATUS=1
            break
        fi
        if [ -z "$X86_64_BINARY" ] || [ ! -f "$X86_64_BINARY" ]; then
            echo "ERROR: x86_64 $DISPLAY_NAME binary not found after build"
            STATUS=1
            break
        fi

        if ! file "$ARM64_BINARY" | grep -q "arm64"; then
            echo "ERROR: arm64 build output is not arm64"
            echo "  $(file "$ARM64_BINARY")"
            STATUS=1
            break
        fi
        if ! file "$X86_64_BINARY" | grep -q "x86_64"; then
            echo "ERROR: x86_64 build output is not x86_64"
            echo "  $(file "$X86_64_BINARY")"
            STATUS=1
            break
        fi

        echo "  Creating universal binary..."
        mkdir -p "$VENDOR_DIR"
        if ! lipo -create -output "$OUTPUT_BINARY" "$ARM64_BINARY" "$X86_64_BINARY"; then
            echo "ERROR: Failed to create universal $OUTPUT_BINARY_NAME"
            STATUS=1
            break
        fi
        chmod 755 "$OUTPUT_BINARY"

        # Verify the universal binary is genuinely arm64+x86_64 BEFORE persisting
        # the baseline/.version. lipo -archs is authoritative; `file | grep universal`
        # also passes for an arm64+arm64e fat binary that LACKS x86_64. Assert the
        # slice set contains BOTH required archs (order-independent, fail-closed).
        local OUTPUT_ARCHS
        OUTPUT_ARCHS=$(lipo -archs "$OUTPUT_BINARY" 2>/dev/null || echo "")
        if ! echo " $OUTPUT_ARCHS " | grep -q " arm64 " || ! echo " $OUTPUT_ARCHS " | grep -q " x86_64 "; then
            echo "ERROR: output is not a universal arm64+x86_64 binary (archs: ${OUTPUT_ARCHS:-none})"
            echo "  $(file "$OUTPUT_BINARY")"
            STATUS=1
            break
        fi
        local OUTPUT_SHA256
        OUTPUT_SHA256=$(get_sha256 "$OUTPUT_BINARY")
        echo "  Output SHA256: $OUTPUT_SHA256"

        if [ "$OUTPUT_PIN_APPLIES" = true ]; then
            if ! is_valid_sha256 "$BASELINE_PIN_OUTPUT_SHA256"; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "missing baseline output_sha256 before source-build baseline rewrite"; then
                    STATUS=1
                    break
                fi
                PROVENANCE_VERIFICATION="override-missing-output-pin"
            elif [ "$OUTPUT_SHA256" != "$BASELINE_PIN_OUTPUT_SHA256" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "output digest mismatch vs baseline pin"; then
                    STATUS=1
                    break
                fi
                PROVENANCE_VERIFICATION="override-output-mismatch"
            fi
        fi

        # Liveness test BEFORE persisting the baseline — a source-built binary
        # that will not exec means a broken build; fail closed rather than record
        # a bad baseline. Superset of the per-tool flags (fd: --version;
        # btop: --version/-v).
        if "$OUTPUT_BINARY" --version >/dev/null 2>&1 || "$OUTPUT_BINARY" -v >/dev/null 2>&1 || "$OUTPUT_BINARY" -V >/dev/null 2>&1 || "$OUTPUT_BINARY" version >/dev/null 2>&1; then
            echo "  Execution test: passed"
        else
            echo "  ERROR: $DISPLAY_NAME did not respond to --version/-v/-V/version after build"
            STATUS=1
            break
        fi

        echo "$LATEST_TAG" > "$VERSION_FILE"

        local LAST_SYNC
        # Both reads are tolerant-by-design date lookups with an explicit fallback
        # chain (upstream date -> pinned baseline last_sync -> today). Under the
        # callers' pipefail, vendor_release_published_date (curl|python3) aborts on
        # an offline/404 curl, and baseline_value (grep|head|cut) aborts on a missing
        # key — `|| true` keeps the empty result so the validation+fallback below runs.
        LAST_SYNC=$(vendor_release_published_date "$GITHUB_REPO" "$LATEST_TAG") || true
        if ! echo "$LAST_SYNC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
            LAST_SYNC=$(baseline_value "last_sync" "$BASELINE_FILE" 2>/dev/null) || true
            echo "$LAST_SYNC" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || LAST_SYNC=$(date +%Y-%m-%d)
        fi

        # Brace-group of echo lines (not a heredoc) so the build_method line is
        # emitted ONLY when BUILD_METHOD is non-empty. Preserves btop's omission
        # plus fd's inclusion and the exact field set + order.
        {
            echo "# $DISPLAY_NAME Baseline Tracking"
            echo "upstream_repo=https://github.com/$GITHUB_REPO"
            echo "upstream_version=$LATEST_TAG"
            echo "last_sync=$LAST_SYNC"
            echo "architecture=universal (arm64 + x86_64)"
            if [ -n "$BUILD_METHOD" ]; then
                echo "build_method=$BUILD_METHOD"
            fi
            if [ -n "$BUILD_INPUT_ID" ]; then
                echo "build_input_id=$BUILD_INPUT_ID"
            fi
            echo "source_archive_url=$SOURCE_URL"
            echo "source_commit=$SOURCE_COMMIT"
            echo "source_tarball_sha256=$SOURCE_TARBALL_SHA256"
            echo "output_sha256=$OUTPUT_SHA256"
            echo "provenance_verification=$PROVENANCE_VERIFICATION"
        } > "$BASELINE_FILE"
        chmod 644 "$BASELINE_FILE"

        echo ""
        echo "  Installed: $OUTPUT_BINARY"
        echo "  Version: $LATEST_TAG"
        echo "  Size: $(du -h "$OUTPUT_BINARY" | cut -f1)"
        echo "  Type: $(file "$OUTPUT_BINARY" | sed 's/.*: //')"

        break
    done

    cleanup_vendor_source_build_temp_dir
    if [ -n "$PREV_EXIT_TRAP" ]; then eval "$PREV_EXIT_TRAP"; else trap - EXIT; fi
    if [ -n "$PREV_INT_TRAP" ]; then eval "$PREV_INT_TRAP"; else trap - INT; fi
    if [ -n "$PREV_TERM_TRAP" ]; then eval "$PREV_TERM_TRAP"; else trap - TERM; fi

    if [ "$STATUS" -ne 0 ]; then
        return 1
    fi

    echo ""
    echo "Done."
    return 0
}
