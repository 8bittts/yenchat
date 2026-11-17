/*
 * Byte-scans the built browser artifacts for the VALUE of every server-side
 * credential, across every encoding Next.js can emit.
 *
 * This gate does not trust the `NEXT_PUBLIC_` prefix or the server/client
 * boundary as proof of safety — a mislabeled public-prefixed credential is the
 * most common catastrophic leak, so a value is only exempt when its name
 * appears in PUBLIC_BY_DESIGN below.
 *
 * It fails closed. Zero credentials, zero artifacts, or an empty artifact class
 * is a failure, never a pass: the natural control flow of an empty loop is a
 * false green, which is the worst outcome for a security check.
 *
 * Findings report the variable NAME and the artifact PATH only. The value is
 * never printed, because this output lands in build logs and CI transcripts.
 */
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..");
const NEXT_OUTPUT = join(REPO_ROOT, ".next");
const STATIC_OUTPUT = join(NEXT_OUTPUT, "static");
/*
 * Prerendered output lives under server/app, except that Next 16.3.8+ writes
 * it under server/route-cache when a build adapter is set, as on Vercel.
 */
export const PRERENDER_OUTPUTS = [
	join(NEXT_OUTPUT, "server/app"),
	join(NEXT_OUTPUT, "server/route-cache"),
];
const ENV_FILES = [
	".env",
	".env.local",
	".env.production",
	".env.production.local",
];

/* Extensions under PRERENDER_OUTPUTS whose bytes are shipped to the browser. */
const BROWSER_FACING_SERVER_SUFFIXES = [".html", ".rsc", ".body"];

/*
 * Values that are published to the browser on purpose. Each entry is an
 * explicit decision, not a naming convention. The site ships no environment
 * value to the browser today, so the set is empty and every credential-shaped
 * name, including any NEXT_PUBLIC_ one, is scanned.
 */
const PUBLIC_BY_DESIGN = new Set<string>();

/*
 * Build, CI, and toolchain metadata. These carry no credential, and several
 * (the commit SHA above all) legitimately appear in bundles, so scanning them
 * would produce guaranteed false positives. Matched by exact name or prefix.
 */
const NON_CREDENTIAL_NAMES = new Set(["NX_DAEMON", "VERCEL", "GSC_SITE_URL"]);
const NON_CREDENTIAL_PREFIXES = [
	"TURBO_",
	"VERCEL_GIT_",
	"VERCEL_ENV",
	"VERCEL_URL",
	"VERCEL_TARGET_ENV",
];

/*
 * The credentials this gate is responsible for, by name.
 *
 * This list exists because the env files are gitignored and absent in CI: on
 * Vercel the values arrive through `process.env` instead, with no file to
 * enumerate. Deriving the name set from `process.env` directly is not an
 * option either — locally that is hundreds of shell variables, and a stray
 * match on one of those would fail the build for no reason.
 *
 * So names come from here (plus anything new found in a local env file), and
 * VALUES are resolved from `process.env` first, falling back to the env files.
 * `tests/147` fails if a local env file holds a credential missing from this
 * list, which is what keeps it from going stale.
 *
 * The drift test can only see local files, so a credential that exists ONLY in
 * the Vercel project (CRON_SECRET was one) is invisible to it. When adding a
 * variable in the Vercel dashboard, reconcile this list against
 * `vercel env ls production` in the same change.
 */
const SCANNED_CREDENTIAL_NAMES = [
	"ADMIN_PASSWORD",
	"ADMIN_SESSION_SECRET",
	"CLOUDFLARE_ACCOUNT_API_TOKEN",
	"CLOUDFLARE_ACCOUNT_API_TOKEN_ID",
	"CLOUDFLARE_ACCOUNT_API_TOKEN_SHA256",
	"CLOUDFLARE_ACCOUNT_ID",
	"CLOUDFLARE_API_TOKEN",
	"CLOUDFLARE_ZONE_ID",
	/* Bearer credential for the removed owner-report cron; lived only on Vercel. */
	"CRON_SECRET",
	"CURSOR_API_KEY",
	"ENCRYPTION_SECRET",
	"GOOGLE_OAUTH_CLIENT_ID",
	"GOOGLE_OAUTH_CLIENT_SECRET",
	"GOOGLE_OAUTH_REFRESH_TOKEN",
	"INTERNAL_API_KEY",
	"NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
	"NEXT_PUBLIC_SUPABASE_URL",
	"OPENCODE_API_KEY",
	"OPENROUTER_API_KEY",
	"RESEND_API_KEY",
	"SUPABASE_API_SECRET_KEY",
	"SUPABASE_DB_PASSWORD",
	"SUPABASE_JWT_SECRET",
	"SUPABASE_SERVICE_ROLE_KEY",
	"UPSTASH_REDIS_REST_TOKEN",
	"UPSTASH_REDIS_REST_URL",
	"VERCEL_OIDC_TOKEN",
] as const;

/*
 * Below this length a value cannot be distinguished from ordinary bundle text,
 * so a match would be noise rather than a leak. Short values are never dropped
 * silently — they are listed by name in the receipt.
 */
const MIN_SCANNABLE_LENGTH = 8;

type Credential = { name: string; value: string };
type Encoding = { label: string; needle: string };
type Finding = { name: string; artifact: string; encoding: string };

export function parseEnvFile(contents: string): Map<string, string> {
	const values = new Map<string, string>();
	for (const rawLine of contents.split("\n")) {
		const line = rawLine.trim();
		if (line.length === 0 || line.startsWith("#")) {
			continue;
		}
		const separator = line.indexOf("=");
		if (separator <= 0) {
			continue;
		}
		const name = line.slice(0, separator).trim();
		if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
			continue;
		}
		let value = line.slice(separator + 1).trim();
		if (
			(value.startsWith('"') && value.endsWith('"') && value.length >= 2) ||
			(value.startsWith("'") && value.endsWith("'") && value.length >= 2)
		) {
			value = value.slice(1, -1);
		}
		values.set(name, value);
	}
	return values;
}

export function isNonCredential(name: string): boolean {
	return (
		NON_CREDENTIAL_NAMES.has(name) ||
		NON_CREDENTIAL_PREFIXES.some((prefix) => name.startsWith(prefix))
	);
}

/*
 * Every encoding a credential could survive into a browser artifact through.
 * A leak that only reaches the bundle JS-escaped or HTML-entity-encoded is
 * exactly as exploitable as a raw one, so raw matching alone is not enough.
 */
export function encodingsFor(value: string): Encoding[] {
	const jsonBody = JSON.stringify(value).slice(1, -1);
	const encodings: Encoding[] = [
		{ label: "raw", needle: value },
		{ label: "json", needle: jsonBody },
		/* RSC/Flight payloads embed a JSON string inside a JSON string. */
		{ label: "rsc-flight", needle: JSON.stringify(jsonBody).slice(1, -1) },
		{ label: "uri", needle: encodeURIComponent(value) },
		{ label: "base64", needle: Buffer.from(value, "utf8").toString("base64") },
	];

	/*
	 * UTF-16 code units, not code points: bundlers escape a non-BMP character
	 * as its surrogate pair, so splitting by code point would build a needle
	 * that never appears in real output.
	 */
	const codePoints = value.split("");
	const unicodeEscaped = codePoints
		.map((char) => `\\u${char.charCodeAt(0).toString(16).padStart(4, "0")}`)
		.join("");
	const hexEscaped = codePoints
		.map((char) => `\\x${char.charCodeAt(0).toString(16).padStart(2, "0")}`)
		.join("");
	const decimalEntities = codePoints
		.map((char) => `&#${char.charCodeAt(0)};`)
		.join("");
	const hexEntities = codePoints
		.map((char) => `&#x${char.charCodeAt(0).toString(16)};`)
		.join("");

	for (const [label, needle] of [
		["js-unicode", unicodeEscaped],
		["js-hex", hexEscaped],
		["html-entity-decimal", decimalEntities],
		["html-entity-hex", hexEntities],
	] as const) {
		encodings.push({ label, needle });
		/* Escape and entity hex digits are case-insensitive in practice. */
		const uppercased = needle.toUpperCase();
		if (uppercased !== needle) {
			encodings.push({ label: `${label}-upper`, needle: uppercased });
		}
	}

	return encodings.filter((encoding) => encoding.needle.length > 0);
}

function collectFiles(
	directory: string,
	suffixes?: readonly string[],
): string[] {
	if (!existsSync(directory)) {
		return [];
	}
	const files: string[] = [];
	for (const entry of readdirSync(directory, { withFileTypes: true })) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) {
			files.push(...collectFiles(path, suffixes));
		} else if (
			entry.isFile() &&
			(!suffixes || suffixes.some((suffix) => entry.name.endsWith(suffix)))
		) {
			files.push(path);
		}
	}
	return files.sort();
}

export function readEnvFiles(): Map<string, string> {
	const merged = new Map<string, string>();
	for (const file of ENV_FILES) {
		const path = join(REPO_ROOT, file);
		if (!existsSync(path)) {
			continue;
		}
		for (const [name, value] of parseEnvFile(readFileSync(path, "utf8"))) {
			merged.set(name, value);
		}
	}
	return merged;
}

/*
 * Credential names a local env file holds that the manifest does not cover.
 * Used by the drift test and reported at runtime, so a newly added credential
 * cannot sit unscanned in CI where the file does not exist.
 */
export function unlistedEnvFileCredentials(
	fileValues: Map<string, string> = readEnvFiles(),
): string[] {
	const listed = new Set<string>(SCANNED_CREDENTIAL_NAMES);
	return Array.from(fileValues.keys())
		.filter(
			(name) =>
				!listed.has(name) &&
				!PUBLIC_BY_DESIGN.has(name) &&
				!isNonCredential(name),
		)
		.sort();
}

export function collectCredentials(): {
	credentials: Credential[];
	publicByDesign: string[];
	unresolved: string[];
	tooShort: string[];
} {
	const fileValues = readEnvFiles();
	/*
	 * process.env wins: on Vercel it is the only source, and locally it is what
	 * the build itself actually saw.
	 */
	const resolve = (name: string): string | undefined =>
		process.env[name] ?? fileValues.get(name);

	const names = Array.from(
		new Set<string>([
			...SCANNED_CREDENTIAL_NAMES,
			...unlistedEnvFileCredentials(fileValues),
		]),
	).sort();

	const credentials: Credential[] = [];
	const unresolved: string[] = [];
	const tooShort: string[] = [];

	for (const name of names) {
		const value = resolve(name);
		if (value === undefined || value.length === 0) {
			unresolved.push(name);
			continue;
		}
		if (value.length < MIN_SCANNABLE_LENGTH) {
			tooShort.push(name);
			continue;
		}
		credentials.push({ name, value });
	}

	const publicByDesign = Array.from(PUBLIC_BY_DESIGN)
		.filter((name) => resolve(name) !== undefined)
		.sort();

	return { credentials, publicByDesign, unresolved, tooShort };
}

export function scanArtifacts(
	artifacts: readonly string[],
	credentials: readonly Credential[],
): Finding[] {
	const needles = credentials.map((credential) => ({
		name: credential.name,
		encodings: encodingsFor(credential.value).map((encoding) => ({
			label: encoding.label,
			bytes: Buffer.from(encoding.needle, "utf8"),
		})),
	}));

	const findings: Finding[] = [];
	for (const artifact of artifacts) {
		const bytes = readFileSync(artifact);
		for (const needle of needles) {
			for (const encoding of needle.encodings) {
				if (bytes.includes(encoding.bytes)) {
					findings.push({
						name: needle.name,
						artifact: relative(REPO_ROOT, artifact),
						encoding: encoding.label,
					});
				}
			}
		}
	}
	return findings;
}

function fail(message: string): never {
	console.error(`[bundle-leaks] FAIL: ${message}`);
	process.exit(1);
}

async function main(): Promise<void> {
	if (!existsSync(NEXT_OUTPUT) || !statSync(NEXT_OUTPUT).isDirectory()) {
		fail(
			`no build output at ${relative(REPO_ROOT, NEXT_OUTPUT)}; run the build first`,
		);
	}

	const { credentials, publicByDesign, unresolved, tooShort } =
		collectCredentials();
	if (credentials.length === 0) {
		fail(
			"no credential values resolved from process.env or the env files, so the scan would pass vacuously",
		);
	}

	const staticArtifacts = collectFiles(STATIC_OUTPUT);
	const serverArtifacts = PRERENDER_OUTPUTS.flatMap((directory) =>
		collectFiles(directory, BROWSER_FACING_SERVER_SUFFIXES),
	);
	if (staticArtifacts.length === 0) {
		fail(`no client bundle files under ${relative(REPO_ROOT, STATIC_OUTPUT)}`);
	}
	if (serverArtifacts.length === 0) {
		fail(
			`no prerendered browser artifacts under ${PRERENDER_OUTPUTS.map((directory) => relative(REPO_ROOT, directory)).join(" or ")}`,
		);
	}
	const artifacts = [...staticArtifacts, ...serverArtifacts];

	/* Report what was excluded. A silent skip reads as "covered everything". */
	if (publicByDesign.length > 0) {
		console.log(
			`[bundle-leaks] public by design, not scanned: ${publicByDesign.join(", ")}`,
		);
	}
	if (unresolved.length > 0) {
		console.log(
			`[bundle-leaks] no value in this environment, not scanned: ${unresolved.join(", ")}`,
		);
	}
	const unlisted = unlistedEnvFileCredentials();
	if (unlisted.length > 0) {
		console.log(
			`[bundle-leaks] found in a local env file but missing from SCANNED_CREDENTIAL_NAMES, so unscanned in CI: ${unlisted.join(", ")}`,
		);
	}
	if (tooShort.length > 0) {
		console.log(
			`[bundle-leaks] shorter than ${MIN_SCANNABLE_LENGTH} chars, not scannable: ${tooShort.join(", ")}`,
		);
	}

	const findings = scanArtifacts(artifacts, credentials);
	if (findings.length > 0) {
		for (const finding of findings) {
			console.error(
				`[bundle-leaks] LEAK ${finding.name} -> ${finding.artifact} (${finding.encoding})`,
			);
		}
		fail(
			`${findings.length} credential value(s) reached the browser bundle across ${new Set(findings.map((finding) => finding.name)).size} variable(s)`,
		);
	}

	console.log(
		`[bundle-leaks] scanned ${credentials.length} credentials against ${artifacts.length} artifacts (${staticArtifacts.length} client bundle, ${serverArtifacts.length} prerendered); no leaks`,
	);
}

if (import.meta.main) {
	await main();
}
