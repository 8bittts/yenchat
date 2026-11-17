import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	getAlternativePage,
	getPublicLibraryPagesByKind,
	getUseCasePage,
	PUBLIC_LIBRARY_PAGES,
} from "../lib/library/public-pages";
import { EXPECTED_COMPETITOR_SLUGS } from "./fixtures/library-slugs";

function readSource(path: string) {
	return readFileSync(join(process.cwd(), path), "utf8");
}

describe("public library page registry", () => {
	test("launches the full researched alternatives set and use cases", () => {
		expect(
			getPublicLibraryPagesByKind("alternative").map((page) => page.slug),
		).toEqual(EXPECTED_COMPETITOR_SLUGS);
		expect(
			getPublicLibraryPagesByKind("use-case").map((page) => page.slug),
		).toEqual([
			"macos-terminal-with-speech-to-text",
			"terminal-with-native-browser-preview",
			"terminal-git-diff-drawer",
			"terminal-ide-local-workflows",
			"privacy-focused-ai-terminal",
			"fast-gpu-terminal-for-macos",
		]);
	});

	test("keeps every public page evidence-backed and non-comparative where data is missing", () => {
		const blockedLanguage = [
			"best terminal",
			"fastest terminal",
			"beats ",
			"cheaper than",
			"more private than",
			"officially endorsed",
		];

		for (const page of PUBLIC_LIBRARY_PAGES) {
			const publicText = [
				page.h1,
				page.summary,
				page.seo.title,
				page.seo.description,
				...page.yenProofPoints.map((point) => point.text),
				...page.decisionPoints.map((point) => point.text),
			]
				.join(" ")
				.toLowerCase();

			for (const phrase of blockedLanguage) {
				expect(
					publicText,
					`${page.path} blocked phrase ${phrase}`,
				).not.toContain(phrase);
			}
			expect(page.conversionLinks.length, page.path).toBeGreaterThanOrEqual(2);
			expect(
				page.conversionLinks.some((link) => link.href === "/docs"),
				page.path,
			).toBe(true);
			expect(
				page.conversionLinks.some((link) => link.href === "/download"),
				page.path,
			).toBe(true);
		}
	});

	test("resolves pages by slug without exposing private workbench paths", () => {
		expect(getAlternativePage("warp")?.path).toBe("/alternatives/warp");
		expect(getUseCasePage("terminal-git-diff-drawer")?.path).toBe(
			"/use-cases/terminal-git-diff-drawer",
		);
		expect(getAlternativePage("library")).toBeUndefined();
		expect(
			PUBLIC_LIBRARY_PAGES.some((page) => page.path.includes("/library")),
		).toBe(false);
	});

	test("finite public page families prerender every eligible registry slug", () => {
		for (const route of [
			"app/alternatives/[slug]/page.tsx",
			"app/use-cases/[slug]/page.tsx",
		]) {
			const source = readSource(route);
			expect(source).not.toContain('export const dynamic = "force-dynamic"');
			expect(source).toContain("export const dynamicParams = false");
			expect(source).toContain("getPublicLibraryPagesByKind");
			expect(source).toContain("slug: page.slug");
			expect(source).not.toContain("LIBRARY_COMPETITORS");
			expect(source).not.toContain("LIBRARY_TOPIC_CLUSTERS");
		}
	});

	test("shared PageShell provides the skip-link + main-content landmark", () => {
		// The skip-link and main#main-content landmark live in the shared
		// PageShell; public pages inherit them by rendering it rather than
		// duplicating the markup inline.
		const shell = readSource("components/shared/page-shell.tsx");
		expect(shell).toContain('href="#main-content"');
		expect(shell).toContain('id="main-content"');
	});

	test("shared public page shell exposes landmark and source affordances", () => {
		const source = readSource("components/library/public-library-page.tsx");
		expect(source).toContain("<PageShell");
		expect(source).toContain("aria-labelledby");
		expect(source).toContain('aria-label="Related public pages"');
		expect(source).toContain('scope="row"');
		expect(source).not.toContain("style={{");
		expect(source).not.toMatch(/#[0-9a-fA-F]{3,8}/);
	});

	test("public hubs expose labeled landmark sections", () => {
		const source = readSource("components/library/public-library-hub.tsx");
		expect(source).toContain("<PageShell");
		expect(source).toContain('aria-labelledby="public-page-index"');
		expect(source).toContain('id="public-page-index"');
		expect(source).toContain('aria-labelledby="quality-gate"');
		expect(source).toContain('id="quality-gate"');
		expect(source).not.toContain("style={{");
		expect(source).not.toMatch(/#[0-9a-fA-F]{3,8}/);
	});
});
