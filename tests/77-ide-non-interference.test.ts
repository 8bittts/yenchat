import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(args: string[], envOverrides: Record<string, string> = {}) {
	return spawnSync(yenBinPath, args, {
		cwd: repoRoot,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

describe("IDE non-interference guardrails", () => {
	test("recording repeated SLO breaches activates auto freeze beyond error budget", () => {
		const stateDir = ideTemp("yen-ide-ni-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_NON_INTERFERENCE_MIN_SAMPLES: "3",
			YEN_IDE_NON_INTERFERENCE_ERROR_BUDGET: "0.10",
		};

		for (let i = 0; i < 3; i += 1) {
			const record = runYen(
				[
					"ide",
					"non-interference",
					"record",
					"--metric",
					"startup-regression-ms",
					"--value",
					"400",
					"--source",
					"ci",
				],
				env,
			);
			expect(record.status).toBe(0);
		}

		const status = runYen(["ide", "non-interference", "status"], env);
		const output = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(output).toContain("Feature freeze: active (mode=auto)");
		expect(output).toContain("Breaches: 3");
		expect(existsSync(join(stateDir, "non-interference-freeze"))).toBe(true);
	});

	test("manual freeze/unfreeze updates status mode", () => {
		const stateDir = ideTemp("yen-ide-ni-manual-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
		};

		const freeze = runYen(
			["ide", "non-interference", "freeze", "--reason", "operator-maintenance"],
			env,
		);
		expect(freeze.status).toBe(0);

		const frozenStatus = runYen(["ide", "non-interference", "status"], env);
		const frozenOutput = `${frozenStatus.stdout ?? ""}\n${frozenStatus.stderr ?? ""}`;
		expect(frozenStatus.status).toBe(0);
		expect(frozenOutput).toContain("Feature freeze: active (mode=manual)");
		expect(frozenOutput).toContain("Freeze reason: operator-maintenance");

		const unfreeze = runYen(["ide", "non-interference", "unfreeze"], env);
		expect(unfreeze.status).toBe(0);

		const unfrozenStatus = runYen(["ide", "non-interference", "status"], env);
		const unfrozenOutput = `${unfrozenStatus.stdout ?? ""}\n${unfrozenStatus.stderr ?? ""}`;
		expect(unfrozenStatus.status).toBe(0);
		expect(unfrozenOutput).toContain(
			"Feature freeze: inactive (mode=inactive)",
		);
	});

	test("freeze state does not block existing fail-open gate dry-run flow", () => {
		const stateDir = ideTemp("yen-ide-ni-open-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
		};

		const freeze = runYen(["ide", "non-interference", "freeze"], env);
		expect(freeze.status).toBe(0);

		const gate = runYen(
			["ide", "gate", "--policy", "off", "--dry-run", "--", "echo", "ok"],
			env,
		);
		const gateOutput = `${gate.stdout ?? ""}\n${gate.stderr ?? ""}`;
		expect(gate.status).toBe(0);
		expect(gateOutput).toContain("Gate summary: policy=off risk=low score=0");
	});
});
