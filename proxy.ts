import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { DEVELOPMENT_CSP_NONCE } from "@/lib/csp/development";
import {
	DYNAMIC_ROOT_INLINE_SCRIPT_HASHES,
	ERROR_INLINE_SCRIPT_HASHES,
	STATIC_INLINE_SCRIPT_HASHES,
} from "@/lib/csp/generated-inline-script-hashes";
import { buildCSP } from "@/lib/csp/policy";
import {
	BLOG_HOST,
	blogUrlForMainHostPath,
	routeBlogHostPath,
} from "@/lib/http/blog-host";
import { resolveRequestHostSignals } from "@/lib/http/request-host";

import { RETIRED_PAGES } from "@/lib/http/retired-pages";

const retired: ReadonlySet<string> = new Set(RETIRED_PAGES);

export { buildCSP } from "@/lib/csp/policy";

const HEADER_BYPASS_PREFIXES = [
	"/api",
	"/_next/static",
	"/_next/image",
	"/favicons",
	"/doc-images",
	"/mascot",
	"/blog-media",
	"/stable",
];

const HEADER_BYPASS_EXACT = new Set([
	"/robots.txt",
	"/sitemap.xml",
	"/manifest.webmanifest",
	"/llms.txt",
	"/bitcoin.pdf",
	"/favicon.ico",
]);

const ENCODED_PATH_SEPARATOR_PATTERN = /%(?:2f|5c)/i;

function matchesExactOrChildPath(pathname: string, prefix: string): boolean {
	return pathname === prefix || pathname.startsWith(`${prefix}/`);
}

function uniqueHashes(...groups: readonly (readonly string[])[]): string[] {
	return Array.from(new Set(groups.flat())).sort();
}

function decodeUnreservedPathname(pathname: string): string {
	return pathname.replace(/%[0-9a-f]{2}/gi, (encodedByte) => {
		const character = String.fromCharCode(
			Number.parseInt(encodedByte.slice(1), 16),
		);
		return /^[A-Za-z0-9._~-]$/.test(character)
			? character
			: encodedByte.toUpperCase();
	});
}

function findCanonicalStaticPath(pathname: string): string | undefined {
	const normalizedPathname = decodeUnreservedPathname(pathname).toLowerCase();
	return Object.keys(STATIC_INLINE_SCRIPT_HASHES).find(
		(candidate) => candidate.toLowerCase() === normalizedPathname,
	);
}

function continueWithCSP(
	request: NextRequest,
	csp: string,
	nonce?: string,
	rewritePathname?: string,
): NextResponse {
	const requestHeaders = new Headers(request.headers);
	requestHeaders.set("Content-Security-Policy", csp);
	if (nonce) {
		requestHeaders.set("x-nonce", nonce);
	} else {
		requestHeaders.delete("x-nonce");
	}

	const init = { request: { headers: requestHeaders } };
	let response: NextResponse;
	if (rewritePathname) {
		const rewriteUrl = request.nextUrl.clone();
		rewriteUrl.pathname = rewritePathname;
		response = NextResponse.rewrite(rewriteUrl, init);
	} else {
		response = NextResponse.next(init);
	}
	response.headers.set("Content-Security-Policy", csp);
	if (nonce) {
		response.headers.set("x-nonce", nonce);
	}
	return response;
}

function getRequestHost(request: NextRequest): {
	hasConflict: boolean;
	host: string;
} {
	return resolveRequestHostSignals({
		nextUrlHost: request.nextUrl.host,
		requestUrl: request.url,
		hostHeader: request.headers.get("host"),
		forwardedHostHeader: request.headers.get("x-forwarded-host"),
	});
}

function shouldBypassSecurityHeaders(pathname: string): boolean {
	if (HEADER_BYPASS_EXACT.has(pathname)) {
		return true;
	}
	return HEADER_BYPASS_PREFIXES.some((prefix) =>
		matchesExactOrChildPath(pathname, prefix),
	);
}

/**
 * Serves `pathname` with its route's CSP: exact static hashes for a prerendered
 * route, otherwise a fresh nonce. `rewritePathname` renders another route at
 * this address (blog.yen.chat/<slug> renders /blog/<slug>).
 */
function serveWithCSP(
	request: NextRequest,
	pathname: string,
	rewritePathname?: string,
): NextResponse {
	const isDevelopment = process.env.NODE_ENV === "development";
	const staticHashes = isDevelopment
		? undefined
		: STATIC_INLINE_SCRIPT_HASHES[pathname];
	if (staticHashes) {
		const csp = buildCSP(
			undefined,
			uniqueHashes(staticHashes, ERROR_INLINE_SCRIPT_HASHES),
		);
		return continueWithCSP(request, csp, undefined, rewritePathname);
	}
	const nonce = isDevelopment
		? DEVELOPMENT_CSP_NONCE
		: btoa(crypto.randomUUID());
	const csp = buildCSP(
		nonce,
		uniqueHashes(DYNAMIC_ROOT_INLINE_SCRIPT_HASHES, ERROR_INLINE_SCRIPT_HASHES),
		isDevelopment,
	);
	return continueWithCSP(request, csp, nonce, rewritePathname);
}

/** blog.yen.chat requests; `null` means a shared asset the normal path serves. */
function routeBlogHost(request: NextRequest): NextResponse | null {
	const route = routeBlogHostPath(request.nextUrl.pathname);
	if (route.kind === "redirect") {
		// A router fetch (prefetch or client navigation) of a relative yen.chat
		// link such as /docs cannot follow a cross-origin redirect: CSP
		// connect-src blocks it. Next strips the rsc header before this proxy,
		// so detect a script fetch by Sec-Fetch-Dest instead; an empty answer
		// makes the router skip the prefetch and fall back to a full navigation,
		// which is a document request and gets the 308.
		const fetchDest = request.headers.get("sec-fetch-dest");
		if (fetchDest && fetchDest !== "document") {
			return new NextResponse(null, { status: 204 });
		}
		// A note's address carries its #anchor, so the query goes before it.
		const location = new URL(route.url);
		location.search = request.nextUrl.search;
		return NextResponse.redirect(location, 308);
	}
	if (route.kind === "file") {
		const rewriteUrl = request.nextUrl.clone();
		rewriteUrl.pathname = route.pathname;
		return NextResponse.rewrite(rewriteUrl);
	}
	if (route.kind === "page") {
		return serveWithCSP(request, route.pathname, route.pathname);
	}
	return null;
}

export function proxy(request: NextRequest) {
	const { hasConflict, host } = getRequestHost(request);
	const pathname = request.nextUrl.pathname;

	if (hasConflict) {
		return new NextResponse("Bad Request", {
			status: 400,
			headers: {
				"Cache-Control": "no-store",
			},
		});
	}

	// Vercel can decode reserved separators after this proxy runs. Reject them
	// here so a non-canonical request cannot inherit the wrong static CSP.
	if (ENCODED_PATH_SEPARATOR_PATTERN.test(pathname)) {
		return new NextResponse("Bad Request", {
			status: 400,
			headers: {
				"Cache-Control": "no-store",
			},
		});
	}

	if (host === "www.yen.chat") {
		const canonicalUrl = new URL(request.url);
		canonicalUrl.protocol = "https:";
		canonicalUrl.hostname = "yen.chat";
		canonicalUrl.port = "";
		return NextResponse.redirect(canonicalUrl, 308);
	}

	if (host === BLOG_HOST) {
		const blogResponse = routeBlogHost(request);
		if (blogResponse) {
			return blogResponse;
		}
	} else if (host === "yen.chat") {
		const blogUrl = blogUrlForMainHostPath(pathname);
		if (blogUrl) {
			return NextResponse.redirect(`${blogUrl}${request.nextUrl.search}`, 308);
		}
	}

	const canonicalStaticPath = findCanonicalStaticPath(pathname);
	if (
		host !== BLOG_HOST &&
		retired.has(decodeUnreservedPathname(pathname).toLowerCase())
	) {
		const url = request.nextUrl.clone();
		url.pathname = "/";
		// A fragment-free redirect preserves the chapter in old /docs# links.
		return NextResponse.redirect(url, 308);
	}
	if (canonicalStaticPath && canonicalStaticPath !== pathname) {
		const canonicalUrl = new URL(request.url);
		canonicalUrl.pathname = canonicalStaticPath;
		return NextResponse.redirect(canonicalUrl, 308);
	}
	if (shouldBypassSecurityHeaders(pathname)) {
		return NextResponse.next();
	}

	return serveWithCSP(request, pathname);
}

export const config = {
	matcher: ["/:path*"],
};
