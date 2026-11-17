import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	symlinkSync,
	writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { createIdeTemp } from "./fixtures/ide-temp";

const { ideTemp } = createIdeTemp();

const repoRoot = process.cwd();
const yenBinPath = join(repoRoot, "yen-cli/bin/yen");

function runYen(
	args: string[],
	envOverrides: Record<string, string> = {},
	cwd = repoRoot,
) {
	return spawnSync(yenBinPath, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function commandOutput(result: ReturnType<typeof runYen>): string {
	return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
}

function parseJsonOutput(result: ReturnType<typeof runYen>) {
	return JSON.parse(result.stdout || "{}");
}

function createProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(join(root, "package.json"), '{"name":"lsp-fixture"}\n', "utf8");
	return realpathSync(root);
}

function createZigProject(prefix: string) {
	const root = ideTemp(prefix);
	writeFileSync(
		join(root, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	return realpathSync(root);
}

function currentPython3Path() {
	const res = spawnSync("bash", ["-lc", "command -v python3"], {
		encoding: "utf8",
	});
	expect(res.status).toBe(0);
	const python3Path = (res.stdout ?? "").trim();
	expect(python3Path).not.toBe("");
	return python3Path;
}

function createRestrictedPythonPath() {
	const binDir = ideTemp("yen-ide-python-bin-");
	symlinkSync(currentPython3Path(), join(binDir, "python3"));
	return `${binDir}:/usr/bin:/bin`;
}

describe("IDE S3C LSP foundation", () => {
	test(
		"lsp trust/start/status/stop/untrust manages lifecycle, trust registry, and timeline events",
		() => {
			const stateDir = ideTemp("yen-ide-lsp-state-");
			const project = createProject("yen-ide-lsp-project-");
			const env = {
				YEN_IDE_STATE_DIR: stateDir,
				YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
			};

			const initialStatus = runYen(
				["ide", "lsp", "status", "--project", project],
				env,
			);
			const initialOutput = commandOutput(initialStatus);
			expect(initialStatus.status).toBe(0);
			expect(initialOutput).toContain("Trusted:            no");
			expect(initialOutput).toContain("Runtime state:      stopped");

			const trust = runYen(["ide", "lsp", "trust", "--project", project], env);
			expect(trust.status).toBe(0);

			const start = runYen(["ide", "lsp", "start", "--project", project], env);
			const startOutput = commandOutput(start);
			expect(start.status).toBe(0);
			expect(startOutput).toContain("Placeholder LSP runtime started:");

			const runningStatus = runYen(
				["ide", "lsp", "status", "--project", project],
				env,
			);
			const runningOutput = commandOutput(runningStatus);
			expect(runningStatus.status).toBe(0);
			expect(runningOutput).toContain("Trusted:            yes");
			expect(runningOutput).toContain("Runtime state:      running");
			expect(runningOutput).toContain("Health:             healthy");
			expect(runningOutput).toContain("placeholder-socket-daemon");

			const trustedList = runYen(["ide", "lsp", "trusted"], env);
			const trustedOutput = commandOutput(trustedList);
			expect(trustedList.status).toBe(0);
			expect(trustedOutput).toContain(project);

			const envStatus = runYen(
				["ide", "lsp", "status", "--project", project, "--format", "env"],
				env,
			);
			const envOutput = commandOutput(envStatus);
			expect(envStatus.status).toBe(0);
			expect(envOutput).toContain(`export YEN_IDE_LSP_ROOT='${project}'`);
			expect(envOutput).toContain("export YEN_IDE_LSP_TRUSTED='yes'");
			expect(envOutput).toContain("export YEN_IDE_LSP_STATE='running'");
			expect(envOutput).toContain("export YEN_IDE_LSP_SOCKET=");
			expect(envOutput).toContain("export YEN_IDE_LSP_PID_FILE=");
			expect(envOutput).toContain("export YEN_IDE_LSP_STATE_FILE=");
			expect(envOutput).toContain("export YEN_IDE_LSP_DIAGNOSTICS_FILE=");
			expect(envOutput).toContain("export YEN_IDE_LSP_DAEMON_LOG_FILE=");
			expect(envOutput).toContain(
				"export YEN_IDE_LSP_IMPL='placeholder-socket-daemon'",
			);
			expect(envOutput).toContain("export YEN_IDE_LSP_HEALTH='healthy'");

			const jsonStatus = runYen(
				["ide", "lsp", "status", "--project", project, "--format", "json"],
				env,
			);
			expect(jsonStatus.status).toBe(0);
			const jsonPayload = parseJsonOutput(jsonStatus);
			expect(jsonPayload.trusted).toBe(true);
			expect(jsonPayload.runtimeState).toBe("running");
			expect(jsonPayload.protocolStatus).toBe("placeholder");
			expect(jsonPayload.daemonLogFile).toContain("/daemon.log");

			const socketMatch = envOutput.match(
				/export YEN_IDE_LSP_SOCKET='([^']+)'/,
			);
			expect(socketMatch).not.toBeNull();
			const socketPath = socketMatch?.[1] ?? "";
			expect(existsSync(socketPath)).toBe(true);

			const trustFile = readFileSync(
				join(stateDir, "trusted-lsp-projects"),
				"utf8",
			);
			expect(trustFile).toContain(project);

			const stop = runYen(["ide", "lsp", "stop", "--project", project], env);
			const stopOutput = commandOutput(stop);
			expect(stop.status).toBe(0);
			expect(stopOutput).toContain("LSP runtime stopped:");
			expect(existsSync(socketPath)).toBe(false);

			const stoppedStatus = runYen(
				["ide", "lsp", "status", "--project", project],
				env,
			);
			const stoppedOutput = commandOutput(stoppedStatus);
			expect(stoppedStatus.status).toBe(0);
			expect(stoppedOutput).toContain("Runtime state:      stopped");
			expect(stoppedOutput).toContain("Health:             inactive");

			const restart = runYen(
				["ide", "lsp", "start", "--project", project],
				env,
			);
			expect(restart.status).toBe(0);

			const untrust = runYen(["ide", "lsp", "untrust", project], env);
			expect(untrust.status).toBe(0);
			const untrustOutput = commandOutput(untrust);
			expect(untrustOutput).toContain("Removed LSP trust:");

			const trustFileAfter = readFileSync(
				join(stateDir, "trusted-lsp-projects"),
				"utf8",
			);
			expect(trustFileAfter).not.toContain(project);

			const timeline = readFileSync(join(stateDir, "timeline.log"), "utf8");
			expect(timeline).toContain("lsp-trust");
			expect(timeline).toContain("lsp-start");
			expect(timeline).toContain("lsp-stop");
			expect(timeline).toContain("trusted");
			expect(timeline).toContain("untrusted");
		},
		{ timeout: 20_000 },
	);

	test("lsp stop clears stale runtime artifacts without a live process", () => {
		const stateDir = ideTemp("yen-ide-lsp-stale-state-");
		const project = createProject("yen-ide-lsp-stale-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		const projectHashRes = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "env"],
			env,
		);
		const output = commandOutput(projectHashRes);
		const socketPath =
			output.match(/export YEN_IDE_LSP_SOCKET='([^']+)'/)?.[1] ?? "";
		const pidFile =
			output.match(/export YEN_IDE_LSP_PID_FILE='([^']+)'/)?.[1] ?? "";
		const stateFile =
			output.match(/export YEN_IDE_LSP_STATE_FILE='([^']+)'/)?.[1] ?? "";

		mkdirSync(dirname(pidFile), { recursive: true });
		writeFileSync(pidFile, "999999\n", "utf8");
		writeFileSync(stateFile, "impl=placeholder-socket-daemon\n", "utf8");

		const staleStatus = runYen(
			["ide", "lsp", "status", "--project", project],
			env,
		);
		const staleOutput = commandOutput(staleStatus);
		expect(staleStatus.status).toBe(0);
		expect(staleOutput).toContain("Runtime state:      stale");
		expect(staleOutput).toContain("Health:             stale");

		const stop = runYen(["ide", "lsp", "stop", "--project", project], env);
		const stopOutput = commandOutput(stop);
		expect(stop.status).toBe(0);
		expect(stopOutput).toContain("Cleared stale LSP runtime state:");
		expect(existsSync(socketPath)).toBe(false);
		expect(existsSync(pidFile)).toBe(false);
		expect(existsSync(stateFile)).toBe(false);
	});

	test("lsp start clears a stale lifecycle lock owned by a dead process", () => {
		const stateDir = ideTemp("yen-ide-lsp-lock-state-");
		const project = createProject("yen-ide-lsp-lock-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const projectHash = createHash("sha256").update(project).digest("hex");
		const lockDir = join(stateDir, "lsp", "locks", `${projectHash}.lock`);
		mkdirSync(lockDir, { recursive: true });
		writeFileSync(join(lockDir, "pid"), "999999\n", "utf8");

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		const startOutput = commandOutput(start);
		expect(start.status).toBe(0);
		expect(startOutput).toContain("Placeholder LSP runtime started:");

		const status = runYen(["ide", "lsp", "status", "--project", project], env);
		const statusOutput = commandOutput(status);
		expect(status.status).toBe(0);
		expect(statusOutput).toContain("Runtime state:      running");
	});

	test("lsp stop clears stale metadata without killing an unrelated live process", () => {
		const stateDir = ideTemp("yen-ide-lsp-foreign-pid-state-");
		const project = createProject("yen-ide-lsp-foreign-pid-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		const projectHashRes = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "env"],
			env,
		);
		const output = commandOutput(projectHashRes);
		const socketPath =
			output.match(/export YEN_IDE_LSP_SOCKET='([^']+)'/)?.[1] ?? "";
		const pidFile =
			output.match(/export YEN_IDE_LSP_PID_FILE='([^']+)'/)?.[1] ?? "";
		const stateFile =
			output.match(/export YEN_IDE_LSP_STATE_FILE='([^']+)'/)?.[1] ?? "";

		const sleeper = spawn("sleep", ["30"], { stdio: "ignore" });
		expect(sleeper.pid).toBeDefined();
		const foreignPid = `${sleeper.pid ?? ""}`;

		try {
			mkdirSync(dirname(pidFile), { recursive: true });
			writeFileSync(pidFile, `${foreignPid}\n`, "utf8");
			writeFileSync(stateFile, "impl=placeholder-socket-daemon\n", "utf8");

			const staleStatus = runYen(
				["ide", "lsp", "status", "--project", project],
				env,
			);
			const staleOutput = commandOutput(staleStatus);
			expect(staleStatus.status).toBe(0);
			expect(staleOutput).toContain("Runtime state:      stale");
			expect(staleOutput).toContain("Health:             stale");

			const stop = runYen(["ide", "lsp", "stop", "--project", project], env);
			const stopOutput = commandOutput(stop);
			expect(stop.status).toBe(0);
			expect(stopOutput).toContain("Cleared stale LSP runtime state:");
			expect(existsSync(socketPath)).toBe(false);
			expect(existsSync(pidFile)).toBe(false);
			expect(existsSync(stateFile)).toBe(false);

			expect(() => process.kill(sleeper.pid ?? 0, 0)).not.toThrow();
		} finally {
			sleeper.kill("SIGTERM");
		}
	});

	test("lsp start/status explain zig placeholder fallback through the explicit zls posture", () => {
		const stateDir = ideTemp("yen-ide-lsp-zig-state-");
		const project = createZigProject("yen-ide-lsp-zig-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		const startOutput = commandOutput(start);
		expect(start.status).toBe(0);
		expect(startOutput).toContain("Server resolution: unavailable-server");
		expect(startOutput).toContain("Expected server: zls");
		expect(startOutput).toContain("detected zig project; expected zls on PATH");

		const status = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "env"],
			env,
		);
		const statusOutput = commandOutput(status);
		expect(status.status).toBe(0);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_RESOLUTION_STATUS='unavailable-server'",
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_RESOLUTION_REASON='detected zig project; expected zls on PATH'",
		);
		expect(statusOutput).toContain("export YEN_IDE_LSP_EXPECTED_SERVER='zls'");

		expect(
			runYen(["ide", "lsp", "stop", "--project", project], env).status,
		).toBe(0);
	});

	test("lsp start/status explain missing local reference servers before widening the matrix", () => {
		const stateDir = ideTemp("yen-ide-lsp-missing-server-state-");
		const project = createProject("yen-ide-lsp-missing-server-project-");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			PATH: createRestrictedPythonPath(),
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		const startOutput = commandOutput(start);
		expect(start.status).toBe(0);
		expect(startOutput).toContain("Server resolution: unavailable-server");
		expect(startOutput).toContain(
			"Expected server: typescript-language-server --stdio",
		);
		expect(startOutput).toContain("detected javascript project");

		const status = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "env"],
			env,
		);
		const statusOutput = commandOutput(status);
		expect(status.status).toBe(0);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_RESOLUTION_STATUS='unavailable-server'",
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_EXPECTED_SERVER='typescript-language-server --stdio'",
		);
		expect(statusOutput).toContain(
			"export YEN_IDE_LSP_PROTOCOL_STATUS='placeholder'",
		);

		expect(
			runYen(["ide", "lsp", "stop", "--project", project], env).status,
		).toBe(0);
	});

	test("lsp start serializes concurrent callers on the same project lock", async () => {
		const stateDir = ideTemp("yen-ide-lsp-concurrent-state-");
		const project = createProject("yen-ide-lsp-concurrent-project-");
		const env = {
			...process.env,
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const startCommand = ["ide", "lsp", "start", "--project", project];
		const first = spawn(yenBinPath, startCommand, {
			cwd: repoRoot,
			env,
			stdio: "pipe",
		});
		const second = spawn(yenBinPath, startCommand, {
			cwd: repoRoot,
			env,
			stdio: "pipe",
		});

		const settle = (child: ReturnType<typeof spawn>) =>
			new Promise<{ code: number | null; output: string }>((resolve) => {
				const chunks: string[] = [];
				child.stdout?.on("data", (chunk) => chunks.push(String(chunk)));
				child.stderr?.on("data", (chunk) => chunks.push(String(chunk)));
				child.on("close", (code) => resolve({ code, output: chunks.join("") }));
			});

		const [firstResult, secondResult] = await Promise.all([
			settle(first),
			settle(second),
		]);

		expect(firstResult.code).toBe(0);
		expect(secondResult.code).toBe(0);
		expect(
			[firstResult.output, secondResult.output].some((output) =>
				output.includes("Placeholder LSP runtime started:"),
			),
		).toBe(true);
		expect(
			[firstResult.output, secondResult.output].some((output) =>
				output.includes("LSP runtime already active"),
			),
		).toBe(true);
	});

	test("lsp trust stays deduplicated under concurrent callers", async () => {
		const stateDir = ideTemp("yen-ide-lsp-trust-state-");
		const project = createProject("yen-ide-lsp-trust-project-");
		const env = {
			...process.env,
			YEN_IDE_STATE_DIR: stateDir,
		};

		const trustArgs = ["ide", "lsp", "trust", "--project", project];
		const first = spawn(yenBinPath, trustArgs, {
			cwd: repoRoot,
			env,
			stdio: "pipe",
		});
		const second = spawn(yenBinPath, trustArgs, {
			cwd: repoRoot,
			env,
			stdio: "pipe",
		});

		const settle = (child: ReturnType<typeof spawn>) =>
			new Promise<number | null>((resolve) => {
				child.on("close", (code) => resolve(code));
			});

		const [firstCode, secondCode] = await Promise.all([
			settle(first),
			settle(second),
		]);

		expect(firstCode).toBe(0);
		expect(secondCode).toBe(0);

		const trustedRoots = readFileSync(
			join(stateDir, "trusted-lsp-projects"),
			"utf8",
		)
			.split("\n")
			.filter((line) => line === project);
		expect(trustedRoots).toHaveLength(1);
	});

	test("lsp lifecycle works for project paths containing spaces", () => {
		const stateDir = ideTemp("yen-ide-lsp-spaces-state-");
		const project = createProject("yen ide lsp spaced project ");
		const env = {
			YEN_IDE_STATE_DIR: stateDir,
			YEN_IDE_LSP_FORCE_PLACEHOLDER: "1",
		};

		expect(
			runYen(["ide", "lsp", "trust", "--project", project], env).status,
		).toBe(0);

		const start = runYen(["ide", "lsp", "start", "--project", project], env);
		expect(start.status).toBe(0);
		expect(commandOutput(start)).toContain("Placeholder LSP runtime started:");

		const status = runYen(
			["ide", "lsp", "status", "--project", project, "--format", "json"],
			env,
		);
		expect(status.status).toBe(0);
		const payload = parseJsonOutput(status);
		expect(payload.root).toBe(project);
		expect(payload.runtimeState).toBe("running");
		expect(payload.daemonLogFile).toContain("daemon.log");
	});
});
