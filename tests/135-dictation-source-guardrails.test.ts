import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const controllerPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Dictation/DictationController.swift",
);
const insertionPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Dictation/DictationInsertionCoordinator.swift",
);
const executorPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Sources/Features/Dictation/DictationPasteExecutor.swift",
);
const permissionTestsPath = join(
	repoRoot,
	"yen-terminal/overlays/macos/Tests/Settings/DictationPermissionStateTests.swift",
);

describe("dictation source guardrails", () => {
	test("does not keep the retired pasteInsertionStrategy helper", () => {
		const controller = readFileSync(controllerPath, "utf8");
		const executor = readFileSync(executorPath, "utf8");
		const insertion = readFileSync(insertionPath, "utf8");
		const permissionTests = readFileSync(permissionTestsPath, "utf8");

		expect(controller).not.toContain("pasteInsertionStrategy");
		expect(insertion).not.toContain("pasteInsertionStrategy");
		expect(executor).not.toContain("pasteInsertionStrategy");
		expect(permissionTests).not.toContain("pasteInsertionStrategy");
	});

	// The synthetic command-v key-pair invariant (one keyDown + one keyUp, both
	// carrying .maskCommand and keycode 0x09) is now exercised behaviorally by the
	// Swift @Test `DictationPasteEventTests.syntheticCommandVPasteCreatesOneCommandKeyPair`
	// (Tests/Dictation/DictationPasteEventTests.swift), which builds real CGEvents
	// instead of counting `CGEvent(keyboardEventSource:` source occurrences.
});
