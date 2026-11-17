import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

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

describe("IDE S3E verify semantic reports", () => {
	test("verify emits semantic step locations beside summary and details reports", () => {
		const stateDir = ideTemp("yen-ide-verify-state-");
		const project = ideTemp("yen-ide-verify-project-");
		mkdirSync(join(project, "src"), { recursive: true });
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "src", "check.ts"),
			"// verify fixture\n",
			"utf8",
		);
		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "verify-semantic-fixture",
					scripts: {
						"lint:check":
							"bash -lc 'echo src/check.ts:7:3 lint failure >&2; exit 1'",
					},
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		const res = runYen(
			["ide", "verify", "--quick", "--no-security"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(1);
		expect(output).toContain("IDE Verification Bundle");
		expect(output).toContain("Summary file:");
		expect(output).toContain("Details file:");
		expect(output).toContain("Semantic file:");
		expect(output).toContain("Verification bundle failed.");

		const summaryMatch = output.match(/Summary file:\s+([^\n]+)/);
		const detailsMatch = output.match(/Details file:\s+([^\n]+)/);
		const semanticMatch = output.match(/Semantic file:\s+([^\n]+)/);
		expect(summaryMatch).not.toBeNull();
		expect(detailsMatch).not.toBeNull();
		expect(semanticMatch).not.toBeNull();

		const summaryPath = summaryMatch?.[1]?.trim() ?? "";
		const detailsPath = detailsMatch?.[1]?.trim() ?? "";
		const semanticPath = semanticMatch?.[1]?.trim() ?? "";
		expect(existsSync(summaryPath)).toBe(true);
		expect(existsSync(detailsPath)).toBe(true);
		expect(existsSync(semanticPath)).toBe(true);

		const semantic = readFileSync(semanticPath, "utf8");
		const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");

		expect(semantic).toContain("\tlint-check\t1\tyes\tsrc/check.ts\t7\t3\t");
		expect(semantic).toContain(
			`\t${realpathSync(join(project, "src", "check.ts"))}\tsrc/check.ts:7:3`,
		);
		expect(timeline).toContain("summary=");
		expect(timeline).toContain("semantic=");
	});
});
