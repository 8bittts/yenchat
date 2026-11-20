import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Runs the real vendor_source_build() offline. A shell-function `curl` serves a
// local source tarball, the GitHub lookups are stubbed, and the build callback
// compiles a tiny program for arm64 and x86_64 whose bytes embed
// VENDOR_BUILD_INPUT_ID, so a changed input id really changes the output digest.

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
		"build_demo() {",
		'  local src="$1" tmp="$2" arch',
		"  for arch in arm64 x86_64; do",
		'    xcrun clang -arch "$arch" -DINPUT_ID="\\"${VENDOR_BUILD_INPUT_ID:-none}${BUILD_SALT:-}\\"" -o "$tmp/demo-$arch" "$src/main.c" >&2 || return 1',
		"  done",
		'  echo "$tmp/demo-arm64"; echo "$tmp/demo-x86_64"',
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

function baseline(): Record<string, string> {
	const text = readFileSync(join(root, "yen-terminal/.demo-baseline"), "utf8");
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
		expect(same.out).toContain("Already current (v1.0) and universal");

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
		rmSync(join(root, "yen-terminal/.demo-baseline"), { force: true });
		rmSync(join(root, "yen-terminal/customizations/vendor/demo"), {
			recursive: true,
			force: true,
		});
		mkdirSync(join(root, "yen-terminal/customizations/vendor/demo"), {
			recursive: true,
		});
		const first = runVendor({});
		expect(first.status).toBe(0);
		expect(baseline().build_input_id).toBeUndefined();

		const drifted = runVendor({ BUILD_SALT: "-drift" }, true);
		expect(drifted.status).not.toBe(0);
		expect(drifted.out).toContain("output digest mismatch vs baseline pin");
	});
});
