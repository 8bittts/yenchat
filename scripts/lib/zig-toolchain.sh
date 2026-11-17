#!/bin/bash
# Zig toolchain pin — the one comparison of the local `zig version` against
# Ghostty's `.minimum_zig_version`.
#
# Two callers run it at different moments with different bypass variables:
# scripts/14-vendor.sh before a Ghostty download (YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT)
# and yen-terminal/customizations/validate-environment.sh before every build
# (YEN_SKIP_ZIG_VERSION_CHECK). Each used to carry its own grep/sed copy of this
# check, so a change to the pin format had two places to miss.
#
# Bash 3.2 compatible. Sourced, never executed.

# zig_toolchain_required_version <build.zig.zon>
# Prints the pinned version, or nothing when the file or pin is absent.
zig_toolchain_required_version() {
    local zon_file="$1"
    [ -f "$zon_file" ] || return 0
    grep 'minimum_zig_version' "$zon_file" | sed -E 's/.*"([^"]+)".*/\1/' | head -1
}

# zig_toolchain_recovery_command <version>
# The exact command that installs and activates the pinned toolchain.
zig_toolchain_recovery_command() {
    local required="$1"
    printf 'zigup fetch %s && export PATH="$HOME/.local/share/zigup/%s/files:$PATH"' "$required" "$required"
}

# zig_toolchain_check <build.zig.zon>
# Sets ZIG_TOOLCHAIN_REQUIRED and ZIG_TOOLCHAIN_HAVE for the caller's message.
# Returns:
#   0  match, or nothing to compare (no pin file, no pin, zig present but silent)
#   1  confirmed mismatch
#   2  zig is not on PATH while a pin exists
zig_toolchain_check() {
    local zon_file="$1"
    ZIG_TOOLCHAIN_REQUIRED=""
    ZIG_TOOLCHAIN_HAVE=""

    ZIG_TOOLCHAIN_REQUIRED="$(zig_toolchain_required_version "$zon_file")"
    [ -n "$ZIG_TOOLCHAIN_REQUIRED" ] || return 0

    command -v zig >/dev/null 2>&1 || return 2

    ZIG_TOOLCHAIN_HAVE="$(zig version 2>/dev/null || true)"
    [ -n "$ZIG_TOOLCHAIN_HAVE" ] || return 0

    [ "$ZIG_TOOLCHAIN_HAVE" = "$ZIG_TOOLCHAIN_REQUIRED" ] && return 0
    return 1
}
