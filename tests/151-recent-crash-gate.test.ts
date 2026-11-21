import { afterEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// /update-yen PF-03. A framework abort (an AttributeGraph precondition) writes only
// the bundled reporter's .yencrash, never an .ips, so a gate that read .ips alone
// passed a release while the installed app was crashing on the first Scratchpad open.
const script = join(process.cwd(), "scripts/manual/12-check-recent-crashes.sh");
const sandboxes: string[] = [];

function sandbox() {
	const root = mkdtempSync(join(tmpdir(), "yen-crash-gate-"));
	sandboxes.push(root);
	const diag = join(root, "DiagnosticReports");
	const crash = join(root, "crash");
	mkdirSync(diag);
	mkdirSync(crash);
	return { root, diag, crash, triaged: join(root, "triaged") };
}

function envelope(executable: string): string {
	return `{"event_id":"x","level":"fatal","release":"1.0.231","debug_meta":{"images":[{"type":"macho","code_file":"${executable}","image_addr":"0x1"}]}}\n\u0000MDMP`;
}

function run(box: ReturnType<typeof sandbox>, ...args: string[]) {
	const result = spawnSync("bash", [script, "--days", "3", ...args], {
		encoding: "utf8",
		env: {
			HOME: box.root,
			NODE_ENV: "test",
			PATH: process.env.PATH,
			YEN_CRASH_DIR: box.crash,
			YEN_DIAGNOSTIC_REPORTS_DIR: box.diag,
			YEN_TRIAGED_CRASHES_FILE: box.triaged,
		},
	});
	return { code: result.status, out: `${result.stdout}${result.stderr}` };
}

afterEach(() => {
	for (const root of sandboxes.splice(0)) {
		rmSync(root, { recursive: true, force: true });
	}
});

describe("recent crash gate", () => {
	test("blocks on a .yencrash from the installed app", () => {
		const box = sandbox();
		writeFileSync(
			join(box.crash, "a.yencrash"),
			envelope("/Applications/YEN.app/Contents/MacOS/yen"),
		);
		const { code, out } = run(box);
		expect(code).toBe(1);
		expect(out).toContain("Scanned 0 .ips and 1 .yencrash file(s)");
		expect(out).toContain("New YEN crash reports found (1)");
		expect(out).toContain("a.yencrash");
	});

	test("ignores .yencrash files from test hosts and Debug builds", () => {
		const box = sandbox();
		writeFileSync(
			join(box.crash, "b.yencrash"),
			envelope("/tmp/dd/Build/Products/Debug/YEN.app/Contents/MacOS/yen"),
		);
		const { code, out } = run(box);
		expect(code).toBe(0);
		expect(out).toContain("Scanned 0 .ips and 1 .yencrash file(s)");
		expect(out).toContain("No new YEN crash reports found");
	});

	test("still blocks on a YEN .ips report", () => {
		const box = sandbox();
		writeFileSync(join(box.diag, "yen-2026-10-22-050419.ips"), "{}");
		const { code, out } = run(box);
		expect(code).toBe(1);
		expect(out).toContain("Scanned 1 .ips and 0 .yencrash file(s)");
	});

	test("a triaged .yencrash no longer blocks", () => {
		const box = sandbox();
		writeFileSync(
			join(box.crash, "c.yencrash"),
			envelope("/Applications/YEN.app/Contents/MacOS/yen"),
		);
		expect(run(box, "--triage-all").out).toContain("Triaged: c.yencrash");
		const { code, out } = run(box);
		expect(code).toBe(0);
		expect(out).toContain("Skipped 1 previously triaged crash report(s)");
	});
});
