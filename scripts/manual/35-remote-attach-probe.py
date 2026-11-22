"""Drive `yen sessions attach --host` in a pty, cut its link, and watch it reattach.

Usage: python3 -I 35-remote-attach-probe.py <yen> <session-id> <sshd-pid> <cut> <log>

The session prints tick-<n> every second. <cut> is "kill" (end the sshd child,
as a crashed peer or closed connection would) or "stall" (stop it, as a dead
network or a sleeping Mac would, so only ssh keepalives notice). Passes when
the ticks keep counting up after the reconnect, which proves the same session
came back. Called by 35-verify-remote-attach-loopback.sh with YEN_SSH_BIN and
YEN_REMOTE_APP set; every ZMX_* variable is dropped.
"""
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

yen, session, sshd_pid, cut, log_path = sys.argv[1:6]
env = {k: v for k, v in os.environ.items() if not k.startswith("ZMX_")}
env.update(YEN_SSH_RETRY_MAX_DELAY="1", TERM="xterm-256color")
log = open(log_path, "a")
out = b""


def say(text):
    log.write(f"[{cut}] {text}\n")
    log.flush()


def pump(seconds, until=None):
    global out
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            out += chunk
            if until and until(out):
                return


def children(ppid):
    found = subprocess.run(["/usr/bin/pgrep", "-P", str(ppid)], capture_output=True, text=True)
    return [int(p) for p in found.stdout.split()]


def ticks(data):
    return [int(n) for n in re.findall(rb"tick-(\d+)", data)]


pid, fd = pty.fork()
if pid == 0:
    os.execve(yen, [yen, "sessions", "attach", "--host", "yen-loop", session], env)

pump(4)
before = ticks(out)
connection = children(sshd_pid)
say(f"attached: last ticks {before[-3:]}, sshd connections {connection}")
mark = len(out)
stopped = []
for child in connection:
    if cut == "kill":
        os.kill(child, signal.SIGTERM)
    else:
        # The privileged child forks the one that carries the session's traffic.
        for grandchild in children(child):
            os.kill(grandchild, signal.SIGSTOP)
            stopped.append(grandchild)
say(f"cut the link ({cut})")
started = time.time()
pump(60 if cut == "stall" else 8, until=lambda data: b"reconnecting" in data[mark:])
say(f"status line after {time.time() - started:.1f}s")
pump(6)
after = ticks(out[mark:])
text = out[mark:].decode("latin1")
say(f"after reconnect: ticks {after[-3:]}, sshd connections {children(sshd_pid)}")
lines = [line for line in text.splitlines() if "yen sessions:" in line or "Connection" in line or "Timeout" in line]
for line in lines:
    say(f"stderr: {line.strip()}")
for grandchild in stopped:
    os.kill(grandchild, signal.SIGKILL)

os.write(fd, b"\x1c")  # zmx detach key; the session keeps running
pump(3)
_, status = os.waitpid(pid, 0)
say(f"attach exit after detach: {os.waitstatus_to_exitcode(status)}")
ok = bool(before) and bool(after) and max(after) >= max(before) + 3 and "reconnecting" in text
say("REATTACHED" if ok else "FAILED")
sys.exit(0 if ok else 1)
