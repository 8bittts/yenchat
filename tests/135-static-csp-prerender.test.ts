import { describe, expect, test } from "bun:test";
import {
	existsSync,
	mkdirSync,
	mkdtempSync,
	readFileSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import blogSlugs from "../content/blog/slugs.json";
import {
	DYNAMIC_ROOT_INLINE_SCRIPT_HASHES,
	ERROR_INLINE_SCRIPT_HASHES,
	STATIC_INLINE_SCRIPT_HASHES,
} from "../lib/csp/generated-inline-script-hashes";
import {
	ORGANIZATION_STRUCTURED_DATA_SCRIPT,
	THEME_COLOR_BOOTSTRAP_SCRIPT,
	WEBSITE_STRUCTURED_DATA_SCRIPT,
} from "../lib/csp/inline-scripts";
import { buildCSP } from "../proxy";
import {
	collectPrerenderArtifacts,
	extractInlineScriptHashes,
	hashInlineScript,
	renderHashManifest,
} from "../scripts/44-build-web-csp";
import { computeWebBuildId } from "../scripts/lib/web-build-id";

const CSP_HASH_PATTERN = /^sha256-[A-Za-z0-9+/]{43}=$/;
const OWNER_HASH = "a".repeat(64);

function withServerOutput(
	files: readonly string[],
	check: (serverOutput: string) => void,
): void {
	const root = mkdtempSync(join(tmpdir(), "yen-csp-artifacts-"));
	try {
		mkdirSync(join(root, "app"), { recursive: true });
		for (const file of files) {
			mkdirSync(join(root, file, ".."), { recursive: true });
			writeFileSync(join(root, file), "", "utf8");
		}
		check(root);
	} finally {
		rmSync(root, { force: true, recursive: true });
	}
}

function artifactNames(
	serverOutput: string,
	suffix: ".body" | ".html",
): string[] {
	return [...collectPrerenderArtifacts(serverOutput, suffix).keys()].sort();
}

describe("static CSP prerender build", () => {
	test("Vercel deploy input retains the custom web build entrypoints", () => {
		const vercelIgnore = readFileSync(
			join(process.cwd(), ".vercelignore"),
			"utf8",
		);
		expect(vercelIgnore).not.toMatch(/^scripts\/$/m);
		expect(vercelIgnore).toContain("!scripts/44-build-web-csp.ts");
		expect(vercelIgnore).toContain("!scripts/lib/");
		expect(vercelIgnore).toContain("!scripts/lib/web-build-id.ts");
	});

	/*
	 * .vercelignore excludes scripts/* with a hand-written allowlist, so a script
	 * added to `build` but not to that allowlist is simply absent in the deploy
	 * upload and the production build dies on "Module not found". Derive the list
	 * from package.json instead of enumerating it, so the next one cannot slip.
	 * `bun install` also runs the lifecycle scripts on Vercel, and `build` reaches
	 * more files through `bun run <name>`, so both are followed: a `prepare`
	 * script outside the allowlist failed the install of a production deploy.
	 */
	test("every script the Vercel install and build run survives .vercelignore", () => {
		const packageJson = JSON.parse(
			readFileSync(join(process.cwd(), "package.json"), "utf8"),
		) as { scripts: Record<string, string> };
		const vercelIgnore = readFileSync(
			join(process.cwd(), ".vercelignore"),
			"utf8",
		);
		const referenced = new Set<string>();
		const visited = new Set<string>();
		const collect = (name: string) => {
			if (visited.has(name)) return;
			visited.add(name);
			const command = packageJson.scripts[name] ?? "";
			for (const match of command.matchAll(
				/scripts\/[\w./-]+\.(?:ts|cjs|mjs|js)/g,
			)) {
				referenced.add(match[0]);
			}
			for (const match of command.matchAll(/bun run ([\w:.-]+)/g)) {
				if (match[1]) collect(match[1]);
			}
		};
		for (const name of [
			"preinstall",
			"install",
			"postinstall",
			"prepare",
			"build",
		]) {
			collect(name);
		}
		expect(referenced.has("scripts/setup-hooks.ts")).toBe(true);
		expect(referenced.size).toBeGreaterThan(3);
		for (const script of referenced) {
			expect(vercelIgnore).toContain(`!${script}`);
		}
	});

	/*
	 * The deploy marker is documented as a commit SUBJECT marker. Matching the
	 * whole message let the literal string "[deploy]" written in prose in a body
	 * trigger a real production build — that is exactly how deployment
	 * dpl_HNmY7iHew9kmA9zLsLnxo7TEGLGG was launched and then failed.
	 */
	test("the deploy marker is matched on the commit subject only", () => {
		const vercelConfig = JSON.parse(
			readFileSync(join(process.cwd(), "vercel.json"), "utf8"),
		) as { ignoreCommand: string; regions: string[] };
		expect(vercelConfig.ignoreCommand).toContain("head -1");
		expect(vercelConfig.ignoreCommand).toContain("\\[deploy\\]");
		expect(vercelConfig.regions).toEqual(["pdx1"]);
	});

	test("manifest metadata route has no conflicting public file", () => {
		expect(existsSync(join(process.cwd(), "app/manifest.ts"))).toBe(true);
		expect(existsSync(join(process.cwd(), "public/manifest.webmanifest"))).toBe(
			false,
		);
	});

	test("extracts exact inline bodies while ignoring external-only scripts", () => {
		const first = "globalThis.first = true;";
		const second = '{"@context":"https://schema.org"}';
		const html = `<script src="/external.js"></script><script>${first}</script><script type="application/ld+json">${second}</script>`;
		expect(extractInlineScriptHashes(html)).toEqual(
			[hashInlineScript(first), hashInlineScript(second)].sort(),
		);
	});

	test("reads prerendered artifacts from the default server/app layout", () => {
		withServerOutput(
			[
				"app/index.html",
				"app/blog/skills.html",
				"app/robots.txt.body",
				"app/page.js",
			],
			(serverOutput) => {
				expect(artifactNames(serverOutput, ".html")).toEqual([
					"blog/skills",
					"index",
				]);
				expect(artifactNames(serverOutput, ".body")).toEqual(["robots.txt"]);
			},
		);
	});

	test("reads prerendered artifacts from the build-adapter route-cache layout", () => {
		withServerOutput(
			[
				`route-cache/APP_PAGE/${OWNER_HASH}/$/index.html`,
				`route-cache/APP_PAGE/${"b".repeat(64)}/$/blog/skills.html`,
				`route-cache/APP_PAGE/${OWNER_HASH}/$/index.rsc`,
				`route-cache/APP_ROUTE/${"c".repeat(64)}/$/robots.txt.body`,
				"app/page.js",
			],
			(serverOutput) => {
				expect(artifactNames(serverOutput, ".html")).toEqual([
					"blog/skills",
					"index",
				]);
				expect(artifactNames(serverOutput, ".body")).toEqual(["robots.txt"]);
			},
		);
	});

	test("rejects mixed, unknown, and duplicate route-cache artifacts", () => {
		withServerOutput(
			["app/index.html", `route-cache/APP_PAGE/${OWNER_HASH}/$/index.html`],
			(serverOutput) => {
				expect(() => collectPrerenderArtifacts(serverOutput, ".html")).toThrow(
					"artifacts in both server/app and route-cache",
				);
			},
		);
		withServerOutput(
			[`route-cache/PAGES/${OWNER_HASH}/$/index.html`],
			(serverOutput) => {
				expect(() => collectPrerenderArtifacts(serverOutput, ".html")).toThrow(
					"unexpected route-cache artifact",
				);
			},
		);
		withServerOutput(
			[
				`route-cache/APP_PAGE/${OWNER_HASH}/$/index.html`,
				`route-cache/APP_PAGE/${"b".repeat(64)}/$/index.html`,
			],
			(serverOutput) => {
				expect(() => collectPrerenderArtifacts(serverOutput, ".html")).toThrow(
					"duplicate prerendered index",
				);
			},
		);
	});

	test("generated manifest covers every finite blog article with strict hashes", () => {
		const expectedPaths = blogSlugs.map((slug) => `/blog/${slug}`).sort();
		const actualPaths = Object.keys(STATIC_INLINE_SCRIPT_HASHES)
			.filter((path) => path.startsWith("/blog/") && path !== "/blog/releases")
			.sort();
		expect(actualPaths).toEqual(expectedPaths);

		for (const path of expectedPaths) {
			const hashes = STATIC_INLINE_SCRIPT_HASHES[path] ?? [];
			expect(hashes.length, path).toBeGreaterThan(0);
			expect(new Set(hashes).size, path).toBe(hashes.length);
			expect(
				hashes.every((hash) => CSP_HASH_PATTERN.test(hash)),
				path,
			).toBe(true);
			const csp = buildCSP(undefined, [
				...hashes,
				...ERROR_INLINE_SCRIPT_HASHES,
			]);
			expect(csp.length, path).toBeLessThan(8_000);
			const scriptSrc = csp
				.split("; ")
				.find((directive) => directive.startsWith("script-src "));
			expect(scriptSrc).not.toContain("'unsafe-inline'");
		}
	});

	test("dynamic fallback includes every shared root script and error shell", () => {
		for (const script of [
			THEME_COLOR_BOOTSTRAP_SCRIPT,
			ORGANIZATION_STRUCTURED_DATA_SCRIPT,
			WEBSITE_STRUCTURED_DATA_SCRIPT,
		]) {
			expect(DYNAMIC_ROOT_INLINE_SCRIPT_HASHES).toContain(
				hashInlineScript(script),
			);
		}
		expect(ERROR_INLINE_SCRIPT_HASHES.length).toBeGreaterThan(0);
		expect(STATIC_INLINE_SCRIPT_HASHES["/"]?.length).toBeGreaterThan(0);
		expect(STATIC_INLINE_SCRIPT_HASHES["/terms"]?.length).toBeGreaterThan(0);
	});

	test("generated source is deterministic regardless of object insertion order", () => {
		const left = renderHashManifest({
			dynamicRoot: ["sha256-dynamic"],
			errors: ["sha256-error"],
			routes: { "/z": ["sha256-z"], "/a": ["sha256-a"] },
		});
		const right = renderHashManifest({
			dynamicRoot: ["sha256-dynamic"],
			errors: ["sha256-error"],
			routes: { "/a": ["sha256-a"], "/z": ["sha256-z"] },
		});
		expect(right).toBe(left);
	});

	test("generated source rejects case-insensitive route collisions", () => {
		expect(() =>
			renderHashManifest({
				dynamicRoot: [],
				errors: [],
				routes: { "/Example": [], "/example": [] },
			}),
		).toThrow("case-insensitive static route collision");
	});

	test("content build ID excludes the generated hash manifest cycle", () => {
		const root = mkdtempSync(join(tmpdir(), "yen-web-build-id-"));
		try {
			for (const directory of [
				"app",
				"components",
				"lib/csp",
				"public/stable",
			]) {
				mkdirSync(join(root, directory), { recursive: true });
			}
			for (const file of [
				"bun.lock",
				"next.config.ts",
				"package.json",
				"postcss.config.mjs",
				"proxy.ts",
				"public/stable/version.json",
				"tsconfig.json",
			]) {
				writeFileSync(join(root, file), `${file}\n`, "utf8");
			}
			writeFileSync(join(root, "app/page.tsx"), "first\n", "utf8");
			const generatedPath = join(
				root,
				"lib/csp/generated-inline-script-hashes.ts",
			);
			writeFileSync(generatedPath, "manifest one\n", "utf8");
			const first = computeWebBuildId(root);

			writeFileSync(generatedPath, "manifest two\n", "utf8");
			expect(computeWebBuildId(root)).toBe(first);

			writeFileSync(join(root, "app/page.tsx"), "second\n", "utf8");
			expect(computeWebBuildId(root)).not.toBe(first);

			writeFileSync(join(root, "app/page.tsx"), "first\n", "utf8");
			writeFileSync(
				join(root, "public/stable/version.json"),
				"version two\n",
				"utf8",
			);
			expect(computeWebBuildId(root)).not.toBe(first);
		} finally {
			rmSync(root, { force: true, recursive: true });
		}
	});
});
