import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
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

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"search-fixture"}\n',
		"utf8",
	);
	mkdirSync(join(root, "src"), { recursive: true });
	return root;
}

function createGitSearchProject(prefix: string) {
	const root = createProject(prefix);
	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};

	writeFileSync(join(root, "CODEOWNERS"), "src/* @frontend-team\n", "utf8");
	writeFileSync(
		join(root, "src", "review-widget.ts"),
		"export class ReviewWidget {}\n",
		"utf8",
	);

	expect(runCommand("git", ["init"], root, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], root, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], root, gitEnv).status).toBe(0);
	expect(runCommand("git", ["commit", "-m", "init"], root, gitEnv).status).toBe(
		0,
	);

	return root;
}

describe("IDE S2 universal search", () => {
	test("search spans files/content/history/actions with project scoping", () => {
		const stateDir = ideTemp("yen-ide-search-state-");
		const projectA = createProject("yen-ide-search-a-");
		const projectB = createProject("yen-ide-search-b-");

		writeFileSync(
			join(projectA, "verify-guide.md"),
			"verify runbook\n",
			"utf8",
		);
		writeFileSync(
			join(projectA, "src", "notes.txt"),
			"first line\nverify keyword here\n",
			"utf8",
		);
		writeFileSync(
			join(projectB, "verify-secret.md"),
			"verify isolated\n",
			"utf8",
		);

		const addHistory = runYen(
			["ide", "history", "add", "yen", "ide", "verify", "--quick"],
			{ YEN_IDE_STATE_DIR: stateDir },
			projectA,
		);
		expect(addHistory.status).toBe(0);

		const search = runYen(
			[
				"ide",
				"search",
				"verify",
				"--project",
				projectA,
				"--sources",
				"files,content,history,actions",
				"--limit",
				"30",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${search.stdout ?? ""}\n${search.stderr ?? ""}`;
		expect(search.status).toBe(0);
		expect(output).toContain("IDE Universal Search");
		expect(output).toContain("file");
		expect(output).toContain("content");
		expect(output).toContain("history");
		expect(output).toContain("action");
		expect(output).toContain("verify-guide.md");
		expect(output).toContain("verify keyword here");
		expect(output).toContain("yen ide verify --quick");
		expect(output).not.toContain("verify-secret.md");
	});

	test("search ranking ties are deterministic and sorted by target", () => {
		const project = createProject("yen-ide-search-order-");
		writeFileSync(join(project, "a-verify.txt"), "alpha\n", "utf8");
		writeFileSync(join(project, "b-verify.txt"), "beta\n", "utf8");

		const first = runYen([
			"ide",
			"search",
			"verify",
			"--project",
			project,
			"--sources",
			"files",
			"--limit",
			"10",
		]);
		const second = runYen([
			"ide",
			"search",
			"verify",
			"--project",
			project,
			"--sources",
			"files",
			"--limit",
			"10",
		]);

		expect(first.status).toBe(0);
		expect(second.status).toBe(0);
		expect(first.stdout).toBe(second.stdout);

		const output = `${first.stdout ?? ""}`;
		const idxA = output.indexOf("a-verify.txt");
		const idxB = output.indexOf("b-verify.txt");
		expect(idxA).toBeGreaterThan(-1);
		expect(idxB).toBeGreaterThan(-1);
		expect(idxA).toBeLessThan(idxB);
	});

	test("search rejects unknown source tokens", () => {
		const project = createProject("yen-ide-search-invalid-");
		const res = runYen([
			"ide",
			"search",
			"verify",
			"--project",
			project,
			"--sources",
			"files,invalid-source",
		]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(1);
		expect(output).toContain("Unknown search source");
	});

	test("search surfaces symbol matches with review routing hints", () => {
		const project = createGitSearchProject("yen-ide-search-symbols-");

		const res = runYen([
			"ide",
			"search",
			"ReviewWidget",
			"--project",
			project,
			"--sources",
			"symbols,files",
			"--limit",
			"10",
		]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("symbol");
		expect(output).toContain("src/review-widget.ts:1:14");
		expect(output).toContain("ReviewWidget [class]");
		expect(output).toContain("owners=@frontend-team");
		expect(output).toContain("last=YEN Test");
		expect(output).not.toContain("yen ide debug start");
	});

	test("search only surfaces explicit debug routing when the local debugger baseline can actually launch the target", () => {
		const stateDir = ideTemp("yen-ide-search-debug-state-");
		const project = createProject("yen-ide-search-debug-project-");

		writeFileSync(
			join(project, "CODEOWNERS"),
			"app.js @runtime-team\n",
			"utf8",
		);
		writeFileSync(
			join(project, "app.js"),
			"export function launchApp() { return true; }\n",
			"utf8",
		);

		const res = runYen(
			[
				"ide",
				"search",
				"launchApp",
				"--project",
				project,
				"--sources",
				"files,content",
				"--limit",
				"10",
			],
			{ YEN_IDE_STATE_DIR: stateDir },
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("app.js");
		expect(output).toContain("owners=@runtime-team");
		expect(output).toContain("debug=yen ide debug start 'app.js:1' --project");
	});
});
