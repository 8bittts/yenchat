# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

collect_env_files() {
    local root="$1"
    if [[ -f "${root}/.env" ]]; then
        printf "%s/.env\n" "${root}"
    fi
    if [[ -f "${root}/.env.local" ]]; then
        printf "%s/.env.local\n" "${root}"
    fi
}

write_env_parse_issue() {
    local report_file="$1"
    local file="$2"
    local line_no="$3"
    local code="$4"
    local raw_line="$5"
    [[ -n "${report_file}" ]] || return 0
    printf "%s\t%s\t%s\t%s\t%s\n" "$(iso_now)" "${file}" "${line_no}" "${code}" "${raw_line}" >> "${report_file}"
}

emit_exports_from_env_file() {
    local file="$1"
    local strict="${2:-0}"
    local report_file="${3:-}"
    local raw
    local line
    local key
    local value
    local escaped
    local line_no=0
    local invalid=0

    while IFS= read -r raw || [[ -n "${raw}" ]]; do
        line_no=$((line_no + 1))
        line=$(trim "${raw}")
        [[ -z "${line}" ]] && continue
        [[ "${line#\#}" != "${line}" ]] && continue

        if [[ "${line}" == export* ]]; then
            line=$(printf "%s" "${line}" | sed 's/^export[[:space:]]*//')
        fi

        if [[ "${line}" != *=* ]]; then
            invalid=$((invalid + 1))
            write_env_parse_issue "${report_file}" "${file}" "${line_no}" "missing-assignment" "${raw}"
            continue
        fi

        key=$(trim "${line%%=*}")
        value=$(trim "${line#*=}")

        if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            invalid=$((invalid + 1))
            write_env_parse_issue "${report_file}" "${file}" "${line_no}" "invalid-key" "${raw}"
            continue
        fi

        # Keep parser intentionally conservative in strict mode to avoid hidden evaluation semantics.
        if [[ "${strict}" == "1" ]]; then
            if [[ "${value}" == *'$('* || "${value}" == *'`'* || "${value}" == *'${'* ]]; then
                invalid=$((invalid + 1))
                write_env_parse_issue "${report_file}" "${file}" "${line_no}" "unsupported-expansion" "${raw}"
                continue
            fi
        fi

        if [[ ${#value} -ge 2 && "${value}" == \"*\" && "${value}" == *\" ]]; then
            value="${value:1:${#value}-2}"
        fi
        if [[ ${#value} -ge 2 && "${value}" == \'*\' && "${value}" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi

        escaped=$(printf "%s" "${value}" | sed "s/'/'\"'\"'/g")
        printf "export %s='%s'\n" "${key}" "${escaped}"
    done < "${file}"

    if [[ "${strict}" == "1" && "${invalid}" -gt 0 ]]; then
        return 2
    fi
    return 0
}

cmd_env_status() {
    local target="$1"
    local root
    local trusted="no"
    local files
    root=$(find_project_root "${target}")
    if is_trusted_project "${root}"; then
        trusted="yes"
    fi
    files=$(collect_env_files "${root}" || true)

    echo ""
    yen_header "IDE Env Status"
    echo "Project root: ${root}"
    echo "Trusted:      ${trusted}"
    if [[ -z "${files}" ]]; then
        echo "Env files:    none"
    else
        echo "Env files:"
        printf "%s\n" "${files}" | sed 's/^/  - /'
    fi
    echo ""
}

cmd_env_load() {
    local target=""
    local force="0"
    local strict="0"
    local report_path=""
    local report_file=""
    local parse_failures="0"
    local file_count="0"
    local root
    local files

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="1"
                ;;
            --strict)
                strict="1"
                ;;
            --report)
                shift
                report_path="${1:-}"
                if [[ -z "${report_path}" ]]; then
                    yen_error "--report requires a path."
                    return 1
                fi
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    files=$(collect_env_files "${root}" || true)
    file_count=$(doctor_count_lines "${files}")
    if [[ -z "${files}" ]]; then
        timeline_log "env-load" "${root}" "no-files" "files=0;strict=${strict};force=${force}"
        return 0
    fi

    if [[ "${force}" != "1" ]] && ! is_trusted_project "${root}"; then
        if [[ -t 0 ]]; then
            echo "Project env is untrusted: ${root}" >&2
            echo "Allow loading .env values?" >&2
            echo "  [o] once  [a] always trust  [n] no" >&2
            printf "> " >&2
            read -r answer
            case "${answer}" in
                a|A|always|ALWAYS)
                    trust_project "${root}"
                    timeline_log "env-trust" "${root}" "trusted" "source=prompt"
                    ;;
                o|O|once|ONCE|y|Y|yes|YES)
                    ;;
                *)
                    timeline_log "env-load" "${root}" "blocked" "reason=denied;files=${file_count};strict=${strict};force=${force}"
                    return 1
                    ;;
            esac
        else
            timeline_log "env-load" "${root}" "blocked" "reason=untrusted-project;files=${file_count};strict=${strict};force=${force}"
            yen_error "Project env is untrusted: ${root}"
            yen_info "Run: yen ide env trust \"${root}\""
            return 1
        fi
    fi

    if [[ -n "${report_path}" ]]; then
        report_file="${report_path}"
        : > "${report_file}"
    fi

    while IFS= read -r file; do
        if ! emit_exports_from_env_file "${file}" "${strict}" "${report_file}"; then
            parse_failures=$((parse_failures + 1))
        fi
    done << EOF
${files}
EOF

    if [[ "${strict}" == "1" && "${parse_failures}" -gt 0 ]]; then
        timeline_log "env-load" "${root}" "failed" "files=${file_count};parse_failures=${parse_failures};strict=${strict};force=${force};report=${report_file}"
        yen_error "env load strict mode rejected unsupported/invalid lines."
        if [[ -n "${report_file}" ]]; then
            yen_info "Parse report: ${report_file}"
        fi
        return 1
    fi

    timeline_log "env-load" "${root}" "loaded" "files=${file_count};parse_failures=${parse_failures};strict=${strict};force=${force};report=${report_file}"
}

cmd_env() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        status)
            cmd_env_status "$1"
            ;;
        trust)
            local root
            root=$(find_project_root "$1")
            trust_project "${root}"
            timeline_log "env-trust" "${root}" "trusted" "source=manual"
            yen_success "Trusted project env: ${root}"
            ;;
        untrust)
            local root
            root=$(find_project_root "$1")
            untrust_project "${root}"
            timeline_log "env-trust" "${root}" "untrusted" "source=manual"
            yen_success "Removed env trust: ${root}"
            ;;
        list)
            ensure_state_dirs
            if [[ ! -s "${IDE_TRUST_FILE}" ]]; then
                yen_info "No trusted projects."
                return 0
            fi
            echo ""
            yen_header "Trusted Env Projects"
            nl -ba "${IDE_TRUST_FILE}"
            echo ""
            ;;
        load)
            cmd_env_load "$@"
            ;;
        *)
            yen_error "Unknown env subcommand: ${sub}"
            show_help
            exit 1
            ;;
    esac
}
