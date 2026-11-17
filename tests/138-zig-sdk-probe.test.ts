import { describe, expect, test } from "bun:test";
import { execFileSync, spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..");
const LIB = join(REPO, "scripts/lib/zig-sdk-workaround.sh");
const source = readFileSync(LIB, "utf8");

/**
 * The Zig SDK link probe exists to detect ONE thing: whether Zig can resolve
 * libSystem symbols against the current macOS SDK. It is a workaround trigger,
 * so a false positive silently activates a synthetic sysroot on machines that
 * do not need one.
 *
 * That is exactly what happened: the original probe called `std.posix.getenv`,
 * which Zig 0.16 removed. The probe stopped COMPILING, never reached the
 * linker, and every build reported "Zig SDK link probe FAILED". These tests
 * pin the properties that prevent the probe from rotting that way again.
 */
describe("zig sdk link probe", () => {
	test("probe source does not depend on the moving std API surface", () => {
		// A probe for a LINKER bug must not be able to fail at COMPILE time
		// because of std churn. Extracting the heredoc keeps this honest even
		// if the surrounding shell is refactored.
		const probe = source.match(
			/<< 'ZIG_SDK_PROBE'\n([\s\S]*?)\nZIG_SDK_PROBE/,
		)?.[1];
		expect(probe).toBeTruthy();
		expect(probe).not.toContain('@import("std")');
		expect(probe).not.toContain("std.");
		expect(probe).toContain('extern "c"');
	});

	test("probe program actually compiles, links, and runs under the local zig", () => {
		const zig = spawnSync("zig", ["version"], { encoding: "utf8" });
		if (zig.status !== 0) {
			// No zig on this machine — the probe is inert, nothing to assert.
			return;
		}
		const probe = source.match(
			/<< 'ZIG_SDK_PROBE'\n([\s\S]*?)\nZIG_SDK_PROBE/,
		)?.[1];
		const dir = mkdtempSync(join(tmpdir(), "yen-zig-probe-test-"));
		try {
			writeFileSync(join(dir, "probe.zig"), `${probe}\n`);
			// Mirrors the real invocation in setup_zig_sdk_workaround.
			execFileSync("zig", ["build-exe", "probe.zig", "-lc"], { cwd: dir });
			execFileSync(join(dir, "probe"), []);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	test("a passing probe is authoritative and short-circuits the tbd heuristic", () => {
		// Without this early return, a machine whose SDK lists only
		// arm64e-macos targets activates the workaround even though Zig
		// demonstrably links fine against it (Zig 0.16 + Xcode 26.4).
		expect(source).toContain('if [ "$_sdk_probe_result" = "pass" ]; then');
		expect(source).toMatch(
			/if \[ "\$_sdk_probe_result" = "pass" \]; then\s*\n\s*return 0/,
		);
	});

	test("only a real link failure activates the workaround", () => {
		// Compile errors must classify as inconclusive, not as `fail`.
		expect(source).toContain('_sdk_probe_result="inconclusive"');
		expect(source).toMatch(/undefined symbol\|symbol not found/);
		// The activation condition reads `fail`, never a generic non-zero exit.
		expect(source).toContain('[ "$_sdk_probe_result" = "fail" ]');
		expect(source).not.toContain("_sdk_probe_failed");
	});

	test("the shell library parses", () => {
		execFileSync("bash", ["-n", LIB]);
	});
});

/**
 * End-to-end classification, driven through a stub `zig` on PATH so each
 * outcome is exercised without needing a machine in that SDK state.
 */
describe("zig sdk probe classification", () => {
	const createSdkFixtures = (dir: string) => {
		const xcodeSdk = join(dir, "Xcode.sdk");
		const cltRoot = join(dir, "CommandLineTools");
		const cltSdk = join(cltRoot, "SDKs", "MacOSX.sdk");
		for (const [sdk, target] of [
			[xcodeSdk, "arm64e-macos"],
			[cltSdk, "arm64-macos"],
		] as const) {
			mkdirSync(join(sdk, "usr", "lib", "system"), { recursive: true });
			for (const name of ["libSystem.tbd", "system/libsystem_c.tbd"]) {
				writeFileSync(
					join(sdk, "usr", "lib", name),
					`targets: [ ${target} ]\n`,
				);
			}
		}
		const xcrun = join(dir, "xcrun");
		writeFileSync(
			xcrun,
			'#!/bin/bash\nprintf "%s\\n" "$YEN_TEST_XCODE_SDK"\n',
			{
				mode: 0o755,
			},
		);
		const library = join(dir, "zig-sdk-workaround.sh");
		// Replace only host paths; execute the real workaround with isolated SDKs.
		// A machine with only Xcode has no CLT SDK to satisfy the activation branch.
		writeFileSync(
			library,
			source
				.replaceAll("/usr/bin/xcrun", '"${YEN_TEST_XCRUN}"')
				.replaceAll(
					"/Library/Developer/CommandLineTools",
					'"${YEN_TEST_CLT_ROOT}"',
				),
		);
		return { library, xcrun, xcodeSdk, cltRoot };
	};

	const runWithStubZig = (stubBody: string) => {
		const dir = mkdtempSync(join(tmpdir(), "yen-zig-stub-"));
		try {
			const sdk = createSdkFixtures(dir);
			writeFileSync(join(dir, "zig"), `#!/bin/bash\n${stubBody}\n`, {
				mode: 0o755,
			});
			const res = spawnSync(
				"bash",
				[
					"-c",
					`set -e; source "${sdk.library}"; setup_zig_sdk_workaround; echo "ACTIVE=[$ZIG_SDK_WORKAROUND_ACTIVE]"`,
				],
				{
					cwd: REPO,
					encoding: "utf8",
					env: {
						...process.env,
						PATH: `${dir}:${process.env.PATH}`,
						TMPDIR: dir,
						YEN_SKIP_ZIG_SDK_WORKAROUND: "",
						YEN_TEST_XCRUN: sdk.xcrun,
						YEN_TEST_XCODE_SDK: sdk.xcodeSdk,
						YEN_TEST_CLT_ROOT: sdk.cltRoot,
					},
				},
			);
			expect(res.status).toBe(0);
			return `${res.stdout}${res.stderr}`;
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	};

	test("unresolved libSystem symbols classify as a link failure", () => {
		const out = runWithStubZig(
			'echo "error: undefined symbol: _malloc_size" >&2\nexit 1',
		);
		expect(out).toContain("Zig SDK link probe FAILED");
		expect(out).toContain("ACTIVE=[1]");
	});

	test("a compile error is inconclusive, never reported as a link failure", () => {
		// The regression: Zig 0.16 removed std.posix.getenv, the probe failed to
		// compile, and the build announced an SDK link failure that never happened.
		const out = runWithStubZig(
			'echo "probe.zig:2:5: error: no member named getenv" >&2\nexit 1',
		);
		expect(out).toContain("INCONCLUSIVE");
		expect(out).not.toContain("Zig SDK link probe FAILED");
	});

	test("a passing probe leaves PATH unmutated", () => {
		const out = runWithStubZig("exit 0");
		expect(out).toContain("Zig SDK link probe PASSED");
		expect(out).toContain("ACTIVE=[]");
		expect(out).not.toContain("Synthetic sysroot ready");
	});
});
