import AppKit
import Testing
@testable import YEN

@MainActor
struct GitDrawerDiffAttributedStringTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // Resolve a (possibly dynamic) NSColor to stable sRGB components under a
    // fixed appearance so role colors can be compared deterministically.
    private func components(_ color: NSColor) -> [CGFloat] {
        var result: [CGFloat] = [0, 0, 0, 0]
        let appearance = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        }
        return result
    }

    private func approximatelyEqual(_ lhs: [CGFloat], _ rhs: [CGFloat]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) < 0.001 }
    }

    private func foregroundColor(in attributed: NSAttributedString, at substring: String) -> NSColor? {
        let range = (attributed.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    @Test func preservesTextExactly() {
        let diff = "@@ -1 +1 @@\n-old\n+new"
        let attributed = GitDrawerDiffAttributedString.make(diff, font: font)
        // Selection-copy fidelity depends on the rendered text matching the diff.
        #expect(attributed.string == diff)
    }

    @Test func colorsLinesByRole() {
        let diff = "diff --git a/x b/x\n@@ -1 +1 @@\n context\n-old\n+new"
        let attributed = GitDrawerDiffAttributedString.make(diff, font: font)

        let metadata = foregroundColor(in: attributed, at: "diff --git a/x b/x")
        let hunk = foregroundColor(in: attributed, at: "@@ -1 +1 @@")
        let deletion = foregroundColor(in: attributed, at: "-old")
        let addition = foregroundColor(in: attributed, at: "+new")

        #expect(metadata != nil)
        #expect(hunk != nil)
        #expect(deletion != nil)
        #expect(addition != nil)

        #expect(approximatelyEqual(components(hunk!), components(GitDrawerSemanticColors.diffTextColor(for: .hunk))))
        #expect(approximatelyEqual(components(deletion!), components(GitDrawerSemanticColors.diffTextColor(for: .deletion))))
        #expect(approximatelyEqual(components(addition!), components(GitDrawerSemanticColors.diffTextColor(for: .addition))))

        // Roles must be visually distinct, not all defaulted to one color.
        #expect(!approximatelyEqual(components(deletion!), components(addition!)))
        #expect(!approximatelyEqual(components(hunk!), components(metadata!)))
    }

    @Test func handlesEmptyDiff() {
        let attributed = GitDrawerDiffAttributedString.make("", font: font)
        #expect(attributed.string.isEmpty)
    }
}
