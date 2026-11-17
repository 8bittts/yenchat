#!/bin/bash
# Evaluate native yen-svgthumb output against vendored resvg.
#
# Usage:
#   ./scripts/30-eval-svgthumb.sh
#   ./scripts/30-eval-svgthumb.sh /path/to/fixtures
#
# Env:
#   MAX_DIMENSION=2000      # Thumbnail longest edge in pixels
#   SIMILARITY_PASS=0.95    # Pass threshold for strict similarity fixtures
#   REBUILD=1               # Rebuild yen-svgthumb before evaluation (default: 1)
#   MANIFEST_FILE=...       # Fixture metadata CSV (default: <fixture-dir>/manifest.csv)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE_DIR="${1:-$REPO_ROOT/yen-svgthumb/fixtures}"
EVAL_DIR="$REPO_ROOT/yen-svgthumb/.eval"

MAX_DIMENSION="${MAX_DIMENSION:-2000}"
SIMILARITY_PASS="${SIMILARITY_PASS:-0.95}"
REBUILD="${REBUILD:-1}"
MANIFEST_FILE="${MANIFEST_FILE:-$FIXTURE_DIR/manifest.csv}"

NATIVE_DIR="$REPO_ROOT/yen-svgthumb"
NATIVE_BIN="$NATIVE_DIR/yen-svgthumb"
COMPARE_SRC="$NATIVE_DIR/compare.swift"
RESVG_BIN="$REPO_ROOT/yen-terminal/customizations/vendor/resvg/resvg"

png_dimensions() {
    local image_path="$1"
    local width
    local height

    width="$(sips -g pixelWidth "$image_path" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$image_path" 2>/dev/null | awk '/pixelHeight/ {print $2}')"

    if [ -z "$width" ] || [ -z "$height" ]; then
        return 1
    fi

    echo "$width,$height"
}

manifest_field() {
    local fixture="$1"
    local field="$2"
    awk -F, -v target="$fixture" -v idx="$field" \
        'NR > 1 && $1 == target {print $idx; exit}' "$MANIFEST_FILE"
}

float_ge() {
    local lhs="$1"
    local rhs="$2"
    awk -v a="$lhs" -v b="$rhs" 'BEGIN { exit !((a + 0) >= (b + 0)) }'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/30-eval-svgthumb.sh [fixture-dir]"
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

if [ ! -f "$COMPARE_SRC" ]; then
    echo "ERROR: Comparator source missing: $COMPARE_SRC"
    exit 1
fi

if [ ! -x "$RESVG_BIN" ]; then
    echo "ERROR: resvg binary missing: $RESVG_BIN"
    echo "Run: ./scripts/14-vendor.sh resvg"
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: swiftc not found"
    exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
    echo "ERROR: sips not found (required for PNG dimension checks)"
    exit 1
fi

if [ "$REBUILD" = "1" ] || [ ! -x "$NATIVE_BIN" ]; then
    echo "Building yen-svgthumb..."
    (cd "$NATIVE_DIR" && ./build.sh)
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

COMPARE_BIN="$TMP_DIR/svg-compare"
echo "Building comparator..."
swiftc -O -parse-as-library -framework AppKit -o "$COMPARE_BIN" "$COMPARE_SRC"

mkdir -p "$EVAL_DIR/resvg" "$EVAL_DIR/native" "$EVAL_DIR/logs"
RESULTS_CSV="$EVAL_DIR/results.csv"

cat >"$RESULTS_CSV" <<'EOF'
fixture,category,policy,resvg_status,native_status,similarity,mae,resvg_width,resvg_height,native_width,native_height
EOF

fixture_total=0
both_ok=0
resvg_failures=0
native_failures=0
strict_total=0
strict_pass=0
strict_fail=0
baseline_total=0
baseline_fail=0
fallback_total=0
fallback_pass=0
fallback_fail=0
fallback_triggered=0
expected_failure_total=0
expected_failure_pass=0
expected_failure_fail=0
unknown_policy_total=0
p0_regressions=0

while IFS= read -r fixture; do
    [ -z "$fixture" ] && continue
    fixture_total=$((fixture_total + 1))

    rel="${fixture#$FIXTURE_DIR/}"
    if [ "$rel" = "manifest.csv" ]; then
        continue
    fi

    category="$(manifest_field "$rel" 2)"
    policy="$(manifest_field "$rel" 3)"
    if [ -z "$category" ]; then
        category="unclassified"
    fi
    if [ -z "$policy" ]; then
        policy="strict_compare"
    fi

    stem="${rel%.*}"
    slug="$(echo "$stem" | tr '/ ' '__')"

    resvg_out="$EVAL_DIR/resvg/$stem.png"
    native_out="$EVAL_DIR/native/$stem.png"
    mkdir -p "$(dirname "$resvg_out")" "$(dirname "$native_out")"

    resvg_status="ok"
    native_status="ok"
    similarity=""
    mae=""
    resvg_width=""
    resvg_height=""
    native_width=""
    native_height=""

    if ! "$NATIVE_BIN" "$fixture" "$native_out" --max-dimension "$MAX_DIMENSION" > /dev/null 2>"$EVAL_DIR/logs/$slug.native.log"; then
        native_status="fail"
        native_failures=$((native_failures + 1))
    fi

    if [ "$native_status" = "ok" ]; then
        dims="$(png_dimensions "$native_out" || true)"
        if [ -n "$dims" ]; then
            native_width="$(echo "$dims" | cut -d',' -f1)"
            native_height="$(echo "$dims" | cut -d',' -f2)"
            if ! "$RESVG_BIN" --width "$native_width" --height "$native_height" "$fixture" "$resvg_out" > /dev/null 2>"$EVAL_DIR/logs/$slug.resvg.log"; then
                resvg_status="fail"
                resvg_failures=$((resvg_failures + 1))
            fi
        else
            native_status="fail"
            native_failures=$((native_failures + 1))
        fi
    fi

    if [ "$native_status" = "fail" ] && [ "$resvg_status" = "ok" ]; then
        if ! "$RESVG_BIN" "$fixture" "$resvg_out" > /dev/null 2>"$EVAL_DIR/logs/$slug.resvg.log"; then
            resvg_status="fail"
            resvg_failures=$((resvg_failures + 1))
        fi
    fi

    if [ "$resvg_status" = "ok" ] && [ "$native_status" = "ok" ]; then
        compare_csv="$("$COMPARE_BIN" "$resvg_out" "$native_out" 2>/dev/null || true)"
        if [ -n "$compare_csv" ]; then
            similarity="$(echo "$compare_csv" | cut -d',' -f1)"
            mae="$(echo "$compare_csv" | cut -d',' -f2)"
            resvg_width="$(echo "$compare_csv" | cut -d',' -f3)"
            resvg_height="$(echo "$compare_csv" | cut -d',' -f4)"
            native_width="$(echo "$compare_csv" | cut -d',' -f5)"
            native_height="$(echo "$compare_csv" | cut -d',' -f6)"
            both_ok=$((both_ok + 1))
        fi
    fi

    case "$policy" in
        strict_compare)
            strict_total=$((strict_total + 1))
            if [ "$resvg_status" = "ok" ] && [ "$native_status" = "ok" ] && [ -n "$similarity" ] && float_ge "$similarity" "$SIMILARITY_PASS"; then
                strict_pass=$((strict_pass + 1))
            else
                strict_fail=$((strict_fail + 1))
            fi
            if [ "$native_status" = "fail" ] && [ "$resvg_status" = "ok" ]; then
                p0_regressions=$((p0_regressions + 1))
            fi
            ;;
        baseline_limitation)
            baseline_total=$((baseline_total + 1))
            if [ "$resvg_status" = "ok" ] && [ "$native_status" = "ok" ]; then
                :
            else
                baseline_fail=$((baseline_fail + 1))
                p0_regressions=$((p0_regressions + 1))
            fi
            ;;
        fallback_expected)
            fallback_total=$((fallback_total + 1))
            if [ "$resvg_status" = "ok" ]; then
                fallback_pass=$((fallback_pass + 1))
            else
                fallback_fail=$((fallback_fail + 1))
                p0_regressions=$((p0_regressions + 1))
            fi
            if [ "$native_status" = "fail" ] && [ "$resvg_status" = "ok" ]; then
                fallback_triggered=$((fallback_triggered + 1))
            fi
            ;;
        expected_failure)
            expected_failure_total=$((expected_failure_total + 1))
            if [ "$native_status" = "fail" ]; then
                expected_failure_pass=$((expected_failure_pass + 1))
            else
                expected_failure_fail=$((expected_failure_fail + 1))
                p0_regressions=$((p0_regressions + 1))
            fi
            ;;
        *)
            unknown_policy_total=$((unknown_policy_total + 1))
            ;;
    esac

    echo "$rel,$category,$policy,$resvg_status,$native_status,$similarity,$mae,$resvg_width,$resvg_height,$native_width,$native_height" >>"$RESULTS_CSV"
done < <(find "$FIXTURE_DIR" -type f \( -name "*.svg" -o -name "*.svgz" \) | sort)

if [ "$fixture_total" -eq 0 ]; then
    echo "ERROR: No fixtures found in $FIXTURE_DIR"
    exit 1
fi

avg_similarity_all="$(awk -F, 'NR>1 && $6 != "" {sum += $6; count += 1} END {if (count == 0) {printf "0.0000"} else {printf "%.4f", sum / count}}' "$RESULTS_CSV")"
strict_similarity_avg="$(awk -F, 'NR>1 && $3 == "strict_compare" && $6 != "" {sum += $6; count += 1} END {if (count == 0) {printf "0.0000"} else {printf "%.4f", sum / count}}' "$RESULTS_CSV")"
strict_similarity_samples="$(awk -F, 'NR>1 && $3 == "strict_compare" && $6 != "" {count += 1} END {print count + 0}' "$RESULTS_CSV")"
corpus_gate="FAIL"
similarity_gate="FAIL"
p0_gate="FAIL"
strict_gate="FAIL"
overall_gate="FAIL"

if [ "$fixture_total" -ge 20 ]; then
    corpus_gate="PASS"
fi

if float_ge "$strict_similarity_avg" "$SIMILARITY_PASS"; then
    similarity_gate="PASS"
fi

if [ "$p0_regressions" -eq 0 ]; then
    p0_gate="PASS"
fi

if [ "$strict_fail" -eq 0 ] && [ "$strict_total" -gt 0 ]; then
    strict_gate="PASS"
fi

if [ "$corpus_gate" = "PASS" ] && [ "$similarity_gate" = "PASS" ] && [ "$p0_gate" = "PASS" ] && [ "$strict_gate" = "PASS" ]; then
    overall_gate="PASS"
fi

SUMMARY_TXT="$EVAL_DIR/summary.txt"
{
    echo "SVG Native Evaluation"
    echo "Fixture directory: $FIXTURE_DIR"
    echo "Fixture manifest: $MANIFEST_FILE"
    echo "Fixtures total: $fixture_total"
    echo "Both rendered: $both_ok"
    echo "resvg failures: $resvg_failures"
    echo "native failures: $native_failures"
    echo "Similarity pass gate: $SIMILARITY_PASS"
    echo "Similarity avg (all comparable): $avg_similarity_all"
    echo "Similarity avg (strict_compare): $strict_similarity_avg"
    echo "Similarity samples (strict_compare): $strict_similarity_samples"
    echo "Strict fixtures: $strict_total"
    echo "Strict pass: $strict_pass"
    echo "Strict fail: $strict_fail"
    echo "Baseline limitation fixtures: $baseline_total"
    echo "Baseline limitation failures: $baseline_fail"
    echo "Fallback-expected fixtures: $fallback_total"
    echo "Fallback-expected pass: $fallback_pass"
    echo "Fallback-expected fail: $fallback_fail"
    echo "Fallback triggered (native fail -> resvg ok): $fallback_triggered"
    echo "Expected-failure fixtures: $expected_failure_total"
    echo "Expected-failure pass: $expected_failure_pass"
    echo "Expected-failure fail: $expected_failure_fail"
    echo "Unknown policy fixtures: $unknown_policy_total"
    echo "P0 regressions: $p0_regressions"
    echo "Gate corpus>=20: $corpus_gate"
    echo "Gate strict similarity avg>=${SIMILARITY_PASS}: $similarity_gate"
    echo "Gate strict per-fixture pass: $strict_gate"
    echo "Gate p0 regressions==0: $p0_gate"
    echo "Success gate (ship/no-ship): $overall_gate"
    echo "Results CSV: $RESULTS_CSV"
    echo
    echo "Lowest similarity fixtures:"
    awk -F, 'NR>1 && $6 != "" {printf "%s,%s,%s\n", $1, $6, $3}' "$RESULTS_CSV" | sort -t, -k2,2n | head -8
} >"$SUMMARY_TXT"

cat "$SUMMARY_TXT"
