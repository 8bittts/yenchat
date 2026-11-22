import { describe, expect, test } from "bun:test";
import {
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// `yen ide` tests launch the real CLI, and a busy machine slows every launch
// and every temp-directory removal. Bun's 5-second default then fails healthy
// tests. The shared fixture owns one limit policy for the whole family; these
// cases run a real `bun test` child against it, so they hold whatever the
// fixture does internally.

const repoRoot = process.cwd();
const fixturePath = join(repoRoot, "tests/fixtures/ide-temp");
const BUN_DEFAULT_LIMIT_SECONDS = 5;
const SLOWER_THAN_DEFAULT_SECONDS = BUN_DEFAULT_LIMIT_SECONDS + 0.3;
const CHILD_RUN_LIMIT_MS = 60_000;

async function runChildTestFile(source: string): Promise<{
	exitCode: number;
	output: string;
}> {
	const dir = mkdtempSync(join(tmpdir(), "yen-ide-limits-"));
	try {
		const file = join(dir, "child.test.ts");
		writeFileSync(file, source, "utf8");
		const child = Bun.spawn(["bun", "test", file], {
			cwd: repoRoot,
			stdout: "pipe",
			stderr: "pipe",
		});
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(child.stdout).text(),
			new Response(child.stderr).text(),
			child.exited,
		]);
		return { exitCode, output: `${stdout}\n${stderr}` };
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

const slowCliCallFile = `
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createIdeTemp } from ${JSON.stringify(fixturePath)};

const { ideTemp } = createIdeTemp();

test("a CLI call slower than Bun's default limit", () => {
	ideTemp("yen-ide-limits-child-");
	const call = spawnSync("/bin/sleep", ["${SLOWER_THAN_DEFAULT_SECONDS}"]);
	expect({ status: call.status, signal: call.signal }).toEqual({
		status: 0,
		signal: null,
	});
});
`;

// The removal blocks once, the way a stalled disk blocks it under build load.
const slowCleanupFile = `
import { expect, mock, test } from "bun:test";
import * as realFs from "node:fs";

const realRmSync = realFs.rmSync;
let slowRemovals = 0;
mock.module("node:fs", () => ({
	...realFs,
	rmSync: (...args: Parameters<typeof realFs.rmSync>) => {
		if (slowRemovals === 0) Bun.sleepSync(${SLOWER_THAN_DEFAULT_SECONDS * 1000});
		slowRemovals += 1;
		return realRmSync(...args);
	},
}));

const { createIdeTemp } = await import(${JSON.stringify(fixturePath)});
const { ideTemp } = createIdeTemp();
let tracked = "";

test("a test whose cleanup is slower than Bun's default limit", () => {
	tracked = ideTemp("yen-ide-limits-child-");
	expect(realFs.existsSync(tracked)).toBe(true);
});

test("the slow cleanup ran and removed the directory", () => {
	expect(slowRemovals).toBeGreaterThan(0);
	expect(realFs.existsSync(tracked)).toBe(false);
});
`;

describe("IDE CLI test limits", () => {
	test(
		"a slow CLI call and a slow cleanup both pass in a file that uses the IDE fixture",
		async () => {
			const [slowCall, slowCleanup] = await Promise.all([
				runChildTestFile(slowCliCallFile),
				runChildTestFile(slowCleanupFile),
			]);

			expect(slowCall.output).not.toContain("timed out");
			expect(slowCall.output).toContain(" 1 pass");
			expect(slowCall.exitCode).toBe(0);

			expect(slowCleanup.output).not.toContain("timed out");
			expect(slowCleanup.output).toContain(" 2 pass");
			expect(slowCleanup.exitCode).toBe(0);
		},
		CHILD_RUN_LIMIT_MS,
	);

	test("no IDE test sets its own numeric limit below the shared policy", () => {
		const ideTestFiles = readdirSync(join(repoRoot, "tests"))
			.filter((name) => /-ide-.*\.(test|integration)\.ts$/.test(name))
			.sort();
		expect(ideTestFiles.length).toBeGreaterThan(0);

		// A literal such as a 15-second option is tighter than the shared
		// default and fails first under load; the shared constants replace it.
		const numericTestLimit = /\{\s*timeout:\s*[\d_]+\s*[,}]|\},\s*[\d_]+\s*\);/;
		const offenders = ideTestFiles.filter((name) =>
			numericTestLimit.test(
				readFileSync(join(repoRoot, "tests", name), "utf8"),
			),
		);
		expect(offenders).toEqual([]);

		const withoutFixture = ideTestFiles.filter(
			(name) =>
				!readFileSync(join(repoRoot, "tests", name), "utf8").includes(
					"createIdeTemp()",
				),
		);
		expect(withoutFixture).toEqual([]);
	});
});
