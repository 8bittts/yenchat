import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { normalizeThemeContent } from "../scripts/theme-contrast.js";

const repoRoot = process.cwd();

function curatedThemes(): string[] {
	return readFileSync(
		join(repoRoot, "yen-terminal/customizations/theme-curated-manifest.txt"),
		"utf8",
	)
		.split(/\r?\n/)
		.map((line) => line.trim())
		.filter((line) => line.length > 0 && !line.startsWith("#"));
}

describe("Theme contrast gates", () => {
	test("tracked custom themes normalize to readable contrast roles", () => {
		const manifestThemes = new Set(curatedThemes());
		const customThemesDir = join(
			repoRoot,
			"yen-terminal/customizations/themes",
		);
		const customThemeNames = readdirSync(customThemesDir).sort();

		// These are the only theme sources available in a clean checkout.
		// The native build generates the remaining upstream sources before bundling.
		expect(customThemeNames).toEqual(["CutePretzel", "Retro Terminal", "YEN"]);

		for (const themeName of customThemeNames) {
			expect(manifestThemes.has(themeName)).toBe(true);
			const themePath = join(customThemesDir, themeName);
			const content = readFileSync(themePath, "utf8");
			const { audit } = normalizeThemeContent(content);

			expect(audit.foregroundRatio).toBeGreaterThanOrEqual(4.5);
			expect(audit.cursorRatio).toBeGreaterThanOrEqual(3);
			expect(audit.cursorTextRatio).toBeGreaterThanOrEqual(3);
			expect(audit.selectionTextRatio).toBeGreaterThanOrEqual(4.5);
			expect(audit.selectionBackgroundRatio).toBeGreaterThanOrEqual(3);
		}
	});

	test("the native bundler owns full curated-catalog normalization and fails closed", () => {
		const bundler = readFileSync(
			join(repoRoot, "scripts/lib/bundle-resource-phases/01-themes.sh"),
			"utf8",
		);

		expect(bundler).toContain(
			'BUNDLED_THEMES_DIR="$YEN_TERMINAL_DIR/ghostty/zig-out/share/yen/themes"',
		);
		expect(bundler).toContain('echo "$theme_name" >> "$MANIFEST_MISSING_FILE"');
		expect(bundler).toContain('if [ -s "$MANIFEST_MISSING_FILE" ]; then');
		expect(bundler).toContain(
			'normalize_theme_copy_manifest "$CURATED_THEME_COPY_PLAN_FILE"',
		);
		expect(bundler).toContain(
			'node "$THEME_CONTRAST_SCRIPT" normalize-manifest "$manifest_path"',
		);
	});
});
