import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	existsSync,
	readdirSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { createServer } from "node:net";
import { join, relative, sep } from "node:path";
import blogSlugs from "@/content/blog/slugs.json";
import {
	ORGANIZATION_STRUCTURED_DATA_SCRIPT,
	WEBSITE_STRUCTURED_DATA_SCRIPT,
} from "@/lib/csp/inline-scripts";
import { buildCSP } from "@/lib/csp/policy";

const REPO_ROOT = join(import.meta.dir, "..");
const NEXT_OUTPUT = join(REPO_ROOT, ".next");
const GENERATED_MANIFEST = join(
	REPO_ROOT,
	"lib/csp/generated-inline-script-hashes.ts",
);
const PRERENDER_MANIFEST = join(NEXT_OUTPUT, "prerender-manifest.json");
const SERVER_OUTPUT = join(NEXT_OUTPUT, "server");
const ROUTE_CACHE_ARTIFACT = /^(?:APP_PAGE|APP_ROUTE)\/[0-9a-f]{64}\/\$\/(.+)$/;
const INTERNAL_ERROR_ROUTES = new Set(["/_global-error", "/_not-found"]);
const MAX_CSP_HEADER_BYTES = 8_000;
const DYNAMIC_PROBE_PATH = "/yen-page-not-found";
const REPRESENTATIVE_PRODUCTION_NONCE = "x".repeat(48);
const NODE_EXECUTABLE = "node";
const ACTIVE_MARKUP_CONTENT_TYPES = [
	"text/html",
	"application/xhtml+xml",
	"image/svg+xml",
] as const;

type HashManifest = {
	dynamicRoot: string[];
	errors: string[];
	routes: Record<string, string[]>;
};

type PrerenderManifest = {
	routes: Record<
		string,
		{
			dataRoute?: string | null;
		}
	>;
};

type InlineScriptElement = {
	attributes: string;
	body: string;
};

type RouteHandlerMeta = {
	headers?: Record<string, string>;
};

export function hashInlineScript(script: string): string {
	return `sha256-${createHash("sha256").update(script).digest("base64")}`;
}

export function extractInlineScriptElements(
	html: string,
): InlineScriptElement[] {
	return Array.from(
		html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi),
		(match) => ({
			attributes: match[1] ?? "",
			body: match[2] ?? "",
		}),
	).filter((script) => script.body.length > 0);
}

export function extractInlineScripts(html: string): string[] {
	return extractInlineScriptElements(html).map((script) => script.body);
}

export function extractInlineScriptHashes(html: string): string[] {
	return Array.from(
		new Set(extractInlineScripts(html).map(hashInlineScript)),
	).sort();
}

function assertNoBlockedInlineBehavior(route: string, html: string): void {
	if (/<[^>]*\son[a-z][a-z0-9:-]*\s*=/i.test(html)) {
		throw new Error(`${route} contains a CSP-blocked inline event handler`);
	}
	if (/\b(?:href|src)\s*=\s*["']\s*javascript:/i.test(html)) {
		throw new Error(`${route} contains a CSP-blocked javascript URL`);
	}
}

function artifactNameForDataRoute(dataRoute: string): string {
	if (!dataRoute.startsWith("/") || !dataRoute.endsWith(".rsc")) {
		throw new Error(`unexpected prerender data route: ${dataRoute}`);
	}
	return dataRoute.slice(1, -4);
}

function collectOutputFiles(directory: string, suffix: string): string[] {
	const files: string[] = [];
	for (const entry of readdirSync(directory, { withFileTypes: true })) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) {
			files.push(...collectOutputFiles(path, suffix));
		} else if (entry.isFile() && entry.name.endsWith(suffix)) {
			files.push(path);
		}
	}
	return files.sort();
}

function scopedArtifactName(relativePath: string): string {
	const name = ROUTE_CACHE_ARTIFACT.exec(relativePath)?.[1];
	if (!name) {
		throw new Error(`unexpected route-cache artifact: ${relativePath}`);
	}
	return name;
}

/**
 * Maps each prerendered artifact name ("index", "blog/skills",
 * "robots.txt") to its file. Next writes them under server/app, except that
 * 16.3.8+ writes them under server/route-cache/<kind>/<owner hash>/$/ when a
 * build adapter is set, which every Vercel build does.
 */
export function collectPrerenderArtifacts(
	serverOutput: string,
	suffix: ".body" | ".html",
): Map<string, string> {
	const appOutput = join(serverOutput, "app");
	const routeCache = join(serverOutput, "route-cache");
	const scoped = existsSync(routeCache);
	if (scoped && collectOutputFiles(appOutput, suffix).length > 0) {
		throw new Error(`${suffix} artifacts in both server/app and route-cache`);
	}
	const root = scoped ? routeCache : appOutput;
	const artifacts = new Map<string, string>();
	for (const path of collectOutputFiles(root, suffix)) {
		const relativePath = relative(root, path).split(sep).join("/");
		const name = (
			scoped ? scopedArtifactName(relativePath) : relativePath
		).slice(0, -suffix.length);
		const existing = artifacts.get(name);
		if (existing) {
			throw new Error(`duplicate prerendered ${name}: ${existing}, ${path}`);
		}
		artifacts.set(name, path);
	}
	return artifacts;
}

function routePathForArtifact(name: string): string {
	return name === "index" ? "/" : `/${name}`;
}

function collectRawMarkupRouteHashes(): Record<string, string[]> {
	const routes: Record<string, string[]> = {};
	for (const [name, bodyPath] of collectPrerenderArtifacts(
		SERVER_OUTPUT,
		".body",
	)) {
		const metaPath = `${bodyPath.slice(0, -".body".length)}.meta`;
		if (!existsSync(metaPath)) {
			throw new Error(`route-handler body is missing metadata: ${bodyPath}`);
		}
		const meta = JSON.parse(readFileSync(metaPath, "utf8")) as RouteHandlerMeta;
		const contentType = Object.entries(meta.headers ?? {}).find(
			([name]) => name.toLowerCase() === "content-type",
		)?.[1];
		if (
			!contentType ||
			!ACTIVE_MARKUP_CONTENT_TYPES.some((type) =>
				contentType.toLowerCase().startsWith(type),
			)
		) {
			continue;
		}

		const html = readFileSync(bodyPath, "utf8");
		const route = routePathForArtifact(name);
		assertNoBlockedInlineBehavior(route, html);
		if (extractInlineScripts(html).length > 0) {
			throw new Error(
				`${route} contains an inline script; move it to a same-origin external file`,
			);
		}
		routes[route] = [];
	}
	return routes;
}

function intersectHashSets(hashSets: readonly string[][]): string[] {
	const [first, ...rest] = hashSets;
	if (!first) {
		return [];
	}
	return first.filter((hash) => rest.every((hashes) => hashes.includes(hash)));
}

function findAvailablePort(): Promise<number> {
	return new Promise((resolve, reject) => {
		const server = createServer();
		server.once("error", reject);
		server.listen(0, "127.0.0.1", () => {
			const address = server.address();
			if (!address || typeof address === "string") {
				server.close();
				reject(new Error("could not allocate a dynamic CSP probe port"));
				return;
			}
			server.close((error) => {
				if (error) {
					reject(error);
				} else {
					resolve(address.port);
				}
			});
		});
	});
}

async function stopServer(server: ReturnType<typeof spawn>): Promise<void> {
	if (server.exitCode !== null) {
		return;
	}
	await new Promise<void>((resolve) => {
		const forceKill = setTimeout(() => server.kill("SIGKILL"), 1_000);
		server.once("exit", () => {
			clearTimeout(forceKill);
			resolve();
		});
		server.kill("SIGTERM");
	});
}

async function waitForDynamicProbe(
	server: ReturnType<typeof spawn>,
	port: number,
): Promise<Response> {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (server.exitCode !== null) {
			throw new Error("next start exited before the dynamic CSP probe");
		}
		try {
			const response = await fetch(
				`http://localhost:${port}${DYNAMIC_PROBE_PATH}`,
			);
			if (response.status === 404) return response;
		} catch {
			// The production server has not opened its socket yet.
		}
		await new Promise((resolve) => setTimeout(resolve, 100));
	}
	throw new Error("timed out probing the built dynamic CSP route");
}

async function readDynamicProbe(
	response: Response,
	label: string,
	previousNonce?: string,
): Promise<{
	hashes: string[];
	nonce: string;
	scripts: InlineScriptElement[];
}> {
	if (response.status !== 404) {
		throw new Error(`${label} returned ${response.status}`);
	}
	const nonce = response.headers.get("x-nonce");
	if (!nonce || nonce === previousNonce) {
		throw new Error(`${label} did not provide a fresh request nonce`);
	}
	const html = await response.text();
	assertNoBlockedInlineBehavior(label, html);
	const scripts = extractInlineScriptElements(html).filter(
		(script) => !script.attributes.includes(`nonce="${nonce}"`),
	);
	return {
		hashes: Array.from(
			new Set(scripts.map((script) => hashInlineScript(script.body))),
		).sort(),
		nonce,
		scripts,
	};
}

function assertDynamicRootScripts(
	hashes: string[],
	scripts: InlineScriptElement[],
): void {
	const required = [
		ORGANIZATION_STRUCTURED_DATA_SCRIPT,
		WEBSITE_STRUCTURED_DATA_SCRIPT,
	].map(hashInlineScript);
	if (required.some((hash) => !hashes.includes(hash))) {
		throw new Error("dynamic root probe omitted a required app-owned script");
	}
	if (
		!scripts.some(
			(script) =>
				script.body.includes("document.documentElement") &&
				script.body.includes("localStorage"),
		)
	) {
		throw new Error("dynamic root probe omitted the next-themes bootstrap");
	}
}

async function collectDynamicRootHashes(): Promise<string[]> {
	const port = await findAvailablePort();
	const nextBin = join(REPO_ROOT, "node_modules/next/dist/bin/next");
	const server = spawn(
		NODE_EXECUTABLE,
		[nextBin, "start", "-p", String(port)],
		{
			cwd: REPO_ROOT,
			env: { ...process.env, NODE_ENV: "production" },
			stdio: "ignore",
		},
	);

	try {
		const first = await readDynamicProbe(
			await waitForDynamicProbe(server, port),
			`${DYNAMIC_PROBE_PATH} dynamic probe`,
		);
		const second = await readDynamicProbe(
			await fetch(`http://localhost:${port}${DYNAMIC_PROBE_PATH}`),
			`${DYNAMIC_PROBE_PATH} second dynamic probe`,
			first.nonce,
		);
		if (JSON.stringify(second.hashes) !== JSON.stringify(first.hashes)) {
			throw new Error("dynamic unnonced inline scripts are not request-stable");
		}
		assertDynamicRootScripts(first.hashes, first.scripts);
		return first.hashes;
	} finally {
		await stopServer(server);
	}
}

function assertCspHeaderSizes(manifest: HashManifest): void {
	for (const [route, hashes] of Object.entries(manifest.routes)) {
		const length = buildCSP(undefined, [...hashes, ...manifest.errors]).length;
		if (length > MAX_CSP_HEADER_BYTES) {
			throw new Error(
				`${route} CSP is ${length} bytes (limit ${MAX_CSP_HEADER_BYTES})`,
			);
		}
	}
	const dynamicLength = buildCSP(REPRESENTATIVE_PRODUCTION_NONCE, [
		...manifest.dynamicRoot,
		...manifest.errors,
	]).length;
	if (dynamicLength > MAX_CSP_HEADER_BYTES) {
		throw new Error(
			`dynamic CSP is ${dynamicLength} bytes (limit ${MAX_CSP_HEADER_BYTES})`,
		);
	}
}

function prerenderedHtmlPath(
	htmlArtifacts: Map<string, string>,
	route: string,
	dataRoute: string,
): string {
	const name = artifactNameForDataRoute(dataRoute);
	const htmlPath = htmlArtifacts.get(name);
	if (!htmlPath) {
		throw new Error(
			`${route} is missing prerendered HTML ${name}.html under ${SERVER_OUTPUT}`,
		);
	}
	return htmlPath;
}

function collectPrerenderRouteHashes(
	prerenderManifest: PrerenderManifest,
	htmlArtifacts: Map<string, string>,
): {
	internalErrors: Map<string, string[]>;
	mappedHtmlPaths: Set<string>;
	routes: Record<string, string[]>;
} {
	const routes: Record<string, string[]> = {};
	const internalErrors = new Map<string, string[]>();
	const mappedHtmlPaths = new Set<string>();
	for (const [route, entry] of Object.entries(prerenderManifest.routes).sort(
		([left], [right]) => left.localeCompare(right),
	)) {
		if (entry.dataRoute === null || entry.dataRoute === undefined) continue;
		const htmlPath = prerenderedHtmlPath(htmlArtifacts, route, entry.dataRoute);
		mappedHtmlPaths.add(htmlPath);
		const html = readFileSync(htmlPath, "utf8");
		assertNoBlockedInlineBehavior(route, html);
		const hashes = extractInlineScriptHashes(html);
		if (INTERNAL_ERROR_ROUTES.has(route)) internalErrors.set(route, hashes);
		else routes[route] = hashes;
	}
	return { internalErrors, mappedHtmlPaths, routes };
}

function mergeRawMarkupRoutes(
	routes: Record<string, string[]>,
	internalErrors: Map<string, string[]>,
): void {
	for (const [route, hashes] of Object.entries(collectRawMarkupRouteHashes())) {
		if (routes[route] || internalErrors.has(route)) {
			throw new Error(`duplicate static CSP route artifact: ${route}`);
		}
		routes[route] = hashes;
	}
}

function assertPrerenderCoverage(
	htmlArtifacts: Map<string, string>,
	mappedHtmlPaths: Set<string>,
	internalErrors: Map<string, string[]>,
): void {
	const unmapped = [...htmlArtifacts.values()]
		.filter((path) => !mappedHtmlPaths.has(path))
		.sort();
	if (unmapped.length > 0) {
		throw new Error(`unmapped prerendered HTML: ${unmapped.join(", ")}`);
	}
	for (const route of INTERNAL_ERROR_ROUTES) {
		if ((internalErrors.get(route)?.length ?? 0) === 0) {
			throw new Error(`missing inline CSP hashes for ${route}`);
		}
	}
}

function assertBlogCoverage(
	prerenderManifest: PrerenderManifest,
	routes: Record<string, string[]>,
	htmlArtifacts: Map<string, string>,
): void {
	const expected = blogSlugs.map((slug) => `/blog/${slug}`).sort();
	const missingPath = expected.find((path) => !routes[path]);
	if (missingPath) {
		throw new Error(`missing prerendered HTML + CSP hashes for ${missingPath}`);
	}
	const actual = Object.keys(routes)
		.filter((path) => path.startsWith("/blog/") && path !== "/blog/releases")
		.sort();
	if (JSON.stringify(actual) !== JSON.stringify(expected)) {
		throw new Error(
			`blog article prerender set drifted: expected ${expected.join(", ")}; got ${actual.join(", ")}`,
		);
	}
	const common = intersectHashSets(
		expected.map((path) => routes[path] ?? []),
	).sort();
	const required = [
		ORGANIZATION_STRUCTURED_DATA_SCRIPT,
		WEBSITE_STRUCTURED_DATA_SCRIPT,
	].map(hashInlineScript);
	const missingHash = required.find((hash) => !common.includes(hash));
	if (missingHash) {
		throw new Error(
			`root inline script hash is not common to every blog article page: ${missingHash}`,
		);
	}
	const bodies = expected
		.map((path) => {
			const dataRoute = prerenderManifest.routes[path]?.dataRoute;
			if (!dataRoute) throw new Error(`missing data route for ${path}`);
			return readFileSync(
				prerenderedHtmlPath(htmlArtifacts, path, dataRoute),
				"utf8",
			);
		})
		.flatMap(extractInlineScripts)
		.filter((script) => common.includes(hashInlineScript(script)));
	if (
		!bodies.some(
			(script) =>
				script.includes("document.documentElement") &&
				script.includes("localStorage"),
		)
	) {
		throw new Error(
			"next-themes bootstrap hash is not common to every blog article page",
		);
	}
}

function collectLegacyErrorHashes(): string[][] {
	return [
		join(NEXT_OUTPUT, "server/pages/404.html"),
		join(NEXT_OUTPUT, "server/pages/500.html"),
	].map((path) => {
		if (!existsSync(path))
			throw new Error(`missing legacy error HTML at ${path}`);
		const html = readFileSync(path, "utf8");
		assertNoBlockedInlineBehavior(path, html);
		const hashes = extractInlineScriptHashes(html);
		if (hashes.length === 0) {
			throw new Error(`legacy error HTML has no inline scripts: ${path}`);
		}
		return hashes;
	});
}

export async function collectHashManifest(): Promise<HashManifest> {
	const prerenderManifest = JSON.parse(
		readFileSync(PRERENDER_MANIFEST, "utf8"),
	) as PrerenderManifest;
	const htmlArtifacts = collectPrerenderArtifacts(SERVER_OUTPUT, ".html");
	const { internalErrors, mappedHtmlPaths, routes } =
		collectPrerenderRouteHashes(prerenderManifest, htmlArtifacts);
	mergeRawMarkupRoutes(routes, internalErrors);
	assertPrerenderCoverage(htmlArtifacts, mappedHtmlPaths, internalErrors);
	assertBlogCoverage(prerenderManifest, routes, htmlArtifacts);
	const legacyErrorHashes = collectLegacyErrorHashes();
	const dynamicRoot = await collectDynamicRootHashes();
	const manifest = {
		dynamicRoot,
		errors: Array.from(
			new Set([...internalErrors.values(), ...legacyErrorHashes].flat()),
		).sort(),
		routes,
	};
	assertCspHeaderSizes(manifest);
	return manifest;
}

function renderStringArray(values: readonly string[], indent: string): string {
	if (values.length === 0) {
		return "[]";
	}
	return `[\n${values.map((value) => `${indent}\t${JSON.stringify(value)},`).join("\n")}\n${indent}]`;
}

export function renderHashManifest(manifest: HashManifest): string {
	const canonicalRoutes = new Map<string, string>();
	for (const route of Object.keys(manifest.routes)) {
		const lowercasedRoute = route.toLowerCase();
		const collision = canonicalRoutes.get(lowercasedRoute);
		if (collision && collision !== route) {
			throw new Error(
				`case-insensitive static route collision: ${collision} and ${route}`,
			);
		}
		canonicalRoutes.set(lowercasedRoute, route);
	}
	const routeEntries = Object.entries(manifest.routes)
		.sort(([left], [right]) => left.localeCompare(right))
		.map(
			([route, hashes]) =>
				`\t${JSON.stringify(route)}: ${renderStringArray(hashes, "\t")},`,
		)
		.join("\n");

	return `/* This file is generated by scripts/44-build-web-csp.ts. Do not edit it manually. */

export const STATIC_INLINE_SCRIPT_HASHES: Readonly<
	Record<string, readonly string[]>
> = {
${routeEntries}
};

export const DYNAMIC_ROOT_INLINE_SCRIPT_HASHES: readonly string[] = ${renderStringArray(manifest.dynamicRoot, "")};

export const ERROR_INLINE_SCRIPT_HASHES: readonly string[] = ${renderStringArray(manifest.errors, "")};
`;
}

function runNextBuild(label: string): void {
	console.log(`\n[web-csp] ${label}`);
	rmSync(NEXT_OUTPUT, { force: true, recursive: true });
	const nextBin = join(REPO_ROOT, "node_modules/next/dist/bin/next");
	const result = spawnSync(NODE_EXECUTABLE, [nextBin, "build"], {
		cwd: REPO_ROOT,
		stdio: "inherit",
	});
	if (result.status !== 0) {
		throw new Error(`next build failed during ${label}`);
	}
}

async function main(): Promise<void> {
	runNextBuild("build pass 1");
	const generated = renderHashManifest(await collectHashManifest());
	const current = existsSync(GENERATED_MANIFEST)
		? readFileSync(GENERATED_MANIFEST, "utf8")
		: "";

	if (current === generated) {
		console.log("[web-csp] generated hash manifest is current");
		return;
	}

	writeFileSync(GENERATED_MANIFEST, generated, "utf8");
	runNextBuild("build pass 2 after hash manifest refresh");
	const verified = renderHashManifest(await collectHashManifest());
	if (verified !== generated) {
		throw new Error(
			"inline CSP hashes changed after the manifest rebuild; refusing a stale artifact",
		);
	}
	console.log("[web-csp] generated hash manifest verified after rebuild");
}

if (import.meta.main) {
	await main();
}
