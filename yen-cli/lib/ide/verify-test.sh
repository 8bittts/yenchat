# shellcheck shell=bash
# Source-time pure verify/test helpers and command handlers for yen ide.

test_runner_clean_field() {
    printf "%s" "$1" | tr '\t\r\n' '   '
}

test_runner_relpath() {
    local root="$1"
    local path="$2"
    if [[ -z "${path}" ]]; then
        printf "\n"
        return 0
    fi
    case "${path}" in
        "${root}")
            printf ".\n"
            ;;
        "${root}"/*)
            printf "%s\n" "${path#${root}/}"
            ;;
        *)
            printf "%s\n" "${path}"
            ;;
    esac
}

append_test_runner_record() {
    local out_file="$1"
    local runner_id="$2"
    local family="$3"
    local label="$4"
    local source_path="$5"
    local workdir="$6"
    local command_text="$7"
    local runnable="$8"
    local quick_eligible="$9"
    local reason="${10}"

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(test_runner_clean_field "${runner_id}")" \
        "$(test_runner_clean_field "${family}")" \
        "$(test_runner_clean_field "${label}")" \
        "$(test_runner_clean_field "${source_path}")" \
        "$(test_runner_clean_field "${workdir}")" \
        "$(test_runner_clean_field "${command_text}")" \
        "$(test_runner_clean_field "${runnable}")" \
        "$(test_runner_clean_field "${quick_eligible}")" \
        "$(test_runner_clean_field "${reason}")" >> "${out_file}"
}

verify_test_runner_rows_for_root() {
    local root="$1"
    local tmp=""

    tmp=$(mktemp "${TMPDIR:-/tmp}/yen-ide-test-runners.XXXXXX" 2>/dev/null || mktemp)

    if [[ -f "${root}/package.json" ]]; then
        local node_pm="none"
        local node_test_cmd=""
        local node_reason=""
        local node_runnable="no"

        node_pm=$(detect_node_package_manager "${root}")
        case "${node_pm}" in
            bun)
                node_test_cmd="bun test"
                ;;
            pnpm)
                node_test_cmd="pnpm test"
                ;;
            yarn)
                node_test_cmd="yarn test"
                ;;
            npm)
                node_test_cmd="npm test --silent"
                ;;
        esac

        if has_package_script "${root}" "test"; then
            if [[ "${node_pm}" == "none" ]]; then
                node_reason="missing-node-package-manager"
            else
                node_runnable="yes"
            fi
        else
            node_reason="missing-test-script"
        fi

        append_test_runner_record "${tmp}" "node-test" "node" "package.json test script" "package.json" "${root}" "${node_test_cmd}" "${node_runnable}" "yes" "${node_reason}"
    fi

    local go_dirs=""
    local go_dir=""
    go_dirs=$(detect_go_module_dirs "${root}")
    if [[ -n "${go_dirs}" ]]; then
        while IFS= read -r go_dir; do
            local source_path="go.mod"
            [[ -z "${go_dir}" ]] && continue
            if [[ "${go_dir}" != "${root}" ]]; then
                source_path="$(test_runner_relpath "${root}" "${go_dir}")/go.mod"
            fi
            append_test_runner_record "${tmp}" "go-test-$(basename "${go_dir}")" "go" "go module tests" "${source_path}" "${go_dir}" "go test ./..." "yes" "no" ""
        done << EOF
${go_dirs}
EOF
    fi

    if [[ -f "${root}/Cargo.toml" ]]; then
        local cargo_runnable="no"
        local cargo_reason="missing-cargo"
        if command -v cargo >/dev/null 2>&1; then
            cargo_runnable="yes"
            cargo_reason=""
        fi
        append_test_runner_record "${tmp}" "cargo-test" "rust" "Cargo test targets" "Cargo.toml" "${root}" "cargo test --all-targets" "${cargo_runnable}" "no" "${cargo_reason}"
    fi

    if [[ -f "${root}/pyproject.toml" || -f "${root}/requirements.txt" || -f "${root}/setup.py" ]]; then
        local py_source="pyproject.toml"
        local py_cmd=""
        local py_runnable="no"
        local py_reason="missing-python"
        if [[ ! -f "${root}/${py_source}" ]]; then
            if [[ -f "${root}/requirements.txt" ]]; then
                py_source="requirements.txt"
            else
                py_source="setup.py"
            fi
        fi
        if command -v python3 >/dev/null 2>&1; then
            py_cmd="python3 -m pytest -q"
            py_runnable="yes"
            py_reason=""
        elif command -v python >/dev/null 2>&1; then
            py_cmd="python -m pytest -q"
            py_runnable="yes"
            py_reason=""
        fi
        append_test_runner_record "${tmp}" "pytest" "python" "Pytest suite" "${py_source}" "${root}" "${py_cmd}" "${py_runnable}" "no" "${py_reason}"
    fi

    if [[ -f "${root}/Package.swift" ]]; then
        local swift_runnable="no"
        local swift_reason="missing-swift"
        if command -v swift >/dev/null 2>&1; then
            swift_runnable="yes"
            swift_reason=""
        fi
        append_test_runner_record "${tmp}" "swift-test" "swift" "Swift package tests" "Package.swift" "${root}" "swift test" "${swift_runnable}" "no" "${swift_reason}"
    fi

    if [[ -f "${root}/build.zig" ]]; then
        local zig_runnable="no"
        local zig_reason="missing-zig"
        if command -v zig >/dev/null 2>&1; then
            zig_runnable="yes"
            zig_reason=""
        fi
        append_test_runner_record "${tmp}" "zig-test" "zig" "Zig build test" "build.zig" "${root}" "zig build test" "${zig_runnable}" "no" "${zig_reason}"
    fi

    if [[ -f "${root}/Makefile" ]]; then
        local make_runnable="no"
        local make_reason="missing-test-target"
        if grep -Eq '^[[:space:]]*test:' "${root}/Makefile"; then
            make_runnable="yes"
            make_reason=""
        fi
        append_test_runner_record "${tmp}" "make-test" "make" "Makefile test target" "Makefile" "${root}" "make test" "${make_runnable}" "no" "${make_reason}"
    fi

    cat "${tmp}"
    rm -f "${tmp}"
}

update_verify_flaky_ledger() {
    local root="$1"
    local step_name="$2"
    local status="$3"
    local step_cmd="$4"
    local key_seed="$(project_hash_seed_for_root "${root}")|${step_name}|${step_cmd}"
    local key
    key=$(project_hash "${key_seed}")

    ensure_state_dirs
    local existing=""
    existing=$(awk -F'\t' -v key="${key}" '$1 == key { line = $0 } END { print line }' "${IDE_VERIFY_FLAKY_FILE}" 2>/dev/null || true)

    local previous_status=""
    local flip_count=0
    local pass_count=0
    local fail_count=0
    if [[ -n "${existing}" ]]; then
        IFS=$'\t' read -r _ previous_status flip_count pass_count fail_count _ _ << EOF
${existing}
EOF
    fi

    if [[ "${status}" -eq 0 ]]; then
        pass_count=$((pass_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
    if [[ -n "${previous_status}" && "${previous_status}" != "${status}" ]]; then
        flip_count=$((flip_count + 1))
    fi

    local flaky_state="stable"
    if [[ "${flip_count}" -gt 0 && "${pass_count}" -gt 0 && "${fail_count}" -gt 0 ]]; then
        flaky_state="flaky"
    fi

    local tmp
    tmp=$(mktemp)
    if [[ -f "${IDE_VERIFY_FLAKY_FILE}" ]]; then
        awk -F'\t' -v key="${key}" '$1 != key { print $0 }' "${IDE_VERIFY_FLAKY_FILE}" > "${tmp}" || true
    fi
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "${key}" "${status}" "${flip_count}" "${pass_count}" "${fail_count}" "$(iso_now)" "${step_name}" >> "${tmp}"
    mv "${tmp}" "${IDE_VERIFY_FLAKY_FILE}"

    printf "%s|%s|%s|%s\n" "${flaky_state}" "${flip_count}" "${pass_count}" "${fail_count}"
}

run_verify_step() {
    local project_root="$1"
    local step_root="$2"
    local report_summary="$3"
    local report_details="$4"
    local report_semantic="$5"
    local step_name="$6"
    local step_cmd="$7"
    local allow_fail="$8"
    local step_category="${9:-general}"
    local start_ms
    local end_ms
    local duration_ms
    local status
    local flaky_info
    local flaky_state
    local flip_count
    local pass_count
    local fail_count

    start_ms=$(now_ms)
    set +e
    local output
    # Default to a login shell so user toolchains (mise/nvm/asdf activated via login
    # profiles) resolve during `yen ide verify`. Tests set YEN_IDE_VERIFY_LOGIN_SHELL=0
    # to use a non-login shell so an injected PATH is honored — a login shell re-sources
    # /etc/profile (path_helper on macOS) and reorders PATH, which would bypass test fakes.
    if [ "${YEN_IDE_VERIFY_LOGIN_SHELL:-1}" = "0" ]; then
        output=$(cd "${step_root}" && bash -c "${step_cmd}" 2>&1)
    else
        output=$(cd "${step_root}" && bash -lc "${step_cmd}" 2>&1)
    fi
    status=$?
    set -e
    end_ms=$(now_ms)
    duration_ms=$((end_ms - start_ms))

    flaky_info=$(update_verify_flaky_ledger "${project_root}" "${step_name}" "${status}" "${step_cmd}")
    flaky_state="${flaky_info%%|*}"
    local flaky_tail="${flaky_info#*|}"
    flip_count="${flaky_tail%%|*}"
    flaky_tail="${flaky_tail#*|}"
    pass_count="${flaky_tail%%|*}"
    fail_count="${flaky_tail#*|}"

    local result="pass"
    if [[ "${status}" -ne 0 ]]; then
        if [[ "${allow_fail}" == "1" ]]; then
            result="warn"
        else
            result="fail"
        fi
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(iso_now)" "${step_name}" "${status}" "${duration_ms}" "${flaky_state}" "${flip_count}" "${step_cmd}" "${result}" "${step_category}" >> "${report_summary}"
    append_semantic_reference_report "${report_semantic}" "${project_root}" "${step_root}" "$(printf "%s\t%s\t%s" "$(iso_now)" "${step_name}" "${status}")" "${output}"
    {
        echo "=== ${step_name} ==="
        echo "category: ${step_category}"
        echo "result: ${result}"
        echo "command: ${step_cmd}"
        echo "status: ${status}"
        echo "duration_ms: ${duration_ms}"
        echo "flaky_state: ${flaky_state} (flips=${flip_count} pass=${pass_count} fail=${fail_count})"
        echo "--- output ---"
        printf "%s\n" "${output}"
        echo ""
    } >> "${report_details}"

    printf "%s|%s|%s\n" "${result}" "${step_name}" "${status}"
}

record_verify_skipped_step() {
    local report_summary="$1"
    local report_details="$2"
    local step_name="$3"
    local step_code="$4"
    local step_note="$5"
    local step_category="${6:-general}"

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(iso_now)" "${step_name}" "${step_code}" "0" "warn" "0" "${step_note}" "warn" "${step_category}" >> "${report_summary}"
    {
        echo "=== ${step_name} ==="
        echo "category: ${step_category}"
        echo "result: warn"
        echo "status: skipped (${step_note})"
        echo ""
    } >> "${report_details}"
}

osv_lockfile_arg_for_path() {
    local path="$1"
    local scanner_path="${path}"
    if [[ "${scanner_path}" == *:* ]]; then
        scanner_path=":${scanner_path}"
    fi
    printf -- "--lockfile=%s" "$(shell_quote_single "${scanner_path}")"
}

osv_scan_targets_for_root() {
    local root="$1"
    find "${root}" \
        \( -type d \( -name .git -o -name .hg -o -name .svn -o -name .next -o -name .turbo -o -name .venv -o -name .yarn -o -name .tmp -o -name .temp -o -name .scratch -o -name DerivedData -o -name __pycache__ -o -name build -o -name dist -o -name ghostty -o -name node_modules -o -name scratch -o -name 'scratch-*' -o -name temp -o -name 'temp-*' -o -name tmp -o -name 'tmp-*' -o -name vendor -o -name venv -o -name zig-out \) -prune \) -o \
        \( -type f \( \
            -name bun.lock -o \
            -name package-lock.json -o \
            -name pnpm-lock.yaml -o \
            -name yarn.lock -o \
            -name go.mod -o \
            -name Cargo.lock -o \
            -name Pipfile.lock -o \
            -name poetry.lock -o \
            -name pdm.lock -o \
            -name pylock.toml -o \
            -name uv.lock -o \
            -name composer.lock -o \
            -name Gemfile.lock -o \
            -name gems.locked -o \
            -name mix.lock -o \
            -name pubspec.lock -o \
            -name conan.lock -o \
            -name renv.lock -o \
            -name deps.json -o \
            -name packages.config -o \
            -name packages.lock.json -o \
            -name gradle.lockfile -o \
            -name buildscript-gradle.lockfile -o \
            -path '*/gradle/verification-metadata.xml' \
        \) -print \) 2>/dev/null | LC_ALL=C sort -u
}

osv_scan_command_for_root() {
    local root="$1"
    local targets=""
    local command="osv-scanner --format json"
    local path=""

    targets=$(osv_scan_targets_for_root "${root}")
    [[ -n "${targets}" ]] || return 1

    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        command="${command} $(osv_lockfile_arg_for_path "${path}")"
    done << EOF
${targets}
EOF

    printf "%s\n" "${command}"
}

verify_status_json_for_root() {
    local root="$1"
    local verify_snapshot=""
    local watch_snapshot=""
    verify_snapshot=$(verify_snapshot_for_root "${root}")
    watch_snapshot=$(watch_state_latest_snapshot_for_root "${root}")
    verify_status_render "${root}" "${verify_snapshot}" "json" "${watch_snapshot}" 2>/dev/null || true
}

verify_security_snapshot_for_root() {
    local root="$1"
    local payload=""
    payload=$(verify_status_json_for_root "${root}")
    [[ -n "${payload}" ]] || return 0

    VERIFY_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
import re


def clean(value):
    return re.sub(r"[\t\r\n]+", " ", str(value or "")).strip()


payload = os.environ.get("VERIFY_STATUS_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    raise SystemExit(0)

latest = data.get("latest") or {}
readiness = data.get("readiness") or {}
security = data.get("security") or {}

rows = {
    "verify_readiness_status": clean(readiness.get("status", "")),
    "verify_readiness_reason": clean(readiness.get("reason", "")),
    "verify_merge_ready": "yes" if readiness.get("mergeReady") else "no",
    "verify_security_status": clean(security.get("status", "")),
    "verify_security_reason": clean(security.get("reason", "")),
    "verify_security_step_count": str(int(security.get("stepCount") or 0)),
    "verify_security_warning_steps": str(int(security.get("warningSteps") or 0)),
    "verify_security_failing_steps": str(int(security.get("failingSteps") or 0)),
    "verify_security_passing_steps": str(int(security.get("passingSteps") or 0)),
    "verify_details_report": clean(latest.get("detailsReport", "")),
}

for key, value in rows.items():
    print(f"{key}={value}")
PY
}

render_verify_status_markdown_section_for_root() {
    local root="$1"
    local payload=""
    payload=$(verify_status_json_for_root "${root}")
    [[ -n "${payload}" ]] || return 0

    VERIFY_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def text(value, fallback):
    value = str(value or "").strip()
    return value if value else fallback


payload = os.environ.get("VERIFY_STATUS_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    raise SystemExit(0)

latest = data.get("latest") or {}
readiness = data.get("readiness") or {}
security = data.get("security") or {}
steps = security.get("steps") or []

print("## Latest Verify Readiness + Security Snapshot")
print("")
print(f"- Latest status: {text(latest.get('status'), 'never-run')}")
print(f"- Readiness: {text(readiness.get('status'), 'unavailable')}")
print(f"- Merge ready: {'yes' if readiness.get('mergeReady') else 'no'}")
print(f"- Readiness note: {text(readiness.get('reason'), 'Run yen ide verify --quick to establish a local verify baseline.')}")
print(f"- Security: {text(security.get('status'), 'unavailable')}")
print(f"- Security note: {text(security.get('reason'), 'No security steps were recorded in the latest local verify report.')}")
print(
    "- Security counts: "
    f"{int(security.get('stepCount') or 0)} total / "
    f"{int(security.get('warningSteps') or 0)} warning / "
    f"{int(security.get('failingSteps') or 0)} blocking"
)
print(f"- Last verify run: {text(latest.get('lastRunAt'), 'never')}")
print(f"- Summary report: {text(latest.get('summaryReport'), 'missing')}")
print(f"- Details report: {text(latest.get('detailsReport'), 'missing')}")
print(f"- Semantic report: {text(latest.get('semanticReport'), 'missing')}")

if steps:
    for step in steps[:12]:
        summary = text(step.get("summary"), "")
        line = (
            f"- Security step: {text(step.get('id'), 'unknown')} | "
            f"result={text(step.get('result'), 'unknown')} | "
            f"exit={int(step.get('exitCode') or 0)}"
        )
        if summary:
            line += f" | {summary}"
        print(line)
else:
    print("- Security step: none recorded")
PY
}

verify_status_render() {
    local root="$1"
    local verify_snapshot="$2"
    local format="${3:-text}"
    local watch_snapshot="${4:-}"

    VERIFY_STATUS_ROOT="${root}" \
    VERIFY_STATUS_SNAPSHOT="${verify_snapshot}" \
    VERIFY_WATCH_SNAPSHOT="${watch_snapshot}" \
    VERIFY_STATUS_DEBUG_HANDOFFS="${VERIFY_STATUS_DEBUG_HANDOFFS:-}" \
    VERIFY_STATUS_FORMAT="${format}" \
    IDE_WORKSPACE_TRANSPORT="${IDE_WORKSPACE_TRANSPORT}" \
    IDE_WORKSPACE_EXECUTION_LOCATION="${IDE_WORKSPACE_EXECUTION_LOCATION}" \
    IDE_WORKSPACE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY}" \
    IDE_WORKSPACE_PORT="${IDE_WORKSPACE_PORT}" \
    IDE_WORKSPACE_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH}" \
    IDE_WORKSPACE_LABEL="${IDE_WORKSPACE_LABEL}" \
    IDE_WORKSPACE_IDENTITY="${IDE_WORKSPACE_IDENTITY}" \
    python3 - <<'PY'
import json
import os


def parse_env_lines(text: str) -> dict:
    data = {}
    for raw in (text or "").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        data[key] = value
    return data


def parse_debug_handoffs(text: str) -> dict:
    rows = {}
    for raw in (text or "").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        while len(parts) < 10:
            parts.append("")
        group, target, command, tool, tool_title, line_applied, trusted, trust_required, trust_command, notes = parts[:10]
        rows[group] = {
            "target": target,
            "command": command,
            "tool": tool,
            "toolTitle": tool_title,
            "lineApplied": line_applied == "yes",
            "trusted": trusted == "yes",
            "trustRequired": trust_required == "yes",
            "trustCommand": trust_command,
            "notes": [note for note in notes.split("|") if note],
        }
    return rows


def infer_category(step_name: str, command: str, explicit: str) -> str:
    if explicit:
        return explicit
    name = (step_name or "").strip()
    command = (command or "").strip()
    if name in {"gitleaks", "node-audit", "osv-scanner"}:
        return "security"
    if "audit" in name or "gitleaks" in name or "osv" in name:
        return "security"
    if name in {"node-toolchain", "tsc-noemit", "lint", "lint-check"}:
        return "quality"
    if name.endswith("-build") or name == "node-build":
        return "build"
    if (
        name.endswith("-test")
        or name in {"pytest", "swift-test", "zig-test", "make-test"}
        or "test" in command
    ):
        return "test"
    return "general"


def infer_result(step_name: str, command: str, exit_code: int, explicit: str) -> str:
    if explicit in {"pass", "warn", "fail"}:
        return explicit
    if exit_code == 0:
        return "pass"
    lowered_name = (step_name or "").strip()
    lowered_cmd = (command or "").strip().lower()
    if exit_code == 127:
        return "warn"
    if lowered_name in {"node-audit"} or "audit" in lowered_name:
        return "warn"
    if "missing-" in lowered_cmd or "missing " in lowered_cmd or "tool missing" in lowered_cmd:
        return "warn"
    return "fail"


def load_detail_sections(path: str) -> dict:
    if not path or not os.path.isfile(path):
        return {}
    sections = {}
    current = None
    reading_output = False
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("=== ") and line.endswith(" ==="):
                if current:
                    while current["outputLines"] and current["outputLines"][-1] == "":
                        current["outputLines"].pop()
                    current["outputExcerpt"] = [entry for entry in current["outputLines"] if entry.strip()][:3]
                    sections[current["stepName"]] = current
                current = {
                    "stepName": line[4:-4],
                    "category": "",
                    "result": "",
                    "command": "",
                    "status": "",
                    "durationMs": 0,
                    "flakySummary": "",
                    "outputLines": [],
                    "outputExcerpt": [],
                }
                reading_output = False
                continue
            if current is None:
                continue
            if line == "--- output ---":
                reading_output = True
                continue
            if reading_output:
                current["outputLines"].append(line)
                continue
            if line.startswith("category: "):
                current["category"] = line[len("category: ") :]
            elif line.startswith("result: "):
                current["result"] = line[len("result: ") :]
            elif line.startswith("command: "):
                current["command"] = line[len("command: ") :]
            elif line.startswith("status: "):
                current["status"] = line[len("status: ") :]
            elif line.startswith("duration_ms: "):
                try:
                    current["durationMs"] = int(line[len("duration_ms: ") :] or "0")
                except ValueError:
                    current["durationMs"] = 0
            elif line.startswith("flaky_state: "):
                current["flakySummary"] = line[len("flaky_state: ") :]
    if current:
        while current["outputLines"] and current["outputLines"][-1] == "":
            current["outputLines"].pop()
        current["outputExcerpt"] = [entry for entry in current["outputLines"] if entry.strip()][:3]
        sections[current["stepName"]] = current
    return sections


def parse_osv_summary(output_lines: list):
    text = "\n".join(output_lines or []).strip()
    if not text:
        return None
    try:
        payload = json.loads(text)
    except Exception:
        return None

    results = payload.get("results") or []
    source_count = 0
    package_count = 0
    vulnerability_count = 0
    seen_groups = set()
    for result in results:
        source_count += 1
        for package_entry in result.get("packages") or []:
            package_count += 1
            groups = package_entry.get("groups") or []
            if groups:
                for group in groups:
                    ids = tuple(sorted(group.get("ids") or []))
                    if ids and ids not in seen_groups:
                        seen_groups.add(ids)
                        vulnerability_count += 1
                continue
            vulns = package_entry.get("vulnerabilities") or []
            if vulns:
                vulnerability_count += len(vulns)

    return {
        "kind": "osv",
        "sourceCount": source_count,
        "packageCount": package_count,
        "vulnerabilityCount": vulnerability_count,
    }


def load_verify_steps(summary_path: str, details_path: str) -> list:
    sections = load_detail_sections(details_path)
    rows = []
    if not summary_path or not os.path.isfile(summary_path):
        return rows
    with open(summary_path, "r", encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            while len(parts) < 9:
                parts.append("")
            time, step_name, exit_code, duration_ms, flaky_state, flip_count, command, result, category = parts[:9]
            if not step_name:
                continue
            try:
                exit_code_int = int(exit_code or "0")
            except ValueError:
                exit_code_int = 0
            try:
                duration_int = int(duration_ms or "0")
            except ValueError:
                duration_int = 0
            try:
                flip_int = int(flip_count or "0")
            except ValueError:
                flip_int = 0
            detail = sections.get(step_name, {})
            resolved_category = infer_category(step_name, command or detail.get("command", ""), category or detail.get("category", ""))
            resolved_result = infer_result(step_name, command or detail.get("command", ""), exit_code_int, result or detail.get("result", ""))
            analysis = None
            summary_text = (detail.get("outputExcerpt") or [""])[0]
            if step_name == "osv-scanner":
                analysis = parse_osv_summary(detail.get("outputLines", []))
                if analysis:
                    summary_text = (
                        f"{analysis['vulnerabilityCount']} vulnerability group(s) across "
                        f"{analysis['packageCount']} package(s) from {analysis['sourceCount']} source(s)"
                    )
            rows.append(
                {
                    "time": time,
                    "id": step_name,
                    "exitCode": exit_code_int,
                    "durationMs": duration_int,
                    "flakyState": flaky_state,
                    "flipCount": flip_int,
                    "command": command or detail.get("command", ""),
                    "result": resolved_result,
                    "category": resolved_category,
                    "analysis": analysis,
                    "statusLine": detail.get("status", ""),
                    "outputExcerpt": detail.get("outputExcerpt", []),
                    "summary": summary_text,
                }
            )
    return rows


def summarize_steps(steps: list) -> dict:
    return {
        "stepCount": len(steps),
        "passingSteps": sum(1 for step in steps if step.get("result") == "pass"),
        "warningSteps": sum(1 for step in steps if step.get("result") == "warn"),
        "failingSteps": sum(1 for step in steps if step.get("result") == "fail"),
    }


snapshot = parse_env_lines(os.environ.get("VERIFY_STATUS_SNAPSHOT", ""))
watch_snapshot = parse_env_lines(os.environ.get("VERIFY_WATCH_SNAPSHOT", ""))
steps = load_verify_steps(snapshot.get("verify_summary", ""), snapshot.get("verify_details", ""))
debug_handoffs = parse_debug_handoffs(os.environ.get("VERIFY_STATUS_DEBUG_HANDOFFS", ""))
for step in steps:
    if step.get("result") == "fail":
        step["debugHandoff"] = debug_handoffs.get(step.get("id") or "")
    else:
        step["debugHandoff"] = None
security_steps = [step for step in steps if step.get("category") == "security"]
summary = summarize_steps(steps)
summary["debuggableSteps"] = sum(1 for step in steps if step.get("debugHandoff"))
security_summary = summarize_steps(security_steps)

latest_status = snapshot.get("verify_status", "never-run")
readiness_status = "unavailable"
readiness_reason = "Run yen ide verify --quick to establish a local verify baseline."
merge_ready = False
if latest_status == "passing":
    readiness_status = "ready"
    readiness_reason = "Latest local verify run passed."
    merge_ready = True
elif latest_status == "warnings":
    readiness_status = "warning"
    readiness_reason = "Latest local verify run has warnings."
elif latest_status in {"failing", "report-missing"}:
    readiness_status = "blocked"
    readiness_reason = (
        "Latest local verify report is missing."
        if latest_status == "report-missing"
        else "Latest local verify run has failures."
    )

security_status = "unavailable"
security_reason = "No security steps were recorded in the latest local verify report."
if security_steps:
    if security_summary["failingSteps"] > 0:
        security_status = "blocked"
        security_reason = "Latest local security checks contain blocking failures."
    elif security_summary["warningSteps"] > 0:
        security_status = "warning"
        security_reason = "Latest local security checks contain warnings or missing tools."
    else:
        security_status = "ready"
        security_reason = "Latest local security checks passed."

workspace = {
    "executionLocation": os.environ.get("IDE_WORKSPACE_EXECUTION_LOCATION", "local"),
    "transport": os.environ.get("IDE_WORKSPACE_TRANSPORT", "local"),
    "identity": os.environ.get("IDE_WORKSPACE_IDENTITY", ""),
    "requestedPath": os.environ.get("IDE_WORKSPACE_REQUESTED_PATH", ""),
    "authority": os.environ.get("IDE_WORKSPACE_AUTHORITY", ""),
    "port": int(os.environ.get("IDE_WORKSPACE_PORT") or "0") if os.environ.get("IDE_WORKSPACE_PORT") else None,
    "label": os.environ.get("IDE_WORKSPACE_LABEL", ""),
}
evidence = {
    "stateSource": "local-ide-state",
    "timelineSource": "local-ide-state",
    "note": (
        "Remote verify status reads local verify reports and timeline rows keyed by workspace identity."
        if workspace["executionLocation"] == "remote"
        else "Verify status reads local verify reports and timeline rows for the current workspace."
    ),
}
watch_reason = "No local build watch has been recorded yet."
watch_payload = {
    "available": False,
    "active": False,
    "kind": "",
    "label": "",
    "branch": "",
    "state": "unavailable",
    "iteration": 0,
    "intervalSeconds": "",
    "maxRuns": "",
    "scope": "",
    "startedAt": "",
    "updatedAt": "",
    "stopReason": "",
    "lastOutcome": "",
    "lastExitCode": 0,
    "lastFailures": 0,
    "lastWarnings": 0,
    "lastExecuted": 0,
    "summaryReport": "",
    "detailsReport": "",
    "semanticReport": "",
    "reason": watch_reason,
}
if watch_snapshot:
    watch_payload.update(
        {
            "available": True,
            "active": (watch_snapshot.get("active") or "").lower() == "yes",
            "kind": watch_snapshot.get("kind") or "",
            "label": watch_snapshot.get("label") or "",
            "branch": watch_snapshot.get("branch") or "",
            "state": watch_snapshot.get("state") or "unavailable",
            "iteration": int(watch_snapshot.get("iteration") or "0"),
            "intervalSeconds": watch_snapshot.get("interval_seconds") or "",
            "maxRuns": watch_snapshot.get("max_runs") or "",
            "scope": watch_snapshot.get("scope") or "",
            "startedAt": watch_snapshot.get("started_at") or "",
            "updatedAt": watch_snapshot.get("updated_at") or "",
            "stopReason": watch_snapshot.get("stop_reason") or "",
            "lastOutcome": watch_snapshot.get("last_outcome") or "",
            "lastExitCode": int(watch_snapshot.get("last_exit_code") or "0"),
            "lastFailures": int(watch_snapshot.get("last_failures") or "0"),
            "lastWarnings": int(watch_snapshot.get("last_warns") or "0"),
            "lastExecuted": int(watch_snapshot.get("last_executed") or "0"),
            "summaryReport": watch_snapshot.get("summary") or "",
            "detailsReport": watch_snapshot.get("details") or "",
            "semanticReport": watch_snapshot.get("semantic") or "",
        }
    )
    if watch_payload["active"]:
        watch_payload["reason"] = "A local build/watch session is currently active."
    elif watch_payload["stopReason"]:
        watch_payload["reason"] = f"Last local build/watch session stopped because {watch_payload['stopReason']}."
    elif watch_payload["state"] != "unavailable":
        watch_payload["reason"] = f"Last local build/watch session ended in state {watch_payload['state']}."
elif workspace["executionLocation"] == "remote":
    watch_payload["reason"] = "Remote build/watch progress is not shipped yet; only local watch state is recorded."

payload = {
    "schemaVersion": 1,
    "root": os.environ.get("VERIFY_STATUS_ROOT", ""),
    "workspace": workspace,
    "evidence": evidence,
    "latest": {
        "status": latest_status,
        "lastRunAt": snapshot.get("verify_last_run_at", ""),
        "summaryReport": snapshot.get("verify_summary", ""),
        "detailsReport": snapshot.get("verify_details", ""),
        "semanticReport": snapshot.get("verify_semantic", ""),
        "failures": int(snapshot.get("verify_failures") or "0"),
        "warnings": int(snapshot.get("verify_warns") or "0"),
        "executedSteps": int(snapshot.get("verify_executed") or "0"),
    },
    "readiness": {
        "status": readiness_status,
        "mergeReady": merge_ready,
        "reason": readiness_reason,
    },
    "summary": summary,
    "security": {
        "status": security_status,
        "reason": security_reason,
        **security_summary,
        "steps": security_steps,
    },
    "watch": watch_payload,
    "steps": steps,
}

format_name = os.environ.get("VERIFY_STATUS_FORMAT", "text")
if format_name == "json":
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0)

print("")
print("IDE Verify Status")
print(f"Project root:       {payload.get('root', '')}")
print(f"Execution location: {workspace.get('executionLocation', 'local')}")
if workspace.get("identity"):
    print(f"Workspace identity: {workspace.get('identity')}")
if workspace.get("requestedPath"):
    print(f"Requested path:     {workspace.get('requestedPath')}")
print(f"State evidence:     {evidence.get('stateSource', 'local-ide-state')}")
print(f"Timeline evidence:  {evidence.get('timelineSource', 'local-ide-state')}")
print(f"Note:               {evidence.get('note', '')}")
print(f"Build watch:        {payload['watch'].get('state', 'unavailable')}")
print(f"Build watch note:   {payload['watch'].get('reason', '')}")
if payload["watch"].get("available"):
    print(
        "Build watch meta:   "
        f"kind={payload['watch'].get('kind', '')} "
        f"active={'yes' if payload['watch'].get('active') else 'no'} "
        f"iteration={payload['watch'].get('iteration', 0)} "
        f"branch={payload['watch'].get('branch', '') or 'unknown'}"
    )
print(f"Latest status:      {payload['latest'].get('status', 'never-run')}")
print(f"Readiness:          {payload['readiness'].get('status', 'unavailable')}")
print(f"Merge ready:        {'yes' if payload['readiness'].get('mergeReady') else 'no'}")
print(f"Readiness note:     {payload['readiness'].get('reason', '')}")
print(f"Last verify run:    {payload['latest'].get('lastRunAt', '') or 'never'}")
print(f"Summary report:     {payload['latest'].get('summaryReport', '') or 'missing'}")
print(f"Details report:     {payload['latest'].get('detailsReport', '') or 'missing'}")
print(f"Semantic report:    {payload['latest'].get('semanticReport', '') or 'missing'}")
print(
    "Executed/warn/fail:"
    f" {payload['latest'].get('executedSteps', 0)} /"
    f" {payload['latest'].get('warnings', 0)} /"
    f" {payload['latest'].get('failures', 0)}"
)
print(f"Security:           {payload['security'].get('status', 'unavailable')}")
print(f"Security note:      {payload['security'].get('reason', '')}")
print("")

if not steps:
    print("No local verify steps have been recorded yet.")
    print("")
    raise SystemExit(0)

print(f"{'STEP':<18} {'RESULT':<7} {'EXIT':<5} {'CATEGORY':<9} COMMAND")
for step in steps:
    print(
        f"{step['id']:<18} {step['result']:<7} {step['exitCode']:<5} "
        f"{step['category']:<9} {step.get('command', '')}"
    )

debuggable_steps = [step for step in steps if step.get("debugHandoff")]
if debuggable_steps:
    print("")
    print("Debug Handoffs:")
    for step in debuggable_steps[:6]:
        handoff = step.get("debugHandoff") or {}
        print(f"  {step['id']}: {handoff.get('command', '')}")
        if handoff.get("trustRequired"):
            print(f"    trust:  {handoff.get('trustCommand', '')}")
        for note in (handoff.get("notes") or [])[:2]:
            print(f"    note:   {note}")

if security_steps:
    print("")
    print("Security Steps:")
    for step in security_steps:
        print(f"  {step['id']} ({step['result']}, exit={step['exitCode']})")
        if step.get("summary"):
            print(f"    summary: {step['summary']}")
        for excerpt in step.get("outputExcerpt", [])[:2]:
            if excerpt != step.get("summary"):
                print(f"    output:  {excerpt}")
print("")
PY
}

cmd_verify_status() {
    local target=""
    local format="text"
    local root=""
    local verify_snapshot=""
    local verify_debug_handoffs=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "verify status accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    if ! workspace_summary_resolve_target "${target}"; then
        return 1
    fi
    root="${IDE_WORKSPACE_SUMMARY_ROOT}"
    verify_snapshot=$(verify_snapshot_for_root "${root}")
    if [[ "${IDE_WORKSPACE_EXECUTION_LOCATION:-local}" != "remote" ]]; then
        verify_debug_handoffs=$(debug_handoff_rows_from_semantic_report "${root}" "$(doctor_snapshot_value "${verify_snapshot}" "verify_semantic")")
    fi
    local watch_snapshot=""
    watch_snapshot=$(watch_state_latest_snapshot_for_root "${root}")

    case "${format}" in
        text|json)
            VERIFY_STATUS_DEBUG_HANDOFFS="${verify_debug_handoffs}" verify_status_render "${root}" "${verify_snapshot}" "${format}" "${watch_snapshot}"
            ;;
        *)
            yen_error "Unknown verify status format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_test_status() {
    local target=""
    local format="text"
    local root=""
    local verify_snapshot=""
    local test_snapshot=""
    local latest_snapshot=""
    local debug_handoffs=""
    local runners=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "test status accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    verify_snapshot=$(verify_snapshot_for_root "${root}")
    test_snapshot=$(test_snapshot_for_root "${root}")
    latest_snapshot=$(latest_test_failure_source_snapshot_for_root "${root}")
    debug_handoffs=$(debug_handoff_rows_from_semantic_report "${root}" "$(doctor_snapshot_value "${latest_snapshot}" "latest_semantic")")
    runners=$(verify_test_runner_rows_for_root "${root}")

    case "${format}" in
        text|json)
            TEST_STATUS_ROOT="${root}" TEST_STATUS_VERIFY="${verify_snapshot}" TEST_STATUS_TEST="${test_snapshot}" TEST_STATUS_LATEST="${latest_snapshot}" TEST_STATUS_RUNNERS="${runners}" TEST_STATUS_DEBUG_HANDOFFS="${debug_handoffs}" TEST_STATUS_FORMAT="${format}" python3 - <<'PY'
import json
import os


def parse_env_lines(text: str) -> dict:
    data = {}
    for raw in (text or "").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        data[key] = value
    return data


def parse_runner_rows(text: str) -> list:
    rows = []
    for raw in (text or "").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        while len(parts) < 9:
            parts.append("")
        runner_id, family, label, source_path, workdir, command, runnable, quick_eligible, reason = parts[:9]
        rows.append(
            {
                "id": runner_id,
                "family": family,
                "label": label,
                "sourcePath": source_path,
                "workdir": workdir,
                "command": command,
                "runnable": runnable == "yes",
                "quickEligible": quick_eligible == "yes",
                "reason": reason,
            }
        )
    return rows


def parse_debug_handoffs(text: str) -> dict:
    rows = {}
    for raw in (text or "").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        while len(parts) < 10:
            parts.append("")
        group, target, command, tool, tool_title, line_applied, trusted, trust_required, trust_command, notes = parts[:10]
        rows[group] = {
            "target": target,
            "command": command,
            "tool": tool,
            "toolTitle": tool_title,
            "lineApplied": line_applied == "yes",
            "trusted": trusted == "yes",
            "trustRequired": trust_required == "yes",
            "trustCommand": trust_command,
            "notes": [note for note in notes.split("|") if note],
        }
    return rows


def load_summary_results(path: str) -> dict:
    results = {}
    if not path or not os.path.isfile(path):
        return results
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            while len(parts) < 7:
                parts.append("")
            time, step_name, exit_code, duration_ms, flaky_state, flip_count, command = parts[:7]
            if not step_name:
                continue
            try:
                exit_code_int = int(exit_code or "0")
            except ValueError:
                exit_code_int = 0
            try:
                duration_int = int(duration_ms or "0")
            except ValueError:
                duration_int = 0
            try:
                flip_int = int(flip_count or "0")
            except ValueError:
                flip_int = 0
            results[step_name] = {
                "time": time,
                "exitCode": exit_code_int,
                "durationMs": duration_int,
                "flakyState": flaky_state,
                "flipCount": flip_int,
                "command": command,
                "status": "passing" if exit_code_int == 0 else "failing",
            }
    return results


def load_detail_sections(path: str) -> dict:
    if not path or not os.path.isfile(path):
        return {}
    sections = {}
    current = None
    reading_output = False
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("=== ") and line.endswith(" ==="):
                if current:
                    while current["outputLines"] and current["outputLines"][-1] == "":
                        current["outputLines"].pop()
                    current["outputExcerpt"] = [entry for entry in current["outputLines"] if entry.strip()][:3]
                    sections[current["stepName"]] = current
                current = {
                    "stepName": line[4:-4],
                    "command": "",
                    "status": "",
                    "durationMs": 0,
                    "flakySummary": "",
                    "outputLines": [],
                    "outputExcerpt": [],
                }
                reading_output = False
                continue
            if current is None:
                continue
            if line == "--- output ---":
                reading_output = True
                continue
            if reading_output:
                current["outputLines"].append(line)
                continue
            if line.startswith("command: "):
                current["command"] = line[len("command: ") :]
            elif line.startswith("status: "):
                current["status"] = line[len("status: ") :]
            elif line.startswith("duration_ms: "):
                try:
                    current["durationMs"] = int(line[len("duration_ms: ") :] or "0")
                except ValueError:
                    current["durationMs"] = 0
            elif line.startswith("flaky_state: "):
                current["flakySummary"] = line[len("flaky_state: ") :]
    if current:
        while current["outputLines"] and current["outputLines"][-1] == "":
            current["outputLines"].pop()
        current["outputExcerpt"] = [entry for entry in current["outputLines"] if entry.strip()][:3]
        sections[current["stepName"]] = current
    return sections


def load_semantic_targets(path: str) -> dict:
    groups = {}
    if not path or not os.path.isfile(path):
        return groups
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            if len(parts) < 9:
                continue
            _, step_name, _, found, rel_path, line, col, absolute_path, location = parts[:9]
            group = groups.setdefault(step_name, {"seen": set(), "targets": []})
            key = (location, absolute_path)
            if key in group["seen"]:
                continue
            group["seen"].add(key)
            try:
                line_int = int(line or "0")
            except ValueError:
                line_int = 0
            try:
                col_int = int(col or "0")
            except ValueError:
                col_int = 0
            group["targets"].append(
                {
                    "found": found == "yes",
                    "path": rel_path,
                    "line": line_int,
                    "col": col_int,
                    "absolutePath": absolute_path,
                    "location": location,
                }
            )
    return {step_name: data["targets"] for step_name, data in groups.items()}


verify = parse_env_lines(os.environ.get("TEST_STATUS_VERIFY", ""))
test_run = parse_env_lines(os.environ.get("TEST_STATUS_TEST", ""))
latest = parse_env_lines(os.environ.get("TEST_STATUS_LATEST", ""))
runners = parse_runner_rows(os.environ.get("TEST_STATUS_RUNNERS", ""))
debug_handoffs = parse_debug_handoffs(os.environ.get("TEST_STATUS_DEBUG_HANDOFFS", ""))
summary_results = load_summary_results(latest.get("latest_summary", ""))
detail_sections = load_detail_sections(latest.get("latest_details", ""))
semantic_targets = load_semantic_targets(latest.get("latest_semantic", ""))

passing = 0
failing = 0
not_run = 0
failure_groups = []

for runner in runners:
    last_run = summary_results.get(runner["id"])
    if not last_run:
        runner["lastRun"] = {
            "status": "not-run",
            "targetCount": 0,
            "targets": [],
            "outputExcerpt": [],
            "primaryTarget": None,
            "debugHandoff": None,
        }
        not_run += 1
        continue

    targets = semantic_targets.get(runner["id"], [])
    details = detail_sections.get(runner["id"], {})
    primary_target = targets[0] if targets else None
    last_run_payload = dict(last_run)
    last_run_payload["targetCount"] = len(targets)
    last_run_payload["targets"] = targets
    last_run_payload["primaryTarget"] = primary_target
    last_run_payload["outputExcerpt"] = details.get("outputExcerpt", [])
    last_run_payload["debugHandoff"] = (
        debug_handoffs.get(runner["id"])
        if last_run.get("status") == "failing"
        else None
    )
    runner["lastRun"] = last_run_payload

    if last_run.get("status") == "passing":
        passing += 1
        continue

    failing += 1
    failure_groups.append(
        {
            "runnerId": runner["id"],
            "family": runner["family"],
            "label": runner["label"],
            "sourcePath": runner["sourcePath"],
            "command": last_run.get("command") or runner.get("command") or "",
            "exitCode": last_run.get("exitCode", 0),
            "durationMs": last_run.get("durationMs", 0),
            "flakyState": last_run.get("flakyState", ""),
            "summary": (details.get("outputExcerpt") or [""])[0],
            "outputExcerpt": details.get("outputExcerpt", []),
            "targetCount": len(targets),
            "primaryTarget": primary_target,
            "targets": targets,
            "debugHandoff": debug_handoffs.get(runner["id"]),
        }
    )

payload = {
    "schemaVersion": 1,
    "root": os.environ.get("TEST_STATUS_ROOT", ""),
    "summary": {
        "runnerCount": len(runners),
        "runnableCount": sum(1 for runner in runners if runner.get("runnable")),
        "unavailableCount": sum(1 for runner in runners if not runner.get("runnable")),
        "lastRunPassing": passing,
        "lastRunFailing": failing,
        "lastRunNotRun": not_run,
        "latestSource": latest.get("latest_source", "none"),
        "latestFailureGroups": len(failure_groups),
        "latestFailureTargets": sum(group.get("targetCount", 0) for group in failure_groups),
        "debuggableFailureGroups": sum(1 for group in failure_groups if group.get("debugHandoff")),
    },
    "verify": {
        "status": verify.get("verify_status", "never-run"),
        "lastRunAt": verify.get("verify_last_run_at", ""),
        "summaryReport": verify.get("verify_summary", ""),
        "detailsReport": verify.get("verify_details", ""),
        "semanticReport": verify.get("verify_semantic", ""),
        "failures": int(verify.get("verify_failures") or "0"),
        "warnings": int(verify.get("verify_warns") or "0"),
        "executedSteps": int(verify.get("verify_executed") or "0"),
    },
    "test": {
        "status": test_run.get("test_status", "never-run"),
        "lastRunAt": test_run.get("test_last_run_at", ""),
        "summaryReport": test_run.get("test_summary", ""),
        "detailsReport": test_run.get("test_details", ""),
        "semanticReport": test_run.get("test_semantic", ""),
        "failures": int(test_run.get("test_failures") or "0"),
        "warnings": int(test_run.get("test_warns") or "0"),
        "executedSteps": int(test_run.get("test_executed") or "0"),
    },
    "latest": {
        "source": latest.get("latest_source", "none"),
        "status": latest.get("latest_status", "never-run"),
        "lastRunAt": latest.get("latest_last_run_at", ""),
        "summaryReport": latest.get("latest_summary", ""),
        "detailsReport": latest.get("latest_details", ""),
        "semanticReport": latest.get("latest_semantic", ""),
        "failures": int(latest.get("latest_failures") or "0"),
        "warnings": int(latest.get("latest_warns") or "0"),
        "executedSteps": int(latest.get("latest_executed") or "0"),
    },
    "failures": failure_groups,
    "runners": runners,
}

format_name = os.environ.get("TEST_STATUS_FORMAT", "text")
if format_name == "json":
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0)

print("")
print("IDE Test Runner Status")
print(f"Project root:       {payload.get('root', '')}")
print(f"Latest source:      {payload['latest'].get('source', 'none')}")
print(f"Latest status:      {payload['latest'].get('status', 'never-run')}")
print(f"Latest test run:    {payload['test'].get('status', 'never-run')}")
print(f"Latest verify:      {payload['verify'].get('status', 'never-run')}")
print(f"Last latest run:    {payload['latest'].get('lastRunAt', '') or 'never'}")
print(f"Summary report:     {payload['latest'].get('summaryReport', '') or 'missing'}")
print(f"Details report:     {payload['latest'].get('detailsReport', '') or 'missing'}")
print(f"Semantic report:    {payload['latest'].get('semanticReport', '') or 'missing'}")
print(f"Failures / warns:   {payload['latest'].get('failures', 0)} / {payload['latest'].get('warnings', 0)}")
print(f"Runners:            {payload['summary'].get('runnerCount', 0)} total / {payload['summary'].get('runnableCount', 0)} runnable")
print("")

if not runners:
    print("No repo-native test runners were detected from the current verify contract.")
    print("")
    raise SystemExit(0)

print(f"{'RUNNER':<18} {'FAMILY':<8} {'RUN':<5} {'QUICK':<5} {'LAST':<10} SOURCE")
for runner in runners:
    last_status = (runner.get("lastRun") or {}).get("status", "not-run")
    line = (
        f"{runner['id']:<18} "
        f"{runner['family']:<8} "
        f"{('yes' if runner.get('runnable') else 'no'):<5} "
        f"{('yes' if runner.get('quickEligible') else 'no'):<5} "
        f"{last_status:<10} "
        f"{runner.get('sourcePath', '')}"
    )
    if runner.get("reason"):
        line = f"{line} ({runner['reason']})"
    print(line)

print("")
print("Commands:")
for runner in runners:
    command = runner.get("command") or "unavailable"
    print(f"  {runner['id']}: {command}")

if failure_groups:
    print("")
    print("Latest Failure Groups:")
    for group in failure_groups:
        print(
            f"  {group['runnerId']} ({group['family']}) exit={group['exitCode']} "
            f"targets={group['targetCount']}"
        )
        if group.get("primaryTarget"):
            print(f"    primary: {group['primaryTarget'].get('location', '')}")
        for target in group.get("targets", [])[1:4]:
            print(f"    target:  {target.get('location', '')}")
        handoff = group.get("debugHandoff") or {}
        if handoff:
            print(f"    debug:   {handoff.get('command', '')}")
            if handoff.get("trustRequired"):
                print(f"    trust:   {handoff.get('trustCommand', '')}")
            for note in (handoff.get("notes") or [])[:2]:
                print(f"    note:    {note}")
        for excerpt in group.get("outputExcerpt", [])[:2]:
            print(f"    output:  {excerpt}")
print("")
PY
            ;;
        *)
            yen_error "Unknown test status format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

test_runner_ids_csv_from_file() {
    local rows_file="$1"
    awk -F'\t' 'NF { print $1 }' "${rows_file}" | paste -sd',' -
}

test_selected_rows_for_runner_ids() {
    local root="$1"
    local output_file="$2"
    shift 2
    local runner_rows=""
    local rows_file=""
    local runner_id=""
    local row=""
    local missing_ids=()

    runner_rows=$(verify_test_runner_rows_for_root "${root}")
    rows_file=$(mktemp "${TMPDIR:-/tmp}/yen-ide-test-runners-refresh.XXXXXX" 2>/dev/null || mktemp)
    printf "%s\n" "${runner_rows}" > "${rows_file}"
    : > "${output_file}"

    for runner_id in "$@"; do
        row=$(awk -F'\t' -v runner="${runner_id}" '$1 == runner { print; exit }' "${rows_file}")
        if [[ -z "${row}" ]]; then
            missing_ids+=("${runner_id}")
            continue
        fi
        printf "%s\n" "${row}" >> "${output_file}"
    done
    rm -f "${rows_file}"

    if [[ ${#missing_ids[@]} -gt 0 ]]; then
        yen_error "Rerun scope no longer matches detected test runners: $(printf "%s\n" "${missing_ids[@]}" | paste -sd',' -)"
        return 1
    fi
}

test_run_execute_selected_rows() {
    local root="$1"
    local selected_file="$2"
    local mode="$3"
    local latest_source="$4"
    local selected_csv="$5"
    local watch_session="$6"
    local watch_iteration="${7:-0}"
    local watch_scope="${8:-}"
    local report_base=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local timestamp=""
    local stamp_ms=""
    local hash=""
    local failures="0"
    local warns="0"
    local executed="0"
    local result=""
    local status=""
    local watch_detail=""

    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    stamp_ms=$(now_ms)
    hash=$(project_short_hash_for_root "${root}")
    report_base="${IDE_TEST_DIR}/test-${timestamp}-${stamp_ms}-${hash}"
    report_summary="${report_base}.tsv"
    report_details="${report_base}.log"
    report_semantic="${report_base}.semantic.tsv"
    : > "${report_summary}"
    : > "${report_details}"
    : > "${report_semantic}"

    if [[ -n "${watch_session}" ]]; then
        watch_detail=";watchSession=${watch_session};watchIteration=${watch_iteration};watchScope=${watch_scope}"
        echo "Watch iteration: ${watch_iteration}"
    fi

    timeline_log "test" "${root}" "start" "mode=${mode};selected=${selected_csv};source=${latest_source}${watch_detail}"

    while IFS=$'\t' read -r runner_id runner_family runner_label runner_source runner_workdir runner_cmd runner_runnable runner_quick runner_reason; do
        [[ -z "${runner_id}" ]] && continue
        if [[ "${runner_runnable}" == "yes" ]]; then
            result=$(run_verify_step "${root}" "${runner_workdir}" "${report_summary}" "${report_details}" "${report_semantic}" "${runner_id}" "${runner_cmd}" "0" "test")
            status="${result##*|}"
            result="${result%%|*}"
            [[ "${result}" == "fail" ]] && failures=$((failures + 1))
            [[ "${result}" == "warn" ]] && warns=$((warns + 1))
            executed=$((executed + 1))
            continue
        fi

        record_verify_skipped_step "${report_summary}" "${report_details}" "${runner_id}" "127" "${runner_reason}" "test"
        warns=$((warns + 1))
    done < "${selected_file}"

    echo "Summary file: ${report_summary}"
    echo "Details file: ${report_details}"
    echo "Semantic file: ${report_semantic}"
    echo "Steps executed: ${executed}"
    echo "Warnings:       ${warns}"
    echo "Failures:       ${failures}"
    echo ""

    timeline_log "test" "${root}" "failures=${failures};warns=${warns};selected=$(awk 'NF { count += 1 } END { print count + 0 }' "${selected_file}" 2>/dev/null)" "summary=${report_summary};semantic=${report_semantic};mode=${mode};source=${latest_source};runners=${selected_csv}${watch_detail}"

    if [[ "${executed}" -eq 0 ]]; then
        yen_error "No runnable test runners were executed."
        return 1
    fi
    if [[ "${failures}" -gt 0 || "${warns}" -gt 0 ]]; then
        yen_error "Test run completed with failures or warnings."
        return 1
    fi
    yen_success "Test run passed."
    return 0
}

cmd_test_run() {
    local target=""
    local quick="0"
    local rerun_failed="0"
    local watch="0"
    local watch_interval="1"
    local watch_max_runs=""
    local root=""
    local runners=""
    local latest_snapshot=""
    local latest_source="none"
    local latest_summary=""
    local requested_csv=""
    local selected_csv=""
    local mode="all"
    local report_base=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local timestamp=""
    local hash=""
    local failures="0"
    local warns="0"
    local executed="0"
    local selected_count="0"
    local result=""
    local status=""
    local runner_ids=()
    local scope_runner_ids=()
    local failed_ids=""
    local rows_file=""
    local selected_file=""
    local watch_scope_label=""
    local watch_scope_key=""
    local watch_session=""
    local watch_snapshot=""
    local watch_fingerprint=""
    local watch_runs_completed="0"
    local run_status="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --quick)
                quick="1"
                ;;
            --failed)
                rerun_failed="1"
                ;;
            --watch)
                watch="1"
                ;;
            --watch-interval)
                shift
                watch_interval="${1:-}"
                ;;
            --watch-interval=*)
                watch_interval="${1#*=}"
                ;;
            --max-runs)
                shift
                watch_max_runs="${1:-}"
                ;;
            --max-runs=*)
                watch_max_runs="${1#*=}"
                ;;
            --runner)
                shift
                if [[ -z "${1:-}" ]]; then
                    yen_error "test run --runner requires a runner id."
                    return 1
                fi
                runner_ids+=("$1")
                ;;
            --runner=*)
                if [[ -z "${1#*=}" ]]; then
                    yen_error "test run --runner requires a runner id."
                    return 1
                fi
                runner_ids+=("${1#*=}")
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "test run accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    if ! ide_watch_validate_interval "${watch_interval}"; then
        return 1
    fi
    if [[ -n "${watch_max_runs}" ]] && ! ide_watch_validate_max_runs "${watch_max_runs}"; then
        return 1
    fi
    if [[ "${watch}" != "1" && -n "${watch_max_runs}" ]]; then
        yen_error "--max-runs requires --watch."
        return 1
    fi

    root=$(find_project_root "${target}")
    runners=$(verify_test_runner_rows_for_root "${root}")
    if [[ -z "${runners}" ]]; then
        yen_error "No repo-native test runners detected for ${root}."
        return 1
    fi

    rows_file=$(mktemp "${TMPDIR:-/tmp}/yen-ide-test-run.XXXXXX" 2>/dev/null || mktemp)
    selected_file=$(mktemp "${TMPDIR:-/tmp}/yen-ide-test-selected.XXXXXX" 2>/dev/null || mktemp)
    printf "%s\n" "${runners}" > "${rows_file}"

    if [[ ${#runner_ids[@]} -gt 0 ]]; then
        local requested_id=""
        for requested_id in "${runner_ids[@]}"; do
            if ! awk -F'\t' -v runner="${requested_id}" '$1 == runner { found = 1 } END { exit(found ? 0 : 1) }' "${rows_file}"; then
                rm -f "${rows_file}" "${selected_file}"
                yen_error "Unknown test runner id: ${requested_id}"
                return 1
            fi
        done
        requested_csv=$(printf "%s\n" "${runner_ids[@]}" | paste -sd',' -)
        mode="selected"
    fi

    if [[ "${rerun_failed}" == "1" ]]; then
        latest_snapshot=$(latest_test_failure_source_snapshot_for_root "${root}")
        latest_source=$(doctor_snapshot_value "${latest_snapshot}" "latest_source")
        latest_summary=$(doctor_snapshot_value "${latest_snapshot}" "latest_summary")
        if [[ "${latest_source}" == "none" || -z "${latest_summary}" || ! -f "${latest_summary}" ]]; then
            rm -f "${rows_file}" "${selected_file}"
            yen_error "test run --failed requires a previous local verify/test report with failing runners."
            return 1
        fi
        failed_ids=$(failing_step_ids_from_summary "${latest_summary}")
        if [[ -z "${failed_ids}" ]]; then
            rm -f "${rows_file}" "${selected_file}"
            yen_error "Latest local ${latest_source} report does not contain failing test runners."
            return 1
        fi
        if [[ "${mode}" == "selected" ]]; then
            mode="failed+selected"
        else
            mode="failed"
        fi
    fi

    while IFS=$'\t' read -r runner_id runner_family runner_label runner_source runner_workdir runner_cmd runner_runnable runner_quick runner_reason; do
        local include="1"
        [[ -z "${runner_id}" ]] && continue

        if [[ ${#runner_ids[@]} -gt 0 ]]; then
            include="0"
            local requested_id=""
            for requested_id in "${runner_ids[@]}"; do
                if [[ "${runner_id}" == "${requested_id}" ]]; then
                    include="1"
                    break
                fi
            done
        fi

        if [[ "${include}" == "1" && "${rerun_failed}" == "1" ]]; then
            if ! printf "%s\n" "${failed_ids}" | grep -Fxq -- "${runner_id}"; then
                include="0"
            fi
        fi

        if [[ "${include}" == "1" && "${quick}" == "1" && "${runner_quick}" != "yes" ]]; then
            include="0"
        fi

        if [[ "${include}" == "1" ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "${runner_id}" "${runner_family}" "${runner_label}" "${runner_source}" "${runner_workdir}" "${runner_cmd}" "${runner_runnable}" "${runner_quick}" "${runner_reason}" >> "${selected_file}"
        fi
    done < "${rows_file}"

    selected_count=$(awk 'NF { count += 1 } END { print count + 0 }' "${selected_file}" 2>/dev/null)
    if [[ "${selected_count}" -eq 0 ]]; then
        rm -f "${rows_file}" "${selected_file}"
        yen_error "No test runners matched the requested scope."
        return 1
    fi

    while IFS=$'\t' read -r runner_id _rest; do
        [[ -n "${runner_id}" ]] && scope_runner_ids+=("${runner_id}")
    done < "${selected_file}"
    selected_csv=$(test_runner_ids_csv_from_file "${selected_file}")

    case "${mode}" in
        selected)
            watch_scope_label="selected runner snapshot (${selected_csv})"
            watch_scope_key="selected-snapshot"
            ;;
        failed|failed+selected)
            watch_scope_label="failing runner snapshot from ${latest_source} (${selected_csv})"
            watch_scope_key="failed-snapshot"
            ;;
        *)
            watch_scope_label="detected runner snapshot (${selected_csv})"
            watch_scope_key="detected-snapshot"
            ;;
    esac

    echo ""
    yen_header "IDE Test Run"
    echo "Project:          ${root}"
    echo "Mode:             ${mode}"
    if [[ -n "${requested_csv}" ]]; then
        echo "Requested:        ${requested_csv}"
    fi
    if [[ "${rerun_failed}" == "1" ]]; then
        echo "Failure source:   ${latest_source}"
    fi
    if [[ "${watch}" == "1" ]]; then
        echo "Watch:            enabled"
        echo "Watch interval:   ${watch_interval}s"
        echo "Max runs:         ${watch_max_runs:-unbounded}"
        echo "Rerun scope:      ${watch_scope_label}"
    fi
    echo "Selected runners: ${selected_csv}"
    echo ""
    printf "%-18s %-8s %-5s %-5s %s\n" "RUNNER" "FAMILY" "RUN" "QUICK" "COMMAND"
    while IFS=$'\t' read -r runner_id runner_family _ runner_source _ runner_cmd runner_runnable runner_quick runner_reason; do
        [[ -z "${runner_id}" ]] && continue
        printf "%-18s %-8s %-5s %-5s %s\n" "${runner_id}" "${runner_family}" "${runner_runnable}" "${runner_quick}" "${runner_cmd}"
    done < "${selected_file}"
    echo ""

    if [[ "${watch}" == "1" ]]; then
        watch_session="test-watch-$(date -u +"%Y%m%dT%H%M%SZ")-$(project_short_hash_for_root "${root}")"
        watch_snapshot=$(ide_watch_snapshot_for_root "${root}")
        watch_fingerprint="${watch_snapshot%%$'\t'*}"
        timeline_log "test-watch" "${root}" "start" "session=${watch_session};scope=${watch_scope_key};interval=${watch_interval};maxRuns=${watch_max_runs:-unbounded};runners=${selected_csv}"
    fi

    while true; do
        : > "${selected_file}"
        if ! test_selected_rows_for_runner_ids "${root}" "${selected_file}" "${scope_runner_ids[@]}"; then
            rm -f "${rows_file}" "${selected_file}"
            if [[ "${watch}" == "1" ]]; then
                timeline_log "test-watch" "${root}" "stop" "session=${watch_session};reason=scope-missing;runners=${selected_csv}"
            fi
            return 1
        fi

        run_status=0
        test_run_execute_selected_rows "${root}" "${selected_file}" "${mode}" "${latest_source}" "${selected_csv}" "${watch_session}" "$((watch_runs_completed + 1))" "${watch_scope_key}" || run_status=$?
        watch_runs_completed=$((watch_runs_completed + 1))

        if [[ "${watch}" != "1" ]]; then
            rm -f "${rows_file}" "${selected_file}"
            return "${run_status}"
        fi

        watch_snapshot=$(ide_watch_snapshot_for_root "${root}")
        watch_fingerprint="${watch_snapshot%%$'\t'*}"

        if [[ -n "${watch_max_runs}" && "${watch_runs_completed}" -ge "${watch_max_runs}" ]]; then
            timeline_log "test-watch" "${root}" "stop" "session=${watch_session};reason=max-runs;runs=${watch_runs_completed};status=${run_status};runners=${selected_csv}"
            rm -f "${rows_file}" "${selected_file}"
            return "${run_status}"
        fi

        yen_info "Watch: waiting for project changes to rerun ${watch_scope_label}. Press Ctrl+C to stop."
        local next_snapshot=""
        local next_fingerprint=""
        local changed_path=""
        local _watch_count=""
        local _watch_mtime=""
        next_snapshot=$(ide_watch_wait_for_change "${root}" "${watch_fingerprint}" "${watch_interval}")
        IFS=$'\t' read -r next_fingerprint _watch_count changed_path _watch_mtime << EOF
${next_snapshot}
EOF
        if [[ "${next_fingerprint}" == "missing" ]]; then
            timeline_log "test-watch" "${root}" "stop" "session=${watch_session};reason=missing-root;runs=${watch_runs_completed};runners=${selected_csv}"
            rm -f "${rows_file}" "${selected_file}"
            yen_error "Watch stopped because the project root is no longer available: ${root}"
            return 1
        fi
        watch_fingerprint="${next_fingerprint}"
        timeline_log "test-watch" "${root}" "rerun" "session=${watch_session};iteration=$((watch_runs_completed + 1));scope=${watch_scope_key};path=${changed_path};runners=${selected_csv}"
        yen_info "Watch: change detected (${changed_path:-project update}); rerunning ${watch_scope_label}."
        echo ""
    done
}

cmd_test() {
    local sub="${1:-status}"
    case "${sub}" in
        status)
            shift || true
            cmd_test_status "$@"
            ;;
        run)
            shift || true
            cmd_test_run "$@"
            ;;
        ""|--*)
            cmd_test_status "$@"
            ;;
        *)
            if [[ -d "${sub}" || -f "${sub}" ]]; then
                cmd_test_status "$@"
                return $?
            fi
            yen_error "Unknown test command: ${sub}"
            return 1
            ;;
    esac
}

VERIFY_LAST_OUTCOME=""
VERIFY_LAST_SUMMARY=""
VERIFY_LAST_DETAILS=""
VERIFY_LAST_SEMANTIC=""
VERIFY_LAST_FAILURES="0"
VERIFY_LAST_WARNS="0"
VERIFY_LAST_EXECUTED="0"
VERIFY_LAST_STATUS_CODE="0"

verify_write_watch_state() {
    local root="$1"
    local session="$2"
    local active="$3"
    local state="$4"
    local iteration="$5"
    local interval="$6"
    local max_runs="$7"
    local scope="$8"
    local branch="$9"
    local stop_reason="${10}"
    local started_at="${11}"

    watch_state_write "${root}" "verify" \
        "kind=verify" \
        "root=$(watch_state_clean_value "${root}")" \
        "session=$(watch_state_clean_value "${session}")" \
        "label=verify" \
        "branch=$(watch_state_clean_value "${branch}")" \
        "active=$(watch_state_clean_value "${active}")" \
        "state=$(watch_state_clean_value "${state}")" \
        "iteration=$(watch_state_clean_value "${iteration}")" \
        "interval_seconds=$(watch_state_clean_value "${interval}")" \
        "max_runs=$(watch_state_clean_value "${max_runs}")" \
        "scope=$(watch_state_clean_value "${scope}")" \
        "started_at=$(watch_state_clean_value "${started_at}")" \
        "updated_at=$(iso_now)" \
        "stop_reason=$(watch_state_clean_value "${stop_reason}")" \
        "last_outcome=$(watch_state_clean_value "${VERIFY_LAST_OUTCOME}")" \
        "last_exit_code=$(watch_state_clean_value "${VERIFY_LAST_STATUS_CODE}")" \
        "last_failures=$(watch_state_clean_value "${VERIFY_LAST_FAILURES}")" \
        "last_warns=$(watch_state_clean_value "${VERIFY_LAST_WARNS}")" \
        "last_executed=$(watch_state_clean_value "${VERIFY_LAST_EXECUTED}")" \
        "summary=$(watch_state_clean_value "${VERIFY_LAST_SUMMARY}")" \
        "details=$(watch_state_clean_value "${VERIFY_LAST_DETAILS}")" \
        "semantic=$(watch_state_clean_value "${VERIFY_LAST_SEMANTIC}")"
}

verify_execute_bundle() {
    local root="$1"
    local quick="$2"
    local no_build="$3"
    local security="$4"
    local strict="$5"
    local watch_session="${6:-}"
    local watch_iteration="${7:-0}"
    local watch_scope="${8:-}"
    local timestamp=""
    local stamp_ms=""
    local hash=""
    local report_base=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local failures="0"
    local warns="0"
    local executed="0"
    local result=""
    local status=""
    local test_runners=""
    local runner_id=""
    local runner_family=""
    local runner_label=""
    local runner_source=""
    local runner_workdir=""
    local runner_cmd=""
    local runner_runnable=""
    local runner_quick=""
    local runner_reason=""
    local watch_detail=""

    VERIFY_LAST_OUTCOME=""
    VERIFY_LAST_SUMMARY=""
    VERIFY_LAST_DETAILS=""
    VERIFY_LAST_SEMANTIC=""
    VERIFY_LAST_FAILURES="0"
    VERIFY_LAST_WARNS="0"
    VERIFY_LAST_EXECUTED="0"
    VERIFY_LAST_STATUS_CODE="0"

    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    stamp_ms=$(now_ms)
    hash=$(project_short_hash_for_root "${root}")
    report_base="${IDE_VERIFY_DIR}/verify-${timestamp}-${stamp_ms}-${hash}"
    report_summary="${report_base}.tsv"
    report_details="${report_base}.log"
    report_semantic="${report_base}.semantic.tsv"
    : > "${report_summary}"
    : > "${report_details}"
    : > "${report_semantic}"

    if [[ -n "${watch_session}" ]]; then
        watch_detail=";watchSession=${watch_session};watchIteration=${watch_iteration};watchScope=${watch_scope}"
        echo "Watch iteration: ${watch_iteration}"
    fi

    echo ""
    yen_header "IDE Verification Bundle"
    echo "Root:          ${root}"
    echo "Summary file:  ${report_summary}"
    echo "Details file:  ${report_details}"
    echo "Semantic file: ${report_semantic}"
    echo "Flaky ledger:  ${IDE_VERIFY_FLAKY_FILE}"
    echo ""

    local node_pm="none"
    if [[ -f "${root}/package.json" ]]; then
        node_pm=$(detect_node_package_manager "${root}")
        if [[ "${node_pm}" == "none" ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$(iso_now)" "node-toolchain" "127" "0" "warn" "0" "missing-node-package-manager" "warn" "quality" >> "${report_summary}"
            {
                echo "=== node-toolchain ==="
                echo "category: quality"
                echo "result: warn"
                echo "status: skipped (no bun/pnpm/yarn/npm found)"
                echo ""
            } >> "${report_details}"
            warns=$((warns + 1))
            if [[ "${strict}" == "1" ]]; then
                failures=$((failures + 1))
            fi
        else
            local tsc_cmd=""
            local lint_check_cmd=""
            local lint_cmd=""
            local build_cmd=""
            case "${node_pm}" in
                bun)
                    tsc_cmd="bunx tsc --noEmit"
                    lint_check_cmd="bun run lint:check"
                    lint_cmd="bun run lint"
                    build_cmd="bun run build"
                    ;;
                pnpm)
                    tsc_cmd="pnpm exec tsc --noEmit"
                    lint_check_cmd="pnpm run lint:check"
                    lint_cmd="pnpm run lint"
                    build_cmd="pnpm run build"
                    ;;
                yarn)
                    tsc_cmd="yarn tsc --noEmit"
                    lint_check_cmd="yarn lint:check"
                    lint_cmd="yarn lint"
                    build_cmd="yarn build"
                    ;;
                npm)
                    tsc_cmd="npx tsc --noEmit"
                    lint_check_cmd="npm run -s lint:check"
                    lint_cmd="npm run -s lint"
                    build_cmd="npm run -s build"
                    ;;
            esac

            if [[ -f "${root}/tsconfig.json" ]]; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "tsc-noemit" "${tsc_cmd}" "0" "quality")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            fi

            if has_package_script "${root}" "lint:check"; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "lint-check" "${lint_check_cmd}" "0" "quality")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            elif has_package_script "${root}" "lint"; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "lint" "${lint_cmd}" "0" "quality")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            else
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$(iso_now)" "lint" "127" "0" "warn" "0" "missing-lint-script" "warn" "quality" >> "${report_summary}"
                {
                    echo "=== lint ==="
                    echo "category: quality"
                    echo "result: warn"
                    echo "status: skipped (missing-lint-script)"
                    echo ""
                } >> "${report_details}"
                warns=$((warns + 1))
                if [[ "${strict}" == "1" ]]; then
                    failures=$((failures + 1))
                fi
            fi

            if [[ "${no_build}" != "1" && "${quick}" != "1" ]] && has_package_script "${root}" "build"; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "node-build" "${build_cmd}" "0" "build")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            fi
        fi
    fi

    test_runners=$(verify_test_runner_rows_for_root "${root}")
    if [[ -n "${test_runners}" ]]; then
        while IFS=$'\t' read -r runner_id runner_family runner_label runner_source runner_workdir runner_cmd runner_runnable runner_quick runner_reason; do
            [[ -z "${runner_id}" ]] && continue
            if [[ "${quick}" == "1" && "${runner_quick}" != "yes" ]]; then
                continue
            fi
            if [[ "${runner_runnable}" == "yes" ]]; then
                result=$(run_verify_step "${root}" "${runner_workdir}" "${report_summary}" "${report_details}" "${report_semantic}" "${runner_id}" "${runner_cmd}" "0" "test")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
                continue
            fi

            case "${runner_reason}" in
                missing-cargo)
                    record_verify_skipped_step "${report_summary}" "${report_details}" "${runner_id}" "127" "cargo missing" "test"
                    warns=$((warns + 1))
                    [[ "${strict}" == "1" ]] && failures=$((failures + 1))
                    ;;
                missing-python)
                    record_verify_skipped_step "${report_summary}" "${report_details}" "${runner_id}" "127" "python missing" "test"
                    warns=$((warns + 1))
                    [[ "${strict}" == "1" ]] && failures=$((failures + 1))
                    ;;
                missing-swift)
                    record_verify_skipped_step "${report_summary}" "${report_details}" "${runner_id}" "127" "swift missing" "test"
                    warns=$((warns + 1))
                    [[ "${strict}" == "1" ]] && failures=$((failures + 1))
                    ;;
                missing-zig)
                    record_verify_skipped_step "${report_summary}" "${report_details}" "${runner_id}" "127" "zig missing" "test"
                    warns=$((warns + 1))
                    [[ "${strict}" == "1" ]] && failures=$((failures + 1))
                    ;;
            esac
        done << EOF
${test_runners}
EOF
    fi

    if [[ "${security}" == "1" ]]; then
        if command -v gitleaks >/dev/null 2>&1; then
            result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "gitleaks" "gitleaks detect --no-banner --redact --source ." "0" "security")
            status="${result##*|}"
            result="${result%%|*}"
            [[ "${result}" == "fail" ]] && failures=$((failures + 1))
            executed=$((executed + 1))
        else
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$(iso_now)" "gitleaks" "127" "0" "warn" "0" "missing-tool" "warn" "security" >> "${report_summary}"
            {
                echo "=== gitleaks ==="
                echo "category: security"
                echo "result: warn"
                echo "status: skipped (tool missing)"
                echo ""
            } >> "${report_details}"
            warns=$((warns + 1))
            if [[ "${strict}" == "1" ]]; then
                failures=$((failures + 1))
            fi
        fi

        if [[ -f "${root}/package.json" && "${node_pm}" != "none" ]]; then
            local audit_cmd=""
            case "${node_pm}" in
                bun)
                    audit_cmd="bun audit"
                    ;;
                pnpm)
                    audit_cmd="pnpm audit"
                    ;;
                yarn)
                    audit_cmd="yarn audit --level high"
                    ;;
                npm)
                    audit_cmd="npm audit --audit-level=high"
                    ;;
            esac
            if [[ -n "${audit_cmd}" ]]; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "node-audit" "${audit_cmd}" "1" "security")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            fi
        fi

        local osv_cmd=""
        osv_cmd=$(osv_scan_command_for_root "${root}" || true)
        if [[ -n "${osv_cmd}" ]]; then
            if command -v osv-scanner >/dev/null 2>&1; then
                result=$(run_verify_step "${root}" "${root}" "${report_summary}" "${report_details}" "${report_semantic}" "osv-scanner" "${osv_cmd}" "1" "security")
                status="${result##*|}"
                result="${result%%|*}"
                [[ "${result}" == "fail" ]] && failures=$((failures + 1))
                [[ "${result}" == "warn" ]] && warns=$((warns + 1))
                executed=$((executed + 1))
            else
                record_verify_skipped_step "${report_summary}" "${report_details}" "osv-scanner" "127" "missing-tool" "security"
                warns=$((warns + 1))
                if [[ "${strict}" == "1" ]]; then
                    failures=$((failures + 1))
                fi
            fi
        fi
    fi

    echo "Steps executed: ${executed}"
    echo "Warnings:       ${warns}"
    echo "Failures:       ${failures}"
    echo ""

    timeline_log "verify" "${root}" "failures=${failures};warns=${warns}" "summary=${report_summary};semantic=${report_semantic}${watch_detail}"

    VERIFY_LAST_SUMMARY="${report_summary}"
    VERIFY_LAST_DETAILS="${report_details}"
    VERIFY_LAST_SEMANTIC="${report_semantic}"
    VERIFY_LAST_FAILURES="${failures}"
    VERIFY_LAST_WARNS="${warns}"
    VERIFY_LAST_EXECUTED="${executed}"
    if [[ "${failures}" -gt 0 ]]; then
        VERIFY_LAST_OUTCOME="failing"
        VERIFY_LAST_STATUS_CODE="1"
        yen_error "Verification bundle failed."
        return 1
    fi
    if [[ "${warns}" -gt 0 ]]; then
        VERIFY_LAST_OUTCOME="warnings"
    else
        VERIFY_LAST_OUTCOME="passing"
    fi
    VERIFY_LAST_STATUS_CODE="0"
    yen_success "Verification bundle passed."
    return 0
}

cmd_verify_run() {
    local quick="0"
    local no_build="0"
    local security="1"
    local strict="0"
    local watch="0"
    local watch_interval="1"
    local watch_max_runs=""
    local root=""
    local watch_scope_label=""
    local watch_scope_key=""
    local watch_scope_descriptor="default"
    local watch_branch=""
    local watch_session=""
    local watch_started_at=""
    local watch_snapshot=""
    local watch_fingerprint=""
    local watch_runs_completed="0"
    local run_status="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick)
                quick="1"
                no_build="1"
                ;;
            --no-build)
                no_build="1"
                ;;
            --security)
                security="1"
                ;;
            --no-security)
                security="0"
                ;;
            --strict)
                strict="1"
                ;;
            --watch)
                watch="1"
                ;;
            --watch-interval)
                shift
                watch_interval="${1:-}"
                ;;
            --watch-interval=*)
                watch_interval="${1#*=}"
                ;;
            --max-runs)
                shift
                watch_max_runs="${1:-}"
                ;;
            --max-runs=*)
                watch_max_runs="${1#*=}"
                ;;
            *)
                yen_error "Unknown verify option: $1"
                return 1
                ;;
        esac
        shift
    done

    if ! ide_watch_validate_interval "${watch_interval}"; then
        return 1
    fi
    if [[ -n "${watch_max_runs}" ]] && ! ide_watch_validate_max_runs "${watch_max_runs}"; then
        return 1
    fi
    if [[ "${watch}" != "1" && -n "${watch_max_runs}" ]]; then
        yen_error "--max-runs requires --watch."
        return 1
    fi

    root=$(find_project_root "${PWD}")
    if [[ "${quick}" == "1" ]]; then
        watch_scope_descriptor="quick,no-build"
        no_build="1"
    fi
    if [[ "${no_build}" == "1" && "${watch_scope_descriptor}" != *"no-build"* ]]; then
        watch_scope_descriptor="${watch_scope_descriptor},no-build"
    fi
    if [[ "${security}" != "1" ]]; then
        watch_scope_descriptor="${watch_scope_descriptor},no-security"
    fi
    if [[ "${strict}" == "1" ]]; then
        watch_scope_descriptor="${watch_scope_descriptor},strict"
    fi
    watch_scope_descriptor=$(printf "%s" "${watch_scope_descriptor}" | sed 's/^default,//')
    watch_scope_label="verify snapshot (${watch_scope_descriptor})"
    watch_scope_key=$(printf "%s" "${watch_scope_descriptor}" | tr ', ' '__')

    if [[ "${watch}" == "1" ]]; then
        watch_branch=$(watch_state_branch_for_root "${root}")
        watch_session="verify-watch-$(date -u +"%Y%m%dT%H%M%SZ")-$(project_short_hash_for_root "${root}")"
        watch_started_at=$(iso_now)
        watch_snapshot=$(ide_watch_snapshot_for_root "${root}")
        watch_fingerprint="${watch_snapshot%%$'\t'*}"
        echo ""
        echo "Watch:            enabled"
        echo "Watch interval:   ${watch_interval}s"
        echo "Max runs:         ${watch_max_runs:-unbounded}"
        echo "Rerun scope:      ${watch_scope_label}"
        echo ""
        timeline_log "verify-watch" "${root}" "start" "session=${watch_session};scope=${watch_scope_key};interval=${watch_interval};maxRuns=${watch_max_runs:-unbounded}"
        verify_write_watch_state "${root}" "${watch_session}" "yes" "starting" "0" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_descriptor}" "${watch_branch}" "" "${watch_started_at}"
    fi

    while true; do
        run_status=0
        verify_execute_bundle "${root}" "${quick}" "${no_build}" "${security}" "${strict}" "${watch_session}" "$((watch_runs_completed + 1))" "${watch_scope_key}" || run_status=$?
        watch_runs_completed=$((watch_runs_completed + 1))

        if [[ "${watch}" != "1" ]]; then
            return "${run_status}"
        fi

        verify_write_watch_state "${root}" "${watch_session}" "yes" "waiting" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_descriptor}" "${watch_branch}" "" "${watch_started_at}"
        watch_snapshot=$(ide_watch_snapshot_for_root "${root}")
        watch_fingerprint="${watch_snapshot%%$'\t'*}"

        if [[ -n "${watch_max_runs}" && "${watch_runs_completed}" -ge "${watch_max_runs}" ]]; then
            verify_write_watch_state "${root}" "${watch_session}" "no" "max-runs" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs}" "${watch_scope_descriptor}" "${watch_branch}" "max-runs" "${watch_started_at}"
            timeline_log "verify-watch" "${root}" "stop" "session=${watch_session};reason=max-runs;runs=${watch_runs_completed};status=${run_status}"
            return "${run_status}"
        fi

        yen_info "Watch: waiting for project changes to rerun ${watch_scope_label}. Press Ctrl+C to stop."
        local next_snapshot=""
        local next_fingerprint=""
        local changed_path=""
        local _watch_count=""
        local _watch_mtime=""
        next_snapshot=$(ide_watch_wait_for_change "${root}" "${watch_fingerprint}" "${watch_interval}")
        IFS=$'\t' read -r next_fingerprint _watch_count changed_path _watch_mtime << EOF
${next_snapshot}
EOF
        if [[ "${next_fingerprint}" == "missing" ]]; then
            verify_write_watch_state "${root}" "${watch_session}" "no" "missing-root" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_descriptor}" "${watch_branch}" "missing-root" "${watch_started_at}"
            timeline_log "verify-watch" "${root}" "stop" "session=${watch_session};reason=missing-root;runs=${watch_runs_completed}"
            yen_error "Watch stopped because the project root is no longer available: ${root}"
            return 1
        fi
        watch_fingerprint="${next_fingerprint}"
        timeline_log "verify-watch" "${root}" "rerun" "session=${watch_session};iteration=$((watch_runs_completed + 1));scope=${watch_scope_key};path=${changed_path}"
        yen_info "Watch: change detected (${changed_path:-project update}); rerunning ${watch_scope_label}."
        echo ""
    done
}

cmd_verify() {
    local sub="${1:-run}"

    case "${sub}" in
        status)
            shift || true
            cmd_verify_status "$@"
            ;;
        run)
            shift || true
            cmd_verify_run "$@"
            ;;
        ""|--*)
            cmd_verify_run "$@"
            ;;
        *)
            yen_error "Unknown verify command: ${sub}"
            return 1
            ;;
    esac
}
