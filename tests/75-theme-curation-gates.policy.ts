import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();

function read(relativePath: string): string {
	return readFileSync(join(repoRoot, relativePath), "utf8");
}

function parseCuratedThemes(manifest: string): string[] {
	return manifest
		.split(/\r?\n/)
		.map((line) => line.trim())
		.filter((line) => line.length > 0 && !line.startsWith("#"));
}

describe("Theme curation pipeline gates", () => {
	test("curated manifest is present, bounded, and pinned defaults are included", () => {
		const manifest = read(
			"yen-terminal/customizations/theme-curated-manifest.txt",
		);
		const themes = parseCuratedThemes(manifest);

		expect(themes.length).toBeGreaterThanOrEqual(16);
		expect(themes.length).toBeLessThanOrEqual(24);
		expect(themes).toContain("YEN");
		expect(themes).toContain("Retro Terminal");
		expect(themes).toContain("CutePretzel");

		const lowered = themes.map((name) => name.toLowerCase());
		expect(new Set(lowered).size).toBe(lowered.length);
	});

	test("curated tags file exists and matches manifest coverage with allowed categories", () => {
		const manifest = read(
			"yen-terminal/customizations/theme-curated-manifest.txt",
		);
		const tags = read("yen-terminal/customizations/theme-curated-tags.txt");
		const themes = parseCuratedThemes(manifest);
		const allowed = new Set([
			"dark",
			"light",
			"retro",
			"neon",
			"low-contrast",
			"high-contrast",
		]);
		const tagsByTheme = new Map<string, Set<string>>();

		for (const line of tags.split(/\r?\n/)) {
			const trimmed = line.trim();
			if (!trimmed || trimmed.startsWith("#")) continue;
			const parts = trimmed.split("|");
			expect(parts.length).toBe(2);
			const theme = parts[0]?.trim() ?? "";
			expect(theme.length).toBeGreaterThan(0);
			const categories = (parts[1] ?? "")
				.split(",")
				.map((token) => token.trim().toLowerCase())
				.filter((token) => token.length > 0);
			expect(categories.length).toBeGreaterThan(0);
			for (const category of categories) {
				expect(allowed.has(category)).toBe(true);
			}
			tagsByTheme.set(theme.toLowerCase(), new Set(categories));
		}

		expect(tagsByTheme.size).toBe(themes.length);
		for (const theme of themes) {
			expect(tagsByTheme.has(theme.toLowerCase())).toBe(true);
		}
	});

	test("every allowed search tag is carried by at least one curated theme", () => {
		// The Settings search tooltip lists these tags; a tag no theme carries
		// is a search that can only return nothing.
		const tags = read("yen-terminal/customizations/theme-curated-tags.txt");
		const used = new Set<string>();
		for (const line of tags.split(/\r?\n/)) {
			const trimmed = line.trim();
			if (!trimmed || trimmed.startsWith("#")) continue;
			for (const token of (trimmed.split("|")[1] ?? "").split(",")) {
				used.add(token.trim().toLowerCase());
			}
		}

		expect(used.size).toBeGreaterThan(0);
		for (const tag of [
			"dark",
			"light",
			"retro",
			"neon",
			"low-contrast",
			"high-contrast",
		]) {
			expect(used.has(tag)).toBe(true);
		}
	});

	test("docs sync script extracts picker pins from the theme catalog source", () => {
		const syncScript = read("scripts/manual/26-sync-theme-catalog.sh");

		expect(syncScript).toContain("SettingsThemeCatalog.swift");
		expect(syncScript).toContain("pinnedThemeOrder");
		expect(syncScript).toContain("could not extract pinnedThemeOrder");
	});

	test("bundle pipeline does not recreate retired full theme catalog", () => {
		const bundler = read("scripts/lib/bundle-resource-phases/01-themes.sh");
		const failureDetector = read("scripts/05-detect-failures.sh");

		expect(bundler).toContain(
			'rm -rf "$APP_PATH/Contents/Resources/yen/themes-full"',
		);
		expect(bundler).not.toContain(
			'mkdir -p "$APP_PATH/Contents/Resources/yen/themes-full"',
		);
		expect(bundler).not.toContain("themes-full/$theme_name");
		expect(bundler).not.toContain("hidden legacy themes");
		expect(failureDetector).toContain(
			"Retired full theme catalog still bundled",
		);
	});
});
