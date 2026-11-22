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
import {
	createIdeTemp,
	IDE_CLI_SLOW_TEST_TIMEOUT_MS,
} from "./fixtures/ide-temp";

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
				name: "debug-parity",
				image: "mcr.microsoft.com/devcontainers/base:ubuntu",
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
	cli = "",
	health = "healthy",
) {
	const hash = projectHash(root);
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
			`workspace_folder=${root}`,
			"forward_ports=3000|9229",
			"",
		].join("\n"),
		"utf8",
	);
}

describe("IDE S3Y remote debugger parity", () => {
	test(
		"debug status, trust, and managed execution reuse workspace identity for remote SSH parity",
		() => {
			const stateDir = ideTemp("yen-ide-remote-debug-state-");
			const project = createDebugProject("yen-ide-remote-debug-project-");
			const remoteTarget = `ssh://dev@example.test${join(project, "src", "app.js")}?label=container`;
			const remoteIdentity = `ssh://dev@example.test${project}?label=container`;
			const sshBinDir = ideTemp("yen-ide-remote-debug-ssh-");
			writeFakeSSH(join(sshBinDir, "ssh"));
			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
			};

			const before = runYen(
				["ide", "debug", "status", remoteTarget, "--format", "json"],
				env,
			);
			expect(before.status).toBe(0);
			const beforePayload = JSON.parse(`${before.stdout ?? ""}`.trim());
			expect(beforePayload.workspace.executionLocation).toBe("remote");
			expect(beforePayload.workspace.transport).toBe("ssh");
			expect(beforePayload.workspace.identity).toBe(remoteIdentity);
			expect(beforePayload.evidence.projectMetadataSource).toBe("remote-probe");
			expect(beforePayload.evidence.stateSource).toBe("local-ide-state");
			expect(beforePayload.trusted).toBe(false);
			expect(beforePayload.recommendedTool).toBe("node-inspect");
			expect(beforePayload.localOnly).toBe(false);
			expect(beforePayload.guidance).toContain(
				"shared local session helper over SSH",
			);
			expect(beforePayload.devcontainerContext.supported).toBe(true);
			expect(beforePayload.families).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "node-inspect",
						recommended: true,
					}),
				]),
			);
			expect(beforePayload.blockedTopologies).not.toContain(
				"remote ssh:// debugger execution",
			);

			const trust = runYen(["ide", "debug", "trust", remoteTarget], env);
			expect(trust.status).toBe(0);

			const trustedList = runYen(["ide", "debug", "trusted"], env);
			expect(trustedList.status).toBe(0);
			expect(trustedList.stdout).toContain(remoteIdentity);

			const after = runYen(
				["ide", "debug", "status", remoteTarget, "--format", "json"],
				env,
			);
			expect(after.status).toBe(0);
			const afterPayload = JSON.parse(`${after.stdout ?? ""}`.trim());
			expect(afterPayload.trusted).toBe(true);

			const trustStatus = runYen(
				[
					"ide",
					"trust",
					"status",
					"--project",
					remoteTarget,
					"--format",
					"json",
				],
				env,
			);
			expect(trustStatus.status).toBe(0);
			const trustPayload = JSON.parse(`${trustStatus.stdout ?? ""}`.trim());
			expect(trustPayload.workspace.executionLocation).toBe("remote");
			expect(trustPayload.capabilities.debug.trusted).toBe(true);
			expect(trustPayload.capabilities.debug.workspace.identity).toBe(
				remoteIdentity,
			);
			expect(trustPayload.capabilities.debug.localOnly).toBe(false);

			const doctor = runYen(
				["ide", "doctor", "--project", remoteTarget, "--format", "json"],
				env,
			);
			expect(doctor.status === 0 || doctor.status === 1).toBeTrue();
			const doctorPayload = JSON.parse(`${doctor.stdout ?? ""}`.trim());
			expect(doctorPayload.workspace.executionLocation).toBe("remote");
			expect(doctorPayload.debug.scope).toBe("remote-execution");
			expect(doctorPayload.debug.executionLocation).toBe("remote");
			expect(doctorPayload.debug.guidance).toContain("SSH-backed launch plan");

			const start = runYen(
				[
					"ide",
					"debug",
					"start",
					"src/app.js:3",
					"--managed",
					"--project",
					remoteIdentity,
				],
				env,
			);
			expect(start.status).toBe(0);
			expect(start.stdout).toContain("Managed Debug Session");

			const during = runYen(
				["ide", "debug", "status", remoteTarget, "--format", "json"],
				env,
			);
			expect(during.status).toBe(0);
			const duringPayload = JSON.parse(`${during.stdout ?? ""}`.trim());
			expect(duringPayload.active).toBe(true);
			expect(duringPayload.state).toBe("managed-paused");
			expect(duringPayload.managedSession?.active).toBe(true);
			expect(duringPayload.lastSession.command).toContain("dev@example.test");
			expect(duringPayload.lastSession.command).toContain("'sh' '-lc'");

			const inspect = runYen(
				[
					"ide",
					"debug",
					"inspect",
					"x",
					"--project",
					remoteIdentity,
					"--format",
					"json",
				],
				env,
			);
			expect(inspect.status).toBe(0);
			const inspectPayload = JSON.parse(`${inspect.stdout ?? ""}`.trim());
			expect(inspectPayload.session.active).toBe(true);

			const stop = runYen(
				["ide", "debug", "stop", "--project", remoteIdentity],
				env,
			);
			expect(stop.status).toBe(0);

			const untrust = runYen(["ide", "debug", "untrust", remoteTarget], env);
			expect(untrust.status).toBe(0);

			const finalStatus = runYen(
				["ide", "debug", "status", remoteTarget, "--format", "json"],
				env,
			);
			expect(finalStatus.status).toBe(0);
			expect(JSON.parse(`${finalStatus.stdout ?? ""}`.trim()).trusted).toBe(
				false,
			);

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);

	test(
		"local debug status and doctor surface tracked devcontainer execution when the container is ready",
		() => {
			const stateDir = ideTemp("yen-ide-local-debug-devcontainer-state-");
			const project = createDebugProject(
				"yen-ide-local-debug-devcontainer-project-",
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

			const status = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(`${status.stdout ?? ""}`.trim());
			expect(statusPayload.workspace.executionLocation).toBe("local");
			expect(statusPayload.devcontainerContext.supported).toBe(true);
			expect(statusPayload.devcontainerContext.state).toBe("running");
			expect(statusPayload.devcontainerContext.health).toBe("healthy");
			expect(statusPayload.devcontainerContext.debugExecutionAvailable).toBe(
				true,
			);
			expect(statusPayload.devcontainerContext.forwardPorts).toEqual([
				"3000",
				"9229",
			]);
			expect(statusPayload.guidance).toContain(
				"Tracked devcontainer debugger execution is also available",
			);
			expect(statusPayload.localOnly).toBe(false);

			const doctor = runYen(
				["ide", "doctor", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(doctor.status === 0 || doctor.status === 1).toBeTrue();
			const doctorPayload = JSON.parse(`${doctor.stdout ?? ""}`.trim());
			expect(doctorPayload.debug.scope).toBe(
				"local-with-devcontainer-execution",
			);
			expect(doctorPayload.debug.executionLocation).toBe("local");
			expect(doctorPayload.debug.devcontainerState).toBe("running");
			expect(doctorPayload.debug.devcontainerHealth).toBe("healthy");
			expect(doctorPayload.debug.devcontainerExecutionAvailable).toBe(true);
			expect(doctorPayload.debug.guidance).toContain(
				"Tracked devcontainer debugger execution is available",
			);

			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);
});
