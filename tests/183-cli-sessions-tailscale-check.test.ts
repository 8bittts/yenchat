import {
	afterAll,
	beforeEach,
	describe,
	expect,
	setDefaultTimeout,
	test,
} from "bun:test";
import { spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
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

// A Tailscale SSH `check` rule whose approval is due holds sign-in and sends
// the control server's text, with a per-connection link, as an auth banner
// (ssh/tailssh/tailssh.go, clientAuth). The fake ssh's check-* steps stand in
// for it. A listing must stop at once with its own exit code and never show
// the link; an attach must show the link in its pane while it waits.

// Runs below wait for a deadline or a held ssh on purpose.
setDefaultTimeout(20_000);

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-k-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const CHECK_REQUIRED = 17;
const list = ["list", "--porcelain", "--host", "mini"];
const attach = ["attach", "--host", "mini", sessionID];
const link = "login.tailscale.com/a/0123456789ab";
const advice =
	"run 'ssh mini' once in a terminal and approve it in the browser";

/// A CLI run with its own TMPDIR, so its temporary files can be checked, and
/// an optional deadline that ends it with SIGTERM as the app's would.
function run(args: string[], timeout = 15_000) {
	const tmp = join(harness.sshDir, "tmp");
	mkdirSync(tmp);
	const started = Date.now();
	const result = spawnSync(yen, ["sessions", ...args], {
		encoding: "utf8",
		env: cliEnvironment(harness.sshDir, { TMPDIR: tmp }),
		input: "",
		timeout,
		killSignal: "SIGTERM",
	});
	return { ...result, seconds: (Date.now() - started) / 1000, tmp };
}

function sshPid(call: number) {
	return Number(readFileSync(join(harness.sshDir, `pid-${call}`), "utf8"));
}

/// Wait up to two seconds for every trace of a run to go: the ssh child, the
/// CLI's temporary directory, and its stderr watcher.
function settled(pid: number, tmp: string) {
	const end = Date.now() + 2_000;
	while (Date.now() < end) {
		const watchers = spawnSync("ps", ["-axo", "command"], { encoding: "utf8" })
			.stdout.split("\n")
			.filter(
				(line) => line.includes("yen-remote-watch") && line.includes(tmp),
			);
		if (!alive(pid) && readdirSync(tmp).length === 0 && watchers.length === 0) {
			return true;
		}
		Bun.sleepSync(100);
	}
	return false;
}

describe("yen sessions list --host: a pending Tailscale SSH check", () => {
	test("stops at once with 17 and the step, without the link", () => {
		harness.plan(["0 check-hold30"]);
		const result = run(list);
		expect(result.status, result.stderr).toBe(CHECK_REQUIRED);
		expect(result.seconds).toBeLessThan(5);
		expect(result.stderr).toContain(
			"yen sessions: mini asks for a Tailscale SSH check;",
		);
		expect(result.stderr).toContain(advice);
		expect(result.stderr).not.toContain(link);
		expect(result.stdout).toBe("");
		expect(settled(sshPid(1), result.tmp)).toBe(true);
	});

	test("a denied or expired check is 17, not a key sign-in problem", () => {
		harness.plan(["0 check-deny"]);
		const result = run(list);
		expect(result.status, result.stderr).toBe(CHECK_REQUIRED);
		expect(result.stderr).toContain(advice);
		expect(result.stderr).not.toContain("asks for a password");
		expect(result.stderr).not.toContain(link);
	});

	test("a listing that ends normally is unchanged", () => {
		harness.plan(["1 0"], { 1: `${header}\n` });
		const result = run(list);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toBe(`${header}\n`);
	});

	test("a deadline that ends the CLI still ends ssh and removes its files", () => {
		harness.plan(["1 sleep30"]);
		const result = run(list, 1_500);
		// The CLI traps the deadline's SIGTERM, cleans up and exits 143.
		expect(result.status).toBe(143);
		expect(settled(sshPid(1), result.tmp)).toBe(true);
	});
});

describe("yen sessions attach --host: a pending Tailscale SSH check", () => {
	test("the pane shows the link while ssh waits for the approval", () => {
		harness.plan(["1 check-hold30"]);
		const result = run(attach, 3_000);
		// The CLI traps the deadline's SIGTERM, cleans up and exits 143.
		expect(result.status).toBe(143);
		expect(result.stderr).toContain(`To authenticate, visit: https://${link}`);
		expect(settled(sshPid(1), result.tmp)).toBe(true);
	});

	test("after the approval the attach goes on, and the link is shown once", () => {
		harness.plan(["1 check-pass1"]);
		const result = run(attach);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stderr.split(link)).toHaveLength(2);
		expect(harness.calls()).toHaveLength(1);
	});

	test("a reconnect that meets the check waits for it instead of looping", () => {
		harness.plan(["1 255", "1 check-pass1"]);
		const result = run(attach);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stderr).toContain("lost the connection to mini");
		expect(result.stderr.split(link)).toHaveLength(2);
		expect(harness.calls()).toHaveLength(2);
	});

	test("a denied check ends the attach with 17 and the step", () => {
		harness.plan(["1 255", "1 check-deny"]);
		const result = run(attach);
		expect(result.status, result.stderr).toBe(CHECK_REQUIRED);
		expect(result.stderr).toContain(advice);
		expect(harness.calls()).toHaveLength(2);
	});
});
