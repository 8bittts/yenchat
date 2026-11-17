import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	existsSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
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

function runYenInProject(
	args: string[],
	cwd: string,
	envOverrides: Record<string, string> = {},
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

function runCommand(
	command: string,
	args: string[],
	cwd: string,
	envOverrides: Record<string, string> = {},
) {
	return spawnSync(command, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function createGhMockSandbox() {
	const root = ideTemp("yen-ide-s3-");
	const binDir = join(root, "bin");
	const logFile = join(root, "gh-calls.log");
	mkdirSync(binDir, { recursive: true });
	writeFileSync(logFile, "", "utf8");

	const ghPath = join(binDir, "gh");
	writeFileSync(
		ghPath,
		`#!/bin/bash
set -e

if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "acme/repo"
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "view" ]]; then
  if [[ "$*" == *"--json number,title,url,headRefName,baseRefName,headRefOid,author,changedFiles,additions,deletions"* ]]; then
    printf "123\\tDemo PR\\thttps://github.com/acme/repo/pull/123\\tfeature\\tmain\\tdeadbeef\\talice\\t2\\t10\\t3\\n"
    exit 0
  fi
  if [[ "$*" == *"--json number"* ]]; then
    echo "123"
    exit 0
  fi
fi

if [[ "$1" == "pr" && "$2" == "diff" ]]; then
  if [[ "$*" == *"--name-only"* ]]; then
    printf "src/a.ts\\nsrc/b.ts\\n"
    exit 0
  fi
  printf "diff --git a/src/a.ts b/src/a.ts\\n@@ -1 +1 @@\\n-oldTop\\n+newTop\\n@@ -12 +12 @@\\n-oldBottom\\n+newBottom\\ndiff --git a/src/b.ts b/src/b.ts\\n@@ -2 +2 @@\\n-before\\n+after\\n"
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "comment" ]]; then
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "review" ]]; then
  exit 0
fi

if [[ "$1" == "api" && "$2" == "repos/acme/repo/pulls/123/files?per_page=100" ]]; then
  printf "@@ -1 +1 @@\\n-oldTop\\n+newTop\\n@@ -12 +12 @@\\n-oldBottom\\n+newBottom\\n"
  exit 0
fi

if [[ "$1" == "api" && "$2" == "repos/acme/repo/pulls/123/comments" ]]; then
  printf "%s\\n" "$*" >> "\${YEN_TEST_GH_CALL_LOG}"
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
`,
		"utf8",
	);
	chmodSync(ghPath, 0o755);

	return {
		root,
		binDir,
		logFile,
	};
}

function createYenResourcesSandbox(deltaScript = "") {
	const root = ideTemp("yen-ide-s3-resources-");
	mkdirSync(join(root, "bin"), { recursive: true });
	mkdirSync(join(root, "commands", "core"), { recursive: true });
	symlinkSync(join(repoRoot, "yen-cli", "lib"), join(root, "lib"));
	copyFileSync(
		join(repoRoot, "yen-cli", "commands", "core", "ide"),
		join(root, "commands", "core", "ide"),
	);
	chmodSync(join(root, "commands", "core", "ide"), 0o755);

	if (deltaScript) {
		const deltaPath = join(root, "bin", "delta");
		writeFileSync(deltaPath, deltaScript, "utf8");
		chmodSync(deltaPath, 0o755);
	}

	return { root };
}

function createPrReviewProject(prefix: string) {
	const root = ideTemp(prefix);
	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};

	mkdirSync(join(root, "src"), { recursive: true });
	writeFileSync(
		join(root, "package.json"),
		'{"name":"pr-review-fixture"}\n',
		"utf8",
	);
	writeFileSync(join(root, "CODEOWNERS"), "src/* @frontend-team\n", "utf8");
	writeFileSync(
		join(root, "src", "a.ts"),
		"export function oldTop() {}\n",
		"utf8",
	);
	writeFileSync(
		join(root, "src", "b.ts"),
		"export function before() {}\n",
		"utf8",
	);
	writeFileSync(
		join(root, "src", "app.js"),
		"export function reviewLaunch() { return true; }\n",
		"utf8",
	);

	expect(runCommand("git", ["init"], root, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], root, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], root, gitEnv).status).toBe(0);
	expect(runCommand("git", ["commit", "-m", "init"], root, gitEnv).status).toBe(
		0,
	);

	return root;
}

describe("IDE S3 workflow controls", () => {
	test("ide help advertises strict env load, loop scripting, inline review, and risk overrides", () => {
		const res = runYen(["ide", "--help"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("--strict fails on unsupported/invalid env lines");
		expect(output).toContain('--loop-script "n,e,q"');
		expect(output).toContain("--list-hunks [--file <path>]");
		expect(output).toContain("--hunk <path:line[:col]>");
		expect(output).toContain("--inline <path:line[:LEFT|RIGHT]>");
		expect(output).toContain("--risk-override <level>");
		expect(output).toContain("--allowlist <path>");
	});

	test("env load strict mode fails on invalid lines and writes report", () => {
		const projectRoot = ideTemp("yen-ide-env-");
		const reportPath = join(projectRoot, "env-report.tsv");
		writeFileSync(
			join(projectRoot, ".env"),
			[
				"OK_VALUE=1",
				"BAD LINE WITHOUT ASSIGNMENT",
				"export GOOD_VALUE='2'",
			].join("\n"),
			"utf8",
		);

		const trust = runYen(["ide", "env", "trust", projectRoot]);
		expect(trust.status).toBe(0);

		const load = runYen([
			"ide",
			"env",
			"load",
			"--strict",
			"--report",
			reportPath,
			projectRoot,
		]);
		const output = `${load.stdout ?? ""}\n${load.stderr ?? ""}`;
		expect(load.status).toBe(1);
		expect(output).toContain("strict mode rejected");
		expect(output).toContain(reportPath);
		expect(existsSync(reportPath)).toBe(true);
		const report = readFileSync(reportPath, "utf8");
		expect(report).toContain("missing-assignment");
	});

	test("gate supports explicit risk override for false-positive bypass in non-interactive mode", () => {
		const res = runYen([
			"ide",
			"gate",
			"--policy",
			"prompt-high",
			"--risk-override",
			"low",
			"--dry-run",
			"--",
			"git",
			"reset",
			"--hard",
		]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Gate summary:");
		expect(output).toContain("risk=low");
	});

	test("pr-review loop-script runs deterministically without an interactive tty", () => {
		const mock = createGhMockSandbox();
		const res = runYen(
			["ide", "pr-review", "123", "--loop", "--loop-script", "e,q"],
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("pr-review(script)> e");
		expect(output).toContain("Wrote PR evidence bundle");
	});

	test("pr-review evidence bundle includes the latest verify readiness and security snapshot", () => {
		const mock = createGhMockSandbox();
		const verifyDir = join(mock.root, "verify");
		const evidenceDir = join(mock.root, "evidence");
		mkdirSync(verifyDir, { recursive: true });

		const summaryPath = join(verifyDir, "verify-20260320T000000Z-fixture.tsv");
		const detailsPath = join(verifyDir, "verify-20260320T000000Z-fixture.log");
		const semanticPath = join(
			verifyDir,
			"verify-20260320T000000Z-fixture.semantic.tsv",
		);
		writeFileSync(
			summaryPath,
			`${[
				"2026-03-20T00:00:00Z\tgitleaks\t2\t12\tstable\t0\tgitleaks detect --no-banner --redact --source .\tfail\tsecurity",
				"2026-03-20T00:00:01Z\tnode-audit\t1\t30\tstable\t0\tbun audit\twarn\tsecurity",
				"2026-03-20T00:00:02Z\tosv-scanner\t1\t44\tstable\t0\tosv-scanner --format json --lockfile='/tmp/repo/bun.lock'\twarn\tsecurity",
			].join("\n")}\n`,
			"utf8",
		);
		writeFileSync(
			detailsPath,
			[
				"=== gitleaks ===",
				"category: security",
				"result: fail",
				"command: gitleaks detect --no-banner --redact --source .",
				"status: 2",
				"--- output ---",
				"fake secret detected",
				"",
				"=== node-audit ===",
				"category: security",
				"result: warn",
				"command: bun audit",
				"status: 1",
				"--- output ---",
				"1 high severity vulnerability",
				"",
				"=== osv-scanner ===",
				"category: security",
				"result: warn",
				"command: osv-scanner --format json --lockfile='/tmp/repo/bun.lock'",
				"status: 1",
				"--- output ---",
				'{"results":[{"source":{"path":"/tmp/repo/bun.lock","type":"lockfile"},"packages":[{"package":{"name":"fixture","version":"1.0.0","ecosystem":"npm"},"groups":[{"ids":["GHSA-1234"]}],"vulnerabilities":[{"id":"GHSA-1234"}]}]}]}',
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(
			semanticPath,
			"found\tpath\tline\tcol\tabsolute_path\tlocation\n",
			"utf8",
		);
		writeFileSync(
			join(mock.root, "timeline.log"),
			[
				`2026-03-20T00:00:03Z\tverify\t${repoRoot}\tfailures=1;warns=2\tsummary=${summaryPath};semantic=${semanticPath}`,
				"",
			].join("\n"),
			"utf8",
		);

		const res = runYen(["ide", "pr-review", "123", "--no-diff", "--evidence"], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_IDE_STATE_DIR: mock.root,
			YEN_TEST_GH_CALL_LOG: mock.logFile,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Wrote PR evidence bundle");

		const evidenceFiles = readdirSync(evidenceDir);
		expect(evidenceFiles.length).toBe(1);
		const evidence = readFileSync(
			join(evidenceDir, evidenceFiles[0] ?? ""),
			"utf8",
		);
		expect(evidence).toContain("## Evidence Status");
		expect(evidence).toContain("- Bundle: exported-with-gaps");
		expect(evidence).toContain("- PR review: available");
		expect(evidence).toContain(
			"## Latest Verify Readiness + Security Snapshot",
		);
		expect(evidence).toContain("- Security: blocked");
		expect(evidence).toContain(`- Details report: ${detailsPath}`);
		expect(evidence).toContain(
			"- Security step: osv-scanner | result=warn | exit=1 | 1 vulnerability group(s) across 1 package(s) from 1 source(s)",
		);
	});

	test("pr-review uses the shared delta renderer contract when explicit fallback is enabled", () => {
		const mock = createGhMockSandbox();
		const resources = createYenResourcesSandbox(`#!/bin/bash
printf "[delta-renderer] %s\\n" "$*"
cat
`);

		const res = runYen(["ide", "pr-review", "123", "--file", "src/a.ts"], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_LIB: join(resources.root, "lib"),
			YEN_TEST_GH_CALL_LOG: mock.logFile,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("[delta-renderer] --paging=never");
		expect(output).toContain("Focused diff: src/a.ts");
		expect(output).toContain("+newTop");
	});

	test("pr-review prints and writes review routing context for selected files", () => {
		const mock = createGhMockSandbox();
		const project = createPrReviewProject("yen-ide-pr-review-context-");
		const stateDir = ideTemp("yen-ide-pr-review-state-");

		const res = runYenInProject(
			[
				"ide",
				"pr-review",
				"123",
				"--no-diff",
				"--file",
				"src/a.ts",
				"--evidence",
			],
			project,
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Review routing:");
		expect(output).toContain("src/a.ts owners=@frontend-team");

		const evidenceDir = join(stateDir, "evidence");
		const evidenceFiles = readdirSync(evidenceDir);
		expect(evidenceFiles.length).toBe(1);
		const evidence = readFileSync(
			join(evidenceDir, evidenceFiles[0] ?? ""),
			"utf8",
		);
		expect(evidence).toContain("## Review Routing");
		expect(evidence).toContain("`src/a.ts`");
		expect(evidence).toContain("@frontend-team");
	});

	test("pr-review evidence reuses recent agent approval and handoff context when present", () => {
		const mock = createGhMockSandbox();
		const project = createPrReviewProject("yen-ide-pr-review-agent-notes-");
		const stateDir = ideTemp("yen-ide-pr-review-state-");
		const agentsStateDir = ideTemp("yen-agents-state-");

		expect(
			runYenInProject(
				[
					"agents",
					"note",
					"--template",
					"handoff-review",
					"--actor",
					"supervisor",
					"--message",
					"Focus src/a.ts before approval.",
				],
				project,
				{
					YEN_AGENTS_STATE_DIR: agentsStateDir,
				},
			).status,
		).toBe(0);

		expect(
			runYenInProject(
				[
					"agents",
					"note",
					"--template",
					"review-approved",
					"--message",
					"Ready for PR review.",
				],
				project,
				{
					YEN_AGENTS_STATE_DIR: agentsStateDir,
				},
			).status,
		).toBe(0);

		const res = runYenInProject(
			[
				"ide",
				"pr-review",
				"123",
				"--no-diff",
				"--file",
				"src/a.ts",
				"--evidence",
			],
			project,
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_AGENTS_STATE_DIR: agentsStateDir,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		expect(res.status).toBe(0);

		const evidenceDir = join(stateDir, "evidence");
		const evidenceFiles = readdirSync(evidenceDir);
		expect(evidenceFiles.length).toBe(1);
		const evidence = readFileSync(
			join(evidenceDir, evidenceFiles[0] ?? ""),
			"utf8",
		);
		expect(evidence).toContain("## Agent Handoff Context");
		expect(evidence).toContain("Review handoff");
		expect(evidence).toContain("template=handoff-review");
		expect(evidence).toContain("approval:approved");
		expect(evidence).toContain("Ready for PR review.");
	});

	test("pr-review only surfaces debug routing for review targets the shipped local debugger can really launch", () => {
		const mock = createGhMockSandbox();
		const project = createPrReviewProject("yen-ide-pr-review-debug-");
		const stateDir = ideTemp("yen-ide-pr-review-debug-state-");

		const res = runYenInProject(
			[
				"ide",
				"pr-review",
				"123",
				"--no-diff",
				"--file",
				"src/app.js",
				"--evidence",
			],
			project,
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Review routing:");
		expect(output).toContain("src/app.js owners=@frontend-team");
		expect(output).toContain("debug: yen ide debug start 'src/app.js'");
		expect(output).toContain("trust: yen ide debug trust");

		const evidenceDir = join(stateDir, "evidence");
		const evidenceFiles = readdirSync(evidenceDir);
		expect(evidenceFiles.length).toBe(1);
		const evidence = readFileSync(
			join(evidenceDir, evidenceFiles[0] ?? ""),
			"utf8",
		);
		expect(evidence).toContain("`src/app.js`");
		expect(evidence).toContain("Debug here: `yen ide debug start 'src/app.js'");
		expect(evidence).toContain("Trust first: `yen ide debug trust");
	});

	test("pr-review lists deterministic semantic hunk targets", () => {
		const mock = createGhMockSandbox();
		const res = runYen(
			["ide", "pr-review", "123", "--list-hunks", "--file", "src/a.ts"],
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("PR Review Hunk Targets");
		expect(output).toContain("src/a.ts:1:1");
		expect(output).toContain("src/a.ts:12:1");
		expect(output).not.toContain("src/b.ts:2:1");
	});

	test("pr-review renders a focused semantic hunk through delta", () => {
		const mock = createGhMockSandbox();
		const resources = createYenResourcesSandbox(`#!/bin/bash
printf "[delta-renderer] %s\\n" "$*"
cat
`);

		const res = runYen(["ide", "pr-review", "123", "--hunk", "src/a.ts:12"], {
			PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
			YEN_LIB: join(resources.root, "lib"),
			YEN_TEST_GH_CALL_LOG: mock.logFile,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("[delta-renderer] --paging=never");
		expect(output).toContain("Focused hunk: src/a.ts:12:1");
		expect(output).toContain("+newBottom");
		expect(output).not.toContain("+newTop");
	});

	test("pr-review inline posting calls GitHub inline comments API", () => {
		const mock = createGhMockSandbox();
		const res = runYen(
			[
				"ide",
				"pr-review",
				"123",
				"--no-diff",
				"--inline",
				"src/a.ts:42:RIGHT",
				"--inline-body",
				"Needs nil check before dereference.",
				"--post",
			],
			{
				PATH: `${mock.binDir}:${process.env.PATH ?? ""}`,
				YEN_TEST_GH_CALL_LOG: mock.logFile,
			},
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("Posted inline comment to PR #123");
		const calls = readFileSync(mock.logFile, "utf8");
		expect(calls).toContain("repos/acme/repo/pulls/123/comments");
		expect(calls).toContain("line=42");
		expect(calls).toContain("side=RIGHT");
	});
});
