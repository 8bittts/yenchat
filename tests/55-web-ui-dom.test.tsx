import { afterEach, beforeEach, describe, expect, mock, test } from "bun:test";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";
import React, { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";

const trackedEvents: Array<{
	event: string;
	payload?: Record<string, unknown> | undefined;
}> = [];
const themeChanges: string[] = [];

let resolvedTheme = "light";
let prefersReducedMotion = false;

mock.module("@vercel/analytics", () => ({
	track: (event: string, payload?: Record<string, unknown>) => {
		trackedEvents.push({ event, payload });
	},
}));

mock.module("next/image", () => ({
	default: (props: Record<string, unknown>) =>
		React.createElement("img", props),
}));

mock.module("next/link", () => ({
	default: React.forwardRef<
		HTMLAnchorElement,
		React.AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }
	>(({ href, children, ...props }, ref) => (
		<a ref={ref} href={href} {...props}>
			{children}
		</a>
	)),
}));

mock.module("next-themes", () => ({
	useTheme: () => ({
		resolvedTheme,
		setTheme: (nextTheme: string) => {
			themeChanges.push(nextTheme);
			resolvedTheme = nextTheme;
		},
	}),
}));

const { Header } = await import("@/components/shared/header");
const { DocPageShell } = await import("@/components/docs/doc-page-shell");
const { HomeClient } = await import("@/app/home-client");
const { TunesClient } = await import("@/app/tunes/tunes-client");
const { DocsPageClient } = await import("@/app/docs/docs-client");
const { TermsPageClient } = await import("@/app/terms/terms-client");
const { LibraryClient } = await import("@/app/library/library-client");
const { NotFoundClient } = await import("@/app/not-found-client");
const { default: ReleaseNotesPage } = await import("@/app/blog/releases/page");
const { default: BlogIndexPage } = await import("@/app/blog/page");
const { getBlogPosts } = await import("@/lib/blog");
const { RELEASE_WEEKS } = await import(
	"@/lib/release-notes/release-notes-data"
);
const { default: GlobalError } = await import("@/app/global-error");
const { PublicLibraryPage } = await import(
	"@/components/library/public-library-page"
);
const { getAlternativePage, getUseCasePage } = await import(
	"@/lib/library/public-pages"
);

let dom: JSDOM;
let root: Root | null = null;

const noop = () => {
	/* noop */
};

function installDom(url = "https://yen.chat/") {
	dom = new JSDOM("<!doctype html><html><body></body></html>", {
		url,
	});

	const { window } = dom;

	Object.assign(globalThis, {
		document: window.document,
		Element: window.Element,
		HTMLElement: window.HTMLElement,
		HTMLAnchorElement: window.HTMLAnchorElement,
		HTMLButtonElement: window.HTMLButtonElement,
		MouseEvent: window.MouseEvent,
		Node: window.Node,
		SVGElement: window.SVGElement,
		window,
	});

	Object.defineProperty(globalThis, "navigator", {
		configurable: true,
		value: window.navigator,
	});

	Object.defineProperty(globalThis, "IS_REACT_ACT_ENVIRONMENT", {
		configurable: true,
		value: true,
	});

	window.matchMedia = ((query: string) => ({
		matches:
			prefersReducedMotion && query === "(prefers-reduced-motion: reduce)",
		media: query,
		onchange: null,
		addEventListener: noop,
		addListener: noop,
		dispatchEvent() {
			return false;
		},
		removeEventListener: noop,
		removeListener: noop,
	})) as typeof window.matchMedia;

	window.open = (() => null) as typeof window.open;

	Object.defineProperty(window.HTMLElement.prototype, "scrollIntoView", {
		configurable: true,
		value: noop,
	});

	class TestIntersectionObserver {
		disconnect = noop;
		observe = noop;
		unobserve = noop;
	}

	Object.assign(globalThis, {
		IntersectionObserver: TestIntersectionObserver,
		requestAnimationFrame: (callback: FrameRequestCallback) =>
			setTimeout(() => callback(Date.now()), 0),
		cancelAnimationFrame: (handle: number) => clearTimeout(handle),
	});
}

async function render(ui: React.ReactNode) {
	const container = document.createElement("div");
	document.body.appendChild(container);
	root = createRoot(container);
	await act(async () => {
		root?.render(ui);
		await new Promise((resolve) => setTimeout(resolve, 0));
	});
	return container;
}

async function click(element: Element | null) {
	expect(element).toBeTruthy();
	await act(async () => {
		element?.dispatchEvent(
			new dom.window.MouseEvent("click", {
				bubbles: true,
				cancelable: true,
			}),
		);
		await Promise.resolve();
	});
}

beforeEach(() => {
	trackedEvents.length = 0;
	themeChanges.length = 0;
	resolvedTheme = "light";
	prefersReducedMotion = false;
	installDom();
});

afterEach(async () => {
	if (root) {
		await act(async () => {
			root?.unmount();
			await Promise.resolve();
		});
		root = null;
	}
	dom.window.close();
});

describe("web client UI smoke", () => {
	test("Header marks the current page, toggles mobile navigation, and flips theme state", async () => {
		const mobileNavStates: boolean[] = [];
		resolvedTheme = "dark";

		await render(
			<Header
				currentPage="docs"
				mobileNavOpen={false}
				onMobileNavToggle={(open) => mobileNavStates.push(open)}
			/>,
		);

		const docsLink = document.querySelector(
			'a[href="/docs"][aria-current="page"]',
		);
		expect(docsLink?.textContent).toBe("Docs");

		await click(
			document.querySelector('button[aria-label="Toggle navigation menu"]'),
		);
		expect(mobileNavStates).toEqual([true]);

		await click(
			document.querySelector('button[aria-label="Switch to light mode"]'),
		);
		expect(themeChanges).toEqual(["light"]);
		expect(trackedEvents).toContainEqual({
			event: "theme_toggle",
			payload: { theme: "light" },
		});
	});

	test("DocPageShell with a site origin points every internal header and footer link at it", async () => {
		await render(
			<DocPageShell siteOrigin="https://yen.chat" navItems={[]}>
				<p>Post</p>
			</DocPageShell>,
		);

		const internalHrefs = [
			...document.querySelectorAll("header a, footer a, #mobile-site-nav a"),
		]
			.map((link) => link.getAttribute("href") ?? "")
			.filter((href) => href.startsWith("/") || href.includes("yen.chat"));
		expect(internalHrefs).toEqual([
			"https://yen.chat/",
			"https://yen.chat/docs",
			"https://yen.chat/docs",
			"https://blog.yen.chat/",
			"https://yen.chat/tunes",
			"https://yen.chat/terms",
		]);
	});

	test("blog pages render the shared shell with the yen.chat origin", () => {
		for (const file of [
			"app/blog/page.tsx",
			"app/blog/[slug]/page.tsx",
			"app/blog/releases/page.tsx",
		]) {
			expect(readFileSync(file, "utf8")).toContain("siteOrigin={SITE_URL}");
		}
	});

	test("HomeClient honors reduced motion and renders stable release links", async () => {
		prefersReducedMotion = true;

		await render(<HomeClient version="1.032" />);
		expect(document.body.textContent).not.toContain("Summarize via AI:");

		expect(document.body.textContent).toContain(
			"Quit, crash, update. Your terminal keeps running.",
		);
		expect(document.querySelector("h1")?.textContent).toBe(
			"Quit, crash, update. Your terminal keeps running.",
		);
		expect(document.querySelector("h1")?.className).toContain("sr-only");
		expect(document.body.textContent).toContain(
			"Speech-to-text in any app. No AI required.",
		);
		expect(
			document.querySelector('[data-layout-reserve="terminal-demo"]')
				?.textContent,
		).toContain("Speech-to-text in any app. No AI required.");
		// The hero heading deliberately does NOT reserve its final height — see
		// _docs/10-gtm.md "Hero typewriter". A reserve was tried and reverted: it
		// removes a 75px post-hydration shift but leaves the full title's height
		// (240px at narrow widths) blank above the fold for the whole animation,
		// which reads as broken. The growth IS the effect.
		expect(
			document.querySelector('[data-layout-reserve="hero-title"]'),
		).toBeNull();
		expect(document.body.textContent).toContain("v1.032");

		const shaLink = Array.from(document.querySelectorAll("a")).find((link) =>
			link.textContent?.includes("SHA256"),
		);
		expect(shaLink?.getAttribute("href")).toBe("/stable/yen-1032.dmg.sha256");
	});

	test("static page trees stay Server Components", () => {
		// These pages carry no hooks, handlers, or browser APIs. Marking any of
		// them "use client" ships its whole static tree to the browser a second time
		// as a hydratable chunk — the release notes once re-shipped every week for two
		// analytics onClicks. The interactive leaves (DocPageShell, TerminalCodeBlock,
		// TrackedDownloadLink) carry their own directives, so nothing here needs one.
		// Nothing else guards this: re-adding the directive, or inlining `track` or a
		// hook, silently re-clientises the tree with every other suite still green.
		for (const relativePath of [
			"app/docs/docs-client.tsx",
			"app/yeni/yeni-client.tsx",
			"app/blog/releases/page.tsx",
			"app/blog/page.tsx",
		]) {
			const source = readFileSync(relativePath, "utf8");
			expect(source).not.toMatch(/^\s*["']use client["']/);
			expect(source).not.toContain("@vercel/analytics");
			expect(source).not.toContain("product-analytics");
		}
	});

	test("TunesClient honors reduced motion and renders the video embed plus platform icons", async () => {
		prefersReducedMotion = true;

		await render(<TunesClient />);

		expect(document.body.textContent).toContain("Terminals and Tunes");
		expect(document.body.textContent).toContain("Terminals & Tunes");
		expect(document.querySelector("h1")?.textContent).toBe(
			"Music for coding, focus, and the beautifully quiet hours between builds.",
		);
		// /tunes has its own typewriter hero and used the SAME data-layout-reserve
		// attribute as home, so the reserve must be pinned absent here too — see
		// _docs/10-gtm.md "Hero typewriter". Guarding only the home test would let
		// the reserve be reintroduced on /tunes with the suite still green.
		expect(
			document.querySelector('[data-layout-reserve="hero-title"]'),
		).toBeNull();
		expect(document.body.textContent).toContain(
			"YEN would not exist if it weren't for music.",
		);
		expect(document.body.textContent).toContain("Listen Now");
		expect(document.querySelector("iframe")?.getAttribute("src")).toContain(
			"youtube-nocookie.com/embed/AyTMFhww7uo",
		);
		expect(document.querySelector("iframe")?.getAttribute("loading")).toBe(
			"lazy",
		);
		const listenNowLink = Array.from(document.querySelectorAll("a")).find(
			(link) => link.textContent?.includes("Listen Now"),
		);
		expect(listenNowLink?.getAttribute("href")).toBe(
			"https://www.youtube.com/watch?v=AyTMFhww7uo",
		);
		expect(listenNowLink?.className).toContain("btn-primary");
		expect(document.querySelector('a[aria-label="Listen on YouTube"]')).toBe(
			listenNowLink ?? null,
		);
		expect(
			document.querySelector('a[aria-label*="Spotify"], a[href*="spotify"]'),
		).toBeNull();
		expect(
			document.querySelectorAll('button[aria-label$="is not available yet"]'),
		).toHaveLength(3);
		expect(document.body.textContent).not.toContain("Summarize via AI:");
	});

	test("DocsPageClient opens the mobile docs nav from the shared header toggle", async () => {
		await render(
			<DocsPageClient
				navItems={[
					{ id: "install", title: "Install" },
					{ id: "commands", title: "Commands" },
				]}
			/>,
		);

		expect(document.body.textContent).not.toContain("Summarize via AI:");
		expect(document.getElementById("terminal-history")).toBeNull();
		expect(
			document
				.getElementById("install")
				?.contains(document.getElementById("requirements")),
		).toBe(true);
		expect(document.getElementById("terminal-ide")?.textContent).toContain(
			"Local Git changes",
		);
		const anchors = Array.from(
			document.querySelectorAll<HTMLAnchorElement>('a[href^="#"]'),
		);
		expect(anchors.length).toBeGreaterThan(0);
		for (const anchor of anchors) {
			expect(document.getElementById(anchor.hash.slice(1))).not.toBeNull();
		}
		expect(
			document.getElementById("ide-workflows")?.querySelector("details summary")
				?.textContent,
		).toContain("Workflow commands");
		expect(
			document.querySelector(
				'nav[aria-label="Documentation table of contents"]',
			)?.textContent,
		).toContain("Install");

		await click(
			document.querySelector('button[aria-label="Toggle navigation menu"]'),
		);

		const mobileDocNav = document.getElementById("mobile-doc-nav");
		expect(mobileDocNav?.textContent).toContain("Install");
		expect(mobileDocNav?.textContent).toContain("Commands");
	});
});

describe("public web surface render smoke", () => {
	const navItems = [
		{ id: "intro", title: "Intro" },
		{ id: "details", title: "Details" },
	];

	test("combined terms and privacy page renders a heading and content", async () => {
		await render(
			<TermsPageClient navItems={navItems} lastUpdated="August 20, 2026" />,
		);
		expect(document.querySelector("h1")).toBeTruthy();
		expect(document.body.textContent?.toLowerCase()).toContain("privacy");
		expect(document.body.textContent?.toLowerCase()).toContain("terms");
		expect(document.body.textContent).toContain(
			"Last updated: August 20, 2026",
		);
		expect(document.body.textContent).toContain("support@yen.chat");
	});

	test("terms legal page renders license copy", async () => {
		await render(
			<TermsPageClient navItems={navItems} lastUpdated="August 20, 2026" />,
		);
		expect(document.querySelector("h1")).toBeTruthy();
		expect(document.body.textContent).toContain(
			"YEN is open source under the MIT License.",
		);
		expect(document.body.textContent).not.toContain("not publicly available");
		expect(
			document.querySelector(
				'a[href="https://github.com/8bittts/yenchat/blob/main/LICENSE"]',
			),
		).toBeTruthy();
		expect(document.body.textContent).toContain(
			"Last updated: August 20, 2026",
		);
	});

	test("library index renders its H1 and skip link", async () => {
		await render(<LibraryClient sections={[]} />);
		expect(document.querySelector("h1")?.textContent).toBe("Page library");
		expect(document.querySelector('a[href="#main-content"]')).toBeTruthy();
		expect(document.querySelector("main")?.id).toBe("main-content");
	});

	test("release notes render shared landmarks and both download CTAs", async () => {
		await render(<ReleaseNotesPage />);

		// The page leads with the newest public build. tests/121 owns the rule
		// that it is the shipped build unless RELEASE_EXCLUDE drops that build.
		const newestPublicVersion = RELEASE_WEEKS[0]?.latestVersion ?? "";
		const downloadLinks = Array.from(
			document.querySelectorAll<HTMLAnchorElement>(
				'a[href="https://yen.chat/download"]',
			),
		);

		expect(document.querySelector("h1")?.textContent).toBe(
			"What changed in YEN",
		);
		// Old yen.chat/release#w-<iso> links survive the redirect on these anchors.
		for (const week of RELEASE_WEEKS) {
			expect(document.getElementById(`w-${week.iso}`)).toBeTruthy();
		}
		// A week links the creator's posts from that week; the index links back.
		const postLinks = Array.from(
			document.querySelectorAll<HTMLAnchorElement>("main a"),
		).filter((link) =>
			getBlogPosts().some(
				(post) => link.getAttribute("href") === `/${post.slug}`,
			),
		);
		expect(postLinks.length).toBeGreaterThan(20);
		expect(document.body.textContent).toContain("From the creator this week:");
		expect(document.querySelector('a[href="#main-content"]')).toBeTruthy();
		expect(document.querySelector("main")?.id).toBe("main-content");
		// Nav is grouped by month (the page itself is grouped by week); labels
		// look like "Jul 2026". Assert the shape, not a specific month, so the
		// test stays stable as history grows.
		expect(
			document.querySelector(
				'nav[aria-label="Documentation table of contents"]',
			)?.textContent,
		).toMatch(/[A-Z][a-z]{2} \d{4}/);
		expect(document.querySelector(".lg\\:docs-sidebar-fixed")).toBeTruthy();
		const releaseNavLinks = Array.from(
			document.querySelectorAll<HTMLAnchorElement>(
				'nav[aria-label="Documentation table of contents"] a[href^="#"]',
			),
		);
		expect(releaseNavLinks.length).toBeGreaterThan(5);
		for (const link of releaseNavLinks) {
			expect(document.getElementById(link.hash.slice(1))).toBeTruthy();
		}
		expect(newestPublicVersion).toMatch(/^\d+(\.\d+)+$/);
		expect(document.body.textContent).toContain(newestPublicVersion);
		expect(downloadLinks).toHaveLength(2);

		await click(
			document.querySelector('button[aria-label="Toggle navigation menu"]'),
		);
		const mobileReleaseNav = document.getElementById("mobile-doc-nav");
		expect(mobileReleaseNav?.textContent).toMatch(/[A-Z][a-z]{2} \d{4}/);
		await click(mobileReleaseNav?.querySelector('a[href="#try-yen"]') ?? null);
		expect(document.getElementById("mobile-doc-nav")).toBeNull();

		for (const link of downloadLinks) {
			link.addEventListener("click", (event) => event.preventDefault());
		}
		await click(downloadLinks[0] ?? null);
		await click(downloadLinks[1] ?? null);
		expect(trackedEvents).toContainEqual({
			event: "download_click",
			payload: { location: "release-hero" },
		});
		expect(trackedEvents).toContainEqual({
			event: "download_click",
			payload: { location: "release-footer" },
		});
	});

	test("blog index lists every post and every release week once, each labeled by kind", async () => {
		await render(<BlogIndexPage />);

		const articles = Array.from(document.querySelectorAll("main article"));
		const eyebrows = articles.map(
			(article) => article.querySelector(".eyebrow-text")?.textContent ?? "",
		);
		const posts = getBlogPosts();
		expect(articles).toHaveLength(posts.length + RELEASE_WEEKS.length);
		expect(
			eyebrows.filter((text) => text.startsWith("From the creator · ")),
		).toHaveLength(posts.length);
		expect(eyebrows.filter((text) => text === "Release notes")).toHaveLength(
			RELEASE_WEEKS.length,
		);

		// The index never repeats a week's story: it links to it on /releases.
		const weekHrefs = Array.from(
			document.querySelectorAll<HTMLAnchorElement>(
				'main a[href^="/releases#w-"]',
			),
		).map((link) => link.getAttribute("href"));
		expect(new Set(weekHrefs).size).toBe(RELEASE_WEEKS.length);
		for (const week of RELEASE_WEEKS) {
			expect(document.body.textContent).not.toContain(
				week.summary.slice(0, 80),
			);
		}
		expect(document.querySelector('a[href="/releases"]')).toBeTruthy();
	});

	test("not-found page renders without throwing", async () => {
		await render(<NotFoundClient />);
		expect(document.querySelector("h1")).toBeTruthy();
	});

	test("global-error boundary renders its root document fallback", () => {
		const markup = renderToStaticMarkup(
			<GlobalError error={new Error("boom")} reset={noop} />,
		);
		expect(markup).toContain("<html");
		expect(markup).toContain("Something went wrong");
		expect(markup).toContain("Try again");
		expect(markup).toContain("btn-primary");
	});

	test("pSEO alternative + use-case pages render their H1 and CTA", async () => {
		const alternative = getAlternativePage("warp");
		expect(alternative).toBeTruthy();
		if (alternative) {
			await render(<PublicLibraryPage page={alternative} relatedPages={[]} />);
			expect(document.querySelector("h1")?.textContent).toBe(alternative.h1);
			// The download link keeps its primary-button styling.
			expect(
				document.querySelector('a.btn-primary[href="/download"]'),
			).toBeTruthy();
			const skip = document.querySelector('a[href="#main-content"]');
			expect(skip).toBeTruthy();
			expect(skip?.textContent).toContain("Skip to main content");

			// PageShell owns mobile-nav state — hamburger must open site nav
			await click(
				document.querySelector('button[aria-label="Toggle navigation menu"]'),
			);
			expect(document.querySelector("#mobile-site-nav")).toBeTruthy();
			expect(
				document.querySelector('#mobile-site-nav a[href="/docs"]'),
			).toBeTruthy();
		}

		const useCase = getUseCasePage("macos-terminal-with-speech-to-text");
		expect(useCase).toBeTruthy();
		if (useCase) {
			await render(<PublicLibraryPage page={useCase} relatedPages={[]} />);
			expect(
				Array.from(document.querySelectorAll("h1")).some(
					(h1) => h1.textContent === useCase.h1,
				),
			).toBe(true);
			expect(
				document.querySelector('a.btn-primary[href="/download"]'),
			).toBeTruthy();
		}
	});
});
