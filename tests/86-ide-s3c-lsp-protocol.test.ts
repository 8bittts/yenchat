import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const test = (
	name: string,
	fn: () => void | Promise<void>,
	options: { timeout?: number } = {},
) => bunTest(name, fn, { timeout: 30_000, ...options });

function delay(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	return spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"lsp-protocol-fixture"}\n',
		"utf8",
	);
	const sourcePath = join(root, "src/bad.ts");
	mkdirSync(dirname(sourcePath), { recursive: true });
	writeFileSync(
		sourcePath,
		"export const broken = () => {\n\treturn 1\n}\n",
		"utf8",
	);
	return root;
}

function writeFakeServer(path: string) {
	writeFileSync(
		path,
		`import json
import sys

def send(payload):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\\r\\n\\r\\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()

def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\\r\\n", b"\\n"):
            break
        key, value = line.decode("ascii", "replace").split(":", 1)
        headers[key.lower().strip()] = value.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body.decode("utf-8"))

while True:
    message = read_message()
    if message is None:
        break
    method = message.get("method")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "capabilities": {
                    "textDocumentSync": 1
                }
            }
        })
    elif method == "textDocument/didOpen":
        uri = message["params"]["textDocument"]["uri"]
        send({
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": {
                "uri": uri,
                "diagnostics": [
                    {
                        "range": {
                            "start": {"line": 2, "character": 4},
                            "end": {"line": 2, "character": 10}
                        },
                        "severity": 1,
                        "code": "FAKE1001",
                        "source": "fake-lsp",
                        "message": "Synthetic failure"
                    }
                ]
            }
        })
`,
		"utf8",
	);
}

function writeFailingServer(path: string) {
	writeFileSync(
		path,
		`import sys

sys.stderr.write("booting fake-lsp\\n")
sys.stderr.flush()
raise SystemExit(1)
`,
		"utf8",
	);
}

function writeCrashAfterOpenServer(path: string) {
	writeFileSync(
		path,
		`import json
import sys

def send(payload):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\\r\\n\\r\\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()

def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\\r\\n", b"\\n"):
            break
        key, value = line.decode("ascii", "replace").split(":", 1)
        headers[key.lower().strip()] = value.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body.decode("utf-8"))

while True:
    message = read_message()
    if message is None:
        break
    method = message.get("method")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "capabilities": {
                    "textDocumentSync": 1
                }
            }
        })
    elif method == "textDocument/didOpen":
        uri = message["params"]["textDocument"]["uri"]
        send({
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": {
                "uri": uri,
                "diagnostics": [
                    {
                        "range": {
                            "start": {"line": 1, "character": 1},
                            "end": {"line": 1, "character": 4}
                        },
                        "severity": 2,
                        "code": "FAKE2007",
                        "source": "fake-lsp-crash-after-open",
                        "message": "Stale crash warning"
                    }
                ]
            }
        })
        sys.stderr.write("fake crash after open\\n")
        sys.stderr.flush()
        raise SystemExit(7)
`,
		"utf8",
	);
}

function writeSlowInitializeServer(path: string) {
	writeFileSync(
		path,
		`import json
import sys
import time

def send(payload):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\\r\\n\\r\\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()

def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\\r\\n", b"\\n"):
            break
        key, value = line.decode("ascii", "replace").split(":", 1)
        headers[key.lower().strip()] = value.strip()
    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    body = sys.stdin.buffer.read(length)
    if not body:
        return None
    return json.loads(body.decode("utf-8"))

while True:
    message = read_message()
    if message is None:
        break
    method = message.get("method")
    if method == "initialize":
        time.sleep(5.5)
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "capabilities": {
                    "textDocumentSync": 1
                }
            }
        })
`,
		"utf8",
	);
}

describe("IDE S3C LSP protocol plumbing", () => {
	test("lsp start can supervise an override server and record publishDiagnostics", async () => {
		const stateDir = ideTemp("yen-ide-lsp-protocol-state-");
		const project = createProject("yen-ide-lsp-protocol-project-");
		const fakeServer = join(stateDir, "fake-lsp-server.py");
		writeFakeServer(fakeServer);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_SERVER_CMD: `python3 ${fakeServer}`,
			YEN_IDE_LSP_SERVER_LABEL: "fake-lsp",
			YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
			YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		const startOutput = `${start.stdout ?? ""}\n${start.stderr ?? ""}`;
		expect(start.status).toBe(0);
		expect(startOutput).toContain("Implementation: stdio-language-server");
		expect(startOutput).toContain("Server: fake-lsp");

		let statusOutput = "";
		let diagnosticsFile = "";
		for (let attempt = 0; attempt < 30; attempt += 1) {
			const status = runYen(
				["ide", "lsp", "status", "--project", project, "--format", "env"],
				env,
			);
			expect(status.status).toBe(0);
			statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
			diagnosticsFile =
				statusOutput.match(
					/export YEN_IDE_LSP_DIAGNOSTICS_FILE='([^']+)'/,
				)?.[1] ?? "";
			if (
				statusOutput.includes(
					"export YEN_IDE_LSP_IMPL='stdio-language-server'",
				) &&
				statusOutput.includes("export YEN_IDE_LSP_SERVER='fake-lsp'") &&
				statusOutput.includes("export YEN_IDE_LSP_DIAGNOSTICS_COUNT='1'")
			) {
				break;
			}
			await delay(100);
		}

		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_IMPL='stdio-language-server'",
		);
		expect(statusOutput).toContain("export YEN_IDE_LSP_MODE='stdio'");
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_PROTOCOL_STATUS='ready'",
		);
		expect(statusOutput).toContain("export YEN_IDE_LSP_SERVER='fake-lsp'");
		expect(statusOutput).toContain(
			`export YEN_IDE_LSP_SERVER_CMD='python3 ${fakeServer}'`,
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_LANGUAGE_ID='typescript'",
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_DIAGNOSTICS_STATUS='fresh'",
		);
		expect(statusOutput).toContain("export YEN_IDE_LSP_DIAGNOSTICS_COUNT='1'");
		expect(diagnosticsFile).not.toBe("");

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const diagnosticsOutput = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(0);
		expect(diagnosticsOutput).toContain("Synthetic failure");
		expect(diagnosticsOutput).toContain("src/bad.ts:3:5");

		const diagnosticsJson = readFileSync(diagnosticsFile, "utf8");
		expect(diagnosticsJson).toContain('"Synthetic failure"');
		expect(diagnosticsJson).toContain('"FAKE1001"');

		const stop = runYen(["ide", "lsp", "stop", "--project", project], env);
		expect(stop.status).toBe(0);
	});

	test("lsp start does not report success when a server only logs stderr before crashing", () => {
		const stateDir = ideTemp("yen-ide-lsp-protocol-fail-state-");
		const project = createProject("yen-ide-lsp-protocol-fail-project-");
		const failingServer = join(stateDir, "fake-lsp-fail.py");
		writeFailingServer(failingServer);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_SERVER_CMD: `python3 ${failingServer}`,
			YEN_IDE_LSP_SERVER_LABEL: "fake-lsp-crash",
			YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
			YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		const startOutput = `${start.stdout ?? ""}\n${start.stderr ?? ""}`;
		expect(start.status).toBe(1);
		expect(startOutput).toContain("LSP runtime failed to start");
		expect(startOutput).not.toContain("LSP runtime started");

		const status = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "json"],
			env,
		);
		expect(status.status).toBe(0);
		const statusPayload = JSON.parse(status.stdout ?? "{}");
		expect(statusPayload.runtimeState).toBe("stopped");
		const daemonLog = readFileSync(statusPayload.daemonLogFile, "utf8");
		expect(daemonLog).toContain("booting fake-lsp");
	});

	test(
		"lsp start tolerates a slow but healthy initialize handshake",
		() => {
			const stateDir = ideTemp("yen-ide-lsp-protocol-slow-state-");
			const project = createProject("yen-ide-lsp-protocol-slow-project-");
			const slowServer = join(stateDir, "fake-lsp-slow.py");
			writeSlowInitializeServer(slowServer);

			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_LSP_SERVER_CMD: `python3 ${slowServer}`,
				YEN_IDE_LSP_SERVER_LABEL: "fake-lsp-slow",
				YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
				YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
			};

			expect(
				runYen(["ide", "lsp", "trust", "--project", project], env).status,
			).toBe(0);

			const start = runYen(["ide", "lsp", "start", "--project", project], env);
			const startOutput = `${start.stdout ?? ""}\n${start.stderr ?? ""}`;
			expect(start.status).toBe(0);
			expect(startOutput).toContain("LSP runtime started");

			const status = runYen(
				["ide", "lsp", "status", "--project", project, "--format", "env"],
				env,
			);
			const statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
			expect(status.status).toBe(0);
			expect(statusOutput).toContain(
				"export YEN_IDE_LSP_PROTOCOL_STATUS='ready'",
			);
			expect(statusOutput).toContain(
				"export YEN_IDE_LSP_SERVER='fake-lsp-slow'",
			);

			expect(
				runYen(["ide", "lsp", "stop", "--project", project], env).status,
			).toBe(0);
		},
		{ timeout: 30_000 },
	);

	test("lsp status surfaces crash metadata and records lsp-crash after a supervised server exits", async () => {
		const stateDir = ideTemp("yen-ide-lsp-protocol-crash-state-");
		const project = createProject("yen-ide-lsp-protocol-crash-project-");
		const crashServer = join(stateDir, "fake-lsp-crash-after-open.py");
		writeCrashAfterOpenServer(crashServer);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_SERVER_CMD: `python3 ${crashServer}`,
			YEN_IDE_LSP_SERVER_LABEL: "fake-lsp-crash-after-open",
			YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
			YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(["ide", "lsp", "start", "--project", project], env).status,
		).toBe(0);

		let statusOutput = "";
		for (let attempt = 0; attempt < 30; attempt += 1) {
			const status = runYen(
				["ide", "lsp", "status", "--project", project, "--format", "env"],
				env,
			);
			expect(status.status).toBe(0);
			statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
			if (
				statusOutput.includes("export YEN_IDE_LSP_STATE='stale'") &&
				statusOutput.includes("export YEN_IDE_LSP_PROTOCOL_STATUS='crashed'")
			) {
				break;
			}
			await delay(100);
		}

		expect(statusOutput).toContain("export YEN_IDE_LSP_STATE='stale'");
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_PROTOCOL_STATUS='crashed'",
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_DIAGNOSTICS_STATUS='stale'",
		);
		expect(statusOutput).toContain("export YEN_IDE_LSP_CHILD_EXIT_CODE='7'");
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_LAST_ERROR='fake crash after open'",
		);

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const diagnosticsOutput = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(0);
		expect(diagnosticsOutput).toContain("Snapshot status: stale");
		expect(diagnosticsOutput).toContain(
			"showing last known diagnostics snapshot",
		);

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("\tlsp-crash\t");
		expect(timeline).toContain("server=fake-lsp-crash-after-open");
		expect(timeline).toContain("exit=7");

		expect(
			runYen(["ide", "lsp", "stop", "--project", project], env).status,
		).toBe(0);
	});
});
