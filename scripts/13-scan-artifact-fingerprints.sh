#!/bin/bash
# Artifact fingerprint scanner for shipped YEN desktop artifacts.
#
# Scans built app bundles and/or DMGs for lineage/provenance indicators:
# - ghostty branding/token residues
# - com.mitchellh.ghostty identifiers
# - upstream Ghostty repo URLs (pattern from scripts/lib/upstream.sh)
# - build path leakage (.zig-global-cache)
# - ReleaseLocal build markers
# - locale catalog string branding residues (.mo payloads)
#
# Usage:
#   ./scripts/13-scan-artifact-fingerprints.sh
#   ./scripts/13-scan-artifact-fingerprints.sh --app /path/to/YEN.app
#   ./scripts/13-scan-artifact-fingerprints.sh --dmg /path/to/yen-0XX.dmg
#   ./scripts/13-scan-artifact-fingerprints.sh --gate-mode report
#   ./scripts/13-scan-artifact-fingerprints.sh --skip-codesig
#   ./scripts/13-scan-artifact-fingerprints.sh --allowlist scripts/lib/fingerprint-allowlist.txt

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"

DEFAULT_APP_PATH="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"
DEFAULT_ALLOWLIST="$REPO_ROOT/scripts/lib/fingerprint-allowlist.txt"
DEFAULT_DMG_PATH=""

VERSION_JSON="$REPO_ROOT/public/stable/version.json"
if [ -f "$VERSION_JSON" ]; then
    VERSION="$(get_version "$VERSION_JSON" 2>/dev/null || true)"
    if [ -n "$VERSION" ]; then
        DMG_FILENAME="$(get_dmg_filename "$VERSION" 2>/dev/null || true)"
        if [ -n "$DMG_FILENAME" ] && [ -f "$REPO_ROOT/public/stable/$DMG_FILENAME" ]; then
            DEFAULT_DMG_PATH="$REPO_ROOT/public/stable/$DMG_FILENAME"
        fi
    fi
fi

APP_PATH=""
DMG_PATH=""
ALLOWLIST_PATH="$DEFAULT_ALLOWLIST"
GATE_MODE="enforce"

# Payloads actually opened by the strings scans. An empty scan set must never
# read as a clean result — reproduced: a bundle containing one text file
# returned `RESULT total=0 ... mode=enforce` with exit 0.
SCANNED_PAYLOADS=0
APP_TARGET_SET=0
DMG_TARGET_SET=0
SCAN_CODESIG=1

usage() {
    cat <<'USAGE'
Usage: ./scripts/13-scan-artifact-fingerprints.sh [options]

Options:
  --app <path>          Scan this YEN.app bundle
  --dmg <path>          Scan this DMG (mounts read-only, scans YEN.app payload)
  --allowlist <path>    Regex allowlist file (one regex per line; # comments allowed)
  --gate-mode <mode>    off | report | enforce
  --skip-codesig        Skip _CodeSignature/CodeResources scanning (local unsigned/ad-hoc scans)
  --help, -h            Show help

Defaults:
  --app      yen-terminal/ghostty/zig-out/YEN.app (if present)
  --dmg      public/stable/<current version dmg> (if present)
  --allowlist scripts/lib/fingerprint-allowlist.txt
  --gate-mode enforce
  --skip-codesig disabled (code-signature metadata scanned)
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            APP_PATH="${2:-}"
            APP_TARGET_SET=1
            shift 2
            ;;
        --dmg)
            DMG_PATH="${2:-}"
            DMG_TARGET_SET=1
            shift 2
            ;;
        --allowlist)
            ALLOWLIST_PATH="${2:-}"
            shift 2
            ;;
        --gate-mode)
            GATE_MODE="${2:-}"
            shift 2
            ;;
        --skip-codesig)
            SCAN_CODESIG=0
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

case "$GATE_MODE" in
    off|report|enforce) ;;
    *)
        echo "ERROR: Invalid --gate-mode '$GATE_MODE' (expected off|report|enforce)" >&2
        exit 1
        ;;
esac

if [ "$GATE_MODE" = "off" ]; then
    echo "Artifact fingerprint scan"
    echo "  Gate mode: off"
    echo "  Result: skipped"
    echo "RESULT total=0 allowlisted=0 remaining=0 scanned=0 mode=off"
    gate_end_disabled "gate mode off"
fi

# Only auto-discover default targets when no explicit target flags were passed.
if [ "$APP_TARGET_SET" -eq 0 ] && [ "$DMG_TARGET_SET" -eq 0 ]; then
    if [ -d "$DEFAULT_APP_PATH" ]; then
        APP_PATH="$DEFAULT_APP_PATH"
    fi
    if [ -n "$DEFAULT_DMG_PATH" ]; then
        DMG_PATH="$DEFAULT_DMG_PATH"
    fi
fi

if [ -n "$APP_PATH" ] && [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App path not found: $APP_PATH" >&2
    exit 1
fi
if [ -n "$DMG_PATH" ] && [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG path not found: $DMG_PATH" >&2
    exit 1
fi
if [ -z "$APP_PATH" ] && [ -z "$DMG_PATH" ]; then
    echo "ERROR: No scan targets found (provide --app and/or --dmg)." >&2
    exit 1
fi

PATTERN_NAMES=(
    "ghostty"
    "com_mitchellh_ghostty"
    "ghostty_upstream_url"
    "zig_global_cache"
    "release_local"
)
PATTERN_REGEX=(
    "[Gg][Hh][Oo][Ss][Tt][Tt][Yy]"
    "com\\.mitchellh\\.ghostty"
    "$(upstream_url_pattern_regex)"
    "\\.zig-global-cache"
    "ReleaseLocal"
)

FINDINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/yen-fingerprint-findings.XXXXXX")"
FILTERED_FILE="$(mktemp "${TMPDIR:-/tmp}/yen-fingerprint-filtered.XXXXXX")"
ALLOWED_FILE="$(mktemp "${TMPDIR:-/tmp}/yen-fingerprint-allowed.XXXXXX")"
DMG_MOUNT_PATH=""
FINGERPRINT_WORKER_DIR=""

# Concurrency for the per-binary / per-locale strings scans. The strings work is
# CPU-bound and embarrassingly parallel; findings are sort -u'd before allowlisting
# so worker scheduling cannot change the result set. Override via env for tests.
FINGERPRINT_SCAN_JOBS="${YEN_FINGERPRINT_SCAN_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
case "$FINGERPRINT_SCAN_JOBS" in
    ''|*[!0-9]*) FINGERPRINT_SCAN_JOBS=4 ;;
esac
[ "$FINGERPRINT_SCAN_JOBS" -lt 1 ] && FINGERPRINT_SCAN_JOBS=1

cleanup() {
    [ -n "$FINGERPRINT_WORKER_DIR" ] && [ -d "$FINGERPRINT_WORKER_DIR" ] && rm -rf "$FINGERPRINT_WORKER_DIR"
    rm -f "$FINDINGS_FILE" "$FILTERED_FILE" "$ALLOWED_FILE"
    if [ -n "$DMG_MOUNT_PATH" ] && [ -d "$DMG_MOUNT_PATH" ]; then
        hdiutil detach "$DMG_MOUNT_PATH" -force >/dev/null 2>&1 || true
    fi
}
# The completion sentinel is now the shared one in scripts/lib/gate-receipt.sh.
# It was hand-copied into three scripts (05, 10, 13); the third copy's comment
# named the first two and still copy-pasted. gate_begin takes this script's own
# cleanup because bash 3.2 traps are single-slot -- installing a second EXIT trap
# here would silently replace the abort handler.
gate_begin 13-scan-artifact-fingerprints cleanup

# Emit one sanitized "category|location|sample" line to stdout. Shared by the
# serial scanners (which append to FINDINGS_FILE) and the parallel workers (which
# append to their own private file) so the line format stays identical.
format_finding() {
    local category="$1"
    local location="$2"
    local sample="$3"

    sample="$(printf '%s' "$sample" | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-240)"
    printf '%s|%s|%s\n' "$category" "$location" "$sample"
}

add_finding() {
    format_finding "$1" "$2" "$3" >> "$FINDINGS_FILE"
}

scan_path_tokens() {
    local app_root="$1"
    local scope="$2"
    local rel_list path_line rel idx

    # Materialize the bundle's relative-path list once, then run a single grep
    # pass per pattern over it — instead of one `printf | grep` per
    # path-per-pattern (~5.2k pipelines per ~1k-path bundle). Findings are
    # sort -u'd downstream, so emission order is irrelevant; the per-line regex
    # match per pattern is identical to the original.
    rel_list="$(mktemp "${TMPDIR:-/tmp}/yen-fingerprint-paths.XXXXXX")"
    while IFS= read -r path_line; do
        rel="${path_line#$app_root/}"
        [ "$rel" = "$path_line" ] && rel="${path_line#$app_root}"
        rel="${rel#/}"
        printf '%s\n' "$rel"
    done < <(find "$app_root" -print) > "$rel_list"

    idx=0
    while [ "$idx" -lt "${#PATTERN_NAMES[@]}" ]; do
        while IFS= read -r rel; do
            add_finding "path:${PATTERN_NAMES[$idx]}" "$scope:$rel" "$rel"
        done < <(grep -E "${PATTERN_REGEX[$idx]}" "$rel_list" || true)
        idx=$((idx + 1))
    done

    rm -f "$rel_list"
}

scan_codesign_tokens() {
    local app_root="$1"
    local scope="$2"
    local code_resources="$app_root/Contents/_CodeSignature/CodeResources"
    local idx line line_no content

    [ -f "$code_resources" ] || return 0

    idx=0
    while [ "$idx" -lt "${#PATTERN_NAMES[@]}" ]; do
        while IFS= read -r line; do
            line_no="${line%%:*}"
            content="${line#*:}"
            add_finding "codesig:${PATTERN_NAMES[$idx]}" "$scope:_CodeSignature/CodeResources:$line_no" "$content"
        done < <(grep -En "${PATTERN_REGEX[$idx]}" "$code_resources" || true)
        idx=$((idx + 1))
    done
}

# Scan one file's `strings` output for all lineage patterns. Findings are written
# to a PRIVATE ".partial" file, which is atomically renamed to "$out" ONLY after the
# full pattern loop completes. FAIL-CLOSED by construction: "$out" exists IFF this
# worker finished, so a worker killed mid-write leaves only ".partial" (never
# concatenated into FINDINGS_FILE, and its missing "$out" trips the completeness
# gate) — partial coverage can never masquerade as complete. An unreadable file
# emits a synthetic scan_error finding so a payload is never silently dropped.
# Mach-O filtering is done by the caller, so every file handed here IS scanned.
#   $1 file  $2 rel  $3 scope  $4 category_prefix (binary|locale)  $5 out
scan_one_file_strings() {
    local file="$1" rel="$2" scope="$3" category_prefix="$4" out="$5"
    local work="${out}.partial"
    local strings_file idx line line_no content

    : > "$work"

    strings_file="$(mktemp "${TMPDIR:-/tmp}/yen-fingerprint-strings.XXXXXX")"
    if ! strings -a "$file" > "$strings_file" 2>/dev/null; then
        format_finding "${category_prefix}:scan_error" "$scope:$rel" "strings failed to read $rel" >> "$work"
        rm -f "$strings_file"
        mv "$work" "$out"   # atomic completion (even the error path is "complete")
        return 0
    fi

    idx=0
    while [ "$idx" -lt "${#PATTERN_NAMES[@]}" ]; do
        while IFS= read -r line; do
            line_no="${line%%:*}"
            content="${line#*:}"
            format_finding "${category_prefix}:${PATTERN_NAMES[$idx]}" "$scope:$rel:$line_no" "$content" >> "$work"
        done < <(grep -En "${PATTERN_REGEX[$idx]}" "$strings_file" || true)
        idx=$((idx + 1))
    done

    rm -f "$strings_file"
    mv "$work" "$out"   # atomic: "$out" appears only after the FULL pattern loop
}

# Run scan_one_file_strings over a NUL-separated file list (stdin) with bounded
# concurrency, then concatenate the COMPLETED worker outputs into FINDINGS_FILE.
# Each worker's "$out" appears only via atomic rename on full completion, so the
# completeness check (produced == launched) fails closed if any worker died mid-scan.
# Output order is irrelevant — the caller sort -u's FINDINGS_FILE.
#   $1 app_root  $2 scope  $3 category_prefix
parallel_strings_scan() {
    local app_root="$1" scope="$2" category_prefix="$3"
    local file rel out n=0 running=0 produced pids=""

    FINGERPRINT_WORKER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yen-fp-workers.XXXXXX")"

    while IFS= read -r -d '' file; do
        rel="${file#$app_root/}"
        [ "$rel" = "$file" ] && rel="${file#$app_root}"
        rel="${rel#/}"
        out="$FINGERPRINT_WORKER_DIR/$n"
        n=$((n + 1))
        scan_one_file_strings "$file" "$rel" "$scope" "$category_prefix" "$out" &
        pids="$pids $!"
        running=$((running + 1))
        if [ "$running" -ge "$FINGERPRINT_SCAN_JOBS" ]; then
            wait $pids 2>/dev/null || true
            pids=""
            running=0
        fi
    done
    [ "$running" -gt 0 ] && { wait $pids 2>/dev/null || true; }

    # Completeness: count only COMPLETED outputs (atomic rename drops the ".partial"
    # suffix). A short count means a worker died mid-scan → fail closed.
    produced=$(find "$FINGERPRINT_WORKER_DIR" -type f ! -name '*.partial' | wc -l | tr -d ' ')
    if [ "$produced" -ne "$n" ]; then
        add_finding "${category_prefix}:scan_incomplete" "$scope" "parallel scan produced $produced/$n completed worker outputs (coverage gap)"
    fi

    if [ "$n" -gt 0 ]; then
        find "$FINGERPRINT_WORKER_DIR" -type f ! -name '*.partial' -exec cat {} + >> "$FINDINGS_FILE" 2>/dev/null || true
    fi

    rm -rf "$FINGERPRINT_WORKER_DIR"
    FINGERPRINT_WORKER_DIR=""
}

scan_binary_tokens() {
    local app_root="$1"
    local scope="$2"
    local app_launcher="$app_root/Contents/MacOS/yen"
    local bundled_cli="$app_root/Contents/Resources/bin/yen"
    # Pre-filter to Mach-O binaries (plus the app launcher and bundled shell CLI,
    # which are force-scanned even if `file` doesn't classify them as Mach-O) in
    # the launcher — serial `file` is cheap, and this keeps the worker pool to the
    # handful of relevant payloads instead of forking a subshell per bundle file.
    # parallel_strings_scan still runs in THIS shell (input via process
    # substitution) so FINGERPRINT_WORKER_DIR stays visible to the cleanup trap.
    # `file` is the Mach-O classifier for everything except the two force-scanned
    # paths. If it is missing from PATH the pre-filter silently yields almost
    # nothing and the gate reports a clean scan of an unscanned bundle, so make
    # its absence fatal rather than quiet.
    if ! command -v file >/dev/null 2>&1; then
        echo "ERROR: \`file\` not found in PATH — cannot classify Mach-O payloads." >&2
        echo "       Refusing to report a fingerprint result from an unfiltered scan." >&2
        exit 1
    fi

    # Materialize the payload list so it can be counted. Built inside the process
    # substitution it lives in a subshell, and the count needed for the coverage
    # assertion below would be lost.
    # Own temp file: FINGERPRINT_WORKER_DIR is created inside
    # parallel_strings_scan and is empty here.
    local payload_list
    payload_list="$(mktemp "${TMPDIR:-/tmp}/yen-fp-payloads.XXXXXX")"
    find "$app_root" -type f -print0 | while IFS= read -r -d '' f; do
        if [ "$f" = "$app_launcher" ] || [ "$f" = "$bundled_cli" ] || file "$f" 2>/dev/null | grep -q "Mach-O"; then
            printf '%s\0' "$f"
        fi
    done > "$payload_list"

    local n
    n=$(tr -cd '\0' < "$payload_list" | wc -c | tr -d ' ')
    SCANNED_PAYLOADS=$((SCANNED_PAYLOADS + n))

    parallel_strings_scan "$app_root" "$scope" "binary" < "$payload_list"
    rm -f "$payload_list"
}

scan_locale_tokens() {
    local app_root="$1"
    local scope="$2"
    local locale_root
    locale_root="$app_root/Contents/Resources/locale"
    [ -d "$locale_root" ] || return 0
    SCANNED_PAYLOADS=$((SCANNED_PAYLOADS + $(find "$locale_root" -type f -name '*.mo' 2>/dev/null | wc -l | tr -d ' ')))
    parallel_strings_scan "$app_root" "$scope" "locale" \
        < <(find "$locale_root" -type f -name "*.mo" -print0)
}

scan_app() {
    local app_root="$1"
    local scope="$2"

    scan_path_tokens "$app_root" "$scope"
    if [ "$SCAN_CODESIG" -eq 1 ]; then
        scan_codesign_tokens "$app_root" "$scope"
    fi
    scan_binary_tokens "$app_root" "$scope"
    scan_locale_tokens "$app_root" "$scope"
}

scan_dmg() {
    local dmg_file="$1"
    local mount_output dmg_app

    mount_output="$(hdiutil attach -readonly -nobrowse "$dmg_file" 2>/dev/null || true)"
    DMG_MOUNT_PATH="$(printf '%s\n' "$mount_output" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)"

    if [ -z "$DMG_MOUNT_PATH" ] || [ ! -d "$DMG_MOUNT_PATH" ]; then
        add_finding "dmg:error" "$dmg_file" "failed to mount dmg for scanning"
        return
    fi

    dmg_app="$DMG_MOUNT_PATH/YEN.app"
    if [ ! -d "$dmg_app" ]; then
        add_finding "dmg:error" "$dmg_file" "YEN.app missing in mounted dmg"
        hdiutil detach "$DMG_MOUNT_PATH" -force >/dev/null 2>&1 || true
        DMG_MOUNT_PATH=""
        return
    fi

    scan_app "$dmg_app" "dmg"

    hdiutil detach "$DMG_MOUNT_PATH" -force >/dev/null 2>&1 || true
    DMG_MOUNT_PATH=""
}

is_allowlisted() {
    local finding="$1"
    local allow_rule

    [ -f "$ALLOWLIST_PATH" ] || return 1

    while IFS= read -r allow_rule || [ -n "$allow_rule" ]; do
        case "$allow_rule" in
            ""|\#*) continue ;;
        esac
        if printf '%s\n' "$finding" | grep -Eq "$allow_rule"; then
            return 0
        fi
    done < "$ALLOWLIST_PATH"

    return 1
}

if [ -n "$APP_PATH" ]; then
    scan_app "$APP_PATH" "app"
fi
if [ -n "$DMG_PATH" ]; then
    scan_dmg "$DMG_PATH"
fi

sort -u "$FINDINGS_FILE" -o "$FINDINGS_FILE"

while IFS= read -r finding || [ -n "$finding" ]; do
    [ -n "$finding" ] || continue
    if is_allowlisted "$finding"; then
        printf '%s\n' "$finding" >> "$ALLOWED_FILE"
    else
        printf '%s\n' "$finding" >> "$FILTERED_FILE"
    fi
done < "$FINDINGS_FILE"

TOTAL_FINDINGS=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
ALLOWED_FINDINGS=$(wc -l < "$ALLOWED_FILE" | tr -d ' ')
REMAINING_FINDINGS=$(wc -l < "$FILTERED_FILE" | tr -d ' ')

echo "Artifact fingerprint scan"
echo "  Gate mode: $GATE_MODE"
if [ "$SCAN_CODESIG" -eq 1 ]; then
    echo "  Code-signature scan: on"
else
    echo "  Code-signature scan: off (--skip-codesig)"
fi
if [ -n "$APP_PATH" ]; then
    echo "  App target: $APP_PATH"
fi
if [ -n "$DMG_PATH" ]; then
    echo "  DMG target: $DMG_PATH"
fi
if [ -f "$ALLOWLIST_PATH" ]; then
    echo "  Allowlist: $ALLOWLIST_PATH"
else
    echo "  Allowlist: (missing) $ALLOWLIST_PATH"
fi

echo "  Findings: total=$TOTAL_FINDINGS allowlisted=$ALLOWED_FINDINGS remaining=$REMAINING_FINDINGS"

if [ "$REMAINING_FINDINGS" -gt 0 ]; then
    echo ""
    echo "Remaining findings:"
    sed 's/^/  ! /' "$FILTERED_FILE"
fi

echo "RESULT total=$TOTAL_FINDINGS allowlisted=$ALLOWED_FINDINGS remaining=$REMAINING_FINDINGS scanned=$SCANNED_PAYLOADS mode=$GATE_MODE"

# Coverage assertion. Zero findings is only meaningful if something was read.
# Reproduced before this: a bundle holding one text file returned
# `RESULT total=0 ... mode=enforce` and exit 0 — "nothing to check" reading as
# a pass, which the repo's build-gate rule forbids outright.
if [ "$SCANNED_PAYLOADS" -eq 0 ]; then
    echo ""
    echo "  X Fingerprint scan opened ZERO payloads."
    echo "    total=0 here means 'nothing was examined', not 'nothing was wrong'."
    echo "    Check the target is a built app bundle and that \`file\` works."
    gate_unit_skipped payload-scan "zero payloads opened"
    gate_unit_skipped allowlist-filter "not reached: zero payloads"
    if [ "$GATE_MODE" = "enforce" ]; then
        gate_end 1 2
    fi
    gate_end 0
fi

gate_unit_ran payload-scan "scanned=$SCANNED_PAYLOADS findings=$TOTAL_FINDINGS"
gate_unit_ran allowlist-filter "allowlisted=$ALLOWED_FINDINGS remaining=$REMAINING_FINDINGS mode=$GATE_MODE"

if [ "$REMAINING_FINDINGS" -gt 0 ] && [ "$GATE_MODE" = "enforce" ]; then
    gate_end 1 2
fi

gate_end 0
