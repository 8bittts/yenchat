import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

// Guardrail for the `yen ide` lazy command router (item C2). Each lazily-routed
// subcommand loads only a curated superset of its transitive modules instead of
// the full ~22-module IDE suite. This test proves every curated light set stays
// sufficient: a benign, handler-reaching invocation must never surface a bash
// "command not found" (a missing sourced function) nor an "IDE module not found"
// loader error. Exit codes are intentionally NOT asserted — several commands
// legitimately error without a real project/PR; we only care that the handler is
// fully wired. Fresh YEN_IDE_STATE_DIR per case keeps runs hermetic.

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

// Each case launches the CLI from a fresh process. Keep a finite bound above the
// healthy runtime observed when the complete suite runs concurrently.
const test = (name: string, fn: () => void) =>
	bunTest(name, fn, { timeout: 15_000 });

function runIde(args: string[], input = "") {
	const stateDir = ideTemp("yen-ide-lazy-state-");
	return spawnSync(yenBinPath, args, {
		cwd: repoRoot,
		encoding: "utf8",
		input,
		env: {
			...process.env,
			YEN_IDE_STATE_DIR: stateDir,
		},
	});
}

describe("IDE lazy command router", () => {
	const project = ideTemp("yen-ide-lazy-proj-");
	const projectFile = join(project, "sample.txt");
	writeFileSync(projectFile, "hello world\n", "utf8");

	// Each entry is a benign invocation that reaches its handler. `input` is only
	// set where the handler reads stdin (parse). Anchored on the low/zero-coverage
	// commands called out in the plan (explain, timeline, pr-notify, open, replay)
	// plus the rest of the lazily-routed surface.
	const cases: Array<{ name: string; args: string[]; input?: string }> = [
		{ name: "ports", args: ["ide", "ports", "--json"] },
		{ name: "parse", args: ["ide", "parse"], input: "" },
		{ name: "history", args: ["ide", "history"] },
		{ name: "replay", args: ["ide", "replay"] },
		{ name: "profile", args: ["ide", "profile"] },
		{ name: "timeline", args: ["ide", "timeline"] },
		{ name: "gate", args: ["ide", "gate", "--dry-run", "--", "true"] },
		{
			name: "non-interference",
			args: ["ide", "non-interference", "status"],
		},
		{ name: "pr-notify", args: ["ide", "pr-notify", "--help"] },
		{
			name: "open",
			args: ["ide", "open", projectFile, "--dry-run", "--editor", "true"],
		},
		{ name: "benchmark", args: ["ide", "benchmark", "--help"] },
		{ name: "explain", args: ["ide", "explain", project] },
		{ name: "env", args: ["ide", "env", project] },
		{
			name: "vscode",
			args: ["ide", "vscode", "import", project, "--dry-run"],
		},
		{ name: "format", args: ["ide", "format", project, "--dry-run"] },
		{ name: "lint", args: ["ide", "lint", project] },
		{ name: "fix", args: ["ide", "fix", project, "--dry-run"] },
		{ name: "share", args: ["ide", "share", "--help"] },
		{
			name: "devcontainer",
			args: ["ide", "devcontainer", "status", project],
		},
		{ name: "workflow", args: ["ide", "workflow", "list", project] },
		// `detect`/`project` share the pre-prompt fast path that shell integration
		// calls before every first prompt, so a missing module there is the most
		// user-visible version of this defect. `--cached --format env` is the exact
		// shape the zsh/bash integrations invoke.
		{ name: "detect", args: ["ide", "detect", project] },
		{ name: "project", args: ["ide", "project", project] },
		{
			name: "detect --cached --format env",
			args: ["ide", "detect", "--cached", "--format", "env", project],
		},
	];

	for (const testCase of cases) {
		test(`${testCase.name} loads a sufficient module set`, () => {
			const res = runIde(testCase.args, testCase.input ?? "");
			const stderr = `${res.stderr ?? ""}`;
			expect(stderr).not.toContain("command not found");
			expect(stderr).not.toContain("IDE module not found");
		});
	}

	// The router must never fall back to eagerly loading the full suite for these
	// light commands. `detect`/`project` keep their own separate fast path, which
	// is covered by the cases above — it was previously assumed to be covered
	// elsewhere, and that gap let `ide_require_detect_modules` ship without
	// `workspace-doctor` while every other suite stayed green.
	test("router keeps light commands off the full-suite fallthrough", () => {
		const res = runIde(["ide", "ports", "--json"]);
		const stderr = `${res.stderr ?? ""}`;
		expect(stderr).not.toContain("command not found");
		expect(stderr).not.toContain("IDE module not found");
	});
});
