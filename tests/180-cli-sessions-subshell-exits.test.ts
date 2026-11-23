import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import {
	cliEnvironment,
	header,
	RemoteHarness,
	repoRoot,
	sessionID,
} from "./fixtures/sessions-remote-harness";

// A function that exits inside `$(...)` ends only that subshell. These are the
// two such call sites in `yen sessions` that a user can reach: the remote
// command builder (remote_command, which refuses YEN_REMOTE_APP) and the local
// listing (list_sessions, which stops when zmx is missing). Each must still
// stop the CLI with its status, and ssh must never get an empty remote
// command, which it would treat as a request for the peer's login shell.

const root = mkdtempSync("/tmp/yse-");
const harness = new RemoteHarness(root);
afterAll(() => rmSync(root, { recursive: true, force: true }));
beforeEach(() => harness.next());

describe("yen sessions --host never hands ssh an empty command", () => {
	const cases: [string, string[]][] = [
		["list", ["list", "--porcelain", "--host", "mini"]],
		["attach", ["attach", "--host", "mini", sessionID]],
	];
	test.each(
		cases.flatMap(([name, args]) =>
			["", "/Users/dev/Applications/YEN.app", "relative/YEN.app", "/x;id"].map(
				(app) => [name, app, args] as const,
			),
		),
	)("%s with YEN_REMOTE_APP=%j", (_, app, args) => {
		harness.plan(["1 0"], { 1: `${header}\n` });
		const result = harness.sessions(args, app ? { YEN_REMOTE_APP: app } : {});
		const calls = harness.calls();
		for (const argv of calls) {
			expect(argv.at(-1)?.trim(), JSON.stringify(argv)).not.toBe("");
			expect(argv.at(-1)).toStartWith("exec /bin/sh -c '");
		}
		// A refused command builder stops before ssh, with the usage status.
		if (app.startsWith("/") && !app.includes(";")) {
			expect(calls).toHaveLength(1);
		} else if (app) {
			expect(result.status).toBe(2);
			expect(calls).toEqual([]);
		}
	});
});

describe("yen sessions list without zmx", () => {
	/// A copy of the CLI with no bundled or development zmx beside it.
	function cliWithoutZmx() {
		const copy = join(root, `cli-${Math.random().toString(16).slice(2, 8)}`);
		cpSync(join(repoRoot, "yen-cli"), join(copy, "yen-cli"), {
			recursive: true,
		});
		return join(copy, "yen-cli/bin/yen");
	}

	test.each([
		["--porcelain", `${header}\n`],
		["", ""],
	])(
		"list %s stops with status 1 and says why, without claiming there are none",
		(flag, stdout) => {
			const sessions = join(root, `zmx-${flag || "table"}`);
			mkdirSync(sessions);
			const result = spawnSync(
				cliWithoutZmx(),
				["sessions", "list", ...(flag ? [flag] : [])],
				{
					encoding: "utf8",
					env: cliEnvironment(harness.sshDir, { YEN_SESSIONS_DIR: sessions }),
					timeout: 15_000,
				},
			);
			expect(result.status).toBe(1);
			expect(result.stderr).toContain("zmx is not available; reinstall YEN.");
			expect(result.stdout).toBe(stdout);
			expect(result.stdout).not.toContain("No persistent sessions.");
		},
	);
});
