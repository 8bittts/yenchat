import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const LINTER = join(repoRoot, "scripts", "41-lint-swift-view-modifiers.sh");

function runLinter(scanDir?: string) {
	const args = [LINTER];
	if (scanDir) args.push(scanDir);
	return spawnSync("bash", args, { cwd: repoRoot, encoding: "utf8" });
}

function withFixture(file: string, contents: string): () => string {
	const dir = mkdtempSync(join(tmpdir(), "yen-view-modifier-lint-"));
	mkdirSync(join(dir, "sub"), { recursive: true });
	writeFileSync(join(dir, "sub", file), contents);
	return () => dir;
}

// A scan of every overlay source takes under a second on an idle machine and
// 5.4 seconds under CPU and disk load, which is past Bun's 5-second default.
// The limit stays finite, so a linter that hangs still fails.
const REAL_SCAN_TIMEOUT_MS = 30_000;

describe("SwiftUI bare-modifier lint (scripts/41-lint-swift-view-modifiers.sh)", () => {
	test(
		"real overlay Sources are clean (regression guard for the sidebar crash)",
		() => {
			const result = runLinter();
			expect(result.status).toBe(0);
			expect(result.stdout).toContain("clean");
		},
		REAL_SCAN_TIMEOUT_MS,
	);

	test(
		"real scan reports a non-trivial scanned-file count (no silent scope collapse)",
		() => {
			const result = runLinter();
			expect(result.status).toBe(0);
			const scanned = result.stdout.match(
				/scanned (\d+) SwiftUI of (\d+) Swift/,
			);
			expect(scanned).not.toBeNull();
			// Without this, the linter reported an identical "clean" whether it
			// scanned every overlay source or none of them.
			expect(Number(scanned?.[1])).toBeGreaterThanOrEqual(40);
			expect(Number(scanned?.[2])).toBeGreaterThanOrEqual(Number(scanned?.[1]));
		},
		REAL_SCAN_TIMEOUT_MS,
	);

	test("fails closed on an empty scan set instead of reporting clean", () => {
		const dir = mkdtempSync(join(tmpdir(), "yen-view-modifier-lint-empty-"));
		try {
			const result = runLinter(dir);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("empty scan set");
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	test("scans SwiftUI files whose import is indented or attributed", () => {
		// ReviewUtilityWindow.swift imports SwiftUI indented inside `#if os(macOS)`
		// and was silently skipped by the old `^import SwiftUI` anchor.
		const getDir = withFixture(
			"Nested.swift",
			[
				"#if os(macOS)",
				"    import SwiftUI",
				"#endif",
				"struct Nested: View {",
				"    var body: some View {",
				"        Circle()",
				"            .fill(.red)",
				"            rotationEffect(.degrees(-45))",
				"    }",
				"}",
				"",
			].join("\n"),
		);
		const dir = getDir();
		try {
			const result = runLinter(dir);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("rotationEffect(.degrees(-45))");
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	test("catches a modifier missing its leading dot (the exact bug class)", () => {
		const getDir = withFixture(
			"Swatch.swift",
			[
				"import SwiftUI",
				"struct Swatch: View {",
				"    var body: some View {",
				"        Circle()",
				"            .fill(.red)",
				"            .frame(width: 10, height: 10)",
				"            rotationEffect(.degrees(-45))",
				"    }",
				"}",
				"",
			].join("\n"),
		);
		const dir = getDir();
		try {
			const result = runLinter(dir);
			expect(result.status).toBe(1);
			expect(result.stdout).toContain("rotationEffect(.degrees(-45))");
			expect(result.stdout).toContain("Swatch.swift:7");
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	test("does not flag the correct dotted form (no false positive)", () => {
		const getDir = withFixture(
			"Swatch.swift",
			[
				"import SwiftUI",
				"struct Swatch: View {",
				"    var body: some View {",
				"        Circle()",
				"            .fill(.red)",
				"            .frame(width: 10, height: 10)",
				"            .rotationEffect(.degrees(-45))",
				"    }",
				"}",
				"",
			].join("\n"),
		);
		const dir = getDir();
		try {
			const result = runLinter(dir);
			expect(result.status).toBe(0);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	test("ignores non-SwiftUI files (free functions can share modifier names)", () => {
		const getDir = withFixture(
			"Geometry.swift",
			[
				"import Foundation",
				"func reframe() {",
				"    layout()",
				"    frame(of: window)",
				"}",
				"",
			].join("\n"),
		);
		const dir = getDir();
		try {
			const result = runLinter(dir);
			expect(result.status).toBe(0);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});
});
