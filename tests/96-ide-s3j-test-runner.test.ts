import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const ideSearchHistoryModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/search-history.sh",
);

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

function delay(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function captureChild(child: ReturnType<typeof spawn>) {
	let output = "";
	child.stdout?.on("data", (chunk) => {
		output += String(chunk);
	});
	child.stderr?.on("data", (chunk) => {
		output += String(chunk);
	});
	return {
		getOutput() {
			return output;
		},
		settled: new Promise<{ code: number | null; output: string }>((resolve) => {
			child.on("close", (code) => resolve({ code, output }));
		}),
	};
}

async function waitForOutput(
	getOutput: () => string,
	needle: string,
	timeoutMs = 5000,
) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		if (getOutput().includes(needle)) {
			return;
		}
		await delay(50);
	}
	throw new Error(`Timed out waiting for output containing: ${needle}`);
}

describe("IDE S3J test runner UX baseline", () => {
	test("test status reuses latest verify reports and runner detection in json and text output", () => {
		const stateDir = ideTemp("yen-ide-test-status-state-");
		const project = ideTemp("yen-ide-test-status-project-");
		const root = realpathSync(project);
		const env = { YEN_IDE_STATE_DIR: stateDir };

		mkdirSync(join(project, "src"), { recursive: true });
		writeFileSync(
			join(project, "src", "failure.test.ts"),
			"// fixture\n",
			"utf8",
		);
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "test-status-fixture",
					scripts: {
						test: "bash -lc 'echo src/failure.test.ts:9:4 broken >&2; exit 1'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		const verify = runYen(
			["ide", "verify", "--quick", "--no-security"],
			env,
			project,
		);
		expect(verify.status).toBe(1);

		const json = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");

		expect(payload.schemaVersion).toBe(1);
		expect(payload.root).toBe(root);
		expect(payload.summary.runnerCount).toBe(1);
		expect(payload.summary.runnableCount).toBe(1);
		expect(payload.summary.latestSource).toBe("verify");
		expect(payload.summary.lastRunFailing).toBe(1);
		expect(payload.summary.latestFailureGroups).toBe(1);
		expect(payload.summary.latestFailureTargets).toBe(1);
		expect(payload.summary.debuggableFailureGroups).toBe(0);
		expect(payload.verify.status).toBe("failing");
		expect(payload.test.status).toBe("never-run");
		expect(payload.latest.source).toBe("verify");
		expect(payload.latest.status).toBe("failing");
		expect(existsSync(payload.verify.summaryReport)).toBe(true);
		expect(existsSync(payload.verify.detailsReport)).toBe(true);
		expect(existsSync(payload.verify.semanticReport)).toBe(true);
		expect(payload.failures).toHaveLength(1);
		expect(payload.failures[0].runnerId).toBe("node-test");
		expect(payload.failures[0].summary).toContain(
			"src/failure.test.ts:9:4 broken",
		);
		expect(payload.failures[0].targetCount).toBe(1);
		expect(payload.failures[0].primaryTarget.location).toBe(
			"src/failure.test.ts:9:4",
		);
		expect(payload.failures[0].debugHandoff).toBeNull();
		expect(payload.runners).toHaveLength(1);
		expect(payload.runners[0]).toMatchObject({
			id: "node-test",
			family: "node",
			sourcePath: "package.json",
			runnable: true,
			quickEligible: true,
		});
		expect(payload.runners[0].command).toContain("test");
		expect(payload.runners[0].lastRun.status).toBe("failing");
		expect(payload.runners[0].lastRun.exitCode).toBe(1);
		expect(payload.runners[0].lastRun.targetCount).toBe(1);
		expect(payload.runners[0].lastRun.primaryTarget.location).toBe(
			"src/failure.test.ts:9:4",
		);
		expect(payload.runners[0].lastRun.debugHandoff).toBeNull();
		expect(payload.runners[0].lastRun.outputExcerpt[0]).toContain(
			"src/failure.test.ts:9:4 broken",
		);

		const text = runYen(["ide", "test", "--project", project], env, project);
		expect(text.status).toBe(0);
		expect(text.stdout).toContain("IDE Test Runner Status");
		expect(text.stdout).toContain("Latest verify:      failing");
		expect(text.stdout).toContain("Latest Failure Groups:");
		expect(text.stdout).toContain("node-test");
		expect(text.stdout).toContain("primary: src/failure.test.ts:9:4");
		expect(text.stdout).toContain("package.json");
	});

	test("test status surfaces unavailable runner reasons before any rerun logic exists", () => {
		const stateDir = ideTemp("yen-ide-test-unavailable-state-");
		const project = ideTemp("yen-ide-test-unavailable-project-");
		const env = { YEN_IDE_STATE_DIR: stateDir };

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify({ name: "unavailable-test-fixture", scripts: {} }, null, 2)}\n`,
			"utf8",
		);
		writeFileSync(
			join(project, "Makefile"),
			["build:", "\t@echo build only", ""].join("\n"),
			"utf8",
		);

		const json = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");
		const reasons = new Map(
			(payload.runners ?? []).map((runner: { id: string; reason: string }) => [
				runner.id,
				runner.reason,
			]),
		);

		expect(payload.verify.status).toBe("never-run");
		expect(payload.test.status).toBe("never-run");
		expect(payload.latest.source).toBe("none");
		expect(payload.summary.runnerCount).toBe(2);
		expect(payload.summary.runnableCount).toBe(0);
		expect(payload.summary.unavailableCount).toBe(2);
		expect(payload.summary.latestFailureGroups).toBe(0);
		expect(reasons.get("node-test")).toBe("missing-test-script");
		expect(reasons.get("make-test")).toBe("missing-test-target");

		const text = runYen(
			["ide", "test", "status", "--project", project],
			env,
			project,
		);
		expect(text.status).toBe(0);
		expect(text.stdout).toContain("missing-test-script");
		expect(text.stdout).toContain("missing-test-target");
	});

	test("test status ignores scratch go modules under tmp while keeping real nested modules", () => {
		const stateDir = ideTemp("yen-ide-test-boundary-state-");
		const project = ideTemp("yen-ide-test-boundary-project-");
		const env = { YEN_IDE_STATE_DIR: stateDir };

		mkdirSync(join(project, "services", "api"), { recursive: true });
		mkdirSync(join(project, "tmp", "scratch"), { recursive: true });
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "test-boundary-fixture",
					scripts: {
						test: "echo root",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(
			join(project, "services", "api", "go.mod"),
			"module example.com/api\n\ngo 1.22.0\n",
			"utf8",
		);
		writeFileSync(
			join(project, "tmp", "scratch", "go.mod"),
			"module example.com/scratch\n\ngo 1.22.0\n",
			"utf8",
		);

		const status = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		const runnerIds = new Set(
			(payload.runners as Array<{ id: string }>).map((runner) => runner.id),
		);
		const sourcePaths = new Set(
			(payload.runners as Array<{ sourcePath: string }>).map(
				(runner) => runner.sourcePath,
			),
		);

		expect(runnerIds.has("go-test-api")).toBe(true);
		expect(runnerIds.has("go-test-scratch")).toBe(false);
		expect(sourcePaths.has("services/api/go.mod")).toBe(true);
		expect(sourcePaths.has("tmp/scratch/go.mod")).toBe(false);
	});

	test("test run supports targeted runner scope and updates status to the latest test report", () => {
		const stateDir = ideTemp("yen-ide-test-run-state-");
		const project = ideTemp("yen-ide-test-run-project-");
		const env = { YEN_IDE_STATE_DIR: stateDir };

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "targeted-test-run-fixture",
					scripts: {
						test: "bash -lc 'echo targeted pass'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		const run = runYen(
			["ide", "test", "run", "--runner", "node-test", "--project", project],
			env,
			project,
		);
		expect(run.status).toBe(0);
		expect(run.stdout).toContain("IDE Test Run");
		expect(run.stdout).toContain("Mode:             selected");
		expect(run.stdout).toContain("Requested:        node-test");
		expect(run.stdout).toContain("Selected runners: node-test");
		expect(run.stdout).toContain("Summary file:");

		const summaryMatch = run.stdout.match(/Summary file:\s+([^\n]+)/);
		const detailsMatch = run.stdout.match(/Details file:\s+([^\n]+)/);
		const semanticMatch = run.stdout.match(/Semantic file:\s+([^\n]+)/);
		expect(summaryMatch).not.toBeNull();
		expect(detailsMatch).not.toBeNull();
		expect(semanticMatch).not.toBeNull();
		expect(existsSync(summaryMatch?.[1]?.trim() ?? "")).toBe(true);
		expect(existsSync(detailsMatch?.[1]?.trim() ?? "")).toBe(true);
		expect(existsSync(semanticMatch?.[1]?.trim() ?? "")).toBe(true);

		const status = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.test.status).toBe("passing");
		expect(payload.latest.source).toBe("test");
		expect(payload.latest.status).toBe("passing");
		expect(payload.summary.lastRunPassing).toBe(1);

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("\ttest\t");
		expect(timeline).toContain("mode=selected");
		expect(timeline).toContain("runners=node-test");
	});

	test("test run --watch keeps a fixed runner snapshot, ignores self-written reports, and refreshes runner availability", async () => {
		const stateDir = ideTemp("yen-ide-test-watch-state-");
		const project = ideTemp("yen-ide-test-watch-project-");
		const env = {
			...process.env,
			YEN_IDE_STATE_DIR: stateDir,
		};

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "watch-test-fixture",
					scripts: {
						test: "node watch-test.js",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(
			join(project, "watch-test.js"),
			"process.stdout.write('watch pass\\n');\n",
			"utf8",
		);

		const child = spawn(
			yenBinPath,
			[
				"ide",
				"test",
				"run",
				"--runner",
				"node-test",
				"--project",
				project,
				"--watch",
				"--watch-interval",
				"0.1",
				"--max-runs",
				"2",
			],
			{
				cwd: project,
				env,
				stdio: "pipe",
			},
		);
		const watchRun = captureChild(child);

		await waitForOutput(
			watchRun.getOutput,
			"Watch: waiting for project changes to rerun selected runner snapshot (node-test).",
		);
		await delay(300);
		expect(watchRun.getOutput()).not.toContain("Watch iteration: 2");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify({ name: "watch-test-fixture", scripts: {} }, null, 2)}\n`,
			"utf8",
		);

		const result = await watchRun.settled;
		expect(result.code).toBe(1);
		const summaryMatches = Array.from(
			result.output.matchAll(/Summary file:\s+([^\n]+)/g),
		);
		expect(result.output).toContain("Watch:            enabled");
		expect(result.output).toContain(
			"Rerun scope:      selected runner snapshot (node-test)",
		);
		expect(result.output).toContain("Watch iteration: 1");
		expect(result.output).toContain("Watch iteration: 2");
		expect(summaryMatches).toHaveLength(2);
		expect(summaryMatches[0]?.[1]?.trim()).not.toBe(
			summaryMatches[1]?.[1]?.trim(),
		);
		expect(existsSync(summaryMatches[0]?.[1]?.trim() ?? "")).toBe(true);
		expect(existsSync(summaryMatches[1]?.[1]?.trim() ?? "")).toBe(true);
		expect(result.output).toContain("No runnable test runners were executed.");
		expect(result.output).toContain(
			"Watch: change detected (package.json); rerunning selected runner snapshot (node-test).",
		);

		const status = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.runners[0].reason).toBe("missing-test-script");
		expect(payload.runners[0].runnable).toBe(false);

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("\ttest-watch\t");
		expect(timeline).toContain("reason=max-runs");
		expect(timeline).toContain("watchIteration=2");
		expect(timeline).toContain("watchScope=selected-snapshot");
		expect(timeline).toContain("runners=node-test");
	});

	test("test status prefers dedicated test reports when verify and test timestamps tie", () => {
		const stateDir = ideTemp("yen-ide-test-tie-state-");
		const project = ideTemp("yen-ide-test-tie-project-");
		const root = realpathSync(project);
		const env = { YEN_IDE_STATE_DIR: stateDir };
		const timestamp = "2026-03-20T12:00:00Z";
		const verifyDir = join(stateDir, "verify");
		const testDir = join(stateDir, "test");
		const verifySummary = join(verifyDir, "verify-same-second.tsv");
		const verifyDetails = join(verifyDir, "verify-same-second.log");
		const verifySemantic = join(verifyDir, "verify-same-second.semantic.tsv");
		const testSummary = join(testDir, "test-same-second.tsv");
		const testDetails = join(testDir, "test-same-second.log");
		const testSemantic = join(testDir, "test-same-second.semantic.tsv");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "same-second-test-fixture",
					scripts: {
						test: "bash -lc 'echo same second pass'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		mkdirSync(verifyDir, { recursive: true });
		mkdirSync(testDir, { recursive: true });
		writeFileSync(
			verifySummary,
			`${timestamp}\tnode-test\t1\t5\tfail\t0\tbun test\n`,
			"utf8",
		);
		writeFileSync(
			verifyDetails,
			[
				"=== node-test ===",
				"command: bun test",
				"status: exit=1",
				"duration_ms: 5",
				"flaky_state: fail",
				"--- output ---",
				"src/verify-only.test.ts:4:2 failed",
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(
			verifySemantic,
			[
				`${timestamp}\tnode-test\tverify\tyes\tsrc/verify-only.test.ts\t4\t2\t${join(root, "src/verify-only.test.ts")}\tsrc/verify-only.test.ts:4:2`,
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(
			testSummary,
			`${timestamp}\tnode-test\t0\t4\tpass\t0\tbun test\n`,
			"utf8",
		);
		writeFileSync(
			testDetails,
			[
				"=== node-test ===",
				"command: bun test",
				"status: exit=0",
				"duration_ms: 4",
				"flaky_state: pass",
				"--- output ---",
				"same second pass",
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(testSemantic, "", "utf8");
		writeFileSync(
			join(stateDir, "timeline.log"),
			[
				`${timestamp}\tverify\t${root}\tfailures=1;warns=0\tsummary=${verifySummary};semantic=${verifySemantic}`,
				`${timestamp}\ttest\t${root}\tfailures=0;warns=0\tsummary=${testSummary};semantic=${testSemantic}`,
				"",
			].join("\n"),
			"utf8",
		);

		const status = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");

		expect(payload.verify.status).toBe("failing");
		expect(payload.test.status).toBe("passing");
		expect(payload.latest.source).toBe("test");
		expect(payload.latest.status).toBe("passing");
		expect(payload.latest.summaryReport).toBe(testSummary);
		expect(payload.summary.latestSource).toBe("test");
		expect(payload.summary.lastRunPassing).toBe(1);
		expect(payload.summary.lastRunFailing).toBe(0);
		expect(payload.failures).toHaveLength(0);
	});

	test("test run --failed reruns the latest failing runner set from local verify/test history", () => {
		const stateDir = ideTemp("yen-ide-test-rerun-state-");
		const project = ideTemp("yen-ide-test-rerun-project-");
		const env = { YEN_IDE_STATE_DIR: stateDir };

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "rerun-failed-fixture",
					scripts: {
						test: "bash -lc 'echo src/rerun.test.ts:4:2 failed >&2; exit 1'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		const verify = runYen(
			["ide", "verify", "--quick", "--no-security"],
			env,
			project,
		);
		expect(verify.status).toBe(1);

		const rerun = runYen(
			["ide", "test", "run", "--failed", "--project", project],
			env,
			project,
		);
		expect(rerun.status).toBe(1);
		expect(rerun.stdout).toContain("Mode:             failed");
		expect(rerun.stdout).toContain("Failure source:   verify");
		expect(rerun.stdout).toContain("Selected runners: node-test");

		const status = runYen(
			["ide", "test", "status", "--project", project, "--format", "json"],
			env,
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		expect(payload.test.status).toBe("failing");
		expect(payload.latest.source).toBe("test");
		expect(payload.latest.status).toBe("failing");
		expect(payload.summary.lastRunFailing).toBe(1);
		expect(payload.failures[0].runnerId).toBe("node-test");
	});

	test("test status is registered in CLI help and action search catalog", () => {
		const help = runYen(["ide"]);
		const searchHistory = readFileSync(ideSearchHistoryModulePath, "utf8");

		expect(help.status).toBe(0);
		expect(help.stdout).toContain("test [options]");
		expect(help.stdout).toContain("status [path] [--format text|json]");
		expect(help.stdout).toContain(
			"run [path] [--runner <id>] [--failed] [--quick] [--watch --watch-interval <sec> --max-runs <N>]",
		);
		expect(searchHistory).toContain("yen ide test status");
		expect(searchHistory).toContain("yen ide test run --failed");
	});
});
