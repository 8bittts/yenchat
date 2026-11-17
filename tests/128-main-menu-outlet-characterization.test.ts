import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();

describe("MainMenu outlet characterization", () => {
	test("MainMenu.xib outlets stay declared on AppDelegate", () => {
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
		const shortcutController = readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/App/AppMenuShortcutController.swift",
			),
			"utf8",
		);

		const outletProperties = [...xib.matchAll(/<outlet property="([^"]+)"/g)]
			.map((match) => match[1])
			.filter((property): property is string =>
				Boolean(property?.startsWith("menu")),
			);

		expect(outletProperties.length).toBeGreaterThan(0);
		expect(new Set(outletProperties).size).toBe(outletProperties.length);

		for (const property of outletProperties) {
			expect(appDelegate).toContain(`var ${property}:`);
		}

		expect(shortcutController).not.toContain("@IBOutlet");
	});
});
