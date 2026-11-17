#!/bin/bash
# Run the canonical Settings panel memory benchmark with Instruments Allocations.
#
# This wrapper standardizes the validated retain-vs-release comparison:
# - release mode forces window-graph teardown on close
# - retain mode keeps the controller-owned window graph resident
# - both modes drive the same Settings tab-walk scenario
#
# Usage:
#   ./scripts/manual/27-run-settings-memory-benchmark.sh
#   ./scripts/manual/27-run-settings-memory-benchmark.sh --mode retain
#   ./scripts/manual/27-run-settings-memory-benchmark.sh --iterations 15 --pause-ms 35
#   ./scripts/manual/27-run-settings-memory-benchmark.sh --output-dir /tmp/settings-mem
#   ./scripts/manual/27-run-settings-memory-benchmark.sh --app /abs/path/to/YEN.app
#
# Exit codes:
#   0 = benchmark completed for all requested modes
#   1 = invalid arguments, missing build artifact, or xctrace failure

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
XCODEPROJ="$REPO_ROOT/yen-terminal/ghostty/macos/YEN.xcodeproj"
SCHEME="YEN"
CONFIGURATION="Debug"
SDK="macosx"
DEFAULT_OUTPUT_DIR="${TMPDIR%/}/yen-settings-memory-benchmark"

MODE="both"
ITERATIONS=30
PAUSE_MS=35
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
APP_PATH=""

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --mode MODE          retain, release, or both (default: both)
  --iterations N       Open/close iterations per mode (default: 30)
  --pause-ms N         Pause between benchmark steps in milliseconds (default: 35)
  --output-dir PATH    Directory for .trace and stdout artifacts
  --app PATH           Built YEN.app bundle or executable to launch
  -h, --help           Show this help text
EOF
}

resolve_app_executable() {
    local path="$1"
    if [ -z "$path" ]; then
        echo ""
        return
    fi

    if [ -d "$path" ]; then
        echo "$path/Contents/MacOS/yen"
        return
    fi

    echo "$path"
}

resolve_default_executable() {
    local built_products_dir

    built_products_dir=$(
        xcodebuild \
            -project "$XCODEPROJ" \
            -scheme "$SCHEME" \
            -configuration "$CONFIGURATION" \
            -sdk "$SDK" \
            -showBuildSettings 2>/dev/null \
            | awk -F' = ' '/BUILT_PRODUCTS_DIR = / { print $2; exit }'
    )

    if [ -z "$built_products_dir" ]; then
        return 1
    fi

    echo "$built_products_dir/YEN.app/Contents/MacOS/yen"
}

extract_result_line() {
    local stdout_path="$1"
    awk '/SETTINGS_MEMORY_BENCHMARK_RESULT/ { line=$0 } END { print line }' "$stdout_path"
}

extract_metric() {
    local result_line="$1"
    local key="$2"

    echo "$result_line" \
        | tr ' ' '\n' \
        | awk -F= -v wanted="$key" '$1 == wanted { print $2; exit }'
}

print_mode_summary() {
    local mode="$1"
    local result_line="$2"
    local resident_delta
    local footprint_delta
    local resident_peak
    local footprint_peak
    local retained_after_hide

    resident_delta=$(extract_metric "$result_line" "resident_delta")
    footprint_delta=$(extract_metric "$result_line" "footprint_delta")
    resident_peak=$(extract_metric "$result_line" "resident_peak")
    footprint_peak=$(extract_metric "$result_line" "footprint_peak")
    retained_after_hide=$(extract_metric "$result_line" "window_retained_after_hide")

    echo "  [$mode] resident_delta=$resident_delta footprint_delta=$footprint_delta resident_peak=$resident_peak footprint_peak=$footprint_peak window_retained_after_hide=$retained_after_hide"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --mode requires a value"
                usage
                exit 1
            fi
            MODE="${1:-}"
            ;;
        --iterations)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --iterations requires a value"
                usage
                exit 1
            fi
            ITERATIONS="${1:-}"
            ;;
        --pause-ms)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --pause-ms requires a value"
                usage
                exit 1
            fi
            PAUSE_MS="${1:-}"
            ;;
        --output-dir)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --output-dir requires a value"
                usage
                exit 1
            fi
            OUTPUT_DIR="${1:-}"
            ;;
        --app)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --app requires a value"
                usage
                exit 1
            fi
            APP_PATH="${1:-}"
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

case "$MODE" in
    both|retain|release)
        ;;
    *)
        echo "ERROR: --mode must be one of: retain, release, both"
        exit 1
        ;;
esac

case "$ITERATIONS" in
    ''|*[!0-9]*)
        echo "ERROR: --iterations must be a positive integer"
        exit 1
        ;;
esac

case "$PAUSE_MS" in
    ''|*[!0-9]*)
        echo "ERROR: --pause-ms must be a positive integer"
        exit 1
        ;;
esac

if [ "$ITERATIONS" -lt 1 ]; then
    echo "ERROR: --iterations must be at least 1"
    exit 1
fi

if [ "$PAUSE_MS" -lt 1 ]; then
    echo "ERROR: --pause-ms must be at least 1"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

EXECUTABLE="$(resolve_app_executable "$APP_PATH")"
if [ -z "$EXECUTABLE" ]; then
    if ! EXECUTABLE="$(resolve_default_executable)"; then
        echo "ERROR: Could not resolve the default Debug build output."
        echo "Run a Debug macOS build first or pass --app /abs/path/to/YEN.app"
        exit 1
    fi
fi

if [ ! -x "$EXECUTABLE" ]; then
    echo "ERROR: Benchmark target is not executable: $EXECUTABLE"
    echo "Run a Debug macOS build first or pass --app /abs/path/to/YEN.app"
    exit 1
fi

MODES=()
if [ "$MODE" = "both" ]; then
    MODES=("release" "retain")
else
    MODES=("$MODE")
fi

echo ""
echo "---------------"
echo "Settings Memory Benchmark"
echo "---------------"
echo "Executable: $EXECUTABLE"
echo "Modes: ${MODES[*]}"
echo "Iterations: $ITERATIONS"
echo "Pause (ms): $PAUSE_MS"
echo "Template: Allocations"
echo "Output dir: $OUTPUT_DIR"
echo ""

RELEASE_RESULT=""
RETAIN_RESULT=""

for current_mode in "${MODES[@]}"; do
    trace_path="$OUTPUT_DIR/settings-${current_mode}-alloc.trace"
    stdout_path="$OUTPUT_DIR/settings-${current_mode}-alloc.stdout"

    rm -rf "$trace_path" "$stdout_path"

    echo "[run] mode=$current_mode"
    xcrun xctrace record \
        --quiet \
        --template "Allocations" \
        --output "$trace_path" \
        --target-stdout "$stdout_path" \
        --env "YEN_SETTINGS_MEMORY_BENCHMARK_MODE=$current_mode" \
        --env "YEN_SETTINGS_MEMORY_BENCHMARK_ITERATIONS=$ITERATIONS" \
        --env "YEN_SETTINGS_MEMORY_BENCHMARK_PAUSE_MS=$PAUSE_MS" \
        --launch -- "$EXECUTABLE"

    result_line="$(extract_result_line "$stdout_path")"
    if [ -z "$result_line" ]; then
        echo "ERROR: No benchmark result line found in $stdout_path"
        exit 1
    fi

    echo "  trace: $trace_path"
    echo "  stdout: $stdout_path"
    print_mode_summary "$current_mode" "$result_line"
    echo ""

    case "$current_mode" in
        release)
            RELEASE_RESULT="$result_line"
            ;;
        retain)
            RETAIN_RESULT="$result_line"
            ;;
    esac
done

if [ -n "$RELEASE_RESULT" ] && [ -n "$RETAIN_RESULT" ]; then
    echo "[compare]"
    echo "  release resident_delta=$(extract_metric "$RELEASE_RESULT" "resident_delta") footprint_delta=$(extract_metric "$RELEASE_RESULT" "footprint_delta")"
    echo "  retain  resident_delta=$(extract_metric "$RETAIN_RESULT" "resident_delta") footprint_delta=$(extract_metric "$RETAIN_RESULT" "footprint_delta")"
    echo ""
fi

echo "Settings memory benchmark completed."
