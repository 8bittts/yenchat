import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");
const paneCommandPath = join(repoRoot, "yen-cli/commands/core/pane");
const helpCommandPath = join(repoRoot, "yen-cli/commands/core/help");
const notificationsSwiftPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/YEN/YENCustomNotifications.swift",
);
const surfaceID = "0C5FEA19-7706-4807-994B-2413265BD194";
const notificationName = "com.yenchat.yen.agentWorkingDirectory";

// The dry runs execute the real osascript JavaScript that parses hook payloads.
const testOnDarwin = process.platform === "darwin" ? test : test.skip;

function paneEnv(overrides: Record<string, string | undefined> = {}) {
	return { ...process.env, YEN_SURFACE_ID: surfaceID, ...overrides };
}

function runPane(
	args: string[],
	options: { env?: NodeJS.ProcessEnv; input?: string; cwd?: string } = {},
) {
	return spawnSync(yenBinPath, ["pane", ...args], {
		cwd: options.cwd ?? repoRoot,
		encoding: "utf8",
		env: options.env ?? paneEnv(),
		input: options.input,
	});
}

function withFailingOsascript(run: (env: NodeJS.ProcessEnv) => void) {
	const root = mkdtempSync(join(tmpdir(), "yen-pane-no-osascript-"));
	const binDir = join(root, "bin");
	mkdirSync(binDir, { recursive: true });
	writeFileSync(
		join(binDir, "osascript"),
		`#!/bin/bash
echo "osascript must not run outside a YEN pane" >&2
exit 99
`,
		"utf8",
	);
	chmodSync(join(binDir, "osascript"), 0o755);
	try {
		run({
			...process.env,
			PATH: `${binDir}:${process.env.PATH ?? ""}`,
			YEN_SURFACE_ID: undefined,
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

describe("yen pane cwd", () => {
	test("help surfaces list the pane command", () => {
		const usage = spawnSync(yenBinPath, [], {
			cwd: repoRoot,
			encoding: "utf8",
			env: process.env,
		});
		expect(usage.status).toBe(0);
		expect(usage.stdout).toContain(
			"pane  Report an agent's working directory for this pane",
		);
		expect(readFileSync(helpCommandPath, "utf8")).toContain(
			"${BOLD}pane${RESET}",
		);
	});

	test("the CLI and the app agree on the notification name", () => {
		expect(readFileSync(paneCommandPath, "utf8")).toContain(notificationName);
		expect(readFileSync(notificationsSwiftPath, "utf8")).toContain(
			`static let agentWorkingDirectory = "${notificationName}"`,
		);
	});

	testOnDarwin("a hook payload reports its new_cwd for this pane", () => {
		const res = runPane(["cwd", "--hook", "--dry-run"], {
			input: JSON.stringify({
				hook_event_name: "CwdChanged",
				old_cwd: "/repos/yenchat",
				new_cwd: "/repos/yenchat/.worktrees/split labels-7f3a",
			}),
		});

		expect(res.stderr).toBe("");
		expect(res.status).toBe(0);
		expect(JSON.parse(res.stdout)).toEqual({
			schema_version: "1",
			surface_id: surfaceID,
			directory: "/repos/yenchat/.worktrees/split labels-7f3a",
		});
	});

	testOnDarwin("a directory argument is reported as its physical path", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-pane-dir-"));
		try {
			mkdirSync(join(root, "worktree"));
			const res = runPane(["cwd", "--dry-run", "worktree"], { cwd: root });

			expect(res.status).toBe(0);
			// tmpdir() sits behind the /var -> /private/var symlink on macOS.
			expect(JSON.parse(res.stdout).directory).toBe(
				realpathSync(join(root, "worktree")),
			);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	testOnDarwin("--clear sends an empty directory", () => {
		const res = runPane(["cwd", "--clear", "--dry-run"]);

		expect(res.status).toBe(0);
		expect(JSON.parse(res.stdout)).toEqual({
			schema_version: "1",
			surface_id: surfaceID,
			directory: "",
		});
	});

	testOnDarwin("a malformed hook payload fails with a readable reason", () => {
		const notJson = runPane(["cwd", "--hook", "--dry-run"], {
			input: "not json",
		});
		expect(notJson.status).toBe(1);
		expect(notJson.stderr.trim()).toBe(
			"yen pane: hook payload on stdin is not JSON",
		);

		const relative = runPane(["cwd", "--hook", "--dry-run"], {
			input: JSON.stringify({ new_cwd: "relative/path" }),
		});
		expect(relative.status).toBe(1);
		expect(relative.stderr.trim()).toBe(
			"yen pane: hook payload has no absolute new_cwd",
		);
	});

	test("outside a YEN pane the hook stays silent and never contacts the app", () => {
		withFailingOsascript((env) => {
			const hook = runPane(["cwd", "--hook"], {
				env,
				input: JSON.stringify({ new_cwd: "/tmp" }),
			});
			expect(hook.status).toBe(0);
			expect(hook.stdout).toBe("");
			expect(hook.stderr).toBe("");

			const direct = runPane(["cwd", "/tmp"], { env });
			expect(direct.status).toBe(1);
			expect(direct.stderr).toContain(
				"run this inside a YEN pane (YEN_SURFACE_ID is not set)",
			);
		});
	});

	test("usage errors name the problem", () => {
		const missing = runPane(["cwd"]);
		expect(missing.status).toBe(2);
		expect(missing.stderr).toContain(
			"cwd needs <directory>, --hook, or --clear",
		);

		const both = runPane(["cwd", "--hook", "/tmp"]);
		expect(both.status).toBe(2);
		expect(both.stderr).toContain(
			"use only one of <directory>, --hook, --clear",
		);

		const notDirectory = runPane(["cwd", "/no/such/directory/here"]);
		expect(notDirectory.status).toBe(1);
		expect(notDirectory.stderr).toContain(
			"not a directory: /no/such/directory/here",
		);
	});
});
