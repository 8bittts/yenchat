import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	EXIT,
	header,
	option,
	RemoteHarness,
	sessionID,
} from "./fixtures/sessions-remote-harness";

// The remote attach contract in _docs/01-architecture.md -> Persistent sessions
// -> Remote attach and _docs/04-security.md -> Remote Attach Threat Model, for
// the parts tests/172 leaves open: the exact ssh options on both connections,
// the ssh failure text the CLI classifies, the bytes it replays, what it hands
// ssh on stdin, and the remote command on the peer.

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-c-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const list = ["list", "--porcelain", "--host", "mini"];
const attach = ["attach", "--host", "mini", sessionID];

/// Every option the contract fixes for every connection, with its value.
const fixedOptions: Record<string, string> = {
	RemoteCommand: "none",
	ConnectTimeout: "10",
	ServerAliveInterval: "10",
	ServerAliveCountMax: "3",
	ControlMaster: "no",
	ControlPath: "none",
	ForwardAgent: "no",
	ForwardX11: "no",
	ClearAllForwardings: "yes",
};

/// What OpenSSH prints for a known host whose key no longer matches.
const changedHostKey = [
	"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@",
	"@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @",
	"@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@",
	"IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!",
	"Someone could be eavesdropping on you right now (man-in-the-middle attack)!",
	"It is also possible that a host key has just been changed.",
	"The fingerprint for the ED25519 key sent by the remote host is",
	"SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.",
	"Please contact your system administrator.",
	"Add correct host key in /Users/dev/.ssh/known_hosts to get rid of this message.",
	"Offending ED25519 key in /Users/dev/.ssh/known_hosts:3",
	"ED25519 host key for mini has changed and you have requested strict checking.",
	"Host key verification failed.",
	"",
].join("\n");

describe("yen sessions --host: every connection's ssh options", () => {
	test.each([
		["list", list],
		["attach", attach],
	])(
		"%s passes the fixed options with their values and no host key override",
		(_, args) => {
			harness.plan(["1 0"], { 1: `${header}\n` });
			const result = harness.sessions(args);
			expect(result.status, result.stderr).toBe(0);
			const argv = harness.firstCall();
			for (const [name, value] of Object.entries(fixedOptions)) {
				expect(option(argv, name), name).toBe(value);
			}
			for (const weakened of [
				"StrictHostKeyChecking",
				"UserKnownHostsFile",
				"GlobalKnownHostsFile",
				"UpdateHostKeys",
				"CheckHostIP",
			]) {
				expect(option(argv, weakened), weakened).toBeUndefined();
			}
			// Nothing follows the fixed remote command.
			const dashes = argv.indexOf("--");
			expect(argv).toHaveLength(dashes + 3);
			expect(argv[dashes + 1]).toBe("mini");
		},
	);

	test("a listing hands ssh no stdin, and an attach hands it the terminal's", () => {
		harness.plan(["1 0"], { 1: `${header}\n` });
		expect(
			harness.sessions(list, { FAKE_SSH_CAPTURE_STDIN: "1" }, "typed\n").status,
		).toBe(0);
		expect(harness.stdinOf(1)).toBe("");

		harness.next();
		harness.plan(["1 0"]);
		expect(
			harness.sessions(attach, { FAKE_SSH_CAPTURE_STDIN: "1" }, "typed\n")
				.status,
		).toBe(0);
		expect(harness.stdinOf(1)).toBe("typed\n");
	});
});

describe("yen sessions --host: ssh failure text", () => {
	test.each([
		["list", list],
		["attach", attach],
	])(
		"%s: OpenSSH's full changed-key report is 15, not an untrusted key",
		(_, args) => {
			harness.plan(["0 255"], {}, { 1: changedHostKey });
			const result = harness.sessions(args);
			expect(result.status).toBe(EXIT.hostKeyChanged);
			expect(result.stderr).toContain(
				"the host key of mini has changed; YEN will not connect until known_hosts is fixed",
			);
			expect(result.stderr).not.toContain("accept the key");
		},
	);

	test("the changed-key banner alone is 15", () => {
		harness.plan(
			["0 255"],
			{},
			{
				1: "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed.\n",
			},
		);
		expect(harness.sessions(list).status).toBe(EXIT.hostKeyChanged);
	});

	test("a reconnect that meets a changed key stops with 15", () => {
		harness.plan(
			["1 255 Connection to mini closed by remote host.", "0 255", "1 0"],
			{},
			{ 2: changedHostKey },
		);
		const result = harness.sessions(attach);
		expect(result.status).toBe(EXIT.hostKeyChanged);
		expect(harness.calls()).toHaveLength(2);
	});

	test("a peer that lists in another format version says so", () => {
		harness.plan(["1 0"], { 1: `yen-sessions\t2\n` });
		const result = harness.sessions(list);
		expect(result.status).toBe(EXIT.tooOld);
		expect(result.stderr).toContain(
			"YEN on mini lists sessions in another format version; update YEN on both Macs",
		);
	});

	test.each([
		["list", list],
		["attach", attach],
	])("%s replays ssh's stderr without control characters", (_, args) => {
		const hostile =
			"ssh: connect to host mini: \u001b]0;pwned\u0007 \u009b31mred\r\n";
		harness.plan(["0 255"], {}, { 1: hostile });
		const result = harness.sessions(args);
		expect(result.status).toBe(EXIT.unreachable);
		expect(result.stderr).toContain(
			"ssh: connect to host mini: ?]0;pwned? ?31mred\n",
		);
		for (const byte of ["\u001b", "\u0007", "\u009b", "\r"]) {
			expect(result.stderr.includes(byte), JSON.stringify(byte)).toBe(false);
		}
	});

	test("a peer's stderr before its header is replayed without control characters", () => {
		harness.plan(["1 1"], {}, { 1: "zsh: \u001b[2Jcleared \u009d8;;x\n" });
		const result = harness.sessions(list);
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("zsh: ?[2Jcleared ?8;;x");
		expect(result.stderr.includes("\u001b")).toBe(false);
		expect(result.stderr.includes("\u009d")).toBe(false);
	});
});

describe("yen sessions --host: the remote command on the peer", () => {
	test.each(["/bin/zsh", "/bin/bash", "/bin/sh"])(
		"attach runs the peer's YEN with only the attach words under %s",
		(shell) => {
			const app = harness.peerApp(
				`[[ "$*" == "sessions attach ${sessionID}" ]] || exit 9`,
			);
			harness.plan(["1 exec"]);
			const result = harness.sessions(attach, {
				YEN_REMOTE_APP: app,
				FAKE_SSH_LOGIN_SHELL: shell,
			});
			expect(result.status, result.stderr).toBe(0);
		},
	);

	test("variables the peer's startup files export never reach its YEN", () => {
		const app = harness.peerApp(
			[
				"for name in YEN_LIB YEN_RESOURCES YEN_CMD_DIR ZMX_SESSION; do",
				'  [[ -z "${!name:-}" ]] || { echo "$name leaked" >&2; exit 8; }',
				"done",
				"printf 'yen-sessions\\t1\\n'",
			].join("\n"),
		);
		harness.plan(["1 exec"]);
		const result = harness.sessions(list, {
			YEN_REMOTE_APP: app,
			FAKE_SSH_LOGIN_SHELL: "/bin/bash",
			FAKE_SSH_REMOTE_EXPORTS: [
				"YEN_LIB=/Users/dev/stale/lib",
				"YEN_RESOURCES=/Users/dev/stale/Resources",
				"YEN_CMD_DIR=/Users/dev/stale/commands",
				`ZMX_SESSION=${sessionID}`,
			].join("\n"),
		});
		expect(result.stderr).not.toContain("leaked");
		expect(result.status, result.stderr).toBe(0);
	});

	test.each(["relative/YEN.app", "/Users/dev/YEN copy.app", "/x;id/YEN.app"])(
		"YEN_REMOTE_APP %j is refused before ssh runs",
		(app) => {
			harness.plan(["1 0"], { 1: `${header}\n` });
			for (const args of [list, attach]) {
				const result = harness.sessions(args, { YEN_REMOTE_APP: app });
				expect(result.status).toBe(EXIT.usage);
				expect(result.stderr).toContain(
					"YEN_REMOTE_APP must be an absolute path",
				);
			}
			expect(harness.calls()).toEqual([]);
		},
	);
});

describe("yen sessions --host: targets the app also refuses", () => {
	test.each([
		"@mini",
		"fd7a:115c:a1e0::1;id",
		"fd7a:115c:a1e0:0:0:0:0:0:1",
		`fd7a:115c:a1e0:${"0:".repeat(12)}:1`,
		`${"u".repeat(65)}@mini`,
		`${"a".repeat(64)}.example.ts.net`,
		"mini-",
		"mini:22",
	])("refuses %j before running ssh", (target) => {
		harness.plan(["1 0"], { 1: `${header}\n` });
		const result = harness.sessions(["list", "--host", target]);
		expect(result.status).toBe(EXIT.usage);
		expect(harness.calls()).toEqual([]);
	});

	test.each([
		"fd7a:115c:a1e0:0:0:0:0:1",
		`${"u".repeat(64)}@mini`,
		`${"a".repeat(63)}.example.ts.net`,
		`${"a".repeat(63)}.${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(61)}`,
	])("accepts %j", (target) => {
		harness.plan(["1 0"], { 1: `${header}\n` });
		const result = harness.sessions(["list", "--porcelain", "--host", target]);
		expect(result.status, result.stderr).toBe(0);
		expect(harness.firstCall()).toContain(target);
	});
});
