import { afterAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";

// An app launched from inside a persistent pane inherits that pane's
// ZMX_SESSION, and PersistentSessionReaper passes its whole environment to
// list-pane-sessions.sh and `zmx kill`. zmx refuses an attach under it as
// nested; listing and ending must still work. Measured with the vendored zmx:
// `ls` marks the row of the session it names with a leading arrow instead of
// two spaces, which both readers skip (the CLI's `list_sessions` and
// `PersistentSessionReaper.parseList` both start at `name=`).

const repoRoot = join(import.meta.dir, "..");
const yen = join(repoRoot, "yen-cli/bin/yen");
const zmx = join(repoRoot, "yen-terminal/customizations/vendor/zmx/zmx");
const helper = join(repoRoot, "yen-cli/lib/list-pane-sessions.sh");
const vendored = existsSync(zmx);
const paneID = "0B1C2D3E-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
const otherID = "1C2D3E4F-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
// A short directory: a Unix socket path caps at 104 bytes.
const directory = mkdtempSync("/tmp/yzi-");

function environment(extra: Record<string, string>): NodeJS.ProcessEnv {
	const env: NodeJS.ProcessEnv = { ...process.env, YEN_LIB: "" };
	for (const key of Object.keys(env)) {
		if (key.startsWith("ZMX_")) delete env[key];
	}
	return { ...env, ...extra };
}

function zmxRun(args: string[], extra: Record<string, string> = {}) {
	return spawnSync(zmx, args, {
		encoding: "utf8",
		env: environment({ ZMX_DIR: directory, ZMX_DIR_MODE: "0700", ...extra }),
		timeout: 10_000,
	});
}

afterAll(() => {
	if (vendored) zmxRun(["kill", paneID]);
	rmSync(directory, { recursive: true, force: true });
});

describe("an inherited ZMX_SESSION", () => {
	test("the vendored zmx is present", () => {
		if (!vendored) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored zmx missing — run scripts/48-vendor-zmx.sh",
			).toBe("1");
		}
	});

	test.skipIf(!vendored)(
		"does not stop the reaper's listing or the CLI from listing and ending a session",
		async () => {
			expect(zmxRun(["run", paneID, "-d", "/bin/sleep", "120"]).status).toBe(0);
			await Bun.sleep(300);
			for (const inherited of [otherID, paneID]) {
				// What PersistentSessionReaper runs, with the app's environment.
				const listed = spawnSync("/bin/bash", [helper, directory, zmx], {
					encoding: "utf8",
					env: environment({
						ZMX_SESSION: inherited,
						ZMX_DIR: directory,
						ZMX_DIR_MODE: "0700",
					}),
					timeout: 15_000,
				});
				expect(listed.status, listed.stderr).toBe(0);
				const row = listed.stdout
					.split("\n")
					.find((line) => line.includes(`name=${paneID}\t`));
				expect(row, listed.stdout).toBeDefined();
				expect(row).toMatch(/\tclients=0(\t|$)/);
				expect(row).not.toContain("err=");

				const cli = spawnSync(yen, ["sessions", "list", "--porcelain"], {
					encoding: "utf8",
					env: environment({
						ZMX_SESSION: inherited,
						YEN_SESSIONS_DIR: directory,
					}),
					timeout: 15_000,
				});
				expect(cli.status, cli.stderr).toBe(0);
				expect(cli.stdout).toMatch(
					new RegExp(`^${paneID}\\tdetached\\t\\d+\\t/`, "m"),
				);
			}

			const ended = spawnSync(zmx, ["kill", paneID], {
				encoding: "utf8",
				env: environment({ ZMX_SESSION: otherID, ZMX_DIR: directory }),
				timeout: 10_000,
			});
			expect(ended.status, ended.stderr).toBe(0);
			for (let i = 0; i < 20 && existsSync(join(directory, paneID)); i++) {
				await Bun.sleep(100);
			}
			expect(existsSync(join(directory, paneID))).toBe(false);
		},
		30_000,
	);
});
