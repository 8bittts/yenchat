import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();

function createDetectCacheProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "a"), { recursive: true });
	mkdirSync(join(project, "b"), { recursive: true });
	writeFileSync(join(project, "package.json"), "{}\n", "utf8");
	return realpathSync(project);
}

function runDetectCacheProbe(
	projectRoot: string,
	commands: string,
	stateDir = ideTemp("yen-ide-detect-cache-state-"),
) {
	const script = `
set -euo pipefail
export IDE_STATE_DIR=${JSON.stringify(stateDir)}
export IDE_TRUST_FILE="$IDE_STATE_DIR/trusted-env-projects"
export IDE_HISTORY_DIR="$IDE_STATE_DIR/history"
export IDE_PROFILE_DIR="$IDE_STATE_DIR/profiles"
export IDE_BENCHMARK_DIR="$IDE_STATE_DIR/benchmarks"
export IDE_VERIFY_DIR="$IDE_STATE_DIR/verify"
export IDE_TEST_DIR="$IDE_STATE_DIR/test"
export IDE_QUALITY_DIR="$IDE_STATE_DIR/quality"
export IDE_EVIDENCE_DIR="$IDE_STATE_DIR/evidence"
export IDE_WORKFLOW_DIR="$IDE_STATE_DIR/workflows"
export IDE_LSP_DIR="$IDE_STATE_DIR/lsp"
export IDE_LSP_TOOLS_DIR="$IDE_STATE_DIR/lsp-tools"
export IDE_LSP_SOCKET_DIR="$IDE_STATE_DIR/lsp-sockets"
export IDE_DEVCONTAINER_DIR="$IDE_STATE_DIR/devcontainer"
export IDE_VSCODE_IMPORT_DIR="$IDE_STATE_DIR/vscode-import"
export IDE_SHARE_DIR="$IDE_STATE_DIR/share"
export IDE_WATCH_DIR="$IDE_STATE_DIR/watch"
export IDE_DEBUG_DIR="$IDE_STATE_DIR/debug"
export IDE_TIMELINE_FILE="$IDE_STATE_DIR/timeline.log"
export IDE_VERIFY_FLAKY_FILE="$IDE_VERIFY_DIR/flaky-ledger.tsv"
export IDE_NON_INTERFERENCE_SLO_FILE="$IDE_STATE_DIR/non-interference-slo.tsv"
export IDE_NON_INTERFERENCE_FREEZE_FILE="$IDE_STATE_DIR/non-interference-freeze"
export IDE_WORKFLOW_TRUST_FILE="$IDE_STATE_DIR/trusted-workflow-projects"
export IDE_LSP_TRUST_FILE="$IDE_STATE_DIR/trusted-lsp-projects"
export IDE_DEVCONTAINER_TRUST_FILE="$IDE_STATE_DIR/trusted-devcontainer-projects"
export IDE_SHARE_TRUST_FILE="$IDE_STATE_DIR/trusted-share-projects"
export IDE_DEBUG_TRUST_FILE="$IDE_STATE_DIR/trusted-debug-projects"

source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/common.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-identity.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/state-trust.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/env.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-summary.sh"))}

root=${JSON.stringify(projectRoot)}
ensure_state_dirs
${commands}
`;

	const result = spawnSync("bash", ["-lc", script], {
		cwd: repoRoot,
		encoding: "utf8",
	});

	return { result, stateDir };
}

test("cached detect invalidates when env trust changes", () => {
	const projectRoot = createDetectCacheProject("yen-ide-detect-cache-trust-");
	const { result, stateDir } = runDetectCacheProbe(
		projectRoot,
		[
			'first=$(cmd_detect --cached --format env "$root")',
			'trust_project "$root"',
			'second=$(cmd_detect --cached --format env "$root")',
			`first_trusted=$(printf "%s\\n" "$first" | sed -n "s/^export YEN_PROJECT_ENV_TRUSTED='\\\\(.*\\\\)'$/\\\\1/p" | head -n 1)`,
			`second_trusted=$(printf "%s\\n" "$second" | sed -n "s/^export YEN_PROJECT_ENV_TRUSTED='\\\\(.*\\\\)'$/\\\\1/p" | head -n 1)`,
			'FIRST_TRUSTED="$first_trusted" SECOND_TRUSTED="$second_trusted" python3 - <<\'PY\'',
			"import json",
			"import os",
			'print(json.dumps({"firstTrusted": os.environ.get("FIRST_TRUSTED", ""), "secondTrusted": os.environ.get("SECOND_TRUSTED", "")}))',
			"PY",
		].join("\n"),
	);

	try {
		expect(result.status).toBe(0);
		const payload = JSON.parse(`${result.stdout ?? ""}`.trim());
		expect(payload.firstTrusted).toBe("no");
		expect(payload.secondTrusted).toBe("yes");
	} finally {
		rmSync(projectRoot, { force: true, recursive: true });
		rmSync(stateDir, { force: true, recursive: true });
	}
});

test("cached detect invalidates when the requested path changes within one repo", () => {
	const projectRoot = createDetectCacheProject(
		"yen-ide-detect-cache-requested-path-",
	);
	const { result, stateDir } = runDetectCacheProbe(
		projectRoot,
		[
			'first=$(cmd_detect --cached --format env "$root/a")',
			'second=$(cmd_detect --cached --format env "$root/b")',
			`first_requested=$(printf "%s\\n" "$first" | sed -n "s/^export YEN_PROJECT_REQUESTED_PATH='\\\\(.*\\\\)'$/\\\\1/p" | head -n 1)`,
			`second_requested=$(printf "%s\\n" "$second" | sed -n "s/^export YEN_PROJECT_REQUESTED_PATH='\\\\(.*\\\\)'$/\\\\1/p" | head -n 1)`,
			'FIRST_REQUESTED="$first_requested" SECOND_REQUESTED="$second_requested" python3 - <<\'PY\'',
			"import json",
			"import os",
			'print(json.dumps({"firstRequested": os.environ.get("FIRST_REQUESTED", ""), "secondRequested": os.environ.get("SECOND_REQUESTED", "")}))',
			"PY",
		].join("\n"),
	);

	try {
		expect(result.status).toBe(0);
		const payload = JSON.parse(`${result.stdout ?? ""}`.trim());
		expect(payload.firstRequested).toBe(`${projectRoot}/a`);
		expect(payload.secondRequested).toBe(`${projectRoot}/b`);
	} finally {
		rmSync(projectRoot, { force: true, recursive: true });
		rmSync(stateDir, { force: true, recursive: true });
	}
});

test("descendant project scan is bounded by YEN_IDE_DETECT_MAX_DIRS", () => {
	// Markerless parent wrapping a single nested project: the full scan finds it,
	// but a too-small budget must give up cleanly (exit 1) instead of walking the
	// whole subtree — the guard that stops a cold detect in $HOME taking ~12s.
	const parent = realpathSync(ideTemp("yen-ide-detect-budget-"));
	mkdirSync(join(parent, "nested", "proj"), { recursive: true });
	writeFileSync(join(parent, "nested", "proj", "package.json"), "{}\n", "utf8");

	const { result, stateDir } = runDetectCacheProbe(
		parent,
		[
			'unbounded=$(find_unique_descendant_project_root "$root" || echo "__none__")',
			"export YEN_IDE_DETECT_MAX_DIRS=1",
			'bounded=$(find_unique_descendant_project_root "$root" || echo "__none__")',
			"unset YEN_IDE_DETECT_MAX_DIRS",
			'UNBOUNDED="$unbounded" BOUNDED="$bounded" python3 - <<\'PY\'',
			"import json",
			"import os",
			'print(json.dumps({"unbounded": os.environ.get("UNBOUNDED", ""), "bounded": os.environ.get("BOUNDED", "")}))',
			"PY",
		].join("\n"),
	);

	try {
		expect(result.status).toBe(0);
		const payload = JSON.parse(`${result.stdout ?? ""}`.trim());
		expect(payload.unbounded).toBe(`${parent}/nested/proj`);
		expect(payload.bounded).toBe("__none__");
	} finally {
		rmSync(parent, { force: true, recursive: true });
		rmSync(stateDir, { force: true, recursive: true });
	}
});
