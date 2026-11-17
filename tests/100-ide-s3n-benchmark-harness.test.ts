import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	cpSync,
	existsSync,
	readFileSync,
	renameSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { ideCommandDiagnostics } from "./fixtures/ide-result";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

// Benchmark cases intentionally run the real fixture-backed CLI suites.
const test = (
	name: string,
	fn: () => void,
	options: { timeout?: number } = {},
) => bunTest(name, fn, { timeout: 30_000, ...options });

function runYen(args: string[], envOverrides: Record<string, string> = {}) {
	return runYenAt(yenBinPath, args, envOverrides);
}

function runYenAt(
	binPath: string,
	args: string[],
	envOverrides: Record<string, string> = {},
) {
	return spawnSync(binPath, args, {
		cwd: repoRoot,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

describe("IDE benchmark harness", () => {
	test("benchmark status reports missing evidence on a fresh state dir", () => {
		const stateDir = ideTemp("yen-ide-benchmark-status-");
		const env = { YEN_IDE_STATE_DIR: stateDir };

		const res = runYen(["ide", "benchmark", "status", "--format", "json"], env);
		expect(res.status, ideCommandDiagnostics(res)).toBe(0);

		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.latestAvailable).toBe(false);
		expect(payload.baselineAvailable).toBe(false);
		expect(payload.summary.overallStatus).toBe("missing");
	});

	test("benchmark run fails closed when baseline proof is missing", () => {
		const stateDir = ideTemp("yen-ide-benchmark-nobase-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_SLO_SEARCH_LATENCY_MS: "5000",
		};

		const res = runYen(
			[
				"ide",
				"benchmark",
				"run",
				"--suite",
				"search",
				"--samples",
				"1",
				"--format",
				"json",
			],
			env,
		);
		expect(res.status, ideCommandDiagnostics(res)).toBe(1);

		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.summary.overallStatus).toBe("fail");
		expect(payload.summary.reason).toContain(
			"No saved benchmark baseline exists yet",
		);
	});

	test(
		"benchmark run writes a fixture-backed baseline across all suites",
		() => {
			const stateDir = ideTemp("yen-ide-benchmark-baseline-");
			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_SLO_SEARCH_LATENCY_MS: "5000",
				YEN_IDE_SLO_LSP_START_MS: "5000",
				YEN_IDE_SLO_VERIFY_DURATION_MS: "5000",
				YEN_IDE_SLO_ORCHESTRATION_LATENCY_MS: "5000",
			};

			const res = runYen(
				[
					"ide",
					"benchmark",
					"run",
					"--suite",
					"all",
					"--samples",
					"1",
					"--write-baseline",
					"--format",
					"json",
				],
				env,
			);
			expect(res.status, ideCommandDiagnostics(res)).toBe(0);

			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			expect(payload.summary.baselineWritten).toBe(true);
			expect(payload.requestedSuites).toEqual([
				"search",
				"lsp",
				"verify",
				"orchestration",
			]);
			expect(payload.suites).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "search",
						status: "pass",
					}),
					expect.objectContaining({
						id: "lsp",
						coverage: expect.objectContaining({
							status: "placeholder",
						}),
					}),
					expect.objectContaining({
						id: "verify",
						execution: expect.objectContaining({
							status: "pass",
						}),
					}),
					expect.objectContaining({
						id: "orchestration",
						coverage: expect.objectContaining({
							status: "mock-adapters",
						}),
					}),
				]),
			);
		},
		{ timeout: 30_000 },
	);

	test(
		"benchmark comparison run records non-interference metrics after baseline exists",
		() => {
			const stateDir = ideTemp("yen-ide-benchmark-compare-");
			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_SLO_SEARCH_LATENCY_MS: "5000",
			};

			const baseline = runYen(
				[
					"ide",
					"benchmark",
					"run",
					"--suite",
					"search",
					"--samples",
					"1",
					"--write-baseline",
					"--format",
					"json",
				],
				env,
			);
			expect(baseline.status, ideCommandDiagnostics(baseline)).toBe(0);

			const res = runYen(
				[
					"ide",
					"benchmark",
					"run",
					"--suite",
					"search",
					"--samples",
					"1",
					"--format",
					"json",
				],
				env,
			);
			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			const suite = payload.suites[0];
			// A real timing comparison may regress under host load. Verify its
			// reported result and exit contract, while retaining the absolute SLO.
			expect(suite.execution.status).toBe("pass");
			expect(suite.guardrail.status).toBe("pass");
			expect(["pass", "warn", "fail"]).toContain(suite.comparison.status);
			expect(payload.summary.overallStatus).toBe(suite.comparison.status);
			expect(res.status, ideCommandDiagnostics(res)).toBe(
				suite.comparison.status === "fail" ? 1 : 0,
			);
			const recorded = JSON.parse(baseline.stdout).suites[0].measurement;
			expect(suite.comparison.baselineColdMs).toBe(recorded.coldMs);
			expect(suite.comparison.baselineWarmAvgMs).toBe(recorded.warmAvgMs);
			expect(payload.suites).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "search",
						guardrail: expect.objectContaining({
							metric: "search-latency-ms",
						}),
					}),
				]),
			);

			const sloLedger = readFileSync(
				join(stateDir, "non-interference-slo.tsv"),
				"utf8",
			);
			expect(sloLedger).toContain("search-latency-ms");
			expect(sloLedger).toContain("benchmark:search");
		},
		{ timeout: 30_000 },
	);

	test("benchmark failures do not emit fake pass samples into the non-interference ledger", () => {
		const tempDir = ideTemp("yen-ide-benchmark-fixture-missing-");
		const stateDir = ideTemp("yen-ide-benchmark-fixture-missing-state-");
		try {
			const resourcesDir = join(tempDir, "resources");
			cpSync(join(repoRoot, "yen-cli/bin"), join(resourcesDir, "bin"), {
				recursive: true,
			});
			cpSync(join(repoRoot, "yen-cli/lib"), join(resourcesDir, "lib"), {
				recursive: true,
			});
			cpSync(
				join(repoRoot, "yen-cli/commands"),
				join(resourcesDir, "commands"),
				{
					recursive: true,
				},
			);
			chmodSync(join(resourcesDir, "bin/yen"), 0o755);

			const res = runYenAt(
				join(resourcesDir, "bin/yen"),
				[
					"ide",
					"benchmark",
					"run",
					"--suite",
					"search",
					"--samples",
					"1",
					"--format",
					"json",
				],
				{
					YEN_IDE_STATE_DIR: stateDir,
					YEN_IDE_SLO_SEARCH_LATENCY_MS: "5000",
				},
			);
			expect(res.status, ideCommandDiagnostics(res)).toBe(1);

			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			expect(payload.suites).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						id: "search",
						execution: expect.objectContaining({
							status: "fail",
						}),
						coverage: expect.objectContaining({
							status: "missing",
						}),
					}),
				]),
			);

			const sloPath = join(stateDir, "non-interference-slo.tsv");
			if (existsSync(sloPath)) {
				const sloLedger = readFileSync(sloPath, "utf8");
				expect(sloLedger.trim()).toBe("");
			}
		} finally {
			rmSync(tempDir, { force: true, recursive: true });
			rmSync(stateDir, { force: true, recursive: true });
		}
	});
	test("benchmark invocations isolate their LSP socket directories", () => {
		const root = ideTemp("yen-benchmark-socket-isolation-");
		const resources = join(root, "resources");
		cpSync(join(repoRoot, "yen-cli"), resources, { recursive: true });
		const realCli = join(resources, "bin/yen-real");
		renameSync(join(resources, "bin/yen"), realCli);
		writeFileSync(
			join(resources, "bin/yen"),
			'#!/bin/bash\nprintf "socket_dir=%s\\n" "${YEN_IDE_LSP_SOCKET_DIR:-unset}"\n',
			{ mode: 0o755 },
		);
		const sockets: string[] = [];
		for (let index = 0; index < 2; index += 1) {
			const result = runYenAt(
				realCli,
				[
					"ide",
					"benchmark",
					"run",
					"--suite",
					"lsp",
					"--samples",
					"1",
					"--write-baseline",
					"--format",
					"json",
				],
				{
					YEN_IDE_STATE_DIR: join(root, `state-${index}`),
				},
			);
			expect(result.status, ideCommandDiagnostics(result)).toBe(0);
			const payload = JSON.parse(result.stdout);
			const line = payload.suites[0].logExcerpt.find((value: string) =>
				value.startsWith("socket_dir="),
			);
			expect(line).toBeDefined();
			const directory = line.slice("socket_dir=".length);
			expect(directory).not.toBe("unset");
			expect(
				Buffer.byteLength(join(directory, "abcdefghijkl.sock")),
			).toBeLessThan(104);
			sockets.push(directory);
		}
		expect(new Set(sockets).size).toBe(2);
	});
});
