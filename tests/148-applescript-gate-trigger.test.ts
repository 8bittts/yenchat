import { describe, expect, test } from "bun:test";
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

/**
 * The AppleScript/workspace gate's trigger baseline.
 *
 * The gate decides whether to run scripts/manual/15-verify-applescript.sh. It
 * originally read only the working tree -- `git diff HEAD`, `git diff --cached`,
 * and untracked files -- so COMMITTING a change to a tripwire path disarmed the
 * tripwire meant to catch it. It then printed a checkmark and exited 0, and
 * because it emitted no receipt, the vendor VB-04 and release VF-01 evals scored
 * that skip as a pass.
 *
 * `zip-verify.md` mandates committing a vendor bump BEFORE starting /update-yen, so in
 * the documented order the gate could never fire for a vendor-introduced change.
 * Measured on 2c3a40580: the same TerminalViewContainer.swift edit triggered the
 * gate while dirty and reported "no changes detected" once committed.
 *
 * These tests drive the real script against a throwaway git repo, so they pin
 * the BEHAVIOR rather than the source text of the current implementation.
 */

const repoRoot = join(import.meta.dir, "..");
const TRIPWIRE =
	"yen-terminal/overlays/macos/Sources/Features/Terminal/TerminalViewContainer.swift";

const OVERLAY_TRIPWIRES = [
	"scripts/lib/overlay-phases/01-branding.sh",
	"scripts/lib/overlay-phases/02-renames.sh",
	"scripts/lib/overlay-phases/06-copy.sh",
	"scripts/lib/overlay-rename-preflight.sh",
	"scripts/lib/overlay-verification.sh",
];

function git(cwd: string, ...args: string[]) {
	const r = spawnSync("git", args, { cwd, encoding: "utf8" });
	if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${r.stderr}`);
	return r.stdout.trim();
}

/** A minimal repo carrying the gate, its library, its units, and the tripwire. */
function withFixture(run: (dir: string) => void) {
	const dir = mkdtempSync(join(tmpdir(), "yen-applescript-gate-"));
	try {
		for (const d of [
			"scripts/manual",
			"scripts/lib/units",
			join(TRIPWIRE, "..").replaceAll("\\", "/"),
			"yen-terminal",
		]) {
			mkdirSync(join(dir, d), { recursive: true });
		}

		for (const f of [
			"scripts/manual/16-verify-applescript-if-needed.sh",
			"scripts/lib/gate-receipt.sh",
			"scripts/lib/units/16-verify-applescript-if-needed.units",
		]) {
			writeFileSync(join(dir, f), readFileSync(join(repoRoot, f), "utf8"));
		}

		// Stub the real verifier: it launches an app bundle, which no test may do.
		const stub = join(dir, "scripts/manual/15-verify-applescript.sh");
		writeFileSync(stub, "#!/bin/bash\necho 'STUB_VERIFIER_RAN'\nexit 0\n");
		spawnSync("chmod", ["+x", stub]);

		// The other declared tripwire paths must exist and be tracked, or the
		// gate's own path list is a dead letter.
		for (const p of [
			"yen-terminal/overlays/macos/YEN.sdef",
			"yen-terminal/overlays/macos/Sources/Features/Settings/KeybindRegistry.swift",
			"scripts/04-verify-branding.sh",
			"yen-terminal/apply-overlays.sh",
			...OVERLAY_TRIPWIRES,
		]) {
			mkdirSync(join(dir, p, ".."), { recursive: true });
			writeFileSync(join(dir, p), "placeholder\n");
		}
		writeFileSync(join(dir, TRIPWIRE), "let original = 1\n");

		git(dir, "init", "-q");
		git(dir, "config", "user.email", "t@example.com");
		git(dir, "config", "user.name", "t");
		git(dir, "add", "-A");
		git(dir, "commit", "-q", "-m", "base");

		run(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function runGate(dir: string) {
	return spawnSync(
		"bash",
		[join(dir, "scripts/manual/16-verify-applescript-if-needed.sh")],
		{ cwd: dir, encoding: "utf8" },
	);
}

function stamp(dir: string, sha: string) {
	writeFileSync(
		join(dir, "yen-terminal/.applescript-verified"),
		`verified_commit=${sha}\n`,
	);
}

describe("AppleScript gate trigger baseline", () => {
	test.each(OVERLAY_TRIPWIRES)(
		"extracted wiring triggers verification: %s",
		(path) => {
			withFixture((dir) => {
				stamp(dir, git(dir, "rev-parse", "HEAD"));
				writeFileSync(join(dir, path), "changed phase wiring\n");
				const result = runGate(dir);
				expect(result.stdout).toContain("STUB_VERIFIER_RAN");
				expect(result.status).toBe(0);
			});
		},
	);

	test("a COMMITTED change to a tripwire path still triggers the verifier", () => {
		withFixture((dir) => {
			const base = git(dir, "rev-parse", "HEAD");
			stamp(dir, base);

			// Edit and COMMIT -- the exact move that used to disarm the gate.
			writeFileSync(join(dir, TRIPWIRE), "let changed = 2\n");
			git(dir, "add", "-A");
			git(dir, "commit", "-q", "-m", "change tripwire");

			const r = runGate(dir);
			expect(r.stdout).toContain("STUB_VERIFIER_RAN");
			expect(r.stdout).toContain(TRIPWIRE);
			expect(r.status).toBe(0);
		});
	});

	test("an uncommitted change still triggers, as it always did", () => {
		withFixture((dir) => {
			stamp(dir, git(dir, "rev-parse", "HEAD"));
			writeFileSync(join(dir, TRIPWIRE), "let dirty = 3\n");

			const r = runGate(dir);
			expect(r.stdout).toContain("STUB_VERIFIER_RAN");
			expect(r.status).toBe(0);
		});
	});

	test("a missing verified stamp runs the verifier instead of reporting clean", () => {
		withFixture((dir) => {
			// No stamp is written: the committed range cannot be examined at all.
			// An unexamined gate is not a clean one.
			const r = runGate(dir);
			expect(r.stdout).toContain("STUB_VERIFIER_RAN");
			expect(r.status).toBe(0);
		});
	});

	test("a stamp naming an unresolvable commit fails closed", () => {
		withFixture((dir) => {
			stamp(dir, "0".repeat(40));
			const r = runGate(dir);
			expect(r.stdout).toContain("STUB_VERIFIER_RAN");
			expect(r.status).toBe(0);
		});
	});

	test("a genuinely unchanged tree skips, and SAYS it skipped in the receipt", () => {
		withFixture((dir) => {
			stamp(dir, git(dir, "rev-parse", "HEAD"));
			const r = runGate(dir);

			expect(r.stdout).not.toContain("STUB_VERIFIER_RAN");
			// The whole point: a skip must be distinguishable from a pass by a
			// POSITIVE field, not by the absence of an error.
			expect(r.stdout).toContain("SKIP|verifier|");
			expect(r.stdout).toMatch(
				/RECEIPT gate=16-verify-applescript-if-needed ran=1 skipped=1 declared=2 result=PASS/,
			);
			expect(r.status).toBe(0);
		});
	});

	test("a passing run on a clean tree advances the stamp to HEAD", () => {
		withFixture((dir) => {
			const base = git(dir, "rev-parse", "HEAD");
			stamp(dir, base);
			writeFileSync(join(dir, TRIPWIRE), "let changed = 4\n");
			git(dir, "add", "-A");
			git(dir, "commit", "-q", "-m", "change tripwire");
			const head = git(dir, "rev-parse", "HEAD");

			expect(runGate(dir).stdout).toContain("STUB_VERIFIER_RAN");
			const written = readFileSync(
				join(dir, "yen-terminal/.applescript-verified"),
				"utf8",
			);
			expect(written).toContain(`verified_commit=${head}`);

			// Re-running now skips, because the range it covers is empty.
			expect(runGate(dir).stdout).toContain("SKIP|verifier|");
		});
	});

	test("a dirty verification does NOT advance the stamp", () => {
		withFixture((dir) => {
			const base = git(dir, "rev-parse", "HEAD");
			stamp(dir, base);
			writeFileSync(join(dir, TRIPWIRE), "let dirty = 5\n");

			const r = runGate(dir);
			expect(r.stdout).toContain("STUB_VERIFIER_RAN");
			expect(r.stdout).toContain("Stamp not advanced");
			// Stamping HEAD here would claim coverage for content no commit holds.
			expect(
				readFileSync(join(dir, "yen-terminal/.applescript-verified"), "utf8"),
			).toContain(`verified_commit=${base}`);
		});
	});

	test("a failing verifier fails the gate", () => {
		withFixture((dir) => {
			stamp(dir, git(dir, "rev-parse", "HEAD"));
			writeFileSync(
				join(dir, "scripts/manual/15-verify-applescript.sh"),
				"#!/bin/bash\necho 'STUB_VERIFIER_RAN'\nexit 3\n",
			);
			writeFileSync(join(dir, TRIPWIRE), "let dirty = 6\n");

			const r = runGate(dir);
			expect(r.status).toBe(3);
			expect(r.stdout).toContain("result=FAIL");
		});
	});
});
