import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const ideCommandPath = join(repoRoot, "yen-cli/commands/core/ide");
const ideBootstrapModulePath = join(repoRoot, "yen-cli/lib/ide/bootstrap.sh");
const ideCommonModulePath = join(repoRoot, "yen-cli/lib/ide/common.sh");
const ideWorkspaceIdentityModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workspace-identity.sh",
);
const ideStateTrustModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/state-trust.sh",
);
const ideTimelineModulePath = join(repoRoot, "yen-cli/lib/ide/timeline.sh");
const ideReportsModulePath = join(repoRoot, "yen-cli/lib/ide/reports.sh");
const ideLspModulePath = join(repoRoot, "yen-cli/lib/ide/lsp.sh");
const ideAstModulePath = join(repoRoot, "yen-cli/lib/ide/ast.sh");
const ideVerifyTestModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/verify-test.sh",
);
const ideWorkflowQualityModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workflow-quality.sh",
);
const ideQualityModulePath = join(repoRoot, "yen-cli/lib/ide/quality.sh");
const ideWorkspaceCapabilitiesModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workspace-capabilities.sh",
);
const ideEnvModulePath = join(repoRoot, "yen-cli/lib/ide/env.sh");
const ideWorkspaceSummaryModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workspace-summary.sh",
);
const ideWorkspaceDoctorModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workspace-doctor.sh",
);
const ideWorkspaceTrustModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/workspace-trust.sh",
);
const ideDevcontainerModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/devcontainer.sh",
);
const ideShareModulePath = join(repoRoot, "yen-cli/lib/ide/share.sh");
const ideVscodeModulePath = join(repoRoot, "yen-cli/lib/ide/vscode.sh");
const ideSearchHistoryModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/search-history.sh",
);
const ideReviewContextModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/review-context.sh",
);
const ideEditorHandoffModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/editor-handoff.sh",
);
const ideDebugExecutionModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/debug-execution.sh",
);
const ideDebugTargetsModulePath = join(
	repoRoot,
	"yen-cli/lib/ide/debug-targets.sh",
);
const ideDebugUiModulePath = join(repoRoot, "yen-cli/lib/ide/debug-ui.sh");
const ideDebuggerModulePath = join(repoRoot, "yen-cli/lib/ide/debugger.sh");
const ideBenchmarkModulePath = join(repoRoot, "yen-cli/lib/ide/benchmark.sh");
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const zshIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/zsh/yen-integration.zsh",
);
const bashIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/bash/yen-integration.bash",
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

function createIdeSmokeProject(prefix: string) {
	const project = ideTemp(prefix);
	writeFileSync(join(project, "Makefile"), "all:\n\t@echo ok\n", "utf8");
	mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
	writeFileSync(
		join(project, ".yen", "workflows", "check.toml"),
		["schema_version = 1", 'name = "check"', 'step = "echo ok"', ""].join("\n"),
		"utf8",
	);
	return project;
}

function createGitRenameProject(prefix: string) {
	const project = createIdeSmokeProject(prefix);
	mkdirSync(join(project, "scripts"), { recursive: true });
	writeFileSync(
		join(project, "scripts", "old task.sh"),
		"#!/bin/bash\necho old\n",
	);

	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};

	expect(runCommand("git", ["init"], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], project, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["commit", "-m", "init"], project, gitEnv).status,
	).toBe(0);
	expect(
		runCommand(
			"git",
			["mv", "scripts/old task.sh", "scripts/new task.sh"],
			project,
			gitEnv,
		).status,
	).toBe(0);

	return project;
}

function createMergeReadinessReviewProject(prefix: string) {
	const project = createIdeSmokeProject(prefix);
	mkdirSync(join(project, "scripts"), { recursive: true });
	writeFileSync(
		join(project, "CODEOWNERS"),
		"scripts/* @release-team\n",
		"utf8",
	);
	writeFileSync(
		join(project, "scripts", "deploy.sh"),
		"#!/bin/bash\necho old\n",
	);

	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};

	expect(runCommand("git", ["init"], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], project, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["commit", "-m", "init"], project, gitEnv).status,
	).toBe(0);

	writeFileSync(
		join(project, "scripts", "deploy.sh"),
		"#!/bin/bash\necho new\n",
	);
	return project;
}

function createMergeReadinessDebugProject(prefix: string) {
	const project = createIdeSmokeProject(prefix);
	writeFileSync(join(project, "CODEOWNERS"), "app.js @runtime-team\n", "utf8");
	writeFileSync(join(project, "app.js"), "console.log('old')\n", "utf8");

	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};

	expect(runCommand("git", ["init"], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], project, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], project, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["commit", "-m", "init"], project, gitEnv).status,
	).toBe(0);

	writeFileSync(
		join(project, "app.js"),
		"console.log('new')\nconsole.log('still launchable')\n",
		"utf8",
	);
	return project;
}

function createShellDetectRaceHarness(shell: "bash" | "zsh") {
	const harnessRoot = ideTemp(`yen-shell-detect-${shell}-`);
	const binDir = join(harnessRoot, "bin");
	const resourcesDir = join(harnessRoot, "resources");
	const shellDir = join(harnessRoot, shell);
	const projA = join(harnessRoot, "projA");
	const projB = join(harnessRoot, "projB");

	mkdirSync(binDir, { recursive: true });
	mkdirSync(resourcesDir, { recursive: true });
	mkdirSync(shellDir, { recursive: true });
	mkdirSync(projA, { recursive: true });
	mkdirSync(projB, { recursive: true });

	writeFileSync(
		join(binDir, "yen"),
		[
			"#!/bin/bash",
			"# Exit immediately on SIGTERM so killed detects don't write stale results",
			"trap 'exit 143' TERM",
			'if [[ "$1" == "ide" && "$2" == "detect" ]]; then',
			"  shift 2",
			'  if [[ "${1:-}" == "--cached" ]]; then',
			"    shift",
			"  fi",
			'  if [[ "${1:-}" == "--format" && "${2:-}" == "env" ]]; then',
			'    if [[ "$PWD" == *projA ]]; then',
			"      sleep 0.15 &",
			"      wait $! 2>/dev/null || exit 143",
			"    else",
			"      sleep 0.02 &",
			"      wait $! 2>/dev/null || exit 143",
			"    fi",
			'    printf "export YEN_PROJECT_ROOT=%q\\n" "$PWD"',
			"    exit 0",
			"  fi",
			"fi",
			'if [[ "$1" == "ide" && "$2" == "env" && "$3" == "load" ]]; then',
			'  printf "export LOADED_FOR=%q\\n" "$4"',
			"  exit 0",
			"fi",
			"exit 1",
			"",
		].join("\n"),
		"utf8",
	);
	chmodSync(join(binDir, "yen"), 0o755);

	writeFileSync(
		join(resourcesDir, "version.json"),
		JSON.stringify({ version: "1.2.3", notes: "test" }),
		"utf8",
	);

	if (shell === "bash") {
		writeFileSync(
			join(shellDir, "yen-integration.bash"),
			readFileSync(bashIntegrationPath, "utf8"),
			"utf8",
		);
		writeFileSync(
			join(shellDir, "bash-preexec.sh"),
			"precmd_functions=()\npreexec_functions=()\n",
			"utf8",
		);
	} else {
		writeFileSync(
			join(shellDir, "yen-integration.zsh"),
			readFileSync(zshIntegrationPath, "utf8"),
			"utf8",
		);
	}

	return {
		binDir,
		projA,
		projB,
		resourcesDir,
		shellDir,
	};
}

function runShellDetectRace(shell: "bash" | "zsh") {
	const harness = createShellDetectRaceHarness(shell);
	const env = {
		...process.env,
		YEN_BIN_DIR: harness.binDir,
		YEN_IDE_AUTO_ENV: "1",
		YEN_RESOURCES_DIR: harness.resourcesDir,
		YEN_WELCOME_SHOWN: "1",
	};

	if (shell === "bash") {
		return {
			...harness,
			result: spawnSync(
				"bash",
				[
					"-ic",
					[
						`source ${JSON.stringify(join(harness.shellDir, "yen-integration.bash"))} >/dev/null`,
						`cd ${JSON.stringify(harness.projA)}`,
						"__yen_ide_start_detect",
						"sleep 0.03",
						`cd ${JSON.stringify(harness.projB)}`,
						"__yen_ide_start_detect",
						"sleep 0.25",
						"__yen_ide_apply_detect",
						'printf "root=%s\\n" "$YEN_PROJECT_ROOT"',
						'printf "loaded=%s\\n" "$LOADED_FOR"',
					].join("\n"),
				],
				{
					encoding: "utf8",
					env,
				},
			),
		};
	}

	return {
		...harness,
		result: spawnSync(
			"zsh",
			[
				"-ic",
				[
					`source ${JSON.stringify(join(harness.shellDir, "yen-integration.zsh"))} >/dev/null`,
					"_yen_deferred_init >/dev/null",
					`cd ${JSON.stringify(harness.projA)}`,
					"_yen_ide_start_detect",
					"sleep 0.03",
					`cd ${JSON.stringify(harness.projB)}`,
					"_yen_ide_start_detect",
					// Wait for the newest detect job to exit (bounded at 5s) instead of a
					// fixed sleep: an interactive zsh under load routinely needs >250ms.
					'for _ in {1..200}; do kill -0 "$_YEN_IDE_DETECT_PID" 2>/dev/null || break; sleep 0.025; done',
					"_yen_ide_apply_detect",
					'printf "root=%s\\n" "$YEN_PROJECT_ROOT"',
					'printf "loaded=%s\\n" "$LOADED_FOR"',
				].join("\n"),
			],
			{
				encoding: "utf8",
				env,
			},
		),
	};
}

function runShellDetectWithStalePidFile(shell: "bash" | "zsh") {
	const harness = createShellDetectRaceHarness(shell);
	const detectTmp = join(harness.binDir, "..", "tmp");
	mkdirSync(detectTmp, { recursive: true });
	const env = {
		...process.env,
		TMPDIR: detectTmp,
		YEN_BIN_DIR: harness.binDir,
		YEN_IDE_AUTO_ENV: "1",
		YEN_RESOURCES_DIR: harness.resourcesDir,
		YEN_WELCOME_SHOWN: "1",
	};

	if (shell === "bash") {
		return {
			...harness,
			result: spawnSync(
				"bash",
				[
					"--noprofile",
					"--norc",
					"-ic",
					[
						`printf 'zsh: command not found: stale\\n' > "$TMPDIR/yen-ide-detect-$$-1.env"`,
						`source ${JSON.stringify(join(harness.shellDir, "yen-integration.bash"))} >/dev/null`,
						`cd ${JSON.stringify(harness.projB)}`,
						"__yen_ide_start_detect",
						// Await the async result instead of assuming an unloaded host finishes in 80 ms.
						`for attempt in {1..200}; do __yen_ide_apply_detect; [[ "$YEN_PROJECT_ROOT" == ${JSON.stringify(harness.projB)} ]] && break; sleep 0.01; done`,
						`if [[ -e "$TMPDIR/yen-ide-detect-$$-1.env" ]]; then printf "stale_exists=yes\\n"; else printf "stale_exists=no\\n"; fi`,
						'printf "root=%s\\n" "$YEN_PROJECT_ROOT"',
					].join("\n"),
				],
				{
					encoding: "utf8",
					env,
				},
			),
		};
	}

	return {
		...harness,
		result: spawnSync(
			"zsh",
			[
				"-fic",
				[
					`printf 'zsh: command not found: stale\\n' > "$TMPDIR/yen-ide-detect-$$-1.env"`,
					`source ${JSON.stringify(join(harness.shellDir, "yen-integration.zsh"))} >/dev/null`,
					"_yen_deferred_init >/dev/null",
					`cd ${JSON.stringify(harness.projB)}`,
					"_yen_ide_start_detect",
					`for attempt in {1..200}; do _yen_ide_apply_detect; [[ "$YEN_PROJECT_ROOT" == ${JSON.stringify(harness.projB)} ]] && break; sleep 0.01; done`,
					`if [[ -e "$TMPDIR/yen-ide-detect-$$-1.env" ]]; then print -r -- "stale_exists=yes"; else print -r -- "stale_exists=no"; fi`,
					'printf "root=%s\\n" "$YEN_PROJECT_ROOT"',
				].join("\n"),
			],
			{
				encoding: "utf8",
				env,
			},
		),
	};
}

function runShellDetectRejectsMalformedOutput(shell: "bash" | "zsh") {
	const harness = createShellDetectRaceHarness(shell);
	writeFileSync(
		join(harness.binDir, "yen"),
		[
			"#!/bin/bash",
			'if [[ "$1" == "ide" && "$2" == "detect" ]]; then',
			'  printf "zsh: command not found: stale\\n"',
			"  exit 0",
			"fi",
			"exit 1",
			"",
		].join("\n"),
		"utf8",
	);
	chmodSync(join(harness.binDir, "yen"), 0o755);

	const detectTmp = join(harness.binDir, "..", "tmp");
	mkdirSync(detectTmp, { recursive: true });
	const env = {
		...process.env,
		TMPDIR: detectTmp,
		YEN_BIN_DIR: harness.binDir,
		YEN_IDE_AUTO_ENV: "0",
		YEN_RESOURCES_DIR: harness.resourcesDir,
		YEN_WELCOME_SHOWN: "1",
	};

	if (shell === "bash") {
		return {
			...harness,
			result: spawnSync(
				"bash",
				[
					"--noprofile",
					"--norc",
					"-ic",
					[
						`source ${JSON.stringify(join(harness.shellDir, "yen-integration.bash"))} >/dev/null`,
						"__yen_ide_start_detect",
						"sleep 0.04",
						"__yen_ide_apply_detect",
						'printf "root=%s\\n" "${YEN_PROJECT_ROOT:-}"',
					].join("\n"),
				],
				{
					encoding: "utf8",
					env,
				},
			),
		};
	}

	return {
		...harness,
		result: spawnSync(
			"zsh",
			[
				"-fic",
				[
					`source ${JSON.stringify(join(harness.shellDir, "yen-integration.zsh"))} >/dev/null`,
					"_yen_deferred_init >/dev/null",
					"_yen_ide_start_detect",
					"sleep 0.04",
					"_yen_ide_apply_detect",
					'printf "root=%s\\n" "${YEN_PROJECT_ROOT:-}"',
				].join("\n"),
			],
			{
				encoding: "utf8",
				env,
			},
		),
	};
}

describe("IDE S2 controls", () => {
	test("ide command includes doctor/lsp/ast/devcontainer/vscode/debug plus verify/merge-readiness/benchmark/gate/pr-review/workflow/timeline/search/non-interference control planes", () => {
		const ide = readFileSync(ideCommandPath, "utf8");
		const helperSources = [
			ideCommonModulePath,
			ideWorkspaceIdentityModulePath,
			ideStateTrustModulePath,
			ideTimelineModulePath,
			ideReportsModulePath,
		]
			.map((path) => readFileSync(path, "utf8"))
			.join("\n");
		const languageIntelSources = [ideLspModulePath, ideAstModulePath]
			.map((path) => readFileSync(path, "utf8"))
			.join("\n");
		const executionSources = [
			ideVerifyTestModulePath,
			ideWorkflowQualityModulePath,
			ideQualityModulePath,
		]
			.map((path) => readFileSync(path, "utf8"))
			.join("\n");
		const workspaceSources = [
			ideEnvModulePath,
			ideWorkspaceSummaryModulePath,
			ideWorkspaceDoctorModulePath,
			ideWorkspaceTrustModulePath,
			ideWorkspaceCapabilitiesModulePath,
			ideDevcontainerModulePath,
			ideShareModulePath,
			ideVscodeModulePath,
			ideSearchHistoryModulePath,
			ideReviewContextModulePath,
			ideEditorHandoffModulePath,
			ideDebugTargetsModulePath,
			ideDebugUiModulePath,
			ideDebuggerModulePath,
			ideBenchmarkModulePath,
		]
			.map((path) => readFileSync(path, "utf8"))
			.join("\n");
		expect(workspaceSources).toContain("cmd_detect()");
		expect(workspaceSources).toContain("cmd_doctor()");
		expect(languageIntelSources).toContain("cmd_lsp()");
		expect(languageIntelSources).toContain("cmd_ast()");
		expect(workspaceSources).toContain("cmd_env()");
		expect(workspaceSources).toContain("cmd_devcontainer()");
		expect(workspaceSources).toContain("cmd_share()");
		expect(workspaceSources).toContain("cmd_vscode()");
		expect(workspaceSources).toContain("cmd_explain()");
		expect(executionSources).toContain("cmd_test()");
		expect(executionSources).toContain("cmd_verify()");
		expect(executionSources).toContain("cmd_quality_action()");
		expect(workspaceSources).toContain("cmd_merge_readiness()");
		expect(ide).toContain("cmd_gate()");
		expect(ide).toContain("cmd_pr_review()");
		expect(executionSources).toContain("cmd_workflow()");
		expect(ide).toContain("write_pr_decision_template()");
		expect(ide).toContain("submit_pr_decision()");
		expect(ide).toContain("cmd_timeline()");
		expect(workspaceSources).toContain("cmd_history()");
		expect(workspaceSources).toContain("cmd_replay()");
		expect(workspaceSources).toContain("cmd_profile()");
		expect(workspaceSources).toContain("cmd_open()");
		expect(workspaceSources).toContain("cmd_debug()");
		expect(workspaceSources).toContain("cmd_benchmark()");
		expect(workspaceSources).toContain("cmd_ports()");
		expect(workspaceSources).toContain("cmd_parse()");
		expect(workspaceSources).toContain("cmd_search()");
		expect(ide).toContain("cmd_non_interference()");
		expect(helperSources).toContain("timeline_log()");
		expect(ide).toContain("policy_mode_for_root()");
		expect(ide).toContain("classify_risk()");
	});

	test("phase 6 modularization router loads modules and asserts exported handler contracts before command definitions", () => {
		const ide = readFileSync(ideCommandPath, "utf8");
		const bootstrap = readFileSync(ideBootstrapModulePath, "utf8");
		const common = readFileSync(ideCommonModulePath, "utf8");
		const workspaceIdentity = readFileSync(
			ideWorkspaceIdentityModulePath,
			"utf8",
		);
		const stateTrust = readFileSync(ideStateTrustModulePath, "utf8");
		const timeline = readFileSync(ideTimelineModulePath, "utf8");
		const reports = readFileSync(ideReportsModulePath, "utf8");
		const lsp = readFileSync(ideLspModulePath, "utf8");
		const ast = readFileSync(ideAstModulePath, "utf8");
		const verifyTest = readFileSync(ideVerifyTestModulePath, "utf8");
		const workflowQuality = readFileSync(ideWorkflowQualityModulePath, "utf8");
		const quality = readFileSync(ideQualityModulePath, "utf8");
		const envModule = readFileSync(ideEnvModulePath, "utf8");
		const workspaceSummary = readFileSync(
			ideWorkspaceSummaryModulePath,
			"utf8",
		);
		const workspaceDoctor = readFileSync(ideWorkspaceDoctorModulePath, "utf8");
		const workspaceTrust = readFileSync(ideWorkspaceTrustModulePath, "utf8");
		const workspaceCapabilities = readFileSync(
			ideWorkspaceCapabilitiesModulePath,
			"utf8",
		);
		const devcontainerModule = readFileSync(ideDevcontainerModulePath, "utf8");
		const shareModule = readFileSync(ideShareModulePath, "utf8");
		const vscodeModule = readFileSync(ideVscodeModulePath, "utf8");
		const searchHistory = readFileSync(ideSearchHistoryModulePath, "utf8");
		const editorHandoff = readFileSync(ideEditorHandoffModulePath, "utf8");
		const debugExecution = readFileSync(ideDebugExecutionModulePath, "utf8");
		const debugTargets = readFileSync(ideDebugTargetsModulePath, "utf8");
		const debugUi = readFileSync(ideDebugUiModulePath, "utf8");
		const debuggerModule = readFileSync(ideDebuggerModulePath, "utf8");
		const benchmark = readFileSync(ideBenchmarkModulePath, "utf8");
		const loadIndex = ide.indexOf('ide_require_module "bootstrap"');
		const phase2Index = ide.indexOf("ide_require_phase2_modules()");
		const phase3Index = ide.indexOf("ide_require_phase3_modules()");
		const phase4Index = ide.indexOf("ide_require_phase4_modules()");
		const phase5Index = ide.indexOf("ide_require_phase5_modules()");
		const contractAssertionIndex = ide.indexOf("ide_assert_phase_contracts");
		const firstCommandDefinitionIndex = ide.indexOf("show_help() {");
		const routerDefinitionIndex = ide.indexOf("ide_require_command_modules(");

		expect(ide).toContain('IDE_MODULE_DIR="${YEN_LIB}/ide"');
		expect(ide).toContain("ide_require_module()");
		expect(ide).toContain("ide_require_module_list()");
		expect(ide).toContain("ide_require_command_modules()");
		// The router is invoked once at top level with the raw subcommand; the old
		// unconditional phase2-5 eager block is replaced by this single call.
		expect(ide).toContain('ide_require_command_modules "${1:-}"');
		// A trivial light command must route to a curated superset, not the full
		// suite: `ports`/`profile` load history/timeline foundations without the
		// heavy debugger/lsp/ast modules.
		expect(ide).toContain("ports|profile)");
		expect(ide).toContain(
			"ide_require_module_list common workspace-identity state-trust timeline search-history",
		);
		// The router definition must precede the first command definition so the
		// modules its `*)` fallthrough asserts are loaded before dispatch.
		expect(routerDefinitionIndex).toBeGreaterThan(-1);
		expect(routerDefinitionIndex).toBeLessThan(firstCommandDefinitionIndex);
		// The eager top-level phase2-5 + assert block is gone: phase5 is only ever
		// called from inside the router's `*)` branch now, never immediately
		// followed by the assert-then-is_number_value top-level sequence. Kept
		// formatting-tolerant by matching the module-name boundary that used to
		// sit directly above `is_number_value`.
		expect(ide).not.toContain(
			"ide_require_phase5_modules\nide_assert_phase_contracts\n\nis_number_value",
		);
		expect(ide).toContain("ide_require_phase1_modules()");
		expect(ide).toContain("ide_require_phase2_modules()");
		expect(ide).toContain("ide_require_phase3_modules()");
		expect(ide).toContain("ide_require_phase4_modules()");
		expect(ide).toContain("ide_require_phase5_modules()");
		expect(ide).toContain("ide_assert_loaded_function()");
		expect(ide).toContain("ide_assert_phase_contracts()");
		expect(ide).toContain(
			"IDE module contract missing required function: ${function_name}",
		);
		expect(loadIndex).toBeGreaterThan(-1);
		expect(phase2Index).toBeGreaterThan(-1);
		expect(phase3Index).toBeGreaterThan(-1);
		expect(phase4Index).toBeGreaterThan(-1);
		expect(phase5Index).toBeGreaterThan(-1);
		expect(contractAssertionIndex).toBeGreaterThan(-1);
		expect(firstCommandDefinitionIndex).toBeGreaterThan(-1);
		expect(loadIndex).toBeLessThan(firstCommandDefinitionIndex);
		expect(phase2Index).toBeLessThan(firstCommandDefinitionIndex);
		expect(phase3Index).toBeLessThan(firstCommandDefinitionIndex);
		expect(phase4Index).toBeLessThan(firstCommandDefinitionIndex);
		expect(phase5Index).toBeLessThan(firstCommandDefinitionIndex);
		expect(contractAssertionIndex).toBeLessThan(firstCommandDefinitionIndex);

		expect(bootstrap).toContain('IDE_BOOTSTRAP_MODULE_API_VERSION="1"');
		expect(bootstrap).toContain('IDE_BOOTSTRAP_MODULE_NAME="bootstrap"');
		expect(bootstrap).toContain("ide_bootstrap_assert_compatible()");
		expect(common).toContain("ensure_state_dirs()");
		expect(common).toContain("is_pid_running()");
		expect(common).toContain("canonicalize_path()");
		expect(common).toContain("detect_runtime_context()");
		expect(workspaceIdentity).toContain("workspace_identity_parse_target()");
		expect(workspaceIdentity).toContain(
			"workspace_identity_set_resolved_root()",
		);
		expect(workspaceIdentity).toContain("workspace_hash_seed_for_root()");
		expect(workspaceIdentity).toContain("workspace_trust_key_for_root()");
		expect(stateTrust).toContain("trust_registry_add()");
		expect(stateTrust).toContain("project_hash()");
		expect(stateTrust).toContain("project_hash_for_root()");
		expect(stateTrust).toContain("project_hash_seed_for_root()");
		expect(stateTrust).toContain("project_short_hash_for_root()");
		expect(stateTrust).toContain("project_trust_key_for_root()");
		expect(stateTrust).toContain("pr_seen_file()");
		expect(timeline).toContain("timeline_log()");
		expect(reports).toContain("report_snapshot_from_timeline_line()");
		expect(reports).toContain("doctor_snapshot_value()");
		expect(lsp).toContain("lsp_force_placeholder()");
		expect(lsp).toContain("cmd_lsp()");
		expect(ast).toContain("ast_supported_language()");
		expect(ast).toContain("cmd_ast()");
		expect(verifyTest).toContain("verify_test_runner_rows_for_root()");
		expect(verifyTest).toContain("cmd_test()");
		expect(verifyTest).toContain("cmd_verify()");
		expect(workflowQuality).toContain("workflow_native_discovery_json()");
		expect(workflowQuality).toContain("cmd_workflow()");
		expect(quality).toContain("quality_action_status_json()");
		expect(quality).toContain("cmd_quality_action()");
		expect(envModule).toContain("cmd_env()");
		expect(envModule).toContain("collect_env_files()");
		expect(workspaceSummary).toContain("cmd_detect()");
		expect(workspaceSummary).toContain("workspace_summary_resolve_target()");
		expect(workspaceDoctor).toContain("cmd_doctor()");
		expect(workspaceDoctor).toContain("doctor_collect_snapshot()");
		expect(workspaceTrust).toContain("cmd_trust()");
		expect(workspaceTrust).toContain("cmd_merge_readiness()");
		expect(workspaceCapabilities).toContain("cmd_explain()");
		expect(workspaceCapabilities).toContain("explain_status_hint()");
		expect(devcontainerModule).toContain("cmd_devcontainer()");
		expect(devcontainerModule).toContain("cmd_devcontainer_status()");
		expect(shareModule).toContain("cmd_share()");
		expect(shareModule).toContain("share_finalize_session_locked()");
		expect(vscodeModule).toContain("cmd_vscode()");
		expect(vscodeModule).toContain("cmd_vscode_inventory()");
		expect(searchHistory).toContain("cmd_history()");
		expect(searchHistory).toContain("append_semantic_reference_report()");
		expect(searchHistory).toContain("cmd_search()");
		expect(editorHandoff).toContain("cmd_open()");
		expect(editorHandoff).toContain("editor_handoff_build_plan()");
		expect(debugExecution).toContain("debug_execution_target_normalize()");
		expect(debugExecution).toContain(
			"debug_devcontainer_context_json_for_root()",
		);
		expect(debugTargets).toContain("debug_resolve_plan()");
		expect(debugTargets).toContain("debug_status_resolve_root()");
		expect(debugTargets).toContain("debug_status_json_for_root()");
		expect(debugUi).toContain("debug_tui_json_for_root()");
		expect(debugUi).toContain("cmd_debug_tui()");
		expect(debuggerModule).toContain("cmd_debug()");
		expect(benchmark).toContain("cmd_benchmark()");
		expect(benchmark).toContain("benchmark_run_json_for_root()");
	});

	test("yen ide help advertises doctor/lsp/ast/devcontainer/vscode/debug plus editor handoff/verify/merge-readiness/benchmark/gate/pr-review/workflow/timeline/search/non-interference", () => {
		const res = runYen(["ide", "--help"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(0);
		expect(output).toContain("doctor [path|ssh://user@host/abs/path]");
		expect(output).toContain(
			"Aggregate repo health across detect/env/lsp/devcontainer/verify",
		);
		expect(output).toContain(
			"--format text|env|json; includes latest verify/security readiness; --strict fails when warnings remain",
		);
		expect(output).toContain("lsp [options]");
		expect(output).toContain(
			"start/status/stop [path] manage the local project LSP runtime",
		);
		expect(output).toContain(
			"hover/definition/references <file:line[:col]> query live LSP responses",
		);
		expect(output).toContain(
			"rename <file:line[:col]> --new-name <value> [--write] previews/applies rename edits",
		);
		expect(output).toContain(
			"install status|install|update [language] manages pinned reference-server installs/guidance",
		);
		expect(output).toContain(
			"diagnostics [path] [--severity levels --limit N] shows grouped diagnostics snapshot output",
		);
		expect(output).toContain("status [path] [--format text|env]");
		expect(output).toContain(
			"trusted lists project roots approved for future LSP execution",
		);
		expect(output).toContain("ast [options]");
		expect(output).toContain(
			"Syntax-aware fallback/complement for Python, JS/TS, Go, and Swift projects",
		);
		expect(output).toContain(
			"definition/references <symbol> [path] label results as AST-sourced and print the active parser engine",
		);
		expect(output).toContain("devcontainer [options]");
		expect(output).toContain("up/status/shell/down plus trust/untrust/trusted");
		expect(output).toContain(
			"ssh targets support remote status/up/shell/down/trust/untrust via the remote CLI with local-record trust and tracked state keyed by workspace identity",
		);
		expect(output).toContain("vscode [options]");
		expect(output).toContain(
			"import [path] [--dry-run] writes .yen/vscode-import/*",
		);
		expect(output).toContain("verify [options]");
		expect(output).toContain(
			"run [--quick] [--no-build] [--no-security] [--strict] [--watch --watch-interval <sec> --max-runs <N>] writes summary/details/semantic reports + flaky tracker updates",
		);
		expect(output).toContain("merge-readiness [path]");
		expect(output).toContain(
			"Read-only merge readiness report over local verify/trust/git/PR state",
		);
		expect(output).toContain("benchmark [options]");
		expect(output).toContain(
			"Repeatable search/LSP/verify/orchestration benchmark harness",
		);
		expect(output).toContain("open <path:line[:col]>");
		expect(output).toContain("Open a semantic location in the user's editor");
		expect(output).toContain("debug [options]");
		expect(output).toContain(
			"Shared debugger status/trust summary plus local + ssh execution baseline",
		);
		expect(output).toContain(
			"status [path|ssh://user@host/abs/path] [--devcontainer] [--format text|json] shows trust, supported families, and latest debug state",
		);
		expect(output).toContain(
			"start <path:line[:col]|executable> [--project <path>] [--tool auto|python-pdb|node-inspect|lldb]",
		);
		expect(output).toContain(
			"[--managed] [--devcontainer] [--dry-run --format text|json] [-- args...] launches the selected local, ssh-backed, or tracked devcontainer debugger",
		);
		expect(output).toContain(
			"tui [path|ssh://user@host/abs/path] [--devcontainer] [--tail N] [--watch --interval N] renders the debugger dashboard over the shared session/transcript state",
		);
		expect(output).toContain(
			"continue|next|step|out|stack|inspect control a live managed session for the selected local, ssh-backed, or tracked devcontainer project",
		);
		expect(output).toContain(
			"breakpoint add|list|remove and watch add|list|remove manage live managed-session state",
		);
		expect(output).toContain(
			"transcript [path] [--tail N] prints the latest managed debug transcript",
		);
		expect(output).toContain("gate [options] -- <cmd>");
		expect(output).toContain("pr-review [options] [pr]");
		expect(output).toContain("--loop key-driven review");
		expect(output).toContain("--decision <approve|request-changes|comment>");
		expect(output).toContain(
			"--evidence writes markdown with latest verify/security snapshot",
		);
		expect(output).toContain(
			"--ci-status shows current-branch CI and latest local build-watch progress; --max-polls <N> bounds watch loops",
		);
		expect(output).toContain("workflow [options]");
		expect(output).toContain(
			"run <name> keeps authored workflows authoritative; run --native <task-id> [--watch --watch-interval <sec> --max-runs <N>] executes one discovered native task explicitly",
		);
		expect(output).toContain(
			"ssh targets now support explicit remote workflow/native-task execution plus trust/untrust; --watch stays local-only and risk metadata stays remote-probe-driven",
		);
		expect(output).toContain("timeline [options]");
		expect(output).toContain("search <query> [options]");
		expect(output).toContain(
			"--sources files,symbols,content,diagnostics,history,actions",
		);
		expect(output).toContain("non-interference [options]");
	});

	test(
		"fixed ide smoke matrix stays runnable across help and status-style families",
		() => {
			const stateDir = ideTemp("yen-ide-smoke-state-");
			const project = createIdeSmokeProject("yen-ide-smoke-project-");
			const env = { YEN_IDE_STATE_DIR: stateDir };
			const smokeCases = [
				{
					args: ["ide", "--help"],
					expectedStatus: 0,
					expectedText: "Usage: yen ide <command> [options]",
				},
				{
					args: ["ide", "doctor", "--format", "json", project],
					expectedStatus: 0,
					expectedText: '"status": "warning"',
				},
				{
					args: ["ide", "trust", "status", project, "--format", "json"],
					expectedStatus: 0,
					expectedText: '"capabilities": {',
				},
				{
					args: ["ide", "lsp", "status", project, "--format", "env"],
					expectedStatus: 0,
					expectedText: "export YEN_IDE_LSP_ROOT=",
				},
				{
					args: [
						"ide",
						"workflow",
						"discover",
						"--project",
						project,
						"--format",
						"json",
					],
					expectedStatus: 0,
					expectedText: '"schemaVersion": 1',
				},
				{
					args: ["ide", "verify", "status", project, "--format", "json"],
					expectedStatus: 0,
					expectedText: '"readiness": {',
				},
				{
					args: ["ide", "merge-readiness", project, "--format", "json"],
					expectedStatus: 0,
					expectedText: '"summary": {',
				},
				{
					args: ["ide", "benchmark", "status", project, "--format", "json"],
					expectedStatus: 0,
					expectedText: '"latestAvailable": false',
				},
				{
					args: [
						"ide",
						"open",
						"Makefile:1:1",
						"--project",
						project,
						"--editor",
						"code --reuse-window",
						"--dry-run",
						"--format",
						"json",
					],
					expectedStatus: 0,
					expectedText: '"family": "code-family"',
				},
				{
					args: [
						"ide",
						"test",
						"status",
						"--project",
						project,
						"--format",
						"json",
					],
					expectedStatus: 0,
					expectedText: '"summary": {',
				},
				{
					args: [
						"ide",
						"debug",
						"tui",
						"--project",
						project,
						"--format",
						"json",
					],
					expectedStatus: 0,
					expectedText: '"mode": "debug-tui"',
				},
			];

			for (const smokeCase of smokeCases) {
				const res = runYen(smokeCase.args, env, repoRoot);
				const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
				expect(res.status).toBe(smokeCase.expectedStatus);
				expect(output).toContain(smokeCase.expectedText);
			}
		},
		// Eleven separate CLI smoke invocations take ~14s on the supported macOS
		// runner; keep a bounded budget while avoiding load-sensitive false failures.
		{ timeout: 25_000 },
	);

	test(
		"merge-readiness reports a no-PR snapshot without inventing a second trust surface",
		() => {
			const stateDir = ideTemp("yen-ide-merge-ready-");
			const project = createIdeSmokeProject("yen-ide-merge-project-");
			const env = { YEN_IDE_STATE_DIR: stateDir };

			const res = runYen(
				["ide", "merge-readiness", project, "--format", "json"],
				env,
				repoRoot,
			);
			const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
			expect(res.status).toBe(0);
			expect(output).toContain('"schemaVersion": 1');
			expect(output).toContain('"available": false');
			expect(output).toContain('"reason":');
			expect(output).toContain('"summary": {');
			expect(output).toContain('"status": "needs human check"');
			expect(output).toContain('"verify": {');
			expect(output).toContain('"trust": {');
			expect(output).toContain('"gate": {');
		},
		{ timeout: 15_000 },
	);

	test(
		"merge-readiness keeps rename status entries on the new path while preserving fromPath metadata",
		() => {
			const stateDir = ideTemp("yen-ide-merge-rename-");
			const project = createGitRenameProject("yen-ide-merge-rename-project-");
			const env = { YEN_IDE_STATE_DIR: stateDir };

			const res = runYen(
				["ide", "merge-readiness", project, "--format", "json"],
				env,
				repoRoot,
			);
			const output = `${res.stdout ?? ""}`.trim();
			expect(res.status).toBe(0);

			const payload = JSON.parse(output);
			expect(payload.git.workingTree.entries).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						code: "R ",
						path: "scripts/new task.sh",
						fromPath: "scripts/old task.sh",
					}),
				]),
			);
			expect(payload.git.changedPaths).toEqual(
				expect.arrayContaining(["scripts/new task.sh", "scripts/old task.sh"]),
			);
			expect(payload.git.riskyFiles).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						path: "scripts/new task.sh",
						tags: expect.arrayContaining(["shell"]),
					}),
				]),
			);
		},
		{ timeout: 15_000 },
	);

	test(
		"merge-readiness enriches risky files with review routing hints",
		() => {
			const stateDir = ideTemp("yen-ide-merge-review-");
			const project = createMergeReadinessReviewProject(
				"yen-ide-merge-review-project-",
			);
			const env = { YEN_IDE_STATE_DIR: stateDir };

			const jsonRes = runYen(
				["ide", "merge-readiness", project, "--format", "json"],
				env,
				repoRoot,
			);
			expect(jsonRes.status).toBe(0);
			const payload = JSON.parse(`${jsonRes.stdout ?? ""}`.trim());
			expect(payload.summary.ownerHints).toBeGreaterThan(0);
			expect(payload.reviewContext).toEqual(
				expect.objectContaining({
					available: true,
				}),
			);
			expect(payload.git.riskyFiles).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						path: "scripts/deploy.sh",
						reviewContext: expect.objectContaining({
							owners: expect.arrayContaining(["@release-team"]),
						}),
					}),
				]),
			);

			const textRes = runYen(
				["ide", "merge-readiness", project],
				env,
				repoRoot,
			);
			const textOutput = `${textRes.stdout ?? ""}\n${textRes.stderr ?? ""}`;
			expect(textRes.status).toBe(0);
			expect(textOutput).toContain("Review Routing:");
			expect(textOutput).toContain("scripts/deploy.sh");
			expect(textOutput).toContain("@release-team");
		},
		{ timeout: 30_000 },
	);

	test(
		"merge-readiness only surfaces debug routing for risky targets the shipped debugger baseline can launch",
		() => {
			const stateDir = ideTemp("yen-ide-merge-debug-");
			const project = createMergeReadinessDebugProject(
				"yen-ide-merge-debug-project-",
			);
			const env = { YEN_IDE_STATE_DIR: stateDir };

			const jsonRes = runYen(
				["ide", "merge-readiness", project, "--format", "json"],
				env,
				repoRoot,
			);
			expect(jsonRes.status).toBe(0);
			const payload = JSON.parse(`${jsonRes.stdout ?? ""}`.trim());
			expect(payload.summary.debuggableReviewTargets).toBeGreaterThan(0);
			expect(payload.reviewContext.paths).toEqual(
				expect.arrayContaining([
					expect.objectContaining({
						path: "app.js",
						debugHandoff: expect.objectContaining({
							tool: "node-inspect",
							command: expect.stringContaining("yen ide debug start 'app.js'"),
							trustRequired: true,
						}),
					}),
				]),
			);

			const textRes = runYen(
				["ide", "merge-readiness", project],
				env,
				repoRoot,
			);
			const textOutput = `${textRes.stdout ?? ""}\n${textRes.stderr ?? ""}`;
			expect(textRes.status).toBe(0);
			expect(textOutput).toContain("Review Routing:");
			expect(textOutput).toContain("app.js owners=@runtime-team");
			expect(textOutput).toContain("debug: yen ide debug start 'app.js'");
			expect(textOutput).toContain("trust: yen ide debug trust");
		},
		{ timeout: 30_000 },
	);

	test("shell integrations wire ?? shortcut and auto IDE context defaults", () => {
		const zsh = readFileSync(zshIntegrationPath, "utf8");
		const bash = readFileSync(bashIntegrationPath, "utf8");

		expect(zsh).toContain("alias '??'='noglob yenwhy'");
		expect(zsh).toContain(': "${YEN_IDE_AUTO_CONTEXT:=1}"');
		expect(zsh).toContain(': "${YEN_IDE_AUTO_HISTORY:=0}"');
		expect(zsh).toContain(': "${YEN_IDE_AUTO_ENV:=0}"');
		expect(zsh).toContain("ide detect --cached --format env");

		expect(bash).toContain("alias '??'='yenwhy'");
		expect(bash).toContain(': "${YEN_IDE_AUTO_CONTEXT:=1}"');
		expect(bash).toContain(': "${YEN_IDE_AUTO_HISTORY:=0}"');
		expect(bash).toContain(': "${YEN_IDE_AUTO_ENV:=0}"');
		expect(bash).toContain("ide detect --cached --format env");

		// The preexec fallback must agree with the `:=0` initialization above.
		// `_yen_deferred_init` runs once per shell and then unregisters itself, so
		// a `:-1` fallback made `unset YEN_IDE_AUTO_HISTORY` silently re-enable
		// capture instead of restoring the documented opt-in default.
		expect(zsh).toContain('"${YEN_IDE_AUTO_HISTORY:-0}" == "1"');
		expect(bash).toContain('"${YEN_IDE_AUTO_HISTORY:-0}" == "1"');
		expect(zsh).not.toContain("YEN_IDE_AUTO_HISTORY:-1");
		expect(bash).not.toContain("YEN_IDE_AUTO_HISTORY:-1");
	});

	test("shell integrations keep the 1.3 prompt-hook parity we rely on", () => {
		const zsh = readFileSync(zshIntegrationPath, "utf8");
		const bash = readFileSync(bashIntegrationPath, "utf8");

		expect(bash).toContain("redraw=last;cl=line;aid=");
		expect(bash).toContain("builtin readonly __yen_ps0");
		expect(bash).toContain("PROMPT_COMMAND");
		expect(bash).toContain('local ret="${1:-$?}"');
		expect(bash).toContain(
			'builtin source "$(dirname -- "${BASH_SOURCE[0]}")/bash-preexec.sh"',
		);

		expect(zsh).toContain("133;A;cl=line");
		expect(zsh).toContain("133;B");
		expect(zsh).toContain("133;P;k=i");
	});

	test("bash shell detect applies only the newest async context result", () => {
		const { projB, result } = runShellDetectRace("bash");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain(`root=${projB}`);
		expect(output).toContain(`loaded=${projB}`);
	});

	test("zsh shell detect applies only the newest async context result", () => {
		const { projB, result } = runShellDetectRace("zsh");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain(`root=${projB}`);
		expect(output).toContain(`loaded=${projB}`);
	});

	test("bash shell detect clears stale PID temp files before startup detection", () => {
		const { projB, result } = runShellDetectWithStalePidFile("bash");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain("stale_exists=no");
		expect(output).toContain(`root=${projB}`);
		expect(output).not.toContain("command not found: zsh:");
	});

	test("zsh shell detect clears stale PID temp files before startup detection", () => {
		const { projB, result } = runShellDetectWithStalePidFile("zsh");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain("stale_exists=no");
		expect(output).toContain(`root=${projB}`);
		expect(output).not.toContain("command not found: zsh:");
	});

	test("bash shell detect ignores malformed async detect output", () => {
		const { result } = runShellDetectRejectsMalformedOutput("bash");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain("root=");
		expect(output).not.toContain("command not found: zsh:");
	});

	test("zsh shell detect ignores malformed async detect output", () => {
		const { result } = runShellDetectRejectsMalformedOutput("zsh");
		const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;

		expect(result.status).toBe(0);
		expect(output).toContain("root=");
		expect(output).not.toContain("command not found: zsh:");
	});

	test("gate policy disabled bypasses prompt path in non-interactive mode", () => {
		const res = runYen([
			"ide",
			"gate",
			"--policy",
			"disabled",
			"--dry-run",
			"--",
			"echo",
			"ok",
		]);
		expect(res.status).toBe(0);
	});

	test("profile preserves command exit code while still reporting profile output", () => {
		const res = runYen(["ide", "profile", "--", "bash", "-lc", "exit 7"]);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(7);
		expect(output).toContain("IDE Profile");
		expect(output).toContain("Exit status: 7");
	});
});
