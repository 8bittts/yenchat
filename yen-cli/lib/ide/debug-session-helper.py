from __future__ import annotations

import json
import os
import pathlib
import pty
import re
import select
import shlex
import socket
import subprocess
import sys
import tempfile
import time
from typing import Any


ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
LOCATION_RE = {
    "python-pdb": re.compile(r">\s+(.+?)\((\d+)\)"),
    "node-inspect": re.compile(r"(?:Break on start in|break in)\s+(.+?):(\d+)"),
    "lldb": re.compile(r"\sat\s+(.+?):(\d+)(?::(\d+))?"),
}
PROMPT_TEXT = {
    "python-pdb": "(Pdb)",
    "node-inspect": "debug>",
    "lldb": "(lldb)",
}
CONTROL_LABELS = [
    "continue",
    "next",
    "step",
    "out",
    "inspect",
    "stack",
    "breakpoint-add",
    "breakpoint-list",
    "breakpoint-remove",
    "watch-add",
    "watch-list",
    "watch-remove",
    "transcript",
    "stop",
]


def iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def ensure_parent(path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def atomic_write_text(path: pathlib.Path, text: str) -> None:
    ensure_parent(path)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(tmp_name, path)


def normalize_output(raw: str) -> str:
    text = raw.replace("\r\n", "\n").replace("\r", "\n")
    text = ANSI_RE.sub("", text)
    while "\b" in text:
        text = re.sub(r".\x08", "", text)
    return text


def clean_text(value: Any) -> str:
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def excerpt_lines(text: str, limit: int = 8) -> list[str]:
    lines = [line.rstrip() for line in normalize_output(text).splitlines()]
    lines = [line for line in lines if line.strip()]
    return lines[-limit:]


def render_command(argv: list[str]) -> str:
    return " ".join(shlex.quote(str(part)) for part in argv)


def meta_payload(state: dict[str, Any]) -> dict[str, Any]:
    payload = dict(state)
    payload["schemaVersion"] = 1
    payload["updatedAt"] = iso_now()
    payload["supportedControls"] = CONTROL_LABELS
    payload["outputExcerpt"] = state.get("outputExcerpt") or []
    payload["breakpoints"] = state.get("breakpoints") or []
    payload["watches"] = state.get("watches") or []
    return payload


def write_meta(state: dict[str, Any]) -> None:
    meta_path = pathlib.Path(state["metaFile"])
    atomic_write_text(meta_path, json.dumps(meta_payload(state), indent=2, sort_keys=True) + "\n")


def write_launch_failure(meta_file: str, config: dict[str, Any], message: str) -> None:
    payload = {
        "schemaVersion": 1,
        "root": clean_text(config.get("root")),
        "tool": clean_text(config.get("tool")),
        "target": clean_text(config.get("target")),
        "displayTarget": clean_text(config.get("displayTarget")),
        "entryPath": clean_text(config.get("entryPath")),
        "line": config.get("line"),
        "column": config.get("column"),
        "lineApplied": bool(config.get("lineApplied")),
        "commandText": clean_text(config.get("commandText")),
        "summaryReport": clean_text(config.get("summaryReport")),
        "detailsReport": clean_text(config.get("detailsReport")),
        "metaFile": clean_text(meta_file),
        "socketFile": clean_text(config.get("socketFile")),
        "startedAt": clean_text(config.get("startedAt")) or iso_now(),
        "endedAt": iso_now(),
        "updatedAt": iso_now(),
        "status": "managed-failed",
        "active": False,
        "exitCode": None,
        "outputExcerpt": [],
        "breakpoints": [],
        "watches": [],
        "supportedControls": CONTROL_LABELS,
        "error": clean_text(message),
    }
    atomic_write_text(pathlib.Path(meta_file), json.dumps(payload, indent=2, sort_keys=True) + "\n")


def append_transcript(state: dict[str, Any], title: str, body: str) -> None:
    text = normalize_output(body or "")
    if not text.strip():
        return
    path = pathlib.Path(state["detailsReport"])
    ensure_parent(path)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"\n--- {title} @ {iso_now()} ---\n")
        handle.write(text)
        if not text.endswith("\n"):
            handle.write("\n")


def summary_row(state: dict[str, Any]) -> str:
    return "\t".join(
        [
            clean_text(state.get("endedAt")),
            clean_text(state.get("startedAt")),
            clean_text(state.get("tool")),
            clean_text(state.get("status")),
            clean_text(state.get("exitCode")),
            clean_text(state.get("displayTarget")),
            clean_text(state.get("entryPath")),
            clean_text(state.get("line")),
            clean_text(state.get("column")),
            clean_text("yes" if state.get("lineApplied") else "no"),
            clean_text(state.get("commandText")),
        ]
    )


def write_summary(state: dict[str, Any]) -> None:
    path = pathlib.Path(state["summaryReport"])
    atomic_write_text(path, summary_row(state) + "\n")


def append_result(state: dict[str, Any]) -> None:
    path = pathlib.Path(state["detailsReport"])
    ensure_parent(path)
    with path.open("a", encoding="utf-8") as handle:
        handle.write("\n--- result ---\n")
        handle.write(f"Ended: {state.get('endedAt') or ''}\n")
        handle.write(f"Status: {state.get('status') or ''}\n")
        handle.write(f"Exit code: {state.get('exitCode') if state.get('exitCode') is not None else ''}\n")


def resolve_location(root: str, raw_path: str, line: str, column: str = "") -> dict[str, str]:
    root_path = pathlib.Path(root).resolve()
    path_text = (raw_path or "").strip()
    if not path_text:
        return {"path": "", "location": ""}
    candidate = pathlib.Path(path_text)
    if candidate.is_absolute():
        absolute = candidate
    else:
        absolute = root_path / candidate
    try:
        absolute = absolute.resolve()
    except Exception:
        absolute = absolute
    try:
        rel = absolute.relative_to(root_path).as_posix()
    except Exception:
        rel = path_text.replace("\\", "/")
    location = rel
    if line:
        location = f"{location}:{line}"
        if column:
            location = f"{location}:{column}"
    return {"path": rel, "location": location}


def normalize_breakpoint_spec(root: str, spec: str) -> dict[str, str] | None:
    match = re.match(r"^(.*?):(\d+)(?::(\d+))?$", clean_text(spec))
    if not match:
        return None
    location = resolve_location(root, match.group(1), match.group(2), match.group(3) or "")
    path_text = clean_text(location.get("path")) or clean_text(match.group(1))
    line_text = clean_text(match.group(2))
    return {
        "commandSpec": f"{path_text}:{line_text}",
        "location": f"{path_text}:{line_text}",
    }


class DebugAdapter:
    def __init__(self, tool: str, state: dict[str, Any]) -> None:
        self.tool = tool
        self.state = state

    def prompt_text(self) -> str:
        return PROMPT_TEXT[self.tool]

    def launch_commands(self) -> list[tuple[str, str]]:
        line = int(self.state.get("line") or 0)
        entry_path = self.state.get("entryPath") or ""
        if self.tool == "python-pdb":
            if line > 1:
                return [
                    (f"break {entry_path}:{line}", "set launch breakpoint"),
                    ("continue", "continue to launch breakpoint"),
                ]
            return []
        if self.tool == "node-inspect":
            return []
        if self.tool == "lldb":
            return [
                ("breakpoint set --name main", "set launch breakpoint"),
                ("run", "run to main"),
            ]
        return []

    def control_command(self, action: str) -> str:
        mapping = {
            "continue": {"python-pdb": "continue", "node-inspect": "cont", "lldb": "continue"},
            "next": {"python-pdb": "next", "node-inspect": "next", "lldb": "next"},
            "step": {"python-pdb": "step", "node-inspect": "step", "lldb": "step"},
            "out": {"python-pdb": "return", "node-inspect": "out", "lldb": "finish"},
            "stack": {"python-pdb": "where", "node-inspect": "backtrace", "lldb": "bt"},
        }
        return mapping[action][self.tool]

    def inspect_command(self, expression: str) -> str:
        if self.tool == "python-pdb":
            return f"p {expression}"
        if self.tool == "node-inspect":
            return f"p({expression})"
        return f"expression -- {expression}"

    def breakpoint_add_command(self, spec: str) -> str:
        if self.tool == "python-pdb":
            return f"break {spec}"
        if self.tool == "node-inspect":
            path_text, line = spec.rsplit(":", 1)
            return f"sb({json.dumps(path_text)}, {int(line)})"
        path_text, line = spec.rsplit(":", 1)
        return f"breakpoint set --file {shlex.quote(path_text)} --line {int(line)}"

    def breakpoint_remove_command(self, breakpoint_row: dict[str, Any]) -> str:
        backend_id = str(breakpoint_row.get("backendId") or "").strip()
        spec = str(breakpoint_row.get("location") or breakpoint_row.get("spec") or "").strip()
        if self.tool == "python-pdb":
            return f"clear {backend_id}"
        if self.tool == "node-inspect":
            path_text, line = spec.rsplit(":", 1)
            return f"cb({json.dumps(path_text)}, {int(line)})"
        return f"breakpoint delete {backend_id}"

    def stop_command(self) -> str:
        if self.tool == "node-inspect":
            return "kill"
        return "quit"

    def parse_breakpoint_backend_id(self, text: str) -> str:
        if self.tool == "node-inspect":
            match = re.search(r"#(\d+)\s+", normalize_output(text))
            return match.group(1) if match else ""
        match = re.search(r"Breakpoint\s+(\d+)", normalize_output(text))
        return match.group(1) if match else ""

    def parse_location(self, text: str) -> dict[str, str]:
        normalized = normalize_output(text)
        match = None
        for candidate in LOCATION_RE[self.tool].finditer(normalized):
            match = candidate
        if not match:
            return {"path": "", "location": ""}
        raw_path = match.group(1)
        line = match.group(2) if match.lastindex and match.lastindex >= 2 else ""
        column = match.group(3) if match.lastindex and match.lastindex >= 3 else ""
        return resolve_location(self.state["root"], raw_path, line, column)


class ManagedDebugger:
    def __init__(self, config: dict[str, Any]) -> None:
        self.state = {
            "root": config["root"],
            "tool": config["tool"],
            "target": config.get("target") or "",
            "displayTarget": config.get("displayTarget") or "",
            "entryPath": config.get("entryPath") or "",
            "line": config.get("line"),
            "column": config.get("column"),
            "lineApplied": bool(config.get("lineApplied")),
            "argv": config.get("argv") or [],
            "commandText": config.get("commandText") or "",
            "startedAt": config.get("startedAt") or iso_now(),
            "endedAt": "",
            "exitCode": None,
            "status": "managed-starting",
            "active": True,
            "metaFile": config["metaFile"],
            "socketFile": config["socketFile"],
            "summaryReport": config["summaryReport"],
            "detailsReport": config["detailsReport"],
            "managerPid": os.getpid(),
            "childPid": None,
            "lastCommand": "",
            "lastCommandAt": "",
            "lastStopLocation": "",
            "outputExcerpt": [],
            "breakpoints": [],
            "watches": [],
        }
        self.adapter = DebugAdapter(self.state["tool"], self.state)
        self.master_fd = -1
        self.process: subprocess.Popen[str] | None = None
        self.breakpoint_seq = 0
        self.watch_seq = 0

    def spawn(self) -> None:
        master_fd, slave_fd = pty.openpty()
        argv = [str(part) for part in self.state["argv"]]
        self.process = subprocess.Popen(
            argv,
            cwd=self.state["root"],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            text=False,
            start_new_session=True,
        )
        os.close(slave_fd)
        self.master_fd = master_fd
        os.set_blocking(self.master_fd, False)
        self.state["childPid"] = self.process.pid
        initial = self.read_until_prompt(20.0)
        append_transcript(self.state, "session-start", initial)
        self.refresh_location(initial)
        for command, title in self.adapter.launch_commands():
            response = self.issue_command(command, title)
            if response["error"]:
                raise RuntimeError(response["error"])
        self.state["status"] = "managed-paused" if self.process and self.process.poll() is None else "managed-exited"
        write_meta(self.state)

    def read_until_prompt(self, timeout_seconds: float) -> str:
        deadline = time.time() + timeout_seconds
        chunks: list[str] = []
        prompt = self.adapter.prompt_text()
        while time.time() < deadline:
            if self.master_fd >= 0:
                ready, _, _ = select.select([self.master_fd], [], [], 0.1)
                if ready:
                    try:
                        data = os.read(self.master_fd, 4096)
                    except BlockingIOError:
                        data = b""
                    if data:
                        chunks.append(data.decode("utf-8", errors="replace"))
                        normalized = normalize_output("".join(chunks))
                        if prompt in normalized:
                            return "".join(chunks)
            if self.process and self.process.poll() is not None:
                self.finalize_process()
                break
        return "".join(chunks)

    def refresh_location(self, output: str) -> None:
        location = self.adapter.parse_location(output)
        if location["location"]:
            self.state["lastStopLocation"] = location["location"]

    def current_breakpoint(self, identifier: str) -> dict[str, Any] | None:
        identifier = clean_text(identifier)
        for row in self.state["breakpoints"]:
            if clean_text(row.get("id")) == identifier or clean_text(row.get("location")) == identifier:
                return row
        return None

    def current_watch(self, identifier: str) -> dict[str, Any] | None:
        identifier = clean_text(identifier)
        for row in self.state["watches"]:
            if clean_text(row.get("id")) == identifier or clean_text(row.get("expression")) == identifier:
                return row
        return None

    def evaluate_watches(self) -> None:
        if not self.state["active"] or not self.state["watches"]:
            return
        for row in self.state["watches"]:
            response = self.issue_command(self.adapter.inspect_command(row["expression"]), f"watch {row['expression']}", evaluate_watches=False)
            row["lastValue"] = clean_text("\n".join(response["outputExcerpt"]))
            row["lastError"] = clean_text(response["error"])

    def finalize_process(self) -> None:
        if not self.process:
            return
        if self.state.get("endedAt"):
            return
        exit_code = self.process.poll()
        if exit_code is None:
            return
        self.state["active"] = False
        self.state["exitCode"] = exit_code
        self.state["endedAt"] = iso_now()
        if exit_code == 0:
            self.state["status"] = "managed-success"
        elif exit_code == 130:
            self.state["status"] = "managed-interrupted"
        else:
            self.state["status"] = "managed-failed"
        append_result(self.state)
        write_summary(self.state)
        write_meta(self.state)
        try:
            os.unlink(self.state["socketFile"])
        except FileNotFoundError:
            pass

    def issue_command(
        self,
        command: str,
        title: str,
        evaluate_watches: bool = True,
        timeout_seconds: float = 20.0,
    ) -> dict[str, Any]:
        if not self.state["active"]:
            return {
                "ok": False,
                "error": "No active managed debug session.",
                "outputExcerpt": [],
                "location": self.state.get("lastStopLocation") or "",
                "active": False,
            }
        assert self.process is not None
        os.write(self.master_fd, (command + "\n").encode("utf-8"))
        output = self.read_until_prompt(timeout_seconds)
        append_transcript(self.state, title, f"$ {command}\n{output}")
        self.state["lastCommand"] = command
        self.state["lastCommandAt"] = iso_now()
        self.state["outputExcerpt"] = excerpt_lines(output)
        self.refresh_location(output)
        if self.process.poll() is not None:
            self.finalize_process()
        else:
            self.state["status"] = "managed-paused"
            if evaluate_watches:
                self.evaluate_watches()
            write_meta(self.state)
        return {
            "ok": self.state["active"] or self.state["exitCode"] == 0,
            "error": "" if self.state["active"] or self.state["exitCode"] == 0 else f"Debugger exited with {self.state['exitCode']}",
            "outputExcerpt": list(self.state.get("outputExcerpt") or []),
            "location": self.state.get("lastStopLocation") or "",
            "active": bool(self.state.get("active")),
        }

    def handle_request(self, request: dict[str, Any]) -> dict[str, Any]:
        action = clean_text(request.get("action"))
        if action == "status":
            if self.process and self.process.poll() is not None:
                self.finalize_process()
            write_meta(self.state)
            return {"ok": True, "session": meta_payload(self.state)}
        if action in {"continue", "next", "step", "out", "stack"}:
            command = self.adapter.control_command(action)
            response = self.issue_command(command, action)
            response["session"] = meta_payload(self.state)
            return response
        if action == "inspect":
            expression = clean_text(request.get("expression"))
            if not expression:
                return {"ok": False, "error": "inspect requires an expression"}
            response = self.issue_command(self.adapter.inspect_command(expression), f"inspect {expression}", evaluate_watches=False)
            response["session"] = meta_payload(self.state)
            return response
        if action == "breakpoint-add":
            spec = clean_text(request.get("spec"))
            normalized = normalize_breakpoint_spec(self.state["root"], spec)
            if not normalized:
                return {"ok": False, "error": "breakpoint add requires path:line"}
            command = self.adapter.breakpoint_add_command(normalized["commandSpec"])
            response = self.issue_command(command, f"breakpoint add {normalized['location']}")
            if response["ok"]:
                self.breakpoint_seq += 1
                self.state["breakpoints"].append(
                    {
                        "id": str(self.breakpoint_seq),
                        "backendId": self.adapter.parse_breakpoint_backend_id("\n".join(response["outputExcerpt"])),
                        "spec": normalized["commandSpec"],
                        "location": normalized["location"],
                    }
                )
                write_meta(self.state)
            response["session"] = meta_payload(self.state)
            return response
        if action == "breakpoint-list":
            return {"ok": True, "breakpoints": self.state["breakpoints"], "session": meta_payload(self.state)}
        if action == "breakpoint-remove":
            identifier = clean_text(request.get("identifier"))
            row = self.current_breakpoint(identifier)
            if not row:
                return {"ok": False, "error": f"Unknown breakpoint: {identifier}"}
            response = self.issue_command(self.adapter.breakpoint_remove_command(row), f"breakpoint remove {identifier}")
            if response["ok"]:
                self.state["breakpoints"] = [item for item in self.state["breakpoints"] if item != row]
                write_meta(self.state)
            response["session"] = meta_payload(self.state)
            return response
        if action == "watch-add":
            expression = clean_text(request.get("expression"))
            if not expression:
                return {"ok": False, "error": "watch add requires an expression"}
            self.watch_seq += 1
            self.state["watches"].append(
                {
                    "id": str(self.watch_seq),
                    "expression": expression,
                    "lastValue": "",
                    "lastError": "",
                }
            )
            self.evaluate_watches()
            write_meta(self.state)
            return {"ok": True, "watches": self.state["watches"], "session": meta_payload(self.state)}
        if action == "watch-list":
            self.evaluate_watches()
            write_meta(self.state)
            return {"ok": True, "watches": self.state["watches"], "session": meta_payload(self.state)}
        if action == "watch-remove":
            identifier = clean_text(request.get("identifier"))
            row = self.current_watch(identifier)
            if not row:
                return {"ok": False, "error": f"Unknown watch: {identifier}"}
            self.state["watches"] = [item for item in self.state["watches"] if item != row]
            write_meta(self.state)
            return {"ok": True, "watches": self.state["watches"], "session": meta_payload(self.state)}
        if action == "stop":
            response = self.issue_command(
                self.adapter.stop_command(),
                "stop",
                evaluate_watches=False,
                timeout_seconds=2.0,
            )
            if self.process and self.process.poll() is None:
                try:
                    self.process.terminate()
                    self.process.wait(timeout=2)
                except Exception:
                    try:
                        self.process.kill()
                    except Exception:
                        pass
            self.finalize_process()
            response["session"] = meta_payload(self.state)
            return response
        return {"ok": False, "error": f"Unknown managed debug action: {action}"}

    def serve(self) -> None:
        socket_path = pathlib.Path(self.state["socketFile"])
        try:
            socket_path.unlink()
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(socket_path))
        server.listen(4)
        try:
            self.spawn()
            while True:
                if self.process and self.process.poll() is not None:
                    self.finalize_process()
                    break
                ready, _, _ = select.select([server], [], [], 0.2)
                if not ready:
                    continue
                conn, _ = server.accept()
                with conn:
                    raw = conn.recv(65536)
                    try:
                        request = json.loads(raw.decode("utf-8"))
                    except Exception:
                        conn.sendall(json.dumps({"ok": False, "error": "invalid request"}).encode("utf-8"))
                        continue
                    response = self.handle_request(request)
                    conn.sendall(json.dumps(response).encode("utf-8"))
                    if clean_text(request.get("action")) == "stop":
                        break
        finally:
            try:
                server.close()
            except Exception:
                pass
            try:
                socket_path.unlink()
            except FileNotFoundError:
                pass
            self.finalize_process()


def load_json(path: str) -> dict[str, Any]:
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"Unable to read JSON payload {path}: {exc}", 2)
    return {}


def launch() -> None:
    plan = json.loads(os.environ.get("YEN_DEBUG_SESSION_PLAN") or "{}")
    root = clean_text(plan.get("root"))
    tool = clean_text(plan.get("tool"))
    if not root or not tool:
        fail("Managed debug launch requires a resolved plan.", 2)
    meta_file = clean_text(os.environ.get("YEN_DEBUG_SESSION_META_FILE"))
    socket_file = clean_text(os.environ.get("YEN_DEBUG_SESSION_SOCKET_FILE"))
    summary_report = clean_text(os.environ.get("YEN_DEBUG_SESSION_SUMMARY_REPORT"))
    details_report = clean_text(os.environ.get("YEN_DEBUG_SESSION_DETAILS_REPORT"))
    started_at = clean_text(os.environ.get("YEN_DEBUG_SESSION_STARTED_AT")) or iso_now()
    command_text = clean_text(os.environ.get("YEN_DEBUG_SESSION_COMMAND_TEXT"))
    config = {
        "root": root,
        "tool": tool,
        "target": plan.get("target") or "",
        "displayTarget": plan.get("displayTarget") or "",
        "entryPath": plan.get("entryPath") or "",
        "line": plan.get("line"),
        "column": plan.get("column"),
        "lineApplied": bool(plan.get("lineApplied")),
        "argv": plan.get("argv") or [],
        "metaFile": meta_file,
        "socketFile": socket_file,
        "summaryReport": summary_report,
        "detailsReport": details_report,
        "startedAt": started_at,
        "commandText": command_text,
    }
    config_path = pathlib.Path(meta_file + ".launch.json")
    atomic_write_text(config_path, json.dumps(config, indent=2, sort_keys=True) + "\n")
    subprocess.Popen(
        [sys.executable, __file__, "daemon", str(config_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 20
    while time.time() < deadline:
        if pathlib.Path(meta_file).is_file():
            payload = load_json(meta_file)
            if pathlib.Path(socket_file).exists():
                print(json.dumps(payload, indent=2, sort_keys=True))
                return
            if payload.get("error"):
                fail(clean_text(payload.get("error")), 2)
        time.sleep(0.1)
    fail("Managed debug session did not become ready in time.", 2)


def daemon(config_path: str) -> None:
    config = load_json(config_path)
    try:
        ManagedDebugger(config).serve()
    except Exception as exc:
        write_launch_failure(clean_text(config.get("metaFile")), config, str(exc))
        raise


def request() -> None:
    if len(sys.argv) < 4:
        fail("Usage: debug-session-helper.py request <socket> <json-request>", 64)
    socket_path = sys.argv[2]
    request_payload = sys.argv[3]
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(socket_path)
        client.sendall(request_payload.encode("utf-8"))
        response = client.recv(65536)
    except FileNotFoundError:
        fail("Managed debug session socket is missing.", 2)
    finally:
        try:
            client.close()
        except Exception:
            pass
    print(response.decode("utf-8"))


def transcript() -> None:
    if len(sys.argv) < 3:
        fail("Usage: debug-session-helper.py transcript <path> [tail]", 64)
    path = pathlib.Path(sys.argv[2])
    tail = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 0
    if not path.is_file():
        fail(f"Transcript is missing: {path}", 2)
    lines = path.read_text(encoding="utf-8").splitlines()
    if tail > 0:
        lines = lines[-tail:]
    print("\n".join(lines))


def main() -> None:
    if len(sys.argv) < 2:
        fail("Usage: debug-session-helper.py <launch|daemon|request|transcript>", 64)
    command = sys.argv[1]
    if command == "launch":
        launch()
        return
    if command == "daemon":
        if len(sys.argv) < 3:
            fail("Usage: debug-session-helper.py daemon <config-path>", 64)
        daemon(sys.argv[2])
        return
    if command == "request":
        request()
        return
    if command == "transcript":
        transcript()
        return
    fail(f"Unknown command: {command}", 64)


if __name__ == "__main__":
    main()
