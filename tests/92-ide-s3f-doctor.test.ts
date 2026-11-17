import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
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

function writeExecutable(path: string, content: string) {
	writeFileSync(path, content, "utf8");
	chmodSync(path, 0o755);
}

function createNestedWorkspaceDoctorFixture(prefix: string) {
	const root = ideTemp(prefix);
	const container = join(root, "yen-terminal");
	const overlays = join(container, "overlays");
	const ghostty = join(container, "ghostty");
	mkdirSync(overlays, { recursive: true });
	mkdirSync(ghostty, { recursive: true });
	writeFileSync(join(root, "package.json"), '{"name":"repo-root"}\n', "utf8");
	writeFileSync(
		join(overlays, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	writeFileSync(
		join(ghostty, "build.zig"),
		'const std = @import("std");\n',
		"utf8",
	);
	return {
		root: realpathSync(root),
		container: realpathSync(container),
		overlays: realpathSync(overlays),
	};
}

describe("IDE S3F workspace doctor", () => {
	test("doctor reports blocking findings for trust gaps, missing tooling, drift, and unsupported versions", () => {
		const stateDir = ideTemp("yen-ide-doctor-state-");
		const project = ideTemp("yen-ide-doctor-project-");
		const fakeBin = join(stateDir, "bin");
		mkdirSync(fakeBin, { recursive: true });

		writeFileSync(
			join(project, "package.json"),
			`${JSON.stringify(
				{
					name: "doctor-fixture",
					packageManager: "bun@1.3.11",
				},
				null,
				2,
			)}\n`,
			"utf8",
		);
		writeFileSync(join(project, "bun.lock"), "", "utf8");
		writeFileSync(join(project, "package-lock.json"), "{}", "utf8");
		writeFileSync(join(project, "tsconfig.json"), "{}\n", "utf8");
		writeFileSync(join(project, ".env.local"), "SECRET_KEY=test\n", "utf8");
		writeFileSync(
			join(project, "go.mod"),
			"module fixture\n\ngo 1.25.5\n",
			"utf8",
		);
		mkdirSync(dirname(join(project, ".devcontainer/devcontainer.json")), {
			recursive: true,
		});
		writeFileSync(
			join(project, ".devcontainer/devcontainer.json"),
			`${JSON.stringify(
				{
					name: "doctor-fixture",
					image: "mcr.microsoft.com/devcontainers/base:ubuntu",
					runArgs: ["--privileged"],
				},
				null,
				2,
			)}\n`,
			"utf8",
		);

		writeExecutable(
			join(fakeBin, "bun"),
			`#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "1.2.0"
  exit 0
fi
exit 0
`,
		);
		writeExecutable(
			join(fakeBin, "go"),
			`#!/bin/bash
echo "go version go1.24.0 darwin/arm64"
`,
		);

		const res = runYen(
			["ide", "doctor", "--format", "json"],
			{
				YEN_IDE_STATE_DIR: stateDir,
				PATH: `${fakeBin}:${process.env.PATH ?? ""}`,
			},
			project,
		);
		const output = `${res.stdout ?? ""}\n${res.stderr ?? ""}`;
		expect(res.status).toBe(1);
		expect(output).toContain('"status": "blocking"');

		const payload = JSON.parse(res.stdout ?? "{}");
		const codes = new Set(
			(payload.findings as Array<{ code: string }>).map((item) => item.code),
		);

		expect(payload.status).toBe("blocking");
		expect(payload.blockers).toBeGreaterThan(0);
		expect(payload.warnings).toBeGreaterThan(0);
		expect(payload.toolchain.packageManager.currentVersion).toBe("1.2.0");
		expect(payload.toolchain.goCurrentVersion).toBe("1.24.0");
		expect(payload.toolchain.lockfiles).toEqual([
			"bun.lock",
			"package-lock.json",
		]);
		expect(codes.has("env-untrusted")).toBe(true);
		expect(codes.has("lsp-untrusted")).toBe(true);
		expect(codes.has("lsp-server-missing")).toBe(true);
		expect(codes.has("devcontainer-cli-missing")).toBe(true);
		expect(codes.has("devcontainer-untrusted")).toBe(true);
		expect(codes.has("devcontainer-unsafe-spec")).toBe(true);
		expect(codes.has("package-manager-outdated")).toBe(true);
		expect(codes.has("go-outdated")).toBe(true);
		expect(codes.has("multiple-lockfiles")).toBe(true);
		expect(codes.has("verify-missing")).toBe(true);
	});

	test("doctor strict mode fails on warnings even when no blockers exist", () => {
		const stateDir = ideTemp("yen-ide-doctor-warning-state-");
		const project = ideTemp("yen-ide-doctor-warning-project-");

		writeFileSync(join(project, "Makefile"), "all:\n\t@echo ok\n", "utf8");

		const nonStrict = runYen(
			["ide", "doctor", "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(nonStrict.status).toBe(0);
		const nonStrictPayload = JSON.parse(nonStrict.stdout ?? "{}");
		expect(nonStrictPayload.status).toBe("warning");
		expect(nonStrictPayload.blockers).toBe(0);
		expect(nonStrictPayload.warnings).toBeGreaterThan(0);
		expect(
			nonStrictPayload.findings.some(
				(item: { code: string }) => item.code === "verify-missing",
			),
		).toBe(true);

		const strict = runYen(
			["ide", "doctor", "--strict", "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(strict.status).toBe(1);
		const strictPayload = JSON.parse(strict.stdout ?? "{}");
		expect(strictPayload.status).toBe("warning");
		expect(strictPayload.blockers).toBe(0);
		expect(strictPayload.warnings).toBeGreaterThan(0);
		expect(
			strictPayload.findings.some(
				(item: { code: string }) => item.code === "verify-missing",
			),
		).toBe(true);
	});

	test("doctor resolves nested workspace container paths to the concrete product root", () => {
		const fixture = createNestedWorkspaceDoctorFixture(
			"yen-ide-doctor-nested-root-",
		);

		const result = runYen(
			["ide", "doctor", "--format", "json", fixture.container],
			{},
			fixture.root,
		);
		expect(result.status === 0 || result.status === 1).toBeTrue();
		const payload = JSON.parse(result.stdout ?? "{}");

		expect(payload.root).toBe(fixture.overlays);
		expect(payload.project.types).toEqual(["zig"]);
	});

	test("doctor exposes verify security readiness in text and json output", () => {
		const stateDir = ideTemp("yen-ide-doctor-security-state-");
		const project = ideTemp("yen-ide-doctor-security-project-");
		const canonicalProject = realpathSync(project);
		const verifyDir = join(stateDir, "verify");
		mkdirSync(verifyDir, { recursive: true });
		writeFileSync(join(project, "Makefile"), "all:\n\t@echo ok\n", "utf8");

		const summaryPath = join(verifyDir, "verify-20260320T000000Z-security.tsv");
		const detailsPath = join(verifyDir, "verify-20260320T000000Z-security.log");
		const semanticPath = join(
			verifyDir,
			"verify-20260320T000000Z-security.semantic.tsv",
		);
		writeFileSync(
			summaryPath,
			`${[
				"2026-03-20T00:00:00Z\tgitleaks\t0\t12\tstable\t0\tgitleaks detect --no-banner --redact --source .\tpass\tsecurity",
				"2026-03-20T00:00:01Z\tosv-scanner\t1\t44\tstable\t0\tosv-scanner --format json --lockfile='/tmp/repo/bun.lock'\twarn\tsecurity",
			].join("\n")}\n`,
			"utf8",
		);
		writeFileSync(
			detailsPath,
			[
				"=== gitleaks ===",
				"category: security",
				"result: pass",
				"command: gitleaks detect --no-banner --redact --source .",
				"status: 0",
				"--- output ---",
				"",
				"=== osv-scanner ===",
				"category: security",
				"result: warn",
				"command: osv-scanner --format json --lockfile='/tmp/repo/bun.lock'",
				"status: 1",
				"--- output ---",
				'{"results":[{"source":{"path":"/tmp/repo/bun.lock","type":"lockfile"},"packages":[{"package":{"name":"fixture","version":"1.0.0","ecosystem":"npm"},"groups":[{"ids":["GHSA-1234"]}],"vulnerabilities":[{"id":"GHSA-1234"}]}]}]}',
				"",
			].join("\n"),
			"utf8",
		);
		writeFileSync(semanticPath, "", "utf8");
		writeFileSync(
			join(stateDir, "timeline.log"),
			[
				`2026-03-20T00:00:02Z\tverify\t${canonicalProject}\tfailures=0;warns=1\tsummary=${summaryPath};semantic=${semanticPath}`,
				"",
			].join("\n"),
			"utf8",
		);

		const json = runYen(
			["ide", "doctor", "--format", "json"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(json.status).toBe(0);
		const payload = JSON.parse(json.stdout ?? "{}");
		expect(payload.verify.readiness.status).toBe("warning");
		expect(payload.verify.security.status).toBe("warning");
		expect(payload.verify.security.stepCount).toBe(2);
		expect(payload.verify.security.warningSteps).toBe(1);
		expect(payload.verify.detailsReport).toBe(detailsPath);

		const text = runYen(
			["ide", "doctor"],
			{ YEN_IDE_STATE_DIR: stateDir },
			project,
		);
		expect(text.status).toBe(0);
		expect(text.stdout).toContain("Security:");
		expect(text.stdout).toContain("warning (steps=2 blockers=0 warnings=1)");
	}, 20_000);
});
