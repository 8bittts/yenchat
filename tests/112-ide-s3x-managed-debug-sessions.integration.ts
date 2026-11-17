import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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

describe("IDE S3X managed debug sessions", () => {
	test(
		"managed python sessions use a short socket path, normalize breakpoint columns, and expose transcripts",
		() => {
			const stateBase = ideTemp("yen-ide-managed-state-");
			const stateDir = join(
				stateBase,
				"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			);
			const project = ideTemp("yen-ide-managed-python-");
			const env = { YEN_IDE_STATE_DIR: stateDir };

			mkdirSync(stateDir, { recursive: true });
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

			expect(
				runYen(["ide", "debug", "trust", project], env, project).status,
			).toBe(0);

			const start = runYen(
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
			);
			expect(start.status).toBe(0);
			expect(start.stdout).toContain("Managed Debug Session");

			const status = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const payload = JSON.parse(status.stdout ?? "{}");
			expect(payload.state).toBe("managed-paused");
			expect(payload.active).toBe(true);
			expect(payload.managedSession?.socketFile).toContain("/yen-debug-");
			expect(payload.managedSession?.socketFile).not.toContain("/debug/");
			expect(existsSync(payload.managedSession.socketFile)).toBe(true);

			const breakpoint = runYen(
				[
					"ide",
					"debug",
					"breakpoint",
					"add",
					"main.py:4:99",
					"--project",
					project,
					"--format",
					"json",
				],
				env,
				project,
			);
			expect(breakpoint.status).toBe(0);
			const breakpointPayload = JSON.parse(breakpoint.stdout ?? "{}");
			expect(breakpointPayload.session.breakpoints).toEqual([
				expect.objectContaining({
					location: "main.py:4",
					spec: "main.py:4",
				}),
			]);

			const transcript = runYen(
				["ide", "debug", "transcript", "--project", project, "--tail", "80"],
				env,
				project,
			);
			expect(transcript.status).toBe(0);
			expect(transcript.stdout).toContain("--- session-start @");
			expect(transcript.stdout).toContain("breakpoint add main.py:4");

			const stop = runYen(
				["ide", "debug", "stop", "--project", project],
				env,
				project,
			);
			expect(stop.status).toBe(0);

			const afterStop = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(afterStop.status).toBe(0);
			const afterPayload = JSON.parse(afterStop.stdout ?? "{}");
			expect(afterPayload.state).toBe("stopped");
			expect(afterPayload.lastSession.status).toBe("stopped");
			expect(afterPayload.lastSession.detailsReport).toBeTruthy();
			expect(
				readFileSync(afterPayload.lastSession.detailsReport, "utf8"),
			).toContain("--- stop @");
		},
		{ timeout: 15000 },
	);

	test(
		"managed node sessions use an ephemeral inspector port instead of 9229",
		() => {
			const stateDir = ideTemp("yen-ide-managed-node-state-");
			const project = ideTemp("yen-ide-managed-node-project-");
			const env = { YEN_IDE_STATE_DIR: stateDir };

			writeFileSync(
				join(project, "app.js"),
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

			expect(
				runYen(["ide", "debug", "trust", project], env, project).status,
			).toBe(0);

			const start = runYen(
				[
					"ide",
					"debug",
					"start",
					"app.js:3",
					"--managed",
					"--project",
					project,
				],
				env,
				project,
			);
			expect(start.status).toBe(0);

			const status = runYen(
				["ide", "debug", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(status.status).toBe(0);
			const payload = JSON.parse(status.stdout ?? "{}");
			expect(payload.active).toBe(true);
			expect(payload.state).toBe("managed-paused");
			expect(payload.lastSession.command).toContain("'--port=0'");
			expect(payload.managedSession?.argv).toContain("--port=0");

			const inspect = runYen(
				[
					"ide",
					"debug",
					"inspect",
					"x",
					"--project",
					project,
					"--format",
					"json",
				],
				env,
				project,
			);
			expect(inspect.status).toBe(0);
			const inspectPayload = JSON.parse(inspect.stdout ?? "{}");
			expect(inspectPayload.session.active).toBe(true);
			expect(inspectPayload.session.lastStopLocation).toContain("app.js:");

			expect(
				runYen(["ide", "debug", "stop", "--project", project], env, project)
					.status,
			).toBe(0);
		},
		{ timeout: 15000 },
	);
});
