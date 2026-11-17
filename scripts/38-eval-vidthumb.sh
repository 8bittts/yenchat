#!/bin/bash
# Evaluate native yen-vidthumb output. Self-validating: ffmpeg/ffprobe were
# removed, so there is no reference renderer to diff against. Instead each
# fixture asserts a valid non-empty PNG, the expected orientation, a downscaled
# (never upscaled) size that preserves aspect ratio, the reported duration, and
# the expected render_ok/expected_failure outcome.
#
# Usage:
#   ./scripts/38-eval-vidthumb.sh
#   ./scripts/38-eval-vidthumb.sh /path/to/fixtures
#
# Env:
#   MAX_DIMENSION=640       # Cap below native fixture dims so a downscale is observable
#   REBUILD=1               # Rebuild yen-vidthumb before evaluation (default: 1)
#   MANIFEST_FILE=...       # Fixture metadata CSV (default: <fixture-dir>/manifest.csv)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE_DIR="${1:-$REPO_ROOT/yen-vidthumb/fixtures}"
EVAL_DIR="$REPO_ROOT/yen-vidthumb/.eval"

MAX_DIMENSION="${MAX_DIMENSION:-640}"
REBUILD="${REBUILD:-1}"
MANIFEST_FILE="${MANIFEST_FILE:-$FIXTURE_DIR/manifest.csv}"

# All render_ok fixtures are 16:9 / 9:16 (ratio ~1.78). A square-stretch bug
# would collapse the ratio toward 1.0, so requiring long/short >= this bound
# proves aspect ratio is preserved without hardcoding the native dimensions.
ASPECT_MIN="1.5"
DURATION_TOLERANCE_S="0.5"

NATIVE_DIR="$REPO_ROOT/yen-vidthumb"
NATIVE_BIN="$NATIVE_DIR/yen-vidthumb"
GENERATOR_SRC="$NATIVE_DIR/make-fixtures.swift"

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

float_within() {
    local value="$1"
    local target="$2"
    local tolerance="$3"
    awk -v a="$value" -v b="$target" -v tol="$tolerance" \
        'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= tol) }'
}

orientation_of() {
    local width="$1"
    local height="$2"
    local diff=$((width - height))
    if [ "$diff" -lt 0 ]; then
        diff=$((-diff))
    fi
    if [ "$diff" -le 2 ]; then
        echo "square"
    elif [ "$width" -gt "$height" ]; then
        echo "landscape"
    else
        echo "portrait"
    fi
}

aspect_ratio_of() {
    local width="$1"
    local height="$2"
    awk -v w="$width" -v h="$height" \
        'BEGIN { lo = (w < h ? w : h); hi = (w > h ? w : h); if (lo == 0) { print "0" } else { printf "%.4f", hi / lo } }'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/38-eval-vidthumb.sh [fixture-dir]"
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

if ! command -v sips >/dev/null 2>&1; then
    echo "ERROR: sips not found (required for PNG dimension checks)"
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

mkdir -p "$EVAL_DIR/png" "$EVAL_DIR/logs"
RESULTS_CSV="$EVAL_DIR/results.csv"

cat >"$RESULTS_CSV" <<'EOF'
fixture,category,policy,expected_orientation,actual_orientation,width,height,aspect_ratio,expected_duration_s,actual_duration_s,status
EOF

fixture_total=0
render_ok_total=0
render_ok_pass=0
render_ok_fail=0
expected_failure_total=0
expected_failure_pass=0
expected_failure_fail=0
unknown_policy_total=0

SUMMARY_TXT="$EVAL_DIR/summary.txt"
: >"$TMP_DIR/lines.txt"

while IFS= read -r fixture; do
    [ -z "$fixture" ] && continue
    fixture_total=$((fixture_total + 1))

    category="$(manifest_field "$fixture" 2)"
    policy="$(manifest_field "$fixture" 3)"
    expected_orientation="$(manifest_field "$fixture" 4)"
    expected_duration="$(manifest_field "$fixture" 5)"
    [ -z "$category" ] && category="unclassified"
    [ -z "$policy" ] && policy="render_ok"

    slug="$(echo "$fixture" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
    fixture_path="$FIXTURE_DIR/$fixture"
    out_png="$EVAL_DIR/png/$slug.png"
    log="$EVAL_DIR/logs/$slug.log"

    actual_orientation=""
    width=""
    height=""
    ratio=""
    actual_duration=""
    status="PASS"
    reason=""

    if [ ! -f "$fixture_path" ]; then
        status="FAIL"
        reason="fixture not generated"
    fi

    case "$policy" in
        render_ok)
            render_ok_total=$((render_ok_total + 1))

            if [ "$status" = "PASS" ]; then
                if ! "$NATIVE_BIN" "$fixture_path" "$out_png" --seek 0 \
                    --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION" \
                    >/dev/null 2>"$log"; then
                    status="FAIL"
                    reason="render_ok exited non-zero"
                fi
            fi

            if [ "$status" = "PASS" ] && [ ! -s "$out_png" ]; then
                status="FAIL"
                reason="output PNG empty or missing"
            fi

            if [ "$status" = "PASS" ]; then
                dims="$(png_dimensions "$out_png" || true)"
                if [ -z "$dims" ]; then
                    status="FAIL"
                    reason="sips could not read PNG dimensions"
                else
                    width="$(echo "$dims" | cut -d',' -f1)"
                    height="$(echo "$dims" | cut -d',' -f2)"
                    actual_orientation="$(orientation_of "$width" "$height")"
                    ratio="$(aspect_ratio_of "$width" "$height")"
                fi
            fi

            if [ "$status" = "PASS" ] && [ "$actual_orientation" != "$expected_orientation" ]; then
                status="FAIL"
                reason="orientation $actual_orientation != $expected_orientation"
            fi

            # AVFoundation only downscales: both edges must fit the cap. Do NOT
            # assert long-edge == cap (that would be an upscale requirement).
            if [ "$status" = "PASS" ]; then
                if [ "$width" -gt $((MAX_DIMENSION + 2)) ] || [ "$height" -gt $((MAX_DIMENSION + 2)) ]; then
                    status="FAIL"
                    reason="dimensions ${width}x${height} exceed cap $MAX_DIMENSION"
                fi
            fi

            if [ "$status" = "PASS" ] && ! float_ge "$ratio" "$ASPECT_MIN"; then
                status="FAIL"
                reason="aspect ratio $ratio below $ASPECT_MIN (possible square-stretch)"
            fi

            actual_duration="$("$NATIVE_BIN" "$fixture_path" --duration 2>>"$log" || echo "")"
            if [ "$status" = "PASS" ]; then
                if [ -z "$actual_duration" ] || ! float_within "$actual_duration" "$expected_duration" "$DURATION_TOLERANCE_S"; then
                    status="FAIL"
                    reason="duration $actual_duration not within +-${DURATION_TOLERANCE_S}s of $expected_duration"
                fi
            fi

            if [ "$status" = "PASS" ]; then
                render_ok_pass=$((render_ok_pass + 1))
            else
                render_ok_fail=$((render_ok_fail + 1))
            fi
            ;;
        expected_failure)
            expected_failure_total=$((expected_failure_total + 1))

            if [ "$status" = "PASS" ]; then
                if "$NATIVE_BIN" "$fixture_path" "$out_png" --seek 0 \
                    --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION" \
                    >/dev/null 2>"$log"; then
                    status="FAIL"
                    reason="expected_failure fixture rendered successfully"
                fi
            fi

            if [ "$status" = "PASS" ]; then
                expected_failure_pass=$((expected_failure_pass + 1))
            else
                expected_failure_fail=$((expected_failure_fail + 1))
            fi
            ;;
        *)
            unknown_policy_total=$((unknown_policy_total + 1))
            status="FAIL"
            reason="unknown policy: $policy"
            ;;
    esac

    echo "$fixture,$category,$policy,$expected_orientation,$actual_orientation,$width,$height,$ratio,$expected_duration,$actual_duration,$status" >>"$RESULTS_CSV"

    line="$fixture [$category/$policy] $status"
    if [ "$policy" = "render_ok" ]; then
        line="$line orient=$actual_orientation dims=${width}x${height} ratio=$ratio dur=$actual_duration"
    fi
    if [ "$status" = "FAIL" ]; then
        line="$line -- $reason"
    fi
    echo "$line" >>"$TMP_DIR/lines.txt"
done < <(awk -F, 'NR > 1 && $1 != "" {print $1}' "$MANIFEST_FILE")

if [ "$fixture_total" -eq 0 ]; then
    echo "ERROR: No fixtures listed in $MANIFEST_FILE"
    exit 1
fi

corpus_gate="FAIL"
render_gate="FAIL"
failure_gate="FAIL"
overall_gate="FAIL"

if [ "$fixture_total" -ge 4 ]; then
    corpus_gate="PASS"
fi
if [ "$render_ok_fail" -eq 0 ] && [ "$render_ok_total" -gt 0 ]; then
    render_gate="PASS"
fi
if [ "$expected_failure_fail" -eq 0 ] && [ "$expected_failure_total" -gt 0 ]; then
    failure_gate="PASS"
fi

if [ "$corpus_gate" = "PASS" ] && [ "$render_gate" = "PASS" ] && \
   [ "$failure_gate" = "PASS" ] && [ "$unknown_policy_total" -eq 0 ]; then
    overall_gate="PASS"
fi

{
    echo "Video Native Evaluation (self-validating)"
    echo "Fixture directory: $FIXTURE_DIR"
    echo "Fixture manifest: $MANIFEST_FILE"
    echo "Max dimension: $MAX_DIMENSION"
    echo "Fixtures total: $fixture_total"
    echo
    echo "Per fixture:"
    cat "$TMP_DIR/lines.txt"
    echo
    echo "render_ok fixtures: $render_ok_total (pass $render_ok_pass / fail $render_ok_fail)"
    echo "expected_failure fixtures: $expected_failure_total (pass $expected_failure_pass / fail $expected_failure_fail)"
    echo "Unknown policy fixtures: $unknown_policy_total"
    echo "Gate corpus>=4: $corpus_gate"
    echo "Gate render_ok all pass: $render_gate"
    echo "Gate expected_failure all fail-closed: $failure_gate"
    echo "Success gate (ship/no-ship): $overall_gate"
    echo "Results CSV: $RESULTS_CSV"
} >"$SUMMARY_TXT"

cat "$SUMMARY_TXT"

if [ "$overall_gate" != "PASS" ]; then
    exit 1
fi
