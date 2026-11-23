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

[[ "$connected" == 1 && -n "$local_command" ]] && /bin/sh -c "$local_command"
[[ -f "$dir/stdout-$count" ]] && cat "$dir/stdout-$count"
[[ -f "$dir/stderr-$count" ]] && cat "$dir/stderr-$count" >&2
[[ -n "$message" ]] && echo "$message" >&2
if [[ "$status" == sleep* ]]; then
    echo "$$" > "$dir/pid-$count"
    exec /bin/sleep "${status#sleep}"
fi
if [[ "$status" == exec ]]; then
    [[ -z "${FAKE_SSH_REMOTE_YEN_LIB:-}" ]] || export YEN_LIB="$FAKE_SSH_REMOTE_YEN_LIB"
    while IFS= read -r assignment; do
        [[ -n "$assignment" ]] && export "${assignment?}"
    done <<< "${FAKE_SSH_REMOTE_EXPORTS:-}"
    exec "${FAKE_SSH_LOGIN_SHELL:-/bin/zsh}" -c "$remote"
fi
exit "$status"
