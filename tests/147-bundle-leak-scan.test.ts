import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	collectCredentials,
	encodingsFor,
	isNonCredential,
	PRERENDER_OUTPUTS,
	parseEnvFile,
	scanArtifacts,
	unlistedEnvFileCredentials,
} from "../scripts/46-scan-bundle-leaks";

const REPO_ROOT = join(import.meta.dir, "..");

describe("bundle leak scan wiring", () => {
	/*
	 * A security gate that is not wired into `build` is a gate nobody runs.
	 * This is the single most important assertion in the file.
	 */
	test("the scan runs as part of bun run build", () => {
		const packageJson = JSON.parse(
			readFileSync(join(REPO_ROOT, "package.json"), "utf8"),
		) as { scripts: Record<string, string> };
		expect(packageJson.scripts.build).toContain("46-scan-bundle-leaks.ts");
	});

	test("the scan runs after the build, not before it", () => {
		const packageJson = JSON.parse(
			readFileSync(join(REPO_ROOT, "package.json"), "utf8"),
		) as { scripts: Record<string, string> };
		const build = packageJson.scripts.build ?? "";
		expect(build.indexOf("44-build-web-csp.ts")).toBeLessThan(
			build.indexOf("46-scan-bundle-leaks.ts"),
		);
	});

	/*
	 * Vercel builds set a build adapter, so Next writes prerendered output under
	 * server/route-cache there instead of server/app.
	 */
	test("the scan covers both prerender output layouts", () => {
		expect(PRERENDER_OUTPUTS).toEqual([
			join(REPO_ROOT, ".next/server/app"),
			join(REPO_ROOT, ".next/server/route-cache"),
		]);
	});
});

describe("env parsing", () => {
	test("reads names and values, ignoring comments and blank lines", () => {
		const parsed = parseEnvFile(
			["# comment", "", "A=one", "B = two ", "MALFORMED", "=orphan"].join("\n"),
		);
		expect(parsed.get("A")).toBe("one");
		expect(parsed.get("B")).toBe("two");
		expect(parsed.has("MALFORMED")).toBe(false);
		expect(parsed.size).toBe(2);
	});

	test("strips matched surrounding quotes", () => {
		const parsed = parseEnvFile(['A="quoted"', "B='single'"].join("\n"));
		expect(parsed.get("A")).toBe("quoted");
		expect(parsed.get("B")).toBe("single");
	});

	test("keeps equals signs inside a value", () => {
		expect(parseEnvFile("A=key=with=equals").get("A")).toBe("key=with=equals");
	});
});

describe("classification", () => {
	test("build metadata is excluded by name and prefix", () => {
		expect(isNonCredential("TURBO_CACHE")).toBe(true);
		expect(isNonCredential("VERCEL_GIT_COMMIT_SHA")).toBe(true);
		expect(isNonCredential("NX_DAEMON")).toBe(true);
	});

	test("credentials are never excluded as build metadata", () => {
		for (const name of [
			"ADMIN_PASSWORD",
			"RESEND_API_KEY",
			"SUPABASE_SERVICE_ROLE_KEY",
			"CLOUDFLARE_API_TOKEN",
			"GOOGLE_OAUTH_CLIENT_SECRET",
		]) {
			expect(isNonCredential(name)).toBe(false);
		}
	});

	/*
	 * The NEXT_PUBLIC_ prefix must not act as a blanket exemption — that is the
	 * mislabeled-public-key leak this gate exists to catch.
	 */
	test("an unrecognized NEXT_PUBLIC_ variable is still scanned", () => {
		expect(isNonCredential("NEXT_PUBLIC_STRIPE_SECRET_KEY")).toBe(false);
	});
});

describe("encoding coverage", () => {
	const value = "sk-live-abcdef0123456789";

	test("covers every encoding a leak could survive into the bundle through", () => {
		const labels = encodingsFor(value).map((encoding) => encoding.label);
		for (const required of [
			"raw",
			"json",
			"rsc-flight",
			"uri",
			"base64",
			"js-unicode",
			"js-hex",
			"html-entity-decimal",
			"html-entity-hex",
		]) {
			expect(labels).toContain(required);
		}
	});

	test("no encoding produces an empty needle", () => {
		for (const encoding of encodingsFor(value)) {
			expect(encoding.needle.length).toBeGreaterThan(0);
		}
	});

	/* An empty needle would match every artifact and flood the gate with noise. */
	test("an empty value produces no needles at all", () => {
		expect(encodingsFor("")).toEqual([]);
	});
});

describe("detection", () => {
	const credential = { name: "TEST_TOKEN", value: "tok-abcdef0123456789" };

	test("finds a raw value in an artifact", async () => {
		const path = join(process.env.TMPDIR ?? "/tmp", "bundle-leak-raw.js");
		await Bun.write(path, `const t="${credential.value}";`);
		const findings = scanArtifacts([path], [credential]);
		expect(findings.length).toBeGreaterThan(0);
		expect(findings[0]?.name).toBe("TEST_TOKEN");
	});

	test("finds a value that only appears JS-unicode-escaped", async () => {
		const escaped = Array.from(credential.value)
			.map((char) => `\\u${char.charCodeAt(0).toString(16).padStart(4, "0")}`)
			.join("");
		const path = join(process.env.TMPDIR ?? "/tmp", "bundle-leak-escaped.js");
		await Bun.write(path, `const t="${escaped}";`);
		const findings = scanArtifacts([path], [credential]);
		expect(findings.map((finding) => finding.encoding)).toContain("js-unicode");
	});

	test("finds a value that only appears base64-encoded", async () => {
		const encoded = Buffer.from(credential.value, "utf8").toString("base64");
		const path = join(process.env.TMPDIR ?? "/tmp", "bundle-leak-base64.js");
		await Bun.write(path, `const t="${encoded}";`);
		expect(
			scanArtifacts([path], [credential]).map((finding) => finding.encoding),
		).toContain("base64");
	});

	test("a clean artifact produces no findings", async () => {
		const path = join(process.env.TMPDIR ?? "/tmp", "bundle-leak-clean.js");
		await Bun.write(path, "export const greeting = 'hello world';");
		expect(scanArtifacts([path], [credential])).toEqual([]);
	});

	/* Fail-closed: an empty artifact set must never look like a pass. */
	test("an empty artifact set yields no findings, which the CLI treats as failure", () => {
		expect(scanArtifacts([], [credential])).toEqual([]);
	});
});

describe("CI environment", () => {
	/*
	 * The env files are gitignored and absent on Vercel, where values arrive
	 * through process.env instead. Sourcing names from the files alone made the
	 * gate resolve zero credentials in CI and fail the production build.
	 */
	test("credentials resolve from process.env with no env file present", () => {
		const name = "RESEND_API_KEY";
		const original = process.env[name];
		process.env[name] = "re_ci_only_value_0123456789";
		try {
			const { credentials } = collectCredentials();
			const found = credentials.find((credential) => credential.name === name);
			expect(found?.value).toBe("re_ci_only_value_0123456789");
		} finally {
			if (original === undefined) {
				delete process.env[name];
			} else {
				process.env[name] = original;
			}
		}
	});

	/*
	 * The manifest is what makes CI coverage possible, so it must never empty
	 * out. Assert the positive count, not the absence of findings.
	 */
	test("the scanned-name manifest is non-empty", () => {
		const { credentials, unresolved } = collectCredentials();
		expect(credentials.length + unresolved.length).toBeGreaterThan(0);
	});

	/*
	 * Drift guard: a credential added to a local env file but not to the
	 * manifest would be scanned locally and silently unscanned on Vercel.
	 */
	test("every local env credential is covered by the manifest", () => {
		expect(unlistedEnvFileCredentials()).toEqual([]);
	});
});

describe("live credential set", () => {
	/*
	 * If this ever reaches zero the scan would pass vacuously, so assert the
	 * positive count rather than trusting the absence of findings.
	 */
	test("real credentials are loaded from the env files", () => {
		const { credentials } = collectCredentials();
		expect(credentials.length).toBeGreaterThan(0);
	});

	test("no credential value is empty", () => {
		for (const credential of collectCredentials().credentials) {
			expect(credential.value.length).toBeGreaterThan(0);
		}
	});
});
