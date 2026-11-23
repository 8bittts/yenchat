import { afterAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";

// The CLI's repair of the session directory never makes anything more open
// and never stops a command when a change fails (_docs/01-architecture.md ->
// Persistent sessions; _docs/04-security.md -> What the session directory
// exposes). tests/173 covers the 0750 repair and the symlink rule.
// Scratch directories live under /tmp/<short> for the socket path limit.

const repoRoot = join(import.meta.dir, "..");
const yen = join(repoRoot, "yen-cli/bin/yen");
const roots: string[] = [];
const locked: string[] = [];

afterAll(() => {
	for (const path of locked) {
		spawnSync("/usr/bin/chflags", ["nouchg", path]);
		chmodSync(path, 0o700);
	}
	for (const root of roots) rmSync(root, { recursive: true, force: true });
});

function sessionDirectory(modes: {
	directory: number;
	logs: number;
	bin: number;
}) {
	const root = mkdtempSync("/tmp/ysr-");
	roots.push(root);
	const directory = join(root, "zmx");
	for (const name of ["", "logs", "bin"])
		mkdirSync(join(directory, name), { recursive: true });
	chmodSync(join(directory, "logs"), modes.logs);
	chmodSync(join(directory, "bin"), modes.bin);
	chmodSync(directory, modes.directory);
	return directory;
}

function list(directory: string) {
	const env: NodeJS.ProcessEnv = {
		...process.env,
		YEN_LIB: "",
		YEN_SESSIONS_DIR: directory,
	};
	for (const key of Object.keys(env)) {
		if (key.startsWith("ZMX_")) delete env[key];
	}
	return spawnSync(yen, ["sessions", "list", "--porcelain"], {
		encoding: "utf8",
		env,
		timeout: 15_000,
	});
}

const mode = (path: string) => statSync(path).mode & 0o777;

describe("yen sessions repairs the session directory without opening it further", () => {
	test("only group and other access is removed; owner bits and a locked directory stay as they were", () => {
		const directory = sessionDirectory({
			directory: 0o750,
			logs: 0o000,
			bin: 0o570,
		});
		locked.push(join(directory, "logs"));
		const result = list(directory);
		expect(result.status, result.stderr).toBe(0);
		expect(mode(directory)).toBe(0o700);
		expect(mode(join(directory, "logs"))).toBe(0o000);
		expect(mode(join(directory, "bin"))).toBe(0o500);
	});

	test("a change that fails leaves that directory as it was and the command still runs", () => {
		const directory = sessionDirectory({
			directory: 0o750,
			logs: 0o750,
			bin: 0o750,
		});
		const logs = join(directory, "logs");
		// An immutable directory refuses chmod, even from its owner.
		expect(spawnSync("/usr/bin/chflags", ["uchg", logs]).status).toBe(0);
		locked.push(logs);
		const result = list(directory);
		expect(result.status, result.stderr).toBe(0);
		expect(result.stdout).toBe("yen-sessions\t1\n");
		expect(mode(logs)).toBe(0o750);
		expect(mode(directory)).toBe(0o700);
		expect(mode(join(directory, "bin"))).toBe(0o700);
	});
});
