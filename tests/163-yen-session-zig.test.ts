import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

// The persistent-session command wrapper (src/termio/yen_session.zig) depends
// only on std, so its Zig unit tests run standalone here instead of waiting for
// a full engine build. Zig is a release prerequisite; a machine without it must
// acknowledge that this check did not run.

const source = join(
	import.meta.dir,
	"..",
	"yen-terminal/overlays/src/termio/yen_session.zig",
);

describe("yen_session.zig", () => {
	test("its Zig unit tests pass", () => {
		const zig = spawnSync("zig", ["version"], { encoding: "utf8" });
		if (zig.status !== 0) {
			expect(
				process.env.YEN_ALLOW_MISSING_ZIG,
				"zig not found — install the pinned toolchain, or set YEN_ALLOW_MISSING_ZIG=1 to acknowledge this check did not run",
			).toBe("1");
			return;
		}

		const result = spawnSync("zig", ["test", "-lc", source], {
			encoding: "utf8",
			timeout: 240_000,
		});
		const out = `${result.stdout}${result.stderr}`;
		expect(result.status, out).toBe(0);
		const passed = out.match(/All (\d+) tests passed/);
		expect(passed, out).not.toBeNull();
		expect(Number(passed?.[1])).toBeGreaterThanOrEqual(9);
	}, 300_000);
});
