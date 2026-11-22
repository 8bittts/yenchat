import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

// The homepage chapter nav has five two-word labels. On a phone a single
// squeezed row split "Split panes", "Field guide" and "Release log" across two
// lines. Labels must stay whole, and phones get aligned columns instead.

const css = readFileSync("app/globals.css", "utf8");

function mediaBlock(query: string): string {
	const start = css.indexOf(`@media ${query} {`);
	expect(start, `@media ${query}`).toBeGreaterThanOrEqual(0);
	let depth = 0;
	for (let index = css.indexOf("{", start); index < css.length; index++) {
		if (css[index] === "{") depth++;
		if (css[index] === "}" && --depth === 0) {
			return css.slice(start, index + 1);
		}
	}
	return "";
}

describe("homepage chapter nav on phones", () => {
	test("chapter labels never break inside a label", () => {
		expect(mediaBlock("(max-width: 700px)")).toMatch(
			/\.ph-chapters a \{[^}]*white-space: nowrap;/,
		);
	});

	test("phones lay the labels out in aligned columns", () => {
		const phone = mediaBlock("(max-width: 520px)");
		expect(phone).toMatch(/\.ph-chapters \.ph-wrap \{[^}]*display: grid;/);
		expect(phone).toMatch(/grid-template-columns: repeat\(3, max-content\);/);
	});
});
