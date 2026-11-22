import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
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

// `yen sessions --host` against a fake ssh (tests/fixtures/fake-ssh.sh): the argv
// it builds, how it refuses hostile input, how it maps each failure class to an
// exit code, and when attach reconnects (_docs/01-architecture.md -> Persistent
// sessions -> Remote attach).

const repoRoot = join(import.meta.dir, "..");
const yen = join(repoRoot, "yen-cli/bin/yen");
const fakeSSH = join(repoRoot, "tests/fixtures/fake-ssh.sh");
const sessionID = "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
const header = "yen-sessions\t1";

const EXIT = {
	usage: 2,
	unreachable: 10,
	firstConnection: 11,
	notInstalled: 12,
	tooOld: 13,
	noSession: 14,
	hostKeyChanged: 15,
} as const;

const root = mkdtempSync(join(tmpdir(), "yen-remote-"));
let sshDir = "";
let run = 0;

afterAll(() => rmSync(root, { recursive: true, force: true }));

beforeEach(() => {
	run += 1;
	sshDir = join(root, `ssh-${run}`);
	mkdirSync(sshDir);
});

function plan(lines: string[], stdout: Record<number, string> = {}) {
	writeFileSync(join(sshDir, "plan"), `${lines.join("\n")}\n`);
	for (const [call, text] of Object.entries(stdout)) {
		writeFileSync(join(sshDir, `stdout-${call}`), text);
	}
}

function sessions(args: string[], env: Record<string, string> = {}) {
	const environment: NodeJS.ProcessEnv = {
		...process.env,
		YEN_LIB: "",
		YEN_SSH_BIN: fakeSSH,
		YEN_SSH_RETRY_MAX_DELAY: "0",
		FAKE_SSH_DIR: sshDir,
		...env,
	};
	// A zmx session inherited from a YEN pane must not reach the probes.
	for (const key of Object.keys(environment)) {
		if (key.startsWith("ZMX_")) delete environment[key];
	}
	return spawnSync(yen, ["sessions", ...args], {
		encoding: "utf8",
		env: environment,
		timeout: 15_000,
	});
}

function calls(): string[][] {
	return readdirSync(sshDir)
		.filter((name) => name.startsWith("argv-"))
		.sort((a, b) => Number(a.slice(5)) - Number(b.slice(5)))
		.map((name) =>
			readFileSync(join(sshDir, name), "utf8").split("\0").slice(0, -1),
		);
}

function firstCall(): string[] {
	const [argv] = calls();
	if (!argv) throw new Error("fake ssh was not called");
	return argv;
}

function option(argv: string[], name: string) {
	const value = argv.find(
		(entry, i) => argv[i - 1] === "-o" && entry.startsWith(`${name}=`),
	);
	return value?.slice(name.length + 1);
}

// A peer whose YEN.app prints a fixed listing, for the exec plan step.
function peerApp(script: string) {
	const app = join(root, `peer-${run}`, "YEN.app");
	const bin = join(app, "Contents/Resources/bin");
	mkdirSync(bin, { recursive: true });
	writeFileSync(join(bin, "yen"), `#!/bin/bash\n${script}\n`);
	chmodSync(join(bin, "yen"), 0o755);
	return app;
}

describe("yen sessions --host: the ssh command", () => {
	test("list runs a fixed remote command after --, with keepalives and BatchMode", () => {
		plan(["1 0"], { 1: `${header}\n` });
		const result = sessions(["list", "--host", "dev@mini.example.ts.net"]);
		expect(result.status, result.stderr).toBe(0);
		const argv = firstCall();
		const dashes = argv.indexOf("--");
		expect(argv.slice(dashes + 1, dashes + 2)).toEqual([
			"dev@mini.example.ts.net",
		]);
		expect(argv).toHaveLength(dashes + 3);
		const remote = argv[dashes + 2] ?? "";
		expect(remote).toStartWith("exec /bin/sh -c '");
		expect(remote).toEndWith("' yen-remote list --porcelain");
		expect(remote).toContain("/Applications/YEN.app");
		expect(remote).toContain('"$HOME/Applications/YEN.app"');
		expect(remote).toContain("exit 127");
		expect(option(argv, "BatchMode")).toBe("yes");
		expect(option(argv, "ConnectTimeout")).toMatch(/^\d+$/);
		expect(option(argv, "ServerAliveInterval")).toMatch(/^\d+$/);
		expect(option(argv, "ServerAliveCountMax")).toMatch(/^\d+$/);
		expect(option(argv, "ForwardAgent")).toBe("no");
		expect(argv.slice(0, dashes)).toContain("-T");
		// YEN never weakens host key checking.
		for (const weakened of [
			"StrictHostKeyChecking",
			"UserKnownHostsFile",
			"GlobalKnownHostsFile",
		]) {
			expect(option(argv, weakened)).toBeUndefined();
		}
	});

	test("attach asks for a tty, marks the connection, and is not BatchMode", () => {
		plan(["1 0"]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status, result.stderr).toBe(0);
		const argv = firstCall();
		const dashes = argv.indexOf("--");
		expect(argv[dashes + 1]).toBe("mini");
		expect(argv[dashes + 2]).toEndWith(` yen-remote attach ${sessionID}`);
		expect(argv.slice(0, dashes)).toContain("-t");
		expect(option(argv, "BatchMode")).toBeUndefined();
		expect(option(argv, "PermitLocalCommand")).toBe("yes");
		expect(option(argv, "LocalCommand")).toMatch(
			/^\/usr\/bin\/touch \/[A-Za-z0-9._/-]+$/,
		);
		expect(option(argv, "ServerAliveInterval")).toMatch(/^\d+$/);
	});

	test.each([
		"-oProxyCommand=touch /tmp/yen-pwned",
		"-oProxyCommand=sh",
		"-p",
		"mini -oProxyCommand=sh",
		"mini;id",
		"$(id)",
		"`id`",
		"mini\nother",
		"user@-oProxyCommand=sh",
		"-user@mini",
		"mini.",
		"mini..ts.net",
		"mini_host",
		"ünicode",
		"",
		"a".repeat(254),
	])("refuses the target %j before running ssh", (target) => {
		plan(["1 0"]);
		for (const args of [
			["list", "--host", target],
			["attach", "--host", target, sessionID],
		]) {
			const result = sessions(args);
			expect(result.status).toBe(EXIT.usage);
			expect(result.stderr).toContain("is not a host name or address");
		}
		expect(calls()).toEqual([]);
	});

	test.each([
		"mini",
		"mini.example.ts.net",
		"dev@mini",
		"dev.name@mini-2",
		"100.64.0.1",
		"fd7a:115c:a1e0::1",
	])("accepts the target %j", (target) => {
		plan(["1 0"], { 1: `${header}\n` });
		const result = sessions(["list", "--porcelain", "--host", target]);
		expect(result.status, result.stderr).toBe(0);
		expect(firstCall()).toContain(target);
	});

	test.each([
		"scratch",
		"../6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C",
		"6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C;id",
		"6F1D2C3B 0A4E 4F5A 9B8C 1D2E3F4A5B6C",
		"-oProxyCommand=sh",
	])("refuses the session id %j before running ssh", (id) => {
		plan(["1 0"]);
		const result = sessions(["attach", "--host", "mini", "--", id]);
		expect(result.status).toBe(EXIT.usage);
		expect(calls()).toEqual([]);
	});

	test("kill takes no --host", () => {
		plan(["1 0"]);
		const result = sessions(["kill", "--host", "mini", sessionID]);
		expect(result.status).toBe(EXIT.usage);
		expect(calls()).toEqual([]);
	});
});

describe("yen sessions --host: failure classes", () => {
	test.each([
		["Host key verification failed.", EXIT.firstConnection],
		["dev@mini: Permission denied (publickey).", EXIT.firstConnection],
		["ssh: connect to host mini port 22: Connection refused", EXIT.unreachable],
		[
			"ssh: connect to host mini port 22: Operation timed out",
			EXIT.unreachable,
		],
		[
			"ssh: Could not resolve hostname mini: nodename nor servname provided, or not known",
			EXIT.unreachable,
		],
		[
			"Host key for mini has changed and you have requested strict checking.",
			EXIT.hostKeyChanged,
		],
	])("ssh failing with %j exits %d", (message, code) => {
		plan([`0 255 ${message}`]);
		const listed = sessions(["list", "--host", "mini"]);
		expect(listed.status).toBe(code);
		expect(listed.stderr).toContain(message);
		// The same failure on a first attach is reported once, not retried.
		writeFileSync(join(sshDir, "count"), "0");
		writeFileSync(join(sshDir, "plan"), `0 255 ${message}\n`);
		const attached = sessions(["attach", "--host", "mini", sessionID]);
		expect(attached.status).toBe(code);
		expect(attached.stderr).not.toContain("reconnecting");
		expect(calls()).toHaveLength(1);
	});

	test("a peer without YEN exits 12", () => {
		plan(["1 127"]);
		const listed = sessions(["list", "--host", "mini"]);
		expect(listed.status).toBe(EXIT.notInstalled);
		expect(listed.stderr).toContain("YEN is not installed on mini");
	});

	test("a peer whose YEN predates --porcelain exits 13", () => {
		plan(["1 2 yen sessions: list takes no arguments"]);
		const listed = sessions(["list", "--host", "mini"]);
		expect(listed.status).toBe(EXIT.tooOld);
		expect(listed.stderr).toContain("update YEN there");
		expect(listed.stdout).toBe("");
	});

	test("a peer speaking another porcelain version exits 13", () => {
		plan(["1 0"], { 1: `yen-sessions\t2\n${sessionID}\tdetached\t1\t/x\n` });
		expect(sessions(["list", "--host", "mini"]).status).toBe(EXIT.tooOld);
	});

	test("attaching to a session the peer does not have exits 14", () => {
		plan(["1 1"]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status).toBe(EXIT.noSession);
		expect(result.stderr).toContain(`no session ${sessionID} on mini`);
	});
});

describe("yen sessions --host: listing", () => {
	test("passes well-formed rows through and drops the rest", () => {
		const other = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
		plan(["1 0"], {
			1: [
				header,
				`${sessionID}\tdetached\t1795380150\t/Users/dev/project`,
				`${other}\tattached\t-\t/Users/dev/\u001b]0;pwned\u0007x\tfuture-field`,
				"not-a-uuid\tdetached\t1\t/x",
				`${sessionID}\trunning\t1\t/x`,
				`${sessionID}\tdetached\tsoon\t/x`,
				"",
			].join("\n"),
		});
		const result = sessions(["list", "--porcelain", "--host", "mini"]);
		expect(result.status).toBe(1);
		expect(result.stderr).toContain("mini reported a listing error");
		expect(result.stdout).toBe(
			[
				header,
				`${sessionID}\tdetached\t1795380150\t/Users/dev/project`,
				`${other}\tattached\t-\t/Users/dev/?]0;pwned?x`,
				"",
			].join("\n"),
		);
	});

	test("renders the human table with remote paths kept absolute", () => {
		plan(["1 0"], {
			1: `${header}\n${sessionID}\tdetached\t-\t${process.env.HOME}/project\n`,
		});
		const result = sessions(["list", "--host", "mini"]);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toMatch(
			new RegExp(
				`^${sessionID}\\s+detached\\s+-\\s+${process.env.HOME}/project$`,
				"m",
			),
		);
	});

	test("an empty peer lists no sessions", () => {
		plan(["1 0"], { 1: `${header}\n` });
		const result = sessions(["list", "--host", "mini"]);
		expect(result.status).toBe(0);
		expect(result.stdout.trim()).toBe("No persistent sessions.");
	});

	test.each(["/bin/zsh", "/bin/bash", "/bin/sh"])(
		"the remote command finds the peer's YEN from the login shell %s",
		(shell) => {
			const app = peerApp(
				`[[ "$*" == "sessions list --porcelain" ]] || exit 9\n[[ -z "\${YEN_LIB:-}" ]] || exit 8\nprintf 'yen-sessions\\t1\\n${sessionID}\\tdetached\\t-\\t/Users/dev\\n'`,
			);
			plan(["1 exec"]);
			const result = sessions(["list", "--porcelain", "--host", "mini"], {
				YEN_REMOTE_APP: app,
				FAKE_SSH_LOGIN_SHELL: shell,
				FAKE_SSH_REMOTE_YEN_LIB: "/Users/dev/stale/lib",
			});
			expect(result.status, result.stderr).toBe(0);
			expect(result.stdout).toBe(
				`${header}\n${sessionID}\tdetached\t-\t/Users/dev\n`,
			);

			plan(["1 exec"]);
			writeFileSync(join(sshDir, "count"), "0");
			const missing = sessions(["list", "--host", "mini"], {
				YEN_REMOTE_APP: join(root, "absent", "YEN.app"),
				FAKE_SSH_LOGIN_SHELL: shell,
			});
			expect(missing.status).toBe(EXIT.notInstalled);
		},
	);
});

describe("yen sessions attach --host: reconnect", () => {
	test("reconnects after a dropped link until the remote exits normally", () => {
		plan([
			"1 255 Connection to mini closed by remote host.",
			"0 255 ssh: connect to host mini port 22: Connection refused",
			"1 255 Timeout, server mini not responding.",
			"1 0",
		]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status, result.stderr).toBe(0);
		expect(calls()).toHaveLength(4);
		expect(result.stderr.match(/reconnecting in \d+s/g)).toHaveLength(3);
		for (const argv of calls()) {
			expect(argv.at(-1)).toEndWith(` yen-remote attach ${sessionID}`);
		}
	});

	test("stops when the session is gone after a reconnect", () => {
		plan(["1 255 Connection to mini closed by remote host.", "1 1"]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status).toBe(EXIT.noSession);
		expect(calls()).toHaveLength(2);
	});

	test("stops when the host key changes during a reconnect", () => {
		plan([
			"1 255 Connection to mini closed by remote host.",
			"0 255 Host key for mini has changed and you have requested strict checking.",
		]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status).toBe(EXIT.hostKeyChanged);
		expect(calls()).toHaveLength(2);
	});

	test("a first attempt that never connects is not retried", () => {
		plan([
			"0 255 ssh: connect to host mini port 22: Connection refused",
			"1 0",
		]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status).toBe(EXIT.unreachable);
		expect(result.stderr).toContain("cannot reach mini");
		expect(calls()).toHaveLength(1);
	});

	test("a normal remote exit ends attach without reconnecting", () => {
		plan(["1 0", "1 0"]);
		const result = sessions(["attach", "--host", "mini", sessionID]);
		expect(result.status).toBe(0);
		expect(result.stderr).not.toContain("reconnecting");
		expect(calls()).toHaveLength(1);
	});

	test("leaves no temporary directory behind", () => {
		const scratch = mkdtempSync(join(root, "tmp-"));
		plan(["1 255 Connection to mini closed by remote host.", "1 0"]);
		const result = sessions(["attach", "--host", "mini", sessionID], {
			TMPDIR: scratch,
		});
		expect(result.status).toBe(0);
		expect(existsSync(scratch) && readdirSync(scratch)).toEqual([]);
	});
});
