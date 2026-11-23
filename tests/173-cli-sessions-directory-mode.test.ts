import { afterAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	existsSync,
	lstatSync,
	mkdirSync,
	mkdtempSync,
	renameSync,
	rmSync,
	statSync,
	symlinkSync,
} from "node:fs";
import { join } from "node:path";

// The session directory holds sockets and zmx logs that record working
// directories and environment values, so YEN keeps it 0700: the CLI repairs an
// existing directory and runs every zmx with ZMX_DIR_MODE=0700, because zmx
// creates logs/ with 0750 otherwise. Scratch directories live under /tmp/<short>
// for the socket path limit, never in the user's ~/.local/state/yen.

const repoRoot = join(import.meta.dir, "..");
const yen = join(repoRoot, "yen-cli/bin/yen");
const zmx = join(repoRoot, "yen-terminal/customizations/vendor/zmx/zmx");
const vendored = existsSync(zmx);
const roots: string[] = [];
const started: [string, string][] = [];

function environment(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
	const env: NodeJS.ProcessEnv = { ...process.env, YEN_LIB: "", ...extra };
	for (const key of Object.keys(env)) {
		if (key.startsWith("ZMX_")) delete env[key];
	}
	return { ...env, ...extra };
}

function scratch(): string {
	const root = mkdtempSync("/tmp/ysm-");
	roots.push(root);
	return root;
}

function sessions(directory: string, args: string[]) {
	return spawnSync(yen, ["sessions", ...args], {
		encoding: "utf8",
		env: environment({ YEN_SESSIONS_DIR: directory }),
		timeout: 15_000,
	});
}

function mode(path: string): number {
	return statSync(path).mode & 0o777;
}

/// A session directory and its logs/ and bin/ as zmx's default leaves them.
function groupReadable(root: string): string {
	const directory = join(root, "zmx");
	for (const path of [
		directory,
		join(directory, "logs"),
		join(directory, "bin"),
	]) {
		mkdirSync(path, { recursive: true });
		chmodSync(path, 0o750);
	}
	return directory;
}

afterAll(() => {
	for (const [directory, id] of started) {
		spawnSync(zmx, ["kill", id], {
			env: environment({ ZMX_DIR: directory }),
			timeout: 10_000,
		});
	}
	for (const root of roots) rmSync(root, { recursive: true, force: true });
});

describe("yen sessions keeps the session directory private", () => {
	test("the vendored zmx is present", () => {
		if (!vendored) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored zmx missing — run scripts/48-vendor-zmx.sh",
			).toBe("1");
		}
	});

	test("list repairs a 0750 directory, logs/ and bin/ to 0700", () => {
		const directory = groupReadable(scratch());
		const result = sessions(directory, ["list", "--porcelain"]);
		expect(result.status, result.stderr).toBe(0);
		expect(mode(directory)).toBe(0o700);
		expect(mode(join(directory, "logs"))).toBe(0o700);
		expect(mode(join(directory, "bin"))).toBe(0o700);
	});

	test("attach repairs the directory even when the session is missing", () => {
		const directory = groupReadable(scratch());
		const result = sessions(directory, [
			"attach",
			"6F1D2C3B-0A4E-4F5A-9B8C-1D2E3F4A5B6C",
		]);
		expect(result.status).toBe(1);
		expect(mode(directory)).toBe(0o700);
		expect(mode(join(directory, "logs"))).toBe(0o700);
	});

	test("the repair never follows a symlink", () => {
		const root = scratch();
		const elsewhere = join(root, "elsewhere");
		mkdirSync(elsewhere);
		chmodSync(elsewhere, 0o755);
		const linked = join(root, "linked");
		symlinkSync(elsewhere, linked);
		sessions(linked, ["list", "--porcelain"]);
		expect(lstatSync(linked).isSymbolicLink()).toBe(true);
		expect(mode(elsewhere)).toBe(0o755);

		const real = join(root, "real");
		const logsElsewhere = join(root, "logs-elsewhere");
		mkdirSync(real);
		mkdirSync(logsElsewhere);
		chmodSync(real, 0o750);
		chmodSync(logsElsewhere, 0o755);
		symlinkSync(logsElsewhere, join(real, "logs"));
		const result = sessions(real, ["list", "--porcelain"]);
		expect(result.status, result.stderr).toBe(0);
		expect(mode(real)).toBe(0o700);
		expect(mode(logsElsewhere)).toBe(0o755);
	});

	test.if(vendored)(
		"zmx run by the CLI creates logs/ as 0700 (kill on a real session)",
		() => {
			const root = scratch();
			const directory = join(root, "z");
			const id = "0A1B2C3D-0A4E-4F5A-9B8C-1D2E3F4A5B6C";
			const run = spawnSync(zmx, ["run", id, "-d", "/bin/sleep", "60"], {
				env: environment({ ZMX_DIR: directory, ZMX_DIR_MODE: "0700" }),
				timeout: 10_000,
			});
			expect(run.status, run.stderr?.toString()).toBe(0);
			started.push([directory, id]);
			// zmx recreates logs/ on its next run; the CLI's run must make it private.
			renameSync(join(directory, "logs"), join(root, "old-logs"));
			const result = sessions(directory, ["kill", id]);
			expect(result.status, result.stderr).toBe(0);
			expect(existsSync(join(directory, "logs"))).toBe(true);
			expect(mode(join(directory, "logs"))).toBe(0o700);
		},
	);
});
