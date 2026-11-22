import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
	createIdeTemp,
	IDE_CLI_SLOW_TEST_TIMEOUT_MS,
} from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

// These cases exercise several real CLI subprocesses per assertion.
const test = (name: string, fn: () => void) =>
	bunTest(name, fn, { timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS });

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

describe("IDE S3T debugger baseline", () => {
	test("debug status reports local-only families and blocked topologies", () => {
		const stateDir = ideTemp("yen-ide-debug-status-");
		const project = ideTemp("yen-ide-debug-project-");
		const root = realpathSync(project);
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify({ name: "debug-status-fixture" }, null, 2)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "app.js"), "console.log('ok')\n", "utf8");

		const res = runYen(
			["ide", "debug", "status", "--project", project, "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(res.status).toBe(0);

		const payload = JSON.parse(res.stdout ?? "{}");
		expect(payload.schemaVersion).toBe(1);
		expect(payload.root).toBe(root);
		expect(payload.trusted).toBe(false);
		expect(payload.state).toBe("stopped");
		expect(payload.recommendedTool).toBe("node-inspect");
		expect(payload.blockedTopologies).toEqual(
			expect.arrayContaining([
				"TypeScript direct-file launch",
				"zero-config adapter installs beyond the shipped Python/Node/LLDB baseline",
			]),
		);
		expect(payload.families).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					id: "node-inspect",
					recommended: true,
					targetMode: "node-entry",
				}),
				expect.objectContaining({
					id: "python-pdb",
					targetMode: "python-entry",
				}),
				expect.objectContaining({
					id: "lldb",
					targetMode: "executable",
				}),
			]),
		);
		expect(existsSync(payload.stateFile)).toBe(false);
	});

	test("debug start dry-run infers python-pdb from the shared semantic target contract", () => {
		const stateDir = ideTemp("yen-ide-debug-plan-");
		const project = ideTemp("yen-ide-debug-plan-project-");
		writeFileSync(
			join(project, "main.py"),
			"value = 1\nprint(value)\n",
			"utf8",
		);

		const res = runYen(
			[
				"ide",
				"debug",
				"start",
				join(project, "main.py:2"),
				"--dry-run",
				"--format",
				"json",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(res.status).toBe(0);

		const payload = JSON.parse(res.stdout ?? "{}");
		expect(payload.tool).toBe("python-pdb");
		expect(payload.line).toBe(2);
		expect(payload.lineApplied).toBe(true);
		expect(payload.root).toBe(realpathSync(project));
		expect(payload.displayTarget).toContain(":2:1");
		expect(payload.argv).toEqual([
			"python3",
			"-m",
			"pdb",
			"-c",
			"until 2",
			join(project, "main.py"),
		]);
	});

	test("debug start is trust-gated, records timeline/state, and stop resets the tracked session", () => {
		const stateDir = ideTemp("yen-ide-debug-run-");
		const project = ideTemp("yen-ide-debug-run-project-");
		const root = realpathSync(project);
		const env = { YEN_IDE_STATE_DIR: stateDir };
		writeFileSync(
			join(project, "main.py"),
			"value = 1\nprint(value)\n",
			"utf8",
		);

		const blocked = runYen(
			["ide", "debug", "start", join(project, "main.py:2")],
			env,
			project,
			"quit\n",
		);
		expect(blocked.status).toBe(1);
		expect(`${blocked.stdout ?? ""}\n${blocked.stderr ?? ""}`).toContain(
			"Project is not trusted for debugger actions.",
		);

		expect(
			runYen(["ide", "debug", "trust", project], env, project).status,
		).toBe(0);

		const start = runYen(
			["ide", "debug", "start", join(project, "main.py:2")],
			env,
			project,
			"quit\n",
		);
		expect(start.status).toBe(0);
		expect(`${start.stdout ?? ""}\n${start.stderr ?? ""}`).toContain(
			"pdb will run until line 2",
		);

		const status = runYen(
			["ide", "debug", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.trusted).toBe(true);
		expect(payload.state).toBe("success");
		expect(payload.lastSession.tool).toBe("python-pdb");
		expect(payload.lastSession.lineApplied).toBe(true);
		expect(payload.lastSession.displayTarget).toContain(":2:1");
		expect(payload.lastSession.command).toContain("'python3' '-m' 'pdb'");

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain(`debug-trust\t${root}\ttrusted`);
		expect(timeline).toContain(`debug-start\t${root}\tlaunched`);
		expect(timeline).toContain(`debug-stop\t${root}\tstatus=success;exit=0`);

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
		const afterPayload = JSON.parse(afterStop.stdout ?? "{}");
		expect(afterPayload.state).toBe("stopped");
		expect(afterPayload.lastSession.status).toBe("stopped");
	});

	test("debug execution requires --project for remote launches and still rejects unshipped TypeScript direct-file targets", () => {
		const stateDir = ideTemp("yen-ide-debug-blocked-");
		const project = ideTemp("yen-ide-debug-blocked-project-");
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify({ name: "debug-blocked-fixture" }, null, 2)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "main.ts"), "console.log('ts')\n", "utf8");
		writeFileSync(join(project, "main.js"), "console.log('js')\n", "utf8");

		const remote = runYen(
			[
				"ide",
				"debug",
				"start",
				"ssh://dev@example.test/Users/dev/app/main.js:1",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(remote.status).toBe(1);
		expect(`${remote.stdout ?? ""}\n${remote.stderr ?? ""}`).toContain(
			"Remote debugger launch requires --project",
		);

		const ts = runYen(
			[
				"ide",
				"debug",
				"start",
				join(project, "main.ts:1"),
				"--dry-run",
				"--format",
				"json",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(ts.status).toBe(1);
		expect(`${ts.stdout ?? ""}\n${ts.stderr ?? ""}`).toContain(
			"Direct ts debugger launch is not shipped.",
		);
	});
});
