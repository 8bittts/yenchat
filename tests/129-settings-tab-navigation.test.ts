import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const settingsPanelPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Settings/SettingsPanel.swift",
);

describe("Settings pane navigation guardrails", () => {
	test("pane selection syncs idempotently between the inspector and the controller", () => {
		// A write that does not change the pane must not write back, or the
		// panel and the controller re-publish to each other in a loop.
		const source = readFileSync(settingsPanelPath, "utf8");
		const paneSelection = source.match(
			/private var paneSelection: Binding<SettingsPane> \{[\s\S]*?\n {4}\}/,
		)?.[0];
		const controllerSync = source.match(
			/\.onReceive\(controller\.\$selectedSettingsPane\.removeDuplicates\(\)\) \{ pane in[\s\S]*?\}/,
		)?.[0];

		expect(paneSelection).toBeDefined();
		expect(paneSelection).toContain(
			"guard selectedPane != pane else { return }",
		);
		expect(paneSelection).toContain(
			"if controller.selectedSettingsPane != pane",
		);
		expect(controllerSync).toBeDefined();
		expect(controllerSync).toContain(
			"guard selectedPane != pane else { return }",
		);
	});

	test("the panel uses the inspector switcher, not a split view or a list selection", () => {
		const source = readFileSync(settingsPanelPath, "utf8");
		// A segmented SwiftUI Picker keeps its natural width and overflowed the
		// inspector; the shared control fills the offered width instead.
		expect(source).toContain("SettingsSegmentedControl(");
		expect(source).not.toContain(".pickerStyle(.segmented)");
		expect(source).not.toContain("NavigationSplitView");
		expect(source).not.toContain("List(selection:");
		// The switcher draws every pane, so no pane is reachable only by search.
		expect(source).toContain("segments: SettingsPane.allCases.map");
	});
});
