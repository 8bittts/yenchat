#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.

echo "[6/9] Resolving Swift packages..."

SWIFT_RESOLVE_OUTPUT=$(cd ghostty/macos && xcodebuild -resolvePackageDependencies -project YEN.xcodeproj 2>&1) || {
    echo "  ERROR: Swift package resolution failed"
    echo "$SWIFT_RESOLVE_OUTPUT" | grep -i "error\|warning\|unable\|failed" | head -10
    exit 1
}

echo "  Swift packages resolved"

echo ""
echo "[7/9] Building YEN.app..."
zip_notify "Build started" "Compiling YEN.app v$VERSION"

# Progress indicator: one line every 30 seconds, and a final line with the build time.
show_progress() {
    local pid=$1
    local start_time=$(date +%s)
    local next_report=$start_time
    # Look at the compiler every second and report every 30. Sleeping the whole
    # 30 s between looks held the build until the next report, up to 30 s after
    # the compiler had ended.
    while kill -0 "$pid" 2>/dev/null; do
        local now=$(date +%s)
        if [ "$now" -ge "$next_report" ]; then
            local elapsed=$((now - start_time))
            local mins=$((elapsed / 60))
            local secs=$((elapsed % 60))
            printf "  Building... %dm %02ds\n" $mins $secs
            next_report=$((now + 30))
        fi
        sleep 1
    done
    # Final elapsed time
    local elapsed=$(($(date +%s) - start_time))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    printf "  Build complete (%dm %02ds)\n" $mins $secs
}

is_zig_retryable_flake() {
    local log_file="$1"
    # Transient cache rename/FileNotFound flakes
    grep -Eiq "FileNotFound|file not found|rename" "$log_file" && return 0
    # Transient dependency fetch / network flakes
    grep -Eiq "HttpConnectionClosing|ConnectionResetByPeer|TlsInitializationFailed|unable to connect to server" "$log_file" && return 0
    # xcframework creation failures (stale artifacts, exit code 70)
    grep -Eiq "xcframework.*failure|exited with code 70" "$log_file" && return 0
    return 1
}

clear_zig_build_caches() {
    rm -rf zig-cache .zig-cache
    rm -rf "$ZIG_GLOBAL_CACHE_DIR"
}

validate_gate_mode() {
    local mode="$1"
    case "$mode" in
        off|report|enforce)
            return 0
            ;;
        *)
            echo "  ERROR: invalid diagnostics gate mode: $mode (expected off|report|enforce)"
            return 1
            ;;
    esac
}

append_finding() {
    local existing="$1"
    local message="$2"
    if [ -n "$existing" ]; then
        printf "%s\n%s" "$existing" "$message"
    else
        printf "%s" "$message"
    fi
}

filter_non_concurrency_allowlist() {
    local findings="$1"
    local allowlist_file="$2"
    local regex

    if [ -z "$findings" ]; then
        printf "%s" ""
        return 0
    fi

    if [ ! -f "$allowlist_file" ]; then
        printf "%s" "$findings"
        return 0
    fi

    while IFS= read -r regex || [ -n "$regex" ]; do
        case "$regex" in
            ""|\#*)
                continue
                ;;
        esac
        findings=$(echo "$findings" | grep -Ev -- "$regex" || true)
    done < "$allowlist_file"

    findings=$(echo "$findings" | sed '/^[[:space:]]*$/d' || true)
    printf "%s" "$findings"
}

evaluate_gate_findings() {
    local gate_name="$1"
    local mode="$2"
    local findings="$3"

    if [ "$mode" = "off" ]; then
        echo "  $gate_name gate: off"
        return 0
    fi

    if [ -n "$findings" ]; then
        echo "  $gate_name gate findings (${mode} mode):"
        echo "$findings" | sed 's/^/    /'
        if [ "$mode" = "enforce" ]; then
            echo "  ERROR: $gate_name gate failed in enforce mode"
            return 1
        fi
        return 0
    fi

    echo "  $gate_name gate passed (${mode} mode)"
    return 0
}

run_app_intents_source_guardrails() {
    local mode="$1"
    local findings=""
    local keybind_file="overlays/macos/Sources/Features/App Intents/KeybindIntent.swift"
    local details_file="overlays/macos/Sources/Features/App Intents/GetTerminalDetailsIntent.swift"

    if [ "$mode" = "off" ]; then
        evaluate_gate_findings "App Intents source-compatibility" "$mode" ""
        return 0
    fi

    if [ ! -f "$keybind_file" ]; then
        findings=$(append_finding "$findings" "missing file: $keybind_file")
    fi

    if [ ! -f "$details_file" ]; then
        findings=$(append_finding "$findings" "missing file: $details_file")
    elif ! grep -Fq 'Summary("Get \(\.$detail) from \(\.$terminal)")' "$details_file"; then
        findings=$(append_finding "$findings" "GetTerminalDetailsIntent parameterSummary drift detected")
    fi

    evaluate_gate_findings "App Intents source-compatibility" "$mode" "$findings"
}

run_concurrency_log_gate() {
    local mode="$1"
    local log_file="$2"
    local findings=""

    if [ "$mode" = "off" ]; then
        evaluate_gate_findings "macOS concurrency diagnostics" "$mode" ""
        return 0
    fi

    if [ ! -f "$log_file" ]; then
        findings=$(append_finding "$findings" "build log missing: $log_file")
        evaluate_gate_findings "macOS concurrency diagnostics" "$mode" "$findings"
        return $?
    fi

    findings=$(grep -E "warning:.*(main actor-isolated|nonisolated context|Sendable|global actor|asynchronous alternative function)" "$log_file" || true)
    findings=$(filter_non_concurrency_allowlist "$findings" "$NON_CONCURRENCY_WARNING_ALLOWLIST_FILE")

    evaluate_gate_findings "macOS concurrency diagnostics" "$mode" "$findings"
}

run_app_intents_log_gate() {
    local mode="$1"
    local log_file="$2"
    local findings=""
    local app_intents_warnings=""
    local metadata_dir="ghostty/zig-out/YEN.app/Contents/Resources/Metadata.appintents"

    if [ "$mode" = "off" ]; then
        evaluate_gate_findings "App Intents build diagnostics" "$mode" ""
        return 0
    fi

    if [ ! -f "$log_file" ]; then
        findings=$(append_finding "$findings" "build log missing: $log_file")
        evaluate_gate_findings "App Intents build diagnostics" "$mode" "$findings"
        return $?
    fi

    if [ ! -d "$metadata_dir" ]; then
        findings=$(append_finding "$findings" "App Intents metadata bundle missing: $metadata_dir")
    fi

    app_intents_warnings=$(grep -E "warning:.*Metadata extraction skipped.*AppIntents.framework dependency found|Sources/Features/App Intents/.*(warning:|error:)" "$log_file" || true)
    app_intents_warnings=$(filter_non_concurrency_allowlist "$app_intents_warnings" "$NON_CONCURRENCY_WARNING_ALLOWLIST_FILE")
    if [ -n "$app_intents_warnings" ]; then
        findings=$(append_finding "$findings" "$app_intents_warnings")
    fi

    evaluate_gate_findings "App Intents build diagnostics" "$mode" "$findings"
}

validate_gate_mode "$CONCURRENCY_GATE_MODE" || exit 1
validate_gate_mode "$APP_INTENTS_GATE_MODE" || exit 1
if [ ! -f "$NON_CONCURRENCY_WARNING_ALLOWLIST_FILE" ]; then
    echo "  ERROR: non-concurrency warning allowlist file not found: $NON_CONCURRENCY_WARNING_ALLOWLIST_FILE"
    exit 1
fi
echo "  Running App Intents source guardrails..."
if ! run_app_intents_source_guardrails "$APP_INTENTS_GATE_MODE"; then
    exit 1
fi

run_zig_build_with_retry() {
    local max_attempts=3
    local attempt=1
    local log_file
    local zig_pid
    local zig_exit

    # Probe the SDK and, on the Xcode 26.4+ arm64e-only .tbd regression, activate a
    # synthetic macOS sysroot + xcrun wrapper so Zig's arm64 MachO linker can resolve
    # libSystem. Full rationale + bypass (YEN_SKIP_ZIG_SDK_WORKAROUND=1) live in
    # scripts/lib/zig-sdk-workaround.sh. setup_ mutates PATH; it is paired with the
    # teardown_zig_sdk_workaround calls below (both exit paths).
    setup_zig_sdk_workaround

    while [ "$attempt" -le "$max_attempts" ]; do
        log_file=$(mktemp)
        echo "  Zig build attempt $attempt/$max_attempts..."

        # `native` builds the engine library for this Mac's architecture only.
        # YEN requires macOS 27, which runs only on Apple silicon, and the app
        # links only arm64; the universal target also compiled an x86_64 copy
        # of the engine that nothing linked.
        set +e
        zig build -Doptimize=ReleaseFast -Dstrip=true -Dxcframework-target=native -Dversion-string="$VERSION_SEMVER" > "$log_file" 2>&1 &
        zig_pid=$!
        show_progress "$zig_pid"
        wait "$zig_pid"
        zig_exit=$?
        set -e

        if [ "$zig_exit" -eq 0 ]; then
            if [ -n "$ZIG_BUILD_LOG_PATH" ] && [ -f "$ZIG_BUILD_LOG_PATH" ]; then
                rm -f "$ZIG_BUILD_LOG_PATH"
            fi
            ZIG_BUILD_LOG_PATH=$(mktemp "${TMPDIR:-/tmp}/yen-zig-build-log.XXXXXX")
            cp "$log_file" "$ZIG_BUILD_LOG_PATH"
            rm -f "$log_file"
            # Restore PATH after Zig SDK workaround
            teardown_zig_sdk_workaround
            return 0
        fi

        echo "  ERROR: zig build failed (attempt $attempt/$max_attempts, exit code: $zig_exit)"
        grep -Ei "FileNotFound|file not found|rename|error:" "$log_file" | head -20 || true

        if [ "$attempt" -lt "$max_attempts" ] && is_zig_retryable_flake "$log_file"; then
            echo "  Retrying after cache cleanup (detected retryable build flake)..."
            clear_zig_build_caches
            rm -rf macos/*.xcframework
            rm -f "$log_file"
            attempt=$((attempt + 1))
            continue
        fi

        echo "  Zig build log:"
        cat "$log_file"
        rm -f "$log_file"
        # Restore PATH even on failure
        teardown_zig_sdk_workaround
        return "$zig_exit"
    done
}

# Run zig build with retry for transient Zig cache rename/FileNotFound flakes.
cd ghostty
if ! run_zig_build_with_retry; then
    cd "$SCRIPT_DIR/.."
    exit 1
fi
cd "$SCRIPT_DIR/.."

echo "  Running post-build diagnostics preflight..."
if ! run_concurrency_log_gate "$CONCURRENCY_GATE_MODE" "$ZIG_BUILD_LOG_PATH"; then
    exit 1
fi
if ! run_app_intents_log_gate "$APP_INTENTS_GATE_MODE" "$ZIG_BUILD_LOG_PATH"; then
    exit 1
fi

echo ""
