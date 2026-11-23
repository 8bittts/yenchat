import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	alive,
	cliEnvironment,
	header,
	RemoteHarness,
	sessionID,
	yen,
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

// attach --host: statuses it passes through, the reconnect backoff, and how it
// stops on a signal (_docs/01-architecture.md -> Reconnect).

const attach = ["attach", "--host", "mini", sessionID];
const dropped = "1 255 Connection to mini closed by remote host.";
const refused = "0 255 ssh: connect to host mini port 22: Connection refused";

/// A `sleep` first on PATH: records each delay, then returns at once, or with
/// FAKE_SLEEP_HANG=1 records its pid and sleeps for real.
const fakeBin = join(harness.root, "fake-bin");
mkdirSync(fakeBin);
writeFileSync(
	join(fakeBin, "sleep"),
	[
		"#!/bin/bash",
		'echo "$1" >> "$FAKE_SSH_DIR/sleeps"',
		'if [[ "${FAKE_SLEEP_HANG:-}" == 1 ]]; then echo "$$" > "$FAKE_SSH_DIR/sleep-pid"; exec /bin/sleep 30; fi',
		"",
	].join("\n"),
	{ mode: 0o755 },
);
const withFakeSleep = (extra: Record<string, string> = {}) => ({
	PATH: `${fakeBin}:${process.env.PATH}`,
	...extra,
});

function sleeps(): string[] {
	const path = join(harness.sshDir, "sleeps");
	return existsSync(path) ? readFileSync(path, "utf8").trim().split("\n") : [];
}

describe("yen sessions attach --host: statuses and backoff", () => {
	test.each([2, 7])(
		"a remote status %d that no class covers is passed through",
		(status) => {
			harness.plan([`1 ${status}`]);
			const result = harness.sessions(attach);
			expect(result.status).toBe(status);
			expect(harness.calls()).toHaveLength(1);
		},
	);

	test("the backoff doubles from 1 second to the 30-second cap and resets after each connection", () => {
		harness.plan([dropped, ...Array(6).fill(refused), dropped, "1 0"]);
		const result = harness.sessions(
			attach,
			withFakeSleep({ YEN_SSH_RETRY_MAX_DELAY: "30" }),
		);
		expect(result.status, result.stderr).toBe(0);
		expect(sleeps()).toEqual(["1", "2", "4", "8", "16", "30", "30", "1"]);
		const attempts = [...result.stderr.matchAll(/\(attempt (\d+),/g)].map(
			(m) => m[1],
		);
		expect(attempts).toEqual(["1", "2", "3", "4", "5", "6", "7", "1"]);
	});

	test("an unset cap is 30 seconds and a lower cap holds", () => {
		harness.plan([dropped, ...Array(6).fill(refused), "1 0"]);
		const environment = withFakeSleep();
		delete (environment as Record<string, string | undefined>)
			.YEN_SSH_RETRY_MAX_DELAY;
		const unset = harness.sessions(attach, {
			...environment,
			YEN_SSH_RETRY_MAX_DELAY: "",
		});
		expect(unset.status, unset.stderr).toBe(0);
		expect(sleeps().at(-1)).toBe("30");

		harness.next();
		harness.plan([dropped, refused, refused, refused, "1 0"]);
		const capped = harness.sessions(
			attach,
			withFakeSleep({ YEN_SSH_RETRY_MAX_DELAY: "5" }),
		);
		expect(capped.status, capped.stderr).toBe(0);
		expect(sleeps()).toEqual(["1", "2", "4", "5"]);
	});

	test.each(["x", "-1", "1.5"])(
		"YEN_SSH_RETRY_MAX_DELAY %j is refused before ssh runs",
		(value) => {
			harness.plan(["1 0"]);
			const result = harness.sessions(attach, {
				YEN_SSH_RETRY_MAX_DELAY: value,
			});
			expect(result.status).toBe(2);
			expect(result.stderr).toContain(
				"YEN_SSH_RETRY_MAX_DELAY must be a whole number of seconds",
			);
			expect(harness.calls()).toEqual([]);
		},
	);

	test("an unusable temporary directory stops before ssh and leaves nothing behind", () => {
		const scratch = join(harness.root, "with space");
		mkdirSync(scratch);
		harness.plan(["1 0"], { 1: `${header}\n` });
		for (const args of [attach, list]) {
			const result = harness.sessions(args, { TMPDIR: scratch });
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("Unusable temporary directory");
		}
		expect(harness.calls()).toEqual([]);
		expect(readdirSync(scratch)).toEqual([]);
	});
});

async function waitForFile(path: string) {
	for (let i = 0; i < 100 && !existsSync(path); i++) await Bun.sleep(50);
	return Number(readFileSync(path, "utf8"));
}

async function expectGone(pid: number) {
	for (let i = 0; i < 40 && alive(pid); i++) await Bun.sleep(50);
	const survived = alive(pid);
	if (survived) process.kill(pid, "SIGKILL");
	expect(survived).toBe(false);
}

describe("yen sessions --host: stopping on a signal", () => {
	const signals = [
		["SIGINT", 130],
		["SIGHUP", 129],
		["SIGTERM", 143],
	] as const;

	test.each(
		signals.flatMap(([signal, code]) =>
			(["list", "attach"] as const).map(
				(command) => [command, signal, code] as const,
			),
		),
	)(
		"%s on %s exits %d while ssh runs, ends ssh and removes the scratch directory",
		async (command, signal, code) => {
			harness.plan(["1 sleep30"]);
			const scratch = mkdtempSync(join(harness.root, "tmp-"));
			const cli = Bun.spawn(
				[yen, "sessions", ...(command === "list" ? list : attach)],
				{
					env: cliEnvironment(harness.sshDir, { TMPDIR: scratch }),
					stdin: "ignore",
					stdout: "ignore",
					stderr: "ignore",
				},
			);
			const ssh = await waitForFile(join(harness.sshDir, "pid-1"));
			cli.kill(signal);
			expect(await cli.exited).toBe(code);
			await expectGone(ssh);
			expect(readdirSync(scratch)).toEqual([]);
		},
		15_000,
	);

	test.each(signals)(
		"%s during the reconnect wait exits %d at once",
		async (signal, code) => {
			harness.plan([dropped, "1 0"]);
			const cli = Bun.spawn([yen, "sessions", ...attach], {
				env: cliEnvironment(
					harness.sshDir,
					withFakeSleep({
						YEN_SSH_RETRY_MAX_DELAY: "30",
						FAKE_SLEEP_HANG: "1",
					}),
				),
				stdin: "ignore",
				stdout: "ignore",
				stderr: "ignore",
			});
			const sleeper = await waitForFile(join(harness.sshDir, "sleep-pid"));
			const started = Date.now();
			cli.kill(signal);
			expect(await cli.exited).toBe(code);
			expect(Date.now() - started).toBeLessThan(5_000);
			await expectGone(sleeper);
			expect(harness.calls()).toHaveLength(1);
		},
		15_000,
	);
});
