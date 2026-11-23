import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	cliEnvironment,
	EXIT,
	RemoteHarness,
	sessionID,
	yen,
} from "./fixtures/sessions-remote-harness";

// The reconnecting mark a remote pane's CLI writes to its own terminal
// (_docs/01-architecture.md -> Persistent sessions -> Remote attach ->
// Reconnecting mark): OSC 9;4;4;0 while it waits to reconnect, OSC 9;4;0 once
// the connection is back and on every way out, and nothing unless the app
// asked for it.

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-m-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const attach = ["attach", "--host", "mini", sessionID];
const dropped = "1 255 Connection to mini closed by remote host.";
const refused = "0 255 ssh: connect to host mini port 22: Connection refused";
const hostKeyUnknown = "0 255 Host key verification failed.";
const askedPassword = "0 255 dev@mini: Permission denied (password).";
const flag = { YEN_REMOTE_RECONNECT_MARK: "1" };

const MARK = "4;0";
const CLEAR = "0";

/// Every OSC 9;4 the CLI wrote, as its state and value ("4;0" or "0").
function reports(stdout: string): string[] {
	const ESC = String.fromCharCode(0x1b);
	const BEL = String.fromCharCode(0x07);
	return stdout
		.split(`${ESC}]9;4;`)
		.slice(1)
		.map((rest) => {
			const end = rest.indexOf(BEL);
			return end < 0 ? "" : rest.slice(0, end);
		});
}

/// The reports with repeats folded, so a refresh of the same state reads once.
function transitions(stdout: string): string[] {
	return reports(stdout).filter(
		(state, index, all) => state !== all[index - 1],
	);
}

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

function sleeps(): number[] {
	const path = join(harness.sshDir, "sleeps");
	return existsSync(path)
		? readFileSync(path, "utf8").trim().split("\n").map(Number)
		: [];
}

describe("yen sessions attach --host: the reconnecting mark", () => {
	test("a drop marks the pane until the connection is back, and every exit clears it", () => {
		harness.plan([dropped, refused, "1 0"]);
		const result = harness.sessions(attach, { ...flag });
		expect(result.status, result.stderr).toBe(0);
		// Connected (cleared after sign-in), dropped, waiting, connected again, done.
		expect(transitions(result.stdout)).toEqual([CLEAR, MARK, CLEAR]);
		expect(reports(result.stdout).at(-1)).toBe(CLEAR);
	});

	test("the mark is written again while it waits, so the pane never loses it", () => {
		harness.plan([dropped, refused, refused, "1 0"]);
		const result = harness.sessions(
			attach,
			withFakeSleep({ ...flag, YEN_SSH_RETRY_MAX_DELAY: "30" }),
		);
		expect(result.status, result.stderr).toBe(0);
		// The engine drops a report after 15 seconds; no wait runs past 10
		// without a fresh mark.
		expect(sleeps().length).toBeGreaterThan(0);
		expect(Math.max(...sleeps())).toBeLessThanOrEqual(10);
		const marks = reports(result.stdout).filter((state) => state === MARK);
		// One before each wait and one before each retry.
		expect(marks.length).toBeGreaterThanOrEqual(sleeps().length);
		expect(transitions(result.stdout)).toEqual([CLEAR, MARK, CLEAR]);
	});

	test("--retry-unreachable marks the wait for a peer that never answered yet", () => {
		harness.plan([refused, refused, "1 0"]);
		const result = harness.sessions([...attach, "--retry-unreachable"], {
			...flag,
		});
		expect(result.status, result.stderr).toBe(0);
		expect(transitions(result.stdout)).toEqual([MARK, CLEAR]);
	});

	test.each([
		["an unconfirmed host key", hostKeyUnknown, EXIT.firstConnection],
		["a password prompt", askedPassword, EXIT.keyRequired],
		["an ended session", "1 1", EXIT.noSession],
	])("a stop on %s after a drop leaves no mark", (_name, failure, code) => {
		harness.plan([dropped, failure]);
		const result = harness.sessions(attach, { ...flag });
		expect(result.status, result.stderr).toBe(code);
		expect(transitions(result.stdout)).toEqual([CLEAR, MARK, CLEAR]);
	});

	test("without the app's flag nothing is written, whatever happens", () => {
		harness.plan([dropped, refused, "1 0"]);
		const result = harness.sessions(attach);
		expect(result.status, result.stderr).toBe(0);
		expect(reports(result.stdout)).toEqual([]);
		const local = harness
			.firstCall()
			.find((argument) => argument.startsWith("LocalCommand="));
		expect(local).toMatch(
			/^LocalCommand=\/usr\/bin\/touch \/[A-Za-z0-9._/-]+$/,
		);

		harness.next();
		harness.plan([refused, "1 0"]);
		const retried = harness.sessions([...attach, "--retry-unreachable"]);
		expect(retried.status, retried.stderr).toBe(0);
		expect(reports(retried.stdout)).toEqual([]);
	});

	test("with the flag the sign-in clear runs from the LocalCommand, with a strict path", () => {
		harness.plan(["1 0"]);
		const result = harness.sessions(attach, { ...flag });
		expect(result.status, result.stderr).toBe(0);
		const local = harness
			.firstCall()
			.find((argument) => argument.startsWith("LocalCommand="));
		expect(local).toMatch(
			/^LocalCommand=\/usr\/bin\/touch \/[A-Za-z0-9._/-]+; \/usr\/bin\/printf '\\033\]9;4;0\\007'$/,
		);
	});
});

async function waitForFile(path: string) {
	for (let i = 0; i < 100 && !existsSync(path); i++) await Bun.sleep(50);
	return Number(readFileSync(path, "utf8"));
}

describe("yen sessions attach --host: a signal during the wait clears the mark", () => {
	test.each([
		["SIGINT", 130],
		["SIGHUP", 129],
		["SIGTERM", 143],
	] as const)(
		"%s exits %d and the last report clears the mark",
		async (signal, code) => {
			harness.plan([dropped, "1 0"]);
			const cli = Bun.spawn([yen, "sessions", ...attach], {
				env: cliEnvironment(
					harness.sshDir,
					withFakeSleep({
						...flag,
						YEN_SSH_RETRY_MAX_DELAY: "30",
						FAKE_SLEEP_HANG: "1",
					}),
				),
				stdin: "ignore",
				stdout: "pipe",
				stderr: "ignore",
			});
			await waitForFile(join(harness.sshDir, "sleep-pid"));
			cli.kill(signal);
			expect(await cli.exited).toBe(code);
			const stdout = await new Response(cli.stdout).text();
			expect(transitions(stdout)).toEqual([CLEAR, MARK, CLEAR]);
		},
		15_000,
	);
});
