# YEN Bash Integration (standalone)
#
# Derived from GPLv3 terminal shell-integration patterns (including Kitty lineage).
# This file is distributed under GPLv3.

# We need to be in interactive mode to proceed.
if [[ "$-" != *i* ]] ; then builtin return; fi

# File browser with cd-on-quit
# Launches the bundled file browser and changes to the last visited directory on exit
function y() {
    local resources="${YEN_RESOURCES_DIR}"
    if [[ -z "$resources" ]]; then
        builtin echo "y: YEN resources not found (not running in YEN terminal?)" >&2
        return 1
    fi

    # resources may be Resources or Resources/yen — match bash integration fallback pattern
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

    # Save existing traps (bash traps are global, not function-scoped)
    local _old_traps
    _old_traps=$(trap -p EXIT INT TERM HUP 2>/dev/null)
    trap 'rm -f -- "$tmp"' EXIT INT TERM HUP

    "$browse_bin" "$@" --cwd-file="$tmp"
    local y_status=$?

    local cwd
    if cwd="$(<"$tmp")" && [[ -n "$cwd" ]] && [[ "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd" || true
    fi
    rm -f -- "$tmp"

    # Restore previous traps
    trap - EXIT INT TERM HUP
    eval "$_old_traps"
    return "$y_status"
}

# When automatic shell integration is active, we were started in POSIX
# mode and need to manually recreate the bash startup sequence.
if [ -n "$YEN_BASH_INJECT" ]; then
  builtin declare __yen_bash_flags="$YEN_BASH_INJECT"
  builtin unset ENV YEN_BASH_INJECT

  if [[ -n "$YEN_BASH_ENV" ]]; then
    builtin export ENV=$YEN_BASH_ENV
    builtin unset YEN_BASH_ENV
  fi

  builtin set +o posix
  builtin shopt -u inherit_errexit 2>/dev/null

  if [[ -n "$YEN_BASH_UNEXPORT_HISTFILE" ]]; then
    builtin export -n HISTFILE
    builtin unset YEN_BASH_UNEXPORT_HISTFILE
  fi

  if builtin shopt -q login_shell; then
    if [[ $__yen_bash_flags != *"--noprofile"* ]]; then
      [ -r /etc/profile ] && builtin source "/etc/profile"
      for __yen_rcfile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [ -r "$__yen_rcfile" ] && { builtin source "$__yen_rcfile"; break; }
      done
    fi
  else
    if [[ $__yen_bash_flags != *"--norc"* ]]; then
      for __yen_rcfile in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc; do
        [ -r "$__yen_rcfile" ] && { builtin source "$__yen_rcfile"; break; }
      done
      if [[ -z "$YEN_BASH_RCFILE" ]]; then YEN_BASH_RCFILE="$HOME/.bashrc"; fi
      [ -r "$YEN_BASH_RCFILE" ] && builtin source "$YEN_BASH_RCFILE"
    fi
  fi

  builtin unset __yen_rcfile
  builtin unset __yen_bash_flags
  builtin unset YEN_BASH_RCFILE
fi

# ============================================================================
# YEN Customizations: Welcome banner and PATH setup
# ============================================================================

function __yen_sync_term_program_version {
    # Skip if .zshenv or prior integration already set it
    [[ -n "$YEN_VERSION" ]] && return 0

    local resources="${YEN_RESOURCES_DIR}"
    [[ -n "$resources" ]] || return 0

    local version_file="$resources/version.json"
    [[ -f "$version_file" ]] || return 0

    local version="" ver_line=""
    while IFS= read -r ver_line; do
        case "$ver_line" in
            *'"version"'*)
                version="${ver_line#*\"version\"*:*\"}"
                version="${version%%\"*}"
                break
                ;;
        esac
    done < "$version_file"
    [[ -n "$version" ]] || return 0

    export TERM_PROGRAM="yen"
    export TERM_PROGRAM_VERSION="$version"
    export YEN_VERSION="$version"
}

__yen_resources_dir="${YEN_RESOURCES_DIR}"
if [[ -n "$__yen_resources_dir" ]]; then
    # Add bundled binaries to PATH
    __yen_bin_dir="$__yen_resources_dir/bin"
    if [[ ! -d "$__yen_bin_dir" ]]; then
        __yen_bin_dir="${__yen_resources_dir%/*}/bin"
    fi
    if [[ -d "$__yen_bin_dir" ]] && [[ ":$PATH:" != *":$__yen_bin_dir:"* ]]; then
        builtin export PATH="$__yen_bin_dir:$PATH"
    fi
    builtin unset __yen_bin_dir
fi

# Keep shell-visible terminal version on YEN marketing version from bundled
# metadata, not upstream build provenance.
__yen_sync_term_program_version

# Source welcome banner
if [[ -n "$__yen_resources_dir" && -z "$YEN_WELCOME_SHOWN" ]]; then
    __yen_welcome="$__yen_resources_dir/shell-integration/yen-welcome.sh"
    if [[ -f "$__yen_welcome" ]]; then
        builtin source "$__yen_welcome"
    fi
    builtin unset __yen_welcome
fi

builtin unset __yen_resources_dir
builtin unset -f __yen_sync_term_program_version

# Route app commands through the YEN CLI so they work even when PATH order
# prefers system binaries over the bundled YEN command set.
function _yen_run_app_command {
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

function _yen_retired_companion_command {
    local retired_cmd="$1"
    builtin echo "${retired_cmd}: retired YEN companion command; use the dedicated app or current workflow instead" >&2
    return 127
}

function btop { _yen_run_app_command btop "$@"; }
function monitor { _yen_run_app_command monitor "$@"; }
function fastfetch { _yen_run_app_command fastfetch "$@"; }
function fetch { _yen_run_app_command fetch "$@"; }
function bios { _yen_run_app_command bios "$@"; }
function resources { _yen_run_app_command resources "$@"; }
function browse { _yen_run_app_command browse "$@"; }
function files { _yen_run_app_command browse "$@"; }
function fm { _yen_run_app_command browse "$@"; }
function lazygit { _yen_run_app_command lazygit "$@"; }
function gitlazy { _yen_run_app_command gitlazy "$@"; }
function yengit { _yen_run_app_command yengit "$@"; }
function gityen { _yen_run_app_command gityen "$@"; }
function yenide { _yen_run_app_command ide "$@"; }
function yenwhy { _yen_run_app_command ide explain --last "$@"; }
function chat { _yen_retired_companion_command chat; }
function mail { _yen_retired_companion_command mail; }
function email { _yen_retired_companion_command email; }
function calendar { _yen_retired_companion_command calendar; }
if ! alias '??' >/dev/null 2>&1; then
  alias '??'='yenwhy'
fi
# Intentionally do NOT override `cal` (preserve system calendar utility).

# ============================================================================
# Terminal Integration Features
# ============================================================================

: "${YEN_IDE_AUTO_CONTEXT:=1}"
: "${YEN_IDE_AUTO_HISTORY:=0}"
: "${YEN_IDE_AUTO_ENV:=0}"

# Add YEN binary to PATH if the path feature is enabled
if [[ "$YEN_SHELL_FEATURES" == *"path"* && -n "$YEN_BIN_DIR" ]]; then
  if [[ ":$PATH:" != *":$YEN_BIN_DIR:"* ]]; then
    export PATH="$PATH:$YEN_BIN_DIR"
  fi
fi

# Sudo wrapper to preserve terminfo
if [[ "$YEN_SHELL_FEATURES" == *"sudo"* && -n "$TERMINFO" ]]; then
  function sudo {
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
  function ssh() {
    builtin local ssh_term ssh_opts ssh_cleanup_dir ssh_status
    ssh_term="xterm-256color"
    ssh_opts=()
    ssh_cleanup_dir=""

    if [[ "$YEN_SHELL_FEATURES" == *ssh-env* ]]; then
      ssh_opts+=(-o "SetEnv COLORTERM=truecolor")
      ssh_opts+=(-o "SendEnv TERM_PROGRAM TERM_PROGRAM_VERSION")
    fi

    if [[ "$YEN_SHELL_FEATURES" == *ssh-terminfo* ]]; then
      builtin local ssh_user ssh_hostname

      while IFS=' ' read -r ssh_key ssh_value; do
        case "$ssh_key" in
          user) ssh_user="$ssh_value" ;;
          hostname) ssh_hostname="$ssh_value" ;;
        esac
        [[ -n "$ssh_user" && -n "$ssh_hostname" ]] && break
      done < <(builtin command ssh -G "$@" 2>/dev/null)

      if [[ -n "$ssh_hostname" ]]; then
        builtin local ssh_target="${ssh_user}@${ssh_hostname}"

        if "$YEN_BIN_DIR/yen" +ssh-cache --host="$ssh_target" >/dev/null 2>&1; then
          ssh_term="xterm-yen"
        elif builtin command -v infocmp >/dev/null 2>&1; then
          builtin local ssh_terminfo ssh_cpath_dir ssh_cpath

          ssh_terminfo=$(infocmp -0 -x xterm-yen 2>/dev/null)

          if [[ -n "$ssh_terminfo" ]]; then
            builtin echo "Setting up xterm-yen terminfo on $ssh_hostname..." >&2

            ssh_cpath_dir=$(mktemp -d "/tmp/yen-ssh-$ssh_user.XXXXXX" 2>/dev/null) || ssh_cpath_dir="/tmp/yen-ssh-$ssh_user.$$"
            ssh_cpath="$ssh_cpath_dir/socket"
            ssh_cleanup_dir="$ssh_cpath_dir"

            # Trap INT/TERM/HUP so Ctrl+C during ssh doesn't orphan the temp dir
            builtin trap 'command rm -rf -- "$ssh_cleanup_dir" >/dev/null 2>&1; builtin trap - INT TERM HUP; return 130' INT TERM HUP

            if builtin echo "$ssh_terminfo" | builtin command ssh -o ControlMaster=yes -o ControlPath="$ssh_cpath" -o ControlPersist=60s "$@" '
              infocmp xterm-yen >/dev/null 2>&1 && exit 0
              command -v tic >/dev/null 2>&1 || exit 1
              mkdir -p ~/.terminfo 2>/dev/null && tic -x - 2>/dev/null && exit 0
              exit 1
            ' 2>/dev/null; then
              ssh_term="xterm-yen"
              ssh_opts+=(-o "ControlPath=$ssh_cpath")

              "$YEN_BIN_DIR/yen" +ssh-cache --add="$ssh_target" >/dev/null 2>&1 || true
            else
              builtin echo "Warning: Failed to install terminfo." >&2
            fi
          else
            builtin echo "Warning: Could not generate terminfo data." >&2
          fi
        else
          builtin echo "Warning: yen command not available for cache management." >&2
        fi
      fi
    fi

    TERM="$ssh_term" builtin command ssh "${ssh_opts[@]}" "$@"
    ssh_status=$?

    if [[ -n "$ssh_cleanup_dir" ]]; then
      builtin trap - INT TERM HUP
      command rm -rf -- "$ssh_cleanup_dir" >/dev/null 2>&1 || true
    fi

    return "$ssh_status"
  }
fi

# State tracking
_yen_executing=""
_yen_last_reported_cwd=""
_yen_ide_last_env_root=""
_yen_ide_detect_prefix="${TMPDIR:-/tmp}/yen-ide-detect-$$"
_yen_ide_detect_file=""
_yen_ide_detect_pid=""
_yen_ide_detect_seq=0

function __yen_ide_cleanup_detect_files() {
    command rm -f -- "${_yen_ide_detect_prefix}"-*.env 2>/dev/null || true
}
__yen_ide_cleanup_detect_files

function __yen_ide_eval_exports() {
    local payload="$1"
    local line=""
    local name=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" != *$'\r'* ]] || return 1
        case "$line" in
            export\ *=*)
                name="${line#export }"
                name="${name%%=*}"
                [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
                ;;
            *)
                return 1
                ;;
        esac
    done <<< "$payload"

    eval "$payload"
}

function __yen_ide_start_detect() {
    [[ "${YEN_IDE_AUTO_CONTEXT:-1}" == "1" ]] || return 0
    local stale_file="${_yen_ide_detect_file}"

    # Kill stale detect if still running
    if [[ -n "$_yen_ide_detect_pid" ]] && kill -0 "$_yen_ide_detect_pid" 2>/dev/null; then
        kill "$_yen_ide_detect_pid" 2>/dev/null
    fi
    [[ -n "$stale_file" ]] && command rm -f -- "$stale_file" 2>/dev/null

    _yen_ide_detect_seq=$((_yen_ide_detect_seq + 1))
    _yen_ide_detect_file="$(mktemp "${_yen_ide_detect_prefix}-${_yen_ide_detect_seq}.XXXXXX.env" 2>/dev/null)"
    if [[ -z "$_yen_ide_detect_file" ]]; then
        _yen_ide_detect_file="${_yen_ide_detect_prefix}-${_yen_ide_detect_seq}.env"
        : > "$_yen_ide_detect_file" || return 0
    fi

    # Launch detect in background; toggle monitor mode off to suppress
    # [1] PID / [1]+ Done job notifications in interactive shells. Use a
    # per-run file so a canceled detect cannot overwrite newer cwd context.
    local _yen_had_monitor=""
    case "$-" in *m*) _yen_had_monitor=1 ;; esac
    builtin set +m 2>/dev/null
    ( _yen_run_app_command ide detect --cached --format env 2>/dev/null > "$_yen_ide_detect_file" ) &
    _yen_ide_detect_pid=$!
    builtin disown "$_yen_ide_detect_pid" 2>/dev/null || true
    [[ -n "$_yen_had_monitor" ]] && builtin set -m 2>/dev/null
}

function __yen_ide_apply_detect() {
    local detect_file="${_yen_ide_detect_file}"

    [[ -n "$detect_file" ]] || return 0

    # Nothing pending
    if [[ ! -s "$detect_file" ]]; then
        if [[ -n "$_yen_ide_detect_pid" ]] && kill -0 "$_yen_ide_detect_pid" 2>/dev/null; then
            return 0
        fi
        command rm -f -- "$detect_file" 2>/dev/null
        _yen_ide_detect_file=""
        _yen_ide_detect_pid=""
        return 0
    fi

    # Still running — wait for next precmd
    if [[ -n "$_yen_ide_detect_pid" ]] && kill -0 "$_yen_ide_detect_pid" 2>/dev/null; then
        return 0
    fi

    local detect_exports=""
    detect_exports="$(<"$detect_file")"
    if ! __yen_ide_eval_exports "$detect_exports"; then
        command rm -f -- "$detect_file" 2>/dev/null
        _yen_ide_detect_file=""
        _yen_ide_detect_pid=""
        return 0
    fi
    command rm -f -- "$detect_file" 2>/dev/null
    _yen_ide_detect_file=""
    _yen_ide_detect_pid=""

    if [[ "${YEN_IDE_AUTO_ENV:-0}" == "1" && -n "${YEN_PROJECT_ROOT:-}" && "${_yen_ide_last_env_root}" != "${YEN_PROJECT_ROOT}" ]]; then
      local env_exports=""
      env_exports=$(_yen_run_app_command ide env load "${YEN_PROJECT_ROOT}" 2>/dev/null) || env_exports=""
      [[ -n "${env_exports}" ]] && __yen_ide_eval_exports "${env_exports}"
      _yen_ide_last_env_root="${YEN_PROJECT_ROOT}"
    fi
}

function __yen_ide_refresh_context() {
    # Skip re-detection when still under the same project root
    if [[ -n "${YEN_PROJECT_ROOT:-}" ]] && [[ "$PWD" == "${YEN_PROJECT_ROOT}" || "$PWD" == "${YEN_PROJECT_ROOT}/"* ]]; then
        return 0
    fi
    __yen_ide_start_detect
}

function __yen_ide_cleanup() {
    if [[ -n "$_yen_ide_detect_pid" ]] && kill -0 "$_yen_ide_detect_pid" 2>/dev/null; then
        kill "$_yen_ide_detect_pid" 2>/dev/null || true
    fi
    __yen_ide_cleanup_detect_files
}

# Chain cleanup onto any existing EXIT trap instead of overwriting
_yen_prev_exit_trap=$(builtin trap -p EXIT 2>/dev/null | command sed "s/^trap -- '//;s/' EXIT$//" || true)
if [[ -n "$_yen_prev_exit_trap" ]]; then
    builtin trap "${_yen_prev_exit_trap}; __yen_ide_cleanup" EXIT
else
    builtin trap '__yen_ide_cleanup' EXIT
fi
builtin unset _yen_prev_exit_trap

function __yen_precmd() {
    local ret="${1:-$?}"
    builtin export YEN_IDE_LAST_STATUS="$ret"
    if test "$_yen_executing" != "0"; then
      _YEN_SAVE_PS1="$PS1"
      _YEN_SAVE_PS2="$PS2"

      # Marks. Start each prompt with A so redraws keep the prompt contract,
      # then terminate the input area with B for click-to-move semantics.
      PS1='\[\e]133;A;redraw=last;cl=line;aid='"$BASHPID"'\a\]'$PS1'\[\e]133;B\a\]'
      PS2='\[\e]133;A;k=s\a\]'$PS2'\[\e]133;B\a\]'

      # bash doesn't redraw the leading lines in a multiline prompt, so
      # explicitly mark each continuation line as a secondary prompt.
      if [[ "${PS1}" == *"\n"* || "${PS1}" == *$'\n'* ]]; then
        builtin local __yen_mark=$'\\[\\e]133;A;k=s\\a\\]'
        PS1="${PS1//$'\n'/$'\n'$__yen_mark}"
        PS1="${PS1//\\n/\\n$__yen_mark}"
      fi

      # Cursor
      if [[ "$YEN_SHELL_FEATURES" == *"cursor"* ]]; then
        [[ "$PS1" != *'\[\e[0 q\]'* ]] && PS1=$PS1'\[\e[0 q\]'
        [[ "$PS0" != *'\[\e[0 q\]'* ]] && PS0=$PS0'\[\e[0 q\]'
      fi

      # Title (working directory)
      if [[ "$YEN_SHELL_FEATURES" == *"title"* ]]; then
        PS1=$PS1'\[\e]2;\w\a\]'
      fi
    fi

    if test "$_yen_executing" != ""; then
      builtin printf "\e]133;D;%s;aid=%s\a" "$ret" "$BASHPID"
    fi

    # Apply any completed async detect results
    __yen_ide_apply_detect

    # Report cwd changes
    if [[ "$_yen_last_reported_cwd" != "$PWD" ]]; then
      _yen_last_reported_cwd="$PWD"
      builtin printf "\e]7;kitty-shell-cwd://%s%s\a" "$HOSTNAME" "$PWD"
      __yen_ide_refresh_context
    fi

    _yen_executing=0
}

function __yen_preexec() {
    builtin local cmd="$1"
    builtin export YEN_IDE_LAST_COMMAND="$cmd"
    # Fallback must match the `:=0` initialization above. With `:-1` an explicit
    # `unset YEN_IDE_AUTO_HISTORY` silently re-enabled capture, because
    # `_yen_deferred_init` runs once per shell and never re-fires.
    if [[ -n "$cmd" && "${YEN_IDE_AUTO_HISTORY:-0}" == "1" && "$cmd" != "yen ide history add"* ]]; then
      _yen_run_app_command ide history add "$cmd" >/dev/null 2>&1 || true
    fi

    PS1="$_YEN_SAVE_PS1"
    PS2="$_YEN_SAVE_PS2"

    # Title (current command)
    if [[ -n $cmd && "$YEN_SHELL_FEATURES" == *"title"* ]]; then
      builtin printf "\e]2;%s\a" "${cmd//[[:cntrl:]]}"
    fi

    builtin printf "\e]133;C;\a"
    _yen_executing=1
}

function __yen_append_unique_hook {
    builtin local hook_array_name="$1"
    builtin local hook_fn="$2"
    builtin local existing=""

    eval "for existing in \"\${${hook_array_name}[@]}\"; do
      if [[ \"\$existing\" == \"$hook_fn\" ]]; then
        return 0
      fi
    done"

    eval "${hook_array_name}+=(\"$hook_fn\")"
}

if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  __yen_preexec_hook() {
    builtin local cmd
    cmd=$(LC_ALL=C HISTTIMEFORMAT='' builtin history 1)
    cmd="${cmd#*[[:digit:]][* ] }"
    [[ -n "$cmd" ]] && __yen_preexec "$cmd"
  }

  if [[ -z "${__yen_ps0+x}" ]]; then
    if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3) )); then
      builtin readonly __yen_ps0='${ __yen_preexec_hook; }'
    else
      builtin readonly __yen_ps0='$(__yen_preexec_hook >/dev/tty)'
    fi
  fi

  __yen_hook() {
    builtin local ret=$?
    __yen_precmd "$ret"
    if [[ "$PS0" != *"$__yen_ps0"* ]]; then
      PS0=$PS0"${__yen_ps0}"
    fi
  }

  if [[ ";${PROMPT_COMMAND[*]:-};" != *";__yen_hook;"* ]]; then
    if [[ -z "${PROMPT_COMMAND[*]}" ]]; then
      if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
        PROMPT_COMMAND=(__yen_hook)
      else
        PROMPT_COMMAND="__yen_hook"
      fi
    elif [[ $(builtin declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a "* ]]; then
      PROMPT_COMMAND+=(__yen_hook)
    else
      [[ "${PROMPT_COMMAND}" =~ \;[[:space:]]*$ ]] || PROMPT_COMMAND+=";"
      PROMPT_COMMAND+=" __yen_hook"
    fi
  fi
else
  # Import bash-preexec for the older bash 3.2 path shipped by macOS.
  builtin source "$(dirname -- "${BASH_SOURCE[0]}")/bash-preexec.sh"
  __yen_append_unique_hook preexec_functions "__yen_preexec"
  __yen_append_unique_hook precmd_functions "__yen_precmd"
fi

__yen_ide_refresh_context
