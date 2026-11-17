import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	mkdirSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const gitReviewToolsPath = join(repoRoot, "yen-cli/lib/git-review-tools.sh");

function runCommand(
	cmd: string,
	args: string[],
	cwd: string,
	envOverrides: Record<string, string> = {},
) {
	return spawnSync(cmd, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function createReviewRepo() {
	const root = ideTemp("yen-yengit-review-");
	mkdirSync(join(root, "src"), { recursive: true });
	runCommand("git", ["init"], root);
	runCommand("git", ["config", "user.name", "YEN Tests"], root);
	runCommand("git", ["config", "user.email", "yen-tests@example.com"], root);

	const initialLines = Array.from(
		{ length: 15 },
		(_, index) => `line ${index + 1}`,
	);
	writeFileSync(
		join(root, "src", "a.ts"),
		`${initialLines.join("\n")}\n`,
		"utf8",
	);
	runCommand("git", ["add", "src/a.ts"], root);
	runCommand("git", ["commit", "-m", "baseline"], root);

	const updatedLines = [...initialLines];
	updatedLines[0] = "line 1 updated";
	updatedLines[11] = "line 12 updated";
	writeFileSync(
		join(root, "src", "a.ts"),
		`${updatedLines.join("\n")}\n`,
		"utf8",
	);

	return root;
}

function createYenResourcesSandbox() {
	const root = ideTemp("yen-yengit-resources-");
	mkdirSync(join(root, "bin"), { recursive: true });
	mkdirSync(join(root, "commands", "core"), { recursive: true });
	symlinkSync(join(repoRoot, "yen-cli", "lib"), join(root, "lib"));
	copyFileSync(
		join(repoRoot, "yen-cli", "commands", "core", "yengit"),
		join(root, "commands", "core", "yengit"),
	);
	chmodSync(join(root, "commands", "core", "yengit"), 0o755);

	const deltaPath = join(root, "bin", "delta");
	writeFileSync(
		deltaPath,
		`#!/bin/bash
printf "[delta-local] %s\\n" "$*"
cat
`,
		"utf8",
	);
	chmodSync(deltaPath, 0o755);

	return root;
}

function runYengitReview(
	repoDir: string,
	args: string[],
	envOverrides: Record<string, string> = {},
) {
	const resourceRoot = createYenResourcesSandbox();
	return spawnSync(yenBinPath, ["yengit", "review", ...args], {
		cwd: repoDir,
		encoding: "utf8",
		env: {
			...process.env,
			YEN_LIB: join(resourceRoot, "lib"),
			...envOverrides,
		},
	});
}

describe("Git review baseline upgrade", () => {
	test("shared hunk parser counts prefixed source and keeps deletion targets unambiguous", () => {
		const diff = `diff --git a/docs/list.md b/docs/list.md
--- a/docs/list.md
+++ b/docs/list.md
@@ -1 +1,5 @@
--- old item
+++ new item
+added 2
+added 3
+added 4
+added 5
@@ -3,2 +7 @@
 context 3
-deleted 4
`;
		const rows = spawnSync(
			"/bin/bash",
			[
				"-c",
				'source "$1"\nyen_git_review_emit_hunk_rows "docs/list.md"',
				"bash",
				gitReviewToolsPath,
			],
			{ input: diff, encoding: "utf8" },
		);

		expect(rows.status).toBe(0);
		expect(rows.stdout).toContain("docs/list.md:1:1");
		expect(rows.stdout).toContain("docs/list.md:7:1");

		const focusedDeletion = spawnSync(
			"/bin/bash",
			[
				"-c",
				'source "$1"\nyen_git_review_extract_hunk_from_file_diff 7',
				"bash",
				gitReviewToolsPath,
			],
			{ input: diff, encoding: "utf8" },
		);

		expect(focusedDeletion.status).toBe(0);
		expect(focusedDeletion.stdout).toContain("@@ -3,2 +7 @@");
		expect(focusedDeletion.stdout).toContain("-deleted 4");
		expect(focusedDeletion.stdout).not.toContain("+++ new item");
	});

	test("yengit review lists deterministic semantic hunk targets", () => {
		const repoDir = createReviewRepo();
		const res = runYengitReview(repoDir, [
			"--list-hunks",
			"--file",
			"src/a.ts",
		]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Git Review Hunk Targets");
		expect(output).toContain("src/a.ts:1:1");
		expect(output).toContain("src/a.ts:12:1");
	});

	test("yengit review renders one focused semantic hunk through bundled delta", () => {
		const repoDir = createReviewRepo();
		const res = runYengitReview(repoDir, ["--hunk", "src/a.ts:12"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("[delta-local] --paging=never");
		expect(output).toContain("Focused hunk: src/a.ts:12:1");
		expect(output).toContain("line 12 updated");
		expect(output).not.toContain("line 1 updated");
	});
});
