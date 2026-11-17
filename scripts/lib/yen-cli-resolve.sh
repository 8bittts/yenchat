#!/bin/bash
# Shared YEN CLI resolution helpers.
#
# The three customizations/ CLI utilities (diagnose-yen-cli.sh, fix-yen-cli.sh,
# clear-app-cache.sh) all need the same "where does `yen` actually resolve"
# logic. This centralizes it so the resolution rules live in one place.
#
# Source from a customizations/ script (which defines REPO_DIR = yen-terminal/):
#   source "$REPO_DIR/../scripts/lib/yen-cli-resolve.sh"
#
# resolve_cli_script reads the caller-set $REPO_DIR global (yen-terminal/) to
# probe the local zig-out build; every other function is self-contained.
#
# Public functions:
#   is_yen_shell                    - true inside a YEN-launched shell
#   detect_shell_type               - zsh | bash | unknown (from $SHELL)
#   detect_shell_config             - ~/.zshrc | ~/.bashrc | "" for the shell
#   derive_cli_from_command_path P  - map an on-PATH `yen` to its CLI script
#   resolve_cli_script              - first working bundled/installed CLI script
#   detect_runtime_command_path     - `type -P yen` (or empty)

is_yen_shell() {
    [[ "${TERM_PROGRAM:-}" == "yen" || -n "${YEN_RESOURCES_DIR:-}" || -n "${YEN_BIN_DIR:-}" ]]
}

detect_shell_type() {
    case "${SHELL:-}" in
        *zsh) echo "zsh" ;;
        *bash) echo "bash" ;;
        *) echo "unknown" ;;
    esac
}

detect_shell_config() {
    case "$(detect_shell_type)" in
        zsh) echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *) echo "" ;;
    esac
}

derive_cli_from_command_path() {
    local command_path="$1"
    local derived=""

    case "$command_path" in
        */Contents/Resources/bin/yen)
            derived="$command_path"
            ;;
        */Contents/MacOS/yen)
            derived="${command_path%/Contents/MacOS/yen}/Contents/Resources/bin/yen"
            ;;
        *)
            if [[ "$(basename "$command_path")" == "yen" ]]; then
                derived="$command_path"
            fi
            ;;
    esac

    [[ -n "$derived" && -x "$derived" ]] && echo "$derived"
}

resolve_cli_script() {
    local candidate=""
    local command_path=""
    local app_path=""
    local results=""

    if [[ -n "${YEN_BIN_DIR:-}" && -x "${YEN_BIN_DIR}/yen" ]]; then
        echo "${YEN_BIN_DIR}/yen"
        return 0
    fi

    if [[ -n "${YEN_RESOURCES_DIR:-}" ]]; then
        candidate="${YEN_RESOURCES_DIR}/bin/yen"
        [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }

        candidate="${YEN_RESOURCES_DIR%/*}/bin/yen"
        [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    command_path="$(type -P yen 2>/dev/null || true)"
    if [[ -n "$command_path" ]]; then
        candidate="$(derive_cli_from_command_path "$command_path")"
        [[ -n "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    candidate="$REPO_DIR/ghostty/zig-out/YEN.app/Contents/Resources/bin/yen"
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }

    candidate="/Applications/YEN.app/Contents/Resources/bin/yen"
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }

    candidate="$HOME/Applications/YEN.app/Contents/Resources/bin/yen"
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }

    if command -v mdfind >/dev/null 2>&1; then
        results="$(mdfind "kMDItemCFBundleIdentifier == 'com.yenchat.yen'" 2>/dev/null || true)"
        app_path="$(printf '%s\n' "$results" | grep '^/Applications/' | head -1)"
        [[ -z "$app_path" ]] && app_path="$(printf '%s\n' "$results" | head -1)"
        candidate="${app_path}/Contents/Resources/bin/yen"
        [[ -n "$app_path" && -x "$candidate" ]] && { echo "$candidate"; return 0; }
    fi

    return 1
}

detect_runtime_command_path() {
    type -P yen 2>/dev/null || true
}
