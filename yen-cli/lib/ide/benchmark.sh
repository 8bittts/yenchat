# shellcheck shell=bash
# Source-time pure benchmark harness helpers and command handlers for yen ide.

benchmark_fixture_bundle_root() {
    printf "%s/fixtures/ide-benchmark\n" "${YEN_RESOURCES}"
}

benchmark_cli_path() {
    printf "%s/bin/yen\n" "${YEN_RESOURCES}"
}

benchmark_report_root() {
    local target="$1"
    if [[ -n "${target}" ]]; then
        find_project_root "${target}"
        return 0
    fi
    benchmark_fixture_bundle_root
}

benchmark_root_hash() {
    local root="$1"
    project_short_hash_for_root "${root}"
}

benchmark_latest_file_for_root() {
    local root="$1"
    printf "%s/benchmark-%s-latest.json\n" "${IDE_BENCHMARK_DIR}" "$(benchmark_root_hash "${root}")"
}

benchmark_baseline_file_for_root() {
    local root="$1"
    printf "%s/benchmark-%s-baseline.json\n" "${IDE_BENCHMARK_DIR}" "$(benchmark_root_hash "${root}")"
}

benchmark_history_file_for_root() {
    local root="$1"
    printf "%s/benchmark-%s-history.tsv\n" "${IDE_BENCHMARK_DIR}" "$(benchmark_root_hash "${root}")"
}

benchmark_status_json_for_root() {
    local root="$1"
    local latest_file=""
    local baseline_file=""

    latest_file=$(benchmark_latest_file_for_root "${root}")
    baseline_file=$(benchmark_baseline_file_for_root "${root}")

    BENCHMARK_STATUS_ROOT="${root}" \
    BENCHMARK_STATUS_LATEST="${latest_file}" \
    BENCHMARK_STATUS_BASELINE="${baseline_file}" \
    python3 - <<'PY'
import json
import os
import pathlib


def load_json(path_text: str):
    if not path_text:
        return None
    path = pathlib.Path(path_text)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


root = os.environ.get("BENCHMARK_STATUS_ROOT", "")
latest = load_json(os.environ.get("BENCHMARK_STATUS_LATEST", ""))
baseline = load_json(os.environ.get("BENCHMARK_STATUS_BASELINE", ""))

summary = {
    "overallStatus": "missing",
    "reason": "No benchmark report has been recorded yet.",
}
if isinstance(latest, dict):
    summary = dict((latest.get("summary") or {}))

payload = {
    "schemaVersion": 1,
    "root": root,
    "latestAvailable": isinstance(latest, dict),
    "baselineAvailable": isinstance(baseline, dict),
    "summary": summary,
    "latest": latest,
    "baseline": baseline,
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

benchmark_run_json_for_root() {
    local root="$1"
    local target_mode="$2"
    local suites_csv="$3"
    local samples="$4"
    local write_baseline="$5"
    local latest_file=""
    local baseline_file=""
    local history_file=""
    local fixture_bundle=""
    local cli_path=""

    latest_file=$(benchmark_latest_file_for_root "${root}")
    baseline_file=$(benchmark_baseline_file_for_root "${root}")
    history_file=$(benchmark_history_file_for_root "${root}")
    fixture_bundle=$(benchmark_fixture_bundle_root)
    cli_path=$(benchmark_cli_path)

    BENCHMARK_ROOT="${root}" \
    BENCHMARK_TARGET_MODE="${target_mode}" \
    BENCHMARK_SUITES="${suites_csv}" \
    BENCHMARK_SAMPLES="${samples}" \
    BENCHMARK_WRITE_BASELINE="${write_baseline}" \
    BENCHMARK_FIXTURE_BUNDLE="${fixture_bundle}" \
    BENCHMARK_CLI_PATH="${cli_path}" \
    BENCHMARK_LATEST_FILE="${latest_file}" \
    BENCHMARK_BASELINE_FILE="${baseline_file}" \
    BENCHMARK_HISTORY_FILE="${history_file}" \
    BENCHMARK_TIMELINE_FILE="${IDE_TIMELINE_FILE}" \
    BENCHMARK_SLO_FILE="${IDE_NON_INTERFERENCE_SLO_FILE}" \
    python3 - <<'PY'
import json
import os
import pathlib
import platform
import shutil
import subprocess
import tempfile
import time


def iso_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def epoch_now():
    return str(int(time.time()))


def sanitize_field(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def first_lines(blob, limit=3):
    lines = []
    for raw in (blob or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        lines.append(line[:240])
        if len(lines) >= limit:
            break
    return lines


def load_json(path_text):
    if not path_text:
        return None
    path = pathlib.Path(path_text)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_json(path_text, payload):
    path = pathlib.Path(path_text)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def append_history(path_text, row):
    path = pathlib.Path(path_text)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(row + "\n")


def append_timeline(path_text, root, status, detail):
    if not path_text:
        return
    path = pathlib.Path(path_text)
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_status = sanitize_field(status)
    safe_detail = sanitize_field(detail)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"{iso_now()}\tbenchmark\t{root}\t{safe_status}\t{safe_detail}\n")


def append_slo(path_text, root, metric, value, threshold, source, sample_status, execution_status):
    if not path_text:
        return
    if execution_status != "pass":
        return
    if sample_status not in {"pass", "breach"}:
        return
    path = pathlib.Path(path_text)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        numeric_value = float(value)
    except Exception:
        numeric_value = 0.0
    try:
        numeric_threshold = float(threshold)
    except Exception:
        numeric_threshold = 0.0
    with path.open("a", encoding="utf-8") as handle:
        handle.write(
            "\t".join(
                [
                    iso_now(),
                    epoch_now(),
                    metric,
                    str(int(round(numeric_value))),
                    str(int(round(numeric_threshold))),
                    sample_status,
                    sanitize_field(source),
                    root,
                ]
            )
            + "\n"
        )


def status_rank(value):
    ranks = {"pass": 0, "warn": 1, "fail": 2, "missing": 2}
    return ranks.get(value, 2)


def combine_status(current, candidate):
    return candidate if status_rank(candidate) > status_rank(current) else current


def non_interference_threshold(metric):
    env_map = {
        "search-latency-ms": "YEN_IDE_SLO_SEARCH_LATENCY_MS",
        "lsp-start-ms": "YEN_IDE_SLO_LSP_START_MS",
        "verify-duration-ms": "YEN_IDE_SLO_VERIFY_DURATION_MS",
        "orchestration-latency-ms": "YEN_IDE_SLO_ORCHESTRATION_LATENCY_MS",
    }
    defaults = {
        "search-latency-ms": 250,
        "lsp-start-ms": 1500,
        "verify-duration-ms": 4000,
        "orchestration-latency-ms": 1200,
    }
    raw = os.environ.get(env_map.get(metric, ""), "")
    try:
        parsed = int(raw)
        if parsed > 0:
            return parsed
    except Exception:
        pass
    return defaults.get(metric, 1000)


def comparison_policy(suite_id):
    return {
        "search": {"allowedMs": 80, "allowedRatio": 0.35},
        "lsp": {"allowedMs": 200, "allowedRatio": 0.50},
        "verify": {"allowedMs": 250, "allowedRatio": 0.35},
        "orchestration": {"allowedMs": 120, "allowedRatio": 0.35},
    }.get(suite_id, {"allowedMs": 100, "allowedRatio": 0.35})


ROOT = os.environ.get("BENCHMARK_ROOT", "")
TARGET_MODE = os.environ.get("BENCHMARK_TARGET_MODE", "fixture")
FIXTURE_BUNDLE = pathlib.Path(os.environ.get("BENCHMARK_FIXTURE_BUNDLE", "")).resolve()
CLI_PATH = os.environ.get("BENCHMARK_CLI_PATH", "")
LATEST_FILE = os.environ.get("BENCHMARK_LATEST_FILE", "")
BASELINE_FILE = os.environ.get("BENCHMARK_BASELINE_FILE", "")
HISTORY_FILE = os.environ.get("BENCHMARK_HISTORY_FILE", "")
TIMELINE_FILE = os.environ.get("BENCHMARK_TIMELINE_FILE", "")
SLO_FILE = os.environ.get("BENCHMARK_SLO_FILE", "")
WRITE_BASELINE = os.environ.get("BENCHMARK_WRITE_BASELINE", "0") == "1"

try:
    SAMPLES = int(os.environ.get("BENCHMARK_SAMPLES", "2") or "2")
except Exception:
    SAMPLES = 2
if SAMPLES < 1:
    raise SystemExit("benchmark --samples must be a positive integer")

raw_suites = os.environ.get("BENCHMARK_SUITES", "all").strip() or "all"
requested = []
for token in raw_suites.replace(" ", "").split(","):
    if not token:
        continue
    if token == "all":
        requested = ["search", "lsp", "verify", "orchestration"]
        break
    if token not in requested:
        requested.append(token)

valid_suites = {"search", "lsp", "verify", "orchestration"}
invalid = [token for token in requested if token not in valid_suites]
if invalid:
    raise SystemExit(f"Unknown benchmark suite(s): {', '.join(invalid)}")
if not requested:
    requested = ["search", "lsp", "verify", "orchestration"]

if not CLI_PATH or not pathlib.Path(CLI_PATH).is_file():
    raise SystemExit("Unable to locate the YEN CLI entrypoint for benchmark execution.")

fixture_roots = {
    "search": FIXTURE_BUNDLE / "lsp",
    "lsp": FIXTURE_BUNDLE / "lsp",
    "verify": FIXTURE_BUNDLE / "verify",
    "orchestration": FIXTURE_BUNDLE / "orchestration",
}
fixture_mock_bin = FIXTURE_BUNDLE / "mock-bin"

suite_labels = {
    "search": "Search latency",
    "lsp": "LSP start latency",
    "verify": "Verify duration",
    "orchestration": "Orchestration control-plane latency",
}
suite_metrics = {
    "search": "search-latency-ms",
    "lsp": "lsp-start-ms",
    "verify": "verify-duration-ms",
    "orchestration": "orchestration-latency-ms",
}


def suite_target_root(suite_id):
    if TARGET_MODE == "project":
        return pathlib.Path(ROOT).resolve()
    return fixture_roots[suite_id].resolve()


def run_command(command, cwd, env):
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    duration_ms = int((time.perf_counter() - started) * 1000)
    output = (completed.stdout or "") + (completed.stderr or "")
    return completed.returncode, duration_ms, output


def run_sequence(steps, cwd, env):
    total_duration = 0
    output_chunks = []
    exit_code = 0
    for command in steps:
        code, duration_ms, output = run_command(command, cwd, env)
        total_duration += duration_ms
        output_chunks.append("$ " + " ".join(command))
        if output:
            output_chunks.append(output)
        if code != 0:
            exit_code = code
            break
    return exit_code, total_duration, "\n".join(output_chunks)


def suite_environment():
    return {
        "os": platform.platform(),
        "python": platform.python_version(),
        "machine": platform.machine(),
        "shell": os.environ.get("SHELL", ""),
        "cliPath": CLI_PATH,
        "fixtureBundle": str(FIXTURE_BUNDLE),
    }


def run_suite(suite_id):
    target_root = suite_target_root(suite_id)
    if not target_root.exists():
        return {
            "id": suite_id,
            "label": suite_labels[suite_id],
            "targetRoot": str(target_root),
            "execution": {
                "status": "fail",
                "exitCode": 127,
                "command": "",
            },
            "coverage": {
                "status": "missing",
                "note": "Fixture root is missing.",
            },
            "measurement": {
                "coldMs": 0,
                "warmAvgMs": 0,
                "warmMinMs": 0,
                "warmMaxMs": 0,
                "warmRuns": 0,
                "warmSamplesMs": [],
            },
            "guardrail": {
                "metric": suite_metrics[suite_id],
                "threshold": non_interference_threshold(suite_metrics[suite_id]),
                "status": "fail",
                "value": 0,
            },
            "comparison": {
                "status": "missing",
                "reason": "Fixture root missing.",
            },
            "status": "fail",
            "notes": ["fixture-missing"],
            "logExcerpt": [],
        }

    temp_root = pathlib.Path(tempfile.mkdtemp(prefix=f"yen-benchmark-{suite_id}-"))
    ide_state = temp_root / "ide-state"
    agents_state = temp_root / "agents-state"
    ide_state.mkdir(parents=True, exist_ok=True)
    agents_state.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env["YEN_IDE_STATE_DIR"] = str(ide_state)
    env["YEN_AGENTS_STATE_DIR"] = str(agents_state)

    if suite_id == "orchestration":
        env["PATH"] = str(fixture_mock_bin) + os.pathsep + env.get("PATH", "")
    if suite_id == "lsp":
        env["YEN_IDE_LSP_FORCE_PLACEHOLDER"] = "1"
        # State isolation must include the socket: concurrent runs share the fixture root.
        env["YEN_IDE_LSP_SOCKET_DIR"] = str(temp_root / "s")

    base_command = CLI_PATH
    working_dir = target_root
    notes = []
    coverage = {"status": "complete", "note": "fixture-backed suite"}

    if suite_id == "search":
        query = "benchmarkNavigator"
        sequence = [[base_command, "ide", "search", query, "--project", str(target_root), "--sources", "files,content,actions", "--limit", "20"]]
        notes.append("search-sources=files,content,actions")
    elif suite_id == "lsp":
        sequence = [
            [base_command, "ide", "lsp", "trust", str(target_root)],
            [base_command, "ide", "lsp", "start", str(target_root)],
            [base_command, "ide", "lsp", "status", str(target_root), "--format", "json"],
            [base_command, "ide", "lsp", "stop", str(target_root)],
        ]
        coverage = {"status": "placeholder", "note": "forced placeholder runtime for deterministic startup timing"}
        notes.append("lsp-runtime=placeholder")
    elif suite_id == "verify":
        sequence = [[base_command, "ide", "verify", "--quick", "--no-security"]]
        notes.append("verify-mode=quick-no-security")
    else:
        sequence = [
            [base_command, "agents", "list"],
            [base_command, "agents", "open", "--profile", "codex", "--dry-run"],
        ]
        coverage = {"status": "mock-adapters", "note": "fixture-provided claude/codex adapters on PATH"}
        notes.append("adapter-mode=mock")

    cold_code, cold_ms, cold_output = run_sequence(sequence, working_dir, env)
    warm_values = []
    warm_output = ""
    warm_code = 0
    for _ in range(SAMPLES):
        code, duration_ms, output = run_sequence(sequence, working_dir, env)
        warm_values.append(duration_ms)
        if not warm_output:
            warm_output = output
        if code != 0:
            warm_code = code
            break

    shutil.rmtree(temp_root, ignore_errors=True)

    execution_status = "pass"
    exit_code = 0
    combined_output = cold_output or warm_output
    if cold_code != 0:
        execution_status = "fail"
        exit_code = cold_code
        warm_values = []
    elif warm_code != 0:
        execution_status = "fail"
        exit_code = warm_code

    warm_runs = len(warm_values)
    warm_avg = int(round(sum(warm_values) / warm_runs)) if warm_runs > 0 else 0
    warm_min = min(warm_values) if warm_values else 0
    warm_max = max(warm_values) if warm_values else 0
    metric_name = suite_metrics[suite_id]
    threshold = non_interference_threshold(metric_name)
    guardrail_status = "breach" if warm_avg > threshold else "pass"
    suite_status = "pass"
    if execution_status != "pass":
        suite_status = "fail"
    elif guardrail_status == "breach":
        suite_status = "fail"

    return {
        "id": suite_id,
        "label": suite_labels[suite_id],
        "targetRoot": str(target_root),
        "execution": {
            "status": execution_status,
            "exitCode": exit_code,
            "command": " && ".join(" ".join(command) for command in sequence),
        },
        "coverage": coverage,
        "measurement": {
            "coldMs": cold_ms,
            "warmAvgMs": warm_avg,
            "warmMinMs": warm_min,
            "warmMaxMs": warm_max,
            "warmRuns": warm_runs,
            "warmSamplesMs": warm_values,
        },
        "guardrail": {
            "metric": metric_name,
            "threshold": threshold,
            "status": guardrail_status,
            "value": warm_avg,
        },
        "comparison": {
            "status": "pending",
            "reason": "",
        },
        "status": suite_status,
        "notes": notes,
        "logExcerpt": first_lines(combined_output),
    }


baseline_payload = load_json(BASELINE_FILE)
baseline_available = isinstance(baseline_payload, dict)
suites = [run_suite(suite_id) for suite_id in requested]

overall_status = "pass"
baseline_written = False
summary_reason = "Benchmarks passed."

baseline_suite_map = {}
if baseline_available:
    for suite in baseline_payload.get("suites") or []:
        suite_id = suite.get("id")
        if suite_id:
            baseline_suite_map[suite_id] = suite

for suite in suites:
    suite_id = suite["id"]
    suite_status = suite.get("status", "pass")
    if suite["execution"]["status"] != "pass":
        suite["comparison"] = {
            "status": "fail",
            "reason": "Benchmark command failed.",
        }
        overall_status = combine_status(overall_status, "fail")
        continue

    if WRITE_BASELINE:
        suite["comparison"] = {
            "status": "baseline-written",
            "reason": "Recorded new benchmark baseline from this run.",
        }
        continue

    baseline_suite = baseline_suite_map.get(suite_id)
    if not baseline_suite:
        suite["comparison"] = {
            "status": "fail",
            "reason": "No baseline exists for this suite.",
        }
        suite["status"] = "fail"
        overall_status = combine_status(overall_status, "fail")
        continue

    base_measurement = baseline_suite.get("measurement") or {}
    base_warm = int(base_measurement.get("warmAvgMs") or 0)
    base_cold = int(base_measurement.get("coldMs") or 0)
    current_warm = int((suite.get("measurement") or {}).get("warmAvgMs") or 0)
    current_cold = int((suite.get("measurement") or {}).get("coldMs") or 0)
    policy = comparison_policy(suite_id)

    warm_delta = current_warm - base_warm
    cold_delta = current_cold - base_cold
    warm_ratio = (float(warm_delta) / float(base_warm)) if base_warm > 0 else 0.0
    cold_ratio = (float(cold_delta) / float(base_cold)) if base_cold > 0 else 0.0

    compare_status = "pass"
    compare_reason = "Within saved baseline tolerance."
    warn_ms = max(int(policy["allowedMs"] / 2), 20)
    warn_ratio = float(policy["allowedRatio"]) / 2.0

    if (
        (warm_delta > policy["allowedMs"] and warm_ratio > policy["allowedRatio"])
        or (cold_delta > policy["allowedMs"] and cold_ratio > policy["allowedRatio"])
    ):
        compare_status = "fail"
        compare_reason = "Measured duration regressed beyond baseline tolerance."
    elif (
        warm_delta > warn_ms
        or cold_delta > warn_ms
        or warm_ratio > warn_ratio
        or cold_ratio > warn_ratio
    ):
        compare_status = "warn"
        compare_reason = "Measured duration drifted above the warning threshold."

    suite["comparison"] = {
        "status": compare_status,
        "reason": compare_reason,
        "baselineWarmAvgMs": base_warm,
        "baselineColdMs": base_cold,
        "warmDeltaMs": warm_delta,
        "coldDeltaMs": cold_delta,
        "warmRatio": round(warm_ratio, 4),
        "coldRatio": round(cold_ratio, 4),
    }

    if suite["guardrail"]["status"] == "breach":
        suite["status"] = "fail"
        suite["notes"].append("non-interference-threshold-breach")
    else:
        suite["status"] = combine_status(suite_status, compare_status)
    overall_status = combine_status(overall_status, suite["status"])

if WRITE_BASELINE:
    if overall_status == "fail":
        baseline_written = False
        summary_reason = "Benchmark run failed; baseline was not updated."
    else:
        baseline_written = True
        summary_reason = "Recorded a fresh benchmark baseline."
else:
    if not baseline_available:
        overall_status = "fail"
        summary_reason = "No saved benchmark baseline exists yet. Re-run with --write-baseline."
    elif overall_status == "warn":
        summary_reason = "Benchmarks completed with warning-level drift."
    elif overall_status == "fail":
        summary_reason = "Benchmarks regressed or breached a guardrail."

summary = {
    "overallStatus": overall_status,
    "reason": summary_reason,
    "suiteCount": len(suites),
    "pass": sum(1 for suite in suites if suite.get("status") == "pass"),
    "warn": sum(1 for suite in suites if suite.get("status") == "warn"),
    "fail": sum(1 for suite in suites if suite.get("status") == "fail"),
    "baselineAvailable": baseline_available or baseline_written,
    "baselineWritten": baseline_written,
}

payload = {
    "schemaVersion": 1,
    "root": ROOT,
    "targetMode": TARGET_MODE,
    "fixtureBundle": str(FIXTURE_BUNDLE),
    "requestedSuites": requested,
    "samples": SAMPLES,
    "ranAt": iso_now(),
    "environment": suite_environment(),
    "summary": summary,
    "suites": suites,
}

write_json(LATEST_FILE, payload)
if baseline_written:
    write_json(BASELINE_FILE, payload)

append_history(
    HISTORY_FILE,
    "\t".join(
        [
            payload["ranAt"],
            ROOT,
            TARGET_MODE,
            overall_status,
            "yes" if baseline_written else "no",
            ",".join(requested),
        ]
    ),
)
append_timeline(
    TIMELINE_FILE,
    ROOT,
    f"status={overall_status};baseline={'yes' if baseline_written else 'no'}",
    f"suites={','.join(requested)};mode={TARGET_MODE};samples={SAMPLES}",
)
for suite in suites:
    append_slo(
        SLO_FILE,
        ROOT,
        suite["guardrail"]["metric"],
        suite["guardrail"]["value"],
        suite["guardrail"]["threshold"],
        f"benchmark:{suite['id']}",
        suite["guardrail"].get("status"),
        (suite.get("execution") or {}).get("status"),
    )

print(json.dumps(payload, indent=2, sort_keys=True))
if overall_status == "fail":
    raise SystemExit(1)
PY
}

benchmark_text_from_payload() {
    local payload="$1"
    BENCHMARK_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def load_payload():
    try:
        return json.loads(os.environ.get("BENCHMARK_PAYLOAD") or "{}")
    except Exception:
        return {}


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


payload = load_payload()
wrapper_mode = "latestAvailable" in payload
latest = payload.get("latest") if wrapper_mode else payload
summary = (latest or {}).get("summary") or {}

print("")
print("IDE Benchmarks")
print(f"Root:            {text(payload.get('root') if wrapper_mode else latest.get('root'))}")
if wrapper_mode:
    print(f"Latest report:   {'present' if payload.get('latestAvailable') else 'missing'}")
    print(f"Baseline:        {'present' if payload.get('baselineAvailable') else 'missing'}")
    if not payload.get("latestAvailable"):
        print(f"Status:          {text(summary.get('overallStatus'), 'missing')}")
        print(f"Reason:          {text(summary.get('reason'), 'No benchmark report has been recorded yet.')}")
        print("")
        raise SystemExit(0)

print(f"Target mode:     {text((latest or {}).get('targetMode'), 'unknown')}")
print(f"Overall status:  {text(summary.get('overallStatus'), 'missing')}")
print(f"Reason:          {text(summary.get('reason'))}")
print(f"Suites:          {int(summary.get('suiteCount') or 0)}")
print(f"Samples:         {int((latest or {}).get('samples') or 0)}")
print(f"Ran at:          {text((latest or {}).get('ranAt'))}")
print("")
print(f"{'SUITE':<16} {'STATUS':<8} {'COLD(ms)':<10} {'WARM(ms)':<10} {'METRIC':<28} {'THRESHOLD':<10}")
for suite in (latest or {}).get("suites") or []:
    measurement = suite.get("measurement") or {}
    guardrail = suite.get("guardrail") or {}
    print(
        f"{text(suite.get('id')):<16} "
        f"{text(suite.get('status')):<8} "
        f"{int(measurement.get('coldMs') or 0):<10} "
        f"{int(measurement.get('warmAvgMs') or 0):<10} "
        f"{text(guardrail.get('metric')):<28} "
        f"{int(guardrail.get('threshold') or 0):<10}"
    )
    comparison = suite.get("comparison") or {}
    if comparison:
        print(f"  compare: {text(comparison.get('status'))} / {text(comparison.get('reason'))}")
    coverage = suite.get("coverage") or {}
    if coverage:
        print(f"  coverage: {text(coverage.get('status'))} / {text(coverage.get('note'))}")
    excerpt = suite.get("logExcerpt") or []
    if excerpt:
        print(f"  excerpt: {excerpt[0]}")
print("")
PY
}

cmd_benchmark() {
    local subcommand="status"
    local target=""
    local format="text"
    local suites_csv="all"
    local samples="2"
    local write_baseline="0"
    local root=""
    local target_mode="fixture"
    local payload=""
    local command_status="0"

    if [[ $# -gt 0 ]]; then
        case "$1" in
            status|run)
                subcommand="$1"
                shift
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                target_mode="project"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            --suite|--suites)
                shift
                suites_csv="${1:-all}"
                ;;
            --suite=*|--suites=*)
                suites_csv="${1#*=}"
                ;;
            --samples)
                shift
                samples="${1:-2}"
                ;;
            --samples=*)
                samples="${1#*=}"
                ;;
            --write-baseline)
                write_baseline="1"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "benchmark accepts at most one project path."
                    return 1
                fi
                target="$1"
                target_mode="project"
                ;;
        esac
        shift
    done

    if [[ ! "${samples}" =~ ^[0-9]+$ ]] || [[ "${samples}" -lt 1 ]]; then
        yen_error "Invalid benchmark sample count '${samples}'. Use a positive integer."
        return 1
    fi

    ensure_state_dirs
    root=$(benchmark_report_root "${target}")

    set +e
    case "${subcommand}" in
        status)
            payload=$(benchmark_status_json_for_root "${root}")
            command_status=$?
            ;;
        run)
            payload=$(benchmark_run_json_for_root "${root}" "${target_mode}" "${suites_csv}" "${samples}" "${write_baseline}")
            command_status=$?
            ;;
        *)
            set -e
            yen_error "Unknown benchmark command: ${subcommand}"
            return 1
            ;;
    esac
    set -e

    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            benchmark_text_from_payload "${payload}"
            ;;
        *)
            yen_error "Unknown benchmark format: ${format} (expected text|json)"
            return 1
            ;;
    esac

    return "${command_status}"
}
