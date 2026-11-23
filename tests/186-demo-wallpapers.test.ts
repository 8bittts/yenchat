import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";

// The app's Demo button downloads clips by name from yen.chat/videos, which
// serves public/videos. A clip renamed or removed on one side only makes Demo
// fail for some presses, so the two lists must stay equal.

const swift = readFileSync(
	"yen-terminal/overlays/macos/Sources/Features/MovingWallpaper/DemoWallpapers.swift",
	"utf8",
);

function appClipNames(): string[] {
	const list = swift.match(/static let fileNames = \[([^\]]*)\]/)?.[1] ?? "";
	return [...list.matchAll(/"([^"]+)"/g)].map((match) => match[1] ?? "");
}

describe("demo wallpapers", () => {
	test("the app lists demo clips", () => {
		expect(appClipNames().length).toBeGreaterThan(1);
	});

	test("the app's clip list equals public/videos", () => {
		const served = readdirSync("public/videos")
			.filter((name) => !name.startsWith("."))
			.sort();
		expect(appClipNames().sort()).toEqual(served);
	});

	test("the app downloads from the site that serves public/videos", () => {
		expect(swift).toContain('URL(string: "https://yen.chat/videos/")');
	});
});
