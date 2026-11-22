import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

// Mobile browsers paint the root background in the safe areas, behind a
// collapsed toolbar, and in overscroll past the footer. The site header and
// footer are always dark, so a light root shows as a pale band below the
// footer and above the header on phones.

const css = readFileSync("app/globals.css", "utf8");
const layout = readFileSync("app/layout.tsx", "utf8");

function ruleBody(selector: string): string {
	const start = css.indexOf(`${selector} {`);
	expect(start, `rule ${selector}`).toBeGreaterThanOrEqual(0);
	const open = css.indexOf("{", start);
	return css.slice(open + 1, css.indexOf("}", open));
}

function declaration(body: string, property: string): string | undefined {
	const match = body.match(new RegExp(`(?:^|[;\\s])${property}:\\s*([^;]+);`));
	return match?.[1]?.trim();
}

function resolveColor(value: string): string {
	const variable = value.match(/^var\((--[\w-]+)\)$/)?.[1];
	if (!variable) {
		return value.toLowerCase();
	}
	const defined = css.match(new RegExp(`${variable}:\\s*([^;]+);`))?.[1];
	expect(defined, `definition of ${variable}`).toBeDefined();
	return resolveColor((defined ?? "").trim());
}

const footerColor = resolveColor(
	declaration(
		ruleBody(".ph-site :is(header.bg-background, footer, #mobile-site-nav)"),
		"--color-background",
	) ?? "",
);

describe("mobile root backdrop", () => {
	test("footer color is a concrete dark color", () => {
		expect(footerColor).toMatch(/^#[0-9a-f]{6}$/);
	});

	test("html and body paint the footer color in every theme", () => {
		for (const selector of ["\thtml", "\tbody"]) {
			const background = declaration(ruleBody(selector), "background-color");
			expect(background, `${selector.trim()} background-color`).toBeDefined();
			expect(resolveColor(background ?? "")).toBe(footerColor);
		}
		expect(css).not.toMatch(/\.dark\s+(?:html|body)\s*\{[^}]*background/);
	});

	test("browser chrome theme-color matches the dark header", () => {
		const constants = readFileSync("app/constants.ts", "utf8");
		const chrome = constants.match(/chrome:\s*"(#[0-9a-fA-F]{6})"/)?.[1];
		expect(chrome?.toLowerCase()).toBe(footerColor);
		expect(layout).toContain(
			'<meta name="theme-color" content={COLORS.chrome} />',
		);
	});
});
