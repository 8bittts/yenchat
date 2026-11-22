import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
} from "node:fs";
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
	return spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function delay(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

function captureChild(child: ReturnType<typeof spawn>) {
	let output = "";
	child.stdout?.on("data", (chunk) => {
		output += String(chunk);
	});
	child.stderr?.on("data", (chunk) => {
		output += String(chunk);
	});
	return {
		getOutput() {
			return output;
		},
		settled: new Promise<{ code: number | null; output: string }>((resolve) => {
			child.on("close", (code) => resolve({ code, output }));
		}),
	};
}

async function waitForOutput(
	getOutput: () => string,
	needle: string,
	timeoutMs = 5000,
) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		if (getOutput().includes(needle)) {
			return;
		}
		await delay(50);
	}
	throw new Error(`Timed out waiting for output containing: ${needle}`);
}

function initGitRepo(root: string) {
	spawnSync("git", ["init", "-b", "main"], { cwd: root, encoding: "utf8" });
	spawnSync("git", ["config", "user.name", "YEN Test"], {
		cwd: root,
		encoding: "utf8",
	});
	spawnSync("git", ["config", "user.email", "test@example.com"], {
		cwd: root,
		encoding: "utf8",
	});
}

function createVerifyWatchProject(prefix: string) {
	const root = ideTemp(prefix);
	initGitRepo(root);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "verify-watch-fixture",
				scripts: {
					lint: "node verify-watch.js lint-pass",
					test: "node verify-watch.js test-pass",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(root, "verify-watch.js"),
		[
			"const mode = process.argv[2] || 'pass';",
			"if (mode.includes('fail')) {",
			"  console.error(`verify ${mode}`);",
			"  process.exit(1);",
			"}",
			"console.log(`verify ${mode}`);",
			"",
		].join("\n"),
		"utf8",
	);
	return root;
}

function createWorkflowBuildWatchProject(prefix: string) {
	const root = ideTemp(prefix);
	initGitRepo(root);
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "workflow-build-watch-fixture",
				scripts: {
					build: "node build-watch.js pass",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(root, "build-watch.js"),
		[
			"const mode = process.argv[2] || 'pass';",
			"if (mode.includes('fail')) {",
			"  console.error(`build ${mode}`);",
			"  process.exit(1);",
			"}",
			"console.log(`build ${mode}`);",
			"",
		].join("\n"),
		"utf8",
	);
	return root;
}

function createGhCiSandbox() {
	const root = ideTemp("yen-ide-pr-ci-");
	const binDir = join(root, "bin");
	const ghPath = join(binDir, "gh");
	const counterFile = join(root, "gh-counter.txt");

	mkdirSync(binDir, { recursive: true });
	writeFileSync(counterFile, "0\n", "utf8");
	writeFileSync(
		ghPath,
		`#!/bin/bash
set -e

counter_file="\${YEN_TEST_GH_COUNTER_FILE}"
count="0"
if [[ -f "\${counter_file}" ]]; then
  count="$(tr -d '[:space:]' < "\${counter_file}")"
fi

if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "acme/repo"
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "list" ]]; then
  exit 0
fi

if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json number,title,url,isDraft,headRefName,statusCheckRollup"* ]]; then
  if [[ "\${count}" == "0" ]]; then
    cat <<'EOF'
{"number":17,"title":"Build Watch","url":"https://github.com/acme/repo/pull/17","isDraft":false,"headRefName":"main","statusCheckRollup":{"contexts":[{"state":"PENDING"}]}}
EOF
    printf "1\n" > "\${counter_file}"
    exit 0
  fi
  cat <<'EOF'
{"number":17,"title":"Build Watch","url":"https://github.com/acme/repo/pull/17","isDraft":false,"headRefName":"main","statusCheckRollup":{"contexts":[{"conclusion":"SUCCESS"}]}}
EOF
  printf "2\n" > "\${counter_file}"
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
`,
		"utf8",
	);
	chmodSync(ghPath, 0o755);

	return { root, binDir, counterFile };
}

describe("IDE S3S local build + CI watch baseline", () => {
	test(
		"verify --watch records shared build-watch progress and verify status surfaces the latest watch snapshot",
		async () => {
			const stateDir = ideTemp("yen-ide-verify-watch-state-");
			const project = createVerifyWatchProject("yen-ide-verify-watch-project-");
			const env = {
				...process.env,
				YEN_IDE_STATE_DIR: stateDir,
			};
			const child = spawn(
				yenBinPath,
				[
					"ide",
					"verify",
					"--quick",
					"--no-security",
					"--watch",
					"--watch-interval",
					"0.1",
					"--max-runs",
					"2",
				],
				{
					cwd: project,
					env,
					stdio: "pipe",
				},
			);
			const watchRun = captureChild(child);

			await waitForOutput(
				watchRun.getOutput,
				"Watch: waiting for project changes to rerun verify snapshot",
			);
			await delay(300);
			expect(watchRun.getOutput()).not.toContain("Watch iteration: 2");

			writeFileSync(
				join(project, "package.json"),
				`${JSON.stringify(
					{
						name: "verify-watch-fixture",
						scripts: {
							lint: "node verify-watch.js lint-pass",
							test: "node verify-watch.js test-fail",
						},
					},
					null,
					2,
				)}\n`,
				"utf8",
			);

			const result = await watchRun.settled;
			expect(result.code).toBe(1);
			expect(result.output).toContain("Watch iteration: 1");
			expect(result.output).toContain("Watch iteration: 2");
			const summaryMatches = Array.from(
				result.output.matchAll(/Summary file:\s+([^\n]+)/g),
			);
			expect(summaryMatches).toHaveLength(2);
			expect(summaryMatches[0]?.[1]?.trim()).not.toBe(
				summaryMatches[1]?.[1]?.trim(),
			);
			expect(existsSync(summaryMatches[0]?.[1]?.trim() ?? "")).toBe(true);
			expect(existsSync(summaryMatches[1]?.[1]?.trim() ?? "")).toBe(true);

			const status = runYen(
				["ide", "verify", "status", "--format", "json"],
				{ YEN_IDE_STATE_DIR: stateDir },
				project,
			);
			expect(status.status, status.stderr).toBe(0);
			const payload = JSON.parse(status.stdout ?? "{}");
			expect(payload.watch.available).toBe(true);
			expect(payload.watch.kind).toBe("verify");
			expect(payload.watch.active).toBe(false);
			expect(payload.watch.state).toBe("max-runs");
			expect(payload.watch.iteration).toBe(2);
			expect(payload.watch.lastOutcome).toBe("failing");
			expect(payload.watch.lastExitCode).toBe(1);
			expect(payload.watch.branch).toBe("main");
			expect(existsSync(payload.watch.summaryReport)).toBe(true);

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("\tverify-watch\t");
			expect(timeline).toContain("reason=max-runs");
			expect(timeline).toContain("\tverify\t");
			expect(timeline).toContain("watchIteration=2");
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);

	test(
		"workflow build watch reuses the shared progress model and verify status surfaces the workflow-native build session",
		async () => {
			const stateDir = ideTemp("yen-ide-workflow-build-watch-state-");
			const project = createWorkflowBuildWatchProject(
				"yen-ide-workflow-build-watch-project-",
			);
			const env = {
				...process.env,
				YEN_IDE_STATE_DIR: stateDir,
			};
			const child = spawn(
				yenBinPath,
				[
					"ide",
					"workflow",
					"run",
					"--native",
					"package.json:build",
					"--allow-untrusted",
					"--watch",
					"--watch-interval",
					"0.1",
				],
				{
					cwd: project,
					env,
					stdio: "pipe",
				},
			);
			const watchRun = captureChild(child);

			await waitForOutput(
				watchRun.getOutput,
				"Watch: waiting for project changes to rerun native task snapshot",
			);
			await delay(300);
			expect(watchRun.getOutput()).not.toContain("Watch iteration:  2");

			writeFileSync(
				join(project, "package.json"),
				`${JSON.stringify(
					{
						name: "workflow-build-watch-fixture",
						scripts: {},
					},
					null,
					2,
				)}\n`,
				"utf8",
			);

			const result = await watchRun.settled;
			expect(result.code).toBe(1);
			expect(result.output).toContain(
				"Native task 'package.json:build' not found.",
			);

			const status = runYen(
				["ide", "verify", "status", "--format", "json"],
				{ YEN_IDE_STATE_DIR: stateDir },
				project,
			);
			expect(status.status, status.stderr).toBe(0);
			const payload = JSON.parse(status.stdout ?? "{}");
			expect(payload.watch.available).toBe(true);
			expect(payload.watch.kind).toBe("workflow-native-build");
			expect(payload.watch.label).toBe("package.json:build");
			expect(payload.watch.active).toBe(false);
			expect(payload.watch.state).toBe("missing");
			expect(payload.watch.stopReason).toBe("missing");
			expect(payload.watch.branch).toBe("main");

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("\tworkflow-watch\t");
			expect(timeline).toContain("reason=missing");
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);

	test(
		"pr-notify --ci-status polls current-branch CI, shows local build-watch progress, and records CI transitions",
		() => {
			const stateDir = ideTemp("yen-ide-pr-ci-state-");
			const project = createVerifyWatchProject("yen-ide-pr-ci-project-");
			const ghSandbox = createGhCiSandbox();
			const verifyWatch = runYen(
				[
					"ide",
					"verify",
					"--quick",
					"--no-security",
					"--watch",
					"--watch-interval",
					"0.1",
					"--max-runs",
					"1",
				],
				{ YEN_IDE_STATE_DIR: stateDir },
				project,
			);
			expect(verifyWatch.status).toBe(0);

			const notify = runYen(
				[
					"ide",
					"pr-notify",
					"--ci-status",
					"--watch",
					"--interval",
					"0.1",
					"--max-polls",
					"2",
				],
				{
					YEN_IDE_STATE_DIR: stateDir,
					PATH: `${ghSandbox.binDir}:${process.env.PATH}`,
					YEN_TEST_GH_COUNTER_FILE: ghSandbox.counterFile,
				},
				project,
			);
			const output = `${notify.stdout ?? ""}\n${notify.stderr ?? ""}`;
			expect(notify.status).toBe(0);
			expect(output).toContain("PR Review Notifications");
			expect(output).toContain("Current Branch CI");
			expect(output).toContain("Status: pending");
			expect(output).toContain("Status: passing");
			expect(output).toContain(
				"Local build watch: max-runs (verify; active=no; iteration=1; branch=main; last=passing)",
			);

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("\tpr-ci\t");
			expect(timeline).toContain("\tpending\t");
			expect(timeline).toContain("\tpassing\t");
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);
});
