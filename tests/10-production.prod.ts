/**
 * Production Tests
 *
 * Focus: live public-surface security and download/update pipeline health.
 *
 * Run with: bun test ./tests/10-production.prod.ts
 */

import { describe, expect, setDefaultTimeout, test } from "bun:test";
import { createHash } from "node:crypto";

const PROD_URL = process.env.YEN_PROD_TEST_URL ?? "https://yen.chat";

// These probes fetch live production pages. Bun's 5s default is shorter than a cold
// fetch of the ~200KB /docs page, measured at 1.2-7.0s, so a slow edge failed the
// gate without any regression.
setDefaultTimeout(30_000);

type InlineScript = {
	attributes: string;
	body: string;
};

function getInlineScripts(html: string): InlineScript[] {
	return Array.from(
		html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi),
		(match) => ({
			attributes: match[1] ?? "",
			body: match[2] ?? "",
		}),
	).filter((script) => script.body.length > 0);
}

function hashInlineScript(script: string): string {
	return `sha256-${createHash("sha256").update(script).digest("base64")}`;
}

function getScriptSrc(response: Response): string {
	return (
		response.headers
			.get("content-security-policy")
			?.split("; ")
			.find((directive) => directive.startsWith("script-src ")) ?? ""
	);
}

function findUnauthorizedScripts(
	scripts: readonly InlineScript[],
	scriptSrc: string,
	nonce: string | null,
): string[] {
	return scripts
		.filter((script) => {
			const hasNonce = nonce
				? script.attributes.includes(`nonce="${nonce}"`)
				: false;
			const hasHash = scriptSrc.includes(`'${hashInlineScript(script.body)}'`);
			return !hasNonce && !hasHash;
		})
		.map((script) => script.body.trim().slice(0, 120));
}

describe("Production: strict CSP authorization", () => {
	test("a terms page is stable HTML authorized by exact hashes", async () => {
		const first = await fetch(`${PROD_URL}/terms`);
		const second = await fetch(`${PROD_URL}/terms`);
		expect(first.status).toBe(200);
		expect(second.status).toBe(200);
		expect(first.headers.get("x-nonce")).toBeNull();
		expect(second.headers.get("x-nonce")).toBeNull();

		const scriptSrc = getScriptSrc(first);
		expect(scriptSrc).toContain("'sha256-");
		expect(scriptSrc).not.toContain("'nonce-");
		expect(scriptSrc).not.toContain("'unsafe-inline'");
		expect(scriptSrc).not.toContain("'unsafe-eval'");
		expect(scriptSrc).not.toContain("yen-development-csp-nonce");

		const firstHtml = await first.text();
		const secondHtml = await second.text();
		expect(secondHtml).toBe(firstHtml);
		const scripts = getInlineScripts(firstHtml);
		expect(scripts.length).toBeGreaterThan(0);
		expect(findUnauthorizedScripts(scripts, scriptSrc, null)).toEqual([]);
	});

	test("encoded and case aliases redirect to an authorized static page", async () => {
		for (const alias of ["/%74erms", "/Terms"]) {
			const redirect = await fetch(`${PROD_URL}${alias}?source=csp-test`, {
				redirect: "manual",
			});
			expect(redirect.status).toBe(308);
			expect(
				new URL(redirect.headers.get("location") ?? "", PROD_URL).toString(),
			).toBe(new URL("/terms?source=csp-test", PROD_URL).toString());

			const response = await fetch(`${PROD_URL}${alias}`);
			expect(response.status).toBe(200);
			const nonce = response.headers.get("x-nonce");
			expect(nonce).toBeNull();
			const scriptSrc = getScriptSrc(response);
			expect(scriptSrc).not.toContain("'unsafe-inline'");
			expect(scriptSrc).not.toContain("'unsafe-eval'");
			const scripts = getInlineScripts(await response.text());
			expect(findUnauthorizedScripts(scripts, scriptSrc, nonce)).toEqual([]);
		}
	});

	test("encoded path separators fail closed before platform normalization", async () => {
		for (const path of [
			"/alternatives/%2fwarp",
			"/alternatives%2fwarp",
			"/alternatives/warp%2f",
			"/alternatives%5cwarp",
			"/use-cases%2fterminal-git-diff-drawer",
		]) {
			const response = await fetch(`${PROD_URL}${path}`, {
				redirect: "manual",
			});

			expect(response.status, path).toBe(400);
			expect(response.headers.get("cache-control"), path).toBe("no-store");
			expect(response.headers.get("location"), path).toBeNull();
			expect(response.headers.get("x-nonce"), path).toBeNull();
		}
	});

	test("a missing page uses a fresh nonce plus exact root hashes", async () => {
		const first = await fetch(`${PROD_URL}/yen-page-not-found`);
		const second = await fetch(`${PROD_URL}/yen-page-not-found`);
		expect(first.status).toBe(404);
		expect(second.status).toBe(404);

		const firstNonce = first.headers.get("x-nonce");
		const secondNonce = second.headers.get("x-nonce");
		expect(firstNonce).toBeTruthy();
		expect(secondNonce).toBeTruthy();
		expect(secondNonce).not.toBe(firstNonce);

		const scriptSrc = getScriptSrc(first);
		expect(scriptSrc).toContain(`'nonce-${firstNonce}'`);
		expect(scriptSrc).toContain("'sha256-");
		expect(scriptSrc).not.toContain("'unsafe-inline'");
		expect(scriptSrc).not.toContain("'unsafe-eval'");
		expect(scriptSrc).not.toContain("yen-development-csp-nonce");
		const scripts = getInlineScripts(await first.text());
		expect(findUnauthorizedScripts(scripts, scriptSrc, firstNonce)).toEqual([]);
	});

	test("an unknown PSEO slug returns a fully authorized static 404", async () => {
		const first = await fetch(`${PROD_URL}/alternatives/not-a-real-page`);
		const second = await fetch(`${PROD_URL}/alternatives/not-a-real-page`);
		for (const response of [first, second]) {
			expect(response.status).toBe(404);
			const nonce = response.headers.get("x-nonce");
			const scriptSrc = getScriptSrc(response);
			const scripts = getInlineScripts(await response.text());
			expect(findUnauthorizedScripts(scripts, scriptSrc, nonce)).toEqual([]);
		}
	});
});

describe("Production: Downloads", () => {
	test("version.json is accessible with required fields", async () => {
		const response = await fetch(`${PROD_URL}/stable/version.json`);
		expect(response.status).toBe(200);

		const version = await response.json();
		expect(version.version).toBeDefined();
		expect(version.url).toBeDefined();
	});

	test("current DMG download is served from GitHub Releases", async () => {
		const versionResponse = await fetch(`${PROD_URL}/stable/version.json`);
		const version = await versionResponse.json();
		expect(version.url).toStartWith(
			"https://github.com/8bittts/yenchat/releases/download/",
		);

		const response = await fetch(version.url, { method: "HEAD" });
		expect(response.status).toBe(200);
		expect(Number(response.headers.get("content-length"))).toBeGreaterThan(
			50_000_000,
		);
	});

	test("/download redirects to the GitHub Releases DMG", async () => {
		const response = await fetch(`${PROD_URL}/download`, {
			redirect: "manual",
		});
		expect(response.status).toBe(302);

		const location = response.headers.get("location");
		expect(location).toStartWith(
			"https://github.com/8bittts/yenchat/releases/download/",
		);
		expect(location).toEndWith(".dmg");
	});
});

describe("Production: Native browser public surface", () => {
	test("retired main-site pages preserve the query on a permanent redirect", async () => {
		for (const path of [
			"/docs",
			"/tunes",
			"/yeni",
			"/library",
			"/alternatives",
			"/alternatives/warp",
			"/use-cases",
			"/use-cases/terminal-with-native-browser-preview",
		]) {
			const response = await fetch(new URL(`${path}?ref=bookmark`, PROD_URL), {
				redirect: "manual",
			});
			expect(response.status, path).toBe(308);
			const location = response.headers.get("location");
			expect(location, path).toBeTruthy();
			expect(new URL(location ?? "", PROD_URL).href, path).toBe(
				new URL("/?ref=bookmark", PROD_URL).href,
			);
		}
	});
	test("old docs lead to the manual on the homepage", async () => {
		const response = await fetch(`${PROD_URL}/docs`);
		expect(response.status).toBe(200);

		const html = await response.text();
		expect(new URL(response.url).pathname).toBe("/");
		expect(html).toContain('id="guide"');
		expect(html).toContain("yen web");
		expect(html).toContain("Browser Split");
	});

	test("/llms.txt describes browser isolation and default-off link capture", async () => {
		const response = await fetch(`${PROD_URL}/llms.txt`);
		expect(response.status).toBe(200);

		const text = await response.text();
		expect(text).toContain("Native browser preview");
		expect(text).toContain("`yen web`");
		expect(text).toContain("optional split targeting");
		expect(text).toContain("terminal link capture is default-off");
		expect(text).toContain("no bundled browser runtime");
	});

	test("/manifest.webmanifest includes native WebKit browser preview copy", async () => {
		const response = await fetch(`${PROD_URL}/manifest.webmanifest`);
		expect(response.status).toBe(200);

		const manifest = await response.json();
		expect(manifest.description).toContain("native WebKit browser preview");
	});
});
