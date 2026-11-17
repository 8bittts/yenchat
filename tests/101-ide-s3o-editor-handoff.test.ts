import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
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

function createProject(prefix: string) {
	const project = ideTemp(prefix);
	mkdirSync(join(project, "src"), { recursive: true });
	writeFileSync(join(project, "Makefile"), "all:\n\t@echo ok\n", "utf8");
	writeFileSync(
		join(project, "src", "app.ts"),
		"export const value = 1;\n",
		"utf8",
	);
	return project;
}

function writeExecutable(path: string, body = "#!/bin/bash\nexit 0\n") {
	writeFileSync(path, body, "utf8");
	chmodSync(path, 0o755);
}

function canonical(path: string) {
	return realpathSync(path);
}

describe("IDE editor handoff", () => {
	test("dry-run resolves repo-relative semantic targets through the code-family goto contract", () => {
		const project = createProject("yen-ide-open-code-");
		const res = runYen([
			"ide",
			"open",
			"src/app.ts:12:3",
			"--project",
			project,
			"--editor",
			"code --reuse-window",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.target.path).toBe(canonical(join(project, "src", "app.ts")));
		expect(payload.target.location).toBe(
			`${canonical(join(project, "src", "app.ts"))}:12:3`,
		);
		expect(payload.editor.family).toBe("code-family");
		expect(payload.editor.lineAware).toBe(true);
		expect(payload.command.argv).toEqual([
			"code",
			"--reuse-window",
			"--goto",
			`${canonical(join(project, "src", "app.ts"))}:12:3`,
		]);
	});

	test("dry-run keeps micro session flags while adding a line-aware cursor target", () => {
		const project = createProject("yen-ide-open-micro-");
		const res = runYen([
			"ide",
			"open",
			"src/app.ts:4:2",
			"--project",
			project,
			"--editor",
			"micro",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.family).toBe("micro");
		expect(payload.editor.lineAware).toBe(true);
		expect(payload.command.argv).toEqual([
			"micro",
			"-ruler",
			"false",
			"-softwrap",
			"true",
			"-wordwrap",
			"true",
			canonical(join(project, "src", "app.ts")),
			"+4:2",
		]);
	});

	test("dry-run falls back to opening the resolved file only when the editor has no known line-aware contract", () => {
		const project = createProject("yen-ide-open-plain-");
		const res = runYen([
			"ide",
			"open",
			"src/app.ts:9:1",
			"--project",
			project,
			"--editor",
			"cat",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.family).toBe("plain");
		expect(payload.editor.lineAware).toBe(false);
		expect(payload.editor.note).toContain("line-aware CLI");
		expect(payload.command.argv).toEqual([
			"cat",
			"--",
			canonical(join(project, "src", "app.ts")),
		]);
	});

	test("dry-run applies wait flags only for editors with an explicit wait contract", () => {
		const project = createProject("yen-ide-open-zed-");
		const binRoot = ideTemp("yen-ide-open-zed-bin-");
		writeExecutable(join(binRoot, "zed"));
		const res = runYen(
			[
				"ide",
				"open",
				"src/app.ts:7:8",
				"--project",
				project,
				"--editor",
				"zed",
				"--wait",
				"--dry-run",
				"--format",
				"json",
			],
			{
				PATH: `${binRoot}:${process.env.PATH ?? ""}`,
			},
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.family).toBe("zed");
		expect(payload.editor.waitRequested).toBe(true);
		expect(payload.editor.waitApplied).toBe(true);
		expect(payload.command.argv).toEqual([
			"zed",
			"--wait",
			`${canonical(join(project, "src", "app.ts"))}:7:8`,
		]);
	});

	test("dry-run preserves quoted editor argv for executables whose path contains spaces", () => {
		const project = createProject("yen-ide-open-quoted-");
		const editorRoot = ideTemp("yen-ide-editor-space-");
		const quotedEditor = join(editorRoot, "editor with space");
		writeExecutable(quotedEditor);

		const res = runYen([
			"ide",
			"open",
			"src/app.ts:3:1",
			"--project",
			project,
			"--editor",
			`"${quotedEditor}" --flag`,
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.binary).toBe(quotedEditor);
		expect(payload.editor.executablePath).toBe(quotedEditor);
		expect(payload.command.argv).toEqual([
			quotedEditor,
			"--flag",
			"--",
			canonical(join(project, "src", "app.ts")),
		]);
	});

	test("dry-run recognizes macOS open-app editor bridges for GUI goto contracts", () => {
		const project = createProject("yen-ide-open-app-bridge-");
		const binRoot = ideTemp("yen-ide-open-app-bridge-bin-");
		writeExecutable(join(binRoot, "open"));

		const res = runYen(
			[
				"ide",
				"open",
				"src/app.ts:8:4",
				"--project",
				project,
				"--editor",
				'open -a "Visual Studio Code" --args --reuse-window',
				"--dry-run",
				"--format",
				"json",
			],
			{
				PATH: `${binRoot}:${process.env.PATH ?? ""}`,
			},
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.family).toBe("code-family");
		expect(payload.editor.executablePath).toBe(join(binRoot, "open"));
		expect(payload.command.argv).toEqual([
			"open",
			"-a",
			"Visual Studio Code",
			"--args",
			"--reuse-window",
			"--goto",
			`${canonical(join(project, "src", "app.ts"))}:8:4`,
		]);
	});

	test("dry-run treats editor metacharacters as literal argv instead of executing them", () => {
		const project = createProject("yen-ide-open-literal-");
		const editorRoot = ideTemp("yen-ide-editor-literal-");
		const mockEditor = join(editorRoot, "mock-editor");
		const sideEffectFlag = join(editorRoot, "should-not-exist");
		writeExecutable(mockEditor);

		const res = runYen([
			"ide",
			"open",
			"src/app.ts:2:1",
			"--project",
			project,
			"--editor",
			`"${mockEditor}" ; touch ${sideEffectFlag}`,
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.command.argv).toEqual([
			mockEditor,
			";",
			"touch",
			sideEffectFlag,
			"--",
			canonical(join(project, "src", "app.ts")),
		]);
		expect(() => canonical(sideEffectFlag)).toThrow();
	});

	test("dry-run keeps dash-prefixed filenames safe in plain-editor fallback mode", () => {
		const project = createProject("yen-ide-open-dash-");
		writeFileSync(
			join(project, "src", "-leading.ts"),
			"export const leading = true;\n",
			"utf8",
		);
		const res = runYen([
			"ide",
			"open",
			"src/-leading.ts:9:1",
			"--project",
			project,
			"--editor",
			"cat",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.command.argv).toEqual([
			"cat",
			"--",
			canonical(join(project, "src", "-leading.ts")),
		]);
	});

	test("dry-run fails closed when the target does not resolve to an existing file", () => {
		const project = createProject("yen-ide-open-missing-target-");
		const res = runYen([
			"ide",
			"open",
			"src/missing.ts:1:1",
			"--project",
			project,
			"--editor",
			"code",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain("Invalid editor target");
	});

	test("dry-run fails closed when the configured editor launcher is unavailable", () => {
		const project = createProject("yen-ide-open-missing-editor-");
		const res = runYen([
			"ide",
			"open",
			"src/app.ts:1:1",
			"--project",
			project,
			"--editor",
			"yen-editor-missing-for-test",
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain(
			"Configured editor launcher is unavailable",
		);
	});

	test("dry-run fails closed when the editor command cannot be parsed", () => {
		const project = createProject("yen-ide-open-bad-editor-");
		const res = runYen([
			"ide",
			"open",
			"src/app.ts:1:1",
			"--project",
			project,
			"--editor",
			'"unterminated',
			"--dry-run",
			"--format",
			"json",
		]);

		expect(res.status).not.toBe(0);
		expect(`${res.stderr ?? ""}`).toContain("Unable to parse editor command");
	});

	test("dry-run falls back from nvr to nvim when no running server is exported", () => {
		const project = createProject("yen-ide-open-nvr-");
		const binRoot = ideTemp("yen-ide-open-nvr-bin-");
		writeExecutable(join(binRoot, "nvr"));
		writeExecutable(join(binRoot, "nvim"));

		const res = runYen(
			[
				"ide",
				"open",
				"src/app.ts:6:4",
				"--project",
				project,
				"--editor",
				"nvr",
				"--dry-run",
				"--format",
				"json",
			],
			{
				PATH: `${binRoot}:${process.env.PATH ?? ""}`,
				NVIM: "",
				NVIM_LISTEN_ADDRESS: "",
			},
		);

		expect(res.status).toBe(0);
		const payload = JSON.parse(`${res.stdout ?? ""}`.trim());
		expect(payload.editor.family).toBe("vim-family");
		expect(payload.editor.binary).toBe("nvim");
		expect(payload.editor.note).toContain("falling back to nvim");
		expect(payload.command.argv).toEqual([
			"nvim",
			"+call cursor(6,4)",
			canonical(join(project, "src", "app.ts")),
		]);
	});
});
