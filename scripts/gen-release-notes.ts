#!/usr/bin/env bun
/**
 * Generate the week-grouped release-notes dataset for the public /release page.
 *
 * Structure source of truth: the frozen `app/release/release-ledger.ts` for builds
 * shipped before the repository went open source, then the
 * `public/stable/version.json` bump commits, which carry a
 * `vX.YYY: <summary> [deploy]` subject per later build. Those define
 * WHICH builds exist and WHEN they shipped; we group them into Monday-Sunday
 * release weeks (newest first), preserving each version's ship day inside its
 * weekly entry — see the "Release Notes Page" rules in `_docs/10-gtm.md`.
 *
 * Voice source of truth: `app/release/release-notes-copy.ts` has two layers.
 * RELEASE_COPY preserves a customer-facing fact line per version, while
 * RELEASE_WEEK_COPY supplies the narrative story actually rendered for each
 * Monday-Sunday batch. Missing weekly copy fails closed: the public page must
 * read like a product story, not an automatically concatenated dev log.
 *
 * Accuracy guardrail (per `_docs/10-gtm.md`): only clean `vX.YYY:` bump commits
 * become public entries. Non-standard `version.json` touches — reverts,
 * test-version toggles, and prose commits that merely happened to edit the file
 * — are intentionally EXCLUDED so the public changelog never shows a revert or a
 * test build. Retired-runtime references (chat / mail / calendar / accounts /
 * login) are excluded via the RETIRED regex on the FALLBACK copy plus an explicit
 * RELEASE_EXCLUDE set for account-era builds whose wording lacks a keyword. Every
 * exclusion is counted and printed so it is never silent.
 *
 * Regenerate at release time:  bun scripts/gen-release-notes.ts
 * The emitted `app/release/release-notes-data.ts` is generated — never hand-edit;
 * edit `release-notes-copy.ts` instead and regenerate.
 */
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import {
	LEDGER_LAST_VERSION,
	PRE_OPEN_SOURCE_RELEASES,
} from "../app/release/release-ledger";
import {
	RELEASE_COPY,
	RELEASE_EXCLUDE,
	RELEASE_WEEK_COPY,
} from "../app/release/release-notes-copy";

const OUT = join(
	import.meta.dir,
	"..",
	"app",
	"release",
	"release-notes-data.ts",
);

// Subject shape: "v1.136: Ghostty terminal-search fingerprint fix [deploy]"
const BUMP = /^v(\d+\.\d+(?:\.\d+)?):\s*(.+?)\s*(?:\[deploy\])?\s*$/;

// Public-copy guardrails (see _docs/10-gtm.md → "Release Notes Page"):
//  1. [HARD REQUIREMENT] never print the upstream terminal-engine name; say
//     "terminal engine". Also drop the bare commit hash that often trails it.
//  2. Retired runtimes (chat / mail / calendar) must not be described as current
//     features. Raw dev-log summaries lack the "retired experiment" framing, so
//     any version whose summary references one is EXCLUDED from the public page
//     rather than mis-framed. Both transformations are counted and printed.
// `email`/`gmail` are deliberately listed in addition to `\bmail\b` because a
// word boundary does not fall inside "email"/"gmail", so the bare `mail` token
// would miss them and leak retired mail-era copy onto the public page.
const RETIRED = /\b(chat|mail|email|gmail|calendar|messaging|inbox|weather)\b/i;

// Weekly stories are authored as blank-line-separated paragraphs, so sanitize
// each paragraph independently — the `\s{2,}` collapse below would otherwise
// flatten the paragraph breaks the /release page renders on.
function sanitizeEngineName(summary: string): string {
	return summary
		.split("\n\n")
		.map((paragraph) => sanitizeParagraph(paragraph))
		.join("\n\n");
}

function sanitizeParagraph(summary: string): string {
	const out = summary
		.replace(/\bghostty\s+[0-9a-f]{6,}\b/gi, "terminal engine")
		.replace(/\bghostty\b/gi, "terminal engine")
		.replace(
			/\bterminal engine update \(terminal engine\)/gi,
			"terminal engine update",
		)
		// "Ghostty terminal-search fix" must not read as
		// "terminal engine terminal-search fix". Only strip the engine label when
		// the remainder is clearly another "terminal-*" product feature name.
		.replace(
			/^terminal engine (terminal[- ].+)$/i,
			(_m, rest: string) => rest.charAt(0).toUpperCase() + rest.slice(1),
		)
		.replace(/\(\s*\)/g, "")
		.replace(/\s{2,}/g, " ")
		.trim();
	return out;
}

// Curated copy is the public voice, so the engine name must never appear in it:
// sanitizeParagraph() below would silently rewrite it, and a hand-written
// "syncs to Ghostty 1.4" then shipped as "syncs to terminal engine 1.4". The
// sanitizer stays as the net for raw commit subjects, where the name is expected;
// curated copy fails closed instead, so the slip is fixed at the source.
const ENGINE_NAME = /\bghostty\b/i;
const namedEngineKeys = [
	...Object.entries(RELEASE_COPY).map(
		([version, text]) => [`RELEASE_COPY["${version}"]`, text] as const,
	),
	...Object.entries(RELEASE_WEEK_COPY).map(
		([iso, text]) => [`RELEASE_WEEK_COPY["${iso}"]`, text] as const,
	),
]
	.filter(([, text]) => ENGINE_NAME.test(text))
	.map(([label]) => label);

if (namedEngineKeys.length > 0) {
	throw new Error(
		`Curated release copy must not name the upstream engine; rewrite ${namedEngineKeys.length} entr${namedEngineKeys.length === 1 ? "y" : "ies"}: ${namedEngineKeys.join(", ")}`,
	);
}

const MONTHS = [
	"Jan",
	"Feb",
	"Mar",
	"Apr",
	"May",
	"Jun",
	"Jul",
	"Aug",
	"Sep",
	"Oct",
	"Nov",
	"Dec",
];

function isoFromUtc(date: Date): string {
	return date.toISOString().slice(0, 10);
}

function utcDate(iso: string): Date {
	const [year, month, day] = iso.split("-").map(Number);
	return new Date(Date.UTC(year ?? 0, (month ?? 1) - 1, day ?? 1));
}

function weekStartIso(iso: string): string {
	const date = utcDate(iso);
	const daysSinceMonday = (date.getUTCDay() + 6) % 7;
	date.setUTCDate(date.getUTCDate() - daysSinceMonday);
	return isoFromUtc(date);
}

function addUtcDays(iso: string, days: number): string {
	const date = utcDate(iso);
	date.setUTCDate(date.getUTCDate() + days);
	return isoFromUtc(date);
}

function weekLabel(startIso: string): string {
	const endIso = addUtcDays(startIso, 6);
	const [startYear, startMonth, startDay] = startIso.split("-").map(Number);
	const [endYear, endMonth, endDay] = endIso.split("-").map(Number);
	const startName = MONTHS[(startMonth ?? 1) - 1] ?? "";
	const endName = MONTHS[(endMonth ?? 1) - 1] ?? "";
	if (startYear === endYear && startMonth === endMonth) {
		return `Week of ${startName} ${startDay}–${endDay}, ${startYear}`;
	}
	if (startYear === endYear) {
		return `Week of ${startName} ${startDay}–${endName} ${endDay}, ${startYear}`;
	}
	return `Week of ${startName} ${startDay}, ${startYear}–${endName} ${endDay}, ${endYear}`;
}

// The Thursday belongs to the majority month of every Monday-Sunday week.
// Use it for the compact month navigation so cross-month weeks land naturally.
function weekMonthLabel(startIso: string): string {
	const anchor = addUtcDays(startIso, 3);
	const [year, month] = anchor.split("-").map(Number);
	return `${MONTHS[(month ?? 1) - 1] ?? ""} ${year}`;
}

// Numeric compare for versions like "1.136" / "0.3.4" (descending).
function cmpVersionDesc(a: string, b: string): number {
	const pa = a.split(".").map(Number);
	const pb = b.split(".").map(Number);
	for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
		const diff = (pb[i] ?? 0) - (pa[i] ?? 0);
		if (diff !== 0) return diff;
	}
	return 0;
}

const raw = execFileSync(
	"git",
	[
		"log",
		"--format=%ad%x09%s",
		"--date=short",
		"--",
		"public/stable/version.json",
	],
	{ encoding: "utf8" },
);

type Entry = { version: string; summary: string; shippedOn: string };
// week start -> version -> entry (dedupe a version to its OLDEST bump = ship day).
const byWeek = new Map<string, Map<string, Entry>>();
const versionFirstSeenDate = new Map<string, string>();
const curatedUsed = new Set<string>();
const fallbackVersions: string[] = [];
let skipped = 0;
let retiredExcluded = 0;

// Records one shipped build. The first record of a version wins, so the ledger
// (seen first) and then the OLDEST git bump fix its ship day; later re-touches
// are ignored. A ledger build has no commit subject, so it needs curated copy.
function recordVersion(version: string, iso: string, rawSummary: string): void {
	if (!version || versionFirstSeenDate.has(version)) return;
	versionFirstSeenDate.set(version, iso);
	// Explicit account/test-era exclusions whose wording lacks a retired keyword.
	if (RELEASE_EXCLUDE[version]) {
		retiredExcluded++;
		return;
	}
	// Curated copy is the public voice; the commit summary is the fallback. Run
	// the retired-runtime guard against the FINAL public text so a curated line
	// can rescue a mixed build (surviving feature only) while a raw fallback that
	// still mentions a retired runtime is excluded rather than mis-framed.
	const curated = RELEASE_COPY[version];
	const publicText = curated ?? rawSummary;
	if (RETIRED.test(publicText)) {
		retiredExcluded++;
		return;
	}
	// Curated copy is authored engine-name-clean, but sanitize unconditionally so
	// a stray fallback (or a future editing slip) can never leak the engine name.
	if (curated) curatedUsed.add(version);
	else fallbackVersions.push(version);
	const weekIso = weekStartIso(iso);
	if (!byWeek.has(weekIso)) byWeek.set(weekIso, new Map());
	byWeek.get(weekIso)?.set(version, {
		version,
		summary: sanitizeEngineName(publicText),
		shippedOn: iso,
	});
}

for (const { version, shippedOn } of PRE_OPEN_SOURCE_RELEASES) {
	recordVersion(version, shippedOn, "");
}

// git log is newest-first; iterate reversed so the OLDEST occurrence of a
// version wins (its original ship date).
const lines = raw.split("\n").filter(Boolean).reverse();
for (const line of lines) {
	const sep = line.indexOf("\t");
	if (sep === -1) continue;
	const match = line.slice(sep + 1).match(BUMP);
	if (!match) {
		skipped++;
		continue;
	}
	recordVersion(match[1] ?? "", line.slice(0, sep), (match[2] ?? "").trim());
}

// Keys for the private era cannot all match: its excluded builds have no ledger
// row and no public commit, so only keys after LEDGER_LAST_VERSION are checked.
function isAfterLedger(version: string): boolean {
	return cmpVersionDesc(version, LEDGER_LAST_VERSION) < 0;
}

// A curated/excluded key that never matched a real shipped version is almost
// always a typo in release-notes-copy.ts — surface it loudly so the voice layer
// cannot silently rot as versions are added.
const unusedCurated = Object.keys(RELEASE_COPY).filter(
	(v) => isAfterLedger(v) && !curatedUsed.has(v),
);
const unusedExclude = Object.keys(RELEASE_EXCLUDE).filter(
	(v) => isAfterLedger(v) && !versionFirstSeenDate.has(v),
);
const missingWeekCopy = [...byWeek.keys()].filter(
	(iso) => !RELEASE_WEEK_COPY[iso],
);
const unusedWeekCopy = Object.keys(RELEASE_WEEK_COPY).filter(
	(iso) => !byWeek.has(iso),
);

if (fallbackVersions.length > 0) {
	throw new Error(
		`Missing RELEASE_COPY for ${fallbackVersions.length} shipped version(s): ${fallbackVersions.join(", ")}`,
	);
}

if (missingWeekCopy.length > 0) {
	throw new Error(
		`Missing RELEASE_WEEK_COPY for ${missingWeekCopy.length} release week(s): ${missingWeekCopy.join(", ")}`,
	);
}

const weeks = [...byWeek.entries()]
	.sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0)) // newest week first
	.map(([iso, versions]) => {
		const sorted = [...versions.values()].sort((a, b) => {
			if (a.shippedOn !== b.shippedOn) {
				return a.shippedOn < b.shippedOn ? 1 : -1;
			}
			return cmpVersionDesc(a.version, b.version);
		});
		return {
			iso,
			label: weekLabel(iso),
			month: weekMonthLabel(iso),
			// Weekly copy is authored engine-name-clean, but sanitize it on the same
			// terms as per-version copy so an editing slip can never leak the
			// upstream engine name onto the public page.
			summary: sanitizeEngineName(RELEASE_WEEK_COPY[iso] ?? ""),
			builds: sorted.length,
			latestVersion: sorted[0]?.version ?? "",
			versions: sorted.map(({ version, shippedOn }) => ({
				version,
				shippedOn,
			})),
		};
	});

const totalVersions = weeks.reduce((n, week) => n + week.versions.length, 0);

const header = `// GENERATED by scripts/gen-release-notes.ts — do not hand-edit.
// Week-grouped release history: structure/dates from app/release/release-ledger.ts
// and public/stable/version.json bump commits, public voice from app/release/release-notes-copy.ts (RELEASE_WEEK_COPY).
// To reword an entry, edit release-notes-copy.ts and regenerate — never this file.
// Regenerate at release time: bun scripts/gen-release-notes.ts
// See _docs/10-gtm.md -> "Release Notes Page".

export type ReleaseVersion = { version: string; shippedOn: string };
export type ReleaseWeek = { iso: string; label: string; month: string; summary: string; builds: number; latestVersion: string; versions: readonly ReleaseVersion[] };

export const RELEASE_WEEKS: readonly ReleaseWeek[] = ${JSON.stringify(weeks, null, "\t")} as const;
`;

writeFileSync(OUT, header);
const curatedCount = curatedUsed.size;
console.log(
	`release-notes: ${weeks.length} weeks, ${totalVersions} versions -> ${OUT}\n` +
		`  ${curatedCount}/${totalVersions} versions use curated copy; ${totalVersions - curatedCount} fall back to the commit summary.\n` +
		`  skipped ${skipped} non-standard version.json commits (reverts / test toggles / prose).\n` +
		`  excluded ${retiredExcluded} versions (retired runtimes + account/test-era builds) per _docs/10-gtm.md.` +
		(unusedCurated.length
			? `\n  [WARN] ${unusedCurated.length} curated key(s) matched no shipped version (typo?): ${unusedCurated.join(", ")}`
			: "") +
		(unusedExclude.length
			? `\n  [WARN] ${unusedExclude.length} exclude key(s) matched no shipped version (typo?): ${unusedExclude.join(", ")}`
			: "") +
		`\n  ${weeks.length}/${weeks.length} release weeks use curated narrative copy.` +
		(unusedWeekCopy.length
			? `\n  [WARN] ${unusedWeekCopy.length} weekly key(s) matched no release week (typo?): ${unusedWeekCopy.join(", ")}`
			: ""),
);
