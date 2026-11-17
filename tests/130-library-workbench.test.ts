import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import sitemap from "../app/sitemap";
import { getLibrarySeoInventory } from "../lib/library/seo-inventory";
import { PUBLIC_PAGE_SEO } from "../lib/seo";

function readSource(path: string) {
	return readFileSync(join(process.cwd(), path), "utf8");
}

describe("private library workbench", () => {
	test("renders a direct page inventory while staying noindex and unlinked", () => {
		const source = readSource("app/library/page.tsx");
		const clientSource = readSource("app/library/library-client.tsx");
		expect(source).toContain("YEN Page Library");
		expect(source).toContain("NOINDEX_ROBOTS");
		expect(source).toContain("export const metadata");
		expect(clientSource).toContain("Page library");
		expect(source).toContain("getLibrarySeoInventory");
		// Standard chrome (Header + Footer) is provided by the shared PageShell,
		// not imported directly — confirms this is a normal page, not a bare workbench.
		expect(clientSource).toContain("PageShell");
		expect(source).toContain('page.path !== "/whitepaper.pdf"');
		expect(clientSource).not.toContain("<Link");
		expect(clientSource).not.toContain("prefetch={false}");
		expect(clientSource).not.toContain("aria-label={`Open ${page.title}`}");
		expect(clientSource).not.toContain("Workbench status");
		expect(clientSource).not.toContain("Next candidates");
		expect(clientSource).not.toContain("Private noindex workbench");
		expect(clientSource).not.toContain("whitepaper");
		expect(source).not.toContain("notFound()");
		expect(source).not.toContain("headers()");
		expect(source).not.toContain("YEN_LIBRARY_WORKBENCH_ENABLED");
	});

	test("stays out of public SEO discovery while private", () => {
		const sitemapUrls = sitemap().map((entry) => entry.url);
		expect(sitemapUrls.some((url) => url.includes("/library"))).toBe(false);
		expect(Object.keys(PUBLIC_PAGE_SEO)).not.toContain("library");
		expect(readSource("components/shared/header.tsx")).not.toContain(
			'href="/library"',
		);
		expect(readSource("components/shared/footer.tsx")).not.toContain(
			'href="/library"',
		);
		expect(readSource("components/shared/footer.tsx")).not.toContain(
			'href="/alternatives"',
		);
		expect(readSource("components/shared/footer.tsx")).not.toContain(
			'href="/use-cases"',
		);
		expect(readSource("public/llms.txt")).not.toContain(
			"https://yen.chat/library",
		);
	});

	test("tracks every sitemap SEO page without a dormant research queue", () => {
		const inventory = getLibrarySeoInventory();
		const sitemapUrls = sitemap().map((entry) => entry.url);
		const inventoryUrls = inventory.sitemapPages.map(
			(page) => `${inventory.siteUrl}${page.path === "/" ? "" : page.path}`,
		);

		expect(inventory.privateWorkbench.path).toBe("/library");
		expect(inventory.privateWorkbench.indexable).toBe(false);
		expect(inventory.privateWorkbench.sitemapIncluded).toBe(false);
		expect(inventoryUrls).toEqual(sitemapUrls);
		expect(inventory.alternativePages).toHaveLength(15);
		expect(inventory.useCasePages).toHaveLength(6);
		expect("researchQueue" in inventory).toBe(false);
	});

	test("uses route-level noindex metadata", () => {
		const source = readSource("app/library/page.tsx");
		expect(source).toContain("NOINDEX_ROBOTS");
		expect(source).toContain('title: "YEN Page Library"');
		expect(source).toContain('export const dynamic = "force-dynamic"');
	});
});
