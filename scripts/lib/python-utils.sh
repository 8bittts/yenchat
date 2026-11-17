#!/bin/bash
# python-utils.sh - shared python runtime checks for release scripts.

require_python3() {
    local context="${1:-for this script}"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is required ${context}"
        return 1
    fi
    return 0
}
