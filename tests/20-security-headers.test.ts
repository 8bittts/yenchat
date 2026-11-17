import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { buildCSP } from "../proxy";

type HeaderEntry = {
	key: string;
	value: string;
};

type HeaderRule = {
	source: string;
	headers: HeaderEntry[];
};

type VercelConfig = {
	headers?: HeaderRule[];
};

function getHeaderValue(
	headers: HeaderEntry[],
	key: string,
): string | undefined {
	return headers.find((header) => header.key === key)?.value;
}

describe("Security headers config", () => {
	const configPath = join(process.cwd(), "vercel.json");
	const raw = readFileSync(configPath, "utf-8");
	const config = JSON.parse(raw) as VercelConfig;
	const globalRule = config.headers?.find((rule) => rule.source === "/(.*)");

	test("global security headers exist", () => {
		expect(globalRule).toBeDefined();
		expect(globalRule?.headers.length).toBeGreaterThan(0);
	});

	test("no Access-Control-Allow-Origin header (no cross-origin API surface)", () => {
		const value = getHeaderValue(
			globalRule?.headers ?? [],
			"Access-Control-Allow-Origin",
		);
		expect(value).toBeUndefined();
	});

	test("cross-origin isolation headers are set", () => {
		expect(
			getHeaderValue(globalRule?.headers ?? [], "Cross-Origin-Opener-Policy"),
		).toBe("same-origin");
		expect(
			getHeaderValue(globalRule?.headers ?? [], "Cross-Origin-Resource-Policy"),
		).toBe("same-origin");
	});

	test("CSP is emitted by proxy and allows docs YouTube embeds with hardening directives", () => {
		const cspHeader = getHeaderValue(
			globalRule?.headers ?? [],
			"Content-Security-Policy",
		);
		expect(cspHeader).toBeUndefined();

		const scriptHash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";
		const csp = buildCSP("test-nonce", [scriptHash]);
		expect(csp).toContain("frame-src https://www.youtube-nocookie.com");
		expect(csp).toContain("object-src 'none'");
		expect(csp).toContain("base-uri 'self'");
		expect(csp).toContain("form-action 'self'");
		expect(csp).toContain("script-src-attr 'none'");
		// Vercel analytics/speed-insights load same-origin (/_vercel/.../script.js),
		// so *.vercel-insights.com belongs only in connect-src (beacons), not script-src.
		const scriptSrc = csp
			.split("; ")
			.find((directive) => directive.startsWith("script-src "));
		expect(scriptSrc).toBe(
			`script-src 'self' 'nonce-test-nonce' '${scriptHash}'`,
		);
		expect(scriptSrc).not.toContain("'unsafe-inline'");
		// img-src is scoped to same-origin + data URIs; the site loads zero
		// external images, so the wildcard https: source was removed.
		expect(csp).toContain("img-src 'self' data:");
		expect(csp).not.toContain("img-src 'self' data: https:");
		// Downloads are a 302 navigation, not a fetch, so neither the GitHub
		// release host nor the retired Supabase host belongs in connect-src.
		expect(csp).toContain(
			"connect-src 'self' https://vitals.vercel-insights.com https://*.vercel-insights.com;",
		);
		expect(csp).not.toContain("supabase.co");
		expect(csp).not.toContain("github.com");
		expect(csp).not.toContain("frame-src 'none'");
		expect(csp).not.toContain("wss://ws-us3.pusher.com");
		expect(csp).not.toContain("https://vercel.live");
	});

	test("static CSP uses exact hashes while development alone allows eval", () => {
		const scriptHash = "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=";
		const staticCsp = buildCSP(undefined, [scriptHash]);
		const staticScriptSrc = staticCsp
			.split("; ")
			.find((directive) => directive.startsWith("script-src "));
		expect(staticScriptSrc).toBe(`script-src 'self' '${scriptHash}'`);
		expect(staticScriptSrc).not.toContain("'unsafe-inline'");
		expect(staticScriptSrc).not.toContain("'unsafe-eval'");

		const developmentCsp = buildCSP("dev-nonce", [], true);
		expect(developmentCsp).toContain(
			"script-src 'self' 'nonce-dev-nonce' 'unsafe-eval'",
		);
		expect(() => buildCSP(undefined, ["sha256-invalid"])).toThrow(
			"invalid CSP script hash",
		);
	});

	test("deprecated X-XSS-Protection header is not set", () => {
		const value = getHeaderValue(globalRule?.headers ?? [], "X-XSS-Protection");
		expect(value).toBeUndefined();
	});
});
