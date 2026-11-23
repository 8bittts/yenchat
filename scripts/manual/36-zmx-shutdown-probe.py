"""End zmx sessions and report how each session daemon exited.

Usage: python3 -I 36-zmx-shutdown-probe.py <zmx-binary> <socket-dir> <runs> [--reports]

Each run ends one session daemon, alternating two ways: `zmx kill` on a
`zmx run -d` session, and an attached session whose own command exits. A
counter session started first through `zmx attach` (the engine's path) stays
up the whole time and must come back, with the same shell pid and a counter
that kept counting, before it is killed last.

The exit status of every daemon comes from kqueue NOTE_EXITSTATUS, which macOS
delivers for a process that is not our child (the daemon's parent is launchd).
A daemon that exits 0 is clean; one that dies on SIGABRT is the shutdown free
of a pointer libmalloc never allocated. With --reports, it also counts the
crash reports in ~/Library/Logs/DiagnosticReports that name each daemon pid.

The last line is a SUMMARY with positive counts. Exits 0 only when every
daemon was observed to end, none aborted, and the counter session survived.
Every inherited ZMX_* variable is dropped.
"""
import glob
import os
import pty
import re
import select
import subprocess
import sys
import time

zmx, sock, runs = sys.argv[1], sys.argv[2], int(sys.argv[3])
want_reports = "--reports" in sys.argv[4:]
env = {k: v for k, v in os.environ.items() if not k.startswith("ZMX_")}
env["ZMX_DIR"] = sock
os.makedirs(sock, exist_ok=True)
REPORTS = os.path.expanduser("~/Library/Logs/DiagnosticReports")
NOTE_EXITSTATUS = 0x04000000
EXIT_WAIT = 30


def zmx_out(*args):
    return subprocess.run([zmx, *args], env=env, capture_output=True, text=True, timeout=30).stdout


def pids(name):
    """Shell pid from `zmx ls`, and the daemon pid as that shell's parent."""
    for line in zmx_out("ls").splitlines():
        if re.search(rf"(^|\s)(name=)?{re.escape(name)}\t", line):
            m = re.search(r"\bpid=(\d+)", line)
            if m:
                shell = int(m.group(1))
                ppid = subprocess.run(["ps", "-o", "ppid=", "-p", str(shell)], capture_output=True, text=True).stdout.strip()
                return shell, int(ppid) if ppid else None
    return None, None


def watch(pid):
    kq = select.kqueue()
    kq.control([select.kevent(pid, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 0, 0)
    return kq


def exit_of(kq):
    events = kq.control(None, 1, EXIT_WAIT)
    kq.close()
    if not events:
        return "timeout"
    status = events[0].data
    sig = status & 0x7F
    return f"signal={sig}" if sig else f"exit={(status >> 8) & 0xFF}"


def attach(name, *cmd, seconds=2.0, detach=True):
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(zmx, [zmx, "attach", name, *cmd], env)
    out, end = b"", time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                out += os.read(fd, 65536)
            except OSError:
                break
    if detach:
        try:
            os.write(fd, b"\x1c")  # ctrl+\ detaches this client only
        except OSError:
            pass
    end = time.time() + 5
    while time.time() < end and os.waitpid(pid, os.WNOHANG)[0] == 0:
        time.sleep(0.1)
    os.close(fd)
    return out


def reports_naming(pid):
    base = os.path.basename(zmx)
    end = time.time() + 15
    while time.time() < end:
        hits = [f for f in glob.glob(f"{REPORTS}/{base}*.ips") if f'"pid" : {pid},' in open(f, errors="replace").read()]
        if hits:
            return len(hits)
        time.sleep(0.5)
    return 0


def wait_for(name, seconds=5):
    end = time.time() + seconds
    while time.time() < end:
        shell, daemon = pids(name)
        if daemon:
            return shell, daemon
        time.sleep(0.2)
    return None, None


ended = aborted = clean = unknown = reports = 0


def record(label, name, daemon, kq):
    global ended, aborted, clean, unknown, reports
    result = exit_of(kq)
    n = reports_naming(daemon) if want_reports and result != "timeout" else 0
    reports += n
    if result == "timeout":
        unknown += 1
    else:
        ended += 1
        if result == "exit=0":
            clean += 1
        elif result == "signal=6":
            aborted += 1
        else:
            unknown += 1
    print(f"{label} session={name} daemon_pid={daemon} {result}" + (f" crash_reports={n}" if want_reports else ""), flush=True)


counter = "i=0; while :; do echo COUNT$i; i=$((i+1)); sleep 1; done"
first = attach("keep", "sh", "-c", counter, seconds=3)
keep_shell, keep_daemon = wait_for("keep")
seen = [int(x) for x in re.findall(rb"COUNT(\d+)", first)]
print(f"counter session: shell_pid={keep_shell} daemon_pid={keep_daemon} count={max(seen) if seen else None}", flush=True)

for i in range(1, runs + 1):
    name = f"s{i}"
    if i % 2:
        zmx_out("run", name, "-d", "sleep", "300")
        _, daemon = wait_for(name)
        if not daemon:
            unknown += 1
            print(f"run={i} session={name} no daemon pid", flush=True)
            continue
        kq = watch(daemon)
        zmx_out("kill", name)
        record(f"run={i} mode=kill", name, daemon, kq)
    else:
        pid, fd = pty.fork()
        if pid == 0:
            os.execve(zmx, [zmx, "attach", name, "sh", "-c", "sleep 3"], env)
        _, daemon = wait_for(name)
        kq = watch(daemon) if daemon else None
        end = time.time() + 15
        while time.time() < end and os.waitpid(pid, os.WNOHANG)[0] == 0:
            try:
                select.select([fd], [], [], 0.1)[0] and os.read(fd, 65536)
            except OSError:
                pass
        os.close(fd)
        if not kq:
            unknown += 1
            print(f"run={i} session={name} no daemon pid", flush=True)
            continue
        record(f"run={i} mode=exit", name, daemon, kq)

again = attach("keep", seconds=3)
counts = [int(x) for x in re.findall(rb"COUNT(\d+)", again)]
shell_now, _ = pids("keep")
survived = bool(keep_shell) and shell_now == keep_shell and bool(counts) and bool(seen) and max(counts) > max(seen)
print(f"counter session after: shell_pid={shell_now} count={max(counts) if counts else None} survived={survived}", flush=True)
if keep_daemon:
    kq = watch(keep_daemon)
    zmx_out("kill", "keep")
    record("counter mode=kill", "keep", keep_daemon, kq)

total = runs + 1
print(f"SUMMARY daemons={total} ended={ended} clean={clean} aborted={aborted} unknown={unknown}"
      + (f" crash_reports={reports}" if want_reports else "") + f" counter_survived={survived}", flush=True)
sys.exit(0 if ended == total and clean == total and survived else 1)
