#!/bin/bash
# Verify `yen sessions --host` end to end against a private loopback sshd.
#
# Usage: scripts/manual/35-verify-remote-attach-loopback.sh [--old-cli <path to a yen without --porcelain>]
#
# Stands in for a second Mac: an unprivileged sshd on 127.0.0.1 with a
# temporary host key and authorized_keys, a throwaway home whose
# Applications/YEN.app runs this checkout's CLI, and a real session started
# with the vendored zmx. It measures each failure class through the real ssh,
# lists the session, then attaches through a pty, cuts the link twice (sshd
# child killed, then stopped until keepalives fire) and requires the same
# session to come back. Nothing outside the temporary directory changes: no
# ~/.ssh, no system sshd, no Tailscale. Exits 0 only when every check passes.
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
yen="$repo/yen-cli/bin/yen"
zmx="$repo/yen-terminal/customizations/vendor/zmx/zmx"
probe="$repo/scripts/manual/35-remote-attach-probe.py"
old_cli=""
[[ "${1:-}" == --old-cli && -n "${2:-}" ]] && old_cli="$2"
[[ -x "$zmx" ]] || { echo "FAIL: vendored zmx missing at $zmx" >&2; exit 1; }
for name in $(env | sed -n 's/^\(ZMX_[A-Za-z_]*\)=.*/\1/p'); do unset "$name"; done

# Short: zmx sockets live under the fake home and cap at 103 bytes.
base="$(mktemp -d /tmp/yrl.XXXXXXXX)"
home="$base/h"
sshd_pid=""
session="$(uuidgen)"
failures=0
cleanup() {
    [[ -S "$home/.local/state/yen/zmx/$session" ]] && env -i HOME="$home" ZMX_DIR="$home/.local/state/yen/zmx" "$zmx" kill "$session" > /dev/null 2>&1
    [[ -n "$sshd_pid" ]] && kill "$sshd_pid" 2> /dev/null
    rm -r -f "$base"
}
trap cleanup EXIT

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $label ($actual)"
    else
        echo "FAIL: $label: expected $expected, got $actual"
        failures=$((failures + 1))
    fi
}

ssh-keygen -q -t ed25519 -N '' -f "$base/host_key"
ssh-keygen -q -t ed25519 -N '' -f "$base/client_key"
ssh-keygen -q -t ed25519 -N '' -f "$base/other_key"
printf 'environment="HOME=%s" %s\n' "$home" "$(cat "$base/client_key.pub")" > "$base/authorized_keys"
mkdir -p "$home/Applications/YEN.app/Contents/Resources/bin" "$home/.local/state/yen/zmx" "$home/Applications/Old.app/Contents/Resources/bin"
chmod 700 "$home/.local/state/yen/zmx"
# A wrapper, not a symlink: bin/yen finds its resources next to its real path.
printf '#!/bin/bash\nexec %q "$@"\n' "$yen" > "$home/Applications/YEN.app/Contents/Resources/bin/yen"
[[ -n "$old_cli" ]] && printf '#!/bin/bash\nexec %q "$@"\n' "$old_cli" > "$home/Applications/Old.app/Contents/Resources/bin/yen"
chmod 755 "$home"/Applications/*.app/Contents/Resources/bin/yen 2> /dev/null

for attempt in 1 2 3 4 5; do
    port=$((20000 + RANDOM % 40000))
    cat > "$base/sshd_config" << EOF
Port $port
ListenAddress 127.0.0.1
HostKey $base/host_key
AuthorizedKeysFile $base/authorized_keys
PidFile $base/sshd.pid
UsePAM no
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitUserEnvironment yes
EOF
    if /usr/sbin/sshd -f "$base/sshd_config" -E "$base/sshd.log"; then
        sleep 0.5
        sshd_pid="$(cat "$base/sshd.pid" 2> /dev/null)"
        [[ -n "$sshd_pid" ]] && break
    fi
done
[[ -n "$sshd_pid" ]] || { echo "FAIL: unprivileged sshd did not start; see $base/sshd.log" >&2; cat "$base/sshd.log" >&2; exit 1; }
echo "sshd pid $sshd_pid on 127.0.0.1:$port"

echo "[127.0.0.1]:$port $(cut -d' ' -f1,2 "$base/host_key.pub")" > "$base/known_hosts"
echo "[127.0.0.1]:$port $(cut -d' ' -f1,2 "$base/other_key.pub")" > "$base/known_hosts_changed"
: > "$base/known_hosts_empty"
ssh_config() {
    cat << EOF
Host yen-loop
  HostName 127.0.0.1
  Port ${3:-$port}
  IdentityFile $1
  IdentitiesOnly yes
  UserKnownHostsFile $2
  GlobalKnownHostsFile /dev/null
EOF
}
ssh_config "$base/client_key" "$base/known_hosts" > "$base/ssh_ok"
ssh_config "$base/client_key" "$base/known_hosts_empty" > "$base/ssh_unknown"
ssh_config "$base/client_key" "$base/known_hosts_changed" > "$base/ssh_changed"
ssh_config "$base/other_key" "$base/known_hosts" > "$base/ssh_denied"
ssh_config "$base/client_key" "$base/known_hosts" "$((port == 65535 ? port - 1 : port + 1))" > "$base/ssh_refused"
for variant in ok unknown changed denied refused; do
    printf '#!/bin/bash\nexec /usr/bin/ssh -F %q "$@"\n' "$base/ssh_$variant" > "$base/bin-$variant"
    chmod 755 "$base/bin-$variant"
done

listing() {
    YEN_SSH_BIN="$base/bin-$1" YEN_REMOTE_APP="$home/Applications/${2:-YEN}.app" \
        "$yen" sessions list --host yen-loop --porcelain > "$base/list.out" 2> "$base/list.err"
    echo $?
}

echo "== failure classes through the real ssh"
check "unknown host key under BatchMode" 11 "$(listing unknown)"
check "changed host key" 15 "$(listing changed)"
check "no usable key" 11 "$(listing denied)"
check "connection refused" 10 "$(listing refused)"
check "YEN not installed on the peer" 12 "$(listing ok Absent)"
if [[ -n "$old_cli" ]]; then
    check "YEN without --porcelain on the peer" 13 "$(listing ok Old)"
else
    echo "SKIP: YEN without --porcelain (pass --old-cli)"
fi

echo "== list and attach"
env -i PATH="$PATH" HOME="$home" ZMX_DIR="$home/.local/state/yen/zmx" "$zmx" run "$session" -d \
    /bin/bash --noprofile --norc -c 'i=0; while :; do i=$((i + 1)); echo tick-$i; sleep 1; done' > /dev/null
sleep 1
check "list" 0 "$(listing ok)"
started="$(awk -F'\t' -v id="$session" '$1 == id { print $3 }' "$base/list.out")"
check "session listed as detached" detached "$(awk -F'\t' -v id="$session" '$1 == id { print $2 }' "$base/list.out")"

for cut in kill stall; do
    YEN_SSH_BIN="$base/bin-ok" YEN_REMOTE_APP="$home/Applications/YEN.app" \
        python3 -I "$probe" "$yen" "$session" "$sshd_pid" "$cut" "$base/probe.log"
    check "reattach after the link is cut ($cut)" 0 "$?"
done
cat "$base/probe.log"

check "list after reconnects" 0 "$(listing ok)"
check "same session, same start time" "$started" "$(awk -F'\t' -v id="$session" '$1 == id { print $3 }' "$base/list.out")"

echo "failures=$failures"
[[ $failures -eq 0 ]]
