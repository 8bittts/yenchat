import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function delay(ms: number) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

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
	return canonical(project);
}

function writeFakeSSH(path: string) {
	writeFileSync(
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
		"utf8",
	);
	chmodSync(path, 0o755);
}

function writeFakeUpterm(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
cmd="$1"
shift || true
case "$cmd" in
  host)
    admin_file="\${YEN_IDE_SHARE_UPTERM_ADMIN_SOCKET_FILE:-}"
    session_file="\${YEN_IDE_SHARE_UPTERM_SESSION_FILE:-}"
    read_only="0"
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --read-only)
          read_only="1"
          ;;
        --)
          break
          ;;
      esac
      shift || true
    done
    admin_socket="\${admin_file}.runtime"
    mkdir -p "$(dirname "$admin_socket")"
    : > "$admin_socket"
    if [[ -n "$admin_file" ]]; then
      printf "%s\\n" "$admin_socket" > "$admin_file"
    fi
    cat > "\${admin_socket}.json" <<EOF
{"sessionId":"fake-upterm-session","host":"upterm.example.test","sshCommand":"ssh fake-upterm-session@upterm.example.test","webUrl":"https://upterm.example.test/fake-upterm-session","readOnly":$read_only}
EOF
    if [[ -n "$session_file" ]]; then
      cp "\${admin_socket}.json" "$session_file"
    fi
    trap 'rm -f "$admin_socket" "\${admin_socket}.json" "$session_file"' EXIT INT TERM
    while true; do
      sleep 1
    done
    ;;
  session)
    sub="$1"
    shift || true
    if [[ "$sub" != "current" ]]; then
      exit 1
    fi
    admin_socket="\${UPTERM_ADMIN_SOCKET:-}"
    cat "\${admin_socket}.json"
    ;;
  *)
    exit 1
    ;;
esac
`,
		"utf8",
	);
	chmodSync(path, 0o755);
}

function readStateValue(stateFile: string, key: string) {
	const line = (readFileSync(stateFile, "utf8")
		.split(/\r?\n/)
		.find((entry) => entry.startsWith(`${key}=`)) ?? "") as string;
	return line.includes("=") ? line.split("=", 2)[1] : "";
}

describe("IDE remote share/session baseline", () => {
	test(
		"remote share host/status/revoke keep execution and reconnect labels explicit",
		() => {
			const project = createProject("yen-ide-remote-share-host-");
			const stateDir = ideTemp("yen-ide-remote-share-state-");
			const binDir = ideTemp("yen-ide-remote-share-bin-");
			const sshLog = join(stateDir, "ssh.log");
			writeFakeSSH(join(binDir, "ssh"));
			writeFakeUpterm(join(binDir, "upterm"));
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=container`;
			const identity = `ssh://dev@example.test${project}?label=container`;

			const env = {
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
				YEN_FAKE_SSH_LOG: sshLog,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_REMOTE_SHARE_UPTERM_CMD: join(binDir, "upterm"),
			};

			expect(runYen(["ide", "share", "trust", target], env).status).toBe(0);

			const host = runYen(
				[
					"ide",
					"share",
					"host",
					target,
					"--ttl-seconds",
					"30",
					"--passphrase",
					"remote-open-sesame",
					"--format",
					"json",
				],
				env,
			);
			expect(host.status).toBe(0);
			const hostPayload = JSON.parse(`${host.stdout ?? ""}`.trim());
			expect(hostPayload.executionLocation).toBe("remote");
			expect(hostPayload.workspaceIdentity).toBe(identity);
			expect(hostPayload.requestedPath).toBe(join(project, "src", "app.ts"));
			expect(hostPayload.reconnectTarget).toBe(
				"fake-upterm-session@upterm.example.test",
			);
			expect(hostPayload.remoteAuthority).toBe("dev@example.test");
			expect(hostPayload.remoteLabel).toBe("container");

			const status = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(`${status.stdout ?? ""}`.trim());
			expect(statusPayload.state).toBe("running");
			expect(statusPayload.transportStatus).toBe("available");
			expect(statusPayload.executionLocation).toBe("remote");
			expect(statusPayload.workspaceIdentity).toBe(identity);
			expect(statusPayload.reconnectTarget).toBe(
				"fake-upterm-session@upterm.example.test",
			);
			expect(statusPayload.shareToken).toBe(hostPayload.shareToken);

			const revoke = runYen(["ide", "share", "revoke", target], env);
			expect(revoke.status).toBe(0);

			const revoked = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			const revokedPayload = JSON.parse(`${revoked.stdout ?? ""}`.trim());
			expect(revokedPayload.state).toBe("revoked");
			expect(revokedPayload.shareToken).toBe("");

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain(identity);
			expect(readFileSync(sshLog, "utf8")).toContain("dev@example.test");

			rmSync(binDir, { force: true, recursive: true });
		},
		{ timeout: 45_000 },
	);

	test(
		"remote share status falls back to cached metadata during SSH disconnects and resumes cleanly",
		() => {
			const project = createProject("yen-ide-remote-share-disconnect-");
			const stateDir = ideTemp("yen-ide-remote-share-disconnect-state-");
			const binDir = ideTemp("yen-ide-remote-share-disconnect-bin-");
			writeFakeSSH(join(binDir, "ssh"));
			writeFakeUpterm(join(binDir, "upterm"));
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}`;
			const identity = `ssh://dev@example.test${project}`;
			const env = {
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_REMOTE_SHARE_UPTERM_CMD: join(binDir, "upterm"),
			};

			expect(runYen(["ide", "share", "trust", target], env).status).toBe(0);
			expect(
				runYen(
					[
						"ide",
						"share",
						"host",
						target,
						"--ttl-seconds",
						"30",
						"--passphrase",
						"resume-me",
						"--format",
						"json",
					],
					env,
				).status,
			).toBe(0);

			const disconnected = runYen(
				["ide", "share", "status", target, "--format", "json"],
				{
					...env,
					YEN_FAKE_SSH_MODE: "fail",
					YEN_FAKE_SSH_ERROR: "host unreachable",
				},
			);
			expect(disconnected.status).toBe(0);
			const disconnectedPayload = JSON.parse(
				`${disconnected.stdout ?? ""}`.trim(),
			);
			expect(disconnectedPayload.state).toBe("disconnected");
			expect(disconnectedPayload.transportStatus).toBe("remote-unreachable");
			expect(disconnectedPayload.metadataSource).toBe("cached-local-state");
			expect(disconnectedPayload.workspaceIdentity).toBe(identity);
			expect(disconnectedPayload.shareToken).toBeTruthy();

			const resumed = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			expect(resumed.status).toBe(0);
			const resumedPayload = JSON.parse(`${resumed.stdout ?? ""}`.trim());
			expect(resumedPayload.state).toBe("running");
			expect(resumedPayload.metadataSource).toBe("live-target");
		},
		{ timeout: 45_000 },
	);

	test(
		"remote share lifecycle marks stale and expired sessions without losing workspace identity",
		async () => {
			const project = createProject("yen-ide-remote-share-lifecycle-");
			const stateDir = ideTemp("yen-ide-remote-share-lifecycle-state-");
			const binDir = ideTemp("yen-ide-remote-share-lifecycle-bin-");
			writeFakeSSH(join(binDir, "ssh"));
			writeFakeUpterm(join(binDir, "upterm"));
			const target = `ssh://dev@example.test${join(project, "src", "app.ts")}?label=session`;
			const identity = `ssh://dev@example.test${project}?label=session`;
			const env = {
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_REMOTE_SHARE_UPTERM_CMD: join(binDir, "upterm"),
			};

			expect(runYen(["ide", "share", "trust", target], env).status).toBe(0);
			const staleHost = runYen(
				[
					"ide",
					"share",
					"host",
					target,
					"--ttl-seconds",
					"30",
					"--passphrase",
					"stale-remote",
					"--format",
					"json",
				],
				env,
			);
			expect(staleHost.status).toBe(0);
			const runningStatus = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			expect(runningStatus.status).toBe(0);
			const stalePayload = JSON.parse(`${runningStatus.stdout ?? ""}`.trim());
			const staleStateFile = stalePayload.stateFile as string;
			const remoteStateDir =
				readStateValue(staleStateFile, "remote_state_dir") ?? "";
			expect(remoteStateDir).toBeTruthy();
			rmSync(remoteStateDir, { force: true, recursive: true });

			const staleStatus = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			expect(staleStatus.status).toBe(0);
			const staleStatusPayload = JSON.parse(
				`${staleStatus.stdout ?? ""}`.trim(),
			);
			expect(staleStatusPayload.state).toBe("stale");
			expect(staleStatusPayload.workspaceIdentity).toBe(identity);
			expect(staleStatusPayload.shareToken).toBe("");

			const expireHost = runYen(
				[
					"ide",
					"share",
					"host",
					target,
					"--replace",
					"--ttl-seconds",
					"2",
					"--passphrase",
					"expire-remote",
					"--format",
					"json",
				],
				env,
			);
			expect(expireHost.status).toBe(0);

			await delay(2500);

			const expired = runYen(
				["ide", "share", "status", target, "--format", "json"],
				env,
			);
			expect(expired.status).toBe(0);
			const expiredPayload = JSON.parse(`${expired.stdout ?? ""}`.trim());
			expect(expiredPayload.state).toBe("expired");
			expect(expiredPayload.workspaceIdentity).toBe(identity);
			expect(expiredPayload.shareToken).toBe("");
		},
		{ timeout: 60_000 },
	);
});
