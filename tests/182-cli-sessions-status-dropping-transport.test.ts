import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	EXIT,
	header,
	RemoteHarness,
	sessionID,
} from "./fixtures/sessions-remote-harness";

// Tailscale SSH on a macOS peer runs every command under macOS login, which
// exits 0 whatever the command's status was, so ssh reports 0 for a peer that
// failed. The fake ssh's exec-login step does the same; exec is OpenSSH's
// sshd, which passes the status through. `yen sessions --host` must tell the
// same story through both (_docs/01-architecture.md -> Remote attach).

const harness = new RemoteHarness(mkdtempSync(join(tmpdir(), "yen-remote-t-")));
afterAll(() => rmSync(harness.root, { recursive: true, force: true }));
beforeEach(() => harness.next());

const list = ["list", "--porcelain", "--host", "mini"];
const attach = ["attach", "--host", "mini", sessionID];
const row = `${sessionID}\tdetached\t1700000000\t/Users/dev/project`;
const transports = [
	["sshd", "exec"],
	["Tailscale SSH on a Mac", "exec-login"],
] as const;

function runList(step: string, peer: string | null) {
	harness.plan([`1 ${step}`]);
	const app = peer === null ? "/Users/dev/none/YEN.app" : harness.peerApp(peer);
	return harness.sessions(list, {
		YEN_REMOTE_APP: app,
		FAKE_SSH_LOGIN_SHELL: "/bin/bash",
	});
}

describe.each(transports)("yen sessions list --host through %s", (_, step) => {
	test("a peer YEN from before sessions is 13, update YEN there", () => {
		const result = runList(step, 'echo "Unknown command: sessions"; exit 1');
		expect(result.status, result.stderr).toBe(EXIT.tooOld);
		expect(result.stderr).toContain("update YEN there");
	});

	test("a peer YEN without --porcelain is 13", () => {
		const result = runList(step, 'echo "usage: yen sessions" >&2; exit 2');
		expect(result.status, result.stderr).toBe(EXIT.tooOld);
	});

	test("no YEN on the peer is 12", () => {
		const result = runList(step, null);
		expect(result.status, result.stderr).toBe(EXIT.notInstalled);
		expect(result.stderr).toContain("YEN is not installed on mini");
	});

	test("rows from a peer whose listing failed are printed, then exit 1", () => {
		const result = runList(step, `printf '%s\\n' '${header}' '${row}'; exit 1`);
		expect(result.stdout).toBe(`${header}\n${row}\n`);
		expect(result.stderr).toContain("mini reported a listing error");
		expect(result.status).toBe(1);
	});

	test("a complete listing is 0 and its stderr is not shown", () => {
		const result = runList(step, `printf '%s\\n' '${header}' '${row}'`);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toBe(`${header}\n${row}\n`);
		expect(result.stderr).toBe("");
	});

	test("a damaged peer is 1 and its own errors are replayed without the status line", () => {
		const result = runList(step, 'echo "dyld: missing library" >&2; exit 6');
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("dyld: missing library");
		expect(result.stderr).toContain("could not list the sessions on mini");
		expect(result.stderr).not.toContain("yen-remote-status");
	});

	test("a peer that prints a status line of its own cannot override the real one", () => {
		const result = runList(
			step,
			'echo "yen-remote-status 0" >&2; echo "Unknown command: sessions"; exit 1',
		);
		expect(result.status, result.stderr).toBe(EXIT.tooOld);
	});
});

describe("yen sessions list --host: what a status line can claim", () => {
	test("a status of 255 from the peer is not an ssh failure", () => {
		const result = runList(
			"exec-login",
			[
				'echo "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @" >&2',
				'echo "Host key verification failed." >&2',
				"exit 255",
			].join("\n"),
		);
		expect(result.status).toBe(1);
		expect(result.stderr).not.toContain("the host key of mini has changed");
	});
});

function runAttach(plan: string[], peer: string | null, input = "\n") {
	harness.plan(plan);
	const app = peer === null ? "/Users/dev/none/YEN.app" : harness.peerApp(peer);
	return harness.sessions(
		attach,
		{ YEN_REMOTE_APP: app, FAKE_SSH_LOGIN_SHELL: "/bin/bash" },
		input,
	);
}

const noSession = `echo "yen sessions: no session ${sessionID}" >&2; exit 1`;
const hold = "press Return to close";

describe("yen sessions attach --host through sshd", () => {
	test("an unknown session is 14 and the peer does not hold the pane", () => {
		const result = runAttach(["1 exec"], noSession);
		expect(result.status).toBe(EXIT.noSession);
		expect(result.stderr).toContain(`no session ${sessionID}`);
		expect(result.stderr).toContain(`could not attach session ${sessionID}`);
		expect(result.stderr).not.toContain(hold);
	});

	test("no YEN on the peer is 12 and the peer does not hold the pane", () => {
		const result = runAttach(["1 exec"], null);
		expect(result.status).toBe(EXIT.notInstalled);
		expect(result.stderr).not.toContain(hold);
	});
});

describe("yen sessions attach --host through Tailscale SSH on a Mac", () => {
	test("an unknown session keeps the peer's message on screen until Return", () => {
		const result = runAttach(["1 exec-login"], noSession);
		expect(result.stderr).toContain(`no session ${sessionID}`);
		expect(result.stderr).toContain(hold);
		// The transport reports 0, so the CLI cannot report 14 itself.
		expect(result.status).toBe(0);
	});

	test("no YEN on the peer is said on screen until Return", () => {
		const result = runAttach(["1 exec-login"], null);
		expect(result.stderr).toContain("YEN is not installed on the remote Mac");
		expect(result.stderr).toContain(hold);
	});

	test("a peer YEN from before sessions is shown until Return", () => {
		const result = runAttach(
			["1 exec-login"],
			'echo "Unknown command: sessions"; exit 1',
		);
		expect(result.stdout).toContain("Unknown command: sessions");
		expect(result.stderr).toContain(hold);
	});

	test.each([
		["a detach or the session ending", "exit 0"],
		["Ctrl-C", "exit 130"],
	])("%s closes without a hold", (_, peer) => {
		const result = runAttach(["1 exec-login"], peer);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stderr).not.toContain(hold);
	});

	test("a reconnect that finds the session gone holds once and ends the loop", () => {
		const result = runAttach(["1 255", "1 exec-login"], noSession);
		expect(result.stderr).toContain("lost the connection to mini");
		expect(result.stderr).toContain(`no session ${sessionID}`);
		expect(result.stderr.split(hold)).toHaveLength(2);
		expect(result.status).toBe(0);
		expect(harness.calls()).toHaveLength(2);
	});
});
