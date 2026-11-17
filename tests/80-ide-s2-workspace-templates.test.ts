import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	readdirSync,
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

function createMockAgentsBin(includeCodex = true) {
	const root = ideTemp("yen-agents-workspace-");
	const binDir = join(root, "bin");
	mkdirSync(binDir, { recursive: true });

	const claudePath = join(binDir, "claude");
	writeFileSync(
		claudePath,
		`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "claude 1.2.3"
  exit 0
fi
echo "claude-launch"
`,
		"utf8",
	);
	chmodSync(claudePath, 0o755);

	if (includeCodex) {
		const codexPath = join(binDir, "codex");
		writeFileSync(
			codexPath,
			`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "codex 4.5.6"
  exit 0
fi
echo "codex-launch"
`,
			"utf8",
		);
		chmodSync(codexPath, 0o755);
	}

	return { root, binDir };
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"workspace-fixture"}\n',
		"utf8",
	);
	mkdirSync(join(root, ".yen", "workspaces"), { recursive: true });
	return root;
}

describe("IDE S2 workspace templates", () => {
	test("templates list advertises built-in pair-coding and review-loop", () => {
		const res = runYen(["agents", "templates", "list"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Workspace Templates");
		expect(output).toContain("pair-coding");
		expect(output).toContain("review-loop");
		expect(output).toContain("SCHEMA");
	});

	test("project template apply is schema-versioned and idempotent", () => {
		const project = createProject("yen-workspace-idempotent-");
		const mock = createMockAgentsBin(true);
		const stateDir = ideTemp("yen-agents-state-");

		writeFileSync(
			join(project, ".yen", "workspaces", "pair-coding.toml"),
			[
				"schema_version = 1",
				'name = "pair-coding"',
				'description = "Project pair coding layout"',
				'slots = "claude,codex,supervisor"',
			].join("\n"),
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: stateDir,
		};

		const dryRun = runYen(
			[
				"agents",
				"templates",
				"apply",
				"pair-coding",
				"--project",
				project,
				"--dry-run",
			],
			env,
		);
		const dryRunOutput = `${dryRun.stdout ?? ""}\n${dryRun.stderr ?? ""}`;
		expect(dryRun.status).toBe(0);
		expect(dryRunOutput).toContain("Schema:       1");
		expect(dryRunOutput).toContain("Dry run: template plan rendered");

		const firstApply = runYen(
			["agents", "templates", "apply", "pair-coding", "--project", project],
			env,
		);
		const firstOutput = `${firstApply.stdout ?? ""}\n${firstApply.stderr ?? ""}`;
		expect(firstApply.status).toBe(0);
		expect(firstOutput).toContain("Applied workspace template 'pair-coding'");

		const stateFiles = readdirSync(join(stateDir, "workspaces"));
		expect(stateFiles.length).toBeGreaterThan(0);

		const secondApply = runYen(
			["agents", "templates", "apply", "pair-coding", "--project", project],
			env,
		);
		const secondOutput = `${secondApply.stdout ?? ""}\n${secondApply.stderr ?? ""}`;
		expect(secondApply.status).toBe(0);
		expect(secondOutput).toContain("already applied (idempotent)");
	});

	test("template apply degrades gracefully for unresolved slots", () => {
		const project = createProject("yen-workspace-degraded-");
		const mock = createMockAgentsBin(false);
		const stateDir = ideTemp("yen-agents-state-");

		const templatePath = join(project, ".yen", "workspaces", "custom.toml");
		writeFileSync(
			templatePath,
			[
				"schema_version = 1",
				'name = "custom"',
				'description = "Custom layout with unresolved slot"',
				'slots = "claude,unknownslot,supervisor"',
			].join("\n"),
			"utf8",
		);
		expect(existsSync(templatePath)).toBe(true);

		const res = runYen(
			[
				"agents",
				"templates",
				"apply",
				"custom",
				"--project",
				project,
				"--dry-run",
			],
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_AGENTS_STATE_DIR: stateDir,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("degraded");
		expect(output).toContain("Run: yen agents list");
	});

	test("template apply records a timeline event for the workspace", () => {
		const project = createProject("yen-workspace-timeline-");
		const mock = createMockAgentsBin(true);
		const stateDir = ideTemp("yen-agents-state-");

		writeFileSync(
			join(project, ".yen", "workspaces", "pair-coding.toml"),
			[
				"schema_version = 1",
				'name = "pair-coding"',
				'description = "Project pair coding layout"',
				'slots = "claude,codex,supervisor"',
			].join("\n"),
			"utf8",
		);

		const env = {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_AGENTS_STATE_DIR: stateDir,
		};

		const applyRes = runYen(
			["agents", "templates", "apply", "pair-coding", "--project", project],
			env,
		);
		expect(applyRes.status).toBe(0);

		const timelineRes = runYen(
			["agents", "timeline", "--project", project],
			env,
		);
		const output = `${timelineRes.stdout ?? ""}\n${timelineRes.stderr ?? ""}`;
		expect(timelineRes.status).toBe(0);
		expect(output).toContain("template-apply");
		expect(output).toContain("template=pair-coding");
		expect(output).toContain("slots=claude,codex,supervisor");
	});
});
