import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	chmodSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	realpathSync,
	rmSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repoRoot = process.cwd();
const lazygitAliasPath = join(repoRoot, "yen-cli/commands/core/lazygit");
const gitlazyAliasPath = join(repoRoot, "yen-cli/commands/core/gitlazy");
const gityenAliasPath = join(repoRoot, "yen-cli/commands/core/gityen");
const webCommandPath = join(repoRoot, "yen-cli/commands/core/web");
const zshIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/zsh/yen-integration.zsh",
);
const bashIntegrationPath = join(
	repoRoot,
	"yen-terminal/customizations/shell-integration/bash/yen-integration.bash",
);
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function withSandbox(
	run: (ctx: {
		binDir: string;
		cmdDir: string;
		libDir: string;
		logFile: string;
		root: string;
	}) => void,
) {
	const root = mkdtempSync(join(tmpdir(), "yen-cli-alias-"));
	const binDir = join(root, "bin");
	const cmdDir = join(root, "commands", "core");
	const libDir = join(root, "lib");
	const logFile = join(root, "calls.log");

	mkdirSync(binDir, { recursive: true });
	mkdirSync(cmdDir, { recursive: true });
	mkdirSync(libDir, { recursive: true });

	writeFileSync(join(libDir, "init.sh"), "#!/bin/bash\n", "utf8");
	writeFileSync(logFile, "", "utf8");

	writeFileSync(
		join(cmdDir, "yengit"),
		`#!/bin/bash
printf 'yengit\\t%s\\n' "$*" >> "${logFile}"
`,
		"utf8",
	);
	chmodSync(join(cmdDir, "yengit"), 0o755);

	writeFileSync(
		join(binDir, "yen"),
		`#!/bin/bash
printf 'yen\\t%s\\n' "$*" >> "${logFile}"
`,
		"utf8",
	);
	chmodSync(join(binDir, "yen"), 0o755);

	try {
		run({ binDir, cmdDir, libDir, logFile, root });
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

function readLog(logFile: string): string[] {
	const raw = readFileSync(logFile, "utf8").trim();
	return raw ? raw.split(/\r?\n/) : [];
}

function withFakeNoRunningYen(
	run: (ctx: { env: NodeJS.ProcessEnv; root: string }) => void,
) {
	const root = mkdtempSync(join(tmpdir(), "yen-web-no-app-"));
	const binDir = join(root, "bin");
	mkdirSync(binDir, { recursive: true });

	writeFileSync(
		join(binDir, "pgrep"),
		`#!/bin/bash
exit 1
`,
		"utf8",
	);
	chmodSync(join(binDir, "pgrep"), 0o755);

	writeFileSync(
		join(binDir, "osascript"),
		`#!/bin/bash
echo "osascript should not be called when YEN is not running" >&2
exit 99
`,
		"utf8",
	);
	chmodSync(join(binDir, "osascript"), 0o755);

	try {
		run({
			root,
			env: {
				...process.env,
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
				YEN_LIB: join(repoRoot, "yen-cli/lib"),
			},
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

function withFakeRunningYen(
	run: (ctx: { env: NodeJS.ProcessEnv; logFile: string; root: string }) => void,
) {
	const root = mkdtempSync(join(tmpdir(), "yen-web-running-app-"));
	const binDir = join(root, "bin");
	const logFile = join(root, "osascript-env.log");
	mkdirSync(binDir, { recursive: true });

	writeFileSync(
		join(binDir, "pgrep"),
		`#!/bin/bash
exit 0
`,
		"utf8",
	);
	chmodSync(join(binDir, "pgrep"), 0o755);

	writeFileSync(
		join(binDir, "osascript"),
		`#!/bin/bash
{
  printf 'action=%s\\n' "$YEN_WEB_ACTION"
  printf 'target_executable=%s\\n' "$YEN_WEB_TARGET_EXECUTABLE_PATH"
} >> "${logFile}"
printf '{"accepted":true,"message":"window=closed split=closed","acknowledged_executable_path":"%s"}\\n' "$YEN_WEB_TARGET_EXECUTABLE_PATH" > "$YEN_WEB_RESPONSE_PATH"
exit 0
`,
		"utf8",
	);
	chmodSync(join(binDir, "osascript"), 0o755);

	try {
		run({
			root,
			logFile,
			env: {
				...process.env,
				PATH: `${binDir}:${process.env.PATH ?? ""}`,
			},
		});
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
}

describe("CLI alias parity guards", () => {
	test("usage help advertises the main alias families without alias boilerplate", () => {
		const res = spawnSync(yenBinPath, [], {
			cwd: repoRoot,
			encoding: "utf8",
			env: process.env,
		});
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;

		expect(res.status).toBe(0);
		expect(output).toContain("System Tools:");
		expect(output).toContain("web  Native browser commands");
		expect(output).toContain("browse (files, fm)");
		expect(output).toContain("fastfetch (fetch, fast)");
		expect(output).toContain("yengit (lazygit, gitlazy, gityen)");
		expect(output).not.toContain("Alias for yengit");
	});

	test("web command exposes the native browser command contract", () => {
		const source = readFileSync(webCommandPath, "utf8");

		expect(source).toContain("com.yenchat.yen.webCommand");
		expect(source).toContain("resolve_target_executable_path");
		expect(source).toContain("resource_root");
		expect(source).toContain("acknowledged_executable_path");
		expect(source).toContain(
			'var schemaVersion = targetExecutablePath.length > 0 ? "2" : "1"',
		);
		expect(source).toContain('"schema_version": schemaVersion');
		expect(source).toContain("YEN_WEB_ALLOW_TARGET_EXECUTABLE_PATH");
		expect(source).toContain("YEN_WEB_TARGET_EXECUTABLE_PATH");
		expect(source).toContain("YEN_WEB_TARGET");
		expect(source).toContain("target_executable_path");
		expect(source).toContain("userInfo.target = target");
		expect(source).toContain("yen web open");
		expect(source).toContain("yen web back");
		expect(source).toContain("yen web forward");
		expect(source).toContain("yen web reload");
		expect(source).toContain("yen web close");
		expect(source).toContain("yen web status");
		expect(source).toContain("--split");
		expect(source).toContain("--target window|--target split");
		expect(source).toContain("--target target");
		expect(source).toContain("automatic, window, split, or focused");
		expect(source).toContain("YEN.app is not running");

		const res = spawnSync(webCommandPath, ["--help"], {
			cwd: repoRoot,
			encoding: "utf8",
			env: {
				...process.env,
				YEN_LIB: join(repoRoot, "yen-cli/lib"),
			},
		});

		expect(res.status).toBe(0);
		expect(res.stdout).toContain("yen web open");
		expect(res.stdout).toContain(
			"--split requires an active YEN terminal window",
		);
		expect(res.stdout).toContain(
			"stateful command targets are automatic, window, split, or focused",
		);
		expect(res.stdout).toContain(
			"status prints acknowledged_executable=<path>",
		);
	});

	test("web command derives targeted executable paths before dispatch", () => {
		withFakeRunningYen(({ env, logFile, root }) => {
			const appResources = join(root, "YEN.app", "Contents", "Resources");
			const appExecutable = join(root, "YEN.app", "Contents", "MacOS", "yen");
			mkdirSync(join(appResources, "lib"), { recursive: true });
			mkdirSync(join(root, "YEN.app", "Contents", "MacOS"), {
				recursive: true,
			});
			writeFileSync(join(appResources, "lib", "init.sh"), "#!/bin/bash\n");
			writeFileSync(appExecutable, "#!/bin/bash\n");
			chmodSync(appExecutable, 0o755);

			const appRes = spawnSync(webCommandPath, ["status"], {
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...env,
					YEN_LIB: join(appResources, "lib"),
					YEN_RESOURCES: appResources,
				},
			});

			expect(appRes.status).toBe(0);
			expect(appRes.stdout).toContain(
				`acknowledged_executable=${realpathSync(appExecutable)}`,
			);
			expect(readFileSync(logFile, "utf8")).toContain(
				`target_executable=${realpathSync(appExecutable)}`,
			);
		});

		withFakeRunningYen(({ env, logFile, root }) => {
			const devResources = join(root, "workspace", "yen-cli");
			const devExecutable = join(
				root,
				"workspace",
				"yen-terminal",
				"ghostty",
				"zig-out",
				"YEN.app",
				"Contents",
				"MacOS",
				"yen",
			);
			mkdirSync(join(devResources, "lib"), { recursive: true });
			mkdirSync(join(devExecutable, ".."), { recursive: true });
			writeFileSync(join(devResources, "lib", "init.sh"), "#!/bin/bash\n");
			writeFileSync(devExecutable, "#!/bin/bash\n");
			chmodSync(devExecutable, 0o755);

			const devRes = spawnSync(webCommandPath, ["status"], {
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...env,
					YEN_LIB: join(devResources, "lib"),
				},
			});

			expect(devRes.status).toBe(0);
			expect(devRes.stdout).toContain(
				`acknowledged_executable=${realpathSync(devExecutable)}`,
			);
			expect(readFileSync(logFile, "utf8")).toContain(
				`target_executable=${realpathSync(devExecutable)}`,
			);
		});
	});

	test("web command keeps schema-one fallback and explicit target override", () => {
		withFakeRunningYen(({ env, logFile, root }) => {
			const devResources = join(root, "workspace", "yen-cli");
			mkdirSync(join(devResources, "lib"), { recursive: true });
			writeFileSync(join(devResources, "lib", "init.sh"), "#!/bin/bash\n");

			const fallbackRes = spawnSync(webCommandPath, ["status"], {
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...env,
					YEN_LIB: join(devResources, "lib"),
				},
			});

			expect(fallbackRes.status).toBe(0);
			expect(fallbackRes.stdout).not.toContain("acknowledged_executable=");
			expect(readFileSync(logFile, "utf8")).toContain("target_executable=\n");
		});

		withFakeRunningYen(({ env, logFile, root }) => {
			const devResources = join(root, "workspace", "yen-cli");
			const explicitTarget = join(
				root,
				"missing",
				"YEN.app",
				"Contents",
				"MacOS",
				"yen",
			);
			mkdirSync(join(devResources, "lib"), { recursive: true });
			writeFileSync(join(devResources, "lib", "init.sh"), "#!/bin/bash\n");

			const overrideRes = spawnSync(webCommandPath, ["status"], {
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...env,
					YEN_LIB: join(devResources, "lib"),
					YEN_WEB_ALLOW_TARGET_EXECUTABLE_PATH: "1",
					YEN_WEB_TARGET_EXECUTABLE_PATH: explicitTarget,
				},
			});

			expect(overrideRes.status).toBe(0);
			expect(overrideRes.stdout).toContain(
				`acknowledged_executable=${explicitTarget}`,
			);
			expect(readFileSync(logFile, "utf8")).toContain(
				`target_executable=${explicitTarget}`,
			);
		});
	});

	test("web command fails closed when YEN is not running", () => {
		withFakeNoRunningYen(({ env }) => {
			const statusRes = spawnSync(webCommandPath, ["status"], {
				cwd: repoRoot,
				encoding: "utf8",
				env,
			});

			expect(statusRes.status).toBe(0);
			expect(statusRes.stdout).toContain("YEN.app: not running");
			expect(statusRes.stderr).not.toContain("osascript should not be called");

			const openRes = spawnSync(
				webCommandPath,
				["open", "https://yen.chat/docs"],
				{
					cwd: repoRoot,
					encoding: "utf8",
					env,
				},
			);

			expect(openRes.status).toBe(1);
			expect(openRes.stderr).toContain("YEN.app is not running");
			expect(openRes.stderr).not.toContain("osascript should not be called");
		});
	});

	test("web command validates user input before app dispatch", () => {
		const invalidTargetRes = spawnSync(
			webCommandPath,
			["open", "--target", "sidebar", "https://yen.chat/docs"],
			{
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...process.env,
					YEN_LIB: join(repoRoot, "yen-cli/lib"),
				},
			},
		);

		expect(invalidTargetRes.status).toBe(2);
		expect(invalidTargetRes.stderr).toContain(
			"yen web: --target must be window or split",
		);

		const invalidStatefulTargetRes = spawnSync(
			webCommandPath,
			["reload", "--target", "sidebar"],
			{
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...process.env,
					YEN_LIB: join(repoRoot, "yen-cli/lib"),
				},
			},
		);

		expect(invalidStatefulTargetRes.status).toBe(2);
		expect(invalidStatefulTargetRes.stderr).toContain(
			"yen web: --target must be window, split, focused, or automatic",
		);

		const extraURLRes = spawnSync(
			webCommandPath,
			["open", "https://yen.chat/docs", "https://example.com"],
			{
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...process.env,
					YEN_LIB: join(repoRoot, "yen-cli/lib"),
				},
			},
		);

		expect(extraURLRes.status).toBe(2);
		expect(extraURLRes.stderr).toContain("yen web: open accepts one URL");

		const statefulPositionalRes = spawnSync(
			webCommandPath,
			["close", "https://yen.chat/docs"],
			{
				cwd: repoRoot,
				encoding: "utf8",
				env: {
					...process.env,
					YEN_LIB: join(repoRoot, "yen-cli/lib"),
				},
			},
		);

		expect(statefulPositionalRes.status).toBe(2);
		expect(statefulPositionalRes.stderr).toContain(
			"yen web: close does not accept positional arguments",
		);
	});

	test("lazygit wrapper commands delegate to yengit at runtime", () => {
		withSandbox(({ cmdDir, libDir, logFile }) => {
			const env = {
				...process.env,
				YEN_CMD_DIR: join(cmdDir, ".."),
				YEN_LIB: libDir,
			};

			for (const wrapper of [
				lazygitAliasPath,
				gitlazyAliasPath,
				gityenAliasPath,
			]) {
				const res = spawnSync(wrapper, ["status", "--short"], {
					cwd: repoRoot,
					encoding: "utf8",
					env,
				});
				expect(res.status).toBe(0);
			}

			expect(readLog(logFile)).toEqual([
				"yengit\tstatus --short",
				"yengit\tstatus --short",
				"yengit\tstatus --short",
			]);
		});
	});

	test("fetch and fast route the yen CLI to fastfetch", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-cli-route-"));
		try {
			const logFile = join(root, "calls.log");
			mkdirSync(join(root, "bin"), { recursive: true });
			mkdirSync(join(root, "commands", "core"), { recursive: true });
			writeFileSync(
				join(root, "bin", "yen"),
				readFileSync(yenBinPath, "utf8"),
				"utf8",
			);
			chmodSync(join(root, "bin", "yen"), 0o755);
			symlinkSync(join(repoRoot, "yen-cli/lib"), join(root, "lib"));
			writeFileSync(
				join(root, "commands", "core", "fastfetch"),
				`#!/bin/bash
printf 'fastfetch\\t%s\\n' "$*" >> "${logFile}"
`,
				"utf8",
			);
			chmodSync(join(root, "commands", "core", "fastfetch"), 0o755);

			// Development mode: an unset YEN_LIB makes yen resolve lib/ beside bin/.
			const { YEN_LIB: _appLib, ...env } = process.env;
			for (const args of [
				["fetch", "--logo"],
				["fast", "--brief"],
			]) {
				const res = spawnSync(join(root, "bin", "yen"), args, {
					cwd: root,
					encoding: "utf8",
					env,
				});
				expect(res.stderr).toBe("");
				expect(res.status).toBe(0);
			}
			expect(readLog(logFile)).toEqual([
				"fastfetch\t--logo",
				"fastfetch\t--brief",
			]);
		} finally {
			rmSync(root, { recursive: true, force: true });
		}
	});

	test("shell integrations route representative aliases back through the YEN CLI", () => {
		withSandbox(({ binDir, logFile }) => {
			const commonEnv = {
				...process.env,
				HOME: join(binDir, ".."),
			};

			const zshScript = `
YEN_BIN_DIR=${JSON.stringify(binDir)}
source ${JSON.stringify(zshIntegrationPath)}
files repo
monitor --cpu
fast --brief
gitlazy status
`;
			const zshRes = spawnSync("zsh", ["-f", "-c", zshScript], {
				cwd: repoRoot,
				encoding: "utf8",
				env: commonEnv,
			});
			expect(zshRes.status).toBe(0);

			const bashScript = `
YEN_BIN_DIR=${JSON.stringify(binDir)}
source ${JSON.stringify(bashIntegrationPath)}
fm docs
fetch --logo
fast --logo
gityen diff
`;
			const bashRes = spawnSync(
				"bash",
				["--noprofile", "--norc", "-ic", bashScript],
				{
					cwd: repoRoot,
					encoding: "utf8",
					env: commonEnv,
				},
			);
			expect(bashRes.status).toBe(0);

			const log = readLog(logFile);
			expect(log).toContain("yen\tbrowse repo");
			expect(log).toContain("yen\tmonitor --cpu");
			expect(log).toContain("yen\tgitlazy status");
			expect(log).toContain("yen\tbrowse docs");
			expect(log).toContain("yen\tfetch --logo");
			expect(log).toContain("yen\tfast --brief");
			expect(log).toContain("yen\tfast --logo");
			expect(log).toContain("yen\tgityen diff");
			expect(log.every((entry) => entry.startsWith("yen\t"))).toBe(true);
		});
	});

	test("shell integrations shadow retired companion commands with a consistent error", () => {
		withSandbox(({ binDir, logFile }) => {
			const commonEnv = {
				...process.env,
				HOME: join(binDir, ".."),
			};

			const zshScript = `
YEN_BIN_DIR=${JSON.stringify(binDir)}
source ${JSON.stringify(zshIntegrationPath)}
chat
`;
			const zshRes = spawnSync("zsh", ["-f", "-c", zshScript], {
				cwd: repoRoot,
				encoding: "utf8",
				env: commonEnv,
			});
			expect(zshRes.status).toBe(127);
			expect(zshRes.stderr).toContain(
				"chat: retired YEN companion command; use the dedicated app or current workflow instead",
			);

			const bashScript = `
YEN_BIN_DIR=${JSON.stringify(binDir)}
source ${JSON.stringify(bashIntegrationPath)}
calendar
`;
			const bashRes = spawnSync(
				"bash",
				["--noprofile", "--norc", "-ic", bashScript],
				{
					cwd: repoRoot,
					encoding: "utf8",
					env: commonEnv,
				},
			);
			expect(bashRes.status).toBe(127);
			expect(bashRes.stderr).toContain(
				"calendar: retired YEN companion command; use the dedicated app or current workflow instead",
			);

			const unexpectedDelegates = readLog(logFile).filter(
				(entry) => !entry.startsWith("yen\tide detect --cached --format env"),
			);
			expect(unexpectedDelegates).toEqual([]);
		});
	});
});
