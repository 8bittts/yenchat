import { afterEach, describe, expect, test } from "bun:test";
import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
	GET as getDownloadRoute,
	resolveDownloadRedirectTarget,
} from "../app/download/route";
import { GET as getStableRoute } from "../app/stable/[...path]/route";
import {
	ERROR_INLINE_SCRIPT_HASHES,
	STATIC_INLINE_SCRIPT_HASHES,
} from "../lib/csp/generated-inline-script-hashes";
import { buildCSP, proxy } from "../proxy";

const repoRoot = process.cwd();
const createdPaths = new Set<string>();

afterEach(async () => {
	for (const path of createdPaths) {
		await rm(path, { force: true });
	}
	createdPaths.clear();
});

describe("download route security", () => {
	test("allows only canonical GitHub release DMG URLs", () => {
		expect(
			resolveDownloadRedirectTarget(
				"https://github.com/8bittts/yenchat/releases/download/v0.990/yen-0990.dmg",
			),
		).toBe(
			"https://github.com/8bittts/yenchat/releases/download/v0.990/yen-0990.dmg",
		);
		expect(
			resolveDownloadRedirectTarget(
				"https://github.com/8bittts/yenchat/releases/download/v0.990/yen-0990.dmg?token=123",
			),
		).toBeNull();
		expect(
			resolveDownloadRedirectTarget(
				"https://example.com/8bittts/yenchat/releases/download/v0.990/yen-0990.dmg",
			),
		).toBeNull();
		expect(
			resolveDownloadRedirectTarget(
				"https://github.com/someone-else/yenchat/releases/download/v0.990/yen-0990.dmg",
			),
		).toBeNull();
		expect(
			resolveDownloadRedirectTarget(
				"https://github.com/8bittts/yenchat/archive/refs/heads/main.zip",
			),
		).toBeNull();
		expect(
			resolveDownloadRedirectTarget(
				"https://github.com/8bittts/yenchat/releases/download/v0.990/yen-0990.zip",
			),
		).toBeNull();
		expect(
			resolveDownloadRedirectTarget(
				"http://github.com/8bittts/yenchat/releases/download/v0.990/yen-0990.dmg",
			),
		).toBeNull();
		expect(resolveDownloadRedirectTarget("javascript:alert(1)")).toBeNull();
	});

	test("download route responses are marked no-store", async () => {
		const response = await getDownloadRoute(
			new Request("https://yen.chat/download") as never,
		);

		expect([302, 404]).toContain(response.status);
		expect(response.headers.get("Cache-Control")).toBe("no-store");
		expect(response.headers.get("X-Robots-Tag")).toBe(
			"noindex, nofollow, noarchive, nosnippet, noimageindex",
		);
	});

	test("download route ignores prefetch requests", async () => {
		const response = await getDownloadRoute(
			new Request("https://yen.chat/download", {
				headers: { "next-router-prefetch": "1" },
			}) as never,
		);

		expect(response.status).toBe(204);
		expect(response.headers.get("Cache-Control")).toBe("no-store");
	});

	test("download route records nothing and sends no email", async () => {
		const route = await readFile(
			join(process.cwd(), "app/download/route.ts"),
			"utf8",
		);
		expect(route).not.toContain("after(");
		expect(route).not.toContain("fetch(");
		expect(route).not.toContain("sendEmail");
	});
});

describe("stable route hardening", () => {
	test("stable route rejects unsafe path segments", async () => {
		const response = await getStableRoute(
			new Request("https://yen.chat/stable/..") as never,
			{
				params: Promise.resolve({ path: [".."] }),
			},
		);

		expect(response.status).toBe(404);
	});

	test("stable route adds download headers for attachment artifacts", async () => {
		const fileName = `codex-static-route-${crypto.randomUUID()}.zip`;
		const filePath = join(repoRoot, "public/stable", fileName);
		createdPaths.add(filePath);
		await writeFile(filePath, "zip payload", "utf8");

		const response = await getStableRoute(
			new Request(`https://yen.chat/stable/${fileName}`) as never,
			{ params: Promise.resolve({ path: [fileName] }) },
		);

		expect(response.status).toBe(200);
		expect(response.headers.get("Content-Type")).toBe("application/zip");
		expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
		expect(response.headers.get("X-Download-Options")).toBe("noopen");
		expect(response.headers.get("Content-Disposition")).toContain(fileName);
	});

	test("stable route uses short cache for appcast.xml and version.json", async () => {
		const shortCache = "public, max-age=300, stale-while-revalidate=60";
		// appcast.xml and version.json are real tracked files; back up and
		// restore their contents rather than deleting them.
		for (const fileName of ["appcast.xml", "version.json"]) {
			const filePath = join(repoRoot, "public/stable", fileName);
			const original = await readFile(filePath);
			try {
				const response = await getStableRoute(
					new Request(`https://yen.chat/stable/${fileName}`) as never,
					{ params: Promise.resolve({ path: [fileName] }) },
				);

				expect(response.status).toBe(200);
				expect(response.headers.get("Cache-Control")).toBe(shortCache);
			} finally {
				await writeFile(filePath, original);
			}
		}
	});

	test("stable route uses long immutable cache for release artifacts", async () => {
		const fileName = `codex-cache-${crypto.randomUUID()}.sha256`;
		const filePath = join(repoRoot, "public/stable", fileName);
		createdPaths.add(filePath);
		await writeFile(filePath, "deadbeef", "utf8");

		const response = await getStableRoute(
			new Request(`https://yen.chat/stable/${fileName}`) as never,
			{ params: Promise.resolve({ path: [fileName] }) },
		);

		expect(response.status).toBe(200);
		expect(response.headers.get("Cache-Control")).toBe(
			"public, max-age=31536000, immutable",
		);
	});
});

describe("proxy security header bypass matching", () => {
	test("CSP is still generated for non-framework prefixes like /apiary", () => {
		expect(buildCSP("nonce-value")).toContain("default-src 'self'");

		const response = proxy({
			headers: new Headers({ host: "yen.chat" }),
			nextUrl: new URL("https://yen.chat/apiary"),
			url: "https://yen.chat/apiary",
		} as never);

		expect(response.headers.get("Content-Security-Policy")).toContain(
			"default-src 'self'",
		);
	});

	test("dynamic CSP nonce matches the emitted and forwarded headers", () => {
		const response = proxy({
			headers: new Headers({ host: "yen.chat" }),
			nextUrl: new URL("https://yen.chat/yen-page-not-found"),
			url: "https://yen.chat/yen-page-not-found",
		} as never);

		const csp = response.headers.get("Content-Security-Policy") ?? "";
		const xNonce = response.headers.get("x-nonce") ?? "";
		const forwardedCsp =
			response.headers.get("x-middleware-request-content-security-policy") ??
			"";
		expect(csp).toBeTruthy();
		expect(xNonce).toBeTruthy();
		expect(forwardedCsp).toBe(csp);

		const nonceFromCsp =
			csp.match(/script-src 'self' 'nonce-([^']+)'/)?.[1] ?? "";
		expect(nonceFromCsp).toBe(xNonce);
	});

	test("prerendered pages use exact hashes without a response nonce", () => {
		const path = "/terms";
		const expectedHashes = STATIC_INLINE_SCRIPT_HASHES[path] ?? [];
		expect(expectedHashes.length).toBeGreaterThan(0);

		const response = proxy({
			headers: new Headers({ host: "yen.chat" }),
			nextUrl: new URL(`https://yen.chat${path}`),
			url: `https://yen.chat${path}`,
		} as never);
		const csp = response.headers.get("Content-Security-Policy") ?? "";
		const scriptSrc =
			csp
				.split("; ")
				.find((directive) => directive.startsWith("script-src ")) ?? "";
		expect(response.headers.get("x-nonce")).toBeNull();
		expect(scriptSrc).not.toContain("'nonce-");
		expect(scriptSrc).not.toContain("'unsafe-inline'");
		expect(scriptSrc).not.toContain("'unsafe-eval'");
		for (const hash of [...expectedHashes, ...ERROR_INLINE_SCRIPT_HASHES]) {
			expect(csp).toContain(`'${hash}'`);
		}
		expect(
			response.headers.get("x-middleware-request-content-security-policy"),
		).toBe(csp);
	});

	test("encoded and case aliases redirect to the exact static path", () => {
		for (const alias of ["/%74erms", "/Terms"]) {
			const url = `https://yen.chat${alias}?source=csp-test`;
			const response = proxy({
				headers: new Headers({ host: "yen.chat" }),
				nextUrl: new URL(url),
				url,
			} as never);

			expect(response.status).toBe(308);
			expect(response.headers.get("location")).toBe(
				"https://yen.chat/terms?source=csp-test",
			);
			expect(response.headers.get("x-nonce")).toBeNull();
		}
	});

	test("encoded path separators fail closed before route normalization", () => {
		for (const path of [
			"/alternatives/%2fwarp",
			"/alternatives%2fwarp",
			"/alternatives/warp%2f",
			"/alternatives%5cwarp",
			"/use-cases%2fterminal-git-diff-drawer",
		]) {
			const url = `https://yen.chat${path}`;
			const response = proxy({
				headers: new Headers({ host: "yen.chat" }),
				nextUrl: new URL(url),
				url,
			} as never);

			expect(response.status, path).toBe(400);
			expect(response.headers.get("Cache-Control"), path).toBe("no-store");
			expect(response.headers.get("location"), path).toBeNull();
			expect(response.headers.get("Content-Security-Policy"), path).toBeNull();
			expect(response.headers.get("x-nonce"), path).toBeNull();
		}
	});

	test("bypassed asset and exact paths emit no CSP or nonce", () => {
		for (const path of [
			"/_next/static/chunk.js",
			"/robots.txt",
			"/stable/version.json",
		]) {
			const response = proxy({
				headers: new Headers({ host: "yen.chat" }),
				nextUrl: new URL(`https://yen.chat${path}`),
				url: `https://yen.chat${path}`,
			} as never);

			expect(response.headers.get("Content-Security-Policy")).toBeNull();
			expect(response.headers.get("x-nonce")).toBeNull();
		}
	});
});
