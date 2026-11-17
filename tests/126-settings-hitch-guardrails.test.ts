import { describe, expect, test } from "bun:test";
import {
	parseSummaryCsv,
	requiredColumns,
	requiredScenarios,
} from "./fixtures/settings-hitch-baseline";

// Default-lane behavior/contract check only. The architecture-doc parity
// (source-text) assertions live in the policy lane — see
// tests/126-settings-hitch-docs.policy.ts and tests/00-tests-readme.md.
describe("Settings hitch trace guardrails", () => {
	test("baseline summary keeps the pinned scenario and metric contract", () => {
		const rows = parseSummaryCsv();

		expect(rows.map((row) => row.scenario)).toEqual([...requiredScenarios]);

		for (const row of rows) {
			for (const column of requiredColumns.slice(1)) {
				expect(Number.isFinite(Number(row[column]))).toBe(true);
			}
		}
	});
});
