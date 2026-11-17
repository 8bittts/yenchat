# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

doctor_lockfile_inventory() {
    local root="$1"
    local out=""
    [[ -f "${root}/bun.lock" ]] && out=$(append_csv_unique "${out}" "bun.lock")
    [[ -f "${root}/bun.lockb" ]] && out=$(append_csv_unique "${out}" "bun.lockb")
    [[ -f "${root}/pnpm-lock.yaml" ]] && out=$(append_csv_unique "${out}" "pnpm-lock.yaml")
    [[ -f "${root}/yarn.lock" ]] && out=$(append_csv_unique "${out}" "yarn.lock")
    [[ -f "${root}/package-lock.json" ]] && out=$(append_csv_unique "${out}" "package-lock.json")
    printf "%s\n" "${out}"
}

doctor_package_manager_requirement() {
    local root="$1"
    local pkg="${root}/package.json"
    [[ -f "${pkg}" ]] || return 0
    sed -nE 's/.*"packageManager"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${pkg}" | head -n 1
}

doctor_package_manager_name() {
    local requirement="$1"
    printf "%s\n" "${requirement}" | sed -nE 's/^([^@]+)@.*$/\1/p'
}

doctor_package_manager_version() {
    local requirement="$1"
    printf "%s\n" "${requirement}" | sed -nE 's/^[^@]+@(.+)$/\1/p'
}

doctor_collect_go_requirements() {
    local root="$1"
    local out=""
    local file=""
    while IFS= read -r file; do
        [[ -z "${file}" ]] && continue
        local version=""
        version=$(sed -nE 's/^go[[:space:]]+([0-9][0-9.]*)$/\1/p' "${file}" | head -n 1)
        if [[ -n "${version}" ]]; then
            out=$(append_csv_unique "${out}" "${version}")
        fi
    done << EOF
$(find "${root}" -maxdepth 3 -name go.mod -type f 2>/dev/null | sort)
EOF
    printf "%s\n" "${out}"
}

doctor_swift_tools_version() {
    local root="$1"
    local file="${root}/Package.swift"
    [[ -f "${file}" ]] || return 0
    sed -nE 's@^//[[:space:]]*swift-tools-version:[[:space:]]*([0-9][0-9.]*)@\1@p' "${file}" | head -n 1
}

doctor_python_requires_version() {
    local root="$1"
    local pyproject="${root}/pyproject.toml"
    [[ -f "${pyproject}" ]] || return 0
    sed -nE "s/^[[:space:]]*requires-python[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\\1/p" "${pyproject}" | head -n 1
}

doctor_tool_version() {
    local tool="$1"
    case "${tool}" in
        bun)
            bun --version 2>/dev/null | head -n 1
            ;;
        npm|pnpm|yarn|zig)
            "${tool}" --version 2>/dev/null | head -n 1
            ;;
        node)
            node --version 2>/dev/null | head -n 1 | sed 's/^v//'
            ;;
        go)
            go version 2>/dev/null | sed -nE 's/.*go([0-9][0-9.]*).*/\1/p' | head -n 1
            ;;
        python3)
            python3 --version 2>/dev/null | sed -nE 's/Python[[:space:]]+([0-9][0-9.]*)/\1/p' | head -n 1
            ;;
        python)
            python --version 2>/dev/null | sed -nE 's/Python[[:space:]]+([0-9][0-9.]*)/\1/p' | head -n 1
            ;;
        swift)
            swift --version 2>/dev/null | sed -nE 's/.*version[[:space:]]+([0-9][0-9.]*).*/\1/p' | head -n 1
            ;;
        cargo)
            cargo --version 2>/dev/null | sed -nE 's/.*cargo[[:space:]]+([0-9][0-9.]*).*/\1/p' | head -n 1
            ;;
        rustc)
            rustc --version 2>/dev/null | sed -nE 's/.*rustc[[:space:]]+([0-9][0-9.]*).*/\1/p' | head -n 1
            ;;
        devcontainer)
            local cli=""
            cli=$(devcontainer_cli_command)
            [[ -n "${cli}" ]] || return 0
            bash -lc "${cli} --version" 2>/dev/null | head -n 1 | sed -nE 's/.*([0-9][0-9.]*).*/\1/p'
            ;;
        *)
            return 0
            ;;
    esac
}

doctor_extract_python_minimum_version() {
    local requirement="$1"
    printf "%s\n" "${requirement}" | sed -nE 's/.*([0-9]+([.][0-9]+)+).*/\1/p' | head -n 1
}

version_lt() {
    local left="$1"
    local right="$2"
    if [[ -z "${left}" || -z "${right}" ]]; then
        return 1
    fi
    local left_parts=()
    local right_parts=()
    local IFS='.'
    read -r -a left_parts <<< "${left}"
    read -r -a right_parts <<< "${right}"
    local max="${#left_parts[@]}"
    if [[ "${#right_parts[@]}" -gt "${max}" ]]; then
        max="${#right_parts[@]}"
    fi
    local index=0
    while [[ "${index}" -lt "${max}" ]]; do
        local left_part="${left_parts[${index}]:-0}"
        local right_part="${right_parts[${index}]:-0}"
        left_part=$(printf "%s\n" "${left_part}" | sed 's/[^0-9].*$//')
        right_part=$(printf "%s\n" "${right_part}" | sed 's/[^0-9].*$//')
        [[ -z "${left_part}" ]] && left_part="0"
        [[ -z "${right_part}" ]] && right_part="0"
        if (( 10#${left_part} < 10#${right_part} )); then
            return 0
        fi
        if (( 10#${left_part} > 10#${right_part} )); then
            return 1
        fi
        index=$((index + 1))
    done
    return 1
}

doctor_max_version_from_csv() {
    local csv="$1"
    local max=""
    local item=""
    local IFS=','
    read -r -a parts <<< "${csv}"
    for item in "${parts[@]}"; do
        [[ -z "${item}" ]] && continue
        if [[ -z "${max}" ]] || version_lt "${max}" "${item}"; then
            max="${item}"
        fi
    done
    printf "%s\n" "${max}"
}

doctor_expected_package_manager() {
    local snapshot="$1"
    local requirement_name=""
    local lockfiles=""
    requirement_name=$(doctor_snapshot_value "${snapshot}" "package_manager_name")
    if [[ -n "${requirement_name}" ]]; then
        printf "%s\n" "${requirement_name}"
        return 0
    fi
    lockfiles=$(doctor_snapshot_value "${snapshot}" "lockfiles")
    if csv_has_token "${lockfiles}" "bun.lock" || csv_has_token "${lockfiles}" "bun.lockb"; then
        printf "bun\n"
        return 0
    fi
    if csv_has_token "${lockfiles}" "pnpm-lock.yaml"; then
        printf "pnpm\n"
        return 0
    fi
    if csv_has_token "${lockfiles}" "yarn.lock"; then
        printf "yarn\n"
        return 0
    fi
    if csv_has_token "${lockfiles}" "package-lock.json"; then
        printf "npm\n"
        return 0
    fi
}

doctor_debug_available_family_count() {
    local root="$1"
    local rows=""
    rows=$(debug_status_family_rows_for_root "${root}" 2>/dev/null || debug_family_rows_for_root "${root}")
    printf "%s\n" "${rows}" | awk -F'\t' '
        NF >= 3 && $3 == "yes" { count += 1 }
        END { print count + 0 }
    '
}

doctor_debug_guidance() {
    local project_types="$1"
    local lsp_language="$2"
    local workspace_execution_location="${3:-local}"
    local devcontainer_state="${4:-stopped}"
    local devcontainer_execution_available="${5:-no}"
    local devcontainer_guidance="${6:-}"
    local remote_guidance=""

    if [[ "${workspace_execution_location}" == "remote" ]]; then
        remote_guidance="Remote debugger execution now runs through the shared SSH-backed launch plan on the existing trust/timeline/evidence model."
        if [[ -n "${devcontainer_guidance}" ]]; then
            printf "%s %s\n" "${remote_guidance}" "${devcontainer_guidance}"
        else
            printf "%s Keep tracked devcontainer debug behind --devcontainer when that container path is ready.\n" "${remote_guidance}"
        fi
        return 0
    fi

    if [[ "${lsp_language}" == "typescript" ]]; then
        printf "Direct .ts debugger launch is not shipped; use emitted .js entry files or keep VS Code for TypeScript, browser, or attach workflows.\n"
        return 0
    fi
    if csv_has_token "${project_types}" "go"; then
        printf "Go package debug is not shipped; use explicit executable targets or keep Delve/VS Code for package or test debug flows.\n"
        return 0
    fi
    if csv_has_token "${project_types}" "rust"; then
        printf "Rust package debug is not shipped; use explicit executable targets or keep CodeLLDB/VS Code for package or test debug flows.\n"
        return 0
    fi
    if [[ "${devcontainer_execution_available}" == "yes" ]] && [[ -n "${devcontainer_guidance}" ]]; then
        printf "%s\n" "${devcontainer_guidance}"
        return 0
    fi
    if [[ "${devcontainer_state}" == "running" ]]; then
        if [[ -n "${devcontainer_guidance}" ]]; then
            printf "%s\n" "${devcontainer_guidance}"
        else
            printf "Debugger status now surfaces the running devcontainer context. Recheck yen ide debug status --devcontainer --project <root> before debugging inside that container.\n"
        fi
        return 0
    fi
    printf "\n"
}

doctor_append_finding() {
    local findings="$1"
    local severity="$2"
    local code="$3"
    local component="$4"
    local summary="$5"
    local remediation="$6"
    local row=""
    row=$(printf "%s\t%s\t%s\t%s\t%s" \
        "${severity}" \
        "${code}" \
        "${component}" \
        "$(doctor_clean_value "${summary}")" \
        "$(doctor_clean_value "${remediation}")")
    if [[ -n "${findings}" ]]; then
        printf "%s\n%s\n" "${findings}" "${row}"
    else
        printf "%s\n" "${row}"
    fi
}

doctor_collect_findings() {
    local snapshot="$1"
    local findings=""
    local root=""
    local workspace_execution_location=""
    local env_trusted=""
    local env_files_count=""
    local debug_recommended_tool=""
    local debug_recommended_title=""
    local debug_recommended_available=""
    local debug_recommended_hint=""
    local lsp_trusted=""
    local lsp_state=""
    local lsp_health=""
    local lsp_resolution_status=""
    local lsp_language=""
    local lsp_expected_server=""
    local devcontainer_supported=""
    local devcontainer_trusted=""
    local devcontainer_state=""
    local devcontainer_health=""
    local devcontainer_cli=""
    local devcontainer_unsafe=""
    local verify_status=""
    local verify_summary=""
    local verify_failures=""
    local verify_warns=""
    local package_manager_requirement=""
    local package_manager_version=""
    local package_manager_current_version=""
    local expected_package_manager=""
    local lockfiles=""
    local go_requirements=""
    local go_current_version=""
    local go_required_max=""
    local swift_tools_version=""
    local swift_current_version=""
    local python_requirement=""
    local python_minimum_version=""
    local python_current_version=""
    local project_types=""

    root=$(doctor_snapshot_value "${snapshot}" "root")
    workspace_execution_location=$(doctor_snapshot_value "${snapshot}" "workspace_execution_location")
    env_trusted=$(doctor_snapshot_value "${snapshot}" "env_trusted")
    env_files_count=$(doctor_snapshot_value "${snapshot}" "env_files_count")
    debug_recommended_tool=$(doctor_snapshot_value "${snapshot}" "debug_recommended_tool")
    debug_recommended_title=$(doctor_snapshot_value "${snapshot}" "debug_recommended_title")
    debug_recommended_available=$(doctor_snapshot_value "${snapshot}" "debug_recommended_available")
    debug_recommended_hint=$(doctor_snapshot_value "${snapshot}" "debug_recommended_hint")
    lsp_trusted=$(doctor_snapshot_value "${snapshot}" "lsp_trusted")
    lsp_state=$(doctor_snapshot_value "${snapshot}" "lsp_state")
    lsp_health=$(doctor_snapshot_value "${snapshot}" "lsp_health")
    lsp_resolution_status=$(doctor_snapshot_value "${snapshot}" "lsp_resolution_status")
    lsp_language=$(doctor_snapshot_value "${snapshot}" "lsp_language")
    lsp_expected_server=$(doctor_snapshot_value "${snapshot}" "lsp_expected_server")
    devcontainer_supported=$(doctor_snapshot_value "${snapshot}" "devcontainer_supported")
    devcontainer_trusted=$(doctor_snapshot_value "${snapshot}" "devcontainer_trusted")
    devcontainer_state=$(doctor_snapshot_value "${snapshot}" "devcontainer_state")
    devcontainer_health=$(doctor_snapshot_value "${snapshot}" "devcontainer_health")
    devcontainer_cli=$(doctor_snapshot_value "${snapshot}" "devcontainer_cli")
    devcontainer_unsafe=$(doctor_snapshot_value "${snapshot}" "devcontainer_unsafe")
    verify_status=$(doctor_snapshot_value "${snapshot}" "verify_status")
    verify_summary=$(doctor_snapshot_value "${snapshot}" "verify_summary")
    verify_failures=$(doctor_snapshot_value "${snapshot}" "verify_failures")
    verify_warns=$(doctor_snapshot_value "${snapshot}" "verify_warns")
    package_manager_requirement=$(doctor_snapshot_value "${snapshot}" "package_manager_requirement")
    package_manager_version=$(doctor_snapshot_value "${snapshot}" "package_manager_version")
    package_manager_current_version=$(doctor_snapshot_value "${snapshot}" "package_manager_current_version")
    lockfiles=$(doctor_snapshot_value "${snapshot}" "lockfiles")
    expected_package_manager=$(doctor_expected_package_manager "${snapshot}")
    go_requirements=$(doctor_snapshot_value "${snapshot}" "go_requirements")
    go_current_version=$(doctor_snapshot_value "${snapshot}" "go_current_version")
    swift_tools_version=$(doctor_snapshot_value "${snapshot}" "swift_tools_version")
    swift_current_version=$(doctor_snapshot_value "${snapshot}" "swift_current_version")
    python_requirement=$(doctor_snapshot_value "${snapshot}" "python_requirement")
    python_minimum_version=$(doctor_extract_python_minimum_version "${python_requirement}")
    python_current_version=$(doctor_snapshot_value "${snapshot}" "python_current_version")
    project_types=$(doctor_snapshot_value "${snapshot}" "project_types")

    if [[ "${env_files_count}" != "0" && "${env_trusted}" != "yes" ]]; then
        local env_remediation=""
        env_remediation="Run: yen ide env trust \"${root}\""
        if [[ "${workspace_execution_location}" == "remote" ]]; then
            env_remediation="Remote trust controls remain read-only until remote lifecycle parity ships."
        fi
        findings=$(doctor_append_finding "${findings}" "blocker" "env-untrusted" "env" \
            "Project has ${env_files_count} env file(s) but env trust is not granted." \
            "${env_remediation}")
    fi

    if [[ "${workspace_execution_location}" != "remote" && -n "${debug_recommended_tool}" && "${debug_recommended_available}" != "yes" ]]; then
        local debug_label=""
        local debug_remediation=""
        debug_label="${debug_recommended_title:-${debug_recommended_tool}}"
        debug_remediation="${debug_recommended_hint}"
        if [[ -n "${debug_remediation}" ]]; then
            debug_remediation="${debug_remediation%$'\n'} Run: yen ide debug status \"${root}\" to inspect the shipped local debugger baseline."
        else
            debug_remediation="Run: yen ide debug status \"${root}\" to inspect the shipped local debugger baseline."
        fi
        findings=$(doctor_append_finding "${findings}" "warning" "debug-tool-missing" "debug" \
            "Recommended local debugger tool ${debug_label} is unavailable for this workspace." \
            "${debug_remediation}")
    fi

    if [[ -n "${lsp_expected_server}" && "${lsp_trusted}" != "yes" ]]; then
        local lsp_remediation=""
        lsp_remediation="Run: yen ide lsp trust \"${root}\""
        if [[ "${workspace_execution_location}" == "remote" ]]; then
            lsp_remediation="Remote trust controls remain read-only until remote lifecycle parity ships."
        fi
        findings=$(doctor_append_finding "${findings}" "blocker" "lsp-untrusted" "lsp" \
            "LSP execution is blocked by trust for this repository." \
            "${lsp_remediation}")
    fi
    if [[ "${workspace_execution_location}" != "remote" && "${lsp_resolution_status}" == "unavailable-server" && -n "${lsp_expected_server}" ]]; then
        local install_hint=""
        install_hint=$(lsp_install_command_text "${lsp_language}" 2>/dev/null || true)
        [[ -z "${install_hint}" ]] && install_hint="Install the expected server: ${lsp_expected_server}"
        findings=$(doctor_append_finding "${findings}" "blocker" "lsp-server-missing" "lsp" \
            "Expected LSP server is unavailable for this ${lsp_language:-current} workspace." \
            "${install_hint}")
    fi
    if [[ "${lsp_state}" == "stale" || "${lsp_health}" == "stale" || "${lsp_health}" == "unresponsive" ]]; then
        findings=$(doctor_append_finding "${findings}" "blocker" "lsp-runtime-stale" "lsp" \
            "Tracked LSP runtime is stale or unresponsive." \
            "Run: yen ide lsp stop \"${root}\" && yen ide lsp start \"${root}\"")
    fi
    if [[ "${lsp_resolution_status}" == "unsupported-language" ]]; then
        findings=$(doctor_append_finding "${findings}" "warning" "lsp-unsupported-language" "lsp" \
            "This workspace does not have a supported reference LSP mapping yet." \
            "Use the shipped AST fallback where available, or configure a local server override before relying on LSP actions.")
    fi

    if [[ "${workspace_execution_location}" != "remote" && "${devcontainer_supported}" == "yes" && -z "${devcontainer_cli}" ]]; then
        findings=$(doctor_append_finding "${findings}" "blocker" "devcontainer-cli-missing" "devcontainer" \
            "A devcontainer spec exists, but the reference devcontainer CLI is not available." \
            "Install the reference devcontainer CLI or set YEN_IDE_DEVCONTAINER_CMD.")
    fi
    if [[ "${devcontainer_supported}" == "yes" && "${devcontainer_trusted}" != "yes" ]]; then
        local devcontainer_remediation=""
        devcontainer_remediation="Run: yen ide devcontainer trust \"${root}\""
        if [[ "${workspace_execution_location}" == "remote" ]]; then
            devcontainer_remediation="Remote trust controls remain read-only until remote lifecycle parity ships."
        fi
        findings=$(doctor_append_finding "${findings}" "blocker" "devcontainer-untrusted" "devcontainer" \
            "Devcontainer execution is blocked by trust for this repository." \
            "${devcontainer_remediation}")
    fi
    if [[ "${devcontainer_supported}" == "yes" && "${devcontainer_unsafe}" != "none" && -n "${devcontainer_unsafe}" ]]; then
        findings=$(doctor_append_finding "${findings}" "blocker" "devcontainer-unsafe-spec" "devcontainer" \
            "Devcontainer spec includes unsafe flags or host mounts that the wrapper will reject by default." \
            "Remove the unsafe spec flags, or pass --allow-unsafe only when you explicitly intend to bypass the safety gate.")
    fi
    if [[ "${devcontainer_state}" == "running" && "${devcontainer_health}" != "healthy" ]]; then
        findings=$(doctor_append_finding "${findings}" "blocker" "devcontainer-unhealthy" "devcontainer" \
            "Tracked devcontainer runtime is running but unhealthy." \
            "Run: yen ide devcontainer down \"${root}\" && yen ide devcontainer up \"${root}\"")
    fi

    case "${verify_status}" in
        never-run)
            findings=$(doctor_append_finding "${findings}" "warning" "verify-missing" "verify" \
                "No verification run has been recorded for this workspace yet." \
                "Run: yen ide verify --quick --no-security")
            ;;
        report-missing)
            findings=$(doctor_append_finding "${findings}" "warning" "verify-report-missing" "verify" \
                "Timeline metadata points at a verify report that no longer exists." \
                "Run: yen ide verify --quick --no-security to regenerate the local reports.")
            ;;
        failing)
            findings=$(doctor_append_finding "${findings}" "blocker" "verify-failing" "verify" \
                "Latest verify run reported ${verify_failures} failure(s)." \
                "Inspect the report at ${verify_summary} and rerun: yen ide verify --quick --no-security")
            ;;
        warnings)
            findings=$(doctor_append_finding "${findings}" "warning" "verify-warnings" "verify" \
                "Latest verify run completed with ${verify_warns} warning(s)." \
                "Inspect the report at ${verify_summary} and resolve the warning conditions before relying on the workspace.")
            ;;
    esac

    if [[ "${workspace_execution_location}" != "remote" && -n "${package_manager_requirement}" && -z "${package_manager_current_version}" ]]; then
        findings=$(doctor_append_finding "${findings}" "blocker" "package-manager-missing" "toolchain" \
            "Declared package manager ${package_manager_requirement} is not installed." \
            "Install ${package_manager_requirement} so repo-native scripts run against the declared toolchain.")
    fi
    if [[ "${workspace_execution_location}" != "remote" && -n "${package_manager_current_version}" && -n "${package_manager_version}" ]] && version_lt "${package_manager_current_version}" "${package_manager_version}"; then
        findings=$(doctor_append_finding "${findings}" "blocker" "package-manager-outdated" "toolchain" \
            "Current ${expected_package_manager:-package-manager} version ${package_manager_current_version} is older than the declared ${package_manager_version} baseline." \
            "Upgrade ${expected_package_manager:-the package manager} to at least ${package_manager_version}.")
    fi
    if [[ "${workspace_execution_location}" != "remote" && -n "${expected_package_manager}" ]]; then
        if ! command -v "${expected_package_manager}" >/dev/null 2>&1; then
            findings=$(doctor_append_finding "${findings}" "blocker" "package-manager-runtime-missing" "toolchain" \
                "Workspace lockfiles indicate ${expected_package_manager}, but that runtime is missing." \
                "Install ${expected_package_manager} before running repo-native dependency, build, or verify commands.")
        fi
    fi
    if [[ "$(doctor_count_csv_items "${lockfiles}")" -gt 1 ]]; then
        findings=$(doctor_append_finding "${findings}" "warning" "multiple-lockfiles" "toolchain" \
            "Multiple package-manager lockfiles are present (${lockfiles})." \
            "Remove stale lockfiles so detect, verify, and local tooling resolve one package-manager story.")
    fi

    if [[ "${workspace_execution_location}" != "remote" && -n "${go_requirements}" ]]; then
        go_required_max=$(doctor_max_version_from_csv "${go_requirements}")
        if [[ -z "${go_current_version}" ]]; then
            findings=$(doctor_append_finding "${findings}" "blocker" "go-missing" "toolchain" \
                "Go modules are present, but the Go toolchain is missing." \
                "Install Go ${go_required_max} or newer before running repo Go workflows.")
        elif version_lt "${go_current_version}" "${go_required_max}"; then
            findings=$(doctor_append_finding "${findings}" "blocker" "go-outdated" "toolchain" \
                "Current Go version ${go_current_version} is older than the repo requirement ${go_required_max}." \
                "Upgrade Go to ${go_required_max} or newer.")
        fi
    fi

    if [[ "${workspace_execution_location}" != "remote" && -n "${swift_tools_version}" ]]; then
        if [[ -z "${swift_current_version}" ]]; then
            findings=$(doctor_append_finding "${findings}" "blocker" "swift-missing" "toolchain" \
                "Package.swift declares Swift tools version ${swift_tools_version}, but Swift is not installed." \
                "Install Xcode or the Swift toolchain, then rerun the doctor.")
        elif version_lt "${swift_current_version}" "${swift_tools_version}"; then
            findings=$(doctor_append_finding "${findings}" "blocker" "swift-outdated" "toolchain" \
                "Current Swift version ${swift_current_version} is older than Package.swift requires (${swift_tools_version})." \
                "Upgrade the Swift/Xcode toolchain to at least ${swift_tools_version}.")
        fi
    fi

    if [[ "${workspace_execution_location}" != "remote" && -n "${python_minimum_version}" ]]; then
        if [[ -z "${python_current_version}" ]]; then
            findings=$(doctor_append_finding "${findings}" "blocker" "python-missing" "toolchain" \
                "Python requirement ${python_requirement} is declared, but Python is not installed." \
                "Install Python ${python_minimum_version} or newer before running repo Python workflows.")
        elif version_lt "${python_current_version}" "${python_minimum_version}"; then
            findings=$(doctor_append_finding "${findings}" "blocker" "python-outdated" "toolchain" \
                "Current Python version ${python_current_version} is older than the declared minimum ${python_minimum_version}." \
                "Upgrade Python to ${python_minimum_version} or newer.")
        fi
    fi

    if [[ "${workspace_execution_location}" != "remote" ]] && csv_has_token "${project_types}" "rust"; then
        if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
            findings=$(doctor_append_finding "${findings}" "blocker" "rust-missing" "toolchain" \
                "Rust project files are present, but cargo/rustc are not both available." \
                "Install the Rust toolchain with rustup before running repo Rust workflows.")
        fi
    fi
    if [[ "${workspace_execution_location}" != "remote" ]] && csv_has_token "${project_types}" "zig"; then
        if ! command -v zig >/dev/null 2>&1; then
            findings=$(doctor_append_finding "${findings}" "blocker" "zig-missing" "toolchain" \
                "Zig project files are present, but zig is not installed." \
                "Install Zig before running repo Zig workflows.")
        fi
    fi

    printf "%s" "${findings}"
}

doctor_count_findings() {
    local findings="$1"
    local severity="$2"
    if [[ -z "${findings}" ]]; then
        printf "0\n"
        return 0
    fi
    printf "%s\n" "${findings}" | awk -F'\t' -v severity="${severity}" '$1 == severity { count += 1 } END { print count + 0 }'
}

doctor_overall_status() {
    local blockers="$1"
    local warnings="$2"
    if [[ "${blockers}" -gt 0 ]]; then
        printf "blocking\n"
    elif [[ "${warnings}" -gt 0 ]]; then
        printf "warning\n"
    else
        printf "ok\n"
    fi
}

doctor_collect_snapshot() {
    local root="$1"
    local workspace_execution_location="local"
    local workspace_transport="local"
    local workspace_identity=""
    local workspace_requested_path=""
    local workspace_authority=""
    local workspace_port=""
    local workspace_label=""
    local project_metadata_source="local-filesystem"
    local state_source="local-ide-state"
    local timeline_source="local-ide-state"
    local workspace_note=""
    local project_types=""
    local runtime_context=""
    local tooling_context=""
    local env_trusted="no"
    local env_files=""
    local env_files_count="0"
    local env_files_pipe=""
    local debug_trusted="no"
    local debug_state="stopped"
    local debug_recommended_tool=""
    local debug_recommended_title=""
    local debug_recommended_available=""
    local debug_recommended_hint=""
    local debug_family_available_count="0"
    local debug_guidance=""
    local debug_devcontainer_health="inactive"
    local debug_devcontainer_execution_available="no"
    local debug_devcontainer_recommended_available="no"
    local debug_devcontainer_guidance=""
    local lsp_trusted="no"
    local lsp_state=""
    local lsp_health=""
    local lsp_resolution_status=""
    local lsp_resolution_reason=""
    local lsp_expected_server=""
    local lsp_protocol_status=""
    local lsp_diagnostics_status=""
    local lsp_language=""
    local devcontainer_supported="no"
    local devcontainer_trusted="no"
    local devcontainer_state="stopped"
    local devcontainer_health="inactive"
    local devcontainer_cli=""
    local devcontainer_cli_version=""
    local devcontainer_spec=""
    local devcontainer_unsafe="none"
    local devcontainer_forward_ports=""
    local verify_status="never-run"
    local verify_last_run_at=""
    local verify_summary=""
    local verify_details=""
    local verify_semantic=""
    local verify_failures="0"
    local verify_warns="0"
    local verify_executed="0"
    local verify_readiness_status=""
    local verify_readiness_reason=""
    local verify_merge_ready="no"
    local verify_security_status="unavailable"
    local verify_security_reason=""
    local verify_security_step_count="0"
    local verify_security_warning_steps="0"
    local verify_security_failing_steps="0"
    local verify_security_passing_steps="0"
    local package_manager_requirement=""
    local package_manager_name=""
    local package_manager_version=""
    local package_manager_current_version=""
    local lockfiles=""
    local go_requirements=""
    local go_current_version=""
    local swift_tools_version=""
    local swift_current_version=""
    local python_requirement=""
    local python_current_version=""
    local node_current_version=""
    local verify_snapshot=""
    local verify_security_snapshot=""
    local debug_devcontainer_context=""

    if [[ -n "${IDE_WORKSPACE_SUMMARY_ROOT}" ]] && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]] && [[ -n "${IDE_WORKSPACE_IDENTITY}" ]]; then
        workspace_execution_location="${IDE_WORKSPACE_EXECUTION_LOCATION:-local}"
        workspace_transport="${IDE_WORKSPACE_TRANSPORT:-local}"
        workspace_identity="${IDE_WORKSPACE_IDENTITY}"
        workspace_requested_path="${IDE_WORKSPACE_REQUESTED_PATH}"
        workspace_authority="${IDE_WORKSPACE_AUTHORITY}"
        workspace_port="${IDE_WORKSPACE_PORT}"
        workspace_label="${IDE_WORKSPACE_LABEL}"
        project_metadata_source=$(workspace_summary_project_metadata_source)
        state_source=$(workspace_summary_state_source)
        timeline_source=$(workspace_summary_timeline_source)
        workspace_note=$(workspace_summary_note)
    fi

    if [[ "${workspace_execution_location}" == "remote" ]]; then
        project_types="${IDE_WORKSPACE_SUMMARY_TYPES}"
        runtime_context="${IDE_WORKSPACE_SUMMARY_RUNTIME}"
        tooling_context="${IDE_WORKSPACE_SUMMARY_TOOLING}"
        env_files="${IDE_WORKSPACE_SUMMARY_ENV_FILES}"
        env_files_count="${IDE_WORKSPACE_SUMMARY_ENV_COUNT}"
    else
        project_types=$(detect_project_types "${root}")
        runtime_context=$(detect_runtime_context "${root}")
        tooling_context=$(detect_tooling_context "${root}")
        env_files=$(collect_env_files "${root}" || true)
        env_files_count=$(doctor_count_lines "${env_files}")
        if [[ -n "${env_files}" ]]; then
            env_files_pipe=$(printf "%s\n" "${env_files}" | doctor_join_lines_with_pipe)
        fi
    fi

    if is_trusted_project "${root}"; then
        env_trusted="yes"
    fi
    if [[ -n "${env_files}" && -z "${env_files_pipe}" ]]; then
        env_files_pipe=$(printf "%s\n" "${env_files}" | doctor_join_lines_with_pipe)
    fi

    if is_debug_trusted_project "${root}"; then
        debug_trusted="yes"
    fi
    debug_state=$(debug_runtime_state "${root}")
    if [[ "${workspace_execution_location}" == "remote" ]]; then
        local debug_rows=""
        local recommended_row=""
        debug_recommended_tool=$(debug_recommended_tool_for_root "${root}")
        debug_family_available_count=$(doctor_debug_available_family_count "${root}")
        if [[ -n "${debug_recommended_tool}" ]]; then
            debug_recommended_title=$(debug_tool_title "${debug_recommended_tool}")
            debug_rows=$(debug_status_family_rows_for_root "${root}" || true)
            recommended_row=$(printf "%s\n" "${debug_rows}" | awk -F'\t' -v tool="${debug_recommended_tool}" '$1 == tool { print $0; exit }')
            if [[ -n "${recommended_row}" ]]; then
                debug_recommended_available=$(printf "%s\n" "${recommended_row}" | awk -F'\t' '{print $3}')
            fi
            if [[ "${debug_recommended_available}" != "yes" ]]; then
                debug_recommended_available="no"
                debug_recommended_hint=$(debug_tool_missing_hint "${debug_recommended_tool}")
            fi
        fi
        debug_guidance="Remote debugger execution is available through the shared SSH-backed launch plan and managed-session controls on top of the existing trust/timeline/evidence model."
    else
        debug_recommended_tool=$(debug_recommended_tool_for_root "${root}")
        debug_family_available_count=$(doctor_debug_available_family_count "${root}")
        if [[ -n "${debug_recommended_tool}" ]]; then
            debug_recommended_title=$(debug_tool_title "${debug_recommended_tool}")
            if debug_tool_available "${debug_recommended_tool}"; then
                debug_recommended_available="yes"
            else
                debug_recommended_available="no"
                debug_recommended_hint=$(debug_tool_missing_hint "${debug_recommended_tool}")
            fi
        fi
    fi

    if is_lsp_trusted_project "${root}"; then
        lsp_trusted="yes"
    fi
    lsp_state=$(lsp_runtime_state "${root}")
    if [[ "${workspace_execution_location}" == "remote" ]]; then
        case "${lsp_state}" in
            running|starting)
                lsp_health="remote-unverified"
                ;;
            stale)
                lsp_health="stale"
                ;;
            *)
                lsp_health="inactive"
                ;;
        esac
        lsp_resolution_status="remote-summary"
        lsp_resolution_reason=$(doctor_clean_value "Remote read-only summary does not resolve remote LSP servers yet.")
        lsp_expected_server=""
        lsp_protocol_status=$(lsp_state_value "${root}" "protocol_status")
        lsp_diagnostics_status=$(lsp_diagnostics_status "${root}")
        lsp_language=""
    else
        lsp_health=$(lsp_health_status "${root}")
        lsp_resolution_status=$(lsp_resolution_status "${root}")
        lsp_resolution_reason=$(doctor_clean_value "$(lsp_resolution_reason "${root}")")
        lsp_expected_server=$(lsp_expected_server "${root}")
        lsp_protocol_status=$(lsp_protocol_status "${root}")
        lsp_diagnostics_status=$(lsp_diagnostics_status "${root}")
        lsp_language=$(lsp_detected_language "${root}")
    fi
    if [[ "${workspace_execution_location}" == "remote" ]]; then
        devcontainer_supported="${IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED:-no}"
        devcontainer_spec=""
        if [[ "${devcontainer_supported}" == "yes" ]]; then
            if [[ -f "${root}/.devcontainer.json" ]]; then
                devcontainer_spec="${root}/.devcontainer.json"
            else
                devcontainer_spec="${root}/.devcontainer/devcontainer.json"
            fi
        fi
    else
        devcontainer_spec=$(devcontainer_spec_file "${root}")
        if [[ -n "${devcontainer_spec}" ]]; then
            devcontainer_supported="yes"
        fi
    fi
    if is_devcontainer_trusted_project "${root}"; then
        devcontainer_trusted="yes"
    fi
    devcontainer_state=$(devcontainer_state_value "${root}" "status")
    [[ -z "${devcontainer_state}" ]] && devcontainer_state="stopped"
    if [[ "${workspace_execution_location}" == "remote" ]]; then
        devcontainer_cli=""
        devcontainer_cli_version=""
        if [[ "${devcontainer_state}" == "running" ]]; then
            devcontainer_health=$(devcontainer_state_value "${root}" "health")
            [[ -z "${devcontainer_health}" ]] && devcontainer_health="remote-unverified"
        else
            devcontainer_health="inactive"
        fi
    else
        devcontainer_cli=$(devcontainer_cli_command)
        devcontainer_cli_version=$(doctor_tool_version "devcontainer")
        devcontainer_health=$(devcontainer_health_status "${root}" "${devcontainer_cli}")
    fi
    debug_devcontainer_health="${devcontainer_health}"
    if [[ "${devcontainer_state}" == "running" ]]; then
        local tracked_debug_devcontainer_health=""
        tracked_debug_devcontainer_health=$(devcontainer_state_value "${root}" "health")
        if [[ -n "${tracked_debug_devcontainer_health}" ]]; then
            debug_devcontainer_health="${tracked_debug_devcontainer_health}"
        fi
    fi
    if [[ "${workspace_execution_location}" != "remote" ]]; then
        if [[ "${devcontainer_supported}" == "yes" || "${devcontainer_state}" == "running" ]]; then
            debug_devcontainer_context=$(debug_devcontainer_context_json_for_root "${root}" 2>/dev/null || printf "{}\n")
        fi
    elif [[ "${devcontainer_state}" == "running" ]]; then
        debug_devcontainer_context=$(debug_devcontainer_context_json_for_root "${root}" 2>/dev/null || printf "{}\n")
    fi
    if [[ -n "${debug_devcontainer_context}" ]] && [[ "${debug_devcontainer_context}" != "{}" ]]; then
        eval "$(debug_devcontainer_context_shell_vars "${debug_devcontainer_context}")"
        debug_devcontainer_execution_available="${debug_devcontainer_execution_available:-no}"
        debug_devcontainer_recommended_available="${debug_devcontainer_recommended_available:-no}"
        debug_devcontainer_guidance="${debug_devcontainer_guidance:-}"
    fi
    if [[ -n "${devcontainer_spec}" && "${workspace_execution_location}" != "remote" ]]; then
        local summary=""
        summary=$(devcontainer_spec_summary "${devcontainer_spec}")
        devcontainer_unsafe=$(devcontainer_summary_value "${summary}" "unsafe")
        [[ -z "${devcontainer_unsafe}" ]] && devcontainer_unsafe="none"
        devcontainer_forward_ports=$(devcontainer_summary_value "${summary}" "forwardPorts")
        local state_forward_ports=""
        state_forward_ports=$(devcontainer_state_value "${root}" "forward_ports")
        if [[ -n "${state_forward_ports}" ]]; then
            devcontainer_forward_ports="${state_forward_ports}"
        fi
    fi
    if [[ "${workspace_execution_location}" != "remote" ]] && \
       [[ "${debug_recommended_available}" != "yes" ]] && \
       [[ "${debug_devcontainer_execution_available}" == "yes" ]] && \
       [[ "${debug_devcontainer_recommended_available}" == "yes" ]]; then
        debug_recommended_available="yes"
        debug_recommended_hint="${debug_devcontainer_guidance}"
    fi
    debug_guidance=$(doctor_debug_guidance \
        "${project_types}" \
        "${lsp_language}" \
        "${workspace_execution_location}" \
        "${devcontainer_state}" \
        "${debug_devcontainer_execution_available}" \
        "${debug_devcontainer_guidance}")

    verify_snapshot=$(verify_snapshot_for_root "${root}")
    verify_status=$(doctor_snapshot_value "${verify_snapshot}" "verify_status")
    verify_last_run_at=$(doctor_snapshot_value "${verify_snapshot}" "verify_last_run_at")
    verify_summary=$(doctor_snapshot_value "${verify_snapshot}" "verify_summary")
    verify_details=$(doctor_snapshot_value "${verify_snapshot}" "verify_details")
    verify_semantic=$(doctor_snapshot_value "${verify_snapshot}" "verify_semantic")
    verify_failures=$(doctor_snapshot_value "${verify_snapshot}" "verify_failures")
    verify_warns=$(doctor_snapshot_value "${verify_snapshot}" "verify_warns")
    verify_executed=$(doctor_snapshot_value "${verify_snapshot}" "verify_executed")
    verify_security_snapshot=$(verify_security_snapshot_for_root "${root}")
    verify_readiness_status=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_readiness_status")
    verify_readiness_reason=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_readiness_reason")
    verify_merge_ready=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_merge_ready")
    verify_security_status=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_status")
    verify_security_reason=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_reason")
    verify_security_step_count=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_step_count")
    verify_security_warning_steps=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_warning_steps")
    verify_security_failing_steps=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_failing_steps")
    verify_security_passing_steps=$(doctor_snapshot_value "${verify_security_snapshot}" "verify_security_passing_steps")
    [[ -z "${verify_readiness_status}" ]] && verify_readiness_status="unavailable"
    [[ -z "${verify_security_status}" ]] && verify_security_status="unavailable"
    [[ -z "${verify_security_step_count}" ]] && verify_security_step_count="0"
    [[ -z "${verify_security_warning_steps}" ]] && verify_security_warning_steps="0"
    [[ -z "${verify_security_failing_steps}" ]] && verify_security_failing_steps="0"
    [[ -z "${verify_security_passing_steps}" ]] && verify_security_passing_steps="0"

    if [[ "${workspace_execution_location}" == "remote" ]]; then
        package_manager_requirement="${IDE_WORKSPACE_SUMMARY_PACKAGE_MANAGER_REQUIREMENT}"
    else
        package_manager_requirement=$(doctor_package_manager_requirement "${root}")
    fi
    package_manager_name=$(doctor_package_manager_name "${package_manager_requirement}")
    package_manager_version=$(doctor_package_manager_version "${package_manager_requirement}")
    if [[ "${workspace_execution_location}" != "remote" ]] && [[ -n "${package_manager_name}" ]] && command -v "${package_manager_name}" >/dev/null 2>&1; then
        package_manager_current_version=$(doctor_tool_version "${package_manager_name}")
    fi
    if [[ "${workspace_execution_location}" == "remote" ]]; then
        lockfiles="${IDE_WORKSPACE_SUMMARY_LOCKFILES}"
    else
        lockfiles=$(doctor_lockfile_inventory "${root}")
    fi

    if [[ "${workspace_execution_location}" == "remote" ]]; then
        go_requirements="${IDE_WORKSPACE_SUMMARY_GO_REQUIREMENTS}"
        swift_tools_version="${IDE_WORKSPACE_SUMMARY_SWIFT_TOOLS_VERSION}"
        python_requirement="${IDE_WORKSPACE_SUMMARY_PYTHON_REQUIREMENT}"
        go_current_version=""
        swift_current_version=""
        python_current_version=""
        node_current_version=""
    else
        go_requirements=$(doctor_collect_go_requirements "${root}")
        go_current_version=$(doctor_tool_version "go")
        swift_tools_version=$(doctor_swift_tools_version "${root}")
        swift_current_version=$(doctor_tool_version "swift")
        python_requirement=$(doctor_python_requires_version "${root}")
        python_current_version=$(doctor_tool_version "python3")
        [[ -z "${python_current_version}" ]] && python_current_version=$(doctor_tool_version "python")
        node_current_version=$(doctor_tool_version "node")
    fi

    cat << EOF
root=${root}
workspace_execution_location=${workspace_execution_location}
workspace_transport=${workspace_transport}
workspace_identity=${workspace_identity}
workspace_requested_path=${workspace_requested_path}
workspace_authority=${workspace_authority}
workspace_port=${workspace_port}
workspace_label=${workspace_label}
project_metadata_source=${project_metadata_source}
state_source=${state_source}
timeline_source=${timeline_source}
workspace_note=${workspace_note}
project_types=${project_types}
runtime_context=${runtime_context}
tooling_context=${tooling_context}
env_trusted=${env_trusted}
env_files_count=${env_files_count}
env_files=${env_files_pipe}
debug_trusted=${debug_trusted}
debug_state=${debug_state}
debug_recommended_tool=${debug_recommended_tool}
debug_recommended_title=${debug_recommended_title}
debug_recommended_available=${debug_recommended_available}
debug_recommended_hint=${debug_recommended_hint}
debug_family_available_count=${debug_family_available_count}
debug_guidance=${debug_guidance}
debug_devcontainer_health=${debug_devcontainer_health}
debug_devcontainer_execution_available=${debug_devcontainer_execution_available}
debug_devcontainer_recommended_available=${debug_devcontainer_recommended_available}
debug_devcontainer_guidance=${debug_devcontainer_guidance}
lsp_trusted=${lsp_trusted}
lsp_state=${lsp_state}
lsp_health=${lsp_health}
lsp_resolution_status=${lsp_resolution_status}
lsp_resolution_reason=${lsp_resolution_reason}
lsp_expected_server=${lsp_expected_server}
lsp_protocol_status=${lsp_protocol_status}
lsp_diagnostics_status=${lsp_diagnostics_status}
lsp_language=${lsp_language}
devcontainer_supported=${devcontainer_supported}
devcontainer_trusted=${devcontainer_trusted}
devcontainer_state=${devcontainer_state}
devcontainer_health=${devcontainer_health}
devcontainer_cli=${devcontainer_cli}
devcontainer_cli_version=${devcontainer_cli_version}
devcontainer_spec=${devcontainer_spec}
devcontainer_unsafe=${devcontainer_unsafe}
devcontainer_forward_ports=${devcontainer_forward_ports}
verify_status=${verify_status}
verify_last_run_at=${verify_last_run_at}
verify_summary=${verify_summary}
verify_details=${verify_details}
verify_semantic=${verify_semantic}
verify_failures=${verify_failures}
verify_warns=${verify_warns}
verify_executed=${verify_executed}
verify_readiness_status=${verify_readiness_status}
verify_readiness_reason=${verify_readiness_reason}
verify_merge_ready=${verify_merge_ready}
verify_security_status=${verify_security_status}
verify_security_reason=${verify_security_reason}
verify_security_step_count=${verify_security_step_count}
verify_security_warning_steps=${verify_security_warning_steps}
verify_security_failing_steps=${verify_security_failing_steps}
verify_security_passing_steps=${verify_security_passing_steps}
package_manager_requirement=${package_manager_requirement}
package_manager_name=${package_manager_name}
package_manager_version=${package_manager_version}
package_manager_current_version=${package_manager_current_version}
lockfiles=${lockfiles}
go_requirements=${go_requirements}
go_current_version=${go_current_version}
swift_tools_version=${swift_tools_version}
swift_current_version=${swift_current_version}
python_requirement=${python_requirement}
python_current_version=${python_current_version}
node_current_version=${node_current_version}
EOF
}

doctor_component_summary() {
    local snapshot="$1"
    local component="$2"
    case "${component}" in
        env)
            local execution_location=""
            local env_trusted=""
            local env_files_count=""
            execution_location=$(doctor_snapshot_value "${snapshot}" "workspace_execution_location")
            env_trusted=$(doctor_snapshot_value "${snapshot}" "env_trusted")
            env_files_count=$(doctor_snapshot_value "${snapshot}" "env_files_count")
            if [[ "${env_files_count}" == "0" ]]; then
                printf "no .env files detected\n"
            elif [[ "${env_trusted}" == "yes" ]]; then
                printf "trusted (%s env file(s))\n" "${env_files_count}"
            elif [[ "${execution_location}" == "remote" ]]; then
                printf "untrusted (%s env file(s)); remote trust controls remain read-only\n" "${env_files_count}"
            else
                printf "untrusted (%s env file(s)); run: yen ide env trust \"%s\"\n" "${env_files_count}" "$(doctor_snapshot_value "${snapshot}" "root")"
            fi
            ;;
        debug)
            local execution_location=""
            local trusted=""
            local state=""
            local recommended_tool=""
            local recommended_title=""
            local recommended_available=""
            local available_families=""
            local guidance=""
            local trust_label=""
            local availability_label=""
            execution_location=$(doctor_snapshot_value "${snapshot}" "workspace_execution_location")
            trusted=$(doctor_snapshot_value "${snapshot}" "debug_trusted")
            state=$(doctor_snapshot_value "${snapshot}" "debug_state")
            recommended_tool=$(doctor_snapshot_value "${snapshot}" "debug_recommended_tool")
            recommended_title=$(doctor_snapshot_value "${snapshot}" "debug_recommended_title")
            recommended_available=$(doctor_snapshot_value "${snapshot}" "debug_recommended_available")
            available_families=$(doctor_snapshot_value "${snapshot}" "debug_family_available_count")
            guidance=$(doctor_snapshot_value "${snapshot}" "debug_guidance")
            trust_label="untrusted"
            if [[ "${trusted}" == "yes" ]]; then
                trust_label="trusted"
            fi
            if [[ "${execution_location}" == "remote" ]]; then
                if [[ -n "${guidance}" ]]; then
                    printf "%s / %s / remote execution via ssh; %s\n" "${trust_label}" "${state}" "${guidance}"
                else
                    printf "%s / %s / remote execution via ssh\n" "${trust_label}" "${state}"
                fi
                return 0
            fi
            if [[ -n "${recommended_tool}" ]]; then
                availability_label="missing"
                if [[ "${recommended_available}" == "yes" ]]; then
                    availability_label="available"
                fi
                if [[ -n "${guidance}" ]]; then
                    printf "%s / %s / %s %s; %s\n" "${trust_label}" "${state}" "${recommended_title:-${recommended_tool}}" "${availability_label}" "${guidance}"
                else
                    printf "%s / %s / %s %s\n" "${trust_label}" "${state}" "${recommended_title:-${recommended_tool}}" "${availability_label}"
                fi
            elif [[ -n "${guidance}" ]]; then
                printf "%s / %s / %s family(s) available; %s\n" "${trust_label}" "${state}" "${available_families:-0}" "${guidance}"
            else
                printf "%s / %s / %s family(s) available\n" "${trust_label}" "${state}" "${available_families:-0}"
            fi
            ;;
        lsp)
            local state=""
            local health=""
            local resolution=""
            local expected_server=""
            state=$(doctor_snapshot_value "${snapshot}" "lsp_state")
            health=$(doctor_snapshot_value "${snapshot}" "lsp_health")
            resolution=$(doctor_snapshot_value "${snapshot}" "lsp_resolution_status")
            expected_server=$(doctor_snapshot_value "${snapshot}" "lsp_expected_server")
            if [[ -n "${expected_server}" ]]; then
                printf "%s / %s / %s (expected server: %s)\n" "${state}" "${health}" "${resolution}" "${expected_server}"
            else
                printf "%s / %s / %s\n" "${state}" "${health}" "${resolution}"
            fi
            ;;
        devcontainer)
            local supported=""
            local trusted=""
            local state=""
            local health=""
            local unsafe=""
            supported=$(doctor_snapshot_value "${snapshot}" "devcontainer_supported")
            trusted=$(doctor_snapshot_value "${snapshot}" "devcontainer_trusted")
            state=$(doctor_snapshot_value "${snapshot}" "devcontainer_state")
            health=$(doctor_snapshot_value "${snapshot}" "devcontainer_health")
            unsafe=$(doctor_snapshot_value "${snapshot}" "devcontainer_unsafe")
            if [[ "${supported}" != "yes" ]]; then
                printf "no devcontainer spec detected\n"
            else
                printf "%s / %s / %s (unsafe=%s)\n" "${trusted}" "${state}" "${health}" "${unsafe:-none}"
            fi
            ;;
        verify)
            local status=""
            local failures=""
            local warns=""
            local summary=""
            local security_status=""
            status=$(doctor_snapshot_value "${snapshot}" "verify_status")
            failures=$(doctor_snapshot_value "${snapshot}" "verify_failures")
            warns=$(doctor_snapshot_value "${snapshot}" "verify_warns")
            summary=$(doctor_snapshot_value "${snapshot}" "verify_summary")
            security_status=$(doctor_snapshot_value "${snapshot}" "verify_security_status")
            if [[ "${status}" == "never-run" ]]; then
                printf "no verify run recorded yet; run: yen ide verify --quick --no-security\n"
            elif [[ -n "${summary}" ]]; then
                printf "%s (failures=%s warns=%s security=%s) report=%s\n" "${status}" "${failures}" "${warns}" "${security_status:-unavailable}" "${summary}"
            else
                printf "%s (failures=%s warns=%s security=%s)\n" "${status}" "${failures}" "${warns}" "${security_status:-unavailable}"
            fi
            ;;
        verify-security)
            local security_status=""
            local step_count=""
            local warning_steps=""
            local failing_steps=""
            local reason=""
            security_status=$(doctor_snapshot_value "${snapshot}" "verify_security_status")
            step_count=$(doctor_snapshot_value "${snapshot}" "verify_security_step_count")
            warning_steps=$(doctor_snapshot_value "${snapshot}" "verify_security_warning_steps")
            failing_steps=$(doctor_snapshot_value "${snapshot}" "verify_security_failing_steps")
            reason=$(doctor_snapshot_value "${snapshot}" "verify_security_reason")
            if [[ -n "${reason}" ]]; then
                printf "%s (steps=%s blockers=%s warnings=%s) %s\n" "${security_status:-unavailable}" "${step_count:-0}" "${failing_steps:-0}" "${warning_steps:-0}" "${reason}"
            else
                printf "%s (steps=%s blockers=%s warnings=%s)\n" "${security_status:-unavailable}" "${step_count:-0}" "${failing_steps:-0}" "${warning_steps:-0}"
            fi
            ;;
        toolchain)
            local execution_location=""
            local requirement=""
            local current=""
            local lockfiles=""
            execution_location=$(doctor_snapshot_value "${snapshot}" "workspace_execution_location")
            requirement=$(doctor_snapshot_value "${snapshot}" "package_manager_requirement")
            current=$(doctor_snapshot_value "${snapshot}" "package_manager_current_version")
            lockfiles=$(doctor_snapshot_value "${snapshot}" "lockfiles")
            if [[ "${execution_location}" == "remote" ]]; then
                if [[ -n "${requirement}" ]]; then
                    printf "remote summary (%s; version checks deferred)\n" "${requirement}"
                elif [[ -n "${lockfiles}" ]]; then
                    printf "remote summary (lockfiles=%s; version checks deferred)\n" "${lockfiles}"
                else
                    printf "remote summary (no packageManager requirement declared)\n"
                fi
                return 0
            fi
            if [[ -n "${requirement}" ]]; then
                printf "%s (current=%s)\n" "${requirement}" "${current:-missing}"
            else
                printf "no packageManager requirement declared\n"
            fi
            ;;
    esac
}

doctor_json_from_snapshot() {
    local snapshot="$1"
    local findings="$2"
    local overall_status="$3"
    local blocker_count="$4"
    local warning_count="$5"
    SNAPSHOT="${snapshot}" FINDINGS="${findings}" OVERALL_STATUS="${overall_status}" BLOCKER_COUNT="${blocker_count}" WARNING_COUNT="${warning_count}" python3 - <<'PY'
import json
import os

raw = os.environ.get("SNAPSHOT", "")
findings_raw = os.environ.get("FINDINGS", "")
data = {}
for line in raw.splitlines():
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    data[key] = value

def split_list(key, delimiter=","):
    value = data.get(key, "")
    if not value:
        return []
    return [item for item in value.split(delimiter) if item]

unsafe = split_list("devcontainer_unsafe", "|")
if unsafe == ["none"]:
    unsafe = []

findings = []
for line in findings_raw.splitlines():
    if not line.strip():
        continue
    severity, code, component, summary, remediation = (line.split("\t", 4) + ["", "", "", "", ""])[:5]
    findings.append(
        {
            "severity": severity,
            "code": code,
            "component": component,
            "summary": summary,
            "remediation": remediation,
        }
    )

payload = {
    "status": os.environ.get("OVERALL_STATUS", "ok"),
    "blockers": int(os.environ.get("BLOCKER_COUNT") or "0"),
    "warnings": int(os.environ.get("WARNING_COUNT") or "0"),
    "root": data.get("root", ""),
    "workspace": {
        "executionLocation": data.get("workspace_execution_location", "local"),
        "transport": data.get("workspace_transport", "local"),
        "identity": data.get("workspace_identity", ""),
        "requestedPath": data.get("workspace_requested_path", ""),
        "authority": data.get("workspace_authority", ""),
        "port": int(data.get("workspace_port") or "0") if data.get("workspace_port") else None,
        "label": data.get("workspace_label", ""),
    },
    "evidence": {
        "projectMetadataSource": data.get("project_metadata_source", "local-filesystem"),
        "stateSource": data.get("state_source", "local-ide-state"),
        "timelineSource": data.get("timeline_source", "local-ide-state"),
        "note": data.get("workspace_note", ""),
    },
    "findings": findings,
    "project": {
        "types": split_list("project_types"),
        "runtime": split_list("runtime_context"),
        "tooling": split_list("tooling_context"),
    },
    "env": {
        "trusted": data.get("env_trusted") == "yes",
        "fileCount": int(data.get("env_files_count") or "0"),
        "files": split_list("env_files", "|"),
        "summary": (
            "no .env files detected"
            if (data.get("env_files_count") or "0") == "0"
            else (
                f"trusted ({data.get('env_files_count')} env file(s))"
                if data.get("env_trusted") == "yes"
                else (
                    f'untrusted ({data.get("env_files_count")} env file(s)); remote trust controls remain read-only'
                    if data.get("workspace_execution_location") == "remote"
                    else f'untrusted ({data.get("env_files_count")} env file(s)); run: yen ide env trust "{data.get("root", "")}"'
                )
            )
        ),
    },
    "debug": {
        "trusted": data.get("debug_trusted") == "yes",
        "state": data.get("debug_state", ""),
        "recommendedTool": data.get("debug_recommended_tool", ""),
        "recommendedToolTitle": data.get("debug_recommended_title", ""),
        "recommendedAvailable": data.get("debug_recommended_available") == "yes",
        "recommendedHint": data.get("debug_recommended_hint", ""),
        "availableFamilies": int(data.get("debug_family_available_count") or "0"),
        "guidance": data.get("debug_guidance", ""),
        "devcontainerExecutionAvailable": data.get("debug_devcontainer_execution_available") == "yes",
        "devcontainerRecommendedAvailable": data.get("debug_devcontainer_recommended_available") == "yes",
        "devcontainerGuidance": data.get("debug_devcontainer_guidance", ""),
        "scope": (
            "remote-execution"
            if data.get("workspace_execution_location") == "remote"
            else (
                "local-with-devcontainer-execution"
                if data.get("debug_devcontainer_execution_available") == "yes"
                else ("local-with-devcontainer-context" if data.get("devcontainer_state") == "running" else "local-only")
            )
        ),
        "executionLocation": data.get("workspace_execution_location", "local"),
        "devcontainerState": data.get("devcontainer_state", ""),
        "devcontainerHealth": data.get("debug_devcontainer_health", data.get("devcontainer_health", "")),
    },
    "lsp": {
        "trusted": data.get("lsp_trusted") == "yes",
        "state": data.get("lsp_state", ""),
        "health": data.get("lsp_health", ""),
        "resolutionStatus": data.get("lsp_resolution_status", ""),
        "resolutionReason": data.get("lsp_resolution_reason", ""),
        "expectedServer": data.get("lsp_expected_server", ""),
        "protocolStatus": data.get("lsp_protocol_status", ""),
        "diagnosticsStatus": data.get("lsp_diagnostics_status", ""),
        "language": data.get("lsp_language", ""),
    },
    "devcontainer": {
        "supported": data.get("devcontainer_supported") == "yes",
        "trusted": data.get("devcontainer_trusted") == "yes",
        "state": data.get("devcontainer_state", ""),
        "health": data.get("devcontainer_health", ""),
        "cli": data.get("devcontainer_cli", ""),
        "cliVersion": data.get("devcontainer_cli_version", ""),
        "spec": data.get("devcontainer_spec", ""),
        "unsafe": unsafe,
        "forwardPorts": split_list("devcontainer_forward_ports", "|"),
    },
    "verify": {
        "status": data.get("verify_status", ""),
        "lastRunAt": data.get("verify_last_run_at", ""),
        "summaryReport": data.get("verify_summary", ""),
        "detailsReport": data.get("verify_details", ""),
        "semanticReport": data.get("verify_semantic", ""),
        "failures": int(data.get("verify_failures") or "0"),
        "warnings": int(data.get("verify_warns") or "0"),
        "executedSteps": int(data.get("verify_executed") or "0"),
        "readiness": {
            "status": data.get("verify_readiness_status", ""),
            "reason": data.get("verify_readiness_reason", ""),
            "mergeReady": data.get("verify_merge_ready", "") == "yes",
        },
        "security": {
            "status": data.get("verify_security_status", ""),
            "reason": data.get("verify_security_reason", ""),
            "stepCount": int(data.get("verify_security_step_count") or "0"),
            "warningSteps": int(data.get("verify_security_warning_steps") or "0"),
            "failingSteps": int(data.get("verify_security_failing_steps") or "0"),
            "passingSteps": int(data.get("verify_security_passing_steps") or "0"),
        },
    },
    "toolchain": {
        "packageManager": {
            "requirement": data.get("package_manager_requirement", ""),
            "name": data.get("package_manager_name", ""),
            "requiredVersion": data.get("package_manager_version", ""),
            "currentVersion": data.get("package_manager_current_version", ""),
        },
        "lockfiles": split_list("lockfiles"),
        "goRequirements": split_list("go_requirements"),
        "goCurrentVersion": data.get("go_current_version", ""),
        "swiftToolsVersion": data.get("swift_tools_version", ""),
        "swiftCurrentVersion": data.get("swift_current_version", ""),
        "pythonRequirement": data.get("python_requirement", ""),
        "pythonCurrentVersion": data.get("python_current_version", ""),
        "nodeCurrentVersion": data.get("node_current_version", ""),
    },
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

cmd_doctor() {
    local target=""
    local format="text"
    local strict="0"
    local root=""
    local snapshot=""
    local findings=""
    local blocker_count="0"
    local warning_count="0"
    local overall_status="ok"
    local exit_code="0"

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
            --strict)
                strict="1"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    if ! workspace_summary_resolve_target "${target}"; then
        return 1
    fi
    root="${IDE_WORKSPACE_SUMMARY_ROOT}"
    snapshot=$(doctor_collect_snapshot "${root}")
    findings=$(doctor_collect_findings "${snapshot}")
    blocker_count=$(doctor_count_findings "${findings}" "blocker")
    warning_count=$(doctor_count_findings "${findings}" "warning")
    overall_status=$(doctor_overall_status "${blocker_count}" "${warning_count}")

    case "${format}" in
        env)
            printf "export YEN_IDE_DOCTOR_STATUS=%s\n" "$(shell_quote_single "${overall_status}")"
            printf "export YEN_IDE_DOCTOR_BLOCKERS=%s\n" "$(shell_quote_single "${blocker_count}")"
            printf "export YEN_IDE_DOCTOR_WARNINGS=%s\n" "$(shell_quote_single "${warning_count}")"
            printf "export YEN_IDE_DOCTOR_ROOT=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "root")")"
            printf "export YEN_IDE_DOCTOR_EXECUTION_LOCATION=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "workspace_execution_location")")"
            printf "export YEN_IDE_DOCTOR_WORKSPACE_IDENTITY=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "workspace_identity")")"
            printf "export YEN_IDE_DOCTOR_REQUESTED_PATH=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "workspace_requested_path")")"
            printf "export YEN_IDE_DOCTOR_PROJECT_METADATA_SOURCE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "project_metadata_source")")"
            printf "export YEN_IDE_DOCTOR_STATE_SOURCE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "state_source")")"
            printf "export YEN_IDE_DOCTOR_PROJECT_TYPES=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "project_types")")"
            printf "export YEN_IDE_DOCTOR_RUNTIME_CONTEXT=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "runtime_context")")"
            printf "export YEN_IDE_DOCTOR_TOOLING_CONTEXT=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "tooling_context")")"
            printf "export YEN_IDE_DOCTOR_ENV_TRUSTED=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "env_trusted")")"
            printf "export YEN_IDE_DOCTOR_ENV_FILE_COUNT=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "env_files_count")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_TRUSTED=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_trusted")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_STATE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_state")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_RECOMMENDED_TOOL=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_recommended_tool")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_RECOMMENDED_AVAILABLE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_recommended_available")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_GUIDANCE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_guidance")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_DEVCONTAINER_EXECUTION_AVAILABLE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_devcontainer_execution_available")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_DEVCONTAINER_RECOMMENDED_AVAILABLE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_devcontainer_recommended_available")")"
            printf "export YEN_IDE_DOCTOR_DEBUG_DEVCONTAINER_GUIDANCE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "debug_devcontainer_guidance")")"
            printf "export YEN_IDE_DOCTOR_LSP_TRUSTED=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "lsp_trusted")")"
            printf "export YEN_IDE_DOCTOR_LSP_STATE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "lsp_state")")"
            printf "export YEN_IDE_DOCTOR_LSP_HEALTH=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "lsp_health")")"
            printf "export YEN_IDE_DOCTOR_LSP_RESOLUTION_STATUS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "lsp_resolution_status")")"
            printf "export YEN_IDE_DOCTOR_DEVCONTAINER_SUPPORTED=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "devcontainer_supported")")"
            printf "export YEN_IDE_DOCTOR_DEVCONTAINER_TRUSTED=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "devcontainer_trusted")")"
            printf "export YEN_IDE_DOCTOR_DEVCONTAINER_STATE=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "devcontainer_state")")"
            printf "export YEN_IDE_DOCTOR_DEVCONTAINER_HEALTH=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "devcontainer_health")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_STATUS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_status")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_FAILURES=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_failures")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_WARNINGS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_warns")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SUMMARY=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_summary")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_DETAILS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_details")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SEMANTIC=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_semantic")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_READINESS_STATUS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_readiness_status")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_MERGE_READY=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_merge_ready")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SECURITY_STATUS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_security_status")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SECURITY_STEPS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_security_step_count")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SECURITY_BLOCKERS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_security_failing_steps")")"
            printf "export YEN_IDE_DOCTOR_VERIFY_SECURITY_WARNINGS=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "verify_security_warning_steps")")"
            printf "export YEN_IDE_DOCTOR_PACKAGE_MANAGER=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "package_manager_requirement")")"
            printf "export YEN_IDE_DOCTOR_LOCKFILES=%s\n" "$(shell_quote_single "$(doctor_snapshot_value "${snapshot}" "lockfiles")")"
            ;;
        json)
            doctor_json_from_snapshot "${snapshot}" "${findings}" "${overall_status}" "${blocker_count}" "${warning_count}"
            ;;
        text)
            echo ""
            yen_header "IDE Workspace / Toolchain Doctor"
            echo "Status:             ${overall_status}"
            echo "Blockers:           ${blocker_count}"
            echo "Warnings:           ${warning_count}"
            echo "Root:               $(doctor_snapshot_value "${snapshot}" "root")"
            echo "Execution location: $(doctor_snapshot_value "${snapshot}" "workspace_execution_location")"
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "workspace_identity")" ]]; then
                echo "Workspace identity: $(doctor_snapshot_value "${snapshot}" "workspace_identity")"
            fi
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "workspace_requested_path")" ]]; then
                echo "Requested path:     $(doctor_snapshot_value "${snapshot}" "workspace_requested_path")"
            fi
            echo "Project types:      $(doctor_snapshot_value "${snapshot}" "project_types")"
            echo "Runtime context:    $(doctor_snapshot_value "${snapshot}" "runtime_context")"
            echo "Tooling context:    $(doctor_snapshot_value "${snapshot}" "tooling_context")"
            echo "Project metadata:   $(doctor_snapshot_value "${snapshot}" "project_metadata_source")"
            echo "State evidence:     $(doctor_snapshot_value "${snapshot}" "state_source")"
            echo "Timeline evidence:  $(doctor_snapshot_value "${snapshot}" "timeline_source")"
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "workspace_note")" ]]; then
                echo "Note:               $(doctor_snapshot_value "${snapshot}" "workspace_note")"
            fi
            echo ""
            echo "Checks:"
            echo "  Env:           $(doctor_component_summary "${snapshot}" "env")"
            echo "  Debug:         $(doctor_component_summary "${snapshot}" "debug")"
            echo "  LSP:           $(doctor_component_summary "${snapshot}" "lsp")"
            echo "  Devcontainer:  $(doctor_component_summary "${snapshot}" "devcontainer")"
            echo "  Verify:        $(doctor_component_summary "${snapshot}" "verify")"
            echo "  Security:      $(doctor_component_summary "${snapshot}" "verify-security")"
            echo "  Toolchain:     $(doctor_component_summary "${snapshot}" "toolchain")"
            echo ""
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "go_requirements")" ]]; then
                echo "Detected Go requirements: $(doctor_snapshot_value "${snapshot}" "go_requirements")"
            fi
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "swift_tools_version")" ]]; then
                echo "Swift tools version:     $(doctor_snapshot_value "${snapshot}" "swift_tools_version")"
            fi
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "python_requirement")" ]]; then
                echo "Python requirement:      $(doctor_snapshot_value "${snapshot}" "python_requirement")"
            fi
            if [[ -n "$(doctor_snapshot_value "${snapshot}" "lockfiles")" ]]; then
                echo "Lockfiles:               $(doctor_snapshot_value "${snapshot}" "lockfiles")"
            fi
            if [[ -z "${findings}" ]]; then
                echo ""
                echo "Findings:"
                echo "  none"
            else
                echo ""
                echo "Findings:"
                while IFS=$'\t' read -r severity code component summary remediation; do
                    [[ -z "${severity}" ]] && continue
                    echo "  [${severity}] ${code} (${component})"
                    echo "    ${summary}"
                    echo "    Fix: ${remediation}"
                done << EOF
${findings}
EOF
            fi
            echo ""
            ;;
        *)
            yen_error "Unknown doctor format: ${format} (expected text|env|json)"
            return 1
            ;;
    esac

    if [[ "${blocker_count}" -gt 0 ]]; then
        exit_code="1"
    elif [[ "${strict}" == "1" && "${warning_count}" -gt 0 ]]; then
        exit_code="1"
    fi

    timeline_log "doctor" "${root}" "status=${overall_status};blockers=${blocker_count};warnings=${warning_count};strict=${strict}" "verify=$(doctor_snapshot_value "${snapshot}" "verify_status");security=$(doctor_snapshot_value "${snapshot}" "verify_security_status");lsp=$(doctor_snapshot_value "${snapshot}" "lsp_resolution_status");devcontainer=$(doctor_snapshot_value "${snapshot}" "devcontainer_state")"
    return "${exit_code}"
}
