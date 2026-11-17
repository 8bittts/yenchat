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

function binaryAvailable(name: string) {
	const result = spawnSync(
		"bash",
		["-lc", `command -v ${name} >/dev/null 2>&1`],
		{
			cwd: repoRoot,
			encoding: "utf8",
		},
	);
	return result.status === 0;
}

function availability(available: boolean, binary: string): string {
	return available ? "available" : `missing-${binary}`;
}

function runnableCount(...entries: Array<[boolean, number]>): number {
	return entries.reduce(
		(total, [available, count]) => total + (available ? count : 0),
		0,
	);
}

function shellQuote(value: string) {
	return /^[A-Za-z0-9_./-]+$/.test(value)
		? value
		: `'${value.replace(/'/g, `'"'"'`)}'`;
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "native-task-fixture",
				scripts: {
					test: "bun test",
					lint: "biome check .",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(join(root, "bun.lock"), "", "utf8");
	writeFileSync(join(root, "Makefile"), "build:\n\t@echo build\n", "utf8");
	writeFileSync(
		join(root, "Justfile"),
		`${["fmt:", "\tbiome format .", "", "review:", "\tbun test"].join("\n")}\n`,
		"utf8",
	);
	writeFileSync(
		join(root, "Taskfile.yml"),
		`${[
			'version: "3"',
			"tasks:",
			"  dev:",
			"    cmds:",
			"      - bun run dev",
			"  ship:",
			"    cmds:",
			"      - bun run build",
		].join("\n")}\n`,
		"utf8",
	);
	mkdirSync(join(root, ".yen", "workflows"), { recursive: true });
	writeFileSync(
		join(root, ".yen", "workflows", "ship.toml"),
		["schema_version = 1", 'name = "ship"', 'step = "echo ok"'].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(root, ".yen", "workflows", "build.toml"),
		[
			"schema_version = 1",
			'name = "build"',
			'step = "echo build workflow"',
		].join("\n"),
		"utf8",
	);
	return root;
}

function createAlternateProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "justfile"),
		`${["check:", "\tbun test"].join("\n")}\n`,
		"utf8",
	);
	writeFileSync(
		join(root, "Taskfile.yaml"),
		`${[
			'version: "3"',
			"tasks:",
			"  lint:",
			"    cmds:",
			"      - biome check .",
		].join("\n")}\n`,
		"utf8",
	);
	mkdirSync(join(root, ".yen", "workflows"), { recursive: true });
	return root;
}

function createNestedWorkspaceContainerProject(prefix: string) {
	const root = ideTemp(prefix);
	const container = join(root, "yen-terminal");
	const overlays = join(container, "overlays");
	const ghostty = join(container, "ghostty");
	mkdirSync(overlays, { recursive: true });
	mkdirSync(ghostty, { recursive: true });
	writeFileSync(join(root, "package.json"), '{"name":"repo-root"}\n', "utf8");
	writeFileSync(
		join(overlays, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	writeFileSync(
		join(ghostty, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	return {
		root: realpathSync(root),
		container: realpathSync(container),
		overlays: realpathSync(overlays),
	};
}

function createNativeRunProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "native-run-fixture",
				scripts: {
					safe: "echo native > native-marker.txt",
					destructive: "rm -rf native-danger",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(join(root, "bun.lock"), "", "utf8");
	mkdirSync(join(root, "native-danger"), { recursive: true });
	mkdirSync(join(root, ".yen", "workflows"), { recursive: true });
	writeFileSync(
		join(root, ".yen", "workflows", "safe.toml"),
		[
			"schema_version = 1",
			'name = "safe"',
			'step = "echo workflow > workflow-marker.txt"',
		].join("\n"),
		"utf8",
	);
	return root;
}

function createNativeNoConflictProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "native-run-no-conflict-fixture",
				scripts: {
					check: "echo native dry run",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	return root;
}

describe("IDE S3H task discovery", () => {
	test("workflow discover reports repo-native tasks across package, make, just, and task sources without changing workflow execution semantics", () => {
		const project = createProject("yen-ide-native-discovery-");
		const root = realpathSync(project);
		const justAvailable = binaryAvailable("just");
		const taskAvailable = binaryAvailable("task");
		const bunAvailable = binaryAvailable("bun");
		const makeAvailable = binaryAvailable("make");
		const expectedRunnable = runnableCount(
			[bunAvailable, 2],
			[makeAvailable, 1],
			[justAvailable, 2],
			[taskAvailable, 2],
		);

		const text = runYen(["ide", "workflow", "discover", "--project", project]);
		const textOutput = `${text.stdout ?? ""}\n${text.stderr ?? ""}`;
		expect(text.status).toBe(0);
		expect(textOutput).toContain("IDE Native Task Discovery");
		expect(textOutput).toContain("Project:");
		expect(textOutput).toContain("package.json");
		expect(textOutput).toContain("Makefile");
		expect(textOutput).toContain("Justfile");
		expect(textOutput).toContain("Taskfile.yml");
		expect(textOutput).toContain("Tasks:   7");
		expect(textOutput).toContain(`Runnable: ${expectedRunnable}`);
		expect(textOutput).toContain("Workflow conflicts: 2");
		expect(textOutput).toContain("package.json:test");
		expect(textOutput).toContain("package.json:lint");
		expect(textOutput).toContain("Makefile:build");
		expect(textOutput).toContain("Justfile:fmt");
		expect(textOutput).toContain("Justfile:review");
		expect(textOutput).toContain("Taskfile.yml:dev");
		expect(textOutput).toContain("Taskfile.yml:ship");

		const json = runYen([
			"ide",
			"workflow",
			"discover",
			"--project",
			project,
			"--format",
			"json",
		]);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");
		expect(payload.schemaVersion).toBe(1);
		expect(payload.root).toBe(root);
		expect(payload.summary).toEqual({
			tasks: 7,
			runnable: expectedRunnable,
			workflowConflicts: 2,
		});
		const tasks = new Map(
			(payload.tasks as Array<Record<string, unknown>>).map((task) => [
				task.id as string,
				task,
			]),
		);
		expect(tasks.get("package.json:lint")).toEqual({
			id: "package.json:lint",
			source: "package.json",
			name: "lint",
			origin: "package.json:scripts.lint",
			path: join(root, "package.json"),
			definition: "biome check .",
			runner: "bun",
			runnable: bunAvailable,
			availability: availability(bunAvailable, "bun"),
			command: "bun run lint",
			category: "lint",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("package.json:test")).toEqual({
			id: "package.json:test",
			source: "package.json",
			name: "test",
			origin: "package.json:scripts.test",
			path: join(root, "package.json"),
			definition: "bun test",
			runner: "bun",
			runnable: bunAvailable,
			availability: availability(bunAvailable, "bun"),
			command: "bun run test",
			category: "test",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Makefile:build")).toEqual({
			id: "Makefile:build",
			source: "Makefile",
			name: "build",
			origin: "Makefile:build",
			path: join(root, "Makefile"),
			definition: "@echo build",
			runner: "make",
			runnable: makeAvailable,
			availability: availability(makeAvailable, "make"),
			command: "make build",
			category: "build",
			workflowConflict: true,
			workflowPath: join(root, ".yen", "workflows", "build.toml"),
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Justfile:fmt")).toEqual({
			id: "Justfile:fmt",
			source: "Justfile",
			name: "fmt",
			origin: "Justfile:fmt",
			path: join(root, "Justfile"),
			definition: "biome format .",
			runner: "just",
			runnable: justAvailable,
			availability: availability(justAvailable, "just"),
			command: `just --justfile ${shellQuote(join(root, "Justfile"))} fmt`,
			category: "format",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Justfile:review")).toEqual({
			id: "Justfile:review",
			source: "Justfile",
			name: "review",
			origin: "Justfile:review",
			path: join(root, "Justfile"),
			definition: "bun test",
			runner: "just",
			runnable: justAvailable,
			availability: availability(justAvailable, "just"),
			command: `just --justfile ${shellQuote(join(root, "Justfile"))} review`,
			category: "test",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Taskfile.yml:dev")).toEqual({
			id: "Taskfile.yml:dev",
			source: "Taskfile.yml",
			name: "dev",
			origin: "Taskfile.yml:dev",
			path: join(root, "Taskfile.yml"),
			definition: "bun run dev",
			runner: "task",
			runnable: taskAvailable,
			availability: availability(taskAvailable, "task"),
			command: `task --taskfile ${shellQuote(join(root, "Taskfile.yml"))} dev`,
			category: "dev",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Taskfile.yml:ship")).toEqual({
			id: "Taskfile.yml:ship",
			source: "Taskfile.yml",
			name: "ship",
			origin: "Taskfile.yml:ship",
			path: join(root, "Taskfile.yml"),
			definition: "bun run build",
			runner: "task",
			runnable: taskAvailable,
			availability: availability(taskAvailable, "task"),
			command: `task --taskfile ${shellQuote(join(root, "Taskfile.yml"))} ship`,
			category: "build",
			workflowConflict: true,
			workflowPath: join(root, ".yen", "workflows", "ship.toml"),
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(payload.sources).toEqual([
			{
				id: "package.json",
				path: join(root, "package.json"),
				present: true,
				support: "implemented",
				taskCount: 2,
			},
			{
				id: "Makefile",
				path: join(root, "Makefile"),
				present: true,
				support: "implemented",
				taskCount: 1,
			},
			{
				id: "Justfile",
				path: join(root, "Justfile"),
				present: true,
				support: "implemented",
				taskCount: 2,
			},
			{
				id: "justfile",
				path: join(root, "justfile"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
			{
				id: "Taskfile.yml",
				path: join(root, "Taskfile.yml"),
				present: true,
				support: "implemented",
				taskCount: 2,
			},
			{
				id: "Taskfile.yaml",
				path: join(root, "Taskfile.yaml"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
		]);

		const workflowShow = runYen([
			"ide",
			"workflow",
			"show",
			"ship",
			"--project",
			project,
		]);
		const workflowOutput = `${workflowShow.stdout ?? ""}\n${workflowShow.stderr ?? ""}`;
		expect(workflowShow.status).toBe(0);
		expect(workflowOutput).toContain("IDE Workflow");
		expect(workflowOutput).toContain("Workflow:       ship");
		expect(
			readFileSync(join(project, ".yen", "workflows", "build.toml"), "utf8"),
		).toContain('name = "build"');
	});

	test("workflow discover also handles lowercase justfile and Taskfile.yaml variants", () => {
		const project = createAlternateProject("yen-ide-native-discovery-alt-");
		const root = realpathSync(project);
		const justAvailable = binaryAvailable("just");
		const taskAvailable = binaryAvailable("task");

		const json = runYen([
			"ide",
			"workflow",
			"discover",
			"--project",
			project,
			"--format",
			"json",
		]);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");
		expect(payload.summary).toEqual({
			tasks: 2,
			runnable: (justAvailable ? 1 : 0) + (taskAvailable ? 1 : 0),
			workflowConflicts: 0,
		});

		const tasks = new Map(
			(payload.tasks as Array<Record<string, unknown>>).map((task) => [
				task.id as string,
				task,
			]),
		);
		expect(tasks.get("justfile:check")).toEqual({
			id: "justfile:check",
			source: "justfile",
			name: "check",
			origin: "justfile:check",
			path: join(root, "justfile"),
			definition: "bun test",
			runner: "just",
			runnable: justAvailable,
			availability: availability(justAvailable, "just"),
			command: `just --justfile ${shellQuote(join(root, "justfile"))} check`,
			category: "test",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(tasks.get("Taskfile.yaml:lint")).toEqual({
			id: "Taskfile.yaml:lint",
			source: "Taskfile.yaml",
			name: "lint",
			origin: "Taskfile.yaml:lint",
			path: join(root, "Taskfile.yaml"),
			definition: "biome check .",
			runner: "task",
			runnable: taskAvailable,
			availability: availability(taskAvailable, "task"),
			command: `task --taskfile ${shellQuote(join(root, "Taskfile.yaml"))} lint`,
			category: "lint",
			workflowConflict: false,
			workflowPath: "",
			risk: {
				level: "low",
				score: 0,
				reason: "baseline",
			},
		});
		expect(payload.sources).toEqual([
			{
				id: "package.json",
				path: join(root, "package.json"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
			{
				id: "Makefile",
				path: join(root, "Makefile"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
			{
				id: "Justfile",
				path: join(root, "Justfile"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
			{
				id: "justfile",
				path: join(root, "justfile"),
				present: true,
				support: "implemented",
				taskCount: 1,
			},
			{
				id: "Taskfile.yml",
				path: join(root, "Taskfile.yml"),
				present: false,
				support: "implemented",
				taskCount: 0,
			},
			{
				id: "Taskfile.yaml",
				path: join(root, "Taskfile.yaml"),
				present: true,
				support: "implemented",
				taskCount: 1,
			},
		]);
	});

	test("workflow discover resolves nested workspace container paths to the concrete product root", () => {
		const fixture = createNestedWorkspaceContainerProject(
			"yen-ide-nested-workflow-discover-",
		);

		const json = runYen([
			"ide",
			"workflow",
			"discover",
			"--project",
			fixture.container,
			"--format",
			"json",
		]);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");

		expect(payload.root).toBe(fixture.overlays);
		expect(payload.summary.tasks).toBe(0);
	});

	test("workflow run --native dry-runs explicitly without falling back to a conflicting workflow", () => {
		const stateDir = ideTemp("yen-ide-native-run-state-");
		const project = createNativeRunProject("yen-ide-native-run-dry-");
		const result = runYen(
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:safe",
				"--project",
				project,
				"--dry-run",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		expect(result.status).toBe(0);
		expect(output).toContain("Native Task Plan");
		expect(output).toContain("Native task:      package.json:safe");
		expect(output).toContain("Workflow conflict:yes");
		expect(output).toContain(
			"Execution would require explicit trust approval before the native task runs.",
		);
		expect(output).toContain(
			"Explicit native execution leaves the authored workflow untouched",
		);
		expect(output).toContain(
			"Dry run: native task plan rendered with zero side effects.",
		);
		expect(existsSync(join(project, "native-marker.txt"))).toBe(false);
		expect(existsSync(join(project, "workflow-marker.txt"))).toBe(false);
	});

	test("workflow run --native executes the discovered task while workflow run <name> keeps authored workflows authoritative", () => {
		const nativeStateDir = ideTemp("yen-ide-native-run-state-");
		const nativeProject = createNativeRunProject(
			"yen-ide-native-run-explicit-",
		);
		const nativeResult = runYen(
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:safe",
				"--project",
				nativeProject,
				"--allow-untrusted",
			],
			{ YEN_IDE_STATE_DIR: nativeStateDir },
		);
		const nativeOutput = `${nativeResult.stdout ?? ""}\n${nativeResult.stderr ?? ""}`;
		expect(nativeResult.status).toBe(0);
		expect(nativeOutput).toContain("Native task completed successfully.");
		expect(existsSync(join(nativeProject, "native-marker.txt"))).toBe(true);
		expect(existsSync(join(nativeProject, "workflow-marker.txt"))).toBe(false);
		expect(
			readFileSync(join(nativeProject, "native-marker.txt"), "utf8"),
		).toContain("native");
		expect(
			readFileSync(join(nativeStateDir, "timeline.log"), "utf8"),
		).toContain("kind=native;source=package.json");

		const workflowStateDir = ideTemp("yen-ide-native-run-workflow-state-");
		const workflowProject = createNativeRunProject(
			"yen-ide-native-run-workflow-",
		);
		const workflowResult = runYen(
			[
				"ide",
				"workflow",
				"run",
				"safe",
				"--project",
				workflowProject,
				"--allow-untrusted",
			],
			{ YEN_IDE_STATE_DIR: workflowStateDir },
		);
		const workflowOutput = `${workflowResult.stdout ?? ""}\n${workflowResult.stderr ?? ""}`;
		expect(workflowResult.status).toBe(0);
		expect(workflowOutput).toContain("Workflow completed successfully.");
		expect(existsSync(join(workflowProject, "workflow-marker.txt"))).toBe(true);
		expect(existsSync(join(workflowProject, "native-marker.txt"))).toBe(false);
		expect(
			readFileSync(join(workflowProject, "workflow-marker.txt"), "utf8"),
		).toContain("workflow");
	});

	test("workflow run --native --watch ignores self-written reports and stops explicitly when the discovered task disappears", async () => {
		const stateDir = ideTemp("yen-ide-native-watch-state-");
		const project = createNativeRunProject("yen-ide-native-watch-project-");
		const env = {
			...process.env,
			YEN_IDE_STATE_DIR: stateDir,
		};
		const child = spawn(
			yenBinPath,
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:safe",
				"--project",
				project,
				"--allow-untrusted",
				"--watch",
				"--watch-interval",
				"0.1",
			],
			{
				cwd: repoRoot,
				env,
				stdio: "pipe",
			},
		);
		const watchRun = captureChild(child);

		await waitForOutput(
			watchRun.getOutput,
			"Watch: waiting for project changes to rerun native task snapshot (package.json:safe).",
		);
		await delay(300);
		expect(watchRun.getOutput()).not.toContain("Watch iteration:  2");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "native-run-fixture",
					scripts: {
						destructive: "rm -rf native-danger",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		const result = await watchRun.settled;
		expect(result.code).toBe(1);
		expect(result.output).toContain("Watch:            enabled");
		expect(result.output).toContain(
			"Rerun scope:      native task snapshot (package.json:safe)",
		);
		expect(result.output).toContain("Watch iteration:  1");
		expect(result.output).toContain(
			"Native task 'package.json:safe' not found.",
		);

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("\tworkflow-watch\t");
		expect(timeline).toContain("reason=missing");
		expect(timeline).toContain("scope=native-task-snapshot");
		expect(timeline).toContain("task=package.json:safe");
		expect(timeline).toContain("path=package.json");
	});

	test("workflow run --native applies the approval gate to high-risk discovered commands", () => {
		const stateDir = ideTemp("yen-ide-native-run-state-");
		const project = createNativeRunProject("yen-ide-native-run-gate-");
		const result = runYen(
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:destructive",
				"--project",
				project,
				"--allow-untrusted",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		expect(result.status).toBe(1);
		expect(output).toContain("Native task denied by approval gate.");
		expect(existsSync(join(project, "native-danger"))).toBe(true);
		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("gate");
		expect(timeline).toContain("approval-denied");
	});

	test("workflow run --native rejects missing task ids explicitly", () => {
		const project = createNativeRunProject("yen-ide-native-run-missing-arg-");
		const result = runYen([
			"ide",
			"workflow",
			"run",
			"--native",
			"--project",
			project,
		]);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		expect(result.status).toBe(1);
		expect(output).toContain("workflow run --native requires a value.");
	});

	test("workflow run --native reports unknown task ids instead of silently succeeding", () => {
		const project = createNativeRunProject("yen-ide-native-run-missing-id-");
		const result = runYen([
			"ide",
			"workflow",
			"run",
			"--native",
			"package.json:missing",
			"--project",
			project,
		]);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		expect(result.status).toBe(1);
		expect(output).toContain("Native task 'package.json:missing' not found.");
		expect(output).toContain("yen ide workflow discover --project");
		expect(existsSync(join(project, "native-marker.txt"))).toBe(false);
		expect(existsSync(join(project, "workflow-marker.txt"))).toBe(false);
	});

	test("workflow run --native text output keeps empty workflow-path fields aligned", () => {
		const project = createNativeNoConflictProject(
			"yen-ide-native-run-text-alignment-",
		);
		const result = runYen([
			"ide",
			"workflow",
			"run",
			"--native",
			"package.json:check",
			"--project",
			project,
			"--dry-run",
		]);
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
		expect(result.status).toBe(0);
		expect(output).toContain("Workflow conflict:no");
		expect(output).not.toContain("Workflow path:    low");
		expect(output).toContain(
			"Description:      Repo-native task from package.json (custom)",
		);
	});

	test("workflow native watch flags are advertised in CLI help", () => {
		const help = runYen(["ide"]);
		expect(help.status).toBe(0);
		expect(help.stdout).toContain(
			"run --native <task-id> [--watch --watch-interval <sec> --max-runs <N>] executes one discovered native task explicitly",
		);
	});
});
