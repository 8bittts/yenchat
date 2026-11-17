#!/bin/bash
#
# Update Ghostty to latest version
#
# Downloads to ghostty/ (exact upstream mirror), then runs apply-overlays.sh
#
# Usage: ./scripts/10-update-ghostty.sh [version]
#   version: Optional. Use "main" for latest dev, or a tag like "v1.2.3"
#            Default: main

set -euo pipefail

VERSION="${1:-main}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
YEN_TERMINAL="$REPO_ROOT/yen-terminal"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/vendor-binary.sh"
source "$REPO_ROOT/scripts/lib/workflow-lock.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"
init_shared_workflow_lock "$REPO_ROOT"

require_python3 "for GitHub API JSON parsing" || exit 1

# Auto-detect GitHub token for rate limit headroom (consistent with 14-vendor.sh)
if [ -z "${GITHUB_TOKEN:-}" ] && command -v gh &>/dev/null; then
    GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
fi
CURL_AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
    CURL_AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
fi

echo "Ghostty Vendor Update"

cd "$YEN_TERMINAL"

LOCK_KEY=$(printf '%s\n' "$YEN_TERMINAL" | cksum | awk '{print $1}')
GHOSTTY_VENDOR_LOCK_DIR="${TMPDIR:-/tmp}/yen-ghostty-vendor-${LOCK_KEY}.lock"
GHOSTTY_VENDOR_LOCK_ACQUIRED=false

GHOSTTY_TEMP_TAR=""  # Set before download, cleaned on exit

release_ghostty_vendor_lock() {
    # Clean temp tarball if download was interrupted
    if [ -n "$GHOSTTY_TEMP_TAR" ] && [ -f "$GHOSTTY_TEMP_TAR" ]; then
        rm -f "$GHOSTTY_TEMP_TAR"
    fi
    release_shared_workflow_lock
    if [ "$GHOSTTY_VENDOR_LOCK_ACQUIRED" = true ] && [ -d "$GHOSTTY_VENDOR_LOCK_DIR" ]; then
        rm -rf "$GHOSTTY_VENDOR_LOCK_DIR"
    fi
}

acquire_ghostty_vendor_lock() {
    acquire_yen_process_lock \
        "$GHOSTTY_VENDOR_LOCK_DIR" \
        GHOSTTY_VENDOR_LOCK_ACQUIRED \
        "10-update-ghostty.sh" \
        "ERROR: Another Ghostty vendor update is already running (pid {pid})
Wait for it to finish before starting a new Ghostty vendor update." \
        "ERROR: Ghostty vendor lock exists without a PID file: $GHOSTTY_VENDOR_LOCK_DIR
If no update process is running, remove the stale lock and retry." \
        "ERROR: Could not acquire Ghostty vendor lock: $GHOSTTY_VENDOR_LOCK_DIR" || exit 1
}

# The sentinel is now the shared one in scripts/lib/gate-receipt.sh -- this was
# the third hand-written copy, and its own comment named the first two (05 and
# 13) while still copy-pasting. bash 3.2 traps are single-slot, so the lock
# release is handed to gate_begin rather than installed as a second EXIT trap.
gate_begin 10-update-ghostty release_ghostty_vendor_lock
acquire_shared_workflow_lock "ghostty-vendor" || exit 1
acquire_ghostty_vendor_lock

CURRENT_BASELINE=""
CURRENT_BASELINE_VERSION=""
CURRENT_BASELINE_ARCHIVE_SHA256=""
CURRENT_BASELINE_PROVENANCE_VERIFICATION=""
if [ -f ".ghostty-baseline" ]; then
    CURRENT_BASELINE=$(grep "^upstream_commit=" .ghostty-baseline 2>/dev/null | cut -d= -f2 || echo "")
    CURRENT_BASELINE_VERSION=$(grep "^upstream_version=" .ghostty-baseline 2>/dev/null | cut -d= -f2 || echo "")
    CURRENT_BASELINE_ARCHIVE_SHA256=$(grep "^source_archive_sha256=" .ghostty-baseline 2>/dev/null | cut -d= -f2 || echo "")
    CURRENT_BASELINE_PROVENANCE_VERIFICATION=$(grep "^provenance_verification=" .ghostty-baseline 2>/dev/null | cut -d= -f2 || echo "")
fi

write_tracking_files() {
    local vendor_info_path="$YEN_TERMINAL/VENDOR_INFO.txt"
    local baseline_path="$YEN_TERMINAL/.ghostty-baseline"
    local written_vendor_commit=""
    local written_baseline_commit=""

    # VENDOR_INFO.txt
    write_atomic_text_file "$vendor_info_path" 644 <<EOF
Ghostty Source Code (Vendored for YEN)
=====================================

Vendored from: $(upstream_web_url)
Version: $VERSION
Commit: $COMMIT_HASH
Vendored Date: $CURRENT_DATE
License: MIT

Structure
---------
ghostty/     = Exact upstream mirror (branding applied by apply-overlays.sh)
overlays/    = YEN customization files copied on top
customizations/ = Build scripts, icons, shell integration

Building
--------
cd yen-terminal && ./customizations/build-release.sh

Updated: $CURRENT_DATE to $VERSION ($COMMIT_HASH)
EOF

    # .ghostty-baseline
    write_atomic_text_file "$baseline_path" 644 <<EOF
# Ghostty Baseline Tracking
upstream_repo=$(upstream_git_url)
upstream_commit=$COMMIT_HASH
upstream_version=$VERSION
last_sync=$CURRENT_DATE
source_archive_url=$SOURCE_ARCHIVE_URL
source_archive_sha256=$SOURCE_ARCHIVE_SHA256
provenance_verification=$PROVENANCE_VERIFICATION
provenance_recorded_at_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EOF

    written_vendor_commit=$(sed -n 's/^Commit: //p' "$vendor_info_path" | head -1)
    written_baseline_commit=$(grep "^upstream_commit=" "$baseline_path" | head -1 | cut -d= -f2-)

    if [ "$written_vendor_commit" != "$COMMIT_HASH" ] || [ "$written_baseline_commit" != "$COMMIT_HASH" ]; then
        echo "ERROR: Ghostty tracking files failed to persist commit $COMMIT_HASH"
        echo "  VENDOR_INFO.txt commit: ${written_vendor_commit:-missing}"
        echo "  .ghostty-baseline commit: ${written_baseline_commit:-missing}"
        return 1
    fi
}

write_atomic_text_file() {
    local output_path="$1"
    local output_mode="$2"
    local output_dir=""
    local output_name=""
    local temp_path=""

    output_dir=$(dirname "$output_path")
    output_name=$(basename "$output_path")
    temp_path=$(mktemp "${output_dir}/.${output_name}.XXXXXX") || {
        echo "ERROR: mktemp failed for $output_path"
        return 1
    }

    if ! cat > "$temp_path"; then
        rm -f "$temp_path"
        echo "ERROR: Failed to write temp file for $output_path"
        return 1
    fi

    chmod "$output_mode" "$temp_path" || {
        rm -f "$temp_path"
        echo "ERROR: Failed to chmod $output_path"
        return 1
    }

    mv "$temp_path" "$output_path" || {
        rm -f "$temp_path"
        echo "ERROR: Failed to move temp file into place for $output_path"
        return 1
    }
}

# Upstream ships AGENTS.md files throughout its tree. They document pre-rebrand
# paths and macros that do not exist after apply-overlays.sh runs, and the root
# one instructs agents to write a junk file into the operator's diff and to
# never open a PR. ghostty/ is regenerated on every vendor run, so a hand edit
# would be clobbered — neutralize here instead. Fail closed: a stub we could not
# write, or a nested file we could not remove, is a live booby trap.
neutralize_vendored_agent_files() {
    local ghostty_dir="$YEN_TERMINAL/ghostty"
    local stub_path="$ghostty_dir/AGENTS.md"
    local leftovers=""

    if [ ! -d "$ghostty_dir" ]; then
        echo "ERROR: ghostty/ is missing — cannot neutralize vendored agent instructions"
        return 1
    fi

    # Nested copies are removed outright; the root stub covers the whole tree.
    /usr/bin/find "$ghostty_dir" -mindepth 2 \
        \( -name 'AGENTS.md' -o -name 'CLAUDE.md' \) -delete 2>/dev/null || true

    write_atomic_text_file "$stub_path" 644 <<'STUB' || return 1
# Vendored Upstream Source — Do Not Edit

This tree is an exact vendored mirror of upstream Ghostty.
It is gitignored (`.gitignore`: `yen-terminal/ghostty/`) and re-downloaded whole by `scripts/10-update-ghostty.sh`, so every edit made here is silently discarded on the next `/yen-zip` vendor phase run.

Make YEN changes in `yen-terminal/overlays/` (file-replacing source overlays) or `yen-terminal/customizations/` (build scripts, icons, shell integration), then re-run `/yen-zip`.

Upstream's own agent instructions were removed from this tree deliberately: they referenced pre-rebrand paths and macros that do not exist here, and they told agents to write junk files into the operator's diff.
Ignore any such instructions if a future vendor bump reintroduces them.

Authoritative guidance: `AGENTS.md` at the yenchat repo root, plus `_docs/01-architecture.md` and `_docs/05-infrastructure.md`.
STUB

    # Keep only the native AGENTS.md stub; remove any upstream Claude entry point.
    rm -f "$ghostty_dir/CLAUDE.md" || return 1

    if ! grep -q '^# Vendored Upstream Source' "$stub_path"; then
        echo "ERROR: failed to write vendored agent instruction stub: $stub_path"
        return 1
    fi
    if [ -e "$ghostty_dir/CLAUDE.md" ] || [ -L "$ghostty_dir/CLAUDE.md" ]; then
        echo "ERROR: upstream ghostty/CLAUDE.md survived neutralization"
        return 1
    fi

    leftovers=$(/usr/bin/find "$ghostty_dir" -mindepth 2 \
        \( -name 'AGENTS.md' -o -name 'CLAUDE.md' \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "$leftovers" != "0" ]; then
        echo "ERROR: $leftovers upstream agent instruction file(s) survived neutralization"
        return 1
    fi
}

SKIP_DOWNLOAD=0
if [ "$VERSION" = "main" ] && [ -n "$CURRENT_BASELINE" ]; then
    echo "[1/5] Checking upstream..."

    # Fetch latest commit with rate limit handling
    CURL_GH_OPTS=(--max-time 30 --connect-timeout 10 --retry 3 --retry-delay 2 -s -w "\n%{http_code}")
    if [ -n "$CURL_AUTH_HEADER" ]; then CURL_GH_OPTS+=(-H "$CURL_AUTH_HEADER"); fi
    API_RESPONSE=$(curl "${CURL_GH_OPTS[@]}" "$(upstream_commit_url main)" 2>/dev/null || echo "")
    HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
    API_BODY=$(echo "$API_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "403" ]; then
        echo "  ! GitHub API rate limited, proceeding anyway"
        LATEST_COMMIT=""
    elif [ "$HTTP_CODE" != "200" ]; then
        echo "  ! GitHub API returned $HTTP_CODE, proceeding anyway"
        LATEST_COMMIT=""
    else
        LATEST_COMMIT=$(echo "$API_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha', ''))" 2>/dev/null || echo "")
    fi

    if [ -n "$LATEST_COMMIT" ] && [ "$CURRENT_BASELINE" = "$LATEST_COMMIT" ]; then
        COMMIT_HASH="$CURRENT_BASELINE"
        CURRENT_DATE=$(date +%Y-%m-%d)
        SOURCE_ARCHIVE_URL="$(upstream_tarball_url "$COMMIT_HASH")"
        if is_valid_sha256 "$CURRENT_BASELINE_ARCHIVE_SHA256" && [ -n "$CURRENT_BASELINE_PROVENANCE_VERIFICATION" ]; then
            echo "  Already up to date (${CURRENT_BASELINE:0:8})"
            SKIP_DOWNLOAD=1
            SOURCE_ARCHIVE_SHA256="$CURRENT_BASELINE_ARCHIVE_SHA256"
            PROVENANCE_VERIFICATION="$CURRENT_BASELINE_PROVENANCE_VERIFICATION"
        else
            echo "  Current commit matches upstream, but provenance metadata is incomplete; refreshing source archive metadata..."
        fi
    fi
fi

if [ "$SKIP_DOWNLOAD" -eq 0 ]; then
    echo "[2/5] Downloading ($VERSION)..."

    if [ "$VERSION" = "main" ] && [ -n "${LATEST_COMMIT:-}" ]; then
        COMMIT_HASH="$LATEST_COMMIT"
    fi

    if [ -z "${COMMIT_HASH:-}" ]; then
        CURL_GH_OPTS2=(--max-time 30 --connect-timeout 10 --retry 3 --retry-delay 2 -s -w "\n%{http_code}")
        if [ -n "$CURL_AUTH_HEADER" ]; then CURL_GH_OPTS2+=(-H "$CURL_AUTH_HEADER"); fi
        API_RESPONSE=$(curl "${CURL_GH_OPTS2[@]}" \
            "$(upstream_commit_url "$VERSION")" 2>/dev/null || echo "")
        HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
        API_BODY=$(echo "$API_RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" = "403" ]; then
            echo "ERROR: GitHub API rate limited"
            [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
            exit 1
        elif [ "$HTTP_CODE" != "200" ]; then
            echo "ERROR: GitHub API returned $HTTP_CODE"
            [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
            exit 1
        fi

        COMMIT_HASH=$(echo "$API_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha', ''))" 2>/dev/null)
    fi

    if [ -z "${COMMIT_HASH:-}" ]; then
        echo "ERROR: Failed to resolve upstream commit hash"
        [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
        exit 1
    fi

    VERIFIED_COMMIT_SHA="$(upstream_verified_commit_sha "$COMMIT_HASH" || true)"
    if [ "$VERIFIED_COMMIT_SHA" != "$COMMIT_HASH" ]; then
        if ! vendor_fail_or_bypass_integrity \
            "$REPO_ROOT" \
            "ghostty:$VERSION@$COMMIT_HASH" \
            "upstream commit is not verified by the configured forge"; then
            [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
            exit 1
        fi
        PROVENANCE_VERIFICATION="override-unverified-commit"
    else
        PROVENANCE_VERIFICATION="github-verified-commit"
        echo "  Verified upstream commit signature/status: $COMMIT_HASH"
    fi

    # Backup current version
    if [ -d "ghostty" ]; then
        rm -rf ghostty.backup
        mv ghostty ghostty.backup
    fi

    # Download exact commit tarball (not moving refs).
    TEMP_TAR=$(mktemp)
    GHOSTTY_TEMP_TAR="$TEMP_TAR"
    SOURCE_ARCHIVE_URL="$(upstream_tarball_url "$COMMIT_HASH")"
    if ! curl --max-time 600 --connect-timeout 30 -sL -o "$TEMP_TAR" "$SOURCE_ARCHIVE_URL"; then
        echo "ERROR: Download failed: $SOURCE_ARCHIVE_URL"
        rm -f "$TEMP_TAR"
        [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
        exit 1
    fi
    SOURCE_ARCHIVE_SHA256=$(shasum -a 256 "$TEMP_TAR" | awk '{print $1}')
    PROVENANCE_VERIFICATION="${PROVENANCE_VERIFICATION:-none}"
    INTEGRITY_CONTEXT="ghostty:$VERSION@$COMMIT_HASH"
    if [ -n "$CURRENT_BASELINE" ] && [ "$CURRENT_BASELINE" = "$COMMIT_HASH" ]; then
        if is_valid_sha256 "$CURRENT_BASELINE_ARCHIVE_SHA256"; then
            if [ "$SOURCE_ARCHIVE_SHA256" != "$CURRENT_BASELINE_ARCHIVE_SHA256" ]; then
                if ! vendor_fail_or_bypass_integrity \
                    "$REPO_ROOT" \
                    "$INTEGRITY_CONTEXT" \
                    "source archive digest mismatch vs baseline pin"; then
                    rm -f "$TEMP_TAR"
                    [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
                    exit 1
                fi
                PROVENANCE_VERIFICATION="override-source-mismatch"
            else
                PROVENANCE_VERIFICATION="baseline-pinned"
                echo "  Baseline pinned source digest matched"
            fi
        else
            if ! vendor_fail_or_bypass_integrity \
                "$REPO_ROOT" \
                "$INTEGRITY_CONTEXT" \
                "missing baseline source_archive_sha256 for current commit"; then
                rm -f "$TEMP_TAR"
                [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
                exit 1
            fi
            PROVENANCE_VERIFICATION="override-missing-pin"
        fi
    elif [ "$PROVENANCE_VERIFICATION" = "github-verified-commit" ]; then
        # Sanctioned pin-on-first-fetch: a new commit can never have a prior
        # digest pin, so a forge-verified commit fetched by immutable
        # commit-hash archive URL is accepted and its digest pinned now.
        # The bypass env var stays reserved for unverified provenance.
        if ! YEN_VENDOR_INTEGRITY_BYPASS_REASON="pin-on-first-fetch (forge-verified commit)" \
            vendor_append_integrity_audit_log \
            "$REPO_ROOT" \
            "$INTEGRITY_CONTEXT" \
            "pin-on-first-fetch: forge-verified new commit $COMMIT_HASH, digest $SOURCE_ARCHIVE_SHA256 pinned"; then
            rm -f "$TEMP_TAR"
            [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
            exit 1
        fi
        echo "  Pinned source digest on first fetch of forge-verified commit"
    else
        if ! vendor_fail_or_bypass_integrity \
            "$REPO_ROOT" \
            "$INTEGRITY_CONTEXT" \
            "no pinned source digest for new commit $COMMIT_HASH"; then
            rm -f "$TEMP_TAR"
            [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
            exit 1
        fi
        PROVENANCE_VERIFICATION="override-new-version"
    fi

    tar xzf "$TEMP_TAR" || {
        echo "ERROR: Extract failed"
        rm -f "$TEMP_TAR"
        [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
        exit 1
    }
    rm -f "$TEMP_TAR"

    # Archive root, derived from the configured repo rather than hardcoded, so a
    # YEN_UPSTREAM_REPO / forge cutover does not silently look for the wrong
    # directory. Every sibling failure path above restores ghostty.backup; this
    # one used to have none, so a bad archive root left the tree without
    # ghostty/ at all (the backup survived, but nothing put it back).
    EXTRACT_DIR="${UPSTREAM_REPO}-${COMMIT_HASH}"
    if [ ! -d "$EXTRACT_DIR" ]; then
        echo "ERROR: extracted archive root not found: $EXTRACT_DIR"
        echo "  The upstream archive did not unpack to the expected <repo>-<sha> layout."
        [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
        exit 1
    fi
    if ! mv "$EXTRACT_DIR" ghostty; then
        echo "ERROR: could not move $EXTRACT_DIR into place"
        [ -d "ghostty.backup" ] && mv ghostty.backup ghostty
        exit 1
    fi
    CURRENT_DATE=$(date +%Y-%m-%d)

    # Don't delete backup yet — overlays may still fail
fi

echo "[2b/5] Neutralizing upstream agent instructions..."

# Runs on both the fresh-download and already-up-to-date paths, so a tree that
# was vendored before this step existed still gets cleaned.
if ! neutralize_vendored_agent_files; then
    echo "ERROR: could not neutralize upstream agent instructions in ghostty/"
    if [ -d "ghostty.backup" ]; then
        echo "  Restoring previous ghostty/ from backup..."
        rm -rf ghostty
        mv ghostty.backup ghostty
    fi
    exit 1
fi

# The whole [3a/5] phase compares overlays against PRISTINE upstream, so it is
# only meaningful when this run actually downloaded a fresh tree. On the
# already-up-to-date path (SKIP_DOWNLOAD=1) ghostty/ still holds the previous
# run's applied overlays, which makes the Swift diff compare files against
# copies of themselves and makes the build.zig gate fail on its own overlay.
if [ "$SKIP_DOWNLOAD" -ne 0 ]; then
    echo "[3a/5] Pre-overlay structural diff skipped (tree already up to date, not freshly downloaded)."
else
echo "[3a/5] Pre-overlay structural diff (upstream vs overlay)..."

# At this point ghostty/ is the fresh, unmodified upstream tree (overlays not
# applied yet). Diff every file-replacing overlay against its upstream pair so
# we learn about upstream refactors BEFORE apply-overlays.sh copies our file on
# top and hides the change. Non-fatal — prints a warning list only.
if [ -d overlays ]; then
    # Every overlay that replaces an upstream file, recorded once. Two defects
    # made this necessary:
    #
    #   1. The scan was `-name '*.swift'` only. Seven paired overlays are not
    #      Swift, and one of them — macos/Sources/App/macOS/MainMenu.xib — had
    #      silently lost the entire upstream Find menu plus Reload
    #      Configuration, Change Tab Title and Terminal Read-only. Ten
    #      @IBOutlets in AppDelegate were nil at runtime. NSMenuItem outlets are
    #      optional, so nothing failed to compile and nothing failed to build.
    #
    #   2. A missing upstream counterpart was `continue` — indistinguishable
    #      from a YEN-only overlay. Upstream deleting or relocating a file YEN
    #      forks would resurrect dead code with no signal at all.
    #
    # A path in this manifest MUST have an upstream counterpart; losing one is
    # a relocation and fails closed. Anything not listed is a YEN-only file and
    # is not checked. Regenerate deliberately after porting a real upstream
    # move — never to silence this gate.
    OVERLAY_PAIRS="$YEN_TERMINAL/.overlay-upstream-pairs.txt"
    if [ ! -s "$OVERLAY_PAIRS" ]; then
        echo "  ERROR: overlay/upstream pair manifest missing or empty: $OVERLAY_PAIRS"
        echo "  Refusing to report structural parity without it."
        [ -d "ghostty.backup" ] && { rm -rf ghostty; mv ghostty.backup ghostty; }
        exit 1
    fi

    OVERLAY_LOST_COUNT=0
    OVERLAY_DRIFT_COUNT=0
    OVERLAY_PAIR_COUNT=0
    OVERLAY_REPIN=""

    while IFS="$(printf '\t')" read -r rel pinned_sha; do
        [ -n "$rel" ] || continue
        case "$rel" in \#*) continue ;; esac
        OVERLAY_PAIR_COUNT=$((OVERLAY_PAIR_COUNT + 1))
        overlay_file="overlays/$rel"
        upstream="ghostty/$rel"

        if [ ! -f "$overlay_file" ]; then
            echo "  ERROR: manifest lists an overlay that no longer exists: $rel"
            OVERLAY_LOST_COUNT=$((OVERLAY_LOST_COUNT + 1))
            continue
        fi
        if [ ! -f "$upstream" ]; then
            if [ "$OVERLAY_LOST_COUNT" -eq 0 ]; then
                echo "  ERROR: upstream counterparts vanished for overlays that replace them:"
            fi
            echo "    $rel"
            OVERLAY_LOST_COUNT=$((OVERLAY_LOST_COUNT + 1))
            continue
        fi

        upstream_sha=$(shasum -a 256 "$upstream" | awk '{print $1}')
        OVERLAY_REPIN="${OVERLAY_REPIN}${rel}$(printf '\t')${upstream_sha}
"

        if [ -z "$pinned_sha" ]; then
            echo "  ERROR: no upstream content pin recorded for $rel"
            OVERLAY_DRIFT_COUNT=$((OVERLAY_DRIFT_COUNT + 1))
        elif [ "$pinned_sha" != "$upstream_sha" ]; then
            if [ "$OVERLAY_DRIFT_COUNT" -eq 0 ]; then
                echo "  ERROR: upstream CHANGED files that YEN replaces wholesale."
                echo "  The overlay copy silently discards these upstream edits — no diff, no compile error:"
            fi
            echo "    $rel"
            echo "      pinned:  $pinned_sha"
            echo "      current: $upstream_sha"
            OVERLAY_DRIFT_COUNT=$((OVERLAY_DRIFT_COUNT + 1))
        fi
    done < "$OVERLAY_PAIRS"

    if [ "$OVERLAY_LOST_COUNT" -gt 0 ]; then
        echo "  ${OVERLAY_LOST_COUNT} overlay/upstream pair(s) broken — upstream moved, renamed or deleted them."
        echo "  Re-anchor the overlay against the new upstream location, then regenerate the manifest."
        echo "  Structural breaks are NOT covered by the content-drift bypass."
        if [ "${YEN_VENDOR_ACCEPT_OVERLAY_PAIR_LOSS:-0}" != "1" ]; then
        [ -d "ghostty.backup" ] && { rm -rf ghostty; mv ghostty.backup ghostty; }
            exit 1
        fi
        echo "  WARNING: pair loss accepted via YEN_VENDOR_ACCEPT_OVERLAY_PAIR_LOSS=1"
    fi

    if [ "$OVERLAY_DRIFT_COUNT" -gt 0 ]; then
        echo "  ${OVERLAY_DRIFT_COUNT} upstream file(s) changed under a whole-file overlay."
        echo "  Read upstream's change, port what applies into yen-terminal/overlays/, then"
        echo "  re-run with YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1 to re-pin."
        if [ "${YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT:-0}" != "1" ]; then
        [ -d "ghostty.backup" ] && { rm -rf ghostty; mv ghostty.backup ghostty; }
            exit 1
        fi
        # Only re-pin a complete set; a short write would drop files from coverage.
        if [ "$(printf '%s' "$OVERLAY_REPIN" | grep -c .)" -eq "$OVERLAY_PAIR_COUNT" ]; then
            {
                grep '^#' "$OVERLAY_PAIRS"
                printf '%s' "$OVERLAY_REPIN"
            } > "$OVERLAY_PAIRS.tmp" && mv "$OVERLAY_PAIRS.tmp" "$OVERLAY_PAIRS"
            chmod 644 "$OVERLAY_PAIRS"
            echo "  WARNING: content drift accepted and re-pinned via YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT=1"
        else
            echo "  ERROR: refusing to re-pin an incomplete manifest."
        [ -d "ghostty.backup" ] && { rm -rf ghostty; mv ghostty.backup ghostty; }
            exit 1
        fi
    fi

    # Informational: a paired overlay that is not yet in the manifest is
    # unwatched. Not fatal — adding an overlay is normal — but it should be
    # recorded so the next upstream move is caught.
    OVERLAY_UNTRACKED=0
    while IFS= read -r overlay_file; do
        rel="${overlay_file#overlays/}"
        [ -f "ghostty/$rel" ] || continue
        cut -f1 "$OVERLAY_PAIRS" | grep -Fxq "$rel" && continue
        if [ "$OVERLAY_UNTRACKED" -eq 0 ]; then
            echo "  NOTE: paired overlays missing from the manifest (add them so upstream moves are caught):"
        fi
        echo "    $rel"
        OVERLAY_UNTRACKED=$((OVERLAY_UNTRACKED + 1))
    done < <(/usr/bin/find overlays -type f -not -path '*/.zig-cache/*' 2>/dev/null)

    # Both halves clean. The old "N of M diverge" line is gone: forks ALWAYS
    # diverge from upstream, so it fired on every pair every run and carried no
    # signal. Content drift against the pinned upstream hash is the real one.
    echo "  Overlay pairs: ${OVERLAY_PAIR_COUNT} tracked, upstream unchanged."

    # Build.zig drift gate (fail-closed). The overlay legitimately diverges from
    # upstream ONLY by YEN's documented customizations: the YEN Custom Resources
    # block, "// YEN:" comments, and the branded libyen-vt / include/yen /
    # <yen/vt.h> literals. scripts/lib/normalize-overlay-buildzig.py reverses
    # exactly those, and the result is compared against the freshly downloaded
    # upstream build.zig; anything left over is upstream-side drift that the
    # overlay copy would SILENTLY DROP.
    # At this phase ghostty/build.zig is pristine upstream (overlays not yet
    # applied). Bypass only if the drift is intentionally unported:
    #   YEN_VENDOR_SKIP_BUILDZIG_DRIFT=1
    if [ -f overlays/build.zig ] && [ -f ghostty/build.zig ]; then
        STRIPPED_BUILDZIG=$(python3 "$REPO_ROOT/scripts/lib/normalize-overlay-buildzig.py" overlays/build.zig) || {
            echo "  ERROR: could not normalize overlays/build.zig for the drift check."
            [ -d "ghostty.backup" ] && { rm -rf ghostty; mv ghostty.backup ghostty; }
            exit 1
        }
        if ! /usr/bin/diff -B <(printf '%s\n' "$STRIPPED_BUILDZIG") ghostty/build.zig >/dev/null 2>&1; then
            if [ "${YEN_VENDOR_SKIP_BUILDZIG_DRIFT:-0}" = "1" ]; then
                echo "  WARNING: upstream build.zig drift detected — bypassed via YEN_VENDOR_SKIP_BUILDZIG_DRIFT=1"
            else
                echo "  ERROR: upstream build.zig changed outside the documented YEN customizations."
                echo "  The overlay copy would silently drop these upstream build changes."
                echo "  Port them into yen-terminal/overlays/build.zig, then retry."
                echo "  Drift (overlay with YEN customizations normalized) vs fresh upstream:"
                { /usr/bin/diff -u <(printf '%s\n' "$STRIPPED_BUILDZIG") ghostty/build.zig || true; } | head -60
                echo "  Bypass only if intentional: YEN_VENDOR_SKIP_BUILDZIG_DRIFT=1"
                if [ -d "ghostty.backup" ]; then
                    echo "  Restoring previous ghostty/ from backup..."
                    rm -rf ghostty
                    mv ghostty.backup ghostty
                fi
                exit 1
            fi
        else
            echo "  build.zig: only YEN customization diverges (no upstream drift)."
        fi
    fi

    # The separate .build-overlay-upstream.sha256 tripwire is retired: its three
    # entries (build.zig, src/build/main.zig, src/build/LibtoolStep.zig) were a
    # strict subset of the manifest above, which now pins upstream content for
    # every paired overlay rather than only the Zig build files.
fi
fi

echo "[3/5] Applying overlays..."

if [ -f "apply-overlays.sh" ]; then
    bash apply-overlays.sh || {
        echo "ERROR: apply-overlays.sh failed"
        # Restore backup if available
        if [ -d "ghostty.backup" ]; then
            echo "  Restoring previous ghostty/ from backup..."
            rm -rf ghostty
            mv ghostty.backup ghostty
        fi
        exit 1
    }
else
    echo "ERROR: apply-overlays.sh not found"
    exit 1
fi

# Overlays succeeded. Verify branding BEFORE bumping any tracking file, so a
# branding regression aborts the run without persisting a new baseline. The
# backup is kept until verification passes so we can roll the tree back.
echo "[4/5] Verifying..."

VERIFY_SCRIPT="$REPO_ROOT/scripts/04-verify-branding.sh"
# A missing verifier must abort, not skip. Skipping here would delete
# ghostty.backup and persist a new baseline with zero verification — the same
# class of failure d6b7eb0f5 hardened this block against. Matches the
# apply-overlays.sh existence check above.
if [ ! -f "$VERIFY_SCRIPT" ]; then
    echo "ERROR: branding verifier not found at $VERIFY_SCRIPT"
    if [ -d "ghostty.backup" ]; then
        echo "  Restoring previous ghostty/ from backup..."
        rm -rf ghostty
        mv ghostty.backup ghostty
    fi
    exit 1
fi
if ! bash "$VERIFY_SCRIPT"; then
    echo "ERROR: branding verification failed — refusing to bump baseline"
    if [ -d "ghostty.backup" ]; then
        echo "  Restoring previous ghostty/ from backup..."
        rm -rf ghostty
        mv ghostty.backup ghostty
    fi
    exit 1
fi

# Verification passed — safe to remove backup and persist tracking files
rm -rf ghostty.backup

TRACKING_NEEDS_REFRESH=0
if [ "$SKIP_DOWNLOAD" -eq 1 ]; then
    CURRENT_VENDOR_INFO_VERSION=""
    if [ -f "VENDOR_INFO.txt" ]; then
        CURRENT_VENDOR_INFO_VERSION=$(sed -n 's/^Version: //p' VENDOR_INFO.txt | head -1)
    fi

    if [ "$CURRENT_BASELINE_VERSION" != "$VERSION" ] || [ "$CURRENT_VENDOR_INFO_VERSION" != "$VERSION" ]; then
        TRACKING_NEEDS_REFRESH=1
    fi
fi

if [ "$SKIP_DOWNLOAD" -eq 0 ] || [ "$TRACKING_NEEDS_REFRESH" -eq 1 ]; then
    echo "[5/5] Updating tracking..."
    write_tracking_files
fi

echo "Vendor update: $VERSION (${COMMIT_HASH:0:8})"
echo "Next: ./customizations/build-release.sh"

if [ "$SKIP_DOWNLOAD" -eq 1 ]; then
    gate_unit_skipped download "already at $VERSION (no fresh tree fetched)"
    # [3a/5] only runs on a fresh tree: on the up-to-date path ghostty/ still
    # holds the previous run's applied overlays, so every comparison would be
    # against itself.
    gate_unit_skipped structural-diff "not run on the already-current path"
else
    gate_unit_ran download "version=$VERSION commit=${COMMIT_HASH:0:8}"
    gate_unit_ran structural-diff "overlay_pairs=$(grep -vc '^#' "$REPO_ROOT/yen-terminal/.overlay-upstream-pairs.txt" 2>/dev/null || true)"
fi
gate_unit_ran overlays-applied "overlay_files=$(/usr/bin/find "$REPO_ROOT/yen-terminal/overlays" -type f 2>/dev/null | grep -c . || true)"
if [ "$SKIP_DOWNLOAD" -eq 0 ] || [ "$TRACKING_NEEDS_REFRESH" -eq 1 ]; then
    gate_unit_ran tracking-files "baseline+VENDOR_INFO written for $VERSION"
else
    gate_unit_skipped tracking-files "already current at $VERSION"
fi
gate_end 0
