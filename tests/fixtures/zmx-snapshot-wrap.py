"""Does a zmx attach snapshot send a soft-wrapped line as one run of text?

Usage: python3 -I zmx-snapshot-wrap.py <zmx-binary> <socket-dir>

A 48-column client prints a 100-character line, detaches, and a second
48-column client attaches. Prints UNWRAPPED when the snapshot carries the line
without a hard break, so the pane can re-wrap and later reflow it; HARD-WRAPPED
otherwise. Exits non-zero when the probe itself cannot run.
"""
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

zmx, sock = sys.argv[1], sys.argv[2]
# Drop inherited ZMX_* variables: run from a YEN pane with Keep Sessions
# Running on, ZMX_SESSION makes this attach a nested one and zmx refuses it.
env = {k: v for k, v in os.environ.items() if not k.startswith("ZMX_")}
env.update(ZMX_DIR=sock, ZMX_NO_DETACH_KEY="1")
name = "wrap-probe-" + str(os.getpid())
marker = "R" * 50 + "S" * 50


def attach(seconds, send=b""):
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(zmx, [zmx, "attach", name, "/bin/zsh", "-f"], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 48, 0, 0))
    os.kill(pid, signal.SIGWINCH)
    out, start, sent = b"", time.time(), False
    while time.time() - start < seconds:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                out += os.read(fd, 65536)
            except OSError:
                break
        if send and not sent and time.time() - start > 1.0:
            os.write(fd, send)
            sent = True
    os.close(fd)
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    return out


try:
    attach(3.0, f"printf '%s\\n' {marker}\r".encode())
    snapshot = attach(2.0)
finally:
    subprocess.run([zmx, "kill", name], env=env, capture_output=True)

text = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07", b"", snapshot).decode("latin1")
if "R" * 20 not in text:
    print("NO-SNAPSHOT")
    sys.exit(2)
print("UNWRAPPED" if marker in text else "HARD-WRAPPED")
