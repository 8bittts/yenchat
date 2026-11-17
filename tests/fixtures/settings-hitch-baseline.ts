import { expect } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Shared settings-hitch baseline helpers used by both the default-lane CSV
 * contract test (126 .test.ts) and the policy-lane architecture-doc parity
 * check (126 .policy.ts). Keeping the parser/constants here avoids duplicating
 * them across the two lanes.
 */
const repoRoot = process.cwd();
export const settingsDocPath = join(repoRoot, "_docs/13-desktop-features.md");
export const summaryCsvPath = join(
	repoRoot,
	"tests/fixtures/settings-hitches/2026-03-05-summary.csv",
);

export const requiredScenarios = [
	"first-open",
	"reopen",
	"rapid-tabs",
	"sounds-refresh",
] as const;

export const requiredColumns = [
	"scenario",
	"hitches_rows",
	"hitches_max_ms",
	"hitches_p95_ms",
	"hitches_over100ms",
	"expensive_updates",
	"expensive_renders",
	"potential_hangs",
	"potential_hang_max_ms",
] as const;

export const thresholdOffsets: Record<string, number> = {
	hitches_rows: 10,
	hitches_max_ms: 100,
	hitches_p95_ms: 50,
	hitches_over100ms: 2,
	expensive_updates: 1,
	expensive_renders: 1,
	potential_hangs: 2,
	potential_hang_max_ms: 100,
};

export type BaselineRow = Record<(typeof requiredColumns)[number], string>;

export const thresholdColumns = Object.keys(
	thresholdOffsets,
) as (keyof typeof thresholdOffsets & keyof BaselineRow)[];

export function parseSummaryCsv(): BaselineRow[] {
	const csv = readFileSync(summaryCsvPath, "utf8").trim();
	const [headerLine = "", ...rowLines] = csv.split(/\r?\n/);
	const headers = headerLine.split(",");

	expect(headers).toEqual([...requiredColumns]);

	return rowLines.map((line) => {
		const values = line.split(",");
		expect(values).toHaveLength(headers.length);

		return Object.fromEntries(
			headers.map((header, index) => [header, values[index]]),
		) as BaselineRow;
	});
}

export function formatBudget(value: number): string {
	return Number.isInteger(value) ? String(value) : value.toFixed(2);
}
