# shellcheck shell=bash
# Source-time pure shared helpers for yen ide timing and timeline output.

now_ms() {
    if command -v perl >/dev/null 2>&1; then
        perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'
        return 0
    fi
    printf "%s000\n" "$(date +%s)"
}

iso_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timeline_log() {
    local event="$1"
    local project_root="$2"
    local status="$3"
    local detail="$4"
    if declare -F project_timeline_key_for_root >/dev/null 2>&1; then
        project_root=$(project_timeline_key_for_root "${project_root}")
    fi
    ensure_state_dirs
    detail=$(printf "%s" "${detail}" | tr '\t\r\n' '   ')
    printf "%s\t%s\t%s\t%s\t%s\n" "$(iso_now)" "${event}" "${project_root}" "${status}" "${detail}" >> "${IDE_TIMELINE_FILE}"
}
