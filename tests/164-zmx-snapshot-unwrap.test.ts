import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";

// A persistent pane receives early output (the welcome banner) inside zmx's
// attach snapshot, written at the pane's narrow startup width. Unless the
// snapshot sends soft-wrapped rows unwrapped, the pane gets hard line breaks
// and cannot reflow them when it grows. scripts/48-vendor-zmx.sh patches zmx
// to unwrap; this runs the real vendored binary in a PTY and fails if a zmx
// bump undoes it.

const repoRoot = join(import.meta.dir, "..");
const zmx = join(repoRoot, "yen-terminal/customizations/vendor/zmx/zmx");
const probe = join(import.meta.dir, "fixtures/zmx-snapshot-wrap.py");

describe("zmx attach snapshot", () => {
	test("sends a soft-wrapped line unwrapped so the pane can reflow it", () => {
		if (!existsSync(zmx)) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored zmx missing — run scripts/48-vendor-zmx.sh, or set YEN_ALLOW_MISSING_VENDOR_TREE=1 to acknowledge this check did not run",
			).toBe("1");
			return;
		}
		// A short absolute directory: a Unix socket path caps at 104 bytes.
		const socketDir = mkdtempSync("/tmp/yzw-");
		try {
			const result = spawnSync("python3", ["-I", probe, zmx, socketDir], {
				encoding: "utf8",
				timeout: 30_000,
			});
			const out = `${result.stdout}${result.stderr}`;
			expect(result.status, out).toBe(0);
			expect(out.trim().split("\n").at(-1)).toBe("UNWRAPPED");
		} finally {
			rmSync(socketDir, { recursive: true, force: true });
		}
	}, 60_000);
});
