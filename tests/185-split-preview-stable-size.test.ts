import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

// Switching the homepage split preview between Comfortable and Compact must
// not change the preview's size, or every section below it jumps. Compact
// may only restyle the panes inside the grid, never the grid box itself.

const css = readFileSync("app/globals.css", "utf8");

const boxProperties =
	/(?:^|[;{\s])(padding|gap|row-gap|column-gap|margin|width|height|min-height|max-height|grid-template-columns|grid-template-rows|border-width|border)\s*:/;

/** Every rule body whose selector list makes `.ph-splits-compact` the styled element. */
function compactContainerRules(): string[] {
	const bodies: string[] = [];
	for (const match of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
		const selectors = (match[1] ?? "").split(",").map((s) => s.trim());
		if (selectors.some((s) => /\.ph-splits-compact$/.test(s))) {
			bodies.push(match[2] ?? "");
		}
	}
	return bodies;
}

describe("split preview size", () => {
	test("the stylesheet styles the compact preview", () => {
		expect(css).toContain(".ph-splits-compact");
	});

	test("Compact never changes the preview grid's own box", () => {
		for (const body of compactContainerRules()) {
			expect(body).not.toMatch(boxProperties);
		}
	});
});
