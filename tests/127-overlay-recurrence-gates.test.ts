import { describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const repoRoot = process.cwd();
const gateScript = join(
	repoRoot,
	"scripts/42-lint-overlay-recurrence-gates.sh",
);
const applyOverlaysPath = join(repoRoot, "yen-terminal/apply-overlays.sh");
const heredocInventoryPath = join(
	repoRoot,
	"scripts/lib/overlay-recurrence-allowlist/apply-overlays-python-heredocs.txt",
);
const componentVerifyPath = join(repoRoot, "scripts/03-verify-components.sh");
const nativeSmokePath = join(repoRoot, "scripts/native/01-macos-smoke.sh");
const terminalViewBackgroundRuntimePath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Terminal/TerminalViewBackgroundRuntime.swift",
);
const terminalViewPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Terminal/TerminalView.swift",
);

function runGate(args: string[] = []) {
	return spawnSync("bash", [gateScript, ...args], {
		cwd: repoRoot,
		encoding: "utf8",
	});
}

function output(result: ReturnType<typeof runGate>): string {
	return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
}

function withTempDir<T>(callback: (dir: string) => T): T {
	const dir = mkdtempSync(join(tmpdir(), "yen-overlay-recurrence-"));
	try {
		return callback(dir);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

function writeSwiftFixture(root: string, relativePath: string, source: string) {
	const path = join(root, relativePath);
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, source, "utf8");
	return path;
}

function writeAllowlistFixture(root: string, files: Record<string, string>) {
	const allowlistDir = join(root, "allowlists");
	mkdirSync(allowlistDir, { recursive: true });
	writeFileSync(
		join(allowlistDir, "apply-overlays-python-heredocs.txt"),
		readFileSync(heredocInventoryPath, "utf8"),
		"utf8",
	);
	writeFileSync(
		join(allowlistDir, "non-debug-print-sites.txt"),
		files.prints ?? "# path|normalized print call|note\n",
		"utf8",
	);
	writeFileSync(
		join(allowlistDir, "timer-without-tolerance-sites.txt"),
		files.timers ?? "# path|timer target|normalized scheduledTimer call|note\n",
		"utf8",
	);
	return allowlistDir;
}

describe("overlay recurrence gates", () => {
	test("native smoke and component verification run the recurrence gates", () => {
		const componentVerify = readFileSync(componentVerifyPath, "utf8");
		const nativeSmoke = readFileSync(nativeSmokePath, "utf8");

		expect(componentVerify).toContain(
			"scripts/42-lint-overlay-recurrence-gates.sh",
		);
		expect(nativeSmoke).toContain(
			"scripts/42-lint-overlay-recurrence-gates.sh",
		);
	});

	test("component verification scans apply-overlays for macOS Bash compatibility", () => {
		const componentVerify = readFileSync(componentVerifyPath, "utf8");

		expect(componentVerify).toContain("BASH4_PATTERN=");
		expect(componentVerify).toContain(
			'"$REPO_ROOT/yen-terminal/apply-overlays.sh"',
		);
		expect(componentVerify).toContain('"$REPO_ROOT/yen-cli/bin/yen"');
	});

	test("terminal whole-window background runtime keeps Ghostty reload hooks source-proven", () => {
		const source = readFileSync(terminalViewBackgroundRuntimePath, "utf8");
		const terminalView = readFileSync(terminalViewPath, "utf8");

		expect(source).toContain(
			"settingsController.writeSurfaceBackgroundRuntimeConfig",
		);
		expect(source).toContain(
			"let runtimeConfig = YEN.Config(at: runtimeConfigPath)",
		);
		expect(source).toContain("yen_surface_update_config(surface, config)");
		expect(source).toContain("yen.reloadConfig(surface: surface, soft: true)");
		expect(source).toContain(
			"settingsController.removeWholeWindowBackgroundRuntimeConfigIfPresent()",
		);
		for (const trigger of [
			".onAppear {",
			".onChange(of: viewModel.surfaceTree.structuralIdentity)",
			".onChange(of: settingsSnapshot.backgroundImagePath)",
			".onChange(of: settingsSnapshot.backgroundImageScope)",
			".onChange(of: settingsSnapshot.backgroundOpacity)",
			".yenConfigDidChange",
		]) {
			const triggerIndex = terminalView.indexOf(trigger);
			expect(triggerIndex).toBeGreaterThanOrEqual(0);
			const syncIndex = terminalView.indexOf(
				"syncWholeWindowBackgroundRuntime(",
				triggerIndex,
			);
			expect(syncIndex).toBeGreaterThan(triggerIndex);
		}
		const configEvent = terminalView.indexOf(".yenConfigDidChange");
		const nextHandler = terminalView.indexOf(".onReceive(", configEvent);
		expect(nextHandler).toBeGreaterThan(configEvent);
		expect(terminalView.slice(configEvent, nextHandler)).toContain(
			"sourceConfig: notification.userInfo?[Notification.Name.YENConfigChangeKey] as? YEN.Config",
		);
	});

	test("current overlay sources pass failing gates while god-file warnings stay non-blocking", () => {
		const result = runGate();
		const combined = output(result);

		expect(result.status).toBe(0);
		expect(combined).toContain("Overlay print gate clean");
		expect(combined).toContain("Timer tolerance gate clean");
		expect(combined).toContain("apply-overlays Python heredoc inventory clean");
	});

	test("apply-overlays does not keep unreachable post-command status guards", () => {
		const script = readFileSync(applyOverlaysPath, "utf8");

		expect(script).not.toContain("if [ $? -ne 0 ]; then");
	});

	test("print gate is token-aware and fails only non-DEBUG Swift print calls", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"Example.swift",
				[
					"import Foundation",
					"func example() {",
					'    let message = "print(allowed string)"',
					'    // print("allowed comment")',
					"    /* outer comment",
					"       /* nested comment */",
					'       print("allowed nested comment")',
					"    */",
					'    logger.print("allowed method")',
					'    let block = """',
					'    print("allowed multiline string")',
					'    """',
					'    let raw = #"print("allowed raw string")"#',
					'    let rawBlock = #"""',
					'    print("allowed raw multiline string")',
					'    """#',
					"    #if DEBUG",
					'    print("allowed debug")',
					"    #endif",
					'    Swift.print("new runtime log")',
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("unallowlisted non-DEBUG print");
			expect(combined).toContain("Example.swift");
			expect(combined).toContain("new runtime log");
			expect(combined).not.toContain("allowed debug");
			expect(combined).not.toContain("allowed string");
			expect(combined).not.toContain("allowed nested comment");
			expect(combined).not.toContain("allowed method");
			expect(combined).not.toContain("allowed multiline string");
			expect(combined).not.toContain("allowed raw string");
			expect(combined).not.toContain("allowed raw multiline string");
		});
	});

	test("print gate fails count-preserving replacements against exact site baselines", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			const allowlistDir = writeAllowlistFixture(dir, {
				prints: [
					"# path|normalized print call|note",
					'Example.swift|print("old runtime log")|fixture baseline',
					"",
				].join("\n"),
			});
			writeSwiftFixture(
				sources,
				"Example.swift",
				[
					"import Foundation",
					"func example() {",
					'    print("new runtime log")',
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
				"--allowlist-dir",
				allowlistDir,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("new runtime log");
			expect(combined).toContain("old runtime log");
		});
	});

	test("print exact-site baselines allow pipe characters in normalized calls", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			const allowlistDir = writeAllowlistFixture(dir, {
				prints: [
					"# path|normalized print call|note",
					'Example.swift|print("runtime | log")|fixture baseline',
					"",
				].join("\n"),
			});
			writeSwiftFixture(
				sources,
				"Example.swift",
				[
					"import Foundation",
					"func example() {",
					'    print("runtime | log")',
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
				"--allowlist-dir",
				allowlistDir,
			]);

			expect(result.status).toBe(0);
			expect(output(result)).toContain("Overlay print gate clean");
		});
	});

	test("timer gate fails new scheduled timers that lack tolerance", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"TimerFixture.swift",
				[
					"import Foundation",
					"final class TimerFixture {",
					"    private var slowTimer: Timer?",
					"    func start() {",
					"        slowTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in",
					"            print(Date())",
					"        }",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("scheduled timers without tolerance");
			expect(combined).toContain("TimerFixture.swift");
			expect(combined).toContain("slowTimer");
		});
	});

	test("timer gate fails count-preserving replacements against exact site baselines", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			const allowlistDir = writeAllowlistFixture(dir, {
				timers: [
					"# path|timer target|normalized scheduledTimer call|note",
					"TimerFixture.swift|oldTimer|Timer.scheduledTimer(withTimeInterval: 5, repeats: true)|fixture baseline",
					"",
				].join("\n"),
			});
			writeSwiftFixture(
				sources,
				"TimerFixture.swift",
				[
					"import Foundation",
					"final class TimerFixture {",
					"    private var newTimer: Timer?",
					"    func start() {",
					"        newTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in",
					"            _ = Date()",
					"        }",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
				"--allowlist-dir",
				allowlistDir,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("newTimer");
			expect(combined).toContain("oldTimer");
		});
	});

	test("timer gate accepts scheduled timers with explicit tolerance", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"TimerFixture.swift",
				[
					"import Foundation",
					"final class TimerFixture {",
					"    private var slowTimer: Timer?",
					"    private var typedTimer: Timer?",
					"    func start() {",
					"        self.slowTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in",
					"            _ = Date()",
					"        }",
					"        self.slowTimer!.tolerance = 0.5",
					"        let localTimer: Timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in",
					"            _ = Date()",
					"        }",
					"        localTimer.tolerance = 1.0",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(0);
			expect(combined).toContain("Timer tolerance gate clean");
		});
	});

	test("surface owner gate fails controller lookups derived from a surface window", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"SurfaceOwnerFixture.swift",
				[
					"import AppKit",
					"final class SurfaceOwnerFixture {",
					"    func focus(_ surface: YEN.SurfaceView) {",
					"        if let controller = surface.window?.windowController as? BaseTerminalController {",
					"            controller.focusSurface(surface)",
					"        }",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("surface-derived controller lookup");
			expect(combined).toContain("BaseTerminalController.controller(owning:)");
		});
	});

	test("surface owner gate matches force-unwrapped and renamed surface receivers", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"SurfaceOwnerVariantsFixture.swift",
				[
					"import AppKit",
					"final class SurfaceOwnerVariantsFixture {",
					"    var palette: BaseTerminalController? {",
					"        surfaceView.window?.windowController as? BaseTerminalController",
					"    }",
					"    var forced: BaseTerminalController? {",
					"        self.focusedSurface.window!.windowController as! BaseTerminalController",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain("surfaceView.window");
			expect(combined).toContain("focusedSurface.window");
		});
	});

	test("surface owner gate allows the ownership helper and window-derived lookups", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"SurfaceOwnerCleanFixture.swift",
				[
					"import AppKit",
					"final class SurfaceOwnerCleanFixture {",
					"    func focus(_ surface: YEN.SurfaceView) {",
					"        if let controller = BaseTerminalController.controller(owning: surface) {",
					"            controller.focusSurface(surface)",
					"        } else {",
					"            surface.window?.makeKeyAndOrderFront(nil)",
					"        }",
					"    }",
					"    func byWindow(_ window: NSWindow) -> BaseTerminalController? {",
					"        window.windowController as? BaseTerminalController",
					"    }",
					"    func byKeyWindow() -> BaseTerminalController? {",
					"        NSApp.keyWindow?.windowController as? BaseTerminalController",
					"    }",
					"    func byTab(_ tab: TabModel) -> BaseTerminalController? {",
					"        tab.window.windowController as? BaseTerminalController",
					"    }",
					"}",
					"",
				].join("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
			]);
			const combined = output(result);

			expect(result.status).toBe(0);
			expect(combined).toContain("surface owner lookup gate clean");
		});
	});

	test("shipped overlays resolve surface owners through the ownership helper", () => {
		const notificationSound = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/App/AppDelegate+NotificationSound.swift",
			),
			"utf8",
		);
		const commandPalette = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/Command Palette/TerminalCommandPalette.swift",
			),
			"utf8",
		);

		expect(notificationSound).toContain(
			"BaseTerminalController.controller(owning: surface)",
		);
		expect(commandPalette).toContain(
			"BaseTerminalController.controller(owning: surfaceView)",
		);
	});

	test("god-file line-count gate warns but does not fail", () => {
		withTempDir((dir) => {
			const sources = join(dir, "Sources");
			writeSwiftFixture(
				sources,
				"Large.swift",
				Array.from({ length: 12 }, (_, index) => `let value${index} = ${index}`)
					.join("\n")
					.concat("\n"),
			);

			const result = runGate([
				"--sources-dir",
				sources,
				"--apply-overlays",
				applyOverlaysPath,
				"--god-file-threshold",
				"10",
			]);
			const combined = output(result);

			expect(result.status).toBe(0);
			expect(combined).toContain("WARN overlay god-file line-count");
			expect(combined).toContain("Large.swift");
		});
	});

	test("god-file line-count gate covers apply-overlays.sh (warn, not fail)", () => {
		withTempDir((dir) => {
			const oversizedApply = join(dir, "apply-overlays.sh");
			writeFileSync(oversizedApply, "# fixture\n".repeat(150));
			const emptySources = join(dir, "empty-sources");
			mkdirSync(emptySources, { recursive: true });

			const result = runGate([
				"--sources-dir",
				emptySources,
				"--apply-overlays",
				oversizedApply,
				"--god-file-threshold",
				"100",
			]);
			const combined = output(result);

			expect(result.status).toBe(0);
			expect(combined).toContain("WARN overlay god-file line-count");
			expect(combined).toContain("apply-overlays.sh");
		});
	});

	test("phase scan fails closed on absent files and inline Python", () => {
		withTempDir((dir) => {
			const sources = join(dir, "sources");
			const phases = join(dir, "phases");
			mkdirSync(sources);
			mkdirSync(phases);
			const args = ["--sources-dir", sources, "--phase-dir", phases];
			const empty = runGate(args);
			expect(empty.status).toBe(1);
			expect(output(empty)).toContain("phase scan matched zero scripts");
			writeFileSync(
				join(phases, "fixture.sh"),
				"python3 - \"$PHASE_INLINE_PATCH\" <<'PATCHPY'\nprint('patch')\nPATCHPY\n",
			);
			const invalid = runGate(args);
			expect(invalid.status).toBe(1);
			expect(output(invalid)).toContain("PHASE_INLINE_PATCH");
			writeFileSync(join(phases, "fixture.sh"), "printf 'fixture\\n'\n");
			const valid = runGate(args);
			expect(valid.status, output(valid)).toBe(0);
			expect(output(valid)).toContain(
				"Python heredoc inventory clean; scanned",
			);
		});
	});

	test("apply-overlays Python heredoc inventory fails closed on new heredocs", () => {
		withTempDir((dir) => {
			const emptySources = join(dir, "empty-sources");
			mkdirSync(emptySources, { recursive: true });
			const modifiedApplyOverlays = join(dir, "apply-overlays.sh");
			writeFileSync(
				modifiedApplyOverlays,
				readFileSync(applyOverlaysPath, "utf8").concat(
					[
						"",
						"python3 - \"$NEW_INLINE_PATCH\" << 'PATCHPY'",
						"print('new inline patch')",
						"PATCHPY",
						"",
					].join("\n"),
				),
				"utf8",
			);

			const result = runGate([
				"--sources-dir",
				emptySources,
				"--apply-overlays",
				modifiedApplyOverlays,
			]);
			const combined = output(result);

			expect(result.status).toBe(1);
			expect(combined).toContain(
				"apply-overlays Python heredoc inventory drift",
			);
			expect(combined).toContain("NEW_INLINE_PATCH");
		});
	});
});
