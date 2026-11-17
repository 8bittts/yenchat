import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

type ProcResult = {
	status: number | null;
	signal: NodeJS.Signals | null;
	stdout: string;
	stderr: string;
};

const repoRoot = process.cwd();
const scannerScript = join(
	repoRoot,
	"scripts/13-scan-artifact-fingerprints.sh",
);

function runScanner(
	args: string[],
	extraEnv: Record<string, string> = {},
): ProcResult {
	const proc = spawnSync("bash", [scannerScript, ...args], {
		cwd: repoRoot,
		encoding: "utf8",
		env: { ...process.env, ...extraEnv },
	});
	return {
		status: proc.status,
		signal: proc.signal,
		stdout: proc.stdout ?? "",
		stderr: proc.stderr ?? "",
	};
}

function withTempDir(fn: (dir: string) => void) {
	const dir = mkdtempSync(join(tmpdir(), "yen-fingerprint-test-"));
	try {
		fn(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function createAppFixture(root: string) {
	const appPath = join(root, "YEN.app");
	mkdirSync(join(appPath, "Contents", "MacOS"), { recursive: true });
	mkdirSync(join(appPath, "Contents", "_CodeSignature"), { recursive: true });
	mkdirSync(
		join(appPath, "Contents", "Resources", "yen", "shell-integration", "bash"),
		{ recursive: true },
	);

	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"bash",
			"ghostty.bash",
		),
		"# fixture",
		"utf8",
	);

	writeFileSync(
		join(appPath, "Contents", "_CodeSignature", "CodeResources"),
		"<key>Resources/yen/themes/Ghostty Default Style Dark</key>\n",
		"utf8",
	);

	writeFileSync(
		join(appPath, "Contents", "MacOS", "yen"),
		[
			"https://github.com/ghostty-org/ghostty/edit/main/src/input/Binding.zig",
			"cache: .zig-global-cache/build-artifacts",
		].join("\n"),
		"utf8",
	);

	return appPath;
}

function createRenamedAppFixture(root: string) {
	const appPath = join(root, "YEN.app");
	mkdirSync(join(appPath, "Contents", "MacOS"), { recursive: true });
	mkdirSync(join(appPath, "Contents", "_CodeSignature"), { recursive: true });
	mkdirSync(
		join(appPath, "Contents", "Resources", "yen", "shell-integration", "bash"),
		{ recursive: true },
	);
	mkdirSync(
		join(appPath, "Contents", "Resources", "yen", "shell-integration", "zsh"),
		{ recursive: true },
	);
	mkdirSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"fish",
			"vendor_conf.d",
		),
		{ recursive: true },
	);
	mkdirSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"elvish",
			"lib",
		),
		{ recursive: true },
	);
	mkdirSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"nushell",
			"vendor",
			"autoload",
		),
		{ recursive: true },
	);
	mkdirSync(join(appPath, "Contents", "Resources", "yen", "themes"), {
		recursive: true,
	});

	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"bash",
			"yen.bash",
		),
		"# bash",
		"utf8",
	);
	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"zsh",
			"yen-integration",
		),
		"# zsh",
		"utf8",
	);
	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"fish",
			"vendor_conf.d",
			"yen-shell-integration.fish",
		),
		"# fish",
		"utf8",
	);
	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"elvish",
			"lib",
			"yen-integration.elv",
		),
		"# elvish",
		"utf8",
	);
	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"shell-integration",
			"nushell",
			"vendor",
			"autoload",
			"yen.nu",
		),
		"export module yen {}",
		"utf8",
	);
	writeFileSync(
		join(
			appPath,
			"Contents",
			"Resources",
			"yen",
			"themes",
			"YEN Default Style Dark",
		),
		"# theme",
		"utf8",
	);
	writeFileSync(
		join(appPath, "Contents", "_CodeSignature", "CodeResources"),
		[
			"<key>Resources/yen/shell-integration/bash/yen.bash</key>",
			"<key>Resources/yen/shell-integration/nushell/vendor/autoload/yen.nu</key>",
			"<key>Resources/yen/themes/YEN Default Style Dark</key>",
		].join("\n"),
		"utf8",
	);
	writeFileSync(
		join(appPath, "Contents", "MacOS", "yen"),
		"binary without residue",
		"utf8",
	);

	return appPath;
}

function createCodesigOnlyFixture(root: string) {
	const appPath = createRenamedAppFixture(root);
	writeFileSync(
		join(appPath, "Contents", "_CodeSignature", "CodeResources"),
		"<key>Resources/yen/shell-integration/bash/ghostty.bash</key>\n",
		"utf8",
	);
	return appPath;
}

describe("artifact fingerprint scanner", () => {
	test("enforce mode fails when residual fingerprint signals exist", () => {
		withTempDir((dir) => {
			const appPath = createAppFixture(dir);
			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);

			expect(res.status).toBe(2);
			expect(res.stdout).toContain("Artifact fingerprint scan");
			expect(res.stdout).toContain("mode=enforce");
			expect(res.stdout).toContain("remaining=");
			expect(res.stdout).toContain("path:ghostty|");
			expect(res.stdout).toContain("binary:ghostty_upstream_url|");
			expect(res.stdout).toContain("codesig:ghostty|");
		});
	});

	test("report mode returns success while still surfacing findings", () => {
		withTempDir((dir) => {
			const appPath = createAppFixture(dir);
			const res = runScanner(["--app", appPath, "--gate-mode", "report"]);

			expect(res.status).toBe(0);
			expect(res.stdout).toContain("mode=report");
			expect(res.stdout).toContain("remaining=");
			expect(res.stdout).toContain("Remaining findings:");
		});
	});

	test("allowlist can suppress matched findings in enforce mode", () => {
		withTempDir((dir) => {
			const appPath = createAppFixture(dir);
			const allowlistPath = join(dir, "allowlist.txt");
			writeFileSync(
				allowlistPath,
				["^path:.*", "^codesig:.*", "^binary:.*"].join("\n"),
				"utf8",
			);

			const res = runScanner([
				"--app",
				appPath,
				"--gate-mode",
				"enforce",
				"--allowlist",
				allowlistPath,
			]);

			expect(res.status).toBe(0);
			expect(res.stdout).toContain("allowlisted=");
			expect(res.stdout).toContain("remaining=0");
		});
	});

	test("off mode skips scanning", () => {
		const res = runScanner(["--gate-mode", "off"]);
		expect(res.status).toBe(0);
		expect(res.stdout).toContain("Result: skipped");
		expect(res.stdout).toContain("mode=off");
	});

	test("yen-branded shell/theme filenames do not trigger path residues", () => {
		withTempDir((dir) => {
			const appPath = createRenamedAppFixture(dir);
			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);

			expect(res.status).toBe(0);
			expect(res.stdout).toContain("remaining=0");
			expect(res.stdout).toContain("mode=enforce");
			expect(res.stdout).not.toContain("path:ghostty|");
			expect(res.stdout).not.toContain("codesig:ghostty|");
		});
	});

	test("locale catalogs are scanned for ghostty branding residues", () => {
		withTempDir((dir) => {
			const appPath = createRenamedAppFixture(dir);
			const localeDir = join(
				appPath,
				"Contents",
				"Resources",
				"locale",
				"en_US.UTF-8",
				"LC_MESSAGES",
			);
			mkdirSync(localeDir, { recursive: true });
			writeFileSync(
				join(localeDir, "com.yenchat.yen.mo"),
				[
					"About Ghostty",
					"Project-Id-Version: com.mitchellh.ghostty",
					"Open in Ghostty",
				].join("\n"),
				"utf8",
			);

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(2);
			expect(res.stdout).toContain("locale:ghostty|");
			expect(res.stdout).toContain("locale:com_mitchellh_ghostty|");
		});
	});

	test("yen provenance markers do not trigger ghostty/zcache binary patterns", () => {
		withTempDir((dir) => {
			const appPath = createRenamedAppFixture(dir);
			writeFileSync(
				join(appPath, "Contents", "MacOS", "yen"),
				[
					"https://github.com/8bittts/yenchat/commit/abcd1234",
					"build cache: .yen-zig-global-cache/p/cache",
				].join("\n"),
				"utf8",
			);

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(0);
			expect(res.stdout).toContain("remaining=0");
			expect(res.stdout).not.toContain("binary:ghostty_upstream_url|");
			expect(res.stdout).not.toContain("binary:zig_global_cache|");
		});
	});

	test("skip-codesig suppresses local codesign metadata-only residues", () => {
		withTempDir((dir) => {
			const appPath = createCodesigOnlyFixture(dir);

			const enforceRes = runScanner([
				"--app",
				appPath,
				"--gate-mode",
				"enforce",
			]);
			expect(enforceRes.status).toBe(2);
			expect(enforceRes.stdout).toContain("codesig:ghostty|");

			const skipCodesigRes = runScanner([
				"--app",
				appPath,
				"--gate-mode",
				"enforce",
				"--skip-codesig",
			]);
			expect(skipCodesigRes.status).toBe(0);
			expect(skipCodesigRes.stdout).toContain("Code-signature scan: off");
			expect(skipCodesigRes.stdout).toContain("remaining=0");
		});
	});

	test("missing CodeResources does not abort codesign scanning", () => {
		withTempDir((dir) => {
			const appPath = join(dir, "YEN.app");
			mkdirSync(join(appPath, "Contents", "MacOS"), { recursive: true });
			writeFileSync(join(appPath, "Contents", "MacOS", "yen"), "ok", "utf8");

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(0);
			expect(res.stdout).toContain("Code-signature scan: on");
			expect(res.stdout).toContain("remaining=0");
		});
	});

	test("uppercase ghostty residues are detected", () => {
		withTempDir((dir) => {
			const appPath = createRenamedAppFixture(dir);
			writeFileSync(
				join(
					appPath,
					"Contents",
					"Resources",
					"yen",
					"themes",
					"GHOSTTY Uppercase Residue",
				),
				"# residue",
				"utf8",
			);

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(2);
			expect(res.stdout).toContain("path:ghostty|");
		});
	});

	test("mach-o payloads beyond main binary are scanned", () => {
		withTempDir((dir) => {
			if (process.platform !== "darwin") {
				return;
			}

			const appPath = createRenamedAppFixture(dir);
			const helperDir = join(appPath, "Contents", "Frameworks");
			const helperBinary = join(helperDir, "HelperBinary");

			mkdirSync(helperDir, { recursive: true });
			const compile = spawnSync("clang", ["-o", helperBinary, "-x", "c", "-"], {
				input: [
					'static const char *kGhosttyUpstream = "https://github.com/ghostty-org/ghostty/commit/extra";',
					"int main(void) { return kGhosttyUpstream[0] == '\\0'; }",
				].join("\n"),
				encoding: "utf8",
			});
			expect(compile.status).toBe(0);
			expect(compile.stderr ?? "").toBe("");

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(2);
			expect(res.stdout).toContain("binary:ghostty_upstream_url|");
			expect(res.stdout).toContain("Contents/Frameworks/HelperBinary");
		});
	});

	test("bundled shell CLI is scanned for fingerprint residues", () => {
		withTempDir((dir) => {
			const appPath = createRenamedAppFixture(dir);
			const binDir = join(appPath, "Contents", "Resources", "bin");
			mkdirSync(binDir, { recursive: true });
			writeFileSync(
				join(binDir, "yen"),
				[
					"#!/bin/bash",
					"echo https://github.com/ghostty-org/ghostty",
					"echo com.mitchellh.ghostty",
				].join("\n"),
				"utf8",
			);

			const res = runScanner(["--app", appPath, "--gate-mode", "enforce"]);
			expect(res.status).toBe(2);
			expect(res.stdout).toContain("binary:ghostty_upstream_url|");
			expect(res.stdout).toContain("binary:com_mitchellh_ghostty|");
			expect(res.stdout).toContain("Contents/Resources/bin/yen");
		});
	});

	// The binary/locale strings scans run with bounded concurrency
	// (YEN_FINGERPRINT_SCAN_JOBS). Worker scheduling must NEVER change the result
	// set — findings are sort -u'd before allowlisting. This pins that invariant so
	// a future refactor of the parallel scan can't silently drop or reorder coverage.
	test("parallel scan is deterministic across job counts (serial == concurrent)", () => {
		withTempDir((dir) => {
			if (process.platform !== "darwin") {
				return;
			}

			const appPath = createRenamedAppFixture(dir);
			const helperDir = join(appPath, "Contents", "Frameworks");
			const helperBinary = join(helperDir, "HelperBinary");
			mkdirSync(helperDir, { recursive: true });
			const compile = spawnSync("clang", ["-o", helperBinary, "-x", "c", "-"], {
				input: [
					'static const char *kGhosttyUpstream = "https://github.com/ghostty-org/ghostty/commit/extra";',
					"int main(void) { return kGhosttyUpstream[0] == '\\0'; }",
				].join("\n"),
				encoding: "utf8",
			});
			expect(compile.status).toBe(0);

			// Empty allowlist + report mode surfaces every finding line, so a diff of
			// the printed findings is a diff of the full result set.
			const emptyAllowlist = join(dir, "empty-allowlist.txt");
			writeFileSync(emptyAllowlist, "", "utf8");
			const scanArgs = [
				"--app",
				appPath,
				"--gate-mode",
				"report",
				"--allowlist",
				emptyAllowlist,
			];

			const findingsFor = (jobs: string) => {
				const res = runScanner(scanArgs, {
					YEN_FINGERPRINT_SCAN_JOBS: jobs,
				});
				expect(res.status).toBe(0); // report mode never exits non-zero
				return res.stdout
					.split("\n")
					.filter((l) => l.startsWith("  ! "))
					.sort()
					.join("\n");
			};

			const serial = findingsFor("1");
			const concurrent = findingsFor("6");

			// Must find the planted residue regardless of concurrency...
			expect(serial).toContain("binary:ghostty_upstream_url|");
			expect(serial).toContain("Contents/Frameworks/HelperBinary");
			// ...and the full finding set must be byte-identical across job counts.
			expect(concurrent).toBe(serial);
		});
	});

	// FAIL-CLOSED: a payload the scanner cannot read must surface as a finding, never
	// be silently dropped from coverage. The parallel worker writes its findings to a
	// ".partial" file that is atomically renamed to its output only on completion, and
	// an unreadable file emits a synthetic scan_error — so an unreadable catalog trips
	// the enforce gate instead of passing as clean.
	test("unreadable locale catalog fails closed (scan_error, not silently skipped)", () => {
		withTempDir((dir) => {
			if (process.platform !== "darwin") {
				return;
			}

			const appPath = join(dir, "YEN.app");
			const moDir = join(
				appPath,
				"Contents",
				"Resources",
				"locale",
				"zz",
				"LC_MESSAGES",
			);
			mkdirSync(join(appPath, "Contents", "MacOS"), { recursive: true });
			mkdirSync(moDir, { recursive: true });
			// Minimal, residue-free main binary so the app is otherwise clean.
			writeFileSync(join(appPath, "Contents", "MacOS", "yen"), "ok", "utf8");

			const moPath = join(moDir, "messages.mo");
			writeFileSync(moPath, "GETTEXT-fixture", "utf8");
			chmodSync(moPath, 0o000);

			// Skip if this environment can still read a 000 file (e.g. running as root).
			let stillReadable = true;
			try {
				readFileSync(moPath);
			} catch {
				stillReadable = false;
			}
			if (stillReadable) {
				chmodSync(moPath, 0o644);
				return;
			}

			const res = runScanner([
				"--app",
				appPath,
				"--gate-mode",
				"enforce",
				"--skip-codesig",
			]);
			chmodSync(moPath, 0o644); // restore so tempdir cleanup can unlink

			expect(res.status).toBe(2);
			expect(res.stdout).toContain("locale:scan_error");
		});
	});
});
