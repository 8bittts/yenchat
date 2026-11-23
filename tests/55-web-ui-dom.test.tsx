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
const { PageShell } = await import("@/components/shared/page-shell");
const { HomeClient } = await import("@/app/home-client");
const { ManualChapters } = await import("@/app/docs/docs-client");
const { TermsPageClient } = await import("@/app/terms/terms-client");
const { NotFoundClient } = await import("@/app/not-found-client");
const { default: ReleaseNotesPage } = await import("@/app/blog/releases/page");
const { default: BlogIndexPage } = await import("@/app/blog/page");
const { getBlogWeeks } = await import("@/lib/blog-weeks");
const { RELEASE_WEEKS } = await import(
	"@/lib/release-notes/release-notes-data"
);
const { default: GlobalError } = await import("@/app/global-error");
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
			'a[href="/#guide"][aria-current="page"]',
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

	test("PageShell with a site origin points every internal header and footer link at it", async () => {
		await render(
			<PageShell siteOrigin="https://yen.chat">
				<p>Post</p>
			</PageShell>,
		);

		const internalHrefs = [
			...document.querySelectorAll("header a, footer a, #mobile-site-nav a"),
		]
			.map((link) => link.getAttribute("href") ?? "")
			.filter((href) => href.startsWith("/") || href.includes("yen.chat"));
		expect(internalHrefs).toEqual([
			"https://yen.chat/",
			"https://yen.chat/#guide",
			"https://yen.chat/#guide",
			"https://blog.yen.chat/",
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

	test("Home shows the session lifecycle, focused repository, and current release links", async () => {
		prefersReducedMotion = true;

		await render(<HomeClient version="1.032" />);
		expect(document.body.textContent).not.toContain("Summarize via AI:");

		expect(document.querySelector("h1")?.textContent).toBe(
			"Quit the app. Keep the shell.",
		);
		const button = (name: string) =>
			Array.from(document.querySelectorAll("button")).find(
				(el) => el.textContent === name,
			) ?? null;
		await click(button("Quit YEN"));
		expect(document.body.textContent).toContain("YEN is closed.");
		await click(button("Send request"));
		expect(document.body.textContent).toContain(
			"Request 2 returned 200 OK while YEN was closed.",
		);
		await click(button("Reopen YEN"));
		expect(document.body.textContent).toContain("#02");
		await click(document.querySelector('[aria-label="Focus Server pane"]'));
		const drawer = document.querySelector(".ph-drawer");
		expect(drawer?.textContent).toContain("~/project/api");
		expect(drawer?.textContent).toContain("Keyboard focusServer");
		expect(document.body.textContent).toContain("v1.032");

		const shaLink = Array.from(document.querySelectorAll("a")).find((link) =>
			link.textContent?.includes("SHA256"),
		);
		expect(shaLink?.getAttribute("href")).toBe("/stable/yen-1032.dmg.sha256");
	});

	test("Split preview draws Spark and Aura on the focused pane only, and each toggle removes one", async () => {
		await render(<HomeClient version="1.032" />);
		const pane = (name: string) =>
			document.querySelector(`[aria-label="Focus ${name} pane"]`);
		const slot = (name: string) => pane(name)?.parentElement ?? null;
		const toggle = (name: string) =>
			Array.from(document.querySelectorAll("#splits button")).find(
				(el) => el.textContent === name,
			) ?? null;

		// Both effects start on, and only the focused pane carries them.
		expect(slot("Editor")?.querySelector(".ph-spark")).toBeTruthy();
		expect(slot("Editor")?.classList.contains("ph-aura")).toBe(true);
		expect(slot("Server")?.querySelector(".ph-spark")).toBeNull();
		expect(slot("Server")?.classList.contains("ph-aura")).toBe(false);

		// The effects follow the focus.
		await click(pane("Server"));
		expect(document.querySelectorAll(".ph-spark")).toHaveLength(1);
		expect(slot("Server")?.querySelector(".ph-spark")).toBeTruthy();
		expect(document.querySelectorAll(".ph-aura")).toHaveLength(1);
		expect(slot("Server")?.classList.contains("ph-aura")).toBe(true);

		await click(toggle("Spark"));
		expect(document.querySelector(".ph-spark")).toBeNull();
		expect(toggle("Spark")?.getAttribute("aria-pressed")).toBe("false");
		expect(document.querySelectorAll(".ph-aura")).toHaveLength(1);

		await click(toggle("Aura"));
		expect(document.querySelector(".ph-aura")).toBeNull();
		expect(toggle("Aura")?.getAttribute("aria-pressed")).toBe("false");

		// The spark comes back, and it is decoration: assistive tech skips it.
		await click(toggle("Spark"));
		expect(
			document.querySelector(".ph-spark")?.getAttribute("aria-hidden"),
		).toBe("true");
	});

	test("static page trees stay Server Components", () => {
		// These pages carry no hooks, handlers, or browser APIs. Marking any of
		// them "use client" ships its whole static tree to the browser a second time
		// as a hydratable chunk — the release notes once re-shipped every week for two
		// analytics onClicks. The interactive leaves (PageShell, TerminalCodeBlock,
		// TrackedDownloadLink) carry their own directives, so nothing here needs one.
		// Nothing else guards this: re-adding the directive, or inlining `track` or a
		// hook, silently re-clientises the tree with every other suite still green.
		for (const relativePath of [
			"app/docs/docs-client.tsx",
			"app/home-client.tsx",
			"app/blog/releases/page.tsx",
			"app/blog/page.tsx",
		]) {
			const source = readFileSync(relativePath, "utf8");
			expect(source).not.toMatch(/^\s*["']use client["']/);
			expect(source).not.toContain("@vercel/analytics");
			expect(source).not.toContain("product-analytics");
		}
	});

	test("homepage manual exposes the workspace and workflow chapters", async () => {
		await render(<ManualChapters />);
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
			document
				.getElementById("ide-workflows")
				?.querySelector(":scope > div details summary")?.textContent,
		).toContain("Workflow commands");
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

	// Every published week links its Friday issue; a week still shipping says
	// when its issue comes out.
	function expectReleaseWeeksLinkTheirIssues() {
		const issueHrefs = new Set(
			Array.from(document.querySelectorAll<HTMLAnchorElement>("main a")).map(
				(link) => link.getAttribute("href"),
			),
		);
		const published = getBlogWeeks().filter((week) => week.release);
		expect(
			published.filter((week) => !issueHrefs.has(`/${week.slug}`)),
		).toEqual([]);
		const newestIssue = getBlogWeeks()[0]?.week ?? "";
		const stillShipping = (RELEASE_WEEKS[0]?.iso ?? "") > newestIssue;
		expect(document.body.textContent?.includes("issue comes out Friday")).toBe(
			stillShipping,
		);
	}

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
		expectReleaseWeeksLinkTheirIssues();
		expect(document.querySelector('a[href="#main-content"]')).toBeTruthy();
		expect(document.querySelector("main")?.id).toBe("main-content");
		// Nav is grouped by month (the page itself is grouped by week); labels
		// look like "Jul 2026". Assert the shape, not a specific month, so the
		// test stays stable as history grows.
		expect(
			document.querySelector('nav[aria-label="Release months"]')?.textContent,
		).toMatch(/[A-Z][a-z]{2} \d{4}/);
		const releaseNavLinks = Array.from(
			document.querySelectorAll<HTMLAnchorElement>(
				'nav[aria-label="Release months"] a[href^="#"]',
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
		expect(
			document.querySelector(
				'#mobile-site-nav a[href="https://yen.chat/#guide"]',
			),
		).toBeTruthy();
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

	test("blog index lists every weekly issue once, and marks the creator's issues apart from updates", async () => {
		await render(<BlogIndexPage />);

		const weeks = getBlogWeeks();
		const rows = Array.from(
			document.querySelectorAll("main .ed-month article"),
		);
		expect(rows).toHaveLength(weeks.length);
		const hrefs = rows.map(
			(row) => row.querySelector("a")?.getAttribute("href") ?? "",
		);
		expect(hrefs).toEqual(weeks.map((week) => `/${week.slug}`));

		// A personal issue is labeled and styled apart; an update is not.
		const personal = weeks.filter((week) => week.kind === "personal");
		const personalRows = rows.filter((row) =>
			row.classList.contains("ed-row-personal"),
		);
		expect(personalRows).toHaveLength(personal.length);
		for (const row of personalRows) {
			expect(row.querySelector(".ed-label")?.textContent).toStartWith(
				"From the creator · ",
			);
		}
		for (const row of rows.filter(
			(r) => !r.classList.contains("ed-row-personal"),
		)) {
			expect(row.querySelector(".ed-label")?.textContent).toStartWith(
				"Weekly update · ",
			);
		}

		// The index lists issues; it never prints a week's story.
		for (const week of weeks) {
			if (week.release) {
				expect(document.body.textContent).not.toContain(
					week.release.summary.slice(0, 80),
				);
			}
		}
		expect(document.querySelector(".ph-kicker")?.textContent).toBe(
			"Engineering Journal",
		);
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
		expect(markup).toContain("<button");
	});
});
