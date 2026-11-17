import getpass
import json
import os
import pathlib
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import textwrap
import time


def iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def resolve_cli(candidate: str) -> str:
    candidate = (candidate or "").strip()
    if not candidate:
        return ""
    if "/" in candidate:
        path = pathlib.Path(candidate)
        if path.is_file() and os.access(str(path), os.X_OK):
            return str(path)
        return ""
    found = shutil.which(candidate)
    return found or ""


def join_target(join_command: str) -> str:
    try:
        parts = shlex.split(join_command)
    except Exception:
        return ""
    if len(parts) != 2 or parts[0] != "ssh":
        return ""
    target = parts[1]
    if "@" not in target:
        return ""
    return target


def parse_upterm_session(raw: str) -> dict:
    payload = json.loads(raw or "{}")
    join_command = str(payload.get("sshCommand") or "").strip()
    if not join_target(join_command):
        fail("Remote upterm session metadata is missing a valid ssh join command.", 2)
    session_id = str(payload.get("sessionId") or "").strip()
    web_url = str(payload.get("webUrl") or "").strip()
    return {
        "sessionId": session_id,
        "joinCommand": join_command,
        "reconnectTarget": join_target(join_command),
        "webUrl": web_url,
    }


def tmate_join_fields(cli: str, socket_path: str, mode: str) -> dict:
    join_format = "#{tmate_ssh_ro}"
    web_format = "#{tmate_web_ro}"
    if mode == "interactive":
        join_format = "#{tmate_ssh}"
        web_format = "#{tmate_web}"
    join_command = subprocess.check_output(
        [cli, "-S", socket_path, "display", "-p", join_format],
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    reconnect_target = join_target(join_command)
    if not reconnect_target:
        fail("Remote tmate session metadata is missing a valid ssh join command.", 2)
    web_url = subprocess.check_output(
        [cli, "-S", socket_path, "display", "-p", web_format],
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    return {
        "joinCommand": join_command,
        "reconnectTarget": reconnect_target,
        "webUrl": web_url,
    }


def watcher_code() -> str:
    return textwrap.dedent(
        """
        import os
        import shutil
        import signal
        import subprocess
        import sys
        import time

        transport = sys.argv[1]
        state_dir = sys.argv[2]
        ttl = int(sys.argv[3])
        pid = sys.argv[4]
        cli = sys.argv[5]
        socket_path = sys.argv[6]

        time.sleep(ttl)

        if transport == "upterm" and pid and pid != "0":
            try:
                os.killpg(int(pid), signal.SIGTERM)
            except Exception:
                pass
            time.sleep(1)
            try:
                os.killpg(int(pid), signal.SIGKILL)
            except Exception:
                pass
        elif transport == "tmate" and cli and socket_path:
            try:
                subprocess.run(
                    [cli, "-S", socket_path, "kill-server"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            except Exception:
                pass

        try:
            shutil.rmtree(state_dir)
        except Exception:
            pass
        """
    ).strip()


def host_identity() -> str:
    user = getpass.getuser().strip() or "unknown"
    host = socket.gethostname().strip() or "unknown"
    return f"{user}@{host}"


def repo_label(root: str) -> str:
    resolved = pathlib.Path(root).resolve()
    return resolved.name or str(resolved)


def remote_available(upterm_candidate: str, tmate_candidate: str) -> None:
    upterm = resolve_cli(upterm_candidate)
    tmate = resolve_cli(tmate_candidate)
    available = []
    if upterm:
        available.append("upterm")
    if tmate:
        available.append("tmate")
    print(
        json.dumps(
            {
                "available": available,
                "resolved": {
                    "upterm": upterm,
                    "tmate": tmate,
                },
            },
            sort_keys=True,
        )
    )


def remote_start(
    root: str,
    transport: str,
    mode: str,
    ttl_seconds: int,
    requested_session_id: str,
    upterm_candidate: str,
    tmate_candidate: str,
) -> None:
    resolved_root = pathlib.Path(root).expanduser().resolve()
    if not resolved_root.is_dir():
        fail(f"Remote share root does not exist: {resolved_root}", 2)

    cli = ""
    if transport == "upterm":
        cli = resolve_cli(upterm_candidate)
    elif transport == "tmate":
        cli = resolve_cli(tmate_candidate)
    if not cli:
        fail(f"Remote {transport} is not available.", 2)

    state_dir = pathlib.Path(tempfile.mkdtemp(prefix="yen-ide-share-"))
    started_at = iso_now()
    session_id = requested_session_id.strip() or os.urandom(9).hex()
    admin_socket = ""
    socket_path = ""
    runtime_pid = ""
    join_command = ""
    reconnect_target = ""
    web_url = ""

    try:
        if transport == "upterm":
            admin_file = state_dir / "upterm-admin.path"
            session_file = state_dir / "upterm-session.json"
            command_script = state_dir / "command.sh"
            command_script.write_text(
                "\n".join(
                    [
                        "#!/bin/bash",
                        "set -e",
                        f"cd {shlex.quote(str(resolved_root))}",
                        f'printf "%s\\n" "${{UPTERM_ADMIN_SOCKET:-}}" > {shlex.quote(str(admin_file))}',
                        'exec ${SHELL:-/bin/bash} -l',
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            command_script.chmod(0o755)
            command = [cli, "host"]
            if mode == "read-only":
                command.append("--read-only")
            command.extend(["--", "bash", str(command_script)])
            host_env = dict(
                os.environ,
                YEN_IDE_SHARE_UPTERM_ADMIN_SOCKET_FILE=str(admin_file),
                YEN_IDE_SHARE_UPTERM_SESSION_FILE=str(session_file),
            )
            proc = subprocess.Popen(
                command,
                cwd=str(resolved_root),
                env=host_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            runtime_pid = str(proc.pid)

            session_payload = None
            for _ in range(120):
                if proc.poll() is not None:
                    break
                if admin_file.is_file():
                    admin_socket = admin_file.read_text(encoding="utf-8").strip()
                    if admin_socket:
                        result = subprocess.run(
                            [cli, "session", "current", "-o", "json"],
                            env=dict(os.environ, UPTERM_ADMIN_SOCKET=admin_socket),
                            stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL,
                            text=True,
                            check=False,
                        )
                        if result.returncode == 0 and result.stdout.strip():
                            session_payload = parse_upterm_session(result.stdout.strip())
                            session_path = pathlib.Path(admin_socket + ".json")
                            if session_path.is_file() and not session_file.exists():
                                session_file.write_text(
                                    session_path.read_text(encoding="utf-8"),
                                    encoding="utf-8",
                                )
                            break
                time.sleep(0.1)
            if session_payload is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except Exception:
                    pass
                try:
                    shutil.rmtree(state_dir)
                except Exception:
                    pass
                fail("Remote upterm session did not publish join metadata.", 2)

            session_id = session_payload.get("sessionId") or session_id
            join_command = session_payload["joinCommand"]
            reconnect_target = session_payload["reconnectTarget"]
            web_url = session_payload.get("webUrl") or ""
        else:
            socket_path = str(state_dir / "tmate.sock")
            subprocess.run(
                [cli, "-S", socket_path, "new-session", "-d"],
                cwd=str(resolved_root),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            subprocess.run(
                [cli, "-S", socket_path, "wait", "tmate-ready"],
                cwd=str(resolved_root),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            join_fields = tmate_join_fields(cli, socket_path, mode)
            join_command = join_fields["joinCommand"]
            reconnect_target = join_fields["reconnectTarget"]
            web_url = join_fields.get("webUrl") or ""

        watcher = subprocess.Popen(
            [
                sys.executable,
                "-c",
                watcher_code(),
                transport,
                str(state_dir),
                str(ttl_seconds),
                runtime_pid or "0",
                cli,
                socket_path,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        print(
            json.dumps(
                {
                    "cli": cli,
                    "hostIdentity": host_identity(),
                    "joinCommand": join_command,
                    "mode": mode,
                    "reconnectTarget": reconnect_target,
                    "remoteAdminSocket": admin_socket,
                    "remotePid": runtime_pid,
                    "remoteSocketFile": socket_path,
                    "remoteStateDir": str(state_dir),
                    "repoLabel": repo_label(str(resolved_root)),
                    "sessionId": session_id,
                    "startedAt": started_at,
                    "watcherPid": str(watcher.pid),
                    "webUrl": web_url,
                },
                sort_keys=True,
            )
        )
    except subprocess.CalledProcessError as exc:
        try:
            shutil.rmtree(state_dir)
        except Exception:
            pass
        fail(f"Remote {transport} command failed with exit status {exc.returncode}.", 2)


def remote_status(
    transport: str,
    cli: str,
    remote_pid: str,
    remote_admin_socket: str,
    remote_socket_file: str,
    mode: str,
) -> None:
    payload = {
        "alive": False,
        "joinCommand": "",
        "reconnectTarget": "",
        "sessionId": "",
        "webUrl": "",
    }
    try:
        if transport == "upterm":
            pid = int(remote_pid or "0")
            try:
                os.kill(pid, 0)
            except Exception:
                print(json.dumps(payload, sort_keys=True))
                return
            admin_socket = (remote_admin_socket or "").strip()
            if not admin_socket:
                print(json.dumps(payload, sort_keys=True))
                return
            result = subprocess.run(
                [cli, "session", "current", "-o", "json"],
                env=dict(os.environ, UPTERM_ADMIN_SOCKET=admin_socket),
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=False,
            )
            if result.returncode != 0 or not result.stdout.strip():
                print(json.dumps(payload, sort_keys=True))
                return
            session_payload = parse_upterm_session(result.stdout.strip())
            payload.update(
                {
                    "alive": True,
                    "joinCommand": session_payload["joinCommand"],
                    "reconnectTarget": session_payload["reconnectTarget"],
                    "sessionId": session_payload.get("sessionId") or "",
                    "webUrl": session_payload.get("webUrl") or "",
                }
            )
            print(json.dumps(payload, sort_keys=True))
            return

        if transport == "tmate":
            socket_path = (remote_socket_file or "").strip()
            if not socket_path:
                print(json.dumps(payload, sort_keys=True))
                return
            result = subprocess.run(
                [cli, "-S", socket_path, "has-session"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if result.returncode != 0:
                print(json.dumps(payload, sort_keys=True))
                return
            join_fields = tmate_join_fields(cli, socket_path, mode)
            payload.update(
                {
                    "alive": True,
                    "joinCommand": join_fields["joinCommand"],
                    "reconnectTarget": join_fields["reconnectTarget"],
                    "webUrl": join_fields.get("webUrl") or "",
                }
            )
            print(json.dumps(payload, sort_keys=True))
            return
    except Exception:
        print(json.dumps(payload, sort_keys=True))
        return

    print(json.dumps(payload, sort_keys=True))


def remote_revoke(
    transport: str,
    cli: str,
    remote_state_dir: str,
    remote_pid: str,
    remote_socket_file: str,
) -> None:
    if transport == "upterm":
        pid = int(remote_pid or "0")
        if pid > 0:
            try:
                os.killpg(pid, signal.SIGTERM)
            except Exception:
                pass
            time.sleep(0.5)
            try:
                os.killpg(pid, signal.SIGKILL)
            except Exception:
                pass
    elif transport == "tmate" and cli and remote_socket_file:
        try:
            subprocess.run(
                [cli, "-S", remote_socket_file, "kill-server"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        except Exception:
            pass

    if remote_state_dir:
        try:
            shutil.rmtree(remote_state_dir)
        except Exception:
            pass

    print(json.dumps({"ok": True}, sort_keys=True))


def main(argv) -> int:
    if len(argv) < 2:
        fail("remote-share-helper requires an action.", 2)
    action = argv[1]
    if action == "available":
        remote_available(argv[2] if len(argv) > 2 else "", argv[3] if len(argv) > 3 else "")
        return 0
    if action == "start":
        remote_start(
            argv[2],
            argv[3],
            argv[4],
            int(argv[5]),
            argv[6],
            argv[7] if len(argv) > 7 else "",
            argv[8] if len(argv) > 8 else "",
        )
        return 0
    if action == "status":
        remote_status(
            argv[2],
            argv[3],
            argv[4],
            argv[5],
            argv[6],
            argv[7],
        )
        return 0
    if action == "revoke":
        remote_revoke(
            argv[2],
            argv[3],
            argv[4],
            argv[5],
            argv[6],
        )
        return 0
    fail(f"Unknown remote-share-helper action: {action}", 2)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
