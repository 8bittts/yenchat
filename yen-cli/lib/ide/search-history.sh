# shellcheck shell=bash
# Source-time pure search/history helpers and command handlers for yen ide.

cmd_history() {
    local sub="list"
    local target=""
    local limit="30"

    if [[ "$1" == "add" || "$1" == "clear" ]]; then
        sub="$1"
        shift
    fi

    case "${sub}" in
        add)
            local command_text="$*"
            if [[ -z "${command_text}" ]]; then
                yen_error "history add requires a command string."
                exit 1
            fi
            local root
            local file
            local timestamp
            root=$(find_project_root "${PWD}")
            file=$(project_history_file "${root}")
            timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            printf "%s\t%s\t%s\n" "${timestamp}" "${PWD}" "${command_text}" >> "${file}"
            ;;
        clear)
            target="${1:-}"
            local root
            local file
            root=$(find_project_root "${target}")
            file=$(project_history_file "${root}")
            : > "${file}"
            yen_success "Cleared history for ${root}"
            ;;
        list)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --limit)
                        shift
                        limit="${1:-30}"
                        ;;
                    *)
                        target="$1"
                        ;;
                esac
                shift
            done
            local root
            local file
            root=$(find_project_root "${target}")
            file=$(project_history_file "${root}")

            if [[ ! -f "${file}" || ! -s "${file}" ]]; then
                yen_info "No project history for ${root}"
                return 0
            fi

            echo ""
            yen_header "Project History"
            echo "Root: ${root}"
            echo ""
            local i=1
            while IFS=$'\t' read -r timestamp cwd cmd; do
                printf "%3d. %s | %s | %s\n" "${i}" "${timestamp}" "${cwd}" "${cmd}"
                i=$((i + 1))
            done < <(tail -r "${file}" | head -n "${limit}")
            echo ""
            ;;
    esac
}

lookup_history_command() {
    local root="$1"
    local index="$2"
    local file
    file=$(project_history_file "${root}")
    if [[ ! -f "${file}" || ! -s "${file}" ]]; then
        return 1
    fi

    if [[ "${index}" == "last" || -z "${index}" ]]; then
        index="1"
    fi
    if [[ ! "${index}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local line
    line=$(tail -r "${file}" | sed -n "${index}p")
    if [[ -z "${line}" ]]; then
        return 1
    fi
    printf "%s\n" "$(printf "%s" "${line}" | cut -f3-)"
}

cmd_replay() {
    local do_exec="0"
    local target=""
    local index="1"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --exec)
                do_exec="1"
                ;;
            --project)
                shift
                target="${1:-}"
                ;;
            last)
                index="last"
                ;;
            *)
                if [[ -z "${index}" || "${index}" == "1" ]]; then
                    index="$1"
                fi
                ;;
        esac
        shift
    done

    local root
    local cmd
    root=$(find_project_root "${target}")
    cmd=$(lookup_history_command "${root}" "${index}" || true)
    if [[ -z "${cmd}" ]]; then
        yen_error "No history entry found for ${root} at index '${index}'."
        exit 1
    fi

    if [[ "${do_exec}" == "1" ]]; then
        yen_info "Replaying: ${cmd}"
        bash -lc "${cmd}"
    else
        printf "%s\n" "${cmd}"
    fi
}

cmd_profile() {
    if [[ "$1" == "--" ]]; then
        shift
    fi
    if [[ $# -eq 0 ]]; then
        yen_error "profile requires a command. Example: yen ide profile -- go test ./..."
        exit 1
    fi

    local root
    local file
    local start_ms
    local end_ms
    local duration_ms
    local status
    local timestamp
    local cmd_text

    root=$(find_project_root "${PWD}")
    file=$(project_profile_file "${root}")
    cmd_text="$*"
    start_ms=$(now_ms)
    set +e
    "$@"
    status=$?
    set -e
    end_ms=$(now_ms)
    duration_ms=$((end_ms - start_ms))
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf "%s\t%s\t%s\t%s\t%s\n" "${timestamp}" "${duration_ms}" "${status}" "${PWD}" "${cmd_text}" >> "${file}"

    echo ""
    yen_header "IDE Profile"
    echo "Root:        ${root}"
    echo "Duration:    ${duration_ms}ms"
    echo "Exit status: ${status}"
    echo "Log file:    ${file}"
    echo ""
    return "${status}"
}

ports_help() {
    yen_header "IDE Ports"
    cat <<'EOF'
Usage:
  yen ide ports [--all|-a] [--json]
  yen ide ports <port> [--all|-a] [--json] [--yes|-y]
  yen ide ports ps [--all|-a] [--json]
  yen ide ports clean [--all|-a] [--json] [--yes|-y]
  yen ide ports watch [--all|-a] [--json]
  yen ide ports help

Subcommands:
  <port>  Show one listening port in detail and offer SIGTERM cleanup
  ps      Show dev processes with CPU, memory, and uptime stats
  clean   Find orphaned or zombie listening processes and optionally terminate them
  watch   Poll every 2 seconds and report newly opened or closed listening ports
  help    Show this help

Flags:
  --all, -a   Include non-dev processes
  --json      Emit JSON instead of text
  --yes, -y   Skip confirmation for destructive actions
EOF
    printf "\n"
}

ports_timeout_command() {
    local seconds="$1"
    shift

    if command -v python3 >/dev/null 2>&1; then
        python3 - "${seconds}" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
command = sys.argv[2:]

try:
    completed = subprocess.run(command, timeout=timeout)
except subprocess.TimeoutExpired:
    raise SystemExit(124)
except FileNotFoundError:
    raise SystemExit(127)

raise SystemExit(completed.returncode)
PY
        return $?
    fi

    "$@"
}

ports_docker_available() {
    if ! command -v docker >/dev/null 2>&1; then
        return 1
    fi
    ports_timeout_command 3 docker info >/dev/null 2>&1
}

ports_extract_port_from_bind() {
    local bind="$1"
    local port=""
    port=$(printf "%s\n" "${bind}" | awk -F: '{print $NF}' | tr -cd '0-9')
    if [[ -n "${port}" ]] && [[ "${port}" =~ ^[0-9]+$ ]]; then
        printf "%s\n" "${port}"
    fi
}

ports_listening_rows() {
    local pid=""
    local command_name=""
    local user_name=""
    local bind=""
    local port=""

    while IFS= read -r line; do
        case "${line%"${line#?}"}" in
            p)
                pid="${line#?}"
                ;;
            c)
                command_name="${line#?}"
                ;;
            u)
                user_name="${line#?}"
                ;;
            n)
                bind=$(printf "%s" "${line#?}" | sed 's/^TCP[[:space:]]*//;s/[[:space:]]*(LISTEN)$//')
                port=$(ports_extract_port_from_bind "${bind}")
                if [[ -n "${pid}" && -n "${port}" ]]; then
                    printf "%s\t%s\t%s\t%s\t%s\n" "${pid}" "${command_name}" "${user_name}" "${port}" "${bind}"
                fi
                ;;
        esac
    done < <(lsof -nP -iTCP -sTCP:LISTEN -Fpcun 2>/dev/null)
}

ports_pid_csv_from_rows() {
    local rows="$1"
    if [[ -z "${rows}" ]]; then
        return 0
    fi
    printf "%s\n" "${rows}" | awk -F'\t' 'NF && !seen[$1]++ {print $1}' | paste -sd, -
}

ports_ps_rows_for_pids() {
    local pid_csv="$1"
    if [[ -z "${pid_csv}" ]]; then
        return 0
    fi

    ps -p "${pid_csv}" -o pid= -o ppid= -o user= -o stat= -o %cpu= -o %mem= -o rss= -o lstart= -o command= 2>/dev/null \
        | awk '{
            pid=$1; ppid=$2; user=$3; stat=$4; cpu=$5; mem=$6; rss=$7;
            uptime=$8" "$9" "$10" "$11" "$12;
            $1=$2=$3=$4=$5=$6=$7=$8=$9=$10=$11=$12="";
            sub(/^[[:space:]]+/, "", $0);
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, user, stat, cpu, mem, rss, uptime, $0
        }'
}

ports_all_process_rows() {
    ps -eo pid= -o ppid= -o user= -o stat= -o %cpu= -o %mem= -o rss= -o lstart= -o command= 2>/dev/null \
        | awk '{
            pid=$1; ppid=$2; user=$3; stat=$4; cpu=$5; mem=$6; rss=$7;
            uptime=$8" "$9" "$10" "$11" "$12;
            $1=$2=$3=$4=$5=$6=$7=$8=$9=$10=$11=$12="";
            sub(/^[[:space:]]+/, "", $0);
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, user, stat, cpu, mem, rss, uptime, $0
        }'
}

ports_cwd_rows_for_pids() {
    local pid_csv="$1"
    local pid=""

    if [[ -z "${pid_csv}" ]]; then
        return 0
    fi

    while IFS= read -r line; do
        case "${line%"${line#?}"}" in
            p)
                pid="${line#?}"
                ;;
            n)
                if [[ -n "${pid}" ]]; then
                    printf "%s\t%s\n" "${pid}" "${line#?}"
                fi
                ;;
        esac
    done < <(lsof -a -d cwd -p "${pid_csv}" -Fpn 2>/dev/null)
}

ports_docker_rows() {
    local docker_rows=""

    if ! ports_docker_available; then
        return 0
    fi

    docker_rows=$(ports_timeout_command 3 docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null || true)
    if [[ -z "${docker_rows}" ]]; then
        return 0
    fi

    PORTS_DOCKER_ROWS="${docker_rows}" python3 - <<'PY'
import os
import re


rows = os.environ.get("PORTS_DOCKER_ROWS", "")
for raw in rows.splitlines():
    if not raw.strip():
        continue
    parts = raw.split("\t", 1)
    name = parts[0].strip()
    ports_blob = parts[1] if len(parts) > 1 else ""
    seen = set()
    for port in re.findall(r":(\d+)->", ports_blob):
        if port in seen:
            continue
        seen.add(port)
        print(f"{port}\t{name}")
PY
}

ports_listening_snapshot_json() {
    local include_all="${1:-0}"
    local lsof_rows=""
    local pid_csv=""
    local ps_rows=""
    local cwd_rows=""
    local docker_rows=""

    lsof_rows=$(ports_listening_rows || true)
    pid_csv=$(ports_pid_csv_from_rows "${lsof_rows}" || true)
    ps_rows=$(ports_ps_rows_for_pids "${pid_csv}" || true)
    cwd_rows=$(ports_cwd_rows_for_pids "${pid_csv}" || true)
    docker_rows=$(ports_docker_rows || true)

    PORTS_INCLUDE_ALL="${include_all}" \
    PORTS_LSOF_ROWS="${lsof_rows}" \
    PORTS_PS_ROWS="${ps_rows}" \
    PORTS_CWD_ROWS="${cwd_rows}" \
    PORTS_DOCKER_ROWS="${docker_rows}" \
    python3 - <<'PY'
import json
import os
import pathlib
import re


def parse_rows(blob, keys):
    rows = []
    for raw in blob.splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) < len(keys):
            parts += [""] * (len(keys) - len(parts))
        rows.append(dict(zip(keys, parts[: len(keys)])))
    return rows


def find_project_root(start_path):
    if not start_path:
        return ""
    path = pathlib.Path(start_path).expanduser()
    if not path.exists():
        return ""
    if path.is_file():
        path = path.parent
    markers = {
        ".git",
        "package.json",
        "go.mod",
        "Cargo.toml",
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "Package.swift",
        "build.zig",
        ".devcontainer",
    }
    current = path
    while True:
        for marker in markers:
            if (current / marker).exists():
                return str(current.resolve())
        if current == current.parent:
            return ""
        current = current.parent


def has_any(path_text, names):
    if not path_text:
        return False
    base = pathlib.Path(path_text)
    for name in names:
        if (base / name).exists():
            return True
    return False


def blob_matches(blob, patterns):
    return any(re.search(pattern, blob) for pattern in patterns)


def detect_framework(command_name, cmdline, cwd, project_root, container_name):
    command_blob = " ".join(
        [command_name or "", cmdline or "", cwd or "", project_root or "", container_name or ""]
    ).lower()

    if blob_matches(command_blob, [r"\bsupabase\b"]):
        return "Supabase"
    if blob_matches(command_blob, [r"\bnext\b", r"\bnext[- ]dev\b"]) or has_any(project_root, ["next.config.js", "next.config.mjs", "next.config.ts"]):
        return "Next.js"
    if blob_matches(command_blob, [r"\bvite\b"]) or has_any(project_root, ["vite.config.js", "vite.config.mjs", "vite.config.ts"]):
        return "Vite"
    if blob_matches(command_blob, [r"\bdjango\b", r"\bmanage\.py runserver\b"]) or has_any(project_root, ["manage.py"]):
        return "Django"
    if blob_matches(command_blob, [r"\bflask\b"]):
        return "Flask"
    if blob_matches(command_blob, [r"\buvicorn\b"]):
        return "Uvicorn"
    if blob_matches(command_blob, [r"\bgunicorn\b"]):
        return "Gunicorn"
    if blob_matches(command_blob, [r"\brails\b", r"\bpuma\b"]) or has_any(project_root, ["config.ru"]):
        return "Rails"
    if blob_matches(command_blob, [r"\bspring\b"]):
        return "Spring"
    if blob_matches(command_blob, [r"\bcaddy\b"]):
        return "Caddy"
    if blob_matches(command_blob, [r"\btraefik\b"]):
        return "Traefik"
    if blob_matches(command_blob, [r"\bturso\b"]):
        return "Turso"
    if blob_matches(command_blob, [r"\bdocker\b", r"\bcontainerd\b"]) or container_name:
        return "Docker"
    if blob_matches(command_blob, [r"\bdeno\b"]):
        return "Deno"
    if blob_matches(command_blob, [r"\bzig\b"]) or has_any(project_root, ["build.zig"]):
        return "Zig"
    if blob_matches(command_blob, [r"\bcargo\b", r"\brustc?\b"]) or has_any(project_root, ["Cargo.toml"]):
        return "Rust"
    if blob_matches(command_blob, [r"\bgo\b"]) or has_any(project_root, ["go.mod"]):
        return "Go"
    if blob_matches(command_blob, [r"\bphp\b"]):
        return "PHP"
    if blob_matches(command_blob, [r"\bpython[0-9.]*\b"]) or has_any(project_root, ["pyproject.toml", "requirements.txt", "setup.py"]):
        return "Python"
    if blob_matches(command_blob, [r"\bbun\b"]) or has_any(project_root, ["bunfig.toml"]):
        return "Bun"
    if blob_matches(command_blob, [r"\bnode\b"]) or has_any(project_root, ["package.json"]):
        return "Node"
    if blob_matches(command_blob, [r"\bjava\b"]):
        return "Java"
    if blob_matches(command_blob, [r"\bruby\b"]):
        return "Ruby"
    return ""


def is_dev_process(command_name, cmdline, framework):
    blob = " ".join([command_name or "", cmdline or "", framework or ""]).lower()
    allow_patterns = [
        r"\bnode\b",
        r"\bpython[0-9.]*\b",
        r"\bruby\b",
        r"\bjava\b",
        r"\bgo\b",
        r"\bcargo\b",
        r"\brustc?\b",
        r"\bbun\b",
        r"\bdeno\b",
        r"\bzig\b",
        r"\bphp\b",
        r"\bdocker\b",
        r"\bsupabase\b",
        r"\bturso\b",
        r"\bcaddy\b",
        r"\btraefik\b",
        r"\buvicorn\b",
        r"\bgunicorn\b",
        r"\bflask\b",
        r"\brails\b",
        r"\bnext\b",
        r"\bvite\b",
        r"\bdjango\b",
        r"\bspring\b",
    ]
    return bool(framework) or blob_matches(blob, allow_patterns)


include_all = os.environ.get("PORTS_INCLUDE_ALL", "0") == "1"
lsof_rows = parse_rows(os.environ.get("PORTS_LSOF_ROWS", ""), ["pid", "command", "user", "port", "bind"])
ps_rows = parse_rows(
    os.environ.get("PORTS_PS_ROWS", ""),
    ["pid", "ppid", "user", "stat", "cpu", "mem", "rss", "startedAt", "cmdline"],
)
cwd_rows = parse_rows(os.environ.get("PORTS_CWD_ROWS", ""), ["pid", "cwd"])
docker_rows = parse_rows(os.environ.get("PORTS_DOCKER_ROWS", ""), ["port", "container"])

ps_map = {row["pid"]: row for row in ps_rows}
cwd_map = {row["pid"]: row["cwd"] for row in cwd_rows}
docker_map = {row["port"]: row["container"] for row in docker_rows}


def parse_started_at(text):
    if not text:
        return None
    try:
        return __import__("datetime").datetime.strptime(text, "%a %b %d %H:%M:%S %Y")
    except Exception:
        return None


def humanize_uptime(text):
    started = parse_started_at(text)
    if started is None:
        return text
    now = __import__("datetime").datetime.now()
    delta = int((now - started).total_seconds())
    if delta < 0:
        delta = 0
    days, rem = divmod(delta, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, seconds = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"

records = []
for row in lsof_rows:
    pid = row["pid"]
    ps_row = ps_map.get(pid, {})
    cwd = cwd_map.get(pid, "")
    project_root = find_project_root(cwd)
    container_name = docker_map.get(row.get("port", ""), "")
    framework = detect_framework(
        row.get("command", ""),
        ps_row.get("cmdline", ""),
        cwd,
        project_root,
        container_name,
    )
    is_dev = is_dev_process(row.get("command", ""), ps_row.get("cmdline", ""), framework)
    if not include_all and not is_dev:
        continue
    records.append(
        {
            "port": row.get("port", ""),
            "pid": pid,
            "ppid": ps_row.get("ppid", ""),
            "command": row.get("command", ""),
            "user": ps_row.get("user", "") or row.get("user", ""),
            "bind": row.get("bind", ""),
            "framework": framework,
            "startedAt": ps_row.get("startedAt", ""),
            "uptime": humanize_uptime(ps_row.get("startedAt", "")),
            "container": container_name,
            "cpu": ps_row.get("cpu", ""),
            "mem": ps_row.get("mem", ""),
            "rss": ps_row.get("rss", ""),
            "stat": ps_row.get("stat", ""),
            "cwd": cwd,
            "projectRoot": project_root,
            "cmdline": ps_row.get("cmdline", ""),
            "isDev": is_dev,
        }
    )

deduped = []
seen_ports = set()
for record in records:
    port = record.get("port", "")
    if not port or port in seen_ports:
        continue
    seen_ports.add(port)
    deduped.append(record)

deduped.sort(key=lambda item: int(item.get("port", "0") or "0"))
print(json.dumps(deduped, indent=2, sort_keys=True))
PY
}

ports_process_list_json() {
    local include_all="${1:-0}"
    local ps_rows=""
    local pid_csv=""
    local cwd_rows=""

    ps_rows=$(ports_all_process_rows || true)
    pid_csv=$(printf "%s\n" "${ps_rows}" | awk -F'\t' 'NF && !seen[$1]++ {print $1}' | paste -sd, -)
    cwd_rows=$(ports_cwd_rows_for_pids "${pid_csv}" || true)

    PORTS_INCLUDE_ALL="${include_all}" \
    PORTS_PS_ROWS="${ps_rows}" \
    PORTS_CWD_ROWS="${cwd_rows}" \
    python3 - <<'PY'
import json
import os
import pathlib
import re


def parse_rows(blob, keys):
    rows = []
    for raw in blob.splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) < len(keys):
            parts += [""] * (len(keys) - len(parts))
        rows.append(dict(zip(keys, parts[: len(keys)])))
    return rows


def has_any(path_text, names):
    if not path_text:
        return False
    base = pathlib.Path(path_text)
    for name in names:
        if (base / name).exists():
            return True
    return False


def blob_matches(blob, patterns):
    return any(re.search(pattern, blob) for pattern in patterns)


def detect_framework(command_name, cmdline, cwd):
    blob = " ".join([command_name or "", cmdline or "", cwd or ""]).lower()
    if blob_matches(blob, [r"\bsupabase\b"]):
        return "Supabase"
    if blob_matches(blob, [r"\bnext\b", r"\bnext[- ]dev\b"]):
        return "Next.js"
    if blob_matches(blob, [r"\bvite\b"]):
        return "Vite"
    if blob_matches(blob, [r"\bdjango\b", r"\bmanage\.py runserver\b"]):
        return "Django"
    if blob_matches(blob, [r"\bflask\b"]):
        return "Flask"
    if blob_matches(blob, [r"\buvicorn\b"]):
        return "Uvicorn"
    if blob_matches(blob, [r"\bgunicorn\b"]):
        return "Gunicorn"
    if blob_matches(blob, [r"\brails\b", r"\bpuma\b"]):
        return "Rails"
    if blob_matches(blob, [r"\bspring\b"]):
        return "Spring"
    if blob_matches(blob, [r"\bcaddy\b"]):
        return "Caddy"
    if blob_matches(blob, [r"\btraefik\b"]):
        return "Traefik"
    if blob_matches(blob, [r"\bturso\b"]):
        return "Turso"
    if blob_matches(blob, [r"\bzig\b"]) or has_any(cwd, ["build.zig"]):
        return "Zig"
    if blob_matches(blob, [r"\bcargo\b", r"\brustc?\b"]) or has_any(cwd, ["Cargo.toml"]):
        return "Rust"
    if blob_matches(blob, [r"\bgo\b"]) or has_any(cwd, ["go.mod"]):
        return "Go"
    if blob_matches(blob, [r"\bphp\b"]):
        return "PHP"
    if blob_matches(blob, [r"\bpython[0-9.]*\b"]) or has_any(cwd, ["pyproject.toml", "requirements.txt", "setup.py"]):
        return "Python"
    if blob_matches(blob, [r"\bbun\b"]) or has_any(cwd, ["bunfig.toml"]):
        return "Bun"
    if blob_matches(blob, [r"\bdeno\b"]):
        return "Deno"
    if blob_matches(blob, [r"\bnode\b"]) or has_any(cwd, ["package.json"]):
        return "Node"
    if blob_matches(blob, [r"\bjava\b"]):
        return "Java"
    if blob_matches(blob, [r"\bruby\b"]):
        return "Ruby"
    return ""


def is_dev_process(command_name, cmdline, framework):
    blob = " ".join([command_name or "", cmdline or "", framework or ""]).lower()
    allow_patterns = [
        r"\bnode\b",
        r"\bpython[0-9.]*\b",
        r"\bruby\b",
        r"\bjava\b",
        r"\bgo\b",
        r"\bcargo\b",
        r"\brustc?\b",
        r"\bbun\b",
        r"\bdeno\b",
        r"\bzig\b",
        r"\bphp\b",
        r"\bdocker\b",
        r"\bsupabase\b",
        r"\bturso\b",
        r"\bcaddy\b",
        r"\btraefik\b",
        r"\buvicorn\b",
        r"\bgunicorn\b",
        r"\bflask\b",
        r"\brails\b",
        r"\bnext\b",
        r"\bvite\b",
        r"\bdjango\b",
        r"\bspring\b",
    ]
    return bool(framework) or blob_matches(blob, allow_patterns)


include_all = os.environ.get("PORTS_INCLUDE_ALL", "0") == "1"
ps_rows = parse_rows(
    os.environ.get("PORTS_PS_ROWS", ""),
    ["pid", "ppid", "user", "stat", "cpu", "mem", "rss", "startedAt", "cmdline"],
)
cwd_rows = parse_rows(os.environ.get("PORTS_CWD_ROWS", ""), ["pid", "cwd"])
cwd_map = {row["pid"]: row["cwd"] for row in cwd_rows}


def parse_started_at(text):
    if not text:
        return None
    try:
        return __import__("datetime").datetime.strptime(text, "%a %b %d %H:%M:%S %Y")
    except Exception:
        return None


def humanize_uptime(text):
    started = parse_started_at(text)
    if started is None:
        return text
    now = __import__("datetime").datetime.now()
    delta = int((now - started).total_seconds())
    if delta < 0:
        delta = 0
    days, rem = divmod(delta, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, seconds = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {seconds}s"
    return f"{seconds}s"

rows = []
docker_group = {
    "count": 0,
    "cpu": 0.0,
    "mem": 0.0,
    "rss": 0,
    "startedAt": "",
    "pids": [],
}

for row in ps_rows:
    cmdline = row.get("cmdline", "")
    command_name = pathlib.Path((cmdline.split() or [""])[0]).name
    framework = detect_framework(command_name, cmdline, cwd_map.get(row["pid"], ""))
    is_dev = is_dev_process(command_name, cmdline, framework)
    if not include_all and not is_dev:
        continue
    lower = " ".join([command_name, cmdline]).lower()
    if "docker" in lower or "containerd" in lower or "com.docker" in lower:
        docker_group["count"] += 1
        docker_group["cpu"] += float(row.get("cpu", "0") or "0")
        docker_group["mem"] += float(row.get("mem", "0") or "0")
        docker_group["rss"] += int(row.get("rss", "0") or "0")
        docker_group["startedAt"] = docker_group["startedAt"] or row.get("startedAt", "")
        docker_group["pids"].append(row["pid"])
        continue
    rows.append(
        {
            "pid": row.get("pid", ""),
            "ppid": row.get("ppid", ""),
            "user": row.get("user", ""),
            "stat": row.get("stat", ""),
            "cpu": row.get("cpu", ""),
            "mem": row.get("mem", ""),
            "rss": row.get("rss", ""),
            "startedAt": row.get("startedAt", ""),
            "uptime": humanize_uptime(row.get("startedAt", "")),
            "command": command_name,
            "framework": framework,
            "cmdline": cmdline,
            "cwd": cwd_map.get(row["pid"], ""),
        }
    )

if docker_group["count"]:
    rows.append(
        {
            "pid": ",".join(docker_group["pids"]),
            "ppid": "",
            "user": "",
            "stat": "",
            "cpu": f"{docker_group['cpu']:.1f}",
            "mem": f"{docker_group['mem']:.1f}",
            "rss": str(docker_group["rss"]),
            "startedAt": docker_group["startedAt"],
            "uptime": humanize_uptime(docker_group["startedAt"]),
            "command": "docker",
            "framework": "Docker",
            "cmdline": f"{docker_group['count']} docker runtime processes",
            "cwd": "",
        }
    )

rows.sort(key=lambda item: item.get("command", ""))
print(json.dumps(rows, indent=2, sort_keys=True))
PY
}

ports_clean_candidates_json() {
    local include_all="${1:-0}"
    local payload=""

    payload=$(ports_listening_snapshot_json "${include_all}")
    PORTS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

rows = json.loads(os.environ.get("PORTS_PAYLOAD", "[]") or "[]")
candidates = []
for row in rows:
    reasons = []
    if row.get("ppid") == "1" and row.get("isDev"):
        reasons.append("orphan")
    if "Z" in (row.get("stat") or ""):
        reasons.append("zombie")
    if reasons:
        item = dict(row)
        item["reasons"] = reasons
        candidates.append(item)

print(json.dumps(
    {
        "candidates": candidates,
        "orphanCount": sum(1 for row in candidates if "orphan" in row.get("reasons", [])),
        "zombieCount": sum(1 for row in candidates if "zombie" in row.get("reasons", [])),
    },
    indent=2,
    sort_keys=True,
))
PY
}

ports_render_table_from_json() {
    local payload="$1"
    PORTS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

rows = json.loads(os.environ.get("PORTS_PAYLOAD", "[]") or "[]")
print(f"{'COMMAND':<18} {'PID':<8} {'PORT':<8} {'FRAMEWORK':<12} {'UPTIME':<24} {'CONTAINER':<18} BIND")
for row in rows:
    uptime = (row.get("uptime", "") or "")[:24]
    container = (row.get("container", "") or "-")[:18]
    framework = (row.get("framework", "") or "-")[:12]
    bind = row.get("bind", "") or "-"
    print(
        f"{(row.get('command', '') or '-')[:18]:<18} "
        f"{(row.get('pid', '') or '-')[:8]:<8} "
        f"{(row.get('port', '') or '-')[:8]:<8} "
        f"{framework:<12} "
        f"{uptime:<24} "
        f"{container:<18} "
        f"{bind}"
    )
PY
}

ports_render_process_table_from_json() {
    local payload="$1"
    PORTS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

rows = json.loads(os.environ.get("PORTS_PAYLOAD", "[]") or "[]")
print(f"{'COMMAND':<18} {'PID':<12} {'CPU':>6} {'MEM':>6} {'RSS':>8} {'FRAMEWORK':<12} UPTIME")
for row in rows:
    print(
        f"{(row.get('command', '') or '-')[:18]:<18} "
        f"{(row.get('pid', '') or '-')[:12]:<12} "
        f"{(row.get('cpu', '') or '0'):>6} "
        f"{(row.get('mem', '') or '0'):>6} "
        f"{(row.get('rss', '') or '0'):>8} "
        f"{(row.get('framework', '') or '-')[:12]:<12} "
        f"{(row.get('uptime', '') or '-')}"
    )
PY
}

ports_render_clean_table_from_json() {
    local payload="$1"
    PORTS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
rows = payload.get("candidates", [])
print(f"{'COMMAND':<18} {'PID':<8} {'PORT':<8} {'REASONS':<16} BIND")
for row in rows:
    reasons = ",".join(row.get("reasons", [])) or "-"
    print(
        f"{(row.get('command', '') or '-')[:18]:<18} "
        f"{(row.get('pid', '') or '-')[:8]:<8} "
        f"{(row.get('port', '') or '-')[:8]:<8} "
        f"{reasons[:16]:<16} "
        f"{(row.get('bind', '') or '-')}"
    )
PY
}

ports_entry_json_for_port() {
    local payload="$1"
    local port="$2"

    PORTS_PAYLOAD="${payload}" PORTS_TARGET_PORT="${port}" python3 - <<'PY'
import json
import os
import sys

rows = json.loads(os.environ.get("PORTS_PAYLOAD", "[]") or "[]")
target = os.environ.get("PORTS_TARGET_PORT", "")
for row in rows:
    if str(row.get("port", "")) == target:
        print(json.dumps(row, indent=2, sort_keys=True))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ports_json_field() {
    local payload="$1"
    local field_name="$2"

    PORTS_PAYLOAD="${payload}" PORTS_FIELD_NAME="${field_name}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
value = payload
for segment in os.environ.get("PORTS_FIELD_NAME", "").split("."):
    if not segment:
        continue
    if isinstance(value, dict):
        value = value.get(segment, "")
    else:
        value = ""
        break
if value is None:
    value = ""
if isinstance(value, bool):
    print("yes" if value else "no")
else:
    print(value)
PY
}

ports_detail_json_with_branch() {
    local payload="$1"
    local git_branch="$2"

    PORTS_PAYLOAD="${payload}" PORTS_GIT_BRANCH="${git_branch}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
payload["gitBranch"] = os.environ.get("PORTS_GIT_BRANCH", "")
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

ports_git_branch_for_root() {
    local root="$1"
    local branch=""

    if [[ -z "${root}" ]] || [[ ! -d "${root}" ]]; then
        return 0
    fi

    branch=$(git -C "${root}" symbolic-ref --quiet --short HEAD 2>/dev/null | head -n 1 | tr -d '\r')
    if [[ -z "${branch}" ]]; then
        branch=$(git -C "${root}" branch --show-current 2>/dev/null | head -n 1 | tr -d '\r')
    fi
    if [[ -n "${branch}" && "${branch}" != "HEAD" ]]; then
        printf "%s\n" "${branch}"
    fi
}

ports_render_detail_from_json() {
    local payload="$1"
    local git_branch="$2"
    local port=""
    local pid=""
    local command_name=""
    local user_name=""
    local framework=""
    local container_name=""
    local started_at=""
    local uptime=""
    local cpu=""
    local mem=""
    local rss=""
    local cwd=""
    local project_root=""
    local bind=""
    local cmdline=""

    port=$(ports_json_field "${payload}" "port")
    pid=$(ports_json_field "${payload}" "pid")
    command_name=$(ports_json_field "${payload}" "command")
    user_name=$(ports_json_field "${payload}" "user")
    framework=$(ports_json_field "${payload}" "framework")
    container_name=$(ports_json_field "${payload}" "container")
    started_at=$(ports_json_field "${payload}" "startedAt")
    uptime=$(ports_json_field "${payload}" "uptime")
    cpu=$(ports_json_field "${payload}" "cpu")
    mem=$(ports_json_field "${payload}" "mem")
    rss=$(ports_json_field "${payload}" "rss")
    cwd=$(ports_json_field "${payload}" "cwd")
    project_root=$(ports_json_field "${payload}" "projectRoot")
    bind=$(ports_json_field "${payload}" "bind")
    cmdline=$(ports_json_field "${payload}" "cmdline")

    yen_header "Port ${port}"
    printf "Command:      %s\n" "${command_name}"
    printf "PID:          %s\n" "${pid}"
    printf "User:         %s\n" "${user_name:-unknown}"
    printf "Framework:    %s\n" "${framework:-unknown}"
    printf "Container:    %s\n" "${container_name:-none}"
    printf "CPU:          %s%%\n" "${cpu:-0}"
    printf "Memory:       %s%%\n" "${mem:-0}"
    printf "RSS:          %s KB\n" "${rss:-0}"
    printf "Started:      %s\n" "${started_at:-unknown}"
    printf "Uptime:       %s\n" "${uptime:-unknown}"
    printf "Bind:         %s\n" "${bind}"
    printf "CWD:          %s\n" "${cwd:-unknown}"
    printf "Project root: %s\n" "${project_root:-unknown}"
    if [[ -n "${git_branch}" ]]; then
        printf "Git branch:   %s\n" "${git_branch}"
    fi
    printf "Command line: %s\n" "${cmdline:-unknown}"
    printf "\n"
}

ports_pid_state() {
    local pid="$1"
    local ps_bin="/bin/ps"
    if [[ -z "${pid}" ]] || [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    if [[ ! -x "${ps_bin}" ]]; then
        ps_bin=$(command -v ps 2>/dev/null || true)
    fi
    if [[ -z "${ps_bin}" ]]; then
        return 0
    fi
    "${ps_bin}" -p "${pid}" -o stat= 2>/dev/null | tr -d ' ' | head -n 1
}

ports_wait_for_pid_exit() {
    local pid="$1"
    local attempts="0"
    local state=""

    while [[ "${attempts}" -lt 10 ]]; do
        if ! is_pid_running "${pid}"; then
            return 0
        fi
        state=$(ports_pid_state "${pid}")
        if [[ "${state}" == *Z* ]]; then
            return 0
        fi
        sleep 0.2
        attempts=$((attempts + 1))
    done

    return 1
}

ports_terminate_pid() {
    local pid="$1"
    local port="$2"
    local root="$3"
    local silent="${4:-0}"

    ports_emit_status() {
        local level="$1"
        local message="$2"
        if [[ "${silent}" == "1" ]]; then
            printf "%s\n" "${message}" >&2
            return 0
        fi
        case "${level}" in
            success)
                yen_success "${message}"
                ;;
            error)
                yen_error "${message}"
                ;;
            info)
                yen_info "${message}"
                ;;
        esac
    }

    if [[ -z "${pid}" ]] || [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
        ports_emit_status error "Invalid PID '${pid}'."
        return 1
    fi

    if ! is_pid_running "${pid}"; then
        ports_emit_status info "PID ${pid} is no longer running."
        return 0
    fi

    if ! kill -TERM "${pid}" 2>/dev/null; then
        ports_emit_status error "Failed to send SIGTERM to PID ${pid}."
        ports_emit_status info "Try: sudo kill -9 ${pid}"
        return 1
    fi

    if ! ports_wait_for_pid_exit "${pid}"; then
        ports_emit_status error "PID ${pid} did not exit after SIGTERM."
        ports_emit_status info "Try: sudo kill -9 ${pid}"
        return 1
    fi

    timeline_log "ports-kill" "${root}" "terminated" "pid=${pid};port=${port};signal=SIGTERM"
    ports_emit_status success "Terminated PID ${pid} on port ${port}."
    return 0
}

ports_watch_loop() {
    local include_all="${1:-0}"
    local json_mode="${2:-0}"
    local state_file=""
    local snapshot=""
    local previous=""
    local changes=""
    local counter="0"

    state_file=$(mktemp "${TMPDIR:-/tmp}/yen-ports-watch.XXXXXX")

    ports_watch_cleanup() {
        rm -f "${state_file}"
    }

    trap 'ports_watch_cleanup; exit' INT TERM HUP

    if [[ "${json_mode}" != "1" ]]; then
        yen_header "Ports Watch"
        printf "Polling every 2 seconds. Press Ctrl+C to stop.\n\n"
    fi

    : > "${state_file}"
    while true; do
        snapshot=$(ports_listening_snapshot_json "${include_all}")
        previous=$(cat "${state_file}" 2>/dev/null || true)
        if [[ -n "${previous}" ]]; then
            changes=$(PORTS_PREVIOUS="${previous}" PORTS_CURRENT="${snapshot}" PORTS_JSON_MODE="${json_mode}" PORTS_ITERATION="${counter}" python3 - <<'PY'
import json
import os

previous = json.loads(os.environ.get("PORTS_PREVIOUS", "[]") or "[]")
current = json.loads(os.environ.get("PORTS_CURRENT", "[]") or "[]")
json_mode = os.environ.get("PORTS_JSON_MODE", "0") == "1"
iteration = int(os.environ.get("PORTS_ITERATION", "0") or "0")

prev_map = {str(row.get("port", "")): row for row in previous}
curr_map = {str(row.get("port", "")): row for row in current}

opened = [curr_map[port] for port in sorted(curr_map.keys()) if port and port not in prev_map]
closed = [prev_map[port] for port in sorted(prev_map.keys()) if port and port not in curr_map]

if json_mode:
    if opened or closed:
        print(json.dumps({
            "iteration": iteration,
            "opened": opened,
            "closed": closed,
        }, sort_keys=True))
else:
    for row in opened:
        print(f"OPEN\t{row.get('port', '')}\t{row.get('command', '')}\t{row.get('framework', '')}")
    for row in closed:
        print(f"CLOSE\t{row.get('port', '')}\t{row.get('command', '')}\t{row.get('framework', '')}")
PY
)
            if [[ -n "${changes}" ]]; then
                if [[ "${json_mode}" == "1" ]]; then
                    printf "%s\n" "${changes}"
                else
                    while IFS=$'\t' read -r kind port command_name framework; do
                        [[ -z "${kind}" ]] && continue
                        printf "%s  %s  port=%s  command=%s  framework=%s\n" "$(iso_now)" "${kind}" "${port}" "${command_name:-unknown}" "${framework:-unknown}"
                    done <<EOF
${changes}
EOF
                fi
            fi
        fi
        printf "%s" "${snapshot}" > "${state_file}"
        counter=$((counter + 1))
        sleep 2
    done
}

cmd_ports() {
    local include_all="0"
    local json_mode="0"
    local assume_yes="0"
    local subcommand="table"
    local target_port=""
    local snapshot=""
    local entry_json=""
    local git_branch=""
    local pid=""
    local root=""
    local answer=""
    local clean_payload=""
    local candidate_pids=""
    local terminated_pids=""
    local failed_pids=""

    if ! command -v lsof >/dev/null 2>&1; then
        yen_error "lsof is required for port inspection."
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all|-a)
                include_all="1"
                ;;
            --json)
                json_mode="1"
                ;;
            --yes|-y)
                assume_yes="1"
                ;;
            help|--help|-h)
                subcommand="help"
                ;;
            ps|clean|watch)
                if [[ -n "${target_port}" || "${subcommand}" != "table" ]]; then
                    yen_error "ports accepts only one subcommand at a time."
                    exit 1
                fi
                subcommand="$1"
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    if [[ -n "${target_port}" || "${subcommand}" != "table" ]]; then
                        yen_error "ports accepts only one port target."
                        exit 1
                    fi
                    target_port="$1"
                    subcommand="detail"
                else
                    yen_error "Unknown ports option/arg: $1"
                    exit 1
                fi
                ;;
        esac
        shift
    done

    case "${subcommand}" in
        help)
            ports_help
            ;;
        table)
            snapshot=$(ports_listening_snapshot_json "${include_all}")
            if [[ "${json_mode}" == "1" ]]; then
                printf "%s\n" "${snapshot}"
                return 0
            fi
            yen_header "Listening Ports"
            if [[ "${snapshot}" == "[]" ]]; then
                yen_info "No listening dev ports found."
            else
                ports_render_table_from_json "${snapshot}"
            fi
            printf "\n"
            ;;
        detail)
            snapshot=$(ports_listening_snapshot_json "${include_all}")
            if ! entry_json=$(ports_entry_json_for_port "${snapshot}" "${target_port}" 2>/dev/null); then
                yen_error "No listening process found on port ${target_port}."
                exit 1
            fi

            root=$(ports_json_field "${entry_json}" "projectRoot")
            if [[ -z "${root}" ]]; then
                root=$(find_project_root "${PWD}")
            fi
            git_branch=$(ports_git_branch_for_root "${root}")

            if [[ "${json_mode}" != "1" ]]; then
                ports_render_detail_from_json "${entry_json}" "${git_branch}"
            fi

            pid=$(ports_json_field "${entry_json}" "pid")
            if [[ "${json_mode}" == "1" && "${assume_yes}" != "1" ]]; then
                ports_detail_json_with_branch "${entry_json}" "${git_branch}"
                return 0
            fi
            if [[ "${assume_yes}" == "1" ]]; then
                if ports_terminate_pid "${pid}" "${target_port}" "${root}" "${json_mode}"; then
                    if [[ "${json_mode}" == "1" ]]; then
                        PORTS_PAYLOAD="$(ports_detail_json_with_branch "${entry_json}" "${git_branch}")" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
payload["killAttempted"] = True
payload["killStatus"] = "terminated"
print(json.dumps(payload, indent=2, sort_keys=True))
PY
                    fi
                else
                    if [[ "${json_mode}" == "1" ]]; then
                        PORTS_PAYLOAD="$(ports_detail_json_with_branch "${entry_json}" "${git_branch}")" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
payload["killAttempted"] = True
payload["killStatus"] = "failed"
print(json.dumps(payload, indent=2, sort_keys=True))
PY
                    fi
                    exit 1
                fi
            elif [[ -t 0 ]]; then
                yen_prompt "Terminate PID ${pid} on port ${target_port}? [y/N]" answer
                case "${answer}" in
                    y|Y|yes|YES)
                        ports_terminate_pid "${pid}" "${target_port}" "${root}" || exit 1
                        ;;
                    *)
                        ;;
                esac
            else
                yen_info "Re-run with --yes to terminate this process non-interactively."
            fi
            ;;
        ps)
            snapshot=$(ports_process_list_json "${include_all}")
            if [[ "${json_mode}" == "1" ]]; then
                printf "%s\n" "${snapshot}"
                return 0
            fi
            yen_header "IDE Port Processes"
            if [[ "${snapshot}" == "[]" ]]; then
                yen_info "No matching processes found."
            else
                ports_render_process_table_from_json "${snapshot}"
            fi
            printf "\n"
            ;;
        clean)
            clean_payload=$(ports_clean_candidates_json "${include_all}")
            if [[ "${json_mode}" != "1" ]]; then
                yen_header "Port Cleanup Candidates"
                if [[ "$(ports_json_field "${clean_payload}" "candidates")" == "[]" ]]; then
                    yen_info "No orphaned or zombie listening processes found."
                    printf "\n"
                    return 0
                fi
                ports_render_clean_table_from_json "${clean_payload}"
                printf "\n"
            elif [[ "${assume_yes}" != "1" ]]; then
                printf "%s\n" "${clean_payload}"
            fi

            candidate_pids=$(PORTS_PAYLOAD="${clean_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
for row in payload.get("candidates", []):
    pid = row.get("pid", "")
    port = row.get("port", "")
    if pid:
        print(f"{pid}\t{port}")
PY
)

            if [[ -z "${candidate_pids}" ]]; then
                if [[ "${json_mode}" == "1" && "${assume_yes}" == "1" ]]; then
                    printf "%s\n" "${clean_payload}"
                fi
                return 0
            fi

            if [[ "${assume_yes}" != "1" ]]; then
                if [[ -t 0 ]]; then
                    yen_prompt "Terminate all cleanup candidates? [y/N]" answer
                    case "${answer}" in
                        y|Y|yes|YES)
                            ;;
                        *)
                            return 0
                            ;;
                    esac
                else
                    if [[ "${json_mode}" != "1" ]]; then
                        yen_info "Re-run with --yes to terminate cleanup candidates non-interactively."
                    fi
                    return 0
                fi
            fi

            root=$(find_project_root "${PWD}")
            while IFS=$'\t' read -r pid target_port; do
                [[ -z "${pid}" ]] && continue
                if ports_terminate_pid "${pid}" "${target_port}" "${root}" "${json_mode}"; then
                    terminated_pids="${terminated_pids}${pid}"$'\n'
                else
                    failed_pids="${failed_pids}${pid}"$'\n'
                fi
            done <<EOF
${candidate_pids}
EOF
            timeline_log "ports-clean" "${root}" "completed" "count=$(printf "%s\n" "${candidate_pids}" | grep -c . 2>/dev/null || printf '0')"
            if [[ "${json_mode}" == "1" ]]; then
                PORTS_PAYLOAD="${clean_payload}" PORTS_TERMINATED="${terminated_pids}" PORTS_FAILED="${failed_pids}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PORTS_PAYLOAD", "{}") or "{}")
payload["killAttempted"] = True
payload["terminatedPids"] = [line for line in os.environ.get("PORTS_TERMINATED", "").splitlines() if line]
payload["failedPids"] = [line for line in os.environ.get("PORTS_FAILED", "").splitlines() if line]
print(json.dumps(payload, indent=2, sort_keys=True))
PY
            fi
            ;;
        watch)
            ports_watch_loop "${include_all}" "${json_mode}"
            ;;
        *)
            yen_error "Unknown ports subcommand: ${subcommand}"
            exit 1
            ;;
    esac
}

extract_semantic_reference_tokens() {
    sed -E 's/\(([^)]*)\)/ \1 /g' \
        | grep -Eo '([A-Za-z0-9_./~:-]+\.[A-Za-z0-9_+-]+:[0-9]+(:[0-9]+)?)' \
        | grep -v '://' \
        | sort -u || true
}

emit_semantic_reference_rows() {
    local project_root="$1"
    local working_dir="$2"

    python3 -c "$(cat <<'PY'
import pathlib
import sys

project_root = pathlib.Path(sys.argv[1]).expanduser().resolve()
working_dir = pathlib.Path(sys.argv[2]).expanduser().resolve()

def parse_ref(ref: str):
    parts = ref.rsplit(":", 2)
    if len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        return parts[0], int(parts[1]), int(parts[2])
    parts = ref.rsplit(":", 1)
    if len(parts) == 2 and parts[1].isdigit():
        return parts[0], int(parts[1]), 1
    return None

def normalize_path(raw_path: str):
    raw = raw_path.strip()
    expanded = pathlib.Path(raw).expanduser()
    candidates = []
    if expanded.is_absolute():
        candidates.append(expanded)
    else:
        candidates.append(working_dir / expanded)
        if project_root != working_dir:
            candidates.append(project_root / expanded)

    chosen = None
    found = False
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except Exception:
            resolved = candidate
        if candidate.exists() or resolved.exists():
            chosen = resolved
            found = True
            break

    if chosen is None:
        fallback = candidates[0] if candidates else expanded
        try:
            chosen = fallback.resolve()
        except Exception:
            chosen = fallback

    try:
        relative = chosen.relative_to(project_root)
        path_text = str(relative)
    except ValueError:
        path_text = raw or str(chosen)

    return found, path_text or ".", str(chosen)

seen = set()
for raw_ref in sys.stdin:
    ref = raw_ref.strip()
    if not ref:
        continue
    parsed = parse_ref(ref)
    if parsed is None:
        continue
    raw_path, line, col = parsed
    found, path_text, absolute_path = normalize_path(raw_path)
    location = f"{path_text}:{line}:{col}"
    key = (path_text, line, col, absolute_path)
    if key in seen:
        continue
    seen.add(key)
    print("\t".join([
        "yes" if found else "no",
        path_text,
        str(line),
        str(col),
        absolute_path,
        location,
    ]))
PY
)" "${project_root}" "${working_dir}"
}

append_semantic_reference_report() {
    local report_file="$1"
    local project_root="$2"
    local working_dir="$3"
    local prefix="$4"
    local output="$5"
    local refs=""
    local rows=""

    refs=$(printf "%s\n" "${output}" | extract_semantic_reference_tokens)
    [[ -n "${refs}" ]] || return 0

    rows=$(printf "%s\n" "${refs}" | emit_semantic_reference_rows "${project_root}" "${working_dir}")
    [[ -n "${rows}" ]] || return 0

    while IFS= read -r row; do
        [[ -n "${row}" ]] || continue
        printf "%s\t%s\n" "${prefix}" "${row}" >> "${report_file}"
    done << EOF
${rows}
EOF
}

emit_symbol_index_rows() {
    local root="$1"
    python3 - "${root}" <<'PY'
import os
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).expanduser().resolve()
ignored = {
    ".git",
    ".next",
    ".nuxt",
    ".swiftpm",
    ".turbo",
    ".venv",
    ".vercel",
    ".yarn",
    "DerivedData",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "ghostty",
    "node_modules",
    "Pods",
    "target",
    "vendor",
    "venv",
    "zig-cache",
    "zig-out",
}
patterns = {
    ".py": [
        ("class", re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("function", re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)")),
    ],
    ".ts": [
        ("function", re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("class", re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("interface", re.compile(r"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("type", re.compile(r"^\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("enum", re.compile(r"^\s*(?:export\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")),
    ],
    ".tsx": [
        ("function", re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("class", re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("interface", re.compile(r"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("type", re.compile(r"^\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("enum", re.compile(r"^\s*(?:export\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")),
    ],
    ".js": [
        ("function", re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("class", re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")),
    ],
    ".jsx": [
        ("function", re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("class", re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=")),
    ],
    ".go": [
        ("function", re.compile(r"^\s*func(?:\s+\([^)]*\))?\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("type", re.compile(r"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("constant", re.compile(r"^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)")),
    ],
    ".swift": [
        ("class", re.compile(r"^\s*(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("struct", re.compile(r"^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("enum", re.compile(r"^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("protocol", re.compile(r"^\s*protocol\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("actor", re.compile(r"^\s*actor\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("typealias", re.compile(r"^\s*typealias\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("function", re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("variable", re.compile(r"^\s*(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)")),
    ],
}
seen = set()
rows = []

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted([name for name in dirnames if name not in ignored])
    for filename in sorted(filenames):
        path = pathlib.Path(dirpath) / filename
        file_patterns = patterns.get(path.suffix.lower())
        if not file_patterns:
            continue
        try:
            relative = path.resolve().relative_to(root).as_posix()
            contents = path.read_text(encoding="utf-8")
        except Exception:
            continue
        for line_number, raw_line in enumerate(contents.splitlines(), start=1):
            for kind, pattern in file_patterns:
                match = pattern.search(raw_line)
                if not match:
                    continue
                symbol = match.group(1)
                column = raw_line.find(symbol) + 1
                location = f"{relative}:{line_number}:{column}"
                key = (symbol, kind, location)
                if key in seen:
                    continue
                seen.add(key)
                rows.append((symbol, kind, relative, line_number, column, location))
                break

rows.sort(key=lambda item: (item[0].lower(), item[2], item[3], item[4]))
for row in rows:
    print("\t".join([str(value) for value in row]))
PY
}

cmd_parse() {
    local input_file=""
    local format="text"
    local root
    local refs
    local rows

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-}"
                if [[ -z "${format}" ]]; then
                    yen_error "parse --format requires text or tsv."
                    exit 1
                fi
                ;;
            -*)
                yen_error "Unknown parse option: $1"
                exit 1
                ;;
            *)
                if [[ -n "${input_file}" ]]; then
                    yen_error "parse accepts at most one input file."
                    exit 1
                fi
                input_file="$1"
                ;;
        esac
        shift
    done

    case "${format}" in
        text|tsv)
            ;;
        *)
            yen_error "Unknown parse format: ${format} (expected text|tsv)"
            exit 1
            ;;
    esac

    root=$(find_project_root "${PWD}")
    if [[ -n "${input_file}" ]]; then
        if [[ ! -f "${input_file}" ]]; then
            yen_error "parse input file not found: ${input_file}"
            exit 1
        fi
        refs=$(extract_semantic_reference_tokens < "${input_file}")
    else
        refs=$(extract_semantic_reference_tokens)
    fi

    if [[ -z "${refs}" ]]; then
        if [[ "${format}" == "text" ]]; then
            yen_info "No file:line references found."
        fi
        return 0
    fi

    rows=$(printf "%s\n" "${refs}" | emit_semantic_reference_rows "${root}" "${PWD}")

    if [[ "${format}" == "tsv" ]]; then
        printf "%s\n" "${rows}"
        return 0
    fi

    echo ""
    yen_header "Parsed References"
    printf "%-6s %-50s %-7s %-7s %-60s %s\n" "FOUND" "FILE" "LINE" "COL" "ABSOLUTE_PATH" "LOCATION"
    while IFS=$'\t' read -r found path line col abs location; do
        [[ -n "${path}" ]] || continue
        printf "%-6s %-50s %-7s %-7s %-60s %s\n" "${found}" "${path}" "${line}" "${col}" "${abs}" "${location}"
    done << EOF
${rows}
EOF
    echo ""
}

search_source_rank() {
    local source="$1"
    case "${source}" in
        action)
            echo "1"
            ;;
        symbol)
            echo "2"
            ;;
        file)
            echo "3"
            ;;
        content)
            echo "4"
            ;;
        diagnostic|diagnostics)
            echo "5"
            ;;
        history)
            echo "6"
            ;;
        *)
            echo "9"
            ;;
    esac
}

search_source_weight() {
    local source="$1"
    case "${source}" in
        action)
            echo "80"
            ;;
        symbol)
            echo "75"
            ;;
        file)
            echo "70"
            ;;
        history)
            echo "60"
            ;;
        diagnostic|diagnostics)
            echo "65"
            ;;
        content)
            echo "50"
            ;;
        *)
            echo "0"
            ;;
    esac
}

search_match_score() {
    local query_lc="$1"
    local raw_text="$2"
    local text_lc
    text_lc=$(printf "%s" "${raw_text}" | tr '[:upper:]' '[:lower:]')
    if [[ -z "${text_lc}" ]]; then
        echo "0"
        return 0
    fi
    if [[ "${text_lc}" == "${query_lc}" ]]; then
        echo "220"
        return 0
    fi
    if [[ "${text_lc}" == "${query_lc}"* ]]; then
        echo "170"
        return 0
    fi
    if [[ "${text_lc}" == *"${query_lc}"* ]]; then
        echo "110"
        return 0
    fi
    echo "0"
}

search_clip_text() {
    local raw="$1"
    local max_len="${2:-120}"
    local sanitized
    sanitized=$(printf "%s" "${raw}" | tr '\t\r\n' '   ')
    if [[ "${#sanitized}" -le "${max_len}" ]]; then
        printf "%s\n" "${sanitized}"
        return 0
    fi
    printf "%s...\n" "$(printf "%s" "${sanitized}" | cut -c1-$((max_len - 3)))"
}

append_search_result() {
    local out_file="$1"
    local score="$2"
    local source="$3"
    local target="$4"
    local preview="$5"
    local source_rank
    source_rank=$(search_source_rank "${source}")
    target=$(printf "%s" "${target}" | tr '\t\r\n' '   ')
    preview=$(printf "%s" "${preview}" | tr '\t\r\n' '   ')
    printf "%s\t%s\t%s\t%s\t%s\n" "${score}" "${source_rank}" "${source}" "${target}" "${preview}" >> "${out_file}"
}

ide_action_catalog() {
    cat << 'EOF'
yen ide detect	project,context
yen ide doctor	repo,health,doctor,toolchain,workspace
yen ide trust status	trust,safety,workspace,audit,consent
yen ide env status	env,context
yen ide lsp status	lsp,language,diagnostics,trust
yen ide lsp diagnostics	lsp,language,diagnostics,error,warning
yen ide lsp hover src/app.ts:12:3	lsp,language,hover
yen ide lsp definition src/app.ts:12:3	lsp,language,definition
yen ide lsp references src/app.ts:12:3	lsp,language,references
yen ide lsp install status	lsp,language,install
yen ide ast status	ast,language,syntax
yen ide share status	share,collaboration,session,trust
yen ide share host --read-only	share,collaboration,pairing,read-only
yen ide share revoke	share,collaboration,revoke,safety
yen ide devcontainer status	devcontainer,container,workspace
yen ide vscode inventory	vscode,migration,workspace
yen ide history --limit 20	history,context
yen ide format status	format,formatter,quality
yen ide format run --dry-run --changed	format,formatter,preview,quality
yen ide lint status	lint,quality,verify
yen ide lint run --dry-run --changed	lint,preview,quality
yen ide fix status	fix,quality,formatter
yen ide fix run --dry-run --changed	fix,preview,quality
yen ide test status	test,runner,verify
yen ide test run --failed	test,runner,rerun
yen ide verify status	verify,security,readiness
yen ide merge-readiness	merge,readiness,review,verify,gate
yen ide benchmark status	benchmark,performance,reliability,slo
yen ide open	path,location,editor,handoff,goto
yen ide debug status	debug,debugger,breakpoint,trust,local
yen ide debug tui	debug,debugger,tui,session
yen ide debug start path/to/file.py:12	debug,debugger,breakpoint,launch
yen ide verify --quick --no-security	verify,node,go,rust,python,swift,zig,make
yen ide gate --dry-run -- echo ok	gate,policy,safety
yen ide workflow run quick-check --dry-run	workflow,automation,safety
yen ide pr-review <number> --loop	pr,review,git
yen ide timeline --limit 20	history,audit
yen ide non-interference status	slo,safety
yen agents list	agents,orchestration
yen agents open codex --dry-run	agents,orchestration
EOF
}

cmd_search() {
    local query=""
    local target=""
    local limit="40"
    local sources_csv="files,symbols,content,diagnostics,history,actions"
    local include_files="0"
    local include_symbols="0"
    local include_content="0"
    local include_diagnostics="0"
    local include_history="0"
    local include_actions="0"
    local root=""
    local query_lc=""
    local results_file=""
    local runtime=""
    local tooling=""
    local context_blob=""
    local line=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)
                shift
                limit="${1:-40}"
                ;;
            --sources)
                shift
                sources_csv="${1:-files,symbols,content,diagnostics,history,actions}"
                ;;
            --project|--path)
                shift
                target="${1:-}"
                ;;
            *)
                if [[ -z "${query}" ]]; then
                    query="$1"
                else
                    yen_error "Unknown search option/arg: $1"
                    exit 1
                fi
                ;;
        esac
        shift
    done

    if [[ -z "${query}" ]]; then
        yen_error "search requires a query. Example: yen ide search verify"
        exit 1
    fi
    if [[ ! "${limit}" =~ ^[0-9]+$ ]] || [[ "${limit}" -lt 1 ]]; then
        yen_error "Invalid --limit '${limit}'. Use a positive integer."
        exit 1
    fi

    local source_token=""
    local parsed_sources
    parsed_sources=$(printf "%s" "${sources_csv}" | tr ',' '\n')
    while IFS= read -r source_token; do
        source_token=$(trim "${source_token}")
        source_token=$(printf "%s" "${source_token}" | tr '[:upper:]' '[:lower:]')
        [[ -z "${source_token}" ]] && continue
        case "${source_token}" in
            file|files)
                include_files="1"
                ;;
            symbol|symbols)
                include_symbols="1"
                ;;
            content|contents)
                include_content="1"
                ;;
            history)
                include_history="1"
                ;;
            diagnostic|diagnostics)
                include_diagnostics="1"
                ;;
            action|actions)
                include_actions="1"
                ;;
            *)
                yen_error "Unknown search source '${source_token}'. Use files,symbols,content,diagnostics,history,actions."
                exit 1
                ;;
        esac
    done << EOF
${parsed_sources}
EOF

    if [[ "${include_files}" != "1" && "${include_symbols}" != "1" && "${include_content}" != "1" && "${include_diagnostics}" != "1" && "${include_history}" != "1" && "${include_actions}" != "1" ]]; then
        yen_error "No valid search sources selected."
        exit 1
    fi

    root=$(find_project_root "${target}")
    query_lc=$(printf "%s" "${query}" | tr '[:upper:]' '[:lower:]')
    runtime=$(detect_runtime_context "${root}")
    tooling=$(detect_tooling_context "${root}")
    context_blob="${runtime},${tooling}"

    results_file=$(mktemp)
    trap 'rm -f "${results_file}"' RETURN

    if [[ "${include_files}" == "1" ]]; then
        if command -v fd >/dev/null 2>&1; then
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                local rel_path="${line}"
                rel_path="${rel_path#${root}/}"
                local base_name
                local score_full
                local score_base
                local score_match
                local score_total
                base_name=$(basename "${rel_path}")
                score_full=$(search_match_score "${query_lc}" "${rel_path}")
                score_base=$(search_match_score "${query_lc}" "${base_name}")
                score_match="${score_full}"
                if [[ "${score_base}" -gt "${score_match}" ]]; then
                    score_match="${score_base}"
                fi
                if [[ "${score_match}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "file") + score_match ))
                append_search_result "${results_file}" "${score_total}" "file" "${rel_path}" "${base_name}"
            done < <(fd -HI -t f --exclude .git . "${root}" 2>/dev/null | head -n 3000)
        else
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                local rel_path="${line#./}"
                local base_name
                local score_full
                local score_base
                local score_match
                local score_total
                base_name=$(basename "${rel_path}")
                score_full=$(search_match_score "${query_lc}" "${rel_path}")
                score_base=$(search_match_score "${query_lc}" "${base_name}")
                score_match="${score_full}"
                if [[ "${score_base}" -gt "${score_match}" ]]; then
                    score_match="${score_base}"
                fi
                if [[ "${score_match}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "file") + score_match ))
                append_search_result "${results_file}" "${score_total}" "file" "${rel_path}" "${base_name}"
            done < <(cd "${root}" && find . -type f -not -path './.git/*' 2>/dev/null | head -n 3000)
        fi
    fi

    if [[ "${include_symbols}" == "1" ]]; then
        while IFS=$'\t' read -r symbol_name symbol_kind rel_file line_no col_no location; do
            [[ -z "${location}" ]] && continue
            local match_score
            local score_total
            match_score=$(search_match_score "${query_lc}" "${symbol_name}")
            if [[ "${match_score}" -le 0 ]]; then
                match_score=$(search_match_score "${query_lc}" "${symbol_kind}")
            fi
            if [[ "${match_score}" -le 0 ]]; then
                match_score=$(search_match_score "${query_lc}" "${rel_file}")
            fi
            if [[ "${match_score}" -le 0 ]]; then
                continue
            fi
            score_total=$(( $(search_source_weight "symbol") + match_score ))
            append_search_result "${results_file}" "${score_total}" "symbol" "${location}" "${symbol_name} [${symbol_kind}]"
        done << EOF
$(emit_symbol_index_rows "${root}" 2>/dev/null || true)
EOF
    fi

    if [[ "${include_content}" == "1" ]]; then
        if command -v rg >/dev/null 2>&1; then
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                local file_part="${line%%:*}"
                local rest="${line#*:}"
                local line_no="${rest%%:*}"
                local snippet="${rest#*:}"
                local rel_file="${file_part#${root}/}"
                local match_score
                local score_total
                if [[ ! "${line_no}" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                match_score=$(search_match_score "${query_lc}" "${snippet}")
                if [[ "${match_score}" -le 0 ]]; then
                    match_score=$(search_match_score "${query_lc}" "${rel_file}")
                fi
                if [[ "${match_score}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "content") + match_score ))
                append_search_result "${results_file}" "${score_total}" "content" "${rel_file}:${line_no}" "$(search_clip_text "${snippet}" 120)"
            done < <(rg -n -i --no-heading --color never --glob '!.git' -- "${query}" "${root}" 2>/dev/null | head -n 1200)
        else
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                local file_part="${line%%:*}"
                local rest="${line#*:}"
                local line_no="${rest%%:*}"
                local snippet="${rest#*:}"
                local rel_file="${file_part#${root}/}"
                local match_score
                local score_total
                if [[ ! "${line_no}" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                match_score=$(search_match_score "${query_lc}" "${snippet}")
                if [[ "${match_score}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "content") + match_score ))
                append_search_result "${results_file}" "${score_total}" "content" "${rel_file}:${line_no}" "$(search_clip_text "${snippet}" 120)"
            done < <(grep -Rin --exclude-dir=.git -- "${query}" "${root}" 2>/dev/null | head -n 1200)
        fi
    fi

    if [[ "${include_diagnostics}" == "1" ]]; then
        local diagnostics_file
        diagnostics_file=$(lsp_diagnostics_file "${root}")
        if [[ -f "${diagnostics_file}" && -s "${diagnostics_file}" ]]; then
            while IFS=$'\t' read -r rel_file line_no col_no severity code source message _abs_path location; do
                [[ -z "${location}" ]] && continue
                local match_score
                local score_total
                match_score=$(search_match_score "${query_lc}" "${message}")
                if [[ "${match_score}" -le 0 ]]; then
                    match_score=$(search_match_score "${query_lc}" "${location}")
                fi
                if [[ "${match_score}" -le 0 && -n "${code}" ]]; then
                    match_score=$(search_match_score "${query_lc}" "${code}")
                fi
                if [[ "${match_score}" -le 0 && -n "${source}" ]]; then
                    match_score=$(search_match_score "${query_lc}" "${source}")
                fi
                if [[ "${match_score}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "diagnostic") + match_score ))
                append_search_result "${results_file}" "${score_total}" "diagnostic" "${location}" "$(search_clip_text "${severity}: ${message}" 120)"
            done << EOF
$(emit_lsp_diagnostics_rows "${diagnostics_file}" "${root}" "all" "200" 2>/dev/null || true)
EOF
        fi
    fi

    if [[ "${include_history}" == "1" ]]; then
        local history_file
        history_file=$(project_history_file "${root}")
        if [[ -f "${history_file}" && -s "${history_file}" ]]; then
            while IFS=$'\t' read -r timestamp cwd cmd; do
                [[ -z "${cmd}" ]] && continue
                local match_score
                local score_total
                local cwd_rel
                match_score=$(search_match_score "${query_lc}" "${cmd}")
                if [[ "${match_score}" -le 0 ]]; then
                    continue
                fi
                score_total=$(( $(search_source_weight "history") + match_score ))
                cwd_rel="${cwd#${root}/}"
                if [[ "${cwd}" == "${root}" ]]; then
                    cwd_rel="."
                fi
                append_search_result "${results_file}" "${score_total}" "history" "${timestamp}" "${cmd} (cwd=${cwd_rel})"
            done < <(tail -r "${history_file}" | head -n 500)
        fi
    fi

    if [[ "${include_actions}" == "1" ]]; then
        while IFS= read -r line; do
            [[ -z "${line}" ]] && continue
            local action_cmd
            local action_tags
            local match_score
            local context_bonus="0"
            local score_total
            local tag
            IFS=$'\t' read -r action_cmd action_tags << EOF
${line}
EOF
            match_score=$(search_match_score "${query_lc}" "${action_cmd}")
            if [[ "${match_score}" -le 0 ]]; then
                continue
            fi
            for tag in $(printf "%s" "${action_tags}" | tr ',' ' '); do
                case ",${context_blob}," in
                    *",${tag},"*)
                        context_bonus="15"
                        break
                        ;;
                esac
            done
            score_total=$(( $(search_source_weight "action") + match_score + context_bonus ))
            append_search_result "${results_file}" "${score_total}" "action" "${action_cmd}" "tags=${action_tags}"
        done << EOF
$(ide_action_catalog)
EOF
    fi

    if [[ ! -s "${results_file}" ]]; then
        trap - RETURN
        rm -f "${results_file}"
        yen_info "No search results for '${query}' in ${root}"
        return 0
    fi

    local sorted_results
    sorted_results=$(sort -t $'\t' -k1,1nr -k2,2n -k4,4 -k5,5 "${results_file}" | head -n "${limit}")

    local review_context_file=""
    local review_target=""
    local -a review_targets=()
    local review_context_json=""
    if [[ -n "${sorted_results}" ]] && declare -F review_context_json_for_targets >/dev/null 2>&1; then
        review_context_file=$(mktemp "${TMPDIR:-/tmp}/yen-search-context.XXXXXX" 2>/dev/null || mktemp)
        while IFS=$'\t' read -r _score _rank source target _preview; do
            case "${source}" in
                file)
                    review_target="${target}"
                    ;;
                content|diagnostic|symbol)
                    review_target="${target}"
                    ;;
                *)
                    review_target=""
                    ;;
            esac
            [[ -n "${review_target}" ]] && review_targets+=("${review_target}")
        done << EOF
${sorted_results}
EOF
        if [[ ${#review_targets[@]} -gt 0 ]]; then
            review_context_json=$(review_context_json_for_targets "${root}" "${review_targets[@]}")
            review_context_summary_rows_from_json "${review_context_json}" > "${review_context_file}"
        fi
    fi
    trap - RETURN
    rm -f "${results_file}"

    local result_count
    result_count=$(printf "%s\n" "${sorted_results}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "search" "${root}" "hits=${result_count}" "query=${query};sources=${sources_csv};limit=${limit}"

    echo ""
    yen_header "IDE Universal Search"
    echo "Root:    ${root}"
    echo "Query:   ${query}"
    echo "Sources: ${sources_csv}"
    echo ""
    printf "%-6s %-10s %-58s %s\n" "SCORE" "SOURCE" "TARGET" "MATCH"
    while IFS=$'\t' read -r score _rank source target preview; do
        [[ -z "${score}" ]] && continue
        local review_summary=""
        if [[ -n "${review_context_file}" && -f "${review_context_file}" ]]; then
            review_summary=$(awk -F'\t' -v key="${target}" '$1 == key { sub(/^[^\t]*\t/, "", $0); print; exit }' "${review_context_file}")
        fi
        if [[ -n "${review_summary}" ]]; then
            preview="${preview} | ${review_summary}"
        fi
        printf "%-6s %-10s %-58s %s\n" "${score}" "${source}" "$(search_clip_text "${target}" 58)" "$(search_clip_text "${preview}" 120)"
    done << EOF
${sorted_results}
EOF
    [[ -n "${review_context_file}" ]] && rm -f "${review_context_file}"
    echo ""
}
