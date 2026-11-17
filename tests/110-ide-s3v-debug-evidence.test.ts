import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
	input?: string,
) {
	return spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		input,
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function startDebugSession() {
	const stateDir = ideTemp("yen-ide-debug-evidence-state-");
	const project = ideTemp("yen-ide-debug-evidence-project-");
	const root = realpathSync(project);
	const env = { YEN_IDE_STATE_DIR: stateDir };

	writeFileSync(join(project, "main.py"), "value = 1\nprint(value)\n", "utf8");

	expect(runYen(["ide", "debug", "trust", project], env, project).status).toBe(
		0,
	);

	const start = runYen(
		["ide", "debug", "start", join(project, "main.py:2")],
		env,
		project,
		"quit\n",
	);
	expect(start.status).toBe(0);

	const status = runYen(
		["ide", "debug", "status", "--project", project, "--format", "json"],
		env,
		project,
	);
	expect(status.status).toBe(0);
	const payload = JSON.parse(status.stdout ?? "{}");
	const last = payload.lastSession ?? {};
	return { stateDir, project, root, env, last };
}

describe("IDE S3V debug evidence follow-on", () => {
	test(
		"debug status preserves session reports after stopping",
		() => {
			const { stateDir, project, root, env, last } = startDebugSession();

			expect(last.summaryReport).toBeTruthy();
			expect(last.detailsReport).toBeTruthy();
			expect(last.reportsReady).toBe(true);
			expect(existsSync(last.summaryReport)).toBe(true);
			expect(existsSync(last.detailsReport)).toBe(true);

			const summaryReport = readFileSync(last.summaryReport, "utf8");
			expect(summaryReport).toContain("python-pdb");
			expect(summaryReport).toContain("success");
			expect(summaryReport).toContain(join(project, "main.py:2:1"));

			const detailsReport = readFileSync(last.detailsReport, "utf8");
			expect(detailsReport).toContain("IDE Debug Session");
			expect(detailsReport).toContain(`Project root: ${root}`);
			expect(detailsReport).toContain("Command:");
			expect(detailsReport).toContain("--- result ---");
			expect(detailsReport).toContain("Status: success");

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain(`summary=${last.summaryReport}`);
			expect(timeline).toContain(`details=${last.detailsReport}`);

			expect(
				runYen(["ide", "debug", "stop", project], env, project).status,
			).toBe(0);

			const afterStop = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(afterStop.status).toBe(0);
			const afterPayload = JSON.parse(afterStop.stdout ?? "{}");
			expect(afterPayload.state).toBe("stopped");
			expect(afterPayload.lastSession.summaryReport).toBe(last.summaryReport);
			expect(afterPayload.lastSession.detailsReport).toBe(last.detailsReport);
			expect(afterPayload.lastSession.reportsReady).toBe(true);
		},
		// Keep the debugger lifecycle separate from the three trust report reads.
		{ timeout: 20_000 },
	);
	test(
		"trust status exposes session evidence as JSON",
		() => {
			const { project, env, last } = startDebugSession();

			const trustJson = runYen(
				["ide", "trust", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(trustJson.status).toBe(0);
			const trustPayload = JSON.parse(trustJson.stdout ?? "{}");
			expect(trustPayload.capabilities.debug.lastSession.summaryReport).toBe(
				last.summaryReport,
			);
			expect(trustPayload.capabilities.debug.lastSession.detailsReport).toBe(
				last.detailsReport,
			);
			expect(trustPayload.capabilities.debug.lastSession.reportsReady).toBe(
				true,
			);
		},
		{ timeout: 20_000 },
	);
	test(
		"trust status exposes session evidence as text",
		() => {
			const { project, env, last } = startDebugSession();

			const trustText = runYen(
				["ide", "trust", "status", "--project", project],
				env,
				project,
			);
			expect(trustText.status).toBe(0);
			expect(trustText.stdout).toContain("Debug Evidence:");
			expect(trustText.stdout).toContain(last.summaryReport);
			expect(trustText.stdout).toContain(last.detailsReport);
		},
		{ timeout: 20_000 },
	);
	test(
		"trust status exposes session evidence as env",
		() => {
			const { project, env } = startDebugSession();

			const trustEnv = runYen(
				["ide", "trust", "status", "--project", project, "--format", "env"],
				env,
				project,
			);
			expect(trustEnv.status).toBe(0);
			expect(trustEnv.stdout).toContain(
				"export YEN_IDE_TRUST_DEBUG_SUMMARY_REPORT=",
			);
			expect(trustEnv.stdout).toContain(
				"export YEN_IDE_TRUST_DEBUG_DETAILS_REPORT=",
			);
			expect(trustEnv.stdout).toContain(
				"export YEN_IDE_TRUST_DEBUG_REPORTS_READY='yes'",
			);
		},
		{ timeout: 20_000 },
	);
});
