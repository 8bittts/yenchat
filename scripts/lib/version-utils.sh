#!/bin/bash
# version-utils.sh — Shared version extraction utilities
#
# Source this file to get version helper functions:
#   source "$(dirname "$0")/lib/version-utils.sh"
#
# Functions:
#   get_version "$VERSION_JSON"         → "0.999" / "1.000" / "1.001"
#   is_valid_release_version "$VERSION" → exit 0 for valid display versions
#   get_version_int "$VERSION"          → "999" / "1000" / "1001"
#   get_version_semver "$VERSION"       → "0.999.0" / "1.0.0" / "1.0.1"
#   get_version_filename "$VERSION"     → "0999" / "1000" / "1001"
#   version_to_filename "$VERSION"      → legacy compatibility wrapper
#   get_dmg_filename "$VERSION"         → "yen-0999.dmg" / "yen-1000.dmg"

# Get version string from version.json
# Usage: VERSION=$(get_version "$VERSION_JSON")
get_version() {
    local version_json="$1"
    if [ ! -f "$version_json" ]; then
        echo "ERROR: version.json not found: $version_json" >&2
        return 1
    fi
    get_version_json_string "$version_json" "version"
}

get_version_json_string() {
    local version_json="$1"
    local key="$2"

    if [ ! -f "$version_json" ]; then
        echo "ERROR: version.json not found: $version_json" >&2
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        command jq -r ".$key" "$version_json" 2>/dev/null
    else
        command grep "\"$key\"" "$version_json" | command sed 's/.*: *"\([^"]*\)".*/\1/'
    fi
}

extract_sparkle_ed_signature() {
    local sign_output="$1"
    printf '%s\n' "$sign_output" | command grep -o 'sparkle:edSignature="[^"]*"' | command sed 's/sparkle:edSignature="\([^"]*\)"/\1/' | command head -1 || true
}

# Valid display-version format:
# - All releases use X.XXX (for example 0.999, 1.000, 1.001)
is_valid_release_version() {
    local version="$1"

    if printf '%s\n' "$version" | command grep -qE '^(0|[1-9][0-9]*)\.[0-9]{3}$'; then
        return 0
    fi

    return 1
}

get_version_major() {
    local version="$1"
    printf '%s\n' "$version" | command awk -F. '{printf "%d", $1+0}'
}

get_version_track() {
    local version="$1"
    printf '%s\n' "$version" | command awk -F. '{printf "%d", $2+0}'
}

# Get integer build version (for CFBundleVersion and sparkle:version)
# Usage: VERSION_INT=$(get_version_int "$VERSION")
get_version_int() {
    local version="$1"
    local major
    local track

    if ! is_valid_release_version "$version"; then
        echo "ERROR: Invalid version format: $version" >&2
        return 1
    fi

    major=$(get_version_major "$version")
    track=$(get_version_track "$version")
    echo $((major * 1000 + track))
}

# Get semver for the compiled binary.
# Legacy 0.XXX releases map to 0.<track>.0.
# Modern X.XXX releases map to X.0.<track>.
get_version_semver() {
    local version="$1"
    local major
    local track

    if ! is_valid_release_version "$version"; then
        echo "ERROR: Invalid version format: $version" >&2
        return 1
    fi

    major=$(get_version_major "$version")
    track=$(get_version_track "$version")

    if [ "$major" -eq 0 ]; then
        printf "%s.%s.0\n" "$major" "$track"
    else
        printf "%s.0.%s\n" "$major" "$track"
    fi
}

# Get version for filenames (monotonic and padded for sorting)
# Usage: VERSION_FILENAME=$(get_version_filename "$VERSION")
get_version_filename() {
    local version="$1"
    local version_int

    version_int=$(get_version_int "$version") || return 1
    printf "%04d\n" "$version_int"
}

# Legacy compatibility wrapper for older automation that still calls the
# pre-v1 helper name. Canonical callers should use get_version_filename().
version_to_filename() {
    get_version_filename "$@"
}

# Get DMG filename
# Usage: DMG_FILENAME=$(get_dmg_filename "$VERSION")
get_dmg_filename() {
    local version="$1"
    local version_filename
    version_filename=$(get_version_filename "$version") || return 1
    echo "yen-${version_filename}.dmg"
}

# Get SHA256 of a file
# Usage: SHA256=$(get_sha256 "$FILE_PATH")
get_sha256() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "ERROR: File not found: $file_path" >&2
        return 1
    fi
    command shasum -a 256 "$file_path" | command awk '{print $1}'
}

# Get git commit hash (short)
# Usage: COMMIT=$(get_git_commit "$REPO_ROOT")
get_git_commit() {
    local repo_root="${1:-.}"
    command git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo "dev"
}
