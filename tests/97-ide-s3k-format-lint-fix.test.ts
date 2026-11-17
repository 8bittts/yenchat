import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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

function runCommand(
	command: string,
	args: string[],
	cwd: string,
	envOverrides: Record<string, string> = {},
) {
	return spawnSync(command, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function initGitRepo(project: string) {
	expect(runCommand("git", ["init"], project).status).toBe(0);
	expect(
		runCommand("git", ["config", "user.email", "yen@example.com"], project)
			.status,
	).toBe(0);
	expect(
		runCommand("git", ["config", "user.name", "YEN Tests"], project).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], project).status).toBe(0);
	expect(runCommand("git", ["commit", "-m", "init"], project).status).toBe(0);
}

function writeExecutable(path: string, content: string) {
	writeFileSync(path, content, "utf8");
	chmodSync(path, 0o755);
}

describe("IDE S3K format/lint/fix baseline", () => {
	test("status surfaces shared repo-native candidates with stable recommended defaults", () => {
		const project = ideTemp("yen-ide-quality-project-");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-fixture",
					scripts: {
						format: "bun run biome format --write .",
						"lint:check": "bun run biome check .",
						lint: "bun run biome check --write .",
						fix: "bun run biome check --write . && bun run biome format --write .",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "Makefile"),
			[
				"fmt:",
				"\tbiome format --write .",
				"",
				"lint:",
				"\tbiome check .",
				"",
			].join("\n"),
			"utf8",
		);

		const formatStatus = runYen(
			["ide", "format", "status", "--project", project, "--format", "json"],
			{},
			project,
		);
		expect(formatStatus.status).toBe(0);
		const formatPayload = JSON.parse(formatStatus.stdout ?? "{}");
		const formatIds = new Set(
			(formatPayload.candidates ?? []).map(
				(candidate: { id: string }) => candidate.id,
			),
		);
		expect(formatPayload.action).toBe("format");
		expect(formatPayload.summary.recommendedId).toBe("package.json:format");
		expect(formatPayload.summary.recommendedRunnable).toBe(true);
		expect(formatIds.has("package.json:format")).toBe(true);
		expect(formatIds.has("Makefile:fmt")).toBe(true);

		const lintStatus = runYen(
			["ide", "lint", "status", "--project", project, "--format", "json"],
			{},
			project,
		);
		expect(lintStatus.status).toBe(0);
		const lintPayload = JSON.parse(lintStatus.stdout ?? "{}");
		const lintIds = new Set(
			(lintPayload.candidates ?? []).map(
				(candidate: { id: string }) => candidate.id,
			),
		);
		expect(lintPayload.action).toBe("lint");
		expect(lintPayload.summary.recommendedId).toBe("package.json:lint:check");
		expect(lintPayload.summary.recommendedRunnable).toBe(true);
		expect(lintIds.has("package.json:lint:check")).toBe(true);
		expect(lintIds.has("package.json:lint")).toBe(true);
		expect(lintIds.has("Makefile:lint")).toBe(true);

		const fixStatus = runYen(
			["ide", "fix", "status", "--project", project, "--format", "json"],
			{},
			project,
		);
		expect(fixStatus.status).toBe(0);
		const fixPayload = JSON.parse(fixStatus.stdout ?? "{}");
		const fixIds = new Set(
			(fixPayload.candidates ?? []).map(
				(candidate: { id: string }) => candidate.id,
			),
		);
		expect(fixPayload.action).toBe("fix");
		expect(fixPayload.summary.recommendedId).toBe("package.json:fix");
		expect(fixPayload.summary.recommendedRunnable).toBe(true);
		expect(fixIds.has("package.json:fix")).toBe(true);

		const text = runYen(["ide", "format", "--project", project], {}, project);
		expect(text.status).toBe(0);
		expect(text.stdout).toContain("IDE Format Status");
		expect(text.stdout).toContain("Recommended:        package.json:format");
		expect(text.stdout).toContain("Makefile:fmt");
	});

	test("status falls back to toolchain-default format candidates with missing-tool guidance", () => {
		const project = ideTemp("yen-ide-quality-fallback-");
		const limitedPath = "/usr/bin:/bin";

		writeFileSync(
			join(project, "Cargo.toml"),
			["[package]", 'name = "quality-fallback"', 'version = "0.1.0"', ""].join(
				"\n",
			),
			"utf8",
		);
		mkdirSync(join(project, "src"), { recursive: true });
		writeFileSync(
			join(project, "src", "lib.rs"),
			"pub fn sample() {}\n",
			"utf8",
		);

		const status = runYen(
			["ide", "format", "status", "--project", project, "--format", "json"],
			{ PATH: limitedPath },
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");

		expect(payload.summary.candidateCount).toBe(1);
		expect(payload.summary.runnableCount).toBe(0);
		expect(payload.summary.recommendedId).toBe("toolchain:cargo-fmt-check");
		expect(payload.recommended.originType).toBe("toolchain-default");
		expect(payload.recommended.sourcePath).toBe("Cargo.toml");
		expect(payload.recommended.runnable).toBe(false);
		expect(payload.recommended.availability).toBe("missing-cargo");
		expect(payload.recommended.explanation).toContain("Install cargo");
		expect(payload.guidance).toContain("Install cargo");
	});

	test("toolchain fallback scanning ignores nested dependency and scratch directories", () => {
		const project = ideTemp("yen-ide-quality-ignore-");

		mkdirSync(join(project, "node_modules", "dep"), { recursive: true });
		writeFileSync(
			join(project, "node_modules", "dep", "go.mod"),
			"module example.com/dep\n\ngo 1.22.0\n",
			"utf8",
		);
		mkdirSync(join(project, "tmp", "scratch-module"), { recursive: true });
		writeFileSync(
			join(project, "tmp", "scratch-module", "go.mod"),
			"module example.com/scratch\n\ngo 1.22.0\n",
			"utf8",
		);

		const status = runYen(
			["ide", "format", "status", "--project", project, "--format", "json"],
			{},
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");

		expect(payload.summary.candidateCount).toBe(0);
		expect(payload.summary.recommendedId).toBe("");
		expect(payload.guidance).toContain("No format candidates were detected");
	});

	test("format run executes repository-implied companion candidates for polyglot coverage", () => {
		const stateDir = ideTemp("yen-ide-quality-polyglot-state-");
		const project = ideTemp("yen-ide-quality-polyglot-project-");
		const fakeBin = join(stateDir, "bin");
		mkdirSync(fakeBin, { recursive: true });
		mkdirSync(join(project, "go-svc"), { recursive: true });

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "polyglot-quality-fixture",
					scripts: {
						format: "echo root format",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "go-svc", "go.mod"),
			"module example.com/polyglot\n\ngo 1.22.0\n",
			"utf8",
		);
		writeFileSync(join(project, "go-svc", "main.go"), "package main\n", "utf8");

		writeExecutable(
			join(fakeBin, "bun"),
			`#!/bin/bash
if [[ "$1" == "run" && "$2" == "format" ]]; then
  printf "root-format" > "$PWD/root-format.txt"
  exit 0
fi
exit 1
`,
		);
		writeExecutable(
			join(fakeBin, "gofmt"),
			`#!/bin/bash
printf "gofmt-ran" > "$PWD/gofmt-ran.txt"
exit 0
`,
		);

		const run = runYen(
			[
				"ide",
				"format",
				"run",
				"--project",
				project,
				"--trust",
				"--yes",
				"--format",
				"json",
			],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(run.status).toBe(0);
		const payload = JSON.parse(run.stdout ?? "{}");

		expect(payload.execution.status).toBe("success");
		expect(payload.selection.selectedId).toBe("package.json:format");
		expect(payload.selection.selectedIds).toContain("package.json:format");
		expect(
			(payload.selection.selectedIds as string[]).some((id) =>
				id.startsWith("toolchain:gofmt-check-"),
			),
		).toBe(true);
		expect(payload.commands).toHaveLength(2);
		expect(
			(payload.commands as Array<{ command: string }>).map(
				(entry) => entry.command,
			),
		).toEqual(expect.arrayContaining(["bun run format", "gofmt -l ."]));
		expect(readFileSync(join(project, "root-format.txt"), "utf8")).toBe(
			"root-format",
		);
		expect(
			(payload.commands as Array<{ command: string; workdir: string }>).some(
				(entry) =>
					entry.command === "gofmt -l ." &&
					String(entry.workdir).endsWith("/go-svc"),
			),
		).toBe(true);
	});

	test("dry-run preview derives changed-file plans from repo-native definitions and surfaces workflow conflicts", () => {
		const project = ideTemp("yen-ide-quality-preview-");

		mkdirSync(join(project, "src"), { recursive: true });
		mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-preview-fixture",
					scripts: {
						format: "biome format --write .",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "src", "app.ts"),
			"export const value = 1;\n",
			"utf8",
		);
		writeFileSync(
			join(project, ".yen", "workflows", "format.toml"),
			[
				"schema_version = 1",
				'name = "format"',
				'description = "workflow conflict fixture"',
				'step = "echo format workflow"',
				"",
			].join("\n"),
			"utf8",
		);
		initGitRepo(project);
		writeFileSync(
			join(project, "src", "app.ts"),
			"export const value = 2;\n",
			"utf8",
		);

		const preview = runYen(
			[
				"ide",
				"format",
				"run",
				"--dry-run",
				"--changed",
				"--project",
				project,
				"--format",
				"json",
			],
			{},
			project,
		);
		expect(preview.status).toBe(0);
		const payload = JSON.parse(preview.stdout ?? "{}");

		expect(payload.planStatus).toBe("ready");
		expect(payload.selection.selectedId).toBe("package.json:format");
		expect(payload.scope.mode).toBe("changed");
		expect(payload.scope.status).toBe("ok");
		expect(payload.scope.supported).toBe(true);
		expect(payload.scope.eligibleCount).toBe(1);
		expect(payload.scope.eligibleFiles).toContain("src/app.ts");
		expect(payload.candidate.workflowConflict).toBe(true);
		expect(payload.guidance).toContain(".yen/workflows/format.toml");
		expect(payload.commands).toHaveLength(1);
		expect(payload.commands[0].command).toContain(
			"biome format --write src/app.ts",
		);

		const status = runYen(["ide", "format", "--project", project], {}, project);
		expect(status.status).toBe(0);
		expect(status.stdout).toContain("conflict: authored workflow also exists");
	});

	test("dry-run preview explains when changed-file scope has no local changes", () => {
		const project = ideTemp("yen-ide-quality-no-changes-");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-no-changes-fixture",
					scripts: {
						lint: "biome check .",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "src.ts"),
			"export const untouched = true;\n",
			"utf8",
		);
		initGitRepo(project);

		const preview = runYen(
			[
				"ide",
				"lint",
				"run",
				"--dry-run",
				"--changed",
				"--project",
				project,
				"--format",
				"json",
			],
			{},
			project,
		);
		expect(preview.status).toBe(0);
		const payload = JSON.parse(preview.stdout ?? "{}");

		expect(payload.planStatus).toBe("no-changes");
		expect(payload.scope.status).toBe("no-changes");
		expect(payload.guidance).toContain("No changed files are available");
		expect(payload.commands).toHaveLength(0);
	});

	test("dry-run preview keeps missing-tool blockers explicit without mutating the workspace", () => {
		const project = ideTemp("yen-ide-quality-blocked-");
		const limitedPath = "/usr/bin:/bin";

		writeFileSync(
			join(project, "Cargo.toml"),
			["[package]", 'name = "quality-blocked"', 'version = "0.1.0"', ""].join(
				"\n",
			),
			"utf8",
		);

		const preview = runYen(
			[
				"ide",
				"format",
				"run",
				"--dry-run",
				"--project",
				project,
				"--format",
				"json",
			],
			{ PATH: limitedPath },
			project,
		);
		expect(preview.status).toBe(0);
		const payload = JSON.parse(preview.stdout ?? "{}");

		expect(payload.planStatus).toBe("blocked-missing-tool");
		expect(payload.selection.selectedId).toBe("toolchain:cargo-fmt-check");
		expect(payload.guidance).toContain("Install cargo");
		expect(payload.commands[0].command).toBe("cargo fmt --all --check");
	});

	test("run executes the recommended quality candidate with workflow trust, reports, and timeline output", () => {
		const stateDir = ideTemp("yen-ide-quality-run-state-");
		const project = ideTemp("yen-ide-quality-run-project-");

		mkdirSync(join(project, "src"), { recursive: true });
		mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-run-fixture",
					scripts: {
						format:
							"bash -lc 'echo src/app.ts:3:1 formatted >&2; printf formatted > formatted.txt'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "src", "app.ts"),
			"export const value = 1;\n",
			"utf8",
		);
		writeFileSync(
			join(project, ".yen", "workflows", "format.toml"),
			[
				"schema_version = 1",
				'name = "format"',
				'description = "workflow conflict fixture"',
				'step = "echo format workflow"',
				"",
			].join("\n"),
			"utf8",
		);

		const run = runYen(
			[
				"ide",
				"format",
				"run",
				"--project",
				project,
				"--trust",
				"--yes",
				"--format",
				"json",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(run.status).toBe(0);
		const payload = JSON.parse(run.stdout ?? "{}");

		expect(payload.execution.status).toBe("success");
		expect(payload.execution.exitCode).toBe(0);
		expect(payload.execution.trusted).toBe(true);
		expect(payload.selection.selectedId).toBe("package.json:format");
		expect(payload.candidate.workflowConflict).toBe(true);
		expect(payload.guidance).toContain(".yen/workflows/format.toml");
		expect(payload.reports.summary).not.toBe("");
		expect(payload.reports.details).not.toBe("");
		expect(payload.reports.semantic).not.toBe("");
		expect(payload.commands).toHaveLength(1);
		expect(payload.commands[0].status).toBe(0);
		expect(payload.commands[0].command).toContain("bun run format");
		expect(readFileSync(payload.reports.semantic, "utf8")).toContain(
			"src/app.ts:3:1",
		);

		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
		expect(timeline).toContain("\tworkflow-trust\t");
		expect(timeline).toContain("\tquality\t");
		expect(timeline).toContain("\tquality-step\t");
	});

	test("run returns a noop result when changed-file scope has nothing to execute", () => {
		const stateDir = ideTemp("yen-ide-quality-noop-state-");
		const project = ideTemp("yen-ide-quality-noop-project-");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-noop-fixture",
					scripts: {
						format: "biome format --write .",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "src.ts"),
			"export const clean = true;\n",
			"utf8",
		);
		initGitRepo(project);

		const run = runYen(
			[
				"ide",
				"format",
				"run",
				"--project",
				project,
				"--changed",
				"--trust",
				"--yes",
				"--format",
				"json",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(run.status).toBe(0);
		const payload = JSON.parse(run.stdout ?? "{}");

		expect(payload.execution.status).toBe("noop");
		expect(payload.planStatus).toBe("no-changes");
		expect(payload.reports.summary).toBe("");
		expect(payload.commands).toHaveLength(0);
	});

	test("run stays machine-readable when execution is blocked by workflow trust", () => {
		const stateDir = ideTemp("yen-ide-quality-untrusted-state-");
		const project = ideTemp("yen-ide-quality-untrusted-project-");

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-untrusted-fixture",
					scripts: {
						lint: "bash -lc 'echo blocked'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");

		const run = runYen(
			["ide", "lint", "run", "--project", project, "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(run.status).toBe(1);
		const payload = JSON.parse(run.stdout ?? "{}");

		expect(payload.execution.status).toBe("blocked");
		expect(payload.execution.exitCode).toBe(1);
		expect(payload.execution.trusted).toBe(false);
		expect(payload.selection.selectedId).toBe("package.json:lint");
	});

	test("text run output keeps workspace scope aligned when workflow path is empty", () => {
		const stateDir = ideTemp("yen-ide-quality-text-state-");
		const project = ideTemp("yen-ide-quality-text-project-");
		const fakeBin = join(stateDir, "bin");
		mkdirSync(fakeBin, { recursive: true });

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "quality-text-fixture",
					scripts: {
						lint: "echo lint",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeExecutable(
			join(fakeBin, "bun"),
			`#!/bin/bash
if [[ "$1" == "run" && "$2" == "lint" ]]; then
  echo "lint ok"
  exit 0
fi
exit 1
`,
		);

		const run = runYen(
			[
				"ide",
				"lint",
				"run",
				"--project",
				project,
				"--allow-untrusted",
				"--yes",
			],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(run.status).toBe(0);
		expect(run.stdout).toContain("Scope:             workspace");
		expect(run.stdout).not.toContain("Workflow path:     workspace");
	});

	test("format/lint/fix commands are registered in CLI help and action search catalog", () => {
		const help = runYen(["ide"]);
		const searchHistory = readFileSync(ideSearchHistoryModulePath, "utf8");

		expect(help.status).toBe(0);
		expect(help.stdout).toContain("format [options]");
		expect(help.stdout).toContain("lint [options]");
		expect(help.stdout).toContain("fix [options]");
		expect(help.stdout).toContain("status [path] [--format text|json]");
		expect(help.stdout).toContain("run [path] [--dry-run] [--changed]");
		expect(searchHistory).toContain("yen ide format status");
		expect(searchHistory).toContain("yen ide format run --dry-run --changed");
		expect(searchHistory).toContain("yen ide lint status");
		expect(searchHistory).toContain("yen ide lint run --dry-run --changed");
		expect(searchHistory).toContain("yen ide fix status");
		expect(searchHistory).toContain("yen ide fix run --dry-run --changed");
	});
});
