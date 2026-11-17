import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	appendFileSync,
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { ideCommandDiagnostics } from "./fixtures/ide-result";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	const result = spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
	expect(result.error, ideCommandDiagnostics(result)).toBeUndefined();
	expect(result.status, ideCommandDiagnostics(result)).not.toBeNull();
	return result;
}

function projectHash(root: string) {
	return createHash("sha256").update(root).digest("hex");
}

function appendTimeline(
	stateDir: string,
	root: string,
	event: string,
	status: string,
	detail: string,
) {
	appendFileSync(
		join(stateDir, "timeline.log"),
		`2026-03-20T00:00:00Z\t${event}\t${root}\t${status}\t${detail}\n`,
		"utf8",
	);
}

describe("IDE S3I workspace trust center", () => {
	test(
		"trust status aggregates existing capability trust and state without creating a new trust model",
		() => {
			const stateDir = ideTemp("yen-ide-trust-state-");
			const project = ideTemp("yen-ide-trust-project-");
			const root = realpathSync(project);
			const env = { YEN_IDE_STATE_DIR: stateDir };
			const hash = projectHash(root);

			writeFileSync(join(project, ".env.local"), "SECRET_TOKEN=test\n", "utf8");
			mkdirSync(join(project, ".devcontainer"), { recursive: true });
			writeFileSync(
				join(project, ".devcontainer", "devcontainer.json"),
				`${JSON.stringify(
					{
						name: "trust-fixture",
						image: "mcr.microsoft.com/devcontainers/base:ubuntu",
					},
					null,
					2,
				)}\n`,
				"utf8",
			);
			mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
			writeFileSync(
				join(project, ".yen", "workflows", "check.toml"),
				["schema_version = 1", 'name = "check"', 'step = "echo ok"'].join("\n"),
				"utf8",
			);

			expect(
				runYen(["ide", "env", "trust", project], env, project).status,
			).toBe(0);
			const envLoad = runYen(["ide", "env", "load", project], env, project);
			expect(envLoad.status).toBe(0);
			expect(envLoad.stdout).toContain("export SECRET_TOKEN='test'");
			expect(
				runYen(["ide", "lsp", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "workflow", "trust", project], env, project).status,
			).toBe(0);

			const devcontainerStateDir = join(stateDir, "devcontainer", hash);
			mkdirSync(devcontainerStateDir, { recursive: true });
			writeFileSync(
				join(devcontainerStateDir, "state.env"),
				[
					"status=running",
					`root=${root}`,
					"cli=",
					`spec=${join(project, ".devcontainer", "devcontainer.json")}`,
					"unsafe=none",
					"started_at=2026-03-20T00:00:00Z",
					"last_command=devcontainer up",
					"health=healthy",
					`workspace_folder=${root}`,
					"forward_ports=3000|9229",
					"",
				].join("\n"),
				"utf8",
			);
			appendTimeline(
				stateDir,
				root,
				"devcontainer-up",
				"running",
				"unsafe=none;spec=.devcontainer/devcontainer.json",
			);
			appendTimeline(
				stateDir,
				root,
				"workflow",
				"success",
				"name=check;summary=workflow.tsv;semantic=workflow.semantic.tsv",
			);

			const json = runYen(
				["ide", "trust", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(json.status).toBe(0);
			const payload = JSON.parse(json.stdout ?? "{}");

			expect(payload.schemaVersion).toBe(1);
			expect(payload.root).toBe(root);
			expect(payload.summary).toEqual({
				capabilities: 6,
				trusted: 3,
				active: 1,
			});
			expect(payload.capabilities.env.trusted).toBe(true);
			expect(payload.capabilities.env.fileCount).toBe(1);
			expect(payload.capabilities.env.state).toBe("idle");
			expect(payload.capabilities.env.lastAction.event).toBe("env-trust");
			expect(payload.capabilities.env.lastAction.status).toBe("trusted");
			expect(payload.capabilities.env.lastRun.event).toBe("env-load");
			expect(payload.capabilities.env.lastRun.status).toBe("loaded");
			expect(payload.capabilities.lsp.trusted).toBe(true);
			expect(payload.capabilities.lsp.state).toBe("stopped");
			expect(payload.capabilities.debug.trusted).toBe(false);
			expect(payload.capabilities.debug.supportsReset).toBe(true);
			expect(payload.capabilities.devcontainer.supported).toBe(true);
			expect(payload.capabilities.devcontainer.trusted).toBe(false);
			expect(payload.capabilities.devcontainer.state).toBe("running");
			expect(payload.capabilities.devcontainer.active).toBe(true);
			expect(payload.capabilities.devcontainer.lastRun.event).toBe(
				"devcontainer-up",
			);
			expect(payload.capabilities.workflow.trusted).toBe(true);
			expect(payload.capabilities.workflow.workflowCount).toBe(1);
			expect(payload.capabilities.workflow.lastAction.event).toBe(
				"workflow-trust",
			);
			expect(payload.capabilities.workflow.lastRun.event).toBe("workflow");
			expect(payload.capabilities.share.trusted).toBe(false);

			const envOutput = runYen(
				["ide", "trust", "status", "--project", project, "--format", "env"],
				env,
				project,
			);
			expect(envOutput.status).toBe(0);
			expect(envOutput.stdout).toContain("export YEN_IDE_TRUST_ROOT=");
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_TRUSTED_COUNT='3'",
			);
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_ACTIVE_COUNT='1'",
			);
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_ENV_TRUSTED='yes'",
			);
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_ENV_LAST_ACTION_EVENT='env-trust'",
			);
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_ENV_LAST_RUN_EVENT='env-load'",
			);
			expect(envOutput.stdout).toContain(
				"export YEN_IDE_TRUST_DEVCONTAINER_STATE='running'",
			);

			const text = runYen(
				["ide", "trust", "status", "--project", project],
				env,
				project,
			);
			expect(text.status).toBe(0);
			expect(text.stdout).toContain("IDE Workspace Trust Center");
			expect(text.stdout).toContain("Capabilities:       6");
			expect(text.stdout).toContain("Trusted:            3");
			expect(text.stdout).toContain("debug");
			expect(text.stdout).toContain("devcontainer");
			expect(text.stdout).toContain("running");
			expect(text.stdout).toContain("LAST ACTION");
			expect(text.stdout).toContain("env-load");
		},
		{ timeout: 15_000 },
	);

	test(
		"trust revoke and reset delegate to existing capability commands",
		() => {
			const stateDir = ideTemp("yen-ide-trust-controls-state-");
			const project = ideTemp("yen-ide-trust-controls-project-");
			const root = realpathSync(project);
			const env = { YEN_IDE_STATE_DIR: stateDir };
			const hash = projectHash(root);

			writeFileSync(join(project, ".env.local"), "ONE=1\n", "utf8");
			mkdirSync(join(project, ".devcontainer"), { recursive: true });
			writeFileSync(
				join(project, ".devcontainer", "devcontainer.json"),
				`${JSON.stringify(
					{ name: "trust-controls", image: "ubuntu:24.04" },
					null,
					2,
				)}\n`,
				"utf8",
			);
			mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
			writeFileSync(
				join(project, ".yen", "workflows", "deploy.toml"),
				["schema_version = 1", 'name = "deploy"', 'step = "echo ok"'].join(
					"\n",
				),
				"utf8",
			);

			expect(
				runYen(["ide", "env", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "lsp", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "debug", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "devcontainer", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "share", "trust", project], env, project).status,
			).toBe(0);
			expect(
				runYen(["ide", "workflow", "trust", project], env, project).status,
			).toBe(0);

			const devcontainerStateFile = join(
				stateDir,
				"devcontainer",
				hash,
				"state.env",
			);
			mkdirSync(join(stateDir, "devcontainer", hash), { recursive: true });
			writeFileSync(
				devcontainerStateFile,
				[
					"status=running",
					`root=${root}`,
					"cli=",
					`spec=${join(project, ".devcontainer", "devcontainer.json")}`,
					"unsafe=none",
					"started_at=2026-03-20T00:00:00Z",
					"last_command=devcontainer up",
					"health=healthy",
					`workspace_folder=${root}`,
					"forward_ports=",
					"",
				].join("\n"),
				"utf8",
			);

			const reset = runYen(
				["ide", "trust", "reset", "devcontainer", "--project", project],
				env,
				project,
			);
			expect(reset.status).toBe(0);
			expect(existsSync(devcontainerStateFile)).toBe(false);

			const invalidReset = runYen(
				["ide", "trust", "reset", "env", "--project", project],
				env,
				project,
			);
			expect(invalidReset.status).toBe(1);
			expect(
				`${invalidReset.stdout ?? ""}\n${invalidReset.stderr ?? ""}`,
			).toContain("expected lsp|debug|devcontainer|share|all");

			const revokeAll = runYen(
				["ide", "trust", "revoke", "all", "--project", project],
				env,
				project,
			);
			expect(revokeAll.status).toBe(0);

			const status = runYen(
				["ide", "trust", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const payload = JSON.parse(status.stdout ?? "{}");
			expect(payload.summary.trusted).toBe(0);
			expect(payload.capabilities.env.trusted).toBe(false);
			expect(payload.capabilities.lsp.trusted).toBe(false);
			expect(payload.capabilities.debug.trusted).toBe(false);
			expect(payload.capabilities.devcontainer.trusted).toBe(false);
			expect(payload.capabilities.share.trusted).toBe(false);
			expect(payload.capabilities.workflow.trusted).toBe(false);
			expect(payload.capabilities.debug.revokeCommand).toContain(
				"yen ide trust revoke debug",
			);
			expect(payload.capabilities.debug.supportsReset).toBe(true);
			expect(payload.capabilities.devcontainer.revokeCommand).toContain(
				"yen ide trust revoke devcontainer",
			);
			expect(payload.capabilities.devcontainer.supportsReset).toBe(true);
			expect(payload.capabilities.env.supportsReset).toBe(false);
		},
		{ timeout: 15_000 },
	);

	test("trust status keeps expired share inspection read-only", () => {
		const stateDir = ideTemp("yen-ide-trust-share-readonly-");
		const project = ideTemp("yen-ide-trust-share-project-");
		const root = realpathSync(project);
		const env = { YEN_IDE_STATE_DIR: stateDir };
		const hash = projectHash(root);
		const shareProjectDir = join(stateDir, "share", hash);
		const shareStateFile = join(shareProjectDir, "state.env");
		const originalState = [
			"status=running",
			`root=${root}`,
			"transport=upterm",
			"mode=read-only",
			"host_identity=tester@host",
			`repo_label=${project.split("/").pop() ?? "repo"}`,
			"session_id=share-test",
			"started_at=2026-03-20T00:00:00Z",
			"expires_at=2026-03-20T00:00:00Z",
			"expires_epoch=1",
			"auth_mode=passphrase",
			"share_token=token-should-hide",
			"transport_status=running",
			"last_error=",
			"revoked_at=",
			"expired_at=",
			"ttl_seconds=3600",
			"cli=",
			"web_url=",
			"",
		].join("\n");

		mkdirSync(shareProjectDir, { recursive: true });
		writeFileSync(shareStateFile, originalState, "utf8");

		const beforeTimeline = existsSync(join(stateDir, "timeline.log"))
			? readFileSync(join(stateDir, "timeline.log"), "utf8")
			: "";
		const status = runYen(
			["ide", "trust", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.capabilities.share.state).toBe("expired");
		expect(payload.capabilities.share.active).toBe(false);
		expect(payload.capabilities.share.shareToken).toBe("");
		expect(readFileSync(shareStateFile, "utf8")).toBe(originalState);
		const afterTimeline = existsSync(join(stateDir, "timeline.log"))
			? readFileSync(join(stateDir, "timeline.log"), "utf8")
			: "";
		expect(afterTimeline).toBe(beforeTimeline);
	});
});
