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
	// The installed app's zmx, and a dwarfdump stand-in that prints its UUID
	// the way `dwarfdump --uuid` does.
	const zmx = join(root, "zmx");
	writeFileSync(zmx, "not a real binary");
	const dwarfdump = join(root, "dwarfdump");
	writeFileSync(
		dwarfdump,
		`#!/bin/sh\necho "UUID: ${SHIPPED_ZMX_UUID.toUpperCase()} (arm64) $2"\n`,
		{ mode: 0o755 },
	);
	return { root, diag, crash, triaged: join(root, "triaged"), zmx, dwarfdump };
}

const SHIPPED_ZMX_UUID = "251d6d41-2229-3b22-a51b-a9bf6612954d";

// The first line of a macOS .ips report: slice_uuid is the crashed binary's.
function ipsReport(name: string, uuid: string): string {
	return `{"app_name":"${name}","slice_uuid":"${uuid}","bug_type":"309","name":"${name}"}\n{\n  "procName" : "${name}"\n}\n`;
}

function envelope(executable: string): string {
	return `{"event_id":"x","level":"fatal","release":"1.0.231","debug_meta":{"images":[{"type":"macho","code_file":"${executable}","image_addr":"0x1"}]}}\n\u0000MDMP`;
}

function run(
	box: ReturnType<typeof sandbox>,
	args: string[] = [],
	extraEnv: Record<string, string> = {},
) {
	const result = spawnSync("bash", [script, "--days", "3", ...args], {
		encoding: "utf8",
		env: {
			HOME: box.root,
			NODE_ENV: "test",
			PATH: process.env.PATH,
			YEN_CRASH_DIR: box.crash,
			YEN_DIAGNOSTIC_REPORTS_DIR: box.diag,
			YEN_DWARFDUMP: box.dwarfdump,
			YEN_SHIPPED_ZMX: box.zmx,
			YEN_TRIAGED_CRASHES_FILE: box.triaged,
			...extraEnv,
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
		expect(run(box, ["--triage-all"]).out).toContain("Triaged: c.yencrash");
		const { code, out } = run(box);
		expect(code).toBe(0);
		expect(out).toContain("Skipped 1 previously triaged crash report(s)");
	});

	// zmx session daemons run as the installed app's bin/zmx or as byte
	// copies of it (<session dir>/bin/zmx-<digest>), so the report's binary
	// UUID, not its redacted path, says whether a shipped zmx crashed.
	test("blocks on a zmx report from the installed app's zmx or a copy of it", () => {
		const box = sandbox();
		writeFileSync(
			join(box.diag, "zmx-2026-11-22-161311.ips"),
			ipsReport("zmx", SHIPPED_ZMX_UUID),
		);
		writeFileSync(
			join(box.diag, "zmx-a41740f381af57b2-2026-11-22-161400.ips"),
			ipsReport("zmx-a41740f381af57b2", SHIPPED_ZMX_UUID),
		);
		const { code, out } = run(box);
		expect(code).toBe(1);
		expect(out).toContain("Scanned 2 .ips and 0 .yencrash file(s)");
		expect(out).toContain("New YEN crash reports found (2)");
		expect(out).toContain("zmx-a41740f381af57b2-2026-11-22-161400.ips");
	});

	test("ignores zmx reports from binaries that are not the installed zmx", () => {
		const box = sandbox();
		writeFileSync(
			join(box.diag, "zmx-run-2026-11-22-180415.ips"),
			ipsReport("zmx-run", "bdaa95b0-e43e-3140-9bad-0b4a4ca8f1ec"),
		);
		const { code, out } = run(box);
		expect(code).toBe(0);
		expect(out).toContain("Scanned 1 .ips and 0 .yencrash file(s)");
		expect(out).toContain("No new YEN crash reports found");
	});

	test("fails closed when it cannot read the installed zmx UUID", () => {
		const box = sandbox();
		writeFileSync(
			join(box.diag, "zmx-2026-11-22-161311.ips"),
			ipsReport("zmx", SHIPPED_ZMX_UUID),
		);
		const { code, out } = run(box, [], {
			YEN_DWARFDUMP: join(box.root, "missing-dwarfdump"),
		});
		expect(code).toBe(1);
		expect(out).toContain("cannot read the UUID of the installed zmx");
	});
});
