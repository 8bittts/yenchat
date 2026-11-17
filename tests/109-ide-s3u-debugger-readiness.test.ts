import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const vscodeModulePath = join(repoRoot, "yen-cli/lib/ide/vscode.sh");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	return spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function createNodeProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify({ name: "debug-readiness-node" }, null, 2)}\n`,
		"utf8",
	);
	writeFileSync(join(root, "app.js"), "console.log('ok')\n", "utf8");
	return root;
}

function createTypeScriptProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify({ name: "debug-readiness-ts" }, null, 2)}\n`,
		"utf8",
	);
	writeFileSync(
		join(root, "tsconfig.json"),
		`${JSON.stringify(
			{
				compilerOptions: {
					target: "ES2022",
					module: "ESNext",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(join(root, "main.ts"), "console.log('ts')\n", "utf8");
	return root;
}

describe("IDE S3U debugger readiness follow-on", () => {
	test(
		"doctor reports debugger readiness and warns when the recommended tool is missing",
		() => {
			const stateDir = ideTemp("yen-ide-debug-doctor-state-");
			const project = createNodeProject("yen-ide-debug-doctor-node-");
			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				PATH: "/usr/bin:/bin",
			};

			const json = runYen(
				["ide", "doctor", "--project", project, "--format", "json"],
				env,
				project,
			);
			expect(json.status).toBe(1);
			const payload = JSON.parse(json.stdout ?? "{}");
			expect(payload.debug.recommendedTool).toBe("node-inspect");
			expect(payload.debug.recommendedToolTitle).toBe("Node inspect");
			expect(payload.debug.recommendedAvailable).toBe(false);
			expect(payload.findings).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						code: "debug-tool-missing",
						component: "debug",
						severity: "warning",
					}),
				]),
			);

			const text = runYen(
				["ide", "doctor", "--project", project],
				env,
				project,
			);
			expect(text.status).toBe(1);
			expect(text.stdout).toContain("Debug:");
			expect(text.stdout).toContain("Node inspect missing");
		},
		{ timeout: 30_000 },
	);

	test(
		"doctor keeps TypeScript debugger limitations explicit without inventing a missing-tool warning",
		() => {
			const stateDir = ideTemp("yen-ide-debug-guidance-state-");
			const project = createTypeScriptProject("yen-ide-debug-guidance-ts-");

			const json = runYen(
				["ide", "doctor", "--project", project, "--format", "json"],
				{ YEN_IDE_STATE_DIR: stateDir },
				project,
			);
			expect(json.status).toBe(1);
			const payload = JSON.parse(json.stdout ?? "{}");
			expect(payload.debug.recommendedTool).toBe("node-inspect");
			expect(payload.debug.recommendedAvailable).toBe(true);
			expect(payload.debug.guidance).toContain(
				"Direct .ts debugger launch is not shipped",
			);
			expect(
				payload.findings.filter(
					(finding: { component: string }) => finding.component === "debug",
				),
			).toHaveLength(0);
		},
		{ timeout: 30_000 },
	);

	test(
		"workspace capabilities keep VS Code debugger guidance pointed at yen ide debug status",
		() => {
			const source = readFileSync(vscodeModulePath, "utf8");
			expect(source).toContain(
				"Run yen ide debug status to confirm local JavaScript entry-file readiness",
			);
			expect(source).toContain(
				"Run yen ide debug status to confirm local Python debugger readiness",
			);
			expect(source).toContain(
				"Run yen ide debug status to confirm the executable-only baseline; keep VS Code or Delve",
			);
			expect(source).toContain(
				"Run yen ide debug status to confirm the executable-only baseline; keep VS Code or CodeLLDB",
			);
		},
		{ timeout: 30_000 },
	);
});
