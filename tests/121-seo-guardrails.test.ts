import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import robots from "../app/robots";
import sitemap from "../app/sitemap";
import { blogUrlForMainHostPath } from "../lib/http/blog-host";
import { RETIRED_PAGES } from "../lib/http/retired-pages";
import { RELEASE_EXCLUDE } from "../lib/release-notes/release-notes-copy";
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
		expect(firstScreen).toContain("[Documentation](https://yen.chat/#guide)");
		expect(firstScreen).not.toContain(
			"[Alternatives](https://yen.chat/alternatives)",
		);
		expect(firstScreen).not.toContain(
			"[Use cases](https://yen.chat/use-cases)",
		);
		expect(firstScreen).toContain("[Download](https://yen.chat/download)");
		expect(firstScreen).toContain("[Terms & Privacy](https://yen.chat/terms)");
		expect(firstScreen).toContain("[Blog](https://blog.yen.chat/)");
		expect(firstScreen).toContain("[Contact](https://twitter.com/yenFTW)");
		expect(firstScreen).not.toContain("https://yen.chat/library");

		for (const path of RETIRED_PAGES) {
			const assertion = expect(llmsText, path);
			const url = `https://yen.chat${path}`;
			assertion.not.toContain(url);
		}
	});

	test("sitemap is deterministic and includes only public eligible URLs", () => {
		const sitemapEntries = sitemap();
		const urls = sitemapEntries.map((entry) => entry.url);

		expect(new Set(urls).size).toBe(urls.length);
		expect(urls).toEqual(["https://yen.chat", "https://yen.chat/terms"]);
		expect(urls.some((url) => url.includes("/library"))).toBe(false);

		for (const entry of sitemapEntries) {
			expect(entry.url).toMatch(/^https:\/\/yen\.chat(\/|$)/);
			expect(entry.url).not.toContain("www.");
		}
	});

	test("release notes live on the blog and the retired /release redirects there", () => {
		const pageSource = readFileSync(
			join(process.cwd(), "app", "blog", "releases", "page.tsx"),
			"utf8",
		);
		const sitemapUrls = sitemap().map((entry) => entry.url);

		// The release notes are a blog page with their own metadata and the shared shell.
		expect(existsSync(join(process.cwd(), "app", "release"))).toBe(false);
		expect(Object.hasOwn(PUBLIC_PAGE_SEO, "release")).toBe(false);
		expect(pageSource).toContain("buildPublicPageMetadata");
		expect(pageSource).toContain("url: `${BLOG_URL}${RELEASES_PATH}`");
		expect(blogUrlForMainHostPath("/release")).toBe(
			"https://blog.yen.chat/releases",
		);
		expect(blogUrlForMainHostPath("/release/")).toBe(
			"https://blog.yen.chat/releases",
		);

		// yen.chat's own sitemap, llms.txt and chrome never point at the retired page.
		expect(sitemapUrls).not.toContain("https://yen.chat/release");
		for (const file of [
			join("components", "shared", "header.tsx"),
			join("components", "shared", "footer.tsx"),
		]) {
			const source = readFileSync(join(process.cwd(), file), "utf8");
			expect(source).not.toContain('href="/release"');
			expect(source).not.toContain('href="/releases"');
		}
		expect(
			readFileSync(
				join(process.cwd(), "components", "shared", "header.tsx"),
				"utf8",
			),
		).not.toContain('href="/tunes"');
		expect(
			readFileSync(join(process.cwd(), "public", "llms.txt"), "utf8"),
		).not.toContain("https://yen.chat/release");
		// The GitHub Release body each build publishes links the blog page.
		expect(
			readFileSync(
				join(
					process.cwd(),
					"scripts",
					"lib",
					"finalize-build-phases",
					"06-upload.sh",
				),
				"utf8",
			),
		).toContain('"Release notes: https://blog.yen.chat/releases"');
	});

	test("shared header and footer list their links in chrome order", () => {
		// Visible text of every <a> or <Link> in a component, in source order; the
		// logo link holds only an image and a span, so it yields no label.
		const linkLabels = (file: string) =>
			[
				...readFileSync(
					join(process.cwd(), "components", "shared", file),
					"utf8",
				).matchAll(/>\s*([^<>{}]+?)\s*<\/(?:a|Link)>/g),
			]
				.map((match) => match[1]?.trim())
				.filter(Boolean);
		const footerSource = readFileSync(
			join(process.cwd(), "components", "shared", "footer.tsx"),
			"utf8",
		);
		const headerSource = readFileSync(
			join(process.cwd(), "components", "shared", "header.tsx"),
			"utf8",
		);

		expect(linkLabels("header.tsx")).toEqual([
			"Docs",
			"GitHub",
			"@yenFTW",
			"Docs",
			"GitHub",
			"@yenFTW",
		]);
		expect(linkLabels("footer.tsx")).toEqual(["Blog", "Email", "Terms"]);
		expect(headerSource).toMatch(
			/href="https:\/\/github\.com\/8bittts\/yenchat"[\s\S]*target="_blank"[\s\S]*rel="noopener noreferrer"/,
		);
		expect(headerSource).toContain("https://twitter.com/yenFTW");
		expect(footerSource).not.toContain("github.com");
		for (const href of ["https://blog.yen.chat/", "https://btc.email"]) {
			expect(footerSource).toMatch(
				new RegExp(
					`href="${href.replace(/[.?/]/g, "\\$&")}"\\s*className="[^"]*"\\s*target="_blank"\\s*rel="noopener noreferrer"`,
				),
			);
		}
		expect(footerSource).not.toContain("jpthecat.com");
	});

	test("week-grouped release history covers the current build and holds public-copy guardrails", () => {
		// blog.yen.chat/releases renders the generated, week-grouped dataset — that
		// file (not the page) is where the real changelog copy lives, so the
		// guardrails must scan it. See scripts/gen-release-notes.ts and
		// _docs/10-gtm.md → "Release Notes".
		const clientSource = readFileSync(
			join(process.cwd(), "app", "blog", "releases", "page.tsx"),
			"utf8",
		);
		const dataSource = readFileSync(
			join(process.cwd(), "lib", "release-notes", "release-notes-data.ts"),
			"utf8",
		);
		const currentVersion = JSON.parse(
			readFileSync(
				join(process.cwd(), "public", "stable", "version.json"),
				"utf8",
			),
		).version as string;

		// Renderer imports the generated data and is grouped by release week.
		expect(clientSource).toContain(
			'from "@/lib/release-notes/release-notes-data"',
		);
		expect(clientSource).toContain("RELEASE_WEEKS");
		expect(dataSource).toContain('"label": "Week of ');
		expect(dataSource).toContain(
			'"label": "Week of Jun 29–Jul 5, 2026",\n\t\t"month": "Jul 2026"',
		);

		// The public voice comes from the hand-curated copy layer, merged by the
		// generator over the terse commit summary (see _docs/10-gtm.md).
		const copySource = readFileSync(
			join(process.cwd(), "lib", "release-notes", "release-notes-copy.ts"),
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

	test("each retired URL redirects with its query intact and unknown slugs stay unknown", () => {
		for (const path of RETIRED_PAGES) {
			const response = proxy(
				new NextRequest(`https://yen.chat${path}?ref=bookmark`),
			);
			expect(response.status, path).toBe(308);
			expect(response.headers.get("location"), path).toBe(
				"https://yen.chat/?ref=bookmark",
			);
		}
		expect(
			proxy(
				new NextRequest("https://yen.chat/alternatives/missing-bookmark"),
			).headers.get("location"),
		).toBeNull();
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
