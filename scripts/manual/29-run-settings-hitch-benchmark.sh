#!/bin/bash
# Run the canonical Settings Animation Hitches benchmark against zig-out/YEN.app.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_PATH="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/yen"
OUTPUT_DIR="$REPO_ROOT/tmp/perf/settings-hitches/$(date +%F)-zigout-launch"
PAUSE_MS=120
SKIP_BUILD=0
START_DELAY_SECONDS=3
# Each scenario writes a ~250MB .trace bundle. Run back-to-back with no
# settle time, that I/O overlaps the NEXT scenario's measurement and the
# numbers degrade monotonically across a session (measured: five sequential
# full runs drove 1-min load 3.23 -> 9.94 and `rapid-tabs hitches_max_ms`
# 8.33 -> 1266.67 with no code change). Cooldown + a load precondition keep
# a run reproducible; see _docs/13-desktop-features.md "Trace contamination rule".
COOLDOWN_SECONDS=20
MAX_LOAD=4.0
PRUNE_TRACES=0

SCENARIOS="first-open reopen rapid-tabs sounds-refresh"
SUMMARY_COLUMNS="scenario,hitches_rows,hitches_max_ms,hitches_p95_ms,hitches_over100ms,expensive_updates,expensive_renders,potential_hangs,potential_hang_max_ms"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --output-dir PATH    Directory for .trace, XML, process, and summary artifacts
  --pause-ms N         In-app pause between scenario steps in milliseconds (default: 120)
  --skip-build         Reuse the existing zig-out/YEN.app instead of building first
  --cooldown-sec N     Settle time between scenarios in seconds (default: 20, 0 disables)
  --max-load N         Abort if 1-min load average exceeds N (default: 4.0, 0 disables)
  --prune-traces       Delete each .trace bundle after its XML export succeeds
  -h, --help           Show this help text

A run is only comparable against the tracked baseline when the machine is
quiet. --max-load fails closed rather than recording a contaminated trace;
--prune-traces keeps a repeated session from piling up ~1.3GB per full run.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir)
            shift
            OUTPUT_DIR="${1:-}"
            ;;
        --pause-ms)
            shift
            PAUSE_MS="${1:-}"
            ;;
        --skip-build)
            SKIP_BUILD=1
            ;;
        --cooldown-sec)
            shift
            COOLDOWN_SECONDS="${1:-}"
            ;;
        --max-load)
            shift
            MAX_LOAD="${1:-}"
            ;;
        --prune-traces)
            PRUNE_TRACES=1
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

case "$PAUSE_MS" in
    ''|*[!0-9]*)
        echo "ERROR: --pause-ms must be a positive integer"
        exit 1
        ;;
esac

if [ "$PAUSE_MS" -lt 20 ]; then
    echo "ERROR: --pause-ms must be at least 20"
    exit 1
fi

case "$COOLDOWN_SECONDS" in
    ''|*[!0-9]*)
        echo "ERROR: --cooldown-sec must be a non-negative integer"
        exit 1
        ;;
esac

case "$MAX_LOAD" in
    ''|*[!0-9.]*|*.*.*)
        echo "ERROR: --max-load must be a non-negative number"
        exit 1
        ;;
esac

# 1-minute load average, portable across the BSD uptime formats.
current_load_1min() {
    uptime | sed -E 's/.*load averages?: *//' | tr -d ',' | awk '{print $1}'
}

# Fail closed rather than record a contaminated trace. A benchmark that
# silently reports numbers from a busy machine is worse than one that
# refuses: the numbers look authoritative and are not comparable.
assert_load_ok() {
    _phase="$1"
    if [ "$MAX_LOAD" = "0" ] || [ "$MAX_LOAD" = "0.0" ]; then
        return 0
    fi
    _load="$(current_load_1min)"
    if [ -z "$_load" ]; then
        echo "ERROR: could not read load average (refusing to record an unattributable trace)"
        exit 1
    fi
    if awk -v l="$_load" -v m="$MAX_LOAD" 'BEGIN { exit !(l > m) }'; then
        echo "ERROR: 1-min load average $_load exceeds --max-load $MAX_LOAD ($_phase)."
        echo "       Quiet the machine and retry, or pass --max-load 0 to record anyway."
        echo "       A trace taken under load is not comparable to the tracked baseline."
        exit 1
    fi
}

if [ "$SKIP_BUILD" -eq 0 ]; then
    bash "$REPO_ROOT/scripts/native/01-macos-smoke.sh" --build-only
fi

if [ ! -x "$EXECUTABLE" ]; then
    echo "ERROR: Missing executable: $EXECUTABLE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
codesign -dv "$APP_PATH" >"$OUTPUT_DIR/codesign.txt" 2>&1

existing_pids="$(pgrep -fx "$EXECUTABLE" || true)"
if [ -n "$existing_pids" ]; then
    echo "ERROR: Refusing to run with an existing zig-out YEN process:"
    echo "$existing_pids"
    exit 1
fi

assert_load_ok "before run"

CONDITIONS_PATH="$OUTPUT_DIR/conditions.txt"
{
    echo "cooldown_seconds=$COOLDOWN_SECONDS"
    echo "max_load=$MAX_LOAD"
    echo "prune_traces=$PRUNE_TRACES"
    echo "pause_ms=$PAUSE_MS"
    echo "load_before_run=$(current_load_1min)"
} >"$CONDITIONS_PATH"

echo "Settings Animation Hitches Benchmark"
echo "Executable: $EXECUTABLE"
echo "Output dir: $OUTPUT_DIR"
echo "Template: Animation Hitches"
echo "Cooldown: ${COOLDOWN_SECONDS}s   Max load: $MAX_LOAD   Prune traces: $PRUNE_TRACES"
echo ""

first_scenario=1
for scenario in $SCENARIOS; do
    if [ "$first_scenario" -eq 0 ] && [ "$COOLDOWN_SECONDS" -gt 0 ]; then
        echo "[cool] settling ${COOLDOWN_SECONDS}s before $scenario"
        sleep "$COOLDOWN_SECONDS"
    fi
    first_scenario=0

    assert_load_ok "before scenario $scenario"
    echo "load_before_${scenario}=$(current_load_1min)" >>"$CONDITIONS_PATH"

    trace_path="$OUTPUT_DIR/${scenario}.trace"
    stdout_path="$OUTPUT_DIR/${scenario}.stdout"
    start_file="$OUTPUT_DIR/${scenario}.start"
    rm -rf "$trace_path" "$stdout_path" "$start_file"

    echo "[run] scenario=$scenario"
    xcrun xctrace record \
        --quiet \
        --template "Animation Hitches" \
        --output "$trace_path" \
        --target-stdout "$stdout_path" \
        --env "YEN_SETTINGS_HITCH_SCENARIO=$scenario" \
        --env "YEN_SETTINGS_HITCH_PAUSE_MS=$PAUSE_MS" \
        --env "YEN_SETTINGS_HITCH_START_FILE=$start_file" \
        --launch -- "$EXECUTABLE" &
    trace_pid="$!"

    sleep "$START_DELAY_SECONDS"
    touch "$start_file"
    wait "$trace_pid"

    xcrun xctrace export \
        --input "$trace_path" \
        --xpath '//trace-toc[1]/run[1]/data[1]/table[62]' \
        --output "$OUTPUT_DIR/${scenario}-hitches.xml" >/dev/null

    xcrun xctrace export \
        --input "$trace_path" \
        --xpath '//trace-toc[1]/run[1]/data[1]/table[19]' \
        --output "$OUTPUT_DIR/${scenario}-potential-hangs.xml" >/dev/null

    if [ ! -s "$OUTPUT_DIR/${scenario}-hitches.xml" ] || [ ! -s "$OUTPUT_DIR/${scenario}-potential-hangs.xml" ]; then
        echo "ERROR: zero-byte XML export for $scenario"
        exit 1
    fi

    echo "load_after_${scenario}=$(current_load_1min)" >>"$CONDITIONS_PATH"

    # Only after both exports are verified non-empty — a failed export keeps
    # its .trace bundle so the run stays debuggable.
    if [ "$PRUNE_TRACES" -eq 1 ]; then
        rm -rf "$trace_path"
    fi
done

node - "$OUTPUT_DIR" "$SUMMARY_COLUMNS" "$START_DELAY_SECONDS" <<'NODE'
const fs = require("fs");
const path = require("path");

const outputDir = process.argv[2];
const summaryColumns = process.argv[3].split(",");
const startDelayMs = Number(process.argv[4]) * 1000;
const scenarios = ["first-open", "reopen", "rapid-tabs", "sounds-refresh"];
const budgets = {
  "first-open": { hitches_rows: 32, hitches_max_ms: 391.67, hitches_p95_ms: 100, hitches_over100ms: 3, expensive_updates: 8, expensive_renders: 3, potential_hangs: 14, potential_hang_max_ms: 233.65 },
  reopen: { hitches_rows: 40, hitches_max_ms: 383.33, hitches_p95_ms: 66.67, hitches_over100ms: 3, expensive_updates: 8, expensive_renders: 4, potential_hangs: 11, potential_hang_max_ms: 234.70 },
  "rapid-tabs": { hitches_rows: 72, hitches_max_ms: 641.66, hitches_p95_ms: 200, hitches_over100ms: 8, expensive_updates: 9, expensive_renders: 2, potential_hangs: 26, potential_hang_max_ms: 543.57 },
  "sounds-refresh": { hitches_rows: 30, hitches_max_ms: 583.33, hitches_p95_ms: 508.33, hitches_over100ms: 5, expensive_updates: 3, expensive_renders: 2, potential_hangs: 19, potential_hang_max_ms: 680.86 },
};

function attr(source, name) {
  const match = source.match(new RegExp(`${name}="([^"]*)"|${name}='([^']*)'`));
  return match && (match[1] ?? match[2]);
}

function rows(xml) {
  return [...xml.matchAll(/<row>([\s\S]*?)<\/row>/g)].map((match) => match[1]);
}

function startMs(row, refs) {
  const match = row.match(/<start-time\b([^>]*)>([^<]*)<\/start-time>|<start-time\b([^>]*)\/>/);
  if (!match) return 0;
  const attrs = match[1] || match[3] || "";
  const ref = attr(attrs, "ref");
  if (ref) return refs.get(ref) ?? 0;
  const id = attr(attrs, "id");
  const ms = Number(match[2] || "0") / 1e6;
  if (id) refs.set(id, ms);
  return ms;
}

function durationMs(row, refs) {
  const match = row.match(/<duration\b([^>]*)>([^<]*)<\/duration>|<duration\b([^>]*)\/>/);
  if (!match) return 0;
  const attrs = match[1] || match[3] || "";
  const ref = attr(attrs, "ref");
  if (ref) return refs.get(ref) ?? 0;
  const id = attr(attrs, "id");
  const ms = Number(match[2] || "0") / 1e6;
  if (id) refs.set(id, ms);
  return ms;
}

function strings(row, refs) {
  const values = [];
  for (const match of row.matchAll(/<string\b([^>]*?)(?:>([\s\S]*?)<\/string>|\/>)/g)) {
    const attrs = match[1] || "";
    const ref = attr(attrs, "ref");
    if (ref) {
      values.push(refs.get(ref) ?? "");
    } else {
      const id = attr(attrs, "id");
      const value = attr(attrs, "fmt") ?? match[2] ?? "";
      if (id) refs.set(id, value);
      values.push(value);
    }
  }
  return values;
}

function quantile(sorted, q) {
  if (sorted.length === 0) return 0;
  const index = Math.ceil(q * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(sorted.length - 1, index))];
}

const lines = [summaryColumns.join(",")];
const failures = [];

for (const scenario of scenarios) {
  const hitchesXml = fs.readFileSync(path.join(outputDir, `${scenario}-hitches.xml`), "utf8");
  const hangsXml = fs.readFileSync(path.join(outputDir, `${scenario}-potential-hangs.xml`), "utf8");
  const startRefs = new Map();
  const durationRefs = new Map();
  const stringRefs = new Map();
  const hitches = rows(hitchesXml)
    .filter((row) => startMs(row, startRefs) >= startDelayMs)
    .map((row) => ({
      ms: durationMs(row, durationRefs),
      text: strings(row, stringRefs).join(" "),
    }));
  const hangStartRefs = new Map();
  const hangRefs = new Map();
  const hangs = rows(hangsXml)
    .filter((row) => startMs(row, hangStartRefs) >= startDelayMs)
    .map((row) => durationMs(row, hangRefs));
  const sortedHitches = hitches.map((hitch) => hitch.ms).sort((a, b) => a - b);
  const metrics = {
    scenario,
    hitches_rows: hitches.length,
    hitches_max_ms: Math.max(0, ...hitches.map((hitch) => hitch.ms)),
    hitches_p95_ms: quantile(sortedHitches, 0.95),
    hitches_over100ms: hitches.filter((hitch) => hitch.ms > 100).length,
    expensive_updates: hitches.filter((hitch) => /expensive app update/i.test(hitch.text)).length,
    expensive_renders: hitches.filter((hitch) => /expensive render/i.test(hitch.text)).length,
    potential_hangs: hangs.length,
    potential_hang_max_ms: Math.max(0, ...hangs),
  };

  const rowFailures = Object.entries(budgets[scenario])
    .filter(([key, budget]) => metrics[key] > budget)
    .map(([key, budget]) => `${scenario}:${key}=${metrics[key].toFixed(2)}>${budget}`);
  failures.push(...rowFailures);

  lines.push(summaryColumns.map((column) => {
    const value = metrics[column];
    return typeof value === "number" && !Number.isInteger(value) ? value.toFixed(2) : String(value);
  }).join(","));
}

fs.writeFileSync(path.join(outputDir, "summary.csv"), `${lines.join("\n")}\n`);
console.log(lines.join("\n"));

if (failures.length > 0) {
  console.error(`ERROR: Settings hitch budgets exceeded:\n${failures.join("\n")}`);
  process.exit(1);
}
NODE

echo ""
echo "Settings Animation Hitches benchmark passed."
