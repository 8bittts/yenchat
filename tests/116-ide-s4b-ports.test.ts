import { describe, expect, test } from "bun:test";
import { spawn, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
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

function runCommand(
	command: string,
	args: string[],
	cwd: string,
	envOverrides: Record<string, string> = {},
) {
	return spawnSync(command, args, {
		cwd,
		encoding: "utf8",
		env: {
			...process.env,
			...envOverrides,
		},
	});
}

function writeExecutable(path: string, body: string) {
	writeFileSync(path, body, "utf8");
	chmodSync(path, 0o755);
}

function createPortsHarness(prefix: string) {
	const harnessRoot = ideTemp(prefix);
	const binDir = join(harnessRoot, "bin");
	const nextApp = join(harnessRoot, "next-app");
	const djangoApp = join(harnessRoot, "django-app");
	const viteApp = join(harnessRoot, "vite-app");
	const systemDir = join(harnessRoot, "system");

	mkdirSync(binDir, { recursive: true });
	mkdirSync(nextApp, { recursive: true });
	mkdirSync(djangoApp, { recursive: true });
	mkdirSync(viteApp, { recursive: true });
	mkdirSync(systemDir, { recursive: true });

	writeFileSync(
		join(nextApp, "package.json"),
		JSON.stringify({ name: "next-app", scripts: { dev: "next dev" } }, null, 2),
		"utf8",
	);
	writeFileSync(
		join(nextApp, "next.config.js"),
		"module.exports = {};\n",
		"utf8",
	);
	writeFileSync(join(djangoApp, "manage.py"), "print('django')\n", "utf8");
	writeFileSync(
		join(viteApp, "package.json"),
		JSON.stringify({ name: "vite-app", scripts: { dev: "vite" } }, null, 2),
		"utf8",
	);
	writeFileSync(
		join(viteApp, "vite.config.ts"),
		"export default {};\n",
		"utf8",
	);
	writeFileSync(
		join(viteApp, "bunfig.toml"),
		"[install]\ncache = false\n",
		"utf8",
	);

	const gitEnv = {
		GIT_AUTHOR_NAME: "YEN Test",
		GIT_AUTHOR_EMAIL: "test@example.com",
		GIT_COMMITTER_NAME: "YEN Test",
		GIT_COMMITTER_EMAIL: "test@example.com",
	};
	expect(runCommand("git", ["init"], nextApp, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["checkout", "-b", "main"], nextApp, gitEnv).status,
	).toBe(0);
	expect(runCommand("git", ["add", "."], nextApp, gitEnv).status).toBe(0);
	expect(
		runCommand("git", ["commit", "-m", "init"], nextApp, gitEnv).status,
	).toBe(0);

	writeExecutable(
		join(binDir, "lsof"),
		`#!/bin/bash
if [[ "$*" == *"-a -d cwd"* ]]; then
  cat <<'EOF'
p4100
n${nextApp}
p4101
n${djangoApp}
p4102
n${systemDir}
p4104
n${viteApp}
p5001
n/Applications/Docker.app
p5002
n/Applications/Docker.app
p6000
n/
EOF
  exit 0
fi

cat <<'EOF'
p4100
cnode
u501
nTCP *:3000 (LISTEN)
p4100
cnode
u501
nTCP 127.0.0.1:3000 (LISTEN)
p4101
cpython3
u501
nTCP *:8000 (LISTEN)
p4104
cbun
u501
nTCP *:3100 (LISTEN)
p5002
ccom.docker.backend
u0
nTCP *:5432 (LISTEN)
p4102
cControlCenter
u501
nTCP *:5000 (LISTEN)
EOF
`,
	);

	writeExecutable(
		join(binDir, "ps"),
		`#!/bin/bash
if [[ "$*" == *"-eo"* ]]; then
  cat <<'EOF'
4100 4000 testuser S 1.2 0.4 11111 Fri Apr  3 10:00:00 2026 node ${nextApp}/node_modules/next/dist/bin/next dev
4101 4001 testuser S 2.5 0.7 22222 Fri Apr  3 10:05:00 2026 python3 ${djangoApp}/manage.py runserver 0.0.0.0:8000
4104 1 testuser Z 0.4 0.3 9999 Fri Apr  3 10:06:00 2026 bun ${viteApp}/node_modules/vite/bin/vite.js
5001 1 root S 0.1 1.0 33333 Fri Apr  3 10:07:00 2026 dockerd --config-file /Users/test/.docker/daemon.json
5002 1 root S 0.2 0.8 44444 Fri Apr  3 10:07:01 2026 com.docker.backend -addr unix:///tmp/docker.sock
6000 1 root S 0.1 0.2 5555 Fri Apr  3 10:08:00 2026 ControlCenter
EOF
  exit 0
fi

cat <<'EOF'
4100 4000 testuser S 1.2 0.4 11111 Fri Apr  3 10:00:00 2026 node ${nextApp}/node_modules/next/dist/bin/next dev
4101 4001 testuser S 2.5 0.7 22222 Fri Apr  3 10:05:00 2026 python3 ${djangoApp}/manage.py runserver 0.0.0.0:8000
4102 1 root S 0.1 0.2 33333 Fri Apr  3 10:04:00 2026 ControlCenter
4104 1 testuser Z 0.4 0.3 9999 Fri Apr  3 10:06:00 2026 bun ${viteApp}/node_modules/vite/bin/vite.js
EOF
`,
	);

	writeExecutable(
		join(binDir, "docker"),
		`#!/bin/bash
if [[ "$1" == "info" ]]; then
  exit 0
fi
if [[ "$1" == "ps" && "$2" == "--format" ]]; then
  printf 'postgres-dev\\t0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp\\n'
  exit 0
fi
exit 1
`,
	);

	return {
		binDir,
		djangoApp,
		harnessRoot,
		nextApp,
		viteApp,
	};
}

function createDestructivePortsHarness(prefix: string) {
	const root = ideTemp(prefix);
	const binDir = join(root, "bin");
	const nextApp = join(root, "next-app");
	const djangoApp = join(root, "django-app");
	const nextProcess = spawn("/bin/sleep", ["60"], { stdio: "ignore" });
	const djangoProcess = spawn("/bin/sleep", ["60"], { stdio: "ignore" });
	const nextPid = `${nextProcess.pid ?? ""}`;
	const djangoPid = `${djangoProcess.pid ?? ""}`;

	mkdirSync(binDir, { recursive: true });
	mkdirSync(nextApp, { recursive: true });
	mkdirSync(djangoApp, { recursive: true });

	writeFileSync(
		join(nextApp, "package.json"),
		JSON.stringify({ name: "next-app", scripts: { dev: "next dev" } }, null, 2),
		"utf8",
	);
	writeFileSync(
		join(nextApp, "next.config.js"),
		"module.exports = {};\n",
		"utf8",
	);
	writeFileSync(join(djangoApp, "manage.py"), "print('django')\n", "utf8");

	writeExecutable(
		join(binDir, "lsof"),
		`#!/bin/bash
if [[ "$*" == *"-a -d cwd"* ]]; then
  cat <<'EOF'
p${nextPid}
n${nextApp}
p${djangoPid}
n${djangoApp}
EOF
  exit 0
fi

cat <<'EOF'
p${nextPid}
cnode
u501
nTCP *:3000 (LISTEN)
p${djangoPid}
cpython3
u501
nTCP *:8000 (LISTEN)
EOF
`,
	);

	writeExecutable(
		join(binDir, "ps"),
		`#!/bin/bash
cat <<'EOF'
${nextPid} 4000 testuser S 1.2 0.4 11111 Fri Apr  3 10:00:00 2026 node ${nextApp}/node_modules/next/dist/bin/next dev
${djangoPid} 1 testuser Z 0.5 1.2 2048 Fri Apr  3 09:00:00 2026 python3 ${djangoApp}/manage.py runserver
EOF
`,
	);

	writeExecutable(
		join(binDir, "docker"),
		`#!/bin/bash
if [[ "$1" == "info" ]]; then
  exit 0
fi
if [[ "$1" == "ps" && "$2" == "-q" ]]; then
  exit 0
fi
exit 1
`,
	);

	writeExecutable(
		join(binDir, "git"),
		`#!/bin/bash
if [[ "$1" == "-C" ]]; then
  shift 2
fi
if [[ "$1" == "symbolic-ref" ]]; then
  printf 'main\\n'
  exit 0
fi
if [[ "$1" == "branch" && "$2" == "--show-current" ]]; then
  printf 'main\\n'
  exit 0
fi
exit 1
`,
	);

	return {
		djangoPid,
		env: {
			PATH: `${binDir}:${process.env.PATH ?? ""}`,
		},
		nextPid,
		root,
		dispose() {
			for (const child of [nextProcess, djangoProcess]) {
				if (!child.pid) {
					continue;
				}
				try {
					process.kill(child.pid, "SIGTERM");
				} catch {
					// Process may already be dead
				}
			}
		},
	};
}

describe("IDE ports", () => {
	test("default json filters non-dev listeners, dedups dual binds, and enriches framework/container metadata", () => {
		const harness = createPortsHarness("yen-ide-ports-default-");
		const res = runYen(
			["ide", "ports", "--json"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.map((row: { port: string }) => row.port)).toEqual([
			"3000",
			"3100",
			"5432",
			"8000",
		]);
		expect(
			payload.find((row: { port: string }) => row.port === "3000")?.framework,
		).toBe("Next.js");
		expect(
			payload.find((row: { port: string }) => row.port === "3100")?.framework,
		).toBe("Vite");
		expect(
			payload.find((row: { port: string }) => row.port === "5432")?.framework,
		).toBe("Docker");
		expect(
			payload.find((row: { port: string }) => row.port === "5432")?.container,
		).toBe("postgres-dev");
		expect(
			payload.find((row: { port: string }) => row.port === "8000")?.framework,
		).toBe("Django");
		expect(
			payload.some((row: { port: string }) => row.port === "5000"),
		).toBeFalse();
	});

	test("all mode restores non-dev listeners", () => {
		const harness = createPortsHarness("yen-ide-ports-all-");
		const res = runYen(
			["ide", "ports", "--all", "--json"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.map((row: { port: string }) => row.port)).toEqual([
			"3000",
			"3100",
			"5000",
			"5432",
			"8000",
		]);
	});

	test("detail json returns the selected port metadata including git branch", () => {
		const harness = createPortsHarness("yen-ide-ports-detail-");
		const res = runYen(
			["ide", "ports", "3000", "--json"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		const resolvedNextApp = realpathSync(harness.nextApp);
		expect(payload.port).toBe("3000");
		expect(payload.framework).toBe("Next.js");
		expect(payload.cwd).toBe(harness.nextApp);
		expect(payload.projectRoot).toBe(resolvedNextApp);
		expect(payload.container).toBe("");
		expect(payload.gitBranch).toBe("main");
	});

	test("ps json keeps dev processes and collapses docker runtime rows into one summary entry", () => {
		const harness = createPortsHarness("yen-ide-ports-ps-");
		const res = runYen(
			["ide", "ports", "ps", "--json"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		const dockerRows = payload.filter(
			(row: { command: string }) => row.command === "docker",
		);
		expect(dockerRows.length).toBe(1);
		expect(dockerRows[0]?.startedAt).toBe("Fri Apr 3 10:07:00 2026");
		expect(dockerRows[0]?.uptime).not.toBe("");
		expect(
			payload.some((row: { framework: string }) => row.framework === "Next.js"),
		).toBe(true);
		expect(
			payload.some((row: { framework: string }) => row.framework === "Django"),
		).toBe(true);
		expect(
			payload.some(
				(row: { command: string }) => row.command === "ControlCenter",
			),
		).toBe(false);
	});

	test("clean json identifies orphaned and zombie listening processes", () => {
		const harness = createPortsHarness("yen-ide-ports-clean-");
		const res = runYen(
			["ide", "ports", "clean", "--json"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.orphanCount).toBe(1);
		expect(payload.zombieCount).toBe(1);
		expect(payload.candidates).toHaveLength(1);
		expect(payload.candidates[0].port).toBe("3100");
		expect(payload.candidates[0].reasons).toEqual(["orphan", "zombie"]);
	});

	test("help documents the expanded subcommand surface", () => {
		const harness = createPortsHarness("yen-ide-ports-help-");
		const res = runYen(
			["ide", "ports", "help"],
			{ PATH: `${harness.binDir}:${process.env.PATH ?? ""}` },
			harness.harnessRoot,
		);

		expect(res.status).toBe(0);
		expect(res.stdout).toContain("yen ide ports watch");
		expect(res.stdout).toContain("yen ide ports clean");
		expect(res.stdout).toContain("--all, -a");
	});

	test("detail json with --yes stays machine-readable and reports termination status", () => {
		const harness = createDestructivePortsHarness("yen-ide-ports-kill-");
		try {
			const res = runYen(
				["ide", "ports", "3000", "--json", "--yes"],
				harness.env,
				harness.root,
			);

			expect(res.status).toBe(0);
			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			expect(payload.port).toBe("3000");
			expect(payload.gitBranch).toBe("main");
			expect(payload.killAttempted).toBe(true);
			expect(payload.killStatus).toBe("terminated");
		} finally {
			harness.dispose();
		}
	});

	test("clean json with --yes reports terminated candidates without breaking json output", () => {
		const harness = createDestructivePortsHarness("yen-ide-ports-clean-kill-");
		try {
			const res = runYen(
				["ide", "ports", "clean", "--json", "--yes"],
				harness.env,
				harness.root,
			);

			expect(res.status).toBe(0);
			const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
			expect(payload.killAttempted).toBe(true);
			expect(payload.orphanCount).toBe(1);
			expect(payload.zombieCount).toBe(1);
			expect(payload.terminatedPids).toEqual([harness.djangoPid]);
			expect(payload.failedPids).toEqual([]);
		} finally {
			harness.dispose();
		}
	});
});
