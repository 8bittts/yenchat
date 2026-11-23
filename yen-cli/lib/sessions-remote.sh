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
#
# Set by the app for a remote pane's CLI, never by a user:
#   YEN_REMOTE_RECONNECT_MARK   1: write the reconnecting mark to the pane
#                               (remote_mark below)

# Exit codes the app and scripts tell apart. 1 and 2 keep their local meaning.
readonly REMOTE_EXIT_UNREACHABLE=10
readonly REMOTE_EXIT_FIRST_CONNECTION=11
readonly REMOTE_EXIT_NOT_INSTALLED=12
readonly REMOTE_EXIT_TOO_OLD=13
readonly REMOTE_EXIT_NO_SESSION=14
readonly REMOTE_EXIT_HOST_KEY_CHANGED=15
readonly REMOTE_EXIT_KEY_REQUIRED=16

# The first line of `yen sessions list --porcelain`. Bump the number only for
# an incompatible change; readers ignore extra trailing fields within a version.
readonly PORCELAIN_HEADER=$'yen-sessions\t1'

readonly REMOTE_SSH_BIN="${YEN_SSH_BIN:-/usr/bin/ssh}"
# What the peer's login shell exits with when the fixed command finds no YEN.
readonly REMOTE_STATUS_NOT_INSTALLED=127

# [user@]host, where host is a DNS name without a trailing dot, an IPv4 address
# or an IPv6 address. No leading '-', no spaces, no shell or ssh metacharacters.
valid_remote_target() {
    # Byte-wise ranges: under another locale [A-Za-z] can match accented letters.
    local LC_ALL=C target="$1" user host label
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
    local LC_ALL=C directory="${4:--}"
    directory="${directory//[[:cntrl:]]/?}"
    # C1 controls (U+0080-U+009F) in UTF-8; some terminals act on them.
    directory="${directory//$'\xc2'[$'\x80'-$'\x9f']/?}"
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$directory"
}

# Reads porcelain on stdin and writes only well-formed rows, re-sanitized.
# Lines before the header are skipped, because a peer's login shell can print
# a banner first; every row after it is strict. Returns 3 without a version 1
# header, 1 when a row was dropped.
read_porcelain() {
    local LC_ALL=C header="" line id state started directory rest dropped=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$PORCELAIN_HEADER" ]]; then
            header="$line"
            break
        fi
    done
    [[ -n "$header" ]] || return 3
    printf '%s\n' "$PORCELAIN_HEADER"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r id state started directory rest <<< "$line"
        if valid_session_id "$id" && [[ "$state" =~ ^(attached|detached|unreachable)$ \
            && "$started" =~ ^(-|[0-9]{1,12})$ && -n "$directory" ]]; then
            porcelain_row "$id" "$state" "$started" "$directory"
        else
            dropped=1
        fi
    done
    return "$dropped"
}

# The command line the peer's login shell runs. It is fixed text apart from the
# validated subcommand words, so the login shell only sees
# `exec /bin/sh -c '<snippet>' yen-remote <words>`.
#
# Some transports drop the peer's exit status: Tailscale SSH on a macOS peer
# runs every command under macOS login, which exits 0 whatever the command's
# status was. So the peer reports its status in-band:
# - list ends its stderr with one `yen-remote-status <n>` line, which
#   take_remote_status reads and removes;
# - attach shares a terminal with the session, so a line cannot be read back.
#   When the snippet's parent is login, a failed attach prints why and waits
#   for Return on the peer, so the message stays on screen although ssh
#   reports 0. Under any other parent it execs the peer's CLI as before, so
#   its status reaches the CLI and the app holds the pane locally.
remote_command() {
    local verb="$1" apps='/Applications/YEN.app "$HOME/Applications/YEN.app"' find snippet
    if [[ -n "${YEN_REMOTE_APP:-}" ]]; then
        [[ "$YEN_REMOTE_APP" =~ ^/[A-Za-z0-9._/-]+$ ]] || usage_error "YEN_REMOTE_APP must be an absolute path"
        apps="$YEN_REMOTE_APP"
    fi
    find='unset YEN_LIB YEN_RESOURCES YEN_CMD_DIR ZMX_SESSION; y=; for a in '"$apps"'; do [ -x "$a/Contents/Resources/bin/yen" ] && { y="$a/Contents/Resources/bin/yen"; break; }; done; '
    if [[ "$verb" == list ]]; then
        snippet="$find"'s='"$REMOTE_STATUS_NOT_INSTALLED"'; if [ -n "$y" ]; then "$y" sessions "$@"; s=$?; fi; printf "\n'"$REMOTE_STATUS_LINE"' %s\n" "$s" >&2; exit "$s"'
    else
        snippet="$find"'case "$(/bin/ps -o comm= -p "$PPID" 2>/dev/null)" in */login|login) ;; *) [ -n "$y" ] && exec "$y" sessions "$@"; exit '"$REMOTE_STATUS_NOT_INSTALLED"' ;; esac; s='"$REMOTE_STATUS_NOT_INSTALLED"'; if [ -n "$y" ]; then "$y" sessions "$@"; s=$?; fi; [ "$s" -eq 0 ] || [ "$s" -eq 130 ] && exit "$s"; if [ "$s" -eq '"$REMOTE_STATUS_NOT_INSTALLED"' ] && [ -z "$y" ]; then printf "\nyen sessions: YEN is not installed on the remote Mac; press Return to close\n" >&2; else printf "\nyen sessions: the session did not attach on the remote Mac (status %s); press Return to close\n" "$s" >&2; fi; read -r _; exit "$s"'
    fi
    printf "exec /bin/sh -c '%s' yen-remote %s" "$snippet" "$*"
}

# The last line of a listing's stderr when the peer's snippet ran.
readonly REMOTE_STATUS_LINE=yen-remote-status

# Print the peer's status from the last status line of a listing's stderr, if
# any, and remove every status line, and the blank line the snippet puts
# before its own, so neither is ever replayed. A peer can print such lines
# itself, but the snippet's comes last, so a peer can only misreport its own
# outcome, which it could already do with its exit status.
take_remote_status() {
    local errors="$1" status
    status="$(LC_ALL=C sed -n -E "s/^${REMOTE_STATUS_LINE} (0|[1-9][0-9]{0,2})\$/\1/p" "$errors" | tail -n 1)"
    LC_ALL=C awk -v line="$REMOTE_STATUS_LINE" '
        $0 ~ "^" line " [0-9]+$" { pending = 0; next }
        { if (pending) print ""; pending = 0 }
        /^$/ { pending = 1; next }
        { print }
        END { if (pending) print "" }
    ' "$errors" > "$errors.replay" && mv "$errors.replay" "$errors"
    [[ -n "$status" && $status -le 255 ]] && printf '%s\n' "$status"
    return 0
}

# Options for every connection: keepalives so a dead link ends ssh instead of
# hanging, no connection sharing, no forwarding, and no RemoteCommand from the
# user's config, which would make ssh refuse the fixed command. Host key
# checking stays as the user configured it; YEN never relaxes it. ProxyJump
# and the rest of the user's config still apply.
remote_ssh_options() {
    printf '%s\n' \
        -o RemoteCommand=none \
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
    LC_ALL=C sed -e $'s/\r$//' -e 's/[[:cntrl:]]/?/g' -e $'s/\xc2[\x80-\x9f]/?/g' "$1" >&2
}

# Map ssh's own failure (exit 255) to a remote exit code from its stderr.
classify_ssh_failure() {
    local errors="$1"
    if grep -qE 'REMOTE HOST IDENTIFICATION HAS CHANGED|has changed and you have requested strict checking' "$errors"; then
        return "$REMOTE_EXIT_HOST_KEY_CHANGED"
    fi
    # ssh checks the host key before it signs in, so an unknown key on a
    # password-only peer reports 11 first and 16 once the key is trusted.
    if grep -qE 'Host key verification failed' "$errors"; then
        return "$REMOTE_EXIT_FIRST_CONNECTION"
    fi
    # BatchMode never prompts, so a peer that offers only a password fails here.
    if grep -qE 'Permission denied|Too many authentication failures|No more authentication methods' "$errors"; then
        return "$REMOTE_EXIT_KEY_REQUIRED"
    fi
    return "$REMOTE_EXIT_UNREACHABLE"
}

remote_failure_message() {
    local code="$1" target="$2"
    case "$code" in
        "$REMOTE_EXIT_UNREACHABLE") echo "yen sessions: cannot reach $target" ;;
        "$REMOTE_EXIT_FIRST_CONNECTION") echo "yen sessions: $target needs its host key confirmed; run 'ssh $target' once and accept the key" ;;
        "$REMOTE_EXIT_KEY_REQUIRED") echo "yen sessions: $target asks for a password; YEN signs in only with an SSH key that works without a prompt; run 'ssh-copy-id $target' once" ;;
        "$REMOTE_EXIT_NOT_INSTALLED") echo "yen sessions: YEN is not installed on $target" ;;
        "$REMOTE_EXIT_TOO_OLD") echo "yen sessions: YEN on $target does not support remote sessions; update YEN there" ;;
        "$REMOTE_EXIT_HOST_KEY_CHANGED") echo "yen sessions: the host key of $target has changed; YEN will not connect until known_hosts is fixed" ;;
    esac
}

# The reconnecting mark (_docs/01-architecture.md -> Reconnecting mark). A
# remote pane's CLI writes a terminal progress report to its own pane while it
# waits to reconnect: OSC 9;4;4;0 (paused at 0%), a value YEN reserves for
# this, cleared with OSC 9;4;0 by the LocalCommand once ssh signs in again and
# on every way out. The engine drops a report after 15 seconds, so a wait
# writes the mark again at least every 10. Only when the app asked for it: by
# hand, in another terminal, OSC 9 may mean something else.
readonly REMOTE_MARK_SET=$'\e]9;4;4;0\a'
readonly REMOTE_MARK_CLEAR=$'\e]9;4;0\a'
readonly REMOTE_MARK_REFRESH=10
remote_marked=0
remote_mark_wanted() { [[ "${YEN_REMOTE_RECONNECT_MARK:-}" == 1 ]]; }
remote_mark() {
    remote_mark_wanted || return 0
    printf '%s' "$REMOTE_MARK_SET" 2> /dev/null || true
    remote_marked=1
}
remote_clear_mark() {
    remote_mark_wanted && [[ $remote_marked == 1 ]] || return 0
    printf '%s' "$REMOTE_MARK_CLEAR" 2> /dev/null || true
    remote_marked=0
}

# Wait before the next attempt; with the mark, in steps that renew it.
remote_wait() {
    local remaining="$1" step
    if ! remote_mark_wanted; then
        remote_run sleep "$remaining"
        return
    fi
    while true; do
        remote_mark
        step=$((remaining < REMOTE_MARK_REFRESH ? remaining : REMOTE_MARK_REFRESH))
        remote_run sleep "$step"
        remaining=$((remaining - step))
        [[ $remaining -gt 0 ]] || break
    done
    # Renewed once more, since ssh may take up to its connect timeout.
    remote_mark
}

remote_scratch=""
remote_child=""
remote_cleanup() {
    # Runs from traps under the command's set -e, so no step may fail it.
    remote_clear_mark
    if [[ -n "$remote_child" ]]; then
        kill -TERM "$remote_child" 2> /dev/null || true
        wait "$remote_child" 2> /dev/null || true
        remote_child=""
    fi
    [[ -n "$remote_scratch" ]] && rm -rf "$remote_scratch"
    remote_scratch=""
}

# Run a command in the background and wait for it, so a signal trap runs at
# once and ends it; bash defers a trap until a foreground child exits, which
# left ssh running after the CLI was stopped. 0<&0 keeps the terminal on stdin,
# which a background job without job control would lose.
remote_run() {
    local status=0
    "$@" 0<&0 &
    remote_child=$!
    wait "$remote_child" || status=$?
    remote_child=""
    return "$status"
}

remote_make_scratch() {
    remote_scratch="$(mktemp -d "${TMPDIR:-/tmp}/yen-remote.XXXXXXXX")" || {
        yen_error "Could not create a temporary directory."
        exit 1
    }
    # Set the cleanup before any check can exit, so a refused path is removed.
    trap remote_cleanup EXIT
    [[ "$remote_scratch" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
        yen_error "Unusable temporary directory: $remote_scratch"
        exit 1
    }
    trap 'remote_cleanup; exit 130' INT
    trap 'remote_cleanup; exit 129' HUP
    trap 'remote_cleanup; exit 143' TERM
}

# yen sessions list --host <target> [--porcelain]
remote_list() {
    local target="$1" porcelain="$2" status=0 parsed=0 code=0 peer_status line command options=()
    # A refusal inside the substitution must stop the CLI, not reach ssh.
    command="$(remote_command list --porcelain)" || exit "$?"
    remote_make_scratch
    while IFS= read -r line; do options+=("$line"); done < <(remote_ssh_options)
    remote_run "$REMOTE_SSH_BIN" "${options[@]}" -o BatchMode=yes -T -- "$target" "$command" \
        < /dev/null > "$remote_scratch/out" 2> "$remote_scratch/err" || status=$?

    if [[ $status -eq 255 ]]; then
        classify_ssh_failure "$remote_scratch/err" || code=$?
        print_remote_errors "$remote_scratch/err"
        remote_failure_message "$code" "$target" >&2
        exit "$code"
    fi
    # The peer's own status, when its snippet ran; otherwise ssh's.
    peer_status="$(take_remote_status "$remote_scratch/err")"
    [[ -z "$peer_status" ]] || status="$peer_status"
    if [[ $status -eq $REMOTE_STATUS_NOT_INSTALLED ]]; then
        remote_failure_message "$REMOTE_EXIT_NOT_INSTALLED" "$target" >&2
        exit "$REMOTE_EXIT_NOT_INSTALLED"
    fi

    read_porcelain < "$remote_scratch/out" > "$remote_scratch/rows" || parsed=$?
    if [[ $parsed -eq 3 ]]; then
        # No header: a YEN with sessions but without --porcelain rejects the
        # option with usage status 2, and one from before sessions prints
        # "Unknown command: sessions" and exits 1. Anything else is a failure
        # of a current YEN there, such as a damaged install.
        if [[ $status -eq 2 ]] || { [[ $status -eq 1 ]] && LC_ALL=C grep -q 'Unknown command:.*sessions' "$remote_scratch/out"; }; then
            remote_failure_message "$REMOTE_EXIT_TOO_OLD" "$target" >&2
            exit "$REMOTE_EXIT_TOO_OLD"
        fi
        if LC_ALL=C grep -qE $'^yen-sessions\t[0-9]+$' "$remote_scratch/out"; then
            echo "yen sessions: YEN on $target lists sessions in another format version; update YEN on both Macs" >&2
            exit "$REMOTE_EXIT_TOO_OLD"
        fi
        print_remote_errors "$remote_scratch/err"
        echo "yen sessions: could not list the sessions on $target" >&2
        exit 1
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
# that never connects is reported and not retried, unless the third argument
# is 1 (--retry-unreachable): then an unreachable peer is retried from the
# first attempt, and every other failure still stops at once.
remote_attach() {
    local target="$1" id="$2" retry_unreachable="${3:-0}" status code established=0 attempt=0 delay cap line command options=()
    cap="${YEN_SSH_RETRY_MAX_DELAY:-30}"
    [[ "$cap" =~ ^[0-9]+$ ]] || usage_error "YEN_SSH_RETRY_MAX_DELAY must be a whole number of seconds"
    command="$(remote_command attach "$id")" || exit "$?"
    remote_make_scratch
    while IFS= read -r line; do options+=("$line"); done < <(remote_ssh_options)
    if remote_mark_wanted; then
        # ssh runs this after it signs in, while the CLI waits on it, so the
        # mark clears the moment the session is back.
        options+=(-o PermitLocalCommand=yes -o "LocalCommand=/usr/bin/touch $remote_scratch/connected; /usr/bin/printf '\\033]9;4;0\\007'")
    else
        options+=(-o PermitLocalCommand=yes -o "LocalCommand=/usr/bin/touch $remote_scratch/connected")
    fi

    while true; do
        rm -f "$remote_scratch/connected"
        status=0
        remote_run "$REMOTE_SSH_BIN" "${options[@]}" -t -- "$target" "$command" \
            2> "$remote_scratch/err" || status=$?
        print_remote_errors "$remote_scratch/err"
        if [[ -e "$remote_scratch/connected" ]]; then
            established=1
            attempt=0
            # The LocalCommand cleared the mark on screen.
            remote_marked=0
        fi

        case "$status" in
            0) exit 0 ;;
            "$REMOTE_STATUS_NOT_INSTALLED")
                remote_failure_message "$REMOTE_EXIT_NOT_INSTALLED" "$target" >&2
                exit "$REMOTE_EXIT_NOT_INSTALLED"
                ;;
            255) ;;
            1)
                # The peer's CLI refused and printed why above. Usually the
                # session has ended; a damaged YEN there also exits 1.
                echo "yen sessions: could not attach session $id on $target; it has ended or YEN there could not attach it" >&2
                exit "$REMOTE_EXIT_NO_SESSION"
                ;;
            *) exit "$status" ;;
        esac

        code=0
        classify_ssh_failure "$remote_scratch/err" || code=$?
        if [[ $code -ne $REMOTE_EXIT_UNREACHABLE || ($established -eq 0 && $retry_unreachable != 1) ]]; then
            remote_failure_message "$code" "$target" >&2
            exit "$code"
        fi
        attempt=$((attempt + 1))
        delay=$((1 << (attempt > 6 ? 6 : attempt - 1)))
        [[ $delay -le $cap ]] || delay="$cap"
        if [[ $established -eq 1 ]]; then
            echo "yen sessions: lost the connection to $target; reconnecting in ${delay}s (attempt $attempt, Ctrl-C to stop)" >&2
        else
            echo "yen sessions: cannot reach $target yet; retrying in ${delay}s (attempt $attempt, Ctrl-C to stop)" >&2
        fi
        remote_wait "$delay"
    done
}
