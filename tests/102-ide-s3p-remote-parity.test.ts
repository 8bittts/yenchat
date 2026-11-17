import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	mkdirSync,
	readFileSync,
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

function createProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		JSON.stringify({ name: prefix, scripts: { test: "echo ok" } }, null, 2),
		"utf8",
	);
	writeFileSync(join(project, "tsconfig.json"), "{\n}\n", "utf8");
	writeFileSync(join(project, ".env"), "API_TOKEN=test\n", "utf8");
	writeFileSync(
		join(project, "src", "app.ts"),
		"export const value = 1;\n",
		"utf8",
	);
	return project;
}

function writeFakeSSH(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
port=""
if [ "$1" = "-p" ]; then
  port="$2"
  shift 2
fi
authority="$1"
shift
if [ -n "$port" ] && [ -n "\${YEN_FAKE_SSH_PORT_LOG:-}" ]; then
  printf "%s\\n" "$port" > "$YEN_FAKE_SSH_PORT_LOG"
fi
if [ -n "\${YEN_FAKE_SSH_LOG:-}" ]; then
  printf "%s\\n" "$authority" > "$YEN_FAKE_SSH_LOG"
fi
if [ "\${YEN_FAKE_SSH_MODE:-ok}" = "fail" ]; then
  printf "%s\\n" "\${YEN_FAKE_SSH_ERROR:-remote detect failed}" >&2
  exit 255
fi
exec "$@"
`,
		"utf8",
	);
	chmodSync(path, 0o755);
}

function canonical(path: string) {
	return realpathSync(path);
}

describe("IDE remote parity foundation", () => {
	test("detect json exposes the local workspace identity contract without changing the resolved project root", () => {
		const project = createProject("yen-ide-detect-local-");
		const target = join(project, "src", "app.ts");
		const res = runYen(["ide", "detect", target, "--format", "json"]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.workspace.executionLocation).toBe("local");
		expect(payload.workspace.transport).toBe("local");
		expect(payload.workspace.requestedPath).toBe(canonical(target));
		expect(payload.workspace.root).toBe(canonical(project));
		expect(payload.workspace.identity).toBe(`local://${canonical(project)}`);
		expect(payload.project.root).toBe(canonical(project));
		expect(payload.project.types).toContain("node");
		expect(payload.project.runtime).toContain("node");
		expect(payload.project.tooling).toContain("typescript");
		expect(payload.project.envCount).toBe(1);
		expect(payload.project.envFiles).toEqual([
			join(canonical(project), ".env"),
		]);
	});

	test("detect json resolves ssh targets through a read-only remote probe and keys reserved paths by remote identity", () => {
		const project = createProject("yen-ide-detect-remote-");
		const target = canonical(join(project, "src", "app.ts"));
		const sshBinDir = ideTemp("yen-ide-fake-ssh-");
		const sshLogPath = join(sshBinDir, "ssh.log");
		const sshPortLogPath = join(sshBinDir, "ssh-port.log");
		writeFakeSSH(join(sshBinDir, "ssh"));

		const localDetect = runYen(["ide", "detect", target, "--format", "json"]);
		expect(localDetect.status).toBe(0);
		const localPayload = JSON.parse(`${localDetect.stdout ?? ""}`.trim());

		const remoteTarget = `ssh://dev@example.test:2201${target}?label=devcontainer`;
		const res = runYen(["ide", "detect", remoteTarget, "--format", "json"], {
			PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
			YEN_FAKE_SSH_LOG: sshLogPath,
			YEN_FAKE_SSH_PORT_LOG: sshPortLogPath,
		});

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.workspace.executionLocation).toBe("remote");
		expect(payload.workspace.transport).toBe("ssh");
		expect(payload.workspace.authority).toBe("dev@example.test");
		expect(payload.workspace.port).toBe(2201);
		expect(payload.workspace.label).toBe("devcontainer");
		expect(payload.workspace.requestedPath).toBe(target);
		expect(payload.workspace.root).toBe(canonical(project));
		expect(payload.workspace.identity).toBe(
			`ssh://dev@example.test:2201${canonical(project)}?label=devcontainer`,
		);
		expect(payload.project.root).toBe(canonical(project));
		expect(payload.project.historyLog).not.toBe(
			localPayload.project.historyLog,
		);
		expect(readFileSync(sshLogPath, "utf8").trim()).toBe("dev@example.test");
		expect(readFileSync(sshPortLogPath, "utf8").trim()).toBe("2201");
		rmSync(sshBinDir, { force: true, recursive: true });
	});

	test("detect env exports include remote execution labels for ssh-backed targets", () => {
		const project = createProject("yen-ide-detect-remote-env-");
		const target = canonical(join(project, "src", "app.ts"));
		const sshBinDir = ideTemp("yen-ide-fake-ssh-env-");
		writeFakeSSH(join(sshBinDir, "ssh"));

		const remoteTarget = `ssh://dev@example.test${target}`;
		const res = runYen(["ide", "detect", remoteTarget, "--format", "env"], {
			PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
		});

		expect(res.status).toBe(0);
		expect(`${res.stdout ?? ""}`).toContain("YEN_PROJECT_TRANSPORT='ssh'");
		expect(`${res.stdout ?? ""}`).toContain(
			"YEN_PROJECT_EXECUTION_LOCATION='remote'",
		);
		expect(`${res.stdout ?? ""}`).toContain(
			`YEN_PROJECT_WORKSPACE_IDENTITY='ssh://dev@example.test${canonical(project)}'`,
		);
		expect(`${res.stdout ?? ""}`).toContain(
			`YEN_PROJECT_REQUESTED_PATH='${target}'`,
		);
		rmSync(sshBinDir, { force: true, recursive: true });
	});

	test("detect fails closed when the remote probe cannot reach the host", () => {
		const project = createProject("yen-ide-detect-remote-fail-");
		const target = canonical(join(project, "src", "app.ts"));
		const sshBinDir = ideTemp("yen-ide-fake-ssh-fail-");
		writeFakeSSH(join(sshBinDir, "ssh"));

		const res = runYen(
			["ide", "detect", `ssh://dev@example.test${target}`, "--format", "json"],
			{
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_FAKE_SSH_MODE: "fail",
				YEN_FAKE_SSH_ERROR: "host unreachable",
			},
		);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain(
			"Unable to inspect remote workspace",
		);
		expect(`${res.stderr ?? ""}`).toContain("host unreachable");
		rmSync(sshBinDir, { force: true, recursive: true });
	});

	test("detect rejects malformed ssh target syntax before probing a remote host", () => {
		const res = runYen([
			"ide",
			"detect",
			"ssh://dev@example.test:not-a-port/tmp/repo",
			"--format",
			"json",
		]);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain("Invalid project target");
	});

	test("detect fails closed when a remote target resolves to multiple nested workspaces", () => {
		const wrapper = ideTemp("yen-ide-detect-remote-ambiguous-");
		const appA = join(wrapper, "packages", "app-a");
		const appB = join(wrapper, "packages", "app-b");
		mkdirSync(appA, { recursive: true });
		mkdirSync(appB, { recursive: true });
		writeFileSync(join(appA, "package.json"), '{"name":"app-a"}\n', "utf8");
		writeFileSync(join(appB, "package.json"), '{"name":"app-b"}\n', "utf8");
		const sshBinDir = ideTemp("yen-ide-fake-ssh-ambiguous-");
		writeFakeSSH(join(sshBinDir, "ssh"));

		const res = runYen(
			[
				"ide",
				"detect",
				`ssh://dev@example.test${canonical(wrapper)}`,
				"--format",
				"json",
			],
			{
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
			},
		);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain("multiple nested workspaces");
		rmSync(sshBinDir, { force: true, recursive: true });
		rmSync(wrapper, { force: true, recursive: true });
	});
});
