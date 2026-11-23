import { describe, expect, test } from "bun:test";
import {
	LEDGER_LAST_VERSION,
	PRE_OPEN_SOURCE_RELEASES,
} from "@/lib/release-notes/release-ledger";
import {
	RELEASE_COPY,
	RELEASE_EXCLUDE,
} from "@/lib/release-notes/release-notes-copy";
import { RELEASE_WEEKS } from "@/lib/release-notes/release-notes-data";

// The public git log starts at the open-source squash, so the ledger is the only
// record of the 514 builds published before it. A regeneration that stops reading
// it empties the release notes while every other gate stays green.
const LEDGER_RELEASE_COUNT = 514;

function isAtOrBeforeLedger(version: string): boolean {
	const a = version.split(".").map(Number);
	const b = LEDGER_LAST_VERSION.split(".").map(Number);
	for (let i = 0; i < Math.max(a.length, b.length); i++) {
		const diff = (a[i] ?? 0) - (b[i] ?? 0);
		if (diff !== 0) return diff < 0;
	}
	return true;
}

const published = new Map(
	RELEASE_WEEKS.flatMap((week) =>
		week.versions.map((build) => [build.version, build.shippedOn] as const),
	),
);

describe("pre-open-source release ledger", () => {
	test("holds every published private-era build once, with an ISO ship day", () => {
		expect(PRE_OPEN_SOURCE_RELEASES).toHaveLength(LEDGER_RELEASE_COUNT);
		const versions = PRE_OPEN_SOURCE_RELEASES.map((row) => row.version);
		expect(new Set(versions).size).toBe(versions.length);
		for (const row of PRE_OPEN_SOURCE_RELEASES) {
			expect(row.shippedOn).toMatch(/^\d{4}-\d{2}-\d{2}$/);
			expect(isAtOrBeforeLedger(row.version)).toBe(true);
		}
	});

	test("the generated page keeps every ledger build on its ledger ship day", () => {
		for (const row of PRE_OPEN_SOURCE_RELEASES) {
			if (RELEASE_EXCLUDE[row.version]) continue;
			expect(published.get(row.version)).toBe(row.shippedOn);
		}
	});

	// The generator drops curated copy that names a retired runtime and only
	// warns about it, so "yen.chat" in a line once hid that build from the page.
	test("the page shows every public-era build that has curated copy", () => {
		const missing = Object.keys(RELEASE_COPY).filter(
			(version) =>
				!isAtOrBeforeLedger(version) &&
				!RELEASE_EXCLUDE[version] &&
				!published.has(version),
		);
		expect(missing).toEqual([]);
	});

	test("the page shows no private-era build the ledger lacks", () => {
		const ledger = new Set(PRE_OPEN_SOURCE_RELEASES.map((row) => row.version));
		const unrecorded = [...published.keys()].filter(
			(version) => isAtOrBeforeLedger(version) && !ledger.has(version),
		);
		expect(unrecorded).toEqual([]);
	});
});
