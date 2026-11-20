import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

type ProcResult = {
	status: number | null;
	signal: NodeJS.Signals | null;
	stdout: string;
	stderr: string;
};

const repoRoot = process.cwd();
const patchFilePath = join(repoRoot, "scripts/lib/patch-file.py");
const patchesDir = join(repoRoot, "scripts/lib/patches");
const appleScriptPolicyHelperPath = join(
	repoRoot,
	"scripts/lib/apple-script-action-policy.py",
);
const applyOverlaysPath = join(repoRoot, "yen-terminal/apply-overlays.sh");
const overlayPhasesDir = join(repoRoot, "scripts/lib/overlay-phases");
const overlayPhaseNames = readdirSync(overlayPhasesDir)
	.filter((name) => name.endsWith(".sh"))
	.sort();
function phaseSource(name: string): string {
	return readFileSync(join(overlayPhasesDir, name), "utf8");
}

const vendorSkillAuditPath = join(
	repoRoot,
	".agents/skills/yen-zip/references/vendor-audit.md",
);

type OverlayPatchOperation = { target: string; arguments: string[] };
const patchPlan = JSON.parse(
	readFileSync(join(repoRoot, "scripts/lib/overlay-patch-plan.json"), "utf8"),
) as Record<string, OverlayPatchOperation>;

function hasPatchArgument(option: string, value?: string): boolean {
	return Object.values(patchPlan).some((operation) =>
		operation.arguments.some(
			(argument, index, args) =>
				argument === option &&
				(value === undefined || args[index + 1] === value),
		),
	);
}

function hasPatchText(value: string): boolean {
	return Object.values(patchPlan).some((operation) =>
		operation.arguments.some((argument) => argument.includes(value)),
	);
}

function patchForLabel(label: string): OverlayPatchOperation {
	const operation = Object.values(patchPlan).find((entry) => {
		const index = entry.arguments.indexOf("--label");
		return index >= 0 && entry.arguments[index + 1] === label;
	});
	if (!operation) throw new Error(`Missing declared patch: ${label}`);
	return operation;
}

const patchRuntimePath = join(repoRoot, "scripts/lib/overlay-patch-runtime.sh");
const patchPreflightPath = join(
	repoRoot,
	"scripts/lib/overlay-patch-preflight.sh",
);
const patchManifestPath = join(
	repoRoot,
	"scripts/lib/overlay-patch-targets.txt",
);

function shellQuote(value: string): string {
	return `'${value.replaceAll("'", "'\\''")}'`;
}

function patchCommands(operations: string[]): string {
	return operations
		.map((operation) => `apply_overlay_patch ${shellQuote(operation)}`)
		.join("\n");
}

// Fixtures call the same sourced runtime as the overlay orchestrator.
const patchFileFn = `source ${shellQuote(patchRuntimePath)}`;
const overlayTallyFns = patchFileFn;

function run(
	cmd: string,
	args: string[],
	options: {
		cwd?: string;
		script?: string;
	} = {},
): ProcResult {
	const res = spawnSync(cmd, args, {
		cwd: options.cwd ?? repoRoot,
		encoding: "utf8",
		input: options.script,
		env: process.env,
	});
	return {
		status: res.status,
		signal: res.signal,
		stdout: res.stdout ?? "",
		stderr: res.stderr ?? "",
	};
}

function output(res: ProcResult): string {
	return `${res.stdout}\n${res.stderr}`;
}

function withTempDir(runInDir: (dir: string) => void) {
	const dir = mkdtempSync(join(tmpdir(), "yen-overlay-test-"));
	try {
		runInDir(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function patchPath(name: string, suffix: "old" | "new"): string {
	return `@${join(patchesDir, `${name}.${suffix}`)}`;
}

function runPatch(args: string[]): ProcResult {
	return run("python3", [patchFilePath, ...args]);
}

function applyYenBinPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"YEN_BIN_DIR fix",
		"--mode",
		"exact",
		"--marker-all",
		'try env.put("YEN_BIN_DIR", bin_dir.?);',
		"--marker-all",
		"if (std.mem.eql(u8, entry, bin_dir.?)) break :yen_path;",
		"--marker-all",
		"try appendEnv(alloc, path, bin_dir.?)",
		"--marker-all",
		'            try env.put("PATH", bin_dir.?);',
		"--old-block",
		patchPath("yen-bin-dir", "old"),
		"--new-block",
		patchPath("yen-bin-dir", "new"),
		"--extra-replace",
		`${patchPath("yen-bin-dir-path-entry", "old")}:::${patchPath("yen-bin-dir-path-entry", "new")}`,
		"--extra-replace",
		`${patchPath("yen-bin-dir-append-env", "old")}:::${patchPath("yen-bin-dir-append-env", "new")}`,
		"--extra-replace",
		`${patchPath("yen-bin-dir-put-path", "old")}:::${patchPath("yen-bin-dir-put-path", "new")}`,
		"--extra-replace",
		`${patchPath("yen-bin-dir-comment", "old")}:::${patchPath("yen-bin-dir-comment", "new")}`,
	]);
}

function applyCopyOnSelectPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"copy-on-select default patch",
		"--mode",
		"proximity",
		"--marker-proximity-anchor",
		'@"copy-on-select"',
		"--marker-proximity-window",
		"5",
		"--marker-proximity-substring",
		".macos => .both",
		"--proximity-anchor",
		'@"copy-on-select"',
		"--proximity-window",
		"5",
		"--proximity-old",
		".linux, .macos => .primary,",
		"--proximity-new",
		".linux => .primary,\n    .macos => .both,",
		"--extra-replace",
		`${patchPath("copy-on-select-doc", "old")}:::${patchPath("copy-on-select-doc", "new")}`,
		"--post-verify-proximity-anchor",
		'@"copy-on-select"',
		"--post-verify-proximity-window",
		"5",
		"--post-verify-proximity-substring",
		".macos => .both",
	]);
}

function applyQuickTerminalPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Quick Terminal keybind patch",
		"--mode",
		"exact",
		"--marker",
		"// Toggle quick terminal (YEN default",
		"--old-block",
		patchPath("quick-terminal", "old"),
		"--new-block",
		patchPath("quick-terminal", "new"),
		"--extra-replace",
		`${patchPath("quick-terminal-doc", "old")}:::${patchPath("quick-terminal-doc", "new")}`,
	]);
}

function applyShiftEnterPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Shift+Enter keybind patch",
		"--mode",
		"exact",
		"--marker",
		"Shift+Enter fix",
		"--old-block",
		patchPath("shift-enter", "old"),
		"--new-block",
		patchPath("shift-enter", "new"),
	]);
}

function applyRuntimePaddingPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Runtime padding reload fix",
		"--mode",
		"exact",
		"--marker",
		"Apply updated padding immediately on config reload",
		"--old-block",
		patchPath("runtime-padding", "old"),
		"--new-block",
		patchPath("runtime-padding", "new"),
	]);
}

function applySelectionPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Selection repaint fix",
		"--mode",
		"exact",
		"--marker",
		"var selection_reapplied = false;",
		"--already-valid-range-start",
		"if (button == .left and action == .release) {",
		"--already-valid-range-end",
		"// Handle link clicking.",
		"--already-valid-range-require",
		"if (self.config.copy_on_select != .none)",
		"--already-valid-range-require",
		"queueRender(",
		"--old-block",
		patchPath("selection-repaint", "old"),
		"--new-block",
		patchPath("selection-repaint", "new"),
	]);
}

function applyRightClickContextMenuPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Right-click context-menu selection patch",
		"--mode",
		"exact",
		"--marker",
		"Preserve the current selection state on right-click and",
		"--old-block",
		patchPath("right-click-context-select", "old"),
		"--new-block",
		patchPath("right-click-context-select", "new"),
	]);
}

function applySplitFocusHitTestPatch(file: string): ProcResult {
	return runPatch([
		"--file",
		file,
		"--label",
		"Split-focus hit-test coordinate fix",
		"--mode",
		"exact",
		"--marker",
		"The clicked location should still resolve back to this surface (or one",
		"--old-block",
		patchPath("split-focus-hit-test", "old"),
		"--new-block",
		patchPath("split-focus-hit-test", "new"),
	]);
}

function runBrandingHelper(root: string, name: string): ProcResult {
	return run(
		"bash",
		[
			"-c",
			`set -euo pipefail
REPO_ROOT=${shellQuote(repoRoot)}
source ${shellQuote(join(repoRoot, "scripts/lib/sparkle-runtime-floor.sh"))}
source ${shellQuote(join(repoRoot, "scripts/lib/overlay-branding.sh"))}
${name}
printf 'Branding helper passed\\n'`,
		],
		{ cwd: root },
	);
}

describe("Overlay patching regression coverage", () => {
	test("eight migrated patches apply and become idempotent on second pass", () => {
		withTempDir((fixtureRoot) => {
			const execPath = join(fixtureRoot, "Exec.zig");
			const configPath = join(fixtureRoot, "Config.zig");
			const surfacePath = join(fixtureRoot, "Surface.zig");
			const surfaceViewAppKitPath = join(
				fixtureRoot,
				"SurfaceView_AppKit.swift",
			);

			const yenOld = readFileSync(join(patchesDir, "yen-bin-dir.old"), "utf8");
			const quickOld = readFileSync(
				join(patchesDir, "quick-terminal.old"),
				"utf8",
			);
			const quickDocOld = readFileSync(
				join(patchesDir, "quick-terminal-doc.old"),
				"utf8",
			);
			const selectionOld = readFileSync(
				join(patchesDir, "selection-repaint.old"),
				"utf8",
			);
			const rightClickOld = readFileSync(
				join(patchesDir, "right-click-context-select.old"),
				"utf8",
			);
			const splitFocusHitTestOld = readFileSync(
				join(patchesDir, "split-focus-hit-test.old"),
				"utf8",
			);

			writeFileSync(
				execPath,
				[
					"header",
					yenOld,
					"if (std.mem.eql(u8, entry, exe_dir)) break :yen_path;",
					"try appendEnv(alloc, path, exe_dir)",
					'            try env.put("PATH", exe_dir);',
					"        // Add our binary to the path if we can find it.",
					"footer",
				].join("\n"),
				"utf8",
			);

			writeFileSync(
				configPath,
				[
					"pre",
					'@"copy-on-select"',
					"line-a",
					".linux, .macos => .primary,",
					"else => .none,",
					"The default value is `primary` on Linux and macOS and `none` otherwise.",
					quickOld,
					quickDocOld,
					"post",
				].join("\n"),
				"utf8",
			);

			writeFileSync(
				surfacePath,
				[
					"top",
					"    self.config = derived;",
					selectionOld,
					rightClickOld,
					"bottom",
				].join("\n"),
				"utf8",
			);

			writeFileSync(
				surfaceViewAppKitPath,
				["top", splitFocusHitTestOld, "bottom"].join("\n"),
				"utf8",
			);

			const firstPass = [
				applyYenBinPatch(execPath),
				applyCopyOnSelectPatch(configPath),
				applyQuickTerminalPatch(configPath),
				applyShiftEnterPatch(configPath),
				applyRuntimePaddingPatch(surfacePath),
				applySelectionPatch(surfacePath),
				applyRightClickContextMenuPatch(surfacePath),
				applySplitFocusHitTestPatch(surfaceViewAppKitPath),
			];

			for (const res of firstPass) {
				expect(res.status).toBe(0);
				expect(output(res)).toContain("Applied");
			}

			const secondPass = [
				applyYenBinPatch(execPath),
				applyCopyOnSelectPatch(configPath),
				applyQuickTerminalPatch(configPath),
				applyShiftEnterPatch(configPath),
				applyRuntimePaddingPatch(surfacePath),
				applySelectionPatch(surfacePath),
				applyRightClickContextMenuPatch(surfacePath),
				applySplitFocusHitTestPatch(surfaceViewAppKitPath),
			];

			for (const res of secondPass) {
				expect(res.status).toBe(0);
				expect(output(res)).toContain("already");
			}
		});
	});

	test("marker-all does not silently skip partial YEN_BIN_DIR state", () => {
		withTempDir((fixtureRoot) => {
			const execPath = join(fixtureRoot, "Exec.zig");
			const patchedBlock = readFileSync(
				join(patchesDir, "yen-bin-dir.new"),
				"utf8",
			);
			writeFileSync(
				execPath,
				[
					"header",
					patchedBlock,
					"if (std.mem.eql(u8, entry, exe_dir)) break :yen_path;",
					"try appendEnv(alloc, path, bin_dir.?)",
					'            try env.put("PATH", bin_dir.?);',
					"footer",
				].join("\n"),
				"utf8",
			);

			const res = applyYenBinPatch(execPath);
			expect(res.status).toBe(1);
			expect(output(res)).toContain("patch anchor not found");
		});
	});

	test("missing extra-replace anchor fails closed", () => {
		withTempDir((fixtureRoot) => {
			const execPath = join(fixtureRoot, "Exec.zig");
			const yenOld = readFileSync(join(patchesDir, "yen-bin-dir.old"), "utf8");
			writeFileSync(
				execPath,
				[
					"header",
					yenOld,
					"if (std.mem.eql(u8, entry, exe_dir)) break :yen_path;",
					"# intentionally missing appendEnv anchor",
					'            try env.put("PATH", exe_dir);',
					"        // Add our binary to the path if we can find it.",
					"footer",
				].join("\n"),
				"utf8",
			);

			const res = applyYenBinPatch(execPath);
			expect(res.status).toBe(1);
			expect(output(res)).toContain("extra-replace anchor not found");
		});
	});

	test("selection patch exits cleanly when upstream-equivalent release rendering exists", () => {
		withTempDir((fixtureRoot) => {
			const surfacePath = join(fixtureRoot, "Surface.zig");
			writeFileSync(
				surfacePath,
				[
					"head",
					"if (button == .left and action == .release) {",
					"    if (self.config.copy_on_select != .none) {",
					"        try self.queueRender();",
					"    }",
					"}",
					"// Handle link clicking.",
				].join("\n"),
				"utf8",
			);

			const res = applySelectionPatch(surfacePath);
			expect(res.status).toBe(0);
			expect(output(res)).toContain("already present upstream");
		});
	});
});

describe("apply-overlays shell guardrails", () => {
	test("YEN_BIN_DIR patch plan keeps full marker-all requirements", () => {
		expect(
			hasPatchArgument(
				"--marker-all",
				'try env.put("YEN_BIN_DIR", bin_dir.?);',
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"if (std.mem.eql(u8, entry, bin_dir.?)) break :yen_path;",
			),
		).toBe(true);
		expect(
			hasPatchArgument("--marker-all", "try appendEnv(alloc, path, bin_dir.?)"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				'            try env.put("PATH", bin_dir.?);',
			),
		).toBe(true);
	});

	test("URL rewrites restore dependencies and update user-facing provenance", () => {
		withTempDir((root) => {
			const files: Record<string, [string, string]> = {
				"src/cli/version.zig": [
					"https://github.com/ghostty-org/ghostty/commit/abc",
					"https://github.com/8bittts/yenchat/commit/abc",
				],
				"src/input/helpgen_actions.zig": [
					"https://github.com/ghostty-org/ghostty/edit/main/src/input/Binding.zig",
					"https://github.com/8bittts/yenchat/edit/main",
				],
				"src/extra/vim.zig": [
					"https://github.com/ghostty-org/ghostty",
					"https://github.com/8bittts/yenchat",
				],
				"src/extra/bash.zig": [
					"https://github.com/ghostty-org/ghostty/discussions/2994",
					"https://github.com/8bittts/yenchat/discussions",
				],
				"src/deps.zig": [
					"https://deps.files.yen.org/file https://github.com/yen-org/yen",
					"https://deps.files.ghostty.org/file https://github.com/ghostty-org/ghostty",
				],
				"macos/Links.swift": [
					"https://yen.org/docs https://tip.files.yen.org/appcast.xml https://release.files.yen.org/appcast.xml",
					"https://yen.chat/docs https://yen.chat/stable/appcast.xml https://yen.chat/stable/appcast.xml",
				],
			};
			for (const [path, [before]] of Object.entries(files)) {
				mkdirSync(dirname(join(root, path)), { recursive: true });
				writeFileSync(join(root, path), `${before}\n`);
			}
			for (let pass = 0; pass < 2; pass++) {
				const result = runBrandingHelper(root, "rewrite_overlay_urls");
				expect(result.status, output(result)).toBe(0);
				expect(output(result)).toContain("Branding helper passed");
				for (const [path, [, after]] of Object.entries(files))
					expect(readFileSync(join(root, path), "utf8")).toBe(`${after}\n`);
			}
			writeFileSync(
				join(root, "src/cli/version.zig"),
				"upstream changed URL\n",
			);
			const drift = runBrandingHelper(root, "rewrite_overlay_urls");
			expect(drift.status).toBe(1);
			expect(output(drift)).toContain("version provenance URL rewrite missing");
		});
	});

	test("URL rewrite scans preserve excluded files and reject empty candidates", () => {
		withTempDir((root) => {
			const empty = runBrandingHelper(root, "rewrite_overlay_urls");
			expect(empty.status).toBe(1);
			expect(output(empty)).toContain("zero candidate files");
			writeFileSync(
				join(root, "included.zig"),
				"https://yen.org https://deps.files.yen.org\n",
			);
			const protectedFiles = [
				".backup/file.zig",
				"zig-cache/file.zig",
				".zig-cache/file.zig",
				"zig-pkg/file.zig",
				"zig-pkg/package.swift",
				".zig-cache/package.swift",
				"zig-out/file.zig",
				"macos/build/file.zig",
				"build.zig.zon",
				"build.zig.zon.json",
				"._file.zig",
				".!file.zig",
			];
			const original = "https://yen.org https://deps.files.yen.org\n";
			for (const file of protectedFiles) {
				mkdirSync(dirname(join(root, file)), { recursive: true });
				writeFileSync(join(root, file), original);
			}
			const result = runBrandingHelper(root, "rewrite_overlay_urls");
			expect(result.status, output(result)).toBe(0);
			expect(readFileSync(join(root, "included.zig"), "utf8")).toBe(
				"https://yen.chat https://deps.files.ghostty.org\n",
			);
			for (const file of protectedFiles)
				expect(readFileSync(join(root, file), "utf8")).toBe(original);
		});
	});

	test("post-rename project configuration removes Calendar permission and preserves its deployment floor", () => {
		withTempDir((root) => {
			const project = join(root, "macos/YEN.xcodeproj/project.pbxproj");
			mkdirSync(dirname(project), { recursive: true });
			writeFileSync(
				project,
				"INFOPLIST_KEY_NSCalendarsUsageDescription = obsolete;\nMACOSX_DEPLOYMENT_TARGET = 15.0;\npath = Ghostty.app;\nINFOPLIST_PREPROCESS = YES;\n",
			);
			for (let pass = 0; pass < 2; pass++) {
				const result = runBrandingHelper(root, "configure_overlay_project");
				expect(result.status, output(result)).toBe(0);
				expect(readFileSync(project, "utf8")).toBe(
					"MACOSX_DEPLOYMENT_TARGET = 13.0;\npath = YEN.app;\nINFOPLIST_PREPROCESS = NO;\n",
				);
			}
		});
	});

	test("CLI help loop patch removes legacy compatibility loop anchors", () => {
		const patchBlock = patchCommands(["cli-help-tiered-action-filtering"]);
		const loopOld = readFileSync(
			join(patchesDir, "cli-help-action-loop.old"),
			"utf8",
		);
		const noteOld = readFileSync(
			join(patchesDir, "cli-help-policy-note.old"),
			"utf8",
		);
		expect(
			hasPatchArgument("--label", "CLI help tiered action filtering"),
		).toBe(true);
		expect(
			hasPatchArgument("--old-block", "@$PATCHES_DIR/cli-help-action-loop.old"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--extra-replace",
				"@$PATCHES_DIR/cli-help-policy-note.old:::@$PATCHES_DIR/cli-help-policy-note.new",
			),
		).toBe(true);

		withTempDir((fixtureRoot) => {
			const helpPath = join(fixtureRoot, "ghostty/src/cli/help.zig");
			mkdirSync(dirname(helpPath), { recursive: true });
			writeFileSync(
				helpPath,
				["pub fn help() {", loopOld, noteOld, "}"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied CLI help tiered action filtering",
			);
			const patched = readFileSync(helpPath, "utf8");
			expect(patched).toContain("action.shouldShowInHelp()");
			expect(patched).toContain("YEN_CLI_SUPPORT_ACTIONS=1");

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				helpPath,
				[
					"pub fn help() {",
					loopOld,
					noteOld.replace(
						"where `<action>` is one of actions listed above.",
						"where `<action>` is listed above.",
					),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("extra-replace anchor not found");
		});
	});

	test("CLI action policy patch applies, is idempotent, and fails closed on drift", () => {
		const patchBlock = patchCommands(["cli-action-policy"]);
		const payloadNames = [
			"cli-yen-build-config-import",
			"cli-yen-action-tier-enum",
			"cli-yen-action-policy-methods",
			"cli-yen-run-policy",
		];
		const oldBlocks = payloadNames.map((name) =>
			readFileSync(join(patchesDir, `${name}.old`), "utf8"),
		);

		expect(hasPatchArgument("--label", "CLI action policy")).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/cli-yen-build-config-import.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--extra-replace",
				"@$PATCHES_DIR/cli-yen-run-policy.old:::@$PATCHES_DIR/cli-yen-run-policy.new",
			),
		).toBe(true);

		withTempDir((fixtureRoot) => {
			const yenPath = join(fixtureRoot, "ghostty/src/cli/yen.zig");
			mkdirSync(dirname(yenPath), { recursive: true });
			writeFileSync(
				yenPath,
				["pub const Action = enum {", ...oldBlocks, "};"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain("Applied CLI action policy");
			const patched = readFileSync(yenPath, "utf8");
			expect(patched).toContain(
				'const build_config = @import("../build_config.zig");',
			);
			expect(patched).toContain("pub const ActionTier = enum");
			expect(patched).toContain("pub fn isAllowed(self: Action) bool");
			expect(patched).toContain("support-only and hidden by default");

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				yenPath,
				[
					"pub const Action = enum {",
					...oldBlocks.map((block, index) =>
						index === 2
							? block.replace("detectSpecialCase", "detectSpecialAction")
							: block,
					),
					"};",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("extra-replace anchor not found");
		});
	});

	test("surface route helper patch removes legacy helper compatibility anchor", () => {
		expect(hasPatchText("surfaceRouteEnvironmentKey")).toBe(true);
		expect(
			hasPatchArgument("--label", "Surface route environment helper"),
		).toBe(true);
		expect(
			hasPatchArgument("--label", "AppKit surface route environment stamp"),
		).toBe(true);
	});

	test("surface route environment patches apply, are idempotent, and fail closed on drift", () => {
		const patchBlock = patchCommands([
			"surface-route-environment-helper",
			"appkit-surface-route-environment-stamp",
		]);
		const helperOld = readFileSync(
			join(patchesDir, "surface-route-environment-helper.old"),
			"utf8",
		);
		const stampOld = readFileSync(
			join(patchesDir, "surface-route-stamp.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const surfaceDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View",
			);
			mkdirSync(surfaceDir, { recursive: true });
			const surfaceViewPath = join(surfaceDir, "SurfaceView.swift");
			const appKitPath = join(surfaceDir, "SurfaceView_AppKit.swift");
			writeFileSync(
				surfaceViewPath,
				["struct Config {", helperOld, "}"].join("\n"),
				"utf8",
			);
			writeFileSync(
				appKitPath,
				["func appkit() {", stampOld, "}"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
SURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied Surface route environment helper",
			);
			expect(output(firstRun)).toContain(
				"Applied AppKit surface route environment stamp",
			);
			expect(readFileSync(surfaceViewPath, "utf8")).toContain(
				'static let surfaceRouteEnvironmentKey = "YEN_SURFACE_ID"',
			);
			expect(readFileSync(appKitPath, "utf8")).toContain(
				"surface_cfg.setRouteEnvironmentID(self.id)",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				appKitPath,
				[
					"func appkit() {",
					stampOld.replace("baseConfig", "existingConfig"),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("persistent session patches apply, are idempotent, and fail closed on drift", () => {
		const patchBlock = patchCommands([
			"persistent-session-prepare",
			"persistent-session-close",
			"persistent-session-tree-leave",
			"persistent-session-window-close",
			"persistent-session-exec",
		]);
		const prepareOld = readFileSync(
			join(patchesDir, "persistent-session-prepare.old"),
			"utf8",
		);
		const closeOld = readFileSync(
			join(patchesDir, "persistent-session-close.old"),
			"utf8",
		);
		const execOld = readFileSync(
			join(patchesDir, "persistent-session-exec.old"),
			"utf8",
		);
		const treeLeaveOld = readFileSync(
			join(patchesDir, "persistent-session-tree-leave.old"),
			"utf8",
		);
		const windowCloseOld = readFileSync(
			join(patchesDir, "persistent-session-window-close.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const surfaceDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View",
			);
			const termioDir = join(fixtureRoot, "ghostty/src/termio");
			mkdirSync(surfaceDir, { recursive: true });
			mkdirSync(termioDir, { recursive: true });
			const appKitPath = join(surfaceDir, "SurfaceView_AppKit.swift");
			const execPath = join(termioDir, "Exec.zig");
			writeFileSync(
				appKitPath,
				["func appkit() {", prepareOld, "}", closeOld, "}"].join("\n"),
				"utf8",
			);
			writeFileSync(execPath, ["fn exec() {", execOld, "}"].join("\n"), "utf8");
			const terminalDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal",
			);
			mkdirSync(terminalDir, { recursive: true });
			const controllerPath = join(terminalDir, "BaseTerminalController.swift");
			writeFileSync(
				controllerPath,
				[
					"func surfaceTreeDidChange() {",
					treeLeaveOld,
					"",
					"        // If our surface tree becomes empty then we have no focused surface.",
					"}",
					"func windowWillClose() {",
					windowCloseOld,
					"}",
				].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain("Applied Persistent session prepare");
			expect(output(firstRun)).toContain("Applied Persistent session close");
			expect(output(firstRun)).toContain(
				"Applied Persistent session exec wrap",
			);
			const appKit = readFileSync(appKitPath, "utf8");
			// The pane is marked after the route stamp and before the surface is created.
			expect(appKit.indexOf("setRouteEnvironmentID(self.id)")).toBeLessThan(
				appKit.indexOf(
					"PersistentSessions.prepare(&surface_cfg, paneID: self.id)",
				),
			);
			expect(
				appKit.indexOf(
					"PersistentSessions.prepare(&surface_cfg, paneID: self.id)",
				),
			).toBeLessThan(appKit.indexOf("surface_cfg.withCValue"));
			expect(appKit).toContain("PersistentSessions.paneDidClose(self.id)");
			expect(output(firstRun)).toContain(
				"Applied Persistent session tree leave",
			);
			expect(output(firstRun)).toContain(
				"Applied Persistent session window close",
			);
			// Both controller hooks land, once each.
			const controller = readFileSync(controllerPath, "utf8");
			expect(controller).toContain(
				"PersistentSessions.paneLeftTree(surfaceView.id, undoExpiration: undoExpiration)",
			);
			expect(controller).toContain(
				"PersistentSessions.panesLeftClosingWindow(surfaceTree.map(\\.id), undoExpiration: undoExpiration)",
			);
			const exec = readFileSync(execPath, "utf8");
			// execCommand must receive the wrapped command, not the raw shell command.
			expect(exec).toContain('@import("yen_session.zig").wrapFromEnv(');
			expect(exec).toContain("            yen_session_command,\n");
			expect(exec).not.toContain(
				"            shell_command,\n            internal_os.passwd",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				execPath,
				[
					"fn exec() {",
					execOld.replace("execCommand(", "execCommandRenamed("),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("persistent session termios patches chain onto the exec wrap and fail closed on drift", () => {
		const chain = [
			"persistent-session-exec",
			"persistent-session-prepare-call",
			"persistent-session-subprocess-field",
			"persistent-session-subprocess-return",
			"persistent-session-threaddata-field",
			"persistent-session-threaddata-init",
			"persistent-session-termios-poll",
		];
		const patchBlock = patchCommands(chain);
		const upstreamBlocks = [
			"persistent-session-exec",
			"persistent-session-subprocess-field",
			"persistent-session-subprocess-return",
			"persistent-session-threaddata-field",
			"persistent-session-threaddata-init",
			"persistent-session-termios-poll",
		].map((name) => readFileSync(join(patchesDir, `${name}.old`), "utf8"));

		withTempDir((fixtureRoot) => {
			const termioDir = join(fixtureRoot, "ghostty/src/termio");
			mkdirSync(termioDir, { recursive: true });
			const execPath = join(termioDir, "Exec.zig");
			writeFileSync(execPath, upstreamBlocks.join("\n// --\n"), "utf8");
			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;

			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status, output(firstRun)).toBe(0);
			const exec = readFileSync(execPath, "utf8");
			// The command handed to execCommand comes from prepare(), and the
			// termios poll prefers the inner pty the subprocess recorded.
			expect(exec).toContain('@import("yen_session.zig").prepare(');
			expect(exec).not.toContain('@import("yen_session.zig").wrapFromEnv(');
			expect(exec).toContain(
				"const yen_session_command = yen_session.command;",
			);
			expect(exec).toContain(".yen_session_tty = yen_session.tty_file,");
			expect(exec).toContain(
				".yen_inner_tty_file = self.subprocess.yen_session_tty,",
			);
			expect(exec).toContain(
				".master = yen_inner_fd orelse exec.read_thread_fd,",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(readFileSync(execPath, "utf8")).toBe(exec);

			writeFileSync(
				execPath,
				upstreamBlocks
					.join("\n// --\n")
					.replace(".master = exec.read_thread_fd,", ".master = exec.pty_fd,"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("surface notification callback patch keeps async add guardrails", () => {
		const patchBlock = patchCommands([
			"surfaceview-async-notification-callback",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "surface-view-appkit-notification-callback.old"),
			"utf8",
		);
		expect(
			hasPatchArgument("--label", "SurfaceView async notification callback"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/surface-view-appkit-notification-callback.old",
			),
		).toBe(true);
		expect(
			hasPatchText("try await UNUserNotificationCenter.current().add(request)"),
		).toBe(true);

		withTempDir((fixtureRoot) => {
			const appKitPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
			);
			mkdirSync(dirname(appKitPath), { recursive: true });
			writeFileSync(
				appKitPath,
				["func notify() {", oldBlock, "}"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied SurfaceView async notification callback",
			);
			expect(readFileSync(appKitPath, "utf8")).toContain(
				"try await UNUserNotificationCenter.current().add(request)",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				appKitPath,
				[
					"func notify() {",
					oldBlock.replace(
						"UNUserNotificationCenter.current().add(request)",
						"notificationCenter.add(request)",
					),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("Ghostty.App notification and browser link patches are patch-file driven", () => {
		const patchBlock = patchCommands([
			"ghostty-app-managed-notification-delivery",
			"ghostty-app-terminal-browser-link-routing",
		]);
		const notificationOld = readFileSync(
			join(patchesDir, "ghostty-app-managed-notification.old"),
			"utf8",
		);
		const browserLinkOld = readFileSync(
			join(patchesDir, "ghostty-app-terminal-browser-link.old"),
			"utf8",
		);

		expect(
			hasPatchArgument("--label", "Ghostty.App managed notification delivery"),
		).toBe(true);
		expect(
			hasPatchArgument("--label", "Ghostty.App terminal browser link routing"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/ghostty-app-managed-notification.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/ghostty-app-terminal-browser-link.old",
			),
		).toBe(true);

		withTempDir((fixtureRoot) => {
			const ghosttyAppPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Ghostty.App.swift",
			);
			mkdirSync(dirname(ghosttyAppPath), { recursive: true });
			writeFileSync(
				ghosttyAppPath,
				["struct GhosttyApp {", notificationOld, browserLinkOld, "}"].join(
					"\n",
				),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied Ghostty.App managed notification delivery",
			);
			expect(output(firstRun)).toContain(
				"Applied Ghostty.App terminal browser link routing",
			);
			const patched = readFileSync(ghosttyAppPath, "utf8");
			expect(patched).toContain(
				"AppDelegate.deliverManagedSurfaceNotification(",
			);
			expect(patched).toContain("TerminalBrowserLinkRouter.open(url)");

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				ghosttyAppPath,
				[
					"struct GhosttyApp {",
					notificationOld,
					browserLinkOld.replace(
						"NSWorkspace.shared.open(url)",
						"workspace.open(url)",
					),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("split-focus hit-test patch remains wired", () => {
		expect(
			hasPatchArgument("--label", "Split-focus hit-test coordinate fix"),
		).toBe(true);
		expect(
			hasPatchArgument("--old-block", "@$PATCHES_DIR/split-focus-hit-test.old"),
		).toBe(true);
		expect(
			hasPatchArgument("--new-block", "@$PATCHES_DIR/split-focus-hit-test.new"),
		).toBe(true);
	});

	test("split-focus hit-test patch applies, is idempotent, and fails closed on drift", () => {
		const splitFocusPatchBlock = patchCommands([
			"split-focus-hit-test-coordinate-fix",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "split-focus-hit-test.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const appKitPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN/Surface View"), {
				recursive: true,
			});
			writeFileSync(appKitPath, ["top", oldBlock, "bottom"].join("\n"), "utf8");

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${splitFocusPatchBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied Split-focus hit-test coordinate fix",
			);

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${splitFocusPatchBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				appKitPath,
				[
					"top",
					oldBlock.replace("hitTest here,", "hit testing here,"),
					"bottom",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${splitFocusPatchBlock}`,
			]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("undo-timeout default patch applies, is idempotent, and fails closed on drift", () => {
		const undoTimeoutBlock = patchCommands([
			"undo-timeout-default-preservation",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "undo-timeout-default.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const configSwiftPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Ghostty.Config.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN"), {
				recursive: true,
			});
			writeFileSync(
				configSwiftPath,
				["struct Fixture {", oldBlock, "}"].join("\n"),
				"utf8",
			);

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nCONFIG_SWIFT="ghostty/macos/Sources/YEN/Ghostty.Config.swift"\n${undoTimeoutBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied undo-timeout default preservation",
			);

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nCONFIG_SWIFT="ghostty/macos/Sources/YEN/Ghostty.Config.swift"\n${undoTimeoutBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				configSwiftPath,
				[
					"struct Fixture {",
					oldBlock.replace(
						"_ = yen_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8)))",
						"_ = yen_config_get(config, &v, key, UInt(key.utf8.count))",
					),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nCONFIG_SWIFT="ghostty/macos/Sources/YEN/Ghostty.Config.swift"\n${undoTimeoutBlock}`,
			]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("performable clipboard shortcut patches remain wired and idempotent", () => {
		expect(
			hasPatchArgument("--label", "Performable clipboard selector helper"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"static func fixedYENMenuShortcutSelector(",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"#selector(AppDelegate.toggleGitDrawer(_:))",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"static func shouldPerformYENMenuShortcutBeforeTerminalEncoding(",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/performable-clipboard-selector.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/performable-clipboard-selector-pre-fixed-git-drawer.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Performable clipboard selector fixed-shortcut upgrade",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"let menuAction = appDelegate?.yenMenuActionSelector(for: event)",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"if Self.shouldPerformYENMenuShortcutBeforeTerminalEncoding(",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"appDelegate?.performYENBindingMenuKeyEquivalent(with: event) == true",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/performable-clipboard-shortcut-pre-fixed-git-drawer.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Performable clipboard shortcut fixed-shortcut upgrade",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/performable-clipboard-shortcut.new",
			),
		).toBe(true);
		expect(hasPatchArgument("--label", "Directional split chord routing")).toBe(
			true,
		);
		expect(
			hasPatchArgument(
				"--marker-all",
				"appDelegate?.directionalSplitSelector(for: event)",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker-all",
				"NSApp.sendAction(directionalSplitAction, to: self, from: nil)",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/directional-split-chord.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/directional-split-chord.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument("--label", "Paste selection validation purity"),
		).toBe(true);
		expect(
			hasPatchArgument("--marker", "return pb.hasOpinionatedStringContents()"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/paste-selection-validation.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/paste-selection-validation.new",
			),
		).toBe(true);

		const clipboardPatchBlock = patchCommands([
			"performable-clipboard-selector-helper",
			"performable-clipboard-selector-fixed-shortcut-upgrade",
			"performable-clipboard-shortcut-routing",
			"performable-clipboard-shortcut-fixed-shortcut-upgrade",
			"directional-split-chord-routing",
			"paste-selection-validation-purity",
		]);
		const selectorOld = readFileSync(
			join(patchesDir, "performable-clipboard-selector.old"),
			"utf8",
		);
		const selectorPreFixed = readFileSync(
			join(
				patchesDir,
				"performable-clipboard-selector-pre-fixed-git-drawer.old",
			),
			"utf8",
		);
		const selectorNew = readFileSync(
			join(patchesDir, "performable-clipboard-selector.new"),
			"utf8",
		);
		const shortcutOld = readFileSync(
			join(patchesDir, "performable-clipboard-shortcut.old"),
			"utf8",
		);
		const shortcutPreFixed = readFileSync(
			join(
				patchesDir,
				"performable-clipboard-shortcut-pre-fixed-git-drawer.old",
			),
			"utf8",
		);
		const shortcutNew = readFileSync(
			join(patchesDir, "performable-clipboard-shortcut.new"),
			"utf8",
		);
		const selectionValidationOld = readFileSync(
			join(patchesDir, "paste-selection-validation.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const appKitPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN/Surface View"), {
				recursive: true,
			});
			writeFileSync(
				appKitPath,
				[
					"top",
					selectorOld,
					"middle",
					shortcutOld,
					selectionValidationOld,
					"bottom",
				].join("\n"),
				"utf8",
			);

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${clipboardPatchBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			const firstOutput = output(firstRun);
			expect(output(firstRun)).toContain(
				"Applied Performable clipboard selector helper",
			);
			expect(output(firstRun)).toContain(
				"Performable clipboard selector fixed-shortcut upgrade already applied",
			);
			expect(output(firstRun)).toContain(
				"Applied Performable clipboard shortcut routing",
			);
			expect(output(firstRun)).toContain(
				"Performable clipboard shortcut fixed-shortcut upgrade already applied",
			);
			expect(output(firstRun)).toContain(
				"Applied Directional split chord routing",
			);
			expect(
				firstOutput.includes("Applied Paste selection validation purity") ||
					firstOutput.includes(
						"Paste selection validation purity already applied",
					),
			).toBe(true);

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${clipboardPatchBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain(
				"Performable clipboard selector helper already applied",
			);
			expect(output(secondRun)).toContain(
				"Performable clipboard selector fixed-shortcut upgrade already applied",
			);
			expect(output(secondRun)).toContain(
				"Performable clipboard shortcut routing already applied",
			);
			expect(output(secondRun)).toContain(
				"Performable clipboard shortcut fixed-shortcut upgrade already applied",
			);
			expect(output(secondRun)).toContain(
				"Directional split chord routing already applied",
			);
			expect(output(secondRun)).toContain(
				"Paste selection validation purity already applied",
			);
		});

		withTempDir((fixtureRoot) => {
			const appKitPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN/Surface View"), {
				recursive: true,
			});
			writeFileSync(
				appKitPath,
				[
					"top",
					selectorPreFixed,
					"middle",
					shortcutPreFixed,
					selectionValidationOld,
					"bottom",
				].join("\n"),
				"utf8",
			);

			const upgradeRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${clipboardPatchBlock}`,
			]);
			expect(upgradeRun.status).toBe(0);
			expect(output(upgradeRun)).toContain(
				"Applied Performable clipboard selector fixed-shortcut upgrade",
			);
			expect(output(upgradeRun)).toContain(
				"Applied Performable clipboard shortcut fixed-shortcut upgrade",
			);
		});

		for (const [label, selectorFixture, shortcutFixture] of [
			[
				"selector",
				selectorNew.replace(
					"            menuAction == #selector(AppDelegate.toggleGitDrawer(_:))",
					"            false",
				),
				shortcutNew,
			],
			[
				"shortcut",
				selectorNew,
				shortcutNew.replace(
					"               appDelegate?.performYENBindingMenuKeyEquivalent(with: event) == true {",
					"               false {",
				),
			],
		] as const) {
			withTempDir((fixtureRoot) => {
				const appKitPath = join(
					fixtureRoot,
					"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
				);
				mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN/Surface View"), {
					recursive: true,
				});
				writeFileSync(
					appKitPath,
					[
						"top",
						selectorFixture,
						"middle",
						shortcutFixture,
						selectionValidationOld,
						"bottom",
					].join("\n"),
					"utf8",
				);

				const partialRun = run("bash", [
					"-lc",
					`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nSURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"\n${clipboardPatchBlock}`,
				]);
				expect(partialRun.status, `${label} partial marker state`).toBe(1);
				expect(output(partialRun)).toContain("patch anchor not found");
			});
		}
	});

	test("clipboard image path bridge patch remains wired and idempotent", () => {
		expect(
			hasPatchArgument("--label", "Opinionated clipboard image path bridge"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker",
				"(try? url.checkResourceIsReachable()) == true",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-path.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-path.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Opinionated clipboard image temp-root hardening",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-temp-root.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-temp-root.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Opinionated clipboard image retention hardening",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-retention.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-retention.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Opinionated clipboard image readability check",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--proximity-old",
				"return canReadObject(forClasses: [NSImage.self], options: nil)",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Opinionated clipboard image temp-file permissions",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-permissions.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/opinionated-clipboard-image-permissions.new",
			),
		).toBe(true);

		const clipboardImageBridgeBlock = patchCommands([
			"opinionated-clipboard-image-path-bridge",
			"opinionated-clipboard-image-temp-root-hardening",
			"opinionated-clipboard-image-retention-hardening",
			"opinionated-clipboard-image-readability-check",
			"opinionated-clipboard-image-temp-file-permissions",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "opinionated-clipboard-image-path.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const pasteboardExtensionPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/Helpers/Extensions"), {
				recursive: true,
			});
			writeFileSync(
				pasteboardExtensionPath,
				["top", oldBlock, "bottom"].join("\n"),
				"utf8",
			);

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\n${clipboardImageBridgeBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied Opinionated clipboard image path bridge",
			);

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\n${clipboardImageBridgeBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain(
				"Opinionated clipboard image path bridge already applied",
			);
			expect(output(secondRun)).toContain(
				"Opinionated clipboard image temp-root hardening already applied",
			);
			expect(output(secondRun)).toContain(
				"Opinionated clipboard image retention hardening already applied",
			);
			expect(output(secondRun)).toContain(
				"Opinionated clipboard image readability check already applied",
			);
			expect(output(secondRun)).toContain(
				"Opinionated clipboard image temp-file permissions already applied",
			);
		});
	});

	test("right-click context-menu selection patch remains wired and self-contained", () => {
		expect(
			hasPatchArgument("--label", "Right-click context-menu selection patch"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--marker",
				"Preserve the current selection state on right-click and",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/right-click-context-select.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/right-click-context-select.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"Right-click context-menu stale block self-heal",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/right-click-context-select-stale.old",
			),
		).toBe(true);
	});

	test("vendor workflows require overlay regression gate for right-click context-menu hardening", () => {
		const vendorSkillAudit = readFileSync(vendorSkillAuditPath, "utf8");
		expect(vendorSkillAudit).toContain(
			"bun test tests/45-overlay-patching.test.ts",
		);
		expect(vendorSkillAudit).toContain(
			"Preserve the current selection state on right-click and",
		);
	});

	test("branding phase brands AppleScript content and preserves dependency metadata", () => {
		withTempDir((root) => {
			mkdirSync(join(root, "ghostty/macos"), { recursive: true });
			writeFileSync(
				join(root, "ghostty/macos/Ghostty.sdef"),
				'<dictionary title="Ghostty"/>\n',
			);
			writeFileSync(
				join(root, "ghostty/macos/App.swift"),
				'let bundle = "com.mitchellh.ghostty"\n',
			);
			writeFileSync(
				join(root, "ghostty/dependency.zig"),
				"https://deps.files.ghostty.org\n",
			);
			writeFileSync(join(root, "ghostty/build.zig.zon"), ".name = .ghostty\n");
			for (const folder of [".zig-cache", "zig-pkg"]) {
				mkdirSync(join(root, "ghostty", folder), { recursive: true });
				writeFileSync(
					join(root, "ghostty", folder, "vendor.swift"),
					"Ghostty dependency\n",
				);
			}
			const result = run(
				"bash",
				[
					"-c",
					`set -euo pipefail\nexport LC_ALL=C\nREPO_ROOT=${shellQuote(repoRoot)}\nsource ${shellQuote(patchRuntimePath)}\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-branding.sh"))}\nsource ${shellQuote(join(overlayPhasesDir, "01-branding.sh"))}\nprintf 'Branding phase passed\\n'`,
				],
				{ cwd: root },
			);
			expect(result.status, output(result)).toBe(0);
			expect(output(result)).toContain("Branding phase passed");
			expect(
				readFileSync(join(root, "ghostty/macos/Ghostty.sdef"), "utf8"),
			).toBe('<dictionary title="YEN"/>\n');
			expect(readFileSync(join(root, "ghostty/macos/App.swift"), "utf8")).toBe(
				'let bundle = "com.yenchat.yen"\n',
			);
			expect(readFileSync(join(root, "ghostty/dependency.zig"), "utf8")).toBe(
				"https://deps.files.ghostty.org\n",
			);
			expect(readFileSync(join(root, "ghostty/build.zig.zon"), "utf8")).toBe(
				".name = .ghostty\n",
			);
			for (const folder of [".zig-cache", "zig-pkg"]) {
				expect(
					readFileSync(join(root, "ghostty", folder, "vendor.swift"), "utf8"),
				).toBe("Ghostty dependency\n");
			}
		});
	});

	test("AppleScript dictionary verification rejects missing and mismatched overlays", () => {
		withTempDir((root) => {
			mkdirSync(join(root, "ghostty/macos"), { recursive: true });
			mkdirSync(join(root, "overlays/macos"), { recursive: true });
			writeFileSync(join(root, "ghostty/macos/YEN.sdef"), "branded upstream\n");
			const invoke = () =>
				run(
					"bash",
					[
						"-c",
						`set -euo pipefail\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nverify_overlay_applescript_dictionary\nprintf 'Dictionary verified\\n'`,
					],
					{ cwd: root },
				);
			const absent = invoke();
			expect(absent.status).toBe(1);
			expect(output(absent)).toContain(
				"Overlay AppleScript dictionary missing",
			);
			writeFileSync(join(root, "overlays/macos/YEN.sdef"), "stale overlay\n");
			const drift = invoke();
			expect(drift.status).toBe(1);
			expect(output(drift)).toContain("dictionary drifted");
			writeFileSync(
				join(root, "overlays/macos/YEN.sdef"),
				"branded upstream\n",
			);
			const valid = invoke();
			expect(valid.status, output(valid)).toBe(0);
			expect(output(valid)).toContain("Dictionary verified");
		});
	});

	test("AppleScript rename guard requires renamed resources and rejects stale paths", () => {
		withTempDir((root) => {
			const appleScriptDir = join(root, "macos/Sources/Features/AppleScript");
			mkdirSync(appleScriptDir, { recursive: true });
			const script = `set -euo pipefail\nFILES_RENAMED=11\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-rename-preflight.sh"))}\nverify_overlay_renames\nprintf 'RENAMES_VERIFIED\\n'`;
			const missingDictionary = run("bash", ["-c", script], { cwd: root });
			expect(missingDictionary.status).toBe(1);
			expect(output(missingDictionary)).toContain(
				"AppleScript dictionary rename missing",
			);
			writeFileSync(join(root, "macos/YEN.sdef"), "fixture");
			const missingModifiers = run("bash", ["-c", script], { cwd: root });
			expect(missingModifiers.status).toBe(1);
			expect(output(missingModifiers)).toContain(
				"AppleScript modifiers extension rename missing",
			);
			writeFileSync(
				join(appleScriptDir, "YEN.Input.Mods+AppleScript.swift"),
				"fixture",
			);
			const complete = run("bash", ["-c", script], { cwd: root });
			expect(complete.status, output(complete)).toBe(0);
			expect(output(complete)).toContain("RENAMES_VERIFIED");
			writeFileSync(join(root, "macos/Ghostty.sdef"), "stale");
			const stale = run("bash", ["-c", script], { cwd: root });
			expect(stale.status).toBe(1);
			expect(output(stale)).toContain("left stale Ghostty AppleScript paths");
		});
	});

	test("AppleScript action policy helper handles accepted anchors and drift", () => {
		const helper = readFileSync(appleScriptPolicyHelperPath, "utf8");
		const block = (name: string) => {
			const match = helper.match(new RegExp(`${name} = """([\\s\\S]*?)"""`));
			expect(match).not.toBeNull();
			return match?.[1] ?? "";
		};
		const current = block("CURRENT_BLOCK");
		const allowlist = block("ALLOWLIST_BLOCK");
		const legacy = block("LEGACY_BLOCK");

		for (const [name, source] of [
			["current", current],
			["allowlist", allowlist],
			["legacy", legacy],
		] as const) {
			withTempDir((fixtureRoot) => {
				const appDelegatePath = join(
					fixtureRoot,
					"AppDelegate+AppleScript.swift",
				);
				writeFileSync(
					appDelegatePath,
					["func perform() {", source, "}"].join("\n"),
					"utf8",
				);
				const firstRun = run("python3", [
					appleScriptPolicyHelperPath,
					appDelegatePath,
				]);
				expect(firstRun.status).toBe(0);
				expect(output(firstRun)).toContain(
					"Aligned AppleScript perform action with shared automation policy",
				);
				const patched = readFileSync(appDelegatePath, "utf8");
				expect(patched).toContain("isAppleScriptActionAllowed(action)");
				expect(patched).toContain("resolveAutomationCommand(action)");
				expect(patched).toContain("resolvedCommand.action");

				const secondRun = run("python3", [
					appleScriptPolicyHelperPath,
					appDelegatePath,
				]);
				expect(secondRun.status).toBe(0);
				expect(output(secondRun)).toContain(
					"already aligned (idempotent skip)",
				);

				writeFileSync(
					appDelegatePath,
					[
						"func perform() {",
						source.replace("Missing terminal target.", "Missing target."),
						"}",
					].join("\n"),
					"utf8",
				);
				const driftRun = run("python3", [
					appleScriptPolicyHelperPath,
					appDelegatePath,
				]);
				expect(driftRun.status).toBe(1);
				expect(output(driftRun)).toContain("perform action anchor not found");
				expect(name.length).toBeGreaterThan(0);
			});
		}
	});

	test("project path restoration supports both rename states and rejects Sparkle drift", () => {
		for (const projectName of ["Ghostty", "YEN"])
			withTempDir((root) => {
				const project = join(
					root,
					`macos/${projectName}.xcodeproj/project.pbxproj`,
				);
				mkdirSync(dirname(project), { recursive: true });
				const input =
					'/* XCRemoteSwiftPackageReference "Sparkle" */ = {\nkind = exactVersion;\nversion = 2.9.6;\n};\n' +
					'			membershipExceptions = (\n				"App/AppDelegate+YEN.swift",\n				YEN/YEN.Surface.swift,\n			);\n			target = A5B30530299BEAAA0047F10C /* YEN */;\n' +
					"path = YEN/YENPackage.swift;\npath = YEN/YENDelegate.swift;\npath = Features/Settings/SettingsView.swift;\n";
				writeFileSync(project, input);
				const first = runBrandingHelper(root, "restore_overlay_project_paths");
				expect(first.status, output(first)).toBe(0);
				const restored = readFileSync(project, "utf8");
				expect(restored).toContain("path = YEN/GhosttyPackage.swift;");
				expect(restored).toContain("path = YEN/GhosttyDelegate.swift;");
				expect(restored).toContain(
					"path = Features/Settings/SettingsPanel.swift;",
				);
				expect(restored).toContain("YEN/YEN.ConfigTypes.swift,");
				expect(restored).not.toContain('"App/AppDelegate+Ghostty.swift",');
				expect(restored).not.toContain("YEN/Ghostty.Surface.swift,");
				const second = runBrandingHelper(root, "restore_overlay_project_paths");
				expect(second.status, output(second)).toBe(0);
				expect(readFileSync(project, "utf8")).toBe(restored);
				writeFileSync(
					project,
					input.replace("version = 2.9.6", "version = 2.5.1"),
				);
				const drift = runBrandingHelper(root, "restore_overlay_project_paths");
				expect(drift.status).toBe(1);
				expect(output(drift)).toContain("below the audited floor");
			});
	});

	test("patch plan resolves surface operations to their required targets", () => {
		for (const label of [
			"Runtime padding reload fix",
			"Selection repaint fix",
			"Right-click context-menu selection patch",
		]) {
			expect(patchForLabel(label).target).toBe("ghostty/src/Surface.zig");
		}
		for (const label of [
			"SurfaceView async notification callback",
			"Split-focus hit-test coordinate fix",
			"Performable clipboard selector helper",
			"AppKit surface route environment stamp",
		]) {
			expect(patchForLabel(label).target).toBe(
				"ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift",
			);
		}
	});

	test("branding verification covers AppleScript, split-focus, tab-title restore, and native fullscreen guardrails", () => {
		const verifyBranding = readFileSync(
			join(repoRoot, "scripts/04-verify-branding.sh"),
			"utf8",
		);
		expect(verifyBranding).toContain("ghostty/macos/YEN.sdef");
		expect(verifyBranding).toContain("overlays/macos/YEN.sdef");
		expect(verifyBranding).toContain(
			"Stale AppleScript dictionary path present (Ghostty.sdef)",
		);
		expect(verifyBranding).toContain(
			"Overlay YEN.sdef drift detected vs branded build-tree AppleScript dictionary",
		);
		expect(verifyBranding).toContain(
			"pbxproj missing YEN.sdef AppleScript resource reference",
		);
		expect(verifyBranding).toContain(
			"AppleScript sdef / @objc class wiring mismatch or Ghostty residue detected",
		);
		expect(verifyBranding).toContain(
			"AppleScript perform action missing shared automation allowlist guard",
		);
		expect(verifyBranding).toContain(
			"AppleScript perform action missing automation audit logging",
		);
		expect(verifyBranding).toContain(
			"macos-applescript default drifted from true",
		);
		expect(verifyBranding).toContain(
			"Split-focus hit-testing helper missing in TerminalSplitTreeView.swift",
		);
		expect(verifyBranding).toContain(
			"AppKit split-focus hit testing is not using content-view coordinates",
		);
		expect(verifyBranding).toContain(
			"Split-focus content-view hit helper missing descendant ownership guard",
		);
		expect(verifyBranding).toContain(
			"BaseTerminalController titleOverride does not invalidate app/window restorable state",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing hasOpinionatedStringContents()",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing clipboard image temp-file prefix",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing dedicated clipboard image temp root",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing stale clipboard image pruning",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing temp-root permission hardening",
		);
		expect(verifyBranding).toContain(
			"NSPasteboard opinionated contents helper missing temp-file permission hardening",
		);
		expect(verifyBranding).toContain(
			"SurfaceView_AppKit performable clipboard routing is not using hasOpinionatedStringContents() for the standard clipboard",
		);
		expect(verifyBranding).toContain(
			"SurfaceView_AppKit performable clipboard routing is not using hasOpinionatedStringContents() for the selection clipboard",
		);
		expect(verifyBranding).toContain(
			"SurfaceView_AppKit pasteSelection validation is not using hasOpinionatedStringContents()",
		);
		expect(verifyBranding).toContain(
			"TerminalController fullscreen notification helper file missing",
		);
		expect(verifyBranding).toContain(
			"TerminalController fullscreen notification path is not routed through the shared helper",
		);
		expect(verifyBranding).toContain(
			"Native fullscreen helper is not using effective fullscreen state",
		);
	});

	test("ghostty package sendable retrofit removal remains wired", () => {
		const patchBlock = patchCommands([
			"ghosttypackage-sendable-retrofit-removal",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "ghostty-package-sendable-retrofit.old"),
			"utf8",
		);

		expect(
			hasPatchArgument("--label", "GhosttyPackage Sendable retrofit removal"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/ghostty-package-sendable-retrofit.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--new-block",
				"@$PATCHES_DIR/ghostty-package-sendable-retrofit.new",
			),
		).toBe(true);
		expect(hasPatchArgument("--old-absent-ok")).toBe(true);
		expect(
			hasPatchArgument(
				"--old-absent-drift-pattern",
				"extension yen_surface_t: @unchecked @retroactive Sendable {}",
			),
		).toBe(true);

		withTempDir((fixtureRoot) => {
			const packagePath = join(
				fixtureRoot,
				"ghostty/macos/Sources/YEN/GhosttyPackage.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/YEN"), {
				recursive: true,
			});
			writeFileSync(
				packagePath,
				["top", oldBlock, "bottom"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied GhosttyPackage Sendable retrofit removal",
			);
			expect(readFileSync(packagePath, "utf8")).not.toContain(oldBlock);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				packagePath,
				[
					"top",
					"extension yen_surface_t: @unchecked @retroactive Sendable {}",
					"bottom",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor changed shape");
		});
	});

	test("overlay phase order and shared verification remain wired", () => {
		const source = readFileSync(applyOverlaysPath, "utf8");
		const declared = [...source.matchAll(/^\s+"(\d{2}-[a-z-]+\.sh)"$/gm)].map(
			(match) => match[1],
		);
		expect(declared).toEqual([
			"01-branding.sh",
			"02-renames.sh",
			"03-project.sh",
			"04-icons.sh",
			"05-emoji.sh",
			"06-copy.sh",
			"07-patches.sh",
			"08-verification.sh",
		]);
		expect(overlayPhaseNames).toEqual(declared as string[]);
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-phases/$phase"',
		);
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-verification.sh"',
		);
		expect(phaseSource("01-branding.sh")).toContain(
			"\nrestore_overlay_project_paths\n",
		);
		expect(phaseSource("03-project.sh")).toContain(
			"\nconfigure_overlay_project\n",
		);
		const patches = phaseSource("07-patches.sh");
		expect(patches.indexOf("\nverify_overlay_shift_enter\n")).toBeGreaterThan(
			0,
		);
		expect(
			patches.indexOf("\nremove_overlay_wrapper_sendable\n"),
		).toBeGreaterThan(patches.indexOf("\nverify_overlay_shift_enter\n"));
		expect(phaseSource("08-verification.sh")).toContain(
			"\nverify_overlay_app_hooks\n",
		);
	});

	test("surface and inspector wrapper sendable removal is byte-stable and fails closed on drift", () => {
		const wrapperSendableBlock = `source ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nremove_overlay_wrapper_sendable`;

		withTempDir((fixtureRoot) => {
			const wrapperDir = join(fixtureRoot, "ghostty/macos/Sources/YEN");
			const surfacePath = join(wrapperDir, "Ghostty.Surface.swift");
			const inspectorPath = join(wrapperDir, "Ghostty.Inspector.swift");
			const surfaceContent = [
				"import Foundation",
				"",
				"final class Surface {",
				"\tlet raw: UnsafeMutableRawPointer?",
				"}",
			].join("\n");
			const inspectorContent = [
				"import Foundation",
				"",
				"final class Inspector {",
				"\tlet raw: UnsafeMutableRawPointer?",
				"}",
			].join("\n");
			mkdirSync(wrapperDir, { recursive: true });
			writeFileSync(surfacePath, surfaceContent, "utf8");
			writeFileSync(inspectorPath, inspectorContent, "utf8");

			const idempotentRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nREPO_ROOT="${repoRoot}"\n${overlayTallyFns}\n${wrapperSendableBlock}`,
			]);
			expect(idempotentRun.status).toBe(0);
			expect(output(idempotentRun)).toContain(
				"Surface wrapper class Sendable conformance already removed",
			);
			expect(output(idempotentRun)).toContain(
				"Inspector wrapper class Sendable conformance already removed",
			);
			expect(readFileSync(surfacePath, "utf8")).toBe(surfaceContent);
			expect(readFileSync(inspectorPath, "utf8")).toBe(inspectorContent);

			writeFileSync(
				surfacePath,
				surfaceContent.replace(
					"final class Surface {",
					"final class Surface: Sendable {",
				),
				"utf8",
			);
			const positiveRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nREPO_ROOT="${repoRoot}"\n${overlayTallyFns}\n${wrapperSendableBlock}`,
			]);
			expect(positiveRun.status).toBe(0);
			expect(output(positiveRun)).toContain(
				"Removed Sendable conformance from Surface wrapper class",
			);
			expect(readFileSync(surfacePath, "utf8")).toBe(surfaceContent);

			writeFileSync(
				surfacePath,
				surfaceContent.replace(
					"final class Surface {",
					"final class Surface: @unchecked Sendable {",
				),
				"utf8",
			);
			const driftRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nREPO_ROOT="${repoRoot}"\n${overlayTallyFns}\n${wrapperSendableBlock}`,
			]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain(
				"Surface wrapper Sendable conformance changed shape",
			);
		});
	});

	test("wrapper sendable removal fails closed on missing file, missing class, multi-decl, and extra-conformance drift", () => {
		const wrapperSendableBlock = `source ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nremove_overlay_wrapper_sendable`;

		const runBlock = (fixtureRoot: string) =>
			run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nREPO_ROOT="${repoRoot}"\n${overlayTallyFns}\n${wrapperSendableBlock}`,
			]);
		const writeWrapper = (root: string, surface: string, inspector: string) => {
			const wrapperDir = join(root, "ghostty/macos/Sources/YEN");
			mkdirSync(wrapperDir, { recursive: true });
			writeFileSync(join(wrapperDir, "Ghostty.Surface.swift"), surface, "utf8");
			writeFileSync(
				join(wrapperDir, "Ghostty.Inspector.swift"),
				inspector,
				"utf8",
			);
		};
		const plainInspector = "final class Inspector {\n}\n";

		// Missing file entirely: must fail closed, not silently skip.
		withTempDir((root) => {
			const result = runBlock(root);
			expect(result.status).toBe(1);
			expect(output(result)).toContain("wrapper class file missing");
		});

		// File present but class declaration gone (e.g. upstream renamed it).
		withTempDir((root) => {
			writeWrapper(root, "import Foundation\n", plainInspector);
			const result = runBlock(root);
			expect(result.status).toBe(1);
			expect(output(result)).toContain(
				"Surface wrapper class declaration missing",
			);
		});

		// Multiple matching declarations: ambiguous, must fail closed.
		withTempDir((root) => {
			writeWrapper(
				root,
				"final class Surface {\n}\nfinal class Surface {\n}\n",
				plainInspector,
			);
			const result = runBlock(root);
			expect(result.status).toBe(1);
			expect(output(result)).toContain(
				"Surface wrapper class declaration count changed",
			);
		});

		// Extra conformance alongside Sendable (shape drift the exact anchor misses).
		withTempDir((root) => {
			writeWrapper(
				root,
				"final class Surface: Sendable, Foo {\n}\n",
				plainInspector,
			);
			const result = runBlock(root);
			expect(result.status).toBe(1);
			expect(output(result)).toContain(
				"Surface wrapper Sendable conformance changed shape",
			);
		});

		// Extension conformance elsewhere in the file must fail closed too.
		withTempDir((root) => {
			writeWrapper(
				root,
				"final class Surface {\n}\nextension Surface: Sendable {\n}\n",
				plainInspector,
			);
			const result = runBlock(root);
			expect(result.status).toBe(1);
			expect(output(result)).toContain(
				"Surface wrapper Sendable conformance remains",
			);
		});
	});

	test("hidden swap-chain overlays are retired", () => {
		// The three hidden swap-chain patches were retired when upstream
		// ghostty-org/ghostty 683d8db6 (#14017) shipped the same behavior
		// natively: `swap_chain` became `?SwapChain` (replacing the `defunct`
		// bool the overlay leaned on), a `display_realized` guard was added,
		// and `setVisible(false)` now calls `releaseGpuResources()` under
		// `comptime !apprt.must_draw_from_app_thread`. That gate is equivalent
		// for YEN: `must_draw_from_app_thread = true` is declared only in
		// src/apprt/gtk/App.zig, so it is false for the embedded macOS build.
		//
		// This marker exists so the patches cannot be silently reintroduced
		// against upstream's new shape, where the old `defunct` anchors would
		// no longer mean what they used to.
		// Every patch label and anchor must be gone, not merely commented near.
		expect(hasPatchArgument("--label", "hidden swap-chain import")).toBe(false);
		expect(hasPatchArgument("--label", "hidden swap-chain renderer")).toBe(
			false,
		);
		expect(
			hasPatchArgument("--label", "hidden swap-chain thread ordering"),
		).toBe(false);
		// The patch files themselves must be deleted, so a reintroduced label
		// cannot quietly resolve against a leftover block.
		for (const stem of ["import", "const", "renderer", "thread"]) {
			for (const ext of ["old", "new"]) {
				expect(
					existsSync(
						join(
							import.meta.dir,
							`../scripts/lib/patches/hidden-swapchain-${stem}.${ext}`,
						),
					),
					`hidden-swapchain-${stem}.${ext} should be deleted with the retired overlay`,
				).toBe(false);
			}
		}
		// The unrelated hidden-titlebar pair must survive this retirement.
		expect(
			existsSync(
				join(
					import.meta.dir,
					"../scripts/lib/patches/hidden-titlebar-effective-fullscreen.old",
				),
			),
		).toBe(true);
	});

	test("sparkle runtime floor patch is retired in favor of the assertion", () => {
		// Upstream ghostty-org/ghostty e8aa0986 (#14082) pinned the Sparkle SPM
		// requirement to `exactVersion 2.9.6`, replacing the broad
		// `upToNextMajorVersion` 2.5.1 floor this patch used to raise to 2.9.4.
		// A content patch would only fight that pin, so the floor is now the
		// fail-closed assertion in scripts/lib/sparkle-runtime-floor.sh (covered
		// behaviorally in tests/123). This marker keeps the old label and
		// anchors from being reintroduced against upstream's new block shape.
		expect(hasPatchArgument("--label", "Sparkle runtime security floor")).toBe(
			false,
		);
		expect(hasPatchArgument("--marker", "minimumVersion = 2.9.4;")).toBe(false);
		// The payload files must be deleted so a reintroduced label cannot
		// quietly resolve against a leftover block.
		for (const ext of ["old", "new"]) {
			expect(
				existsSync(join(patchesDir, `sparkle-runtime-floor.${ext}`)),
				`sparkle-runtime-floor.${ext} should be deleted with the retired patch`,
			).toBe(false);
		}
	});

	test("stale split-focus mouse-up patch is retired in favor of upstream's reset", () => {
		// Upstream ghostty-org/ghostty "macos: fix split activation mouse handling"
		// (#15190) renamed the flag to suppressLeftMouseUntilRelease, resets it on
		// every left-mouse-down in the local monitor and on focus loss, and has
		// mouseDown honor it. That covers the stranded-flag case this patch
		// guarded, so a content patch would only fight upstream's new shape.
		expect(
			hasPatchArgument(
				"--label",
				"Stale split-focus mouse-up suppression guard",
			),
		).toBe(false);
		expect(
			hasPatchArgument(
				"--marker",
				"A stale focus-transfer suppression flag means the matching mouse-up never",
			),
		).toBe(false);
		for (const ext of ["old", "new"]) {
			expect(
				existsSync(join(patchesDir, `stale-split-focus-mouseup.${ext}`)),
				`stale-split-focus-mouseup.${ext} should be deleted with the retired patch`,
			).toBe(false);
		}
	});

	test("retired renderer and dock tile rewrites are absent from the patch plan", () => {
		for (const target of [
			"DockTilePlugin.swift",
			"renderer/generic.zig",
			"renderer/Thread.zig",
		]) {
			expect(
				Object.values(patchPlan).some((operation) =>
					operation.target.endsWith(target),
				),
			).toBe(false);
		}
	});

	test("tab title restore invalidation patch remains wired", () => {
		const newBlock = readFileSync(
			join(patchesDir, "terminal-title-override-restorable.new"),
			"utf8",
		);
		expect(
			hasPatchArgument(
				"--label",
				"BaseTerminalController titleOverride restorable-state invalidation",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/terminal-title-override-restorable.old",
			),
		).toBe(true);
		expect(newBlock).toContain("var titleOverride: String?");
		expect(newBlock).toContain("NSApp.invalidateRestorableState()");
		expect(newBlock).toContain("window?.invalidateRestorableState()");
	});

	test("terminal resign-key focus sync is deferred to avoid surface lock reentry", () => {
		const newBlock = readFileSync(
			join(patchesDir, "terminal-resign-key-focus.new"),
			"utf8",
		);
		expect(
			hasPatchArgument(
				"--label",
				"BaseTerminalController windowDidResignKey focus deferral",
			),
		).toBe(true);
		expect(hasPatchArgument("--marker", "self?.syncFocusToSurfaceTree()")).toBe(
			true,
		);
		expect(
			hasPatchArgument("--marker", "DispatchQueue.main.async { [weak self] in"),
		).toBe(false);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/terminal-resign-key-focus.old",
			),
		).toBe(true);
		expect(newBlock).toContain("DispatchQueue.main.async { [weak self] in");
		expect(newBlock).toContain("self?.syncFocusToSurfaceTree()");
	});

	test("terminal resign-key focus sync patch applies, is idempotent, and fails closed on drift", () => {
		const resignKeyPatchBlock = patchCommands([
			"baseterminalcontroller-windowdidresignkey-focus-deferral",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "terminal-resign-key-focus.old"),
			"utf8",
		);

		const oldBaseTerminalController = `import Cocoa

class BaseTerminalController: NSWindowController {
${oldBlock}
    func syncFocusToSurfaceTree() {}
}
`;

		withTempDir((fixtureRoot) => {
			const controllerDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal",
			);
			const controllerPath = join(
				controllerDir,
				"BaseTerminalController.swift",
			);
			mkdirSync(controllerDir, { recursive: true });
			writeFileSync(controllerPath, oldBaseTerminalController, "utf8");

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${resignKeyPatchBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied BaseTerminalController windowDidResignKey focus deferral",
			);
			const patched = readFileSync(controllerPath, "utf8");
			expect(patched).toContain("DispatchQueue.main.async { [weak self] in");
			expect(patched).toContain("self?.syncFocusToSurfaceTree()");

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${resignKeyPatchBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			const drifted = oldBaseTerminalController.replace(
				"        self.syncFocusToSurfaceTree()",
				"        syncFocusToSurfaceTree(reason: .windowDidResignKey)",
			);
			writeFileSync(controllerPath, drifted, "utf8");
			const driftRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${resignKeyPatchBlock}`,
			]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("native window resize bound patch applies, is idempotent, and fails closed on drift", () => {
		const patchBlock = patchCommands([
			"baseterminalcontroller-visible-frame-resize-bound",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "base-terminal-visible-resize.old"),
			"utf8",
		);
		const oldBaseTerminalController = `import Cocoa

class BaseTerminalController: NSWindowController {
${oldBlock}}
`;

		withTempDir((fixtureRoot) => {
			const controllerDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal",
			);
			const controllerPath = join(
				controllerDir,
				"BaseTerminalController.swift",
			);
			mkdirSync(controllerDir, { recursive: true });
			writeFileSync(controllerPath, oldBaseTerminalController, "utf8");
			const command = `set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${patchBlock}`;

			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied BaseTerminalController visible-frame resize bound",
			);
			const patched = readFileSync(controllerPath, "utf8");
			expect(patched).toContain("func windowWillResize(");
			expect(patched).toContain("YENGeometryClamp.sanitize(");
			expect(patched).toContain("screen.visibleFrame.size");

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				controllerPath,
				oldBaseTerminalController.replace(
					"windowFrameDidChange()",
					"windowFrameDidChange(reason: .resize)",
				),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("native fullscreen transition patch remains wired", () => {
		const fullscreenHelper = readFileSync(
			join(repoRoot, "scripts/lib/native-fullscreen-helper.py"),
			"utf8",
		);
		const hiddenTitlebarNewBlock = readFileSync(
			join(patchesDir, "hidden-titlebar-effective-fullscreen.new"),
			"utf8",
		);
		expect(hasPatchText("window.yenIsEffectivelyFullscreen")).toBe(true);
		expect(
			hasPatchText("handleToggleFullscreenNotification(notification)"),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"BaseTerminalController native fullscreen guard",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/base-terminal-effective-fullscreen-resize.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"TerminalController effective fullscreen state",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/terminal-controller-toggle-fullscreen.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--extra-replace",
				"@$PATCHES_DIR/terminal-controller-window-effective-fullscreen.old:::@$PATCHES_DIR/terminal-controller-window-effective-fullscreen.new",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--label",
				"TerminalController resizeWindow fullscreen guard",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/terminal-controller-resize-window-fullscreen.old",
			),
		).toBe(true);
		expect(fullscreenHelper).toContain("ENTER_CANDIDATES");
		expect(fullscreenHelper).toContain("EXIT_CANDIDATES");
		expect(fullscreenHelper).toContain(
			"Native fullscreen transition guard patch already applied to Fullscreen.swift",
		);
		expect(
			hasPatchArgument(
				"--label",
				"HiddenTitlebarTerminalWindow effective fullscreen state",
			),
		).toBe(true);
		expect(hiddenTitlebarNewBlock).toContain(
			"yenIsEffectivelyFullscreen || (terminalController?.fullscreenStyle?.isFullscreen ?? false)",
		);
	});

	test("base terminal native fullscreen guard patch applies, is idempotent, and fails closed on drift", () => {
		const patchBlock = patchCommands([
			"baseterminalcontroller-native-fullscreen-guard",
		]);
		const resizeOld = readFileSync(
			join(patchesDir, "base-terminal-effective-fullscreen-resize.old"),
			"utf8",
		);
		const transparencyOld = readFileSync(
			join(patchesDir, "base-terminal-effective-fullscreen-transparency.old"),
			"utf8",
		);
		const toggleOld = readFileSync(
			join(patchesDir, "base-terminal-fullscreen-toggle-guard.old"),
			"utf8",
		);

		expect(
			hasPatchArgument(
				"--label",
				"BaseTerminalController native fullscreen guard",
			),
		).toBe(true);
		expect(hasPatchArgument("--extra-replace")).toBe(true);

		withTempDir((fixtureRoot) => {
			const controllerPath = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift",
			);
			mkdirSync(join(fixtureRoot, "ghostty/macos/Sources/Features/Terminal"), {
				recursive: true,
			});
			writeFileSync(
				controllerPath,
				["top", resizeOld, transparencyOld, toggleOld, "bottom"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
BASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied BaseTerminalController native fullscreen guard",
			);
			const patched = readFileSync(controllerPath, "utf8");
			expect(patched).toContain(
				"guard !window.yenIsEffectivelyFullscreen else { return }",
			);
			expect(patched).toContain(
				"guard let window, !window.yenIsEffectivelyFullscreen else { return }",
			);
			expect(patched).toContain(
				"logFullscreenToggleRequest(mode: mode, window: window)",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				controllerPath,
				[
					"top",
					resizeOld,
					transparencyOld.replace("styleMask", "window.styleMask"),
					toggleOld,
					"bottom",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("extra-replace anchor not found");
		});
	});

	test("native fullscreen fallback candidates do not keep malformed duplicate blocks", () => {
		const fullscreenHelper = readFileSync(
			join(repoRoot, "scripts/lib/native-fullscreen-helper.py"),
			"utf8",
		);
		expect(fullscreenHelper).not.toContain(
			"and we don't want to double notify.\n    }\n\n        // The titlebar separator shows up erroneously",
		);
		expect(fullscreenHelper).not.toContain(
			"and we don't want to double notify.\n    }\n\n        window.titlebarSeparatorStyle = .automatic",
		);
		expect(fullscreenHelper).toContain("ENTER_CANDIDATES = [");
		expect(fullscreenHelper).toContain("EXIT_CANDIDATES = [");
	});

	test("terminal window effective fullscreen patch applies, is idempotent, and fails closed on drift", () => {
		const terminalWindowPatchBlock = patchCommands([
			"terminalwindow-effective-fullscreen-state",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "terminal-window-effective-fullscreen.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const windowDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal/Window Styles",
			);
			const windowPath = join(windowDir, "TerminalWindow.swift");
			mkdirSync(windowDir, { recursive: true });
			writeFileSync(
				windowPath,
				["final class Window {", oldBlock, "}"].join("\n"),
				"utf8",
			);

			const runScript = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${terminalWindowPatchBlock}`;
			const firstRun = run("bash", ["-lc", runScript]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied TerminalWindow effective fullscreen state",
			);
			expect(readFileSync(windowPath, "utf8")).toContain(
				"if !yenIsEffectivelyFullscreen &&",
			);

			const secondRun = run("bash", ["-lc", runScript]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				windowPath,
				[
					"final class Window {",
					oldBlock.replace("styleMask", "window.styleMask"),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", runScript]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("terminal controller effective fullscreen patch applies, is idempotent, and fails closed on drift", () => {
		const patchBlock = patchCommands([
			"terminalcontroller-effective-fullscreen-state",
			"terminalcontroller-resizewindow-fullscreen-guard",
		]);
		const payloadNames = [
			"terminal-controller-toggle-fullscreen",
			"terminal-controller-parent-effective-fullscreen",
			"terminal-controller-window-not-effective-fullscreen",
			"terminal-controller-window-not-effective-fullscreen",
			"terminal-controller-window-not-effective-fullscreen-continuation",
			"terminal-controller-window-not-effective-fullscreen-basic",
			"terminal-controller-window-effective-fullscreen",
			"terminal-controller-resize-window-fullscreen",
		];
		const oldBlocks = payloadNames.map((name) =>
			readFileSync(join(patchesDir, `${name}.old`), "utf8"),
		);
		const resizeGuardIndex = payloadNames.indexOf(
			"terminal-controller-resize-window-fullscreen",
		);

		withTempDir((fixtureRoot) => {
			const controllerDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal",
			);
			const controllerPath = join(controllerDir, "TerminalController.swift");
			mkdirSync(controllerDir, { recursive: true });
			writeFileSync(
				controllerPath,
				["top", ...oldBlocks, "bottom"].join("\n"),
				"utf8",
			);

			const command = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${patchBlock}`;
			const firstRun = run("bash", ["-lc", command]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied TerminalController effective fullscreen state",
			);
			const patched = readFileSync(controllerPath, "utf8");
			expect(patched).toContain(
				"handleToggleFullscreenNotification(notification)",
			);
			expect(patched).toContain("parent.yenIsEffectivelyFullscreen");
			expect(patched).toContain("window.yenIsEffectivelyFullscreen");
			expect(output(firstRun)).toContain(
				"Applied TerminalController resizeWindow fullscreen guard",
			);
			expect(patched).toContain(
				"!window.yenIsEffectivelyFullscreen,\n              !(fullscreenStyle?.isFullscreen ?? false) else { return false }",
			);

			const secondRun = run("bash", ["-lc", command]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain(
				"TerminalController effective fullscreen state already applied (idempotent skip)",
			);
			expect(output(secondRun)).toContain(
				"TerminalController resizeWindow fullscreen guard already applied (idempotent skip)",
			);

			writeFileSync(
				controllerPath,
				[
					"top",
					...oldBlocks.map((block, index) =>
						index === resizeGuardIndex
							? block.replace("fullscreenStyle?.", "fullscreenMode?.")
							: block,
					),
					"bottom",
				].join("\n"),
				"utf8",
			);
			const resizeDriftRun = run("bash", ["-lc", command]);
			expect(resizeDriftRun.status).toBe(1);
			expect(output(resizeDriftRun)).toContain(
				"TerminalController resizeWindow fullscreen guard patch anchor not found",
			);

			writeFileSync(
				controllerPath,
				[
					"top",
					...oldBlocks.map((block, index) =>
						index === 1
							? block.replace("parent.styleMask", "parent.windowStyleMask")
							: block,
					),
					"bottom",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", command]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("extra-replace anchor not found");
		});
	});

	test("hidden titlebar fullscreen patch applies, is idempotent, and fails closed on drift", () => {
		const hiddenTitlebarPatchBlock = patchCommands([
			"hiddentitlebarterminalwindow-effective-fullscreen-state",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "hidden-titlebar-effective-fullscreen.old"),
			"utf8",
		);

		withTempDir((fixtureRoot) => {
			const windowDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal/Window Styles",
			);
			const windowPath = join(windowDir, "HiddenTitlebarTerminalWindow.swift");
			mkdirSync(windowDir, { recursive: true });
			writeFileSync(
				windowPath,
				["final class Window {", oldBlock, "}"].join("\n"),
				"utf8",
			);

			const runScript = `set -euo pipefail
cd "${fixtureRoot}"
PATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}
PATCHES_DIR="${patchesDir}"
${hiddenTitlebarPatchBlock}`;

			const firstRun = run("bash", ["-lc", runScript]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied HiddenTitlebarTerminalWindow effective fullscreen state",
			);

			const secondRun = run("bash", ["-lc", runScript]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				windowPath,
				[
					"final class Window {",
					oldBlock.replace(
						"fullscreenStyle?.isFullscreen",
						"fullscreenMode?.isFullscreen",
					),
					"}",
				].join("\n"),
				"utf8",
			);
			const driftRun = run("bash", ["-lc", runScript]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("app hook verification checks setup, menu hooks, search names, and cross-file methods", () => {
		withTempDir((root) => {
			const appDir = join(root, "ghostty/macos/Sources/App");
			const otherDir = join(root, "ghostty/macos/Sources/Other");
			mkdirSync(appDir, { recursive: true });
			mkdirSync(otherDir, { recursive: true });
			const appPath = join(appDir, "AppDelegate.swift");
			const menuPath = join(appDir, "AppMenuShortcutController.swift");
			const hooks = [
				"DictationController.shared.setup()",
				"showOnboardingIfNeeded()",
				"TabSidebarController.shared.setup()",
				"LayoutShortcutController.shared.setup()",
				"setupBuildNotificationObserver()",
				"DictationController.backgroundModeActive",
				"NotificationCenter.default.post(name: .yenConfigDidReload, object: nil)",
				"func performYENBindingMenuKeyEquivalent",
			];
			const invoke = () =>
				run(
					"bash",
					[
						"-c",
						`set -euo pipefail\nREPO_ROOT=${shellQuote(repoRoot)}\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nverify_overlay_app_hooks\nprintf 'Hook verification passed\\n'`,
					],
					{ cwd: root },
				);
			const absent = invoke();
			expect(absent.status).toBe(1);
			expect(output(absent)).toContain("AppDelegate.swift not found");
			writeFileSync(menuPath, "menuItemsByShortcut\nstruct MenuShortcutKey\n");
			for (const hook of hooks) {
				writeFileSync(
					appPath,
					hooks.filter((value) => value !== hook).join("\n"),
				);
				const missing = invoke();
				expect(missing.status).toBe(1);
				expect(output(missing)).toContain(`missing required hook: ${hook}`);
			}
			writeFileSync(appPath, hooks.join("\n"));
			for (const hook of ["menuItemsByShortcut", "struct MenuShortcutKey"]) {
				writeFileSync(menuPath, hook);
				const missing = invoke();
				expect(missing.status).toBe(1);
				expect(output(missing)).toContain(
					"AppMenuShortcutController overlay missing required hook",
				);
			}
			writeFileSync(menuPath, "menuItemsByShortcut\nstruct MenuShortcutKey\n");
			for (const name of ["search:next", "search:previous"]) {
				writeFileSync(appPath, `${hooks.join("\n")}\n"${name}"`);
				const stale = invoke();
				expect(stale.status).toBe(1);
				expect(output(stale)).toContain("must use navigate_search:*");
			}
			writeFileSync(appPath, hooks.join("\n"));
			writeFileSync(
				join(otherDir, "Caller.swift"),
				"appDelegate.newUpstreamMethod()\n",
			);
			const missingMethod = invoke();
			expect(missingMethod.status).toBe(1);
			expect(output(missingMethod)).toContain(
				"missing method called outside AppDelegate: newUpstreamMethod",
			);
			writeFileSync(
				join(appDir, "AppDelegate+Support.swift"),
				"func newUpstreamMethod() {}\n",
			);
			const valid = invoke();
			expect(valid.status, output(valid)).toBe(0);
			expect(output(valid)).toContain("Hook verification passed");
		});
	});

	test("tab title restore invalidation patch applies, is idempotent, and fails closed on drift", () => {
		const titleOverridePatchBlock = patchCommands([
			"baseterminalcontroller-titleoverride-restorable-state-invalidation",
		]);
		const oldBlock = readFileSync(
			join(patchesDir, "terminal-title-override-restorable.old"),
			"utf8",
		);

		const oldBaseTerminalController = `import Cocoa

class BaseTerminalController: NSWindowController {
${oldBlock}

    /// The last computed title
    private var lastComputedTitle: String = "YEN"

    private func applyTitleToWindow() {}
}
`;

		withTempDir((fixtureRoot) => {
			const controllerDir = join(
				fixtureRoot,
				"ghostty/macos/Sources/Features/Terminal",
			);
			const controllerPath = join(
				controllerDir,
				"BaseTerminalController.swift",
			);
			mkdirSync(controllerDir, { recursive: true });
			writeFileSync(controllerPath, oldBaseTerminalController, "utf8");

			const firstRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${titleOverridePatchBlock}`,
			]);
			expect(firstRun.status).toBe(0);
			expect(output(firstRun)).toContain(
				"Applied BaseTerminalController titleOverride restorable-state invalidation",
			);
			const patched = readFileSync(controllerPath, "utf8");
			expect(patched).toContain("NSApp.invalidateRestorableState()");
			expect(patched).toContain("window?.invalidateRestorableState()");

			const secondRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${titleOverridePatchBlock}`,
			]);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			const drifted = oldBaseTerminalController.replace(
				"didSet { applyTitleToWindow() }",
				"didSet { applyWindowTitle() }",
			);
			writeFileSync(controllerPath, drifted, "utf8");
			const driftRun = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nPATCH_FILE_UTIL="${patchFilePath}"\n${patchFileFn}\nPATCHES_DIR="${patchesDir}"\nBASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"\n${titleOverridePatchBlock}`,
			]);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("write_screen_file keybind remap patches remain declared", () => {
		expect(hasPatchText("write_screen_file copy remap")).toBe(true);
		expect(hasPatchText("write_screen_file paste remap")).toBe(true);
		expect(hasPatchText("write_screen_file open remap")).toBe(true);
		// Verify remapped to 'u' key (away from 'j' which collides with scratchpad)
		expect(
			hasPatchText(
				".{ .key = .{ .unicode = 'u' }, .mods = .{ .shift = true, .ctrl = true, .super = true } },",
			),
		).toBe(true);
		expect(
			hasPatchText(
				".{ .key = .{ .unicode = 'u' }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true }) },",
			),
		).toBe(true);
		expect(
			hasPatchText(
				".{ .key = .{ .unicode = 'u' }, .mods = inputpkg.ctrlOrSuper(.{ .shift = true, .alt = true }) },",
			),
		).toBe(true);
	});

	test("Quick Terminal keeps vendor-native sizing and animation geometry", () => {
		const quickTerminalOverlayRoot = join(
			repoRoot,
			"yen-terminal/overlays/macos/Sources/Features/QuickTerminal",
		);
		expect(hasPatchText("Quick Terminal shared panel motion")).toBe(true);
		expect(hasPatchArgument("--mode", "exact")).toBe(true);
		expect(
			hasPatchArgument(
				"--old-block",
				"@$PATCHES_DIR/quick-terminal-shared-motion-in.old",
			),
		).toBe(true);
		expect(
			hasPatchArgument(
				"--extra-replace",
				"@$PATCHES_DIR/quick-terminal-shared-motion-out.old:::@$PATCHES_DIR/quick-terminal-shared-motion-out.new",
			),
		).toBe(true);
		expect(
			existsSync(join(quickTerminalOverlayRoot, "QuickTerminalPosition.swift")),
		).toBe(false);
		expect(
			existsSync(
				join(quickTerminalOverlayRoot, "QuickTerminalScreenStateCache.swift"),
			),
		).toBe(false);
		const windowOverlay = readFileSync(
			join(quickTerminalOverlayRoot, "QuickTerminalWindow.swift"),
			"utf8",
		);
		expect(windowOverlay).not.toContain("prepareNextFrameAnchor");
		expect(windowOverlay).not.toContain("override func orderOut");
		expect(windowOverlay).toContain("styleMask.remove(.titled)");
		expect(windowOverlay).toContain("applyTerminalFacingCorners");

		const sharedMotion = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/SlidingPanel/SlidingUtilityPanel.swift",
			),
			"utf8",
		);
		expect(sharedMotion).toContain("static func transition(");
		expect(sharedMotion).not.toContain("static func runSlide(");
		expect(
			sharedMotion.match(/NSAnimationContext\.runAnimationGroup/g),
		).toHaveLength(1);
		// Single ease-in timing for BOTH enter and exit (vendor Quick Terminal).
		expect(sharedMotion).toContain("case .entering, .exiting:");
		expect(sharedMotion).toContain("CAMediaTimingFunction(name: .easeIn)");
		expect(sharedMotion).not.toContain("easeOut");
		expect(sharedMotion).not.toContain("easeInEaseOut");
		expect(sharedMotion).toContain(
			"reduceMotion ? 0 : max(0, configuredDuration)",
		);
		expect(sharedMotion).toContain("static func currentAnimationDuration(");
		expect(sharedMotion).toContain(".quickTerminalAnimationDuration");
		expect(sharedMotion).toContain(
			"defaultAnimationDuration: TimeInterval = 0.2",
		);
		// Panels no longer move their window frames; the frame-parking helper is gone.
		expect(sharedMotion).not.toContain("prepareForSlideIn");

		// One edge-reveal for every in-window surface: a clip that parks content one
		// full extent past its edge at alpha 0 and slides it inside the shared envelope.
		const edgeReveal = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/SlidingPanel/EdgeRevealView.swift",
			),
			"utf8",
		);
		expect(edgeReveal).toContain("final class EdgeRevealView: NSView");
		expect(edgeReveal).toContain("layer?.masksToBounds = true");
		expect(edgeReveal).toContain("override func makeBackingLayer() -> CALayer");
		expect(edgeReveal).toContain(
			"var parkedOffset: CGFloat { edge == .trailing ? extent : -extent }",
		);
		expect(edgeReveal).toContain("SlidingUtilityPanel.transition(");
		expect(edgeReveal).not.toContain("NSAnimationContext");
		expect(edgeReveal).toContain(
			"self.animator().alphaValue = entering ? 1 : 0",
		);
		expect(edgeReveal).toContain("root.animator().layoutSubtreeIfNeeded()");
		// Rest frames are placed without animation, flush inside the window.
		expect(edgeReveal).toContain("panel.setFrame(frame, display: true)");
		expect(edgeReveal).toContain("window.contentLayoutRect");

		const controllerOverlaySources = [
			"Features/Terminal/TerminalViewContainer.swift",
			"Features/TabSidebar/TabSidebarController.swift",
			"Features/Scratchpad/ScratchpadController.swift",
		].map((relativePath) =>
			readFileSync(
				join(repoRoot, "yen-terminal/overlays/macos/Sources", relativePath),
				"utf8",
			),
		);
		const trayControllersJoined = controllerOverlaySources.join("\n");
		// Controllers must not own a second animation context; only SlidingUtilityPanel does.
		expect(trayControllersJoined).not.toContain(
			"NSAnimationContext.runAnimationGroup",
		);
		expect(trayControllersJoined).not.toContain(
			"NSAnimationContext.beginGrouping",
		);
		expect(trayControllersJoined).not.toContain("context.timingFunction");
		expect(controllerOverlaySources[1]).toContain(
			"SlidingUtilityPanel.currentAnimationDuration()",
		);
		expect(controllerOverlaySources[2]).toContain(
			"SlidingUtilityPanel.currentAnimationDuration()",
		);
		const gitDrawerControllerSource = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/GitDrawer/GitDrawerController.swift",
			),
			"utf8",
		);
		expect(gitDrawerControllerSource).toContain(
			"SlidingUtilityPanel.currentAnimationDuration()",
		);
		// Every tray surface enters and exits through the shared edge reveal.
		expect(controllerOverlaySources[0]).toContain(
			"clip.slide(.entering, duration: animationDuration, layoutRoot: self)",
		);
		expect(controllerOverlaySources[0]).toContain(
			"clip.slide(.exiting, duration: animationDuration, layoutRoot: self",
		);
		expect(controllerOverlaySources[0]).toContain(
			"EdgeRevealView(edge: .bottom)",
		);
		// No surface animates its own panel frame any more.
		expect(trayControllersJoined).not.toContain("panel.animator()");
		expect(trayControllersJoined).not.toContain("prepareForSlideIn");
		// Git Drawer must always park then run the shared enter envelope — including
		// Reduce Motion (duration 0). No second instant-present path.
		expect(controllerOverlaySources[0]).not.toContain(
			"let animating = animationDuration > 0",
		);
		expect(controllerOverlaySources[0]).not.toMatch(
			/animating\s*\?\s*-height\s*:\s*0/,
		);
		// Park behind the edge at alpha 0 before the enter slide (vendor setInitial).
		expect(controllerOverlaySources[0]).toMatch(
			/clip\.park\(layoutRoot: self\)[\s\S]*?clip\.slide\(\.entering/,
		);
		// Exit teardown must be synchronous in the completion (no Task hop).
		expect(controllerOverlaySources[0]).toMatch(
			/completion:\s*\{\s*\[weak self\] in\s*guard let self/,
		);
		expect(controllerOverlaySources[0]).toContain("self.teardownGitDrawer()");
		// Tab Sidebar reveals from the window's left edge, Scratchpad from its right:
		// rest frame, park, order front, then slide (vendor setInitial -> setFinal).
		expect(controllerOverlaySources[1]).toContain(
			"EdgeRevealView(edge: .leading)",
		);
		expect(controllerOverlaySources[1]).toMatch(
			/positionPanel\(panel, relativeTo: terminalWindow\)\s*revealView\?\.park\(\)\s*panel\.orderFront\(nil\)\s*revealView\?\.slide\(\.entering/,
		);
		expect(controllerOverlaySources[1]).toContain(
			"reveal.slide(\n            .exiting",
		);
		expect(controllerOverlaySources[2]).toContain(
			"EdgeRevealView(edge: .trailing)",
		);
		expect(controllerOverlaySources[2]).toMatch(
			/positionPanel\(panel, relativeTo: terminalWindow\)\s*reveal\.park\(\)\s*panel\.orderFront\(nil\)\s*reveal\.slide\(\s*\.entering/,
		);
		expect(controllerOverlaySources[2]).toContain(
			"reveal.slide(\n            .exiting",
		);
		// Scratchpad + Tab Sidebar must complete exit orderOut synchronously (vendor QT
		// pattern) and focus Scratchpad only after the enter envelope completes.
		expect(controllerOverlaySources[1]).not.toMatch(
			/completion:\s*\{\s*\[weak self\] in\s*Task\s*\{\s*@MainActor/,
		);
		expect(controllerOverlaySources[2]).not.toMatch(
			/completion:\s*\{\s*\[weak self\] in\s*Task\s*\{\s*@MainActor/,
		);
		// Scratchpad must not schedule focus on the next runloop before enter completes.
		expect(controllerOverlaySources[2]).not.toMatch(
			/DispatchQueue\.main\.async\s*\{\s*\[weak self\] in\s*self\?\.focusTextEditor\(\)/,
		);
		// registerTextView runs from makeNSView inside the first forced layout; focusing
		// there re-enters that layout and AttributeGraph aborts the app.
		expect(controllerOverlaySources[2]).toMatch(
			/func registerTextView\(_ textView: NSTextView\) \{\s*self\.textView = textView\s*\}/,
		);
		// Enter completion owns focus (visible guard + focusTextEditor).
		expect(controllerOverlaySources[2]).toMatch(
			/\.entering[\s\S]*?completion:\s*\{\s*\[weak self\] in\s*guard let self, self\.visible else \{ return \}\s*self\.focusTextEditor\(\)/,
		);
		// Exit completion owns orderOut synchronously.
		expect(controllerOverlaySources[2]).toMatch(
			/\.exiting[\s\S]*?completion:\s*\{\s*\[weak self\] in\s*guard let self else \{ return \}\s*guard !self\.visible else \{ return \}\s*panel\.orderOut\(nil\)/,
		);
		expect(controllerOverlaySources[1]).toMatch(
			/\.exiting[\s\S]*?completion:\s*\{\s*\[weak self\] in\s*guard let self else \{ return \}\s*guard self\.visible == false else \{ return \}\s*self\.panel\?\.orderOut\(nil\)/,
		);
		// Both panels rest flush inside the window through the shared placement.
		const scratchpadAnchoringSource = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/Scratchpad/ScratchpadAnchoring.swift",
			),
			"utf8",
		);
		expect(scratchpadAnchoringSource).toContain(
			"EdgeRevealPanelGeometry.place(",
		);
		expect(controllerOverlaySources[1]).toContain(
			"EdgeRevealPanelGeometry.place(",
		);

		// A window shadow is computed once and would outline the full panel before
		// the sliding content arrives, so the fixed-frame panels carry none.
		for (const relativePath of [
			"Features/Scratchpad/ScratchpadPanel.swift",
			"Features/TabSidebar/TabSidebarPanel.swift",
		]) {
			const panelSource = readFileSync(
				join(repoRoot, "yen-terminal/overlays/macos/Sources", relativePath),
				"utf8",
			);
			expect(panelSource).toMatch(/hasShadow = false/);
		}

		const floatingPanelSources = [
			"Features/Scratchpad/ScratchpadPanel.swift",
			"Features/TabSidebar/TabSidebarPanel.swift",
			"Features/QuickTerminal/QuickTerminalWindow.swift",
		].map((relativePath) =>
			readFileSync(
				join(repoRoot, "yen-terminal/overlays/macos/Sources", relativePath),
				"utf8",
			),
		);
		for (const panelSource of floatingPanelSources) {
			expect(panelSource).toContain("animationBehavior = .none");
		}

		// Quick Terminal motion patches must use the shared runner + reduce-motion helper
		// with the vendor configured duration (not a hard-coded 0.2).
		const quickTerminalMotionIn = readFileSync(
			join(patchesDir, "quick-terminal-shared-motion-in.new"),
			"utf8",
		);
		const quickTerminalMotionOut = readFileSync(
			join(patchesDir, "quick-terminal-shared-motion-out.new"),
			"utf8",
		);
		for (const body of [quickTerminalMotionIn, quickTerminalMotionOut]) {
			expect(body).toContain("SlidingUtilityPanel.transition(");
			expect(body).toContain("SlidingUtilityPanel.animationDuration(");
			expect(body).toContain(
				"configuredDuration: derivedConfig.quickTerminalAnimationDuration",
			);
			expect(body).not.toContain("NSAnimationContext.runAnimationGroup");
		}
		expect(quickTerminalMotionIn).toContain(
			"SlidingUtilityPanel.transition(\n            .entering",
		);
		expect(quickTerminalMotionOut).toContain(
			"SlidingUtilityPanel.transition(\n            .exiting",
		);

		withTempDir((fixtureRoot) => {
			const controllerPath = join(fixtureRoot, "QuickTerminalController.swift");
			const motionInOld = readFileSync(
				join(patchesDir, "quick-terminal-shared-motion-in.old"),
				"utf8",
			);
			const motionOutOld = readFileSync(
				join(patchesDir, "quick-terminal-shared-motion-out.old"),
				"utf8",
			);
			writeFileSync(
				controllerPath,
				[
					"final class QuickTerminalController {",
					motionInOld,
					motionOutOld,
					"}",
				].join("\n"),
				"utf8",
			);

			const patchArgs = [
				"--file",
				controllerPath,
				"--label",
				"Quick Terminal shared panel motion",
				"--mode",
				"exact",
				"--marker-all",
				"            .entering,",
				"--marker-all",
				"            .exiting,",
				"--old-block",
				patchPath("quick-terminal-shared-motion-in", "old"),
				"--new-block",
				patchPath("quick-terminal-shared-motion-in", "new"),
				"--extra-replace",
				`${patchPath("quick-terminal-shared-motion-out", "old")}:::${patchPath("quick-terminal-shared-motion-out", "new")}`,
			];
			const firstRun = runPatch(patchArgs);
			expect(firstRun.status, output(firstRun)).toBe(0);
			const patchedController = readFileSync(controllerPath, "utf8");
			expect(patchedController).not.toContain(
				"NSAnimationContext.runAnimationGroup",
			);
			expect(patchedController).toContain(
				"SlidingUtilityPanel.transition(\n            .entering",
			);
			expect(patchedController).toContain(
				"SlidingUtilityPanel.transition(\n            .exiting",
			);

			const secondRun = runPatch(patchArgs);
			expect(secondRun.status).toBe(0);
			expect(output(secondRun)).toContain("already applied (idempotent skip)");

			writeFileSync(
				controllerPath,
				patchedController.replace(
					"            .entering,",
					"            .enteringDrifted,",
				),
				"utf8",
			);
			const driftRun = runPatch(patchArgs);
			expect(driftRun.status).toBe(1);
			expect(output(driftRun)).toContain("patch anchor not found");
		});
	});

	test("Shift+Enter verifier rejects missing, incorrect, and out-of-scope payloads", () => {
		withTempDir((root) => {
			const config = join(root, "Config.zig");
			const key =
				".{ .key = .{ .physical = .enter }, .mods = .{ .shift = true } },";
			const payload = String.raw`.{ .text = "\\x0d" },`;
			const invoke = () =>
				run("bash", [
					"-c",
					`set -euo pipefail\nCONFIG_ZIG=${shellQuote(config)}\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nverify_overlay_shift_enter\nprintf 'Shift+Enter verified\\n'`,
				]);
			for (const content of [
				`${key}\n${payload}`,
				`// Shift+Enter fix\n${key}`,
				`// Shift+Enter fix\n${payload}`,
				`// Shift+Enter fix\n${key}\n.{ .text = "wrong" },`,
				`// Shift+Enter fix\n${"// gap\n".repeat(40)}${key}\n${payload}`,
			]) {
				writeFileSync(config, content);
				const invalid = invoke();
				expect(invalid.status).toBe(1);
				expect(output(invalid)).toContain(
					"Shift+Enter keybind payload not found",
				);
			}
			writeFileSync(config, `// Shift+Enter fix\n${key}\n${payload}`);
			const valid = invoke();
			expect(valid.status, output(valid)).toBe(0);
			expect(output(valid)).toContain("Shift+Enter verified");
		});
	});

	test("retired-file data removes each group without deleting neighboring files", () => {
		withTempDir((root) => {
			const rows = readFileSync(
				join(repoRoot, "scripts/lib/overlay-data/retired-paths.tsv"),
				"utf8",
			)
				.trim()
				.split("\n")
				.map((row) => {
					const [group, path] = row.split("\t");
					if (!group || !path)
						throw new Error("Invalid retired-file fixture row");
					return { group, path };
				});
			expect(rows.length).toBe(28);
			const calledGroups = overlayPhaseNames.flatMap((name) =>
				[
					...phaseSource(name).matchAll(
						/^remove_overlay_retired_files ([a-z-]+)$/gm,
					),
				].map((match) => match[1]),
			);
			expect(calledGroups.sort()).toEqual(
				[...new Set(rows.map((row) => row.group))].sort(),
			);
			for (const { path } of rows) {
				mkdirSync(dirname(join(root, path)), { recursive: true });
				writeFileSync(join(root, path), "retired");
				writeFileSync(join(root, `${path}.keep`), "keep");
			}
			for (const group of new Set(rows.map((row) => row.group))) {
				for (let pass = 0; pass < 2; pass++) {
					const result = run(
						"bash",
						[
							"-c",
							`set -euo pipefail\nREPO_ROOT=${shellQuote(repoRoot)}\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-files.sh"))}\nremove_overlay_retired_files ${shellQuote(group)}`,
						],
						{ cwd: root },
					);
					expect(result.status, output(result)).toBe(0);
					expect(output(result)).toContain("Retired files: checked");
				}
			}
			for (const { path } of rows) {
				expect(existsSync(join(root, path))).toBe(false);
				expect(readFileSync(join(root, `${path}.keep`), "utf8")).toBe("keep");
			}
		});
	});

	test("overlay data readers reject missing, empty, and malformed declarations", () => {
		withTempDir((root) => {
			const manifest = join(root, "manifest");
			const candidates = join(root, "candidates");
			writeFileSync(candidates, "target\0");
			writeFileSync(join(root, "target"), "fixture");
			const invoke = (helper: string, call: string) =>
				run(
					"bash",
					[
						"-c",
						`set -euo pipefail\nREPO_ROOT=${shellQuote(repoRoot)}\nsource ${shellQuote(join(repoRoot, `scripts/lib/${helper}.sh`))}\n${call}`,
					],
					{ cwd: root },
				);
			for (const value of [null, "", "\n"]) {
				if (value !== null) writeFileSync(manifest, value);
				for (const [helper, call] of [
					[
						"overlay-branding",
						`rewrite_overlay_url_files fixture ${shellQuote(candidates)} ${shellQuote(manifest)}`,
					],
					[
						"overlay-verification",
						`verify_overlay_required_hooks target ${shellQuote(manifest)} fixture`,
					],
					[
						"overlay-files",
						`remove_overlay_retired_files fixture ${shellQuote(manifest)}`,
					],
				] as const) {
					expect(invoke(helper, call).status).toBe(1);
				}
			}
			writeFileSync(manifest, "fixture	../outside\n");
			const unsafe = invoke(
				"overlay-files",
				`remove_overlay_retired_files fixture ${shellQuote(manifest)}`,
			);
			expect(unsafe.status).toBe(1);
			expect(output(unsafe)).toContain("Invalid retired path");
			writeFileSync(manifest, "not a sed substitution\n");
			const malformed = invoke(
				"overlay-branding",
				`rewrite_overlay_url_files fixture ${shellQuote(candidates)} ${shellQuote(manifest)}`,
			);
			expect(malformed.status).toBe(1);
			expect(output(malformed)).toContain("Invalid URL rewrite rule");
		});
	});

	test("native geometry guard rejects retired sizing code in every source", () => {
		withTempDir((root) => {
			const folder = join(root, "ghostty/macos/Sources/Features/QuickTerminal");
			mkdirSync(folder, { recursive: true });
			const files = [
				"QuickTerminalPosition.swift",
				"QuickTerminalScreenStateCache.swift",
				"QuickTerminalController.swift",
			];
			for (const file of files)
				writeFileSync(join(folder, file), "vendor geometry\n");
			const invoke = () =>
				run(
					"bash",
					[
						"-c",
						`set -euo pipefail\nsource ${shellQuote(join(repoRoot, "scripts/lib/overlay-verification.sh"))}\nverify_overlay_native_geometry\nprintf 'Geometry verified\\n'`,
					],
					{ cwd: root },
				);
			const valid = invoke();
			expect(valid.status, output(valid)).toBe(0);
			expect(output(valid)).toContain("Geometry verified");
			for (const file of files) {
				rmSync(join(folder, file));
				const missing = invoke();
				expect(missing.status).toBe(1);
				expect(output(missing)).toContain(
					"Quick Terminal geometry source missing",
				);
				for (const marker of [
					"windowAnchoredFrameSize",
					"frameBounds(for:",
					"hasFrameAnchor",
					"YENGeometryClamp.sanitize",
				]) {
					writeFileSync(join(folder, file), marker);
					const drift = invoke();
					expect(drift.status).toBe(1);
					expect(output(drift)).toContain(
						"Retired YEN Quick Terminal geometry override remains",
					);
				}
				writeFileSync(join(folder, file), "vendor geometry\n");
			}
		});
	});

	test("rename-count guard fails on drift but allows idempotent rerun state", () => {
		const guardBlock = `source ${shellQuote(join(repoRoot, "scripts/lib/overlay-rename-preflight.sh"))}\nverify_overlay_renames`;

		withTempDir((fixtureRoot) => {
			const failing = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nFILES_RENAMED=1\n${guardBlock}`,
			]);
			expect(failing.status).toBe(1);
			expect(output(failing)).toContain("renamed too few paths");

			mkdirSync(join(fixtureRoot, "src/cli"), { recursive: true });
			writeFileSync(join(fixtureRoot, "src/cli/yen.zig"), "", "utf8");
			mkdirSync(join(fixtureRoot, "src"), { recursive: true });
			writeFileSync(join(fixtureRoot, "src/main_yen.zig"), "", "utf8");
			mkdirSync(join(fixtureRoot, "src/terminfo"), { recursive: true });
			writeFileSync(join(fixtureRoot, "src/terminfo/yen.zig"), "", "utf8");
			mkdirSync(join(fixtureRoot, "include/yen"), { recursive: true });
			writeFileSync(join(fixtureRoot, "include/yen.h"), "", "utf8");
			mkdirSync(join(fixtureRoot, "macos/YEN.xcodeproj"), { recursive: true });
			writeFileSync(join(fixtureRoot, "macos/YEN-Info.plist"), "", "utf8");
			writeFileSync(join(fixtureRoot, "macos/YEN.entitlements"), "", "utf8");
			writeFileSync(
				join(fixtureRoot, "macos/YENDebug.entitlements"),
				"",
				"utf8",
			);
			writeFileSync(
				join(fixtureRoot, "macos/YENReleaseLocal.entitlements"),
				"",
				"utf8",
			);
			mkdirSync(join(fixtureRoot, "macos/Sources/Features/Custom App Icon"), {
				recursive: true,
			});
			writeFileSync(
				join(
					fixtureRoot,
					"macos/Sources/Features/Custom App Icon/ColorizedYENIcon.swift",
				),
				"",
				"utf8",
			);

			const idempotent = run("bash", [
				"-lc",
				`set -euo pipefail\ncd "${fixtureRoot}"\nFILES_RENAMED=0\n${overlayTallyFns}\n${guardBlock}`,
			]);
			expect(idempotent.status).toBe(0);
			expect(output(idempotent)).toContain(
				"already applied (idempotent/converged state)",
			);
		});
	});

	const plistTest = existsSync("/usr/libexec/PlistBuddy") ? test : test.skip;
	plistTest(
		"plist_upsert string values preserve quotes and backslashes",
		() => {
			const helpers = `source ${shellQuote(join(repoRoot, "scripts/lib/overlay-plist.sh"))}`;

			withTempDir((fixtureRoot) => {
				const helpersPath = join(fixtureRoot, "plist-helpers.sh");
				const plistPath = join(fixtureRoot, "Info.plist");
				writeFileSync(helpersPath, helpers, "utf8");
				writeFileSync(
					plistPath,
					[
						'<?xml version="1.0" encoding="UTF-8"?>',
						'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
						'<plist version="1.0"><dict></dict></plist>',
					].join("\n"),
					"utf8",
				);

				const value = 'value with "quotes" and \\ slash';
				const escaped = value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
				const res = run("bash", [
					"-lc",
					`set -euo pipefail
source "${helpersPath}"
plist_upsert "${plistPath}" "TestString" "string" "initial value"
plist_upsert "${plistPath}" "TestString" "string" "${escaped}"
/usr/libexec/PlistBuddy -c "Print :TestString" "${plistPath}"`,
				]);

				expect(res.status).toBe(0);
				expect(res.stdout.trim()).toBe(value);
			});
		},
	);
});

// ---------------------------------------------------------------------------
// Upstream-relocation fail-closed coverage.
//
// A patch whose target file moved is the failure mode an upstream API-boundary
// refactor produces: apply-overlays.sh used to skip it and exit 0, so a vendor
// bump went green while silently dropping the patch. These tests hold the
// wrapper, the preflight manifest, and the vendor-side gates fail-closed.
// ---------------------------------------------------------------------------
describe("upstream relocation guardrails", () => {
	const ghosttyVendorPath = join(repoRoot, "scripts/10-update-ghostty.sh");

	function overlaySource(): string {
		return readFileSync(applyOverlaysPath, "utf8");
	}

	function declaredPatchTargets(): Set<string> {
		const targets = new Set<string>();
		const operations = overlayPhaseNames.flatMap((name) => {
			const source = phaseSource(name);
			expect(source).not.toMatch(/^\s*patch_file /m);
			return [...source.matchAll(/^\s*apply_overlay_patch ([a-z0-9-]+)$/gm)];
		});
		expect(operations.map((match) => match[1]).sort()).toEqual(
			Object.keys(patchPlan).sort(),
		);
		for (const match of operations) {
			const operation = patchPlan[match[1] ?? ""];
			if (!operation) throw new Error(`Unknown patch operation: ${match[1]}`);
			targets.add(operation.target);
		}
		return targets;
	}

	function preflightManifest(): string[] {
		return readFileSync(patchManifestPath, "utf8")
			.split("\n")
			.filter((line) => line.length > 0 && !line.startsWith("#"));
	}

	test("shared runtime counts applied and idempotent patch verdicts", () => {
		withTempDir((root) => {
			const target = join(root, "target.swift");
			writeFileSync(target, "before\n");
			const invocation = `patch_file ${shellQuote(target)} --label fixture --mode exact --marker after --old-block before --new-block after`;
			const result = run("bash", [
				"-c",
				`set -euo pipefail
PATCH_FILE_UTIL=${shellQuote(patchFilePath)}
${patchFileFn}
${invocation}
${invocation}
printf 'COUNTS applied=%s skipped=%s\\n' "$OVERLAY_APPLIED" "$OVERLAY_SKIPPED"`,
			]);
			expect(result.status, output(result)).toBe(0);
			expect(readFileSync(target, "utf8")).toBe("after\n");
			expect(output(result)).toContain("COUNTS applied=1 skipped=1");
		});
	});

	test("patch_file fails closed when its target is missing", () => {
		const dir = mkdtempSync(join(tmpdir(), "yen-patch-missing-"));
		const res = run("bash", [
			"-lc",
			`set -euo pipefail
PATCH_FILE_UTIL="${patchFilePath}"
${patchFileFn}
patch_file "${join(dir, "does-not-exist.swift")}" --label "x" --mode exact --marker m --old-block a --new-block b
echo "REACHED_END"`,
		]);

		expect(res.status).not.toBe(0);
		expect(res.stdout).not.toContain("REACHED_END");
		expect(`${res.stdout}${res.stderr}`).toContain("patch target missing");
		rmSync(dir, { recursive: true, force: true });
	});

	test("patch_file --optional still skips a missing target", () => {
		const dir = mkdtempSync(join(tmpdir(), "yen-patch-optional-"));
		const res = run("bash", [
			"-lc",
			`set -euo pipefail
PATCH_FILE_UTIL="${patchFilePath}"
${patchFileFn}
patch_file "${join(dir, "does-not-exist.swift")}" --optional --label "x" --mode exact --marker m --old-block a --new-block b
echo "REACHED_END"`,
		]);

		expect(res.status).toBe(0);
		expect(res.stdout).toContain("REACHED_END");
		rmSync(dir, { recursive: true, force: true });
	});

	test("overlay orchestration invokes the shared runtime and target preflight", () => {
		const source = overlaySource();
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-plist.sh"',
		);
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-rename-preflight.sh"',
		);
		expect(phaseSource("02-renames.sh")).toContain("verify_overlay_renames\n");
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-patch-runtime.sh"',
		);
		expect(source).toContain(
			'source "$REPO_ROOT/scripts/lib/overlay-patch-preflight.sh"',
		);
		expect(phaseSource("06-copy.sh")).toContain(
			'verify_overlay_patch_targets "$REPO_ROOT/scripts/lib/overlay-patch-targets.txt"',
		);
	});

	test("preflight manifest covers every patch_file target", () => {
		const manifest = preflightManifest();
		const targets = declaredPatchTargets();

		expect(targets.size).toBeGreaterThan(15);
		const uncovered = [...targets].filter((t) => !manifest.includes(t));
		expect(uncovered).toEqual([]);
	});

	test("preflight manifest has no stale entries", () => {
		const manifest = preflightManifest();
		const targets = declaredPatchTargets();
		const stale = manifest.filter((entry) => !targets.has(entry));
		expect(stale).toEqual([]);
	});

	test("preflight manifest has no duplicates", () => {
		const manifest = preflightManifest();
		expect(manifest.length).toBe(new Set(manifest).size);
	});

	test("preflight reports every missing target and accepts a complete fixture", () => {
		withTempDir((root) => {
			const manifest = join(root, "targets.txt");
			writeFileSync(manifest, "first.swift\nsecond file.swift\n");
			const script = `set -euo pipefail\nsource ${shellQuote(patchPreflightPath)}\nverify_overlay_patch_targets ${shellQuote(manifest)}`;
			const missing = run("bash", ["-c", script], { cwd: root });
			expect(missing.status).toBe(1);
			expect(output(missing)).toContain("first.swift");
			expect(output(missing)).toContain("second file.swift");
			expect(output(missing)).toContain(
				"2 of 2 patch targets could not be resolved",
			);
			writeFileSync(join(root, "first.swift"), "fixture");
			writeFileSync(join(root, "second file.swift"), "fixture");
			const complete = run("bash", ["-c", script], { cwd: root });
			expect(complete.status, output(complete)).toBe(0);
			expect(output(complete)).toContain("verified 2 targets");
		});
	});

	test("preflight rejects missing, empty, comment-only, and duplicate manifests", () => {
		withTempDir((root) => {
			const manifest = join(root, "targets.txt");
			const script = `set -euo pipefail\nsource ${shellQuote(patchPreflightPath)}\nverify_overlay_patch_targets ${shellQuote(manifest)}`;
			expect(run("bash", ["-c", script], { cwd: root }).status).toBe(1);
			writeFileSync(join(root, "file.swift"), "fixture");
			for (const [contents, reason] of [
				["", "manifest missing or empty"],
				["# no targets\n", "manifest contains no targets"],
				["file.swift\nfile.swift\n", "duplicate patch target: file.swift"],
			] as const) {
				writeFileSync(manifest, contents);
				const rejected = run("bash", ["-c", script], { cwd: root });
				expect(rejected.status).toBe(1);
				expect(output(rejected)).toContain(reason);
			}
		});
	});

	test("patch plan rejects invalid declarations and unknown operations", () => {
		withTempDir((root) => {
			const planPath = join(root, "plan.json");
			const invoke = (operation = "fixture") =>
				run(
					"python3",
					[
						join(repoRoot, "scripts/lib/overlay-patch-plan.py"),
						"--plan",
						planPath,
						"--patches-dir",
						patchesDir,
						"--patch-tool",
						patchFilePath,
						operation,
					],
					{ cwd: root },
				);
			expect(invoke().status).toBe(1);
			for (const [contents, reason] of [
				["{}", "at least one operation"],
				["[]", "at least one operation"],
				['{"fixture":{},"fixture":{}}', "duplicate patch-plan key"],
				[
					'{"fixture":{"target":"file.swift","arguments":[]}}',
					"missing patch arguments",
				],
				[
					'{"fixture":{"target":"file.swift","arguments":[1]}}',
					"non-string patch argument",
				],
				[
					'{"fixture":{"target":"","arguments":["--mode","exact"]}}',
					"missing patch target",
				],
			] as const) {
				writeFileSync(planPath, contents);
				const result = invoke();
				expect(result.status).toBe(1);
				expect(output(result)).toContain(reason);
			}
			writeFileSync(
				planPath,
				JSON.stringify({
					fixture: {
						target: "file.swift",
						arguments: [
							"--label",
							"fixture",
							"--mode",
							"exact",
							"--marker",
							"after",
							"--old-block",
							"before",
							"--new-block",
							"after",
						],
					},
				}),
			);
			writeFileSync(join(root, "file.swift"), "before\n");
			const unknown = invoke("unknown");
			expect(unknown.status).toBe(1);
			expect(output(unknown)).toContain("unknown patch operation: unknown");
			const first = invoke();
			expect(first.status, output(first)).toBe(0);
			expect(readFileSync(join(root, "file.swift"), "utf8")).toBe("after\n");
			const second = invoke();
			expect(second.status, output(second)).toBe(0);
			expect(output(second)).toContain("idempotent skip");
		});
	});

	test("every declared patch fails closed when its target is missing", () => {
		withTempDir((root) => {
			for (const [operation, entry] of Object.entries(patchPlan)) {
				const result = run(
					"python3",
					[
						join(repoRoot, "scripts/lib/overlay-patch-plan.py"),
						"--plan",
						join(repoRoot, "scripts/lib/overlay-patch-plan.json"),
						"--patches-dir",
						patchesDir,
						"--patch-tool",
						patchFilePath,
						operation,
					],
					{ cwd: root },
				);
				expect(result.status).toBe(1);
				expect(output(result)).toContain(
					`patch target missing — ${entry.target}`,
				);
			}
		});
	});

	test("[3a/5] pre-overlay diff only runs on a freshly downloaded tree", () => {
		const source = readFileSync(ghosttyVendorPath, "utf8");
		// On SKIP_DOWNLOAD=1 the tree still holds the previous run's applied
		// overlays, so every comparison would be against itself.
		expect(source).toMatch(
			/if \[ "\$SKIP_DOWNLOAD" -ne 0 \]; then\n\s*echo "\[3a\/5\][^"]*skipped[^"]*"\nelse\n/,
		);
		const guarded = source.slice(
			source.indexOf('if [ "$SKIP_DOWNLOAD" -ne 0 ]; then'),
		);
		expect(guarded).toContain(
			"Pre-overlay structural diff (upstream vs overlay)",
		);
		expect(guarded).toContain("OVERLAY_PAIRS=");
	});

	test("the pair manifest drives both relocation and content checks", () => {
		const source = readFileSync(ghosttyVendorPath, "utf8");
		const gate = source.slice(source.indexOf("OVERLAY_PAIRS="));

		// Relocation half.
		expect(gate).toContain("upstream counterparts vanished");
		expect(gate).toContain("YEN_VENDOR_ACCEPT_OVERLAY_PAIR_LOSS");
		// Content half — this is what the retired three-entry Zig tripwire used
		// to cover, now generalized to every paired overlay.
		expect(gate).toContain("CHANGED files that YEN replaces wholesale");
		expect(gate).toContain("YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT");
		expect(gate).toContain("shasum -a 256");
		// Empty manifest is failure, not "nothing to check".
		expect(gate).toMatch(/if \[ ! -s "\$OVERLAY_PAIRS" \][\s\S]*?exit 1/);
		// Both failure paths roll the tree back.
		expect(gate).toContain("mv ghostty.backup ghostty");
	});

	test("the content-drift env cannot forgive a structural break", () => {
		const source = readFileSync(ghosttyVendorPath, "utf8");
		const gate = source.slice(source.indexOf("OVERLAY_PAIRS="));
		// The pair-loss block exits before the drift block is reached, and its
		// only escape is its own env — a moved file is not "content drift".
		const lossIdx = gate.indexOf("upstream counterparts vanished");
		const driftIdx = gate.indexOf("CHANGED files that YEN replaces wholesale");
		expect(lossIdx).toBeGreaterThan(-1);
		expect(driftIdx).toBeGreaterThan(lossIdx);
		expect(gate).toContain(
			"Structural breaks are NOT covered by the content-drift bypass",
		);
		// A re-pin must never write a short manifest.
		expect(gate).toContain("refusing to re-pin an incomplete manifest");
	});

	test("the vendor updater cannot report success after aborting", () => {
		const source = readFileSync(ghosttyVendorPath, "utf8");
		// Same EXIT-trap-swallows-set-u hole as 05-detect-failures.sh and
		// 13-scan-artifact-fingerprints.sh. This was the THIRD hand-written copy
		// of the sentinel; all three now share one implementation, so the next
		// author cannot forget it. Behavioural coverage: tests/145.
		expect(source).toContain("scripts/lib/gate-receipt.sh");
		expect(source).toContain(
			"gate_begin 10-update-ghostty release_ghostty_vendor_lock",
		);
		expect(source).not.toContain("VENDOR_UPDATE_COMPLETED");
		// bash 3.2 traps are single-slot: a second EXIT trap here would silently
		// replace the abort handler, which is why the lock release is passed to
		// gate_begin instead of installed separately.
		expect(source).not.toMatch(/^trap .* EXIT/m);
		// The receipt must be emitted only after the tracking files are written,
		// so a run that dies mid-update cannot report a successful vendor bump.
		const done = source.indexOf('echo "Vendor update: $VERSION');
		expect(done).toBeGreaterThan(0);
		expect(source.indexOf("gate_end 0")).toBeGreaterThan(done);
	});

	test("branding verification is not skippable when the script is absent", () => {
		const source = readFileSync(ghosttyVendorPath, "utf8");
		// The old shape was `if [ -f "$VERIFY_SCRIPT" ]; then ... fi` with no else,
		// which fell through to deleting ghostty.backup and writing a new baseline.
		expect(source).not.toMatch(/if \[ -f "\$VERIFY_SCRIPT" \]; then/);
		expect(source).toMatch(
			/if \[ ! -f "\$VERIFY_SCRIPT" \]; then[\s\S]*?exit 1\nfi/,
		);
	});
});

// ---------------------------------------------------------------------------
// Overlay/upstream pair tracking.
//
// The [3a/5] structural diff was `-name '*.swift'` only, so seven paired
// overlays were never compared. One of them — MainMenu.xib — had silently lost
// the entire upstream Find menu plus Reload Configuration, Change Tab Title
// and Terminal Read-only, leaving ten @IBOutlets nil at runtime. NSMenuItem
// outlets are optional, so nothing failed to compile or build.
// ---------------------------------------------------------------------------
describe("overlay/upstream pair manifest", () => {
	const manifestPath = join(
		repoRoot,
		"yen-terminal/.overlay-upstream-pairs.txt",
	);
	const vendorScript = join(repoRoot, "scripts/10-update-ghostty.sh");

	function pairs(): string[] {
		// Rows are "path<TAB>upstream_sha256" since the pair manifest absorbed
		// the retired build-overlay content tripwire.
		return readFileSync(manifestPath, "utf8")
			.split("\n")
			.filter((l) => l.trim() && !l.startsWith("#"))
			.map((l) => (l.split("\t")[0] ?? "").trim())
			.filter(Boolean);
	}

	test("manifest exists, is non-trivial, and every entry is a real overlay", () => {
		const entries = pairs();
		// ~40 real forks. The first version of this manifest was generated from
		// the APPLIED tree instead of pristine upstream, so every YEN-only file
		// looked like it had an upstream counterpart: 265 entries, 225 of them
		// false. An inflated count is the signature of that mistake, so bound it
		// from BOTH sides rather than just asserting "non-trivial".
		expect(entries.length).toBeGreaterThan(20);
		expect(entries.length).toBeLessThan(80);
		// YEN-only files must never appear — they have no upstream counterpart,
		// so [3a/5] would hard-fail on the next fresh download.
		for (const rel of entries) {
			// YEN-prefixed only. ColorizedGhosttyIconTests.swift is a genuine
			// upstream file despite the name, so a broader pattern false-positives.
			expect(rel).not.toMatch(/\/YEN[A-Za-z]*\.(swift|zig)$/);
			expect(rel).not.toBe("macos/YEN.sdef");
		}
		for (const rel of entries) {
			expect(existsSync(join(repoRoot, "yen-terminal/overlays", rel))).toBe(
				true,
			);
		}
	});

	test("manifest is not Swift-only — the non-Swift pairs are what broke", () => {
		const entries = pairs();
		const nonSwift = entries.filter((e) => !e.endsWith(".swift"));
		expect(nonSwift.length).toBeGreaterThan(0);
		// The specific file whose divergence shipped.
		expect(entries).toContain("macos/Sources/App/MainMenu.xib");
	});

	test("the [3a/5] scan is driven by the manifest, not a *.swift glob", () => {
		const script = readFileSync(vendorScript, "utf8");
		const phase = script.slice(script.indexOf("[3a/5]"));
		expect(phase).toContain("OVERLAY_PAIRS=");
		expect(phase).toContain('done < "$OVERLAY_PAIRS"');
		// A vanished upstream counterpart must fail, not `continue`.
		expect(phase).toContain("upstream counterparts vanished");
		// Content drift is the other half, and is separately waivable.
		expect(phase).toContain("CHANGED files that YEN replaces wholesale");
		expect(phase).toContain("YEN_VENDOR_ACCEPT_OVERLAY_CONTENT_DRIFT");
		expect(phase).toMatch(
			/OVERLAY_LOST_COUNT" -gt 0 \][\s\S]*?YEN_VENDOR_ACCEPT_OVERLAY_PAIR_LOSS[\s\S]*?exit 1/,
		);
		// Empty manifest is failure, not "nothing to check".
		expect(phase).toMatch(/if \[ ! -s "\$OVERLAY_PAIRS" \][\s\S]*?exit 1/);
	});

	test("every AppDelegate menu outlet is connected in the overlay xib", () => {
		// A nil NSMenuItem outlet is silent: optional, so no compile error and
		// no runtime crash — the menu item simply is not there.
		const xib = readFileSync(
			join(repoRoot, "yen-terminal/overlays/macos/Sources/App/MainMenu.xib"),
			"utf8",
		);
		const appDelegate = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/App/AppDelegate.swift",
			),
			"utf8",
		);
		const declared = [
			...appDelegate.matchAll(/@IBOutlet\s+(?:private\s+)?var\s+(menu\w+)/g),
		]
			.map((m) => m[1])
			.filter((v): v is string => v !== undefined);
		const connected = new Set(
			[...xib.matchAll(/property="(menu\w+)"/g)]
				.map((m) => m[1])
				.filter((v): v is string => v !== undefined),
		);

		expect(declared.length).toBeGreaterThan(50);
		// Every declared outlet must now be connected. menuOpenConfig was the
		// last holdout: upstream binds it to "Preferences…" on Cmd+, which YEN
		// replaced with its Settings panel, so it is restored as "Open
		// Configuration File" with no key equivalent instead.
		const nil = declared.filter((d) => !connected.has(d));
		expect(nil).toEqual([]);
	});

	test("the restored Find menu is wired end to end", () => {
		const xib = readFileSync(
			join(repoRoot, "yen-terminal/overlays/macos/Sources/App/MainMenu.xib"),
			"utf8",
		);
		for (const sel of [
			"find:",
			"findNext:",
			"findPrevious:",
			"findHide:",
			"selectionForFind:",
			"scrollToSelection:",
			"reloadConfig:",
			"changeTabTitle:",
			"toggleReadonly:",
			"openConfig:",
		]) {
			expect(xib).toContain(`selector="${sel}"`);
		}
		// Cmd+, must remain YEN's Settings panel, not upstream's Preferences.
		expect(xib).toContain('title="Settings..." keyEquivalent=","');
		expect((xib.match(/keyEquivalent=","/g) || []).length).toBe(1);
	});

	function collectRepeatableConfigKeys(schema: string): Set<string> {
		const keys = new Set<string>();
		for (const match of schema.matchAll(
			/^(?:@"([a-z0-9-]+)"|([a-z0-9_]+)):\s*Repeatable[A-Za-z]*\s*=/gm,
		)) {
			const key = match[1] ?? match[2];
			if (key) keys.add(key);
		}
		return keys;
	}

	function addDocumentedRepeatableConfigKeys(
		keys: Set<string>,
		schema: string,
	): void {
		const declarationPattern =
			/^(?:@"([a-z0-9-]+)"|([a-z0-9_]+)):\s*[A-Za-z][A-Za-z0-9_.]*\s*=/;
		const lines = schema.split("\n");
		for (let index = 0; index < lines.length; index += 1) {
			if (!/This configuration can be repeated/i.test(lines[index] ?? ""))
				continue;
			const candidates = lines.slice(index + 1, index + 40);
			const declaration = candidates
				.map((line) => declarationPattern.exec(line ?? ""))
				.find((match) => match !== null);
			const key = declaration?.[1] ?? declaration?.[2];
			if (key) keys.add(key);
		}
	}

	function extractManagedRepeatableKeys(documentSource: string): Set<string> {
		const body =
			documentSource.match(
				/static let repeatableKeys: Set<String> = \[([\s\S]*?)\]/,
			)?.[1] ?? "";
		return new Set(
			[...body.matchAll(/^\s*"([^"]+)",\s*$/gm)]
				.map((match) => match[1])
				.filter((key): key is string => key !== undefined),
		);
	}

	test("every upstream repeatable config key is listed in ManagedConfigDocument.repeatableKeys", () => {
		// ManagedConfigDocument.merged() de-duplicates by key. A repeatable key missing
		// from `repeatableKeys` has every occurrence after the first silently DELETED
		// from the user's config.yen on the next Settings write — a hand-authored
		// 16-line `palette` block destroyed by an unrelated slider drag. Only `keybind`
		// used to be listed, so `palette`, `config-file`, the font-family fallback
		// chain, `link`, `env` and the rest were all being truncated.
		//
		// Re-derive the truth from the vendored schema rather than trusting a
		// hand-maintained list, so a vendor bump that adds a repeatable key fails here
		// instead of silently eating user data.
		const configZig = join(
			repoRoot,
			"yen-terminal/ghostty/src/config/Config.zig",
		);
		// Fail closed, not open. A bare `return` here reports green while checking
		// nothing, and this is the ONLY guard standing between a vendor bump and silent
		// config data loss. Set YEN_ALLOW_MISSING_VENDOR_TREE=1 for the fresh-clone case.
		if (!existsSync(configZig)) {
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"vendored Config.zig missing — run scripts/10-update-ghostty.sh, or set YEN_ALLOW_MISSING_VENDOR_TREE=1 to acknowledge this check did not run",
			).toBe("1");
			return;
		}

		const schema = readFileSync(configZig, "utf8");
		const upstreamRepeatable = collectRepeatableConfigKeys(schema);
		// Keys that accumulate through a CUSTOM type rather than a `Repeatable*` family
		// (`Keybinds`, `Palette`, `KeyRemapSet` today). DERIVED from upstream's own doc
		// comments, not hand-listed: a hand-list is how `key-remap` was missed in the
		// first place, and a hand-list cannot fail when upstream adds the next one.
		addDocumentedRepeatableConfigKeys(upstreamRepeatable, schema);
		// `palette` and `keybind` accumulate but are not documented with that phrasing.
		upstreamRepeatable.add("palette");
		upstreamRepeatable.add("keybind");

		// Fail closed if the doc-comment sweep stops finding the key it was written for.
		expect(
			upstreamRepeatable.has("key-remap"),
			"key-remap must be DISCOVERED from Config.zig, not hand-listed",
		).toBe(true);

		// Sanity-check the extraction itself, so a schema reshuffle cannot turn this
		// into a vacuous pass over an empty set.
		expect(upstreamRepeatable.size).toBeGreaterThanOrEqual(15);
		expect(upstreamRepeatable.has("config-file")).toBe(true);
		expect(upstreamRepeatable.has("font-family")).toBe(true);

		const documentSource = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/Settings/ManagedConfigDocument.swift",
			),
			"utf8",
		);
		const declared = extractManagedRepeatableKeys(documentSource);

		const missing = [...upstreamRepeatable].filter((key) => !declared.has(key));
		expect(
			missing,
			`repeatable keys missing from repeatableKeys: ${missing.join(", ")}`,
		).toEqual([]);
	});
});

// A fileSystemSynchronizedGroup resolves its sources by FOLDER NAME on disk.
// The branding pass rewrites `Ghostty` to `YEN` throughout the pbxproj, so any
// group whose folder is not renamed alongside it silently points at nothing.
// The resulting target compiles zero sources and emits no executable, yet the
// BUILD still exits 0 — the failure only surfaces later, as a bundle-load error
// at test time, which no gate in this repo runs.
//
// This is exactly how YENUITests shipped broken: 28 UI tests across 6 files
// never executed. Assert the invariant rather than the one instance, so the
// next upstream target that arrives with a synchronized group is covered too.
describe("pbxproj synchronized groups", () => {
	const projectPath = join(
		repoRoot,
		"yen-terminal/ghostty/macos/YEN.xcodeproj/project.pbxproj",
	);

	test("every synchronized-group folder exists on disk", () => {
		if (!existsSync(projectPath)) {
			// Fail closed rather than skip: a missing generated tree means this guard
			// verified nothing, and reporting that as a pass is the bug it catches.
			expect(
				process.env.YEN_ALLOW_MISSING_VENDOR_TREE,
				"ghostty tree absent; run apply-overlays.sh or set YEN_ALLOW_MISSING_VENDOR_TREE=1",
			).toBe("1");
			return;
		}

		const source = readFileSync(projectPath, "utf8");
		const macosDir = join(repoRoot, "yen-terminal/ghostty/macos");

		// PBXFileSystemSynchronizedRootGroup entries carry the folder in `path`.
		const groups = [
			...source.matchAll(
				/isa = PBXFileSystemSynchronizedRootGroup;[\s\S]*?path = ([^;]+);/g,
			),
		].map((match) => (match[1] ?? "").trim().replace(/^"|"$/g, ""));

		expect(
			groups.length,
			"no synchronized root groups found — the regex or the pbxproj format changed",
		).toBeGreaterThan(0);

		const missing = groups.filter(
			(folder) => !existsSync(join(macosDir, folder)),
		);
		expect(
			missing,
			`synchronized group folders missing on disk: ${missing.join(", ")}`,
		).toEqual([]);
	});
});
