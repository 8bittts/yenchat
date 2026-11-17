#!/usr/bin/env bun
import {
	PUBLIC_LIBRARY_PAGES,
	PUBLIC_LIBRARY_SOURCE_CHECKED_AT,
} from "../lib/library/public-pages";

type OutputFormat = "text" | "json";

interface SourceRecord {
	title: string;
	url: string;
	owners: string[];
	lastCheckedAt: string[];
}

interface SourceCheckResult extends SourceRecord {
	status: "ok" | "stale" | "failed";
	httpStatus?: number;
	error?: string;
}

interface SourceCheckOptions {
	format: OutputFormat;
	listOnly: boolean;
	maxAgeDays: number;
	timeoutMs: number;
}

function printHelp() {
	console.log(`Usage: bun scripts/43-check-library-sources.ts [options]

Checks official source URLs used by public comparison and use-case pages.

Options:
  --json                 Print machine-readable JSON.
  --list-only            Do not fetch URLs; list the source inventory only.
  --max-age-days <days>  Fail sources older than this many days. Default: 30.
  --timeout-ms <ms>      Per-request timeout. Default: 12000.
  --help                 Show this help.
`);
}

function valueAfter(args: string[], flag: string, fallback: string) {
	const index = args.indexOf(flag);
	if (index === -1) {
		return fallback;
	}

	const value = args[index + 1];
	if (!value || value.startsWith("--")) {
		throw new Error(`${flag} requires a value`);
	}
	return value;
}

function parseOptions(args: string[]): SourceCheckOptions {
	if (args.includes("--help")) {
		printHelp();
		process.exit(0);
	}

	const maxAgeDays = Number.parseInt(
		valueAfter(args, "--max-age-days", "30"),
		10,
	);
	const timeoutMs = Number.parseInt(
		valueAfter(args, "--timeout-ms", "12000"),
		10,
	);
	if (!Number.isFinite(maxAgeDays) || maxAgeDays < 0) {
		throw new Error("--max-age-days must be a non-negative number");
	}
	if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
		throw new Error("--timeout-ms must be a positive number");
	}

	return {
		format: args.includes("--json") ? "json" : "text",
		listOnly: args.includes("--list-only"),
		maxAgeDays,
		timeoutMs,
	};
}

function addSource(
	sources: Map<string, SourceRecord>,
	source: { title: string; url: string; lastCheckedAt: string },
	owner: string,
) {
	const existing = sources.get(source.url);
	if (existing) {
		existing.owners.push(owner);
		if (!existing.lastCheckedAt.includes(source.lastCheckedAt)) {
			existing.lastCheckedAt.push(source.lastCheckedAt);
		}
		return;
	}

	sources.set(source.url, {
		title: source.title,
		url: source.url,
		owners: [owner],
		lastCheckedAt: [source.lastCheckedAt],
	});
}

function collectSourceRecords() {
	const sources = new Map<string, SourceRecord>();

	for (const page of PUBLIC_LIBRARY_PAGES) {
		for (const source of page.officialSources) {
			addSource(sources, source, `public:${page.path}`);
		}
	}

	return [...sources.values()].sort((a, b) => a.url.localeCompare(b.url));
}

function isStale(lastCheckedAt: string, maxAgeDays: number) {
	const checkedAt = new Date(`${lastCheckedAt}T00:00:00.000Z`).getTime();
	if (!Number.isFinite(checkedAt)) {
		return true;
	}

	const ageMs = Date.now() - checkedAt;
	return ageMs > maxAgeDays * 24 * 60 * 60 * 1000;
}

async function fetchStatus(url: string, timeoutMs: number) {
	const headers = {
		"User-Agent": "YEN source refresh checker (+https://yen.chat)",
	};
	const signal = AbortSignal.timeout(timeoutMs);

	const head = await fetch(url, { headers, method: "HEAD", signal });
	if (head.ok) {
		return head.status;
	}

	if (head.status !== 403 && head.status !== 405) {
		return head.status;
	}

	const get = await fetch(url, { headers, method: "GET", signal });
	return get.status;
}

async function checkSource(
	source: SourceRecord,
	options: SourceCheckOptions,
): Promise<SourceCheckResult> {
	if (source.lastCheckedAt.some((date) => isStale(date, options.maxAgeDays))) {
		return { ...source, status: "stale" };
	}

	try {
		const httpStatus = await fetchStatus(source.url, options.timeoutMs);
		return {
			...source,
			status: httpStatus >= 200 && httpStatus < 400 ? "ok" : "failed",
			httpStatus,
		};
	} catch (error) {
		return {
			...source,
			status: "failed",
			error: error instanceof Error ? error.message : String(error),
		};
	}
}

function printText(results: SourceCheckResult[], listOnly: boolean) {
	console.log(`Library source check (${results.length} unique URL(s))`);
	console.log(`Public pages checked at: ${PUBLIC_LIBRARY_SOURCE_CHECKED_AT}`);

	for (const result of results) {
		const suffix = listOnly
			? "listed"
			: [result.status, result.httpStatus ? `http=${result.httpStatus}` : null]
					.filter(Boolean)
					.join(" ");
		console.log(`- ${suffix}: ${result.title} <${result.url}>`);
		if (result.error) {
			console.log(`  error: ${result.error}`);
		}
	}
}

async function main() {
	const options = parseOptions(Bun.argv.slice(2));
	const sources = collectSourceRecords();
	const results = options.listOnly
		? sources.map((source) => ({ ...source, status: "ok" as const }))
		: await Promise.all(sources.map((source) => checkSource(source, options)));
	const failures = results.filter((result) => result.status !== "ok");

	if (options.format === "json") {
		console.log(
			JSON.stringify(
				{
					ok: failures.length === 0,
					listOnly: options.listOnly,
					sourceCount: results.length,
					failures,
					results,
				},
				null,
				2,
			),
		);
	} else {
		printText(results, options.listOnly);
		if (failures.length > 0) {
			console.error(`\n${failures.length} source check(s) need attention.`);
		}
	}

	if (failures.length > 0) {
		process.exit(1);
	}
}

await main();
