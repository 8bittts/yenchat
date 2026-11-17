import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const settingsDir = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Settings",
);
const read = (name: string) => readFileSync(join(settingsDir, name), "utf8");

describe("Settings panel rendering guardrails", () => {
	test("the panel offers no search, import, export, or per-pane reset", () => {
		// The Studio panel removed these on purpose: every setting is on one of
		// five short panes, so there is nothing to hunt for and nothing to back up.
		const sources = readdirSync(settingsDir)
			.filter((name) => name.endsWith(".swift"))
			.map((name) => ({ name, source: read(name) }));

		expect(sources.length).toBeGreaterThan(20);
		for (const { name, source } of sources) {
			const where = `Settings/${name}`;
			expect(source, where).not.toContain(".searchable(");
			expect(source, where).not.toContain("NSSavePanel");
			expect(source, where).not.toContain("yenconfig");
			expect(source, where).not.toContain("exportSettingsConfiguration");
			expect(source, where).not.toContain("importSettingsConfiguration");
			expect(source, where).not.toContain("resetSelectedSettingsSection");
			expect(source, where).not.toContain("keyboardSearchText");
			expect(source, where).not.toContain("themeSearchText");
		}
	});

	test("theme settings no longer expose legacy full-catalog controls", () => {
		for (const name of [
			"SettingsPanel.swift",
			"SettingsStudioPreview.swift",
			"ThemesSettingsStore.swift",
		]) {
			const source = read(name);
			expect(source).not.toContain("Legacy Catalog");
			expect(source).not.toContain("Full Theme Catalog");
			expect(source).not.toContain("showFullThemeCatalog");
			expect(source).not.toContain("themes-legacy-catalog");
		}
	});

	test("theme catalog source cannot load hidden themes-full directory", () => {
		for (const name of [
			"SettingsController.swift",
			"SettingsThemeCatalog.swift",
		]) {
			const source = read(name);
			expect(source).not.toContain("themes-full");
			expect(source).not.toContain("fullThemesDirectory");
			expect(source).not.toContain("includeFullThemeCatalog");
			expect(source).not.toContain("hasHiddenFullCatalogThemes");
		}
	});
});
