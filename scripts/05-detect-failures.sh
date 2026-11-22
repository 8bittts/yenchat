#!/bin/bash
# Silent Failure Detection Script
# Runs comprehensive verification AFTER build but BEFORE git commit.
# Outputs compact summary on success, details on failure.
#
# Usage: ./scripts/05-detect-failures.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
cd "$REPO_ROOT"

# Source shared utilities
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/required-app-bins.sh"
source "$REPO_ROOT/scripts/lib/signing-constants.sh"
source "$REPO_ROOT/scripts/lib/signature-utils.sh"
source "$REPO_ROOT/scripts/lib/release-constants.sh"
## privileged-surface-utils.sh — no longer needed here (promoted to 03-verify-components.sh)

FAILED=0
CHECKS=0
DETAILS=""
PARALLEL_GATE_DIR=""
PARALLEL_GATE_OUTCOME=""
PARALLEL_GATE_MESSAGE=""

fail() {
    DETAILS="$DETAILS\n    X $1"
    FAILED=1
}

cleanup_parallel_gate_dir() {
    if [ -n "${PARALLEL_GATE_DIR:-}" ] && [ -d "$PARALLEL_GATE_DIR" ]; then
        rm -rf "$PARALLEL_GATE_DIR"
    fi
}

# Completion sentinel. An EXIT trap SWALLOWS a `set -euo pipefail` fatal abort
# in bash 3.2: $? is already 0 when the trap fires, so the script exits 0 having
# verified nothing. Reproduced — with version.json absent this printed only
# "VERSION_FILENAME: unbound variable" and exited 0, which /update-yen Step 6 reads as
# PASS on a shipping gate. The `set -u` hole itself is fixed below by
# initializing the filenames, but any future abort in a 1000-line script would
# do the same, so assert we actually reached the summary.
# The sentinel is now the shared one in scripts/lib/gate-receipt.sh -- this was
# one of three hand-written copies. bash 3.2 traps are single-slot, so the
# existing cleanup is handed to gate_begin rather than installed separately.
gate_begin 05-detect-failures cleanup_parallel_gate_dir

summarize_output() {
    echo "$1" | tail -n 40 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g'
}

to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

repo_relative_path() {
    local raw="$1"
    echo "$raw" | sed "s|^$REPO_ROOT/||"
}

normalize_signature_body() {
    local raw="$1"
    local extracted

    extracted=$(printf "%s" "$raw" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$extracted" ]; then
        printf "%s" "$extracted" | tr -d '[:space:]'
    else
        printf "%s" "$raw" | tr -d '[:space:]'
    fi
}

is_domain_allowlisted() {
    local domain
    domain=$(to_lowercase "$1")
    local allowlist_file="$2"
    local regex=""

    if [ ! -f "$allowlist_file" ]; then
        return 1
    fi

    while IFS= read -r regex || [ -n "$regex" ]; do
        case "$regex" in
            ""|\#*)
                continue
                ;;
        esac
        if echo "$domain" | grep -Eq "$regex"; then
            return 0
        fi
    done < "$allowlist_file"

    return 1
}

extract_urls_from_text_artifact() {
    local file_path="$1"

    grep -Eo 'https?://[^"'\''<>()[:space:]]+' "$file_path" 2>/dev/null | \
        sed 's/[),.;:]$//' | \
        sort -u || true
}

run_artifact_credential_url_scan() {
    local findings_file="$1"
    local allowlist_file="$2"
    shift 2
    local files=("$@")

    : > "$findings_file"

    if [ ! -f "$allowlist_file" ]; then
        echo "allowlist file missing: $(repo_relative_path "$allowlist_file")" >&2
        return 1
    fi

    local artifact_file=""
    local artifact_rel=""
    local mime_type=""
    local urls=""
    local url=""
    local domain=""
    local credentials_in_url=""
    local sensitive_query=""
    local credential_hits=""

    for artifact_file in "${files[@]}"; do
        [ -f "$artifact_file" ] || continue

        mime_type=$(file -b --mime-type "$artifact_file" 2>/dev/null || echo "")
        case "$mime_type" in
            text/*|application/json|application/xml|application/x-plist|application/x-empty)
                ;;
            *)
                continue
                ;;
        esac

        artifact_rel=$(repo_relative_path "$artifact_file")
        urls=$(extract_urls_from_text_artifact "$artifact_file")
        if [ -n "$urls" ]; then
            while IFS= read -r url; do
                [ -n "$url" ] || continue
                domain=$(echo "$url" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://([^/?#:]+).*#\1#')
                domain=$(to_lowercase "$domain")

                if ! is_domain_allowlisted "$domain" "$allowlist_file"; then
                    echo "unexpected-url-domain|$artifact_rel|$domain|$url" >> "$findings_file"
                fi

                credentials_in_url=$(echo "$url" | sed -nE 's#^[A-Za-z][A-Za-z0-9+.-]*://([^/]+).*$#\1#p' | grep '@' || true)
                [ -n "$credentials_in_url" ] && echo "url-contains-userinfo|$artifact_rel|$url" >> "$findings_file"

                sensitive_query=$(echo "$url" | grep -Eio '[?&](token|access_token|apikey|api_key|signature|sig|key)=' || true)
                [ -n "$sensitive_query" ] && echo "url-contains-sensitive-query|$artifact_rel|$url" >> "$findings_file"
            done <<< "$urls"
        fi

        credential_hits=$(grep -En \
            -e 'gh[pousr]_[A-Za-z0-9]{36,}' \
            -e 'github_pat_[A-Za-z0-9_]{40,}' \
            -e 'AKIA[0-9A-Z]{16}' \
            -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
            -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
            "$artifact_file" 2>/dev/null || true)
        if [ -n "$credential_hits" ]; then
            while IFS= read -r hit; do
                [ -n "$hit" ] || continue
                echo "credential-pattern|$artifact_rel|$hit" >> "$findings_file"
            done <<< "$credential_hits"
        fi
    done

    return 0
}

write_parallel_gate_result() {
    local result_file="$1"
    local outcome="$2"
    local message="${3:-}"
    local tmp_file

    tmp_file=$(mktemp "${result_file}.XXXXXX" 2>/dev/null) || return 1
    {
        printf '%s\n' "$outcome"
        printf '%s\n' "$message"
    } > "$tmp_file"
    mv "$tmp_file" "$result_file"
}

read_parallel_gate_result() {
    local result_file="$1"

    PARALLEL_GATE_OUTCOME=""
    PARALLEL_GATE_MESSAGE=""

    [ -f "$result_file" ] || return 1

    PARALLEL_GATE_OUTCOME=$(sed -n '1p' "$result_file" 2>/dev/null || echo "")
    PARALLEL_GATE_MESSAGE=$(sed '1d' "$result_file" 2>/dev/null || true)
    return 0
}

apply_parallel_gate_result() {
    local result_file="$1"

    if ! read_parallel_gate_result "$result_file"; then
        fail "Parallel gate result missing: $(basename "$result_file")"
        return
    fi

    case "$PARALLEL_GATE_OUTCOME" in
        pass|"")
            ;;
        detail)
            DETAILS="$DETAILS\n    ! $PARALLEL_GATE_MESSAGE"
            ;;
        fail)
            fail "$PARALLEL_GATE_MESSAGE"
            ;;
        *)
            fail "Parallel gate produced invalid outcome '$PARALLEL_GATE_OUTCOME'"
            ;;
    esac
}

run_artifact_url_scan_gate() {
    local result_file="$1"
    local findings_file=""
    local artifact_scan_findings_count=""
    local artifact_scan_summary=""

    if [ "$ARTIFACT_URL_SCAN_GATE_MODE" = "off" ]; then
        write_parallel_gate_result "$result_file" "detail" "Artifact credential/URL scan skipped (YEN_ARTIFACT_URL_SCAN_GATE_MODE=off)" || true
        return 0
    fi

    findings_file=$(mktemp "$PARALLEL_GATE_DIR/artifact-url-findings.XXXXXX" 2>/dev/null || echo "")
    if [ -z "$findings_file" ]; then
        write_parallel_gate_result "$result_file" "fail" "Artifact credential/URL scan could not create temp file" || true
        return 0
    fi

    if ! run_artifact_credential_url_scan "$findings_file" "$ARTIFACT_URL_ALLOWLIST_FILE" \
        "$VERSION_JSON" "$APPCAST_XML" "$INFO_PLIST"; then
        rm -f "$findings_file"
        write_parallel_gate_result "$result_file" "fail" "Artifact credential/URL scan failed to execute" || true
        return 0
    fi

    artifact_scan_findings_count=$(wc -l < "$findings_file" | tr -d '[:space:]')
    if [ "$artifact_scan_findings_count" -gt 0 ]; then
        artifact_scan_summary=$(summarize_output "$(head -n 20 "$findings_file")")
        rm -f "$findings_file"
        if [ "$ARTIFACT_URL_SCAN_GATE_MODE" = "enforce" ]; then
            write_parallel_gate_result "$result_file" "fail" "Artifact credential/URL scan findings (blocking): $artifact_scan_summary" || true
        else
            write_parallel_gate_result "$result_file" "detail" "Artifact credential/URL scan findings (report-only): $artifact_scan_findings_count ($artifact_scan_summary)" || true
        fi
        return 0
    fi

    rm -f "$findings_file"
    write_parallel_gate_result "$result_file" "pass" "" || true
    return 0
}

run_fingerprint_gate() {
    local result_file="$1"
    local -a fp_cmd
    local fp_output=""
    local fp_status=0
    local fp_summary=""
    local fp_remaining=0

    if [ "$FINGERPRINT_GATE_MODE" = "off" ]; then
        write_parallel_gate_result "$result_file" "detail" "Artifact fingerprint gate skipped (YEN_FINGERPRINT_GATE_MODE=off)" || true
        return 0
    fi

    if [ ! -x "$FINGERPRINT_SCAN_SCRIPT" ]; then
        write_parallel_gate_result "$result_file" "fail" "Artifact fingerprint scanner missing or not executable: $FINGERPRINT_SCAN_SCRIPT" || true
        return 0
    fi

    fp_cmd=(bash "$FINGERPRINT_SCAN_SCRIPT" --gate-mode "$FINGERPRINT_GATE_MODE" --app "$BUILT_APP")
    [ -f "$RELEASE_DMG" ] && fp_cmd+=(--dmg "$RELEASE_DMG")
    [ -n "$FINGERPRINT_ALLOWLIST_FILE" ] && fp_cmd+=(--allowlist "$FINGERPRINT_ALLOWLIST_FILE")

    set +e
    fp_output=$("${fp_cmd[@]}" 2>&1)
    fp_status=$?
    set -e

    fp_summary=$(summarize_output "$fp_output")
    fp_remaining=$(echo "$fp_output" | sed -nE 's/.*remaining=([0-9]+).*/\1/p' | tail -1)
    [ -z "$fp_remaining" ] && fp_remaining=0

    if [ "$fp_status" -ne 0 ]; then
        if [ "$FINGERPRINT_GATE_MODE" = "enforce" ]; then
            write_parallel_gate_result "$result_file" "fail" "Artifact fingerprint gate failed (blocking): $fp_summary" || true
        else
            write_parallel_gate_result "$result_file" "fail" "Artifact fingerprint scan execution failed: $fp_summary" || true
        fi
        return 0
    fi

    if [ "$FINGERPRINT_GATE_MODE" = "report" ] && [ "$fp_remaining" -gt 0 ]; then
        write_parallel_gate_result "$result_file" "detail" "Artifact fingerprint findings (report-only): $fp_remaining remaining" || true
        return 0
    fi

    write_parallel_gate_result "$result_file" "pass" "" || true
    return 0
}

## snapshot_privileged_action_surface() — sourced from scripts/lib/privileged-surface-utils.sh
## validate_non_concurrency_allowlist_metadata() — sourced from scripts/lib/non-concurrency-utils.sh

ARTIFACT_URL_SCAN_GATE_MODE="${YEN_ARTIFACT_URL_SCAN_GATE_MODE:-enforce}"
case "$ARTIFACT_URL_SCAN_GATE_MODE" in
    off|report|enforce) ;;
    *)
        fail "Invalid YEN_ARTIFACT_URL_SCAN_GATE_MODE value: $ARTIFACT_URL_SCAN_GATE_MODE (expected off|report|enforce)"
        ARTIFACT_URL_SCAN_GATE_MODE="enforce"
        ;;
esac
ARTIFACT_URL_ALLOWLIST_FILE="${YEN_ARTIFACT_URL_ALLOWLIST_FILE:-$REPO_ROOT/scripts/lib/artifact-url-domain-allowlist.txt}"

## Privileged-action surface gate — promoted to pre-build (03-verify-components.sh Check 11).
## Removed from post-build: source files don't change during compilation.

FINGERPRINT_GATE_MODE="${YEN_FINGERPRINT_GATE_MODE:-enforce}"
case "$FINGERPRINT_GATE_MODE" in
    off|report|enforce) ;;
    *)
        fail "Invalid YEN_FINGERPRINT_GATE_MODE value: $FINGERPRINT_GATE_MODE (expected off|report|enforce)"
        FINGERPRINT_GATE_MODE="enforce"
        ;;
esac
FINGERPRINT_SCAN_SCRIPT="$REPO_ROOT/scripts/13-scan-artifact-fingerprints.sh"
FINGERPRINT_ALLOWLIST_FILE="${YEN_FINGERPRINT_ALLOWLIST_FILE:-$REPO_ROOT/scripts/lib/fingerprint-allowlist.txt}"
## Non-concurrency allowlist gate — promoted to pre-build (03-verify-components.sh Check 12).
## Weather removal regression gate — promoted to pre-build (03-verify-components.sh Check 13).

DMG_LAYOUT_GATE_MODE="${YEN_DMG_LAYOUT_GATE_MODE:-enforce}"
case "$DMG_LAYOUT_GATE_MODE" in
    off|report|enforce) ;;
    *)
        fail "Invalid YEN_DMG_LAYOUT_GATE_MODE value: $DMG_LAYOUT_GATE_MODE (expected off|report|enforce)"
        DMG_LAYOUT_GATE_MODE="enforce"
        ;;
esac
DMG_LAYOUT_VERIFY_SCRIPT="$REPO_ROOT/scripts/manual/14-verify-dmg-layout.sh"
DMG_LAYOUT_SKIP_FINDER_CHECK="${YEN_DMG_LAYOUT_SKIP_FINDER_CHECK:-0}"

# Security-gate downgrade guard. 05-detect-failures.sh is the shipping gate, so a
# non-enforce mode on a provenance/credential/layout gate would let a real finding
# ship as a non-blocking note. Refuse to run downgraded unless the operator sets an
# explicit, self-documenting acknowledgment so it can never happen silently.
GATE_DOWNGRADE_ACK="${YEN_ALLOW_GATE_DOWNGRADE:-0}"
for _gm in \
    "YEN_ARTIFACT_URL_SCAN_GATE_MODE=$ARTIFACT_URL_SCAN_GATE_MODE" \
    "YEN_FINGERPRINT_GATE_MODE=$FINGERPRINT_GATE_MODE" \
    "YEN_DMG_LAYOUT_GATE_MODE=$DMG_LAYOUT_GATE_MODE"; do
    if [ "${_gm##*=}" != "enforce" ]; then
        if [ "$GATE_DOWNGRADE_ACK" = "1" ]; then
            echo "  [WARNING] Security gate downgraded: $_gm (acknowledged via YEN_ALLOW_GATE_DOWNGRADE=1)"
            echo "            A real finding on this gate will NOT block. Do not ship a release this way."
        else
            fail "Security gate $_gm is not 'enforce'. Refusing to run downgraded. Set YEN_ALLOW_GATE_DOWNGRADE=1 to override (non-shipping use only)."
        fi
    fi
done

# Get version and file paths
VERSION_JSON="$REPO_ROOT/public/stable/version.json"
# Default so an absent version.json cannot abort the run under `set -u`.
VERSION_FILENAME=""
DMG_FILENAME=""
VERSION_SIG="$REPO_ROOT/public/stable/version.sig"
APPCAST_XML="$REPO_ROOT/public/stable/appcast.xml"
BUILT_APP="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"
INFO_PLIST="$BUILT_APP/Contents/Info.plist"
## CLI_ENTRYPOINT / APP_INTENTS_PERMISSION_POLICY — only needed by privileged surface check (now in 03)
EXPECTED_BUNDLE_ID=""
PUB_KEY=""
VERSION_URL=""
VERSION_SHA256=""
YAZI_BASELINE="$REPO_ROOT/yen-terminal/.yazi-baseline"
YAZI_EXPECTED_VERSION=""

if [ -f "$YAZI_BASELINE" ]; then
    YAZI_EXPECTED_VERSION=$(grep "^upstream_version=" "$YAZI_BASELINE" | head -1 | cut -d'=' -f2- || true)
fi

if [ -f "$VERSION_JSON" ]; then
    VERSION=$(get_version "$VERSION_JSON")
    VERSION_FILENAME=$(get_version_filename "$VERSION")
    DMG_FILENAME=$(get_dmg_filename "$VERSION")
    RELEASE_DMG="$REPO_ROOT/public/stable/$DMG_FILENAME"
    DMG_SHA256_FILE="$REPO_ROOT/public/stable/${DMG_FILENAME}.sha256"

    if command -v jq >/dev/null 2>&1; then
        VERSION_URL=$(jq -r '.url // ""' "$VERSION_JSON" 2>/dev/null || echo "")
        VERSION_SHA256=$(jq -r '.sha256 // ""' "$VERSION_JSON" 2>/dev/null || echo "")
    elif command -v python3 >/dev/null 2>&1; then
        VERSION_META=$(python3 - "$VERSION_JSON" <<'PY' 2>/dev/null || true
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print((payload.get("url") or "").strip())
print((payload.get("sha256") or "").strip())
PY
        )
        VERSION_URL=$(echo "$VERSION_META" | sed -n '1p')
        VERSION_SHA256=$(echo "$VERSION_META" | sed -n '2p')
    else
        VERSION_URL=$(grep '"url"' "$VERSION_JSON" | sed -nE 's/.*"url"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
        VERSION_SHA256=$(grep '"sha256"' "$VERSION_JSON" | sed -nE 's/.*"sha256"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
    fi
else
    fail "version.json not found"
    VERSION=""
    RELEASE_DMG=""
    DMG_SHA256_FILE=""
fi

# ============================================================================
# Check 1: Build Artifacts
# ============================================================================

# Built app exists
if [ ! -d "$BUILT_APP" ]; then
    fail "Built app not found"
else
    INFO_PLIST="$BUILT_APP/Contents/Info.plist"
    RESOURCES="$BUILT_APP/Contents/Resources"

    # Main binary exists and is universal (arm64 + x86_64)
    MAIN_BINARY="$BUILT_APP/Contents/MacOS/yen"
    if [ ! -f "$MAIN_BINARY" ]; then
        fail "Main binary not found at Contents/MacOS/yen"
    else
        if ! bash "$REPO_ROOT/scripts/lib/verify-macos-floor.sh" "$BUILT_APP"; then
            fail "Packaged executable architecture, platform, or macOS deployment target is invalid"
        fi
    fi

    # Info.plist checks
    if [ -f "$INFO_PLIST" ] && command -v /usr/libexec/PlistBuddy &>/dev/null; then
        # SUEnableInstallerLauncherService
        INSTALLER_SERVICE=$(/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$INFO_PLIST" 2>/dev/null || echo "missing")
        [ "$INSTALLER_SERVICE" != "true" ] && fail "SUEnableInstallerLauncherService missing"

        # SUFeedURL
        FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null || echo "missing")
        echo "$FEED_URL" | grep -q "yen.chat/stable/appcast.xml" || fail "SUFeedURL incorrect"

        # SUPublicEDKey
        PUB_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || echo "")
        [ -z "$PUB_KEY" ] && fail "SUPublicEDKey missing"

        # NSMicrophoneUsageDescription (dictation)
        MIC_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" 2>/dev/null || echo "")
        [ -z "$MIC_DESC" ] && fail "NSMicrophoneUsageDescription missing (dictation)"

        # NSSpeechRecognitionUsageDescription (dictation)
        SPEECH_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$INFO_PLIST" 2>/dev/null || echo "")
        [ -z "$SPEECH_DESC" ] && fail "NSSpeechRecognitionUsageDescription missing (dictation)"

        # NSScreenCaptureUsageDescription must stay absent: own-window screenshot
        # capture does not require Screen Recording permission and the key widens
        # prompt surface.
        SCREEN_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSScreenCaptureUsageDescription" "$INFO_PLIST" 2>/dev/null || true)
        [ -n "$SCREEN_DESC" ] && fail "NSScreenCaptureUsageDescription should be absent (prompt-surface minimization)"

        # Bundle ID
        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "")
        [ "$BUNDLE_ID" != "com.yenchat.yen" ] && fail "Bundle ID incorrect: $BUNDLE_ID (expected com.yenchat.yen)"
        EXPECTED_BUNDLE_ID="$BUNDLE_ID"

        # Version match
        if [ -n "$VERSION" ]; then
            PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "")
            [ "$PLIST_VERSION" != "$VERSION" ] && fail "Version mismatch: $PLIST_VERSION vs $VERSION"
        fi

        # Main binary version/provenance must align to release metadata.
        # build-release injects a semver-normalized version string derived
        # from version.json via scripts/lib/version-utils.sh.
        if [ -x "$MAIN_BINARY" ] && [ -n "$VERSION" ]; then
            EXPECTED_MAIN_VERSION=$(get_version_semver "$VERSION" 2>/dev/null || echo "")
            if [ -z "$EXPECTED_MAIN_VERSION" ]; then
                fail "Invalid release version format in version.json: $VERSION"
            fi
            MAIN_VERSION_LINE=$("$MAIN_BINARY" +version 2>/dev/null | head -1)
            MAIN_VERSION=$(echo "$MAIN_VERSION_LINE" | awk '{print $2}')
            [ -z "$MAIN_VERSION" ] && fail "Could not parse main binary version from '+version' output"
            [ "$MAIN_VERSION" != "$EXPECTED_MAIN_VERSION" ] && \
                fail "Main binary version mismatch: $MAIN_VERSION vs $EXPECTED_MAIN_VERSION"
            echo "$MAIN_VERSION" | grep -Eq -- '-[A-Za-z0-9._-]+\+[0-9a-f]{7,}$' && \
                fail "Main binary version leaks branch/hash provenance: $MAIN_VERSION"
        fi
    fi

    # Tiered CLI action policy checks
    if [ -x "$MAIN_BINARY" ]; then
        HELP_OUTPUT=$("$MAIN_BINARY" +help 2>/dev/null || true)
        echo "$HELP_OUTPUT" | grep -q '+show-config' && fail "+show-config should be hidden from default +help output"
        echo "$HELP_OUTPUT" | grep -q '+crash-report' && fail "+crash-report should be hidden from default +help output"
        echo "$HELP_OUTPUT" | grep -q '+boo' && fail "+boo should be hidden from default +help output"
        echo "$HELP_OUTPUT" | grep -q '+ssh-cache' || fail "+ssh-cache should remain visible in default +help output"

        POLICY_OUTPUT="$(mktemp)"
        if "$MAIN_BINARY" +show-config --help >"$POLICY_OUTPUT" 2>&1; then
            fail "+show-config unexpectedly allowed without support override"
        else
            grep -q "support-only and hidden by default" "$POLICY_OUTPUT" || \
                fail "+show-config block message missing expected support-only guidance"
        fi
        if ! YEN_CLI_SUPPORT_ACTIONS=1 "$MAIN_BINARY" +show-config --help >/dev/null 2>&1; then
            fail "+show-config should run when YEN_CLI_SUPPORT_ACTIONS=1 is set"
        fi

        if "$MAIN_BINARY" +crash-report --help >"$POLICY_OUTPUT" 2>&1; then
            fail "+crash-report unexpectedly allowed without support override"
        else
            grep -q "support-only and hidden by default" "$POLICY_OUTPUT" || \
                fail "+crash-report block message missing expected support-only guidance"
        fi
        if ! YEN_CLI_SUPPORT_ACTIONS=1 "$MAIN_BINARY" +crash-report --help >/dev/null 2>&1; then
            fail "+crash-report should run when YEN_CLI_SUPPORT_ACTIONS=1 is set"
        fi

        if "$MAIN_BINARY" +boo >"$POLICY_OUTPUT" 2>&1; then
            fail "+boo unexpectedly allowed without internal override"
        else
            grep -q "internal-only and blocked in release builds" "$POLICY_OUTPUT" || \
                fail "+boo block message missing expected internal-only guidance"
        fi
        rm -f "$POLICY_OUTPUT"
    fi

    # CLI bundled
    [ ! -f "$RESOURCES/bin/yen" ] || [ ! -x "$RESOURCES/bin/yen" ] && fail "CLI not bundled"
    [ ! -f "$RESOURCES/lib/common.sh" ] && fail "CLI lib/common.sh missing"
    [ ! -d "$RESOURCES/commands" ] && fail "CLI commands directory missing"

    # version.json bundled (for welcome banner)
    [ ! -f "$RESOURCES/yen/version.json" ] && fail "Bundled version.json missing at yen/version.json"

    # File browser bundled and executable
    [ ! -f "$RESOURCES/bin/yazi" ] || [ ! -x "$RESOURCES/bin/yazi" ] && fail "File browser binary not bundled"
    [ ! -f "$RESOURCES/bin/ya" ] || [ ! -x "$RESOURCES/bin/ya" ] && fail "File browser companion (ya) not bundled"
    if [ -f "$RESOURCES/bin/yazi" ] && ! assert_universal_binary "$RESOURCES/bin/yazi"; then
        fail "File browser (yazi) is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/ya" ] && ! assert_universal_binary "$RESOURCES/bin/ya"; then
        fail "File browser companion (ya) is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/yazi" ] && [ -x "$RESOURCES/bin/yazi" ]; then
        YAZI_VERSION_OUTPUT="$("$RESOURCES/bin/yazi" --version 2>/dev/null || true)"
        if [ -z "$YAZI_EXPECTED_VERSION" ]; then
            fail "Yazi baseline missing upstream_version (expected in yen-terminal/.yazi-baseline)"
        else
            YAZI_EXPECTED_VERSION_DISPLAY="${YAZI_EXPECTED_VERSION#v}"
            echo "$YAZI_VERSION_OUTPUT" | grep -q "Yazi" && echo "$YAZI_VERSION_OUTPUT" | grep -q "$YAZI_EXPECTED_VERSION_DISPLAY" || \
                fail "Yazi version drifted from baseline (expected $YAZI_EXPECTED_VERSION_DISPLAY from .yazi-baseline; got: $YAZI_VERSION_OUTPUT)"
        fi
    fi
    [ ! -f "$RESOURCES/bin/browse" ] || [ ! -x "$RESOURCES/bin/browse" ] && fail "Browse wrapper not bundled"
    [ ! -f "$RESOURCES/bin/yen-yazi-edit" ] || [ ! -x "$RESOURCES/bin/yen-yazi-edit" ] && fail "Yazi editor wrapper not bundled"
    if [ -f "$RESOURCES/bin/yen-yazi-edit" ]; then
        grep -Fq 'if [ "$editor_name" = "micro" ]; then' "$RESOURCES/bin/yen-yazi-edit" || \
            fail "Bundled yazi editor wrapper missing micro branch"
        grep -Fq -- "-ruler false" "$RESOURCES/bin/yen-yazi-edit" || \
            fail "Bundled yazi editor wrapper missing micro ruler-disable flag"
        grep -Fq -- "-softwrap true" "$RESOURCES/bin/yen-yazi-edit" || \
            fail "Bundled yazi editor wrapper missing micro softwrap flag"
        grep -Fq -- "-wordwrap true" "$RESOURCES/bin/yen-yazi-edit" || \
            fail "Bundled yazi editor wrapper missing micro wordwrap flag"
    fi
    [ -e "$RESOURCES/bin/generate-yazi-theme.sh" ] && fail "Legacy Yazi theme generator should not be bundled"

    # Yazi config bundled with YEN branding.
    # Yazi v26.5.6 removed `title_format` in favor of the `ind-app-title`
    # DDS event, so the YEN branding now lives in init.lua instead.
    YAZI_CONFIG="$RESOURCES/yazi-config/yazi.toml"
    [ ! -f "$YAZI_CONFIG" ] && fail "Yazi config not bundled"

    # Yazi init.lua and git plugin
    [ ! -f "$RESOURCES/yazi-config/init.lua" ] && fail "Yazi init.lua not bundled"
    if [ -f "$RESOURCES/yazi-config/init.lua" ]; then
        grep -q 'ind-app-title' "$RESOURCES/yazi-config/init.lua" || \
            fail "Yazi init.lua missing YEN branding via ind-app-title DDS event"
        grep -q '"YEN' "$RESOURCES/yazi-config/init.lua" || \
            fail "Yazi init.lua missing YEN branding string"
    fi
    [ ! -f "$RESOURCES/yazi-config/plugins/git.yazi/main.lua" ] && fail "Git plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/video-native.yazi/main.lua" ] && fail "Video-native plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/pdf-native.yazi/main.lua" ] && fail "PDF-native plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/svg-native.yazi/main.lua" ] && fail "SVG-native plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/archive-native.yazi/main.lua" ] && fail "Archive-native plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/extract-native.yazi/main.lua" ] && fail "Extract-native plugin not bundled"
    [ ! -f "$RESOURCES/yazi-config/plugins/code-guard.yazi/main.lua" ] && fail "Code-guard plugin not bundled"
    grep -q "extract-native" "$YAZI_CONFIG" || fail "Yazi config missing native archive extractor opener"

    # Lua syntax validation on bundled plugins (fail-closed; no silent skip)
    if command -v luac &>/dev/null; then
        while IFS= read -r lua_file; do
            if ! luac -p "$lua_file" 2>/dev/null; then
                fail "Lua syntax error in bundled $(echo "$lua_file" | sed "s|$RESOURCES/||")"
            fi
        done < <(find "$RESOURCES/yazi-config" -name "*.lua" -type f 2>/dev/null || true)
    else
        fail "luac not available — cannot validate bundled Lua plugins"
    fi

    # Yazi theme and keymap (YEN customizations)
    [ ! -f "$RESOURCES/yazi-config/theme.toml" ] && fail "Yazi theme.toml not bundled"
    [ ! -f "$RESOURCES/yazi-config/keymap.toml" ] && fail "Yazi keymap.toml not bundled"
    [ ! -f "$RESOURCES/yazi-config/bat-theme" ] && fail "Yazi bat-theme fallback file not bundled"
    YAZI_FALLBACK_BAT_THEME="$(head -n 1 "$RESOURCES/yazi-config/bat-theme" 2>/dev/null | tr -d '\r')"
    [ -z "$YAZI_FALLBACK_BAT_THEME" ] && fail "Yazi bat-theme fallback file is empty"
    if [ -f "$RESOURCES/yazi-config/theme.toml" ]; then
        grep -q '^\[flavor\]' "$RESOURCES/yazi-config/theme.toml" || fail "Yazi theme.toml missing [flavor] block"
    fi

    # Yazi flavor assets (syntax coloring for built-in code previews)
    YAZI_FLAVORS_DIR="$RESOURCES/yazi-config/flavors"
    [ ! -d "$YAZI_FLAVORS_DIR" ] && fail "Yazi flavors directory not bundled"
    for flavor in catppuccin-mocha catppuccin-latte; do
        FLAVOR_DIR="$YAZI_FLAVORS_DIR/$flavor.yazi"
        [ ! -d "$FLAVOR_DIR" ] && fail "Yazi flavor not bundled: $flavor"
        [ ! -f "$FLAVOR_DIR/flavor.toml" ] && fail "Yazi flavor missing flavor.toml: $flavor"
        [ ! -f "$FLAVOR_DIR/tmtheme.xml" ] && fail "Yazi flavor missing tmtheme.xml: $flavor"
        [ ! -f "$FLAVOR_DIR/LICENSE" ] && fail "Yazi flavor missing LICENSE: $flavor"
        [ ! -f "$FLAVOR_DIR/LICENSE-tmtheme" ] && fail "Yazi flavor missing LICENSE-tmtheme: $flavor"
    done
    if [ -f "$RESOURCES/yazi-config/theme.toml" ]; then
        THEME_FLAVOR_DARK=$(awk -F= '
            /^\[flavor\]/ { in_flavor=1; next }
            in_flavor && /^\[/ { in_flavor=0 }
            in_flavor && /^[[:space:]]*dark[[:space:]]*=/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                gsub(/"/, "", $2)
                print $2
                exit
            }
        ' "$RESOURCES/yazi-config/theme.toml")
        THEME_FLAVOR_LIGHT=$(awk -F= '
            /^\[flavor\]/ { in_flavor=1; next }
            in_flavor && /^\[/ { in_flavor=0 }
            in_flavor && /^[[:space:]]*light[[:space:]]*=/ {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                gsub(/"/, "", $2)
                print $2
                exit
            }
        ' "$RESOURCES/yazi-config/theme.toml")
        [ -z "$THEME_FLAVOR_DARK" ] && fail "Yazi theme.toml [flavor] missing dark value"
        [ -z "$THEME_FLAVOR_LIGHT" ] && fail "Yazi theme.toml [flavor] missing light value"
        for flavor_ref in "$THEME_FLAVOR_DARK" "$THEME_FLAVOR_LIGHT"; do
            [ ! -d "$YAZI_FLAVORS_DIR/$flavor_ref.yazi" ] && fail "Yazi theme.toml references missing flavor: $flavor_ref"
        done
    fi

    # CLI tools (enhance file browser)
    [ ! -f "$RESOURCES/bin/fd" ] || [ ! -x "$RESOURCES/bin/fd" ] && fail "fd binary not bundled"
    [ ! -f "$RESOURCES/bin/rg" ] || [ ! -x "$RESOURCES/bin/rg" ] && fail "ripgrep binary not bundled"
    [ ! -f "$RESOURCES/bin/fzf" ] || [ ! -x "$RESOURCES/bin/fzf" ] && fail "fzf binary not bundled"
    [ ! -f "$RESOURCES/bin/zoxide" ] || [ ! -x "$RESOURCES/bin/zoxide" ] && fail "zoxide binary not bundled"
    [ ! -f "$RESOURCES/bin/bat" ] || [ ! -x "$RESOURCES/bin/bat" ] && fail "bat binary not bundled"
    if [ -x "$RESOURCES/bin/bat" ]; then
        if [ "$YAZI_FALLBACK_BAT_THEME" != "auto" ] && ! "$RESOURCES/bin/bat" --list-themes 2>/dev/null | grep -Fxq "$YAZI_FALLBACK_BAT_THEME"; then
            fail "Bundled yazi fallback bat-theme '$YAZI_FALLBACK_BAT_THEME' is not available in bundled bat"
        fi
    fi
    [ ! -f "$RESOURCES/bin/jq" ] || [ ! -x "$RESOURCES/bin/jq" ] && fail "jq binary not bundled"
    [ ! -f "$RESOURCES/bin/lazygit" ] || [ ! -x "$RESOURCES/bin/lazygit" ] && fail "lazygit binary not bundled"
    [ ! -f "$RESOURCES/bin/delta" ] || [ ! -x "$RESOURCES/bin/delta" ] && fail "delta binary not bundled"
    [ ! -f "$RESOURCES/bin/zmx" ] || [ ! -x "$RESOURCES/bin/zmx" ] && fail "zmx binary not bundled"
    [ ! -f "$RESOURCES/bin/yen-vidthumb" ] || [ ! -x "$RESOURCES/bin/yen-vidthumb" ] && fail "yen-vidthumb binary not bundled"
    [ ! -f "$RESOURCES/bin/yen-pdfthumb" ] || [ ! -x "$RESOURCES/bin/yen-pdfthumb" ] && fail "yen-pdfthumb binary not bundled"
    [ ! -f "$RESOURCES/bin/yen-svgthumb" ] || [ ! -x "$RESOURCES/bin/yen-svgthumb" ] && fail "yen-svgthumb binary not bundled"
    [ ! -f "$RESOURCES/bin/resvg" ] || [ ! -x "$RESOURCES/bin/resvg" ] && fail "resvg binary not bundled"
    [ -e "$RESOURCES/bin/gh" ] && fail "Removed GitHub CLI binary reintroduced at Resources/bin/gh"
    [ -e "$RESOURCES/bin/yen-weather" ] && fail "Deprecated weather helper binary still bundled"
    [ -e "$RESOURCES/bin/yen-weather.entitlements" ] && fail "Deprecated weather helper entitlements still bundled"
    [ -e "$RESOURCES/bin/yen-weather.app" ] && fail "Deprecated weather helper app bundle still bundled"
    command -v bsdtar >/dev/null 2>&1 || fail "bsdtar not available (required for native archive preview/extract)"
    if [ -f "$RESOURCES/bin/yen-vidthumb" ] && ! assert_universal_binary "$RESOURCES/bin/yen-vidthumb"; then
        fail "yen-vidthumb is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/yen-pdfthumb" ] && ! assert_universal_binary "$RESOURCES/bin/yen-pdfthumb"; then
        fail "yen-pdfthumb is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/yen-svgthumb" ] && ! assert_universal_binary "$RESOURCES/bin/yen-svgthumb"; then
        fail "yen-svgthumb is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/resvg" ] && ! assert_universal_binary "$RESOURCES/bin/resvg"; then
        fail "resvg is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/lazygit" ] && ! assert_universal_binary "$RESOURCES/bin/lazygit"; then
        fail "lazygit is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/delta" ] && ! assert_universal_binary "$RESOURCES/bin/delta"; then
        fail "delta is not a universal binary"
    fi
    if [ -f "$RESOURCES/bin/zmx" ] && ! assert_universal_binary "$RESOURCES/bin/zmx"; then
        fail "zmx is not a universal binary"
    fi
    # Shell integration — all files at Resources/yen/shell-integration/
    SHELL_ZSH="$RESOURCES/yen/shell-integration/zsh/.zshenv"
    SHELL_BASH="$RESOURCES/yen/shell-integration/bash/yen.bash"
    SHELL_ZSH_INTEG="$RESOURCES/yen/shell-integration/zsh/yen-integration"
    SHELL_WELCOME="$RESOURCES/yen/shell-integration/yen-welcome.sh"
    BASH_PREEXEC="$RESOURCES/yen/shell-integration/bash/bash-preexec.sh"
    SHELL_FISH="$RESOURCES/yen/shell-integration/fish/vendor_conf.d/yen-shell-integration.fish"
    SHELL_ELVISH="$RESOURCES/yen/shell-integration/elvish/lib/yen-integration.elv"
    SHELL_NUSHELL="$RESOURCES/yen/shell-integration/nushell/vendor/autoload/yen.nu"

    LEGACY_SHELL_BASH="$RESOURCES/yen/shell-integration/bash/ghostty.bash"
    LEGACY_SHELL_ZSH="$RESOURCES/yen/shell-integration/zsh/ghostty-integration"
    LEGACY_SHELL_FISH="$RESOURCES/yen/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
    LEGACY_SHELL_ELVISH="$RESOURCES/yen/shell-integration/elvish/lib/ghostty-integration.elv"
    LEGACY_SHELL_NUSHELL="$RESOURCES/yen/shell-integration/nushell/vendor/autoload/ghostty.nu"
    LEGACY_THEME_DEFAULT="$RESOURCES/yen/themes/Ghostty Default Style Dark"
    CURATED_THEME_MANIFEST="$RESOURCES/yen/theme-curated-manifest.txt"

    # File existence
    [ ! -f "$SHELL_ZSH" ] && fail "zsh .zshenv not found"
    [ ! -f "$SHELL_ZSH_INTEG" ] && fail "zsh yen-integration not found"
    [ ! -f "$SHELL_BASH" ] && fail "bash yen.bash not found"
    [ ! -f "$SHELL_WELCOME" ] && fail "yen-welcome.sh not found"
    [ ! -f "$BASH_PREEXEC" ] && fail "bash-preexec.sh not found (required by bash integration)"
    [ ! -f "$SHELL_FISH" ] && fail "fish yen-shell-integration.fish not found"
    [ ! -f "$SHELL_ELVISH" ] && fail "elvish yen-integration.elv not found"
    [ ! -f "$SHELL_NUSHELL" ] && fail "nushell yen.nu not found"

    # Legacy Ghostty filename residues should never ship.
    [ -e "$LEGACY_SHELL_BASH" ] && fail "legacy bash ghostty.bash still bundled"
    [ -e "$LEGACY_SHELL_ZSH" ] && fail "legacy zsh ghostty-integration still bundled"
    [ -e "$LEGACY_SHELL_FISH" ] && fail "legacy fish ghostty-shell-integration.fish still bundled"
    [ -e "$LEGACY_SHELL_ELVISH" ] && fail "legacy elvish ghostty-integration.elv still bundled"
    [ -e "$LEGACY_SHELL_NUSHELL" ] && fail "legacy nushell ghostty.nu still bundled"
    [ -e "$LEGACY_THEME_DEFAULT" ] && fail "legacy Ghostty Default Style Dark theme still bundled"

    # Executable permissions
    [ -f "$SHELL_ZSH_INTEG" ] && [ ! -x "$SHELL_ZSH_INTEG" ] && fail "zsh yen-integration not executable"
    [ -f "$SHELL_BASH" ] && [ ! -x "$SHELL_BASH" ] && fail "bash yen.bash not executable"
    [ -f "$SHELL_WELCOME" ] && [ ! -x "$SHELL_WELCOME" ] && fail "yen-welcome.sh not executable"

    # Content verification
    if [ -f "$SHELL_ZSH" ]; then
        grep -q "bin_dir" "$SHELL_ZSH" || fail "zsh shell integration missing PATH setup"
    fi
    if [ -f "$SHELL_BASH" ]; then
        grep -q "__yen_bin_dir" "$SHELL_BASH" || fail "bash shell integration missing PATH setup"
    fi
    if [ -f "$SHELL_NUSHELL" ]; then
        grep -q "export module yen" "$SHELL_NUSHELL" || fail "nushell integration missing yen module export"
    fi
    if [ -f "$SHELL_ZSH_INTEG" ]; then
        grep -q "_yen_precmd" "$SHELL_ZSH_INTEG" || fail "zsh integration missing terminal features (OSC 133)"
        grep -q "function y()" "$SHELL_ZSH_INTEG" || fail "zsh integration missing y() function (cd-on-quit)"
        grep -q "lazygit() { _yen_run_app_command lazygit" "$SHELL_ZSH_INTEG" || fail "zsh integration missing lazygit wrapper"
        grep -q "gitlazy() { _yen_run_app_command gitlazy" "$SHELL_ZSH_INTEG" || fail "zsh integration missing gitlazy wrapper"
        grep -q "yengit() { _yen_run_app_command yengit" "$SHELL_ZSH_INTEG" || fail "zsh integration missing yengit wrapper"
        grep -q "gityen() { _yen_run_app_command gityen" "$SHELL_ZSH_INTEG" || fail "zsh integration missing gityen wrapper"
    fi
    if [ -f "$SHELL_BASH" ]; then
        grep -q "__yen_precmd" "$SHELL_BASH" || fail "bash integration missing terminal features (OSC 133)"
        grep -q "function y()" "$SHELL_BASH" || fail "bash integration missing y() function (cd-on-quit)"
        grep -q "function lazygit { _yen_run_app_command lazygit" "$SHELL_BASH" || fail "bash integration missing lazygit wrapper"
        grep -q "function gitlazy { _yen_run_app_command gitlazy" "$SHELL_BASH" || fail "bash integration missing gitlazy wrapper"
        grep -q "function yengit { _yen_run_app_command yengit" "$SHELL_BASH" || fail "bash integration missing yengit wrapper"
        grep -q "function gityen { _yen_run_app_command gityen" "$SHELL_BASH" || fail "bash integration missing gityen wrapper"
    fi

    # Lazygit config overlays + aliases
    [ ! -f "$RESOURCES/yen/lazygit/config.yml" ] && fail "Bundled lazygit config missing at Resources/yen/lazygit/config.yml"
    if [ -f "$RESOURCES/yen/lazygit/config.yml" ]; then
        grep -q "disableStartupPopups: true" "$RESOURCES/yen/lazygit/config.yml" || fail "Bundled lazygit config missing disableStartupPopups override"
        grep -q "showBottomLine: true" "$RESOURCES/yen/lazygit/config.yml" || fail "Bundled lazygit config missing showBottomLine: true"
    fi
    for lazygit_cmd in lazygit gitlazy yengit gityen; do
        [ ! -x "$RESOURCES/commands/core/$lazygit_cmd" ] && fail "CLI command wrapper missing: commands/core/$lazygit_cmd"
    done

    # Themes at correct path (Resources/yen/themes/, not Resources/themes/)
    if [ ! -d "$RESOURCES/yen/themes" ]; then
        fail "Themes directory missing at Resources/yen/themes/"
    else
        THEME_COUNT=$(ls -1 "$RESOURCES/yen/themes" 2>/dev/null | wc -l | tr -d ' ')
        [ "$THEME_COUNT" -lt 16 ] && fail "Only $THEME_COUNT curated themes bundled (expected 16-24)"
        [ "$THEME_COUNT" -gt 24 ] && fail "$THEME_COUNT curated themes bundled (expected 16-24)"

        [ ! -f "$CURATED_THEME_MANIFEST" ] && fail "Curated theme manifest missing at Resources/yen/theme-curated-manifest.txt"
        if [ -f "$CURATED_THEME_MANIFEST" ]; then
            CURATED_THEME_COUNT=$(awk '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                sub(/[[:space:]]+$/, "", line)
                if (line == "" || line ~ /^#/) next
                print line
            }
            ' "$CURATED_THEME_MANIFEST" | wc -l | tr -d ' ')
            [ "$CURATED_THEME_COUNT" -lt 16 ] && fail "Curated theme manifest has too few entries ($CURATED_THEME_COUNT, expected 16-24)"
            [ "$CURATED_THEME_COUNT" -gt 24 ] && fail "Curated theme manifest has too many entries ($CURATED_THEME_COUNT, expected 16-24)"
            [ "$THEME_COUNT" -ne "$CURATED_THEME_COUNT" ] && fail "Bundled theme count ($THEME_COUNT) does not match curated manifest entries ($CURATED_THEME_COUNT)"

            grep -Fxq "YEN" "$CURATED_THEME_MANIFEST" || fail "Curated theme manifest missing required theme: YEN"
            grep -Fxq "Retro Terminal" "$CURATED_THEME_MANIFEST" || fail "Curated theme manifest missing required theme: Retro Terminal"
            grep -Fxq "CutePretzel" "$CURATED_THEME_MANIFEST" || fail "Curated theme manifest missing required theme: CutePretzel"
        fi

        [ ! -f "$RESOURCES/yen/themes/YEN" ] && fail "YEN theme not found at Resources/yen/themes/YEN"
        [ ! -f "$RESOURCES/yen/themes/Retro Terminal" ] && fail "Retro Terminal theme not found at Resources/yen/themes/Retro Terminal"
        [ ! -f "$RESOURCES/yen/themes/CutePretzel" ] && fail "CutePretzel theme not found at Resources/yen/themes/CutePretzel"
    fi
    # Guard: old wrong path must not exist
    [ -d "$RESOURCES/themes" ] && fail "Themes at wrong path Resources/themes/ (should be Resources/yen/themes/)"
    [ -d "$RESOURCES/yen/themes-full" ] && fail "Retired full theme catalog still bundled at Resources/yen/themes-full/"

    # CLI init commands work
    INIT_ZSH=$("$RESOURCES/bin/yen" init zsh 2>&1 || echo "")
    echo "$INIT_ZSH" | grep -q "yen()" || fail "CLI init zsh broken"
    echo "$INIT_ZSH" | grep -q "lazygit()" || fail "CLI init zsh missing lazygit shell wrapper"
    echo "$INIT_ZSH" | grep -q "gitlazy()" || fail "CLI init zsh missing gitlazy shell wrapper"
    echo "$INIT_ZSH" | grep -q "yengit()" || fail "CLI init zsh missing yengit shell wrapper"
    echo "$INIT_ZSH" | grep -q "gityen()" || fail "CLI init zsh missing gityen shell wrapper"

    CLI_HELP=$("$RESOURCES/bin/yen" help 2>&1 || echo "")
    echo "$CLI_HELP" | grep -q "gitlazy" || fail "CLI help missing gitlazy command"
    echo "$CLI_HELP" | grep -q "yengit" || fail "CLI help missing yengit command"
    echo "$CLI_HELP" | grep -q "gityen" || fail "CLI help missing gityen command"

    # Canonical vendor audit doc must match bundled inventory + baselines.
    if [ -f "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" ]; then
        VENDOR_AUDIT_OUTPUT=$(bash "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" --app "$BUILT_APP" 2>&1) || \
            fail "Vendor audit doc drift: $VENDOR_AUDIT_OUTPUT"
    else
        fail "scripts/12-verify-vendor-audit.sh missing"
    fi

fi

# Release artifacts (DMG exists locally during build, hosted on GitHub Releases for distribution)
[ -n "$RELEASE_DMG" ] && [ ! -f "$RELEASE_DMG" ] && fail "DMG not found (expected at $RELEASE_DMG after build)"
[ -n "$DMG_SHA256_FILE" ] && [ ! -f "$DMG_SHA256_FILE" ] && fail "DMG checksum not found"
[ ! -f "$VERSION_SIG" ] && fail "version.sig not found"
[ ! -f "$APPCAST_XML" ] && fail "appcast.xml not found"

VERSION_SIG_BODY=""
if [ -f "$VERSION_SIG" ]; then
    VERSION_SIG_BODY=$(normalize_signature_body "$(cat "$VERSION_SIG" 2>/dev/null || true)")
    echo "$VERSION_SIG_BODY" | grep -Eq '^[A-Za-z0-9+/=]+$' || fail "version.sig is not valid base64 text"
fi

if [ -f "$VERSION_JSON" ] && [ -n "$PUB_KEY" ] && [ -n "$VERSION_SIG_BODY" ]; then
    if ! verify_signed_file_with_public_key "$VERSION_JSON" "$VERSION_SIG_BODY" "$PUB_KEY"; then
        fail "version.json signature verification failed against SUPublicEDKey"
    fi
fi

# DMG checksum verification
if [ -f "$RELEASE_DMG" ] && [ -f "$DMG_SHA256_FILE" ]; then
    STORED_SHA=$(cat "$DMG_SHA256_FILE" | tr -d '[:space:]')
    ACTUAL_SHA=$(get_sha256 "$RELEASE_DMG")
    [ "$STORED_SHA" != "$ACTUAL_SHA" ] && fail "DMG checksum mismatch"

    [ -z "$VERSION_SHA256" ] && fail "version.json missing sha256 field"
    if [ -n "$VERSION_SHA256" ] && [ "$VERSION_SHA256" != "$ACTUAL_SHA" ]; then
        fail "version.json sha256 does not match release DMG checksum"
    fi
fi

# DMG contract + trust checks
if [ -f "$RELEASE_DMG" ] && [ -n "$DMG_FILENAME" ]; then
    EXPECTED_DMG_URL="$(github_release_asset_url "$VERSION" "$DMG_FILENAME")"
    [ -z "$VERSION_URL" ] && fail "version.json missing url field"
    if [ -n "$VERSION_URL" ] && [ "$VERSION_URL" != "$EXPECTED_DMG_URL" ]; then
        fail "version.json url mismatch: expected $EXPECTED_DMG_URL"
    fi

    if ! HDIUTIL_VERIFY_OUTPUT=$(hdiutil verify "$RELEASE_DMG" 2>&1); then
        fail "hdiutil verify failed for DMG: $(summarize_output "$HDIUTIL_VERIFY_OUTPUT")"
    fi

    if ! SPCTL_DMG_OUTPUT=$(spctl -a -t open --context context:primary-signature "$RELEASE_DMG" 2>&1); then
        fail "Gatekeeper assessment failed for DMG: $(summarize_output "$SPCTL_DMG_OUTPUT")"
    fi

    if ! STAPLER_DMG_OUTPUT=$(xcrun stapler validate "$RELEASE_DMG" 2>&1); then
        fail "DMG stapler validate failed: $(summarize_output "$STAPLER_DMG_OUTPUT")"
    fi
fi

# DMG layout/structure verification gate.
if [ -f "$RELEASE_DMG" ] && [ "$DMG_LAYOUT_GATE_MODE" != "off" ]; then
    if [ ! -x "$DMG_LAYOUT_VERIFY_SCRIPT" ]; then
        if [ "$DMG_LAYOUT_GATE_MODE" = "enforce" ]; then
            fail "DMG layout gate script missing or not executable: scripts/manual/14-verify-dmg-layout.sh"
        else
            DETAILS="$DETAILS\n    ! DMG layout gate script missing (report mode)"
        fi
    else
        if [ "$DMG_LAYOUT_SKIP_FINDER_CHECK" = "1" ]; then
            DMG_LAYOUT_VERIFY_DESC="structure-only (--skip-finder-check)"
            if DMG_LAYOUT_OUTPUT=$("$DMG_LAYOUT_VERIFY_SCRIPT" --dmg "$RELEASE_DMG" --skip-finder-check 2>&1); then
                DMG_LAYOUT_STATUS=0
            else
                DMG_LAYOUT_STATUS=$?
            fi
        else
            DMG_LAYOUT_VERIFY_DESC="full Finder geometry"
            if DMG_LAYOUT_OUTPUT=$("$DMG_LAYOUT_VERIFY_SCRIPT" --dmg "$RELEASE_DMG" 2>&1); then
                DMG_LAYOUT_STATUS=0
            else
                DMG_LAYOUT_STATUS=$?
            fi
        fi
        if [ "$DMG_LAYOUT_STATUS" -eq 0 ]; then
            :
        else
            DMG_LAYOUT_SUMMARY=$(summarize_output "$DMG_LAYOUT_OUTPUT")
            if [ "$DMG_LAYOUT_GATE_MODE" = "enforce" ]; then
                fail "DMG layout verification failed ($DMG_LAYOUT_VERIFY_DESC): $DMG_LAYOUT_SUMMARY"
            else
                DETAILS="$DETAILS\n    ! DMG layout verification warning ($DMG_LAYOUT_VERIFY_DESC): $DMG_LAYOUT_SUMMARY"
            fi
        fi
    fi
fi

# Appcast checks
if [ -f "$APPCAST_XML" ]; then
    # Presence-grep alone is not verification: it matched any occurrence in the
    # file, including a delta's, and said nothing about whether the signature is
    # valid for the DMG we actually ship. A bad appcast signature silently stops
    # auto-update for every installed user, so round-trip it against the DMG
    # with the same key already used for version.json below.
    grep -q "sparkle:edSignature" "$APPCAST_XML" || fail "Appcast missing EdDSA signature"
    APPCAST_SIG=$(extract_sparkle_ed_signature "$(cat "$APPCAST_XML")")
    if [ -z "$APPCAST_SIG" ]; then
        fail "Appcast EdDSA signature could not be extracted"
    elif [ -z "$PUB_KEY" ]; then
        fail "Sparkle public key unavailable — cannot verify the appcast signature"
    elif [ ! -f "$RELEASE_DMG" ]; then
        fail "Release DMG missing — cannot verify the appcast signature against it"
    elif ! verify_signed_file_with_public_key "$RELEASE_DMG" "$APPCAST_SIG" "$PUB_KEY"; then
        fail "Appcast EdDSA signature does not verify against $RELEASE_DMG"
    fi
    [ -n "$VERSION_FILENAME" ] && ! grep -q "yen-${VERSION_FILENAME}.dmg" "$APPCAST_XML" && fail "Appcast version mismatch"
fi

# Notarization
if [ -d "$BUILT_APP" ]; then
    STAPLE_OUTPUT=$(stapler validate "$BUILT_APP" 2>&1 || true)
    if ! echo "$STAPLE_OUTPUT" | grep -q "worked"; then
        DETAILS="$DETAILS\n    ! App not stapled (expected — DMG notarization covers distribution)"
    fi
fi

# ============================================================================
gate_unit_ran build-artifacts "app=$(basename "$BUILT_APP") bundled_bins=$(command ls "$BUILT_APP/Contents/Resources/bin" 2>/dev/null | grep -c . || true)"

# Check 2: Security
# ============================================================================

if [ -d "$BUILT_APP" ]; then
    CODESIGN_OUTPUT=$(codesign -d --verbose=2 "$BUILT_APP" 2>&1 || echo "")
    echo "$CODESIGN_OUTPUT" | grep -q "flags=.*runtime" || fail "Hardened runtime not enabled"
    echo "$CODESIGN_OUTPUT" | grep -q "Timestamp=" || fail "No timestamp on signature"

    # Verify entitlements (required for microphone, speech recognition)
    ENTITLEMENTS_OUTPUT=$(codesign -d --entitlements - "$BUILT_APP" 2>&1 || echo "")
    echo "$ENTITLEMENTS_OUTPUT" | grep -q "audio-input" || fail "Missing audio-input entitlement"

    # A bare `if [ -d ]` with no else reported "Sparkle signed" for a bundle that
    # has no Sparkle at all — an app that cannot auto-update, and one that fails
    # to launch if anything links against the missing framework.
    SPARKLE_FRAMEWORK="$BUILT_APP/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FRAMEWORK" ]; then
        codesign --verify --deep --strict "$SPARKLE_FRAMEWORK" 2>&1 >/dev/null || fail "Sparkle signature invalid"
    else
        fail "Sparkle.framework missing from $BUILT_APP/Contents/Frameworks"
    fi

    codesign --verify --deep --strict "$BUILT_APP" 2>&1 >/dev/null || fail "App signature invalid"

    set_required_app_bins
    for bin_name in "${REQUIRED_APP_BINS[@]}"; do
        BIN_REL_PATH=$(required_app_bin_path "$bin_name")
        BIN_PATH="$BUILT_APP/Contents/Resources/bin/$BIN_REL_PATH"
        [ -f "$BIN_PATH" ] || { fail "Bundled binary missing for signature verification: $BIN_REL_PATH"; continue; }
        codesign --verify --strict "$BIN_PATH" 2>&1 >/dev/null || fail "Bundled binary signature invalid: $bin_name"
    done

    # Detect unexpected Mach-O binaries not in REQUIRED_APP_BINS
    # Shell scripts (yen, browse) are intentionally unsigned — gatekeeper doesn't check them
    for extra_bin in "$BUILT_APP/Contents/Resources/bin"/*; do
        [ -f "$extra_bin" ] || continue
        extra_name=$(basename "$extra_bin")
        file "$extra_bin" | grep -q "Mach-O" || continue
        found=0
        for known in "${REQUIRED_APP_BINS[@]}"; do
            [ "$extra_name" = "$known" ] && found=1 && break
        done
        [ "$found" -eq 0 ] && fail "Unexpected Mach-O binary not in REQUIRED_APP_BINS: $extra_name"
    done
fi

# ============================================================================
gate_unit_ran security "signed_payloads=$(codesign -dv "$BUILT_APP" 2>&1 | grep -c . || true) checks=4"

# Check 3: Critical Files
# ============================================================================

CRITICAL_FILES=(
    "$VERSION_JSON"
    "$REPO_ROOT/yen-terminal/ghostty/macos/YEN-Info.plist"
    "$REPO_ROOT/yen-cli/lib/common.sh"
)

for file in "${CRITICAL_FILES[@]}"; do
    [ -f "$file" ] && [ ! -s "$file" ] && fail "Empty: $(basename "$file")"
done

## App Intent source-level hardening checks — covered by 04-verify-branding.sh Check 12d.
## Removed from post-build: source files don't change during compilation.

# ============================================================================
gate_unit_ran critical-files "version.json+Info.plist+common.sh+themes checked=4"

# Check 4: Consistency
# ============================================================================

# Download links verification
if [ -f "./scripts/06-verify-download-links.sh" ]; then
    DL_VERIFY_OUTPUT=$(bash ./scripts/06-verify-download-links.sh 2>&1) || fail "Download links mismatch: $DL_VERIFY_OUTPUT"
else
    fail "Download link verification script missing (scripts/06-verify-download-links.sh)"
fi

# XML validation
if [ -f "$APPCAST_XML" ]; then
    if command -v xmllint &>/dev/null; then
        XMLLINT_OUTPUT=$(xmllint --noout "$APPCAST_XML" 2>&1) || fail "Invalid appcast XML: $XMLLINT_OUTPUT"
    else
        fail "xmllint not available — cannot validate appcast XML"
    fi
fi

# ============================================================================
gate_unit_ran consistency "download_links+appcast_xml checked=2"

# Check 5: Artifact Credential/URL Scan Gate
# ============================================================================
PARALLEL_GATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yen-postbuild-gates.XXXXXX")
ARTIFACT_URL_RESULT_FILE="$PARALLEL_GATE_DIR/artifact-url.result"
FINGERPRINT_RESULT_FILE="$PARALLEL_GATE_DIR/fingerprint.result"
run_artifact_url_scan_gate "$ARTIFACT_URL_RESULT_FILE" &
ARTIFACT_URL_GATE_PID=$!

## Check 6 (Privileged-Action Surface Diff) — promoted to pre-build (03-verify-components.sh Check 11).

# ============================================================================
# Check 6: Artifact Fingerprint Gate
# ============================================================================
run_fingerprint_gate "$FINGERPRINT_RESULT_FILE" &
FINGERPRINT_GATE_PID=$!

set +e
wait "$ARTIFACT_URL_GATE_PID"
wait "$FINGERPRINT_GATE_PID"
set -e

apply_parallel_gate_result "$ARTIFACT_URL_RESULT_FILE"
gate_unit_ran url-scan-gate "outcome=${PARALLEL_GATE_OUTCOME:-pass} mode=${YEN_ARTIFACT_URL_SCAN_GATE_MODE:-enforce}"
apply_parallel_gate_result "$FINGERPRINT_RESULT_FILE"
gate_unit_ran fingerprint-gate "outcome=${PARALLEL_GATE_OUTCOME:-pass} mode=${YEN_FINGERPRINT_GATE_MODE:-enforce}"

# ============================================================================
# Check 7: Git State
# ============================================================================
# Info only, doesn't fail

# ============================================================================
# Summary
# ============================================================================
# git-state is informational (see Check 7 above), but the receipt framework
# fails any unit that records RAN with a zero quantity — correctly, since a scan
# that examined nothing has not passed. A CLEAN tree legitimately has zero
# tracked changes, so reporting RAN there aborted the whole gate on the one tree
# state that should be least alarming, contradicting "Info only, doesn't fail".
# Report a skip with the reason instead, so a clean tree yields a real RECEIPT.
GIT_STATE_TRACKED_CHANGES=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -c . || true)
if [ "$GIT_STATE_TRACKED_CHANGES" -gt 0 ]; then
    gate_unit_ran git-state "tracked_changes=$GIT_STATE_TRACKED_CHANGES"
else
    gate_unit_skipped git-state "clean worktree — no tracked changes to summarize"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "  X Post-build verification failed"
    echo -e "$DETAILS"
    echo ""
    echo "  DO NOT COMMIT. Fix issues and restart /update-yen from Step 1."
fi

# gate_end prints every unit on BOTH branches. $DETAILS previously carried
# report-mode notices that were discarded on green runs -- exactly the runs where
# nobody was looking.
gate_end "$FAILED"
