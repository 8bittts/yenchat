import { afterEach, expect, test } from "bun:test";
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

const roots: string[] = [];
afterEach(() => {
	for (const root of roots.splice(0))
		rmSync(root, { recursive: true, force: true });
});
function fixture() {
	const root = mkdtempSync(join(tmpdir(), "yen-native-fixtures-"));
	roots.push(root);
	const source = join(root, "source");
	const copy = join(root, "copy");
	mkdirSync(copy);
	for (const path of [
		"yen-terminal/ghostty/macos/Sources/Example.swift",
		"yen-terminal/ghostty/src/config/Config.zig",
		"_docs/12-commands.md",
		"_docs/13-desktop-features.md",
	]) {
		const full = join(source, path);
		mkdirSync(join(full, ".."), { recursive: true });
		writeFileSync(full, `source: ${path}\n`);
	}
	const run = (mode: string) =>
		spawnSync(
			"python3",
			["scripts/native/source-fixtures.py", mode, source, copy],
			{ encoding: "utf8" },
		);
	return { source, copy, run };
}

test("native source snapshots verify exact bytes and detect source or copied-file drift", () => {
	const { source, copy, run } = fixture();
	const prepared = run("prepare");
	expect(prepared.status, prepared.stderr).toBe(0);
	expect(prepared.stdout).toContain("files=4 result=PASS");
	expect(run("verify").status).toBe(0);
	const path = "_docs/12-commands.md";
	writeFileSync(join(copy, path), "tampered");
	expect(run("verify").status).toBe(1);
	writeFileSync(join(copy, path), readFileSync(join(source, path)));
	writeFileSync(join(source, path), "new source");
	expect(run("verify").status).toBe(1);
});

test("native source snapshots fail on an empty scan or missing required input", () => {
	const { source, run } = fixture();
	rmSync(join(source, "_docs/12-commands.md"));
	expect(run("prepare").status).toBe(1);
	writeFileSync(join(source, "_docs/12-commands.md"), "restored");
	rmSync(join(source, "yen-terminal/ghostty/macos/Sources/Example.swift"));
	expect(run("prepare").status).toBe(1);
});

test("the native gate prepares, forwards and verifies source inputs around execution", () => {
	const script = readFileSync("scripts/native/01-macos-smoke.sh", "utf8");
	const prepare = script.indexOf('source-fixtures.py" prepare');
	const execute = script.indexOf(
		'TEST_RUNNER_YEN_NATIVE_TEST_SOURCE_ROOT="$NATIVE_SOURCE_FIXTURES" xcodebuild',
	);
	const verify = script.indexOf('source-fixtures.py" verify');
	expect(prepare).toBeGreaterThan(0);
	expect(execute).toBeGreaterThan(prepare);
	expect(verify).toBeGreaterThan(execute);
});
