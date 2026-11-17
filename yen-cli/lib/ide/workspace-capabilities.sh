# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

explain_status_hint() {
    local status="$1"
    case "${status}" in
        0)
            echo "Command exited successfully."
            ;;
        1)
            echo "General failure. Check command stderr and input arguments."
            ;;
        2)
            echo "Shell misuse or invalid CLI arguments (common for getopt/usage errors)."
            ;;
        126)
            echo "Command located but not executable. Check permissions (chmod +x) and path type."
            ;;
        127)
            echo "Command not found. Check PATH, typos, and tool installation."
            ;;
        130)
            echo "Interrupted (SIGINT / Ctrl+C)."
            ;;
        *)
            if [[ "${status}" -gt 128 ]]; then
                echo "Terminated by signal $((status - 128))."
            else
                echo "Non-zero exit status: ${status}."
            fi
            ;;
    esac
}

cmd_explain() {
    local status="${YEN_IDE_LAST_STATUS:-1}"
    local use_last="0"
    local command=""
    local output_file=""
    local root
    local types
    local runtime
    local tooling

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last)
                use_last="1"
                ;;
            --status=*)
                status="${1#*=}"
                ;;
            --status)
                shift
                status="${1:-1}"
                ;;
            --output|--output-file)
                shift
                output_file="${1:-}"
                ;;
            *)
                if [[ -z "${command}" ]]; then
                    command="$1"
                else
                    command="${command} $1"
                fi
                ;;
        esac
        shift
    done

    if [[ "${use_last}" == "1" ]]; then
        if [[ -n "${YEN_IDE_LAST_COMMAND:-}" ]]; then
            command="${YEN_IDE_LAST_COMMAND}"
        else
            root=$(find_project_root "${PWD}")
            command=$(lookup_history_command "${root}" "1" || true)
        fi
    fi

    if [[ -z "${command}" ]]; then
        command=$(lookup_history_command "$(find_project_root "${PWD}")" "1" || true)
    fi

    if [[ -z "${command}" ]]; then
        yen_error "No command context available. Provide a command or run with --last after a failure."
        exit 1
    fi

    root=$(find_project_root "${PWD}")
    types=$(detect_project_types "${root}")
    runtime=$(detect_runtime_context "${root}")
    tooling=$(detect_tooling_context "${root}")

    local primary
    primary=$(explain_status_hint "${status}")

    local checks=()
    if [[ "${status}" == "127" ]]; then
        checks+=("Run: command -v $(printf "%s" "${command}" | awk '{print $1}')")
        checks+=("Verify tool install and PATH ordering in this shell.")
    fi
    if [[ "${command}" == *"go test"* ]]; then
        checks+=("Run: go test ./... to confirm package-level failures.")
        checks+=("Run: go env GOPATH GOMOD")
    fi
    if [[ "${command}" == *"bun "* || "${command}" == "bun" ]]; then
        checks+=("Run: bun install to refresh dependencies.")
        checks+=("Run: bunx tsc --noEmit for type errors.")
    fi
    if [[ "${command}" == *"npm "* || "${command}" == "npm" ]]; then
        checks+=("Run: npm install (or ci) to sync node_modules.")
    fi
    if [[ "${command}" == *"yarn "* || "${command}" == "yarn" ]]; then
        checks+=("Run: yarn install to refresh lockfile state.")
    fi
    if [[ "${command}" == *"python "* || "${command}" == *"pytest"* ]]; then
        checks+=("Validate active venv and interpreter: which python")
    fi
    if [[ "${command}" == *"docker "* ]]; then
        checks+=("Check daemon state: docker info")
    fi

    echo ""
    yen_header "IDE Error Explanation"
    echo "Command:      ${command}"
    echo "Exit status:  ${status}"
    echo "Project root: ${root}"
    echo "Context:      types=${types} runtime=${runtime} tooling=${tooling}"
    echo ""
    echo "Likely cause:"
    echo "  - ${primary}"

    if [[ ${#checks[@]} -gt 0 ]]; then
        echo ""
        echo "Suggested checks:"
        local check
        for check in "${checks[@]}"; do
            echo "  - ${check}"
        done
    fi

    if [[ -n "${output_file}" && -f "${output_file}" ]]; then
        local refs
        refs=$(cat "${output_file}" | grep -Eo '([A-Za-z0-9_./~:-]+\.[A-Za-z0-9_+-]+:[0-9]+(:[0-9]+)?)' | grep -v '://' | head -n 5 || true)
        if [[ -n "${refs}" ]]; then
            echo ""
            echo "Top file references:"
            printf "%s\n" "${refs}" | sed 's/^/  - /'
        fi
    fi
    timeline_log "explain" "${root}" "status=${status}" "cmd=${command}"
    echo ""
}
