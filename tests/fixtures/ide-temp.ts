import { afterAll, afterEach, setDefaultTimeout } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Limits for every `yen ide` test file.
 *
 * Each test launches the real CLI, so a busy machine slows it: under generated
 * CPU and disk load these tests ran up to 3.6 times slower than idle, and Bun's
 * 5-second default failed healthy ones. Both limits leave about twice that
 * margin and stay finite, so a CLI call that hangs still fails its test.
 *
 * - `IDE_CLI_TEST_TIMEOUT_MS` is the default for a test and for the cleanup
 *   hooks. It fits a test that takes up to about 4 seconds on an idle machine.
 * - `IDE_CLI_SLOW_TEST_TIMEOUT_MS` is for a test that chains many CLI calls or
 *   waits on a daemon, up to about 16 seconds idle. Pass it as the test's
 *   `timeout` in place of a number; `tests/170-cli-test-limits.test.ts`
 *   refuses a numeric limit in these files.
 */
export const IDE_CLI_TEST_TIMEOUT_MS = 30_000;
export const IDE_CLI_SLOW_TEST_TIMEOUT_MS = 120_000;

/**
 * Per-file temp tracker for `yen ide` tests.
 * Import and call `createIdeTemp()` once at module scope, then use `ideTemp`
 * instead of `mkdtempSync(join(tmpdir(), ...))`.
 *
 * Each file gets its own set, so parallel bun test files cannot sweep
 * each other's directories. afterEach removes what that file created.
 * Processes whose argv contains a tracked path are torn down first.
 *
 * The call also applies the limits above to the calling file: Bun scopes
 * `setDefaultTimeout` to one file, and a hook keeps Bun's 5-second default
 * unless it is given its own limit.
 */
export function createIdeTemp(): {
	ideTemp: (prefix: string) => string;
	sweep: () => void;
} {
	setDefaultTimeout(IDE_CLI_TEST_TIMEOUT_MS);
	const dirs = new Set<string>();

	function track(dir: string): void {
		dirs.add(dir);
		try {
			dirs.add(realpathSync(dir));
		} catch {
			// Directory may already be gone; the original path is enough.
		}
	}

	function ideTemp(prefix: string): string {
		const dir = mkdtempSync(join(tmpdir(), prefix));
		track(dir);
		return dir;
	}

	function sweep(): void {
		if (dirs.size === 0) return;
		killProcessesTouching(dirs);
		for (const dir of dirs) {
			rmSync(dir, { force: true, recursive: true });
		}
		dirs.clear();
	}

	afterEach(sweep, { timeout: IDE_CLI_TEST_TIMEOUT_MS });
	afterAll(sweep, { timeout: IDE_CLI_TEST_TIMEOUT_MS });
	return { ideTemp, sweep };
}

function killProcessesTouching(dirs: ReadonlySet<string>): void {
	const listing = spawnSync("/bin/ps", ["-axo", "pid=,ppid=,args="], {
		encoding: "utf8",
	});
	if (!listing.stdout) return;
	const rows = parseProcessRows(listing.stdout);
	const victims = findMatchingProcesses(rows, dirs, String(process.pid));
	expandProcessDescendants(rows, victims, String(process.pid));
	for (const pid of victims) terminateProcess(pid);
}

type ProcessRow = { pid: string; ppid: string; line: string };

function parseProcessRows(stdout: string): ProcessRow[] {
	const rows: { pid: string; ppid: string; line: string }[] = [];
	for (const raw of stdout.split("\n")) {
		const line = raw.trim();
		if (!line) continue;
		const parts = line.split(/\s+/);
		if (parts.length < 2) continue;
		const [pid, ppid] = parts;
		if (!pid || !ppid) continue;
		rows.push({ pid, ppid, line });
	}
	return rows;
}

function findMatchingProcesses(
	rows: ProcessRow[],
	dirs: ReadonlySet<string>,
	self: string,
): Set<string> {
	const victims = new Set<string>();
	for (const row of rows) {
		if (row.pid === self) continue;
		if ([...dirs].some((dir) => row.line.includes(dir))) victims.add(row.pid);
	}
	return victims;
}

function expandProcessDescendants(
	rows: ProcessRow[],
	victims: Set<string>,
	self: string,
): void {
	let grew = true;
	while (grew) {
		grew = false;
		for (const row of rows) {
			if (victims.has(row.ppid) && !victims.has(row.pid) && row.pid !== self) {
				victims.add(row.pid);
				grew = true;
			}
		}
	}
}

function terminateProcess(pid: string): void {
	const numericPid = Number(pid);
	if (!Number.isInteger(numericPid) || numericPid <= 1) return;
	for (const signal of ["SIGTERM", "SIGKILL"] as const) {
		try {
			process.kill(numericPid, signal);
		} catch {
			// Already gone or not owned by this process.
		}
	}
}
