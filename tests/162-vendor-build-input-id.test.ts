import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Runs the real vendor_source_build() and vendor_binary() offline. A
// shell-function `curl` serves a local tarball, the GitHub lookups are stubbed,
// and the build callback compiles a tiny arm64 program whose bytes embed
// VENDOR_BUILD_INPUT_ID, so a changed input id really changes the output digest.
// YEN requires macOS 27 (Apple silicon only), so every vendored binary must
// come out arm64-only.

const helper = join(import.meta.dir, "..", "scripts/lib/vendor-binary.sh");
const hasClang =
	spawnSync("xcrun", ["--find", "clang"], { encoding: "utf8" }).status === 0;

let root = "";

beforeAll(() => {
	root = mkdtempSync(join(tmpdir(), "yen-build-input-id-"));
	mkdirSync(join(root, "scripts"), { recursive: true });
	mkdirSync(join(root, "yen-terminal/customizations/vendor/demo"), {
		recursive: true,
	});
	const src = join(root, "src-stage/demo-1.0");
	mkdirSync(src, { recursive: true });
	writeFileSync(
		join(src, "main.c"),
		[
			"#include <stdio.h>",
			"#ifndef INPUT_ID",
			'#define INPUT_ID "none"',
			"#endif",
			'int main(void) { puts("demo 1.0 " INPUT_ID); return 0; }',
			"",
		].join("\n"),
	);
	const tar = spawnSync(
		"tar",
		[
			"-czf",
			join(root, "demo.tar.gz"),
			"-C",
			join(root, "src-stage"),
			"demo-1.0",
		],
		{ encoding: "utf8" },
	);
	expect(tar.status).toBe(0);
});

afterAll(() => {
	if (root) rmSync(root, { recursive: true, force: true });
});

function runVendor(env: Record<string, string>, force = false) {
	const script = [
		`source ${JSON.stringify(helper)}`,
		'vendor_resolve_tag_commit() { echo "0123456789abcdef0123456789abcdef01234567"; }',
		'vendor_release_published_date() { echo "2026-01-01"; }',
		// Serve the fixture tarball for the source download; nothing else may reach the network.
		`curl() { local out=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; shift; fi; shift; done; cp ${JSON.stringify(join(root, "demo.tar.gz"))} "$out"; }`,
		// BUILD_ARCHS lets a test hand back a fat binary, as an upstream build
		// system that defaults to universal output would.
		"build_demo() {",
		'  local src="$1" tmp="$2" arch flags=""',
		'  for arch in ${BUILD_ARCHS:-arm64}; do flags="$flags -arch $arch"; done',
		'  xcrun clang $flags -DINPUT_ID="\\"${VENDOR_BUILD_INPUT_ID:-none}${BUILD_SALT:-}\\"" -o "$tmp/demo-built" "$src/main.c" >&2 || return 1',
		'  echo "$tmp/demo-built"',
		"}",
		`vendor_source_build demo owner/demo demo .demo-baseline demo build_demo ${force} ""`,
	].join("\n");
	const result = spawnSync(
		"/bin/bash",
		["-c", script, join(root, "scripts/fake-vendor.sh")],
		{
			encoding: "utf8",
			env: {
				NODE_ENV: "test",
				PATH: process.env.PATH ?? "/usr/bin:/bin",
				HOME: root,
				VENDOR_LATEST_TAG: "v1.0",
				...env,
			},
		},
	);
	return { status: result.status, out: `${result.stdout}${result.stderr}` };
}

function parseBaseline(path: string): Record<string, string> {
	const text = readFileSync(path, "utf8");
	return Object.fromEntries(
		text
			.split("\n")
			.filter((line) => line.includes("="))
			.map((line) => [
				line.slice(0, line.indexOf("=")),
				line.slice(line.indexOf("=") + 1),
			]),
	);
}

function baseline(): Record<string, string> {
	return parseBaseline(join(root, "yen-terminal/.demo-baseline"));
}

const demoBinary = () =>
	join(root, "yen-terminal/customizations/vendor/demo/demo");

function archs(path: string): string {
	return spawnSync("lipo", ["-archs", path], {
		encoding: "utf8",
	}).stdout.trim();
}

function sha256(path: string): string {
	return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function resetDemo() {
	rmSync(join(root, "yen-terminal/.demo-baseline"), { force: true });
	rmSync(join(root, "yen-terminal/customizations/vendor/demo"), {
		recursive: true,
		force: true,
	});
	mkdirSync(join(root, "yen-terminal/customizations/vendor/demo"), {
		recursive: true,
	});
}

describe.skipIf(!hasClang)("vendor_source_build build-input identity", () => {
	test("records the input id, revalidates it, and rebuilds with a new pin when it changes", () => {
		const first = runVendor({ VENDOR_BUILD_INPUT_ID: "engine-aaa" });
		expect(first.status).toBe(0);
		const pinA = baseline();
		expect(pinA.build_input_id).toBe("engine-aaa");
		expect(pinA.output_sha256).toMatch(/^[0-9a-f]{64}$/);

		const same = runVendor({ VENDOR_BUILD_INPUT_ID: "engine-aaa" });
		expect(same.status).toBe(0);
		expect(same.out).toContain(
			"Output digest revalidated against baseline pin",
		);
		expect(same.out).toContain("Already current (v1.0) and arm64-only");

		const changed = runVendor({ VENDOR_BUILD_INPUT_ID: "engine-bbb" });
		expect(changed.status).toBe(0);
		expect(changed.out).toContain(
			"Build inputs changed (engine-aaa -> engine-bbb)",
		);
		expect(changed.out).not.toContain("Integrity verification failed");
		const pinB = baseline();
		expect(pinB.build_input_id).toBe("engine-bbb");
		expect(pinB.output_sha256).not.toBe(pinA.output_sha256);
	});

	test("without an input id a changed output for the same tag still fails closed", () => {
		resetDemo();
		const first = runVendor({});
		expect(first.status).toBe(0);
		expect(baseline().build_input_id).toBeUndefined();

		const drifted = runVendor({ BUILD_SALT: "-drift" }, true);
		expect(drifted.status).not.toBe(0);
		expect(drifted.out).toContain("output digest mismatch vs baseline pin");
	});
	test("installs only the arm64 slice when the build hands back a fat binary", () => {
		resetDemo();
		const built = runVendor({ BUILD_ARCHS: "arm64 x86_64" });
		expect(built.status, built.out).toBe(0);
		expect(archs(demoBinary())).toBe("arm64");
		expect(baseline().architecture).toBe("arm64");
	});

	test("a baseline pinned for a universal binary does not fail the arm64 rebuild, and the old binary is not kept", () => {
		resetDemo();
		// The state every checkout is in when the arm64-only change lands: a
		// baseline that pinned a universal output, and that universal binary
		// installed at the same version.
		const universal = spawnSync(
			"xcrun",
			[
				"clang",
				"-arch",
				"arm64",
				"-arch",
				"x86_64",
				"-o",
				demoBinary(),
				join(root, "src-stage/demo-1.0/main.c"),
			],
			{ encoding: "utf8" },
		);
		expect(universal.status, universal.stderr).toBe(0);
		expect(archs(demoBinary())).toBe("x86_64 arm64");
		writeFileSync(
			join(root, "yen-terminal/customizations/vendor/demo/.version"),
			"v1.0\n",
		);
		const oldPin = sha256(demoBinary());
		writeFileSync(
			join(root, "yen-terminal/.demo-baseline"),
			[
				"# demo Baseline Tracking",
				"upstream_repo=https://github.com/owner/demo",
				"upstream_version=v1.0",
				"last_sync=2026-01-01",
				"architecture=universal (arm64 + x86_64)",
				`source_tarball_sha256=${sha256(join(root, "demo.tar.gz"))}`,
				`output_sha256=${oldPin}`,
				"provenance_verification=github-commit-bound-archive",
				"",
			].join("\n"),
		);

		const migrated = runVendor({});
		expect(migrated.status, migrated.out).toBe(0);
		expect(migrated.out).toContain("is not arm64-only. Rebuilding");
		expect(migrated.out).not.toContain("Integrity verification failed");
		expect(archs(demoBinary())).toBe("arm64");
		const pin = baseline();
		expect(pin.architecture).toBe("arm64");
		expect(pin.output_sha256).toBe(sha256(demoBinary()));
		expect(pin.output_sha256).not.toBe(oldPin);

		// Once the arm64 pin exists it binds: a changed output for the same
		// tag fails closed again.
		const drifted = runVendor({ BUILD_SALT: "-drift" }, true);
		expect(drifted.status).not.toBe(0);
		expect(drifted.out).toContain("output digest mismatch vs baseline pin");
	});
});

describe.skipIf(!hasClang)("vendor_binary arm64 install", () => {
	// A release asset holding `tool` (and a `tool-helper` companion), built
	// with the given architectures and served by the `curl` stub.
	function stageAsset(buildArchs: string[], salt = "") {
		const stage = join(root, "asset-stage");
		rmSync(stage, { recursive: true, force: true });
		mkdirSync(join(stage, "tool-1.0"), { recursive: true });
		for (const name of ["tool", "tool-helper"]) {
			const compile = spawnSync(
				"xcrun",
				[
					"clang",
					...buildArchs.flatMap((arch) => ["-arch", arch]),
					`-DINPUT_ID="${name}${salt}"`,
					"-o",
					join(stage, "tool-1.0", name),
					join(root, "src-stage/demo-1.0/main.c"),
				],
				{ encoding: "utf8" },
			);
			expect(compile.status, compile.stderr).toBe(0);
		}
		const tar = spawnSync(
			"tar",
			["-czf", join(root, "tool-asset.tar.gz"), "-C", stage, "tool-1.0"],
			{ encoding: "utf8" },
		);
		expect(tar.status).toBe(0);
	}

	function runBinaryVendor(force = false) {
		const asset = join(root, "tool-asset.tar.gz");
		const script = [
			`source ${JSON.stringify(helper)}`,
			'vendor_release_published_date() { echo "2026-01-01"; }',
			// GitHub's provider-side digest for the asset, so provenance verifies.
			`vendor_release_asset_sha256() { shasum -a 256 ${JSON.stringify(asset)} | awk '{print $1}'; }`,
			// Serve the asset for the one `-o` download; every other request
			// (checksum file probes) is a 404, and nothing reaches the network.
			`curl() { local out=""; while [ $# -gt 0 ]; do if [ "$1" = "-o" ]; then out="$2"; shift; fi; shift; done; [ -n "$out" ] || return 22; cp ${JSON.stringify(asset)} "$out"; }`,
			`VENDOR_COMPANION_ARCHIVE_BINARY_NAME=tool-helper VENDOR_REQUIRE_COMPANION=true vendor_binary tool owner/tool tool tool .tool-baseline "tool-{VNUM}.tar.gz" ${force}`,
		].join("\n");
		const result = spawnSync(
			"/bin/bash",
			["-c", script, join(root, "scripts/fake-vendor.sh")],
			{
				encoding: "utf8",
				env: {
					NODE_ENV: "test",
					PATH: process.env.PATH ?? "/usr/bin:/bin",
					HOME: root,
					VENDOR_LATEST_TAG: "v1.0",
				},
			},
		);
		return { status: result.status, out: `${result.stdout}${result.stderr}` };
	}

	const toolDir = () => join(root, "yen-terminal/customizations/vendor/tool");
	const toolBaseline = () =>
		parseBaseline(join(root, "yen-terminal/.tool-baseline"));

	test("a universal upstream asset is thinned to arm64 for the binary and its companion", () => {
		stageAsset(["arm64", "x86_64"]);
		const installed = runBinaryVendor();
		expect(installed.status, installed.out).toBe(0);
		expect(installed.out).toContain(
			"GitHub release-asset digest verification passed",
		);
		expect(archs(join(toolDir(), "tool"))).toBe("arm64");
		expect(archs(join(toolDir(), "tool-helper"))).toBe("arm64");
		const pin = toolBaseline();
		expect(pin.architecture).toBe("arm64");
		expect(pin.provenance_verification).toBe("github-release-asset-digests");
		expect(pin.source_asset_arm64).toBe("tool-1.0.tar.gz");
		expect(pin.source_sha256_arm64).toBe(
			sha256(join(root, "tool-asset.tar.gz")),
		);
		expect(pin.output_sha256).toBe(sha256(join(toolDir(), "tool")));
		expect(pin.companion_output_sha256).toBe(
			sha256(join(toolDir(), "tool-helper")),
		);
		// The installed binary still runs after its other slice is dropped.
		const run = spawnSync(join(toolDir(), "tool"), { encoding: "utf8" });
		expect(run.status).toBe(0);

		const again = runBinaryVendor();
		expect(again.status, again.out).toBe(0);
		expect(again.out).toContain("Already current (v1.0) and arm64-only");
	});

	test("a baseline pinned for a universal binary does not fail the arm64 reinstall", () => {
		rmSync(toolDir(), { recursive: true, force: true });
		mkdirSync(toolDir(), { recursive: true });
		stageAsset(["arm64", "x86_64"]);
		// The universal binary an older baseline pinned, installed at the
		// same version.
		const stale = spawnSync(
			"tar",
			[
				"-xzf",
				join(root, "tool-asset.tar.gz"),
				"-C",
				toolDir(),
				"--strip-components",
				"1",
			],
			{ encoding: "utf8" },
		);
		expect(stale.status, stale.stderr).toBe(0);
		expect(archs(join(toolDir(), "tool"))).toBe("x86_64 arm64");
		writeFileSync(join(toolDir(), ".version"), "v1.0\n");
		const oldPin = sha256(join(toolDir(), "tool"));
		writeFileSync(
			join(root, "yen-terminal/.tool-baseline"),
			[
				"# tool Baseline Tracking",
				"upstream_version=v1.0",
				"last_sync=2026-01-01",
				"architecture=universal (arm64 + x86_64)",
				`output_sha256=${oldPin}`,
				`companion_output_sha256=${sha256(join(toolDir(), "tool-helper"))}`,
				"",
			].join("\n"),
		);

		const migrated = runBinaryVendor();
		expect(migrated.status, migrated.out).toBe(0);
		expect(migrated.out).toContain("is not arm64-only. Reinstalling");
		expect(migrated.out).not.toContain("Integrity verification failed");
		expect(archs(join(toolDir(), "tool"))).toBe("arm64");
		expect(archs(join(toolDir(), "tool-helper"))).toBe("arm64");
		expect(toolBaseline().architecture).toBe("arm64");
		expect(toolBaseline().output_sha256).not.toBe(oldPin);
	});

	test("an asset with no arm64 slice fails before any baseline is written", () => {
		rmSync(toolDir(), { recursive: true, force: true });
		rmSync(join(root, "yen-terminal/.tool-baseline"), { force: true });
		stageAsset(["x86_64"]);
		const refused = runBinaryVendor();
		expect(refused.status).not.toBe(0);
		expect(refused.out).toContain("no arm64 slice in tool");
		expect(existsSync(join(root, "yen-terminal/.tool-baseline"))).toBe(false);
		expect(existsSync(join(toolDir(), ".version"))).toBe(false);
	});

	test("a different binary for the same pinned tag fails closed on reinstall", () => {
		rmSync(toolDir(), { recursive: true, force: true });
		rmSync(join(root, "yen-terminal/.tool-baseline"), { force: true });
		stageAsset(["arm64"]);
		expect(runBinaryVendor().status).toBe(0);

		stageAsset(["arm64"], "-swapped");
		const swapped = runBinaryVendor(true);
		expect(swapped.status).not.toBe(0);
		expect(swapped.out).toContain("output digest mismatch vs baseline pin");
	});
});
