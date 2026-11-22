#!/bin/bash
# Check that a built engine binary resolves the legacy `copy-on-select = true`
# to `both`, so a hand-written or older config still reaches the system
# clipboard as well as the selection pasteboard.
#
# The binary reads its config from the user's Application Support folder, so
# each probe points CFFIXED_USER_HOME at a temporary home that holds one line.
# `false` must resolve to `none` there first: that proves the binary read the
# temporary config and not the real one, whose value would hide a regression.
#
# Usage: copy_on_select_compat_check <main-binary>
# Prints the failure and returns 1, or prints nothing and returns 0.

copy_on_select_resolved_value() {
    local binary="$1" value="$2" home config_dir resolved
    home="$(mktemp -d "${TMPDIR:-/tmp}/yen-copy-on-select.XXXXXX")" || return 1
    config_dir="$home/Library/Application Support/com.yenchat.yen"
    if ! mkdir -p "$config_dir"; then
        rm -rf "$home"
        return 1
    fi
    printf 'copy-on-select = %s\n' "$value" > "$config_dir/config.yen"
    resolved="$(CFFIXED_USER_HOME="$home" HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        YEN_CLI_SUPPORT_ACTIONS=1 "$binary" +show-config --no-pager --changes-only=false 2>/dev/null |
        sed -n 's/^copy-on-select = //p' | head -1)"
    rm -rf "$home"
    printf '%s' "$resolved"
}

copy_on_select_compat_check() {
    local binary="$1" control legacy
    if [ ! -x "$binary" ]; then
        echo "copy-on-select check has no executable binary at $binary"
        return 1
    fi
    control="$(copy_on_select_resolved_value "$binary" false)"
    if [ "$control" != "none" ]; then
        echo "copy-on-select check did not read its temporary config: false resolved to '${control:-nothing}', expected 'none'"
        return 1
    fi
    legacy="$(copy_on_select_resolved_value "$binary" true)"
    if [ "$legacy" != "both" ]; then
        echo "copy-on-select = true resolved to '${legacy:-nothing}', expected 'both'"
        return 1
    fi
    return 0
}
