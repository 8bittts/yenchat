#!/bin/bash
# Soak-test native yen-vidthumb rendering (latency + memory). There is no
# fallback engine: ffmpeg/ffprobe were removed, so the runner wraps ONLY the
# native helper across the render_ok fixtures.
#
# Usage:
#   ./scripts/39-soak-vidthumb.sh
#   ./scripts/39-soak-vidthumb.sh /path/to/fixtures
#
# Env:
#   ROUNDS=12              # Full render_ok fixture passes
#   MAX_DIMENSION=640      # Longest output edge (AVFoundation downscales only)
#   REBUILD=1              # Rebuild yen-vidthumb before soak
#   NATIVE_BIN=/path/to/bin # Override renderer (test/debug only)
#   P95_TARGET_MS=400      # UX gate target (decode is heavier than PDF raster)
#   MEMORY_DRIFT_MAX_PCT=10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE_DIR="${1:-$REPO_ROOT/yen-vidthumb/fixtures}"
MANIFEST_FILE="${MANIFEST_FILE:-$FIXTURE_DIR/manifest.csv}"
EVAL_DIR="$REPO_ROOT/yen-vidthumb/.eval"

ROUNDS="${ROUNDS:-12}"
MAX_DIMENSION="${MAX_DIMENSION:-640}"
REBUILD="${REBUILD:-1}"
P95_TARGET_MS="${P95_TARGET_MS:-400}"
MEMORY_DRIFT_MAX_PCT="${MEMORY_DRIFT_MAX_PCT:-10}"

NATIVE_DIR="$REPO_ROOT/yen-vidthumb"
NATIVE_BIN="${NATIVE_BIN:-$NATIVE_DIR/yen-vidthumb}"
GENERATOR_SRC="$NATIVE_DIR/make-fixtures.swift"

manifest_field() {
    local fixture="$1"
    local field="$2"
    awk -F, -v target="$fixture" -v idx="$field" \
        'NR > 1 && $1 == target {print $idx; exit}' "$MANIFEST_FILE"
}

float_le() {
    local lhs="$1"
    local rhs="$2"
    awk -v a="$lhs" -v b="$rhs" 'BEGIN { exit !((a + 0) <= (b + 0)) }'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/39-soak-vidthumb.sh [fixture-dir]"
    exit 0
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Fixture manifest missing: $MANIFEST_FILE"
    exit 1
fi

if [ ! -f "$GENERATOR_SRC" ]; then
    echo "ERROR: Fixture generator source missing: $GENERATOR_SRC"
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: swiftc not found"
    exit 1
fi

if [ ! -x "/usr/bin/time" ]; then
    echo "ERROR: /usr/bin/time not found"
    exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
    echo "ERROR: sips not found (required for PNG validation)"
    exit 1
fi

case "$ROUNDS" in
    ''|*[!0-9]*|0*)
        echo "ERROR: ROUNDS must be an integer from 1 through 9999 without leading zeros"
        exit 1
        ;;
esac
if [ "${#ROUNDS}" -gt 4 ]; then
    echo "ERROR: ROUNDS must be an integer from 1 through 9999 without leading zeros"
    exit 1
fi

if [ "$REBUILD" = "1" ] || [ ! -x "$NATIVE_BIN" ]; then
    echo "Building yen-vidthumb..."
    (cd "$NATIVE_DIR" && ./build.sh)
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GENERATOR_BIN="$TMP_DIR/vid-make-fixtures"
echo "Building fixture generator..."
swiftc -O -parse-as-library \
    -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework AppKit \
    -o "$GENERATOR_BIN" "$GENERATOR_SRC"

mkdir -p "$FIXTURE_DIR"
echo "Generating fixtures..."
"$GENERATOR_BIN" "$FIXTURE_DIR"

RUNNER="$TMP_DIR/render-native.sh"
cat >"$RUNNER" <<'RUNNER_EOF'
#!/bin/bash
set -euo pipefail
native_bin="$1"
input="$2"
out="$3"
max_dimension="$4"

mkdir -p "$(dirname "$out")"

if "$native_bin" "$input" "$out" --seek 0 --max-width "$max_dimension" --max-height "$max_dimension" >/dev/null 2>&1; then
    echo "native"
    exit 0
fi

echo "fail"
exit 1
RUNNER_EOF
chmod 755 "$RUNNER"

RENDER_OK_LIST="$TMP_DIR/render-ok.txt"
awk -F, 'NR > 1 && $3 == "render_ok" && $1 != "" {print $1}' "$MANIFEST_FILE" >"$RENDER_OK_LIST"

if [ ! -s "$RENDER_OK_LIST" ]; then
    echo "ERROR: No render_ok fixtures listed in $MANIFEST_FILE"
    exit 1
fi

fixtures_per_round="$(wc -l <"$RENDER_OK_LIST" | tr -d '[:space:]')"
expected_samples=$((fixtures_per_round * ROUNDS))

mkdir -p "$EVAL_DIR"
SOAK_CSV="$EVAL_DIR/soak.csv"
SOAK_SUMMARY="$EVAL_DIR/soak-summary.txt"

cat >"$SOAK_CSV" <<'CSV_EOF'
run,fixture,policy,status,path_used,elapsed_ms,max_rss_bytes,peak_mem_bytes
CSV_EOF

run_id=0

while [ "$run_id" -lt "$ROUNDS" ]; do
    round=$((run_id + 1))
    while IFS= read -r fixture; do
        [ -z "$fixture" ] && continue

        policy="$(manifest_field "$fixture" 3)"
        [ -z "$policy" ] && policy="render_ok"

        slug="$(echo "$fixture" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
        out_path="$TMP_DIR/out/round-$round/$slug.png"
        stdout_path="$TMP_DIR/stdout-$round-$slug.txt"
        time_log="$TMP_DIR/time-$round-$slug.log"

        set +e
        /usr/bin/time -l "$RUNNER" "$NATIVE_BIN" "$FIXTURE_DIR/$fixture" "$out_path" "$MAX_DIMENSION" >"$stdout_path" 2>"$time_log"
        status_code=$?
        set -e

        if [ "$status_code" -eq 0 ]; then
            png_info=""
            decoded_probe="$TMP_DIR/decoded/round-$round/$slug.png"
            if [ ! -s "$out_path" ] || \
               ! png_info="$(sips -g format -g pixelWidth -g pixelHeight "$out_path" 2>/dev/null)" || \
               ! echo "$png_info" | grep -Eq '^[[:space:]]*format: png$' || \
               ! echo "$png_info" | grep -Eq '^[[:space:]]*pixelWidth: [1-9][0-9]*$' || \
               ! echo "$png_info" | grep -Eq '^[[:space:]]*pixelHeight: [1-9][0-9]*$' || \
               ! mkdir -p "$(dirname "$decoded_probe")" || \
               ! sips -s format png "$out_path" --out "$decoded_probe" >/dev/null 2>&1 || \
               [ ! -s "$decoded_probe" ]; then
                status_code=1
                echo "invalid or missing PNG output: $out_path" >>"$time_log"
            fi
        fi

        if [ "$status_code" -eq 0 ]; then
            status="ok"
        else
            status="fail"
        fi

        path_used="$(tr -d '\r\n' < "$stdout_path" || true)"
        if [ -z "$path_used" ]; then
            path_used="unknown"
        fi

        elapsed_s="$(awk 'NR == 1 {print $1}' "$time_log")"
        elapsed_ms=""
        if [ -n "$elapsed_s" ]; then
            elapsed_ms="$(awk -v s="$elapsed_s" 'BEGIN {printf "%.2f", s * 1000}')"
        fi

        max_rss="$(awk '/maximum resident set size/ {print $1; exit}' "$time_log")"
        peak_mem="$(awk '/peak memory footprint/ {print $1; exit}' "$time_log")"

        echo "$round,$fixture,$policy,$status,$path_used,$elapsed_ms,$max_rss,$peak_mem" >>"$SOAK_CSV"
    done <"$RENDER_OK_LIST"

    run_id=$round
done

success_count="$(awk -F, 'NR > 1 && $4 == "ok" {count += 1} END {print count + 0}' "$SOAK_CSV")"
fail_count="$(awk -F, 'NR > 1 && $4 == "fail" {count += 1} END {print count + 0}' "$SOAK_CSV")"

latency_file="$TMP_DIR/latencies.txt"
awk -F, 'NR > 1 && $4 == "ok" && $6 != "" {print $6}' "$SOAK_CSV" | sort -n >"$latency_file"
latency_samples="$(wc -l <"$latency_file" | tr -d '[:space:]')"
rss_samples="$(awk -F, 'NR > 1 && $4 == "ok" && $7 ~ /^[0-9]+$/ && $7 > 0 {count += 1} END {print count + 0}' "$SOAK_CSV")"

p95_ms="0.00"
if [ "$latency_samples" -gt 0 ]; then
    p95_index=$(((95 * latency_samples + 99) / 100))
    p95_ms="$(sed -n "${p95_index}p" "$latency_file")"
fi

window=5
if [ "$success_count" -gt 0 ]; then
    if [ "$success_count" -lt 10 ]; then
        window="$success_count"
    else
        window_calc=$((success_count / 5))
        if [ "$window_calc" -gt "$window" ]; then
            window="$window_calc"
        fi
    fi
fi

first_avg_rss="0"
last_avg_rss="0"
if [ "$success_count" -gt 0 ]; then
    first_avg_rss="$(awk -F, -v n="$window" 'NR > 1 && $4 == "ok" {count += 1; if (count <= n) sum += $7} END {if (count == 0) {print 0} else {d = (count < n ? count : n); printf "%.0f", sum / d}}' "$SOAK_CSV")"
    last_avg_rss="$(awk -F, -v n="$window" 'NR > 1 && $4 == "ok" {vals[++count] = $7} END {if (count == 0) {print 0; exit} start = count - n + 1; if (start < 1) start = 1; for (i = start; i <= count; i++) sum += vals[i]; printf "%.0f", sum / (count - start + 1)}' "$SOAK_CSV")"
fi

rss_drift_pct="0.00"
if [ "$first_avg_rss" -gt 0 ]; then
    rss_drift_pct="$(awk -v a="$first_avg_rss" -v b="$last_avg_rss" 'BEGIN {printf "%.2f", ((b - a) / a) * 100}')"
fi

latency_gate="FAIL"
memory_gate="FAIL"
result_gate="FAIL"

if [ "$success_count" -eq "$expected_samples" ] && \
   [ "$fail_count" -eq 0 ] && \
   [ "$latency_samples" -eq "$expected_samples" ] && \
   [ "$rss_samples" -eq "$expected_samples" ]; then
    result_gate="PASS"
fi

if float_le "$p95_ms" "$P95_TARGET_MS"; then
    latency_gate="PASS"
fi

if awk -v drift="$rss_drift_pct" -v max="$MEMORY_DRIFT_MAX_PCT" 'BEGIN {exit !((drift + 0) <= (max + 0))}'; then
    memory_gate="PASS"
fi

{
    echo "Video Soak Evaluation"
    echo "Fixture directory: $FIXTURE_DIR"
    echo "Fixture manifest: $MANIFEST_FILE"
    echo "Rounds: $ROUNDS"
    echo "Max dimension: $MAX_DIMENSION"
    echo "Runs successful: $success_count"
    echo "Runs failed: $fail_count"
    echo "Expected samples: $expected_samples"
    echo "Latency samples: $latency_samples"
    echo "RSS samples: $rss_samples"
    echo "Render/result gate: $result_gate"
    echo "p95 latency ms: $p95_ms"
    echo "Latency gate (p95 <= ${P95_TARGET_MS}ms): $latency_gate"
    echo "Memory window size: $window"
    echo "Avg max RSS first window (bytes): $first_avg_rss"
    echo "Avg max RSS last window (bytes): $last_avg_rss"
    echo "RSS drift (%): $rss_drift_pct"
    echo "Memory drift gate (<= ${MEMORY_DRIFT_MAX_PCT}%): $memory_gate"
    echo "Soak CSV: $SOAK_CSV"
} >"$SOAK_SUMMARY"

cat "$SOAK_SUMMARY"

if [ "$result_gate" != "PASS" ] || [ "$latency_gate" != "PASS" ] || [ "$memory_gate" != "PASS" ]; then
    exit 1
fi
