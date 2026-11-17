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

function createProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		JSON.stringify({ name: prefix, scripts: { test: "echo ok" } }, null, 2),
		"utf8",
	);
	writeFileSync(join(project, "tsconfig.json"), "{\n}\n", "utf8");
	writeFileSync(join(project, ".env"), "API_TOKEN=test\n", "utf8");
	writeFileSync(
		join(project, ".yen", "workflows", "check.toml"),
		["schema_version = 1", 'name = "check"', 'step = "echo ok"'].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(project, "src", "app.ts"),
		"export const value = 1;\n",
		"utf8",
	);
	return realpathSync(project);
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
if [ "\${YEN_FAKE_SSH_MODE:-ok}" = "fail" ]; then
  printf "%s\\n" "\${YEN_FAKE_SSH_ERROR:-remote summary failed}" >&2
  exit 255
fi
exec "$@"
`,
		"utf8",
	);
	chmodSync(path, 0o755);
}

function sha256(value: string) {
	return createHash("sha256").update(value).digest("hex");
}

function seedRemoteSummaryState(stateDir: string, remoteIdentity: string) {
	const remoteShortHash = sha256(remoteIdentity).slice(0, 12);
	const verifyDir = join(stateDir, "verify");
	const trustedEnv = join(stateDir, "trusted-env-projects");
	const trustedWorkflow = join(stateDir, "trusted-workflow-projects");
	const timelineFile = join(stateDir, "timeline.log");
	const summaryReport = join(
		verifyDir,
		`verify-20260322T000000Z-${remoteShortHash}.tsv`,
	);
	const detailsReport = summaryReport.replace(/\.tsv$/, ".log");

	mkdirSync(verifyDir, { recursive: true });
	writeFileSync(trustedEnv, `${remoteIdentity}\n`, "utf8");
	writeFileSync(trustedWorkflow, `${remoteIdentity}\n`, "utf8");
	writeFileSync(
		summaryReport,
		[
			"2026-03-22T00:00:00Z\tverify-quick\t0\t12\tstable\t0\techo ok\tpass\tgeneral",
			"",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		detailsReport,
		[
			"=== verify-quick ===",
			"category: general",
			"result: pass",
			"command: echo ok",
			"status: ok",
			"duration_ms: 12",
			"--- output ---",
			"ok",
			"",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		timelineFile,
		[
			`2026-03-22T00:00:00Z\tenv-trust\t${remoteIdentity}\ttrusted\tsource=manual`,
			`2026-03-22T00:00:01Z\tenv-load\t${remoteIdentity}\tloaded\tfiles=1`,
			`2026-03-22T00:00:02Z\tworkflow-trust\t${remoteIdentity}\ttrusted\tsource=manual`,
			`2026-03-22T00:00:03Z\tverify\t${remoteIdentity}\tfailures=0;warns=0\tsummary=${summaryReport};semantic=`,
			"",
		].join("\n"),
		"utf8",
	);
}

describe("IDE remote summary parity", () => {
	test(
		"trust status and doctor label remote evidence explicitly and key lookups by workspace identity",
		() => {
			const stateDir = ideTemp("yen-ide-remote-summary-state-");
			const project = createProject("yen-ide-remote-summary-project-");
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
			const identity = `ssh://dev@example.test${project}?label=container`;
			const sshBinDir = ideTemp("yen-ide-remote-summary-ssh-");
			writeFakeSSH(join(sshBinDir, "ssh"));
			seedRemoteSummaryState(stateDir, identity);

			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
			};

			const trust = runYen(
				["ide", "trust", "status", "--project", target, "--format", "json"],
				env,
			);
			expect(trust.status).toBe(0);
			const trustPayload = JSON.parse(`${trust.stdout ?? ""}`.trim());
			expect(trustPayload.workspace.executionLocation).toBe("remote");
			expect(trustPayload.workspace.identity).toBe(identity);
			expect(trustPayload.evidence.projectMetadataSource).toBe("remote-probe");
			expect(trustPayload.evidence.stateSource).toBe("local-ide-state");
			expect(trustPayload.evidence.timelineSource).toBe("local-ide-state");
			expect(trustPayload.evidence.controlsAvailable).toBe(false);
			expect(trustPayload.summary).toEqual({
				capabilities: 6,
				trusted: 2,
				active: 0,
			});
			expect(trustPayload.capabilities.env.trusted).toBe(true);
			expect(trustPayload.capabilities.env.lastAction.event).toBe("env-trust");
			expect(trustPayload.capabilities.env.lastRun.event).toBe("env-load");
			expect(trustPayload.capabilities.workflow.trusted).toBe(true);
			expect(trustPayload.capabilities.workflow.workflowCount).toBe(1);
			expect(trustPayload.capabilities.workflow.lastAction.event).toBe(
				"workflow-trust",
			);
			expect(trustPayload.capabilities.debug.trusted).toBe(false);
			expect(trustPayload.capabilities.debug.workspace.executionLocation).toBe(
				"remote",
			);
			expect(
				trustPayload.capabilities.debug.evidence.projectMetadataSource,
			).toBe("remote-probe");
			expect(trustPayload.capabilities.debug.localOnly).toBe(false);
			expect(trustPayload.capabilities.env.revokeCommand).toBe("");
			expect(trustPayload.capabilities.env.controlsAvailable).toBe(false);

			const doctor = runYen(
				["ide", "doctor", "--project", target, "--format", "json"],
				env,
			);
			expect(doctor.status).toBe(0);
			const doctorPayload = JSON.parse(`${doctor.stdout ?? ""}`.trim());
			expect(doctorPayload.workspace.executionLocation).toBe("remote");
			expect(doctorPayload.workspace.identity).toBe(identity);
			expect(doctorPayload.evidence.projectMetadataSource).toBe("remote-probe");
			expect(doctorPayload.evidence.stateSource).toBe("local-ide-state");
			expect(doctorPayload.blockers).toBe(0);
			expect(doctorPayload.env.trusted).toBe(true);
			expect(doctorPayload.verify.status).toBe("passing");
			expect(doctorPayload.verify.summaryReport).toContain(
				`verify-20260322T000000Z-${sha256(identity).slice(0, 12)}.tsv`,
			);

			const verify = runYen(
				["ide", "verify", "status", "--project", target, "--format", "json"],
				env,
			);
			expect(verify.status).toBe(0);
			const verifyPayload = JSON.parse(`${verify.stdout ?? ""}`.trim());
			expect(verifyPayload.workspace.executionLocation).toBe("remote");
			expect(verifyPayload.workspace.identity).toBe(identity);
			expect(verifyPayload.evidence.stateSource).toBe("local-ide-state");
			expect(verifyPayload.latest.status).toBe("passing");

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 30000 },
	);

	test(
		"trust status text renders remote labels and omits local-only controls for remote workspaces",
		() => {
			const stateDir = ideTemp("yen-ide-remote-summary-text-state-");
			const project = createProject("yen-ide-remote-summary-text-project-");
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
			const identity = `ssh://dev@example.test${project}?label=container`;
			const sshBinDir = ideTemp("yen-ide-remote-summary-text-ssh-");
			writeFakeSSH(join(sshBinDir, "ssh"));
			seedRemoteSummaryState(stateDir, identity);

			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
			};

			const trustText = runYen(
				["ide", "trust", "status", "--project", target],
				env,
			);
			expect(trustText.status).toBe(0);
			expect(trustText.stdout).toContain("Execution location: remote");
			expect(trustText.stdout).toContain(`Workspace identity: ${identity}`);
			expect(trustText.stdout).toContain("Project metadata:   remote-probe");
			expect(trustText.stdout).toContain(
				"Remote trust controls remain read-only until remote lifecycle parity ships.",
			);

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 30000 },
	);

	test(
		"host changes invalidate prior remote trust evidence instead of reusing another remote identity",
		() => {
			const stateDir = ideTemp("yen-ide-remote-summary-state-host-");
			const project = createProject("yen-ide-remote-summary-project-host-");
			const goodIdentity = `ssh://dev@example.test${project}?label=container`;
			const target = `ssh://other@example.test${join(project, "src", "app.ts")}?label=container`;
			const sshBinDir = ideTemp("yen-ide-remote-summary-ssh-host-");
			writeFakeSSH(join(sshBinDir, "ssh"));
			seedRemoteSummaryState(stateDir, goodIdentity);

			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
			};
			const trust = runYen(
				["ide", "trust", "status", "--project", target, "--format", "json"],
				env,
			);

			expect(trust.status).toBe(0);
			const payload = JSON.parse(`${trust.stdout ?? ""}`.trim());
			expect(payload.workspace.executionLocation).toBe("remote");
			expect(payload.workspace.identity).toBe(
				`ssh://other@example.test${project}?label=container`,
			);
			expect(payload.summary.trusted).toBe(0);
			expect(payload.capabilities.env.trusted).toBe(false);
			expect(payload.capabilities.env.lastAction.event).toBe("");
			expect(payload.capabilities.workflow.trusted).toBe(false);

			const doctor = runYen(
				["ide", "doctor", "--project", target, "--format", "json"],
				env,
			);
			expect(doctor.status).not.toBe(0);
			const doctorPayload = JSON.parse(`${doctor.stdout ?? ""}`.trim());
			const envFinding = (doctorPayload.findings ?? []).find(
				(item: { code?: string }) => item.code === "env-untrusted",
			);
			expect(envFinding?.remediation).toBe(
				"Remote trust controls remain read-only until remote lifecycle parity ships.",
			);

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 30000 },
	);

	test(
		"remote doctor fails closed when the workspace can no longer be inspected even if local evidence exists",
		() => {
			const stateDir = ideTemp("yen-ide-remote-summary-state-missing-");
			const project = createProject("yen-ide-remote-summary-project-missing-");
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
			const identity = `ssh://dev@example.test${project}?label=container`;
			const sshBinDir = ideTemp("yen-ide-remote-summary-ssh-missing-");
			writeFakeSSH(join(sshBinDir, "ssh"));
			seedRemoteSummaryState(stateDir, identity);

			const env = {
				PATH: `${sshBinDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_FAKE_SSH_MODE: "fail",
				YEN_FAKE_SSH_ERROR: "remote root missing",
			};
			const doctor = runYen(
				["ide", "doctor", "--project", target, "--format", "json"],
				env,
			);

			expect(doctor.status).not.toBe(0);
			expect(`${doctor.stderr ?? ""}`).toContain(
				"Unable to inspect remote workspace",
			);
			expect(`${doctor.stderr ?? ""}`).toContain("remote root missing");

			rmSync(sshBinDir, { force: true, recursive: true });
			rmSync(project, { force: true, recursive: true });
		},
		{ timeout: 30000 },
	);
});
