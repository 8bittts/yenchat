import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
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

function createDevcontainerProject(prefix: string, unsafe = false) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"devcontainer-fixture"}\n',
		"utf8",
	);
	const specPath = join(root, ".devcontainer/devcontainer.json");
	mkdirSync(dirname(specPath), { recursive: true });
	if (unsafe) {
		writeFileSync(
			specPath,
			JSON.stringify(
				{
					name: "Unsafe Fixture",
					image: "mcr.microsoft.com/devcontainers/base:ubuntu",
					runArgs: ["--privileged"],
				},
				null,
				2,
			),
			"utf8",
		);
	} else {
		writeFileSync(
			specPath,
			`{
	// Safe fixture keeps comment-like text inside strings.
	"name": "Safe Fixture",
	"image": "mcr.microsoft.com/devcontainers/base:ubuntu",
	"workspaceFolder": "/workspace",
	"postCreateCommand": "printf 'keep // text'",
}
`,
			"utf8",
		);
	}
	return root;
}

function writeFakeDevcontainer(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
cmd="$1"
shift || true
case "$cmd" in
  up)
    echo '{"outcome":"success","workspaceFolder":"/workspace"}'
    ;;
  exec)
    workspace=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --workspace-folder)
          shift
          workspace="$1"
          ;;
        *)
          break
          ;;
      esac
      shift || true
    done
    if [[ "$1" == "true" ]]; then
      exit 0
    fi
    if [[ "$1" == "pwd" ]]; then
      echo "/workspace"
      exit 0
    fi
    "$@"
    ;;
  down)
    echo "stopped"
    ;;
esac
`,
		"utf8",
	);
	spawnSync("chmod", ["755", path]);
}

function createVSCodeProject(prefix: string) {
	const root = ideTemp(prefix);
	const vscodeDir = join(root, ".vscode");
	mkdirSync(vscodeDir, { recursive: true });
	writeFileSync(
		join(root, "package.json"),
		`${JSON.stringify(
			{
				name: "vscode-fixture",
				scripts: {
					test: "bun test",
					lint: "bun run lint",
				},
			},
			null,
			2,
		)}\n`,
		"utf8",
	);
	writeFileSync(
		join(vscodeDir, "keybindings.json"),
		`[
	// supported
	{ "key": "cmd+shift+p", "command": "workbench.action.showCommands" },
	{ "key": "cmd+alt+p", "command": "workbench.action.showCommands", "when": "editorTextFocus" },
	{ "key": "cmd+k", "command": "workbench.action.unsupported" },
]
`,
		"utf8",
	);
	writeFileSync(
		join(vscodeDir, "tasks.json"),
		`{
	"tasks": [
		{ "label": "Say \\"Hi\\"", "type": "shell", "command": "printf \\"hi\\"" },
		{
			"label": "Composite",
			"type": "shell",
			"command": "bun run lint",
			"dependsOn": ["Say \\"Hi\\""]
		},
	],
}
`,
		"utf8",
	);
	writeFileSync(
		join(vscodeDir, "settings.json"),
		`{
	// comments + strings that contain // must survive parsing
	"editor.tabSize": 2,
	"terminal.integrated.defaultProfile.osx": "zsh",
	"workbench.colorTheme": "YEN // theme",
}
`,
		"utf8",
	);
	writeFileSync(
		join(vscodeDir, "sample.code-snippets"),
		`{
	"hello": {
		"prefix": "hello",
		"body": ["echo // not comment"],
		"description": "hello /* keep */ snippet",
	},
}
`,
		"utf8",
	);
	writeFileSync(
		join(vscodeDir, "extensions.json"),
		`{
	"recommendations": [
		"ms-vscode-remote.remote-containers",
		"github.vscode-pull-request-github",
		"ms-vscode.js-debug-nightly",
	],
	"unwantedRecommendations": ["vscodevim.vim"],
}
`,
		"utf8",
	);
	return root;
}

function createPythonProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "pyproject.toml"),
		"[project]\nname = 'ast-fixture'\n",
		"utf8",
	);
	const sourcePath = join(root, "app/main.py");
	mkdirSync(dirname(sourcePath), { recursive: true });
	writeFileSync(
		sourcePath,
		"class Widget:\n    pass\n\n\ndef build_widget():\n    return Widget()\n",
		"utf8",
	);
	return { root, sourcePath };
}

function parseJsonFromMixedOutput(output: string) {
	const start = output.indexOf("{");
	expect(start).toBeGreaterThanOrEqual(0);
	return JSON.parse(output.slice(start));
}

describe("IDE S3D devcontainer/vscode plus AST fallback", () => {
	test("devcontainer trust, unsafe gating, status, shell, and down use the reference CLI wrapper", () => {
		const stateDir = ideTemp("yen-ide-devcontainer-state-");
		const safeProject = createDevcontainerProject("yen-ide-devcontainer-safe-");
		const unsafeProject = createDevcontainerProject(
			"yen-ide-devcontainer-unsafe-",
			true,
		);
		const fakeCli = join(stateDir, "fake-devcontainer");
		writeFakeDevcontainer(fakeCli);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_DEVCONTAINER_CMD: fakeCli,
		};

		const initial = runYen(
			["ide", "devcontainer", "status", "--project", safeProject],
			env,
		);
		const initialOutput = `${initial.stdout ?? ""}\n${initial.stderr ?? ""}`;
		expect(initial.status).toBe(0);
		expect(initialOutput).toContain("Supported:     yes");
		expect(initialOutput).toContain("Trusted:       no");

		const untrustedUp = runYen(
			["ide", "devcontainer", "up", "--project", safeProject],
			env,
		);
		expect(untrustedUp.status).toBe(1);

		expect(
			runYen(["ide", "devcontainer", "trust", safeProject], env).status,
		).toBe(0);
		expect(
			runYen(["ide", "devcontainer", "trust", unsafeProject], env).status,
		).toBe(0);

		const unsafeUp = runYen(
			["ide", "devcontainer", "up", "--project", unsafeProject],
			env,
		);
		const unsafeOutput = `${unsafeUp.stdout ?? ""}\n${unsafeUp.stderr ?? ""}`;
		expect(unsafeUp.status).toBe(1);
		expect(unsafeOutput).toContain("unsafe flags");

		const up = runYen(
			["ide", "devcontainer", "up", "--project", safeProject],
			env,
		);
		const upOutput = `${up.stdout ?? ""}\n${up.stderr ?? ""}`;
		expect(up.status).toBe(0);
		expect(upOutput).toContain("IDE Devcontainer Up");
		expect(upOutput).toContain("State:        running");

		const statusJson = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				safeProject,
				"--format",
				"json",
			],
			env,
		);
		const statusPayload = JSON.parse(statusJson.stdout ?? "{}");
		expect(statusJson.status).toBe(0);
		expect(statusPayload.supported).toBe(true);
		expect(statusPayload.trusted).toBe(true);
		expect(statusPayload.state).toBe("running");
		expect(statusPayload.health).toBe("healthy");

		const shell = runYen(
			["ide", "devcontainer", "shell", "--project", safeProject, "--", "pwd"],
			env,
		);
		expect(shell.status).toBe(0);
		expect(`${shell.stdout ?? ""}\n${shell.stderr ?? ""}`).toContain(
			"/workspace",
		);

		const untrust = runYen(
			["ide", "devcontainer", "untrust", safeProject],
			env,
		);
		const untrustOutput = `${untrust.stdout ?? ""}\n${untrust.stderr ?? ""}`;
		expect(untrust.status).toBe(0);
		expect(untrustOutput).toContain("Removed devcontainer trust:");

		const afterUntrust = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				safeProject,
				"--format",
				"json",
			],
			env,
		);
		const afterUntrustPayload = JSON.parse(afterUntrust.stdout ?? "{}");
		expect(afterUntrust.status).toBe(0);
		expect(afterUntrustPayload.trusted).toBe(false);
		expect(afterUntrustPayload.state).toBe("stopped");

		const blockedShell = runYen(
			["ide", "devcontainer", "shell", "--project", safeProject, "--", "pwd"],
			env,
		);
		expect(blockedShell.status).toBe(1);
	});

	test("vscode inventory/import classify and emit deterministic project-local artifacts", () => {
		const project = createVSCodeProject("yen-ide-vscode-project-");

		const inventory = runYen([
			"ide",
			"vscode",
			"inventory",
			"--project",
			project,
		]);
		const inventoryOutput = `${inventory.stdout ?? ""}\n${inventory.stderr ?? ""}`;
		expect(inventory.status).toBe(0);
		expect(inventoryOutput).toContain(
			"Keybindings supported=1 partial=1 unsupported=1",
		);
		expect(inventoryOutput).toContain(
			"Tasks       supported=1 partial=1 unsupported=0",
		);
		expect(inventoryOutput).toContain(
			"Settings    supported=1 partial=1 unsupported=1",
		);
		expect(inventoryOutput).toContain(
			"Snippets    supported=1 partial=0 unsupported=0",
		);
		expect(inventoryOutput).toContain("Ext recs:   recommended=3 unwanted=1");
		expect(inventoryOutput).toContain("Task parity: mapped=1 partial=1");
		expect(inventoryOutput).toContain("Test parity: native=1");
		expect(inventoryOutput).toContain(
			"Extensions  supported=1 partial=2 unsupported=0",
		);
		const inventoryJson = runYen([
			"ide",
			"vscode",
			"inventory",
			"--project",
			project,
			"--format",
			"json",
		]);
		expect(inventoryJson.status).toBe(0);
		const inventoryPayload = JSON.parse(inventoryJson.stdout ?? "{}");
		const realProject = realpathSync(project);
		expect(inventoryPayload.schemaVersion).toBe(1);
		expect(inventoryPayload.present).toBe(true);
		expect(inventoryPayload.artifacts.importDir).toBe(
			join(realProject, ".yen/vscode-import"),
		);
		expect(inventoryPayload.artifacts.workflowDir).toBe(
			join(realProject, ".yen/workflows"),
		);
		expect(inventoryPayload.summary).toEqual({
			supported: 5,
			partial: 5,
			unsupported: 2,
		});
		expect(inventoryPayload.migration.coverage).toEqual({
			extensions: "classified",
			taskParity: "derived",
			testParity: "derived",
			manualCleanupChecklist: "derived",
		});
		expect(inventoryPayload.migration.extensionRecommendations).toEqual({
			recommended: 3,
			unwanted: 1,
			unwantedRecommendations: ["vscodevim.vim"],
		});
		expect(inventoryPayload.migration.unsupportedInventory).toHaveLength(7);
		expect(inventoryPayload.categories.keybindings.supported).toHaveLength(1);
		expect(inventoryPayload.categories.keybindings.partial[0].reason).toBe(
			"conditional-when-clause",
		);
		expect(inventoryPayload.categories.tasks.partial).toHaveLength(1);
		expect(inventoryPayload.categories.tasks.partial[0].reason).toBe(
			"composite-or-editor-managed-task",
		);
		expect(inventoryPayload.categories.settings.unsupported).toHaveLength(1);
		expect(inventoryPayload.categories.settings.unsupported[0].reason).toBe(
			"editor-or-workbench-setting",
		);
		expect(inventoryPayload.categories.snippets.supported[0].body).toEqual([
			"echo // not comment",
		]);
		expect(inventoryPayload.categories.extensions.supported[0]).toMatchObject({
			id: "ms-vscode-remote.remote-containers",
			reason: "yen-devcontainer-built-in",
			migrationTarget: "yen ide devcontainer",
		});
		expect(inventoryPayload.categories.extensions.partial).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					id: "github.vscode-pull-request-github",
					reason: "yen-pr-review-baseline",
					migrationTarget: "yen ide pr-review",
				}),
				expect.objectContaining({
					id: "ms-vscode.js-debug-nightly",
					reason: "node-debugger-baseline",
					migrationTarget: "yen ide debug",
					manualAction: expect.stringContaining("yen ide debug status"),
				}),
			]),
		);
		expect(inventoryPayload.categories.extensions.unsupported).toHaveLength(0);
		expect(inventoryPayload.migration.taskParityNotes).toHaveLength(2);
		expect(inventoryPayload.migration.taskParityNotes[0]).toMatchObject({
			source: 'task:Say "Hi"',
			status: "mapped",
			migrationTarget: ".yen/workflows/vscode-task-say-hi.toml",
		});
		expect(inventoryPayload.migration.taskParityNotes[1]).toMatchObject({
			source: "task:Composite",
			status: "partial",
			repoSignal: "package.json:scripts.lint",
		});
		expect(inventoryPayload.migration.testParityNotes).toEqual([
			{
				source: "package.json:scripts.test",
				status: "native",
				reason: "repo-native-test-signal",
				detail:
					"The repo already exposes a native test command, so YEN can rely on verify/workflow without a VS Code test task.",
				migrationTarget: "yen ide verify --quick",
				repoSignal: "package.json:scripts.test",
				manualAction: "",
			},
		]);
		expect(inventoryPayload.migration.manualCleanupChecklist).toEqual([
			{
				id: "keybindings-manual-review",
				detail:
					"Review 2 keybinding(s) with VS Code-only context or unsupported commands before dropping the old editor setup.",
			},
			{
				id: "tasks-manual-review",
				detail:
					"Split or rewrite 1 VS Code task(s) before relying on them as YEN workflows.",
			},
			{
				id: "settings-manual-review",
				detail:
					"Recreate 2 VS Code setting(s) manually in YEN or the target editor.",
			},
			{
				id: "extensions-manual-review",
				detail:
					"Keep, replace, or drop 3 VS Code extension recommendation(s) manually; YEN does not fully cover them yet.",
			},
		]);

		const dryRun = runYen([
			"ide",
			"vscode",
			"import",
			"--project",
			project,
			"--dry-run",
		]);
		const dryRunOutput = `${dryRun.stdout ?? ""}\n${dryRun.stderr ?? ""}`;
		expect(dryRun.status).toBe(0);
		expect(dryRunOutput).toContain('"status": "create"');
		expect(dryRunOutput).toContain('"diff":');
		expect(dryRunOutput).toContain(".yen/vscode-import/keybindings.json");
		expect(dryRunOutput).toContain(".yen/vscode-import/migration-report.json");
		expect(dryRunOutput).toContain(".yen/vscode-import/manual-cleanup.txt");
		expect(dryRunOutput).toContain(".yen/workflows/vscode-task-say-hi.toml");
		expect(dryRunOutput).toContain("vscode-task-say-hi.toml (before)");
		const dryRunPayload = parseJsonFromMixedOutput(dryRun.stdout ?? "");
		expect(dryRunPayload.schemaVersion).toBe(1);
		expect(dryRunPayload.report.summary).toEqual(inventoryPayload.summary);
		expect(dryRunPayload.report.migration.coverage.extensions).toBe(
			"classified",
		);
		expect(dryRunPayload.report.migration.extensionRecommendations).toEqual(
			inventoryPayload.migration.extensionRecommendations,
		);
		expect(dryRunPayload.report.migration.taskParityNotes).toEqual(
			inventoryPayload.migration.taskParityNotes,
		);
		expect(dryRunPayload.report.migration.testParityNotes).toEqual(
			inventoryPayload.migration.testParityNotes,
		);
		expect(dryRunPayload.report.migration.manualCleanupChecklist).toEqual(
			inventoryPayload.migration.manualCleanupChecklist,
		);
		expect(dryRunPayload.writes).toHaveLength(6);

		const apply = runYen(["ide", "vscode", "import", "--project", project]);
		expect(apply.status).toBe(0);
		expect(
			existsSync(join(project, ".yen/vscode-import/keybindings.json")),
		).toBe(true);
		expect(existsSync(join(project, ".yen/vscode-import/settings.json"))).toBe(
			true,
		);
		expect(
			existsSync(join(project, ".yen/vscode-import/snippets/sample.json")),
		).toBe(true);
		expect(
			existsSync(join(project, ".yen/workflows/vscode-task-say-hi.toml")),
		).toBe(true);
		expect(
			existsSync(join(project, ".yen/vscode-import/migration-report.json")),
		).toBe(true);
		expect(
			existsSync(join(project, ".yen/vscode-import/manual-cleanup.txt")),
		).toBe(true);

		const second = runYen([
			"ide",
			"vscode",
			"import",
			"--project",
			project,
			"--dry-run",
		]);
		const secondOutput = `${second.stdout ?? ""}\n${second.stderr ?? ""}`;
		expect(second.status).toBe(0);
		expect(secondOutput).toContain('"status": "unchanged"');
		expect(
			readFileSync(
				join(project, ".yen/workflows/vscode-task-say-hi.toml"),
				"utf8",
			),
		).toContain('name = "Say \\"Hi\\""');
		expect(
			readFileSync(
				join(project, ".yen/workflows/vscode-task-say-hi.toml"),
				"utf8",
			),
		).toContain('step = "printf \\"hi\\""');
		expect(
			readFileSync(
				join(project, ".yen/vscode-import/snippets/sample.json"),
				"utf8",
			),
		).toContain("echo // not comment");
		expect(
			readFileSync(
				join(project, ".yen/vscode-import/migration-report.json"),
				"utf8",
			),
		).toContain('"manualCleanupChecklist"');
		expect(
			readFileSync(
				join(project, ".yen/vscode-import/manual-cleanup.txt"),
				"utf8",
			),
		).toContain("Manual cleanup still required");
		expect(
			readFileSync(
				join(project, ".yen/vscode-import/manual-cleanup.txt"),
				"utf8",
			),
		).toContain("Keep, replace, or drop 3 VS Code extension recommendation(s)");
	});

	test("ast status/definition/references provide syntax-aware fallback output for python projects", () => {
		const { root: project } = createPythonProject("yen-ide-ast-project-");

		const status = runYen(["ide", "ast", "status", "--project", project]);
		const statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(statusOutput).toContain("Supported: yes");
		expect(statusOutput).toContain("Source:    python-ast");

		const definition = runYen(["ide", "ast", "definition", "Widget", project]);
		const definitionOutput = `${definition.stdout ?? ""}\n${definition.stderr ?? ""}`;
		expect(definition.status).toBe(0);
		expect(definitionOutput).toContain("Source:    ast");
		expect(definitionOutput).toContain("app/main.py:1:7");

		const references = runYen(["ide", "ast", "references", "Widget", project]);
		const referencesOutput = `${references.stdout ?? ""}\n${references.stderr ?? ""}`;
		expect(references.status).toBe(0);
		expect(referencesOutput).toContain("app/main.py:1:7");
		expect(referencesOutput).toContain("app/main.py:6:12");
	});
});
