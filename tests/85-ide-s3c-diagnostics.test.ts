import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import {
	createIdeTemp,
	IDE_CLI_SLOW_TEST_TIMEOUT_MS,
} from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

// These hermetic CLI integration cases launch several subprocesses. Keep a finite
// bound above the healthy runtime observed when the complete suite runs concurrently.
const test = (name: string, fn: () => void) =>
	bunTest(name, fn, { timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS });

function runYen(
	args: string[],
	env: Record<string, string> = {},
	cwd = repoRoot,
) {
	return spawnSync(yenBinPath, args, {
		cwd,
		env: {
			...process.env,
			...env,
		},
		encoding: "utf8",
	});
}

function createProject(prefix: string) {
	const project = ideTemp(prefix);
	for (const relativePath of ["src/a.ts", "src/b.ts"]) {
		const absPath = join(project, relativePath);
		mkdirSync(dirname(absPath), { recursive: true });
		writeFileSync(absPath, `// fixture ${relativePath}\n`, "utf8");
	}
	return project;
}

function diagnosticsFileFor(project: string, env: Record<string, string>) {
	const res = runYen(
		["ide", "lsp", "status", "--project", project, "--format", "env"],
		env,
	);
	const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
	expect(res.status).toBe(0);
	return (
		output.match(/export YEN_IDE_LSP_DIAGNOSTICS_FILE='([^']+)'/)?.[1] ?? ""
	);
}

describe("IDE S3C diagnostics", () => {
	test("lsp diagnostics groups files, filters severities, and emits parse-compatible locations", () => {
		const stateDir = ideTemp("yen-ide-diagnostics-state-");
		const project = createProject("yen-ide-diagnostics-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(["ide", "lsp", "start", "--project", project], env).status,
		).toBe(0);

		const diagnosticsFile = diagnosticsFileFor(project, env);
		expect(diagnosticsFile).not.toBe("");
		mkdirSync(dirname(diagnosticsFile), { recursive: true });
		writeFileSync(
			diagnosticsFile,
			JSON.stringify(
				{
					items: [
						{
							file: "src/b.ts",
							line: 9,
							col: 4,
							severity: "warning",
							code: "TS6133",
							source: "tsserver",
							message: "Unused symbol",
						},
						{
							file: "src/a.ts",
							line: 2,
							severity: "error",
							code: "TS1005",
							source: "tsserver",
							message: "Expected semicolon",
						},
						{
							file: "src/a.ts",
							line: 7,
							col: 3,
							severity: "warning",
							code: "TS6196",
							source: "tsserver",
							message: "Declaration is never read",
						},
					],
				},
				null,
				2,
			),
			"utf8",
		);

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const diagnosticsOutput = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(0);
		expect(diagnosticsOutput).toContain("IDE LSP Diagnostics");
		expect(diagnosticsOutput).toContain("Snapshot status: fresh");
		expect(diagnosticsOutput).toContain("Results:      3");
		expect(diagnosticsOutput).toContain("src/a.ts");
		expect(diagnosticsOutput).toContain("src/b.ts");
		expect(diagnosticsOutput).toContain("src/a.ts:2:1");
		expect(diagnosticsOutput).toContain("src/a.ts:7:3");
		expect(diagnosticsOutput).toContain("src/b.ts:9:4");
		expect(diagnosticsOutput.indexOf("src/a.ts")).toBeLessThan(
			diagnosticsOutput.indexOf("src/b.ts"),
		);
		expect(diagnosticsOutput.indexOf("src/a.ts:2:1")).toBeLessThan(
			diagnosticsOutput.indexOf("src/a.ts:7:3"),
		);

		const errorOnly = runYen(
			[
				"ide",
				"lsp",
				"diagnostics",
				"--project",
				project,
				"--severity",
				"error",
			],
			env,
		);
		const errorOnlyOutput = `${errorOnly.stdout ?? ""}\n${errorOnly.stderr ?? ""}`;
		expect(errorOnly.status).toBe(0);
		expect(errorOnlyOutput).toContain("Results:      1");
		expect(errorOnlyOutput).toContain("src/a.ts:2:1");
		expect(errorOnlyOutput).not.toContain("src/a.ts:7:3");
		expect(errorOnlyOutput).not.toContain("src/b.ts:9:4");

		const parsed = runYen(["ide", "parse"], env, project);
		const parsedOutput = `${parsed.stdout ?? ""}\n${parsed.stderr ?? ""}`;
		const parseWithInput = spawnSync(yenBinPath, ["ide", "parse"], {
			cwd: project,
			env: {
				...process.env,
				...env,
			},
			input: diagnosticsOutput,
			encoding: "utf8",
		});
		const parseWithTsv = spawnSync(
			yenBinPath,
			["ide", "parse", "--format", "tsv"],
			{
				cwd: project,
				env: {
					...process.env,
					...env,
				},
				input: diagnosticsOutput,
				encoding: "utf8",
			},
		);
		const parseOutput = `${parseWithInput.stdout ?? ""}\n${parseWithInput.stderr ?? ""}`;
		const parseTsvOutput = `${parseWithTsv.stdout ?? ""}\n${parseWithTsv.stderr ?? ""}`;
		const fileARealPath = realpathSync(join(project, "src/a.ts"));
		const fileBRealPath = realpathSync(join(project, "src/b.ts"));
		expect(parsed.status).toBe(0);
		expect(parseWithInput.status).toBe(0);
		expect(parseWithTsv.status).toBe(0);
		expect(parseOutput).toContain("Parsed References");
		expect(parseOutput).toContain(fileARealPath);
		expect(parseOutput).toContain(fileBRealPath);
		expect(parseTsvOutput).toContain(
			`yes\tsrc/a.ts\t2\t1\t${fileARealPath}\tsrc/a.ts:2:1`,
		);
		expect(parseTsvOutput).toContain(
			`yes\tsrc/b.ts\t9\t4\t${fileBRealPath}\tsrc/b.ts:9:4`,
		);
		expect(parsedOutput).toContain("No file:line references found.");
	});

	test("lsp diagnostics only surfaces explicit debug routing for truly launchable local targets", () => {
		const stateDir = ideTemp("yen-ide-diagnostics-debug-state-");
		const project = ideTemp("yen-ide-diagnostics-debug-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		mkdirSync(join(project, "src"), { recursive: true });
		writeFileSync(
			join(project, "src", "app.js"),
			"throw new Error('boom')\n",
			"utf8",
		);
		writeFileSync(
			join(project, "src", "type-only.ts"),
			"export const value = 1;\n",
			"utf8",
		);

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(["ide", "lsp", "start", "--project", project], env).status,
		).toBe(0);

		const diagnosticsFile = diagnosticsFileFor(project, env);
		mkdirSync(dirname(diagnosticsFile), { recursive: true });
		writeFileSync(
			diagnosticsFile,
			JSON.stringify(
				{
					items: [
						{
							file: "src/app.js",
							line: 1,
							col: 1,
							severity: "error",
							code: "NODE100",
							source: "runtime",
							message: "Boom here",
						},
						{
							file: "src/type-only.ts",
							line: 1,
							col: 1,
							severity: "warning",
							code: "TS1005",
							source: "tsserver",
							message: "Keep external debugger for TS",
						},
					],
				},
				null,
				2,
			),
			"utf8",
		);

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const output = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(0);
		expect(output).toContain("src/app.js:1:1");
		expect(output).toContain("debug: yen ide debug start 'src/app.js:1:1'");
		expect(output).toContain("trust: yen ide debug trust");
		expect(output).toContain("src/type-only.ts:1:1");
		expect(output).not.toContain(
			"debug: yen ide debug start 'src/type-only.ts:1:1'",
		);
	});

	test("lsp diagnostics degrades cleanly when the runtime is inactive", () => {
		const stateDir = ideTemp("yen-ide-diagnostics-inactive-state-");
		const project = createProject("yen-ide-diagnostics-inactive-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const diagnosticsOutput = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(0);
		expect(diagnosticsOutput).toContain("No diagnostics snapshot available");
	});

	test("lsp diagnostics reports unreadable snapshots instead of pretending there were no matches", () => {
		const stateDir = ideTemp("yen-ide-diagnostics-corrupt-state-");
		const project = createProject("yen-ide-diagnostics-corrupt-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);
		expect(
			runYen(["ide", "lsp", "start", "--project", project], env).status,
		).toBe(0);

		const diagnosticsFile = diagnosticsFileFor(project, env);
		writeFileSync(diagnosticsFile, "{not-json\n", "utf8");

		const diagnostics = runYen(
			["ide", "lsp", "diagnostics", "--project", project],
			env,
		);
		const diagnosticsOutput = `${diagnostics.stdout ?? ""}\n${diagnostics.stderr ?? ""}`;
		expect(diagnostics.status).toBe(1);
		expect(diagnosticsOutput).toContain("Failed to read diagnostics snapshot");
		expect(diagnosticsOutput).toContain("invalid diagnostics snapshot");
	});
});
