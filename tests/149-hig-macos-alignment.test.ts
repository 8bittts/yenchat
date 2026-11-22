import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();

function readOverlay(relativePath: string): string {
	return readFileSync(
		join(repoRoot, "yen-terminal/overlays/macos", relativePath),
		"utf8",
	);
}

describe("Native macOS HIG alignment guardrails", () => {
	test("Moving Wallpaper copy names YEN, not the standalone MovingPaper app", () => {
		const folder = "Sources/Features/MovingWallpaper";
		const files = readdirSync(
			join(repoRoot, "yen-terminal/overlays/macos", folder),
		).filter((name) => name.endsWith(".swift"));
		expect(files.length).toBeGreaterThan(0);
		for (const name of files) {
			const literals =
				readOverlay(`${folder}/${name}`).match(
					/"[^"\n]*MovingPaper[^"\n]*"/g,
				) ?? [];
			expect(literals, name).toEqual([]);
		}
	});

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

	test("Help holds YEN Help and Bitcoin Email, and no link to the retired JP the Cat", () => {
		const xib = readOverlay("Sources/App/MainMenu.xib");
		const appDelegate = readOverlay("Sources/App/AppDelegate.swift");
		const helpMenu = xib.match(
			/<menu key="submenu" title="Help" systemMenu="help"[\s\S]*?<\/menu>/,
		)?.[0];
		expect(helpMenu).toBeDefined();
		const titles = Array.from(
			helpMenu?.matchAll(/<menuItem title="([^"]+)"/g) ?? [],
			(match) => match[1],
		);
		expect(titles).toEqual(["YEN Help", "Bitcoin Email"]);
		// A menu item, outlet, action or link left behind would still reach the retired site.
		expect(xib).not.toMatch(/JP ?the ?Cat/i);
		expect(appDelegate).not.toMatch(/JP ?the ?Cat/i);
		expect(appDelegate).not.toContain('systemSymbolName: "pawprint"');
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
