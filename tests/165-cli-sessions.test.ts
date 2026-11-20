import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
		"lists pane sessions, ends one, and refuses unusable ids",
		async () => {
			expect(sessions([]).stdout.trim()).toBe("No persistent sessions.");

			expect(zmxRun(["run", paneID, "-d", "sleep", "120"]).status).toBe(0);
			expect(zmxRun(["run", "scratch", "-d", "sleep", "120"]).status).toBe(0);
			// The record points at the build to use; here the vendored binary itself.
			writeFileSync(join(socketDir, `${paneID}.zmx`), `${zmx}\n`);
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
			expect(sessions([]).stdout.trim()).toBe("No persistent sessions.");

			const missing = sessions(["attach", paneID]);
			expect(missing.status).toBe(1);
			expect(missing.stderr).toContain(`no session ${paneID}`);
		},
		60_000,
	);
});
