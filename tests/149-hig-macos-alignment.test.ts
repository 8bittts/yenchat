import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();

function readOverlay(relativePath: string): string {
	return readFileSync(
		join(repoRoot, "yen-terminal/overlays/macos", relativePath),
		"utf8",
	);
}

describe("Native macOS HIG alignment guardrails", () => {
	test("Settings section headers are not forced uppercase", () => {
		for (const name of [
			"SettingsPanel.swift",
			"SettingsStudioPanes.swift",
			"SettingsShortcutsPane.swift",
			"SettingsStudioPreview.swift",
		]) {
			const source = readOverlay(`Sources/Features/Settings/${name}`);
			expect(source).not.toContain(".textCase(.uppercase)");
		}
	});

	test("Settings uses grouped system forms and glass", () => {
		const panes = readOverlay(
			"Sources/Features/Settings/SettingsStudioPanes.swift",
		);
		const preview = readOverlay(
			"Sources/Features/Settings/SettingsStudioPreview.swift",
		);
		expect(panes).toContain(".formStyle(.grouped)");
		expect(panes).toContain(".scrollContentBackground(.hidden)");
		expect(preview).toContain(".glassEffect(.regular, in: shape)");
		// The cursor blink honors Reduce Motion.
		expect(preview).toContain("accessibilityReduceMotion");
	});

	test("JP the Cat lives in Help, not the Apple menu", () => {
		const xib = readOverlay("Sources/App/MainMenu.xib");
		const appDelegate = readOverlay("Sources/App/AppDelegate.swift");
		const appleMenu = xib.match(
			/<menu key="submenu" title="YEN" systemMenu="apple"[\s\S]*?<\/menu>/,
		)?.[0];
		const helpMenu = xib.match(
			/<menu key="submenu" title="Help" systemMenu="help"[\s\S]*?<\/menu>/,
		)?.[0];
		expect(appleMenu).toBeDefined();
		expect(helpMenu).toBeDefined();
		expect(appleMenu).not.toContain('title="JP the Cat"');
		expect(helpMenu).toContain('title="JP the Cat"');
		expect(helpMenu).toContain('title="Bitcoin Email"');
		expect(helpMenu?.indexOf("JP the Cat")).toBeLessThan(
			helpMenu?.indexOf("Bitcoin Email") ?? -1,
		);
		expect(appDelegate).toContain('systemSymbolName: "pawprint"');
		expect(appDelegate).toContain('systemSymbolName: "bitcoinsign.circle"');
		expect(appDelegate).toContain('systemSymbolName: "lightbulb"');
		expect(appDelegate).toContain("func openBitcoinEmail");
		expect(appDelegate).toContain('"https://btc.email"');
	});

	test("idle dictation status item uses a template SF Symbol", () => {
		const source = readOverlay(
			"Sources/Features/Dictation/DictationController.swift",
		);
		expect(source).toContain("makeIdleStatusImage");
		expect(source).toContain('systemSymbolName: "waveform"');
		expect(source).toContain("image?.isTemplate = true");
		expect(source).not.toContain("image.isTemplate = false");
	});

	test("About uses Dynamic Type and a system button", () => {
		const about = readOverlay("Sources/Features/About/AboutView.swift");
		expect(about).toContain(".font(.title2.weight(.semibold))");
		expect(about).toContain('"https://btc.email"');
		for (const title of ["Docs", "Bitcoin"]) {
			const modifiers = about.match(
				new RegExp(
					`Button\\("${title}"\\)\\s*\\{[^}]*\\}((?:\\s*\\.[^\\n]+)*)`,
				),
			)?.[1];
			expect(modifiers).toContain(".buttonStyle(.bordered)");
			expect(modifiers).not.toContain(".clipShape(");
		}
		expect(about).not.toContain(".font(.system(size: 24");
	});

	test("command palette search field uses scaled system font", () => {
		const palette = readOverlay(
			"Sources/Features/Command Palette/CommandPalette.swift",
		);
		expect(palette).toContain(
			".settingsScaledSystemFont(size: 20, relativeTo: .title3, weight: .light)",
		);
		expect(palette).not.toContain(".font(.system(size: 20, weight: .light))");
	});

	test("onboarding permission status respects Differentiate Without Color", () => {
		const onboarding = readOverlay(
			"Sources/Features/Onboarding/OnboardingPanel.swift",
		);
		expect(onboarding).toContain("accessibilityDifferentiateWithoutColor");
		expect(onboarding).toContain("statusColor");
	});
});
