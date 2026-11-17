import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();

function createProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		JSON.stringify({ name: prefix, scripts: { test: "echo ok" } }, null, 2),
		"utf8",
	);
	writeFileSync(
		join(project, "src", "app.ts"),
		"export const value = 1;\n",
		"utf8",
	);
	return realpathSync(project);
}

function runStateProbe(projectRoot: string) {
	const stateDir = ideTemp("yen-ide-remote-state-");
	const remoteTarget = `ssh://dev@example.test${projectRoot}?label=container`;
	const script = `
set -e
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
export IDE_MODULE_DIR=${JSON.stringify(join(repoRoot, "yen-cli/lib/ide"))}

source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/common.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-identity.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/state-trust.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/timeline.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/benchmark.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/env.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-summary.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-doctor.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-trust.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/workspace-capabilities.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/devcontainer.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/share.sh"))}
source ${JSON.stringify(join(repoRoot, "yen-cli/lib/ide/vscode.sh"))}

root=${JSON.stringify(projectRoot)}
workspace_identity_reset
workspace_identity_set_resolved_root "$root"
ensure_state_dirs
export local_history=$(project_history_file "$root")
export local_profile=$(project_profile_file "$root")
export local_lsp_dir=$(lsp_project_dir "$root")
export local_devcontainer_state=$(devcontainer_state_file "$root")
export local_share_state=$(share_state_file "$root")
export local_pr_seen=$(pr_seen_file "$root")
export local_benchmark_hash=$(benchmark_root_hash "$root")
export local_vscode_lock=$(vscode_import_lock_dir "$root")
trust_project "$root"
trust_lsp_project "$root"
trust_devcontainer_project "$root"
trust_share_project "$root"
trust_workflow_project "$root"
export local_env_trusted=$(is_trusted_project "$root" && echo yes || echo no)
timeline_log "env-trust" "$root" "trusted" "source=local-test"

workspace_identity_parse_target ${JSON.stringify(remoteTarget)}
workspace_identity_set_resolved_root "$root"
export IDE_WORKSPACE_IDENTITY
export remote_history=$(project_history_file "$root")
export remote_profile=$(project_profile_file "$root")
export remote_lsp_dir=$(lsp_project_dir "$root")
export remote_devcontainer_state=$(devcontainer_state_file "$root")
export remote_share_state=$(share_state_file "$root")
export remote_pr_seen=$(pr_seen_file "$root")
export remote_benchmark_hash=$(benchmark_root_hash "$root")
export remote_vscode_lock=$(vscode_import_lock_dir "$root")
trust_project "$root"
trust_lsp_project "$root"
trust_devcontainer_project "$root"
trust_share_project "$root"
trust_workflow_project "$root"
export remote_env_trusted=$(is_trusted_project "$root" && echo yes || echo no)
timeline_log "env-trust" "$root" "trusted" "source=remote-test"

python3 - <<'PY'
import json
import os
import pathlib

state_dir = pathlib.Path(os.environ["IDE_STATE_DIR"])

def read_lines(name: str):
    path = state_dir / name
    if not path.is_file():
        return []
    return [line for line in path.read_text(encoding="utf-8").splitlines() if line]

timeline_rows = read_lines("timeline.log")
timeline_roots = [row.split("\\t")[2] for row in timeline_rows if row.count("\\t") >= 4]

payload = {
    "local": {
        "history": os.environ.get("local_history", ""),
        "profile": os.environ.get("local_profile", ""),
        "lspDir": os.environ.get("local_lsp_dir", ""),
        "devcontainerState": os.environ.get("local_devcontainer_state", ""),
        "shareState": os.environ.get("local_share_state", ""),
        "prSeen": os.environ.get("local_pr_seen", ""),
        "benchmarkHash": os.environ.get("local_benchmark_hash", ""),
        "vscodeLock": os.environ.get("local_vscode_lock", ""),
        "trusted": os.environ.get("local_env_trusted", ""),
    },
    "remote": {
        "history": os.environ.get("remote_history", ""),
        "profile": os.environ.get("remote_profile", ""),
        "lspDir": os.environ.get("remote_lsp_dir", ""),
        "devcontainerState": os.environ.get("remote_devcontainer_state", ""),
        "shareState": os.environ.get("remote_share_state", ""),
        "prSeen": os.environ.get("remote_pr_seen", ""),
        "benchmarkHash": os.environ.get("remote_benchmark_hash", ""),
        "vscodeLock": os.environ.get("remote_vscode_lock", ""),
        "trusted": os.environ.get("remote_env_trusted", ""),
        "identity": os.environ.get("IDE_WORKSPACE_IDENTITY", ""),
    },
    "trust": {
        "env": read_lines("trusted-env-projects"),
        "lsp": read_lines("trusted-lsp-projects"),
        "devcontainer": read_lines("trusted-devcontainer-projects"),
        "share": read_lines("trusted-share-projects"),
        "workflow": read_lines("trusted-workflow-projects"),
    },
    "timelineRoots": timeline_roots,
}
print(json.dumps(payload))
PY
`;

	return spawnSync("bash", ["-lc", script], {
		cwd: repoRoot,
		encoding: "utf8",
	});
}

describe("IDE remote state keying", () => {
	test("shared state helpers keep local and remote trust/state paths distinct for the same repo root", () => {
		const projectRoot = createProject("yen-ide-remote-state-key-");
		const result = runStateProbe(projectRoot);
		expect(result.status).toBe(0);

		const payload = JSON.parse(`${result.stdout ?? ""}`.trim());
		const localHash = createHash("sha256").update(projectRoot).digest("hex");
		const remoteIdentity = `ssh://dev@example.test${projectRoot}?label=container`;
		const remoteHash = createHash("sha256")
			.update(remoteIdentity)
			.digest("hex");

		expect(payload.local.trusted).toBe("yes");
		expect(payload.remote.trusted).toBe("yes");
		expect(payload.local.history).not.toBe(payload.remote.history);
		expect(payload.local.profile).not.toBe(payload.remote.profile);
		expect(payload.local.lspDir).not.toBe(payload.remote.lspDir);
		expect(payload.local.devcontainerState).not.toBe(
			payload.remote.devcontainerState,
		);
		expect(payload.local.shareState).not.toBe(payload.remote.shareState);
		expect(payload.local.prSeen).not.toBe(payload.remote.prSeen);
		expect(payload.local.vscodeLock).not.toBe(payload.remote.vscodeLock);
		expect(payload.local.history).toEndWith(`/${localHash}.log`);
		expect(payload.local.profile).toEndWith(`/${localHash}.log`);
		expect(payload.local.lspDir).toEndWith(`/${localHash}`);
		expect(payload.local.prSeen).toEndWith(`/pr-seen-${localHash}.log`);
		expect(payload.local.vscodeLock).toEndWith(
			`/vscode-locks/${localHash}.lock`,
		);
		expect(payload.local.benchmarkHash).toBe(localHash.slice(0, 12));
		expect(payload.remote.identity).toBe(remoteIdentity);
		expect(payload.remote.history).toEndWith(`/${remoteHash}.log`);
		expect(payload.remote.profile).toEndWith(`/${remoteHash}.log`);
		expect(payload.remote.lspDir).toEndWith(`/${remoteHash}`);
		expect(payload.remote.prSeen).toEndWith(`/pr-seen-${remoteHash}.log`);
		expect(payload.remote.vscodeLock).toEndWith(
			`/vscode-locks/${remoteHash}.lock`,
		);
		expect(payload.remote.benchmarkHash).toBe(remoteHash.slice(0, 12));

		expect(payload.trust.env).toEqual([projectRoot, remoteIdentity]);
		expect(payload.trust.lsp).toEqual(payload.trust.env);
		expect(payload.trust.devcontainer).toEqual(payload.trust.env);
		expect(payload.trust.share).toEqual(payload.trust.env);
		expect(payload.trust.workflow).toEqual(payload.trust.env);
		expect(payload.timelineRoots).toEqual([projectRoot, remoteIdentity]);
	});
});
