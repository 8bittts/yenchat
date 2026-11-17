#!/bin/bash
# YEN Command Initialization
# Source this at the top of every command to handle boilerplate:
#   - set -e (exit on error)
#   - Common utilities sourcing
#   - Lazy library loading via yen_require
#
# Usage:
#   #!/bin/bash
#   source "${YEN_LIB}/init.sh"
#
# bin/yen sets YEN_LIB and YEN_CMD_DIR before any command runs; commands are
# always invoked via bin/yen, never directly.

set -e

if [[ -z "$YEN_LIB" ]]; then
    echo "Error: YEN_LIB not set. Commands must be invoked via 'yen' command." >&2
    exit 1
fi

# Use YEN_LIB as canonical base path
export YEN_LIB_DIR="$YEN_LIB"

# Ensure derived paths are set (should already be set by bin/yen, but ensure for safety)
export YEN_CMD_DIR="${YEN_CMD_DIR:-${YEN_LIB_DIR}/../commands}"

# For backward compatibility with existing code that uses LIB_DIR
export LIB_DIR="${LIB_DIR:-$YEN_LIB_DIR}"

# =============================================================================
# COMMON UTILITIES
# =============================================================================
# Always source common.sh - it's small and used by everything

source "${YEN_LIB_DIR}/common.sh"

# =============================================================================
# LAZY LIBRARY LOADING
# =============================================================================
# Load libraries on demand to reduce startup time for simple commands

# Track which libraries have been loaded to avoid double-sourcing
declare -a _YEN_LOADED_LIBS=()

# Check if a library is already loaded
_yen_lib_loaded() {
    local lib="$1"
    local loaded
    for loaded in "${_YEN_LOADED_LIBS[@]}"; do
        [[ "$loaded" == "$lib" ]] && return 0
    done
    return 1
}

# Load a library by name (for future extensibility)
# Usage: yen_require <library_name>
yen_require() {
    local lib="$1"

    # Skip if already loaded
    if _yen_lib_loaded "$lib"; then
        return 0
    fi

    local lib_path="${YEN_LIB_DIR}/${lib}.sh"

    if [[ -f "$lib_path" ]]; then
        # shellcheck source=/dev/null
        source "$lib_path"
        _YEN_LOADED_LIBS+=("$lib")
    else
        yen_error "Library not found: $lib"
        exit 1
    fi
}

# =============================================================================
# HELP GENERATION
# =============================================================================

yen_help() {
    local cmd="$1"

    # Search for command in nested directory structure
    local cmd_path
    cmd_path=$(find "${YEN_CMD_DIR}" -name "${cmd}" -type f 2>/dev/null | head -1)

    if [[ -n "$cmd_path" && -x "$cmd_path" ]]; then
        "$cmd_path" --help 2>/dev/null || echo "Run: yen $cmd --help"
    else
        echo "Unknown command: $cmd"
        echo "Run: yen help"
    fi
}
