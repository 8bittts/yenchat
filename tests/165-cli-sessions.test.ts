import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";

// `yen sessions` against the real vendored zmx in a throwaway socket directory:
// it lists only pane (UUID) sessions, ends one with the build its record names,
// and refuses ids it cannot act on.

const repoRoot = join(import.meta.dir, "..");
const yen = join(repoRoot, "yen-cli/bin/yen");
const zmx = join(repoRoot, "yen-terminal/customizations/vendor/zmx/zmx");
const paneID = "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
const vendored = existsSync(zmx);

let socketDir = "";

function zmxRun(args: string[]) {
	return spawnSync(zmx, args, {
		encoding: "utf8",
		env: { ...process.env, ZMX_DIR: socketDir },
		timeout: 10_000,
	});
}

function sessions(args: string[]) {
	return spawnSync(yen, ["sessions", ...args], {
		encoding: "utf8",
		env: { ...process.env, YEN_SESSIONS_DIR: socketDir, YEN_LIB: "" },
		timeout: 15_000,
	});
}

beforeAll(() => {
	// A short absolute directory: a Unix socket path caps at 104 bytes.
	socketDir = mkdtempSync("/tmp/yst-");
});

afterAll(() => {
	if (vendored && socketDir) {
		for (const name of [paneID, "scratch"]) zmxRun(["kill", name]);
	}
	if (socketDir) rmSync(socketDir, { recursive: true, force: true });
});

describe("yen sessions", () => {
	test("the vendored zmx is present", () => {
		if (!vendored) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored zmx missing — run scripts/48-vendor-zmx.sh, or set YEN_ALLOW_MISSING_VENDOR_TREE=1 to acknowledge these checks did not run",
			).toBe("1");
		}
	});

	test.skipIf(!vendored)(
		"reports a listing failure for an unreadable session directory",
		() => {
			chmodSync(socketDir, 0);
			try {
				const result = sessions([]);
				expect(result.status).not.toBe(0);
				expect(result.stderr.trim()).not.toBe("");
				expect(result.stdout).not.toContain("No persistent sessions.");
			} finally {
				chmodSync(socketDir, 0o700);
			}
		},
	);

	test.skipIf(!vendored)(
		"discovers incompatible sessions alongside sessions without a build record",
		() => {
			const oldID = "DDDDDDDD-2222-3333-4444-555555555555";
			// The current client cannot speak to this socket. The recorded client
			// understands it and rejects a query that includes another build's socket.
			const listener = Bun.listen({
				unix: join(socketDir, oldID),
				socket: {
					data(socket) {
						socket.end();
					},
				},
			});
			const client = [
				"#!/bin/bash",
				"set -eu",
				'[[ "$1" == ls ]]',
				`[[ -S "$ZMX_DIR/${oldID}" ]]`,
				`[[ ! -S "$ZMX_DIR/${paneID}" ]]`,
				`printf 'name=%s\\tclients=0\\tcreated=1\\n' ${oldID}`,
			].join("\n");
			const digest = createHash("sha256")
				.update(client)
				.digest("hex")
				.slice(0, 16);
			mkdirSync(join(socketDir, "bin"), { recursive: true });
			const binary = join(socketDir, "bin", `zmx-${digest}`);
			writeFileSync(binary, client, { mode: 0o700 });
			writeFileSync(join(socketDir, `${oldID}.zmx`), binary);
			try {
				expect(zmxRun(["run", paneID, "-d", "sleep", "120"]).status).toBe(0);
				const result = sessions([]);
				expect(result.status, result.stderr).toBe(0);
				for (const id of [oldID, paneID]) {
					expect(
						result.stdout.match(new RegExp(`^${id}\\s+detached\\s`, "gm")),
					).toHaveLength(1);
				}
				chmodSync(binary, 0o600);
				const partial = sessions([]);
				expect(partial.status).not.toBe(0);
				expect(partial.stdout).toMatch(
					new RegExp(`^${oldID}\\s+unreachable\\s`, "m"),
				);
				expect(partial.stdout).toMatch(
					new RegExp(`^${paneID}\\s+detached\\s`, "m"),
				);
			} finally {
				listener.stop(true);
				zmxRun(["kill", paneID]);
			}
		},
		30_000,
	);

	test.skipIf(!vendored)(
		"prints a versioned tab-separated listing with --porcelain",
		async () => {
			expect(sessions(["list", "--porcelain"]).stdout).toBe(
				"yen-sessions\t1\n",
			);
			expect(zmxRun(["run", paneID, "-d", "sleep", "120"]).status).toBe(0);
			try {
				await Bun.sleep(300);
				const result = sessions(["list", "--porcelain"]);
				expect(result.status, result.stderr).toBe(0);
				const [header, ...rows] = result.stdout.trimEnd().split("\n");
				expect(header).toBe("yen-sessions\t1");
				expect(rows).toHaveLength(1);
				const [id, state, started, directory, ...rest] = (rows[0] ?? "").split(
					"\t",
				);
				expect([id, state, rest]).toEqual([paneID, "detached", []]);
				expect(started).toMatch(/^\d+$/);
				expect(Math.abs(Number(started) - Date.now() / 1000)).toBeLessThan(120);
				// An absolute path, never the ~ the table shows.
				expect(directory).toStartWith("/");
			} finally {
				zmxRun(["kill", paneID]);
			}
		},
		30_000,
	);

	test.skipIf(!vendored)(
		"removes a refused socket after its owning client confirms it is stale",
		() => {
			const socket = join(socketDir, "11111111-2222-3333-4444-555555555555");
			const bound = spawnSync("python3", [
				"-I",
				"-c",
				"import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()",
				socket,
			]);
			expect(bound.status).toBe(0);
			expect(existsSync(socket)).toBe(true);
			const result = sessions([]);
			expect(result.status).toBe(0);
			expect(result.stdout).toContain("unreachable");
			expect(existsSync(socket)).toBe(false);
		},
	);

	test.skipIf(!vendored)(
		"lists pane sessions, ends one, and refuses unusable ids",
		async () => {
			expect(sessions([]).stdout.trim()).toBe("No persistent sessions.");

			expect(zmxRun(["run", paneID, "-d", "sleep", "120"]).status).toBe(0);
			expect(zmxRun(["run", "scratch", "-d", "sleep", "120"]).status).toBe(0);
			// The record points at the build to use; here the vendored binary itself.
			writeFileSync(join(socketDir, `${paneID}.zmx`), `${zmx}\n`);
			writeFileSync(
				join(socketDir, `${paneID}.owner`),
				"com.yenchat.yen\n/Applications/YEN.app\n4001\n",
			);
			await Bun.sleep(500);

			const listed = sessions([]);
			expect(listed.status).toBe(0);
			expect(listed.stdout).toMatch(
				new RegExp(`^${paneID}\\s+detached\\s`, "m"),
			);
			// A session not named by a pane UUID is not YEN's to show.
			expect(listed.stdout).not.toContain("scratch");

			const bad = sessions(["kill", "scratch"]);
			expect(bad.status).toBe(2);
			expect(bad.stderr).toContain("is not a session id");

			const ended = sessions(["kill", paneID]);
			expect(ended.status, ended.stderr).toBe(0);
			expect(ended.stdout).toContain(`Ended session ${paneID}`);
			expect(existsSync(join(socketDir, `${paneID}.zmx`))).toBe(false);
			expect(existsSync(join(socketDir, `${paneID}.owner`))).toBe(false);
			expect(sessions([]).stdout.trim()).toBe("No persistent sessions.");

			const missing = sessions(["attach", paneID]);
			expect(missing.status).toBe(1);
			expect(missing.stderr).toContain(`no session ${paneID}`);
		},
		60_000,
	);
});
