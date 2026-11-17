# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

share_upterm_command() {
    if [[ -n "${YEN_IDE_SHARE_UPTERM_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_SHARE_UPTERM_CMD}"
        return 0
    fi
    if command -v upterm >/dev/null 2>&1; then
        printf "upterm\n"
        return 0
    fi
}

share_tmate_command() {
    if [[ -n "${YEN_IDE_SHARE_TMATE_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_SHARE_TMATE_CMD}"
        return 0
    fi
    if command -v tmate >/dev/null 2>&1; then
        printf "tmate\n"
        return 0
    fi
}

share_remote_upterm_command() {
    if [[ -n "${YEN_IDE_REMOTE_SHARE_UPTERM_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_REMOTE_SHARE_UPTERM_CMD}"
        return 0
    fi
    printf "upterm\n"
}

share_remote_tmate_command() {
    if [[ -n "${YEN_IDE_REMOTE_SHARE_TMATE_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_REMOTE_SHARE_TMATE_CMD}"
        return 0
    fi
    printf "tmate\n"
}

share_remote_helper_script() {
    local current_script=""
    current_script=$(canonicalize_path "${BASH_SOURCE[0]}")
    printf "%s/remote-share-helper.py\n" "$(dirname "${current_script}")"
}

SHARE_REMOTE_LAST_STDERR=""

share_remote_action() {
    local authority="$1"
    local port="$2"
    local action="$3"
    shift 3
    local ssh_bin=""
    local helper_script=""
    local stderr_file=""
    local stderr_text=""
    local output=""
    local status=0
    local -a ssh_cmd=()

    SHARE_REMOTE_LAST_STDERR=""
    ssh_bin=$(remote_detect_ssh_binary) || {
        SHARE_REMOTE_LAST_STDERR="ssh is required for remote share support."
        return 1
    }
    helper_script=$(share_remote_helper_script)
    if [[ ! -f "${helper_script}" ]]; then
        SHARE_REMOTE_LAST_STDERR="Remote share helper is missing."
        return 1
    fi
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/yen-remote-share.XXXXXX" 2>/dev/null) || {
        SHARE_REMOTE_LAST_STDERR="Unable to allocate a temp file for remote share execution."
        return 1
    }

    ssh_cmd=("${ssh_bin}")
    if [[ -n "${port}" ]]; then
        ssh_cmd+=("-p" "${port}")
    fi
    ssh_cmd+=("${authority}" "python3" "-" "${action}")
    while [[ $# -gt 0 ]]; do
        ssh_cmd+=("$1")
        shift
    done

    output=$("${ssh_cmd[@]}" 2>"${stderr_file}" < "${helper_script}")
    status=$?
    stderr_text=$(tr '\n' ' ' < "${stderr_file}" | sed 's/[[:space:]]*$//')
    rm -f "${stderr_file}"
    SHARE_REMOTE_LAST_STDERR="${stderr_text}"
    if [[ "${status}" -ne 0 ]]; then
        [[ -n "${SHARE_REMOTE_LAST_STDERR}" ]] || SHARE_REMOTE_LAST_STDERR="remote share helper failed"
        return 1
    fi
    printf "%s\n" "${output}"
}

share_default_transport_from_available() {
    local available=""
    available="$1"
    if csv_has_token "${available}" "upterm"; then
        printf "upterm\n"
        return 0
    fi
    if csv_has_token "${available}" "tmate"; then
        printf "tmate\n"
        return 0
    fi
}

share_select_transport_from_available() {
    local requested="${1:-auto}"
    local available="$2"
    case "${requested}" in
        ""|auto)
            share_default_transport_from_available "${available}"
            ;;
        upterm|tmate)
            if csv_has_token "${available}" "${requested}"; then
                printf "%s\n" "${requested}"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

share_available_transports() {
    local out=""
    [[ -n "$(share_upterm_command)" ]] && out=$(append_csv_unique "${out}" "upterm")
    [[ -n "$(share_tmate_command)" ]] && out=$(append_csv_unique "${out}" "tmate")
    printf "%s\n" "${out}"
}

share_remote_available_transports() {
    local authority="$1"
    local port="$2"
    local payload=""

    payload=$(share_remote_action "${authority}" "${port}" "available" "$(share_remote_upterm_command)" "$(share_remote_tmate_command)") || return 1
    python3 - "${payload}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print(",".join(str(item) for item in payload.get("available") or []))
PY
}

share_default_ttl_seconds() {
    local raw="${YEN_IDE_SHARE_DEFAULT_TTL_SEC:-3600}"
    if [[ ! "${raw}" =~ ^[0-9]+$ ]] || [[ "${raw}" -lt 60 ]]; then
        raw="3600"
    fi
    printf "%s\n" "${raw}"
}

share_format_ttl() {
    local total="$1"
    local hours=0
    local minutes=0
    local seconds=0
    if [[ ! "${total}" =~ ^-?[0-9]+$ ]]; then
        total="0"
    fi
    if [[ "${total}" -lt 0 ]]; then
        total="0"
    fi
    hours=$(( total / 3600 ))
    minutes=$(( (total % 3600) / 60 ))
    seconds=$(( total % 60 ))
    printf "%02d:%02d:%02d\n" "${hours}" "${minutes}" "${seconds}"
}

epoch_to_iso_utc() {
    local epoch="$1"
    python3 - "${epoch}" <<'PY'
import datetime
import sys

epoch = int(sys.argv[1] or "0")
print(datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

iso_to_epoch_utc() {
    local iso_text="$1"
    if [[ -z "${iso_text}" ]]; then
        printf "0\n"
        return 0
    fi
    python3 - "${iso_text}" <<'PY'
import datetime
import sys

raw = sys.argv[1]
if raw.endswith("Z"):
    raw = raw[:-1] + "+00:00"
try:
    parsed = datetime.datetime.fromisoformat(raw)
except ValueError:
    print("0")
    raise SystemExit(0)
if parsed.tzinfo is None:
    parsed = parsed.replace(tzinfo=datetime.timezone.utc)
print(int(parsed.timestamp()))
PY
}

share_host_identity() {
    local user_name=""
    local host_name=""
    user_name=$(id -un 2>/dev/null || whoami 2>/dev/null || printf "unknown")
    host_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf "host")
    printf "%s@%s\n" "${user_name}" "${host_name}"
}

share_repo_label() {
    local root="$1"
    basename "${root}"
}

share_generate_session_id() {
    if command -v openssl >/dev/null 2>&1; then
        printf "share-%s\n" "$(openssl rand -hex 6)"
        return 0
    fi
    printf "share-%s\n" "$(date +%s)"
}

share_generate_passphrase() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 9
        return 0
    fi
    python3 - <<'PY'
import secrets
print(secrets.token_hex(9))
PY
}

share_state_value() {
    local root="$1"
    local key="$2"
    local state_file
    state_file=$(share_state_file "${root}")
    if [[ ! -f "${state_file}" ]]; then
        return 0
    fi
    grep -F "${key}=" "${state_file}" 2>/dev/null | head -n 1 | cut -d= -f2-
}

write_share_state() {
    local root="$1"
    local status="$2"
    local transport="$3"
    local mode="$4"
    local host_identity="$5"
    local repo_label="$6"
    local session_id="$7"
    local started_at="$8"
    local expires_at="$9"
    local expires_epoch="${10}"
    local auth_mode="${11}"
    local share_token="${12}"
    local transport_status="${13}"
    local last_error="${14}"
    local revoked_at="${15}"
    local expired_at="${16}"
    local ttl_seconds="${17}"
    local cli="${18}"
    local web_url="${19}"
    local execution_location="${20}"
    local workspace_identity="${21}"
    local requested_path="${22}"
    local reconnect_target="${23}"
    local remote_authority="${24}"
    local remote_port="${25}"
    local remote_label="${26}"
    local remote_state_dir="${27}"
    local remote_pid="${28}"
    local remote_admin_socket="${29}"
    local remote_socket_file="${30}"
    local content=""

    content="status=${status}
root=${root}
transport=${transport}
mode=${mode}
host_identity=${host_identity}
repo_label=${repo_label}
session_id=${session_id}
started_at=${started_at}
expires_at=${expires_at}
expires_epoch=${expires_epoch}
auth_mode=${auth_mode}
share_token=${share_token}
transport_status=${transport_status}
last_error=${last_error}
revoked_at=${revoked_at}
expired_at=${expired_at}
ttl_seconds=${ttl_seconds}
cli=${cli}
web_url=${web_url}
execution_location=${execution_location}
workspace_identity=${workspace_identity}
requested_path=${requested_path}
reconnect_target=${reconnect_target}
remote_authority=${remote_authority}
remote_port=${remote_port}
remote_label=${remote_label}
remote_state_dir=${remote_state_dir}
remote_pid=${remote_pid}
remote_admin_socket=${remote_admin_socket}
remote_socket_file=${remote_socket_file}
"
    atomic_write_text "$(share_state_file "${root}")" "${content}"
}

share_execution_location_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]]; then
        printf "remote\n"
        return 0
    fi
    printf "local\n"
}

share_workspace_identity_for_root() {
    local root="$1"
    if declare -F workspace_identity_for_root >/dev/null 2>&1; then
        workspace_identity_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

share_requested_path_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]] && [[ -n "${IDE_WORKSPACE_REQUESTED_PATH}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_REQUESTED_PATH}"
        return 0
    fi
    printf "%s\n" "${root}"
}

share_remote_authority_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_AUTHORITY}"
        return 0
    fi
}

share_remote_port_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_PORT}"
        return 0
    fi
}

share_remote_label_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_LABEL}"
        return 0
    fi
}

share_reconnect_target_from_join_command() {
    local join_command="$1"
    share_join_target "${join_command}" 2>/dev/null || true
}

share_available_transports_for_root() {
    local root="$1"
    local available=""

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_ROOT}" == "${root}" ]]; then
        available=$(share_remote_available_transports "${IDE_WORKSPACE_AUTHORITY}" "${IDE_WORKSPACE_PORT}" || true)
        printf "%s\n" "${available}"
        return 0
    fi
    share_available_transports
}

SHARE_TARGET_ROOT=""
SHARE_TARGET_USED_CACHED_REMOTE_ROOT="0"

share_find_remote_root_from_state() {
    local authority="$1"
    local port="$2"
    local label="$3"
    local requested_path="$4"

    ensure_state_dirs
    python3 - "${IDE_SHARE_DIR}" "${authority}" "${port}" "${label}" "${requested_path}" <<'PY'
import os
import pathlib
import sys

share_dir = pathlib.Path(sys.argv[1])
authority = sys.argv[2]
port = sys.argv[3]
label = sys.argv[4]
requested_path = sys.argv[5]


def parse_state(path: pathlib.Path) -> dict:
    data = {}
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            if "=" not in raw:
                continue
            key, value = raw.split("=", 1)
            data[key] = value
    except Exception:
        return {}
    return data


def matches(payload: dict) -> bool:
    if payload.get("execution_location") != "remote":
        return False
    if payload.get("remote_authority", "") != authority:
        return False
    if payload.get("remote_port", "") != port:
        return False
    if payload.get("remote_label", "") != label:
        return False
    root = payload.get("root", "")
    requested = payload.get("requested_path", "")
    if not root:
        return False
    if requested_path == root or requested_path == requested:
        return True
    if requested_path.startswith(root.rstrip("/") + "/"):
        return True
    return False


candidates = []
if share_dir.is_dir():
    for state_file in share_dir.glob("*/state.env"):
        payload = parse_state(state_file)
        if matches(payload):
            root = payload.get("root", "")
            if root and root not in candidates:
                candidates.append(root)

if len(candidates) == 1:
    print(candidates[0])
PY
}

share_resolve_target() {
    local target="$1"
    local allow_cached_remote="${2:-0}"
    local cached_root=""

    SHARE_TARGET_ROOT=""
    SHARE_TARGET_USED_CACHED_REMOTE_ROOT="0"

    if workspace_summary_resolve_target "${target}" >/dev/null 2>&1; then
        SHARE_TARGET_ROOT="${IDE_WORKSPACE_SUMMARY_ROOT}"
        return 0
    fi

    if ! workspace_identity_parse_target "${target}" >/dev/null 2>&1; then
        workspace_summary_resolve_target "${target}"
        return 1
    fi

    if workspace_identity_is_remote && [[ "${allow_cached_remote}" == "1" ]]; then
        cached_root=$(share_find_remote_root_from_state "${IDE_WORKSPACE_AUTHORITY}" "${IDE_WORKSPACE_PORT}" "${IDE_WORKSPACE_LABEL}" "${IDE_WORKSPACE_REQUESTED_PATH}" || true)
        if [[ -n "${cached_root}" ]]; then
            workspace_summary_reset
            IDE_WORKSPACE_SUMMARY_ROOT="${cached_root}"
            workspace_identity_set_resolved_root "${cached_root}"
            SHARE_TARGET_ROOT="${cached_root}"
            SHARE_TARGET_USED_CACHED_REMOTE_ROOT="1"
            return 0
        fi
    fi

    workspace_summary_resolve_target "${target}"
}

read_share_pid() {
    local root="$1"
    local pid_file
    pid_file=$(share_pid_file "${root}")
    if [[ ! -f "${pid_file}" ]]; then
        return 0
    fi
    tr -d '[:space:]' < "${pid_file}" | sed -n '1p'
}

read_share_expiry_pid() {
    local root="$1"
    local pid_file
    pid_file=$(share_expiry_pid_file "${root}")
    if [[ ! -f "${pid_file}" ]]; then
        return 0
    fi
    tr -d '[:space:]' < "${pid_file}" | sed -n '1p'
}

pid_matches_script() {
    local pid="$1"
    local script_path="$2"
    local command_line=""

    if ! is_pid_running "${pid}"; then
        return 1
    fi

    command_line=$(ps -p "${pid}" -o command= 2>/dev/null || true)
    if [[ -z "${command_line}" ]]; then
        return 1
    fi
    if [[ "${command_line}" != *"${script_path}"* ]]; then
        return 1
    fi
    return 0
}

share_pid_matches_runtime() {
    local root="$1"
    local pid="$2"
    local command_line=""

    if ! is_pid_running "${pid}"; then
        return 1
    fi
    command_line=$(ps -p "${pid}" -o command= 2>/dev/null || true)
    if [[ -z "${command_line}" ]]; then
        return 1
    fi
    if [[ "${command_line}" == *"$(share_wrapper_script_file "${root}")"* ]]; then
        return 0
    fi
    if [[ "${command_line}" == *"$(share_upterm_command_script_file "${root}")"* ]]; then
        return 0
    fi
    return 1
}

share_expiry_pid_matches_runtime() {
    local root="$1"
    local pid="$2"
    pid_matches_script "${pid}" "$(share_expiry_script_file "${root}")"
}

cleanup_share_runtime_artifacts() {
    local root="$1"
    local preserve_state="${2:-0}"
    local project_dir=""
    project_dir=$(share_project_dir "${root}")

    rm -f "$(share_pid_file "${root}")" \
        "$(share_expiry_pid_file "${root}")" \
        "$(share_wrapper_script_file "${root}")" \
        "$(share_expiry_script_file "${root}")" \
        "$(share_upterm_command_script_file "${root}")" \
        "$(share_upterm_admin_file "${root}")" \
        "$(share_upterm_session_file "${root}")" \
        "$(share_tmate_socket_file "${root}")"
    if [[ "${preserve_state}" != "1" ]]; then
        rm -f "$(share_state_file "${root}")"
    fi
    if [[ -d "${project_dir}" ]] && [[ -z "$(find "${project_dir}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
        rmdir "${project_dir}" 2>/dev/null || true
    fi
}

share_require_crypto_support() {
    if command -v openssl >/dev/null 2>&1; then
        return 0
    fi
    yen_error "openssl is required for encrypted share tokens."
    return 1
}

share_encrypt_payload() {
    local payload="$1"
    local passphrase="$2"
    exec 3<<<"${passphrase}"
    printf "%s" "${payload}" | openssl enc -aes-256-cbc -pbkdf2 -salt -a -A -pass fd:3 2>/dev/null
    local status=$?
    exec 3<&-
    return "${status}"
}

share_decrypt_payload() {
    local token="$1"
    local passphrase="$2"
    exec 3<<<"${passphrase}"
    printf "%s" "${token}" | openssl enc -d -aes-256-cbc -pbkdf2 -a -A -pass fd:3 2>/dev/null
    local status=$?
    exec 3<&-
    return "${status}"
}

share_build_token_payload() {
    local session_id="$1"
    local transport="$2"
    local mode="$3"
    local host_identity="$4"
    local repo_label="$5"
    local expires_at="$6"
    local auth_mode="$7"
    local join_command="$8"
    local web_url="$9"
    local execution_location="${10}"
    local workspace_identity="${11}"
    local requested_path="${12}"
    local reconnect_target="${13}"
    python3 - "${session_id}" "${transport}" "${mode}" "${host_identity}" "${repo_label}" "${expires_at}" "${auth_mode}" "${join_command}" "${web_url}" "${execution_location}" "${workspace_identity}" "${requested_path}" "${reconnect_target}" <<'PY'
import json
import sys

print(json.dumps(
    {
        "version": 2,
        "sessionId": sys.argv[1],
        "transport": sys.argv[2],
        "mode": sys.argv[3],
        "hostIdentity": sys.argv[4],
        "repoLabel": sys.argv[5],
        "expiresAt": sys.argv[6],
        "authMode": sys.argv[7],
        "joinCommand": sys.argv[8],
        "webUrl": sys.argv[9],
        "executionLocation": sys.argv[10],
        "workspaceIdentity": sys.argv[11],
        "requestedPath": sys.argv[12],
        "reconnectTarget": sys.argv[13],
    },
    separators=(",", ":"),
    sort_keys=True,
))
PY
}

share_token_json_field() {
    local payload="$1"
    local key="$2"
    python3 - "${payload}" "${key}" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1] or "{}")
except Exception:
    sys.exit(1)
value = payload.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(str(value))
PY
}

share_token_payload_valid() {
    local payload="$1"
    python3 - "${payload}" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1] or "")
except Exception:
    sys.exit(1)

if not isinstance(payload, dict):
    sys.exit(1)

required = ("version", "sessionId", "transport", "mode", "hostIdentity", "repoLabel", "expiresAt", "authMode", "joinCommand")
for key in required:
    value = payload.get(key)
    if value in ("", None):
        sys.exit(1)

if payload.get("version") not in (1, 2):
    sys.exit(1)
PY
}

share_join_metadata_valid() {
    local transport="$1"
    local mode="$2"
    local join_command="$3"

    case "${transport}" in
        upterm|tmate)
            ;;
        *)
            return 1
            ;;
    esac

    case "${mode}" in
        read-only|interactive)
            ;;
        *)
            return 1
            ;;
    esac

    share_join_target "${join_command}" >/dev/null 2>&1
}

share_join_target() {
    local join_command="$1"
    local target=""
    local user_part=""
    local host_part=""

    if [[ -z "${join_command}" ]] || [[ "${join_command}" == *$'\n'* ]] || [[ "${join_command}" == *$'\r'* ]]; then
        return 1
    fi

    set -f
    set -- ${join_command}
    set +f
    if [[ "$#" -ne 2 ]] || [[ "$1" != "ssh" ]]; then
        return 1
    fi
    target="$2"
    if [[ "${target}" != *@* ]]; then
        return 1
    fi

    user_part="${target%%@*}"
    host_part="${target#*@}"
    if [[ -z "${user_part}" ]] || [[ -z "${host_part}" ]]; then
        return 1
    fi
    case "${user_part}" in
        *[!A-Za-z0-9._-]*)
            return 1
            ;;
    esac
    case "${host_part}" in
        *[!A-Za-z0-9.-]*)
            return 1
            ;;
    esac

    printf "%s\n" "${target}"
}

share_output_format_valid() {
    local format="$1"
    case "${format}" in
        text|env|json)
            return 0
            ;;
    esac
    return 1
}

share_prompt_for_passphrase() {
    local prompt_text="${1:-Passphrase: }"
    local answer=""
    if [[ ! -t 0 ]]; then
        return 1
    fi
    printf "%s" "${prompt_text}" >&2
    stty -echo 2>/dev/null || true
    read -r answer
    stty echo 2>/dev/null || true
    printf "\n" >&2
    printf "%s\n" "${answer}"
}

ensure_share_trusted_or_prompt() {
    local root="$1"
    local trust_label=""
    if is_share_trusted_project "${root}"; then
        return 0
    fi
    trust_label=$(share_workspace_identity_for_root "${root}")
    if [[ -z "${trust_label}" ]]; then
        trust_label="${root}"
    fi

    if [[ -t 0 ]]; then
        echo "Project sharing is untrusted: ${trust_label}" >&2
        echo "Allow YEN to host a terminal-sharing session for this project?" >&2
        echo "  [o] once  [a] always trust  [n] no" >&2
        printf "> " >&2
        local answer=""
        read -r answer
        case "${answer}" in
            a|A|always|ALWAYS)
                trust_share_project "${root}"
                timeline_log "share-trust" "${root}" "trusted" "source=prompt"
                return 0
                ;;
            o|O|once|ONCE|y|Y|yes|YES)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    yen_error "Project sharing is untrusted: ${trust_label}"
    yen_info "Run: yen ide share trust \"${trust_label}\""
    return 1
}

share_remote_status_snapshot() {
    local root="$1"
    local authority=""
    local port=""
    local transport=""
    local cli=""
    local remote_pid=""
    local remote_admin_socket=""
    local remote_socket_file=""
    local mode=""

    authority=$(share_state_value "${root}" "remote_authority")
    port=$(share_state_value "${root}" "remote_port")
    transport=$(share_state_value "${root}" "transport")
    cli=$(share_state_value "${root}" "cli")
    remote_pid=$(share_state_value "${root}" "remote_pid")
    remote_admin_socket=$(share_state_value "${root}" "remote_admin_socket")
    remote_socket_file=$(share_state_value "${root}" "remote_socket_file")
    mode=$(share_state_value "${root}" "mode")
    if [[ -z "${authority}" ]] || [[ -z "${transport}" ]] || [[ -z "${cli}" ]]; then
        printf "{\"alive\": false}\n"
        return 0
    fi
    share_remote_action "${authority}" "${port}" "status" "${transport}" "${cli}" "${remote_pid}" "${remote_admin_socket}" "${remote_socket_file}" "${mode}"
}

share_runtime_state() {
    local root="$1"
    local state_file=""
    local status=""
    local transport=""
    local execution_location=""
    local pid=""
    local expires_epoch="0"
    local now_epoch
    local cli=""
    local socket_file=""
    local remote_snapshot=""
    local remote_alive="no"

    state_file=$(share_state_file "${root}")
    if [[ ! -f "${state_file}" ]]; then
        printf "stopped\n"
        return 0
    fi

    status=$(share_state_value "${root}" "status")
    transport=$(share_state_value "${root}" "transport")
    execution_location=$(share_state_value "${root}" "execution_location")
    expires_epoch=$(share_state_value "${root}" "expires_epoch")
    [[ ! "${expires_epoch}" =~ ^[0-9]+$ ]] && expires_epoch="0"
    now_epoch=$(date +%s)

    case "${status}" in
        revoked|expired|failed)
            printf "%s\n" "${status}"
            return 0
            ;;
    esac

    if [[ "${expires_epoch}" -gt 0 && "${now_epoch}" -ge "${expires_epoch}" ]]; then
        printf "expired\n"
        return 0
    fi

    if [[ "${execution_location}" == "remote" ]]; then
        remote_snapshot=$(share_remote_status_snapshot "${root}" || true)
        if [[ -z "${remote_snapshot}" ]]; then
            printf "disconnected\n"
            return 0
        fi
        remote_alive=$(python3 - "${remote_snapshot}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print("yes" if payload.get("alive") else "no")
PY
)
        if [[ "${remote_alive}" == "yes" ]]; then
            printf "running\n"
        else
            printf "stale\n"
        fi
        return 0
    fi

    case "${transport}" in
        upterm)
            pid=$(read_share_pid "${root}")
            if share_pid_matches_runtime "${root}" "${pid}"; then
                printf "running\n"
            else
                printf "stale\n"
            fi
            return 0
            ;;
        tmate)
            socket_file=$(share_tmate_socket_file "${root}")
            if [[ -S "${socket_file}" || -e "${socket_file}" ]]; then
                cli=$(share_tmate_command)
                if [[ -n "${cli}" ]]; then
                    if bash -lc "${cli} -S $(shell_quote_single "${socket_file}") has-session" >/dev/null 2>&1; then
                        printf "running\n"
                    else
                        printf "stale\n"
                    fi
                else
                    printf "running\n"
                fi
            else
                printf "stale\n"
            fi
            return 0
            ;;
    esac

    printf "stopped\n"
}

share_transport_status() {
    local root="$1"
    local state="$2"
    local transport="$3"
    local available=""
    local execution_location=""
    available=$(share_available_transports_for_root "${root}")
    execution_location=$(share_state_value "${root}" "execution_location")

    if [[ "${state}" == "running" ]]; then
        if [[ "${execution_location}" == "remote" ]]; then
            printf "available\n"
            return 0
        fi
        case "${transport}" in
            upterm)
                if [[ -n "$(share_upterm_command)" ]]; then
                    printf "available\n"
                else
                    printf "missing-cli\n"
                fi
                return 0
                ;;
            tmate)
                if [[ -n "$(share_tmate_command)" ]]; then
                    printf "available\n"
                else
                    printf "missing-cli\n"
                fi
                return 0
                ;;
        esac
    fi

    if [[ "${state}" == "stale" ]]; then
        printf "stale\n"
        return 0
    fi
    if [[ "${state}" == "disconnected" ]]; then
        printf "remote-unreachable\n"
        return 0
    fi
    if [[ "${state}" == "expired" || "${state}" == "revoked" ]]; then
        printf "inactive\n"
        return 0
    fi
    if [[ -n "${available}" ]]; then
        printf "ready\n"
    else
        printf "unavailable\n"
    fi
}

share_parse_upterm_session() {
    local session_json="$1"
    local mode="$2"
    python3 - "${session_json}" "${mode}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
mode = sys.argv[2]

def fetch(obj, *paths):
    for path in paths:
        current = obj
        ok = True
        for part in path:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                ok = False
                break
        if ok and current not in ("", None):
            return current
    return ""

join_command = fetch(
    payload,
    ("sshCommand",),
    ("ssh_command",),
    ("session", "sshCommand"),
    ("session", "ssh_command"),
    ("join", "sshCommand"),
    ("join", "ssh_command"),
)
session_id = fetch(payload, ("sessionId",), ("session_id",), ("id",))
host = fetch(payload, ("host",), ("nodeAddr",), ("node_addr",), ("addr",))
web_url = fetch(payload, ("webUrl",), ("web_url",), ("session", "webUrl"), ("session", "web_url"))

if not join_command and session_id and host:
    join_command = f"ssh {session_id}@{host}"

print(f"session_id={session_id}")
print(f"join_command={join_command}")
print(f"web_url={web_url}")
PY
}

share_remote_start_session() {
    local authority="$1"
    local port="$2"
    local root="$3"
    local transport="$4"
    local mode="$5"
    local ttl_seconds="$6"
    local session_id="$7"

    share_remote_action \
        "${authority}" \
        "${port}" \
        "start" \
        "${root}" \
        "${transport}" \
        "${mode}" \
        "${ttl_seconds}" \
        "${session_id}" \
        "$(share_remote_upterm_command)" \
        "$(share_remote_tmate_command)"
}

share_remote_revoke_session() {
    local root="$1"
    local authority=""
    local port=""
    local transport=""
    local cli=""
    local remote_state_dir=""
    local remote_pid=""
    local remote_socket_file=""

    authority=$(share_state_value "${root}" "remote_authority")
    port=$(share_state_value "${root}" "remote_port")
    transport=$(share_state_value "${root}" "transport")
    cli=$(share_state_value "${root}" "cli")
    remote_state_dir=$(share_state_value "${root}" "remote_state_dir")
    remote_pid=$(share_state_value "${root}" "remote_pid")
    remote_socket_file=$(share_state_value "${root}" "remote_socket_file")
    if [[ -z "${authority}" ]] || [[ -z "${transport}" ]] || [[ -z "${cli}" ]]; then
        return 0
    fi
    share_remote_revoke_session_values "${authority}" "${port}" "${transport}" "${cli}" "${remote_state_dir}" "${remote_pid}" "${remote_socket_file}"
}

share_remote_revoke_session_values() {
    local authority="$1"
    local port="$2"
    local transport="$3"
    local cli="$4"
    local remote_state_dir="$5"
    local remote_pid="$6"
    local remote_socket_file="$7"

    share_remote_action "${authority}" "${port}" "revoke" "${transport}" "${cli}" "${remote_state_dir}" "${remote_pid}" "${remote_socket_file}" >/dev/null
}

share_start_expiry_watcher() {
    local root="$1"
    local session_id="$2"
    local ttl_seconds="$3"
    local script_file=""
    local script_source=""
    local pid=""
    local current_script=""
    local project_target=""

    current_script=$(canonicalize_path "${BASH_SOURCE[0]}")
    project_target=$(share_workspace_identity_for_root "${root}")
    if [[ -z "${project_target}" ]]; then
        project_target="${root}"
    fi
    script_file=$(share_expiry_script_file "${root}")
    script_source="#!/bin/bash
set -e
export YEN_LIB=$(shell_quote_single "${YEN_LIB}")
sleep ${ttl_seconds}
$(shell_quote_single "${current_script}") __share-expire --project $(shell_quote_single "${project_target}") --session-id $(shell_quote_single "${session_id}")
"
    atomic_write_text "${script_file}" "${script_source}"
    chmod 755 "${script_file}"
    nohup bash "${script_file}" >/dev/null 2>&1 &
    pid=$!
    atomic_write_text "$(share_expiry_pid_file "${root}")" "$(printf "%s\n" "${pid}")"
}

share_finalize_session_locked() {
    local root="$1"
    local final_status="$2"
    local event_name="$3"
    local event_detail="$4"
    local cleanup_policy="${5:-strict}"
    local transport=""
    local mode=""
    local host_identity=""
    local repo_label=""
    local session_id=""
    local started_at=""
    local expires_at=""
    local expires_epoch=""
    local auth_mode=""
    local cli=""
    local web_url=""
    local ttl_seconds=""
    local execution_location=""
    local workspace_identity=""
    local requested_path=""
    local reconnect_target=""
    local remote_authority=""
    local remote_port=""
    local remote_label=""
    local remote_state_dir=""
    local remote_pid=""
    local remote_admin_socket=""
    local remote_socket_file=""
    local pid=""
    local expiry_pid=""
    local socket_file=""
    local finalized_at=""
    local revoked_at=""
    local expired_at=""

    transport=$(share_state_value "${root}" "transport")
    mode=$(share_state_value "${root}" "mode")
    host_identity=$(share_state_value "${root}" "host_identity")
    repo_label=$(share_state_value "${root}" "repo_label")
    session_id=$(share_state_value "${root}" "session_id")
    started_at=$(share_state_value "${root}" "started_at")
    expires_at=$(share_state_value "${root}" "expires_at")
    expires_epoch=$(share_state_value "${root}" "expires_epoch")
    auth_mode=$(share_state_value "${root}" "auth_mode")
    cli=$(share_state_value "${root}" "cli")
    web_url=$(share_state_value "${root}" "web_url")
    ttl_seconds=$(share_state_value "${root}" "ttl_seconds")
    execution_location=$(share_state_value "${root}" "execution_location")
    workspace_identity=$(share_state_value "${root}" "workspace_identity")
    requested_path=$(share_state_value "${root}" "requested_path")
    reconnect_target=$(share_state_value "${root}" "reconnect_target")
    remote_authority=$(share_state_value "${root}" "remote_authority")
    remote_port=$(share_state_value "${root}" "remote_port")
    remote_label=$(share_state_value "${root}" "remote_label")
    remote_state_dir=$(share_state_value "${root}" "remote_state_dir")
    remote_pid=$(share_state_value "${root}" "remote_pid")
    remote_admin_socket=$(share_state_value "${root}" "remote_admin_socket")
    remote_socket_file=$(share_state_value "${root}" "remote_socket_file")

    if [[ "${execution_location}" == "remote" ]]; then
        if ! share_remote_revoke_session "${root}"; then
            if [[ "${cleanup_policy}" != "best-effort" ]]; then
                return 1
            fi
        fi
    fi

    expiry_pid=$(read_share_expiry_pid "${root}")
    if share_expiry_pid_matches_runtime "${root}" "${expiry_pid}"; then
        kill "${expiry_pid}" 2>/dev/null || true
    fi

    if [[ "${execution_location}" != "remote" ]]; then
        case "${transport}" in
            upterm)
                pid=$(read_share_pid "${root}")
                if share_pid_matches_runtime "${root}" "${pid}"; then
                    kill "${pid}" 2>/dev/null || true
                    local attempts=0
                    while share_pid_matches_runtime "${root}" "${pid}" && [[ "${attempts}" -lt 20 ]]; do
                        sleep 0.1
                        attempts=$((attempts + 1))
                    done
                    if share_pid_matches_runtime "${root}" "${pid}"; then
                        kill -9 "${pid}" 2>/dev/null || true
                    fi
                fi
                ;;
            tmate)
                socket_file=$(share_tmate_socket_file "${root}")
                if [[ -n "${cli}" ]] && [[ -e "${socket_file}" ]]; then
                    bash -lc "${cli} -S $(shell_quote_single "${socket_file}") kill-server" >/dev/null 2>&1 || true
                fi
                pid=$(read_share_pid "${root}")
                if share_pid_matches_runtime "${root}" "${pid}"; then
                    kill "${pid}" 2>/dev/null || true
                    local attempts=0
                    while share_pid_matches_runtime "${root}" "${pid}" && [[ "${attempts}" -lt 20 ]]; do
                        sleep 0.1
                        attempts=$((attempts + 1))
                    done
                    if share_pid_matches_runtime "${root}" "${pid}"; then
                        kill -9 "${pid}" 2>/dev/null || true
                    fi
                fi
                ;;
        esac
    fi

    cleanup_share_runtime_artifacts "${root}" "1"
    finalized_at=$(iso_now)
    if [[ "${final_status}" == "revoked" ]]; then
        revoked_at="${finalized_at}"
    fi
    if [[ "${final_status}" == "expired" ]]; then
        expired_at="${finalized_at}"
    fi
    write_share_state \
        "${root}" \
        "${final_status}" \
        "${transport}" \
        "${mode}" \
        "${host_identity}" \
        "${repo_label}" \
        "${session_id}" \
        "${started_at}" \
        "${expires_at}" \
        "${expires_epoch}" \
        "${auth_mode}" \
        "" \
        "$(share_transport_status "${root}" "${final_status}" "${transport}")" \
        "" \
        "${revoked_at}" \
        "${expired_at}" \
        "${ttl_seconds}" \
        "${cli}" \
        "${web_url}" \
        "${execution_location}" \
        "${workspace_identity}" \
        "${requested_path}" \
        "${reconnect_target}" \
        "${remote_authority}" \
        "${remote_port}" \
        "${remote_label}" \
        "${remote_state_dir}" \
        "${remote_pid}" \
        "${remote_admin_socket}" \
        "${remote_socket_file}"
    timeline_log "${event_name}" "${root}" "${final_status}" "${event_detail}"
}

cmd_share_expire_internal() {
    local root="$1"
    local expected_session_id="$2"
    local lock_dir=""
    local lock_released="0"
    local current_session_id=""
    local current_status=""
    local expires_epoch=""
    local now_epoch

    lock_dir=$(share_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "IDE share lifecycle"; then
        return 1
    fi
    trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR

    current_session_id=$(share_state_value "${root}" "session_id")
    current_status=$(share_state_value "${root}" "status")
    expires_epoch=$(share_state_value "${root}" "expires_epoch")
    [[ ! "${expires_epoch}" =~ ^[0-9]+$ ]] && expires_epoch="0"
    now_epoch=$(date +%s)

    if [[ -n "${expected_session_id}" && "${current_session_id}" != "${expected_session_id}" ]]; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 0
    fi
    if [[ "${current_status}" != "running" ]] || [[ "${expires_epoch}" -le 0 ]] || [[ "${now_epoch}" -lt "${expires_epoch}" ]]; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 0
    fi

    share_finalize_session_locked "${root}" "expired" "share-expire" "session=${current_session_id};transport=$(share_state_value "${root}" "transport")" "best-effort"
    lock_released="1"
    release_state_lock "${lock_dir}"
    trap - ERR
}

cmd_share_revoke_internal() {
    local root="$1"
    local reason="${2:-manual}"
    local lock_dir=""
    local lock_released="0"
    local state=""
    local session_id=""
    local transport=""

    lock_dir=$(share_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "IDE share lifecycle"; then
        return 1
    fi
    trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR

    state=$(share_runtime_state "${root}")
    session_id=$(share_state_value "${root}" "session_id")
    transport=$(share_state_value "${root}" "transport")

    if [[ "${state}" == "stopped" ]] && [[ ! -f "$(share_state_file "${root}")" ]]; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 2
    fi

    if ! share_finalize_session_locked "${root}" "revoked" "share-revoke" "reason=${reason};session=${session_id};transport=${transport}" "strict"; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 1
    fi
    lock_released="1"
    release_state_lock "${lock_dir}"
    trap - ERR
    return 0
}

cmd_share_status() {
    local target=""
    local format="text"
    local root=""
    local raw_status=""
    local state=""
    local transport=""
    local preferred_transport=""
    local available_transports=""
    local trusted="no"
    local mode=""
    local host_identity=""
    local repo_label=""
    local session_id=""
    local started_at=""
    local expires_at=""
    local expires_epoch="0"
    local auth_mode=""
    local share_token=""
    local transport_status=""
    local last_error=""
    local remaining_seconds="0"
    local remaining_text="00:00:00"
    local cli=""
    local web_url=""
    local execution_location=""
    local workspace_identity=""
    local requested_path=""
    local reconnect_target=""
    local remote_authority=""
    local remote_port=""
    local remote_label=""
    local target_for_commands=""

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
                target="$1"
                ;;
        esac
        shift
    done

    if ! share_output_format_valid "${format}"; then
        yen_error "Unknown share status format: ${format} (expected text|env|json)"
        return 1
    fi

    if ! share_resolve_target "${target}" "1"; then
        return 1
    fi
    root="${SHARE_TARGET_ROOT}"
    workspace_identity=$(share_state_value "${root}" "workspace_identity")
    [[ -n "${workspace_identity}" ]] || workspace_identity=$(share_workspace_identity_for_root "${root}")
    raw_status=$(share_state_value "${root}" "status")
    if [[ "$(share_runtime_state "${root}")" == "expired" && "${raw_status}" == "running" ]]; then
        cmd_share_expire_internal "${workspace_identity:-$root}" "$(share_state_value "${root}" "session_id")" >/dev/null 2>&1 || true
    fi

    state=$(share_runtime_state "${root}")
    transport=$(share_state_value "${root}" "transport")
    available_transports=$(share_available_transports_for_root "${root}")
    preferred_transport=$(share_default_transport_from_available "${available_transports}")
    if is_share_trusted_project "${root}"; then
        trusted="yes"
    fi
    mode=$(share_state_value "${root}" "mode")
    host_identity=$(share_state_value "${root}" "host_identity")
    repo_label=$(share_state_value "${root}" "repo_label")
    session_id=$(share_state_value "${root}" "session_id")
    started_at=$(share_state_value "${root}" "started_at")
    expires_at=$(share_state_value "${root}" "expires_at")
    expires_epoch=$(share_state_value "${root}" "expires_epoch")
    auth_mode=$(share_state_value "${root}" "auth_mode")
    share_token=$(share_state_value "${root}" "share_token")
    last_error=$(share_state_value "${root}" "last_error")
    cli=$(share_state_value "${root}" "cli")
    web_url=$(share_state_value "${root}" "web_url")
    execution_location=$(share_state_value "${root}" "execution_location")
    requested_path=$(share_state_value "${root}" "requested_path")
    reconnect_target=$(share_state_value "${root}" "reconnect_target")
    remote_authority=$(share_state_value "${root}" "remote_authority")
    remote_port=$(share_state_value "${root}" "remote_port")
    remote_label=$(share_state_value "${root}" "remote_label")
    [[ -n "${execution_location}" ]] || execution_location=$(share_execution_location_for_root "${root}")
    [[ -n "${workspace_identity}" ]] || workspace_identity=$(share_workspace_identity_for_root "${root}")
    [[ -n "${requested_path}" ]] || requested_path=$(share_requested_path_for_root "${root}")
    [[ -n "${remote_authority}" ]] || remote_authority=$(share_remote_authority_for_root "${root}")
    [[ -n "${remote_port}" ]] || remote_port=$(share_remote_port_for_root "${root}")
    [[ -n "${remote_label}" ]] || remote_label=$(share_remote_label_for_root "${root}")
    [[ ! "${expires_epoch}" =~ ^[0-9]+$ ]] && expires_epoch="0"
    if [[ "${expires_epoch}" -gt 0 ]]; then
        remaining_seconds=$(( expires_epoch - $(date +%s) ))
        if [[ "${remaining_seconds}" -lt 0 ]]; then
            remaining_seconds="0"
        fi
        remaining_text=$(share_format_ttl "${remaining_seconds}")
    fi
    if [[ -z "${transport}" ]]; then
        transport="${preferred_transport:-none}"
    fi
    if [[ "${state}" != "running" ]] && [[ "${state}" != "disconnected" ]]; then
        share_token=""
    fi
    transport_status=$(share_transport_status "${root}" "${state}" "${transport}")
    target_for_commands="${root}"
    if [[ "${execution_location}" == "remote" ]] && [[ -n "${workspace_identity}" ]]; then
        target_for_commands="${workspace_identity}"
    fi

    case "${format}" in
        text)
            echo ""
            yen_header "IDE Share Status"
            echo "Project root:       ${root}"
            echo "Execution location: ${execution_location}"
            if [[ -n "${workspace_identity}" ]]; then
                echo "Workspace identity: ${workspace_identity}"
            fi
            if [[ -n "${requested_path}" ]] && [[ "${requested_path}" != "${root}" ]]; then
                echo "Requested path:     ${requested_path}"
            fi
            if [[ -n "${remote_authority}" ]]; then
                if [[ -n "${remote_port}" ]]; then
                    echo "Remote authority:   ${remote_authority}:${remote_port}"
                else
                    echo "Remote authority:   ${remote_authority}"
                fi
            fi
            if [[ -n "${remote_label}" ]]; then
                echo "Remote label:       ${remote_label}"
            fi
            echo "Trusted:            ${trusted}"
            echo "State:              ${state}"
            echo "Transport:          ${transport:-none}"
            echo "Transport status:   ${transport_status}"
            echo "Available:          ${available_transports:-none}"
            if [[ -n "${preferred_transport}" ]]; then
                echo "Preferred:          ${preferred_transport}"
            fi
            if [[ -n "${session_id}" ]]; then
                echo "Session:            ${session_id}"
            fi
            if [[ -n "${mode}" ]]; then
                echo "Mode:               ${mode}"
            fi
            if [[ -n "${auth_mode}" ]]; then
                echo "Viewer auth:        ${auth_mode}"
                if [[ "${auth_mode}" == "passphrase" ]]; then
                    echo "Passphrase stored:  no"
                fi
            fi
            if [[ -n "${host_identity}" ]]; then
                echo "Host:               ${host_identity}"
            fi
            if [[ -n "${repo_label}" ]]; then
                echo "Repo label:         ${repo_label}"
            fi
            if [[ -n "${reconnect_target}" ]]; then
                echo "Reconnect target:   ${reconnect_target}"
            fi
            if [[ -n "${started_at}" ]]; then
                echo "Started at:         ${started_at}"
            fi
            if [[ -n "${expires_at}" ]]; then
                echo "Expires at:         ${expires_at}"
                echo "Time remaining:     ${remaining_text}"
            fi
            echo "Share token:        $( [[ -n "${share_token}" ]] && printf "present" || printf "none" )"
            if [[ -n "${web_url}" ]]; then
                echo "Web view:           ${web_url}"
            fi
            if [[ -n "${last_error}" ]]; then
                echo "Last error:         ${last_error}"
            fi
            if [[ "${SHARE_TARGET_USED_CACHED_REMOTE_ROOT}" == "1" ]]; then
                echo "Metadata source:    cached local session metadata"
            fi
            if [[ "${trusted}" != "yes" ]]; then
                echo ""
                echo "Grant consent with: yen ide share trust \"${target_for_commands}\""
            fi
            if [[ "${transport_status}" == "unavailable" ]]; then
                echo ""
                if [[ "${execution_location}" == "remote" ]]; then
                    echo "Install upterm (preferred) or tmate on the remote host, or set YEN_IDE_REMOTE_SHARE_UPTERM_CMD / YEN_IDE_REMOTE_SHARE_TMATE_CMD."
                else
                    echo "Install upterm (preferred) or tmate, or set YEN_IDE_SHARE_UPTERM_CMD / YEN_IDE_SHARE_TMATE_CMD."
                fi
            fi
            if [[ "${state}" == "disconnected" ]]; then
                echo ""
                echo "The remote host is temporarily unreachable. Session metadata is kept locally so you can retry when SSH access returns."
            fi
            echo ""
            ;;
        env)
            printf "export YEN_IDE_SHARE_ROOT=%s\n" "$(shell_quote_single "${root}")"
            printf "export YEN_IDE_SHARE_EXECUTION_LOCATION=%s\n" "$(shell_quote_single "${execution_location}")"
            printf "export YEN_IDE_SHARE_WORKSPACE_IDENTITY=%s\n" "$(shell_quote_single "${workspace_identity}")"
            printf "export YEN_IDE_SHARE_REQUESTED_PATH=%s\n" "$(shell_quote_single "${requested_path}")"
            printf "export YEN_IDE_SHARE_TRUSTED=%s\n" "$(shell_quote_single "${trusted}")"
            printf "export YEN_IDE_SHARE_STATE=%s\n" "$(shell_quote_single "${state}")"
            printf "export YEN_IDE_SHARE_TRANSPORT=%s\n" "$(shell_quote_single "${transport}")"
            printf "export YEN_IDE_SHARE_TRANSPORT_STATUS=%s\n" "$(shell_quote_single "${transport_status}")"
            printf "export YEN_IDE_SHARE_AVAILABLE=%s\n" "$(shell_quote_single "${available_transports}")"
            printf "export YEN_IDE_SHARE_PREFERRED=%s\n" "$(shell_quote_single "${preferred_transport}")"
            printf "export YEN_IDE_SHARE_MODE=%s\n" "$(shell_quote_single "${mode}")"
            printf "export YEN_IDE_SHARE_AUTH=%s\n" "$(shell_quote_single "${auth_mode}")"
            printf "export YEN_IDE_SHARE_HOST=%s\n" "$(shell_quote_single "${host_identity}")"
            printf "export YEN_IDE_SHARE_REPO_LABEL=%s\n" "$(shell_quote_single "${repo_label}")"
            printf "export YEN_IDE_SHARE_RECONNECT_TARGET=%s\n" "$(shell_quote_single "${reconnect_target}")"
            printf "export YEN_IDE_SHARE_REMOTE_AUTHORITY=%s\n" "$(shell_quote_single "${remote_authority}")"
            printf "export YEN_IDE_SHARE_REMOTE_PORT=%s\n" "$(shell_quote_single "${remote_port}")"
            printf "export YEN_IDE_SHARE_REMOTE_LABEL=%s\n" "$(shell_quote_single "${remote_label}")"
            printf "export YEN_IDE_SHARE_SESSION_ID=%s\n" "$(shell_quote_single "${session_id}")"
            printf "export YEN_IDE_SHARE_STARTED_AT=%s\n" "$(shell_quote_single "${started_at}")"
            printf "export YEN_IDE_SHARE_EXPIRES_AT=%s\n" "$(shell_quote_single "${expires_at}")"
            printf "export YEN_IDE_SHARE_TIME_REMAINING=%s\n" "$(shell_quote_single "${remaining_text}")"
            printf "export YEN_IDE_SHARE_TOKEN=%s\n" "$(shell_quote_single "${share_token}")"
            printf "export YEN_IDE_SHARE_WEB_URL=%s\n" "$(shell_quote_single "${web_url}")"
            printf "export YEN_IDE_SHARE_METADATA_SOURCE=%s\n" "$(shell_quote_single "$( [[ "${SHARE_TARGET_USED_CACHED_REMOTE_ROOT}" == "1" ]] && printf "cached-local-state" || printf "live-target" )")"
            printf "export YEN_IDE_SHARE_STATE_FILE=%s\n" "$(shell_quote_single "$(share_state_file "${root}")")"
            printf "export YEN_IDE_SHARE_PID_FILE=%s\n" "$(shell_quote_single "$(share_pid_file "${root}")")"
            printf "export YEN_IDE_SHARE_LOCK_DIR=%s\n" "$(shell_quote_single "$(share_lock_dir "${root}")")"
            ;;
        json)
            python3 - "${root}" "${execution_location}" "${workspace_identity}" "${requested_path}" "${trusted}" "${state}" "${transport}" "${transport_status}" "${available_transports}" "${preferred_transport}" "${mode}" "${auth_mode}" "${host_identity}" "${repo_label}" "${reconnect_target}" "${remote_authority}" "${remote_port}" "${remote_label}" "${session_id}" "${started_at}" "${expires_at}" "${remaining_text}" "${share_token}" "${web_url}" "${last_error}" "$( [[ "${SHARE_TARGET_USED_CACHED_REMOTE_ROOT}" == "1" ]] && printf "cached-local-state" || printf "live-target" )" "$(share_state_file "${root}")" "$(share_pid_file "${root}")" "$(share_lock_dir "${root}")" <<'PY'
import json
import sys

print(json.dumps(
    {
        "root": sys.argv[1],
        "executionLocation": sys.argv[2],
        "workspaceIdentity": sys.argv[3],
        "requestedPath": sys.argv[4],
        "trusted": sys.argv[5] == "yes",
        "state": sys.argv[6],
        "transport": sys.argv[7],
        "transportStatus": sys.argv[8],
        "availableTransports": [] if sys.argv[9] == "" else sys.argv[9].split(","),
        "preferredTransport": sys.argv[10],
        "mode": sys.argv[11],
        "auth": sys.argv[12],
        "hostIdentity": sys.argv[13],
        "repoLabel": sys.argv[14],
        "reconnectTarget": sys.argv[15],
        "remoteAuthority": sys.argv[16],
        "remotePort": int(sys.argv[17]) if sys.argv[17] else None,
        "remoteLabel": sys.argv[18],
        "sessionId": sys.argv[19],
        "startedAt": sys.argv[20],
        "expiresAt": sys.argv[21],
        "timeRemaining": sys.argv[22],
        "shareToken": sys.argv[23],
        "webUrl": sys.argv[24],
        "lastError": sys.argv[25],
        "metadataSource": sys.argv[26],
        "stateFile": sys.argv[27],
        "pidFile": sys.argv[28],
        "lockDir": sys.argv[29],
    },
    indent=2,
    sort_keys=True,
))
PY
            ;;
    esac
}

cmd_share_host() {
    local target=""
    local transport_request="${YEN_IDE_SHARE_TRANSPORT:-auto}"
    local mode="read-only"
    local ttl_seconds=""
    local passphrase=""
    local format="text"
    local replace="0"
    local root=""
    local lock_dir=""
    local state=""
    local transport=""
    local cli=""
    local session_id=""
    local started_at=""
    local expires_epoch=""
    local expires_at=""
    local host_identity=""
    local repo_label=""
    local join_command=""
    local web_url=""
    local share_token=""
    local token_payload=""
    local host_command=""
    local admin_socket=""
    local wrapper_script=""
    local command_script=""
    local session_json=""
    local session_meta=""
    local pid=""
    local attempts=0
    local max_attempts=120
    local lock_released="0"
    local execution_location=""
    local workspace_identity=""
    local requested_path=""
    local reconnect_target=""
    local remote_authority=""
    local remote_port=""
    local remote_label=""
    local remote_state_dir=""
    local remote_pid=""
    local remote_admin_socket=""
    local remote_socket_file=""
    local available_transports=""
    local active_session="0"
    local remote_payload=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --transport)
                shift
                transport_request="${1:-auto}"
                ;;
            --read-only)
                mode="read-only"
                ;;
            --interactive)
                mode="interactive"
                ;;
            --ttl-minutes)
                shift
                ttl_seconds="$(( ${1:-60} * 60 ))"
                ;;
            --ttl-seconds)
                shift
                ttl_seconds="${1:-}"
                ;;
            --passphrase)
                shift
                passphrase="${1:-}"
                ;;
            --replace)
                replace="1"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    if ! share_output_format_valid "${format}"; then
        yen_error "Unknown share host format: ${format} (expected text|env|json)"
        return 1
    fi
    case "${transport_request}" in
        auto|upterm|tmate)
            ;;
        *)
            yen_error "Unknown share transport: ${transport_request} (expected auto|upterm|tmate)"
            return 1
            ;;
    esac
    if [[ -z "${ttl_seconds}" ]]; then
        ttl_seconds=$(share_default_ttl_seconds)
    fi
    if [[ ! "${ttl_seconds}" =~ ^[0-9]+$ ]] || [[ "${ttl_seconds}" -lt 1 ]]; then
        yen_error "Invalid share TTL '${ttl_seconds}'. Use --ttl-seconds <positive integer> or --ttl-minutes <positive integer>."
        return 1
    fi
    if [[ -z "${passphrase}" ]]; then
        passphrase=$(share_generate_passphrase)
    fi
    if ! share_resolve_target "${target}" "0"; then
        return 1
    fi
    root="${SHARE_TARGET_ROOT}"
    execution_location=$(share_execution_location_for_root "${root}")
    workspace_identity=$(share_workspace_identity_for_root "${root}")
    requested_path=$(share_requested_path_for_root "${root}")
    remote_authority=$(share_remote_authority_for_root "${root}")
    remote_port=$(share_remote_port_for_root "${root}")
    remote_label=$(share_remote_label_for_root "${root}")

    lock_dir=$(share_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "IDE share lifecycle"; then
        return 1
    fi
    trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR

    if ! ensure_share_trusted_or_prompt "${root}"; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 1
    fi
    if ! share_require_crypto_support; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 1
    fi

    state=$(share_runtime_state "${root}")
    if [[ "${state}" == "running" || "${state}" == "disconnected" ]]; then
        active_session="1"
    fi
    if [[ "${active_session}" == "1" && "${replace}" != "1" ]]; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        yen_error "A share session is already active for ${root}. Revoke it first or re-run with --replace."
        return 1
    fi
    if [[ "${active_session}" == "1" && "${replace}" == "1" ]]; then
        if ! share_finalize_session_locked "${root}" "revoked" "share-revoke" "reason=replace;session=$(share_state_value "${root}" "session_id");transport=$(share_state_value "${root}" "transport")" "strict"; then
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            yen_error "Unable to replace the existing share session for ${root}: ${SHARE_REMOTE_LAST_STDERR:-remote cleanup failed}"
            return 1
        fi
    else
        cleanup_share_runtime_artifacts "${root}" "0"
    fi

    available_transports=$(share_available_transports_for_root "${root}")
    transport=$(share_select_transport_from_available "${transport_request}" "${available_transports}")
    if [[ -z "${transport}" ]]; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        yen_error "No supported sharing transport is available."
        if [[ "${execution_location}" == "remote" ]]; then
            yen_info "Install upterm (preferred) or tmate on the remote host, or set YEN_IDE_REMOTE_SHARE_UPTERM_CMD / YEN_IDE_REMOTE_SHARE_TMATE_CMD."
        else
            yen_info "Install upterm (preferred) or tmate, or set YEN_IDE_SHARE_UPTERM_CMD / YEN_IDE_SHARE_TMATE_CMD."
        fi
        return 1
    fi

    case "${transport}" in
        upterm)
            if [[ "${execution_location}" == "remote" ]]; then
                cli=$(share_remote_upterm_command)
            else
                cli=$(share_upterm_command)
            fi
            ;;
        tmate)
            if [[ "${execution_location}" == "remote" ]]; then
                cli=$(share_remote_tmate_command)
            else
                cli=$(share_tmate_command)
            fi
            ;;
    esac

    session_id=$(share_generate_session_id)
    started_at=$(iso_now)
    expires_epoch=$(( $(date +%s) + ttl_seconds ))
    expires_at=$(epoch_to_iso_utc "${expires_epoch}")
    if [[ "${execution_location}" == "remote" ]]; then
        remote_payload=$(share_remote_start_session "${remote_authority}" "${remote_port}" "${root}" "${transport}" "${mode}" "${ttl_seconds}" "${session_id}" || true)
        if [[ -z "${remote_payload}" ]]; then
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            yen_error "Failed to start remote share host for ${workspace_identity:-$root}: ${SHARE_REMOTE_LAST_STDERR:-remote share helper failed}"
            return 1
        fi
        cli=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("cli", ""))
PY
)
        host_identity=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("hostIdentity", ""))
PY
)
        repo_label=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("repoLabel", ""))
PY
)
        session_id=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("sessionId", ""))
PY
)
        started_at=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("startedAt", ""))
PY
)
        join_command=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("joinCommand", ""))
PY
)
        reconnect_target=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("reconnectTarget", ""))
PY
)
        web_url=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("webUrl", ""))
PY
)
        remote_state_dir=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("remoteStateDir", ""))
PY
)
        remote_pid=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("remotePid", ""))
PY
)
        remote_admin_socket=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("remoteAdminSocket", ""))
PY
)
        remote_socket_file=$(python3 - "${remote_payload}" <<'PY'
import json
import sys
print((json.loads(sys.argv[1] or "{}")).get("remoteSocketFile", ""))
PY
)
    else
        host_identity=$(share_host_identity)
        repo_label=$(share_repo_label "${root}")
        mkdir -p "$(share_project_dir "${root}")"
        wrapper_script=$(share_wrapper_script_file "${root}")
        case "${transport}" in
            upterm)
                admin_socket=$(share_upterm_admin_file "${root}")
                command_script=$(share_upterm_command_script_file "${root}")
                atomic_write_text "${command_script}" "#!/bin/bash
set -e
cd $(shell_quote_single "${root}")
printf \"%s\\n\" \"\${UPTERM_ADMIN_SOCKET:-}\" > $(shell_quote_single "${admin_socket}")
exec \${SHELL:-/bin/bash} -l
"
                chmod 755 "${command_script}"
                host_command="#!/bin/bash
set -e
cd $(shell_quote_single "${root}")
export YEN_IDE_SHARE_UPTERM_ADMIN_SOCKET_FILE=$(shell_quote_single "${admin_socket}")
export YEN_IDE_SHARE_UPTERM_SESSION_FILE=$(shell_quote_single "$(share_upterm_session_file "${root}")")
exec ${cli} host $( [[ "${mode}" == "read-only" ]] && printf -- "--read-only " )-- bash $(shell_quote_single "${command_script}")
"
                ;;
            tmate)
                host_command="#!/bin/bash
set -e
cd $(shell_quote_single "${root}")
${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") new-session -d
${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") wait tmate-ready
while true; do sleep 60; done
"
                ;;
        esac
        atomic_write_text "${wrapper_script}" "${host_command}"
        chmod 755 "${wrapper_script}"
        nohup bash "${wrapper_script}" >/dev/null 2>&1 &
        pid=$!
        atomic_write_text "$(share_pid_file "${root}")" "$(printf "%s\n" "${pid}")"

        while [[ "${attempts}" -lt "${max_attempts}" ]]; do
            case "${transport}" in
                upterm)
                    if ! share_pid_matches_runtime "${root}" "${pid}"; then
                        break
                    fi
                    admin_socket=$(tr -d '[:space:]' < "$(share_upterm_admin_file "${root}")" 2>/dev/null | sed -n '1p' || true)
                    if [[ -n "${admin_socket}" ]]; then
                        session_json=$(UPTERM_ADMIN_SOCKET="${admin_socket}" bash -lc "${cli} session current -o json" 2>/dev/null || true)
                        if [[ -n "${session_json}" ]]; then
                            session_meta=$(share_parse_upterm_session "${session_json}" "${mode}" 2>/dev/null || true)
                            join_command=$(printf "%s\n" "${session_meta}" | sed -nE 's/^join_command=(.*)$/\1/p' | head -n 1)
                            web_url=$(printf "%s\n" "${session_meta}" | sed -nE 's/^web_url=(.*)$/\1/p' | head -n 1)
                            local parsed_session_id=""
                            parsed_session_id=$(printf "%s\n" "${session_meta}" | sed -nE 's/^session_id=(.*)$/\1/p' | head -n 1)
                            if [[ -n "${parsed_session_id}" ]]; then
                                session_id="${parsed_session_id}"
                            fi
                            if [[ -n "${join_command}" ]]; then
                                reconnect_target=$(share_reconnect_target_from_join_command "${join_command}")
                                break
                            fi
                        fi
                    fi
                    ;;
                tmate)
                    if ! share_pid_matches_runtime "${root}" "${pid}"; then
                        break
                    fi
                    local join_format='#{tmate_ssh_ro}'
                    local web_format='#{tmate_web_ro}'
                    if [[ "${mode}" == "interactive" ]]; then
                        join_format='#{tmate_ssh}'
                        web_format='#{tmate_web}'
                    fi
                    join_command=$(bash -lc "${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") display -p $(shell_quote_single "${join_format}")" 2>/dev/null | tr -d '\r' | sed -n '1p' || true)
                    web_url=$(bash -lc "${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") display -p $(shell_quote_single "${web_format}")" 2>/dev/null | tr -d '\r' | sed -n '1p' || true)
                    if [[ -n "${join_command}" ]]; then
                        reconnect_target=$(share_reconnect_target_from_join_command "${join_command}")
                        break
                    fi
                    ;;
            esac
            sleep 0.1
            attempts=$((attempts + 1))
        done

        if [[ -z "${join_command}" ]]; then
            if [[ "${transport}" == "tmate" && -n "${cli}" && -e "$(share_tmate_socket_file "${root}")" ]]; then
                bash -lc "${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") kill-server" >/dev/null 2>&1 || true
            fi
            if share_pid_matches_runtime "${root}" "${pid}"; then
                kill "${pid}" 2>/dev/null || true
            fi
            cleanup_share_runtime_artifacts "${root}" "0"
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            yen_error "Failed to start share host for ${root}."
            return 1
        fi
    fi

    token_payload=$(share_build_token_payload "${session_id}" "${transport}" "${mode}" "${host_identity}" "${repo_label}" "${expires_at}" "passphrase" "${join_command}" "${web_url}" "${execution_location}" "${workspace_identity}" "${requested_path}" "${reconnect_target}")
    share_token=$(share_encrypt_payload "${token_payload}" "${passphrase}")
    if [[ -z "${share_token}" ]]; then
        if [[ "${execution_location}" == "remote" ]]; then
            share_remote_revoke_session_values "${remote_authority}" "${remote_port}" "${transport}" "${cli}" "${remote_state_dir}" "${remote_pid}" "${remote_socket_file}" >/dev/null 2>&1 || true
        else
            if [[ "${transport}" == "tmate" && -n "${cli}" && -e "$(share_tmate_socket_file "${root}")" ]]; then
                bash -lc "${cli} -S $(shell_quote_single "$(share_tmate_socket_file "${root}")") kill-server" >/dev/null 2>&1 || true
            fi
            if share_pid_matches_runtime "${root}" "${pid}"; then
                kill "${pid}" 2>/dev/null || true
            fi
        fi
        cleanup_share_runtime_artifacts "${root}" "0"
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        yen_error "Failed to generate an encrypted share token for ${root}."
        return 1
    fi

    write_share_state \
        "${root}" \
        "running" \
        "${transport}" \
        "${mode}" \
        "${host_identity}" \
        "${repo_label}" \
        "${session_id}" \
        "${started_at}" \
        "${expires_at}" \
        "${expires_epoch}" \
        "passphrase" \
        "${share_token}" \
        "available" \
        "" \
        "" \
        "" \
        "${ttl_seconds}" \
        "${cli}" \
        "${web_url}" \
        "${execution_location}" \
        "${workspace_identity}" \
        "${requested_path}" \
        "${reconnect_target}" \
        "${remote_authority}" \
        "${remote_port}" \
        "${remote_label}" \
        "${remote_state_dir}" \
        "${remote_pid}" \
        "${remote_admin_socket}" \
        "${remote_socket_file}"
    share_start_expiry_watcher "${root}" "${session_id}" "${ttl_seconds}"
    timeline_log "share-host" "${root}" "running" "transport=${transport};mode=${mode};session=${session_id};ttl=${ttl_seconds};location=${execution_location}"
    lock_released="1"
    release_state_lock "${lock_dir}"
    trap - ERR

    case "${format}" in
        text)
            echo ""
            yen_header "IDE Share Host"
            echo "Project root:       ${root}"
            echo "Execution location: ${execution_location}"
            if [[ -n "${workspace_identity}" ]]; then
                echo "Workspace identity: ${workspace_identity}"
            fi
            if [[ -n "${requested_path}" ]] && [[ "${requested_path}" != "${root}" ]]; then
                echo "Requested path:     ${requested_path}"
            fi
            echo "Transport:          ${transport}"
            echo "Mode:               ${mode}"
            echo "Viewer auth:        passphrase"
            echo "Host:               ${host_identity}"
            echo "Repo label:         ${repo_label}"
            if [[ -n "${reconnect_target}" ]]; then
                echo "Reconnect target:   ${reconnect_target}"
            fi
            echo "Session:            ${session_id}"
            echo "Started at:         ${started_at}"
            echo "Expires at:         ${expires_at}"
            echo "Time remaining:     $(share_format_ttl "${ttl_seconds}")"
            echo "Share token:        ${share_token}"
            echo "Passphrase:         ${passphrase}"
            echo "Join:               yen ide share join --token $(shell_quote_single "${share_token}") --passphrase $(shell_quote_single "${passphrase}")"
            if [[ -n "${web_url}" ]]; then
                echo "Web view:           ${web_url}"
            fi
            echo ""
            ;;
        env)
            printf "export YEN_IDE_SHARE_ROOT=%s\n" "$(shell_quote_single "${root}")"
            printf "export YEN_IDE_SHARE_EXECUTION_LOCATION=%s\n" "$(shell_quote_single "${execution_location}")"
            printf "export YEN_IDE_SHARE_WORKSPACE_IDENTITY=%s\n" "$(shell_quote_single "${workspace_identity}")"
            printf "export YEN_IDE_SHARE_REQUESTED_PATH=%s\n" "$(shell_quote_single "${requested_path}")"
            printf "export YEN_IDE_SHARE_TRANSPORT=%s\n" "$(shell_quote_single "${transport}")"
            printf "export YEN_IDE_SHARE_MODE=%s\n" "$(shell_quote_single "${mode}")"
            printf "export YEN_IDE_SHARE_HOST=%s\n" "$(shell_quote_single "${host_identity}")"
            printf "export YEN_IDE_SHARE_REPO_LABEL=%s\n" "$(shell_quote_single "${repo_label}")"
            printf "export YEN_IDE_SHARE_RECONNECT_TARGET=%s\n" "$(shell_quote_single "${reconnect_target}")"
            printf "export YEN_IDE_SHARE_REMOTE_AUTHORITY=%s\n" "$(shell_quote_single "${remote_authority}")"
            printf "export YEN_IDE_SHARE_REMOTE_PORT=%s\n" "$(shell_quote_single "${remote_port}")"
            printf "export YEN_IDE_SHARE_REMOTE_LABEL=%s\n" "$(shell_quote_single "${remote_label}")"
            printf "export YEN_IDE_SHARE_SESSION_ID=%s\n" "$(shell_quote_single "${session_id}")"
            printf "export YEN_IDE_SHARE_STARTED_AT=%s\n" "$(shell_quote_single "${started_at}")"
            printf "export YEN_IDE_SHARE_EXPIRES_AT=%s\n" "$(shell_quote_single "${expires_at}")"
            printf "export YEN_IDE_SHARE_TOKEN=%s\n" "$(shell_quote_single "${share_token}")"
            printf "export YEN_IDE_SHARE_PASSPHRASE=%s\n" "$(shell_quote_single "${passphrase}")"
            printf "export YEN_IDE_SHARE_JOIN=%s\n" "$(shell_quote_single "yen ide share join --token '${share_token}' --passphrase '${passphrase}'")"
            ;;
        json)
            python3 - "${root}" "${execution_location}" "${workspace_identity}" "${requested_path}" "${transport}" "${mode}" "${host_identity}" "${repo_label}" "${reconnect_target}" "${remote_authority}" "${remote_port}" "${remote_label}" "${session_id}" "${started_at}" "${expires_at}" "${share_token}" "${passphrase}" "${web_url}" <<'PY'
import json
import sys

token = sys.argv[16]
passphrase = sys.argv[17]
print(json.dumps(
    {
        "root": sys.argv[1],
        "executionLocation": sys.argv[2],
        "workspaceIdentity": sys.argv[3],
        "requestedPath": sys.argv[4],
        "transport": sys.argv[5],
        "mode": sys.argv[6],
        "hostIdentity": sys.argv[7],
        "repoLabel": sys.argv[8],
        "reconnectTarget": sys.argv[9],
        "remoteAuthority": sys.argv[10],
        "remotePort": int(sys.argv[11]) if sys.argv[11] else None,
        "remoteLabel": sys.argv[12],
        "sessionId": sys.argv[13],
        "startedAt": sys.argv[14],
        "expiresAt": sys.argv[15],
        "shareToken": token,
        "passphrase": passphrase,
        "joinCommand": f"yen ide share join --token '{token}' --passphrase '{passphrase}'",
        "webUrl": sys.argv[18],
    },
    indent=2,
    sort_keys=True,
))
PY
            ;;
        *)
            yen_error "Unknown share host format: ${format} (expected text|env|json)"
            return 1
            ;;
    esac
}

cmd_share_join() {
    local token=""
    local passphrase=""
    local print_command="0"
    local payload=""
    local join_command=""
    local transport=""
    local mode=""
    local host_identity=""
    local repo_label=""
    local session_id=""
    local expires_at=""
    local auth_mode=""
    local web_url=""
    local execution_location=""
    local workspace_identity=""
    local requested_path=""
    local reconnect_target=""
    local timeline_root="share:unknown"
    local ssh_target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token)
                shift
                token="${1:-}"
                ;;
            --passphrase)
                shift
                passphrase="${1:-}"
                ;;
            --print-command|--dry-run)
                print_command="1"
                ;;
            *)
                if [[ -z "${token}" ]]; then
                    token="$1"
                else
                    yen_error "Unknown share join option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -z "${token}" ]]; then
        yen_error "share join requires --token <encrypted-token>."
        return 1
    fi
    if [[ -z "${passphrase}" ]]; then
        passphrase=$(share_prompt_for_passphrase "Share passphrase: " || true)
    fi
    if [[ -z "${passphrase}" ]]; then
        yen_error "share join requires a passphrase."
        return 1
    fi

    payload=$(share_decrypt_payload "${token}" "${passphrase}" || true)
    if [[ -z "${payload}" ]]; then
        timeline_log "share-join" "${timeline_root}" "auth-failed" "transport=unknown"
        yen_error "Invalid share token or passphrase."
        return 1
    fi
    if ! share_token_payload_valid "${payload}" >/dev/null 2>&1; then
        timeline_log "share-join" "${timeline_root}" "auth-failed" "transport=unknown"
        yen_error "Invalid share token or passphrase."
        return 1
    fi

    join_command=$(share_token_json_field "${payload}" "joinCommand" || true)
    transport=$(share_token_json_field "${payload}" "transport" || true)
    mode=$(share_token_json_field "${payload}" "mode" || true)
    host_identity=$(share_token_json_field "${payload}" "hostIdentity" || true)
    repo_label=$(share_token_json_field "${payload}" "repoLabel" || true)
    session_id=$(share_token_json_field "${payload}" "sessionId" || true)
    expires_at=$(share_token_json_field "${payload}" "expiresAt" || true)
    auth_mode=$(share_token_json_field "${payload}" "authMode" || true)
    web_url=$(share_token_json_field "${payload}" "webUrl" || true)
    execution_location=$(share_token_json_field "${payload}" "executionLocation" || true)
    workspace_identity=$(share_token_json_field "${payload}" "workspaceIdentity" || true)
    requested_path=$(share_token_json_field "${payload}" "requestedPath" || true)
    reconnect_target=$(share_token_json_field "${payload}" "reconnectTarget" || true)
    timeline_root="share:${host_identity}/${repo_label}"

    if ! share_join_metadata_valid "${transport}" "${mode}" "${join_command}"; then
        timeline_log "share-join" "${timeline_root}" "invalid" "session=${session_id};transport=${transport}"
        yen_error "Share token is missing or has invalid join metadata."
        return 1
    fi
    ssh_target=$(share_join_target "${join_command}" || true)
    if [[ -z "${reconnect_target}" ]]; then
        reconnect_target="${ssh_target}"
    fi
    if [[ -z "${ssh_target}" ]]; then
        timeline_log "share-join" "${timeline_root}" "invalid" "session=${session_id};transport=${transport}"
        yen_error "Share token is missing or has invalid join metadata."
        return 1
    fi
    if [[ "$(iso_to_epoch_utc "${expires_at}")" -le "$(date +%s)" ]]; then
        timeline_log "share-join" "${timeline_root}" "expired" "session=${session_id};transport=${transport}"
        yen_error "This share token has expired."
        return 1
    fi

    echo ""
    yen_header "IDE Share Join"
    if [[ -n "${execution_location}" ]]; then
        echo "Execution location: ${execution_location}"
    fi
    if [[ -n "${workspace_identity}" ]]; then
        echo "Workspace identity: ${workspace_identity}"
    fi
    if [[ -n "${requested_path}" ]]; then
        echo "Requested path:     ${requested_path}"
    fi
    echo "Host:               ${host_identity}"
    echo "Repo label:         ${repo_label}"
    echo "Reconnect target:   ${reconnect_target}"
    echo "Session:            ${session_id}"
    echo "Transport:          ${transport}"
    echo "Mode:               ${mode}"
    echo "Viewer auth:        ${auth_mode}"
    echo "Expires at:         ${expires_at}"
    if [[ -n "${web_url}" ]]; then
        echo "Web view:           ${web_url}"
    fi
    echo ""

    if [[ "${print_command}" == "1" ]]; then
        printf "ssh %s\n" "${ssh_target}"
        timeline_log "share-join" "${timeline_root}" "dry-run" "session=${session_id};transport=${transport};mode=${mode}"
        return 0
    fi

    timeline_log "share-join" "${timeline_root}" "start" "session=${session_id};transport=${transport};mode=${mode}"
    command ssh "${ssh_target}"
    local join_status=$?
    if [[ "${join_status}" -eq 0 ]]; then
        timeline_log "share-join" "${timeline_root}" "ok" "session=${session_id};transport=${transport};mode=${mode}"
    else
        timeline_log "share-join" "${timeline_root}" "failed" "session=${session_id};transport=${transport};mode=${mode};status=${join_status}"
    fi
    return "${join_status}"
}

cmd_share() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        status)
            cmd_share_status "$@"
            ;;
        host)
            cmd_share_host "$@"
            ;;
        join)
            cmd_share_join "$@"
            ;;
        revoke|stop)
            local root=""
            local target=""
            local revoke_status=0
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        target="${1:-}"
                        ;;
                    *)
                        target="$1"
                        ;;
                esac
                shift
            done
            if ! share_resolve_target "${target}" "1"; then
                return 1
            fi
            root="${SHARE_TARGET_ROOT}"
            cmd_share_revoke_internal "${root}" "manual"
            revoke_status=$?
            if [[ "${revoke_status}" -eq 2 ]]; then
                yen_info "Share session already inactive for ${root}."
                return 0
            fi
            if [[ "${revoke_status}" -ne 0 ]]; then
                if [[ -n "${SHARE_REMOTE_LAST_STDERR}" ]]; then
                    yen_error "Unable to revoke share session for ${root}: ${SHARE_REMOTE_LAST_STDERR}"
                fi
                return 1
            fi
            yen_success "Share session revoked: ${root}"
            ;;
        trust)
            local root=""
            local target=""
            local lock_dir=""
            local lock_released="0"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        target="${1:-}"
                        ;;
                    *)
                        target="$1"
                        ;;
                esac
                shift
            done
            if ! share_resolve_target "${target}" "0"; then
                return 1
            fi
            root="${SHARE_TARGET_ROOT}"
            lock_dir=$(share_lock_dir "${root}")
            if ! acquire_state_lock "${lock_dir}" "IDE share lifecycle"; then
                return 1
            fi
            trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR
            if is_share_trusted_project "${root}"; then
                lock_released="1"
                release_state_lock "${lock_dir}"
                trap - ERR
                yen_info "Project already trusted for sharing: ${root}"
                return 0
            fi
            if ! trust_share_project "${root}"; then
                lock_released="1"
                release_state_lock "${lock_dir}"
                trap - ERR
                yen_error "Failed to update sharing trust for ${root}."
                return 1
            fi
            if ! timeline_log "share-trust" "${root}" "trusted" "source=manual"; then
                lock_released="1"
                release_state_lock "${lock_dir}"
                trap - ERR
                yen_error "Failed to write sharing trust audit event for ${root}."
                return 1
            fi
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            yen_success "Trusted project for sharing: ${root}"
            ;;
        untrust)
            local root=""
            local target=""
            local lock_dir=""
            local lock_released="0"
            local runtime_state=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        target="${1:-}"
                        ;;
                    *)
                        target="$1"
                        ;;
                esac
                shift
            done
            if ! share_resolve_target "${target}" "1"; then
                return 1
            fi
            root="${SHARE_TARGET_ROOT}"
            lock_dir=$(share_lock_dir "${root}")
            if ! acquire_state_lock "${lock_dir}" "IDE share lifecycle"; then
                return 1
            fi
            trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR
            runtime_state=$(share_runtime_state "${root}")
            if [[ "${runtime_state}" == "running" || "${runtime_state}" == "disconnected" ]]; then
                if ! share_finalize_session_locked "${root}" "revoked" "share-revoke" "reason=untrust;session=$(share_state_value "${root}" "session_id");transport=$(share_state_value "${root}" "transport")" "strict"; then
                    lock_released="1"
                    release_state_lock "${lock_dir}"
                    trap - ERR
                    yen_error "Unable to revoke the active share session for ${root}: ${SHARE_REMOTE_LAST_STDERR:-remote cleanup failed}"
                    return 1
                fi
            fi
            if ! untrust_share_project "${root}"; then
                lock_released="1"
                release_state_lock "${lock_dir}"
                trap - ERR
                yen_error "Failed to remove sharing trust for ${root}."
                return 1
            fi
            if ! timeline_log "share-trust" "${root}" "untrusted" "source=manual"; then
                lock_released="1"
                release_state_lock "${lock_dir}"
                trap - ERR
                yen_error "Failed to write sharing trust audit event for ${root}."
                return 1
            fi
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            yen_success "Removed sharing trust: ${root}"
            ;;
        trusted|list)
            ensure_state_dirs
            if [[ ! -s "${IDE_SHARE_TRUST_FILE}" ]]; then
                yen_info "No share-trusted projects."
                return 0
            fi
            echo ""
            yen_header "Trusted Share Projects"
            nl -ba "${IDE_SHARE_TRUST_FILE}"
            echo ""
            ;;
        __expire)
            local root=""
            local session_id=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        if share_resolve_target "${1:-}" "1"; then
                            root="${SHARE_TARGET_ROOT}"
                        else
                            root=""
                        fi
                        ;;
                    --session-id)
                        shift
                        session_id="${1:-}"
                        ;;
                esac
                shift
            done
            if [[ -n "${root}" && -n "${session_id}" ]]; then
                cmd_share_expire_internal "${root}" "${session_id}" >/dev/null 2>&1 || true
            fi
            ;;
        *)
            yen_error "Unknown share subcommand: ${sub}"
            return 1
            ;;
    esac
}

