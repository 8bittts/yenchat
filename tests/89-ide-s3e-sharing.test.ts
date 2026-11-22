import { test as bunTest, describe, expect } from "bun:test";
import { spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
	createIdeTemp,
	IDE_CLI_SLOW_TEST_TIMEOUT_MS,
} from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

// Share lifecycle cases launch multiple CLI processes and mock transports.
const test = (
	name: string,
	fn: () => void | Promise<void>,
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

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "package.json"),
		'{"name":"share-fixture"}\n',
		"utf8",
	);
	return root;
}

function forceExpired(stateFile: string) {
	const current = readFileSync(stateFile, "utf8");
	const expired = current
		.replace(/^expires_epoch=.*$/m, "expires_epoch=1")
		.replace(/^expires_at=.*$/m, "expires_at=1970-01-01T00:00:01Z");
	expect(expired).not.toBe(current);
	writeFileSync(stateFile, expired, "utf8");
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
	spawnSync("chmod", ["755", path]);
}

function writeFakeTmate(path: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
socket=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -S)
      shift
      socket="$1"
      ;;
    *)
      break
      ;;
  esac
  shift || true
done
cmd="$1"
shift || true
state_dir="\${socket}.state"
case "$cmd" in
  new-session)
    mkdir -p "$state_dir"
    : > "$socket"
    echo ready > "\${state_dir}/ready"
    ;;
  wait)
    [[ -f "\${state_dir}/ready" ]]
    ;;
  display)
    if [[ "$1" == "-p" ]]; then
      shift || true
    fi
    format="$1"
    case "$format" in
      '#{tmate_ssh_ro}')
        echo "ssh ro-fake@tmate.example.test"
        ;;
      '#{tmate_ssh}')
        echo "ssh rw-fake@tmate.example.test"
        ;;
      '#{tmate_web_ro}')
        echo "https://tmate.example.test/ro"
        ;;
      '#{tmate_web}')
        echo "https://tmate.example.test/rw"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  has-session)
    [[ -f "\${state_dir}/ready" ]]
    ;;
  kill-server)
    rm -rf "$state_dir"
    rm -f "$socket"
    ;;
  *)
    exit 1
    ;;
esac
`,
		"utf8",
	);
	spawnSync("chmod", ["755", path]);
}

function writeFakeSSH(path: string, logPath: string) {
	writeFileSync(
		path,
		`#!/bin/bash
set -e
printf "%s\\n" "$*" > ${JSON.stringify(logPath)}
`,
		"utf8",
	);
	spawnSync("chmod", ["755", path]);
}

function encryptSharePayload(payload: string, passphrase: string) {
	const result = spawnSync(
		"openssl",
		[
			"enc",
			"-aes-256-cbc",
			"-pbkdf2",
			"-salt",
			"-a",
			"-A",
			"-pass",
			`pass:${passphrase}`,
		],
		{
			encoding: "utf8",
			input: payload,
		},
	);
	expect(result.status).toBe(0);
	return (result.stdout ?? "").trim();
}

describe("IDE S3E sharing control plane", () => {
	test(
		"share host/status/join/revoke use upterm first, encrypted tokens, and audited lifecycle events",
		() => {
			const stateDir = ideTemp("yen-ide-share-state-");
			const project = createProject("yen-ide-share-project-");
			const binDir = ideTemp("yen-ide-share-bin-");
			const fakeUpterm = join(binDir, "upterm");
			const fakeSSH = join(binDir, "ssh");
			const sshLog = join(stateDir, "ssh.log");
			writeFakeUpterm(fakeUpterm);
			writeFakeSSH(fakeSSH, sshLog);

			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_SHARE_UPTERM_CMD: fakeUpterm,
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
			};

			const initialStatus = runYen(
				["ide", "share", "status", "--project", project],
				env,
			);
			const initialOutput = `${initialStatus.stdout ?? ""}\n${initialStatus.stderr ?? ""}`;
			expect(initialStatus.status).toBe(0);
			expect(initialOutput).toContain("Trusted:            no");
			expect(initialOutput).toContain("State:              stopped");
			expect(initialOutput).toContain("Preferred:          upterm");

			const blockedHost = runYen(
				[
					"ide",
					"share",
					"host",
					"--project",
					project,
					"--ttl-seconds",
					"30",
					"--passphrase",
					"open-sesame",
				],
				env,
			);
			expect(blockedHost.status).toBe(1);

			expect(runYen(["ide", "share", "trust", project], env).status).toBe(0);

			const host = runYen(
				[
					"ide",
					"share",
					"host",
					"--project",
					project,
					"--read-only",
					"--ttl-seconds",
					"30",
					"--passphrase",
					"open-sesame",
					"--format",
					"json",
				],
				env,
			);
			expect(host.status).toBe(0);
			const hostPayload = JSON.parse(host.stdout ?? "{}");
			expect(hostPayload.transport).toBe("upterm");
			expect(hostPayload.mode).toBe("read-only");
			expect(hostPayload.passphrase).toBe("open-sesame");
			expect(hostPayload.shareToken).toBeTruthy();

			const status = runYen(
				["ide", "share", "status", "--project", project, "--format", "json"],
				env,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(status.stdout ?? "{}");
			expect(statusPayload.trusted).toBe(true);
			expect(statusPayload.state).toBe("running");
			expect(statusPayload.transport).toBe("upterm");
			expect(statusPayload.auth).toBe("passphrase");
			expect(statusPayload.shareToken).toBe(hostPayload.shareToken);

			const dryJoin = runYen(
				[
					"ide",
					"share",
					"join",
					"--token",
					hostPayload.shareToken,
					"--passphrase",
					"open-sesame",
					"--print-command",
				],
				env,
			);
			expect(dryJoin.status).toBe(0);
			expect(`${dryJoin.stdout ?? ""}\n${dryJoin.stderr ?? ""}`).toContain(
				"ssh fake-upterm-session@upterm.example.test",
			);

			const actualJoin = runYen(
				[
					"ide",
					"share",
					"join",
					"--token",
					hostPayload.shareToken,
					"--passphrase",
					"open-sesame",
				],
				env,
			);
			const actualJoinOutput = `${actualJoin.stdout ?? ""}\n${actualJoin.stderr ?? ""}`;
			expect(actualJoin.status).toBe(0);
			expect(actualJoinOutput).toContain("IDE Share Join");
			expect(actualJoinOutput).toContain("Mode:               read-only");
			expect(readFileSync(sshLog, "utf8")).toContain(
				"fake-upterm-session@upterm.example.test",
			);

			const badJoin = runYen(
				[
					"ide",
					"share",
					"join",
					"--token",
					hostPayload.shareToken,
					"--passphrase",
					"wrong-passphrase",
				],
				env,
			);
			expect(badJoin.status).toBe(1);
			expect(`${badJoin.stdout ?? ""}\n${badJoin.stderr ?? ""}`).toContain(
				"Invalid share token or passphrase.",
			);

			const revoke = runYen(
				["ide", "share", "revoke", "--project", project],
				env,
			);
			expect(revoke.status).toBe(0);
			expect(`${revoke.stdout ?? ""}\n${revoke.stderr ?? ""}`).toContain(
				"Share session revoked:",
			);

			const revokedStatus = runYen(
				["ide", "share", "status", "--project", project, "--format", "json"],
				env,
			);
			expect(revokedStatus.status).toBe(0);
			const revokedPayload = JSON.parse(revokedStatus.stdout ?? "{}");
			expect(revokedPayload.state).toBe("revoked");
			expect(revokedPayload.shareToken).toBe("");

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("share-trust");
			expect(timeline).toContain("share-host");
			expect(timeline).toContain("share-join");
			expect(timeline).toContain("share-revoke");
			expect(timeline).toContain("auth-failed");
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);

	test(
		"share falls back to tmate and marks expired sessions clearly in status",
		() => {
			const stateDir = ideTemp("yen-ide-share-expire-state-");
			const project = createProject("yen-ide-share-expire-project-");
			const binDir = ideTemp("yen-ide-share-expire-bin-");
			const fakeTmate = join(binDir, "tmate");
			writeFakeTmate(fakeTmate);

			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_SHARE_TMATE_CMD: fakeTmate,
			};

			expect(runYen(["ide", "share", "trust", project], env).status).toBe(0);

			const host = runYen(
				[
					"ide",
					"share",
					"host",
					"--project",
					project,
					"--read-only",
					"--ttl-seconds",
					"30",
					"--passphrase",
					"shortlived",
					"--format",
					"json",
				],
				env,
			);
			expect(host.status).toBe(0);
			const hostPayload = JSON.parse(host.stdout ?? "{}");
			expect(hostPayload.transport).toBe("tmate");

			const joinPreview = runYen(
				[
					"ide",
					"share",
					"join",
					"--token",
					hostPayload.shareToken,
					"--passphrase",
					"shortlived",
					"--print-command",
				],
				env,
			);
			expect(joinPreview.status).toBe(0);
			expect(joinPreview.stdout ?? "").toContain(
				"ssh ro-fake@tmate.example.test",
			);

			const running = runYen(
				["ide", "share", "status", "--project", project, "--format", "json"],
				env,
			);
			expect(running.status).toBe(0);
			const runningPayload = JSON.parse(running.stdout ?? "{}");
			forceExpired(runningPayload.stateFile as string);

			const status = runYen(
				["ide", "share", "status", "--project", project, "--format", "json"],
				env,
			);
			expect(status.status).toBe(0);
			const statusPayload = JSON.parse(status.stdout ?? "{}");
			expect(statusPayload.state).toBe("expired");
			expect(statusPayload.transport).toBe("tmate");
			expect(statusPayload.shareToken).toBe("");

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("share-expire");
		},
		{ timeout: IDE_CLI_SLOW_TEST_TIMEOUT_MS },
	);

	test("share degrades cleanly when no supported transport is available", () => {
		const stateDir = ideTemp("yen-ide-share-missing-state-");
		const project = createProject("yen-ide-share-missing-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			PATH: "/usr/bin:/bin",
		};

		expect(runYen(["ide", "share", "trust", project], env).status).toBe(0);

		const status = runYen(
			["ide", "share", "status", "--project", project],
			env,
		);
		const statusOutput = `${status.stdout ?? ""}\n${status.stderr ?? ""}`;
		expect(status.status).toBe(0);
		expect(statusOutput).toContain("Transport status:   unavailable");
		expect(statusOutput).toContain("Available:          none");

		const host = runYen(
			[
				"ide",
				"share",
				"host",
				"--project",
				project,
				"--ttl-seconds",
				"30",
				"--passphrase",
				"missing-cli",
			],
			env,
		);
		expect(host.status).toBe(1);
		expect(`${host.stdout ?? ""}\n${host.stderr ?? ""}`).toContain(
			"No supported sharing transport is available.",
		);
	});

	test("share host rejects invalid transport and format before starting a session", () => {
		const stateDir = ideTemp("yen-ide-share-validate-state-");
		const project = createProject("yen-ide-share-validate-project-");
		const binDir = ideTemp("yen-ide-share-validate-bin-");
		const fakeUpterm = join(binDir, "upterm");
		writeFakeUpterm(fakeUpterm);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_SHARE_UPTERM_CMD: fakeUpterm,
			PATH: `${binDir}:${process.env.PATH ?? ""}`,
		};

		const badTransport = runYen(
			["ide", "share", "host", "--project", project, "--transport", "ssh"],
			env,
		);
		expect(badTransport.status).toBe(1);
		expect(
			`${badTransport.stdout ?? ""}\n${badTransport.stderr ?? ""}`,
		).toContain("Unknown share transport: ssh");
		expect(
			`${badTransport.stdout ?? ""}\n${badTransport.stderr ?? ""}`,
		).not.toContain("Project sharing is untrusted");

		const badFormat = runYen(
			["ide", "share", "host", "--project", project, "--format", "yaml"],
			env,
		);
		expect(badFormat.status).toBe(1);
		expect(`${badFormat.stdout ?? ""}\n${badFormat.stderr ?? ""}`).toContain(
			"Unknown share host format: yaml",
		);
		expect(
			`${badFormat.stdout ?? ""}\n${badFormat.stderr ?? ""}`,
		).not.toContain("Project sharing is untrusted");

		const status = runYen(
			["ide", "share", "status", "--project", project, "--format", "json"],
			env,
		);
		expect(status.status).toBe(0);
		const statusPayload = JSON.parse(status.stdout ?? "{}");
		expect(statusPayload.state).toBe("stopped");
		expect(statusPayload.shareToken).toBe("");
		expect(statusPayload.trusted).toBe(false);
	});

	test("stale share status hides the share token after the runtime disappears", () => {
		const stateDir = ideTemp("yen-ide-share-stale-state-");
		const project = createProject("yen-ide-share-stale-project-");
		const binDir = ideTemp("yen-ide-share-stale-bin-");
		const fakeUpterm = join(binDir, "upterm");
		writeFakeUpterm(fakeUpterm);

		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_SHARE_UPTERM_CMD: fakeUpterm,
			PATH: `${binDir}:${process.env.PATH ?? ""}`,
		};

		expect(runYen(["ide", "share", "trust", project], env).status).toBe(0);
		const host = runYen(
			[
				"ide",
				"share",
				"host",
				"--project",
				project,
				"--ttl-seconds",
				"30",
				"--passphrase",
				"stale-share",
				"--format",
				"json",
			],
			env,
		);
		expect(host.status).toBe(0);
		const hostPayload = JSON.parse(host.stdout ?? "{}");
		expect(hostPayload.shareToken).toBeTruthy();

		const runningStatus = runYen(
			["ide", "share", "status", "--project", project, "--format", "json"],
			env,
		);
		const runningPayload = JSON.parse(runningStatus.stdout ?? "{}");
		const pidFile = runningPayload.pidFile as string;
		const pid = Number.parseInt(readFileSync(pidFile, "utf8").trim(), 10);
		expect(Number.isFinite(pid)).toBe(true);
		process.kill(pid, "SIGKILL");

		const staleStatus = runYen(
			["ide", "share", "status", "--project", project, "--format", "json"],
			env,
		);
		expect(staleStatus.status).toBe(0);
		const stalePayload = JSON.parse(staleStatus.stdout ?? "{}");
		expect(stalePayload.state).toBe("stale");
		expect(stalePayload.shareToken).toBe("");
	});

	test("share join rejects decrypted payloads with invalid attach commands", () => {
		const payload = JSON.stringify({
			version: 1,
			sessionId: "bad-share",
			transport: "upterm",
			mode: "read-only",
			hostIdentity: "tester@host",
			repoLabel: "repo",
			expiresAt: "2099-01-01T00:00:00Z",
			authMode: "passphrase",
			joinCommand: "bash -lc 'echo bad'",
			webUrl: "",
		});
		const token = encryptSharePayload(payload, "bad-share-secret");
		const join = runYen([
			"ide",
			"share",
			"join",
			"--token",
			token,
			"--passphrase",
			"bad-share-secret",
		]);
		expect(join.status).toBe(1);
		expect(`${join.stdout ?? ""}\n${join.stderr ?? ""}`).toContain(
			"Share token is missing or has invalid join metadata.",
		);
	});

	test("share join rejects ssh commands that try to smuggle extra flags", () => {
		const payload = JSON.stringify({
			version: 1,
			sessionId: "bad-share-flags",
			transport: "upterm",
			mode: "read-only",
			hostIdentity: "tester@host",
			repoLabel: "repo",
			expiresAt: "2099-01-01T00:00:00Z",
			authMode: "passphrase",
			joinCommand: "ssh -o ProxyCommand=bad ro-fake@tmate.example.test",
			webUrl: "",
		});
		const token = encryptSharePayload(payload, "bad-share-flags-secret");
		const join = runYen([
			"ide",
			"share",
			"join",
			"--token",
			token,
			"--passphrase",
			"bad-share-flags-secret",
		]);
		expect(join.status).toBe(1);
		expect(`${join.stdout ?? ""}\n${join.stderr ?? ""}`).toContain(
			"Share token is missing or has invalid join metadata.",
		);
	});
});
