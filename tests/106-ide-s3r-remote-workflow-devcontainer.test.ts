import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	rmSync,
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

// Each case drives a fake remote through several real CLI subprocesses.
const test = (
	name: string,
	fn: () => void,
	options: { timeout?: number } = {},
) => bunTest(name, fn, { timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS, ...options });

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

function canonical(path: string) {
	return realpathSync(path);
}

function sha256(value: string) {
	return createHash("sha256").update(value).digest("hex");
}

function restrictedPath(binDir: string) {
	return `${binDir}:/usr/bin:/bin:/usr/sbin:/sbin`;
}

function writeScript(path: string, content: string) {
	writeFileSync(path, content, "utf8");
	chmodSync(path, 0o755);
}

function writeFakeSSH(path: string) {
	writeScript(
		path,
		`#!/bin/bash
set -e
port=""
if [ "$1" = "-p" ]; then
  port="$2"
  shift 2
fi
authority="$1"
shift
if [ -n "\${YEN_FAKE_SSH_LOG:-}" ]; then
  printf "%s\\n" "$authority" >> "$YEN_FAKE_SSH_LOG"
fi
if [ -n "$port" ] && [ -n "\${YEN_FAKE_SSH_PORT_LOG:-}" ]; then
  printf "%s\\n" "$port" >> "$YEN_FAKE_SSH_PORT_LOG"
fi
if [ "\${YEN_FAKE_SSH_MODE:-ok}" = "fail" ]; then
  printf "%s\\n" "\${YEN_FAKE_SSH_ERROR:-remote ssh failure}" >&2
  exit 255
fi
exec "$@"
`,
	);
}

function writePythonProxy(path: string) {
	const python = spawnSync(
		"python3",
		["-c", "import sys; print(sys.executable)"],
		{
			encoding: "utf8",
		},
	);
	const pythonPath = `${python.stdout ?? ""}`.trim();
	writeScript(path, `#!/bin/bash\nexec ${pythonPath} "$@"\n`);
}

function writeFakeBun(path: string) {
	writeScript(
		path,
		`#!/bin/bash
set -e
if [ -n "\${YEN_FAKE_BUN_LOG:-}" ]; then
  printf "%s\\n" "$*" >> "$YEN_FAKE_BUN_LOG"
fi
if [ -n "\${YEN_FAKE_BUN_FAIL_ARGS:-}" ] && [ "$*" = "\${YEN_FAKE_BUN_FAIL_ARGS}" ]; then
  printf "bun failed: %s\\n" "$*" >&2
  exit 1
fi
printf "bun %s\\n" "$*"
`,
	);
}

function writeFakeDevcontainer(path: string) {
	writeScript(
		path,
		`#!/bin/bash
set -e
if [ -n "\${YEN_FAKE_DEVCONTAINER_LOG:-}" ]; then
  printf "%s\\n" "$*" >> "$YEN_FAKE_DEVCONTAINER_LOG"
fi
if [ "$1" = "--version" ]; then
  echo "devcontainer 1.0.0"
  exit 0
fi
action="$1"
shift
if [ "\${YEN_FAKE_DEVCONTAINER_FAIL_ACTION:-}" = "$action" ]; then
  printf "devcontainer %s failed\\n" "$action" >&2
  exit 1
fi
workspace=""
if [ "$1" = "--workspace-folder" ]; then
  workspace="$2"
  shift 2
fi
case "$action" in
  up)
    printf "up:%s\\n" "$workspace"
    ;;
  down)
    printf "down:%s\\n" "$workspace"
    ;;
  exec)
    if [ "$#" -eq 0 ]; then
      exit 0
    fi
    cd "$workspace" 2>/dev/null || true
    exec "$@"
    ;;
  *)
    printf "unsupported action: %s\\n" "$action" >&2
    exit 1
    ;;
esac
`,
	);
}

function createRemoteProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	mkdirSync(join(project, ".yen", "workflows"), { recursive: true });
	mkdirSync(join(project, ".devcontainer"), { recursive: true });
	writeFileSync(
		join(project, "package.json"),
		JSON.stringify(
			{
				name: prefix,
				scripts: {
					test: "bun test",
					lint: "bun run lint",
				},
			},
			null,
			2,
		),
		"utf8",
	);
	writeFileSync(join(project, "bun.lockb"), "", "utf8");
	writeFileSync(
		join(project, ".yen", "workflows", "build.toml"),
		[
			"schema_version = 1",
			'name = "build"',
			'description = "Build the project"',
			"trust_required = true",
			'step = "bun run lint"',
			'optional_step = "bun test"',
			"",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(project, ".devcontainer", "devcontainer.json"),
		JSON.stringify(
			{
				name: "remote-devcontainer",
				image: "mcr.microsoft.com/devcontainers/base:ubuntu",
				workspaceFolder: "/workspace/remote",
				forwardPorts: [3000],
			},
			null,
			2,
		),
		"utf8",
	);
	writeFileSync(
		join(project, "src", "app.ts"),
		"export const value = 1;\n",
		"utf8",
	);
	return canonical(project);
}

function extractReportPath(output: string, label: string) {
	const match = output.match(new RegExp(`${label}:\\s+([^\\n]+)`));
	return match?.[1]?.trim() ?? "";
}

const remoteDevcontainerLifecycleTestName =
	"remote devcontainer up/shell/down verify runtime state and preserve tracked state on transport failure";

function remoteDevcontainerLifecycleTest(fn: () => void) {
	test(remoteDevcontainerLifecycleTestName, fn, {
		timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS,
	});
}

describe("IDE remote workflow/devcontainer execution parity", () => {
	test("remote workflow list/show/discover advertise explicit remote execution instead of plan-only", () => {
		const project = createRemoteProject("yen-ide-remote-workflow-list-");
		const binDir = ideTemp("yen-ide-remote-workflow-list-bin-");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));
		writeFakeBun(join(binDir, "bun"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
		const identity = `ssh://dev@example.test${project}?label=container`;
		const env = {
			PATH: restrictedPath(binDir),
		};

		const list = runYen(["ide", "workflow", "list", "--project", target], env);
		expect(list.status).toBe(0);
		expect(`${list.stdout ?? ""}`).toContain("Execution location: remote");
		expect(`${list.stdout ?? ""}`).toContain("Execution mode:    remote-exec");
		expect(`${list.stdout ?? ""}`).toContain("Trust model:       local-record");

		const show = runYen(
			["ide", "workflow", "show", "build", "--project", target],
			env,
		);
		expect(show.status).toBe(0);
		expect(`${show.stdout ?? ""}`).toContain("Workflow:       build");
		expect(`${show.stdout ?? ""}`).toContain("Execution mode:    remote-exec");
		expect(`${show.stdout ?? ""}`).toContain(
			"Risk source:       heuristic-remote-probe",
		);

		const discover = runYen(
			["ide", "workflow", "discover", "--project", target, "--format", "json"],
			env,
		);
		expect(discover.status).toBe(0);
		const discoverPayload = JSON.parse(`${discover.stdout ?? ""}`.trim());
		expect(discoverPayload.executionLocation).toBe("remote");
		expect(discoverPayload.executionMode).toBe("remote-exec");
		expect(discoverPayload.workspaceIdentity).toBe(identity);
		expect(discoverPayload.limitations).toContain(
			"Remote workflow trust is local-record-only and remote watch-mode is still blocked.",
		);

		const dryRun = runYen(
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:test",
				"--dry-run",
				"--project",
				target,
			],
			env,
		);
		expect(dryRun.status).toBe(0);
		expect(`${dryRun.stdout ?? ""}`).toContain("Execution mode:   dry-run");
		expect(`${dryRun.stdout ?? ""}`).toContain(
			"Dry run: remote native task plan rendered with zero side effects.",
		);

		rmSync(binDir, { force: true, recursive: true });
	});

	test("remote workflow trust plus authored/native execution reuse the local trust and report model", () => {
		const project = createRemoteProject("yen-ide-remote-workflow-run-");
		const stateDir = ideTemp("yen-ide-remote-workflow-state-");
		const binDir = ideTemp("yen-ide-remote-workflow-bin-");
		const bunLog = join(binDir, "bun.log");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));
		writeFakeBun(join(binDir, "bun"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
		const identity = `ssh://dev@example.test${project}?label=container`;
		const env = {
			PATH: restrictedPath(binDir),
			YEN_IDE_STATE_DIR: stateDir,
			YEN_FAKE_BUN_LOG: bunLog,
		};

		const blocked = runYen(
			["ide", "workflow", "run", "build", "--project", target],
			env,
		);
		expect(blocked.status).not.toBe(0);
		expect(`${blocked.stderr ?? ""}`).toContain(
			"Remote workflow execution blocked: workspace is untrusted locally.",
		);

		const trust = runYen(["ide", "workflow", "trust", target], env);
		expect(trust.status).toBe(0);
		expect(`${trust.stdout ?? ""}`).toContain(
			`Workflow trust enabled for remote workspace ${identity}`,
		);

		const authored = runYen(
			["ide", "workflow", "run", "build", "--project", target],
			env,
		);
		expect(authored.status).toBe(0);
		expect(`${authored.stdout ?? ""}`).toContain(
			"Remote workflow completed successfully.",
		);
		const authoredSummary = extractReportPath(
			`${authored.stdout ?? ""}`,
			"Summary file",
		);
		const authoredDetails = extractReportPath(
			`${authored.stdout ?? ""}`,
			"Details file",
		);
		expect(existsSync(authoredSummary)).toBe(true);
		expect(existsSync(authoredDetails)).toBe(true);
		expect(readFileSync(authoredDetails, "utf8")).toContain("location: remote");

		const native = runYen(
			[
				"ide",
				"workflow",
				"run",
				"--native",
				"package.json:test",
				"--project",
				target,
				"--risk-override",
				"low",
				"--yes",
			],
			env,
		);
		expect(native.status).toBe(0);
		expect(`${native.stdout ?? ""}`).toContain(
			"Remote native task completed successfully.",
		);

		const bunRuns = readFileSync(bunLog, "utf8");
		expect(bunRuns).toContain("run lint");
		expect(bunRuns).toContain("test");

		rmSync(binDir, { force: true, recursive: true });
	});

	test("remote devcontainer status reports missing remote CLI and remote trust is explicit", () => {
		const project = createRemoteProject("yen-ide-remote-devcontainer-missing-");
		const binDir = ideTemp("yen-ide-remote-devcontainer-missing-bin-");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}`;
		const identity = `ssh://dev@example.test${project}`;
		const env = {
			PATH: restrictedPath(binDir),
		};

		const trust = runYen(["ide", "devcontainer", "trust", target], env);
		expect(trust.status).toBe(0);
		expect(`${trust.stdout ?? ""}`).toContain(identity);

		const status = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				target,
				"--format",
				"json",
			],
			env,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(`${status.stdout ?? ""}`.trim());
		expect(payload.executionLocation).toBe("remote");
		expect(payload.supported).toBe(true);
		expect(payload.cli).toBe("");
		expect(payload.health).toBe("missing-remote-cli");
		expect(payload.lifecycleMode).toBe("remote-lifecycle");
		expect(payload.metadataSource).toBe("remote-probe");
		expect(payload.stateSource).toBe("local-ide-state");

		const up = runYen(["ide", "devcontainer", "up", "--project", target], env);
		expect(up.status).not.toBe(0);
		expect(`${up.stderr ?? ""}`).toContain(
			"Remote devcontainer CLI is not available.",
		);

		rmSync(binDir, { force: true, recursive: true });
	});

	remoteDevcontainerLifecycleTest(() => {
		const project = createRemoteProject(
			"yen-ide-remote-devcontainer-lifecycle-",
		);
		const stateDir = ideTemp("yen-ide-remote-devcontainer-state-");
		const binDir = ideTemp("yen-ide-remote-devcontainer-bin-");
		const devcontainerLog = join(binDir, "devcontainer.log");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));
		writeFakeDevcontainer(join(binDir, "devcontainer"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=session`;
		const identity = `ssh://dev@example.test${project}?label=session`;
		const env = {
			PATH: restrictedPath(binDir),
			YEN_IDE_STATE_DIR: stateDir,
			YEN_FAKE_DEVCONTAINER_LOG: devcontainerLog,
		};

		expect(runYen(["ide", "devcontainer", "trust", target], env).status).toBe(
			0,
		);

		const up = runYen(["ide", "devcontainer", "up", "--project", target], env);
		expect(up.status).toBe(0);
		expect(`${up.stdout ?? ""}`).toContain("Execution location: remote");

		const runningStatus = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				target,
				"--format",
				"json",
			],
			env,
		);
		expect(runningStatus.status).toBe(0);
		const runningPayload = JSON.parse(`${runningStatus.stdout ?? ""}`.trim());
		expect(runningPayload.workspaceIdentity).toBe(identity);
		expect(runningPayload.state).toBe("running");
		expect(runningPayload.health).toBe("tracked-remote");
		expect(runningPayload.remoteStateVerified).toBe(true);
		expect(runningPayload.lifecycleMode).toBe("remote-lifecycle");

		const shell = runYen(
			["ide", "devcontainer", "shell", "--project", target, "--", "pwd"],
			env,
		);
		expect(shell.status).toBe(0);
		expect(`${shell.stdout ?? ""}`).toContain(project);

		const failedDown = runYen(
			["ide", "devcontainer", "down", "--project", identity],
			{
				...env,
				YEN_FAKE_SSH_MODE: "fail",
				YEN_FAKE_SSH_ERROR: "remote host unreachable",
			},
		);
		expect(failedDown.status).not.toBe(0);
		expect(`${failedDown.stderr ?? ""}`).toContain(
			"tracked state was preserved",
		);

		const disconnectedStatus = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				identity,
				"--format",
				"json",
			],
			{
				...env,
				YEN_FAKE_SSH_MODE: "fail",
				YEN_FAKE_SSH_ERROR: "remote host unreachable",
			},
		);
		expect(disconnectedStatus.status).toBe(0);
		const disconnectedPayload = JSON.parse(
			`${disconnectedStatus.stdout ?? ""}`.trim(),
		);
		expect(disconnectedPayload.state).toBe("running");
		expect(disconnectedPayload.health).toBe("disconnected");
		expect(disconnectedPayload.remoteStateVerified).toBe(false);

		const down = runYen(
			["ide", "devcontainer", "down", "--project", identity],
			env,
		);
		expect(down.status).toBe(0);
		expect(`${down.stdout ?? ""}`).toContain("Remote devcontainer stopped");

		const stoppedStatus = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				target,
				"--format",
				"json",
			],
			env,
		);
		expect(stoppedStatus.status).toBe(0);
		const stoppedPayload = JSON.parse(`${stoppedStatus.stdout ?? ""}`.trim());
		expect(stoppedPayload.state).toBe("stopped");

		const devcontainerRuns = readFileSync(devcontainerLog, "utf8");
		expect(devcontainerRuns).toContain("up --workspace-folder");
		expect(devcontainerRuns).toContain("exec --workspace-folder");
		expect(devcontainerRuns).toContain("down --workspace-folder");

		rmSync(binDir, { force: true, recursive: true });
	});

	test("remote devcontainer status detects spec drift against remote-scoped tracked state", () => {
		const project = createRemoteProject("yen-ide-remote-devcontainer-drift-");
		const stateDir = ideTemp("yen-ide-remote-devcontainer-drift-state-");
		const binDir = ideTemp("yen-ide-remote-devcontainer-drift-bin-");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));
		writeFakeDevcontainer(join(binDir, "devcontainer"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=session`;
		const identity = `ssh://dev@example.test${project}?label=session`;
		const hash = sha256(identity);
		const devcontainerDir = join(stateDir, "devcontainer", hash);
		mkdirSync(devcontainerDir, { recursive: true });
		writeFileSync(
			join(devcontainerDir, "state.env"),
			[
				"status=running",
				`root=${project}`,
				"cli=devcontainer",
				`spec=${join(project, ".devcontainer", "old-devcontainer.json")}`,
				"unsafe=none",
				"started_at=2026-03-22T00:00:00Z",
				"last_command=devcontainer up",
				"health=unknown",
				"workspace_folder=/workspace/old",
				"forward_ports=9999",
				"",
			].join("\n"),
			"utf8",
		);

		const env = {
			PATH: restrictedPath(binDir),
			YEN_IDE_STATE_DIR: stateDir,
		};

		const status = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				target,
				"--format",
				"json",
			],
			env,
		);
		expect(status.status).toBe(0);
		const payload = JSON.parse(`${status.stdout ?? ""}`.trim());
		expect(payload.workspaceIdentity).toBe(identity);
		expect(payload.state).toBe("running");
		expect(payload.health).toBe("spec-drift");
		expect(payload.remoteStateVerified).toBe(true);
		expect(payload.specMatchesTrackedState).toBe(false);
		expect(payload.forwardPorts).toEqual(["3000"]);
		expect(payload.trackedForwardPorts).toEqual(["9999"]);
		expect(payload.spec).toBe(
			join(project, ".devcontainer", "devcontainer.json"),
		);
		expect(payload.trackedSpec).toBe(
			join(project, ".devcontainer", "old-devcontainer.json"),
		);

		rmSync(binDir, { force: true, recursive: true });
	});

	test("remote devcontainer status text/env formats expose remote metadata and lifecycle mode", () => {
		const project = createRemoteProject("yen-ide-remote-devcontainer-formats-");
		const binDir = ideTemp("yen-ide-remote-devcontainer-formats-bin-");
		writeFakeSSH(join(binDir, "ssh"));
		writePythonProxy(join(binDir, "python3"));
		writeFakeDevcontainer(join(binDir, "devcontainer"));

		const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=session`;
		const env = {
			PATH: restrictedPath(binDir),
		};

		const textStatus = runYen(
			[
				"ide",
				"devcontainer",
				"status",
				"--project",
				target,
				"--format",
				"text",
			],
			env,
		);
		expect(textStatus.status).toBe(0);
		expect(`${textStatus.stdout ?? ""}`).toContain(
			"Execution location: remote",
		);
		expect(`${textStatus.stdout ?? ""}`).toContain(
			"Metadata source:    remote-probe",
		);
		expect(`${textStatus.stdout ?? ""}`).toContain(
			"State source:       local-ide-state",
		);
		expect(`${textStatus.stdout ?? ""}`).toContain(
			"Lifecycle mode:     remote-lifecycle",
		);

		const envStatus = runYen(
			["ide", "devcontainer", "status", "--project", target, "--format", "env"],
			env,
		);
		expect(envStatus.status).toBe(0);
		expect(`${envStatus.stdout ?? ""}`).toContain(
			"export YEN_IDE_DEVCONTAINER_EXECUTION_LOCATION=remote",
		);
		expect(`${envStatus.stdout ?? ""}`).toContain(
			"export YEN_IDE_DEVCONTAINER_METADATA_SOURCE=remote-probe",
		);
		expect(`${envStatus.stdout ?? ""}`).toContain(
			"export YEN_IDE_DEVCONTAINER_STATE_SOURCE=local-ide-state",
		);
		expect(`${envStatus.stdout ?? ""}`).toContain(
			"export YEN_IDE_DEVCONTAINER_LIFECYCLE_MODE=remote-lifecycle",
		);

		rmSync(binDir, { force: true, recursive: true });
	});
});
