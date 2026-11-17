import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	copyFileSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const repoRoot = process.cwd();
const sourceDiagnosePath = join(
	repoRoot,
	"yen-terminal/customizations/diagnose-yen-cli.sh",
);
const sourceFixPath = join(
	repoRoot,
	"yen-terminal/customizations/fix-yen-cli.sh",
);
const sourceLibPath = join(repoRoot, "scripts/lib/yen-cli-resolve.sh");

const testOnDarwin = process.platform === "darwin" ? test : test.skip;

function makeEnv(overrides: Record<string, string>) {
	const env = { ...process.env };
	env.TERM_PROGRAM = undefined;
	env.TERM_PROGRAM_VERSION = undefined;
	env.YEN_BIN_DIR = undefined;
	env.YEN_RESOURCES_DIR = undefined;
	env.YEN_VERSION = undefined;
	return { ...env, ...overrides };
}

function writeExecutable(path: string, content: string) {
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, content, "utf8");
	chmodSync(path, 0o755);
}

function createSandbox() {
	const root = mkdtempSync(join(tmpdir(), "yen-cli-doctor-"));
	// Mirror the real repo layout so the scripts' REPO_DIR (= <root>/yen-terminal)
	// resolves `$REPO_DIR/../scripts/lib/yen-cli-resolve.sh` inside the sandbox.
	const customizationsDir = join(root, "yen-terminal", "customizations");
	const libDir = join(root, "scripts", "lib");
	const libPath = join(libDir, "yen-cli-resolve.sh");
	const homeDir = join(root, "home");
	const diagnosePath = join(customizationsDir, "diagnose-yen-cli.sh");
	const fixPath = join(customizationsDir, "fix-yen-cli.sh");

	mkdirSync(customizationsDir, { recursive: true });
	mkdirSync(libDir, { recursive: true });
	mkdirSync(homeDir, { recursive: true });
	copyFileSync(sourceDiagnosePath, diagnosePath);
	copyFileSync(sourceFixPath, fixPath);
	copyFileSync(sourceLibPath, libPath);
	chmodSync(diagnosePath, 0o755);
	chmodSync(fixPath, 0o755);
	chmodSync(libPath, 0o755);

	return { customizationsDir, diagnosePath, fixPath, homeDir, root };
}

function createFakeCli(path: string) {
	writeExecutable(
		path,
		`#!/bin/bash
case "$1" in
  --version|version)
    echo "yen 1.2.3"
    ;;
  *)
    echo "ok"
    ;;
esac
`,
	);
}

describe("CLI diagnostics contract", () => {
	testOnDarwin(
		"diagnose treats a missing manual wrapper as expected inside YEN-launched shells",
		() => {
			const sandbox = createSandbox();
			const bundledBinDir = join(sandbox.root, "bundled-bin");
			const shellConfig = join(sandbox.homeDir, ".zshrc");

			mkdirSync(bundledBinDir, { recursive: true });
			writeFileSync(shellConfig, "", "utf8");
			createFakeCli(join(bundledBinDir, "yen"));

			try {
				const res = spawnSync("bash", [sandbox.diagnosePath], {
					cwd: sandbox.root,
					encoding: "utf8",
					env: makeEnv({
						HOME: sandbox.homeDir,
						PATH: `${bundledBinDir}:/usr/bin:/bin:/usr/sbin:/sbin`,
						SHELL: "/bin/zsh",
						TERM_PROGRAM: "yen",
						YEN_BIN_DIR: bundledBinDir,
					}),
				});
				const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

				expect(res.status).toBe(0);
				expect(output).toContain(
					`No manual yen() wrapper in ${shellConfig} (expected inside YEN-launched shells)`,
				);
				expect(output).toContain("Current CLI resolution looks healthy.");
				expect(output).not.toContain("Run: yen init zsh");
			} finally {
				rmSync(sandbox.root, { force: true, recursive: true });
			}
		},
		// The production diagnostic intentionally inventories LaunchServices; a full
		// `lsregister -dump` can exceed Bun's 5-second default under suite-wide load.
		15_000,
	);

	testOnDarwin(
		"diagnose recommends the resolved local-build CLI path instead of a bare yen init command",
		() => {
			const sandbox = createSandbox();
			const shellConfig = join(sandbox.homeDir, ".zshrc");
			const localBuildCliPath = join(
				sandbox.root,
				"yen-terminal",
				"ghostty/zig-out/YEN.app/Contents/Resources/bin/yen",
			);

			writeFileSync(shellConfig, "", "utf8");
			createFakeCli(localBuildCliPath);

			try {
				const res = spawnSync("bash", [sandbox.diagnosePath], {
					cwd: sandbox.root,
					encoding: "utf8",
					env: makeEnv({
						HOME: sandbox.homeDir,
						PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
						SHELL: "/bin/zsh",
					}),
				});
				const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

				expect(res.status).toBe(0);
				expect(output).toContain(`CLI script found: ${localBuildCliPath}`);
				expect(output).toContain(`Run: "${localBuildCliPath}" init zsh`);
				expect(output).not.toContain("Run: yen init zsh");
			} finally {
				rmSync(sandbox.root, { force: true, recursive: true });
			}
		},
		15_000,
	);

	testOnDarwin(
		"fix removes invalid config entries and keeps remediation on the resolved CLI path",
		() => {
			const sandbox = createSandbox();
			const shellConfig = join(sandbox.homeDir, ".zshrc");
			const localBuildCliPath = join(
				sandbox.root,
				"yen-terminal",
				"ghostty/zig-out/YEN.app/Contents/Resources/bin/yen",
			);
			const configDir = join(
				sandbox.homeDir,
				"Library/Application Support/com.yenchat.yen",
			);
			const configFile = join(configDir, "config.yen");

			writeFileSync(shellConfig, "", "utf8");
			mkdirSync(configDir, { recursive: true });
			writeFileSync(
				configFile,
				["font-size = 14", "cli: stale-wrapper", "theme = yen"].join("\n"),
				"utf8",
			);
			createFakeCli(localBuildCliPath);

			try {
				const res = spawnSync("bash", [sandbox.fixPath], {
					cwd: sandbox.root,
					encoding: "utf8",
					env: makeEnv({
						HOME: sandbox.homeDir,
						PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
						SHELL: "/bin/zsh",
					}),
				});
				const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

				expect(res.status).toBe(0);
				expect(readFileSync(configFile, "utf8")).toBe(
					["font-size = 14", "theme = yen"].join("\n"),
				);
				expect(
					readdirSync(configDir).some((name) =>
						name.startsWith("config.yen.backup."),
					),
				).toBe(true);
				expect(output).toContain(
					"Removed invalid 'cli:' entries from config.yen",
				);
				expect(output).toContain(`Run: "${localBuildCliPath}" init zsh`);
				expect(output).not.toContain("Run: yen init zsh");
			} finally {
				rmSync(sandbox.root, { force: true, recursive: true });
			}
		},
	);
});
