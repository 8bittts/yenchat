import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	mkdirSync,
	readdirSync,
	readFileSync,
	writeFileSync,
} from "node:fs";
import { join } from "node:path";

// Shared driver for `yen sessions --host` tests against tests/fixtures/fake-ssh.sh.
// Each harness owns a root directory; `next()` starts a fresh fake-ssh state
// directory for one scenario.

export const repoRoot = join(import.meta.dir, "../..");
export const yen = join(repoRoot, "yen-cli/bin/yen");
export const fakeSSH = join(repoRoot, "tests/fixtures/fake-ssh.sh");
export const sessionID = "6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
export const header = "yen-sessions\t1";

export const EXIT = {
	usage: 2,
	unreachable: 10,
	firstConnection: 11,
	notInstalled: 12,
	tooOld: 13,
	noSession: 14,
	hostKeyChanged: 15,
	keyRequired: 16,
} as const;

/// The environment of a CLI run: the fake ssh, no backoff sleep, and no zmx
/// session inherited from a YEN pane.
export function cliEnvironment(
	sshDir: string,
	extra: Record<string, string> = {},
): NodeJS.ProcessEnv {
	const environment: NodeJS.ProcessEnv = {
		...process.env,
		YEN_LIB: "",
		YEN_SSH_BIN: fakeSSH,
		YEN_SSH_RETRY_MAX_DELAY: "0",
		FAKE_SSH_DIR: sshDir,
		...extra,
	};
	for (const key of Object.keys(environment)) {
		if (key.startsWith("ZMX_")) delete environment[key];
	}
	return environment;
}

export class RemoteHarness {
	private run = 0;
	sshDir = "";

	constructor(readonly root: string) {}

	next(): string {
		this.run += 1;
		this.sshDir = join(this.root, `ssh-${this.run}`);
		mkdirSync(this.sshDir);
		return this.sshDir;
	}

	/// One plan line per ssh call; optional stdout and stderr files per call.
	plan(
		lines: string[],
		stdout: Record<number, string> = {},
		stderr: Record<number, string> = {},
	) {
		writeFileSync(join(this.sshDir, "plan"), `${lines.join("\n")}\n`);
		for (const [call, text] of Object.entries(stdout)) {
			writeFileSync(join(this.sshDir, `stdout-${call}`), text);
		}
		for (const [call, text] of Object.entries(stderr)) {
			writeFileSync(join(this.sshDir, `stderr-${call}`), text);
		}
	}

	sessions(args: string[], env: Record<string, string> = {}, input?: string) {
		return spawnSync(yen, ["sessions", ...args], {
			encoding: "utf8",
			env: cliEnvironment(this.sshDir, env),
			input,
			timeout: 15_000,
		});
	}

	calls(): string[][] {
		return readdirSync(this.sshDir)
			.filter((name) => name.startsWith("argv-"))
			.sort((a, b) => Number(a.slice(5)) - Number(b.slice(5)))
			.map((name) =>
				readFileSync(join(this.sshDir, name), "utf8").split("\0").slice(0, -1),
			);
	}

	firstCall(): string[] {
		const [argv] = this.calls();
		if (!argv) throw new Error("fake ssh was not called");
		return argv;
	}

	/// What ssh call `n` read on stdin (FAKE_SSH_CAPTURE_STDIN=1).
	stdinOf(call: number): string | undefined {
		const path = join(this.sshDir, `stdin-${call}`);
		return existsSync(path) ? readFileSync(path, "utf8") : undefined;
	}

	/// A peer YEN.app whose bundled CLI runs `script`, for the exec plan step.
	peerApp(script: string): string {
		const app = join(this.root, `peer-${this.run}`, "YEN.app");
		const bin = join(app, "Contents/Resources/bin");
		mkdirSync(bin, { recursive: true });
		writeFileSync(join(bin, "yen"), `#!/bin/bash\n${script}\n`);
		chmodSync(join(bin, "yen"), 0o755);
		return app;
	}
}

/// The value of `-o <name>=<value>`, the first one as ssh reads it.
export function option(argv: string[], name: string) {
	const value = argv.find(
		(entry, i) => argv[i - 1] === "-o" && entry.startsWith(`${name}=`),
	);
	return value?.slice(name.length + 1);
}

export function alive(pid: number) {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}
