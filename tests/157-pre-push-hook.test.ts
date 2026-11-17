import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const hookPath = resolve(import.meta.dir, "../.githooks/pre-push");
const hookSource = readFileSync(hookPath, "utf8");
const ZERO = "0".repeat(40);

let dir = "";
beforeAll(() => {
	dir = mkdtempSync(join(tmpdir(), "pre-push-"));
});
afterAll(() => {
	rmSync(dir, { recursive: true, force: true });
});

const gitEnv = () => ({
	NODE_ENV: "test" as const,
	PATH: process.env.PATH ?? "",
	HOME: dir,
	GIT_CONFIG_NOSYSTEM: "1",
	GIT_CONFIG_GLOBAL: "/dev/null",
	GIT_AUTHOR_NAME: "YEN Test",
	GIT_AUTHOR_EMAIL: "test@example.invalid",
	GIT_COMMITTER_NAME: "YEN Test",
	GIT_COMMITTER_EMAIL: "test@example.invalid",
});

function git(repo: string, args: string[]) {
	const result = spawnSync("git", args, {
		cwd: repo,
		encoding: "utf8",
		env: gitEnv(),
	});
	if (result.status !== 0) throw new Error(result.stderr);
	return result.stdout.trim();
}

function repoWithCommits(
	name: string,
	count: number,
): { repo: string; shas: string[] } {
	const repo = join(dir, name);
	mkdirSync(repo);
	git(repo, ["init", "-q"]);
	const shas: string[] = [];
	for (let i = 0; i < count; i++) {
		git(repo, ["commit", "-q", "--allow-empty", "-m", `${name} commit ${i}`]);
		shas.push(git(repo, ["rev-parse", "HEAD"]));
	}
	return { repo, shas };
}

/** Runs the real hook with its pinned root swapped for a fixture root. */
function runHook(repo: string, root: string, pushedSha: string) {
	const hook = join(repo, "pre-push-under-test");
	writeFileSync(
		hook,
		hookSource.replace(
			/^PRIVATE_HISTORY_ROOT=[0-9a-f]{40}$/m,
			`PRIVATE_HISTORY_ROOT=${root}`,
		),
	);
	return spawnSync("sh", [hook, "origin", "https://example.invalid/repo.git"], {
		cwd: repo,
		encoding: "utf8",
		env: gitEnv(),
		input: `refs/heads/main ${pushedSha} refs/heads/main ${ZERO}\n`,
	});
}

describe("pre-push hook", () => {
	test("is executable and pins one full private-history root commit", () => {
		expect(statSync(hookPath).mode & 0o111).not.toBe(0);
		expect(hookSource).toMatch(/^PRIVATE_HISTORY_ROOT=[0-9a-f]{40}$/m);
	});

	test("rejects a push that descends from the private history root", () => {
		const { repo, shas } = repoWithCommits("private", 2);
		const result = runHook(repo, shas[0] ?? "", shas[1] ?? "");
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("[BLOCKED]");
	});

	test("allows a push from unrelated public history and a branch delete", () => {
		const privateRoot = repoWithCommits("old", 1).shas[0] ?? "";
		const { repo: publicRepo, shas: publicShas } = repoWithCommits("public", 2);
		expect(privateRoot).toMatch(/^[0-9a-f]{40}$/);
		expect(runHook(publicRepo, privateRoot, publicShas[1] ?? "").status).toBe(
			0,
		);
		expect(runHook(publicRepo, privateRoot, ZERO).status).toBe(0);
	});
});
