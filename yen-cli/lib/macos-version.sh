# Minimum system version for YEN builds and standalone CLI commands.
YEN_MIN_MACOS=27.0

require_yen_macos() {
    local version major minor
    version=$(sw_vers -productVersion 2>/dev/null) || version=""
    if [[ "$version" =~ ^([1-9][0-9]*)[.]([0-9]+)([.][0-9]+)?$ ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
        if (( major > ${YEN_MIN_MACOS%.*} || (major == ${YEN_MIN_MACOS%.*} && 10#$minor >= ${YEN_MIN_MACOS#*.}) )); then
            return 0
        fi
    fi
    echo "YEN requires macOS $YEN_MIN_MACOS or later." >&2
    return 1
}
