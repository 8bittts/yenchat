#!/bin/bash
# A stand-in for /usr/bin/ssh, selected with YEN_SSH_BIN, for the remote
# sessions tests. Each call records its argv and follows one line of
# $FAKE_SSH_DIR/plan, by call number:
#
#   <connected> <status> [stderr text...]
#
# connected=1 runs the LocalCommand option the way ssh does after it
# authenticates; connected=0 is a connection that never succeeded.
# status=exec runs the remote command with $FAKE_SSH_LOGIN_SHELL -c, as the
# peer's login shell would, and exits with its status; $FAKE_SSH_REMOTE_YEN_LIB
# stands for a YEN_LIB the peer's shell startup files export, and each
# NAME=VALUE line of $FAKE_SSH_REMOTE_EXPORTS for any other exported variable.
# status=exec-login does the same through a parent named /usr/bin/login that
# exits 0 whatever the command's status was, as Tailscale SSH on a macOS peer
# does: its incubator runs commands under macOS login, which waits for the
# program and then exits 0. The peer's stdout and stderr still arrive intact.
# status=check-hold<seconds>, check-pass<seconds> and check-deny stand for a
# Tailscale SSH `check` rule whose approval is due: the server sends the
# control server's text as an SSH auth banner before sign-in, which OpenSSH
# prints on stderr, and holds sign-in for up to 30 minutes until the user
# approves in a browser (ssh/tailssh/tailssh.go, clientAuth, HoldAndDelegate).
# check-hold records its pid like sleep and waits; check-pass waits, then signs
# in (LocalCommand runs only then) and exits 0; check-deny is the denial or the
# 30-minute timeout: a banner, then sign-in fails and ssh exits 255.
# check-timeout<seconds> is ssh giving up on a held sign-in first: OpenSSH
# applies ServerAliveInterval x ServerAliveCountMax to authentication, so with
# YEN's options it prints "Connection to <host> port 22 timed out" after 30
# seconds and exits 255 while the check is still pending (measured with
# OpenSSH 10.5 against an sshd whose sign-in was held).
# status=sleep<seconds> records its pid in $FAKE_SSH_DIR/pid-<n> and hangs,
# like ssh waiting on a dead link.
# $FAKE_SSH_DIR/stdout-<n>, when present, is printed as the remote output, and
# $FAKE_SSH_DIR/stderr-<n> as ssh's own stderr (for multi-line messages).
# With FAKE_SSH_CAPTURE_STDIN=1 each call first copies its stdin to
# $FAKE_SSH_DIR/stdin-<n>, to show what the CLI hands ssh.
set -u
dir="$FAKE_SSH_DIR"
count=$(($(cat "$dir/count" 2>/dev/null || echo 0) + 1))
echo "$count" > "$dir/count"
printf '%s\0' "$@" > "$dir/argv-$count"
[[ "${FAKE_SSH_CAPTURE_STDIN:-}" == 1 ]] && cat > "$dir/stdin-$count"

line=$(sed -n "${count}p" "$dir/plan")
[[ -n "$line" ]] || { echo "fake ssh: no plan for call $count" >&2; exit 99; }
read -r connected status message <<< "$line"

local_command="" remote=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            [[ "$2" == LocalCommand=* ]] && local_command="${2#LocalCommand=}"
            shift 2
            ;;
        --) remote="$3"; break ;;
        *) shift ;;
    esac
done

if [[ "$status" == check* ]]; then
    printf '%s\n' "# Tailscale SSH requires an additional check." \
        "# To authenticate, visit: https://login.tailscale.com/a/0123456789ab" >&2
    case "$status" in
        check-hold*)
            echo "$$" > "$dir/pid-$count"
            exec /bin/sleep "${status#check-hold}"
            ;;
        check-pass*)
            /bin/sleep "${status#check-pass}"
            status=0
            ;;
        check-timeout*)
            /bin/sleep "${status#check-timeout}"
            echo "Connection to mini port 22 timed out" >&2
            exit 255
            ;;
        check-deny)
            echo "tailscale: access denied" >&2
            echo "dev@mini: Permission denied ()." >&2
            exit 255
            ;;
    esac
fi
[[ "$connected" == 1 && -n "$local_command" ]] && /bin/sh -c "$local_command"
[[ -f "$dir/stdout-$count" ]] && cat "$dir/stdout-$count"
[[ -f "$dir/stderr-$count" ]] && cat "$dir/stderr-$count" >&2
[[ -n "$message" ]] && echo "$message" >&2
if [[ "$status" == sleep* ]]; then
    echo "$$" > "$dir/pid-$count"
    exec /bin/sleep "${status#sleep}"
fi
if [[ "$status" == exec || "$status" == exec-login ]]; then
    [[ -z "${FAKE_SSH_REMOTE_YEN_LIB:-}" ]] || export YEN_LIB="$FAKE_SSH_REMOTE_YEN_LIB"
    while IFS= read -r assignment; do
        [[ -n "$assignment" ]] && export "${assignment?}"
    done <<< "${FAKE_SSH_REMOTE_EXPORTS:-}"
    if [[ "$status" == exec-login ]]; then
        # ps reports this process as /usr/bin/login, the parent of the login shell.
        exec -a /usr/bin/login /bin/bash -c '"$1" -c "$2"; exit 0' login "${FAKE_SSH_LOGIN_SHELL:-/bin/zsh}" "$remote"
    fi
    exec "${FAKE_SSH_LOGIN_SHELL:-/bin/zsh}" -c "$remote"
fi
exit "$status"
