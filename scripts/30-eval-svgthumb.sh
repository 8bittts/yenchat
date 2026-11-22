#!/bin/bash
# Evaluate native yen-svgthumb output. Self-validating: there is no reference
# renderer to diff against. Each fixture asserts its manifest policy:
#   render_ok         exits 0, writes a readable PNG whose long edge equals the
#                     cap, and draws at least one pixel (a blank render fails)
#   expected_failure  exits non-zero and writes no output
# A `.svgz` fixture with a `.svg` sibling must also render the same bytes.
#
# Usage:
#   ./scripts/30-eval-svgthumb.sh
#   ./scripts/30-eval-svgthumb.sh /path/to/fixtures
#
# Env:
#   MAX_DIMENSION=2000      # Thumbnail longest edge in pixels
#   REBUILD=1               # Rebuild yen-svgthumb before evaluation (default: 1)
#   MANIFEST_FILE=...       # Fixture metadata CSV (default: <fixture-dir>/manifest.csv)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/30-eval-svgthumb.sh [fixture-dir]"
    exit 0
fi

FIXTURE_DIR="${1:-$REPO_ROOT/yen-svgthumb/fixtures}"
EVAL_DIR="$REPO_ROOT/yen-svgthumb/.eval"

MAX_DIMENSION="${MAX_DIMENSION:-2000}"
REBUILD="${REBUILD:-1}"
MANIFEST_FILE="${MANIFEST_FILE:-$FIXTURE_DIR/manifest.csv}"

NATIVE_DIR="$REPO_ROOT/yen-svgthumb"
NATIVE_BIN="$NATIVE_DIR/yen-svgthumb"
INSPECT_SRC="$NATIVE_DIR/inspect.swift"

manifest_field() {
    local fixture="$1"
    local field="$2"
    awk -F, -v target="$fixture" -v idx="$field" \
        'NR > 1 && $1 == target {print $idx; exit}' "$MANIFEST_FILE"
}

within_tolerance() {
    local value="$1"
    local target="$2"
    local tolerance="$3"
    local diff=$((value - target))
    if [ "$diff" -lt 0 ]; then
        diff=$((-diff))
    fi
    [ "$diff" -le "$tolerance" ]
}

if [ ! -d "$FIXTURE_DIR" ]; then
    echo "ERROR: Fixture directory not found: $FIXTURE_DIR"
    exit 1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Fixture manifest missing: $MANIFEST_FILE"
    exit 1
fi

if [ ! -f "$INSPECT_SRC" ]; then
    echo "ERROR: Inspector source missing: $INSPECT_SRC"
    exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "ERROR: swiftc not found"
    exit 1
fi

if [ "$REBUILD" = "1" ] || [ ! -x "$NATIVE_BIN" ]; then
    echo "Building yen-svgthumb..."
    (cd "$NATIVE_DIR" && ./build.sh)
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

INSPECT_BIN="$TMP_DIR/svg-inspect"
echo "Building inspector..."
swiftc -O -parse-as-library -framework AppKit -o "$INSPECT_BIN" "$INSPECT_SRC"

rm -rf "$EVAL_DIR/png" "$EVAL_DIR/logs"
mkdir -p "$EVAL_DIR/png" "$EVAL_DIR/logs"
RESULTS_CSV="$EVAL_DIR/results.csv"

cat >"$RESULTS_CSV" <<'EOF'
fixture,category,policy,width,height,max_edge,drawn_fraction,status
EOF

fixture_total=0
render_ok_total=0
render_ok_pass=0
render_ok_fail=0
expected_failure_total=0
expected_failure_pass=0
expected_failure_fail=0
compressed_total=0
compressed_fail=0
unknown_policy_total=0
unlisted_total=0

: >"$TMP_DIR/lines.txt"

while IFS= read -r fixture; do
    [ -z "$fixture" ] && continue
    fixture_total=$((fixture_total + 1))

    rel="${fixture#$FIXTURE_DIR/}"
    category="$(manifest_field "$rel" 2)"
    policy="$(manifest_field "$rel" 3)"

    slug="$(echo "$rel" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
    out_png="$EVAL_DIR/png/$slug.png"
    log="$EVAL_DIR/logs/$slug.log"

    width=""
    height=""
    max_edge=""
    drawn=""
    status="PASS"
    reason=""

    # A fixture the manifest does not list has no declared outcome.
    if [ -z "$policy" ]; then
        unlisted_total=$((unlisted_total + 1))
        policy="unlisted"
        status="FAIL"
        reason="fixture missing from the manifest"
    fi

    case "$policy" in
        render_ok)
            render_ok_total=$((render_ok_total + 1))

            if ! "$NATIVE_BIN" "$fixture" "$out_png" --max-dimension "$MAX_DIMENSION" >/dev/null 2>"$log"; then
                status="FAIL"
                reason="render exited non-zero"
            fi

            if [ "$status" = "PASS" ] && [ ! -s "$out_png" ]; then
                status="FAIL"
                reason="output PNG empty or missing"
            fi

            if [ "$status" = "PASS" ]; then
                inspect_csv="$("$INSPECT_BIN" "$out_png" 2>>"$log" || true)"
                if [ -z "$inspect_csv" ]; then
                    status="FAIL"
                    reason="output PNG is not readable"
                else
                    width="$(echo "$inspect_csv" | cut -d',' -f1)"
                    height="$(echo "$inspect_csv" | cut -d',' -f2)"
                    drawn="$(echo "$inspect_csv" | cut -d',' -f3)"
                    if [ "$width" -ge "$height" ]; then
                        max_edge="$width"
                    else
                        max_edge="$height"
                    fi
                fi
            fi

            if [ "$status" = "PASS" ] && ! within_tolerance "$max_edge" "$MAX_DIMENSION" 2; then
                status="FAIL"
                reason="max edge $max_edge not within +-2 of $MAX_DIMENSION"
            fi

            if [ "$status" = "PASS" ] && ! awk -v d="$drawn" 'BEGIN { exit !((d + 0) > 0) }'; then
                status="FAIL"
                reason="render is blank (no drawn pixels)"
            fi

            # A gzip-compressed fixture must match its plain sibling exactly.
            case "$rel" in
                *.svgz)
                    sibling="${fixture%.svgz}.svg"
                    if [ -f "$sibling" ]; then
                        compressed_total=$((compressed_total + 1))
                        sibling_png="$TMP_DIR/$slug.sibling.png"
                        if [ "$status" = "PASS" ]; then
                            if ! "$NATIVE_BIN" "$sibling" "$sibling_png" --max-dimension "$MAX_DIMENSION" >/dev/null 2>>"$log" \
                                || ! cmp -s "$out_png" "$sibling_png"; then
                                status="FAIL"
                                reason="compressed render differs from $(basename "$sibling")"
                                compressed_fail=$((compressed_fail + 1))
                            fi
                        else
                            compressed_fail=$((compressed_fail + 1))
                        fi
                    fi
                    ;;
            esac

            if [ "$status" = "PASS" ]; then
                render_ok_pass=$((render_ok_pass + 1))
            else
                render_ok_fail=$((render_ok_fail + 1))
            fi
            ;;
        expected_failure)
            expected_failure_total=$((expected_failure_total + 1))

            if "$NATIVE_BIN" "$fixture" "$out_png" --max-dimension "$MAX_DIMENSION" >/dev/null 2>"$log"; then
                status="FAIL"
                reason="expected_failure fixture rendered successfully"
            elif [ -e "$out_png" ]; then
                status="FAIL"
                reason="expected_failure fixture left an output file"
            fi

            if [ "$status" = "PASS" ]; then
                expected_failure_pass=$((expected_failure_pass + 1))
            else
                expected_failure_fail=$((expected_failure_fail + 1))
            fi
            ;;
        unlisted)
            ;;
        *)
            unknown_policy_total=$((unknown_policy_total + 1))
            status="FAIL"
            reason="unknown policy: $policy"
            ;;
    esac

    echo "$rel,$category,$policy,$width,$height,$max_edge,$drawn,$status" >>"$RESULTS_CSV"

    line="$rel [$category/$policy] $status"
    if [ "$policy" = "render_ok" ] && [ -n "$width" ]; then
        line="$line dims=${width}x${height} drawn=$drawn"
    fi
    if [ "$status" = "FAIL" ]; then
        line="$line -- $reason"
    fi
    echo "$line" >>"$TMP_DIR/lines.txt"
done < <(find "$FIXTURE_DIR" -type f \( -name "*.svg" -o -name "*.svgz" \) | sort)

if [ "$fixture_total" -eq 0 ]; then
    echo "ERROR: No fixtures found in $FIXTURE_DIR"
    exit 1
fi

corpus_gate="FAIL"
render_gate="FAIL"
failure_gate="FAIL"
compressed_gate="FAIL"
overall_gate="FAIL"

if [ "$fixture_total" -ge 20 ]; then
    corpus_gate="PASS"
fi
if [ "$render_ok_fail" -eq 0 ] && [ "$render_ok_total" -gt 0 ]; then
    render_gate="PASS"
fi
if [ "$expected_failure_fail" -eq 0 ] && [ "$expected_failure_total" -gt 0 ]; then
    failure_gate="PASS"
fi
if [ "$compressed_fail" -eq 0 ] && [ "$compressed_total" -gt 0 ]; then
    compressed_gate="PASS"
fi

if [ "$corpus_gate" = "PASS" ] && [ "$render_gate" = "PASS" ] && \
   [ "$failure_gate" = "PASS" ] && [ "$compressed_gate" = "PASS" ] && \
   [ "$unknown_policy_total" -eq 0 ] && [ "$unlisted_total" -eq 0 ]; then
    overall_gate="PASS"
fi

SUMMARY_TXT="$EVAL_DIR/summary.txt"
{
    echo "SVG Native Evaluation (self-validating)"
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
    echo "Compressed fixtures with a plain sibling: $compressed_total (fail $compressed_fail)"
    echo "Unknown policy fixtures: $unknown_policy_total"
    echo "Fixtures missing from the manifest: $unlisted_total"
    echo "Gate corpus>=20: $corpus_gate"
    echo "Gate render_ok all pass: $render_gate"
    echo "Gate expected_failure all fail-closed: $failure_gate"
    echo "Gate compressed matches plain: $compressed_gate"
    echo "Success gate (ship/no-ship): $overall_gate"
    echo "Results CSV: $RESULTS_CSV"
} >"$SUMMARY_TXT"

cat "$SUMMARY_TXT"

if [ "$overall_gate" != "PASS" ]; then
    exit 1
fi
