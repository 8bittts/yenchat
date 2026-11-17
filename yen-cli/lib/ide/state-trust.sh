# shellcheck shell=bash
# Source-time pure shared helpers for yen ide state paths and trust registries.

project_hash() {
    local root="$1"
    if command -v shasum >/dev/null 2>&1; then
        printf "%s" "${root}" | shasum -a 256 | awk '{print $1}'
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        printf "%s" "${root}" | openssl dgst -sha256 | awk '{print $2}'
        return 0
    fi
    if command -v md5 >/dev/null 2>&1; then
        md5 -q -s "${root}"
        return 0
    fi
    printf "%s\n" "${root}" | tr -cd '[:alnum:]' | cut -c1-32
}

project_hash_seed_for_root() {
    local root="$1"
    if declare -F workspace_hash_seed_for_root >/dev/null 2>&1; then
        workspace_hash_seed_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

project_hash_for_root() {
    local root="$1"
    project_hash "$(project_hash_seed_for_root "${root}")"
}

project_short_hash_for_root() {
    local root="$1"
    project_hash_for_root "${root}" | cut -c1-12
}

project_trust_key_for_root() {
    local root="$1"
    if declare -F workspace_trust_key_for_root >/dev/null 2>&1; then
        workspace_trust_key_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

project_timeline_key_for_root() {
    local root="$1"
    if declare -F workspace_timeline_key_for_root >/dev/null 2>&1; then
        workspace_timeline_key_for_root "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

acquire_state_lock() {
    local lock_dir="$1"
    local label="$2"
    local timeout_seconds="${3:-${YEN_IDE_LOCK_TIMEOUT_SEC:-10}}"
    local waited_tenths=0
    local max_wait_tenths=0

    if [[ ! "${timeout_seconds}" =~ ^[0-9]+$ ]]; then
        timeout_seconds="10"
    fi
    max_wait_tenths=$(( timeout_seconds * 10 ))

    mkdir -p "$(dirname "${lock_dir}")"
    while ! mkdir "${lock_dir}" 2>/dev/null; do
        local owner_pid=""
        if [[ -f "${lock_dir}/pid" ]]; then
            owner_pid=$(tr -d '[:space:]' < "${lock_dir}/pid" | sed -n '1p')
        fi
        if [[ -n "${owner_pid}" ]] && ! is_pid_running "${owner_pid}"; then
            rm -rf "${lock_dir}"
            continue
        fi
        if [[ "${waited_tenths}" -ge "${max_wait_tenths}" ]]; then
            yen_error "${label} is busy for another process. Retry in a moment."
            return 1
        fi
        sleep 0.1
        waited_tenths=$(( waited_tenths + 1 ))
    done
    printf "%s\n" "$$" > "${lock_dir}/pid"
}

release_state_lock() {
    local lock_dir="$1"
    rm -rf "${lock_dir}"
}

project_history_file() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s.log\n" "${IDE_HISTORY_DIR}" "${hash}"
}

project_profile_file() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s.log\n" "${IDE_PROFILE_DIR}" "${hash}"
}

is_trusted_project() {
    local root="$1"
    local trust_key=""
    [[ -f "${IDE_TRUST_FILE}" ]] || return 1
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_TRUST_FILE}" 2>/dev/null
}

trust_registry_lock_dir() {
    local file="$1"
    printf "%s.lock\n" "${file}"
}

trust_registry_add() {
    local file="$1"
    local root="$2"
    local label="$3"
    local lock_dir=""

    ensure_state_dirs
    lock_dir=$(trust_registry_lock_dir "${file}")
    if ! acquire_state_lock "${lock_dir}" "${label}" "5"; then
        return 1
    fi
    if ! grep -Fxq -- "${root}" "${file}" 2>/dev/null; then
        if ! printf "%s\n" "${root}" >> "${file}"; then
            release_state_lock "${lock_dir}"
            return 1
        fi
    fi
    release_state_lock "${lock_dir}"
}

trust_registry_remove() {
    local file="$1"
    local root="$2"
    local label="$3"
    local lock_dir=""
    local tmp=""

    ensure_state_dirs
    if [[ ! -f "${file}" ]]; then
        return 0
    fi
    lock_dir=$(trust_registry_lock_dir "${file}")
    if ! acquire_state_lock "${lock_dir}" "${label}" "5"; then
        return 1
    fi
    if ! tmp=$(mktemp "${TMPDIR:-/tmp}/yen-trust.XXXXXX" 2>/dev/null); then
        release_state_lock "${lock_dir}"
        return 1
    fi
    grep -Fvx -- "${root}" "${file}" > "${tmp}" || true
    if ! mv "${tmp}" "${file}"; then
        rm -f "${tmp}"
        release_state_lock "${lock_dir}"
        return 1
    fi
    release_state_lock "${lock_dir}"
}

trust_project() {
    local root="$1"
    trust_registry_add "${IDE_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE env trust registry"
}

untrust_project() {
    local root="$1"
    trust_registry_remove "${IDE_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE env trust registry"
}

is_workflow_trusted_project() {
    local root="$1"
    local trust_key=""
    [[ -f "${IDE_WORKFLOW_TRUST_FILE}" ]] || return 1
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_WORKFLOW_TRUST_FILE}" 2>/dev/null
}

trust_workflow_project() {
    local root="$1"
    trust_registry_add "${IDE_WORKFLOW_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE workflow trust registry"
}

untrust_workflow_project() {
    local root="$1"
    trust_registry_remove "${IDE_WORKFLOW_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE workflow trust registry"
}

lsp_project_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s\n" "${IDE_LSP_DIR}" "${hash}"
}

lsp_lock_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/locks/%s.lock\n" "${IDE_LSP_DIR}" "${hash}"
}

lsp_socket_id() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s\n" "${hash}" | cut -c1-12
}

lsp_socket_file() {
    local root="$1"
    printf "%s/%s.sock\n" "${IDE_LSP_SOCKET_DIR}" "$(lsp_socket_id "${root}")"
}

lsp_pid_file() {
    local root="$1"
    printf "%s/lsp.pid\n" "$(lsp_project_dir "${root}")"
}

lsp_state_file() {
    local root="$1"
    printf "%s/state.env\n" "$(lsp_project_dir "${root}")"
}

lsp_diagnostics_file() {
    local root="$1"
    printf "%s/diagnostics.json\n" "$(lsp_project_dir "${root}")"
}

lsp_daemon_script_file() {
    local root="$1"
    printf "%s/daemon.py\n" "$(lsp_project_dir "${root}")"
}

lsp_daemon_log_file() {
    local root="$1"
    printf "%s/daemon.log\n" "$(lsp_project_dir "${root}")"
}

is_lsp_trusted_project() {
    local root="$1"
    local trust_key=""
    ensure_state_dirs
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_LSP_TRUST_FILE}" 2>/dev/null
}

trust_lsp_project() {
    local root="$1"
    trust_registry_add "${IDE_LSP_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE LSP trust registry"
}

untrust_lsp_project() {
    local root="$1"
    trust_registry_remove "${IDE_LSP_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE LSP trust registry"
}

debug_project_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s\n" "${IDE_DEBUG_DIR}" "${hash}"
}

debug_socket_dir() {
    printf "%s\n" "${YEN_IDE_DEBUG_SOCKET_DIR:-${TMPDIR:-/tmp}/yen-debug-${UID}}"
}

debug_socket_state_id() {
    project_hash "${IDE_STATE_DIR}" | cut -c1-8
}

debug_socket_id() {
    local root="$1"
    printf "%s-%s\n" "$(debug_socket_state_id)" "$(project_short_hash_for_root "${root}")"
}

debug_socket_file() {
    local root="$1"
    printf "%s/%s.sock\n" "$(debug_socket_dir)" "$(debug_socket_id "${root}")"
}

debug_lock_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/locks/%s.lock\n" "${IDE_DEBUG_DIR}" "${hash}"
}

debug_state_file() {
    local root="$1"
    printf "%s/state.env\n" "$(debug_project_dir "${root}")"
}

debug_summary_report_file() {
    local root="$1"
    local token="$2"
    printf "%s/debug-%s.tsv\n" "$(debug_project_dir "${root}")" "${token}"
}

debug_details_report_file() {
    local root="$1"
    local token="$2"
    printf "%s/debug-%s.log\n" "$(debug_project_dir "${root}")" "${token}"
}

is_debug_trusted_project() {
    local root="$1"
    local trust_key=""
    ensure_state_dirs
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_DEBUG_TRUST_FILE}" 2>/dev/null
}

trust_debug_project() {
    local root="$1"
    trust_registry_add "${IDE_DEBUG_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE debug trust registry"
}

untrust_debug_project() {
    local root="$1"
    trust_registry_remove "${IDE_DEBUG_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE debug trust registry"
}

devcontainer_project_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s\n" "${IDE_DEVCONTAINER_DIR}" "${hash}"
}

devcontainer_state_file() {
    local root="$1"
    printf "%s/state.env\n" "$(devcontainer_project_dir "${root}")"
}

devcontainer_spec_file() {
    local root="$1"
    if [[ -f "${root}/.devcontainer/devcontainer.json" ]]; then
        printf "%s/.devcontainer/devcontainer.json\n" "${root}"
        return 0
    fi
    if [[ -f "${root}/.devcontainer.json" ]]; then
        printf "%s/.devcontainer.json\n" "${root}"
        return 0
    fi
}

is_devcontainer_supported_project() {
    local root="$1"
    [[ -n "$(devcontainer_spec_file "${root}")" ]]
}

is_devcontainer_trusted_project() {
    local root="$1"
    local trust_key=""
    ensure_state_dirs
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_DEVCONTAINER_TRUST_FILE}" 2>/dev/null
}

trust_devcontainer_project() {
    local root="$1"
    trust_registry_add "${IDE_DEVCONTAINER_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE devcontainer trust registry"
}

untrust_devcontainer_project() {
    local root="$1"
    trust_registry_remove "${IDE_DEVCONTAINER_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE devcontainer trust registry"
}

share_project_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/%s\n" "${IDE_SHARE_DIR}" "${hash}"
}

share_lock_dir() {
    local root="$1"
    local hash=""
    hash=$(project_hash_for_root "${root}")
    printf "%s/locks/%s.lock\n" "${IDE_SHARE_DIR}" "${hash}"
}

share_state_file() {
    local root="$1"
    printf "%s/state.env\n" "$(share_project_dir "${root}")"
}

share_pid_file() {
    local root="$1"
    printf "%s/share.pid\n" "$(share_project_dir "${root}")"
}

share_wrapper_script_file() {
    local root="$1"
    printf "%s/host.sh\n" "$(share_project_dir "${root}")"
}

share_expiry_script_file() {
    local root="$1"
    printf "%s/expire.sh\n" "$(share_project_dir "${root}")"
}

share_expiry_pid_file() {
    local root="$1"
    printf "%s/expire.pid\n" "$(share_project_dir "${root}")"
}

share_upterm_command_script_file() {
    local root="$1"
    printf "%s/upterm-command.sh\n" "$(share_project_dir "${root}")"
}

share_upterm_admin_file() {
    local root="$1"
    printf "%s/upterm-admin.sock\n" "$(share_project_dir "${root}")"
}

share_upterm_session_file() {
    local root="$1"
    printf "%s/upterm-session.json\n" "$(share_project_dir "${root}")"
}

share_tmate_socket_file() {
    local root="$1"
    printf "%s/tmate.sock\n" "$(share_project_dir "${root}")"
}

is_share_trusted_project() {
    local root="$1"
    local trust_key=""
    ensure_state_dirs
    trust_key=$(project_trust_key_for_root "${root}")
    grep -Fxq -- "${trust_key}" "${IDE_SHARE_TRUST_FILE}" 2>/dev/null
}

trust_share_project() {
    local root="$1"
    trust_registry_add "${IDE_SHARE_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE share trust registry"
}

untrust_share_project() {
    local root="$1"
    trust_registry_remove "${IDE_SHARE_TRUST_FILE}" "$(project_trust_key_for_root "${root}")" "IDE share trust registry"
}

pr_seen_file() {
    local root="$1"
    printf "%s/pr-seen-%s.log\n" "${IDE_STATE_DIR}" "$(project_hash_for_root "${root}")"
}
