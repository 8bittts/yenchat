import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const gitDrawerViewSource = readFileSync(
	join(
		repoRoot,
		"yen-terminal/overlays/macos/Sources/Features/GitDrawer/GitDrawerView.swift",
	),
	"utf8",
);

function sourceBlockBetween(startMarker: string, endMarker: string): string {
	const start = gitDrawerViewSource.indexOf(startMarker);
	const end = gitDrawerViewSource.indexOf(
		endMarker,
		start + startMarker.length,
	);

	expect(start).toBeGreaterThanOrEqual(0);
	expect(end).toBeGreaterThan(start);

	return gitDrawerViewSource.slice(start, end);
}

describe("Git drawer header layout", () => {
	test("left and right header icon groups share the same downward optical nudge", () => {
		const offsetApplication =
			".offset(y: GitDrawerHeaderMetrics.controlVerticalOffset)";
		const offsetApplications = gitDrawerViewSource.matchAll(
			/\.offset\(y: GitDrawerHeaderMetrics\.controlVerticalOffset\)/g,
		);

		expect(gitDrawerViewSource).toContain(
			"static let controlVerticalOffset: CGFloat = 2",
		);
		expect(Array.from(offsetApplications)).toHaveLength(2);
		expect(
			sourceBlockBetween(
				"private struct GitDrawerHeaderButton: View",
				"private struct GitDrawerFilterIconBar: View",
			),
		).toContain(offsetApplication);
		expect(
			sourceBlockBetween(
				"private struct GitDrawerFilterIconBar: View",
				"private enum GitDrawerHeaderMetrics",
			),
		).toContain(offsetApplication);
	});
});
