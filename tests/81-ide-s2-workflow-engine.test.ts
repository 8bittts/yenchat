import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
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

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"workflow-fixture"}\n',
		"utf8",
	);
	mkdirSync(join(root, ".yen", "workflows"), { recursive: true });
	return root;
}

describe("IDE S2 workflow engine", () => {
	test("workflow dry-run renders ordered plan and leaves zero side effects", () => {
		const stateDir = ideTemp("yen-ide-workflow-state-");
		const project = createProject("yen-ide-workflow-dryrun-");
		const markerPath = join(project, "dry-run-marker.txt");

		writeFileSync(
			join(project, ".yen", "workflows", "quick-check.toml"),
			[
				"schema_version = 1",
				'name = "quick-check"',
				'description = "Validate dry-run plan output"',
				'step = "echo dry-run > dry-run-marker.txt"',
				'optional_step = "echo optional step"',
			].join("\n"),
			"utf8",
		);

		const res = runYen(
			[
				"ide",
				"workflow",
				"run",
				"quick-check",
				"--project",
				project,
				"--dry-run",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Workflow Plan");
		expect(output).toContain("Trust required: true");
		expect(output).toContain("STEP");
		expect(output).toContain(
			"Dry run: workflow plan rendered with zero side effects.",
		);
		expect(output).toContain("Execution would require explicit trust approval");
		expect(existsSync(markerPath)).toBe(false);
	});

	test("workflow execution is trust-gated for untrusted projects", () => {
		const stateDir = ideTemp("yen-ide-workflow-state-");
		const project = createProject("yen-ide-workflow-trust-");
		const markerPath = join(project, "trust-marker.txt");

		writeFileSync(
			join(project, ".yen", "workflows", "ship.toml"),
			[
				"schema_version = 1",
				'name = "ship"',
				'step = "echo trusted > trust-marker.txt"',
			].join("\n"),
			"utf8",
		);

		const blocked = runYen(
			["ide", "workflow", "run", "ship", "--project", project],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const blockedOutput = `${blocked.stdout ?? ""}\n${blocked.stderr ?? ""}`;
		expect(blocked.status).toBe(1);
		expect(blockedOutput).toContain(
			"Workflow execution blocked: project is untrusted.",
		);
		expect(existsSync(markerPath)).toBe(false);

		const allowUntrusted = runYen(
			[
				"ide",
				"workflow",
				"run",
				"ship",
				"--project",
				project,
				"--allow-untrusted",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const allowOutput = `${allowUntrusted.stdout ?? ""}\n${allowUntrusted.stderr ?? ""}`;
		expect(allowUntrusted.status).toBe(0);
		expect(allowOutput).toContain("Workflow completed successfully.");
		expect(existsSync(markerPath)).toBe(true);
	});

	test("workflow run logs step-level records and propagates non-zero failures", () => {
		const stateDir = ideTemp("yen-ide-workflow-state-");
		const project = createProject("yen-ide-workflow-fail-");
		mkdirSync(join(project, "src"), { recursive: true });
		writeFileSync(
			join(project, "src", "runtime.ts"),
			"// workflow fixture\n",
			"utf8",
		);

		writeFileSync(
			join(project, ".yen", "workflows", "failing.toml"),
			[
				"schema_version = 1",
				'name = "failing"',
				'step = "echo first > first-step.txt"',
				`step = "bash -lc 'echo src/runtime.ts:11:5 workflow failure >&2; exit 7'"`,
			].join("\n"),
			"utf8",
		);

		const res = runYen(
			[
				"ide",
				"workflow",
				"run",
				"failing",
				"--project",
				project,
				"--allow-untrusted",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(7);
		expect(output).toContain("Workflow failed at step 2 (status=7).");
		expect(output).toContain("Summary file:");
		expect(output).toContain("Details file:");
		expect(output).toContain("Semantic file:");

		const summaryMatch = output.match(/Summary file:\s+([^\n]+)/);
		const detailsMatch = output.match(/Details file:\s+([^\n]+)/);
		const semanticMatch = output.match(/Semantic file:\s+([^\n]+)/);
		expect(summaryMatch).not.toBeNull();
		expect(detailsMatch).not.toBeNull();
		expect(semanticMatch).not.toBeNull();

		const summaryPath = summaryMatch?.[1]?.trim() ?? "";
		const detailsPath = detailsMatch?.[1]?.trim() ?? "";
		const semanticPath = semanticMatch?.[1]?.trim() ?? "";
		expect(existsSync(summaryPath)).toBe(true);
		expect(existsSync(detailsPath)).toBe(true);
		expect(existsSync(semanticPath)).toBe(true);

		const summary = readFileSync(summaryPath, "utf8");
		const details = readFileSync(detailsPath, "utf8");
		const semantic = readFileSync(semanticPath, "utf8");
		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");

		expect(summary).toContain("\t1\trequired\t0\t");
		expect(summary).toContain("\t2\trequired\t7\t");
		expect(details).toContain("=== step 2 (required) ===");
		expect(semantic).toContain(
			"\t2\trequired\t7\tyes\tsrc/runtime.ts\t11\t5\t",
		);
		expect(semantic).toContain(
			`\t${realpathSync(join(project, "src", "runtime.ts"))}\tsrc/runtime.ts:11:5`,
		);
		expect(timeline).toContain("workflow-step");
		expect(timeline).toContain("status=7");
		expect(timeline).toContain("semantic=");
	});

	test("workflow schema validation rejects files missing schema_version", () => {
		const project = createProject("yen-ide-workflow-schema-");
		writeFileSync(
			join(project, ".yen", "workflows", "invalid.toml"),
			['name = "invalid"', 'step = "echo should-not-run"'].join("\n"),
			"utf8",
		);

		const res = runYen([
			"ide",
			"workflow",
			"show",
			"invalid",
			"--project",
			project,
		]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).not.toBe(0);
		expect(output).toContain("missing required 'schema_version'");
	});
});
