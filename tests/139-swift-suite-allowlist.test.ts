import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

// The macOS test target compiles every Swift file under overlays/macos/Tests via a
// PBXFileSystemSynchronizedRootGroup, but the scripts that RUN tests name suites
// one at a time with `-only-testing:`. Nothing forced a new suite into those lists,
// so suites could be added, compile forever, and never execute — which is exactly
// how TerminalViewContainerTests sat red for weeks against an AGENTS.md
// surface. This gate makes every unlisted suite an explicit, reviewed decision.

const repoRoot = process.cwd();
const testsRoot = join(repoRoot, "yen-terminal/overlays/macos/Tests");
const smokeScript = join(repoRoot, "scripts/native/01-macos-smoke.sh");
const componentScript = join(repoRoot, "scripts/03-verify-components.sh");

// Suites deliberately excluded from every run list, each with a recorded reason.
// Adding a name here is a review decision, not a default — an unlisted suite that
// is not in this map fails the gate.
const DOCUMENTED_EXCLUSIONS: Record<string, string> = {
	WebPreviewRepresentableTests:
		"WKWebView-backed. In a whole-target run the WebKit networking process fails to start ('Could not signal service com.apple.WebKit.Networking: Operation not permitted') and a different test in the suite fails on each run. Passes in isolation; run it with -only-testing on its own when touching the browser surface.",
	BenchmarkTests:
		"Upstream-mirrored benchmark harness, declared .enabled(if: false). Nothing to execute.",
};

// Empty on purpose: every compiled suite is on a run list or in
// DOCUMENTED_EXCLUSIONS. The ratchet below still fails if a new suite
// appears without being listed. Do not put names back here.
const KNOWN_UNRUN: readonly string[] = [];

function swiftTestFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			out.push(...swiftTestFiles(full));
		} else if (entry.endsWith(".swift")) {
			out.push(full);
		}
	}
	return out;
}

/** Suite names declared with Swift Testing `struct X {` carrying @Test, or XCTest classes. */
function declaredSuites(): Set<string> {
	const suites = new Set<string>();
	for (const file of swiftTestFiles(testsRoot)) {
		const source = readFileSync(file, "utf8");
		// Only count types that actually hold tests.
		const hasSwiftTestingCases = /^\s*@Test\b/m.test(source);
		for (const m of source.matchAll(
			/^\s*(?:public\s+|internal\s+|final\s+)*(?:struct|class)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^{]*)?\{/gm,
		)) {
			const name = m[1];
			if (!name?.endsWith("Tests")) continue;
			const isXCTestCase = new RegExp(
				`(?:struct|class)\\s+${name}\\s*:[^{]*XCTestCase`,
			).test(source);
			if (isXCTestCase || hasSwiftTestingCases) suites.add(name);
		}
	}
	return suites;
}

function allowlistedSuites(): Set<string> {
	const names = new Set<string>();
	for (const script of [smokeScript, componentScript]) {
		const source = readFileSync(script, "utf8");
		for (const m of source.matchAll(
			/-only-testing:YENTests\/([A-Za-z0-9_]+)/g,
		)) {
			if (m[1]) names.add(m[1]);
		}
	}
	return names;
}

describe("Swift suite allowlist drift", () => {
	test("every compiled Swift suite is either in a run list or a documented exclusion", () => {
		const declared = declaredSuites();
		const allowlisted = allowlistedSuites();

		// Fail closed if either scan set collapses.
		expect(declared.size).toBeGreaterThan(50);
		expect(allowlisted.size).toBeGreaterThan(20);

		const unrun = [...declared]
			.filter((s) => !allowlisted.has(s))
			.filter((s) => !(s in DOCUMENTED_EXCLUSIONS))
			.sort();

		// Ratchet: the backlog is empty. A new unlisted suite is a failure, not
		// a new KNOWN_UNRUN entry. What must never happen again is silent GROWTH.
		const added = unrun.filter((s) => !KNOWN_UNRUN.includes(s));
		expect(
			added,
			`New Swift suite(s) that no script runs:\n  ${added.join("\n  ")}\n` +
				"Add each to a -only-testing list in scripts/native/01-macos-smoke.sh, or record a reason in DOCUMENTED_EXCLUSIONS.",
		).toEqual([]);

		// Shrinking the backlog must also shrink the baseline, or the list rots into
		// permission to stop caring.
		const stale = KNOWN_UNRUN.filter((s) => !unrun.includes(s));
		expect(
			stale,
			`These suites now run (or no longer exist) — remove them from KNOWN_UNRUN:\n  ${stale.join("\n  ")}`,
		).toEqual([]);
	});

	test("every allowlisted -only-testing target resolves to a real suite", () => {
		const declared = declaredSuites();
		const allowlisted = allowlistedSuites();

		// Same floors as the sibling test above, for the same reason. `dangling`
		// is a filter over `allowlisted`, so a collapsed scan set yields [] and
		// this assertion passes having compared nothing -- a gate against run
		// lists that name no real suite, itself reporting clean because it found
		// no run lists. A rewrite that breaks the -only-testing regex is exactly
		// how that collapse happens.
		expect(declared.size).toBeGreaterThan(50);
		expect(allowlisted.size).toBeGreaterThan(20);

		const dangling = [...allowlisted].filter((s) => !declared.has(s)).sort();
		expect(
			dangling,
			`-only-testing targets naming suites that do not exist: ${dangling.join(", ")}`,
		).toEqual([]);
	});

	test("documented exclusions stay honest", () => {
		const declared = declaredSuites();
		const allowlisted = allowlistedSuites();

		for (const [name, reason] of Object.entries(DOCUMENTED_EXCLUSIONS)) {
			// A stale exclusion is worse than none: it silently keeps a suite out of
			// the run lists long after the suite is gone or has been re-listed.
			expect(
				declared.has(name),
				`exclusion names a suite that no longer exists: ${name}`,
			).toBe(true);
			expect(
				allowlisted.has(name),
				`${name} is both allowlisted and excluded — drop the exclusion`,
			).toBe(false);
			expect(
				reason.length,
				`exclusion for ${name} needs a real reason`,
			).toBeGreaterThan(40);
		}
	});
});
