import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	cpSync,
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// MIT and Apache-2.0 require their notice in every copy of the software, so
// YEN.app carries one notice per bundled third-party component. The vendor
// baselines are the list of components. The fingerprint gate rejects the
// upstream engine's name in a bundle path, so the engine's notice has a
// neutral file name while its text names the copyright holder.

const repoRoot = process.cwd();
const noticesLib = join(repoRoot, "scripts/lib/third-party-notices.sh");
const noticesDir = join(repoRoot, "yen-terminal/customizations/notices");
const scannerScript = join(
	repoRoot,
	"scripts/13-scan-artifact-fingerprints.sh",
);
const ENGINE_NOTICE = "TerminalEngine.txt";

function runNoticesFunction(name: string, args: string[]) {
	const result = spawnSync(
		"bash",
		["-c", 'source "$1"; shift; "$@"', "bash", noticesLib, name, ...args],
		{ encoding: "utf8" },
	);
	return {
		status: result.status,
		lines: `${result.stdout}${result.stderr}`
			.split("\n")
			.filter((line) => line.length > 0),
	};
}

function withTempDir(run: (dir: string) => void): void {
	const dir = mkdtempSync(join(tmpdir(), "yen-notices-test-"));
	try {
		run(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function write(path: string, contents: string): void {
	mkdirSync(join(path, ".."), { recursive: true });
	writeFileSync(path, contents, "utf8");
}

function vendoredComponents(): string[] {
	return readdirSync(join(repoRoot, "yen-terminal"))
		.map((name) => /^\.(.+)-baseline$/.exec(name)?.[1])
		.filter((name): name is string => name !== undefined)
		.sort();
}

function noticeNameFor(component: string): string {
	return component === "ghostty" ? ENGINE_NOTICE : `${component}.txt`;
}

describe("third-party notices in the repository", () => {
	test("every vendored component has a notice that grants a license and names a copyright holder", () => {
		const components = vendoredComponents();
		// Floor against a short listing: the engine plus seven vendored tools.
		expect(components.length).toBeGreaterThanOrEqual(8);
		expect(components).toContain("ghostty");

		const problems: string[] = [];
		for (const component of components) {
			const path = join(noticesDir, noticeNameFor(component));
			if (!existsSync(path)) {
				problems.push(`${component}: no notice`);
				continue;
			}
			const text = readFileSync(path, "utf8");
			if (!/Permission is hereby granted|Apache License/.test(text)) {
				problems.push(`${component}: no license grant`);
			}
			if (!/copyright/i.test(text)) {
				problems.push(`${component}: no copyright line`);
			}
		}
		expect(problems).toEqual([]);

		const sourceCheck = runNoticesFunction(
			"third_party_notices_source_issues",
			[repoRoot],
		);
		expect(sourceCheck).toEqual({ status: 0, lines: [] });
	});

	test("the engine notice carries the upstream copyright line under a neutral file name", () => {
		const text = readFileSync(join(noticesDir, ENGINE_NOTICE), "utf8");
		expect(text).toContain(
			"Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors",
		);
		expect(text).toContain(
			"The above copyright notice and this permission notice shall be included in all",
		);

		const notices = readdirSync(noticesDir);
		expect(notices.length).toBeGreaterThan(0);
		expect(notices.filter((name) => /ghostty/i.test(name))).toEqual([]);
	});
});

describe("third-party notice gates", () => {
	test("the source check names a vendored component that has no notice", () =>
		withTempDir((root) => {
			write(join(root, "yen-terminal/.bat-baseline"), "upstream_version=1\n");
			write(
				join(root, "yen-terminal/.ghostty-baseline"),
				"upstream_version=1\n",
			);
			write(
				join(root, "yen-terminal/customizations/notices/bat.txt"),
				"MIT License\n",
			);

			const missingEngine = runNoticesFunction(
				"third_party_notices_source_issues",
				[root],
			);
			expect(missingEngine.status).toBe(1);
			expect(missingEngine.lines).toEqual([
				`license notice missing for a vendored component: yen-terminal/customizations/notices/${ENGINE_NOTICE}`,
			]);

			// An empty notice is a missing notice.
			write(
				join(root, "yen-terminal/customizations/notices", ENGINE_NOTICE),
				"",
			);
			expect(
				runNoticesFunction("third_party_notices_source_issues", [root]).status,
			).toBe(1);

			write(
				join(root, "yen-terminal/customizations/notices", ENGINE_NOTICE),
				"MIT License\n",
			);
			expect(
				runNoticesFunction("third_party_notices_source_issues", [root]),
			).toEqual({ status: 0, lines: [] });
		}));

	test("the source check fails closed when it finds no vendor baselines", () =>
		withTempDir((root) => {
			mkdirSync(join(root, "yen-terminal"), { recursive: true });
			const result = runNoticesFunction("third_party_notices_source_issues", [
				root,
			]);
			expect(result.status).toBe(1);
			expect(result.lines.join("\n")).toContain("found no vendor baselines");
		}));

	test("the bundle check requires every tracked notice in the app, byte for byte", () =>
		withTempDir((root) => {
			const tracked = join(root, "yen-terminal/customizations/notices");
			const bundled = join(root, "YEN.app/Contents/Resources/Notices");
			write(join(tracked, "bat.txt"), "MIT License\nbat\n");
			write(join(tracked, ENGINE_NOTICE), "MIT License\nengine\n");
			const check = () =>
				runNoticesFunction("third_party_notices_bundle_issues", [
					root,
					join(root, "YEN.app"),
				]);

			const noFolder = check();
			expect(noFolder.status).toBe(1);
			expect(noFolder.lines).toEqual([
				"license notice not bundled: Contents/Resources/Notices/bat.txt",
				`license notice not bundled: Contents/Resources/Notices/${ENGINE_NOTICE}`,
			]);

			write(join(bundled, "bat.txt"), "MIT License\nbat\n");
			write(join(bundled, ENGINE_NOTICE), "MIT License\n");
			const altered = check();
			expect(altered.status).toBe(1);
			expect(altered.lines).toEqual([
				`bundled license notice differs from its source: Contents/Resources/Notices/${ENGINE_NOTICE}`,
			]);

			write(join(bundled, ENGINE_NOTICE), "MIT License\nengine\n");
			expect(check()).toEqual({ status: 0, lines: [] });
		}));

	test("the bundle check fails closed when no notice is tracked", () =>
		withTempDir((root) => {
			mkdirSync(join(root, "yen-terminal/customizations/notices"), {
				recursive: true,
			});
			mkdirSync(join(root, "YEN.app/Contents/Resources/Notices"), {
				recursive: true,
			});
			const result = runNoticesFunction("third_party_notices_bundle_issues", [
				root,
				join(root, "YEN.app"),
			]);
			expect(result.status).toBe(1);
			expect(result.lines.join("\n")).toContain("found no tracked notices");
		}));

	test("both release gates run the notice checks", () => {
		const preBuild = readFileSync(
			join(repoRoot, "scripts/03-verify-components.sh"),
			"utf8",
		);
		expect(preBuild).toContain(
			'source "$REPO_ROOT/scripts/lib/third-party-notices.sh"',
		);
		expect(preBuild).toContain(
			'third_party_notices_source_issues "$REPO_ROOT"',
		);

		const postBuild = readFileSync(
			join(repoRoot, "scripts/05-detect-failures.sh"),
			"utf8",
		);
		expect(postBuild).toContain(
			'source "$REPO_ROOT/scripts/lib/third-party-notices.sh"',
		);
		expect(postBuild).toContain(
			'third_party_notices_bundle_issues "$REPO_ROOT" "$BUILT_APP"',
		);
	});
});

describe("third-party notices and the fingerprint gate", () => {
	function scan(appPath: string) {
		const result = spawnSync(
			"bash",
			[
				scannerScript,
				"--app",
				appPath,
				"--gate-mode",
				"enforce",
				"--skip-codesig",
			],
			{ cwd: repoRoot, encoding: "utf8" },
		);
		return { status: result.status, stdout: result.stdout };
	}

	function appWithNotices(root: string): string {
		const appPath = join(root, "YEN.app");
		write(join(appPath, "Contents/MacOS/yen"), "launcher fixture\n");
		cpSync(noticesDir, join(appPath, "Contents/Resources/Notices"), {
			recursive: true,
		});
		return appPath;
	}

	test("a bundle that carries the tracked notices passes the scan", () =>
		withTempDir((root) => {
			const appPath = appWithNotices(root);
			expect(
				existsSync(join(appPath, "Contents/Resources/Notices", ENGINE_NOTICE)),
			).toBe(true);

			const result = scan(appPath);
			expect(result.stdout).toContain("remaining=0");
			expect(result.status).toBe(0);
		}));

	test("a notice file named after the upstream engine still fails the scan", () =>
		withTempDir((root) => {
			const appPath = appWithNotices(root);
			write(
				join(appPath, "Contents/Resources/Notices/Ghostty.txt"),
				"MIT License\n",
			);

			const result = scan(appPath);
			expect(result.status).toBe(2);
			expect(result.stdout).toContain("path:ghostty|");
			expect(result.stdout).toContain("Notices/Ghostty.txt");
		}));
});
