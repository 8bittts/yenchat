import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";

// zmx v1.0.1 freed the caller-owned socket path with its post-fork C
// allocator when a session daemon shut down. Under ReleaseSafe that buffer
// came from a different allocator, so every ended session aborted with
// SIGABRT and left a crash report. scripts/48-vendor-zmx.sh carries upstream
// f5d604e; this ends real sessions of the vendored binary, through `zmx kill`
// and through a command that exits, and requires each daemon to exit 0 while
// a counter session stays up with the same shell.

const repoRoot = join(import.meta.dir, "..");
const zmx = join(repoRoot, "yen-terminal/customizations/vendor/zmx/zmx");
const probe = join(repoRoot, "scripts/manual/36-zmx-shutdown-probe.py");

describe("zmx session daemon shutdown", () => {
	test("every ended session daemon exits 0 and a running session survives", () => {
		if (!existsSync(zmx)) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored zmx missing — run scripts/48-vendor-zmx.sh, or set YEN_ALLOW_MISSING_VENDOR_TREE=1 to acknowledge this check did not run",
			).toBe("1");
			return;
		}
		// A short absolute directory: a Unix socket path caps at 104 bytes.
		const dir = mkdtempSync("/tmp/yzd-");
		try {
			// A distinct copy name keeps any crash report it leaves attributable.
			const copy = join(dir, "zmxshuttest");
			copyFileSync(zmx, copy);
			const result = spawnSync(
				"python3",
				["-I", probe, copy, join(dir, "s"), "2"],
				{
					encoding: "utf8",
					timeout: 150_000,
				},
			);
			const out = `${result.stdout}${result.stderr}`;
			expect(out.trim().split("\n").at(-1)).toBe(
				"SUMMARY daemons=3 ended=3 clean=3 aborted=0 unknown=0 counter_survived=True",
			);
			expect(result.status, out).toBe(0);
		} finally {
			// End any session a failed probe left running.
			const sessionEnv: NodeJS.ProcessEnv = {
				...process.env,
				ZMX_DIR: join(dir, "s"),
			};
			for (const key of Object.keys(sessionEnv)) {
				if (key.startsWith("ZMX_") && key !== "ZMX_DIR") {
					sessionEnv[key] = undefined;
				}
			}
			const copy = join(dir, "zmxshuttest");
			if (existsSync(copy)) {
				const names = spawnSync(copy, ["ls", "--short"], {
					encoding: "utf8",
					env: sessionEnv,
				});
				for (const name of (names.stdout ?? "").split("\n").filter(Boolean)) {
					spawnSync(copy, ["kill", name], { env: sessionEnv });
				}
			}
			rmSync(dir, { recursive: true, force: true });
		}
	}, 180_000);
});
