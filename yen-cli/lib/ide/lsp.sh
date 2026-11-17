# shellcheck shell=bash
# Source-time pure LSP helpers and command handlers for yen ide.

lsp_force_placeholder() {
    [[ "${YEN_IDE_LSP_FORCE_PLACEHOLDER:-0}" == "1" ]]
}

lsp_resolved_command() {
    local root="$1"
    local runtime=""
    local tooling=""
    local managed_command=""

    if lsp_force_placeholder; then
        return 0
    fi
    if [[ -n "${YEN_IDE_LSP_SERVER_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_LSP_SERVER_CMD}"
        return 0
    fi

    runtime=$(detect_runtime_context "${root}")
    tooling=$(detect_tooling_context "${root}")

    if csv_has_token "${runtime}" "go"; then
        managed_command=$(lsp_managed_server_command "go")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "rust"; then
        managed_command=$(lsp_managed_server_command "rust")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "swift"; then
        managed_command=$(lsp_managed_server_command "swift")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "zig"; then
        managed_command=$(lsp_managed_server_command "zig")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "python"; then
        managed_command=$(lsp_managed_server_command "python")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "node"; then
        managed_command=$(lsp_managed_server_command "typescript")
        if [[ -n "${managed_command}" ]]; then
            printf "%s\n" "${managed_command}"
            return 0
        fi
    fi

    if csv_has_token "${runtime}" "go" && command -v gopls >/dev/null 2>&1; then
        printf "gopls\n"
        return 0
    fi
    if csv_has_token "${runtime}" "rust" && command -v rust-analyzer >/dev/null 2>&1; then
        printf "rust-analyzer\n"
        return 0
    fi
    if csv_has_token "${runtime}" "swift" && command -v sourcekit-lsp >/dev/null 2>&1; then
        printf "sourcekit-lsp\n"
        return 0
    fi
    if csv_has_token "${runtime}" "zig" && command -v zls >/dev/null 2>&1; then
        printf "zls\n"
        return 0
    fi
    if csv_has_token "${runtime}" "python"; then
        if command -v pyright-langserver >/dev/null 2>&1; then
            printf "pyright-langserver --stdio\n"
            return 0
        fi
        if command -v basedpyright-langserver >/dev/null 2>&1; then
            printf "basedpyright-langserver --stdio\n"
            return 0
        fi
    fi
    if csv_has_token "${runtime}" "node" && command -v typescript-language-server >/dev/null 2>&1; then
        if csv_has_token "${tooling}" "typescript"; then
            printf "typescript-language-server --stdio\n"
            return 0
        fi
        printf "typescript-language-server --stdio\n"
        return 0
    fi
}

lsp_resolved_protocol_mode() {
    local root="$1"
    local command_string=""
    command_string=$(lsp_resolved_command "${root}")
    if [[ -n "${command_string}" ]]; then
        printf "stdio\n"
    else
        printf "placeholder\n"
    fi
}

lsp_resolved_impl() {
    local root="$1"
    local command_string=""
    command_string=$(lsp_resolved_command "${root}")
    if [[ -n "${command_string}" ]]; then
        printf "stdio-language-server\n"
    else
        printf "placeholder-socket-daemon\n"
    fi
}

lsp_resolved_label() {
    local root="$1"
    local command_string=""
    local tooling=""
    local first_token=""

    if lsp_force_placeholder; then
        printf "placeholder-socket-daemon\n"
        return 0
    fi
    if [[ -n "${YEN_IDE_LSP_SERVER_CMD:-}" ]]; then
        if [[ -n "${YEN_IDE_LSP_SERVER_LABEL:-}" ]]; then
            printf "%s\n" "${YEN_IDE_LSP_SERVER_LABEL}"
        else
            printf "custom-lsp-server\n"
        fi
        return 0
    fi

    command_string=$(lsp_resolved_command "${root}")
    if [[ -z "${command_string}" ]]; then
        printf "placeholder-socket-daemon\n"
        return 0
    fi

    tooling=$(detect_tooling_context "${root}")
    if csv_has_token "${tooling}" "typescript"; then
        printf "typescript-language-server\n"
        return 0
    fi

    first_token=$(printf "%s\n" "${command_string}" | awk '{print $1}')
    printf "%s\n" "$(basename "${first_token}")"
}

lsp_resolved_language_id() {
    local root="$1"
    local runtime=""
    local tooling=""

    if [[ -n "${YEN_IDE_LSP_SERVER_LANGUAGE_ID:-}" ]]; then
        printf "%s\n" "${YEN_IDE_LSP_SERVER_LANGUAGE_ID}"
        return 0
    fi

    runtime=$(detect_runtime_context "${root}")
    tooling=$(detect_tooling_context "${root}")

    if csv_has_token "${runtime}" "go"; then
        printf "go\n"
        return 0
    fi
    if csv_has_token "${runtime}" "rust"; then
        printf "rust\n"
        return 0
    fi
    if csv_has_token "${runtime}" "python"; then
        printf "python\n"
        return 0
    fi
    if csv_has_token "${runtime}" "swift"; then
        printf "swift\n"
        return 0
    fi
    if csv_has_token "${runtime}" "zig"; then
        printf "zig\n"
        return 0
    fi
    if csv_has_token "${runtime}" "node"; then
        if csv_has_token "${tooling}" "typescript"; then
            printf "typescript\n"
        else
            printf "javascript\n"
        fi
        return 0
    fi
}

lsp_resolved_extensions() {
    local root="$1"
    local runtime=""
    local tooling=""

    if [[ -n "${YEN_IDE_LSP_SERVER_EXTENSIONS:-}" ]]; then
        printf "%s\n" "${YEN_IDE_LSP_SERVER_EXTENSIONS}"
        return 0
    fi

    runtime=$(detect_runtime_context "${root}")
    tooling=$(detect_tooling_context "${root}")

    if csv_has_token "${runtime}" "go"; then
        printf ".go\n"
        return 0
    fi
    if csv_has_token "${runtime}" "rust"; then
        printf ".rs\n"
        return 0
    fi
    if csv_has_token "${runtime}" "python"; then
        printf ".py\n"
        return 0
    fi
    if csv_has_token "${runtime}" "swift"; then
        printf ".swift\n"
        return 0
    fi
    if csv_has_token "${runtime}" "zig"; then
        printf ".zig,.zon\n"
        return 0
    fi
    if csv_has_token "${runtime}" "node"; then
        if csv_has_token "${tooling}" "typescript"; then
            printf ".ts,.tsx,.mts,.cts\n"
        else
            printf ".js,.jsx,.mjs,.cjs\n"
        fi
        return 0
    fi
}

lsp_detected_language() {
    local root="$1"
    local runtime=""
    local language_id=""

    language_id=$(lsp_resolved_language_id "${root}")
    if [[ -n "${language_id}" ]]; then
        printf "%s\n" "${language_id}"
        return 0
    fi

    runtime=$(detect_runtime_context "${root}")
    if csv_has_token "${runtime}" "zig"; then
        printf "zig\n"
        return 0
    fi
    if csv_has_token "${runtime}" "bun"; then
        printf "bun\n"
        return 0
    fi
    if csv_has_token "${runtime}" "unknown"; then
        printf "unknown\n"
        return 0
    fi
    printf "%s\n" "$(printf "%s\n" "${runtime}" | cut -d, -f1)"
}

lsp_expected_server() {
    local root="$1"
    local language=""

    language=$(lsp_detected_language "${root}")
    lsp_expected_server_for_language "${language}"
}

lsp_expected_server_for_language() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        typescript|javascript|node|bun)
            printf "typescript-language-server --stdio\n"
            ;;
        go)
            printf "gopls\n"
            ;;
        rust)
            printf "rust-analyzer\n"
            ;;
        python)
            printf "pyright-langserver --stdio (or basedpyright-langserver --stdio)\n"
            ;;
        swift)
            printf "sourcekit-lsp\n"
            ;;
        zig)
            printf "zls\n"
            ;;
    esac
}

lsp_normalize_language() {
    local language="$1"
    case "${language}" in
        ts|typescript)
            printf "typescript\n"
            ;;
        js|javascript|node|bun)
            printf "javascript\n"
            ;;
        py|python)
            printf "python\n"
            ;;
        go|golang)
            printf "go\n"
            ;;
        rust|rs)
            printf "rust\n"
            ;;
        swift)
            printf "swift\n"
            ;;
        zig)
            printf "zig\n"
            ;;
        *)
            return 1
            ;;
    esac
}

lsp_install_target_language() {
    local root="$1"
    local requested="${2:-}"
    if [[ -n "${requested}" ]]; then
        lsp_normalize_language "${requested}"
        return $?
    fi
    lsp_detected_language "${root}"
}

lsp_managed_tool_root() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            printf "%s/node\n" "${IDE_LSP_TOOLS_DIR}"
            ;;
        python)
            printf "%s/python\n" "${IDE_LSP_TOOLS_DIR}"
            ;;
        go)
            printf "%s/go\n" "${IDE_LSP_TOOLS_DIR}"
            ;;
        *)
            return 1
            ;;
    esac
}

lsp_managed_server_command() {
    local language="$1"
    local root=""
    local bin=""
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    root=$(lsp_managed_tool_root "${language}" 2>/dev/null || true)
    case "${language}" in
        javascript|typescript)
            bin="${root}/node_modules/.bin/typescript-language-server"
            if [[ -x "${bin}" ]]; then
                printf "%s --stdio\n" "${bin}"
            fi
            ;;
        python)
            bin="${root}/node_modules/.bin/pyright-langserver"
            if [[ -x "${bin}" ]]; then
                printf "%s --stdio\n" "${bin}"
                return 0
            fi
            bin="${root}/node_modules/.bin/basedpyright-langserver"
            if [[ -x "${bin}" ]]; then
                printf "%s --stdio\n" "${bin}"
            fi
            ;;
        go)
            bin="${root}/bin/gopls"
            if [[ -x "${bin}" ]]; then
                printf "%s\n" "${bin}"
            fi
            ;;
    esac
}

lsp_install_pin_version() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            printf "typescript-language-server@5.0.1 + typescript@5.8.2\n"
            ;;
        python)
            printf "pyright@1.1.403\n"
            ;;
        go)
            printf "gopls@v0.18.1\n"
            ;;
        rust)
            printf "toolchain-managed (rust-analyzer from rustup/cargo toolchain)\n"
            ;;
        swift)
            printf "toolchain-managed (sourcekit-lsp from Xcode/Swift toolchain)\n"
            ;;
        zig)
            printf "toolchain-managed (zls on PATH)\n"
            ;;
    esac
}

lsp_install_footprint_bound() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            printf "<= 45 MiB\n"
            ;;
        python)
            printf "<= 35 MiB\n"
            ;;
        go)
            printf "<= 55 MiB\n"
            ;;
        rust)
            printf "toolchain-managed (~65 MiB expected)\n"
            ;;
        swift)
            printf "toolchain-managed (bundled with Xcode)\n"
            ;;
        zig)
            printf "toolchain-managed (~25 MiB expected)\n"
            ;;
    esac
}

lsp_install_strategy() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            printf "managed-npm-prefix\n"
            ;;
        python)
            printf "managed-npm-prefix\n"
            ;;
        go)
            printf "managed-gobin\n"
            ;;
        rust)
            printf "toolchain-path\n"
            ;;
        swift)
            printf "toolchain-path\n"
            ;;
        zig)
            printf "toolchain-path\n"
            ;;
    esac
}

lsp_install_family() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            printf "shared-js-ts\n"
            ;;
        python)
            printf "python\n"
            ;;
        go)
            printf "go\n"
            ;;
        rust)
            printf "rust\n"
            ;;
        swift)
            printf "swift\n"
            ;;
        zig)
            printf "zig\n"
            ;;
    esac
}

lsp_install_manager_label() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript|python)
            printf "yen-managed-node\n"
            ;;
        go)
            printf "yen-managed-go\n"
            ;;
        rust)
            printf "rustup-toolchain\n"
            ;;
        swift)
            printf "xcode-swift-toolchain\n"
            ;;
        zig)
            printf "external-package-manager\n"
            ;;
    esac
}

lsp_install_runtime_root_display() {
    local language="$1"
    local root=""
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    root=$(lsp_managed_tool_root "${language}" 2>/dev/null || true)
    if [[ -n "${root}" ]]; then
        printf "%s\n" "${root}"
        return 0
    fi
    printf "toolchain-path\n"
}

lsp_install_note() {
    local language="$1"
    local root=""
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    root=$(lsp_install_runtime_root_display "${language}")
    case "${language}" in
        javascript|typescript)
            printf "one managed TypeScript language-server install under %s covers both JavaScript and TypeScript projects\n" "${root}"
            ;;
        python)
            printf "YEN manages the pyright baseline under %s and reuses that local install before checking PATH\n" "${root}"
            ;;
        go)
            printf "YEN manages the gopls baseline under %s and reuses that local install before checking PATH\n" "${root}"
            ;;
        rust)
            printf "rust-analyzer stays toolchain-managed via rustup/cargo; YEN reads PATH but does not vendor or auto-install it\n"
            ;;
        swift)
            printf "sourcekit-lsp stays toolchain-managed via Xcode or Swift toolchains; YEN reads PATH but does not vendor or auto-install it\n"
            ;;
        zig)
            printf "zls stays toolchain-managed on PATH; YEN shows explicit install/update guidance but does not vendor or auto-install it\n"
            ;;
    esac
}

lsp_install_command_text() {
    local language="$1"
    local root=""
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    root=$(lsp_managed_tool_root "${language}" 2>/dev/null || true)
    case "${language}" in
        javascript|typescript)
            printf "npm install --prefix %s typescript-language-server@5.0.1 typescript@5.8.2\n" "$(shell_quote_single "${root}")"
            ;;
        python)
            printf "npm install --prefix %s pyright@1.1.403\n" "$(shell_quote_single "${root}")"
            ;;
        go)
            printf "GOBIN=%s go install golang.org/x/tools/gopls@v0.18.1\n" "$(shell_quote_single "${root}/bin")"
            ;;
        rust)
            printf "rustup component add rust-analyzer\n"
            ;;
        swift)
            printf "xcode-select --install  # or install full Xcode toolchain with sourcekit-lsp\n"
            ;;
        zig)
            printf "brew install zls  # or make zls available on PATH via your preferred package manager\n"
            ;;
    esac
}

lsp_update_command_text() {
    local language="$1"
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript|python|go)
            lsp_install_command_text "${language}"
            ;;
        rust)
            printf "rustup update\n"
            ;;
        swift)
            printf "softwareupdate --all --install --force  # or update Xcode command line tools\n"
            ;;
        zig)
            printf "brew upgrade zls  # or update zls via your preferred package manager\n"
            ;;
    esac
}

lsp_server_available_for_language() {
    local language="$1"
    local command_string=""
    language=$(lsp_normalize_language "${language}" 2>/dev/null || printf "%s" "${language}")
    case "${language}" in
        javascript|typescript)
            command_string=$(lsp_managed_server_command "typescript")
            [[ -n "${command_string}" || -n "$(command -v typescript-language-server 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        python)
            command_string=$(lsp_managed_server_command "python")
            [[ -n "${command_string}" || -n "$(command -v pyright-langserver 2>/dev/null || true)" || -n "$(command -v basedpyright-langserver 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        go)
            command_string=$(lsp_managed_server_command "go")
            [[ -n "${command_string}" || -n "$(command -v gopls 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        rust)
            [[ -n "$(command -v rust-analyzer 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        swift)
            [[ -n "$(command -v sourcekit-lsp 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        zig)
            [[ -n "$(command -v zls 2>/dev/null || true)" ]] && printf "yes\n" || printf "no\n"
            ;;
        *)
            printf "no\n"
            ;;
    esac
}

lsp_resolution_status() {
    local root="$1"
    local command_string=""
    local expected_server=""

    if lsp_force_placeholder; then
        printf "placeholder-forced\n"
        return 0
    fi
    if [[ -n "${YEN_IDE_LSP_SERVER_CMD:-}" ]]; then
        printf "override\n"
        return 0
    fi

    command_string=$(lsp_resolved_command "${root}")
    if [[ -n "${command_string}" ]]; then
        printf "resolved\n"
        return 0
    fi

    expected_server=$(lsp_expected_server "${root}")
    if [[ -n "${expected_server}" ]]; then
        printf "unavailable-server\n"
    else
        printf "unsupported-language\n"
    fi
}

lsp_resolution_reason() {
    local root="$1"
    local status=""
    local expected_server=""
    local language=""

    status=$(lsp_resolution_status "${root}")
    expected_server=$(lsp_expected_server "${root}")
    language=$(lsp_detected_language "${root}")

    case "${status}" in
        placeholder-forced)
            printf "forced placeholder runtime via YEN_IDE_LSP_FORCE_PLACEHOLDER=1\n"
            ;;
        override)
            printf "using explicit override from YEN_IDE_LSP_SERVER_CMD\n"
            ;;
        resolved)
            printf "resolved local server on PATH\n"
            ;;
        unavailable-server)
            printf "detected %s project; expected %s on PATH\n" "${language}" "${expected_server}"
            ;;
        unsupported-language)
            printf "detected %s project; no supported reference server mapping yet\n" "${language}"
            ;;
        *)
            printf "no resolver guidance available\n"
            ;;
    esac
}

read_lsp_pid() {
    local root="$1"
    local pid_file
    pid_file=$(lsp_pid_file "${root}")
    if [[ ! -f "${pid_file}" ]]; then
        return 0
    fi
    tr -d '[:space:]' < "${pid_file}" | sed -n '1p'
}

lsp_pid_matches_runtime() {
    local root="$1"
    local pid="$2"
    local daemon_script
    local command_line

    if ! is_pid_running "${pid}"; then
        return 1
    fi

    daemon_script=$(lsp_daemon_script_file "${root}")

    command_line=$(ps -p "${pid}" -o command= 2>/dev/null || true)
    if [[ -z "${command_line}" ]]; then
        return 1
    fi

    if [[ "${command_line}" != *"${daemon_script}"* ]]; then
        return 1
    fi

    return 0
}

lsp_runtime_state() {
    local root="$1"
    local pid
    local socket_file
    local pid_file
    local state_file
    pid=$(read_lsp_pid "${root}")
    socket_file=$(lsp_socket_file "${root}")
    pid_file=$(lsp_pid_file "${root}")
    state_file=$(lsp_state_file "${root}")
    if lsp_pid_matches_runtime "${root}" "${pid}"; then
        if [[ -S "${socket_file}" ]]; then
            printf "running\n"
        else
            printf "starting\n"
        fi
        return 0
    fi
    if [[ -n "${pid}" ]] || [[ -S "${socket_file}" ]] || [[ -f "${pid_file}" ]] || [[ -f "${state_file}" ]]; then
        printf "stale\n"
        return 0
    fi
    printf "stopped\n"
}

lsp_state_value() {
    local root="$1"
    local key="$2"
    local state_file
    state_file=$(lsp_state_file "${root}")
    if [[ ! -f "${state_file}" ]]; then
        return 0
    fi
    grep -F "${key}=" "${state_file}" 2>/dev/null | head -n 1 | cut -d= -f2-
}

cleanup_lsp_runtime() {
    local root="$1"
    local preserve_diagnostics="${2:-0}"
    local project_dir
    local socket_file
    local pid_file
    local state_file
    local diagnostics_file
    local daemon_script
    project_dir=$(lsp_project_dir "${root}")
    socket_file=$(lsp_socket_file "${root}")
    pid_file=$(lsp_pid_file "${root}")
    state_file=$(lsp_state_file "${root}")
    diagnostics_file=$(lsp_diagnostics_file "${root}")
    daemon_script=$(lsp_daemon_script_file "${root}")

    rm -f "${socket_file}" "${pid_file}" "${state_file}" "${daemon_script}"
    if [[ "${preserve_diagnostics}" != "1" ]]; then
        rm -f "${diagnostics_file}"
    fi
    if [[ -d "${project_dir}" ]] && [[ -z "$(find "${project_dir}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
        rmdir "${project_dir}" 2>/dev/null || true
    fi
}

lsp_daemon_python_source() {
    cat << 'PY'
import datetime
import json
import os
import pathlib
import queue
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

socket_path = sys.argv[1]
state_path = sys.argv[2]
diagnostics_path = sys.argv[3]
root = sys.argv[4]
protocol_mode = sys.argv[5]
impl = sys.argv[6]
server_label = sys.argv[7]
server_cmd = sys.argv[8]
language_id = sys.argv[9]
extensions_csv = sys.argv[10]
timeline_path = sys.argv[11]
started_at = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
running = True
child = None
stderr_thread = None
child_exit_code = ""
diagnostics_by_file = {}
diagnostics_count = 0
diagnostics_updated_at = ""
last_error = ""
current_status = "starting"
protocol_status = "placeholder" if protocol_mode == "placeholder" else "booting"
protocol_ready_at = ""
crash_logged = False
pending = {}
pending_lock = threading.Lock()
write_lock = threading.Lock()
state_lock = threading.RLock()
next_request_id = 0
server_socket = None
max_open_file_bytes = 262144
max_initial_open_files = 24
doc_versions = {}
doc_mtimes = {}
doc_sizes = {}
tracked_documents = set()
tracked_lock = threading.Lock()

def iso_now():
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

def atomic_write_text(path, text):
    directory = os.path.dirname(path) or "."
    fd, tmp_path = tempfile.mkstemp(prefix=".yen-lsp-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, path)
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass

def write_state(status):
    global diagnostics_count, diagnostics_updated_at, child_exit_code, current_status, last_error, protocol_ready_at, protocol_status
    child_pid = ""
    current_status = status
    if child is not None and child.poll() is None:
        child_pid = str(child.pid)
    lines = [
        f"impl={sanitize(impl)}\n",
        f"status={sanitize(status)}\n",
        f"pid={os.getpid()}\n",
        f"started_at={started_at}\n",
        f"root={sanitize(root)}\n",
        f"protocol_mode={sanitize(protocol_mode)}\n",
        f"server_label={sanitize(server_label)}\n",
        f"server_command={sanitize(server_cmd)}\n",
        f"language_id={sanitize(language_id)}\n",
        f"extensions={sanitize(extensions_csv)}\n",
        f"protocol_status={sanitize(protocol_status)}\n",
        f"diagnostics_count={diagnostics_count}\n",
    ]
    if diagnostics_updated_at:
        lines.append(f"diagnostics_updated_at={sanitize(diagnostics_updated_at)}\n")
    if protocol_ready_at:
        lines.append(f"protocol_ready_at={sanitize(protocol_ready_at)}\n")
    if child_pid:
        lines.append(f"child_pid={child_pid}\n")
    if child_exit_code:
        lines.append(f"child_exit_code={sanitize(child_exit_code)}\n")
    if last_error:
        lines.append(f"last_error={sanitize(last_error)}\n")
    with state_lock:
        atomic_write_text(state_path, "".join(lines))

def write_snapshot():
    global diagnostics_count, diagnostics_updated_at
    items = []
    for _, value in sorted(diagnostics_by_file.items()):
        items.extend(value)
    diagnostics_count = len(items)
    diagnostics_updated_at = iso_now()
    snapshot = json.dumps(
        {
            "updated_at": diagnostics_updated_at,
            "items": items,
        },
        indent=2,
        sort_keys=True,
    )
    with state_lock:
        atomic_write_text(diagnostics_path, f"{snapshot}\n")
        write_state("running")

def sanitize(value):
    return " ".join(str(value or "").replace("\t", " ").split())

def uri_to_path(uri):
    if not uri:
        return ""
    if uri.startswith("file://"):
        return urllib.parse.unquote(urllib.parse.urlparse(uri).path)
    return uri

def path_to_uri(path):
    return pathlib.Path(path).resolve().as_uri()

def file_language_for_path(file_path):
    suffix = pathlib.Path(file_path).suffix.lower()
    if suffix in {".ts", ".tsx", ".mts", ".cts"}:
        return "typescript"
    if suffix in {".js", ".jsx", ".mjs", ".cjs"}:
        return "javascript"
    if suffix == ".py":
        return "python"
    if suffix == ".go":
        return "go"
    if suffix == ".rs":
        return "rust"
    if suffix == ".swift":
        return "swift"
    return language_id or "plaintext"

def file_metadata(file_path):
    stats = os.stat(file_path)
    return (
        stats.st_mtime_ns,
        stats.st_size,
    )

def sync_document(file_path, force=False):
    abs_path = str(pathlib.Path(file_path).resolve())
    try:
        mtime_ns, size = file_metadata(abs_path)
    except OSError as exc:
        raise RuntimeError(f"missing-file={exc}")
    if size > max_open_file_bytes:
        raise RuntimeError(f"file-too-large>{max_open_file_bytes}")

    previous_mtime = doc_mtimes.get(abs_path)
    previous_size = doc_sizes.get(abs_path)
    if not force and previous_mtime == mtime_ns and previous_size == size and abs_path in doc_versions:
        with tracked_lock:
            tracked_documents.add(abs_path)
        return {"path": abs_path, "synced": False, "version": doc_versions.get(abs_path, 1)}

    try:
        with open(abs_path, "r", encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except Exception as exc:
        raise RuntimeError(f"read-failed={exc}")

    version = doc_versions.get(abs_path, 0) + 1
    uri = path_to_uri(abs_path)
    text_document = {
        "uri": uri,
        "languageId": file_language_for_path(abs_path),
        "version": version,
        "text": text,
    }
    if abs_path in doc_versions:
        send_notification(
            "textDocument/didChange",
            {
                "textDocument": {
                    "uri": uri,
                    "version": version,
                },
                "contentChanges": [{"text": text}],
            },
        )
    else:
        send_notification("textDocument/didOpen", {"textDocument": text_document})
    doc_versions[abs_path] = version
    doc_mtimes[abs_path] = mtime_ns
    doc_sizes[abs_path] = size
    with tracked_lock:
        tracked_documents.add(abs_path)
    return {"path": abs_path, "synced": True, "version": version}

def sync_tracked_documents():
    with tracked_lock:
        paths = list(tracked_documents)
    for file_path in paths:
        try:
            sync_document(file_path, force=False)
        except Exception:
            continue

def sync_thread():
    while running:
        if protocol_mode == "stdio" and protocol_status == "ready":
            sync_tracked_documents()
        time.sleep(0.8)

def timeline_log(event, status, detail):
    safe_detail = sanitize(detail)
    with open(timeline_path, "a", encoding="utf-8") as fh:
        fh.write(f"{iso_now()}\t{event}\t{root}\t{status}\t{safe_detail}\n")

def record_crash(status):
    global crash_logged
    if crash_logged:
        return
    crash_logged = True
    timeline_log(
        "lsp-crash",
        status,
        f"mode={protocol_mode};server={server_label};exit={child_exit_code};error={last_error}",
    )

def normalize_diagnostics(params):
    uri = params.get("uri") or params.get("path") or ""
    file_path = uri_to_path(uri)
    severity_map = {
        1: "error",
        2: "warning",
        3: "info",
        4: "hint",
    }
    items = []
    for diagnostic in params.get("diagnostics", []):
        start = (((diagnostic.get("range") or {}).get("start")) or {})
        end = (((diagnostic.get("range") or {}).get("end")) or {})
        code = diagnostic.get("code", "")
        if isinstance(code, dict):
            code = code.get("value") or code.get("target") or json.dumps(code, sort_keys=True)
        severity_number = diagnostic.get("severity", 1)
        try:
            severity_number = int(severity_number)
        except Exception:
            severity_number = 1
        items.append(
            {
                "file": file_path,
                "line": int(start.get("line", 0)) + 1,
                "col": int(start.get("character", 0)) + 1,
                "endLine": int(end.get("line", start.get("line", 0))) + 1,
                "endCol": int(end.get("character", start.get("character", 0))) + 1,
                "severity": severity_map.get(severity_number, "error"),
                "severityNumber": severity_number,
                "code": sanitize(code),
                "source": sanitize(diagnostic.get("source", server_label)),
                "message": sanitize(diagnostic.get("message", "")),
            }
        )
    diagnostics_by_file[file_path] = items
    write_snapshot()

def send_payload(payload):
    if child is None or child.stdin is None:
        return
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
    with write_lock:
        child.stdin.write(header + body)
        child.stdin.flush()

def send_response(message_id, result=None):
    send_payload({
        "jsonrpc": "2.0",
        "id": message_id,
        "result": result,
    })

def send_notification(method, params=None):
    send_payload({
        "jsonrpc": "2.0",
        "method": method,
        "params": params or {},
    })

def send_request(method, params=None, timeout=8.0):
    global next_request_id
    wait_queue = queue.Queue()
    deadline = time.time() + timeout
    with pending_lock:
        next_request_id += 1
        request_id = next_request_id
        pending[str(request_id)] = wait_queue
    send_payload({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params or {},
    })
    try:
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise queue.Empty()
            try:
                return wait_queue.get(timeout=min(0.1, remaining))
            except queue.Empty:
                if child is not None and child.poll() is not None:
                    exit_code = child.returncode
                    raise RuntimeError(sanitize(last_error or f"child-exit={exit_code}"))
    finally:
        with pending_lock:
            pending.pop(str(request_id), None)

def respond_to_server_request(message):
    method = message.get("method", "")
    request_id = message.get("id")
    params = message.get("params") or {}
    result = None
    if method == "workspace/configuration":
        result = [None for _ in params.get("items", [])]
    elif method == "workspace/workspaceFolders":
        result = [{"uri": path_to_uri(root), "name": os.path.basename(root)}]
    send_response(request_id, result)

def handle_message(message):
    if "id" in message and "method" not in message:
        with pending_lock:
            wait_queue = pending.get(str(message.get("id")))
        if wait_queue is not None:
            wait_queue.put(message)
        return

    method = message.get("method")
    if not method:
        return

    if "id" in message:
        respond_to_server_request(message)
        return

    if method == "textDocument/publishDiagnostics":
        normalize_diagnostics(message.get("params") or {})

def normalize_locations(payload):
    if payload is None:
        return []
    if isinstance(payload, dict):
        if "targetUri" in payload:
            payload = [payload]
        elif "uri" in payload:
            payload = [payload]
        else:
            payload = []
    items = []
    for entry in payload:
        if not isinstance(entry, dict):
            continue
        uri = entry.get("targetUri") or entry.get("uri") or ""
        file_path = uri_to_path(uri)
        range_info = entry.get("targetSelectionRange") or entry.get("range") or {}
        start = (range_info.get("start") or {}) if isinstance(range_info, dict) else {}
        items.append(
            {
                "path": file_path,
                "line": int(start.get("line", 0)) + 1,
                "col": int(start.get("character", 0)) + 1,
                "location": f"{file_path}:{int(start.get('line', 0)) + 1}:{int(start.get('character', 0)) + 1}",
            }
        )
    return items

def normalize_workspace_edit(edit):
    if not isinstance(edit, dict):
        return {"changes": [], "documentChanges": []}
    normalized_changes = []
    for uri, edits in sorted((edit.get("changes") or {}).items()):
        file_path = uri_to_path(uri)
        normalized_edits = []
        for edit_item in edits or []:
            range_info = edit_item.get("range") or {}
            start = (range_info.get("start") or {}) if isinstance(range_info, dict) else {}
            end = (range_info.get("end") or {}) if isinstance(range_info, dict) else {}
            normalized_edits.append(
                {
                    "startLine": int(start.get("line", 0)) + 1,
                    "startCol": int(start.get("character", 0)) + 1,
                    "endLine": int(end.get("line", 0)) + 1,
                    "endCol": int(end.get("character", 0)) + 1,
                    "newText": edit_item.get("newText") or "",
                }
            )
        normalized_changes.append(
            {
                "path": file_path,
                "edits": normalized_edits,
            }
        )
    normalized_document_changes = []
    for change in edit.get("documentChanges") or []:
        if not isinstance(change, dict):
            continue
        text_document = change.get("textDocument") or {}
        file_path = uri_to_path(text_document.get("uri") or "")
        normalized_edits = []
        for edit_item in change.get("edits") or []:
            range_info = edit_item.get("range") or {}
            start = (range_info.get("start") or {}) if isinstance(range_info, dict) else {}
            end = (range_info.get("end") or {}) if isinstance(range_info, dict) else {}
            normalized_edits.append(
                {
                    "startLine": int(start.get("line", 0)) + 1,
                    "startCol": int(start.get("character", 0)) + 1,
                    "endLine": int(end.get("line", 0)) + 1,
                    "endCol": int(end.get("character", 0)) + 1,
                    "newText": edit_item.get("newText") or "",
                }
            )
        normalized_document_changes.append(
            {
                "path": file_path,
                "edits": normalized_edits,
            }
        )
    return {
        "changes": normalized_changes,
        "documentChanges": normalized_document_changes,
    }

def response_error_message(response):
    if not isinstance(response, dict):
        return ""
    error = response.get("error")
    if not error:
        return ""
    if isinstance(error, dict):
        return sanitize(
            error.get("message")
            or error.get("code")
            or json.dumps(error, sort_keys=True)
        )
    return sanitize(error)

def normalize_command_payload(command):
    if not isinstance(command, dict):
        return {
            "title": "",
            "command": "",
            "argumentCount": 0,
        }
    arguments = command.get("arguments")
    if isinstance(arguments, list):
        argument_count = len(arguments)
    elif arguments is None:
        argument_count = 0
    else:
        argument_count = 1
    return {
        "title": sanitize(command.get("title") or ""),
        "command": sanitize(command.get("command") or ""),
        "argumentCount": argument_count,
    }

def normalized_edit_counts(edit):
    entries = []
    entries.extend(edit.get("changes") or [])
    entries.extend(edit.get("documentChanges") or [])
    return (
        len(entries),
        sum(len(entry.get("edits") or []) for entry in entries),
    )

def normalize_code_actions(result):
    if result is None:
        return []
    if isinstance(result, dict):
        result = [result]
    actions = []
    for entry in result:
        if not isinstance(entry, dict):
            continue
        command_payload = normalize_command_payload(
            entry.get("command")
            if isinstance(entry.get("command"), dict)
            else entry
        )
        edit = normalize_workspace_edit(entry.get("edit"))
        file_count, edit_count = normalized_edit_counts(edit)
        disabled_payload = entry.get("disabled")
        disabled_reason = ""
        disabled = False
        if isinstance(disabled_payload, dict):
            disabled = True
            disabled_reason = sanitize(disabled_payload.get("reason") or "")
        elif disabled_payload:
            disabled = True
            disabled_reason = sanitize(disabled_payload)
        title = sanitize(entry.get("title") or command_payload.get("title") or "")
        actions.append(
            {
                "title": title,
                "kind": sanitize(entry.get("kind") or ""),
                "preferred": bool(entry.get("isPreferred")),
                "disabled": disabled,
                "disabledReason": disabled_reason,
                "hasEdit": edit_count > 0,
                "hasCommand": bool(command_payload.get("command")),
                "fileCount": file_count,
                "editCount": edit_count,
                "edit": edit,
                "commandTitle": command_payload.get("title") or "",
                "commandName": command_payload.get("command") or "",
                "commandArgumentCount": int(command_payload.get("argumentCount") or 0),
            }
        )
    return actions

def diagnostic_context_for(file_path, line, col):
    entries = diagnostics_by_file.get(file_path) or []
    exact = []
    fallback = []
    for item in entries:
        start_line = max(int(item.get("line") or 1), 1)
        start_col = max(int(item.get("col") or 1), 1)
        end_line = max(int(item.get("endLine") or start_line), start_line)
        end_col = max(int(item.get("endCol") or start_col), start_col)
        diagnostic = {
            "range": {
                "start": {
                    "line": start_line - 1,
                    "character": start_col - 1,
                },
                "end": {
                    "line": end_line - 1,
                    "character": end_col - 1,
                },
            },
            "severity": int(item.get("severityNumber") or 1),
            "code": item.get("code") or None,
            "source": item.get("source") or None,
            "message": item.get("message") or "",
        }
        fallback.append(diagnostic)
        if start_line <= line <= end_line:
            if line != end_line or col <= end_col:
                exact.append(diagnostic)
    return exact or fallback

def handle_control_request(raw_payload):
    try:
        request = json.loads(raw_payload or "{}")
    except Exception as exc:
        return {"ok": False, "error": f"invalid-json={exc}"}

    command = sanitize(request.get("command"))
    if not command:
        return {"ok": False, "error": "missing-command"}
    if command == "health":
        return {"ok": True, "status": "ready", "protocol": protocol_status}
    if protocol_mode != "stdio":
        return {"ok": False, "error": "placeholder-runtime"}
    if protocol_status != "ready":
        return {"ok": False, "error": f"protocol-{protocol_status}"}

    file_path = request.get("file") or ""
    line = max(int(request.get("line") or 1), 1)
    col = max(int(request.get("col") or 1), 1)
    include_declaration = bool(request.get("includeDeclaration", True))
    new_name = request.get("newName") or ""
    if file_path:
        try:
            sync_document(file_path, force=True)
        except Exception as exc:
            return {"ok": False, "error": sanitize(exc)}

    text_document = {"uri": path_to_uri(file_path)} if file_path else {}
    position = {"line": line - 1, "character": col - 1}

    try:
        if command == "hover":
            response = send_request(
                "textDocument/hover",
                {"textDocument": text_document, "position": position},
                timeout=8.0,
            )
            error_message = response_error_message(response)
            if error_message:
                return {"ok": False, "error": error_message}
            result = response.get("result")
            contents = ""
            if isinstance(result, dict):
                raw_contents = result.get("contents")
                if isinstance(raw_contents, str):
                    contents = raw_contents
                elif isinstance(raw_contents, list):
                    contents = "\n".join(
                        sanitize(item.get("value") if isinstance(item, dict) else item)
                        for item in raw_contents
                    )
                elif isinstance(raw_contents, dict):
                    contents = sanitize(raw_contents.get("value") or raw_contents.get("language") or raw_contents)
            return {"ok": True, "command": command, "contents": sanitize(contents)}
        if command == "definition":
            response = send_request(
                "textDocument/definition",
                {"textDocument": text_document, "position": position},
                timeout=8.0,
            )
            error_message = response_error_message(response)
            if error_message:
                return {"ok": False, "error": error_message}
            return {"ok": True, "command": command, "items": normalize_locations(response.get("result"))}
        if command == "references":
            response = send_request(
                "textDocument/references",
                {
                    "textDocument": text_document,
                    "position": position,
                    "context": {"includeDeclaration": include_declaration},
                },
                timeout=8.0,
            )
            error_message = response_error_message(response)
            if error_message:
                return {"ok": False, "error": error_message}
            return {"ok": True, "command": command, "items": normalize_locations(response.get("result"))}
        if command == "code-actions":
            response = send_request(
                "textDocument/codeAction",
                {
                    "textDocument": text_document,
                    "range": {
                        "start": position,
                        "end": position,
                    },
                    "context": {
                        "diagnostics": diagnostic_context_for(file_path, line, col),
                    },
                },
                timeout=8.0,
            )
            error_message = response_error_message(response)
            if error_message:
                return {"ok": False, "error": error_message}
            return {
                "ok": True,
                "command": command,
                "actions": normalize_code_actions(response.get("result")),
            }
        if command == "rename":
            if not new_name:
                return {"ok": False, "error": "missing-newName"}
            response = send_request(
                "textDocument/rename",
                {
                    "textDocument": text_document,
                    "position": position,
                    "newName": new_name,
                },
                timeout=8.0,
            )
            error_message = response_error_message(response)
            if error_message:
                return {"ok": False, "error": error_message}
            return {
                "ok": True,
                "command": command,
                "edit": normalize_workspace_edit(response.get("result")),
            }
    except Exception as exc:
        return {"ok": False, "error": sanitize(exc)}

    return {"ok": False, "error": f"unknown-command={command}"}

def stdout_reader():
    global running
    buffer = b""
    while running and child is not None and child.stdout is not None:
        chunk = os.read(child.stdout.fileno(), 4096)
        if not chunk:
            break
        buffer += chunk
        while True:
            header_end = buffer.find(b"\r\n\r\n")
            if header_end < 0:
                break
            header_block = buffer[:header_end].decode("ascii", "replace")
            content_length = None
            for line in header_block.split("\r\n"):
                if ":" not in line:
                    continue
                key, value = line.split(":", 1)
                if key.lower() == "content-length":
                    try:
                        content_length = int(value.strip())
                    except ValueError:
                        content_length = None
                    break
            if content_length is None:
                buffer = b""
                break
            total_length = header_end + 4 + content_length
            if len(buffer) < total_length:
                break
            body = buffer[header_end + 4 : total_length]
            buffer = buffer[total_length:]
            try:
                handle_message(json.loads(body.decode("utf-8", "replace")))
            except Exception:
                continue

def stderr_reader():
    global last_error
    if child is None or child.stderr is None:
        return
    while running:
        line = child.stderr.readline()
        if not line:
            break
        try:
            text = line.decode("utf-8", "replace").strip()
        except Exception:
            text = ""
        if text:
            last_error = sanitize(text)
            write_state(current_status)

def detect_candidate_files():
    allowed_extensions = [item.strip() for item in extensions_csv.split(",") if item.strip()]
    if not allowed_extensions:
        return []
    ignored_dirs = {
        ".git",
        ".next",
        "DerivedData",
        "build",
        "dist",
        "ghostty",
        "node_modules",
        "target",
        "vendor",
        "zig-out",
    }
    priority_dirs = []
    if language_id in {"typescript", "javascript"}:
        priority_dirs = ["src", "app", "lib", "server", "components", "pages", "tests"]
    elif language_id == "go":
        priority_dirs = ["cmd", "internal", "pkg", "tests"]
    elif language_id == "rust":
        priority_dirs = ["src", "tests", "examples", "benches"]
    elif language_id == "python":
        priority_dirs = ["src", "app", "tests"]
    elif language_id == "swift":
        priority_dirs = ["Sources", "Tests"]

    results = []
    seen = set()

    def append_file(file_path):
        normalized = str(pathlib.Path(file_path).resolve())
        if normalized in seen:
            return False
        try:
            if os.path.getsize(normalized) > max_open_file_bytes:
                return False
        except OSError:
            return False
        seen.add(normalized)
        results.append(normalized)
        return len(results) >= max_initial_open_files

    def walk_directory(start_dir):
        if not os.path.isdir(start_dir):
            return False
        for dirpath, dirnames, filenames in os.walk(start_dir):
            dirnames[:] = sorted([name for name in dirnames if name not in ignored_dirs])
            for filename in sorted(filenames):
                if not any(filename.endswith(extension) for extension in allowed_extensions):
                    continue
                if append_file(os.path.join(dirpath, filename)):
                    return True
        return False

    for relative_dir in priority_dirs:
        if walk_directory(os.path.join(root, relative_dir)):
            return results
    walk_directory(root)
    return results

def open_candidate_files():
    for file_path in detect_candidate_files():
        try:
            sync_document(file_path, force=True)
        except Exception:
            continue

def shutdown_child():
    global child
    if child is None:
        return
    if child.poll() is None:
        child.terminate()
        deadline = time.time() + 3.0
        while time.time() < deadline:
            if child.poll() is not None:
                break
            time.sleep(0.1)
    if child.poll() is None:
        child.kill()

def handle_signal(signum, frame):
    global running
    running = False
    shutdown_child()

signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGHUP, handle_signal)

os.makedirs(os.path.dirname(socket_path), exist_ok=True)
os.makedirs(os.path.dirname(state_path), exist_ok=True)
os.makedirs(os.path.dirname(timeline_path), exist_ok=True)
if os.path.exists(socket_path):
    os.unlink(socket_path)

server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server_socket.bind(socket_path)
server_socket.listen(4)
server_socket.settimeout(0.5)

def health_server():
    while running:
        try:
            conn, _ = server_socket.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            conn.settimeout(0.2)
            payload = b""
            try:
                payload = conn.recv(65536)
            except socket.timeout:
                payload = b""
            except OSError:
                payload = b""
            if payload.strip():
                response = handle_control_request(payload.decode("utf-8", "replace"))
                conn.sendall((json.dumps(response, sort_keys=True) + "\n").encode("utf-8"))
            else:
                conn.sendall(b"YEN-LSP-READY\n")
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

threading.Thread(target=health_server, daemon=True).start()
write_state("starting")

try:
    if protocol_mode == "placeholder":
        protocol_status = "placeholder"
        write_state("running")
        while running:
            time.sleep(0.2)
    else:
        child = subprocess.Popen(
            shlex.split(server_cmd),
            cwd=root,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        threading.Thread(target=stdout_reader, daemon=True).start()
        stderr_thread = threading.Thread(target=stderr_reader, daemon=True)
        stderr_thread.start()

        init_response = send_request(
            "initialize",
            {
                "processId": os.getpid(),
                "rootPath": root,
                "rootUri": path_to_uri(root),
                "workspaceFolders": [{"uri": path_to_uri(root), "name": os.path.basename(root)}],
                "capabilities": {
                    "workspace": {
                        "configuration": True,
                        "workspaceFolders": True,
                    },
                    "textDocument": {
                        "publishDiagnostics": {
                            "relatedInformation": True,
                        }
                    },
                },
            },
            timeout=8.0,
        )
        if "error" in init_response:
            raise RuntimeError(sanitize(init_response.get("error")))
        send_notification("initialized", {})
        protocol_status = "ready"
        protocol_ready_at = iso_now()
        write_state("running")
        open_candidate_files()
        threading.Thread(target=sync_thread, daemon=True).start()

        while running:
            if child.poll() is not None:
                child_exit_code = str(child.returncode)
                last_error = sanitize(last_error or f"child-exit={child.returncode}")
                protocol_status = "crashed"
                write_state("stale")
                record_crash("crashed")
                running = False
                break
            time.sleep(0.2)
except Exception as exc:
    if child is not None:
        try:
            child.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
    if stderr_thread is not None:
        stderr_thread.join(timeout=0.5)
    last_error = sanitize(last_error or exc)
    protocol_status = "failed"
    if child is not None and child.poll() is not None:
        child_exit_code = str(child.returncode)
        record_crash("failed")
    write_state("failed")
    raise RuntimeError(last_error) from exc
finally:
    try:
        shutdown_child()
    except Exception:
        pass
    try:
        if server_socket is not None:
            server_socket.close()
    except OSError:
        pass
    try:
        if os.path.exists(socket_path):
            os.unlink(socket_path)
    except OSError:
        pass
PY
}

probe_lsp_socket() {
    local socket_file="$1"
    if [[ ! -S "${socket_file}" ]]; then
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        return 2
    fi
    python3 - "${socket_file}" <<'PY' >/dev/null 2>&1
import socket
import sys

sock_path = sys.argv[1]
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(0.5)
try:
    client.connect(sock_path)
    payload = client.recv(64)
    if payload == b"YEN-LSP-READY\n":
        raise SystemExit(0)
except Exception:
    raise SystemExit(1)
finally:
    try:
        client.close()
    except Exception:
        pass
PY
}

lsp_health_status() {
    local root="$1"
    local runtime_state
    local socket_file
    runtime_state=$(lsp_runtime_state "${root}")
    socket_file=$(lsp_socket_file "${root}")

    case "${runtime_state}" in
        running)
            if probe_lsp_socket "${socket_file}"; then
                printf "healthy\n"
                return 0
            fi
            local probe_status=$?
            if [[ "${probe_status}" -eq 2 ]]; then
                printf "unknown\n"
            else
                printf "unresponsive\n"
            fi
            return 0
            ;;
        starting)
            printf "starting\n"
            ;;
        stale)
            printf "stale\n"
            ;;
        *)
            printf "inactive\n"
            ;;
    esac
}

lsp_protocol_status() {
    local root="$1"
    local runtime_state=""
    local daemon_status=""
    local protocol_mode=""
    local child_exit_code=""

    runtime_state=$(lsp_runtime_state "${root}")
    daemon_status=$(lsp_state_value "${root}" "status")
    protocol_mode=$(lsp_state_value "${root}" "protocol_mode")
    child_exit_code=$(lsp_state_value "${root}" "child_exit_code")

    if [[ -z "${daemon_status}" ]] && [[ "${runtime_state}" == "stopped" ]]; then
        printf "inactive\n"
        return 0
    fi
    if [[ "${daemon_status}" == "failed" ]]; then
        printf "failed\n"
        return 0
    fi
    if [[ "${daemon_status}" == "stale" ]] || [[ "${runtime_state}" == "stale" ]]; then
        if [[ -n "${child_exit_code}" ]]; then
            printf "crashed\n"
        else
            printf "stale\n"
        fi
        return 0
    fi
    if [[ "${protocol_mode}" == "placeholder" ]]; then
        if [[ "${runtime_state}" == "running" || "${daemon_status}" == "running" ]]; then
            printf "placeholder\n"
        else
            printf "inactive\n"
        fi
        return 0
    fi
    if [[ "${daemon_status}" == "starting" ]] || [[ "${runtime_state}" == "starting" ]]; then
        printf "booting\n"
        return 0
    fi
    if [[ "${daemon_status}" == "running" ]]; then
        printf "ready\n"
        return 0
    fi
    printf "inactive\n"
}

lsp_diagnostics_status() {
    local root="$1"
    local runtime_state=""
    local diagnostics_file=""

    runtime_state=$(lsp_runtime_state "${root}")
    diagnostics_file=$(lsp_diagnostics_file "${root}")

    if [[ -f "${diagnostics_file}" && -s "${diagnostics_file}" ]]; then
        if [[ "${runtime_state}" == "running" ]]; then
            printf "fresh\n"
        else
            printf "stale\n"
        fi
        return 0
    fi

    if [[ "${runtime_state}" == "running" || "${runtime_state}" == "starting" ]]; then
        printf "waiting\n"
    else
        printf "unavailable\n"
    fi
}

lsp_send_control_request() {
    local root="$1"
    local command_name="$2"
    local file_path="$3"
    local line="$4"
    local col="$5"
    local include_declaration="${6:-1}"
    local new_name="${7:-}"
    local socket_file=""

    socket_file=$(lsp_socket_file "${root}")
    if [[ ! -S "${socket_file}" ]]; then
        yen_error "LSP runtime socket is unavailable for ${root}. Start it with: yen ide lsp start \"${root}\""
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        yen_error "python3 is required for interactive LSP requests."
        return 1
    fi

    python3 - "${socket_file}" "${command_name}" "${file_path}" "${line}" "${col}" "${include_declaration}" "${new_name}" <<'PY'
import json
import socket
import sys

socket_path = sys.argv[1]
command_name = sys.argv[2]
file_path = sys.argv[3]
line = int(sys.argv[4] or "1")
col = int(sys.argv[5] or "1")
include_declaration = sys.argv[6] == "1"
new_name = sys.argv[7]

payload = {
    "command": command_name,
    "file": file_path,
    "line": line,
    "col": col,
    "includeDeclaration": include_declaration,
    "newName": new_name,
}
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(8.0)
try:
    client.connect(socket_path)
    client.sendall((json.dumps(payload) + "\n").encode("utf-8"))
    data = b""
    while True:
        chunk = client.recv(65536)
        if not chunk:
            break
        data += chunk
    sys.stdout.write(data.decode("utf-8", "replace").strip())
except Exception as exc:
    sys.stderr.write(str(exc))
    raise SystemExit(2)
finally:
    try:
        client.close()
    except Exception:
        pass
PY
}

lsp_parse_location_arg() {
    local raw="$1"
    local resolved=""
    local file_path=""
    local line="1"
    local col="1"

    if [[ -z "${raw}" ]]; then
        return 1
    fi

    if [[ "${raw}" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
        file_path="${BASH_REMATCH[1]}"
        line="${BASH_REMATCH[2]}"
        col="${BASH_REMATCH[3]}"
    elif [[ "${raw}" =~ ^(.+):([0-9]+)$ ]]; then
        file_path="${BASH_REMATCH[1]}"
        line="${BASH_REMATCH[2]}"
    else
        file_path="${raw}"
    fi

    resolved=$(resolve_start_path "${file_path}")
    printf "%s\t%s\t%s\n" "${resolved}" "${line}" "${col}"
}

lsp_runtime_ready_or_error() {
    local root="$1"
    local protocol_status=""
    local resolution_status=""

    protocol_status=$(lsp_protocol_status "${root}")
    resolution_status=$(lsp_resolution_status "${root}")
    case "${protocol_status}" in
        ready)
            ;;
        booting)
            yen_error "LSP runtime is still booting for ${root}. Wait for it to report ready, then retry."
            return 1
            ;;
        placeholder)
            yen_error "The current runtime for ${root} is still placeholder-only."
            if [[ -n "$(lsp_expected_server "${root}")" ]]; then
                yen_info "Install the reference server first: $(lsp_expected_server "${root}")"
            fi
            if [[ -n "$(ast_supported_language "${root}" 2>/dev/null || true)" ]]; then
                yen_info "AST fallback is available: yen ide ast status \"${root}\""
            fi
            return 1
            ;;
        *)
            yen_error "LSP runtime is not ready for ${root} (${protocol_status}). Start it with: yen ide lsp start \"${root}\""
            if [[ "${resolution_status}" == "unavailable-server" ]]; then
                yen_info "Expected server: $(lsp_expected_server "${root}")"
            fi
            if [[ -n "$(ast_supported_language "${root}" 2>/dev/null || true)" ]]; then
                yen_info "AST fallback is available: yen ide ast status \"${root}\""
            fi
            return 1
            ;;
    esac
    return 0
}

lsp_response_value() {
    local response_json="$1"
    local field="$2"
    python3 - "${response_json}" "${field}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
value = payload
for token in sys.argv[2].split("."):
    if isinstance(value, dict):
        value = value.get(token, "")
    else:
        value = ""
        break
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

emit_lsp_response_locations() {
    local response_json="$1"
    python3 - "${response_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
items = payload.get("items") or []
for item in items:
    path = item.get("path") or ""
    line = item.get("line") or 1
    col = item.get("col") or 1
    location = item.get("location") or f"{path}:{line}:{col}"
    print("\t".join([path, str(line), str(col), location]))
PY
}

apply_lsp_workspace_edit() {
    local response_json="$1"
    python3 - "${response_json}" <<'PY'
import json
import os
import pathlib
import sys
import tempfile

payload = json.loads(sys.argv[1] or "{}")
edit = payload.get("edit") or {}
entries = []
entries.extend(edit.get("changes") or [])
entries.extend(edit.get("documentChanges") or [])

def line_starts(text):
    starts = [0]
    for index, char in enumerate(text):
        if char == "\n":
            starts.append(index + 1)
    return starts

def offset_for(starts, line, col):
    line_index = max(line - 1, 0)
    if line_index >= len(starts):
        return len(starts) and starts[-1] or 0
    return starts[line_index] + max(col - 1, 0)

for entry in entries:
    file_path = entry.get("path")
    if not file_path:
        continue
    path = pathlib.Path(file_path)
    text = path.read_text(encoding="utf-8")
    starts = line_starts(text)
    edits = entry.get("edits") or []
    normalized = []
    for edit_item in edits:
        start = offset_for(starts, int(edit_item.get("startLine") or 1), int(edit_item.get("startCol") or 1))
        end = offset_for(starts, int(edit_item.get("endLine") or 1), int(edit_item.get("endCol") or 1))
        normalized.append((start, end, edit_item.get("newText") or ""))
    normalized.sort(key=lambda item: (item[0], item[1]), reverse=True)
    for start, end, replacement in normalized:
        text = text[:start] + replacement + text[end:]
    fd, tmp_path = tempfile.mkstemp(prefix=".yen-lsp-edit-", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()
    pathlib.Path(tmp_path).replace(path)
    print(f"{path}\t{len(normalized)}")
PY
}

emit_lsp_code_action_rows() {
    local response_json="$1"
    python3 - "${response_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
actions = payload.get("actions") or []


def apply_mode(action):
    if action.get("disabled"):
        return "disabled"
    has_edit = bool(action.get("hasEdit"))
    has_command = bool(action.get("hasCommand"))
    if has_edit and has_command:
        return "edit+command"
    if has_edit:
        return "edit"
    if has_command:
        return "command"
    return "unresolved"


def selection_info(items):
    selectable = [
        (index, action)
        for index, action in enumerate(items, start=1)
        if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand")
    ]
    preferred = [(index, action) for index, action in selectable if action.get("preferred")]
    if not items:
        return ("none", 0, "No code actions are available for this location.")
    if len(selectable) == 1:
        return ("single", selectable[0][0], "One edit-only code action is available.")
    if len(preferred) == 1:
        return ("preferred", preferred[0][0], "One preferred edit-only code action is available.")
    if len(selectable) > 1:
        return (
            "ambiguous",
            0,
            "Multiple edit-only code actions are available. Preview first instead of applying automatically.",
        )
    if any(not action.get("disabled") and action.get("hasEdit") and action.get("hasCommand") for action in items):
        return (
            "needs-command",
            0,
            "Available code actions combine edits with commands, which preview is supported for but auto-apply is not.",
        )
    if any(not action.get("disabled") and action.get("hasCommand") for action in items):
        return (
            "command-only",
            0,
            "Available code actions are command-only, which preview is supported for but auto-apply is not.",
        )
    if any(action.get("disabled") for action in items):
        return ("disabled", 0, "All available code actions are disabled by the language server.")
    return ("unresolved", 0, "Available code actions do not expose an apply-ready workspace edit.")


selection_status, selected_index, selection_reason = selection_info(actions)
selectable_count = sum(
    1
    for action in actions
    if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand")
)
preferred_count = sum(
    1
    for action in actions
    if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand") and action.get("preferred")
)
print(
    "\t".join(
        [
            "SUMMARY",
            str(len(actions)),
            str(selectable_count),
            str(preferred_count),
            selection_status,
            str(selected_index),
            selection_reason,
        ]
    )
)
for index, action in enumerate(actions, start=1):
    print(
        "\t".join(
            [
                "ACTION",
                str(index),
                str(action.get("title") or "").replace("\t", " ").replace("\n", " "),
                str(action.get("kind") or ""),
                "yes" if action.get("preferred") else "no",
                "yes" if action.get("disabled") else "no",
                apply_mode(action),
                str(int(action.get("fileCount") or 0)),
                str(int(action.get("editCount") or 0)),
                str(action.get("commandName") or ""),
                str(action.get("disabledReason") or "").replace("\t", " ").replace("\n", " "),
            ]
        )
    )
PY
}

lsp_code_action_edit_wrapper() {
    local response_json="$1"
    local index="$2"
    python3 - "${response_json}" "${index}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
requested_index = int(sys.argv[2] or "0")
actions = payload.get("actions") or []
if requested_index < 1 or requested_index > len(actions):
    raise SystemExit(2)
action = actions[requested_index - 1]
print(json.dumps({"edit": action.get("edit") or {}}, sort_keys=True))
PY
}

emit_lsp_code_actions_json() {
    local response_json="$1"
    local root="$2"
    local file_path="$3"
    local line="$4"
    local col="$5"
    local apply_requested="$6"
    local applied="$7"
    local applied_index="$8"
    local error_message="${9:-}"

    python3 - "${response_json}" "${root}" "${file_path}" "${line}" "${col}" "${apply_requested}" "${applied}" "${applied_index}" "${error_message}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
root = sys.argv[2]
file_path = sys.argv[3]
line = int(sys.argv[4] or "1")
col = int(sys.argv[5] or "1")
apply_requested = sys.argv[6] == "1"
applied = sys.argv[7] == "1"
applied_index = int(sys.argv[8] or "0")
error_message = sys.argv[9]
actions = payload.get("actions") or []


def apply_mode(action):
    if action.get("disabled"):
        return "disabled"
    has_edit = bool(action.get("hasEdit"))
    has_command = bool(action.get("hasCommand"))
    if has_edit and has_command:
        return "edit+command"
    if has_edit:
        return "edit"
    if has_command:
        return "command"
    return "unresolved"


def selection_info(items):
    selectable = [
        (index, action)
        for index, action in enumerate(items, start=1)
        if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand")
    ]
    preferred = [(index, action) for index, action in selectable if action.get("preferred")]
    if not items:
        return ("none", 0, "No code actions are available for this location.")
    if len(selectable) == 1:
        return ("single", selectable[0][0], "One edit-only code action is available.")
    if len(preferred) == 1:
        return ("preferred", preferred[0][0], "One preferred edit-only code action is available.")
    if len(selectable) > 1:
        return (
            "ambiguous",
            0,
            "Multiple edit-only code actions are available. Preview first instead of applying automatically.",
        )
    if any(not action.get("disabled") and action.get("hasEdit") and action.get("hasCommand") for action in items):
        return (
            "needs-command",
            0,
            "Available code actions combine edits with commands, which preview is supported for but auto-apply is not.",
        )
    if any(not action.get("disabled") and action.get("hasCommand") for action in items):
        return (
            "command-only",
            0,
            "Available code actions are command-only, which preview is supported for but auto-apply is not.",
        )
    if any(action.get("disabled") for action in items):
        return ("disabled", 0, "All available code actions are disabled by the language server.")
    return ("unresolved", 0, "Available code actions do not expose an apply-ready workspace edit.")


selection_status, selected_index, selection_reason = selection_info(actions)
selectable_count = sum(
    1
    for action in actions
    if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand")
)
preferred_count = sum(
    1
    for action in actions
    if not action.get("disabled") and action.get("hasEdit") and not action.get("hasCommand") and action.get("preferred")
)
serialized_actions = []
for index, action in enumerate(actions, start=1):
    item = dict(action)
    item["index"] = index
    item["applyMode"] = apply_mode(action)
    serialized_actions.append(item)

result = {
    "schemaVersion": 1,
    "root": root,
    "location": {
        "path": file_path,
        "line": line,
        "col": col,
        "value": f"{file_path}:{line}:{col}",
    },
    "source": "lsp",
    "applyRequested": apply_requested,
    "applied": applied,
    "summary": {
        "actionCount": len(serialized_actions),
        "selectableEditCount": selectable_count,
        "preferredSelectableCount": preferred_count,
    },
    "selection": {
        "status": selection_status,
        "selectedIndex": selected_index,
        "reason": selection_reason,
    },
    "actions": serialized_actions,
}
if applied_index >= 1 and applied_index <= len(serialized_actions):
    result["appliedAction"] = serialized_actions[applied_index - 1]
if error_message:
    result["error"] = error_message
print(json.dumps(result, indent=2, sort_keys=True))
PY
}

ensure_lsp_trusted_or_prompt() {
    local root="$1"
    if is_lsp_trusted_project "${root}"; then
        return 0
    fi

    if [[ -t 0 ]]; then
        echo "Project LSP execution is untrusted: ${root}" >&2
        echo "Allow YEN to start the local LSP runtime for this project?" >&2
        echo "  [o] once  [a] always trust  [n] no" >&2
        printf "> " >&2
        local answer=""
        read -r answer
        case "${answer}" in
            a|A|always|ALWAYS)
                trust_lsp_project "${root}"
                timeline_log "lsp-trust" "${root}" "trusted" "source=prompt"
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

    yen_error "Project LSP execution is untrusted: ${root}"
    yen_info "Run: yen ide lsp trust \"${root}\""
    return 1
}

cmd_lsp_stop_internal() {
    local root="$1"
    local previous_state
    local pid
    local forced="0"
    local attempts=0
    local active_pid="0"
    local lock_dir=""
    local lock_released="0"
    lock_dir=$(lsp_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "LSP lifecycle"; then
        return 1
    fi
    trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR
    previous_state=$(lsp_runtime_state "${root}")
    pid=$(read_lsp_pid "${root}")

    if [[ "${previous_state}" == "stopped" ]]; then
        cleanup_lsp_runtime "${root}"
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 0
    fi

    if lsp_pid_matches_runtime "${root}" "${pid}"; then
        active_pid="1"
        kill "${pid}" 2>/dev/null || true
        while is_pid_running "${pid}" && [[ "${attempts}" -lt 30 ]]; do
            sleep 0.1
            attempts=$((attempts + 1))
        done
        if is_pid_running "${pid}"; then
            kill -9 "${pid}" 2>/dev/null || true
            forced="1"
            attempts=0
            while is_pid_running "${pid}" && [[ "${attempts}" -lt 10 ]]; do
                sleep 0.1
                attempts=$((attempts + 1))
            done
        fi
    fi

    if [[ "${active_pid}" == "1" ]] && is_pid_running "${pid}"; then
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        yen_error "Failed to stop LSP runtime for ${root}."
        return 1
    fi

    cleanup_lsp_runtime "${root}"
    timeline_log "lsp-stop" "${root}" "stopped" "previous=${previous_state};pid=${pid};forced=${forced}"
    lock_released="1"
    release_state_lock "${lock_dir}"
    trap - ERR
    return 0
}

emit_lsp_diagnostics_rows() {
    local diagnostics_file="$1"
    local root="$2"
    local severity_csv="$3"
    local limit="$4"

    python3 - "${diagnostics_file}" "${root}" "${severity_csv}" "${limit}" <<'PY'
import json
import pathlib
import sys

diagnostics_file = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()
severity_csv = sys.argv[3]
limit = int(sys.argv[4])

severity_rank = {
    "error": 0,
    "warning": 1,
    "info": 2,
    "hint": 3,
}

allowed = None
if severity_csv and severity_csv != "all":
    allowed = {token.strip().lower() for token in severity_csv.split(",") if token.strip()}

try:
    with diagnostics_file.open("r", encoding="utf-8") as fh:
        payload = json.load(fh)
except Exception as exc:
    print(f"invalid diagnostics snapshot: {exc}", file=sys.stderr)
    raise SystemExit(2)

items = payload.get("items", []) if isinstance(payload, dict) else payload

def clean_text(value: object) -> str:
    return " ".join(str(value or "").replace("\t", " ").split())

def normalize_file(path_value):
    raw = str(path_value or "").strip()
    if not raw:
        raw = "."
    candidate = pathlib.Path(raw)
    abs_path = candidate if candidate.is_absolute() else (root / candidate)
    abs_path = abs_path.resolve()
    try:
        rel = abs_path.relative_to(root)
        rel_text = str(rel)
    except ValueError:
        rel_text = raw
    return rel_text, str(abs_path)

rows = []
for item in items:
    if not isinstance(item, dict):
        continue
    severity = clean_text(item.get("severity") or "error").lower()
    if allowed is not None and severity not in allowed:
        continue
    line = int(item.get("line") or 1)
    col = int(item.get("col") or item.get("column") or 1)
    rel_file, abs_path = normalize_file(item.get("file") or item.get("path"))
    code = clean_text(item.get("code"))
    source = clean_text(item.get("source"))
    message = clean_text(item.get("message"))
    location = f"{rel_file}:{line}:{col}"
    rows.append(
        (
            rel_file,
            severity_rank.get(severity, 99),
            line,
            col,
            severity,
            code,
            source,
            message,
            abs_path,
            location,
        )
    )

rows.sort(key=lambda row: (row[0], row[1], row[2], row[3], row[5], row[7], row[6], row[8]))

for row in rows[:limit]:
    print(
        "\t".join(
            [
                row[0],
                str(row[2]),
                str(row[3]),
                row[4],
                row[5],
                row[6],
                row[7],
                row[8],
                row[9],
            ]
        )
    )
PY
}

cmd_lsp_status() {
    local target=""
    local format="text"
    local root=""
    local trusted="no"
    local runtime_state=""
    local project_dir=""
    local socket_file=""
    local pid_file=""
    local state_file=""
    local diagnostics_file=""
    local pid=""
    local impl=""
    local started_at=""
    local health=""
    local resolution_status=""
    local resolution_reason=""
    local expected_server=""
    local protocol_mode=""
    local protocol_status=""
    local protocol_ready_at=""
    local server_label=""
    local server_command=""
    local language_id=""
    local child_pid=""
    local child_exit_code=""
    local last_error=""
    local diagnostics_status=""
    local diagnostics_updated_at=""
    local diagnostics_count=""
    local daemon_log_file=""
    local detected_language=""
    local install_family=""
    local install_manager=""
    local install_root=""
    local install_strategy=""
    local install_hint=""
    local update_hint=""
    local install_note=""
    local install_status=""
    local ast_language=""
    local ast_source=""
    local ast_ready=""
    local ast_hint=""
    local ast_guidance=""

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

    root=$(find_project_root "${target}")
    if is_lsp_trusted_project "${root}"; then
        trusted="yes"
    fi
    runtime_state=$(lsp_runtime_state "${root}")
    project_dir=$(lsp_project_dir "${root}")
    socket_file=$(lsp_socket_file "${root}")
    pid_file=$(lsp_pid_file "${root}")
    state_file=$(lsp_state_file "${root}")
    diagnostics_file=$(lsp_diagnostics_file "${root}")
    pid=$(read_lsp_pid "${root}")
    impl=$(lsp_state_value "${root}" "impl")
    started_at=$(lsp_state_value "${root}" "started_at")
    health=$(lsp_health_status "${root}")
    resolution_status=$(lsp_resolution_status "${root}")
    resolution_reason=$(lsp_resolution_reason "${root}")
    expected_server=$(lsp_expected_server "${root}")
    protocol_mode=$(lsp_state_value "${root}" "protocol_mode")
    protocol_status=$(lsp_protocol_status "${root}")
    protocol_ready_at=$(lsp_state_value "${root}" "protocol_ready_at")
    server_label=$(lsp_state_value "${root}" "server_label")
    server_command=$(lsp_state_value "${root}" "server_command")
    language_id=$(lsp_state_value "${root}" "language_id")
    child_pid=$(lsp_state_value "${root}" "child_pid")
    child_exit_code=$(lsp_state_value "${root}" "child_exit_code")
    last_error=$(lsp_state_value "${root}" "last_error")
    diagnostics_status=$(lsp_diagnostics_status "${root}")
    diagnostics_updated_at=$(lsp_state_value "${root}" "diagnostics_updated_at")
    diagnostics_count=$(lsp_state_value "${root}" "diagnostics_count")
    daemon_log_file=$(lsp_daemon_log_file "${root}")
    detected_language=$(lsp_detected_language "${root}" 2>/dev/null || true)
    if [[ -n "${detected_language}" ]]; then
        install_family=$(lsp_install_family "${detected_language}" 2>/dev/null || true)
        install_manager=$(lsp_install_manager_label "${detected_language}" 2>/dev/null || true)
        install_root=$(lsp_install_runtime_root_display "${detected_language}" 2>/dev/null || true)
        install_strategy=$(lsp_install_strategy "${detected_language}" 2>/dev/null || true)
        install_hint=$(lsp_install_command_text "${detected_language}" 2>/dev/null || true)
        update_hint=$(lsp_update_command_text "${detected_language}" 2>/dev/null || true)
        install_note=$(lsp_install_note "${detected_language}" 2>/dev/null || true)
        install_status=$(lsp_server_available_for_language "${detected_language}" 2>/dev/null || true)
    fi
    ast_language=$(ast_detected_language "${root}" 2>/dev/null || true)
    ast_source=$(ast_source_label "${root}" "${ast_language:-unknown}" 2>/dev/null || true)
    ast_ready=$(ast_ready_state "${root}" "${ast_language:-unknown}" 2>/dev/null || true)
    ast_hint=$(ast_install_hint "${ast_language:-unknown}" 2>/dev/null || true)
    ast_guidance=$(ast_guidance_text "${root}" "${ast_language:-unknown}" 2>/dev/null || true)

    case "${format}" in
        env)
            printf "export YEN_IDE_LSP_ROOT=%s\n" "$(shell_quote_single "${root}")"
            printf "export YEN_IDE_LSP_TRUSTED=%s\n" "$(shell_quote_single "${trusted}")"
            printf "export YEN_IDE_LSP_STATE=%s\n" "$(shell_quote_single "${runtime_state}")"
            printf "export YEN_IDE_LSP_PROJECT_DIR=%s\n" "$(shell_quote_single "${project_dir}")"
            printf "export YEN_IDE_LSP_SOCKET=%s\n" "$(shell_quote_single "${socket_file}")"
            printf "export YEN_IDE_LSP_PID_FILE=%s\n" "$(shell_quote_single "${pid_file}")"
            printf "export YEN_IDE_LSP_STATE_FILE=%s\n" "$(shell_quote_single "${state_file}")"
            printf "export YEN_IDE_LSP_DIAGNOSTICS_FILE=%s\n" "$(shell_quote_single "${diagnostics_file}")"
            printf "export YEN_IDE_LSP_DAEMON_LOG_FILE=%s\n" "$(shell_quote_single "${daemon_log_file}")"
            printf "export YEN_IDE_LSP_PID=%s\n" "$(shell_quote_single "${pid}")"
            printf "export YEN_IDE_LSP_IMPL=%s\n" "$(shell_quote_single "${impl}")"
            printf "export YEN_IDE_LSP_STARTED_AT=%s\n" "$(shell_quote_single "${started_at}")"
            printf "export YEN_IDE_LSP_HEALTH=%s\n" "$(shell_quote_single "${health}")"
            printf "export YEN_IDE_LSP_RESOLUTION_STATUS=%s\n" "$(shell_quote_single "${resolution_status}")"
            printf "export YEN_IDE_LSP_RESOLUTION_REASON=%s\n" "$(shell_quote_single "${resolution_reason}")"
            printf "export YEN_IDE_LSP_EXPECTED_SERVER=%s\n" "$(shell_quote_single "${expected_server}")"
            printf "export YEN_IDE_LSP_MODE=%s\n" "$(shell_quote_single "${protocol_mode}")"
            printf "export YEN_IDE_LSP_PROTOCOL_STATUS=%s\n" "$(shell_quote_single "${protocol_status}")"
            printf "export YEN_IDE_LSP_PROTOCOL_READY_AT=%s\n" "$(shell_quote_single "${protocol_ready_at}")"
            printf "export YEN_IDE_LSP_SERVER=%s\n" "$(shell_quote_single "${server_label}")"
            printf "export YEN_IDE_LSP_SERVER_CMD=%s\n" "$(shell_quote_single "${server_command}")"
            printf "export YEN_IDE_LSP_LANGUAGE_ID=%s\n" "$(shell_quote_single "${language_id}")"
            printf "export YEN_IDE_LSP_CHILD_PID=%s\n" "$(shell_quote_single "${child_pid}")"
            printf "export YEN_IDE_LSP_CHILD_EXIT_CODE=%s\n" "$(shell_quote_single "${child_exit_code}")"
            printf "export YEN_IDE_LSP_LAST_ERROR=%s\n" "$(shell_quote_single "${last_error}")"
            printf "export YEN_IDE_LSP_DIAGNOSTICS_STATUS=%s\n" "$(shell_quote_single "${diagnostics_status}")"
            printf "export YEN_IDE_LSP_DIAGNOSTICS_UPDATED_AT=%s\n" "$(shell_quote_single "${diagnostics_updated_at}")"
            printf "export YEN_IDE_LSP_DIAGNOSTICS_COUNT=%s\n" "$(shell_quote_single "${diagnostics_count}")"
            printf "export YEN_IDE_LSP_DETECTED_LANGUAGE=%s\n" "$(shell_quote_single "${detected_language}")"
            printf "export YEN_IDE_LSP_INSTALL_FAMILY=%s\n" "$(shell_quote_single "${install_family}")"
            printf "export YEN_IDE_LSP_INSTALL_MANAGER=%s\n" "$(shell_quote_single "${install_manager}")"
            printf "export YEN_IDE_LSP_INSTALL_ROOT=%s\n" "$(shell_quote_single "${install_root}")"
            printf "export YEN_IDE_LSP_INSTALL_STRATEGY=%s\n" "$(shell_quote_single "${install_strategy}")"
            printf "export YEN_IDE_LSP_INSTALL_STATUS=%s\n" "$(shell_quote_single "${install_status}")"
            printf "export YEN_IDE_LSP_INSTALL_HINT=%s\n" "$(shell_quote_single "${install_hint}")"
            printf "export YEN_IDE_LSP_UPDATE_HINT=%s\n" "$(shell_quote_single "${update_hint}")"
            printf "export YEN_IDE_LSP_INSTALL_NOTE=%s\n" "$(shell_quote_single "${install_note}")"
            printf "export YEN_IDE_LSP_AST_LANGUAGE=%s\n" "$(shell_quote_single "${ast_language}")"
            printf "export YEN_IDE_LSP_AST_SOURCE=%s\n" "$(shell_quote_single "${ast_source}")"
            printf "export YEN_IDE_LSP_AST_READY=%s\n" "$(shell_quote_single "${ast_ready}")"
            printf "export YEN_IDE_LSP_AST_HINT=%s\n" "$(shell_quote_single "${ast_hint}")"
            printf "export YEN_IDE_LSP_AST_GUIDANCE=%s\n" "$(shell_quote_single "${ast_guidance}")"
            return 0
            ;;
        json)
            python3 - "${root}" "${trusted}" "${runtime_state}" "${project_dir}" "${socket_file}" "${pid_file}" "${state_file}" "${diagnostics_file}" "${daemon_log_file}" "${pid}" "${impl}" "${started_at}" "${health}" "${resolution_status}" "${resolution_reason}" "${expected_server}" "${protocol_mode}" "${protocol_status}" "${protocol_ready_at}" "${server_label}" "${server_command}" "${language_id}" "${child_pid}" "${child_exit_code}" "${last_error}" "${diagnostics_status}" "${diagnostics_updated_at}" "${diagnostics_count}" "${detected_language}" "${install_family}" "${install_manager}" "${install_root}" "${install_strategy}" "${install_status}" "${install_hint}" "${update_hint}" "${install_note}" "${ast_language}" "${ast_source}" "${ast_ready}" "${ast_hint}" "${ast_guidance}" <<'PY'
import json
import sys

print(json.dumps(
    {
        "root": sys.argv[1],
        "trusted": sys.argv[2] == "yes",
        "runtimeState": sys.argv[3],
        "projectDir": sys.argv[4],
        "socketFile": sys.argv[5],
        "pidFile": sys.argv[6],
        "stateFile": sys.argv[7],
        "diagnosticsFile": sys.argv[8],
        "daemonLogFile": sys.argv[9],
        "pid": sys.argv[10],
        "implementation": sys.argv[11],
        "startedAt": sys.argv[12],
        "health": sys.argv[13],
        "resolutionStatus": sys.argv[14],
        "resolutionReason": sys.argv[15],
        "expectedServer": sys.argv[16],
        "protocolMode": sys.argv[17],
        "protocolStatus": sys.argv[18],
        "protocolReadyAt": sys.argv[19],
        "serverLabel": sys.argv[20],
        "serverCommand": sys.argv[21],
        "languageId": sys.argv[22],
        "childPid": sys.argv[23],
        "childExitCode": sys.argv[24],
        "lastError": sys.argv[25],
        "diagnosticsStatus": sys.argv[26],
        "diagnosticsUpdatedAt": sys.argv[27],
        "diagnosticsCount": sys.argv[28],
        "detectedLanguage": sys.argv[29],
        "installFamily": sys.argv[30],
        "installManager": sys.argv[31],
        "installRoot": sys.argv[32],
        "installStrategy": sys.argv[33],
        "installStatus": sys.argv[34],
        "installHint": sys.argv[35],
        "updateHint": sys.argv[36],
        "installNote": sys.argv[37],
        "astLanguage": sys.argv[38],
        "astSource": sys.argv[39],
        "astReady": sys.argv[40] == "yes",
        "astHint": sys.argv[41],
        "astGuidance": sys.argv[42],
    },
    indent=2,
    sort_keys=True,
))
PY
            return 0
            ;;
        text)
            ;;
        *)
            yen_error "Unknown lsp status format: ${format} (expected text|env|json)"
            return 1
            ;;
    esac

    echo ""
    yen_header "IDE LSP Status"
    echo "Project root:       ${root}"
    echo "Trusted:            ${trusted}"
    echo "Runtime state:      ${runtime_state}"
    echo "Project dir:        ${project_dir}"
    echo "Socket path:        ${socket_file}"
    echo "PID file:           ${pid_file}"
    echo "State file:         ${state_file}"
    echo "Diagnostics file:   ${diagnostics_file}"
    echo "Daemon log:         ${daemon_log_file}"
    echo "Health:             ${health}"
    if [[ -n "${detected_language}" ]]; then
        echo "Detected language:  ${detected_language}"
    fi
    if [[ -n "${install_family}" ]]; then
        echo "Install family:     ${install_family}"
    fi
    if [[ -n "${install_manager}" ]]; then
        echo "Install manager:    ${install_manager}"
    fi
    if [[ -n "${install_root}" ]]; then
        echo "Install root:       ${install_root}"
    fi
    if [[ -n "${resolution_status}" ]]; then
        echo "Resolution:         ${resolution_status}"
    fi
    if [[ -n "${expected_server}" ]]; then
        echo "Expected server:    ${expected_server}"
    fi
    if [[ -n "${install_strategy}" ]]; then
        echo "Install strategy:   ${install_strategy}"
    fi
    if [[ -n "${install_status}" ]]; then
        echo "Install status:     ${install_status}"
    fi
    if [[ -n "${install_hint}" ]]; then
        echo "Install hint:       ${install_hint}"
    fi
    if [[ -n "${update_hint}" ]]; then
        echo "Update hint:        ${update_hint}"
    fi
    if [[ -n "${install_note}" ]]; then
        echo "Install note:       ${install_note}"
    fi
    if [[ -n "${resolution_reason}" ]]; then
        echo "Guidance:           ${resolution_reason}"
    fi
    if [[ -n "${ast_language}" ]]; then
        echo "AST language:       ${ast_language}"
    fi
    if [[ -n "${ast_source}" ]]; then
        echo "AST source:         ${ast_source}"
    fi
    if [[ -n "${ast_ready}" ]]; then
        echo "AST ready:          ${ast_ready}"
    fi
    if [[ -n "${ast_hint}" ]]; then
        echo "AST install:        ${ast_hint}"
    fi
    if [[ -n "${ast_guidance}" ]]; then
        echo "AST guidance:       ${ast_guidance}"
    fi
    if [[ -n "${pid}" ]]; then
        echo "PID:                ${pid}"
    else
        echo "PID:                none"
    fi
    if [[ -n "${impl}" ]]; then
        echo "Implementation:     ${impl}"
    fi
    if [[ -n "${protocol_mode}" ]]; then
        echo "Protocol mode:      ${protocol_mode}"
    fi
    if [[ -n "${protocol_status}" ]]; then
        echo "Protocol:           ${protocol_status}"
    fi
    if [[ -n "${server_label}" ]]; then
        echo "Server:             ${server_label}"
    fi
    if [[ -n "${server_command}" ]]; then
        echo "Command:            ${server_command}"
    fi
    if [[ -n "${language_id}" ]]; then
        echo "Language:           ${language_id}"
    fi
    if [[ -n "${child_pid}" ]]; then
        echo "Child PID:          ${child_pid}"
    fi
    if [[ -n "${child_exit_code}" ]]; then
        echo "Child exit:         ${child_exit_code}"
    fi
    if [[ -n "${started_at}" ]]; then
        echo "Started at:         ${started_at}"
    fi
    if [[ -n "${protocol_ready_at}" ]]; then
        echo "Protocol ready at:  ${protocol_ready_at}"
    fi
    if [[ -n "${diagnostics_count}" ]]; then
        echo "Diagnostics count:  ${diagnostics_count}"
    fi
    if [[ -n "${diagnostics_status}" ]]; then
        echo "Diagnostics status: ${diagnostics_status}"
    fi
    if [[ -n "${diagnostics_updated_at}" ]]; then
        echo "Diagnostics at:     ${diagnostics_updated_at}"
    fi
    if [[ -n "${last_error}" ]]; then
        echo "Last error:         ${last_error}"
    fi
    if [[ "${trusted}" != "yes" ]]; then
        echo ""
        echo "Grant consent with: yen ide lsp trust \"${root}\""
    fi
    echo ""
}

cmd_lsp_diagnostics() {
    local target=""
    local severity_csv="all"
    local limit="200"
    local root=""
    local runtime_state=""
    local protocol_status=""
    local diagnostics_file=""
    local diagnostics_status=""
    local rows=""
    local row_count="0"
    local current_file=""
    local debug_handoff_file=""
    local debug_candidates=""
    local debug_handoffs=""
    local debug_handoff=""
    local handoff_target=""
    local handoff_command=""
    local handoff_tool=""
    local handoff_title=""
    local handoff_line_applied=""
    local handoff_trusted=""
    local handoff_trust_required=""
    local handoff_trust_command=""
    local handoff_notes=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --severity)
                shift
                severity_csv="${1:-all}"
                ;;
            --limit)
                shift
                limit="${1:-200}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    if [[ ! "${limit}" =~ ^[0-9]+$ ]] || [[ "${limit}" -lt 1 ]]; then
        yen_error "Invalid --limit '${limit}'. Use a positive integer."
        return 1
    fi

    root=$(find_project_root "${target}")
    runtime_state=$(lsp_runtime_state "${root}")
    protocol_status=$(lsp_protocol_status "${root}")
    diagnostics_file=$(lsp_diagnostics_file "${root}")
    diagnostics_status=$(lsp_diagnostics_status "${root}")

    if [[ ! -f "${diagnostics_file}" || ! -s "${diagnostics_file}" ]]; then
        case "${diagnostics_status}" in
            waiting)
                yen_info "Diagnostics snapshot is not available yet for ${root}."
                ;;
            unavailable)
                if [[ "${protocol_status}" == "placeholder" ]]; then
                    yen_info "No diagnostics snapshot available for ${root} because the placeholder runtime has no resolved language server."
                else
                    yen_info "No diagnostics snapshot available for ${root}. Start it with: yen ide lsp start \"${root}\""
                fi
                ;;
            *)
                yen_info "No diagnostics snapshot available for ${root}."
                ;;
        esac
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        yen_error "python3 is required to render the current diagnostics snapshot."
        return 1
    fi

    if ! rows=$(emit_lsp_diagnostics_rows "${diagnostics_file}" "${root}" "${severity_csv}" "${limit}" 2>&1); then
        yen_error "Failed to read diagnostics snapshot ${diagnostics_file}: ${rows}"
        return 1
    fi
    if [[ -z "${rows}" ]]; then
        yen_info "No diagnostics matched severity filter '${severity_csv}' for ${root}."
        return 0
    fi

    row_count=$(printf "%s\n" "${rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "lsp-diagnostics" "${root}" "hits=${row_count}" "severity=${severity_csv};limit=${limit}"

    if declare -F debug_handoff_rows_from_target_rows >/dev/null 2>&1; then
        debug_candidates=$(printf "%s\n" "${rows}" | awk -F'\t' 'NF >= 9 && $9 != "" && !seen[$9]++ { print $9 "\t" $9 }')
        if [[ -n "${debug_candidates}" ]]; then
            debug_handoffs=$(debug_handoff_rows_from_target_rows "${root}" <<EOF
${debug_candidates}
EOF
)
            if [[ -n "${debug_handoffs}" ]]; then
                debug_handoff_file=$(mktemp "${TMPDIR:-/tmp}/yen-lsp-debug-handoff.XXXXXX" 2>/dev/null || mktemp)
                printf "%s\n" "${debug_handoffs}" > "${debug_handoff_file}"
            fi
        fi
    fi

    echo ""
    yen_header "IDE LSP Diagnostics"
    echo "Root:         ${root}"
    echo "Runtime:      ${runtime_state}"
    echo "Protocol:     ${protocol_status}"
    echo "Snapshot:     ${diagnostics_file}"
    echo "Snapshot status: ${diagnostics_status}"
    echo "Severities:   ${severity_csv}"
    echo "Results:      ${row_count}"
    if [[ "${diagnostics_status}" == "stale" ]]; then
        echo "Notice:       showing last known diagnostics snapshot"
    fi
    echo ""

    while IFS=$'\t' read -r rel_file line col severity code source message abs_path location; do
        [[ -z "${location}" ]] && continue
        if [[ "${rel_file}" != "${current_file}" ]]; then
            [[ -n "${current_file}" ]] && echo ""
            echo "${rel_file}"
            printf "%-8s %-40s %-12s %-12s %s\n" "SEVERITY" "LOCATION" "CODE" "SOURCE" "MESSAGE"
            current_file="${rel_file}"
        fi
        printf "%-8s %-40s %-12s %-12s %s\n" "${severity}" "${location}" "${code:-"-"}" "${source:-"-"}" "${message}"
        if [[ -n "${debug_handoff_file}" && -f "${debug_handoff_file}" ]]; then
            debug_handoff=$(awk -F'\t' -v key="${location}" '$1 == key { print; exit }' "${debug_handoff_file}")
            if [[ -n "${debug_handoff}" ]]; then
                IFS=$'\t' read -r _location handoff_target handoff_command handoff_tool handoff_title handoff_line_applied handoff_trusted handoff_trust_required handoff_trust_command handoff_notes << EOF
${debug_handoff}
EOF
                [[ -n "${handoff_command}" ]] && echo "           debug: ${handoff_command}"
                [[ "${handoff_trust_required}" == "yes" && -n "${handoff_trust_command}" ]] && echo "           trust: ${handoff_trust_command}"
            fi
        fi
    done << EOF
${rows}
EOF
    [[ -n "${debug_handoff_file}" ]] && rm -f "${debug_handoff_file}"
    echo ""
}

cmd_lsp_hover() {
    local target=""
    local location_arg=""
    local file_path=""
    local line="1"
    local col="1"
    local root=""
    local response=""
    local ok=""
    local contents=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --file)
                shift
                file_path="${1:-}"
                ;;
            --line)
                shift
                line="${1:-1}"
                ;;
            --col|--column)
                shift
                col="${1:-1}"
                ;;
            *)
                if [[ -z "${location_arg}" ]]; then
                    location_arg="$1"
                else
                    yen_error "Unknown hover option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -n "${location_arg}" ]]; then
        IFS=$'\t' read -r file_path line col << EOF
$(lsp_parse_location_arg "${location_arg}")
EOF
    fi
    if [[ -z "${file_path}" ]]; then
        yen_error "hover requires a file location. Example: yen ide lsp hover src/app.ts:12:3"
        return 1
    fi
    root=$(find_project_root "${target:-${file_path}}")
    if ! lsp_runtime_ready_or_error "${root}"; then
        return 1
    fi
    if ! response=$(lsp_send_control_request "${root}" "hover" "${file_path}" "${line}" "${col}" "1" "" 2>&1); then
        yen_error "hover request failed: ${response}"
        return 1
    fi
    ok=$(lsp_response_value "${response}" "ok")
    if [[ "${ok}" != "true" ]]; then
        yen_error "hover request failed: $(lsp_response_value "${response}" "error")"
        return 1
    fi
    contents=$(lsp_response_value "${response}" "contents")
    if [[ -z "${contents}" ]]; then
        yen_info "No hover result for ${file_path}:${line}:${col}"
        return 0
    fi
    timeline_log "lsp-hover" "${root}" "ok" "file=${file_path};line=${line};col=${col}"
    echo ""
    yen_header "IDE LSP Hover"
    echo "Root:      ${root}"
    echo "Location:  ${file_path}:${line}:${col}"
    echo "Source:    lsp"
    echo ""
    printf "%s\n" "${contents}"
    echo ""
}

cmd_lsp_definition() {
    local target=""
    local location_arg=""
    local file_path=""
    local line="1"
    local col="1"
    local root=""
    local response=""
    local ok=""
    local rows=""
    local count="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --file)
                shift
                file_path="${1:-}"
                ;;
            --line)
                shift
                line="${1:-1}"
                ;;
            --col|--column)
                shift
                col="${1:-1}"
                ;;
            *)
                if [[ -z "${location_arg}" ]]; then
                    location_arg="$1"
                else
                    yen_error "Unknown definition option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -n "${location_arg}" ]]; then
        IFS=$'\t' read -r file_path line col << EOF
$(lsp_parse_location_arg "${location_arg}")
EOF
    fi
    if [[ -z "${file_path}" ]]; then
        yen_error "definition requires a file location. Example: yen ide lsp definition src/app.ts:12:3"
        return 1
    fi
    root=$(find_project_root "${target:-${file_path}}")
    if ! lsp_runtime_ready_or_error "${root}"; then
        return 1
    fi
    if ! response=$(lsp_send_control_request "${root}" "definition" "${file_path}" "${line}" "${col}" "1" "" 2>&1); then
        yen_error "definition request failed: ${response}"
        return 1
    fi
    ok=$(lsp_response_value "${response}" "ok")
    if [[ "${ok}" != "true" ]]; then
        yen_error "definition request failed: $(lsp_response_value "${response}" "error")"
        return 1
    fi
    rows=$(emit_lsp_response_locations "${response}")
    if [[ -z "${rows}" ]]; then
        yen_info "No definition result for ${file_path}:${line}:${col}"
        return 0
    fi
    count=$(printf "%s\n" "${rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "lsp-definition" "${root}" "hits=${count}" "file=${file_path};line=${line};col=${col}"
    echo ""
    yen_header "IDE LSP Definition"
    echo "Root:      ${root}"
    echo "Location:  ${file_path}:${line}:${col}"
    echo "Source:    lsp"
    echo "Results:   ${count}"
    echo ""
    printf "%-7s %-7s %s\n" "LINE" "COL" "LOCATION"
    while IFS=$'\t' read -r _ line_value col_value location; do
        [[ -z "${location}" ]] && continue
        printf "%-7s %-7s %s\n" "${line_value}" "${col_value}" "${location}"
    done << EOF
${rows}
EOF
    echo ""
}

cmd_lsp_references() {
    local target=""
    local location_arg=""
    local file_path=""
    local line="1"
    local col="1"
    local include_declaration="1"
    local root=""
    local response=""
    local ok=""
    local rows=""
    local count="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --file)
                shift
                file_path="${1:-}"
                ;;
            --line)
                shift
                line="${1:-1}"
                ;;
            --col|--column)
                shift
                col="${1:-1}"
                ;;
            --exclude-declaration|--no-declaration)
                include_declaration="0"
                ;;
            *)
                if [[ -z "${location_arg}" ]]; then
                    location_arg="$1"
                else
                    yen_error "Unknown references option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -n "${location_arg}" ]]; then
        IFS=$'\t' read -r file_path line col << EOF
$(lsp_parse_location_arg "${location_arg}")
EOF
    fi
    if [[ -z "${file_path}" ]]; then
        yen_error "references requires a file location. Example: yen ide lsp references src/app.ts:12:3"
        return 1
    fi
    root=$(find_project_root "${target:-${file_path}}")
    if ! lsp_runtime_ready_or_error "${root}"; then
        return 1
    fi
    if ! response=$(lsp_send_control_request "${root}" "references" "${file_path}" "${line}" "${col}" "${include_declaration}" "" 2>&1); then
        yen_error "references request failed: ${response}"
        return 1
    fi
    ok=$(lsp_response_value "${response}" "ok")
    if [[ "${ok}" != "true" ]]; then
        yen_error "references request failed: $(lsp_response_value "${response}" "error")"
        return 1
    fi
    rows=$(emit_lsp_response_locations "${response}")
    if [[ -z "${rows}" ]]; then
        yen_info "No references found for ${file_path}:${line}:${col}"
        return 0
    fi
    count=$(printf "%s\n" "${rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "lsp-references" "${root}" "hits=${count}" "file=${file_path};line=${line};col=${col};include_declaration=${include_declaration}"
    echo ""
    yen_header "IDE LSP References"
    echo "Root:      ${root}"
    echo "Location:  ${file_path}:${line}:${col}"
    echo "Source:    lsp"
    echo "Results:   ${count}"
    echo ""
    printf "%-7s %-7s %s\n" "LINE" "COL" "LOCATION"
    while IFS=$'\t' read -r _ line_value col_value location; do
        [[ -z "${location}" ]] && continue
        printf "%-7s %-7s %s\n" "${line_value}" "${col_value}" "${location}"
    done << EOF
${rows}
EOF
    echo ""
}

cmd_lsp_code_actions() {
    local target=""
    local location_arg=""
    local file_path=""
    local line="1"
    local col="1"
    local format="text"
    local apply_changes="0"
    local root=""
    local response=""
    local ok=""
    local rendered=""
    local summary=""
    local rows=""
    local action_count="0"
    local selectable_count="0"
    local preferred_count="0"
    local selection_status=""
    local selected_index="0"
    local selection_reason=""
    local selected_title=""
    local selected_mode=""
    local selected_file_count="0"
    local selected_edit_count="0"
    local selected_command_name=""
    local edit_wrapper=""
    local applied=""
    local error_message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --file)
                shift
                file_path="${1:-}"
                ;;
            --line)
                shift
                line="${1:-1}"
                ;;
            --col|--column)
                shift
                col="${1:-1}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            --apply|--write)
                apply_changes="1"
                ;;
            *)
                if [[ -z "${location_arg}" ]]; then
                    location_arg="$1"
                else
                    yen_error "Unknown code-actions option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    case "${format}" in
        text|json)
            ;;
        *)
            yen_error "Unknown code-actions format: ${format} (expected text|json)"
            return 1
            ;;
    esac

    if [[ -n "${location_arg}" ]]; then
        IFS=$'\t' read -r file_path line col << EOF
$(lsp_parse_location_arg "${location_arg}")
EOF
    fi
    if [[ -z "${file_path}" ]]; then
        yen_error "code-actions requires a file location. Example: yen ide lsp code-actions src/app.ts:12:3"
        return 1
    fi
    root=$(find_project_root "${target:-${file_path}}")
    if ! lsp_runtime_ready_or_error "${root}"; then
        return 1
    fi
    if ! response=$(lsp_send_control_request "${root}" "code-actions" "${file_path}" "${line}" "${col}" "1" "" 2>&1); then
        yen_error "code-actions request failed: ${response}"
        return 1
    fi
    ok=$(lsp_response_value "${response}" "ok")
    if [[ "${ok}" != "true" ]]; then
        yen_error "code-actions request failed: $(lsp_response_value "${response}" "error")"
        return 1
    fi
    if ! rendered=$(emit_lsp_code_action_rows "${response}" 2>&1); then
        yen_error "Failed to render code actions: ${rendered}"
        return 1
    fi

    summary=$(printf "%s\n" "${rendered}" | sed -n '1p')
    rows=$(printf "%s\n" "${rendered}" | tail -n +2)
    action_count=$(printf "%s\n" "${summary}" | cut -f2)
    selectable_count=$(printf "%s\n" "${summary}" | cut -f3)
    preferred_count=$(printf "%s\n" "${summary}" | cut -f4)
    selection_status=$(printf "%s\n" "${summary}" | cut -f5)
    selected_index=$(printf "%s\n" "${summary}" | cut -f6)
    selection_reason=$(printf "%s\n" "${summary}" | cut -f7-)

    if [[ "${action_count}" == "0" || -z "${action_count}" ]]; then
        if [[ "${apply_changes}" == "1" ]]; then
            error_message="No code actions are available for ${file_path}:${line}:${col}."
            timeline_log "lsp-code-actions" "${root}" "none" "file=${file_path};line=${line};col=${col}"
            if [[ "${format}" == "json" ]]; then
                emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "0" "${error_message}"
                return 1
            fi
            yen_error "${error_message}"
            return 1
        fi
        timeline_log "lsp-code-actions" "${root}" "none" "file=${file_path};line=${line};col=${col}"
        if [[ "${format}" == "json" ]]; then
            emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "0" ""
            return 0
        fi
        yen_info "No code actions available for ${file_path}:${line}:${col}"
        return 0
    fi

    if [[ "${selected_index}" =~ ^[0-9]+$ ]] && [[ "${selected_index}" -gt 0 ]]; then
        IFS=$'\t' read -r selected_title selected_mode selected_file_count selected_edit_count selected_command_name << EOF
$(printf "%s\n" "${rows}" | awk -F'\t' -v idx="${selected_index}" '$1 == "ACTION" && $2 == idx { print $3 "\t" $7 "\t" $8 "\t" $9 "\t" $10; exit }')
EOF
    fi

    if [[ "${apply_changes}" == "1" ]]; then
        if [[ "${selected_index}" -lt 1 ]]; then
            error_message="Cannot auto-apply code actions for ${file_path}:${line}:${col}. ${selection_reason}"
            timeline_log "lsp-code-actions" "${root}" "blocked" "file=${file_path};line=${line};col=${col};selection=${selection_status};actions=${action_count}"
            if [[ "${format}" == "json" ]]; then
                emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "0" "${error_message}"
                return 1
            fi
        elif [[ "${selected_mode}" != "edit" ]]; then
            error_message="Cannot auto-apply the selected code action for ${file_path}:${line}:${col} because it is '${selected_mode}', not a pure workspace edit."
            timeline_log "lsp-code-actions" "${root}" "blocked" "file=${file_path};line=${line};col=${col};selection=${selection_status};mode=${selected_mode};actions=${action_count}"
            if [[ "${format}" == "json" ]]; then
                emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "${selected_index}" "${error_message}"
                return 1
            fi
        else
            if ! edit_wrapper=$(lsp_code_action_edit_wrapper "${response}" "${selected_index}" 2>&1); then
                error_message="Failed to prepare the selected code action edit: ${edit_wrapper}"
                timeline_log "lsp-code-actions" "${root}" "blocked" "file=${file_path};line=${line};col=${col};selection=${selection_status};error=wrap-failed"
                if [[ "${format}" == "json" ]]; then
                    emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "${selected_index}" "${error_message}"
                    return 1
                fi
            else
                if ! applied=$(apply_lsp_workspace_edit "${edit_wrapper}" 2>&1); then
                    error_message="Failed to apply code action edits: ${applied}"
                    timeline_log "lsp-code-actions" "${root}" "blocked" "file=${file_path};line=${line};col=${col};selection=${selection_status};error=apply-failed"
                    if [[ "${format}" == "json" ]]; then
                        emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "${selected_index}" "${error_message}"
                        return 1
                    fi
                else
                    timeline_log "lsp-code-actions" "${root}" "applied" "file=${file_path};line=${line};col=${col};selection=${selection_status};index=${selected_index};title=${selected_title};files=${selected_file_count};edits=${selected_edit_count}"
                    if [[ "${format}" == "json" ]]; then
                        emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "1" "${selected_index}" ""
                        return 0
                    fi
                    echo ""
                    yen_header "IDE LSP Code Actions"
                    echo "Root:      ${root}"
                    echo "Location:  ${file_path}:${line}:${col}"
                    echo "Source:    lsp"
                    echo "Applied:   yes"
                    echo "Actions:   ${action_count}"
                    echo "Selectable edits: ${selectable_count}"
                    echo "Selection: ${selection_status}"
                    echo "Selected:  #${selected_index} ${selected_title}"
                    echo "Files:     ${selected_file_count}"
                    echo "Edits:     ${selected_edit_count}"
                    echo ""
                    printf "%-3s %-13s %-18s %-5s %-5s %-5s %s\n" "#" "MODE" "KIND" "PREF" "FILES" "EDITS" "TITLE"
                    while IFS=$'\t' read -r record_type index title kind preferred disabled apply_mode file_count edit_count command_name disabled_reason; do
                        [[ "${record_type}" != "ACTION" ]] && continue
                        [[ -z "${title}" ]] && title="-"
                        [[ -z "${kind}" ]] && kind="-"
                        printf "%-3s %-13s %-18s %-5s %-5s %-5s %s\n" "${index}" "${apply_mode}" "${kind}" "${preferred}" "${file_count}" "${edit_count}" "${title}"
                        [[ -n "${command_name}" ]] && echo "    command: ${command_name}"
                        [[ -n "${disabled_reason}" ]] && echo "    disabled: ${disabled_reason}"
                    done << EOF
${rows}
EOF
                    echo ""
                    return 0
                fi
            fi
        fi
    fi

    if [[ "${format}" == "json" ]]; then
        emit_lsp_code_actions_json "${response}" "${root}" "${file_path}" "${line}" "${col}" "${apply_changes}" "0" "${selected_index}" "${error_message}"
        [[ -n "${error_message}" ]] && return 1
        timeline_log "lsp-code-actions" "${root}" "preview" "file=${file_path};line=${line};col=${col};actions=${action_count};selection=${selection_status}"
        return 0
    fi

    echo ""
    yen_header "IDE LSP Code Actions"
    echo "Root:      ${root}"
    echo "Location:  ${file_path}:${line}:${col}"
    echo "Source:    lsp"
    echo "Applied:   no"
    echo "Actions:   ${action_count}"
    echo "Selectable edits: ${selectable_count}"
    echo "Preferred selectable: ${preferred_count}"
    echo "Selection: ${selection_status}"
    echo "Guidance:  ${selection_reason}"
    if [[ "${selected_index}" -gt 0 ]]; then
        echo "Auto-apply candidate: #${selected_index} ${selected_title}"
    fi
    echo ""
    printf "%-3s %-13s %-18s %-5s %-5s %-5s %s\n" "#" "MODE" "KIND" "PREF" "FILES" "EDITS" "TITLE"
    while IFS=$'\t' read -r record_type index title kind preferred disabled apply_mode file_count edit_count command_name disabled_reason; do
        [[ "${record_type}" != "ACTION" ]] && continue
        [[ -z "${title}" ]] && title="-"
        [[ -z "${kind}" ]] && kind="-"
        printf "%-3s %-13s %-18s %-5s %-5s %-5s %s\n" "${index}" "${apply_mode}" "${kind}" "${preferred}" "${file_count}" "${edit_count}" "${title}"
        [[ -n "${command_name}" ]] && echo "    command: ${command_name}"
        [[ -n "${disabled_reason}" ]] && echo "    disabled: ${disabled_reason}"
    done << EOF
${rows}
EOF
    echo ""
    timeline_log "lsp-code-actions" "${root}" "preview" "file=${file_path};line=${line};col=${col};actions=${action_count};selection=${selection_status}"

    if [[ -n "${error_message}" ]]; then
        yen_error "${error_message}"
        return 1
    fi
}

cmd_lsp_rename() {
    local target=""
    local location_arg=""
    local file_path=""
    local line="1"
    local col="1"
    local new_name=""
    local apply_changes="0"
    local root=""
    local response=""
    local ok=""
    local edit_count="0"
    local touched_count="0"
    local rendered=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --file)
                shift
                file_path="${1:-}"
                ;;
            --line)
                shift
                line="${1:-1}"
                ;;
            --col|--column)
                shift
                col="${1:-1}"
                ;;
            --new-name)
                shift
                new_name="${1:-}"
                ;;
            --write|--apply)
                apply_changes="1"
                ;;
            *)
                if [[ -z "${location_arg}" ]]; then
                    location_arg="$1"
                else
                    yen_error "Unknown rename option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ -n "${location_arg}" ]]; then
        IFS=$'\t' read -r file_path line col << EOF
$(lsp_parse_location_arg "${location_arg}")
EOF
    fi
    if [[ -z "${file_path}" ]]; then
        yen_error "rename requires a file location. Example: yen ide lsp rename src/app.ts:12:3 --new-name nextValue"
        return 1
    fi
    if [[ -z "${new_name}" ]]; then
        yen_error "rename requires --new-name <value>."
        return 1
    fi
    root=$(find_project_root "${target:-${file_path}}")
    if ! lsp_runtime_ready_or_error "${root}"; then
        return 1
    fi
    if ! response=$(lsp_send_control_request "${root}" "rename" "${file_path}" "${line}" "${col}" "1" "${new_name}" 2>&1); then
        yen_error "rename request failed: ${response}"
        return 1
    fi
    ok=$(lsp_response_value "${response}" "ok")
    if [[ "${ok}" != "true" ]]; then
        yen_error "rename request failed: $(lsp_response_value "${response}" "error")"
        return 1
    fi
    rendered=$(python3 - "${response}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
edit = payload.get("edit") or {}
entries = []
entries.extend(edit.get("changes") or [])
entries.extend(edit.get("documentChanges") or [])
total_edits = 0
for entry in entries:
    total_edits += len(entry.get("edits") or [])
print(f"{len(entries)}\t{total_edits}")
for entry in entries:
    path = entry.get("path") or ""
    edits = entry.get("edits") or []
    print("\t".join([path, str(len(edits))]))
PY
)
    touched_count=$(printf "%s\n" "${rendered}" | sed -n '1p' | cut -f1)
    edit_count=$(printf "%s\n" "${rendered}" | sed -n '1p' | cut -f2)
    if [[ "${edit_count}" == "0" || -z "${edit_count}" ]]; then
        yen_info "Rename produced no edits for ${file_path}:${line}:${col}"
        return 0
    fi
    if [[ "${apply_changes}" == "1" ]]; then
        local applied=""
        if ! applied=$(apply_lsp_workspace_edit "${response}" 2>&1); then
            yen_error "Failed to apply rename edits: ${applied}"
            return 1
        fi
        timeline_log "lsp-rename" "${root}" "applied" "file=${file_path};line=${line};col=${col};new_name=${new_name};files=${touched_count};edits=${edit_count}"
        echo ""
        yen_header "IDE LSP Rename"
        echo "Root:      ${root}"
        echo "Location:  ${file_path}:${line}:${col}"
        echo "Source:    lsp"
        echo "Applied:   yes"
        echo "New name:  ${new_name}"
        echo "Files:     ${touched_count}"
        echo "Edits:     ${edit_count}"
        echo ""
        printf "%-5s %s\n" "EDITS" "FILE"
        while IFS=$'\t' read -r path_value edit_value; do
            [[ -z "${path_value}" ]] && continue
            printf "%-5s %s\n" "${edit_value}" "${path_value}"
        done << EOF
${applied}
EOF
        echo ""
        return 0
    fi

    timeline_log "lsp-rename" "${root}" "preview" "file=${file_path};line=${line};col=${col};new_name=${new_name};files=${touched_count};edits=${edit_count}"
    echo ""
    yen_header "IDE LSP Rename"
    echo "Root:      ${root}"
    echo "Location:  ${file_path}:${line}:${col}"
    echo "Source:    lsp"
    echo "Applied:   no"
    echo "New name:  ${new_name}"
    echo "Files:     ${touched_count}"
    echo "Edits:     ${edit_count}"
    echo "Use --write to apply the returned workspace edit."
    echo ""
    printf "%-5s %s\n" "EDITS" "FILE"
    printf "%s\n" "${rendered}" | tail -n +2 | while IFS=$'\t' read -r path_value edit_value; do
        [[ -z "${path_value}" ]] && continue
        printf "%-5s %s\n" "${edit_value}" "${path_value}"
    done
    echo ""
}

cmd_lsp_install() {
    local mode="${1:-status}"
    if [[ $# -gt 0 ]]; then
        shift || true
    fi
    local target=""
    local requested_language=""
    local all_languages="0"
    local dry_run="0"
    local root=""
    local languages=""
    local language=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --language)
                shift
                requested_language="${1:-}"
                ;;
            --all)
                all_languages="1"
                ;;
            --dry-run)
                dry_run="1"
                ;;
            *)
                if [[ -z "${requested_language}" ]]; then
                    requested_language="$1"
                else
                    yen_error "Unknown lsp install option/arg: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    if [[ "${all_languages}" == "1" ]]; then
        languages=$'typescript\njavascript\npython\ngo\nrust\nswift\nzig'
    else
        language=$(lsp_install_target_language "${root}" "${requested_language}" 2>/dev/null || true)
        if [[ -z "${language}" ]]; then
            yen_error "Unknown or unsupported LSP install language '${requested_language:-auto}'."
            return 1
        fi
        languages="${language}"
    fi

    case "${mode}" in
        status|list)
            echo ""
            yen_header "IDE LSP Install Matrix"
            echo "Root:      ${root}"
            echo "State dir: ${IDE_LSP_TOOLS_DIR}"
            echo ""
            printf "%-12s %-30s %-24s %-10s %s\n" "LANGUAGE" "SERVER" "MANAGER" "INSTALLED" "AST"
            while IFS= read -r language; do
                [[ -z "${language}" ]] && continue
                local strategy=""
                local installed="no"
                local pin=""
                local footprint=""
                local server=""
                local manager=""
                local family=""
                local root_hint=""
                local note=""
                local ast_summary=""
                strategy=$(lsp_install_strategy "${language}")
                footprint=$(lsp_install_footprint_bound "${language}")
                pin=$(lsp_install_pin_version "${language}")
                server=$(lsp_expected_server_for_language "${language}")
                manager=$(lsp_install_manager_label "${language}")
                family=$(lsp_install_family "${language}")
                root_hint=$(lsp_install_runtime_root_display "${language}")
                note=$(lsp_install_note "${language}")
                installed=$(lsp_server_available_for_language "${language}")
                ast_summary=$(ast_source_label "${root}" "${language}")
                if [[ -z "${ast_summary}" || "${ast_summary}" == "none" ]]; then
                    ast_summary="not-shipped"
                fi
                printf "%-12s %-30s %-24s %-10s %s\n" "${language}" "${server}" "${manager}" "${installed}" "${ast_summary}"
                echo "  family:    ${family}"
                echo "  strategy:  ${strategy}"
                echo "  root:      ${root_hint}"
                echo "  footprint: ${footprint}"
                echo "  pin:       ${pin}"
                echo "  note:      ${note}"
                echo "  install: $(lsp_install_command_text "${language}")"
                echo "  update:  $(lsp_update_command_text "${language}")"
            done << EOF
${languages}
EOF
            echo ""
            ;;
        install|update)
            if [[ "${all_languages}" == "1" ]]; then
                yen_error "install/update accepts a single language at a time."
                return 1
            fi
            language=$(printf "%s\n" "${languages}" | head -n 1)
            local strategy=""
            local manager=""
            local family=""
            local root_hint=""
            local note=""
            local command_text=""
            local mode_title=""
            local tool_root=""
            strategy=$(lsp_install_strategy "${language}")
            manager=$(lsp_install_manager_label "${language}")
            family=$(lsp_install_family "${language}")
            root_hint=$(lsp_install_runtime_root_display "${language}")
            note=$(lsp_install_note "${language}")
            if [[ "${mode}" == "update" ]]; then
                command_text=$(lsp_update_command_text "${language}")
            else
                command_text=$(lsp_install_command_text "${language}")
            fi
            mode_title=$(printf "%s" "${mode}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
            tool_root=$(lsp_managed_tool_root "${language}" 2>/dev/null || true)
            echo ""
            yen_header "IDE LSP ${mode_title}"
            echo "Root:      ${root}"
            echo "Language:  ${language}"
            echo "Strategy:  ${strategy}"
            echo "Manager:   ${manager}"
            echo "Family:    ${family}"
            echo "Runtime:   ${root_hint}"
            echo "Pin:       $(lsp_install_pin_version "${language}")"
            echo "Note:      ${note}"
            echo "Command:   ${command_text}"
            if [[ "${dry_run}" == "1" ]]; then
                echo "Dry run:   yes"
                echo ""
                return 0
            fi
            case "${strategy}" in
                managed-npm-prefix|managed-gobin)
                    [[ -n "${tool_root}" ]] && mkdir -p "${tool_root}" "${tool_root}/bin"
                    if ! bash -lc "${command_text}"; then
                        yen_error "Failed to ${mode} LSP server for ${language}."
                        return 1
                    fi
                    ;;
                toolchain-path)
                    yen_info "This server is toolchain-managed. Run the printed command manually."
                    echo ""
                    return 0
                    ;;
                *)
                    yen_error "Unknown install strategy '${strategy}'."
                    return 1
                    ;;
            esac
            timeline_log "lsp-install" "${root}" "${mode}" "language=${language};strategy=${strategy}"
            yen_success "LSP ${mode} complete for ${language}."
            echo ""
            ;;
        *)
            yen_error "Unknown lsp install mode: ${mode} (expected status|list|install|update)"
            return 1
            ;;
    esac
}

cmd_lsp_start() {
    local target=""
    local root=""
    local project_dir=""
    local socket_file=""
    local pid_file=""
    local state_file=""
    local diagnostics_file=""
    local daemon_script=""
    local runtime_state=""
    local health=""
    local python_source=""
    local pid=""
    local attempts=0
    local max_attempts=120
    local protocol_mode=""
    local impl=""
    local server_label=""
    local server_command=""
    local language_id=""
    local extensions_csv=""
    local resolution_status=""
    local resolution_reason=""
    local expected_server=""
    local daemon_status=""
    local protocol_status=""
    local protocol_ready_at=""
    local lock_dir=""
    local daemon_log_file=""
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

    root=$(find_project_root "${target}")
    if ! ensure_lsp_trusted_or_prompt "${root}"; then
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        yen_error "python3 is required for the current local LSP runtime scaffold."
        return 1
    fi

    lock_dir=$(lsp_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "LSP lifecycle"; then
        return 1
    fi
    trap 'if [[ "${lock_released}" != "1" && -n "${lock_dir}" ]]; then release_state_lock "${lock_dir}"; lock_released="1"; fi; trap - ERR' ERR

    runtime_state=$(lsp_runtime_state "${root}")
    case "${runtime_state}" in
        running|starting)
            yen_info "LSP runtime already active for ${root} (${runtime_state})."
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            return 0
            ;;
        stale)
            cleanup_lsp_runtime "${root}" "1"
            ;;
    esac

    project_dir=$(lsp_project_dir "${root}")
    socket_file=$(lsp_socket_file "${root}")
    pid_file=$(lsp_pid_file "${root}")
    state_file=$(lsp_state_file "${root}")
    diagnostics_file=$(lsp_diagnostics_file "${root}")
    daemon_script=$(lsp_daemon_script_file "${root}")
    daemon_log_file=$(lsp_daemon_log_file "${root}")
    protocol_mode=$(lsp_resolved_protocol_mode "${root}")
    impl=$(lsp_resolved_impl "${root}")
    server_label=$(lsp_resolved_label "${root}")
    server_command=$(lsp_resolved_command "${root}")
    language_id=$(lsp_resolved_language_id "${root}")
    extensions_csv=$(lsp_resolved_extensions "${root}")
    resolution_status=$(lsp_resolution_status "${root}")
    resolution_reason=$(lsp_resolution_reason "${root}")
    expected_server=$(lsp_expected_server "${root}")
    mkdir -p "${project_dir}"
    : > "${daemon_log_file}"

    python_source=$(lsp_daemon_python_source)
    atomic_write_text "${daemon_script}" "$(printf "%s\n" "${python_source}")"
    nohup python3 "${daemon_script}" "${socket_file}" "${state_file}" "${diagnostics_file}" "${root}" "${protocol_mode}" "${impl}" "${server_label}" "${server_command}" "${language_id}" "${extensions_csv}" "${IDE_TIMELINE_FILE}" >/dev/null 2>> "${daemon_log_file}" &
    pid=$!
    atomic_write_text "${pid_file}" "$(printf "%s\n" "${pid}")"

    while [[ "${attempts}" -lt "${max_attempts}" ]]; do
        if ! is_pid_running "${pid}"; then
            break
        fi
        health=$(lsp_health_status "${root}")
        daemon_status=$(lsp_state_value "${root}" "status")
        protocol_status=$(lsp_state_value "${root}" "protocol_status")
        if [[ "${daemon_status}" == "failed" ]]; then
            break
        fi
        if [[ "${health}" == "healthy" || "${health}" == "unknown" ]]; then
            if [[ "${protocol_mode}" == "stdio" && "${daemon_status}" != "running" ]]; then
                sleep 0.1
                attempts=$((attempts + 1))
                continue
            fi
            timeline_log "lsp-start" "${root}" "running" "pid=${pid};impl=${impl};server=${server_label}"
            if [[ "${resolution_status}" == "resolved" || "${resolution_status}" == "override" ]]; then
                yen_success "LSP runtime started: ${root}"
            else
                yen_success "Placeholder LSP runtime started: ${root}"
            fi
            echo "Implementation: ${impl}"
            if [[ -n "${server_label}" ]]; then
                echo "Server: ${server_label}"
            fi
            if [[ "${resolution_status}" != "resolved" && "${resolution_status}" != "override" ]]; then
                echo "Server resolution: ${resolution_status}"
                if [[ -n "${expected_server}" ]]; then
                    echo "Expected server: ${expected_server}"
                fi
                if [[ -n "${resolution_reason}" ]]; then
                    echo "Guidance: ${resolution_reason}"
                fi
            fi
            echo "Socket path: ${socket_file}"
            lock_released="1"
            release_state_lock "${lock_dir}"
            trap - ERR
            return 0
        fi
        sleep 0.1
        attempts=$((attempts + 1))
    done

    local last_error=""
    daemon_status=$(lsp_state_value "${root}" "status")
    protocol_status=$(lsp_state_value "${root}" "protocol_status")
    protocol_ready_at=$(lsp_state_value "${root}" "protocol_ready_at")
    if [[ "${daemon_status}" == "stale" && "${protocol_status}" == "crashed" && -n "${protocol_ready_at}" ]]; then
        timeline_log "lsp-start" "${root}" "stale" "pid=${pid};impl=${impl};server=${server_label};crashed_after_ready=1"
        yen_warn "LSP runtime started for ${root}, then crashed after protocol ready."
        lock_released="1"
        release_state_lock "${lock_dir}"
        trap - ERR
        return 0
    fi
    if [[ "${daemon_status}" == "failed" || "${daemon_status}" == "stale" ]]; then
        last_error=$(lsp_state_value "${root}" "last_error")
    fi
    if is_pid_running "${pid}"; then
        kill "${pid}" 2>/dev/null || true
    fi
    cleanup_lsp_runtime "${root}"
    lock_released="1"
    release_state_lock "${lock_dir}"
    trap - ERR
    if [[ -n "${last_error}" ]]; then
        yen_error "LSP runtime failed to start for ${root}: ${last_error}"
        return 1
    fi
    yen_error "LSP runtime failed to start for ${root}."
    return 1
}

cmd_lsp_stop() {
    local target=""
    local root=""
    local previous_state=""

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

    root=$(find_project_root "${target}")
    previous_state=$(lsp_runtime_state "${root}")

    if ! cmd_lsp_stop_internal "${root}"; then
        return 1
    fi

    case "${previous_state}" in
        stopped)
            yen_info "LSP runtime already stopped for ${root}."
            ;;
        stale)
            yen_success "Cleared stale LSP runtime state: ${root}"
            ;;
        *)
            yen_success "LSP runtime stopped: ${root}"
            ;;
    esac
}

cmd_lsp() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        start)
            cmd_lsp_start "$@"
            ;;
        status)
            cmd_lsp_status "$@"
            ;;
        hover)
            cmd_lsp_hover "$@"
            ;;
        definition)
            cmd_lsp_definition "$@"
            ;;
        references|refs)
            cmd_lsp_references "$@"
            ;;
        code-actions|codeactions|actions)
            cmd_lsp_code_actions "$@"
            ;;
        rename)
            cmd_lsp_rename "$@"
            ;;
        diagnostics)
            cmd_lsp_diagnostics "$@"
            ;;
        install)
            cmd_lsp_install "$@"
            ;;
        stop)
            cmd_lsp_stop "$@"
            ;;
        trust)
            local root=""
            local target=""
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
            root=$(find_project_root "${target}")
            if is_lsp_trusted_project "${root}"; then
                yen_info "Project already trusted for LSP execution: ${root}"
                return 0
            fi
            trust_lsp_project "${root}"
            timeline_log "lsp-trust" "${root}" "trusted" "source=manual"
            yen_success "Trusted project for LSP execution: ${root}"
            ;;
        untrust)
            local root=""
            local target=""
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
            root=$(find_project_root "${target}")
            if ! is_lsp_trusted_project "${root}"; then
                if [[ "$(lsp_runtime_state "${root}")" != "stopped" ]]; then
                    if ! cmd_lsp_stop_internal "${root}"; then
                        return 1
                    fi
                fi
                yen_info "Project already untrusted for LSP execution: ${root}"
                return 0
            fi
            if [[ "$(lsp_runtime_state "${root}")" != "stopped" ]]; then
                if ! cmd_lsp_stop_internal "${root}"; then
                    return 1
                fi
            fi
            untrust_lsp_project "${root}"
            timeline_log "lsp-trust" "${root}" "untrusted" "source=manual"
            yen_success "Removed LSP trust: ${root}"
            ;;
        trusted|list)
            ensure_state_dirs
            if [[ ! -s "${IDE_LSP_TRUST_FILE}" ]]; then
                yen_info "No LSP-trusted projects."
                return 0
            fi
            echo ""
            yen_header "Trusted LSP Projects"
            nl -ba "${IDE_LSP_TRUST_FILE}"
            echo ""
            ;;
        *)
            yen_error "Unknown lsp subcommand: ${sub}"
            show_help
            exit 1
            ;;
    esac
}
