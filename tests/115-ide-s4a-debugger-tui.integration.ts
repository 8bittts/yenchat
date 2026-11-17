import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

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

function projectHash(root: string) {
	return createHash("sha256").update(root).digest("hex");
}

function createPythonProject(prefix: string) {
	const project = ideTemp(prefix);
	writeFileSync(
		join(project, "main.py"),
		[
			"def main():",
			"    value = 1",
			"    second = value + 2",
			"    print(second)",
			"main()",
			"",
		].join("\n"),
		"utf8",
	);
	return realpathSync(project);
}

function createNodeDevcontainerProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	mkdirSync(join(project, ".devcontainer"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		`${JSON.stringify(
			{ name: prefix, scripts: { start: "node src/app.js" } },
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(project, ".devcontainer", "devcontainer.json"),
		`${JSON.stringify(
			{
				name: "debug-tui",
				image: "mcr.microsoft.com/devcontainers/base:ubuntu",
				workspaceFolder: "/workspace/debug",
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(project, "src", "app.js"),
		[
			"function main() {",
			"  const value = 1;",
			"  const second = value + 2;",
			"  console.log(second);",
			"}",
			"main();",
			"",
		].join("\n"),
		"utf8",
	);
	return realpathSync(project);
}

function writeFakeSSH(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
if [ "$1" = "-p" ]; then
  shift 2
fi
shift
exec "$@"
`,
		"utf8",
	);
	chmodSync(path, 0o755);
}

function writeFakeDevcontainer(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
if [ "$1" = "--version" ]; then
  echo "devcontainer 1.0.0"
  exit 0
fi
action="$1"
shift || true
workspace=""
if [ "$1" = "--workspace-folder" ]; then
  workspace="$2"
  shift 2
fi
case "$action" in
  exec)
    cd "$workspace" 2>/dev/null || true
    exec "$@"
    ;;
  *)
    printf "unsupported action: %s\\n" "$action" >&2
    exit 1
    ;;
esac
`,
		"utf8",
	);
	chmodSync(path, 0o755);
}

function seedDevcontainerState(
	stateDir: string,
	hashSeed: string,
	specRoot: string,
	workspaceFolder: string,
	cli: string,
) {
	const hash = projectHash(hashSeed);
	const devcontainerStateDir = join(stateDir, "devcontainer", hash);
	mkdirSync(devcontainerStateDir, { recursive: true });
	writeFileSync(
		join(devcontainerStateDir, "state.env"),
		[
			"status=running",
			`root=${hashSeed}`,
			`cli=${cli}`,
			`spec=${join(specRoot, ".devcontainer", "devcontainer.json")}`,
			"unsafe=none",
			"started_at=2026-03-23T00:00:00Z",
			"last_command=devcontainer up",
			"health=healthy",
			`workspace_folder=${workspaceFolder}`,
			"forward_ports=3000|9229",
			"",
		].join("\n"),
		"utf8",
	);
}

describe("IDE S4A debugger TUI parity", () => {
	test(
		"debug tui renders active managed-session source, transcript, breakpoints, watches, and live controls",
		() => {
			const stateDir = ideTemp("yen-ide-debug-tui-state-");
			const project = createPythonProject("yen-ide-debug-tui-python-");
			const env = { YEN_IDE_STATE_DIR: stateDir };

			expect(
				runYen(["ide", "debug", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(
					[
						"ide",
						"debug",
						"start",
						"main.py:3",
						"--managed",
						"--project",
						project,
					],
					env,
					project,
				).status,
			).toBe(0);
			expect(
				runYen(
					[
						"ide",
						"debug",
						"breakpoint",
						"add",
						"main.py:4",
						"--project",
						project,
						"--format",
						"json",
					],
					env,
					project,
				).status,
			).toBe(0);
			expect(
				runYen(
					[
						"ide",
						"debug",
						"watch",
						"add",
						"value",
						"--project",
						project,
						"--format",
						"json",
					],
					env,
					project,
				).status,
			).toBe(0);

			const jsonRes = runYen(
				["ide", "debug", "tui", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(jsonRes.status).toBe(0);
			const payload = JSON.parse(`${jsonRes.stdout ?? ""}`.trim());
			expect(payload.mode).toBe("debug-tui");
			expect(payload.session.active).toBe(true);
			expect(payload.session.location).toBe("main.py:3");
			expect(payload.sourceExcerpt.available).toBe(true);
			expect(payload.sourceExcerpt.lines).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						lineNumber: 3,
						current: true,
						text: "    second = value + 2",
					}),
				]),
			);
			expect(payload.session.breakpoints).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						location: "main.py:4",
					}),
				]),
			);
			expect(payload.session.watches).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						expression: "value",
						lastValue: expect.stringContaining("1"),
					}),
				]),
			);
			expect(payload.transcriptTail.available).toBe(true);
			expect(payload.transcriptTail.lines.join("\n")).toContain(
				"session-start",
			);
			expect(payload.controls).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "continue",
						available: true,
					}),
					expect.objectContaining({
						id: "breakpoint-add",
						available: true,
					}),
				]),
			);
			expect(payload.status.blockedTopologies).toContain(
				"zero-config adapter installs beyond the shipped Python/Node/LLDB baseline",
			);

			const textRes = runYen(
				["ide", "debug", "tui", "--project", project],
				env,
				project,
			);
			expect(textRes.status).toBe(0);
			expect(textRes.stdout).toContain("IDE Debug TUI");
			expect(textRes.stdout).toContain("Source Excerpt:");
			expect(textRes.stdout).toContain(">    3 |     second = value + 2");
			expect(textRes.stdout).toContain("[ready] Continue:");

			expect(
				runYen(["ide", "debug", "stop", "--project", project], env, project)
					.status,
			).toBe(0);
		},
		{ timeout: 15000 },
	);

	test(
		"debug tui keeps remote devcontainer source rendering honest while preserving the shared control commands",
		() => {
			const stateDir = ideTemp("yen-ide-debug-tui-remote-");
			const project = createNodeDevcontainerProject("yen-ide-debug-tui-node-");
			const remoteTarget = `ssh://dev@example.test${join(project, "src", "app.js")}?label=container`;
			const remoteIdentity = `ssh://dev@example.test${project}?label=container`;
			const sshBinDir = ideTemp("yen-ide-debug-tui-ssh-");
			const fakeDevcontainerPath = join(sshBinDir, "devcontainer");
			writeFakeSSH(join(sshBinDir, "ssh"));
			writeFakeDevcontainer(fakeDevcontainerPath);
			seedDevcontainerState(
				stateDir,
				remoteIdentity,
				project,
				"/workspace/debug",
				fakeDevcontainerPath,
			);
			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_DEVCONTAINER_CMD: fakeDevcontainerPath,
			};

			expect(
				runYen(["ide", "devcontainer", "trust", remoteTarget], env).status,
			).toBe(0);

			const res = runYen(
				[
					"ide",
					"debug",
					"tui",
					remoteTarget,
					"--devcontainer",
					"--format",
					"json",
				],
				env,
			);
			expect(res.status).toBe(0);
			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			expect(payload.executionTarget).toBe("devcontainer");
			expect(payload.workspace.executionLocation).toBe("remote");
			expect(payload.sourceExcerpt.available).toBe(false);
			expect(payload.sourceExcerpt.reason).toBe("remote-workspace");
			expect(payload.transcriptTail.available).toBe(false);
			expect(payload.controls).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "status",
						command: expect.stringContaining("--devcontainer"),
					}),
					expect.objectContaining({
						id: "managed-start",
						command: expect.stringContaining("--managed"),
					}),
				]),
			);
			expect(
				payload.controls.find(
					(row: { id: string }) => row.id === "managed-start",
				)?.command,
			).toContain("ssh://dev@example.test");
		},
		{ timeout: 15000 },
	);
});
