import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	chmodSync,
	mkdirSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
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

function createDebugProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	mkdirSync(join(project, ".devcontainer"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		`${JSON.stringify(
			{ name: prefix, scripts: { test: "node src/app.js" } },
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(project, ".devcontainer", "devcontainer.json"),
		`${JSON.stringify(
			{
				name: "debug-devcontainer",
				image: "mcr.microsoft.com/devcontainers/base:ubuntu",
				workspaceFolder: "/workspace/debug",
				forwardPorts: [3000, 9229],
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
			"  const x = 1;",
			"  const y = x + 2;",
			"  console.log(y);",
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
authority="$1"
shift
if [ "\${YEN_FAKE_SSH_MODE:-ok}" = "fail" ]; then
  printf "%s\\n" "\${YEN_FAKE_SSH_ERROR:-remote debug probe failed}" >&2
  exit 255
fi
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
    if [ "$#" -eq 0 ]; then
      exit 0
    fi
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
	root: string,
	cli: string,
	health = "healthy",
	hashSeed = root,
	workspaceFolder = root,
) {
	const hash = projectHash(hashSeed);
	const devcontainerStateDir = join(stateDir, "devcontainer", hash);
	mkdirSync(devcontainerStateDir, { recursive: true });
	writeFileSync(
		join(devcontainerStateDir, "state.env"),
		[
			"status=running",
			`root=${root}`,
			`cli=${cli}`,
			`spec=${join(root, ".devcontainer", "devcontainer.json")}`,
			"unsafe=none",
			"started_at=2026-03-22T00:00:00Z",
			"last_command=devcontainer up",
			`health=${health}`,
			`workspace_folder=${workspaceFolder}`,
			"forward_ports=3000|9229",
			"",
		].join("\n"),
		"utf8",
	);
}

describe("IDE S3Z devcontainer debugger parity", () => {
	test(
		"local tracked devcontainer execution supports status and managed debugger launch on the shared control plane",
		() => {
			const stateDir = ideTemp("yen-ide-local-devcontainer-debug-state-");
			const project = createDebugProject(
				"yen-ide-local-devcontainer-debug-project-",
			);
			const fakeCli = join(stateDir, "fake-devcontainer");
			writeFakeDevcontainer(fakeCli);
			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_DEVCONTAINER_CMD: fakeCli,
			};

			seedDevcontainerState(stateDir, project, fakeCli);
			expect(
				runYen(["ide", "devcontainer", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "debug", "trust", project], env, project).status,
			).toBe(0);

			const status = runYen(
				[
					"ide",
					"debug",
					"status",
					"--devcontainer",
					"--project",
					project,
					"--format",
					"json",
				],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(`${status.stdout ?? ""}`.trim());
			expect(statusPayload.executionTarget).toBe("devcontainer");
			expect(statusPayload.workspace.executionLocation).toBe("local");
			expect(statusPayload.devcontainerContext.debugExecutionAvailable).toBe(
				true,
			);
			expect(statusPayload.localOnly).toBe(false);
			expect(statusPayload.guidance).toContain(
				"Tracked devcontainer debugger execution is available",
			);
			expect(statusPayload.families).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "node-inspect",
						available: true,
						recommended: true,
					}),
				]),
			);

			const start = runYen(
				[
					"ide",
					"debug",
					"start",
					"src/app.js:3",
					"--managed",
					"--devcontainer",
					"--project",
					project,
				],
				env,
				project,
			);
			expect(start.status).toBe(0);
			expect(start.stdout).toContain("Managed Debug Session");

			const during = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(during.status).toBe(0);
			const duringPayload = JSON.parse(`${during.stdout ?? ""}`.trim());
			expect(duringPayload.active).toBe(true);
			expect(duringPayload.state).toBe("managed-paused");
			expect(duringPayload.lastSession.command).toContain(fakeCli);
			expect(duringPayload.lastSession.command).toContain(
				"exec --workspace-folder",
			);

			expect(
				runYen(["ide", "debug", "stop", "--project", project], env, project)
					.status,
			).toBe(0);

			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 15000 },
	);

	test(
		"remote tracked devcontainer execution supports status and managed debugger launch over SSH without a second state model",
		() => {
			const stateDir = ideTemp("yen-ide-remote-devcontainer-debug-state-");
			const project = createDebugProject(
				"yen-ide-remote-devcontainer-debug-project-",
			);
			const fakeCli = join(stateDir, "fake-devcontainer");
			const sshBinDir = ideTemp("yen-ide-remote-devcontainer-debug-ssh-");
			writeFakeDevcontainer(fakeCli);
			writeFakeSSH(join(sshBinDir, "ssh"));
			const remoteTarget = `ssh://dev@example.test${join(project, "src", "app.js")}?label=container`;
			const remoteIdentity = `ssh://dev@example.test${project}?label=container`;
			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_REMOTE_DEVCONTAINER_CMD: fakeCli,
			};

			seedDevcontainerState(
				stateDir,
				project,
				fakeCli,
				"tracked-remote",
				remoteIdentity,
				"/workspace/debug",
			);
			expect(
				runYen(["ide", "devcontainer", "trust", remoteTarget], env, project)
					.status,
			).toBe(0);
			expect(
				runYen(["ide", "debug", "trust", remoteTarget], env, project).status,
			).toBe(0);

			const status = runYen(
				[
					"ide",
					"debug",
					"status",
					remoteTarget,
					"--devcontainer",
					"--format",
					"json",
				],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(`${status.stdout ?? ""}`.trim());
			expect(statusPayload.executionTarget).toBe("devcontainer");
			expect(statusPayload.workspace.executionLocation).toBe("remote");
			expect(statusPayload.workspace.identity).toBe(remoteIdentity);
			expect(statusPayload.devcontainerContext.executionLocation).toBe(
				"remote",
			);
			expect(statusPayload.devcontainerContext.debugExecutionAvailable).toBe(
				true,
			);
			expect(statusPayload.guidance).toContain(
				"Tracked devcontainer debugger execution is available",
			);
			expect(statusPayload.localOnly).toBe(false);

			const start = runYen(
				[
					"ide",
					"debug",
					"start",
					"src/app.js:3",
					"--managed",
					"--devcontainer",
					"--project",
					remoteIdentity,
				],
				env,
				project,
			);
			expect(start.status).toBe(0);
			expect(start.stdout).toContain("Managed Debug Session");

			const during = runYen(
				["ide", "debug", "status", remoteTarget, "--format", "json"],
				env,
				project,
			);
			expect(during.status).toBe(0);
			const duringPayload = JSON.parse(`${during.stdout ?? ""}`.trim());
			expect(duringPayload.active).toBe(true);
			expect(duringPayload.state).toBe("managed-paused");
			expect(duringPayload.lastSession.command).toContain("dev@example.test");
			expect(duringPayload.lastSession.command).toContain(fakeCli);
			expect(duringPayload.lastSession.command).toContain(
				"exec --workspace-folder",
			);

			expect(
				runYen(
					["ide", "debug", "stop", "--project", remoteIdentity],
					env,
					project,
				).status,
			).toBe(0);

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 15000 },
	);
});
