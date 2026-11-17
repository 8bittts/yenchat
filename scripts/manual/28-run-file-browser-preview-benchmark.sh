#!/bin/bash
# Run a targeted file-browser preview benchmark across representative archive,
# large/minified text, PDF, video, and SVG inputs using the shipped native
# helpers and Yazi-adjacent backend paths.
#
# Usage:
#   ./scripts/manual/28-run-file-browser-preview-benchmark.sh
#
# Env:
#   ARCHIVE_ENTRIES=3000
#   MAX_DIMENSION=2000
#   PDF_FIXTURE=/abs/path/file.pdf
#   VIDEO_FIXTURE=/abs/path/file.mp4
#   SVG_FIXTURE_COMPLEX=/abs/path/file.svg
#   SVG_FIXTURE_LARGE=/abs/path/file.svg
#   OUT_DIR=/abs/path/output-dir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ARCHIVE_ENTRIES="${ARCHIVE_ENTRIES:-3000}"
MAX_DIMENSION="${MAX_DIMENSION:-2000}"
PDF_FIXTURE="${PDF_FIXTURE:-$REPO_ROOT/public/whitepaper.pdf}"
VIDEO_FIXTURE="${VIDEO_FIXTURE:-$REPO_ROOT/public/doc-images/yen-9-customize.mp4}"
SVG_FIXTURE_COMPLEX="${SVG_FIXTURE_COMPLEX:-$REPO_ROOT/yen-svgthumb/fixtures/technical-network-diagram.svg}"
SVG_FIXTURE_LARGE="${SVG_FIXTURE_LARGE:-$REPO_ROOT/yen-svgthumb/fixtures/huge-canvas.svg}"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/yen-terminal/.eval}"
BENCH_DIR="$OUT_DIR/file-browser-preview-benchmark"
RESULTS_CSV="$BENCH_DIR/results.csv"
SUMMARY_TXT="$BENCH_DIR/summary.txt"

YEN_VIDTHUMB="$REPO_ROOT/yen-vidthumb/yen-vidthumb"
YEN_PDFTHUMB="$REPO_ROOT/yen-pdfthumb/yen-pdfthumb"
YEN_SVGTHUMB="$REPO_ROOT/yen-svgthumb/yen-svgthumb"
CODE_GUARD_PLUGIN="$REPO_ROOT/yen-terminal/customizations/yazi-config/plugins/code-guard.yazi/main.lua"
LUA_BIN="${LUA_BIN:-$(command -v lua || true)}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/manual/28-run-file-browser-preview-benchmark.sh"
    exit 0
fi

require_file() {
    if [ ! -f "$1" ]; then
        echo "ERROR: Missing required file: $1"
        exit 1
    fi
}

ensure_exec() {
    if [ ! -x "$1" ]; then
        echo "ERROR: Missing required executable: $1"
        exit 1
    fi
}

float_to_int() {
    awk -v value="$1" 'BEGIN { printf "%d", int(value + 0) }'
}

record_command() {
    local case_id="$1"
    shift

    local stdout_log="$TMP_DIR/$case_id.stdout"
    local time_log="$TMP_DIR/$case_id.time"

    set +e
    /usr/bin/time -l "$@" >"$stdout_log" 2>"$time_log"
    local status=$?
    set -e

    local elapsed_s
    elapsed_s="$(awk 'NR == 1 {print $1; exit}' "$time_log")"
    local elapsed_ms="0.00"
    if [ -n "$elapsed_s" ]; then
        elapsed_ms="$(awk -v s="$elapsed_s" 'BEGIN {printf "%.2f", s * 1000}')"
    fi

    local max_rss
    max_rss="$(awk '/maximum resident set size/ {print $1; exit}' "$time_log")"
    if [ -z "$max_rss" ]; then
        max_rss="0"
    fi

    echo "$case_id,$status,$elapsed_ms,$max_rss" >>"$RESULTS_CSV"

    if [ "$status" -ne 0 ]; then
        echo "ERROR: Benchmark case failed: $case_id"
        echo "See: $time_log"
        exit 1
    fi
}

mkdir -p "$BENCH_DIR"

require_file "$PDF_FIXTURE"
require_file "$VIDEO_FIXTURE"
require_file "$SVG_FIXTURE_COMPLEX"
require_file "$SVG_FIXTURE_LARGE"
require_file "$CODE_GUARD_PLUGIN"

ensure_exec "$YEN_VIDTHUMB"
ensure_exec "$YEN_PDFTHUMB"
ensure_exec "$YEN_SVGTHUMB"
ensure_exec "/usr/bin/time"
ensure_exec "/usr/bin/bsdtar"
if [ -z "$LUA_BIN" ]; then
    echo "ERROR: lua not found on PATH"
    exit 1
fi
ensure_exec "$LUA_BIN"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_SRC_DIR="$TMP_DIR/archive-src"
ARCHIVE_FIXTURE="$TMP_DIR/preview-benchmark.tar"
MINIFIED_FIXTURE="$TMP_DIR/minified-large.json"
PDF_OUT_DIR="$TMP_DIR/pdf"
VIDEO_OUT_DIR="$TMP_DIR/video"
SVG_OUT_DIR="$TMP_DIR/svg"
CODE_GUARD_RUNNER="$TMP_DIR/code-guard-bench.lua"

mkdir -p "$ARCHIVE_SRC_DIR" "$PDF_OUT_DIR" "$VIDEO_OUT_DIR" "$SVG_OUT_DIR"

echo "Building large archive fixture with $ARCHIVE_ENTRIES entries..."
i=1
while [ "$i" -le "$ARCHIVE_ENTRIES" ]; do
    group=$(((i - 1) / 100))
    group_dir="$ARCHIVE_SRC_DIR/group-$group"
    [ -d "$group_dir" ] || mkdir -p "$group_dir"
    printf "entry-%04d\n" "$i" >"$group_dir/file-$i.txt"
    i=$((i + 1))
done
/usr/bin/bsdtar -cf "$ARCHIVE_FIXTURE" -C "$ARCHIVE_SRC_DIR" .

awk 'BEGIN {
    printf "{\"items\":[";
    for (i = 0; i < 50000; i++) {
        if (i > 0) {
            printf ",";
        }
        printf "\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"";
    }
    printf "]}";
}' >"$MINIFIED_FIXTURE"

cat >"$CODE_GUARD_RUNNER" <<'LUA_EOF'
local plugin_path = assert(arg[1], "missing plugin path")
local target_path = assert(arg[2], "missing target path")

local function read_all(path)
  local handle = assert(io.open(path, "r"))
  local data = assert(handle:read("*a"))
  handle:close()
  return data
end

local source = read_all(plugin_path)
source = source:gsub(
  "return M",
  "return { __test = { build_plain_lines = build_plain_lines } }",
  1
)

local attrs = { len = 0, mtime = 7, mode = 33188 }
do
  local handle = assert(io.open(target_path, "rb"))
  attrs.len = assert(handle:seek("end")) or 0
  handle:close()
end

local open_count = 0
local real_io_open = io.open
io.open = function(...)
  open_count = open_count + 1
  return real_io_open(...)
end

ya = {
  emit = function() end,
  preview_widget = function() end,
}
ui = {
  Text = function(items)
    return {
      items = items,
      area = function(self, _)
        return self
      end,
    }
  end,
}
fs = {
  cha = function(_)
    return attrs
  end,
}
cx = {
  active = {
    preview = { skip = 0 },
  },
}

local plugin = assert(load(source, "@code-guard.yazi"))()

local start = os.clock()
local first = plugin.__test.build_plain_lines(target_path, "minified content", attrs.len)
local first_ms = (os.clock() - start) * 1000

start = os.clock()
local second = plugin.__test.build_plain_lines(target_path, "minified content", attrs.len)
local second_ms = (os.clock() - start) * 1000

print(string.format("first_ms=%.3f", first_ms))
print(string.format("second_ms=%.3f", second_ms))
print(string.format("open_count=%d", open_count))
print(string.format("first_lines=%d", #first))
print(string.format("second_lines=%d", #second))
LUA_EOF

PDF_PAGES="$("$YEN_PDFTHUMB" "$PDF_FIXTURE" --pages | tr -d '\r')"
PDF_MID_PAGE="0"
if [ "$PDF_PAGES" -gt 1 ]; then
    PDF_MID_PAGE=$((PDF_PAGES / 2))
fi

VIDEO_DURATION="$("$YEN_VIDTHUMB" "$VIDEO_FIXTURE" --duration | tr -d '\r')"
VIDEO_FIRST_SEEK="0"
if awk -v d="$VIDEO_DURATION" 'BEGIN { exit !((d + 0) >= 1) }'; then
    VIDEO_FIRST_SEEK="1"
fi
VIDEO_MID_SEEK="$(awk -v d="$VIDEO_DURATION" 'BEGIN { mid = int((d + 0) / 2); if (mid < 0) mid = 0; printf "%d", mid }')"

cat >"$RESULTS_CSV" <<'CSV_EOF'
case,status,elapsed_ms,max_rss_bytes
CSV_EOF

echo "Running archive benchmarks..."
record_command "archive-first" /usr/bin/bsdtar -tf "$ARCHIVE_FIXTURE"
record_command "archive-repeat" /usr/bin/bsdtar -tf "$ARCHIVE_FIXTURE"

echo "Running code-guard benchmark..."
CODE_GUARD_OUTPUT="$("$LUA_BIN" "$CODE_GUARD_RUNNER" "$CODE_GUARD_PLUGIN" "$MINIFIED_FIXTURE")"
CODE_GUARD_FIRST_MS="$(echo "$CODE_GUARD_OUTPUT" | awk -F= '/^first_ms=/ {print $2; exit}')"
CODE_GUARD_SECOND_MS="$(echo "$CODE_GUARD_OUTPUT" | awk -F= '/^second_ms=/ {print $2; exit}')"
CODE_GUARD_OPEN_COUNT="$(echo "$CODE_GUARD_OUTPUT" | awk -F= '/^open_count=/ {print $2; exit}')"
CODE_GUARD_FIRST_LINES="$(echo "$CODE_GUARD_OUTPUT" | awk -F= '/^first_lines=/ {print $2; exit}')"
CODE_GUARD_SECOND_LINES="$(echo "$CODE_GUARD_OUTPUT" | awk -F= '/^second_lines=/ {print $2; exit}')"
echo "code-guard-first,0,$CODE_GUARD_FIRST_MS,0" >>"$RESULTS_CSV"
echo "code-guard-repeat,0,$CODE_GUARD_SECOND_MS,0" >>"$RESULTS_CSV"

echo "Running PDF benchmarks..."
record_command "pdf-first" "$YEN_PDFTHUMB" "$PDF_FIXTURE" "$PDF_OUT_DIR/page-first.png" --page 0 --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"
record_command "pdf-scroll" "$YEN_PDFTHUMB" "$PDF_FIXTURE" "$PDF_OUT_DIR/page-mid.png" --page "$PDF_MID_PAGE" --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"
record_command "pdf-repeat" "$YEN_PDFTHUMB" "$PDF_FIXTURE" "$PDF_OUT_DIR/page-mid-repeat.png" --page "$PDF_MID_PAGE" --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"

echo "Running video benchmarks..."
record_command "video-first" "$YEN_VIDTHUMB" "$VIDEO_FIXTURE" "$VIDEO_OUT_DIR/first.png" --seek "$VIDEO_FIRST_SEEK" --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"
record_command "video-scroll" "$YEN_VIDTHUMB" "$VIDEO_FIXTURE" "$VIDEO_OUT_DIR/mid.png" --seek "$VIDEO_MID_SEEK" --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"
record_command "video-repeat" "$YEN_VIDTHUMB" "$VIDEO_FIXTURE" "$VIDEO_OUT_DIR/mid-repeat.png" --seek "$VIDEO_MID_SEEK" --max-width "$MAX_DIMENSION" --max-height "$MAX_DIMENSION"

echo "Running SVG benchmarks..."
record_command "svg-complex-first" "$YEN_SVGTHUMB" "$SVG_FIXTURE_COMPLEX" "$SVG_OUT_DIR/complex-first.png" --max-dimension "$MAX_DIMENSION"
record_command "svg-complex-repeat" "$YEN_SVGTHUMB" "$SVG_FIXTURE_COMPLEX" "$SVG_OUT_DIR/complex-repeat.png" --max-dimension "$MAX_DIMENSION"
record_command "svg-large-first" "$YEN_SVGTHUMB" "$SVG_FIXTURE_LARGE" "$SVG_OUT_DIR/large-first.png" --max-dimension "$MAX_DIMENSION"
record_command "svg-large-repeat" "$YEN_SVGTHUMB" "$SVG_FIXTURE_LARGE" "$SVG_OUT_DIR/large-repeat.png" --max-dimension "$MAX_DIMENSION"

{
    echo "File Browser Preview Benchmark"
    echo "Archive fixture: $ARCHIVE_FIXTURE ($ARCHIVE_ENTRIES entries)"
    echo "Minified fixture: $MINIFIED_FIXTURE ($(wc -c <"$MINIFIED_FIXTURE" | tr -d '[:space:]') bytes)"
    echo "PDF fixture: $PDF_FIXTURE (pages=$PDF_PAGES mid_page=$PDF_MID_PAGE)"
    echo "Video fixture: $VIDEO_FIXTURE (duration_s=$VIDEO_DURATION mid_seek=$VIDEO_MID_SEEK)"
    echo "SVG fixtures: $SVG_FIXTURE_COMPLEX ; $SVG_FIXTURE_LARGE"
    echo "Max dimension: $MAX_DIMENSION"
    echo
    echo "Code-guard cache check:"
    echo "  first_ms=$CODE_GUARD_FIRST_MS"
    echo "  second_ms=$CODE_GUARD_SECOND_MS"
    echo "  open_count=$CODE_GUARD_OPEN_COUNT"
    echo "  first_lines=$CODE_GUARD_FIRST_LINES"
    echo "  second_lines=$CODE_GUARD_SECOND_LINES"
    echo
    echo "Results CSV: $RESULTS_CSV"
    cat "$RESULTS_CSV"
} >"$SUMMARY_TXT"

cat "$SUMMARY_TXT"
