#!/bin/bash
# Soak-test SVG preview rendering using native-first + resvg fallback path.
#
# Usage:
#   ./scripts/31-soak-svgthumb.sh
#   ./scripts/31-soak-svgthumb.sh /path/to/fixtures
#
# Env:
#   ROUNDS=12              # Full fixture passes
#   MAX_DIMENSION=1400     # Longest output edge (<=2MP for square output)
#   REBUILD=1              # Rebuild yen-svgthumb before soak
#   P95_TARGET_MS=120      # UX gate target
#   MEMORY_DRIFT_MAX_PCT=10

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE_DIR="${1:-$REPO_ROOT/yen-svgthumb/fixtures}"
MANIFEST_FILE="${MANIFEST_FILE:-$FIXTURE_DIR/manifest.csv}"
EVAL_DIR="$REPO_ROOT/yen-svgthumb/.eval"

ROUNDS="${ROUNDS:-12}"
MAX_DIMENSION="${MAX_DIMENSION:-1400}"
REBUILD="${REBUILD:-1}"
P95_TARGET_MS="${P95_TARGET_MS:-120}"
MEMORY_DRIFT_MAX_PCT="${MEMORY_DRIFT_MAX_PCT:-10}"

NATIVE_DIR="$REPO_ROOT/yen-svgthumb"
NATIVE_BIN="$NATIVE_DIR/yen-svgthumb"
RESVG_BIN="$REPO_ROOT/yen-terminal/customizations/vendor/resvg/resvg"

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
    echo "Usage: ./scripts/31-soak-svgthumb.sh [fixture-dir]"
    exit 0
fi

if [ ! -d "$FIXTURE_DIR" ]; then
    echo "ERROR: Fixture directory not found: $FIXTURE_DIR"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Fixture manifest missing: $MANIFEST_FILE"
    exit 1
fi

if [ ! -x "$RESVG_BIN" ]; then
    echo "ERROR: resvg binary missing: $RESVG_BIN"
    echo "Run: ./scripts/14-vendor.sh resvg"
    exit 1
fi

if [ ! -x "/usr/bin/time" ]; then
    echo "ERROR: /usr/bin/time not found"
    exit 1
fi

if [ "$REBUILD" = "1" ] || [ ! -x "$NATIVE_BIN" ]; then
    echo "Building yen-svgthumb..."
    (cd "$NATIVE_DIR" && ./build.sh)
fi

fixture_count="$(find "$FIXTURE_DIR" -type f \( -name "*.svg" -o -name "*.svgz" \) | wc -l | tr -d '[:space:]')"
if [ "$fixture_count" -eq 0 ]; then
    echo "ERROR: no .svg/.svgz fixtures under $FIXTURE_DIR"
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUNNER="$TMP_DIR/render-with-fallback.sh"
cat >"$RUNNER" <<'RUNNER_EOF'
#!/bin/bash
set -euo pipefail
native_bin="$1"
resvg_bin="$2"
input="$3"
out="$4"
max_dimension="$5"

mkdir -p "$(dirname "$out")"

if "$native_bin" "$input" "$out" --max-dimension "$max_dimension" >/dev/null 2>&1; then
    echo "native"
    exit 0
fi

if "$resvg_bin" "$input" "$out" >/dev/null 2>&1; then
    echo "resvg"
    exit 0
fi

echo "fail"
exit 1
RUNNER_EOF
chmod 755 "$RUNNER"

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

        rel="${fixture#$FIXTURE_DIR/}"
        if [ "$rel" = "manifest.csv" ]; then
            continue
        fi

        policy="$(manifest_field "$rel" 3)"
        if [ -z "$policy" ]; then
            policy="strict_compare"
        fi

        slug="$(echo "$rel" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
        out_path="$TMP_DIR/out/round-$round/$slug.png"
        stdout_path="$TMP_DIR/stdout-$round-$slug.txt"
        time_log="$TMP_DIR/time-$round-$slug.log"

        set +e
        /usr/bin/time -l "$RUNNER" "$NATIVE_BIN" "$RESVG_BIN" "$fixture" "$out_path" "$MAX_DIMENSION" >"$stdout_path" 2>"$time_log"
        status_code=$?
        set -e

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

        echo "$round,$rel,$policy,$status,$path_used,$elapsed_ms,$max_rss,$peak_mem" >>"$SOAK_CSV"
    done < <(find "$FIXTURE_DIR" -type f \( -name "*.svg" -o -name "*.svgz" \) | sort)

    run_id=$round
done

success_count="$(awk -F, 'NR > 1 && $4 == "ok" {count += 1} END {print count + 0}' "$SOAK_CSV")"
fail_count="$(awk -F, 'NR > 1 && $4 == "fail" {count += 1} END {print count + 0}' "$SOAK_CSV")"
native_count="$(awk -F, 'NR > 1 && $5 == "native" {count += 1} END {print count + 0}' "$SOAK_CSV")"
fallback_count="$(awk -F, 'NR > 1 && $5 == "resvg" {count += 1} END {print count + 0}' "$SOAK_CSV")"

latency_file="$TMP_DIR/latencies.txt"
awk -F, 'NR > 1 && $4 == "ok" && $6 != "" {print $6}' "$SOAK_CSV" | sort -n >"$latency_file"
latency_samples="$(wc -l <"$latency_file" | tr -d '[:space:]')"

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

# Native-path gate. The resvg fallback launders native failure: with the
# yen-svgthumb binary dead, every fixture still renders through resvg and the
# latency/memory gates stay green. The manifest declares per-fixture policy, so
# hold the strict_compare fixtures to the native path and let the
# fallback_expected / expected_failure / baseline_limitation fixtures behave as
# documented.
strict_total="$(awk -F, 'NR > 1 && $3 == "strict_compare" {count += 1} END {print count + 0}' "$SOAK_CSV")"
strict_native_ok="$(awk -F, 'NR > 1 && $3 == "strict_compare" && $4 == "ok" && $5 == "native" {count += 1} END {print count + 0}' "$SOAK_CSV")"
total_runs="$((success_count + fail_count))"
expected_runs="$((fixture_count * ROUNDS))"

latency_gate="FAIL"
memory_gate="FAIL"
native_gate="FAIL"
result_gate="FAIL"

# Fail closed on an empty or short scan set: no fixtures rendered must never
# read the same as every fixture rendering cleanly.
if [ "$fixture_count" -gt 0 ] && [ "$total_runs" -eq "$expected_runs" ] && [ "$total_runs" -gt 0 ]; then
    result_gate="PASS"
fi

if [ "$strict_total" -gt 0 ] && [ "$strict_native_ok" -eq "$strict_total" ]; then
    native_gate="PASS"
fi

if float_le "$p95_ms" "$P95_TARGET_MS"; then
    latency_gate="PASS"
fi

if awk -v drift="$rss_drift_pct" -v max="$MEMORY_DRIFT_MAX_PCT" 'BEGIN {exit !((drift + 0) <= (max + 0))}'; then
    memory_gate="PASS"
fi

{
    echo "SVG Soak Evaluation"
    echo "Fixture directory: $FIXTURE_DIR"
    echo "Fixture manifest: $MANIFEST_FILE"
    echo "Rounds: $ROUNDS"
    echo "Max dimension: $MAX_DIMENSION"
    echo "Fixtures discovered: $fixture_count"
    echo "Runs total: $total_runs (expected $expected_runs)"
    echo "Render/result gate: $result_gate"
    echo "Runs successful: $success_count"
    echo "Runs failed: $fail_count"
    echo "Native renders: $native_count"
    echo "Fallback renders (resvg): $fallback_count"
    echo "strict_compare native renders: $strict_native_ok / $strict_total"
    echo "Native path gate (all strict_compare native): $native_gate"
    echo "Latency samples: $latency_samples"
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

# Mirror the pdf/video soaks: compute gates AND act on them. Without this the
# script printed FAIL and still exited 0.
if [ "$result_gate" != "PASS" ] || [ "$native_gate" != "PASS" ] || \
   [ "$latency_gate" != "PASS" ] || [ "$memory_gate" != "PASS" ]; then
    exit 1
fi
