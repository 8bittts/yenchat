#!/bin/bash

# Shipping builds must use a stable Xcode.app selection.
# Apple GM build numbers often end in a letter (e.g. 27A266a, 16A242d), so a
# trailing-letter heuristic is not a prerelease signal. Block by install path
# and by the human-readable version line instead.

validate_selected_xcode_release_policy() {
    local developer_dir
    local build_version
    local version_line
    local developer_dir_lower
    local version_line_lower
    local xcodebuild_out

    developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
    xcodebuild_out="$(xcodebuild -version 2>/dev/null || true)"
    version_line="$(printf '%s\n' "$xcodebuild_out" | awk '/^Xcode / { print; exit }')"
    build_version="$(printf '%s\n' "$xcodebuild_out" | awk '/^Build version / { print $3; exit }')"
    developer_dir_lower="$(printf '%s' "$developer_dir" | tr '[:upper:]' '[:lower:]')"
    version_line_lower="$(printf '%s' "$version_line" | tr '[:upper:]' '[:lower:]')"

    if [ -z "$developer_dir" ] || [ -z "$build_version" ]; then
        echo "  ERROR: Could not resolve the selected Xcode developer directory and build version"
        return 1
    fi

    case "$developer_dir_lower" in
        */xcode-beta.app/*|*/xcode_beta.app/*|*/xcode-rc.app/*)
            if [ "${YEN_ALLOW_PRERELEASE_XCODE:-0}" = "1" ]; then
                echo "  WARNING: Pre-release Xcode explicitly allowed: $developer_dir ($build_version)"
                return 0
            fi
            echo "  ERROR: Refusing pre-release Xcode: $developer_dir ($build_version)"
            echo "    Select stable Xcode: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
            echo "    Emergency override: YEN_ALLOW_PRERELEASE_XCODE=1"
            return 1
            ;;
    esac

    # Match beta / RC wording in the human-readable version line only.
    # Do not key off ProductBuildVersion letter suffixes — Apple GMs use them.
    if [[ "$version_line_lower" == *beta* ]] ||
        [[ "$version_line_lower" == *"release candidate"* ]] ||
        [[ "$version_line_lower" == *" rc"* ]] ||
        [[ "$version_line_lower" == *"rc "* ]]; then
        if [ "${YEN_ALLOW_PRERELEASE_XCODE:-0}" = "1" ]; then
            echo "  WARNING: Pre-release Xcode explicitly allowed: $developer_dir ($build_version)"
            return 0
        fi
        echo "  ERROR: Refusing pre-release Xcode: $developer_dir ($build_version)"
        echo "    Select stable Xcode: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        echo "    Emergency override: YEN_ALLOW_PRERELEASE_XCODE=1"
        return 1
    fi

    echo "  ✓ Stable Xcode selected: $developer_dir ($build_version)"
}
