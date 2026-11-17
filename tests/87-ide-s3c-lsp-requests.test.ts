import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

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

function commandOutput(result: ReturnType<typeof runYen>): string {
	return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
}

function parseJsonOutput(result: ReturnType<typeof runYen>) {
	return JSON.parse(result.stdout || "{}");
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"lsp-request-fixture"}\n',
		"utf8",
	);
	const sourcePath = join(root, "src/app.ts");
	mkdirSync(dirname(sourcePath), { recursive: true });
	writeFileSync(
		sourcePath,
		"export const oldName = 1;\nconsole.log(oldName)\n",
		"utf8",
	);
	return { root, sourcePath };
}

function writeInteractiveServer(path: string) {
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

def publish(uri, text):
    message = "Updated failure" if "newName" in text or "renamedValue" in text or "preferredName" in text else "Initial failure"
    send({
        "jsonrpc": "2.0",
        "method": "textDocument/publishDiagnostics",
        "params": {
            "uri": uri,
            "diagnostics": [
                {
                    "range": {
                        "start": {"line": 0, "character": 13},
                        "end": {"line": 0, "character": 20}
                    },
                    "severity": 1,
                    "code": "REQ1001",
                    "source": "fake-lsp-requests",
                    "message": message
                }
            ]
        }
    })

documents = {}

while True:
    message = read_message()
    if message is None:
        break
    method = message.get("method")
    if method == "initialize":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {"capabilities": {"textDocumentSync": 1, "codeActionProvider": True}}
        })
    elif method == "textDocument/didOpen":
        doc = message["params"]["textDocument"]
        documents[doc["uri"]] = doc["text"]
        publish(doc["uri"], doc["text"])
    elif method == "textDocument/didChange":
        uri = message["params"]["textDocument"]["uri"]
        changes = message["params"].get("contentChanges") or []
        text = changes[0].get("text", "") if changes else ""
        documents[uri] = text
        publish(uri, text)
    elif method == "textDocument/hover":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {"contents": "hover type: number"}
        })
    elif method == "textDocument/definition":
        uri = message["params"]["textDocument"]["uri"]
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "uri": uri,
                "range": {
                    "start": {"line": 0, "character": 13},
                    "end": {"line": 0, "character": 20}
                }
            }
        })
    elif method == "textDocument/references":
        uri = message["params"]["textDocument"]["uri"]
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": [
                {
                    "uri": uri,
                    "range": {
                        "start": {"line": 0, "character": 13},
                        "end": {"line": 0, "character": 20}
                    }
                },
                {
                    "uri": uri,
                    "range": {
                        "start": {"line": 1, "character": 12},
                        "end": {"line": 1, "character": 19}
                    }
                }
            ]
        })
    elif method == "textDocument/rename":
        uri = message["params"]["textDocument"]["uri"]
        new_name = message["params"]["newName"]
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {
                "changes": {
                    uri: [
                        {
                            "range": {
                                "start": {"line": 0, "character": 13},
                                "end": {"line": 0, "character": 20}
                            },
                            "newText": new_name
                        },
                        {
                            "range": {
                                "start": {"line": 1, "character": 12},
                                "end": {"line": 1, "character": 19}
                            },
                            "newText": new_name
                        }
                    ]
                }
            }
        })
    elif method == "textDocument/codeAction":
        uri = message["params"]["textDocument"]["uri"]
        position = (message["params"].get("range") or {}).get("start") or {}
        if position.get("line") == 0 and position.get("character") == 12:
            send({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": [
                    {
                        "title": "Rewrite and run follow-up command",
                        "kind": "refactor.rewrite",
                        "edit": {
                            "changes": {
                                uri: [
                                    {
                                        "range": {
                                            "start": {"line": 0, "character": 13},
                                            "end": {"line": 0, "character": 20}
                                        },
                                        "newText": "comboName"
                                    }
                                ]
                            }
                        },
                        "command": {
                            "title": "Run follow-up",
                            "command": "fake.editPlusCommand"
                        }
                    }
                ]
            })
            continue
        if position.get("line") != 0 or position.get("character") != 13:
            send({
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": []
            })
            continue
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": [
                {
                    "title": "Promote to preferredName",
                    "kind": "quickfix",
                    "isPreferred": True,
                    "edit": {
                        "changes": {
                            uri: [
                                {
                                    "range": {
                                        "start": {"line": 0, "character": 13},
                                        "end": {"line": 0, "character": 20}
                                    },
                                    "newText": "preferredName"
                                },
                                {
                                    "range": {
                                        "start": {"line": 1, "character": 12},
                                        "end": {"line": 1, "character": 19}
                                    },
                                    "newText": "preferredName"
                                }
                            ]
                        }
                    }
                },
                {
                    "title": "Promote to alternateName",
                    "kind": "refactor.rewrite",
                    "edit": {
                        "changes": {
                            uri: [
                                {
                                    "range": {
                                        "start": {"line": 0, "character": 13},
                                        "end": {"line": 0, "character": 20}
                                    },
                                    "newText": "alternateName"
                                },
                                {
                                    "range": {
                                        "start": {"line": 1, "character": 12},
                                        "end": {"line": 1, "character": 19}
                                    },
                                    "newText": "alternateName"
                                }
                            ]
                        }
                    }
                },
                {
                    "title": "Record command-only action",
                    "command": "fake.commandOnly",
                    "arguments": [uri, documents.get(uri, "")]
                }
            ]
        })
`,
		"utf8",
	);
}

function writeSlowInteractiveServer(path: string) {
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
        time.sleep(4.0)
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {"capabilities": {"textDocumentSync": 1}}
        })
    elif method == "textDocument/hover":
        send({
            "jsonrpc": "2.0",
            "id": message["id"],
            "result": {"contents": "slow hover"}
        })
`,
		"utf8",
	);
}

describe("IDE S3C interactive LSP surfaces", () => {
	test(
		"hover/definition/references/rename and live diagnostics updates work through the local daemon",
		async () => {
			const stateDir = ideTemp("yen-ide-lsp-request-state-");
			const { root: project, sourcePath } = createProject(
				"yen-ide-lsp-request-project-",
			);
			const fakeServer = join(stateDir, "fake-lsp-requests.py");
			writeInteractiveServer(fakeServer);

			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_LSP_SERVER_CMD: `python3 ${fakeServer}`,
				YEN_IDE_LSP_SERVER_LABEL: "fake-lsp-requests",
				YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
				YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
			};

			expect(
				runYen(["ide", "lsp", "trust", "--project", project], env).status,
			).toBe(0);
			expect(
				runYen(["ide", "lsp", "start", "--project", project], env).status,
			).toBe(0);

			const hover = runYen(["ide", "lsp", "hover", `${sourcePath}:1:14`], env);
			const hoverOutput = commandOutput(hover);
			expect(hover.status).toBe(0);
			expect(hoverOutput).toContain("IDE LSP Hover");
			expect(hoverOutput).toContain("Source:    lsp");
			expect(hoverOutput).toContain("hover type: number");

			const definition = runYen(
				["ide", "lsp", "definition", `${sourcePath}:1:14`],
				env,
			);
			const definitionOutput = commandOutput(definition);
			expect(definition.status).toBe(0);
			expect(definitionOutput).toContain(`${sourcePath}:1:14`);

			const references = runYen(
				["ide", "lsp", "references", `${sourcePath}:1:14`],
				env,
			);
			const referencesOutput = commandOutput(references);
			expect(references.status).toBe(0);
			expect(referencesOutput).toContain(`${sourcePath}:1:14`);
			expect(referencesOutput).toContain(`${sourcePath}:2:13`);

			const renamePreview = runYen(
				["ide", "lsp", "rename", `${sourcePath}:1:14`, "--new-name", "newName"],
				env,
			);
			const renamePreviewOutput = commandOutput(renamePreview);
			expect(renamePreview.status).toBe(0);
			expect(renamePreviewOutput).toContain("Applied:   no");
			expect(renamePreviewOutput).toContain("Edits:     2");

			const renameWrite = runYen(
				[
					"ide",
					"lsp",
					"rename",
					`${sourcePath}:1:14`,
					"--new-name",
					"newName",
					"--write",
				],
				env,
			);
			const renameWriteOutput = commandOutput(renameWrite);
			expect(renameWrite.status).toBe(0);
			expect(renameWriteOutput).toContain("Applied:   yes");
			expect(readFileSync(sourcePath, "utf8")).toContain("newName");

			const codeActionsPreview = runYen(
				["ide", "lsp", "code-actions", `${sourcePath}:1:14`],
				env,
			);
			const codeActionsPreviewOutput = commandOutput(codeActionsPreview);
			expect(codeActionsPreview.status).toBe(0);
			expect(codeActionsPreviewOutput).toContain("IDE LSP Code Actions");
			expect(codeActionsPreviewOutput).toContain("Selection: preferred");
			expect(codeActionsPreviewOutput).toContain("Promote to preferredName");
			expect(codeActionsPreviewOutput).toContain("Promote to alternateName");
			expect(codeActionsPreviewOutput).toContain("Record command-only action");
			expect(codeActionsPreviewOutput).toContain(
				"Auto-apply candidate: #1 Promote to preferredName",
			);

			const codeActionsJson = runYen(
				[
					"ide",
					"lsp",
					"code-actions",
					`${sourcePath}:1:14`,
					"--format",
					"json",
				],
				env,
			);
			expect(codeActionsJson.status).toBe(0);
			const codeActionsPayload = parseJsonOutput(codeActionsJson);
			expect(codeActionsPayload.summary.actionCount).toBe(3);
			expect(codeActionsPayload.summary.selectableEditCount).toBe(2);
			expect(codeActionsPayload.selection.status).toBe("preferred");
			expect(codeActionsPayload.selection.selectedIndex).toBe(1);
			expect(codeActionsPayload.actions[2].applyMode).toBe("command");

			const codeActionsApply = runYen(
				["ide", "lsp", "code-actions", `${sourcePath}:1:14`, "--apply"],
				env,
			);
			const codeActionsApplyOutput = commandOutput(codeActionsApply);
			expect(codeActionsApply.status).toBe(0);
			expect(codeActionsApplyOutput).toContain("Applied:   yes");
			expect(codeActionsApplyOutput).toContain(
				"Selected:  #1 Promote to preferredName",
			);
			expect(readFileSync(sourcePath, "utf8")).toContain("preferredName");

			const codeActionsApplyNone = runYen(
				[
					"ide",
					"lsp",
					"code-actions",
					`${sourcePath}:1:1`,
					"--apply",
					"--format",
					"json",
				],
				env,
			);
			expect(codeActionsApplyNone.status).toBe(1);
			const codeActionsApplyNonePayload = parseJsonOutput(codeActionsApplyNone);
			expect(codeActionsApplyNonePayload.summary.actionCount).toBe(0);
			expect(codeActionsApplyNonePayload.selection.status).toBe("none");
			expect(codeActionsApplyNonePayload.error).toContain(
				"No code actions are available",
			);

			const codeActionsApplyNeedsCommand = runYen(
				[
					"ide",
					"lsp",
					"code-actions",
					`${sourcePath}:1:13`,
					"--apply",
					"--format",
					"json",
				],
				env,
			);
			expect(codeActionsApplyNeedsCommand.status).toBe(1);
			const codeActionsApplyNeedsCommandPayload = parseJsonOutput(
				codeActionsApplyNeedsCommand,
			);
			expect(codeActionsApplyNeedsCommandPayload.selection.status).toBe(
				"needs-command",
			);
			expect(codeActionsApplyNeedsCommandPayload.actions[0].applyMode).toBe(
				"edit+command",
			);
			expect(codeActionsApplyNeedsCommandPayload.error).toContain(
				"combine edits with commands",
			);

			const codeActionsInvalidFormat = runYen(
				[
					"ide",
					"lsp",
					"code-actions",
					`${sourcePath}:1:14`,
					"--format",
					"yaml",
				],
				env,
			);
			expect(codeActionsInvalidFormat.status).toBe(1);
			expect(commandOutput(codeActionsInvalidFormat)).toContain(
				"Unknown code-actions format: yaml (expected text|json)",
			);

			for (let attempt = 0; attempt < 20; attempt += 1) {
				const diagnostics = runYen(
					["ide", "lsp", "diagnostics", "--project", project],
					env,
				);
				const diagnosticsOutput = commandOutput(diagnostics);
				if (diagnosticsOutput.includes("Updated failure")) {
					break;
				}
				await delay(120);
			}

			const diagnostics = runYen(
				["ide", "lsp", "diagnostics", "--project", project],
				env,
			);
			const diagnosticsOutput = commandOutput(diagnostics);
			expect(diagnostics.status).toBe(0);
			expect(diagnosticsOutput).toContain("Updated failure");

			const diagnosticSearch = runYen(
				[
					"ide",
					"search",
					"Updated",
					"--sources",
					"diagnostics",
					"--project",
					project,
				],
				env,
			);
			const searchOutput = commandOutput(diagnosticSearch);
			expect(diagnosticSearch.status).toBe(0);
			expect(searchOutput).toContain("diagnostic");
			expect(searchOutput).toContain("Updated failure");

			const installStatus = runYen(
				["ide", "lsp", "install", "status", "--all"],
				env,
			);
			const installStatusOutput = commandOutput(installStatus);
			expect(installStatus.status).toBe(0);
			expect(installStatusOutput).toContain("typescript");
			expect(installStatusOutput).toContain("managed-npm-prefix");
			expect(installStatusOutput).toContain("toolchain-path");

			expect(
				runYen(["ide", "lsp", "stop", "--project", project], env).status,
			).toBe(0);
		},
		{ timeout: 15_000 },
	);

	test(
		"interactive requests reject booting runtimes until the initialize handshake finishes",
		async () => {
			const stateDir = ideTemp("yen-ide-lsp-booting-state-");
			const { root: project, sourcePath } = createProject(
				"yen-ide-lsp-booting-project-",
			);
			const fakeServer = join(stateDir, "fake-lsp-booting.py");
			writeSlowInteractiveServer(fakeServer);

			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_LSP_SERVER_CMD: `python3 ${fakeServer}`,
				YEN_IDE_LSP_SERVER_LABEL: "fake-lsp-booting",
				YEN_IDE_LSP_SERVER_LANGUAGE_ID: "typescript",
				YEN_IDE_LSP_SERVER_EXTENSIONS: ".ts",
			};

			expect(
				runYen(["ide", "lsp", "trust", "--project", project], env).status,
			).toBe(0);

			const start = spawn(
				yenBinPath,
				["ide", "lsp", "start", "--project", project],
				{
					cwd: repoRoot,
					env: {
						...process.env,
						...env,
					},
					stdio: ["ignore", "pipe", "pipe"],
				},
			);

			let sawBooting = false;
			for (let attempt = 0; attempt < 20; attempt += 1) {
				const status = runYen(
					["ide", "lsp", "status", "--project", project, "--format", "env"],
					env,
				);
				const statusOutput = commandOutput(status);
				if (statusOutput.includes("YEN_IDE_LSP_PROTOCOL_STATUS='booting'")) {
					sawBooting = true;
					break;
				}
				await delay(80);
			}
			expect(sawBooting).toBe(true);

			const hoverDuringBoot = runYen(
				["ide", "lsp", "hover", `${sourcePath}:1:14`],
				env,
			);
			const hoverDuringBootOutput = commandOutput(hoverDuringBoot);
			expect(hoverDuringBoot.status).toBe(1);
			expect(hoverDuringBootOutput).toContain("still booting");

			await new Promise<void>((resolve, reject) => {
				start.on("error", reject);
				start.on("close", (code) => {
					if (code === 0) {
						resolve();
						return;
					}
					reject(new Error(`yen ide lsp start exited with ${code}`));
				});
			});

			const hoverAfterReady = runYen(
				["ide", "lsp", "hover", `${sourcePath}:1:14`],
				env,
			);
			expect(hoverAfterReady.status).toBe(0);
			expect(commandOutput(hoverAfterReady)).toContain("slow hover");

			expect(
				runYen(["ide", "lsp", "stop", "--project", project], env).status,
			).toBe(0);
		},
		{ timeout: 15_000 },
	);
});
