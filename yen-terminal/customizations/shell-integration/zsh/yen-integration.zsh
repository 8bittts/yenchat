# vim:ft=zsh
#
# YEN Zsh Integration (standalone)
#
# Derived from GPLv3 terminal shell-integration patterns (including Kitty lineage).
# This file is distributed under GPLv3.
#
# This is an autoloadable function. It's invoked automatically in shells
# directly spawned by YEN but not in any other shells. For example, running
# `exec zsh`, `sudo -E zsh`, `tmux`, or plain `zsh` will create a shell where
# yen-integration won't automatically run.

# File browser with cd-on-quit
# Launches the bundled file browser and changes to the last visited directory on exit
function y() {
    builtin emulate -L zsh
    setopt localtraps
    local resources="${YEN_RESOURCES_DIR}"
    if [[ -z "$resources" ]]; then
        builtin echo "y: YEN resources not found (not running in YEN terminal?)" >&2
        return 1
    fi

    # resources may be Resources or Resources/yen — match .zshenv fallback pattern
    local browse_bin="$resources/bin/browse"
    if [[ ! -x "$browse_bin" ]]; then
        browse_bin="${resources%/*}/bin/browse"
    fi
    if [[ ! -x "$browse_bin" ]]; then
        builtin echo "y: browse launcher not found at $browse_bin" >&2
        return 1
    fi

    local tmp
    if ! tmp="$(mktemp -t "yazi-cwd.XXXXXX")"; then
        return 1
    fi
    trap 'rm -f -- "$tmp"' INT TERM HUP

    "$browse_bin" "$@" --cwd-file="$tmp"
    local y_status=$?

    local cwd
    if cwd="$(<"$tmp")" && [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd" || true
    fi
    rm -f -- "$tmp"
    return $y_status
}

# Route app commands through the YEN CLI so they work even when PATH order
# prefers system binaries over the bundled YEN command set.
_yen_run_app_command() {
    builtin emulate -L zsh
    local app_cmd="$1"
    shift

    local yen_bin=""
    if [[ -n "$YEN_BIN_DIR" ]] && [[ -x "$YEN_BIN_DIR/yen" ]]; then
        yen_bin="$YEN_BIN_DIR/yen"
    else
        local resources="${YEN_RESOURCES_DIR}"
        if [[ -n "$resources" ]]; then
            yen_bin="$resources/bin/yen"
            if [[ ! -x "$yen_bin" ]]; then
                yen_bin="${resources%/*}/bin/yen"
            fi
        fi
    fi

    if [[ -x "$yen_bin" ]]; then
        "$yen_bin" "$app_cmd" "$@"
    else
        builtin echo "${app_cmd}: YEN CLI not found (YEN_BIN_DIR/YEN_RESOURCES_DIR unavailable)" >&2
        return 127
    fi
}

_yen_retired_companion_command() {
    builtin emulate -L zsh
    local retired_cmd="$1"
    builtin echo "${retired_cmd}: retired YEN companion command; use the dedicated app or current workflow instead" >&2
    return 127
}

btop() { _yen_run_app_command btop "$@"; }
monitor() { _yen_run_app_command monitor "$@"; }
fastfetch() { _yen_run_app_command fastfetch "$@"; }
fetch() { _yen_run_app_command fetch "$@"; }
fast() { _yen_run_app_command fast "$@"; }
bios() { _yen_run_app_command bios "$@"; }
resources() { _yen_run_app_command resources "$@"; }
browse() { _yen_run_app_command browse "$@"; }
files() { _yen_run_app_command browse "$@"; }
fm() { _yen_run_app_command browse "$@"; }
lazygit() { _yen_run_app_command lazygit "$@"; }
gitlazy() { _yen_run_app_command gitlazy "$@"; }
yengit() { _yen_run_app_command yengit "$@"; }
gityen() { _yen_run_app_command gityen "$@"; }
yenide() { _yen_run_app_command ide "$@"; }
yenwhy() { _yen_run_app_command ide explain --last "$@"; }
chat() { _yen_retired_companion_command chat; }
mail() { _yen_retired_companion_command mail; }
email() { _yen_retired_companion_command email; }
calendar() { _yen_retired_companion_command calendar; }
if ! alias '??' >/dev/null 2>&1; then
    alias '??'='noglob yenwhy'
fi
# Intentionally do NOT override `cal` (preserve system calendar utility).

_entrypoint() {
    builtin emulate -L zsh -o no_warn_create_global -o no_aliases

    [[ -o interactive ]]              || builtin return 0  # non-interactive shell
    (( ! $+_yen_state ))              || builtin return 0  # already initialized

    # We require zsh 5.1+ (released Sept 2015) for features like functions_source,
    # introspection arrays, and array pattern substitution.
    if ! { builtin autoload -- is-at-least 2>/dev/null && is-at-least 5.1; }; then
        builtin echo "Zsh ${ZSH_VERSION} is too old for YEN shell integration (5.1+ required)" >&2
        builtin return 1
    fi

    # 0: no OSC 133 [AC] marks have been written yet.
    # 1: the last written OSC 133 C has not been closed with D yet.
    # 2: none of the above.
    builtin typeset -gi _yen_state

    # Attempt to create a writable file descriptor to the TTY so that we can print
    # to the TTY later even when STDOUT is redirected.
    typeset -gi _yen_fd
    {
        builtin zmodload zsh/system && (( $+builtins[sysopen] )) && {
            { [[ -w     $TTY ]] && builtin sysopen -o cloexec -wu _yen_fd --     $TTY } ||
            { [[ -w /dev/tty ]] && builtin sysopen -o cloexec -wu _yen_fd -- /dev/tty }
        }
    } 2>/dev/null || (( _yen_fd = 1 ))

    # Defer initialization so that other zsh init files can configure the integration.
    builtin typeset -ag precmd_functions
    precmd_functions+=(_yen_deferred_init)
}

_yen_sync_term_program_version() {
    builtin emulate -L zsh -o no_warn_create_global -o no_aliases

    # .zshenv already parsed version.json with builtins — skip if cached
    if [[ -n "$YEN_VERSION" ]]; then
        builtin return 0
    fi

    local resources="${YEN_RESOURCES_DIR}"
    [[ -n "$resources" ]] || builtin return 0

    local version_file="$resources/version.json"
    [[ -f "$version_file" ]] || builtin return 0

    local version="" ver_line=""
    while IFS= builtin read -r ver_line; do
        case "$ver_line" in
            *'"version"'*)
                version="${ver_line#*\"version\"*:*\"}"
                version="${version%%\"*}"
                break
                ;;
        esac
    done < "$version_file"
    [[ -n "$version" ]] || builtin return 0

    builtin export TERM_PROGRAM="yen"
    builtin export TERM_PROGRAM_VERSION="$version"
    builtin export YEN_VERSION="$version"
}

_yen_deferred_init() {
    builtin emulate -L zsh -o no_warn_create_global -o no_aliases

    # Keep shell-visible terminal version on YEN marketing version from
    # bundled metadata, not upstream build provenance.
    _yen_sync_term_program_version

    # IDE shell behavior (S1 foundation) defaults.
    builtin : "${YEN_IDE_AUTO_CONTEXT:=1}"
    builtin : "${YEN_IDE_AUTO_HISTORY:=0}"
    builtin : "${YEN_IDE_AUTO_ENV:=0}"
    builtin typeset -g _YEN_IDE_LAST_ENV_ROOT="${_YEN_IDE_LAST_ENV_ROOT:-}"

    # Async IDE context detection — runs detect in background, applies on next precmd
    builtin typeset -g _YEN_IDE_DETECT_PREFIX="${TMPDIR:-/tmp}/yen-ide-detect-$$"
    builtin typeset -g _YEN_IDE_DETECT_FILE=""
    builtin typeset -g _YEN_IDE_DETECT_PID=""
    builtin typeset -gi _YEN_IDE_DETECT_SEQ=0

    _yen_ide_cleanup_detect_files() {
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        builtin setopt local_options nonomatch
        command rm -f -- "${_YEN_IDE_DETECT_PREFIX}"-*.env 2>/dev/null || true
    }
    _yen_ide_cleanup_detect_files

    _yen_ide_eval_exports() {
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        local payload="$1"
        local line=""
        local name=""

        while IFS= builtin read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && builtin continue
            [[ "$line" != *$'\r'* ]] || builtin return 1
            case "$line" in
                export\ *=*)
                    name="${line#export }"
                    name="${name%%=*}"
                    [[ "$name" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || builtin return 1
                    ;;
                *)
                    builtin return 1
                    ;;
            esac
        done <<< "$payload"

        eval "$payload"
    }

    _yen_ide_start_detect() {
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        [[ "${YEN_IDE_AUTO_CONTEXT:-1}" == "1" ]] || builtin return 0
        local stale_file="${_YEN_IDE_DETECT_FILE:-}"

        # Kill stale detect if still running
        if [[ -n "$_YEN_IDE_DETECT_PID" ]] && kill -0 "$_YEN_IDE_DETECT_PID" 2>/dev/null; then
            kill "$_YEN_IDE_DETECT_PID" 2>/dev/null
        fi
        [[ -n "$stale_file" ]] && command rm -f -- "$stale_file" 2>/dev/null

        _YEN_IDE_DETECT_SEQ=$((_YEN_IDE_DETECT_SEQ + 1))
        _YEN_IDE_DETECT_FILE="$(mktemp "${_YEN_IDE_DETECT_PREFIX}-${_YEN_IDE_DETECT_SEQ}.XXXXXX.env" 2>/dev/null)"
        if [[ -z "$_YEN_IDE_DETECT_FILE" ]]; then
            _YEN_IDE_DETECT_FILE="${_YEN_IDE_DETECT_PREFIX}-${_YEN_IDE_DETECT_SEQ}.env"
            : > "$_YEN_IDE_DETECT_FILE" || builtin return 0
        fi

        # Launch detect in background; use a per-run file so a canceled detect
        # cannot overwrite newer cwd context after the next prompt.
        ( _yen_run_app_command ide detect --cached --format env 2>/dev/null > "$_YEN_IDE_DETECT_FILE" ) &!
        _YEN_IDE_DETECT_PID=$!
    }

    _yen_ide_apply_detect() {
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        local detect_file="${_YEN_IDE_DETECT_FILE:-}"

        [[ -n "$detect_file" ]] || builtin return 0

        # Nothing pending
        if [[ ! -s "$detect_file" ]]; then
            if [[ -n "$_YEN_IDE_DETECT_PID" ]] && kill -0 "$_YEN_IDE_DETECT_PID" 2>/dev/null; then
                builtin return 0
            fi
            command rm -f -- "$detect_file" 2>/dev/null
            _YEN_IDE_DETECT_FILE=""
            _YEN_IDE_DETECT_PID=""
            builtin return 0
        fi

        # Still running — wait for next precmd
        if [[ -n "$_YEN_IDE_DETECT_PID" ]] && kill -0 "$_YEN_IDE_DETECT_PID" 2>/dev/null; then
            builtin return 0
        fi

        local detect_exports=""
        detect_exports="$(<"$detect_file")"
        if ! _yen_ide_eval_exports "$detect_exports"; then
            command rm -f -- "$detect_file" 2>/dev/null
            _YEN_IDE_DETECT_FILE=""
            _YEN_IDE_DETECT_PID=""
            builtin return 0
        fi
        command rm -f -- "$detect_file" 2>/dev/null
        _YEN_IDE_DETECT_FILE=""
        _YEN_IDE_DETECT_PID=""

        if [[ "${YEN_IDE_AUTO_ENV:-0}" == "1" ]] && [[ -n "${YEN_PROJECT_ROOT:-}" ]] && [[ "${_YEN_IDE_LAST_ENV_ROOT:-}" != "${YEN_PROJECT_ROOT}" ]]; then
            local env_exports=""
            env_exports=$(_yen_run_app_command ide env load "${YEN_PROJECT_ROOT}" 2>/dev/null) || env_exports=""
            [[ -n "${env_exports}" ]] && _yen_ide_eval_exports "${env_exports}"
            builtin typeset -g _YEN_IDE_LAST_ENV_ROOT="${YEN_PROJECT_ROOT}"
        fi
    }

    _yen_ide_refresh_context() {
        # Skip re-detection when still under the same project root
        if [[ -n "${YEN_PROJECT_ROOT:-}" ]] && [[ "$PWD" == "${YEN_PROJECT_ROOT}" || "$PWD" == "${YEN_PROJECT_ROOT}/"* ]]; then
            builtin return 0
        fi
        _yen_ide_start_detect
    }

    _yen_ide_cleanup() {
        if [[ -n "$_YEN_IDE_DETECT_PID" ]] && kill -0 "$_YEN_IDE_DETECT_PID" 2>/dev/null; then
            kill "$_YEN_IDE_DETECT_PID" 2>/dev/null || true
        fi
        _yen_ide_cleanup_detect_files
    }
    # Use zshexit hook array to avoid clobbering user EXIT traps
    builtin typeset -ag zshexit_functions
    zshexit_functions+=(_yen_ide_cleanup)

    # Enable semantic markup with OSC 133.
    _yen_precmd() {
        builtin local -i cmd_status=$?
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        builtin export YEN_IDE_LAST_STATUS="$cmd_status"

        # Don't write OSC 133 D when our precmd handler is invoked from zle.
        if ! builtin zle; then
            if (( _yen_state == 1 )); then
                builtin print -nu $_yen_fd '\e]133;D;'$cmd_status'\a'
                (( _yen_state = 2 ))
            elif (( _yen_state == 2 )); then
                builtin print -nu $_yen_fd '\e]133;D\a'
            fi
        fi

        builtin local mark1=$'%{\e]133;A;cl=line\a%}'
        if [[ -o prompt_percent ]]; then
            builtin typeset -g precmd_functions
            if [[ ${precmd_functions[-1]} == _yen_precmd ]]; then
                builtin local mark2=$'%{\e]133;A;k=s\a%}'
                builtin local markB=$'%{\e]133;B\a%}'
                [[ $PS1 == *$mark1* ]] || PS1=${mark1}${PS1}
                [[ $PS1 == *$markB* ]] || PS1=${PS1}${markB}
                if [[ $PS1 == ${mark1}$'\n'* ]]; then
                    builtin local rest=${PS1#${mark1}$'\n'}
                    if [[ $rest == *$'\n'* ]]; then
                        PS1=${mark1}$'\n'${rest//$'\n'/$'\n'${mark2}}
                    fi
                elif [[ $PS1 == *$'\n'* ]]; then
                    PS1=${PS1//$'\n'/$'\n'${mark2}}
                fi

                [[ $PS2 == *$mark2* ]] || PS2=${mark2}${PS2}
                [[ $PS2 == *$markB* ]] || PS2=${PS2}${markB}
                (( _yen_state = 2 ))
            else
                precmd_functions=(${precmd_functions:#_yen_precmd} _yen_precmd)
                if ! builtin zle; then
                    builtin print -rnu $_yen_fd -- $mark1[3,-3]
                    (( _yen_state = 2 ))
                fi
            fi
        elif ! builtin zle; then
            builtin print -rnu $_yen_fd -- $mark1[3,-3]
            (( _yen_state = 2 ))
        fi
    }

    _yen_preexec() {
        builtin emulate -L zsh -o no_warn_create_global -o no_aliases
        builtin export YEN_IDE_LAST_COMMAND="${1:-}"
        # Fallback must match the `:=0` initialization above. With `:-1` an
        # explicit `unset YEN_IDE_AUTO_HISTORY` silently re-enabled capture,
        # because `_yen_deferred_init` runs once per shell and never re-fires.
        if [[ "${YEN_IDE_AUTO_HISTORY:-0}" == "1" ]] && [[ "${1:-}" != "yen ide history add"* ]]; then
            _yen_run_app_command ide history add "${1:-}" >/dev/null 2>&1 || true
        fi

        PS1=${PS1//$'%{\e]133;A;cl=line\a%}'}
        PS1=${PS1//$'%{\e]133;A;k=s\a%}'}
        PS1=${PS1//$'%{\e]133;B\a%}'}
        PS2=${PS2//$'%{\e]133;A;k=s\a%}'}
        PS2=${PS2//$'%{\e]133;B\a%}'}

        builtin print -nu $_yen_fd '\e]133;C\a'
        (( _yen_state = 1 ))
    }

    # Enable reporting current working dir to terminal (kitty-shell-cwd format)
    _yen_report_pwd() { builtin print -nu $_yen_fd '\e]7;kitty-shell-cwd://'"$HOST""$PWD"'\a'; }
    chpwd_functions=(${chpwd_functions[@]} "_yen_report_pwd" "_yen_ide_refresh_context")
    functions[_yen_precmd]+="
        _yen_report_pwd
        _yen_ide_apply_detect"
    _yen_report_pwd
    _yen_ide_refresh_context

    if [[ "$YEN_SHELL_FEATURES" == *"title"* ]]; then
      functions[_yen_precmd]+="
          builtin print -rnu $_yen_fd \$'\\e]2;'\"\${(%):-%(4~|…/%3~|%~)}\"\$'\\a'"
      functions[_yen_preexec]+="
          builtin print -rnu $_yen_fd \$'\\e]2;'\"\${1//[[:cntrl:]]}\"\$'\\a'"
    fi

    if [[ "$YEN_SHELL_FEATURES" == *"cursor"* ]]; then
      _yen_zle_line_init _yen_zle_line_finish _yen_zle_keymap_select() {
          case ${KEYMAP-} in
              vicmd|visual) builtin print -nu "$_yen_fd" '\e[1 q';;
              *)            builtin print -nu "$_yen_fd" '\e[0 q';;
          esac
      }
      functions[_yen_preexec]+="
          builtin print -rnu $_yen_fd \$'\\e[0 q'"
    fi

    (( $+functions[_yen_zle_line_init] )) || _yen_zle_line_init() { builtin true; }
    functions[_yen_zle_line_init]="
        if [[ \$PS1 != *$'%{\\e]133;A'* ]]; then
            builtin print -nu \$_yen_fd '\\e]133;P;k=i\\a\\e]133;B\\a'
        fi
    "${functions[_yen_zle_line_init]}

    # Add YEN binary to PATH if the path feature is enabled
    if [[ "$YEN_SHELL_FEATURES" == *"path"* ]] && [[ -n "$YEN_BIN_DIR" ]]; then
      if [[ ":$PATH:" != *":$YEN_BIN_DIR:"* ]]; then
        builtin export PATH="$PATH:$YEN_BIN_DIR"
      fi
    fi

    # Sudo wrapper to preserve terminfo
    if [[ "$YEN_SHELL_FEATURES" == *"sudo"* ]] && [[ -n "$TERMINFO" ]]; then
      sudo() {
        builtin local sudo_has_sudoedit_flags="no"
        for arg in "$@"; do
          if [[ "$arg" == "-e" || $arg == "--edit" ]]; then
            sudo_has_sudoedit_flags="yes"
            builtin break
          fi
          if [[ "$arg" != -* && "$arg" != *=* ]]; then
            builtin break
          fi
        done
        if [[ "$sudo_has_sudoedit_flags" == "yes" ]]; then
          builtin command sudo "$@";
        else
          builtin command sudo --preserve-env=TERMINFO "$@";
        fi
      }
    fi

    # SSH Integration
    if [[ "$YEN_SHELL_FEATURES" == *ssh-* ]]; then
      ssh() {
        emulate -L zsh
        setopt local_options no_glob_subst

        local ssh_term ssh_opts ssh_cleanup_dir ssh_status
        ssh_term="xterm-256color"
        ssh_opts=()
        ssh_cleanup_dir=""

        if [[ "$YEN_SHELL_FEATURES" == *ssh-env* ]]; then
          ssh_opts+=(-o "SetEnv COLORTERM=truecolor")
          ssh_opts+=(-o "SendEnv TERM_PROGRAM TERM_PROGRAM_VERSION")
        fi

        if [[ "$YEN_SHELL_FEATURES" == *ssh-terminfo* ]]; then
          local ssh_user ssh_hostname

          while IFS=' ' read -r ssh_key ssh_value; do
            case "$ssh_key" in
              user) ssh_user="$ssh_value" ;;
              hostname) ssh_hostname="$ssh_value" ;;
            esac
            [[ -n "$ssh_user" && -n "$ssh_hostname" ]] && break
          done < <(command ssh -G "$@" 2>/dev/null)

          if [[ -n "$ssh_hostname" ]]; then
            local ssh_target="${ssh_user}@${ssh_hostname}"

            if "$YEN_BIN_DIR/yen" +ssh-cache --host="$ssh_target" >/dev/null 2>&1; then
              ssh_term="xterm-yen"
            elif (( $+commands[infocmp] )); then
              local ssh_terminfo ssh_cpath_dir ssh_cpath

              ssh_terminfo=$(infocmp -0 -x xterm-yen 2>/dev/null)

              if [[ -n "$ssh_terminfo" ]]; then
                print "Setting up xterm-yen terminfo on $ssh_hostname..." >&2

                ssh_cpath_dir=$(mktemp -d "/tmp/yen-ssh-$ssh_user.XXXXXX" 2>/dev/null) || ssh_cpath_dir="/tmp/yen-ssh-$ssh_user.$$"
                ssh_cpath="$ssh_cpath_dir/socket"
                ssh_cleanup_dir="$ssh_cpath_dir"

                # Trap INT/TERM/HUP so Ctrl+C during ssh doesn't orphan the temp dir
                trap 'command rm -rf -- "$ssh_cleanup_dir" >/dev/null 2>&1; trap - INT TERM HUP; return 130' INT TERM HUP

                if print "$ssh_terminfo" | command ssh "${ssh_opts[@]}" -o ControlMaster=yes -o ControlPath="$ssh_cpath" -o ControlPersist=60s "$@" '
                  infocmp xterm-yen >/dev/null 2>&1 && exit 0
                  command -v tic >/dev/null 2>&1 || exit 1
                  mkdir -p ~/.terminfo 2>/dev/null && tic -x - 2>/dev/null && exit 0
                  exit 1
                ' 2>/dev/null; then
                  ssh_term="xterm-yen"
                  ssh_opts+=(-o "ControlPath=$ssh_cpath")

                  "$YEN_BIN_DIR/yen" +ssh-cache --add="$ssh_target" >/dev/null 2>&1 || true
                else
                  print "Warning: Failed to install terminfo." >&2
                fi
              else
                print "Warning: Could not generate terminfo data." >&2
              fi
            else
              print "Warning: yen command not available for cache management." >&2
            fi
          fi
        fi

        TERM="$ssh_term" command ssh "${ssh_opts[@]}" "$@"
        ssh_status=$?

        if [[ -n "$ssh_cleanup_dir" ]]; then
          trap - INT TERM HUP
          command rm -rf -- "$ssh_cleanup_dir" >/dev/null 2>&1 || true
        fi

        return "$ssh_status"
      }
    fi

    # Hook up zle widgets
    builtin local hook func widget orig_widget flag
    for hook in line-init line-finish keymap-select; do
        func=_yen_zle_${hook/-/_}
        (( $+functions[$func] )) || builtin continue
        widget=zle-$hook
        if [[ $widgets[$widget] == user:azhw:* &&
              $+functions[add-zle-hook-widget] -eq 1 ]]; then
            add-zle-hook-widget $hook $func
        else
            if (( $+widgets[$widget] )); then
                orig_widget=._yen_orig_$widget
                builtin zle -A $widget $orig_widget
                if [[ $widgets[$widget] == user:* ]]; then
                    flag=
                else
                    flag=w
                fi
                functions[$func]+="
                    builtin zle $orig_widget -N$flag -- \"\$@\""
            fi
            builtin zle -N $widget $func
        fi
    done

    if (( $+functions[_yen_preexec] )); then
        builtin typeset -ag preexec_functions
        preexec_functions+=(_yen_preexec)
    fi

    builtin typeset -ag precmd_functions
    if (( $+functions[_yen_precmd] )); then
        precmd_functions=(${precmd_functions:/_yen_deferred_init/_yen_precmd})
        _yen_precmd
    else
        precmd_functions=(${precmd_functions:#_yen_deferred_init})
    fi

    builtin unfunction _yen_deferred_init
}

_entrypoint
