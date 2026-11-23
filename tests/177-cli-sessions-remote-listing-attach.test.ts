import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	header,
	RemoteHarness,
	sessionID,
} from "./fixtures/sessions-remote-harness";

// `yen sessions list --host` reading a peer's porcelain, for the rows and exit
// statuses tests/172 leaves open (_docs/01-architecture.md -> Persistent
// sessions -> Remote attach, the porcelain paragraph and the exit table).

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-l-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const other = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
const list = ["list", "--porcelain", "--host", "mini"];

describe("yen sessions list --host: rows", () => {
	test("keeps every valid state and a 12-digit start, and drops an empty directory or a 13-digit start", () => {
		harness.plan(["1 0"], {
			1: [
				header,
				`${sessionID}\tunreachable\t999999999999\t-`,
				`${other}\tattached\t1\t/Users/dev`,
				`${other}\tdetached\t1\t`,
				`${other}\tdetached\t1000000000000\t/x`,
				"",
			].join("\n"),
		});
		const result = harness.sessions(list);
		expect(result.stdout).toBe(
			[
				header,
				`${sessionID}\tunreachable\t999999999999\t-`,
				`${other}\tattached\t1\t/Users/dev`,
				"",
			].join("\n"),
		);
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("mini reported a listing error");
	});

	test("replaces C1 control characters in a directory", () => {
		harness.plan(["1 0"], {
			1: `${header}\n${sessionID}\tdetached\t-\t/Users/dev/\u009b31mred\u0085x\n`,
		});
		const result = harness.sessions(list);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toBe(
			`${header}\n${sessionID}\tdetached\t-\t/Users/dev/?31mred?x\n`,
		);
	});

	test("keeps a last row that has no newline", () => {
		harness.plan(["1 0"], {
			1: `${header}\n${other}\tattached\t-\t/a\n${sessionID}\tdetached\t-\t/Users/dev`,
		});
		const result = harness.sessions(list);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toBe(
			`${header}\n${other}\tattached\t-\t/a\n${sessionID}\tdetached\t-\t/Users/dev\n`,
		);
	});

	test.each([
		["porcelain", list],
		["table", ["list", "--host", "mini"]],
	])(
		"a peer that lists and then fails still shows its rows and exits 1 (%s)",
		(_, args) => {
			harness.plan(["1 1"], {
				1: `${header}\n${sessionID}\tdetached\t-\t/Users/dev\n`,
			});
			const result = harness.sessions(args);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain(sessionID);
			expect(result.stderr).toContain("mini reported a listing error");
		},
	);
});

describe("yen sessions --host: the temporary directory", () => {
	test("an unusable temporary directory stops before ssh and leaves nothing behind", () => {
		const scratch = join(harness.root, "with space");
		mkdirSync(scratch);
		harness.plan(["1 0"], { 1: `${header}\n` });
		for (const args of [["attach", "--host", "mini", sessionID], list]) {
			const result = harness.sessions(args, { TMPDIR: scratch });
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("Unusable temporary directory");
		}
		expect(harness.calls()).toEqual([]);
		expect(readdirSync(scratch)).toEqual([]);
	});
});
