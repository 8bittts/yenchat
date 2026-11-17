#!/bin/bash
# Shared workflow lock helpers
#
# Prevents conflicting top-level workflows from running at the same time
# (vendor, build-release, finalize-build).

init_shared_workflow_lock() {
    local repo_root="$1"
    local lock_key

    lock_key=$(printf '%s\n' "$repo_root" | cksum | awk '{print $1}')
    YEN_SHARED_WORKFLOW_LOCK_DIR="${TMPDIR:-/tmp}/yen-workflow-${lock_key}.lock"
    YEN_SHARED_WORKFLOW_LOCK_ACQUIRED=false
    YEN_SHARED_WORKFLOW_LOCK_ATTACHED=false
}

acquire_shared_workflow_lock() {
    local workflow_name="$1"
    local existing_pid
    local existing_workflow

    if [ -z "${YEN_SHARED_WORKFLOW_LOCK_DIR:-}" ]; then
        echo "ERROR: Shared workflow lock not initialized"
        return 1
    fi

    # Nested workflow invocation (e.g. build-release -> finalize-build).
    if [ -n "${YEN_SHARED_WORKFLOW_LOCK_TOKEN:-}" ] && \
        [ "$YEN_SHARED_WORKFLOW_LOCK_TOKEN" = "$YEN_SHARED_WORKFLOW_LOCK_DIR" ]; then
        existing_pid=""
        if [ -f "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" ]; then
            existing_pid=$(cat "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" 2>/dev/null || true)
        fi
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
            YEN_SHARED_WORKFLOW_LOCK_ATTACHED=true
            return 0
        fi
    fi

    if mkdir "$YEN_SHARED_WORKFLOW_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" || {
            rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
            return 1
        }
        echo "$workflow_name" > "$YEN_SHARED_WORKFLOW_LOCK_DIR/workflow" || {
            rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
            return 1
        }
        YEN_SHARED_WORKFLOW_LOCK_ACQUIRED=true
        export YEN_SHARED_WORKFLOW_LOCK_TOKEN="$YEN_SHARED_WORKFLOW_LOCK_DIR"
        return 0
    fi

    existing_pid=""
    existing_workflow=""

    if [ -f "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" ]; then
        existing_pid=$(cat "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" 2>/dev/null || true)
    fi
    if [ -f "$YEN_SHARED_WORKFLOW_LOCK_DIR/workflow" ]; then
        existing_workflow=$(cat "$YEN_SHARED_WORKFLOW_LOCK_DIR/workflow" 2>/dev/null || true)
    fi

    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        if [ -z "$existing_workflow" ]; then
            existing_workflow="unknown workflow"
        fi
        echo "ERROR: Another workflow is running (${existing_workflow}, pid $existing_pid)"
        echo "Wait for it to finish before starting ${workflow_name}."
        return 1
    fi

    if [ -z "$existing_pid" ]; then
        echo "ERROR: Shared workflow lock exists without a PID file: $YEN_SHARED_WORKFLOW_LOCK_DIR"
        echo "If no workflow is running, remove the stale lock and retry."
        return 1
    fi

    # Stale lock cleanup (pid is dead, or reused by a different command).
    rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
    if mkdir "$YEN_SHARED_WORKFLOW_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" || {
            rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
            return 1
        }
        echo "$workflow_name" > "$YEN_SHARED_WORKFLOW_LOCK_DIR/workflow" || {
            rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
            return 1
        }
        YEN_SHARED_WORKFLOW_LOCK_ACQUIRED=true
        export YEN_SHARED_WORKFLOW_LOCK_TOKEN="$YEN_SHARED_WORKFLOW_LOCK_DIR"
        return 0
    fi

    echo "ERROR: Could not acquire shared workflow lock: $YEN_SHARED_WORKFLOW_LOCK_DIR"
    return 1
}

release_shared_workflow_lock() {
    local lock_pid

    if [ "${YEN_SHARED_WORKFLOW_LOCK_ACQUIRED:-false}" = true ] && \
        [ -d "${YEN_SHARED_WORKFLOW_LOCK_DIR:-}" ]; then
        lock_pid=""
        if [ -f "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" ]; then
            lock_pid=$(cat "$YEN_SHARED_WORKFLOW_LOCK_DIR/pid" 2>/dev/null || true)
        fi
        if [ -z "$lock_pid" ] || [ "$lock_pid" = "$$" ]; then
            rm -rf "$YEN_SHARED_WORKFLOW_LOCK_DIR"
        fi
    fi
}

acquire_yen_process_lock() {
    local lock_dir="$1"
    local acquired_var="$2"
    local script_marker="$3"
    local busy_message="$4"
    local missing_pid_message="$5"
    local acquire_failed_message="$6"
    local existing_pid
    local existing_cmd

    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$$" > "$lock_dir/pid" || {
            rm -rf "$lock_dir"
            printf '%s\n' "$acquire_failed_message"
            return 1
        }
        eval "$acquired_var=true"
        return 0
    fi

    existing_pid=""
    if [ -f "$lock_dir/pid" ]; then
        existing_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    fi

    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        existing_cmd=$(ps -p "$existing_pid" -o command= 2>/dev/null || true)
        if echo "$existing_cmd" | grep -q "$script_marker"; then
            busy_message="${busy_message//\{pid\}/$existing_pid}"
            printf '%s\n' "$busy_message"
            return 1
        fi
    fi

    if [ -z "$existing_pid" ]; then
        printf '%s\n' "$missing_pid_message"
        return 1
    fi

    # Stale lock cleanup (pid is dead, or reused by a different command).
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$$" > "$lock_dir/pid" || {
            rm -rf "$lock_dir"
            printf '%s\n' "$acquire_failed_message"
            return 1
        }
        eval "$acquired_var=true"
        return 0
    fi

    printf '%s\n' "$acquire_failed_message"
    return 1
}
