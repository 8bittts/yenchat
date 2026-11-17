import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { RELEASE_EXCLUDE } from "../app/release/release-notes-copy";
import robots from "../app/robots";
import sitemap from "../app/sitemap";
import {
	getPublicLibrarySitemapEntries,
	isPublicLibraryPageEligible,
	isPublicLibraryPageLlmsDiscoverable,
	PUBLIC_LIBRARY_LAST_MODIFIED,
	PUBLIC_LIBRARY_MIN_EVIDENCE_SCORE,
	PUBLIC_LIBRARY_PAGES,
} from "../lib/library/public-pages";
import {
	buildPublicPageMetadata,
	PUBLIC_PAGE_SEO,
	SEO_DESCRIPTION_MAX_LENGTH,
	SEO_TITLE_MAX_LENGTH,
} from "../lib/seo";
import { proxy } from "../proxy";

describe("public SEO guardrails", () => {
	test("public page titles and descriptions stay concise and canonical", () => {
		const titles = new Set<string>();
		const descriptions = new Set<string>();
		for (const [page, metadata] of Object.entries(PUBLIC_PAGE_SEO)) {
			expect(metadata.title.length, `${page} title`).toBeLessThanOrEqual(
				SEO_TITLE_MAX_LENGTH,
			);
			expect(
				metadata.description.length,
				`${page} description`,
			).toBeLessThanOrEqual(SEO_DESCRIPTION_MAX_LENGTH);
			expect(metadata.url).toMatch(/^https:\/\/yen\.chat(\/|$)/);
			expect(metadata.url).not.toContain("www.");
			expect(titles.has(metadata.title), `${page} title uniqueness`).toBe(
				false,
			);
			expect(
				descriptions.has(metadata.description),
				`${page} description uniqueness`,
			).toBe(false);
			titles.add(metadata.title);
			descriptions.add(metadata.description);

			const pageMetadata = buildPublicPageMetadata(metadata);
			expect(pageMetadata.alternates?.canonical, page).toBe(metadata.url);
			expect(pageMetadata.openGraph?.title, page).toBe(metadata.title);
			expect(pageMetadata.openGraph?.description, page).toBe(
				metadata.description,
			);
			expect(pageMetadata.openGraph?.url, page).toBe(metadata.url);
			expect(pageMetadata.twitter?.title, page).toBe(metadata.title);
			expect(pageMetadata.twitter?.description, page).toBe(
				metadata.description,
			);
		}
	});

	test("robots.txt lets redirect/noindex routes resolve while blocking release artifacts", () => {
		const config = robots();
		expect(config.sitemap).toBe("https://yen.chat/sitemap.xml");
		expect("host" in config).toBe(false);

		const rules = Array.isArray(config.rules) ? config.rules : [config.rules];
		for (const rule of rules) {
			const disallow = Array.isArray(rule.disallow)
				? rule.disallow
				: [rule.disallow].filter(Boolean);
			// No trailing slash so bare /api and /stable (which 404) are also blocked.
			expect(disallow).toContain("/api");
			expect(disallow).toContain("/stable");
			expect(disallow).not.toContain("/download");
			expect(disallow).not.toContain("/cookies");
		}
	});

	test("llms.txt starts with concise Markdown links for agent discovery", () => {
		const llmsText = readFileSync(
			join(process.cwd(), "public", "llms.txt"),
			"utf8",
		);
		const firstScreen = llmsText.split("\n").slice(0, 24).join("\n");

		expect(firstScreen).toContain("[YEN website](https://yen.chat/)");
		expect(firstScreen).toContain("[Documentation](https://yen.chat/docs)");
		expect(firstScreen).toContain(
			"[Alternatives](https://yen.chat/alternatives)",
		);
		expect(firstScreen).toContain("[Use cases](https://yen.chat/use-cases)");
		expect(firstScreen).toContain("[Download](https://yen.chat/download)");
		expect(firstScreen).toContain("[Terms & Privacy](https://yen.chat/terms)");
		expect(firstScreen).toContain("[Blog](https://blog.yen.chat/)");
		expect(firstScreen).toContain("[Contact](https://twitter.com/yenFTW)");
		expect(firstScreen).not.toContain("https://yen.chat/library");

		for (const page of PUBLIC_LIBRARY_PAGES) {
			const assertion = expect(llmsText, page.path);
			const url = `https://yen.chat${page.path}`;
			if (isPublicLibraryPageLlmsDiscoverable(page)) {
				assertion.toContain(url);
			} else {
				assertion.not.toContain(url);
			}
		}
	});

	test("sitemap is deterministic and includes only public eligible URLs", () => {
		const sitemapEntries = sitemap();
		const urls = sitemapEntries.map((entry) => entry.url);
		const expectedPublicLibraryUrls = getPublicLibrarySitemapEntries().map(
			(entry) => entry.url,
		);

		expect(new Set(urls).size).toBe(urls.length);
		expect(urls).toEqual([
			"https://yen.chat",
			"https://yen.chat/docs",
			"https://yen.chat/tunes",
			"https://yen.chat/alternatives",
			"https://yen.chat/use-cases",
			...expectedPublicLibraryUrls,
			"https://yen.chat/whitepaper.pdf",
			"https://yen.chat/terms",
		]);
		expect(urls.some((url) => url.includes("/library"))).toBe(false);

		for (const entry of sitemapEntries) {
			expect(entry.url).toMatch(/^https:\/\/yen\.chat(\/|$)/);
			expect(entry.url).not.toContain("www.");
			expect(entry.lastModified).toBeInstanceOf(Date);
			expect((entry.lastModified as Date).toISOString()).toBe(
				PUBLIC_LIBRARY_LAST_MODIFIED.toISOString(),
			);
		}
	});

	test("release history is indexable but not sitemap- or chrome-linked", () => {
		const pageSource = readFileSync(
			join(process.cwd(), "app", "release", "page.tsx"),
			"utf8",
		);
		const clientSource = readFileSync(
			join(process.cwd(), "app", "release", "release-client.tsx"),
			"utf8",
		);
		const sitemapUrls = sitemap().map((entry) => entry.url);

		expect(PUBLIC_PAGE_SEO.release.url).toBe("https://yen.chat/release");
		expect(pageSource).toContain("buildPublicPageMetadata");
		expect(pageSource).toContain("PUBLIC_PAGE_SEO.release");
		expect(clientSource).toContain("DocPageShell");
		expect(clientSource).toContain("DocSection");
		expect(clientSource).not.toContain('from "@/components/shared/page-shell"');
		// Kept out of the sitemap, llms.txt, and header nav...
		expect(sitemapUrls).not.toContain("https://yen.chat/release");
		expect(
			readFileSync(
				join(process.cwd(), "components", "shared", "header.tsx"),
				"utf8",
			),
		).not.toContain('href="/release"');
		expect(
			readFileSync(
				join(process.cwd(), "components", "shared", "header.tsx"),
				"utf8",
			),
		).not.toContain('href="/tunes"');
		expect(
			readFileSync(join(process.cwd(), "public", "llms.txt"), "utf8"),
		).not.toContain("https://yen.chat/release");
		expect(
			readFileSync(
				join(process.cwd(), "components", "shared", "footer.tsx"),
				"utf8",
			),
		).not.toContain('href="/release"');
	});

	test("shared footer lists brand and legal links in chrome order", () => {
		const footerSource = readFileSync(
			join(process.cwd(), "components", "shared", "footer.tsx"),
			"utf8",
		);

		const onigiriIndex = footerSource.indexOf("Onigiri");
		const musicIndex = footerSource.indexOf("Music");
		const bitcoinIndex = footerSource.indexOf("Bitcoin Email");
		const jpIndex = footerSource.indexOf("JP the Cat");
		const termsIndex = footerSource.indexOf("Terms");

		expect(onigiriIndex).toBeGreaterThan(-1);
		expect(musicIndex).toBeGreaterThan(onigiriIndex);
		expect(bitcoinIndex).toBeGreaterThan(musicIndex);
		expect(jpIndex).toBeGreaterThan(bitcoinIndex);
		expect(termsIndex).toBeGreaterThan(jpIndex);

		expect(footerSource).toContain('href="https://jpthecat.com"');
		expect(footerSource).toContain('item: "JP the Cat"');
		expect(footerSource).toMatch(
			/href="https:\/\/jpthecat\.com"[\s\S]*target="_blank"[\s\S]*rel="noopener noreferrer"/,
		);
	});

	test("yeni character bible has page-local social metadata and stays unlisted", () => {
		const pageSource = readFileSync(
			join(process.cwd(), "app", "yeni", "page.tsx"),
			"utf8",
		);
		const sitemapUrls = sitemap().map((entry) => entry.url);
		const llmsText = readFileSync(
			join(process.cwd(), "public", "llms.txt"),
			"utf8",
		);
		const headerSource = readFileSync(
			join(process.cwd(), "components", "shared", "header.tsx"),
			"utf8",
		);
		const footerSource = readFileSync(
			join(process.cwd(), "components", "shared", "footer.tsx"),
			"utf8",
		);

		expect(PUBLIC_PAGE_SEO.yeni.url).toBe("https://yen.chat/yeni");
		expect(PUBLIC_PAGE_SEO.yeni.image.url).toBe(
			"https://yen.chat/yeni/yeni-canonical-front.png",
		);
		expect(pageSource).toContain("buildPublicPageMetadata");
		expect(pageSource).toContain("PUBLIC_PAGE_SEO.yeni");

		// Direct URL only — not discoverable via sitemap, llms, or chrome links.
		expect(sitemapUrls).not.toContain("https://yen.chat/yeni");
		expect(llmsText).not.toContain("https://yen.chat/yeni");
		expect(headerSource).not.toContain('href="/yeni"');
		expect(footerSource).not.toContain('href="/yeni"');
	});

	test("week-grouped release history covers the current build and holds public-copy guardrails", () => {
		// The /release page renders the generated, week-grouped dataset — that
		// file (not release-client.tsx) is where the real changelog copy lives,
		// so the guardrails must scan it. See scripts/gen-release-notes.ts and
		// _docs/10-gtm.md → "Release Notes Page".
		const clientSource = readFileSync(
			join(process.cwd(), "app", "release", "release-client.tsx"),
			"utf8",
		);
		const dataSource = readFileSync(
			join(process.cwd(), "app", "release", "release-notes-data.ts"),
			"utf8",
		);
		const currentVersion = JSON.parse(
			readFileSync(
				join(process.cwd(), "public", "stable", "version.json"),
				"utf8",
			),
		).version as string;

		// Renderer imports the generated data and is grouped by release week.
		expect(clientSource).toContain('from "./release-notes-data"');
		expect(clientSource).toContain("RELEASE_WEEKS");
		expect(dataSource).toContain('"label": "Week of ');
		expect(dataSource).toContain(
			'"label": "Week of Jun 29–Jul 5, 2026",\n\t\t"month": "Jul 2026"',
		);

		// The public voice comes from the hand-curated copy layer, merged by the
		// generator over the terse commit summary (see _docs/10-gtm.md).
		const copySource = readFileSync(
			join(process.cwd(), "app", "release", "release-notes-copy.ts"),
			"utf8",
		);
		expect(copySource).toContain("RELEASE_COPY");
		expect(copySource).toContain("RELEASE_WEEK_COPY");
		const genSource = readFileSync(
			join(process.cwd(), "scripts", "gen-release-notes.ts"),
			"utf8",
		);
		expect(genSource).toContain("release-notes-copy");

		// The newest shipped build appears in the changelog unless
		// release-notes-copy.ts excludes it with a reason: exactly one holds.
		expect(dataSource.includes(`"${currentVersion}"`)).toBe(
			!Object.hasOwn(RELEASE_EXCLUDE, currentVersion),
		);

		// [HARD REQUIREMENT] no upstream terminal-engine name in public copy.
		expect(dataSource).not.toMatch(/\bGhostty\b/i);
		// Retired runtimes/eras must not surface as current features (GTM rule):
		// chat/mail/calendar plus the mail-era (email/gmail) and weather runtimes.
		expect(dataSource).not.toMatch(
			/\b(chat|mail|email|gmail|calendar|messaging|inbox|weather)\b/i,
		);
		// Every public summary is one weekly story, not one bullet per build.
		// The week count grows. The build count must stay several times larger,
		// so a per-build inventory still fails after the history passes any fixed cap.
		const shippedVersions = dataSource.match(
			/"shippedOn": "\d{4}-\d{2}-\d{2}"/g,
		);
		expect(shippedVersions?.length).toBeGreaterThan(300);
		const summaries = [
			...dataSource.matchAll(/"summary": "((?:[^"\\]|\\.)*)"/g),
		].map((m) => m[1] ?? "");
		expect(summaries.length).toBeGreaterThan(20);
		expect((shippedVersions?.length ?? 0) / summaries.length).toBeGreaterThan(
			4,
		);
		// Weekly product stories need enough room for a theme, concrete changes, and
		// a clear payoff without turning back into exhaustive build inventories.
		const lengths = summaries
			.map((summary) => summary.length)
			.sort((a, b) => a - b);
		const median = lengths[Math.floor(lengths.length / 2)] ?? 0;
		expect(median).toBeGreaterThanOrEqual(220);
		expect(summaries.every((summary) => !summary.includes("!"))).toBe(true);
	});

	test("public library pages have unique concise metadata", () => {
		const paths = new Set<string>();
		const titles = new Set<string>();
		const descriptions = new Set<string>();

		for (const page of PUBLIC_LIBRARY_PAGES) {
			expect(page.publicEligible, page.path).toBe(true);
			expect(page.path).toMatch(/^\/(alternatives|use-cases)\//);
			expect(paths.has(page.path), `${page.path} duplicate path`).toBe(false);
			expect(titles.has(page.seo.title), `${page.path} duplicate title`).toBe(
				false,
			);
			expect(
				descriptions.has(page.seo.description),
				`${page.path} duplicate description`,
			).toBe(false);

			paths.add(page.path);
			titles.add(page.seo.title);
			descriptions.add(page.seo.description);

			expect(page.seo.title.length, `${page.path} title`).toBeLessThanOrEqual(
				SEO_TITLE_MAX_LENGTH,
			);
			expect(
				page.seo.description.length,
				`${page.path} description`,
			).toBeLessThanOrEqual(SEO_DESCRIPTION_MAX_LENGTH);
			expect(page.evidenceScore, page.path).toBeGreaterThanOrEqual(
				PUBLIC_LIBRARY_MIN_EVIDENCE_SCORE,
			);
			expect(isPublicLibraryPageEligible(page), page.path).toBe(true);
			expect(page.yenProofPoints.length, page.path).toBeGreaterThanOrEqual(2);
			expect(page.decisionPoints.length, page.path).toBeGreaterThanOrEqual(3);

			if (page.kind === "alternative") {
				expect(page.officialSources.length, page.path).toBeGreaterThanOrEqual(
					2,
				);
			}
		}
	});

	test("www host redirects permanently to the apex canonical host", () => {
		const response = proxy({
			headers: new Headers({ host: "www.yen.chat" }),
			nextUrl: new URL("https://www.yen.chat/docs?ref=seo"),
			url: "https://www.yen.chat/docs?ref=seo",
		} as never);

		expect(response.status).toBe(308);
		expect(response.headers.get("location")).toBe(
			"https://yen.chat/docs?ref=seo",
		);
	});
});
