import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
	createIdeTemp,
	IDE_CLI_SLOW_TEST_TIMEOUT_MS,
} from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	const result = spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		timeout: 10_000,
		env: {
			...process.env,
			...envOverrides,
		},
	});
	if (result.error) {
		throw new Error(
			`yen ${args.join(" ")}: ${result.error.message}\n${result.stderr}`,
		);
	}
	return result;
}

describe("IDE S3W test-to-debug handoff", () => {
	test(
		"test status and verify status surface one explicit local debug handoff when the debugger baseline can launch the failing target",
		() => {
			const stateDir = ideTemp("yen-ide-test-debug-state-");
			const project = ideTemp("yen-ide-test-debug-project-");
			const root = realpathSync(project);
			const env = { YEN_IDE_STATE_DIR: stateDir };

			writeFileSync(
				join(project, "app.js"),
				"throw new Error('boom')\n",
				"utf8",
			);
			writeFileSync(
				join(project, "package.json"),
				`${JSON.stringify(
					{
						name: "test-debug-handoff",
						scripts: {
							test: "bash -lc 'echo app.js:7:1 boom >&2; exit 1'",
						},
					},
					null,
					2,
				)}\n`,
				"utf8",
			);

			const verify = runYen(
				["ide", "verify", "--quick", "--no-security"],
				env,
				project,
			);
			expect(verify.status, `${verify.stdout}\n${verify.stderr}`).toBe(1);

			const testJson = runYen(
				["ide", "test", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(testJson.status, `${testJson.stdout}\n${testJson.stderr}`).toBe(0);
			const testPayload = JSON.parse(testJson.stdout ?? "{}");
			expect(testPayload.summary.debuggableFailureGroups).toBe(1);
			expect(testPayload.failures[0].debugHandoff).toMatchObject({
				tool: "node-inspect",
				toolTitle: "Node inspect",
				trustRequired: true,
				trustCommand: `yen ide debug trust '${root}'`,
			});
			expect(testPayload.failures[0].debugHandoff.command).toContain(
				"yen ide debug start 'app.js:7:1' --project",
			);
			expect(testPayload.runners[0].lastRun.debugHandoff.command).toContain(
				"yen ide debug start 'app.js:7:1' --project",
			);

			const testText = runYen(
				["ide", "test", "status", "--project", project],
				env,
				project,
			);
			expect(testText.status, `${testText.stdout}\n${testText.stderr}`).toBe(0);
			expect(testText.stdout).toContain("Latest Failure Groups:");
			expect(testText.stdout).toContain(
				"debug:   yen ide debug start 'app.js:7:1'",
			);
			expect(testText.stdout).toContain("trust:   yen ide debug trust");

			const verifyJson = runYen(
				["ide", "verify", "status", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(
				verifyJson.status,
				`${verifyJson.stdout}\n${verifyJson.stderr}`,
			).toBe(0);
			const verifyPayload = JSON.parse(verifyJson.stdout ?? "{}");
			const nodeStep = (verifyPayload.steps ?? []).find(
				(step: { id: string }) => step.id === "node-test",
			);
			expect(nodeStep).toBeTruthy();
			expect(nodeStep.debugHandoff).toMatchObject({
				tool: "node-inspect",
				toolTitle: "Node inspect",
				trustRequired: true,
			});
			expect(nodeStep.debugHandoff.command).toContain(
				"yen ide debug start 'app.js:7:1' --project",
			);
			expect(verifyPayload.summary.debuggableSteps).toBe(1);

			const verifyText = runYen(
				["ide", "verify", "status", "--project", project],
				env,
				project,
			);
			expect(
				verifyText.status,
				`${verifyText.stdout}\n${verifyText.stderr}`,
			).toBe(0);
			expect(verifyText.stdout).toContain("Debug Handoffs:");
			expect(verifyText.stdout).toContain("node-test:");
			expect(verifyText.stdout).toContain(
				"yen ide debug start 'app.js:7:1' --project",
			);
		},
		// Five real CLI processes can exceed Bun's default 5s budget under build load.
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);
});
