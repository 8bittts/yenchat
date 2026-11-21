import AppKit
import SwiftUI
import Testing
@testable import YEN

struct GitDrawerPresentationTests {
    @Test func diffTextColorReturnsCachedInstancePerRole() {
        // The five diff role colors are built once and shared; diffTextColor(for:)
        // is called per diff line on every re-render, so it must return the cached
        // instance (identity) instead of allocating fresh NSColors each call.
        for role in [GitDrawerDiffLineRole.metadata, .hunk, .addition, .deletion, .truncation] {
            #expect(
                GitDrawerSemanticColors.diffTextColor(for: role)
                    === GitDrawerSemanticColors.diffTextColor(for: role)
            )
        }
    }

    @Test func semanticColorsMeetContrastFloorInLightAndDarkAppearances() {
        let badges = ["M", "A", "D", "R", "C", "??", "U"]
        let diffRoles: [GitDrawerDiffLineRole] = [.metadata, .hunk, .addition, .deletion, .truncation, .context]
        let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

        for appearance in appearances {
            let windowBackground = resolvedColor(.windowBackgroundColor, appearance: appearance)
            let diffBackground = resolvedColor(GitDrawerSemanticColors.diffBackgroundColor, appearance: appearance)
            let diffText = resolvedColor(GitDrawerSemanticColors.diffTextColor, appearance: appearance)

            #expect(
                WindowBorderGradientResolver.contrastRatioForTesting(of: diffText, against: diffBackground) >= wcagNormalTextContrastFloor,
                "Git drawer diff text contrast failed in \(appearance.rawValue)"
            )

            for role in diffRoles {
                let diffRoleText = resolvedColor(GitDrawerSemanticColors.diffTextColor(for: role), appearance: appearance)
                #expect(
                    WindowBorderGradientResolver.contrastRatioForTesting(of: diffRoleText, against: diffBackground) >= wcagNormalTextContrastFloor,
                    "Git drawer diff \(role) contrast failed in \(appearance.rawValue)"
                )
            }

            for badge in badges {
                let badgeText = resolvedColor(
                    GitDrawerSemanticColors.badgeTextColor(for: badge),
                    appearance: appearance
                )
                #expect(
                    WindowBorderGradientResolver.contrastRatioForTesting(of: badgeText, against: windowBackground) >= wcagNormalTextContrastFloor,
                    "Git drawer badge \(badge) contrast failed in \(appearance.rawValue)"
                )
            }
        }
    }

    @Test func diffLineClassifierRecognizesUnifiedDiffRoles() {
        let lines = [
            "diff --git a/Sources/App.swift b/Sources/App.swift",
            "index 1111111..2222222 100644",
            "--- a/Sources/App.swift",
            "+++ b/Sources/App.swift",
            "@@ -1,2 +1,2 @@",
            "-old",
            "+new",
            " unchanged",
            "\\ No newline at end of file",
            "[diff truncated]",
            "new file mode 100644",
            "deleted file mode 100644",
            "old mode 100755",
            "new mode 100644",
            "similarity index 91%",
            "dissimilarity index 12%",
            "rename from old.swift",
            "rename to new.swift",
            "copy from source.swift",
            "copy to duplicate.swift",
            "Binary files a/image.png and b/image.png differ",
            "GIT binary patch",
            "literal 12",
            "delta 8",
            "+++literal",
            "---literal",
        ]

        #expect(lines.map(GitDrawerDiffLineClassifier.role(for:)) == [
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .hunk,
            .deletion,
            .addition,
            .context,
            .metadata,
            .truncation,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .metadata,
            .addition,
            .deletion,
        ])
    }

    @Test func streamedDiffClassificationDistinguishesHeadersFromPrefixedSource() {
        let lines = [
            "diff --git a/list.md b/list.md",
            "--- a/list.md",
            "+++ b/list.md",
            "@@ -1 +1 @@",
            "--- deleted source beginning with two dashes",
            "+++ added source beginning with two pluses",
        ]
        var classifier = SelectableDiffTextLineClassifier()

        #expect(lines.map { classifier.role(for: $0, renderingMode: .unifiedDiff) } == [
            .metadata,
            .metadata,
            .metadata,
            .hunk,
            .deletion,
            .addition,
        ])
    }

    @Test func plainTextModeNeverTreatsSourcePrefixesAsDiffSyntax() {
        let lines = [
            "- Markdown list item",
            "+ literal source line",
            "@@ decorator",
            "diff --git prose",
        ]
        var classifier = SelectableDiffTextLineClassifier()

        #expect(lines.map { classifier.role(for: $0, renderingMode: .plain) } == [
            .context,
            .context,
            .context,
            .context,
        ])
    }

    @Test @MainActor func replacingSelectableDiffContentResetsSelectionAndBothScrollAxes() throws {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let textView = try #require(scrollView.documentView as? NSTextView)
        textView.frame = NSRect(x: 0, y: 0, width: 1_000, height: 2_000)
        textView.string = String(repeating: "long diff line\n", count: 200)
        textView.setSelectedRange(NSRange(location: 5, length: 8))
        scrollView.contentView.scroll(to: NSPoint(x: 40, y: 800))

        #expect(scrollView.contentView.bounds.origin != .zero)
        GitDrawerDiffTextView.resetSelectionAndViewport(in: textView)

        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(scrollView.contentView.bounds.origin == .zero)
    }

    @Test func identicalTextAndLabelsStillRenderForANewTargetIdentity() {
        let commonArguments = (
            diff: "same source text",
            label: "Ours • HEAD",
            mode: SelectableDiffTextRenderingMode.plain
        )

        #expect(
            GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-1#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 12
            )
        )
        #expect(
            !GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-2#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 12
            )
        )
        #expect(
            GitDrawerDiffTextView.requiresRender(
                renderedDiff: commonArguments.diff,
                renderedAccessibilityLabel: commonArguments.label,
                renderedIdentity: "repo#file#hunk-2#ours",
                renderedMode: commonArguments.mode,
                renderedFontSize: 12,
                diffText: commonArguments.diff,
                accessibilityLabel: commonArguments.label,
                renderIdentity: "repo#file#hunk-2#ours",
                renderingMode: commonArguments.mode,
                fontSize: 15
            )
        )
    }

}

private let wcagNormalTextContrastFloor = 4.5

private func resolvedColor(_ color: NSColor, appearance: NSAppearance.Name) -> NSColor {
    var resolved = color
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.deviceRGB) ?? color
    }
    return resolved
}
