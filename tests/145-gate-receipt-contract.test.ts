import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	existsSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * The gate receipt contract.
 *
 * Between 2025-12 and 2026-08, 33 distinct shell files in this repo were patched
 * for the same defect: a gate reported success without having done its work. Each
 * fix closed one route and pinned it with a source-text guardrail. The discovery
 * rate did not fall -- it rose, because a source-text guardrail encodes the syntax
 * of the last incident and cannot fail on a new route to the same outcome.
 *
 * The root cause is that `exit 0` is unfalsifiable: it is produced identically by
 * "ran everything, found nothing" and by "ran nothing". So each fix could only add
 * a NEGATIVE marker for one skip route, which left the positive claim unstated and
 * manufactured the next inference-from-absence. That is literally how the trigger
 * happened: a SKIPPED suffix was added to 03-verify-components.sh, and the next day
 * its ABSENCE was read as proof the native slice had executed.
 *
 * These tests pin the mechanism that replaces that pattern, not the shape of any
 * one hole. They EXECUTE the library against fixtures rather than grepping it.
 */

const repoRoot = join(import.meta.dir, "..");
const receiptLib = join(repoRoot, "scripts/lib/gate-receipt.sh");
const rosterPath = join(repoRoot, "scripts/lib/gate-roster.txt");

function withTempGate(
	units: string | null,
	body: string,
	run: (result: ReturnType<typeof spawnSync>) => void,
) {
	const dir = mkdtempSync(join(tmpdir(), "yen-gate-receipt-"));
	try {
		const libDir = join(dir, "lib");
		const unitsDir = join(libDir, "units");
		spawnSync("mkdir", ["-p", unitsDir]);
		writeFileSync(
			join(libDir, "gate-receipt.sh"),
			readFileSync(receiptLib, "utf8"),
		);
		if (units !== null) {
			writeFileSync(join(unitsDir, "fixture.units"), units);
		}
		const script = join(dir, "gate.sh");
		writeFileSync(
			script,
			[
				"#!/bin/bash",
				"set -euo pipefail",
				`source "${join(libDir, "gate-receipt.sh")}"`,
				body,
			].join("\n"),
		);
		run(spawnSync("bash", [script], { encoding: "utf8" }));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

const out = (r: ReturnType<typeof spawnSync>) =>
	`${r.stdout ?? ""}${r.stderr ?? ""}`;

describe("gate receipt contract", () => {
	test("a gate with no unit declaration cannot run at all", () => {
		withTempGate(null, "gate_begin fixture\ngate_end 0", (r) => {
			expect(r.status).toBe(1);
			expect(out(r)).toContain("no unit declaration");
			expect(out(r)).not.toContain("result=PASS");
		});
	});

	test("an empty unit roster is a false green and is refused", () => {
		// The empty-scan-set shape, applied to the contract itself. An empty loop's
		// natural control flow is a pass, which is the worst outcome for a gate.
		withTempGate(
			"# nothing declared\n",
			"gate_begin fixture\ngate_end 0",
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("declares zero units");
				expect(out(r)).not.toContain("result=PASS");
			},
		);
	});

	test("a declared unit that records nothing fails the gate", () => {
		// This is the property no prior fix had: a NEW skip route that nobody
		// anticipated fails, because the unit goes unaccounted for. Enumerating
		// skips is open-ended; accounting for declared units is finite.
		withTempGate(
			"alpha\nbeta\n",
			'gate_begin fixture\ngate_unit_ran alpha "scanned=4"\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("without accounting for: beta");
				expect(out(r)).toContain("result=FAIL");
				expect(out(r)).not.toContain("result=PASS");
			},
		);
	});

	test("a unit cannot be recorded RAN with a zero measurement", () => {
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran alpha "scanned=0"\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("zero quantity");
			},
		);
	});

	test("a clean multi-field result with zero findings is still a pass", () => {
		// "entries=3 findings=0" means three things were examined and none were
		// bad. Rejecting any zero-valued field would ban the normal shape of a
		// passing scan.
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran alpha "entries=3 findings=0"\ngate_end 0',
			(r) => {
				expect(r.status).toBe(0);
				expect(out(r)).toContain("result=PASS");
			},
		);
	});

	test("a unit cannot be recorded RAN with no evidence at all", () => {
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran alpha ""\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("no evidence");
			},
		);
	});

	test("a skip must carry a reason", () => {
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_skipped alpha ""\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("SKIP with no reason");
			},
		);
	});

	test("an all-skipped gate is not a pass", () => {
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_skipped alpha "toolchain absent"\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("ran zero units");
				expect(out(r)).not.toContain("result=PASS");
			},
		);
	});

	test("a gate that dies before its summary cannot leave earlier ticks reading as a verdict", () => {
		// Replaces the three hand-copied completion sentinels. bash 3.2 + `set -u`
		// lets an EXIT trap swallow a fatal abort, so a gate could exit 0 having
		// verified nothing; 11 scripts still carry that shape today.
		withTempGate(
			"alpha\n",
			[
				"gate_begin fixture",
				'echo "  ✓ everything looks fine"',
				"false  # a set -e fatal, mid-gate",
				'gate_unit_ran alpha "scanned=1"',
				"gate_end 0",
			].join("\n"),
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("aborted before emitting a RECEIPT");
				expect(out(r)).not.toContain("RECEIPT gate=");
			},
		);
	});

	test("an undeclared unit id is refused, so the roster cannot drift from the code", () => {
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran gamma "scanned=1"\ngate_end 0',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("not declared");
			},
		);
	});

	test("the happy path emits every unit and puts the digest last", () => {
		withTempGate(
			"alpha\nbeta\n",
			[
				"gate_begin fixture",
				'gate_unit_ran alpha "scanned=12"',
				'gate_unit_skipped beta "go toolchain absent"',
				"gate_end 0",
			].join("\n"),
			(r) => {
				expect(r.status).toBe(0);
				const lines = out(r).trim().split("\n").filter(Boolean);
				expect(lines).toContain("RAN|alpha|scanned=12");
				expect(lines).toContain("SKIP|beta|go toolchain absent");
				// Digest LAST, so a truncated transcript is detectable: no RECEIPT
				// line means no pass, rather than a pass that scrolled off.
				expect(lines[lines.length - 1]).toBe(
					"RECEIPT gate=fixture ran=1 skipped=1 declared=2 result=PASS",
				);
			},
		);
	});

	test("a gate can preserve a non-1 failure exit code", () => {
		// 13-scan-artifact-fingerprints.sh distinguishes 2 (findings remain /
		// nothing scanned) from 1 (internal abort), and callers switch on it.
		// Collapsing them would silently change release-path error handling.
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran alpha "scanned=3"\ngate_end 1 2',
			(r) => {
				expect(r.status).toBe(2);
				expect(out(r)).toContain("result=FAIL");
			},
		);
	});

	test("an operator-disabled gate reports DISABLED, never PASS", () => {
		// A gate switched off by env is a legitimate all-skip, so it must not trip
		// the "ran zero units" rule -- but it must never render as a pass either.
		withTempGate(
			"alpha\nbeta\n",
			'gate_begin fixture\ngate_end_disabled "gate mode off"',
			(r) => {
				expect(r.status).toBe(0);
				expect(out(r)).toContain("result=DISABLED reason=gate mode off");
				expect(out(r)).not.toContain("result=PASS");
			},
		);
	});

	test("units are reported on the FAIL branch too, not just on green", () => {
		// Every gate on the roster used to build its notes into a $DETAILS buffer
		// printed only in the failure branch, so degraded-but-passing states were
		// destroyed exactly on the runs where nobody was looking.
		withTempGate(
			"alpha\n",
			'gate_begin fixture\ngate_unit_ran alpha "scanned=3"\ngate_end 1',
			(r) => {
				expect(r.status).toBe(1);
				expect(out(r)).toContain("RAN|alpha|scanned=3");
				expect(out(r)).toContain("result=FAIL");
			},
		);
	});
});

describe("gate roster", () => {
	const roster = readFileSync(rosterPath, "utf8")
		.split("\n")
		.map((l) => l.trim())
		.filter((l) => l.length > 0 && !l.startsWith("#"));

	test("the roster is non-empty", () => {
		// Fail closed on an empty roster: an empty loop below would otherwise
		// report every contract assertion as satisfied over zero gates.
		expect(roster.length).toBeGreaterThanOrEqual(2);
	});

	test("the roster reaches scripts/manual/", () => {
		// scripts/manual/ was outside this loop's reach because entries were
		// resolved as scripts/<entry>.sh with no directory component. That is how
		// 16-verify-applescript-if-needed ran on both the /update-yen vendor and release paths
		// while emitting no receipt at all.
		expect(roster.some((g) => g.startsWith("manual/"))).toBe(true);
	});

	for (const gate of roster) {
		describe(gate, () => {
			// An entry may name a subdirectory under scripts/. The gate NAME --
			// used in the RECEIPT line and the units filename -- is the basename.
			const scriptPath = join(repoRoot, "scripts", `${gate}.sh`);
			const gateName = gate.slice(gate.lastIndexOf("/") + 1);

			test("declares its units and emits a receipt naming itself", () => {
				expect(existsSync(scriptPath)).toBe(true);
				const script = readFileSync(scriptPath, "utf8");
				const declaresViaLib =
					script.includes("gate-receipt.sh") && script.includes("gate_begin");
				const declaresInline = script.includes(`RECEIPT gate=${gateName}`);
				expect(declaresViaLib || declaresInline).toBe(true);

				if (declaresViaLib) {
					const unitsPath = join(
						repoRoot,
						"scripts/lib/units",
						`${gateName}.units`,
					);
					expect(existsSync(unitsPath)).toBe(true);
					const declared = readFileSync(unitsPath, "utf8")
						.split("\n")
						.map((l) => l.trim())
						.filter((l) => l.length > 0 && !l.startsWith("#"));
					expect(declared.length).toBeGreaterThan(0);

					// Every id used in the script must be declared. The reverse
					// direction is enforced at runtime by gate_end.
					const used = new Set<string>(
						[...script.matchAll(/gate_unit_(?:ran|skipped)\s+([a-z0-9-]+)/g)]
							.map((m) => m[1])
							.filter((id): id is string => id !== undefined),
					);
					for (const id of used) {
						expect(declared).toContain(id);
					}
				}
			});

			test("carries no hand-rolled '(N checks)' summary", () => {
				// A constant rendered where a reader expects a measurement is worse
				// than no number: 03's "16 checks" counted increments in the source
				// text, all outside every guard, and a test defended the agreement
				// between that constant and the docs.
				const script = readFileSync(scriptPath, "utf8");
				const summaryLines = script
					.split("\n")
					.filter((l) => !l.trimStart().startsWith("#"))
					.filter((l) => /echo\s+"[^"]*\(\$[A-Z_]+ checks\)/.test(l));
				expect(summaryLines).toEqual([]);
			});
		});
	}
});

describe("gate 42 fails closed on a broken scan set", () => {
	test("a nonexistent sources dir cannot report clean", () => {
		// Reproduced live before the fix: three nonexistent path flags printed four
		// "OK ... clean" lines and exited 0, byte-identical to a real clean run.
		const r = spawnSync(
			"bash",
			[
				join(repoRoot, "scripts/42-lint-overlay-recurrence-gates.sh"),
				"--sources-dir",
				join(tmpdir(), "yen-definitely-not-a-real-sources-dir"),
			],
			{ encoding: "utf8" },
		);
		expect(r.status).toBe(1);
		expect(out(r)).toContain("Refusing to report clean over an empty scan set");
		expect(out(r)).not.toContain("result=PASS");
	});
});
