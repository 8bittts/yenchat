import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();

const harnesses = [
	{
		label: "PDF",
		script: join(repoRoot, "scripts/37-soak-pdfthumb.sh"),
		manifest: join(repoRoot, "yen-pdfthumb/fixtures/manifest.csv"),
	},
	{
		label: "video",
		script: join(repoRoot, "scripts/39-soak-vidthumb.sh"),
		manifest: join(repoRoot, "yen-vidthumb/fixtures/manifest.csv"),
	},
] as const;

function runHarness(
	script: string,
	fixtureDirectory: string | undefined,
	environment: Record<string, string>,
) {
	const args = fixtureDirectory ? [script, fixtureDirectory] : [script];
	const result = spawnSync("/bin/bash", args, {
		cwd: repoRoot,
		encoding: "utf8",
		env: {
			...process.env,
			REBUILD: "0",
			...environment,
		},
		timeout: 30_000,
	});

	if (result.error) throw result.error;
	return {
		status: result.status,
		output: `${result.stdout ?? ""}${result.stderr ?? ""}`,
	};
}

describe("thumbnail soak fail-closed guardrails", () => {
	for (const harness of harnesses) {
		test(`${harness.label} rejects invalid and ambiguous round counts before running`, () => {
			for (const rounds of ["0", "08", "abc", "10000"]) {
				const result = runHarness(harness.script, undefined, {
					ROUNDS: rounds,
				});
				expect(result.status, `ROUNDS=${rounds}`).toBe(1);
				expect(result.output).toContain(
					"ROUNDS must be an integer from 1 through 9999 without leading zeros",
				);
				expect(result.output).not.toContain("Building fixture generator");
			}
		});

		test(`${harness.label} requires a successful renderer and actual PNG output`, () => {
			const fixtureRoot = mkdtempSync(
				join(tmpdir(), `yen-${harness.label.toLowerCase()}-soak-`),
			);
			const fixtureDirectory = join(fixtureRoot, "fixtures");
			const fakeRenderer = join(fixtureRoot, "copy-renderer.sh");
			const truncatedPNG = join(fixtureRoot, "truncated.png");
			mkdirSync(fixtureDirectory, { recursive: true });
			copyFileSync(harness.manifest, join(fixtureDirectory, "manifest.csv"));
			writeFileSync(
				truncatedPNG,
				readFileSync(join(repoRoot, "public/yen-logo-square-16.png")).subarray(
					0,
					24,
				),
			);
			writeFileSync(
				fakeRenderer,
				[
					"#!/bin/bash",
					"set -euo pipefail",
					'out="$2"',
					'mkdir -p "$(dirname "$out")"',
					'/bin/cp "$COPY_SOURCE" "$out"',
				].join("\n"),
				"utf8",
			);
			chmodSync(fakeRenderer, 0o755);

			try {
				const failedRenderer = runHarness(harness.script, fixtureDirectory, {
					NATIVE_BIN: "/usr/bin/false",
					ROUNDS: "1",
				});
				expect(failedRenderer.status).toBe(1);
				expect(failedRenderer.output).toContain("Render/result gate: FAIL");

				const mislabeledJPEG = runHarness(harness.script, fixtureDirectory, {
					COPY_SOURCE: join(repoRoot, "public/dmg-frame-base.jpg"),
					NATIVE_BIN: fakeRenderer,
					ROUNDS: "1",
				});
				expect(mislabeledJPEG.status).toBe(1);
				expect(mislabeledJPEG.output).toContain("Render/result gate: FAIL");

				const truncated = runHarness(harness.script, fixtureDirectory, {
					COPY_SOURCE: truncatedPNG,
					NATIVE_BIN: fakeRenderer,
					ROUNDS: "1",
				});
				expect(truncated.status).toBe(1);
				expect(truncated.output).toContain("Render/result gate: FAIL");

				const validPNG = runHarness(harness.script, fixtureDirectory, {
					COPY_SOURCE: join(repoRoot, "public/yen-logo-square-16.png"),
					MEMORY_DRIFT_MAX_PCT: "100000",
					NATIVE_BIN: fakeRenderer,
					P95_TARGET_MS: "10000",
					ROUNDS: "1",
				});
				expect(validPNG.status).toBe(0);
				expect(validPNG.output).toContain("Render/result gate: PASS");
			} finally {
				rmSync(fixtureRoot, { recursive: true, force: true });
			}
		}, 60_000);
	}
});
