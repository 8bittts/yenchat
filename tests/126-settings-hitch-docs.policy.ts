import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import {
	formatBudget,
	parseSummaryCsv,
	requiredScenarios,
	settingsDocPath,
	thresholdColumns,
	thresholdOffsets,
} from "./fixtures/settings-hitch-baseline";

// Policy lane: verbatim source-text/doc-copy parity against _docs/13-desktop-features.md (Settings hitch benchmark).
// Per tests/00-tests-readme.md this must NOT run in the default `bun test` lane.
describe("Settings hitch doc parity (policy)", () => {
	test("settings doc defines repeatable trace commands and pass/fail budgets", () => {
		const doc = readFileSync(settingsDocPath, "utf8");
		const rows = parseSummaryCsv();

		for (const needle of [
			"tests/fixtures/settings-hitches/2026-03-05-summary.csv",
			"tmp/perf/settings-hitches/2026-03-05/summary.csv",
			"scripts/manual/29-run-settings-hitch-benchmark.sh",
			"yen-terminal/ghostty/zig-out/YEN.app",
			"YEN_SETTINGS_HITCH_SCENARIO",
			"YEN_SETTINGS_HITCH_START_FILE",
			"start-file release point",
			'--launch -- "$YEN_TRACE_EXE"',
			"xcrun xctrace record",
			'--template "Animation Hitches"',
			"xcrun xctrace export",
			"--xpath '//trace-toc[1]/run[1]/data[1]/table[62]'",
			"--xpath '//trace-toc[1]/run[1]/data[1]/table[19]'",
			"scenario,hitches_rows,hitches_max_ms,hitches_p95_ms,hitches_over100ms,expensive_updates,expensive_renders,potential_hangs,potential_hang_max_ms",
			"Trace contamination rule",
			"Do not close, quit, or retarget any existing `/Applications/YEN.app` process",
		]) {
			expect(doc).toContain(needle);
		}

		for (const scenario of requiredScenarios) {
			expect(doc).toContain(`\`${scenario}\``);
		}

		for (const row of rows) {
			const budgets = thresholdColumns.map((column) => {
				const offset = thresholdOffsets[column] ?? 0;
				return `${column}<=${formatBudget(Number(row[column]) + offset)}`;
			});
			expect(doc).toContain(`\`${row.scenario}\` | ${budgets.join(" | ")}`);
		}

		for (const failClosedRule of [
			"missing scenario",
			"missing column",
			"non-numeric metric",
			"zero-byte XML",
		]) {
			expect(doc).toContain(failClosedRule);
		}
	});
});
