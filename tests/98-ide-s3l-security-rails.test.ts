import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
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
const ideCommandPath = join(repoRoot, "yen-cli/commands/core/ide");
const ideVerifyTestModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/verify-test.sh",
);
const ideSearchHistoryModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/search-history.sh",
);

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

function writeExecutable(path: string, content: string) {
	writeFileSync(path, content, "utf8");
	chmodSync(path, 0o755);
}

describe("IDE S3L default security rails expansion", () => {
	test("verify status reports the latest local security/readiness snapshot from new verify reports", () => {
		const stateDir = ideTemp("yen-ide-verify-status-state-");
		const project = ideTemp("yen-ide-verify-status-project-");
		const fakeBin = join(stateDir, "bin");
		mkdirSync(fakeBin, { recursive: true });
		mkdirSync(join(project, "node_modules", "dep"), { recursive: true });
		mkdirSync(join(project, "tmp", "scratch"), { recursive: true });

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "security-status-fixture",
					packageManager: "bun@1.3.11",
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(
			join(project, "node_modules", "dep", "package-lock.json"),
			"{}",
			"utf8",
		);
		writeFileSync(
			join(project, "tmp", "scratch", "package-lock.json"),
			"{}",
			"utf8",
		);

		writeExecutable(
			join(fakeBin, "bun"),
			`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "1.3.11"
  exit 0
fi
if [[ "$1" == "audit" ]]; then
  echo "critical vulnerability in fixture"
  exit 1
fi
exit 0
`,
		);
		writeExecutable(
			join(fakeBin, "gitleaks"),
			`#!/bin/bash
echo "fake secret detected"
exit 2
`,
		);
		writeExecutable(
			join(fakeBin, "osv-scanner"),
			`#!/bin/bash
cat <<'JSON'
{"results":[{"source":{"path":"${join(project, "bun.lock")}","type":"lockfile"},"packages":[{"package":{"name":"fixture","version":"1.0.0","ecosystem":"npm"},"groups":[{"ids":["GHSA-1234"]}],"vulnerabilities":[{"id":"GHSA-1234"}]}]}]}
JSON
exit 1
`,
		);

		const verify = runYen(
			["ide", "verify", "--no-build"],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(verify.status).toBe(1);

		const status = runYen(
			["ide", "verify", "status", "--format", "json"],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");

		expect(payload.latest.status).toBe("failing");
		expect(payload.readiness.status).toBe("blocked");
		expect(payload.readiness.mergeReady).toBe(false);
		expect(payload.security.status).toBe("blocked");
		expect(payload.security.stepCount).toBe(3);
		expect(payload.security.warningSteps).toBe(2);
		expect(payload.security.failingSteps).toBe(1);

		const securityIds = new Set(
			(payload.security.steps as Array<{ id: string }>).map((item) => item.id),
		);
		expect(securityIds.has("gitleaks")).toBe(true);
		expect(securityIds.has("node-audit")).toBe(true);
		expect(securityIds.has("osv-scanner")).toBe(true);
		expect(
			(payload.security.steps as Array<{ id: string; result: string }>).find(
				(item) => item.id === "gitleaks",
			)?.result,
		).toBe("fail");
		expect(
			(payload.security.steps as Array<{ id: string; result: string }>).find(
				(item) => item.id === "node-audit",
			)?.result,
		).toBe("warn");
		const osvStep = (
			payload.security.steps as Array<{
				id: string;
				result: string;
				command?: string;
				summary?: string;
				analysis?: {
					kind: string;
					sourceCount?: number;
					packageCount?: number;
					vulnerabilityCount?: number;
				};
			}>
		).find((item) => item.id === "osv-scanner");
		expect(osvStep?.result).toBe("warn");
		expect(osvStep?.analysis?.kind).toBe("osv");
		expect(osvStep?.analysis?.sourceCount).toBe(1);
		expect(osvStep?.analysis?.packageCount).toBe(1);
		expect(osvStep?.analysis?.vulnerabilityCount).toBe(1);
		expect(osvStep?.summary).toContain("1 vulnerability group(s)");
		expect(osvStep?.command).toContain("--lockfile=");
		expect(osvStep?.command).toContain("bun.lock");
		expect(osvStep?.command).not.toContain("node_modules");
		expect(osvStep?.command).not.toContain(
			join(project, "tmp", "scratch", "package-lock.json"),
		);

		const summaryPath = payload.latest.summaryReport as string;
		const summaryLines = readFileSync(summaryPath, "utf8")
			.trim()
			.split("\n")
			.filter(Boolean);
		expect(summaryLines.length).toBeGreaterThan(0);
		for (const line of summaryLines) {
			expect(line.split("\t").length).toBeGreaterThanOrEqual(9);
		}
	});

	test("verify records a deterministic osv-scanner missing-tool warning when supported lockfiles exist", () => {
		const stateDir = ideTemp("yen-ide-verify-osv-missing-state-");
		const project = ideTemp("yen-ide-verify-osv-missing-project-");
		const fakeBin = join(stateDir, "bin");
		mkdirSync(fakeBin, { recursive: true });

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "security-osv-missing-fixture",
					packageManager: "bun@1.3.11",
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeExecutable(
			join(fakeBin, "bun"),
			`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "1.3.11"
  exit 0
fi
if [[ "$1" == "audit" ]]; then
  exit 0
fi
exit 0
`,
		);

		const verify = runYen(
			["ide", "verify", "--no-build"],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(verify.status).toBe(0);

		const status = runYen(
			["ide", "verify", "status", "--format", "json"],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");
		const osvStep = (
			payload.security.steps as Array<{
				id: string;
				result: string;
				category?: string;
				statusLine?: string;
			}>
		).find((item) => item.id === "osv-scanner");

		expect(payload.latest.status).toBe("warnings");
		expect(payload.security.status).toBe("warning");
		expect(osvStep?.result).toBe("warn");
		expect(osvStep?.category).toBe("security");
		expect(osvStep?.statusLine).toBe("skipped (missing-tool)");
	});

	test("verify status stays backward-compatible with older seven-column verify summaries", () => {
		const stateDir = ideTemp("yen-ide-verify-old-state-");
		const project = ideTemp("yen-ide-verify-old-project-");
		const canonicalProject = realpathSync(project);
		const verifyDir = join(stateDir, "verify");
		mkdirSync(verifyDir, { recursive: true });
		writeFileSync(join(project, "Makefile"), "all:\n\t@echo ok\n", "utf8");

		const summaryPath = join(verifyDir, "verify-20260320T000000Z-old.tsv");
		const detailsPath = join(verifyDir, "verify-20260320T000000Z-old.log");
		const semanticPath = join(
			verifyDir,
			"verify-20260320T000000Z-old.semantic.tsv",
		);
		const timelinePath = join(stateDir, "timeline.log");

		writeFileSync(
			summaryPath,
			`${[
				"2026-03-20T00:00:00Z\tgitleaks\t0\t12\tstable\t0\tgitleaks detect --no-banner --redact --source .",
				"2026-03-20T00:00:01Z\tnode-audit\t1\t30\tstable\t0\tbun audit",
			].join("\n")}\n`,
			"utf8",
		);
		writeFileSync(
			detailsPath,
			[
				"=== gitleaks ===",
				"command: gitleaks detect --no-banner --redact --source .",
				"status: 0",
				"duration_ms: 12",
				"--- output ---",
				"",
				"=== node-audit ===",
				"command: bun audit",
				"status: 1",
				"duration_ms: 30",
				"--- output ---",
				"1 high severity vulnerability",
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(semanticPath, "", "utf8");
		writeFileSync(
			timelinePath,
			[
				`2026-03-20T00:00:02Z\tverify\t${canonicalProject}\tfailures=0;warns=1\tsummary=${summaryPath};semantic=${semanticPath}`,
				"",
			].join("\n"),
			"utf8",
		);

		const status = runYen(
			["ide", "verify", "status", "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(status.stdout ?? "{}");

		expect(payload.latest.status).toBe("warnings");
		expect(payload.readiness.status).toBe("warning");
		expect(payload.security.status).toBe("warning");
		expect(payload.security.stepCount).toBe(2);
		expect(payload.security.warningSteps).toBe(1);
		expect(payload.security.failingSteps).toBe(0);
		expect(
			(payload.security.steps as Array<{ id: string; category: string }>).every(
				(item) => item.category === "security",
			),
		).toBe(true);
		expect(
			(payload.security.steps as Array<{ id: string; result: string }>).find(
				(item) => item.id === "node-audit",
			)?.result,
		).toBe("warn");
	});

	test("verify status is registered in CLI help and action search catalog", () => {
		const _ide = readFileSync(ideCommandPath, "utf8");
		const verifyTest = readFileSync(ideVerifyTestModulePath, "utf8");
		const searchHistory = readFileSync(ideSearchHistoryModulePath, "utf8");
		expect(verifyTest).toContain("cmd_verify_status()");
		expect(searchHistory).toContain("yen ide verify status");

		const help = runYen(["ide", "--help"]);
		expect(help.status).toBe(0);
		expect(help.stdout).toContain("verify [options]");
		expect(help.stdout).toContain(
			"status [path|ssh://user@host/abs/path] [--format text|json] shows latest verify/readiness/security snapshot from local reports",
		);
		expect(help.stdout).toContain(
			"run [--quick] [--no-build] [--no-security] [--strict] [--watch --watch-interval <sec> --max-runs <N>] writes summary/details/semantic reports + flaky tracker updates",
		);
	});
});
