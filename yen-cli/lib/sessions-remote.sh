#!/bin/bash
# Remote transport for `yen sessions --host`: list and attach to the persistent
# sessions of another Mac over ssh (_docs/01-architecture.md -> Persistent sessions).
#
# The peer runs its own bundled `yen sessions`, so a remote session is always
# listed and attached with the zmx build that created it. Everything the peer
# sends back is untrusted: listing rows are parsed strictly and control
# characters never reach the terminal.
#
# Test hooks (never set by the app):
#   YEN_SSH_BIN                 ssh client to run (default /usr/bin/ssh)
#   YEN_SSH_RETRY_MAX_DELAY     reconnect backoff cap in seconds (default 30; 0 never sleeps)
#   YEN_REMOTE_APP              absolute path of the YEN.app to run on the peer,
#                               instead of /Applications and ~/Applications

# Exit codes the app and scripts tell apart. 1 and 2 keep their local meaning.
readonly REMOTE_EXIT_UNREACHABLE=10
readonly REMOTE_EXIT_FIRST_CONNECTION=11
readonly REMOTE_EXIT_NOT_INSTALLED=12
readonly REMOTE_EXIT_TOO_OLD=13
readonly REMOTE_EXIT_NO_SESSION=14
readonly REMOTE_EXIT_HOST_KEY_CHANGED=15

# The first line of `yen sessions list --porcelain`. Bump the number only for
# an incompatible change; readers ignore extra trailing fields within a version.
readonly PORCELAIN_HEADER=$'yen-sessions\t1'

readonly REMOTE_SSH_BIN="${YEN_SSH_BIN:-/usr/bin/ssh}"
# What the peer's login shell exits with when the fixed command finds no YEN.
readonly REMOTE_STATUS_NOT_INSTALLED=127

# [user@]host, where host is a DNS name without a trailing dot, an IPv4 address
# or an IPv6 address. No leading '-', no spaces, no shell or ssh metacharacters.
valid_remote_target() {
    local target="$1" user host label
    [[ -n "$target" && ${#target} -le 253 && "$target" != -* ]] || return 1
    host="$target"
    if [[ "$target" == *@* ]]; then
        user="${target%@*}"
        host="${target##*@}"
        [[ "$user" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$ ]] || return 1
    fi
    if [[ "$host" == *:* ]]; then
        [[ "$host" =~ ^[0-9A-Fa-f:]+$ && "$host" == *::* || "$host" =~ ^([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}$ ]] || return 1
        [[ ${#host} -le 39 ]] || return 1
        return 0
    fi
    label='[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    [[ "$host" =~ ^${label}(\.${label})*$ ]]
}

# One porcelain row from a local listing: id, state, started (Unix seconds or -),
# directory (absolute path or -). Tabs, newlines and other control characters
# in the directory become '?'.
porcelain_row() {
    local directory="${4:--}"
    directory="${directory//[[:cntrl:]]/?}"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$directory"
}

# Reads porcelain on stdin and writes only well-formed rows, re-sanitized.
# Returns 3 without a version 1 header, 1 when a row was dropped.
read_porcelain() {
    local header line id state started directory rest dropped=0
    IFS= read -r header || header=""
    [[ "$header" == "$PORCELAIN_HEADER" ]] || return 3
    printf '%s\n' "$PORCELAIN_HEADER"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r id state started directory rest <<< "$line"
        if [[ "$id" =~ $UUID_PATTERN && "$state" =~ ^(attached|detached|unreachable)$ \
            && "$started" =~ ^(-|[0-9]{1,12})$ && -n "$directory" ]]; then
            porcelain_row "$id" "$state" "$started" "$directory"
        else
            dropped=1
        fi
    done
    return "$dropped"
}

# The command line the peer's login shell runs. It is fixed text apart from the
# validated subcommand words, so the login shell (zsh, bash or fish) only sees
# `exec /bin/sh -c '<snippet>' yen-remote <words>`.
remote_command() {
    local apps='/Applications/YEN.app "$HOME/Applications/YEN.app"'
    if [[ -n "${YEN_REMOTE_APP:-}" ]]; then
        [[ "$YEN_REMOTE_APP" =~ ^/[A-Za-z0-9._/-]+$ ]] || usage_error "YEN_REMOTE_APP must be an absolute path"
        apps="$YEN_REMOTE_APP"
    fi
    local snippet='unset YEN_LIB YEN_RESOURCES YEN_CMD_DIR; for a in '"$apps"'; do y="$a/Contents/Resources/bin/yen"; [ -x "$y" ] && exec "$y" sessions "$@"; done; exit '"$REMOTE_STATUS_NOT_INSTALLED"
    printf "exec /bin/sh -c '%s' yen-remote %s" "$snippet" "$*"
}

# Options for every connection: keepalives so a dead link ends ssh instead of
# hanging, no connection sharing, no forwarding. Host key checking stays as the
# user configured it; YEN never relaxes it.
remote_ssh_options() {
    printf '%s\n' \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=3 \
        -o ControlMaster=no \
        -o ControlPath=none \
        -o ForwardAgent=no \
        -o ForwardX11=no \
        -o ClearAllForwardings=yes
}

# Replay ssh's stderr without the peer's control characters.
print_remote_errors() {
    LC_ALL=C sed -e $'s/\r$//' -e 's/[[:cntrl:]]/?/g' "$1" >&2
}

# Map ssh's own failure (exit 255) to a remote exit code from its stderr.
classify_ssh_failure() {
    local errors="$1"
    if grep -qE 'REMOTE HOST IDENTIFICATION HAS CHANGED|has changed and you have requested strict checking' "$errors"; then
        return "$REMOTE_EXIT_HOST_KEY_CHANGED"
    fi
    if grep -qE 'Host key verification failed|Permission denied|Too many authentication failures|No more authentication methods' "$errors"; then
        return "$REMOTE_EXIT_FIRST_CONNECTION"
    fi
    return "$REMOTE_EXIT_UNREACHABLE"
}

remote_failure_message() {
    local code="$1" target="$2"
    case "$code" in
        "$REMOTE_EXIT_UNREACHABLE") echo "yen sessions: cannot reach $target" ;;
        "$REMOTE_EXIT_FIRST_CONNECTION") echo "yen sessions: $target needs a first connection; run 'ssh $target' once to confirm its host key and sign in" ;;
        "$REMOTE_EXIT_NOT_INSTALLED") echo "yen sessions: YEN is not installed on $target" ;;
        "$REMOTE_EXIT_TOO_OLD") echo "yen sessions: YEN on $target does not support remote sessions; update YEN there" ;;
        "$REMOTE_EXIT_HOST_KEY_CHANGED") echo "yen sessions: the host key of $target has changed; YEN will not connect until known_hosts is fixed" ;;
    esac
}

remote_scratch=""
remote_cleanup() {
    [[ -n "$remote_scratch" ]] && rm -rf "$remote_scratch"
    remote_scratch=""
}

remote_make_scratch() {
    remote_scratch="$(mktemp -d "${TMPDIR:-/tmp}/yen-remote.XXXXXXXX")" || {
        yen_error "Could not create a temporary directory."
        exit 1
    }
    [[ "$remote_scratch" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
        yen_error "Unusable temporary directory: $remote_scratch"
        exit 1
    }
    trap remote_cleanup EXIT
}

# yen sessions list --host <target> [--porcelain]
remote_list() {
    local target="$1" porcelain="$2" status=0 parsed=0 code=0 line options=()
    remote_make_scratch
    while IFS= read -r line; do options+=("$line"); done < <(remote_ssh_options)
    "$REMOTE_SSH_BIN" "${options[@]}" -o BatchMode=yes -T -- "$target" "$(remote_command list --porcelain)" \
        < /dev/null > "$remote_scratch/out" 2> "$remote_scratch/err" || status=$?

    if [[ $status -eq 255 ]]; then
        classify_ssh_failure "$remote_scratch/err" || code=$?
        print_remote_errors "$remote_scratch/err"
        remote_failure_message "$code" "$target" >&2
        exit "$code"
    fi
    if [[ $status -eq $REMOTE_STATUS_NOT_INSTALLED ]]; then
        remote_failure_message "$REMOTE_EXIT_NOT_INSTALLED" "$target" >&2
        exit "$REMOTE_EXIT_NOT_INSTALLED"
    fi

    read_porcelain < "$remote_scratch/out" > "$remote_scratch/rows" || parsed=$?
    if [[ $parsed -eq 3 ]]; then
        remote_failure_message "$REMOTE_EXIT_TOO_OLD" "$target" >&2
        exit "$REMOTE_EXIT_TOO_OLD"
    fi
    if [[ $porcelain == 1 ]]; then
        cat "$remote_scratch/rows"
    else
        print_porcelain_table remote < "$remote_scratch/rows"
    fi
    if [[ $status -ne 0 || $parsed -ne 0 ]]; then
        echo "yen sessions: $target reported a listing error" >&2
        exit 1
    fi
    exit 0
}

# yen sessions attach --host <target> <id>
#
# Reconnects after a dropped link: ssh exits 255 both for a lost connection
# and for a connection that never succeeded, so a LocalCommand marker, which
# ssh runs only after authentication, tells the two apart. A first attempt
# that never connects is reported and not retried.
remote_attach() {
    local target="$1" id="$2" status code established=0 attempt=0 delay cap line options=()
    cap="${YEN_SSH_RETRY_MAX_DELAY:-30}"
    [[ "$cap" =~ ^[0-9]+$ ]] || usage_error "YEN_SSH_RETRY_MAX_DELAY must be a whole number of seconds"
    remote_make_scratch
    trap 'remote_cleanup; exit 130' INT
    trap 'remote_cleanup; exit 129' HUP
    trap 'remote_cleanup; exit 143' TERM
    while IFS= read -r line; do options+=("$line"); done < <(remote_ssh_options)
    options+=(-o PermitLocalCommand=yes -o "LocalCommand=/usr/bin/touch $remote_scratch/connected")

    while true; do
        rm -f "$remote_scratch/connected"
        status=0
        "$REMOTE_SSH_BIN" "${options[@]}" -t -- "$target" "$(remote_command attach "$id")" \
            2> "$remote_scratch/err" || status=$?
        print_remote_errors "$remote_scratch/err"
        if [[ -e "$remote_scratch/connected" ]]; then
            established=1
            attempt=0
        fi

        case "$status" in
            0) exit 0 ;;
            "$REMOTE_STATUS_NOT_INSTALLED")
                remote_failure_message "$REMOTE_EXIT_NOT_INSTALLED" "$target" >&2
                exit "$REMOTE_EXIT_NOT_INSTALLED"
                ;;
            255) ;;
            1)
                echo "yen sessions: no session $id on $target" >&2
                exit "$REMOTE_EXIT_NO_SESSION"
                ;;
            *) exit "$status" ;;
        esac

        code=0
        classify_ssh_failure "$remote_scratch/err" || code=$?
        if [[ $established -eq 0 || $code -ne $REMOTE_EXIT_UNREACHABLE ]]; then
            remote_failure_message "$code" "$target" >&2
            exit "$code"
        fi
        attempt=$((attempt + 1))
        delay=$((1 << (attempt > 6 ? 6 : attempt - 1)))
        [[ $delay -le $cap ]] || delay="$cap"
        echo "yen sessions: lost the connection to $target; reconnecting in ${delay}s (attempt $attempt, Ctrl-C to stop)" >&2
        sleep "$delay"
    done
}
