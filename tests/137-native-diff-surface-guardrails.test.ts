import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const repoRoot = process.cwd();
const sharedView = readFileSync(
	join(
		repoRoot,
		"yen-terminal/overlays/macos/Sources/Features/GitDrawer/GitDrawerDiffTextView.swift",
	),
	"utf8",
);
const mergeView = readFileSync(
	join(
		repoRoot,
		"yen-terminal/overlays/macos/Sources/Features/Review/MergeConflictView.swift",
	),
	"utf8",
);
const reviewWorkspace = [
	"PRReviewWorkspace.swift",
	"PRReviewTypes.swift",
	"PRReviewDiffParser.swift",
]
	.map((name) =>
		readFileSync(
			join(
				repoRoot,
				"yen-terminal/overlays/macos/Sources/Features/Review",
				name,
			),
			"utf8",
		),
	)
	.join("\n");
const diffPreview = readFileSync(
	join(
		repoRoot,
		"yen-terminal/overlays/macos/Sources/Features/Review/IDEDiffPreview.swift",
	),
	"utf8",
);
const gitReviewTools = readFileSync(
	join(repoRoot, "yen-cli/lib/git-review-tools.sh"),
	"utf8",
);
const nativeSmoke = readFileSync(
	join(repoRoot, "scripts/native/01-macos-smoke.sh"),
	"utf8",
);

function sourceSection(source: string, start: string, end: string): string {
	const startIndex = source.indexOf(start);
	const endIndex = source.indexOf(end, startIndex + start.length);
	expect(startIndex).toBeGreaterThanOrEqual(0);
	expect(endIndex).toBeGreaterThan(startIndex);
	return source.slice(startIndex, endIndex);
}

describe("native selectable diff surface guardrails", () => {
	test("PR Review displays raw file and hunk diffs", () => {
		expect(reviewWorkspace).toContain("let diff: String");
		expect(reviewWorkspace).toContain(
			'focusedDiff = selectedHunk?.diff ?? selectedFile?.diff ?? ""',
		);
		expect(reviewWorkspace).not.toContain(
			"focusedDiff = selectedHunk?.preview.text ?? selectedFile?.preview.text",
		);
		expect(reviewWorkspace).not.toContain("renderPreview");
		expect(reviewWorkspace).not.toContain("IDEDiffPreviewRenderer");
		expect(reviewWorkspace).toContain("guard !isInsideHunk else { continue }");
		expect(reviewWorkspace).toContain("commentLine: commentLine");
		expect(diffPreview).not.toContain("static func render(");
		expect(diffPreview).not.toContain("static func runDeltaPreview(");
	});

	test("CLI hunk routing shares prefix handling without ambiguous old-side targets", () => {
		expect(gitReviewTools).not.toContain('index($0, "+++") != 1');
		expect(gitReviewTools).not.toContain('index($0, "---") != 1');
		expect(gitReviewTools).toContain("pending_deletion_new_line");
		expect(gitReviewTools).toContain(
			"location_line = pending_new_start + pending_new_count - 1",
		);
	});

	test("shared view resets for explicit target identity or mode changes", () => {
		expect(sharedView).toContain(
			"renderedAccessibilityLabel != accessibilityLabel",
		);
		expect(sharedView).toContain("renderedIdentity != renderIdentity");
		expect(sharedView).toContain("renderedMode != renderingMode");
		expect(sharedView).toContain("scrollView.contentView.scroll(to: .zero)");
		expect(mergeView).toContain('previewIdentity(pane: "ours")');
		expect(mergeView).toContain('previewIdentity(pane: "base")');
		expect(mergeView).toContain('previewIdentity(pane: "theirs")');
		expect(mergeView).toContain('previewIdentity(pane: "resolution-patch")');
		expect(mergeView).toContain('previewIdentity(pane: "resolved-file")');
	});

	test("Merge Conflict uses split panes without nested vertical scrollers", () => {
		const hunkDetail = sourceSection(
			mergeView,
			"private var hunkDetailContent",
			"private func hunkPicker",
		);
		const resultSidebar = sourceSection(
			mergeView,
			"private var resultSidebar",
			"private var selectedHunkPreviewRenderingMode",
		);

		expect(hunkDetail).toContain("VSplitView");
		expect(resultSidebar).toContain("VSplitView");
		expect(hunkDetail).not.toContain("ScrollView {");
		expect(resultSidebar).not.toContain("ScrollView {");
		expect(mergeView).toContain("renderingMode: .plain");
	});

	test("Merge Conflict uses the current SwiftUI confirmation alert API", () => {
		expect(mergeView).not.toContain(".alert(item:");
		expect(mergeView).not.toContain("Alert(");
		expect(mergeView).toContain(
			"isPresented: resolutionConfirmationIsPresented",
		);
		expect(mergeView).toContain(
			"presenting: model.pendingResolutionConfirmation",
		);
		expect(mergeView).toContain("model.dismissPendingResolutionConfirmation()");
	});

	test("fast native smoke executes the regression suites", () => {
		expect(nativeSmoke).toContain(
			"-only-testing:YENTests/TerminalCommandPalettePresentationTests",
		);
		expect(nativeSmoke).toContain(
			"-only-testing:YENTests/PullRequestReviewDiffParserTests",
		);
		expect(nativeSmoke).toContain(
			"-only-testing:YENTests/PullRequestReviewModelTests",
		);
		expect(nativeSmoke).toContain(
			"-only-testing:YENTests/GitDrawerPresentationTests",
		);
	});
});
